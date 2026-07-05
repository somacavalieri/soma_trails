import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'gpx_parser.dart';
import 'location_service.dart';
import 'models/recorded_track.dart';

enum RecordingState { idle, recording, paused }

const _distance = Distance();

/// Grava o trajeto percorrido (breadcrumb "de onde eu vim").
///
/// - Consome o [LocationService] compartilhado (sem GPS duplicado); durante a
///   gravação liga o *foreground service* para o One UI não matar o GPS.
/// - Auto-salva o GPX no disco a cada ~30 s. Se o app for morto gravando, ao
///   reabrir retoma automaticamente, com o intervalo virando um novo segmento
///   (sem linha reta falsa).
/// - Filtros: descarta pontos com precisão pior que 30 m (evita "novelo").
class TrackRecorder extends ChangeNotifier {
  TrackRecorder(this._location);

  final LocationService _location;

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;
  bool get isRecording => _state == RecordingState.recording;
  bool get isActive => _state != RecordingState.idle;

  final List<List<LatLng>> _segments = [];
  double _distanceMeters = 0;
  Duration _accumulated = Duration.zero;
  DateTime? _runStart;

  String? _activeId;
  String? _activeName;
  DateTime? _startedAt;

  StreamSubscription<Position>? _sub;
  Timer? _tick; // relógio do HUD (1 s)
  Timer? _autosave; // persistência (30 s)

  bool _needsAutoResume = false;
  bool get needsAutoResume => _needsAutoResume;

  final List<RecordedTrack> _saved = [];
  List<RecordedTrack> get saved => List.unmodifiable(_saved);

  Directory? _dir;
  static const _accuracyCeilingMeters = 30.0;

  // ---- Estado derivado (para o HUD e o mapa) ----------------------------

  Duration get elapsed {
    var e = _accumulated;
    if (_state == RecordingState.recording && _runStart != null) {
      e += DateTime.now().difference(_runStart!);
    }
    return e;
  }

  double get distanceKm => _distanceMeters / 1000.0;

  /// Segmentos da gravação em curso (para desenhar a linha "meu trajeto").
  List<List<LatLng>> get liveSegments =>
      _segments.map((s) => List<LatLng>.unmodifiable(s)).toList();

  /// Primeiro ponto gravado (pino de início), se houver.
  LatLng? get startPoint {
    for (final seg in _segments) {
      if (seg.isNotEmpty) return seg.first;
    }
    return null;
  }

  // ---- Ciclo de vida -----------------------------------------------------

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  File _savedMeta(Directory dir) => File('${dir.path}/recordings.json');
  File _activeMeta(Directory dir) => File('${dir.path}/active.json');
  File _gpxFile(Directory dir, String id) => File('${dir.path}/$id.gpx');

  /// Carrega trajetos salvos e detecta uma gravação ativa interrompida.
  Future<void> init() async {
    final dir = await _directory();

    final meta = _savedMeta(dir);
    if (await meta.exists()) {
      final raw = jsonDecode(await meta.readAsString()) as List<dynamic>;
      for (final e in raw.cast<Map<String, dynamic>>()) {
        final file = File(e['storedPath'] as String);
        if (!await file.exists()) continue;
        try {
          final parsed = parseGpx(await file.readAsString(),
              simplifyToleranceMeters: 0);
          _saved.add(RecordedTrack(
            id: e['id'] as String,
            name: e['name'] as String,
            storedPath: e['storedPath'] as String,
            startedAt: DateTime.parse(e['startedAt'] as String),
            duration: Duration(milliseconds: e['durationMs'] as int),
            distanceMeters: (e['distanceMeters'] as num).toDouble(),
            segments: parsed.segments,
          ));
        } catch (_) {}
      }
    }

    await _restoreActive(dir);
    notifyListeners();
  }

  Future<void> _restoreActive(Directory dir) async {
    final active = _activeMeta(dir);
    if (!await active.exists()) return;
    try {
      final d = jsonDecode(await active.readAsString()) as Map<String, dynamic>;
      final id = d['id'] as String;
      final gpx = _gpxFile(dir, id);
      if (!await gpx.exists()) {
        await active.delete();
        return;
      }
      final parsed = parseGpx(await gpx.readAsString(), simplifyToleranceMeters: 0);
      _segments
        ..clear()
        ..addAll(parsed.segments.map((s) => s.toList()));
      _activeId = id;
      _activeName = d['name'] as String?;
      _startedAt = DateTime.parse(d['startedAt'] as String);
      _distanceMeters = (d['distanceMeters'] as num).toDouble();
      _accumulated = Duration(milliseconds: d['elapsedMs'] as int);
      final wasRecording = d['state'] == 'recording';
      _state = RecordingState.paused; // fica pausado até o GPS estar pronto
      _needsAutoResume = wasRecording;
    } catch (_) {
      // Descritor corrompido: descarta para não travar a abertura.
      try {
        await _activeMeta(dir).delete();
      } catch (_) {}
    }
  }

  // ---- Controles ---------------------------------------------------------

  Future<void> start() async {
    if (_state != RecordingState.idle) return;
    _activeId = '${DateTime.now().microsecondsSinceEpoch}';
    _startedAt = DateTime.now();
    _activeName = _defaultName(_startedAt!);
    _segments
      ..clear()
      ..add(<LatLng>[]);
    _distanceMeters = 0;
    _accumulated = Duration.zero;
    await _beginRun();
  }

