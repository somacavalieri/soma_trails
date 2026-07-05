import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:path_provider/path_provider.dart';

import 'models/download_region.dart';
import 'tile_source.dart';

/// Estimativa: satélite ~18 KiB/tile; ~55 tiles/s no download (heurística).
const double _avgKiBPerTile = 18;
const double _tilesPerSecond = 55;

/// Gerencia o download de satélite por área/trilha e as regiões baixadas.
///
/// Cada região vai para seu próprio store FMTC (`rgn_<id>`), então excluir uma
/// região libera exatamente o espaço dela. O mapa renderiza as regiões da fonte
/// ativa (ver [regionStoresFor]).
class OfflineDownloadController extends ChangeNotifier {
  final List<DownloadRegion> _regions = [];
  List<DownloadRegion> get regions => List.unmodifiable(_regions);

  File? _file;

  // Estado do download em curso
  bool _downloading = false;
  bool get isDownloading => _downloading;
  int _doneTiles = 0;
  int _totalTiles = 0;
  double _doneKiB = 0;
  int get doneTiles => _doneTiles;
  int get totalTiles => _totalTiles;
  double get doneKiB => _doneKiB;
  double get progress => _totalTiles == 0 ? 0 : _doneTiles / _totalTiles;

  StreamSubscription? _sub;
  String? _activeStoreName;
  DownloadRegion? _lastFinished;
  DownloadRegion? get lastFinished => _lastFinished;

  double get totalStorageKiB =>
      _regions.fold(0.0, (sum, r) => sum + r.sizeKiB);

  /// Stores das regiões baixadas para uma fonte (para o mapa renderizar offline).
  Iterable<String> regionStoresFor(String sourceId) =>
      _regions.where((r) => r.sourceId == sourceId).map((r) => r.storeName);

  Future<File> _storage() async {
    if (_file != null) return _file!;
    final docs = await getApplicationDocumentsDirectory();
    return _file = File('${docs.path}/regions.json');
  }

  Future<void> load() async {
    final file = await _storage();
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _regions
        ..clear()
        ..addAll(raw.cast<Map<String, dynamic>>().map(DownloadRegion.fromJson));
    } catch (_) {}
    notifyListeners();
  }

  TileLayer _layerFor(TileSource source) => TileLayer(
        urlTemplate: source.urlTemplate,
        subdomains: source.subdomains,
        userAgentPackageName: 'dev.soma.soma_trails',
      );

  /// Conta tiles e estima tamanho/tempo sem baixar.
  Future<DownloadEstimate> estimate({
    required BaseRegion region,
    required int minZoom,
    required int maxZoom,
    required TileSource source,
  }) async {
    final downloadable = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: _layerFor(source),
    );
    final tiles =
        await FMTCStore(source.storeName).download.countTiles(downloadable);
    return DownloadEstimate(
      tiles: tiles,
      sizeKiB: tiles * _avgKiBPerTile,
      seconds: (tiles / _tilesPerSecond).ceil(),
    );
  }

  /// Inicia o download. Atualiza o progresso; ao terminar, persiste a região
  /// e a expõe em [lastFinished].
  Future<void> start({
    required BaseRegion region,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required TileSource source,
    required String name,
  }) async {
    if (_downloading) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final storeName = 'rgn_$id';
    _activeStoreName = storeName;
    await FMTCStore(storeName).manage.create();

    final downloadable = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: _layerFor(source),
    );

    _downloading = true;
    _doneTiles = 0;
    _doneKiB = 0;
    _totalTiles = await FMTCStore(source.storeName).download.countTiles(downloadable);
    _lastFinished = null;
    notifyListeners();

    final completer = Completer<void>();
    final result = FMTCStore(storeName).download.startForeground(
          region: downloadable,
          skipSeaTiles: false,
        );

    _sub = result.downloadProgress.listen(
      (p) {
        _doneTiles = p.successfulTilesCount;
        _doneKiB = p.successfulTilesSize;
        _totalTiles = p.maxTilesCount;
        notifyListeners();
      },
      onDone: () async {
        await _finish(
          id: id,
          storeName: storeName,
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
          source: source,
          name: name,
        );
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  Future<void> _finish({
    required String id,
    required String storeName,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required TileSource source,
    required String name,
  }) async {
    final region = DownloadRegion(
      id: id,
      name: name,
      sourceId: source.id,
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
      minZoom: minZoom,
      maxZoom: maxZoom,
      tiles: _doneTiles,
      sizeKiB: _doneKiB,
      createdAt: DateTime.now(),
    );

    if (_doneTiles > 0) {
      _regions.insert(0, region);
      await _save();
      _lastFinished = region;
    } else {
      // Nada baixado: descarta o store vazio.
      await _deleteStore(storeName);
    }

    _downloading = false;
    _activeStoreName = null;
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  /// Cancela o download em curso e descarta o store parcial.
  Future<void> cancel() async {
    if (!_downloading || _activeStoreName == null) return;
    final storeName = _activeStoreName!;
    try {
      await FMTCStore(storeName).download.cancel();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    await _deleteStore(storeName);
    _downloading = false;
    _activeStoreName = null;
    notifyListeners();
  }

  Future<void> removeRegion(String id) async {
    final r = _byId(id);
    if (r == null) return;
    _regions.remove(r);
    await _deleteStore(r.storeName);
    await _save();
    notifyListeners();
  }

  DownloadRegion? _byId(String id) {
    for (final r in _regions) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _deleteStore(String storeName) async {
    try {
      await FMTCStore(storeName).manage.delete();
    } catch (_) {}
  }

  Future<void> _save() async {
    final file = await _storage();
    await file.writeAsString(jsonEncode(_regions.map((r) => r.toJson()).toList()));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
