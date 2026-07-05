import 'package:flutter_test/flutter_test.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:soma_trails/format.dart';
import 'package:soma_trails/gpx_parser.dart';

void main() {
  test('formatElapsed: M:SS e H:MM:SS', () {
    expect(formatElapsed(const Duration(seconds: 39)), '0:39');
    expect(formatElapsed(const Duration(minutes: 2, seconds: 36)), '2:36');
    expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 5)),
        '1:02:05');
  });

  test('formatDurationShort: min e h mm', () {
    expect(formatDurationShort(const Duration(minutes: 47)), '47 min');
    expect(formatDurationShort(const Duration(hours: 1, minutes: 2)), '1h 02');
  });

  test('formatWhen: Hoje / Ontem / data', () {
    final now = DateTime(2026, 7, 5, 20, 0);
    expect(formatWhen(DateTime(2026, 7, 5, 14, 5), now: now), 'Hoje · 14:05');
    expect(formatWhen(DateTime(2026, 7, 4, 16, 20), now: now), 'Ontem · 16:20');
    expect(formatWhen(DateTime(2026, 6, 24, 7, 45), now: now), '24/06 · 07:45');
  });

  test('GPX gravado é re-importável (round-trip)', () {
    final seg = [
      const LatLng(-19.300, -43.600),
      const LatLng(-19.301, -43.601),
      const LatLng(-19.302, -43.602),
    ];
    final gpx = Gpx()
      ..creator = 'soma_trails'
      ..trks = [
        Trk(trksegs: [
          Trkseg(
            trkpts: [for (final p in seg) Wpt(lat: p.latitude, lon: p.longitude)],
          ),
        ]),
      ];
    final xml = GpxWriter().asString(gpx);
    final parsed = parseGpx(xml, simplifyToleranceMeters: 0);
    expect(parsed.segments.length, 1);
    expect(parsed.segments.first.length, 3);
    expect(parsed.distanceMeters, greaterThan(0));
  });
}
