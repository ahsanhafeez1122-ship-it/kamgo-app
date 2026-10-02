/// Build-time configuration, supplied with `--dart-define-from-file=.env`.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The public key from Supabase → Project Settings → API Keys
  /// (`sb_publishable_…`, or the legacy `anon` key). Never the secret /
  /// service-role key.
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
