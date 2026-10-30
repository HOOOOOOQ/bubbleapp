-- =============================================================================
-- 0011: Push delivery bookkeeping. The push-dispatch Edge Function (service role)
-- sends FCM messages for notifications where push_sent_at is null. Preferences are
-- already enforced when notify_user() inserts the row.
-- =============================================================================
alter table public.notifications add column if not exists push_sent_at timestamptz;
alter table public.notifications add column if not exists push_attempts int not null default 0;
alter table public.notifications add column if not exists push_error text;

create index if not exists notifications_push_pending_idx
  on public.notifications (created_at) where push_sent_at is null;

-- Clients may read their own rows already (RLS). Delivery bookkeeping is service-role only.
revoke update (push_sent_at, push_attempts, push_error) on public.notifications from anon, authenticated;
