import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ride_models.dart';
import 'ride_flow_providers.dart';

class LiveRequest {
  const LiveRequest({required this.request, required this.offers});
  final RideRequest request;
  final List<DriverOffer> offers;

  List<DriverOffer> get liveOffers => offers.where((o) => o.isLive).toList();
}

/// A request plus its offers, kept fresh by Realtime with a slow polling
/// fallback for weak networks. The server is always the source of truth.
final liveRequestProvider =
    AsyncNotifierProvider.autoDispose.family<LiveRequestNotifier, LiveRequest, String>(LiveRequestNotifier.new);

class LiveRequestNotifier extends AutoDisposeFamilyAsyncNotifier<LiveRequest, String> {
  @override
  Future<LiveRequest> build(String requestId) async {
    final repo = ref.watch(rideRepositoryProvider);
    final subs = <StreamSubscription<void>>[
      repo.offerChanges(requestId).listen((_) => refresh()),
      repo.requestChanges(requestId).listen((_) => refresh()),
    ];
    final poll = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    ref.onDispose(() {
      poll.cancel();
      for (final s in subs) {
        s.cancel();
      }
    });
    return _fetch(requestId);
  }

  Future<LiveRequest> _fetch(String requestId) async {
    final repo = ref.read(rideRepositoryProvider);
    final results = await Future.wait([repo.request(requestId), repo.offers(requestId)]);
    final request = results[0] as RideRequest?;
    if (request == null) throw StateError('Request not found');
    return LiveRequest(request: request, offers: results[1] as List<DriverOffer>);
  }

  bool _busy = false;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final next = await _fetch(arg);
      state = AsyncData(next);
    } catch (_) {
      // Keep showing the last good data; the banner tells the user if offline.
    } finally {
      _busy = false;
    }
  }
}

/// A ride's details, refreshed on status changes and new driver locations.
final liveRideProvider =
    AsyncNotifierProvider.autoDispose.family<LiveRideNotifier, RideDetails, String>(LiveRideNotifier.new);

class LiveRideNotifier extends AutoDisposeFamilyAsyncNotifier<RideDetails, String> {
  @override
  Future<RideDetails> build(String rideId) async {
    final repo = ref.watch(rideRepositoryProvider);
    final sub = repo.rideChanges(rideId).listen((_) => refresh());
    final poll = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    ref.onDispose(() {
      poll.cancel();
      sub.cancel();
    });
    return repo.ride(rideId);
  }

  bool _busy = false;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      state = AsyncData(await ref.read(rideRepositoryProvider).ride(arg));
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
