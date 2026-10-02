import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/routing_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const pirMahal = LatLng(30.7667, 72.4333);
  const kamalia = LatLng(30.7258, 72.6447);

  test('haversine distance is sensible', () {
    final km = haversineKm(pirMahal, kamalia);
    expect(km, inInclusiveRange(19, 22));
  });

  test('offline routing applies the 1.3 road factor', () async {
    final est = await const HaversineRoutingService().route([pirMahal, kamalia]);
    expect(est.distanceKm, closeTo(haversineKm(pirMahal, kamalia) * 1.3, 1e-9));
    expect(est.minutes, greaterThan(0));
    expect(est.points, [pirMahal, kamalia]);
  });

  test('pointAlong walks the polyline', () {
    final line = [pirMahal, kamalia];
    expect(pointAlong(line, 0), pirMahal);
    expect(pointAlong(line, 1), kamalia);
    final mid = pointAlong(line, 0.5);
    expect(mid.latitude, closeTo((pirMahal.latitude + kamalia.latitude) / 2, 1e-3));
  });

  test('fractionAlong finds the closest progress', () {
    final line = [pirMahal, kamalia];
    expect(fractionAlong(line, pointAlong(line, 0.3)), closeTo(0.3, 0.02));
  });

  test('OSRM failure falls back to haversine', () async {
    final est = await OsrmRoutingService('http://127.0.0.1:9').route([pirMahal, kamalia]);
    expect(est.points, [pirMahal, kamalia]);
  });
}
