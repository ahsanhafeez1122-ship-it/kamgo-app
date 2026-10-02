import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/l10n/strings.dart';
import 'core/services/push_service.dart';
import 'core/widgets/app_overlays.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/states.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _ConfigMissingApp());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const KamgoApp(),
  ));
}

class KamgoApp extends ConsumerWidget {
  const KamgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register for push once signed in (no-op when Firebase isn't configured).
    ref.listen(authUserIdProvider, (_, next) {
      if (next.valueOrNull != null) ref.read(pushServiceProvider).start();
    });
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      // English by default; Urdu (RTL) from Profile → Language.
      locale: ref.watch(localeProvider),
      builder: (context, child) => AppOverlays(child: child ?? const SizedBox.shrink()),
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

final pushServiceProvider = Provider((ref) => PushService(ref.watch(supabaseClientProvider)));

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: InfoState(
          icon: Icons.settings_rounded,
          title: 'Supabase is not configured',
          message: 'Copy .env.example to .env, fill in SUPABASE_URL and '
              'SUPABASE_PUBLISHABLE_KEY, then run:\n'
              'flutter run --dart-define-from-file=.env',
        ),
      ),
    );
  }
}
