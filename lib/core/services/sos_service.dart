/// Placeholder for a future SOS feature (alert emergency contact + KAM GO
/// with live location). Kept as an interface so screens can depend on it now.
abstract interface class SosService {
  bool get isAvailable;
  Future<void> trigger({required String rideId});
}

class NoopSosService implements SosService {
  const NoopSosService();

  @override
  bool get isAvailable => false;

  @override
  Future<void> trigger({required String rideId}) async {}
}
