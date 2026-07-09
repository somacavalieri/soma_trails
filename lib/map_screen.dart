import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'download_controller.dart';
import 'download_wizard.dart';
import 'location_marker.dart';
import 'location_service.dart';
import 'models/track.dart';
import 'point_manager.dart';
import 'points_panel.dart';
import 'recording_hud.dart';
import 'settings_controller.dart';
import 'settings_screen.dart';
import 'source_manager.dart';
import 'sources_screen.dart';
import 'theme.dart';
import 'track_manager.dart';
import 'track_recorder.dart';
import 'tracks_panel.dart';
import 'trajeto_panel.dart';
import 'widgets/bottom_nav.dart';

/// Zoom máximo da câmera. Acima do `maxNativeZoom` da fonte o mapa escala os
/// tiles (overzoom) em vez de mostrar tela cinza.
const double _cameraMaxZoom = 20;
const double _cameraMinZoom = 3;
const double _followZoom = 16;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _location = LocationService();
  final _tracks = TrackManager();
  final _points = PointManager();
  final _sources = SourceManager();
  final _download = OfflineDownloadController();
  late final SettingsController _settings = SettingsController(_sources);
  late final TrackRecorder _recorder = TrackRecorder(_location);
  StreamSubscription<Position>? _positionSub;

  Position? _position;
  bool _follow = false;
  double _zoom = 13;
  Timer? _debugTimer;

  /// Trajetos salvos que o usuário mandou mostrar no mapa (por id).
  final Set<String> _shownRecordings = {};

  /// Painel de diagnóstico do GPS — ligado/desligado nos Ajustes.
  bool get _showDebug => _settings.gpsDebug;

  static const _serraDoCipo = LatLng(-19.3690, -43.5896);

  @override
  void initState() {
    super.initState();
    _tracks.addListener(_onChange);
    _recorder.addListener(_onChange);
    _points.addListener(_onChange);
    _points.load();
    _sources.addListener(_onChange);
    _sources.load();
    _download.addListener(_onChange);
    _download.load();
    _settings.addListener(_onChange);
    _settings.load();
    _tracks.load().then((_) {
      if (mounted && !_follow) {
        _fitToTracks(_tracks.tracks.where((t) => t.visible));
      }
    });
    // Se o app foi morto gravando, retoma automaticamente ao reabrir.
    _recorder.init().then((_) {
      if (mounted && _recorder.needsAutoResume) _resumeRecording();
    });
    _startLocation(recenter: false);
    // Mantém o painel de diagnóstico (tempo desde o último fix) atualizado.
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _showDebug) setState(() {});
    });
  }

  @override
  void dispose() {
    _tracks.removeListener(_onChange);
    _recorder.removeListener(_onChange);
    _points.removeListener(_onChange);
    _sources.removeListener(_onChange);
    _download.removeListener(_onChange);
    _download.dispose();
    _settings.removeListener(_onChange);
    _debugTimer?.cancel();
    _recorder.dispose();
    _positionSub?.cancel();
    _location.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  // ---- Localização -------------------------------------------------------

  /// Garante permissão + serviço, liga o stream e assina o marcador.
  Future<bool> _ensureLocation() async {
    final result = await _location.ensureReady();
    if (!mounted) return false;
    if (result != LocationReadyResult.ready) {
      _showLocationProblem(result);
      return false;
    }
    await _location.start();
    _positionSub ??= _location.positions.listen(_onPosition);
    return true;
  }

  Future<void> _startLocation({required bool recenter}) async {
    if (!await _ensureLocation()) return;
    if (recenter) {
      final last = await _location.lastKnown();
      if (last != null && mounted) {
        _mapController.move(_toLatLng(last), _followZoom);
      }
      setState(() => _follow = true);
    }
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    setState(() => _position = pos);
    if (_follow) {
      _mapController.move(_toLatLng(pos), _mapController.camera.zoom);
    }
  }

  void _onRecenter() {
    if (_position != null) {
      setState(() => _follow = true);
      _mapController.move(_toLatLng(_position!), _followZoom);
    } else {
      _startLocation(recenter: true);
    }
  }

  void _onMapEvent(MapEvent event) {
    final z = event.camera.zoom;
    final unfollow = _follow && event.source == MapEventSource.onDrag;
    // Rebuild só quando o zoom exibido muda (ou ao sair do modo seguir).
    if (unfollow || z.round() != _zoom.round()) {
      setState(() {
        if (unfollow) _follow = false;
        _zoom = z;
      });
    } else {
      _zoom = z;
    }
  }

  /// Maior zoom baixado que cobre o centro atual (para avisar de overzoom).
  int? _downloadedMaxZoomAtCenter() {
    LatLng center;
    try {
      center = _mapController.camera.center;
    } catch (_) {
      return null;
    }
    int? maxZoom;
    for (final r in _download.regions) {
      if (r.sourceId == _sources.active.id && r.contains(center)) {
        if (maxZoom == null || r.maxZoom > maxZoom) maxZoom = r.maxZoom;
      }
    }
    return maxZoom;
  }

  void _showLocationProblem(LocationReadyResult result) {
    final (message, action) = switch (result) {
      LocationReadyResult.serviceDisabled => (
          'Ligue a localização (GPS) do aparelho.',
          null,
        ),
      LocationReadyResult.denied => ('Permissão de localização negada.', null),
      LocationReadyResult.deniedForever => (
          'Permissão bloqueada. Abra as configurações do app.',
          ('Configurações', _location.openAppSettings),
        ),
      LocationReadyResult.ready => ('', null),
    };
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null
            ? null
            : SnackBarAction(label: action.$1, onPressed: action.$2),
      ),
    );
  }

  // ---- Gravação ----------------------------------------------------------

  Future<void> _startRecording() async {
    if (!await _ensureLocation()) return;
    await _recorder.start();
    setState(() => _follow = true);
    if (_position != null) {
      _mapController.move(_toLatLng(_position!), _followZoom);
    }
  }

  Future<void> _resumeRecording() async {
    if (!await _ensureLocation()) return;
    await _recorder.resume();
    setState(() => _follow = true);
  }

  Future<void> _stopRecording() async {
    final track = await _recorder.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(track == null
            ? 'Gravação descartada (sem pontos).'
            : 'Trajeto salvo em "Meu trajeto".'),
      ),
    );
  }

  // ---- Trilhas / trajetos ------------------------------------------------

  void _fitToTracks(Iterable<Track> tracks) {
    final points = [
      for (final t in tracks) ...[
        for (final seg in t.segments) ...seg,
        for (final w in t.waypoints) w.point,
      ],
    ];
    _fitToPoints(points);
  }

  void _fitToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  void _openTracks() {
    showTracksPanel(
      context,
      _tracks,
      onZoomToTrack: (track) {
        Navigator.pop(context);
        _fitToTracks([track]);
      },
      onImported: (imported) {
        setState(() => _follow = false);
        _fitToTracks(imported);
      },
    );
  }

  void _openTrajeto() {
    showTrajetoPanel(
      context,
      _recorder,
      shownIds: _shownRecordings,
      onStartRecording: _startRecording,
      onToggleTrack: (track) {
        final willShow = !_shownRecordings.contains(track.id);
        setState(() {
          _follow = false;
          if (willShow) {
            _shownRecordings.add(track.id);
          } else {
            _shownRecordings.remove(track.id);
          }
        });
        if (willShow) {
          _fitToPoints([for (final seg in track.segments) ...seg]);
        }
      },
    );
  }

  List<Polyline> _savedRecordingPolylines() {
    if (_shownRecordings.isEmpty) return const [];
    final width = _settings.highContrast ? 6.0 : 4.5;
    final lines = <Polyline>[];
    for (final t in _recorder.saved) {
      if (!_shownRecordings.contains(t.id)) continue;
      for (final seg in t.segments) {
        if (seg.length >= 2) {
          lines.add(Polyline(
            points: seg,
            color: AppColors.accent,
            strokeWidth: width,
            borderColor: Colors.black.withValues(alpha: 0.5),
            borderStrokeWidth: 1.5,
          ));
        }
      }
    }
    return lines;
  }

  // ---- Pontos ------------------------------------------------------------

  Future<void> _onLongPress(LatLng at) async {
    final data = await showAddPointDialog(context, at);
    if (data == null || !mounted) return;
    await _points.add(point: at, name: data.name, category: data.category);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ponto marcado.')),
    );
  }

  void _openPoints() {
    showPointsPanel(
      context,
      _points,
      onShow: (p) {
        setState(() => _follow = false);
        final zoom = _mapController.camera.zoom;
        _mapController.move(p.point, zoom < 15 ? 16 : zoom);
      },
    );
  }

  List<Marker> _pointMarkers() {
    return [
      for (final p in _points.points)
        Marker(
          point: p.point,
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${p.displayName} · ${p.category.label}')),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: p.category.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)],
              ),
              child: Icon(p.category.icon, size: 18, color: Colors.black87),
            ),
          ),
        ),
    ];
  }

  void _openSources() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SourcesScreen(manager: _sources)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(settings: _settings)),
    );
  }

  void _openDownload() {
    LatLngBounds bounds;
    try {
      bounds = _mapController.camera.visibleBounds;
    } catch (_) {
      bounds = LatLngBounds(
        const LatLng(-19.45, -43.70),
        const LatLng(-19.29, -43.48),
      );
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DownloadWizard(
        controller: _download,
        sources: _sources,
        tracks: _tracks,
        initialBounds: bounds,
      ),
    ));
  }

  /// Stores do FMTC para o mapa: browse da fonte ativa (read/write) + regiões
  /// baixadas dessa fonte (read) — assim os tiles baixados renderizam offline.
  Map<String, BrowseStoreStrategy> _providerStores() {
    final stores = <String, BrowseStoreStrategy>{
      _sources.active.storeName: BrowseStoreStrategy.readUpdateCreate,
    };
    for (final s in _download.regionStoresFor(_sources.active.id)) {
      stores[s] = BrowseStoreStrategy.read;
    }
    return stores;
  }

  /// "Offline pronto": o centro atual está coberto por uma região baixada.
  bool _offlineReady() {
    LatLng center;
    try {
      center = _mapController.camera.center;
    } catch (_) {
      return false;
    }
    return _download.regions
        .any((r) => r.sourceId == _sources.active.id && r.contains(center));
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final target = (camera.zoom + delta).clamp(_cameraMinZoom, _cameraMaxZoom);
    _mapController.move(camera.center, target);
  }

  static LatLng _toLatLng(Position p) => LatLng(p.latitude, p.longitude);

  // ---- Camadas -----------------------------------------------------------

  List<Polyline> _trackPolylines() {
    final hc = _settings.highContrast;
    final width = hc ? 6.0 : 4.0;
    final lines = <Polyline>[];
    for (final t in _tracks.tracks) {
      if (!t.visible) continue;
      for (final seg in t.segments) {
        lines.add(Polyline(
          points: seg,
          color: t.color,
          strokeWidth: width,
          borderColor: hc ? Colors.black : const Color(0x00000000),
          borderStrokeWidth: hc ? 2 : 0,
        ));
      }
    }
    return lines;
  }

  List<Marker> _waypointMarkers() {
    final markers = <Marker>[];
    for (final t in _tracks.tracks) {
      if (!t.visible) continue;
      for (final w in t.waypoints) {
        markers.add(
          Marker(
            point: w.point,
            width: 30,
            height: 30,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {
                if (w.name != null && w.name!.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(w.name!)));
                }
              },
              child: Icon(Icons.place, color: t.color, size: 28),
            ),
          ),
        );
      }
    }
    return markers;
  }

  List<Polyline> _recordingPolylines() {
    if (!_recorder.isActive) return const [];
    final width = _settings.highContrast ? 7.0 : 5.0;
    return [
      for (final seg in _recorder.liveSegments)
        if (seg.length >= 2)
          Polyline(
            points: seg,
            color: AppColors.accent,
            strokeWidth: width,
            borderColor: Colors.black.withValues(alpha: 0.5),
            borderStrokeWidth: 1.5,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topInset = MediaQuery.of(context).padding.top;
    final startPoint = _recorder.startPoint;
    // Controles do topo descem quando o HUD de gravação ou o painel de debug
    // ocupam o topo.
    final controlsTop =
        topInset + (_recorder.isActive ? 96.0 : 24.0) + (_showDebug ? 62.0 : 0.0);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _serraDoCipo,
              initialZoom: 13,
              minZoom: _cameraMinZoom,
              maxZoom: _cameraMaxZoom,
              onMapEvent: _onMapEvent,
              onLongPress: (_, latlng) => _onLongPress(latlng),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                key: ValueKey(
                    '${_sources.active.id}_${_download.regions.length}'),
                urlTemplate: _sources.active.urlTemplate,
                subdomains: _sources.active.subdomains,
                userAgentPackageName: 'dev.soma.soma_trails',
                maxNativeZoom: _sources.active.maxNativeZoom,
                tileProvider: FMTCTileProvider(stores: _providerStores()),
              ),
              PolylineLayer(polylines: _trackPolylines()),
              MarkerLayer(markers: _waypointMarkers()),
              MarkerLayer(markers: _pointMarkers()),
              PolylineLayer(polylines: _savedRecordingPolylines()),
              PolylineLayer(polylines: _recordingPolylines()),
              if (startPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: startPoint,
                      width: 22,
                      height: 22,
                      child: const _StartPin(),
                    ),
                  ],
                ),
              if (pos != null) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _toLatLng(pos),
                      radius: pos.accuracy,
                      useRadiusInMeter: true,
                      color: const Color(0x222F7BFF),
                      borderColor: const Color(0x552F7BFF),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _toLatLng(pos),
                      width: 44,
                      height: 44,
                      child: LocationDot(
                        headingRadians:
                            headingToRadians(pos.heading, pos.speed),
                      ),
                    ),
                  ],
                ),
              ],
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(_sources.active.attribution),
                ],
              ),
            ],
          ),

          // HUD de gravação (topo)
          if (_recorder.isActive)
            Positioned(
              top: topInset + 12,
              left: 12,
              right: 12,
              child: RecordingHud(recorder: _recorder),
            ),

          // Painel de diagnóstico do GPS (temporário; toque para esconder)
          if (_showDebug)
            Positioned(
              top: topInset + 4,
              left: 8,
              right: 8,
              child: _GpsDebugPanel(
                location: _location,
                recorder: _recorder,
                position: _position,
                onHide: () => _settings.setGpsDebug(false),
              ),
            ),

          // Chip "Offline pronto" (centro coberto por região baixada)
          if (!_recorder.isActive && !_showDebug && _offlineReady())
            Positioned(
              top: topInset + 28,
              left: 0,
              right: 0,
              child: const Center(child: _OfflineReadyChip()),
            ),

          // Camadas (fontes do mapa)
          Positioned(
            left: 12,
            top: controlsTop,
            child: _MapIconButton(icon: Icons.layers, onTap: _openSources),
          ),

          // Zoom +/- com indicador do nível atual
          Positioned(
            right: 12,
            top: controlsTop,
            child: Column(
              children: [
                _ZoomControls(
                  onZoomIn: () => _zoomBy(1),
                  onZoomOut: () => _zoomBy(-1),
                ),
                const SizedBox(height: 6),
                _ZoomBadge(
                  zoom: _zoom.round(),
                  downloadedMax: _downloadedMaxZoomAtCenter(),
                ),
              ],
            ),
          ),

          // Recentralizar
          Positioned(
            right: 16,
            bottom: 96 + bottomInset,
            child: FloatingActionButton(
              heroTag: 'recenter',
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              onPressed: _onRecenter,
              child:
                  Icon(_follow ? Icons.my_location : Icons.location_searching),
            ),
          ),

          // Controles de gravação (canto inferior esquerdo)
          Positioned(
            left: 16,
            bottom: 96 + bottomInset,
            child: _RecordControls(
              state: _recorder.state,
              onStart: _startRecording,
              onPause: _recorder.pause,
              onResume: _resumeRecording,
              onStop: _stopRecording,
            ),
          ),

          // Pill de pontos (hint "segure no mapa" + abre o painel Pontos)
          Positioned(
            left: 0,
            right: 0,
            bottom: 172 + bottomInset,
            child: Center(
              child: _PointsPill(
                count: _points.count,
                onTap: _openPoints,
              ),
            ),
          ),

          // Barra inferior
          Align(
            alignment: Alignment.bottomCenter,
            child: BottomNav(
              visibleTrackCount: _tracks.visibleCount,
              recording: _recorder.isRecording,
              onTrilhas: _openTracks,
              onTrajeto: _openTrajeto,
              onBaixar: _openDownload,
              onAjustes: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel de diagnóstico do GPS (temporário, para depurar a gravação).
class _GpsDebugPanel extends StatelessWidget {
  const _GpsDebugPanel({
    required this.location,
    required this.recorder,
    required this.position,
    required this.onHide,
  });

  final LocationService location;
  final TrackRecorder recorder;
  final Position? position;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final acc = position?.accuracy;
    final sinceFix = location.lastFixAt == null
        ? '—'
        : '${DateTime.now().difference(location.lastFixAt!).inSeconds}s';
    final mode = location.isForeground ? 'foreground' : 'normal';
    final reb = location.rebindCount > 0 ? ' · reb ${location.rebindCount}' : '';
    final rec = recorder.isActive
        ? ' · rec ${recorder.recordedPointCount}pts drop ${recorder.droppedByAccuracy}'
        : '';
    final rawErr = location.lastError?.toString() ?? '';
    final err = rawErr.isEmpty
        ? ''
        : ' · ERRO ${rawErr.length > 48 ? rawErr.substring(0, 48) : rawErr}';

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onHide,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DefaultTextStyle(
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS fixes ${location.fixCount} · último $sinceFix atrás · '
                  '${acc == null ? 'sem fix' : 'prec ${acc.toStringAsFixed(0)}m'}',
                  style: TextStyle(
                    color: location.fixCount == 0
                        ? const Color(0xFFFF6B6B)
                        : Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                Text('modo $mode$reb$rec$err (toque p/ esconder)',
                    style: const TextStyle(
                        color: Color(0xFFB0B0B0),
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip verde "Offline pronto".
class _OfflineReadyChip extends StatelessWidget {
  const _OfflineReadyChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ok.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle, color: AppColors.ok, size: 16),
          SizedBox(width: 6),
          Text('Offline pronto',
              style: TextStyle(
                  color: AppColors.ok,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Selinho com o nível de zoom atual. Fica âmbar quando o zoom passou do
/// máximo baixado no centro (aí a imagem é escalada/borrada, não crua).
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.zoom, required this.downloadedMax});

  final int zoom;
  final int? downloadedMax;

  @override
  Widget build(BuildContext context) {
    final overzoomed = downloadedMax != null && zoom > downloadedMax!;
    final color = overzoomed ? const Color(0xFFFFB020) : AppColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overzoomed) ...[
            Icon(Icons.warning_amber_rounded, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            overzoomed ? 'z$zoom › baixado z$downloadedMax' : 'z$zoom',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Botão redondo escuro sobre o mapa (camadas, etc.).
class _MapIconButton extends StatelessWidget {
  const _MapIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// Pill central: dica "segure no mapa" (0 pontos) ou contador (abre Pontos).
class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 0
        ? 'Segure no mapa para marcar um ponto'
        : '$count ponto${count == 1 ? '' : 's'} marcado${count == 1 ? '' : 's'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x33FF2DAA)),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: AppColors.accentAlt, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pino de início do trajeto gravado.
class _StartPin extends StatelessWidget {
  const _StartPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
    );
  }
}

/// Botão(ões) de gravação: gravar (idle) ou pausar/retomar + parar (ativo).
class _RecordControls extends StatelessWidget {
  const _RecordControls({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecordingState state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (state == RecordingState.idle) {
      return FloatingActionButton(
        heroTag: 'record',
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        onPressed: onStart,
        child: const Icon(Icons.fiber_manual_record, size: 30),
      );
    }
    final recording = state == RecordingState.recording;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'record_toggle',
          backgroundColor: const Color(0xFFE53935),
          foregroundColor: Colors.white,
          onPressed: recording ? onPause : onResume,
          child: Icon(recording ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'record_stop',
          backgroundColor: AppColors.panel,
          foregroundColor: Colors.white,
          onPressed: onStop,
          child: const Icon(Icons.stop),
        ),
      ],
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
