import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/commission.dart';

void main() {
  test('Rs. 1,200 at 10% → KAM GO Rs. 120, driver Rs. 1,080', () {
    final b = CommissionBreakdown.compute(1200, 10);
    expect(b.commission, 120);
    expect(b.driverEarning, 1080);
    expect(b.commission + b.driverEarning, b.finalFare);
  });

  test('rounds to paisa, half up, and still sums to the fare', () {
    final b = CommissionBreakdown.compute(1155, 10);
    expect(b.commission, 115.5);
    expect(b.driverEarning, 1039.5);

    final c = CommissionBreakdown.compute(999.99, 12.5);
    expect(c.commission, 125); // 124.99875 → 125.00
    expect(c.commission + c.driverEarning, closeTo(999.99, 1e-9));
  });

  test('zero percent leaves the full fare to the driver', () {
    final b = CommissionBreakdown.compute(800, 0);
    expect(b.commission, 0);
    expect(b.driverEarning, 800);
  });

  test('rejects negative fares and out-of-range percentages', () {
    expect(() => CommissionBreakdown.compute(-1, 10), throwsArgumentError);
    expect(() => CommissionBreakdown.compute(100, -5), throwsArgumentError);
    expect(() => CommissionBreakdown.compute(100, 101), throwsArgumentError);
  });
}
