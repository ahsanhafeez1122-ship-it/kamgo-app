import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_service.dart';

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  Stream<String?> userIdChanges() =>
      _client.auth.onAuthStateChange.map((s) => s.session?.user.id);

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> sendOtp(String phoneE164) async {
    try {
      await _client.auth.signInWithOtp(phone: phoneE164);
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> verifyOtp({required String phoneE164, required String code}) async {
    try {
      await _client.auth.verifyOTP(phone: phoneE164, token: code, type: OtpType.sms);
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) {
      return 'That code is not correct or has expired. Please try again.';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (m.contains('sms') || m.contains('provider')) {
      return 'We could not send the SMS right now. Please try again shortly.';
    }
    return e.message;
  }
}
