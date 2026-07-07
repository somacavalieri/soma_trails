import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import 'download_controller.dart';
import 'models/download_region.dart';
import 'models/track.dart';
import 'regions_screen.dart';
import 'source_manager.dart';
import 'theme.dart';
import 'track_manager.dart';

const _distance = Distance();
const int _minZoom = 12;

/// Margem baixada em volta da trilha, para você não ficar sem mapa ao desviar
/// da rota. O FMTC aplica ~0,785× (π/4) sobre o raio do LineRegion, então
/// ~1300 m dão ~1 km de folga de cada lado (faixa de ~2 km de largura).
const double _trackMarginMeters = 1300;

/// Folga em metros usada para os limites salvos da região (para o chip
/// "Offline pronto" acender quando você desvia para dentro da faixa baixada).
const double _trackBoundsMarginMeters = 1000;

enum _Step { select, detail, progress, done }

enum _Mode { area, track }

/// Assistente "Baixar satélite": selecionar área/trilha → zoom+estimativa →
/// progresso → pronto.
class DownloadWizard extends StatefulWidget {
  const DownloadWizard({
    super.key,
    required this.controller,
    required this.sources,
    required this.tracks,
    required this.initialBounds,
  });

  final OfflineDownloadController controller;
  final SourceManager sources;
  final TrackManager tracks;
  final LatLngBounds initialBounds;

  @override
  State<DownloadWizard> createState() => _DownloadWizardState();
}

class _DownloadWizardState extends State<DownloadWizard> {
  _Step _step = _Step.select;
  _Mode _mode = _Mode.area;
  double _areaScale = 1;
  Track? _track;
  int _maxZoom = 15;
  DownloadEstimate? _estimate;
  bool _estimating = false;

  LatLngBounds get _areaBounds {
    final b = widget.initialBounds;
    final cLat = (b.south + b.north) / 2;
    final cLon = (b.west + b.east) / 2;
    final halfLat = (b.north - b.south) / 2 * _areaScale;
    final halfLon = (b.east - b.west) / 2 * _areaScale;
    return LatLngBounds(
      LatLng(cLat - halfLat, cLon - halfLon),
      LatLng(cLat + halfLat, cLon + halfLon),
    );
  }

  double _areaKm2(LatLngBounds b) {
    final cLat = (b.south + b.north) / 2;
    final w = _distance.as(
        LengthUnit.Meter, LatLng(cLat, b.west), LatLng(cLat, b.east));
    final cLon = (b.west + b.east) / 2;
    final h = _distance.as(
        LengthUnit.Meter, LatLng(b.south, cLon), LatLng(b.north, cLon));
    return (w * h) / 1e6;
  }

  List<LatLng> get _trackPoints =>
      [for (final seg in _track?.segments ?? const []) ...seg];

  BaseRegion _region() {
    if (_mode == _Mode.track && _trackPoints.length >= 2) {
      // Corredor de ~1 km de cada lado do traçado (raio em METROS).
      return LineRegion(_trackPoints, _trackMarginMeters);
    }
    return RectangleRegion(_areaBounds);
  }

  /// Limites da região para metadados/"Offline pronto". Na trilha, o bbox do
  /// traçado é expandido pela margem para bater com a faixa realmente baixada.
  LatLngBounds _regionBounds() {
    if (_mode == _Mode.track && _trackPoints.isNotEmpty) {
      return _expandBounds(
        LatLngBounds.fromPoints(_trackPoints),
        _trackBoundsMarginMeters,
      );
    }
    return _areaBounds;
  }

  LatLngBounds _expandBounds(LatLngBounds b, double meters) {
    final latDelta = meters / 111320.0;
    final cLat = (b.south + b.north) / 2;
    final lonDelta =
        meters / (111320.0 * math.cos(cLat * math.pi / 180.0)).abs();
    return LatLngBounds(
      LatLng(b.south - latDelta, b.west - lonDelta),
      LatLng(b.north + latDelta, b.east + lonDelta),
    );
  }

  String _regionName() {
    if (_mode == _Mode.track && _track != null) return _track!.name;
    return 'Área ${DateTime.now().day}/${DateTime.now().month}';
  }

  bool get _canProceed =>
      _mode == _Mode.area || (_mode == _Mode.track && _track != null);

