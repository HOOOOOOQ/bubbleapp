/// Build-time configuration. Values are injected with --dart-define, never hard-coded.
///
/// flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///              --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The anon key is public by design; Row Level Security protects the data.
/// The service_role key must never be placed in this app.
class AppConfig {
  const AppConfig._();

  static const String appName = 'BubbleApp';
  static const String tagline = "More Than Just Chat. It's Your Digital Life.";

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Official channel username; the database guarantees it exists and is mandatory.
  static const String officialChannelUsername = 'bubbleapp';

  /// Storage bucket for verification documents (private; accessed through RLS).
  static const String verificationBucket = 'verification-docs';
}
