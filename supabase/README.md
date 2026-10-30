# BubbleApp database (Supabase PostgreSQL)

PostgreSQL in Supabase is the source of truth. Apply the migrations in order:

1. `migrations/20261030000001_core.sql` – profiles, businesses, settings, platform settings, base RLS
2. `migrations/20261030000002_rbac.sql` – roles, permissions, admin assignments, audit logs, admin functions
3. `migrations/20261030000003_channels.sql` – channels, subscriptions, mandatory official channel
4. `migrations/20261030000004_verification.sql` – verification applications, documents, history
5. `migrations/20261030000005_partners.sql` – partner applications, profiles, partner-scoped permissions
6. `migrations/20261030000006_messaging_social.sql` – conversations, messages, stories, communities
7. `migrations/20261030000007_business_platform_ops.sql` – business catalog, premium, notifications, reports, announcements
8. `migrations/20261030000008_policies_stats_storage_realtime.sql` – grants, presence, owner stats, storage buckets, realtime
9. `migrations/20261030000009_messaging_calls_notifications.sql` – audio/GIF/sticker messages, message pin and star,
   direct voice/video calls, preference-aware notifications, channel-post and status notifications, security events

Key rules enforced in the database (not in the app):

- Verification badges change only through `review_verification_application`; users cannot self-grant.
- Exactly one active Owner (unique partial index); `bootstrap_owner` runs only in a trusted context.
- Official channel cannot be deleted and its mandatory subscription cannot be removed by users.
- Partner role is granted and revoked by functions and does not imply admin.
- Verification documents live in the private `verification-docs` bucket under `{uid}/{application_id}/…`
  and are read via short-lived signed URLs.
- Every privileged action writes to `admin_audit_logs` or `owner_audit_logs`; audit rows cannot be edited.

Scheduled jobs (not created by the migrations; configure one of):

- `select public.expire_stale_calls();` – every minute (marks unanswered calls as missed).
- `select public.dispatch_due_channel_posts();` – every minute (notifies subscribers of scheduled posts).

Use `pg_cron` on Supabase or a scheduled Edge Function with the service role. These functions are not callable
by app users.

## Tests

`scripts/test_db.sh` applies a local Supabase stand-in (`tests/00_supabase_stub.sql`) and all migrations to a
scratch database, then runs the scenario suites (`tests/01_helpers.sql`, `02_scenarios.sql`,
`03_scenarios_business_social_ops.sql`, `04_scenarios_messaging_calls.sql`). It requires `DATABASE_URL` pointing to
a database you can drop and recreate. The last full run passed on PostgreSQL 16 (245 PASS lines, exit 0).

Not yet verified: running the migrations on a hosted Supabase project (the stand-in replaces `auth`, `storage`
and `realtime` locally, so hosted-specific behaviour should be smoke-tested on a staging project).