  Future<void> _computeEstimate() async {
    setState(() => _estimating = true);
    try {
      final est = await widget.controller.estimate(
        region: _region(),
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        source: widget.sources.active,
      );
      if (mounted) setState(() => _estimate = est);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _download() async {
    setState(() => _step = _Step.progress);
    await widget.controller.start(
      region: _region(),
      bounds: _regionBounds(),
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      source: widget.sources.active,
      name: _regionName(),
    );
    if (mounted) setState(() => _step = _Step.done);
  }

  Future<void> _cancel() async {
    await widget.controller.cancel();
    if (mounted) setState(() => _step = _Step.detail);
  }

  void _openRegions() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RegionsScreen(controller: widget.controller),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(switch (_step) {
          _Step.select => 'Selecionar área',
          _Step.detail => 'Detalhe (zoom)',
          _Step.progress => 'Baixando…',
          _Step.done => 'Pronto!',
        }),
        actions: [
          TextButton.icon(
            onPressed: _openRegions,
            icon: const Icon(Icons.folder_outlined, color: AppColors.ok),
            label: const Text('Regiões', style: TextStyle(color: AppColors.ok)),
          ),
        ],
      ),
      body: switch (_step) {
        _Step.select => _buildSelect(),
        _Step.detail => _buildDetail(),
        _Step.progress => _buildProgress(),
        _Step.done => _buildDone(),
      },
    );
  }

  // ---- Passo 1: selecionar --------------------------------------------

  Widget _buildSelect() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(
                  value: _Mode.area,
                  icon: Icon(Icons.crop_free),
                  label: Text('Por área')),
              ButtonSegment(
                  value: _Mode.track,
                  icon: Icon(Icons.route),
                  label: Text('Por trilha')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: _mode == _Mode.area ? _buildAreaSelect() : _buildTrackSelect(),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _canProceed
                    ? () {
                        setState(() => _step = _Step.detail);
                        _computeEstimate();
                      }
                    : null,
                child: const Text('Próximo: Detalhe'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaSelect() {
    final bounds = _areaBounds;
    final km2 = _areaKm2(bounds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A área é o mapa que você estava vendo. Ajuste o tamanho abaixo.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tamanho da área',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text('${km2.toStringAsFixed(0)} km²',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _areaScale,
            min: 0.5,
            max: 3,
            activeColor: AppColors.accent,
            onChanged: (v) => setState(() => _areaScale = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackSelect() {
    final tracks = widget.tracks.tracks;
    if (tracks.isEmpty) {
      return const Center(
        child: Text('Importe uma trilha primeiro.',
            style: TextStyle(color: AppColors.textDim)),
      );
    }
    return RadioGroup<Track>(
      groupValue: _track,
      onChanged: (v) => setState(() => _track = v),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Escolha a trilha — a área se ajusta ao redor dela',
                style: TextStyle(color: AppColors.textDim)),
          ),
          for (final t in tracks)
            RadioListTile<Track>(
              value: t,
              activeColor: AppColors.accent,
              title: Text(t.name),
              subtitle: Text(
                  '${t.distanceKm.toStringAsFixed(1)} km · ${t.fileName}',
                  style: const TextStyle(color: AppColors.textDim)),
              secondary: Container(
                  width: 22,
                  height: 22,
                  decoration:
                      BoxDecoration(color: t.color, shape: BoxShape.circle)),
            ),
        ],
      ),
    );
  }

  // ---- Passo 2: detalhe/zoom ------------------------------------------

  Widget _buildDetail() {
    final est = _estimate;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_mode == _Mode.track && _track != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x22F57C1F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('MAPA A PARTIR DA TRILHA',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                            Text(_track!.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Nível de detalhe (zoom)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('$_minZoom → $_maxZoom',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _maxZoom.toDouble(),
                min: 12,
                max: 18,
                divisions: 6,
                label: '$_maxZoom',
                activeColor: AppColors.accent,
                onChanged: (v) => setState(() => _maxZoom = v.round()),
                onChangeEnd: (_) => _computeEstimate(),
              ),
              const Text('Mais zoom = mais nítido, porém muito mais tiles.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 24),
              _EstimateRow(estimate: est, loading: _estimating),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () => setState(() => _step = _Step.select),
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: (est == null || _estimating) ? null : _download,
                    icon: const Icon(Icons.download),
                    label: Text(est == null
                        ? 'Baixar'
                        : 'Baixar · ${formatSizeKiB(est.sizeKiB)}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Passo 3: progresso ---------------------------------------------

  Widget _buildProgress() {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final c = widget.controller;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LinearProgressIndicator(
                value: c.progress == 0 ? null : c.progress,
                color: AppColors.accent,
                backgroundColor: Colors.white12,
                minHeight: 8,
              ),
              const SizedBox(height: 20),
              Text('${(c.progress * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${c.doneTiles} / ${c.totalTiles} tiles · ${formatSizeKiB(c.doneKiB)}',
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B),
                  side: const BorderSide(color: Color(0x55FF6B6B)),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Passo 4: pronto -------------------------------------------------

  Widget _buildDone() {
    final region = widget.controller.lastFinished;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: AppColors.ok, size: 52),
          ),
          const SizedBox(height: 20),
          const Text('Área pronta para offline',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            region == null
                ? 'Nada foi baixado.'
                : '${region.name} está salva. Você pode navegar sem sinal.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim),
          ),
          if (region != null) ...[
            const SizedBox(height: 12),
            Text('${region.tiles} tiles · ${formatSizeKiB(region.sizeKiB)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Concluir'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _openRegions,
              child: const Text('Ver regiões baixadas'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.estimate, required this.loading});
  final DownloadEstimate? estimate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading || estimate == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    final e = estimate!;
    return Row(
      children: [
        _Stat(value: '${e.tiles}', label: 'tiles'),
        _Stat(value: formatSizeKiB(e.sizeKiB), label: 'tamanho'),
        _Stat(value: '${e.seconds}s', label: 'tempo est.'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
