import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'gpx_parser.dart';
import 'models/track.dart';
import 'models/track_folder.dart';

/// Estado agregado de visibilidade das trilhas de uma pasta (para o olho da
/// pasta no painel). Pasta vazia conta como [none].
enum FolderVisibility { all, none, partial }

/// Resultado de uma importação, para dar feedback ao usuário.
class ImportResult {
  const ImportResult({
    required this.imported,
    required this.skipped,
    this.tracks = const [],
  });
  final int imported;
  final int skipped;

  /// As trilhas efetivamente importadas (para o mapa se ajustar a elas).
  final List<Track> tracks;
}

/// Gerencia as trilhas importadas: importa GPX, persiste (arquivos + JSON),
/// controla visibilidade/cor e expõe a geometria para o mapa.
///
/// `ChangeNotifier` para o mapa e o painel se atualizarem juntos.
class TrackManager extends ChangeNotifier {
  /// [dirOverride] troca o diretório de dados (testes usam um temp dir e assim
  /// não dependem do path_provider).
  TrackManager({this._dirOverride});

  final List<Track> _tracks = [];
  List<Track> get tracks => List.unmodifiable(_tracks);

  final List<TrackFolder> _folders = [];

  /// Pastas na ordem de exibição (ordem de criação; sem reordenar no v1).
  List<TrackFolder> get folders => List.unmodifiable(_folders);

  final Directory? _dirOverride;
  Directory? _tracksDir;
  int _counter = 0;

  int get visibleCount => _tracks.where((t) => t.visible).length;

  Future<Directory> _dir() async {
    if (_tracksDir != null) return _tracksDir!;
    final dir = _dirOverride ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/tracks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _tracksDir = dir;
  }

  File _metadataFile(Directory dir) => File('${dir.path}/tracks.json');

  File _foldersFile(Directory dir) => File('${dir.path}/folders.json');

  /// Carrega as trilhas salvas e re-parseia a geometria de cada GPX.
  Future<void> load() async {
    final dir = await _dir();
    await _loadFolders(dir);
    final meta = _metadataFile(dir);
    if (await meta.exists()) {
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
    }
    final valid = _folders.map((f) => f.id).toSet();
    for (final t in _tracks) {
      t.folderIds.removeWhere((id) => !valid.contains(id));
    }
    notifyListeners();
  }

  Future<void> _loadFolders(Directory dir) async {
    final file = _foldersFile(dir);
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _folders
        ..clear()
        ..addAll(raw.cast<Map<String, dynamic>>().map(TrackFolder.fromJson));
    } catch (_) {
      _folders.clear(); // corrompido: segue sem pastas
    }
  }

  Track _trackFromMeta(Map<String, dynamic> e, ParsedGpx parsed) => Track(
        id: e['id'] as String,
        name: e['name'] as String,
        fileName: e['fileName'] as String,
        storedPath: e['storedPath'] as String,
        color: Color(e['color'] as int),
        visible: e['visible'] as bool? ?? true,
        folderIds: (e['folderIds'] as List<dynamic>?)?.cast<String>().toList() ??
            [if (e['folderId'] is String) e['folderId'] as String],
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
    final importedTracks = <Track>[];
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
        final track = Track(
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
        );
        _tracks.add(track);
        importedTracks.add(track);
      } catch (_) {
        skipped++;
      }
    }

    if (importedTracks.isNotEmpty) await _save();
    notifyListeners();
    return ImportResult(
      imported: importedTracks.length,
      skipped: skipped,
      tracks: importedTracks,
    );
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

  Future<void> _saveFolders() async {
    final dir = await _dir();
    await _foldersFile(dir)
        .writeAsString(jsonEncode(_folders.map((f) => f.toJson()).toList()));
  }

  Future<TrackFolder?> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final folder = TrackFolder(id: _newId(), name: trimmed);
    _folders.add(folder);
    await _saveFolders();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    final folder = _folderById(id);
    if (folder == null || trimmed.isEmpty) return;
    folder.name = trimmed;
    await _saveFolders();
    notifyListeners();
  }

  /// Exclui a pasta. Com [deleteTracks], exclui também (GPX + metadados) toda
  /// trilha que pertença a ela — mesmo que a trilha esteja em outras pastas.
  Future<void> deleteFolder(String id, {required bool deleteTracks}) async {
    final folder = _folderById(id);
    if (folder == null) return;
    if (deleteTracks) {
      final ids = _tracks
          .where((t) => t.folderIds.contains(id))
          .map((t) => t.id)
          .toList();
      await removeMany(ids);
    } else {
      for (final t in _tracks) {
        t.folderIds.remove(id);
      }
      await _save();
    }
    _folders.remove(folder);
    await _saveFolders();
    notifyListeners();
  }

  /// Exclui várias trilhas de uma vez (GPX + metadados).
  Future<void> removeMany(List<String> trackIds) async {
    final toRemove = trackIds.toSet();
    final victims = _tracks.where((t) => toRemove.contains(t.id)).toList();
    if (victims.isEmpty) return;
    for (final t in victims) {
      _tracks.remove(t);
      try {
        final f = File(t.storedPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  TrackFolder? _folderById(String id) {
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> remove(String id) => removeMany([id]);

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

  /// Retorna todas as trilhas que pertencem a uma pasta.
  List<Track> tracksInFolder(String folderId) =>
      _tracks.where((t) => t.folderIds.contains(folderId)).toList();

  /// Trilhas fora de qualquer pasta (listadas soltas na raiz do painel).
  List<Track> get looseTracks =>
      _tracks.where((t) => t.folderIds.isEmpty).toList();

  /// Computa o estado agregado de visibilidade de uma pasta.
  FolderVisibility folderVisibility(String folderId) {
    final ts = tracksInFolder(folderId);
    final visible = ts.where((t) => t.visible).length;
    if (visible == 0) return FolderVisibility.none;
    return visible == ts.length
        ? FolderVisibility.all
        : FolderVisibility.partial;
  }

  /// Ação em massa do olho da pasta: liga/desliga todas as trilhas dela.
  Future<void> setFolderVisible(String folderId, bool visible) async {
    for (final t in tracksInFolder(folderId)) {
      t.visible = visible;
    }
    await _save();
    notifyListeners();
  }

  /// Aplica o resultado do sheet "Pastas desta trilha" (substitui o conjunto).
  Future<void> setTrackFolders(String trackId, Set<String> folderIds) async {
    final t = _byId(trackId);
    if (t == null) return;
    t.folderIds = folderIds.toList();
    await _save();
    notifyListeners();
  }

  /// Ação em massa "Adicionar à pasta": adiciona sem tirar das outras pastas.
  Future<void> addToFolder(List<String> trackIds, String folderId) async {
    for (final id in trackIds) {
      final t = _byId(id);
      if (t != null && !t.folderIds.contains(folderId)) {
        t.folderIds.add(folderId);
      }
    }
    await _save();
    notifyListeners();
  }
}
