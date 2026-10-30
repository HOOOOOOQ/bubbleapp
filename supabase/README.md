# BubbleApp backend (Supabase)

PostgreSQL is the source of truth. Supabase Auth provides Email OTP sign-in. Row Level Security and
SECURITY DEFINER functions with permission checks enforce every rule; the Flutter client and Edge
Functions are not trusted to decide permissions.

## Layout

| Path | Purpose |
|---|---|
| `config.toml` | Supabase CLI project config (auth OTP, realtime, storage, function JWT settings) |
| `migrations/` | Ordered schema, RLS, RPCs, storage policies. Applied in filename order |
| `functions/` | Edge Functions (Deno/TypeScript). Shared helpers in `functions/_shared/` |
| `tests/` | SQL test suites run against a disposable PostgreSQL database (`scripts/test_db.sh`) |

### Migration map

The migrations keep the timestamped Supabase CLI naming (`YYYYMMDDHHMMSS_name.sql`). Their order is
the same as the numbered plan: 001 core, 002 RBAC, 003 channels, 004 verification, 005 partners,
006 messaging and social, 007 business and platform operations, 008 policies, stats, storage and
realtime, 009 messaging completeness, calls and notifications, 010 owner bootstrap, scheduling and
labels, 011 push delivery. Migrations are not renamed after they are applied anywhere.

