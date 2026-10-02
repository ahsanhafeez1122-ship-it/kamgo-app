// Verifies that Supabase Realtime delivers the events the app relies on,
// with RLS applied, against the LOCAL stack:
//   dart run tools/realtime_check.dart <publishable-key>
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';
import 'dart:io';

import 'package:supabase/supabase.dart';

const url = 'http://127.0.0.1:54321';

Future<SupabaseClient> signIn(String key, String phone) async {
  final c = SupabaseClient(url, key);
  await c.auth.signInWithOtp(phone: phone);
  await c.auth.verifyOTP(phone: phone, token: '123456', type: OtpType.sms);
  return c;
}

Future<bool> waitFor(Completer<void> c, String label) async {
  try {
    await c.future.timeout(const Duration(seconds: 10));
    print('  ✅ $label');
    return true;
  } on TimeoutException {
    print('  ❌ $label (no event in 10 s)');
    return false;
  }
}

Future<void> subscribed(RealtimeChannel ch) {
  final done = Completer<void>();
  ch.subscribe((status, _) {
    if (status == RealtimeSubscribeStatus.subscribed && !done.isCompleted) done.complete();
  });
  // "SUBSCRIBED" arrives slightly before the Postgres listener is live;
  // give it a moment so the very next event isn't missed.
  return done.future
      .timeout(const Duration(seconds: 10))
      .then((_) => Future<void>.delayed(const Duration(seconds: 2)));
}

Future<void> main(List<String> args) async {
  final key = args.first;
  final passenger = await signIn(key, '+923000000002');
  final driverA = await signIn(key, '+923000000011');
  final driverB = await signIn(key, '+923000000012');
  final offline = await signIn(key, '+923000000014');
  var ok = true;

  // Driver A listens to requests in Pir Mahal (as the dashboard does).
  final pirMahal = '11111111-1111-4111-8111-000000000002';
  final aSawRequest = Completer<void>();
  final dSawRequest = Completer<void>();
  await subscribed(driverA.channel('feed-a').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'ride_requests',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'origin_city_id', value: pirMahal),
      callback: (_) => aSawRequest.isCompleted ? null : aSawRequest.complete()));
  await subscribed(offline.channel('feed-d').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'ride_requests',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'origin_city_id', value: pirMahal),
      callback: (_) => dSawRequest.isCompleted ? null : dSawRequest.complete()));

  print('Passenger creates a request…');
  final req = await passenger.rpc('create_ride_request', params: {
    'p_route_id': '22222222-2222-4222-8222-000000000003', 'p_passenger_count': 2, 'p_offered_fare': 1100,
  }) as Map<String, dynamic>;
  final requestId = req['id'] as String;
  ok &= await waitFor(aSawRequest, 'online driver A receives the new request live');
  await Future<void>.delayed(const Duration(seconds: 2));
  if (dSawRequest.isCompleted) {
    print('  ❌ offline driver D received it');
    ok = false;
  } else {
    print('  ✅ offline driver D did not receive it');
  }

  // Passenger listens for offers on the request (Finding / Offers screens).
  final gotOffer = Completer<void>();
  await subscribed(passenger.channel('offers').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'ride_offers',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'request_id', value: requestId),
      callback: (_) => gotOffer.isCompleted ? null : gotOffer.complete()));
  // Passenger listens for their own notifications (slide-down banner).
  final gotAlert = Completer<void>();
  final passengerId = passenger.auth.currentUser!.id;
  await subscribed(passenger.channel('alerts').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'notifications',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: passengerId),
      callback: (_) => gotAlert.isCompleted ? null : gotAlert.complete()));
  // Driver B listens for a ride row for them (auto-open on selection).
  final bId = driverB.auth.currentUser!.id;
  final bGotRide = Completer<void>();
  await subscribed(driverB.channel('rides-b').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'rides',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'driver_id', value: bId),
      callback: (_) => bGotRide.isCompleted ? null : bGotRide.complete()));

  print('Driver B counters 1,200…');
  final offer = await driverB.rpc('submit_offer', params: {
    'p_request_id': requestId, 'p_offer_type': 'COUNTER', 'p_fare': 1200,
  }) as Map<String, dynamic>;
  ok &= await waitFor(gotOffer, 'passenger receives the offer live');
  ok &= await waitFor(gotAlert, 'passenger receives the in-app notification live');

  // Passenger then watches the ride row + locations (ride screen).
  print('Passenger selects B…');
  final ride = await passenger.rpc('select_offer', params: {'p_offer_id': offer['id']}) as Map<String, dynamic>;
  ok &= await waitFor(bGotRide, 'driver B is told live that they were selected');

  final rideId = ride['id'] as String;
  final statusChange = Completer<void>();
  final location = Completer<void>();
  await subscribed(passenger.channel('ride').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'rides',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: rideId),
      callback: (_) => statusChange.isCompleted ? null : statusChange.complete()));
  await subscribed(passenger.channel('ride-loc').onPostgresChanges(
      event: PostgresChangeEvent.insert, schema: 'public', table: 'ride_locations',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'ride_id', value: rideId),
      callback: (_) => location.isCompleted ? null : location.complete()));

  await driverB.rpc('update_ride_status', params: {'p_ride_id': rideId, 'p_new_status': 'RIDE_STARTED'});
  ok &= await waitFor(statusChange, 'passenger sees "ride started" live');
  await driverB.from('ride_locations').insert({'ride_id': rideId, 'driver_id': bId, 'lat': 30.75, 'lng': 72.38});
  ok &= await waitFor(location, 'passenger receives driver GPS live');

  try {
    await driverA.from('ride_locations').insert({
      'ride_id': rideId, 'driver_id': driverA.auth.currentUser!.id, 'lat': 1, 'lng': 1,
    });
    print('  ❌ another driver could post a location for this ride');
    ok = false;
  } on PostgrestException {
    print('  ✅ another driver cannot post locations for this ride');
  }

  for (final c in [passenger, driverA, driverB, offline]) {
    await c.removeAllChannels();
    await c.dispose();
  }
  print(ok ? '\nRealtime check passed' : '\nRealtime check FAILED');
  exit(ok ? 0 : 1);
}
