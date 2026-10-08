import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/fare_service.dart';

import 'support/fare_fixtures.dart';

void main() {
  const svc = FareService(FareSettings());

  int fare(FareConfig c, double km, {bool night = false}) => FareService.round10(svc.oneWayFare(c, km, night: night));

  test('car_mini by day: the worked examples', () {
    expect(fare(miniFare, 5), 770);
    expect(fare(miniFare, 20), 2310);
    expect(fare(miniFare, 40), 3360);
    expect(fare(miniFare, 95), 7470);
  });

  test('profit table: straight line between points, slope continues past the last', () {
    expect(FareService.profit(miniFare.profitPoints, 0), 200);
    expect(FareService.profit(miniFare.profitPoints, 2.5), 350);
    expect(FareService.profit(miniFare.profitPoints, 7), 500);
    expect(FareService.profit(miniFare.profitPoints, 30), 1200);
    expect(FareService.profit(miniFare.profitPoints, 70), 1800);
    expect(FareService.profit(miniFare.profitPoints, 150), 3400);
  });

  test('a very short trip pays the minimum fare', () {
    expect(fare(miniFare, 0.5), 450);
    expect(fare(bikeFare, 0.2), 100);
  });

  test('night adds 20 percent', () {
    expect(fare(miniFare, 20, night: true), 2770);
  });

  test('night window is 23:00 to 06:00 Pakistan time', () {
    DateTime pk(int h) => DateTime.utc(2026, 1, 1, h).subtract(const Duration(hours: 5));
    expect(svc.isNight(pk(23)), isTrue);
    expect(svc.isNight(pk(2)), isTrue);
    expect(svc.isNight(pk(5)), isTrue);
    expect(svc.isNight(pk(6)), isFalse);
    expect(svc.isNight(pk(14)), isFalse);
    expect(svc.isNight(pk(22)), isFalse);
  });

  test('loader adds the loading charge only when asked', () {
    final plain = svc.quote(loaderFare, 10);
    final loaded = svc.quote(loaderFare, 10, loading: true);
    expect(loaded.recommended - plain.recommended, 100);
  });

  test('quote: band, commission and driver share', () {
    final q = svc.quoteFor(2310);
    expect(q.minOffer, 1960);
    expect(q.maxOffer, 4620);
    expect(q.commission, 231);
    expect(q.driverGets, 2079);
  });

  test('settings are not hard-coded: a different petrol price changes the fare', () {
    const dear = FareService(FareSettings(petrolPrice: 500));
    expect(FareService.round10(dear.oneWayFare(miniFare, 20)), greaterThan(2310));
  });

  test('waiting: free minutes first, then the per-minute rate', () {
    expect(svc.waitingCharge(miniFare, 4), 0);
    expect(svc.waitingCharge(miniFare, 5), 0);
    expect(svc.waitingCharge(miniFare, 10), 40);
  });

  test('availability by max km', () {
    expect(FareService.availableFor(bikeFare, 40), isTrue);
    expect(FareService.availableFor(bikeFare, 41), isFalse);
    expect(FareService.availableFor(miniFare, 500), isTrue);
  });

  group('hourly rental', () {
    final p4 = testPackages[1];
    test('4h / 40 km: Mini 3940, Comfort 4910, XL 5560', () {
      expect(svc.hourlyFare(miniFare, p4), 3940);
      expect(svc.hourlyFare(comfortFare, p4), 4910);
      expect(svc.hourlyFare(xlFare, p4), 5560);
    });

    test('other packages follow the same formula (hours, km and multiplier come from the data)', () {
      expect(svc.hourlyFare(miniFare, testPackages[0]), greaterThan(0));
      expect(svc.hourlyFare(miniFare, testPackages[3]), greaterThan(svc.hourlyFare(miniFare, testPackages[2])));
    });

    test('quote carries the offer band and the split', () {
      final q = svc.hourlyQuote(miniFare, p4);
      expect(q.recommended, 3940);
      expect(q.minOffer, 3350);
      expect(q.commission, 394);
      expect(q.driverGets, 3546);
    });

    test('end of trip: 55 km in 4h20m = 3940 + 15 x 60 + 1 x 560 = 5400', () {
      final b = svc.hourlyFinal(miniFare, p4, agreed: 3940, actualKm: 55, actualMinutes: 260);
      expect(b.extraKm, 15);
      expect(b.extraKmCharge, 900);
      expect(b.extraHours, 1);
      expect(b.extraHourCharge, 560);
      expect(b.total, 5400);
    });

    test('inside the package nothing extra is charged; a started extra hour counts in full', () {
      expect(svc.hourlyFinal(miniFare, p4, agreed: 3940, actualKm: 39, actualMinutes: 240).total, 3940);
      expect(svc.hourlyFinal(miniFare, p4, agreed: 3940, actualKm: 10, actualMinutes: 241).extraHours, 1);
      expect(svc.hourlyFinal(miniFare, p4, agreed: 3940, actualKm: 10, actualMinutes: 300).extraHours, 1);
      expect(svc.hourlyFinal(miniFare, p4, agreed: 3940, actualKm: 10, actualMinutes: 301).extraHours, 2);
    });
  });

  group('round trip', () {
    test('Mini: 20 km = 3530, 95 km = 10610', () {
      expect(svc.roundTripBase(miniFare, 20), 3530);
      expect(svc.roundTripBase(miniFare, 95), 10610);
    });

    test('waiting at the destination: 30 minutes free, then per started hour', () {
      expect(svc.roundTripWaitCharge(miniFare, 30), 0);
      expect(svc.roundTripWaitCharge(miniFare, 31), 250);
      expect(svc.roundTripWaitCharge(miniFare, 90), 250);
      expect(svc.roundTripWaitCharge(miniFare, 91), 500);
    });

    test('20 km with 1h30 expected waiting = 3530 + 250 = 3780', () {
      expect(svc.roundTripQuote(miniFare, 20, expectedWaitMinutes: 90).recommended, 3780);
    });

    test('final fare swaps the expected waiting for the real waiting', () {
      expect(svc.roundTripFinal(miniFare, agreed: 3780, expectedWaitMinutes: 90, actualWaitMinutes: 90).total, 3780);
      expect(svc.roundTripFinal(miniFare, agreed: 3780, expectedWaitMinutes: 90, actualWaitMinutes: 120).total, 4030);
      expect(svc.roundTripFinal(miniFare, agreed: 3780, expectedWaitMinutes: 90, actualWaitMinutes: 20).total, 3530);
    });
  });

  test('only cars can be priced hourly or as a round trip', () {
    final c = Catalog(cities: const [], routes: const [], settings: const AppSettings(), categories: testCategories);
    expect(c.quoteBooking('car_mini', BookingType.hourly, package: testPackages[1])!.recommended, 3940);
    expect(c.quoteBooking('bike', BookingType.hourly, package: testPackages[1]), isNull);
    expect(c.quoteBooking('loader', BookingType.roundTrip, distanceKm: 20), isNull);
    expect(c.quoteBooking('car_mini', BookingType.roundTrip, distanceKm: 20)!.recommended, 3530);
    expect(c.quoteBooking('bike', BookingType.oneWay, distanceKm: 5)!.recommended, greaterThan(0));
  });}
