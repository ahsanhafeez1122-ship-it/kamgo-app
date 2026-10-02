import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true = some network interface is up. (Reachability of Supabase itself is
/// handled per request; this drives the "Connection lost" banner.)
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield up(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(up).distinct();
});
