import 'package:latlong2/latlong.dart';

/// Um trajeto gravado (breadcrumb "de onde eu vim"), já finalizado e salvo.
///
/// Persistido como GPX no disco + metadados no JSON. A geometria ([segments])
/// é re-parseada do GPX na abertura.
class RecordedTrack {
  RecordedTrack({
    required this.id,
    required this.name,
    required this.storedPath,
    required this.startedAt,
    required this.duration,
    required this.distanceMeters,
    required this.segments,
  });

  final String id;
  String name;
  final String storedPath;
  final DateTime startedAt;
  final Duration duration;
  final double distanceMeters;
  final List<List<LatLng>> segments;

  double get distanceKm => distanceMeters / 1000.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'storedPath': storedPath,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'distanceMeters': distanceMeters,
      };
}
