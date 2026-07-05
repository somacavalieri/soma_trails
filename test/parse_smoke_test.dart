import 'package:flutter_test/flutter_test.dart';
import 'package:soma_trails/gpx_parser.dart';

const sample = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test">
  <wpt lat="-19.30" lon="-43.60"><name>Nascente fria</name></wpt>
  <trk><name>Descida do Diabo</name>
    <trkseg>
      <trkpt lat="-19.300" lon="-43.600"/>
      <trkpt lat="-19.3005" lon="-43.6005"/>
      <trkpt lat="-19.301" lon="-43.601"/>
      <trkpt lat="-19.302" lon="-43.602"/>
    </trkseg>
    <trkseg>
      <trkpt lat="-19.310" lon="-43.610"/>
      <trkpt lat="-19.311" lon="-43.611"/>
    </trkseg>
  </trk>
  <rte><name>Rota alt</name>
    <rtept lat="-19.320" lon="-43.620"/>
    <rtept lat="-19.321" lon="-43.621"/>
  </rte>
</gpx>''';

void main() {
  test('parseGpx: 2 trksegs + 1 rte = 3 segmentos, 1 waypoint, nome do trk', () {
    final p = parseGpx(sample);
    expect(p.segments.length, 3);
    expect(p.waypoints.length, 1);
    expect(p.waypoints.first.name, 'Nascente fria');
    expect(p.suggestedName, 'Descida do Diabo');
    expect(p.distanceMeters, greaterThan(0));
  });
}
