import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const SomaTrailsApp());

class SomaTrailsApp extends StatelessWidget {
  const SomaTrailsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'soma_trails',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MapScreen(),
    );
  }
}

/// Passo 1 do plano: "hello map" — valida toolchain + flutter_map no device.
/// Tiles online direto da Esri; FMTC (cache offline) entra no passo 2.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  static const _serraDoCipo = LatLng(-19.3690, -43.5896);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: _serraDoCipo,
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'dev.soma.soma_trails',
            maxNativeZoom: 19,
          ),
          const SimpleAttributionWidget(
            source: Text('Esri World Imagery'),
          ),
        ],
      ),
    );
  }
}
