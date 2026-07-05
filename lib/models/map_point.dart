import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Categorias de ponto do protótipo (água, mirante, perigo...), cada uma com
/// cor e ícone próprios.
enum PointCategory {
  agua('Água', Color(0xFF18E0E0), Icons.water_drop),
  mirante('Mirante', Color(0xFFFFD23F), Icons.landscape),
  perigo('Perigo', Color(0xFFFF5A5A), Icons.warning_amber_rounded),
  bifurcacao('Bifurcação', Color(0xFFF57C1F), Icons.call_split),
  descanso('Descanso', Color(0xFF8FE04A), Icons.park),
  outro('Outro', Color(0xFFFF2DAA), Icons.place);

  const PointCategory(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  static PointCategory fromName(String? name) => PointCategory.values.firstWhere(
        (c) => c.name == name,
        orElse: () => PointCategory.outro,
      );
}

/// Um ponto pessoal marcado no mapa (long-press).
class MapPoint {
  MapPoint({
    required this.id,
    required this.name,
    required this.category,
    required this.point,
    required this.createdAt,
  });

  final String id;
  String name;
  PointCategory category;
  final LatLng point;
  final DateTime createdAt;

  /// Nome de exibição: o nome dado, ou o rótulo da categoria como fallback.
  String get displayName => name.trim().isNotEmpty ? name : category.label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'lat': point.latitude,
        'lon': point.longitude,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MapPoint.fromJson(Map<String, dynamic> j) => MapPoint(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: PointCategory.fromName(j['category'] as String?),
        point: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