  Future<void> pause() async {
    if (_state != RecordingState.recording) return;
    _accumulateTime();
    _endRun();
    _state = RecordingState.paused;
    await _location.setForeground(false);
    await _persistActive();
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != RecordingState.paused) return;
    _needsAutoResume = false;
    _segments.add(<LatLng>[]); // intervalo vira novo segmento
    await _beginRun();
  }

  /// Inicia/retoma a coleta de pontos (foreground + assinatura + timers).
  Future<void> _beginRun() async {
    _state = RecordingState.recording;
    _runStart = DateTime.now();
    await _location.setForeground(true);
    _sub ??= _location.positions.listen(_onPosition);
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state == RecordingState.recording) notifyListeners();
    });
    _autosave ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _persistActive();
    });
    await _persistActive();
    notifyListeners();
  }

  Future<RecordedTrack?> stop() async {
    if (_state == RecordingState.idle) return null;
    if (_state == RecordingState.recording) _accumulateTime();
    _endRun();
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    _autosave?.cancel();
    _autosave = null;
    await _location.setForeground(false);

    final dir = await _directory();
    final id = _activeId!;
    final track = RecordedTrack(
      id: id,
      name: _activeName ?? _defaultName(_startedAt ?? DateTime.now()),
      storedPath: _gpxFile(dir, id).path,
      startedAt: _startedAt ?? DateTime.now(),
      duration: _accumulated,
      distanceMeters: _distanceMeters,
      segments: _segments.map((s) => s.toList()).toList(),
    );

    // Se nada foi gravado, descarta em vez de salvar um trajeto vazio.
    final hasPoints = _segments.any((s) => s.length >= 2);
    if (hasPoints) {
      await _writeGpx(dir, id, finalName: track.name);
      _saved.insert(0, track);
      await _saveList();
    } else {
      try {
        final f = _gpxFile(dir, id);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    await _clearActive(dir);
    _resetActiveState();
    _state = RecordingState.idle;
    notifyListeners();
    return hasPoints ? track : null;
  }

  void _onPosition(Position pos) {
    if (_state != RecordingState.recording) return;
    if (pos.accuracy > _accuracyCeilingMeters) return; // ponto ruim: ignora
    final p = LatLng(pos.latitude, pos.longitude);
    final seg = _segments.last;
    if (seg.isNotEmpty) {
      _distanceMeters += _distance.as(LengthUnit.Meter, seg.last, p);
    }
    seg.add(p);
    notifyListeners();
  }

  // ---- Trajetos salvos ---------------------------------------------------

  Future<void> renameSaved(String id, String name) async {
    final t = _savedById(id);
    if (t == null || name.trim().isEmpty) return;
    t.name = name.trim();
    await _saveList();
    notifyListeners();
  }

  Future<void> removeSaved(String id) async {
    final t = _savedById(id);
    if (t == null) return;
    _saved.remove(t);
    try {
      final f = File(t.storedPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _saveList();
    notifyListeners();
  }

  /// Conteúdo GPX de um trajeto salvo (para exportar/compartilhar).
  Future<String?> gpxOf(String id) async {
    final t = _savedById(id);
    if (t == null) return null;
    final f = File(t.storedPath);
    return await f.exists() ? f.readAsString() : null;
  }

  RecordedTrack? _savedById(String id) {
    for (final t in _saved) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ---- Persistência ------------------------------------------------------

  void _accumulateTime() {
    if (_runStart != null) {
      _accumulated += DateTime.now().difference(_runStart!);
    }
  }

  void _endRun() => _runStart = null;

  void _resetActiveState() {
    _segments.clear();
    _distanceMeters = 0;
    _accumulated = Duration.zero;
    _runStart = null;
    _activeId = null;
    _activeName = null;
    _startedAt = null;
    _needsAutoResume = false;
  }

  Future<void> _persistActive() async {
    if (_activeId == null) return;
    final dir = await _directory();
    await _writeGpx(dir, _activeId!, finalName: _activeName);
    await _activeMeta(dir).writeAsString(jsonEncode({
      'id': _activeId,
      'name': _activeName,
      'startedAt': (_startedAt ?? DateTime.now()).toIso8601String(),
      'elapsedMs': elapsed.inMilliseconds,
      'distanceMeters': _distanceMeters,
      'state': _state == RecordingState.recording ? 'recording' : 'paused',
    }));
  }

  Future<void> _clearActive(Directory dir) async {
    try {
      final f = _activeMeta(dir);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _writeGpx(Directory dir, String id, {String? finalName}) async {
    final gpx = Gpx()
      ..creator = 'soma_trails'
      ..trks = [
        Trk(
          name: finalName,
          trksegs: [
            for (final seg in _segments)
              if (seg.isNotEmpty)
                Trkseg(
                  trkpts: [
                    for (final p in seg) Wpt(lat: p.latitude, lon: p.longitude),
                  ],
                ),
          ],
        ),
      ];
    await _gpxFile(dir, id).writeAsString(GpxWriter().asString(gpx));
  }

  Future<void> _saveList() async {
    final dir = await _directory();
    await _savedMeta(dir)
        .writeAsString(jsonEncode(_saved.map((t) => t.toJson()).toList()));
  }

  String _defaultName(DateTime when) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Trajeto ${two(when.day)}/${two(when.month)} ${two(when.hour)}:${two(when.minute)}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _autosave?.cancel();
    super.dispose();
  }
}
