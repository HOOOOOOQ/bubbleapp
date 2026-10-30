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
labels, 011 push delivery, 012 call engine, 013 social ecosystem. Migrations are not renamed after they are applied anywhere.

Storage buckets (migrations 008/013): `avatars`, `profile-covers`, `business-media` (public read; writes
restricted to the owner's folder or business managers), `chat-media`, `chat-attachments`, `story-media`,
`channel-media`, `community-media`, `post-media`, `wallpapers` (private), and `verification-documents` (private, MIME-restricted,
read only through signed URLs issued by `signed-document-url`). RLS via `storage.objects` policies enforces folder-based access and `can_view_story`/`is_community_member` checks for private media.

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
| `scheduled-jobs` | `x-job-secret` | Expires unanswered calls, publishes due channel posts, sends due scheduled messages, cleans expired call signals and expired stories (24h) |
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

## Social ecosystem (Part 6)

Migration `20261030000013_social_ecosystem.sql` adds:

- **Followers/Close Friends**: `follows`, `close_friends` + `is_follower`/`is_close_friend` helpers; used for story privacy `followers`/`close_friends`/`custom`.
- **Stories**: columns `caption/background_color/text_color/text_elements/stickers/link_url/music_url/poll_id/view_count/is_highlight` + `story_audience`/`story_hidden_from`/`story_mutes`; `can_view_story` now enforces all privacy modes + `is_blocked_between` + `story_hidden_from`; RLS on `stories/story_views/story_reactions/story_replies`; `cleanup_expired_stories()` (24h, keeps highlights); private `story-media` URLs require `can_view_story`.
- **Channels**: `category/rules/allow_comments` + `channel_members` (owner/admin/editor/moderator/member) + `can_publish_channel` rank; `channel_posts` enriched with `poll_id/link_preview/is_scheduled/scheduled_for/edited_at`.
- **Communities**: `username/slug/category/rules/join_approval/allow_invites/member_count` + `community_join_requests`/`community_groups` (multiple discussion spaces); role `moderator/group_manager` added.
- **Groups**: `group_settings` (permissions for send/media/add/change/pin/polls/calls/invites + `require_approval` + `invite_link`) + `group_invites`; member roles owner/admin/moderator/member.
- **Posts/Feed**: `posts` (text/image/images/video/poll/link/share, visibility public/followers/contacts/private, media_paths, link_preview, poll/shared ids), `post_reactions/bookmarks/views`, `comments` (nested depth 0-5, `hashtag`/`mention` extraction), `comment_reactions`; RLS respects `is_blocked_between` + visibility.
- **Polls**: `polls/poll_options/poll_votes` + `guard_poll_vote` trigger (expiry, single/multiple, option belongs) + `cast_poll_vote` (vote change if allowed, duplicate prevented by PK).
- **Hashtags/Mentions**: `hashtags/post_hashtags/mentions` + `extract_hashtags`, `trending_hashtags/posts`, `search_all` (respects privacy/blocking), `recent_searches` + `record_search`.
- **Discovery**: `search_all` returns users/channels/communities/posts via `lower(... ) like` with privacy checks; trending from real `post_count`/`reaction_count`.
- **Reports**: expanded `target_type` to user/message/channel/channel_post/story/community/group/post/comment/poll/business + `category` column; `reports_insert/select` RLS.
- **Storage**: new buckets `community-media`, `post-media` with private policies re-created to include them; `chat-media/channel-media/story-media` policies preserved.
- **Notifications**: triggers `on_post_notify/on_comment_notify/on_mention_notify/on_community_join_request_notify` via `notify_user` (respects user_settings.notifications jsonb with new keys posts/comments/mentions/communities).
- **Realtime**: publication adds stories, story_views/reactions, posts, post_reactions, comments, polls/votes, communities/members.

All privileged actions use `SECURITY DEFINER` + permission checks (e.g., `community_members` prevents owner removal by admins via rank check, `channel_members` rank, `group_settings` only owner/admin). No fake followers/engagement — trending uses real counts.

## Testing

```
DATABASE_URL=postgresql://... scripts/test_db.sh
```

Use a disposable database: the script resets the auth, storage, and realtime stand-ins, then applies
every migration in order and runs the suites `01` to `07`. The last run passed all assertions (292 + 40 from 06_calls_webrtc + 45 from 07_social_ecosystem).
`tests/00_supabase_stub.sql` is a local stand-in for Supabase-managed schemas. It is not deployed.

Edge Function code is type-checked in strict mode against `supabase-js` 2.x, with a shim for Deno
globals. It has not been executed against a Supabase project in this environment. `scheduled-jobs` now also calls `cleanup_expired_stories()` for 24h story expiration.

## Known operational gaps

- No pg_cron or external scheduler is configured in this repository (see above).
- FCM delivery is implemented but not exercised: it needs a Firebase project, a service account, and
  `google-services.json` / `GoogleService-Info.plist` in the app, which are not in the repository.
- STUN/TURN and SFU are infrastructure the operator must provision (see Calls section). Without TURN, calls may fail behind symmetric NAT. Without an SFU, large groups stay mesh (battery/bandwidth heavy).
- The Dart/Flutter client has not been compiled here (see `app/README.md`).
