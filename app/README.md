# BubbleApp Flutter client

Flutter (Material 3), Riverpod, and GoRouter, backed by Supabase. The client holds no privileges:
RLS, RBAC, and SECURITY DEFINER RPCs decide everything.

## Status (read first)

- **Not compiled here** (no Flutter/Dart SDK, pub.dev blocked). 38 lib files pass Node parser; 6 test
  files cover messaging, delivery, offline dedup, realtime. `flutter analyze` / `test` / `build` not run
  — storage.googleapis.com is unreachable in this environment.
- All 11 migrations (292 assertions) and 14 Edge Functions from prior phases are preserved untouched.
- Screens (routes in `lib/router/app_router.dart`): sign-in (OTP), home shell with Chats tab, chat list
  (search, unread/pinned/archived/muted, swipe pin/archive, folders), conversation (iOS header, bubbles
  with ticks, date/unread separators, typing, reply/edit/delete/forward/copy/pin/star/react/report,
  multi-select, system), new chat/group, search (users/chats/messages/channels + in-chat), business
  messaging (labels, quick replies, welcome/away), plus prior screens (channels, official, verification,
  partners, business, settings, profile, owner, admin).
- Media & voice: chat-media / chat-attachments buckets with signed URLs, size/MIME guards, progress
  contract; voice recorder (record/pause/resume/cancel/send, waveform, playback).
- Realtime & delivery: postgres_changes filtered by RLS, deduped, reconnection/background/multi-device;
  explicit delivered/read receipts (not inferred from insert); optimistic + idempotent queue via
  flutter_secure_storage (no SQLite primary).

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
