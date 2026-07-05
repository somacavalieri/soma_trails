import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'gpx_parser.dart';
import 'models/track.dart';

/// Resultado de uma importação, para dar feedback ao usuário.
class ImportResult {
  const ImportResult({required this.imported, required this.skipped});
  final int imported;
  final int skipped;
}

/// Gerencia as trilhas importadas: importa GPX, persiste (arquivos + JSON),
/// controla visibilidade/cor e expõe a geometria para o mapa.
///
/// `ChangeNotifier` para o mapa e o painel se atualizarem juntos.
class TrackManager extends ChangeNotifier {
  final List<Track> _tracks = [];
  List<Track> get tracks => List.unmodifiable(_tracks);

  Directory? _tracksDir;
  int _counter = 0;

  int get visibleCount => _tracks.where((t) => t.visible).length;

  Future<Directory> _dir() async {
    if (_tracksDir != null) return _tracksDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/tracks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _tracksDir = dir;
  }

  File _metadataFile(Directory dir) => File('${dir.path}/tracks.json');

  /// Carrega as trilhas salvas e re-parseia a geometria de cada GPX.
  Future<void> load() async {
    final dir = await _dir();
    final meta = _metadataFile(dir);
    if (!await meta.exists()) return;

    final raw = jsonDecode(await meta.readAsString()) as List<dynamic>;
    _tracks.clear();
    for (final entry in raw.cast<Map<String, dynamic>>()) {
      final stored = File(entry['storedPath'] as String);
      if (!await stored.exists()) continue; // arquivo sumiu: pula
      try {
        final parsed = parseGpx(await stored.readAsString());
        _tracks.add(_trackFromMeta(entry, parsed));
      } catch (_) {
        // GPX corrompido: ignora em vez de derrubar o app.
      }
    }
    notifyListeners();
  }

  Track _trackFromMeta(Map<String, dynamic> e, ParsedGpx parsed) => Track(
        id: e['id'] as String,
        name: e['name'] as String,
        fileName: e['fileName'] as String,
        storedPath: e['storedPath'] as String,
        color: Color(e['color'] as int),
        visible: e['visible'] as bool? ?? true,
        folderId: e['folderId'] as String?,
        segments: parsed.segments,
        waypoints: parsed.waypoints,
        distanceMeters: parsed.distanceMeters,
      );

  String _newId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }

  Color _nextColor() {
    final used = _tracks.map((t) => t.color.toARGB32()).toSet();
    for (final c in trackPalette) {
      if (!used.contains(c.toARGB32())) return c;
    }
    // Todas em uso: cicla pela paleta.
    return trackPalette[_tracks.length % trackPalette.length];
  }

  /// Abre o seletor de arquivos e importa os GPX escolhidos.
  Future<ImportResult> importFromPicker() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      withData: true,
    );
    if (picked == null) return const ImportResult(imported: 0, skipped: 0);

    final dir = await _dir();
    var imported = 0;
    var skipped = 0;

    for (final file in picked.files) {
      try {
        final xml = _readFileAsString(file);
        if (xml == null) {
          skipped++;
          continue;
        }
        final parsed = parseGpx(xml);
        if (parsed.isEmpty) {
          skipped++;
          continue;
        }
        final id = _newId();
        final stored = File('${dir.path}/$id.gpx');
        await stored.writeAsString(xml);
        _tracks.add(Track(
          id: id,
          name: parsed.suggestedName?.trim().isNotEmpty == true
              ? parsed.suggestedName!.trim()
              : _stripExtension(file.name),
          fileName: file.name,
          storedPath: stored.path,
          color: _nextColor(),
          visible: true,
          segments: parsed.segments,
          waypoints: parsed.waypoints,
          distanceMeters: parsed.distanceMeters,
        ));
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    if (imported > 0) await _save();
    notifyListeners();
    return ImportResult(imported: imported, skipped: skipped);
  }

  String? _readFileAsString(PlatformFile file) {
    if (file.bytes != null) return utf8.decode(file.bytes!, allowMalformed: true);
    if (file.path != null) return File(file.path!).readAsStringSync();
    return null;
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> toggleVisible(String id) async {
    final t = _byId(id);
    if (t == null) return;
    t.visible = !t.visible;
    await _save();
    notifyListeners();
  }

  Future<void> setColor(String id, Color color) async {
    final t = _byId(id);
    if (t == null) return;
    t.color = color;
    await _save();
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final t = _byId(id);
    if (t == null || name.trim().isEmpty) return;
    t.name = name.trim();
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final t = _byId(id);
    if (t == null) return;
    _tracks.remove(t);
    try {
      final f = File(t.storedPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<void> setAllVisible(bool visible) async {
    for (final t in _tracks) {
      t.visible = visible;
    }
    await _save();
    notifyListeners();
  }

  Track? _byId(String id) {
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _save() async {
    final dir = await _dir();
    final json = _tracks.map((t) => t.toJson()).toList();
    await _metadataFile(dir).writeAsString(jsonEncode(json));
  }
}