Storage buckets (migration 008): `avatars`, `profile-covers`, `business-media` (public read; writes
restricted to the owner's folder or business managers), `chat-media`, `chat-attachments`, `story-media`,
`channel-media`, `wallpapers` (private), and `verification-documents` (private, MIME-restricted,
read only through signed URLs issued by `signed-document-url`).

## Set up a project

1. Create a Supabase project. Note the project ref, URL, anon (publishable) key, and service-role key.
2. Install the CLI (`npm i -g supabase` or the official binary) and log in with `supabase login`.
3. `supabase link --project-ref <ref>`
4. `supabase db push` applies all migrations in order.
5. Auth: in the dashboard, keep Email provider enabled with OTP. Confirm the email template shows
   `{{ .Token }}` (the 6-digit code). Set the site URL and the `bubbleapp://auth-callback` redirect.
6. Set function secrets (values come from your own password manager, never from this repository):
   ```
   supabase secrets set JOB_SECRET=... PUSH_WEBHOOK_SECRET=... \
     FCM_PROJECT_ID=... FCM_CLIENT_EMAIL=... FCM_PRIVATE_KEY="..."
   ```
7. Deploy functions: `supabase functions deploy` (deploys every folder in `functions/`).

## Owner bootstrap (one time, server-side)

The Owner role is never granted by the client, by a migration, or by a function that a user can call
without a secret. The sequence is:

1. The intended owner creates an account through Email OTP and confirms the email address.
2. The operator opens the database as the `postgres` role (Supabase SQL editor, or `psql` with the
   database password). A direct database session has no API claims, so `is_trusted_context()` is true. Confirm this in your project before relying on it. Run:
   ```sql
   select public.issue_owner_bootstrap_token('initial-owner', interval '2 hours');
   ```
   The plaintext token is returned once. Only its SHA-256 hash is stored. Copy it into a password
   manager. It expires after the lifetime given (maximum 7 days).
3. The owner signs in to the app and calls the `bootstrap-owner` function with `{"token": "..."}`
   (`redeem_owner_bootstrap`). The database checks the signed-in account, the email confirmation,
   that no owner exists, that the token is valid, unexpired, and unused. It then grants the role and
   audit-logs the redemption. The token is consumed.
4. After this, the bootstrap path refuses all callers, because an Owner exists. Owners can create
   Super Admins and Admins through `admin-management`.

## Edge Functions

All user-initiated functions forward the caller's JWT to the database, so the database RBAC and RLS
decide. Service-role access is used only by `delete-account`, `scheduled-jobs`, and `push-dispatch`.

| Function | Auth | Purpose |
|---|---|---|
| `bootstrap-owner` | user JWT | Redeems the one-time Owner token |
| `verification-decision` | user JWT | Approve, reject, suspend, revoke, or restore a verification; writes history and audit |
| `partner-decision` | user JWT | Partner application decisions |
| `partner-permission` | user JWT | Grants or revokes one partner permission (independent of admin rights) |
| `partner-announcement` | user JWT | Partner announcements |
| `report-decision` | user JWT | Resolves a moderation report |
| `account-status` | user JWT | Suspends, bans, or restores an account |
| `admin-management` | user JWT | Creates or updates admins and their permissions |
| `platform-settings` | user JWT | Sets platform settings (protected keys need owner.manage) |
| `platform-announcement` | user JWT | Platform-wide announcements, optionally to @BubbleApp |
| `signed-document-url` | user JWT | Five-minute signed URL for a verification document (storage RLS applies) |
| `delete-account` | user JWT + confirmation text | Deletes the caller's account; blocked while the caller is Owner |
| `scheduled-jobs` | `x-job-secret` | Expires unanswered calls, publishes due channel posts, sends due scheduled messages, cleans expired call signals |
| `push-dispatch` | `x-webhook-secret` | FCM HTTP v1 delivery for new notification rows |
| `turn-credentials` | user JWT | Returns STUN/TURN iceServers for WebRTC (reads TURN_* secrets) |

Scheduling `scheduled-jobs`: call it every minute with `x-job-secret`. Options are Supabase Cron
(pg_cron with pg_net) or any external scheduler. Without a scheduler, unanswered calls are not ended
and scheduled messages and official-channel posts are not sent. Set `push-dispatch` as a Database
Webhook on INSERT into `public.notifications`, sending the `x-webhook-secret` header.

## Calls: STUN/TURN and SFU

Calls use WebRTC. The app requests TURN/STUN from `turn-credentials` (user JWT required).

**Required secrets** (set via `supabase secrets set`):

```
supabase secrets set \
  TURN_URL=turns:turn.bubbleapp.example:5349 \
  TURN_USERNAME=bubbleapp \
  TURN_CREDENTIAL=... \
  TURN_TTL_SECONDS=86400 \
  STUN_URLS=stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302
```

- `TURN_URL` or `TURN_URLS` (comma-separated) — one or more `turn:` / `turns:` URLs.
- `TURN_USERNAME` + `TURN_CREDENTIAL` — long-lived TURN credentials (coturn, Cloudflare Calls, Twilio Network Traversal, etc.).
- `TURN_TTL_SECONDS` — TTL advertised to the client (default 86400).
- `STUN_URLS` — optional STUN list (default Google + Twilio).

If no TURN secrets are set, the function returns STUN-only `iceServers` — calls work on open networks but may fail behind symmetric NAT. Production should provision TURN.

**Group calls** are stored as `calls.is_group = true` with `call_participants`. The current delivery is mesh (N peer connections); for >4 participants, set `calls.sfu_room_id` and point the app to an SFU (LiveKit, Janus, mediasoup, Cloudflare Calls SFU). The schema already has `sfu_room_id`/`max_participants`; the client will use SFU when `sfu_room_id` is present.

Calls need push for background/terminated: configure FCM (Firebase project, service account, `google-services.json`/`GoogleService-Info.plist`) and `push-dispatch`. Foreground calls work via Supabase Realtime alone.

See `supabase/migrations/20261030000012_call_engine.sql` (RLS + `start_call`, `send_call_signal`, `expire_stale_calls`, `cleanup_expired_call_signals`, `hide_call_history`, etc.), `supabase/functions/turn-credentials/`, and `supabase/tests/06_calls_webrtc.sql`.

## Testing

```
DATABASE_URL=postgresql://... scripts/test_db.sh
```

Use a disposable database: the script resets the auth, storage, and realtime stand-ins, then applies
every migration in order and runs the suites `01` to `06`. The last run passed all assertions (292 + new suites).
`tests/00_supabase_stub.sql` is a local stand-in for Supabase-managed schemas. It is not deployed.

Edge Function code is type-checked in strict mode against `supabase-js` 2.x, with a shim for Deno
globals. It has not been executed against a Supabase project in this environment.

## Known operational gaps

- No pg_cron or external scheduler is configured in this repository (see above).
- FCM delivery is implemented but not exercised: it needs a Firebase project, a service account, and
  `google-services.json` / `GoogleService-Info.plist` in the app, which are not in the repository.
- STUN/TURN and SFU are infrastructure the operator must provision (see Calls section). Without TURN, calls may fail behind symmetric NAT. Without an SFU, large groups stay mesh (battery/bandwidth heavy).
- The Dart/Flutter client has not been compiled here (see `app/README.md`).
