import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/fare_service.dart';

import 'support/fare_fixtures.dart';

void main() {
  final catalog = Catalog(
    cities: const [],
    routes: const [],
    settings: const AppSettings(maxPassengers: 6),
    categories: testCategories,
  );
  final bike = catalog.category('bike')!;
  final mini = catalog.category('car_mini')!;

  test('every ride type has its own recommended fare', () {
    expect(catalog.quoteFor('car_mini', 5)!.recommended, 770);
    expect(catalog.quoteFor('car_comfort', 5)!.recommended, greaterThan(770));
    expect(catalog.quoteFor('bike', 5)!.recommended, lessThan(770));
    expect(catalog.quoteFor('jet', 5), isNull);
  });

  test('the offer band follows the admin settings (85% to 200%)', () {
    final q = catalog.quoteFor('car_mini', 20)!;
    expect(q.recommended, 2310);
    expect(q.minOffer, 1960);
    expect(q.maxOffer, 4620);
    expect(q.check(1959), FareCheck.tooLow);
    expect(q.check(1960), FareCheck.ok);
    expect(q.check(4621), FareCheck.tooHigh);
  });

  test('categories are listed in display order and hidden past their longest trip', () {
    expect(catalog.categoriesFor(10).map((c) => c.code), ['car_mini', 'car_comfort', 'car_xl', 'bike', 'loader']);
    expect(catalog.categoriesFor(45).map((c) => c.code), ['car_mini', 'car_comfort', 'car_xl', 'loader']);
    expect(catalog.categoriesFor(60).map((c) => c.code), ['car_mini', 'car_comfort', 'car_xl']);
  });

  test('passenger limit is the smaller of the ride type and the global limit', () {
    expect(catalog.maxPassengersFor('bike'), 1);
    expect(catalog.maxPassengersFor('car_mini'), 4);
    expect(catalog.maxPassengersFor('car_xl'), 6);
    expect(catalog.maxPassengersFor('jet'), 6);
    expect(bike.isSingle, isTrue);
    expect(mini.isSingle, isFalse);
  });

  test('categories survive the device cache round trip', () {
    final back = RideCategory.fromJson(bike.toJson());
    expect(back.code, 'bike');
    expect(back.maxKm, 40);
    expect(back.fare.cityMileage, 45);
    expect(back.fare.profitPoints.length, 6);
    expect(back.isCar, isFalse);
    expect(RideCategory.fromJson(mini.toJson()).isCar, isTrue);
  });

  test('service city: nearest city inside its radius, else null', () {
    final c = Catalog(
      cities: const [
        City(id: 't', name: 'Toba Tek Singh', lat: 30.9709, lng: 72.4826, serviceRadiusKm: 25),
        City(id: 'k', name: 'Kamalia', lat: 30.7258, lng: 72.6447, serviceRadiusKm: 25),
      ],
      routes: const [],
      settings: const AppSettings(),
    );
    expect(c.serviceCity(30.98, 72.49)!.id, 't');
    expect(c.serviceCity(30.73, 72.64)!.id, 'k');
    expect(c.serviceCity(32.5, 74.0), isNull);
  });

  test('car lists: only the allowed cars of a ride type', () {
    final withModels = Catalog(
      cities: const [],
      routes: const [],
      settings: const AppSettings(),
      categories: testCategories,
      vehicleModels: const [
        VehicleModel(category: 'car_mini', make: 'Suzuki', model: 'Alto'),
        VehicleModel(category: 'car_mini', make: 'Suzuki', model: 'Wagon R'),
        VehicleModel(category: 'car_comfort', make: 'Honda', model: 'Civic'),
      ],
    );
    expect(withModels.modelsFor('car_mini').map((m) => m.title), ['Suzuki Alto', 'Suzuki Wagon R']);
    expect(withModels.modelsFor('bike'), isEmpty);
    final alto = withModels.modelsFor('car_mini').first;
    expect(alto.matches('suzuki', ' ALTO '), isTrue);
    expect(alto.matches('Toyota', 'Alto'), isFalse);
  });
}