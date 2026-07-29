import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../gpx_parser.dart';

/// Paleta de cores distintas para as trilhas (do protótipo `Soma Trails.html`).
/// Novas importações recebem a próxima cor não usada; editável pelo usuário.
const trackPalette = <Color>[
  Color(0xFFFF2DAA), // rosa
  Color(0xFF18E0E0), // ciano
  Color(0xFFFFD23F), // amarelo
  Color(0xFF8FE04A), // verde-limão
  Color(0xFFF57C1F), // laranja
  Color(0xFF3FA9FF), // azul
  Color(0xFFB06BFF), // roxo
  Color(0xFFFF6B6B), // vermelho
  Color(0xFF35E0A1), // verde-água
  Color(0xFFFFA0D2), // rosa claro
];

/// Uma trilha importada de um arquivo GPX.
///
/// Persistido: metadados (id, nome, arquivo, cor, visível, pastas). A geometria
/// ([segments]/[waypoints]/[distanceMeters]) é re-parseada do GPX na abertura,
/// não vai para o JSON.
class Track {
  Track({
    required this.id,
    required this.name,
    required this.fileName,
    required this.storedPath,
    required this.color,
    required this.visible,
    required this.segments,
    required this.waypoints,
    required this.distanceMeters,
    List<String>? folderIds,
  }) : folderIds = folderIds ?? [];

  final String id;
  String name;
  final String fileName;
  final String storedPath;
  Color color;
  bool visible;

  /// Ids das pastas às quais a trilha pertence (pode ser mais de uma; vazia =
  /// trilha avulsa na raiz do painel).
  List<String> folderIds;

  final List<List<LatLng>> segments;
  final List<GpxWaypoint> waypoints;
  final double distanceMeters;

  double get distanceKm => distanceMeters / 1000.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileName': fileName,
        'storedPath': storedPath,
        'color': color.toARGB32(),
        'visible': visible,
        'folderIds': folderIds,
      };
}
