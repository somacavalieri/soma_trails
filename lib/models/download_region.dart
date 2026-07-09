import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Uma região de satélite baixada para uso offline. Associada a uma fonte
/// ([sourceId]) — só é renderizada quando essa fonte está ativa.
///
/// [shared] = modelo atual (MyTrails): todas as regiões de uma fonte gravam num
/// mesmo store (`dl_<sourceId>`), com dedup — rebaixar área sobreposta não
/// duplica tiles. Regiões antigas (`shared == false`) têm store próprio
/// (`rgn_<id>`) e continuam funcionando (compatibilidade).
class DownloadRegion {
  DownloadRegion({
    required this.id,
    required this.name,
    required this.sourceId,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.minZoom,
    required this.maxZoom,
    required this.tiles,
    required this.sizeKiB,
    required this.createdAt,
    this.shared = true,
  });

  final String id;
  String name;
  final String sourceId;
  final double south;
  final double west;
  final double north;
  final double east;
  final int minZoom;
  final int maxZoom;
  final int tiles;
  final double sizeKiB;
  final DateTime createdAt;
  final bool shared;

  /// Store compartilhado por fonte (novo) ou próprio (legado).
  String get storeName => shared ? 'dl_$sourceId' : 'rgn_$id';

  LatLngBounds get bounds =>
      LatLngBounds(LatLng(south, west), LatLng(north, east));

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceId': sourceId,
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tiles': tiles,
        'sizeKiB': sizeKiB,
        'createdAt': createdAt.toIso8601String(),
        'shared': shared,
      };

  factory DownloadRegion.fromJson(Map<String, dynamic> j) => DownloadRegion(
        id: j['id'] as String,
        name: j['name'] as String,
        sourceId: j['sourceId'] as String,
        south: (j['south'] as num).toDouble(),
        west: (j['west'] as num).toDouble(),
        north: (j['north'] as num).toDouble(),
        east: (j['east'] as num).toDouble(),
        minZoom: (j['minZoom'] as num).toInt(),
        maxZoom: (j['maxZoom'] as num).toInt(),
        tiles: (j['tiles'] as num).toInt(),
        sizeKiB: (j['sizeKiB'] as num).toDouble(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        // JSON antigo não tem 'shared' → era store próprio (legado).
        shared: j['shared'] as bool? ?? false,
      );
}

/// Estimativa mostrada antes de baixar.
class DownloadEstimate {
  const DownloadEstimate({
    required this.tiles,
    required this.sizeKiB,
    required this.seconds,
  });
  final int tiles;
  final double sizeKiB;
  final int seconds;
}

/// Formata KiB em MB/GB legível.
String formatSizeKiB(double kib) {
  final mb = kib / 1024.0;
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  if (mb >= 10) return '${mb.round()} MB';
  return '${mb.toStringAsFixed(1)} MB';
}
