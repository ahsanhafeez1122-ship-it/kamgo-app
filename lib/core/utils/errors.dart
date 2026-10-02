import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short message that is safe to show a user.
/// Server functions raise readable messages on purpose, so those pass through.
String friendlyError(Object error) {
  if (error is PostgrestException) {
    final m = error.message;
    if (m.contains('JWT') || error.code == 'PGRST301') return 'Please sign in again.';
    if (error.code == '42501' && m.startsWith('permission denied')) {
      return 'You are not allowed to do that.';
    }
    return m;
  }
  if (error is AuthException) return error.message;
  if (error is StorageException) return error.message;
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup') ||
      s.contains('TimeoutException')) {
    return 'No connection. Check your internet and try again.';
  }
  return 'Something went wrong. Please try again.';
}
