import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/map_pick.dart';
import 'package:kamgo_app/features/rides/domain/ride_models.dart';

void main() {
  const chichawatni = GeoPoint(30.5301, 72.6917);
  const toba = GeoPoint(30.9709, 72.4826);

  test('trip distance is straight line x 1.3, one decimal, at least 1 km', () {
    final km = tripDistanceKm(chichawatni, toba);
    expect(km, inInclusiveRange(65, 72));
    expect((km * 10).round() / 10, km);
    expect(tripDistanceKm(chichawatni, chichawatni), 1);
  });

  test('nearest city picks the closest town centre', () {
    final catalog = Catalog(
      cities: const [
        City(id: 'k', name: 'Kamalia', lat: 30.7258, lng: 72.6447),
        City(id: 'c', name: 'Chichawatni', lat: 30.5301, lng: 72.6917),
      ],
      routes: const [],
      settings: const AppSettings(),
    );
    final near = catalog.nearestCity(30.54, 72.70)!;
    expect(near.city.name, 'Chichawatni');
    expect(near.km, lessThan(2));
  });

  test('the title is exactly what the passenger wrote, with nothing added', () {
    const typed = MapPick(point: chichawatni, nearestName: 'Chichawatni', label: 'ravi town kamalia');
    const pin = MapPick(point: chichawatni, nearestName: 'Chichawatni');
    const town = MapPick(point: chichawatni, nearestName: 'Chichawatni', isTownCentre: true);
    expect(typed.title, 'ravi town kamalia');
    expect(typed.serverLabel, 'ravi town kamalia');
    expect(pin.title, 'Pinned location');
    expect(pin.serverLabel, 'Pinned location');
    expect(town.title, 'Chichawatni (town centre)');
    expect(town.serverLabel, 'Chichawatni (town centre)');
    for (final p in [typed, pin, town]) {
      expect(p.title.toLowerCase(), isNot(contains('near')));
    }
  });
}
