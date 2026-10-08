import 'dart:math' as math;

/// The ONE fare service. Passenger app, driver app and admin all use this; the server
/// (`fare_calc()` in the database) does the same arithmetic and is the authority.
///
/// Every number comes from [FareSettings] / [FareConfig], which are loaded from the database
/// and edited in the admin panel. Nothing about a price is written in code.
///
///   cost   = cityKm x (petrol / cityMileage + cityMaint)
///          + outKm  x (petrol / highwayMileage + highwayMaint) x (1 + returnFactor)
///   fare   = max((cost + profit) / (1 - commission%), minFare);  night: x (1 + night%)
///   recommended = round10(fare) + loading charge (if chosen) + toll
class FareSettings {
  const FareSettings({
    this.petrolPrice = 400,
    this.commissionPercent = 10,
    this.slabKm = 8,
    this.returnFactor = 0.5,
    this.minOfferPercent = 85,
    this.maxOfferPercent = 200,
    this.nightSurchargePercent = 20,
    this.nightStartHour = 23,
    this.nightEndHour = 6,
    this.waitingFreeMinutes = 5,
    this.roundTripCostFactor = 2,
    this.roundTripProfitFactor = 1.5,
    this.roundTripFreeWaitMinutes = 30,
  });

  final double petrolPrice;
  final double commissionPercent;
  final double slabKm;
  final double returnFactor;
  final double minOfferPercent;
  final double maxOfferPercent;
  final double nightSurchargePercent;
  final int nightStartHour;
  final int nightEndHour;
  final int waitingFreeMinutes;

  /// Round trip: the one-way running cost counts this many times, the profit this many times.
  final double roundTripCostFactor;
  final double roundTripProfitFactor;

  /// Round trip: free waiting at the destination.
  final int roundTripFreeWaitMinutes;
}

/// Per ride type: mileage, maintenance, minimum fare, waiting rate, profit table...
class FareConfig {
  const FareConfig({
    required this.cityMileage,
    required this.highwayMileage,
    required this.cityMaint,
    required this.highwayMaint,
    required this.minFare,
    required this.waitingPerMin,
    required this.profitPoints,
    this.maxKm,
    this.loadingCharge = 0,
    this.roundTripWaitPerHour = 0,
    this.hourProfit = 0,
    this.extraKmRate = 0,
    this.extraHourRate = 0,
  });

  final double cityMileage;
  final double highwayMileage;
  final double cityMaint;
  final double highwayMaint;
  final double minFare;
  final double waitingPerMin;

  /// Longest trip this ride type takes; null = no limit.
  final double? maxKm;
  final double loadingCharge;
  final double roundTripWaitPerHour;

  /// Hourly rental: profit per hour, and the price of each extra km / started extra hour.
  final double hourProfit;
  final double extraKmRate;
  final double extraHourRate;

  /// `[[km, profit], ...]`
  final List<List<double>> profitPoints;
}

enum FareCheck { ok, tooLow, tooHigh, invalidRoute }

/// One way, a car by the hour, or there-and-back with waiting. Only cars take the last two.
enum BookingType {
  oneWay('one_way', 'One Way'),
  hourly('hourly', 'Hourly'),
  roundTrip('round_trip', 'Round Trip');

  const BookingType(this.code, this.label);
  final String code;
  final String label;

  static BookingType fromCode(String? code) =>
      BookingType.values.firstWhere((t) => t.code == code, orElse: () => BookingType.oneWay);
}

/// An hourly package (admin-managed): hours, included km and the profit multiplier.
class HourlyPackage {
  const HourlyPackage({
    required this.id,
    required this.hours,
    required this.includedKm,
    required this.profitMultiplier,
    this.sortOrder = 0,
  });

  factory HourlyPackage.fromJson(Map<String, dynamic> j) => HourlyPackage(
        id: j['id'] as String,
        hours: (j['hours'] as num).toInt(),
        includedKm: (j['included_km'] as num).toDouble(),
        profitMultiplier: (j['profit_multiplier'] as num).toDouble(),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final int hours;
  final double includedKm;
  final double profitMultiplier;
  final int sortOrder;

  String get label => '${hours}h · ${includedKm.round()} km';

  Map<String, dynamic> toJson() => {
        'id': id,
        'hours': hours,
        'included_km': includedKm,
        'profit_multiplier': profitMultiplier,
        'sort_order': sortOrder,
      };
}

/// What a finished trip costs, line by line (the same lines both people see).
class TripBreakdown {
  const TripBreakdown({
    required this.agreed,
    this.pickupWaiting = 0,
    this.extraKm = 0,
    this.extraKmCharge = 0,
    this.extraHours = 0,
    this.extraHourCharge = 0,
    this.destinationWaiting = 0,
    this.expectedWaitingCredit = 0,
  });

