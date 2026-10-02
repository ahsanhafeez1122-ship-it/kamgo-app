// KAM GO admin panel (Flutter Web).
//   flutter run -d chrome -t lib/main_admin.dart --dart-define-from-file=.env
//   flutter build web -t lib/main_admin.dart --dart-define-from-file=.env --output build/admin
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/services/supabase_providers.dart';
import 'features/admin/presentation/admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY')))));
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const KamgoAdminApp(),
  ));
}
