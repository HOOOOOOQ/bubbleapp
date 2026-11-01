# BubbleApp

BubbleApp is a messaging and social platform: personal and business accounts, verified identities, the
official @BubbleApp channel with a mandatory subscription, a partner programme, and role-based
administration. The client is Flutter (Material 3, Riverpod, GoRouter). The backend is Supabase
(PostgreSQL as the source of truth, Email OTP auth, Row Level Security, Edge Functions, storage).

## Current state

Read these before relying on the project:

- **Database:** 16 migrations and the suites in `supabase/tests` (02–09). All suites pass on PostgreSQL 16
  against a fresh database: 509 assertions, 0 failures. It has not been applied to a Supabase project.
- **Edge Functions:** 14 functions. Type-checked in strict mode; not deployed or executed.
- **Flutter app:** Full realtime messaging client — chat list, conversation screen, delivery lifecycle
  (sending→sent→delivered→read→failed), Supabase Realtime, offline queue with dedup, message interactions
  (reply/forward/edit/delete/copy/pin/star/react/report/select), media & files via private buckets with
  signed URLs, chat profile preview with blur, voice notes, global + in-chat search, business messaging
  (labels, quick replies, welcome/away). Part 8 adds the business workspace (team, catalog, inquiry inbox,
  customers, analytics, verification) and the partner workspace (benefits, directory, resources, support,
  application lifecycle). The Flutter SDK is unavailable in this environment, so `dart analyze`,
  `flutter test` and builds were **not** run; see `docs/PART8_BUSINESS_PARTNER.md` for the exact status.
- **Android APK:** not built. Toolchains unavailable, so no APK was produced.

## Repository layout

```
app/                  Flutter client (lib/, test/, pubspec.yaml)
supabase/
  migrations/         Ordered SQL migrations (schema, RLS, RBAC, storage, realtime)
  functions/          Edge Functions (Deno/TypeScript) and _shared helpers
  tests/              SQL test suites
  config.toml         Supabase CLI project configuration
scripts/test_db.sh    Applies migrations to a disposable database and runs the suites
.env.example          Every setting the project needs, with no secret values
```

## Getting started

1. Read `supabase/README.md` to create the project, apply migrations, set function secrets, and
   bootstrap the Owner account.
2. Run the database tests against a disposable local PostgreSQL:
   `DATABASE_URL=postgresql://user:pass@host:5432/db scripts/test_db.sh`
3. Run the app with `--dart-define` values as described in `app/README.md`.

## Security model (summary)

- Owner is provisioned only through a one-time, hashed, expiring token redeemed by a verified account.
- Verification badges change only through the database decision function. Users cannot set them.
- The official channel subscription is mandatory and cannot be removed by ordinary users.
- Partner status does not grant admin rights; partner permissions are set one at a time.
- Verification documents are in a private bucket and are read only through short-lived signed URLs.
- The service-role key is used only in Edge Functions that have no user context.
- Secrets are read from environment variables and are never stored in the repository (`.gitignore`).
