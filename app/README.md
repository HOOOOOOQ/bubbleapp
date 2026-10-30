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
- Voice & Video Calls (Part 5): 1-1 voice/video, group voice/video (SFU-ready, mesh fallback), ringing/connecting/connected/reconnecting/ended, busy/missed/failed/timeout, WebRTC engine (flutter_webrtc) with STUN/TURN, secure signaling via Supabase Realtime + `call_signals` (5-min TTL), call history with hide/clear, chat header integration, incoming/outgoing/active screens, group grid + PIP, call settings, FCM stub, wakelock, background handling.
- Social Ecosystem (Part 6): Stories (24h, text/image/video, captions/background/colors/text/stickers/links, viewer progress, privacy Everyone/Followers/Contacts/CloseFriends/Custom+Hide,Insights, backend can_view_story), Channels (public/private/official/verified/business, category/rules, Owner/Admin/Editor/Moderator/Member, feed text/image/video/polls/link previews/reactions/views/share/search/pin/edit/delete/scheduled, analytics), Communities (multiple groups, username/category/rules, public/private, approval, Owner/Admin/Moderator/GroupManager/Member, join requests, member directory, announcements, search, block/report, activity feed), Groups (group profile, member/admin management, invites/join links, approval, announcements, pinned, permissions send/media/add/change/pin/polls/calls/invites enforced by RLS, mentions, media gallery, group calls), Social Feed (home/following/discover/trending/profile, text/image/images/video/poll/link/share, like/reactions/comment/reply/mention/share/bookmark/report/edit/delete/pin), Comments (nested depth 5, like/react/edit/delete/mention/report), Polls (single/multiple, expiration, anonymous, change allowed, duplicate prevented by PK+trigger), Discovery (users/channels/communities/groups/posts/hashtags/topics, recent/suggestions/filters, trending from real engagement), Hashtags/Mentions (extraction/indexing/discovery/trending, mention notifications), Media (private signed URLs, community-media/post-media buckets, MIME/size validation, progress, orphan cleanup), Notifications (story/channel/community/group/mentions/comments/poll integrated, prefs), Moderation (reports spam/harassment/etc, review/notes/remove/warn/suspend/escalate, audit, Owner protected).

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

Unit tests (12 files): config, error mapping, messaging, offline queue, realtime, call models/state, social stories/communities/posts/polls/feed, discovery — cover creation, expiration, privacy, subscriptions, membership, roles, comment ownership, poll duplicate prevention, search visibility, blocked restrictions, storage access. Not executed here: `flutter test` requires Dart SDK (storage.googleapis.com blocked). Node parser checked 70 Dart files for brace balance. Supabase SQL suites 01-07 (332 assertions including 07_social_ecosystem) require disposable PostgreSQL (`scripts/test_db.sh` with DATABASE_URL) — not executed here (no psql).

## Verification uploads

Documents go to the private `verification-documents` bucket under `{uid}/{application_id}/`. The app
never receives a public URL. It asks the `signed-document-url` function for a five-minute signed URL.
Decisions go through the `verification-decision` function.
