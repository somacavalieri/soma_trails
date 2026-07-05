import 'dart:math' as math;

import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

/// Um waypoint nomeado do GPX (início, água, mirante...).
class GpxWaypoint {
  const GpxWaypoint(this.point, this.name);
  final LatLng point;
  final String? name;
}

/// Resultado de parsear um GPX: geometria pronta para desenhar.
///
/// `segments` é uma lista de polylines — um GPX pode ter vários `<trk>`,
/// vários `<trkseg>` e `<rte>` (rotas). Todos viram segmentos aqui.
class ParsedGpx {
  const ParsedGpx({
    required this.segments,
    required this.waypoints,
    required this.distanceMeters,
    required this.suggestedName,
  });

  final List<List<LatLng>> segments;
  final List<GpxWaypoint> waypoints;
  final double distanceMeters;
  final String? suggestedName;

  bool get isEmpty => segments.isEmpty && waypoints.isEmpty;
}

const _distance = Distance();

/// Parseia o conteúdo de um arquivo GPX. Trata múltiplos tracks/segmentos e
/// rotas; simplifica cada segmento para não engasgar com trilhas longas.
ParsedGpx parseGpx(String xml, {double simplifyToleranceMeters = 5}) {
  final gpx = GpxReader().fromString(xml);

  final segments = <List<LatLng>>[];
  String? suggestedName;

  void addSegment(List<Wpt> points) {
    final pts = <LatLng>[];
    for (final w in points) {
      if (w.lat != null && w.lon != null) {
        pts.add(LatLng(w.lat!, w.lon!));
      }
    }
    if (pts.length >= 2) {
      segments.add(_simplify(pts, simplifyToleranceMeters));
    }
  }

  for (final trk in gpx.trks) {
    suggestedName ??= trk.name;
    for (final seg in trk.trksegs) {
      addSegment(seg.trkpts);
    }
  }
  for (final rte in gpx.rtes) {
    suggestedName ??= rte.name;
    addSegment(rte.rtepts);
  }

  final waypoints = <GpxWaypoint>[];
  for (final w in gpx.wpts) {
    if (w.lat != null && w.lon != null) {
      waypoints.add(GpxWaypoint(LatLng(w.lat!, w.lon!), w.name));
    }
  }

  double dist = 0;
  for (final seg in segments) {
    for (var i = 1; i < seg.length; i++) {
      dist += _distance.as(LengthUnit.Meter, seg[i - 1], seg[i]);
    }
  }

  return ParsedGpx(
    segments: segments,
    waypoints: waypoints,
    distanceMeters: dist,
    suggestedName: suggestedName,
  );
}

/// Ramer–Douglas–Peucker: reduz o nº de pontos preservando o formato.
/// Usa aproximação planar local (equiretangular) — precisa o bastante na
/// escala de uma trilha.
List<LatLng> _simplify(List<LatLng> points, double toleranceMeters) {
  if (points.length <= 2 || toleranceMeters <= 0) return points;

  final lat0 = points.first.latitudeInRad;
  final mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * math.cos(lat0);

  double px(LatLng p) => p.longitude * mPerDegLon;
  double py(LatLng p) => p.latitude * mPerDegLat;

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  final stack = <List<int>>[
    [0, points.length - 1],
  ];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final first = range[0];
    final last = range[1];
    if (last <= first + 1) continue;

    final ax = px(points[first]), ay = py(points[first]);
    final bx = px(points[last]), by = py(points[last]);
    final dx = bx - ax, dy = by - ay;
    final segLenSq = dx * dx + dy * dy;

    var maxDist = -1.0;
    var index = first;
    for (var i = first + 1; i < last; i++) {
      final cx = px(points[i]), cy = py(points[i]);
      double d;
      if (segLenSq == 0) {
        final ex = cx - ax, ey = cy - ay;
        d = math.sqrt(ex * ex + ey * ey);
      } else {
        // Distância perpendicular do ponto i à reta first–last.
        final cross = ((cx - ax) * dy - (cy - ay) * dx).abs();
        d = cross / math.sqrt(segLenSq);
      }
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist > toleranceMeters) {
      keep[index] = true;
      stack.add([first, index]);
      stack.add([index, last]);
    }
  }

  final result = <LatLng>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) result.add(points[i]);
  }
  return result;
}
