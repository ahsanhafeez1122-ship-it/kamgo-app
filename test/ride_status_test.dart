import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/features/rides/domain/ride_status.dart';

void main() {
  test('happy path is allowed for the right actors', () {
    const path = [
      (RideStatus.requested, RideStatus.searching, RideActor.system),
      (RideStatus.searching, RideStatus.offerReceived, RideActor.system),
      (RideStatus.offerReceived, RideStatus.driverSelected, RideActor.passenger),
      (RideStatus.driverSelected, RideStatus.confirmed, RideActor.system),
      (RideStatus.confirmed, RideStatus.driverArriving, RideActor.driver),
      (RideStatus.driverArriving, RideStatus.rideStarted, RideActor.driver),
      (RideStatus.rideStarted, RideStatus.completed, RideActor.driver),
    ];
    for (final (from, to, actor) in path) {
      expect(canTransition(from, to, actor), isTrue, reason: '$from → $to by $actor');
    }
  });

  test('only the driver can complete, and only from RIDE_STARTED', () {
    expect(canTransition(RideStatus.rideStarted, RideStatus.completed, RideActor.passenger), isFalse);
    expect(canTransition(RideStatus.confirmed, RideStatus.completed, RideActor.driver), isFalse);
    expect(canTransition(RideStatus.driverArriving, RideStatus.completed, RideActor.driver), isFalse);
  });

  test('only the passenger selects a driver', () {
    expect(canTransition(RideStatus.offerReceived, RideStatus.driverSelected, RideActor.driver), isFalse);
  });

  test('steps cannot be skipped or reversed', () {
    expect(canTransition(RideStatus.requested, RideStatus.confirmed, RideActor.system), isFalse);
    expect(canTransition(RideStatus.rideStarted, RideStatus.confirmed, RideActor.driver), isFalse);
    expect(canTransition(RideStatus.completed, RideStatus.rideStarted, RideActor.driver), isFalse);
  });

  test('a started ride can only be cancelled by an admin', () {
    expect(canTransition(RideStatus.rideStarted, RideStatus.cancelled, RideActor.passenger), isFalse);
    expect(canTransition(RideStatus.rideStarted, RideStatus.cancelled, RideActor.driver), isFalse);
    expect(canTransition(RideStatus.rideStarted, RideStatus.cancelled, RideActor.admin), isTrue);
  });

  test('terminal states have no way out', () {
    for (final s in RideStatus.values.where((s) => s.isTerminal)) {
      expect(rideTransitions[s], isNull, reason: '$s');
    }
  });

  test('codes round-trip with the database enum', () {
    for (final s in RideStatus.values) {
      expect(RideStatus.fromCode(s.code), s);
    }
  });
}
