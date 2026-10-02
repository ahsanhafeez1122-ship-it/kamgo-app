import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/driver/domain/driver_models.dart';
import 'package:kamgo_app/features/profile/domain/profile.dart';
import 'package:kamgo_app/features/rides/domain/ride_models.dart';
import 'package:kamgo_app/features/rides/domain/ride_status.dart';

void main() {
  test('DriverOffer parses an RPC row', () {
    final o = DriverOffer.fromJson({
      'offer_id': 'o1', 'driver_id': 'd1', 'driver_name': 'Bilal Hussain', 'rating': 4.9,
      'vehicle': 'Toyota Corolla', 'vehicle_type': 'CAR', 'plate': 'TTA-1202', 'offer_type': 'COUNTER',
      'fare': 1200.0, 'status': 'PENDING', 'eta_min': 5, 'distance_km': 1.4,
      'expires_at': DateTime.now().add(const Duration(minutes: 2)).toUtc().toIso8601String(),
    });
    expect(o.type, OfferType.counter);
    expect(o.fare, 1200);
    expect(o.isLive, isTrue);
  });

  test('expired offers are not live', () {
    final o = DriverOffer.fromJson({
      'offer_id': 'o1', 'driver_id': 'd1', 'offer_type': 'ACCEPT', 'fare': 1100, 'status': 'PENDING',
      'expires_at': DateTime.now().subtract(const Duration(seconds: 1)).toUtc().toIso8601String(),
    });
    expect(o.isLive, isFalse);
  });

  test('RideDetails parses get_ride_details output', () {
    final r = RideDetails.fromJson({
      'id': 'r1', 'status': 'RIDE_STARTED', 'final_fare': 1200, 'passenger_count': 2,
      'distance_km': 22, 'est_duration_min': 30, 'started_at': '2026-10-02T10:00:00Z',
      'origin': {'id': 'p', 'name': 'Pir Mahal', 'lat': 30.76, 'lng': 72.43, 'label': 'Bus Adda'},
      'destination': {'id': 'r', 'name': 'Rajana', 'lat': 30.73, 'lng': 72.30},
      'stops': [],
      'driver': {'id': 'd', 'name': 'Bilal', 'rating': 4.9, 'phone': '+923000000012',
        'vehicle': {'make': 'Toyota', 'model': 'Corolla', 'plate': 'TTA-1202'}},
      'passenger': {'id': 'p1', 'name': 'Ali', 'rating': 5},
      'commission': {'amount': 120, 'driver_earning': 1080, 'percent': 10},
    });
    expect(r.status, RideStatus.rideStarted);
    expect(r.isActive, isTrue);
    expect(r.routeName, 'Pir Mahal → Rajana');
    expect(r.origin.display, 'Bus Adda, Pir Mahal');
    expect(r.vehicle.title, 'Toyota Corolla');
    expect(r.commission, 120);
    expect(r.driverEarning, 1080);
  });

  test('DriverDashboard parses get_driver_dashboard output', () {
    final d = DriverDashboard.fromJson({
      'status': 'APPROVED', 'is_online': true, 'city_id': 'c', 'city_name': 'Rajana', 'rating': 4.9,
      'rating_count': 3, 'total_rides': 7, 'cnic': '33100-0000012-1',
      'vehicle': {'type': 'CAR', 'make': 'Toyota', 'model': 'Corolla', 'plate': 'TTA-1202', 'seats': 4},
      'route_ids': ['r1'], 'documents': [{'type': 'CNIC_FRONT', 'status': 'APPROVED'}],
      'earnings': {'today': 1080, 'week': 2000, 'month': 5000, 'rides_today': 1, 'commission_due': 120},
      'adda': {'online_drivers': 3, 'open_requests': 1}, 'recent_ratings': [{'stars': 5, 'comment': 'Great'}],
    });
    expect(d.status, DriverStatus.approved);
    expect(d.earnings.commissionDue, 120);
    expect(d.addaOnline, 3);
    expect(d.documentTypes, {'CNIC_FRONT'});
    expect(d.hasApplication, isTrue);
  });
}
