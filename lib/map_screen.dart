import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'location_marker.dart';
import 'location_service.dart';
import 'models/track.dart';
import 'point_manager.dart';
import 'points_panel.dart';
import 'recording_hud.dart';
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
  late final TrackRecorder _recorder = TrackRecorder(_location);
  StreamSubscription<Position>? _positionSub;

  Position? _position;
  bool _follow = false;

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
  }

  @override
  void dispose() {
    _tracks.removeListener(_onChange);
    _recorder.removeListener(_onChange);
    _points.removeListener(_onChange);
    _sources.removeListener(_onChange);
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
    _location.start();
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
    if (_follow && event.source == MapEventSource.onDrag) {
      setState(() => _follow = false);
    }
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
      onStartRecording: _startRecording,
      onShowTrack: (track) {
        setState(() => _follow = false);
        _fitToPoints([for (final seg in track.segments) ...seg]);
      },
    );
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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — em breve')),
    );
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final target = (camera.zoom + delta).clamp(_cameraMinZoom, _cameraMaxZoom);
    _mapController.move(camera.center, target);
  }

  static LatLng _toLatLng(Position p) => LatLng(p.latitude, p.longitude);

  // ---- Camadas -----------------------------------------------------------

  List<Polyline> _trackPolylines() {
    final lines = <Polyline>[];
    for (final t in _tracks.tracks) {
      if (!t.visible) continue;
      for (final seg in t.segments) {
        lines.add(Polyline(points: seg, color: t.color, strokeWidth: 4));
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
    return [
      for (final seg in _recorder.liveSegments)
        if (seg.length >= 2)
          Polyline(
            points: seg,
            color: AppColors.accent,
            strokeWidth: 5,
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
                key: ValueKey(_sources.active.id),
                urlTemplate: _sources.active.urlTemplate,
                subdomains: _sources.active.subdomains,
                userAgentPackageName: 'dev.soma.soma_trails',
                maxNativeZoom: _sources.active.maxNativeZoom,
                tileProvider: FMTCTileProvider(
                  stores: {
                    _sources.active.storeName:
                        BrowseStoreStrategy.readUpdateCreate,
                  },
                ),
              ),
              PolylineLayer(polylines: _trackPolylines()),
              MarkerLayer(markers: _waypointMarkers()),
              MarkerLayer(markers: _pointMarkers()),
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

          // Camadas (fontes do mapa)
          Positioned(
            left: 12,
            top: topInset + (_recorder.isActive ? 96 : 24),
            child: _MapIconButton(icon: Icons.layers, onTap: _openSources),
          ),

          // Zoom +/-
          Positioned(
            right: 12,
            top: topInset + (_recorder.isActive ? 96 : 24),
            child: _ZoomControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
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
              onBaixar: () => _comingSoon('Baixar satélite'),
              onAjustes: () => _comingSoon('Ajustes'),
            ),
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
