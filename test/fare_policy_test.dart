import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/fare_policy.dart';

void main() {
  // Seeded defaults: Rs. 20–100 per km. Pir Mahal → Rajana is 22 km.
  const policy = FarePolicy(minPerKm: 20, maxPerKm: 100);
  const pirMahalToRajana = 22.0;

  test('bounds come from per-km guardrails', () {
    expect(policy.minFare(pirMahalToRajana), 440);
    expect(policy.maxFare(pirMahalToRajana), 2200);
  });

  test('acceptance fares are allowed', () {
    for (final fare in [1100, 1200, 1300]) {
      expect(policy.check(fare, pirMahalToRajana), FareCheck.ok, reason: 'Rs. $fare');
    }
  });

  test('Rs. 10 is rejected as too low', () {
    expect(policy.check(10, pirMahalToRajana), FareCheck.tooLow);
  });

  test('Rs. 50,000 is rejected as too high', () {
    expect(policy.check(50000, pirMahalToRajana), FareCheck.tooHigh);
  });

  test('edges are inclusive', () {
    expect(policy.check(440, pirMahalToRajana), FareCheck.ok);
    expect(policy.check(439, pirMahalToRajana), FareCheck.tooLow);
    expect(policy.check(2200, pirMahalToRajana), FareCheck.ok);
    expect(policy.check(2201, pirMahalToRajana), FareCheck.tooHigh);
  });

  test('non-positive distance is an invalid route', () {
    expect(policy.check(500, 0), FareCheck.invalidRoute);
  });

  test('suggested fare is within bounds and a multiple of 50', () {
    for (final km in [5.0, 22.0, 25.0, 45.0, 120.5]) {
      final s = policy.suggestedFare(km);
      expect(policy.check(s, km), FareCheck.ok, reason: '$km km → $s');
      expect(s % 50, 0, reason: '$km km → $s');
    }
  });
}
