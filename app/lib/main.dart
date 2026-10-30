import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'core/secure_session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(),
    ),
  );

  runApp(const ProviderScope(child: BubbleApp()));
}

/// Shown when the build was started without --dart-define values. Explains the fix
/// instead of silently running against a fake backend.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'BubbleApp is not configured.\n\n'
                'Start the app with:\n'
                'flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co '
                '--dart-define=SUPABASE_ANON_KEY=<anon key>\n\n'
                'Use the project anon key only. Never embed the service_role key.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
