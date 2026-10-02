/// Ride lifecycle. Mirrors the `ride_status` Postgres enum and the
/// `ride_status_transitions` table, which is what the server actually enforces.
enum RideStatus {
  requested('REQUESTED'),
  searching('SEARCHING'),
  offerReceived('OFFER_RECEIVED'),
  driverSelected('DRIVER_SELECTED'),
  confirmed('CONFIRMED'),
  driverArriving('DRIVER_ARRIVING'),
  rideStarted('RIDE_STARTED'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  noShow('NO_SHOW'),
  expired('EXPIRED');

  const RideStatus(this.code);
  final String code;

  static RideStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => throw ArgumentError(code));

  bool get isTerminal => this == completed || this == cancelled || this == noShow || this == expired;

  /// Request is still collecting offers.
  bool get isOpen => this == requested || this == searching || this == offerReceived;
}

enum RideActor { passenger, driver, system, admin }

/// Allowed transitions and who may trigger each one.
const Map<RideStatus, Map<RideStatus, Set<RideActor>>> rideTransitions = {
  RideStatus.requested: {
    RideStatus.searching: {RideActor.system},
    RideStatus.cancelled: {RideActor.passenger, RideActor.admin},
    RideStatus.expired: {RideActor.system},
  },
  RideStatus.searching: {
    RideStatus.offerReceived: {RideActor.system},
    RideStatus.cancelled: {RideActor.passenger, RideActor.admin},
    RideStatus.expired: {RideActor.system},
  },
  RideStatus.offerReceived: {
    RideStatus.driverSelected: {RideActor.passenger},
    RideStatus.cancelled: {RideActor.passenger, RideActor.admin},
    RideStatus.expired: {RideActor.system},
  },
  RideStatus.driverSelected: {
    RideStatus.confirmed: {RideActor.system},
    RideStatus.cancelled: {RideActor.passenger, RideActor.driver, RideActor.admin},
  },
  RideStatus.confirmed: {
    RideStatus.driverArriving: {RideActor.driver},
    RideStatus.rideStarted: {RideActor.driver},
    RideStatus.cancelled: {RideActor.passenger, RideActor.driver, RideActor.admin},
    RideStatus.noShow: {RideActor.driver, RideActor.passenger},
  },
  RideStatus.driverArriving: {
    RideStatus.rideStarted: {RideActor.driver},
    RideStatus.cancelled: {RideActor.passenger, RideActor.driver, RideActor.admin},
    RideStatus.noShow: {RideActor.driver, RideActor.passenger},
  },
  RideStatus.rideStarted: {
    RideStatus.completed: {RideActor.driver},
    RideStatus.cancelled: {RideActor.admin},
  },
};

bool canTransition(RideStatus from, RideStatus to, RideActor actor) =>
    rideTransitions[from]?[to]?.contains(actor) ?? false;
