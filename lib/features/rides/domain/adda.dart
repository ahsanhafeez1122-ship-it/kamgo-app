/// Live "adda" (travel stand) numbers for one city.
class AddaSummary {
  const AddaSummary({
    required this.cityId,
    required this.cityName,
    required this.onlineDrivers,
    required this.openRequests,
  });

  factory AddaSummary.fromJson(Map<String, dynamic> j) => AddaSummary(
        cityId: j['city_id'] as String,
        cityName: j['city_name'] as String,
        onlineDrivers: (j['online_drivers'] as num).toInt(),
        openRequests: (j['open_requests'] as num).toInt(),
      );

  final String cityId;
  final String cityName;
  final int onlineDrivers;
  final int openRequests;
}

class PopularRoute {
  const PopularRoute({
    required this.routeId,
    required this.originName,
    required this.destinationName,
    required this.approxFare,
  });

  factory PopularRoute.fromJson(Map<String, dynamic> j) => PopularRoute(
        routeId: j['route_id'] as String,
        originName: j['origin_name'] as String,
        destinationName: j['destination_name'] as String,
        approxFare: (j['approx_fare'] as num).toDouble(),
      );

  final String routeId;
  final String originName;
  final String destinationName;
  final double approxFare;
}

abstract interface class AddaRepository {
  Future<List<AddaSummary>> summary();
  Future<PopularRoute?> popularRoute({String? originCityId});
}
