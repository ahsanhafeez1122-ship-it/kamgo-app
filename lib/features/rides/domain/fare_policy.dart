/// Fare guardrails. The server enforces the same rule in
/// `public.fare_bounds()` / `public.assert_fare_allowed()`; this client copy
/// only exists to give instant feedback while typing.
class FarePolicy {
  const FarePolicy({required this.minPerKm, required this.maxPerKm})
      : assert(minPerKm > 0 && maxPerKm >= minPerKm);

  final double minPerKm;
  final double maxPerKm;

  /// Lowest allowed fare for [distanceKm], rounded up to whole rupees.
  int minFare(double distanceKm) => (distanceKm * minPerKm).ceil();

  /// Highest allowed fare for [distanceKm], rounded down to whole rupees.
  int maxFare(double distanceKm) => (distanceKm * maxPerKm).floor();

  /// A friendly starting offer: the midpoint, rounded to the nearest Rs. 50.
  int suggestedFare(double distanceKm) {
    final mid = (minFare(distanceKm) + maxFare(distanceKm)) / 2;
    return ((mid / 50).round() * 50).clamp(minFare(distanceKm), maxFare(distanceKm));
  }

  FareCheck check(num fare, double distanceKm) {
    if (distanceKm <= 0) return FareCheck.invalidRoute;
    if (fare < minFare(distanceKm)) return FareCheck.tooLow;
    if (fare > maxFare(distanceKm)) return FareCheck.tooHigh;
    return FareCheck.ok;
  }
}

enum FareCheck { ok, tooLow, tooHigh, invalidRoute }
