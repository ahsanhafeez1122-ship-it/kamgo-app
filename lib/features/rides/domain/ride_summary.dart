import 'ride_status.dart';

/// A row in the passenger's "My Rides" history.
class RideSummary {
  const RideSummary({
    required this.id,
    required this.originName,
    required this.destinationName,
    required this.fare,
    required this.status,
    required this.createdAt,
  });

  factory RideSummary.fromJson(Map<String, dynamic> j) => RideSummary(
        id: j['id'] as String,
        originName: (j['origin'] as Map?)?['name'] as String? ?? '?',
        destinationName: (j['destination'] as Map?)?['name'] as String? ?? '?',
        fare: (j['final_fare'] as num).toDouble(),
        status: RideStatus.fromCode(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  final String id;
  final String originName;
  final String destinationName;
  final double fare;
  final RideStatus status;
  final DateTime createdAt;
}

abstract interface class RideHistoryRepository {
  Future<List<RideSummary>> myRides({int page = 0, int pageSize = 20});

  /// City ids the passenger most recently travelled to, newest first.
  Future<List<String>> recentDestinationIds({int limit = 6});
}