  final int agreed;
  final int pickupWaiting;
  final double extraKm;
  final int extraKmCharge;
  final int extraHours;
  final int extraHourCharge;
  final int destinationWaiting;
  final int expectedWaitingCredit;

  int get total =>
      agreed + pickupWaiting + extraKmCharge + extraHourCharge + destinationWaiting - expectedWaitingCredit;
}

/// What a passenger and a driver see for one trip.
class FareQuote {
  const FareQuote({
    required this.recommended,
    required this.minOffer,
    required this.maxOffer,
    required this.commission,
    required this.driverGets,
  });

  final int recommended;
  final int minOffer;
  final int maxOffer;
  final int commission;
  final int driverGets;

  /// Is [fare] inside the allowed offer band?
  FareCheck check(num fare) {
    if (fare < minOffer) return FareCheck.tooLow;
    if (fare > maxOffer) return FareCheck.tooHigh;
    return FareCheck.ok;
  }
}

class FareService {
  const FareService(this.settings);

  final FareSettings settings;

  /// Round half up to the nearest 10 (same as the server: floor(x / 10 + 0.5) x 10).
  static int round10(double v) => (v / 10 + 0.5).floor() * 10;

  /// Linear interpolation of the profit table; past the last point it continues the slope
  /// of the last two points.
  static double profit(List<List<double>> points, double distanceKm) {
    if (points.isEmpty) return 0;
    final p = [...points]..sort((a, b) => a[0].compareTo(b[0]));
    if (p.length == 1) return p.first[1];
    for (var i = 0; i < p.length - 1; i++) {
      final x0 = p[i][0], y0 = p[i][1], x1 = p[i + 1][0], y1 = p[i + 1][1];
      if (distanceKm <= x1 || i == p.length - 2) {
        if (x1 == x0) return y0;
        return y0 + (y1 - y0) * (distanceKm - x0) / (x1 - x0);
      }
    }
    return 0;
  }

  /// Is [at] (Pakistan time, UTC+5) inside the night window?
  bool isNight(DateTime at) {
    final h = at.toUtc().add(const Duration(hours: 5)).hour;
    final s = settings.nightStartHour, e = settings.nightEndHour;
    return s > e ? (h >= s || h < e) : (h >= s && h < e);
  }

  /// The raw one-way fare (before rounding) for [distanceKm].
  double oneWayFare(FareConfig c, double distanceKm, {bool night = false}) {
    final cityKm = math.min(distanceKm, settings.slabKm);
    final outKm = math.max(distanceKm - settings.slabKm, 0);
    final cost = cityKm * (settings.petrolPrice / c.cityMileage + c.cityMaint) +
        outKm * (settings.petrolPrice / c.highwayMileage + c.highwayMaint) * (1 + settings.returnFactor);
    final prof = profit(c.profitPoints, distanceKm);
    var fare = math.max((cost + prof) / (1 - settings.commissionPercent / 100), c.minFare);
    if (night) fare *= 1 + settings.nightSurchargePercent / 100;
    return fare;
  }

  /// Quote for a one-way trip.
  FareQuote quote(FareConfig c, double distanceKm, {bool night = false, bool loading = false, double toll = 0}) {
    final rec = round10(oneWayFare(c, distanceKm, night: night)) + (loading ? c.loadingCharge : 0) + toll;
    return quoteFor(rec);
  }

  /// The offer band, commission and driver share around a recommended fare.
  FareQuote quoteFor(num recommended) {
    final rec = recommended.toDouble();
    final commission = (rec * settings.commissionPercent / 100 + 0.5).floor();
    return FareQuote(
      recommended: rec.round(),
      minOffer: round10(rec * settings.minOfferPercent / 100),
      maxOffer: (rec * settings.maxOfferPercent / 100).floor(),
      commission: commission,
      driverGets: rec.round() - commission,
    );
  }

