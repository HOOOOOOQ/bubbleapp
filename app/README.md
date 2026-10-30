# BubbleApp client (Flutter)

Material 3 · Riverpod 2 · GoRouter 14 · supabase_flutter 2.x

> **Status: uncompiled.** The sandbox used to write this code could not download the Flutter or
> Dart SDK or reach pub.dev, so these sources have **not been compiled, analysed or run**.
> Expect to fix a small number of compile/analyzer errors on first build. Run the steps below first.

## 1. Prerequisites

- Flutter **3.27 or newer** (the theme uses `CardThemeData` and `Color.withValues`).
- A Supabase project with migrations `supabase/migrations/20261030000001…08` applied in order.

## 2. Create the platform folders (once)

This repository contains only `lib/`, `test/` and `pubspec.yaml`. Generate the native folders:

```bash
cd app
flutter create . --platforms=android,ios,web --project-name bubbleapp --org app.bubble
flutter pub get
```

`flutter create .` keeps existing files; if it asks to overwrite `pubspec.yaml`, keep yours.

## 3. Configure Supabase (no secrets in code)

Pass the **project URL** and **anon key** at build/run time. Never embed the `service_role` key.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public-key>
```

Without both values the app shows a configuration screen instead of running against a fake backend.

In the Supabase dashboard:

- **Authentication → Providers → Email**: enable email; enable OTP sign-in.
- **Authentication → Email templates → Magic Link / OTP**: include `{{ .Token }}` so users receive a
  6-digit code (the app verifies a code, not a link).
- Leave public sign-ups on, or restrict them as you prefer; accounts are created on first OTP sign-in.

## 4. Create the Owner (trusted server-side only)

The client cannot create or transfer ownership. After the future Owner signs in once with email OTP,
run this **in a trusted server context** (SQL editor with the service role, or a server job):

```sql
select public.bootstrap_owner('owner@example.com');
```

It succeeds once; a second call is refused. Admins are then created with `admin_create_admin` by the Owner.

## 5. Run the tests

```bash
flutter test
```

The unit tests cover model parsing (including that `email` is never read), permission gating data,
error message mapping, and configuration defaults. Database behaviour is covered by the SQL suite
in `../scripts/test_db.sh`.

## 6. Feature map and what is **not** built yet

Built (routed, wired to the backend):

| Area | Screens |
| --- | --- |
| Auth | Email OTP sign-in (`features/auth`) |
| Home hub | Profile card, username prompt, official channel card, mandatory subscription sync, staff shortcuts (`features/home`) |
| Channels | Browse, join/leave, invite codes, create, delete, official channel page, posts, pin, view counts, channel stats (`features/channels`) |
| Verification | Apply (user, organization, business, channel), track status, upload private documents, staff queue with permission- and status-gated actions (`features/verification`) |
| Partners | Apply, status dashboard, announcements, staff queue (`features/partners`) |
| Business | Create, dashboard, account-mode switch, apply for verification (`features/business`) |
| Settings | Edit profile, notifications, sign out (`features/settings`) |
| Owner | Platform metrics, owner and admin audit logs (`features/owner`) |
| Admin console | Users (search, suspend/ban/restore), reports (dismiss, warn, hide, suspend, escalate), platform announcements, audit log (`features/admin`) |

Not built (the originally planned ~112 pages are **not** delivered):

- Direct and group **messaging UI** (the database tables and functions exist; the chat screens do not).
- Stories, communities, contacts, blocking UI, and comments on channel posts.
- Business catalog, quick replies and operator management screens.
- Premium purchase/entitlement screens (the `premium_subscriptions` table exists; there is no billing).
- Admin management UI (promote/demote admins, per-admin permission grants), role grant UI, platform
  settings editor, partner-resources page.
- Theme and privacy switches in Settings (the `user_settings` table supports them).
- Chat media and avatar upload UI (storage buckets and policies exist).

Known limitations:

- Verification documents accept **JPEG and PNG images** picked from the gallery (no PDF picker yet).
- `last_seen_at` is readable by any signed-in user and does not yet respect the privacy setting.
- The partner announcement permission is taken from the database function; check it matches your intent.
