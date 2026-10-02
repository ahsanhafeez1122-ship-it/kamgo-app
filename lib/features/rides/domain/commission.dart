/// Commission split for a completed ride.
///
/// The authoritative calculation lives in `public.complete_ride()` on the
/// server; this mirrors it for display and is covered by unit tests so the
/// two never drift apart.
class CommissionBreakdown {
  const CommissionBreakdown({
    required this.finalFare,
    required this.percent,
    required this.commission,
    required this.driverEarning,
  });

  factory CommissionBreakdown.compute(num finalFare, num percent) {
    if (finalFare < 0) throw ArgumentError.value(finalFare, 'finalFare');
    if (percent < 0 || percent > 100) throw ArgumentError.value(percent, 'percent');
    // Work in paisa to avoid floating point drift; round half up like
    // Postgres `round(numeric, 2)`.
    final farePaisa = (finalFare * 100).round();
    final commissionPaisa = (farePaisa * percent / 100).round();
    return CommissionBreakdown(
      finalFare: farePaisa / 100,
      percent: percent.toDouble(),
      commission: commissionPaisa / 100,
      driverEarning: (farePaisa - commissionPaisa) / 100,
    );
  }

  final double finalFare;
  final double percent;
  final double commission;
  final double driverEarning;
}
