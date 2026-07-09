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

  /// Uso real em disco (KiB), somando o tamanho de cada store distinto usado
  /// pelas regiões. Com dedup, rebaixar não infla este número.
  Future<double> totalStorageKiB() async {
    var total = 0.0;
    for (final s in _distinctStores()) {
      try {
        total += await FMTCStore(s).stats.size;
      } catch (_) {}
    }
    return total;
  }

  /// Stores das regiões baixadas para uma fonte (para o mapa renderizar
  /// offline). É um Set: regiões `shared` da mesma fonte colapsam num só store.
  Iterable<String> regionStoresFor(String sourceId) {
    final stores = <String>{};
    for (final r in _regions) {
      if (r.sourceId == sourceId) stores.add(r.storeName);
    }
    return stores;
  }

  Set<String> _distinctStores() => {for (final r in _regions) r.storeName};

  String _downloadStore(String sourceId) => 'dl_$sourceId';

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
    // Garante que os stores existam para o mapa lê-los offline (idempotente).
    for (final s in _distinctStores()) {
      try {
        await FMTCStore(s).manage.create();
      } catch (_) {}
    }
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
    // Store compartilhado por fonte: dedup entre downloads (modelo MyTrails).
    final storeName = _downloadStore(source.id);
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
          skipExistingTiles: true, // dedup: não rebaixa tile que já está no store
          skipSeaTiles: false,
        );

    _sub = result.downloadProgress.listen(
      (p) {
        // Barra avança com tentados (novos + pulados); tamanho = só o adicionado.
        _doneTiles = p.attemptedTilesCount;
        _doneKiB = p.successfulTilesSize;
        _totalTiles = p.maxTilesCount;
        notifyListeners();
      },
      onDone: () async {
        await _finish(
          id: id,
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
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required TileSource source,
    required String name,
  }) async {
    // `tiles` = cobertura total da região; `sizeKiB` = quanto ESTE download
    // adicionou (com dedup, rebaixar mostra ~0 MB, mas a região cobre a área).
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
      tiles: _totalTiles,
      sizeKiB: _doneKiB,
      createdAt: DateTime.now(),
    );

    if (_totalTiles > 0) {
      _regions.insert(0, region);
      await _save();
      _lastFinished = region;
    }
    // Store compartilhado nunca é apagado aqui (pode ter tiles de outras regiões).

    _downloading = false;
    _activeStoreName = null;
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  /// Cancela o download em curso. Os tiles já baixados permanecem no cache
  /// compartilhado (válidos e reaproveitáveis) — não apaga o store.
  Future<void> cancel() async {
    if (!_downloading || _activeStoreName == null) return;
    try {
      await FMTCStore(_activeStoreName!).download.cancel();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    _downloading = false;
    _activeStoreName = null;
    notifyListeners();
  }

  Future<void> removeRegion(String id) async {
    final r = _byId(id);
    if (r == null) return;
    _regions.remove(r);
    if (r.shared) {
      // Metadado apenas (tiles são compartilhados). Se não sobra nenhuma
      // região dessa fonte, o store fica órfão → esvazia para liberar espaço.
      final anyLeft =
          _regions.any((x) => x.shared && x.sourceId == r.sourceId);
      if (!anyLeft) await _resetStore(r.storeName);
    } else {
      // Legado: store próprio, excluir libera exatamente o espaço dela.
      await _deleteStore(r.storeName);
    }
    await _save();
    notifyListeners();
  }

  /// Apaga todos os downloads (tiles + metadados) para liberar espaço.
  Future<void> clearAllDownloads() async {
    for (final s in _distinctStores()) {
      if (s.startsWith('dl_')) {
        await _resetStore(s);
      } else {
        await _deleteStore(s);
      }
    }
    _regions.clear();
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

  /// Esvazia um store (mantém o store, remove os tiles).
  Future<void> _resetStore(String storeName) async {
    try {
      await FMTCStore(storeName).manage.reset();
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
