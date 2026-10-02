import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Firebase Cloud Messaging, entirely optional: if the FIREBASE_* values are
/// not supplied at build time the app runs without push and relies on the
/// in-app (Realtime) notifications instead.
///
/// Configured from --dart-define(-from-file) rather than google-services.json
/// so the Android build never depends on a Firebase file being present.
class PushService {
  PushService(this._client);

  final SupabaseClient _client;
  final _local = FlutterLocalNotificationsPlugin();
  bool _started = false;

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get isConfigured =>
      !kIsWeb && _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty;

  static const _channel = AndroidNotificationChannel(
    'kamgo_rides',
    'Rides',
    description: 'Ride requests, offers and trip updates',
    importance: Importance.high,
  );

  /// Call after sign-in. Safe to call more than once.
  Future<void> start() async {
    if (!isConfigured || _started) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
          ),
        );
      }
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission();
      final token = await fcm.getToken();
      if (token != null) await _register(token);
      fcm.onTokenRefresh.listen(_register);

      // FCM shows notifications itself in the background; in the foreground
      // we show a lightweight local one.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _local.show(
          id: m.hashCode,
          title: n.title,
          body: n.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      });
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _client.rpc('register_device_token', params: {'p_token': token, 'p_platform': 'android'});
    } catch (_) {
      // Retried on next start / token refresh.
    }
  }
}
