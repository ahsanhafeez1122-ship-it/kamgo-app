/// Phone-OTP authentication contract.
///
/// The UI only talks to this interface, so the Supabase SMS flow can later be
/// replaced by a local SMS / WhatsApp OTP provider without touching screens.
abstract interface class AuthService {
  /// Emits the signed-in user id, or null when signed out.
  Stream<String?> userIdChanges();

  String? get currentUserId;

  /// [phoneE164] like `+923001234567`.
  Future<void> sendOtp(String phoneE164);

  Future<void> verifyOtp({required String phoneE164, required String code});

  Future<void> signOut();
}

/// User-facing auth failure with a message safe to show on screen.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
