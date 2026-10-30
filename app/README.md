# BubbleApp Flutter client

Flutter (Material 3), Riverpod, and GoRouter, backed by Supabase. The client holds no privileges:
RLS, RBAC, and SECURITY DEFINER RPCs decide everything.

## Status (read first)

- **Not compiled or tested in the build environment that produced this repository.** The Flutter and
  Dart SDKs, Java, and the Android SDK were not available, and pub.dev was unreachable. The code was
  checked only with a Dart parser (all 23 files parse). `flutter pub get`, `flutter analyze`,
  `flutter test`, and `flutter build apk` have **not** been run.
- The dependency list in `pubspec.yaml` is the set the existing code uses. Features that need more
  packages (voice and video calls, FCM client registration, media playback, camera and recording) are
  not implemented, so their packages are not listed.
- Implemented screens (routes in `lib/router/app_router.dart`): sign in (Email OTP), home shell,
  channels list, official @BubbleApp channel, channel detail, create channel, verification home, apply
  for verification, verification queue, partners home, partner apply, partner queue, business home,
  create business, business dashboard, settings, profile edit, owner dashboard, admin console.
- **Not implemented:** the messaging client. There is no chat list or conversation thread screen, and
  no send, edit, delete, reply, forward, reaction, read-receipt, typing, offline-queue, or realtime code
  in the repository. The database side of messaging (migrations 006 and 009) is in place and tested.
  Most of the planned 112-page catalogue is also not built. Screens were not created as empty placeholders.

## Configuration

Values are injected at build time with `--dart-define`. Nothing is hard-coded.

```
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_OR_PUBLISHABLE_KEY
```

If either value is missing, `AppConfig.isConfigured` is false and the app shows a configuration screen
instead of attempting sign-in. Never use the service-role key here.

Auth sessions are kept in `flutter_secure_storage` through `SecureSessionStorage`.

## Tests

Unit tests exist for config, error mapping, and models (`test/`). They have not been executed. The
planned Flutter widget and integration tests (auth, OTP, chat list, reactions, uploads, verification,
subscription, partner dashboard, owner and admin permissions, theme, and navigation) are not written.
Critical database workflows are covered by the SQL suites in `supabase/tests/` (run `scripts/test_db.sh`).

## Verification uploads

Documents go to the private `verification-documents` bucket under `{uid}/{application_id}/`. The app
never receives a public URL. It asks the `signed-document-url` function for a five-minute signed URL.
Decisions go through the `verification-decision` function.
