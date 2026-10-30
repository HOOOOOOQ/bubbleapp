# BubbleApp Flutter client

Flutter (Material 3), Riverpod, and GoRouter, backed by Supabase. The client holds no privileges:
RLS, RBAC, and SECURITY DEFINER RPCs decide everything.

## Status (read first)

- **Not compiled or run in this environment** (no Flutter/Dart SDK, no Android toolchain, pub.dev blocked).
  Lib files (38) pass a Node-based parser check; tests (6 files) cover messaging models, delivery lifecycle,
  offline queue dedup, attachments, and realtime contracts. `flutter analyze` / `flutter test` / `flutter build`
  have not been executed — the environment cannot fetch the SDK from storage.googleapis.com.
- All database work (11 migrations, 292 assertions) and Edge Functions (14) from prior phases are preserved.
- Implemented screens (routes in `lib/router/app_router.dart`): sign in (Email OTP), home shell with Chats tab,
  chat list (search, filters, unread, pinned, archived, muted, folders, swipe actions), conversation screen
  (iOS header, bubbles with ticks, date/unread separators, typing, reply/edit/delete/forward/copy/pin/star/react/report, multi-select, system messages),
  new chat & new group, search (users, conversations, messages, channels, in-chat), business messaging (labels, quick replies, notes),
  plus all prior screens: channels list, official channel, channel detail, create channel, verification, partners, business, settings, profile, owner, admin.
- Media & voice: image/video/document/location/contact sharing via private `chat-media` / `chat-attachments` buckets with signed URLs,
  size/MIME validation, upload progress contract; voice recorder (record/pause/resume/cancel/send, waveform, playback speed, duration).
- Realtime & delivery: Supabase Realtime subscriptions filtered by RLS, deduped by message id, with reconnection / backgrounding / multi-device handling;
  explicit delivery receipts (delivered → read) separate from insert success; optimistic updates with idempotency keys; offline queue persisted to secure storage.

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
