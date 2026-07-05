import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import 'theme.dart';
import 'tile_source.dart';

/// Zoom máximo da câmera. Acima do `maxNativeZoom` da fonte o mapa escala os
/// tiles (overzoom) em vez de mostrar tela cinza.
const double _cameraMaxZoom = 20;
const double _cameraMinZoom = 3;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  static const _serraDoCipo = LatLng(-19.3690, -43.5896);

  static const TileSource _source = TileSources.active;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final target = (camera.zoom + delta).clamp(_cameraMinZoom, _cameraMaxZoom);
    _mapController.move(camera.center, target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _serraDoCipo,
              initialZoom: 13,
              minZoom: _cameraMinZoom,
              maxZoom: _cameraMaxZoom,
              // Norte fixo: o mapa não rotaciona (decisão travada no PRD).
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _source.urlTemplate,
                subdomains: _source.subdomains,
                userAgentPackageName: 'dev.soma.soma_trails',
                maxNativeZoom: _source.maxNativeZoom,
                // Cache por navegação: cada tile buscado fica salvo no store.
                // Offline, o mesmo tile carrega do disco sem rede.
                tileProvider: FMTCTileProvider(
                  stores: {
                    _source.storeName: BrowseStoreStrategy.readUpdateCreate,
                  },
                ),
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(_source.attribution),
                ],
              ),
            ],
          ),
          Positioned(
            right: 12,
            top: MediaQuery.of(context).padding.top + 96,
            child: _ZoomControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botões +/- empilhados num cartão escuro arredondado, como no protótipo.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.add, onTap: onZoomIn),
          const SizedBox(
            width: 32,
            child: Divider(height: 1, color: Colors.white12),
          ),
          _ZoomButton(icon: Icons.remove, onTap: onZoomOut),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Icon(icon, size: 26, color: Colors.white),
      ),
    );
  }
}