  /// Commission and driver share of an amount actually agreed (an offer or a final fare).
  ({int commission, int driverGets}) split(num fare) {
    final commission = (fare * settings.commissionPercent / 100 + 0.5).floor();
    return (commission: commission, driverGets: fare.round() - commission);
  }

  /// Waiting at the pickup: free minutes first, then [FareConfig.waitingPerMin] per extra minute.
  int waitingCharge(FareConfig c, int waitedMinutes) =>
      (math.max(0, waitedMinutes - settings.waitingFreeMinutes) * c.waitingPerMin).round();

  // ── Hourly rental ───────────────────────────────────────────────────────────
  /// Petrol and maintenance for one city km.
  double cityCostPerKm(FareConfig c) => settings.petrolPrice / c.cityMileage + c.cityMaint;

  /// round10((included km x city cost per km + hours x hour profit x multiplier) / (1 - commission))
  int hourlyFare(FareConfig c, HourlyPackage p) {
    final raw = (p.includedKm * cityCostPerKm(c) + p.hours * c.hourProfit * p.profitMultiplier) /
        (1 - settings.commissionPercent / 100);
    return round10(raw);
  }

  FareQuote hourlyQuote(FareConfig c, HourlyPackage p) => quoteFor(hourlyFare(c, p));

  /// Package price + extra km x rate + started extra hours x rate (+ waiting at the pickup).
  TripBreakdown hourlyFinal(
    FareConfig c,
    HourlyPackage p, {
    required num agreed,
    required double actualKm,
    required int actualMinutes,
    int pickupWaiting = 0,
  }) {
    final extraKm = math.max(0, actualKm - p.includedKm);
    final extraHours = (math.max(0, actualMinutes - p.hours * 60) / 60).ceil();
    return TripBreakdown(
      agreed: agreed.round(),
      pickupWaiting: pickupWaiting,
      extraKm: double.parse(extraKm.toStringAsFixed(1)),
      extraKmCharge: (extraKm * c.extraKmRate).round(),
      extraHours: extraHours,
      extraHourCharge: (extraHours * c.extraHourRate).round(),
    );
  }

  // ── Round trip ──────────────────────────────────────────────────────────────
  /// Waiting at the destination: free minutes first, then the rate per STARTED hour.
  int roundTripWaitCharge(FareConfig c, int waitedMinutes) =>
      (math.max(0, waitedMinutes - settings.roundTripFreeWaitMinutes) / 60).ceil() * c.roundTripWaitPerHour.round();

  /// round10((2 x one-way cost without the return share + 1.5 x profit(d)) / (1 - commission)) for a one-way distance d.
  int roundTripBase(FareConfig c, double distanceKm) {
    final cityKm = math.min(distanceKm, settings.slabKm);
    final outKm = math.max(distanceKm - settings.slabKm, 0);
    final cost = cityKm * cityCostPerKm(c) + outKm * (settings.petrolPrice / c.highwayMileage + c.highwayMaint);
    final raw = (settings.roundTripCostFactor * cost + settings.roundTripProfitFactor * profit(c.profitPoints, distanceKm)) /
        (1 - settings.commissionPercent / 100);
    return math.max(round10(raw), c.minFare.round());
  }

  /// Round trip quote including the waiting the passenger expects at the destination.
  FareQuote roundTripQuote(FareConfig c, double distanceKm, {int expectedWaitMinutes = 0}) =>
      quoteFor(roundTripBase(c, distanceKm) + roundTripWaitCharge(c, expectedWaitMinutes));

  /// Agreed fare, with the expected waiting swapped for the waiting that really happened.
  TripBreakdown roundTripFinal(
    FareConfig c, {
    required num agreed,
    required int expectedWaitMinutes,
    required int actualWaitMinutes,
    int pickupWaiting = 0,
  }) =>
      TripBreakdown(
        agreed: agreed.round(),
        pickupWaiting: pickupWaiting,
        destinationWaiting: roundTripWaitCharge(c, actualWaitMinutes),
        expectedWaitingCredit: roundTripWaitCharge(c, expectedWaitMinutes),
      );

  /// Is this ride type available for a trip of [distanceKm]?
  static bool availableFor(FareConfig c, double distanceKm) => c.maxKm == null || distanceKm <= c.maxKm!;
}
