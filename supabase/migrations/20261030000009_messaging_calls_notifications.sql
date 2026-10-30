-- =============================================================================
-- 0009  Messaging completeness, calls, and preference-aware notifications
--   * Message kinds: audio, gif, sticker (in addition to 0006 kinds)
--   * Message pin (conversation-wide, members) and per-user star
--   * Direct voice/video call records with ringing, answer, decline, cancel, missed
--   * notify_user honours notification preferences; security alerts are never suppressed
--   * Notification triggers: new messages, channel posts, verification and partner
--     status changes, story reactions, role changes and account status changes
--   * Security events feed for account activity
--   * Owner statistics: total conversations
-- All new functions are revoked from PUBLIC/anon by default (PostgreSQL grants
-- EXECUTE to PUBLIC on creation); client-callable ones are granted explicitly.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Message kinds
-- ---------------------------------------------------------------------------
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_valid check (
  kind in ('text', 'image', 'video', 'voice', 'audio', 'document', 'gif', 'sticker',
           'location', 'contact', 'system')
);

-- ---------------------------------------------------------------------------
-- 2. Pin (conversation-wide) and star (personal)
-- ---------------------------------------------------------------------------
alter table public.messages add column if not exists pinned_at timestamptz;
alter table public.messages add column if not exists pinned_by uuid references public.profiles (id) on delete set null;
create index if not exists messages_pinned on public.messages (conversation_id, pinned_at desc) where pinned_at is not null;

create or replace function public.set_message_pinned(p_message_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  select conversation_id into v_conv
    from public.messages
   where id = p_message_id and deleted_at is null and hidden_at is null;
  if v_conv is null or not public.is_conversation_member(v_conv) then
    raise exception 'Message not found' using errcode = '42501';
  end if;
  update public.messages
     set pinned_at = case when p_pinned then now() else null end,
         pinned_by = case when p_pinned then auth.uid() else null end
   where id = p_message_id;
end;
$$;

create table if not exists public.message_stars (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  message_id  uuid not null references public.messages (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table public.message_stars enable row level security;

create policy message_stars_own_select on public.message_stars for select to authenticated
  using (user_id = auth.uid());
create policy message_stars_own_insert on public.message_stars for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.messages m
       where m.id = message_id and public.is_conversation_member(m.conversation_id)
    )
  );
create policy message_stars_own_delete on public.message_stars for delete to authenticated
  using (user_id = auth.uid());
grant select, insert, delete on public.message_stars to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Notifications honour preferences (user_settings.notifications)
--    Preference-controlled kinds: messages, calls, channels.
--    Everything else (security, verification, partner, moderation, stories) is always delivered.
-- ---------------------------------------------------------------------------
create or replace function public.notify_user(p_user_id uuid, p_kind text, p_title text, p_body text, p_data jsonb default '{}')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pref text;
  v_enabled boolean := true;
begin
  v_pref := case
    when p_kind = 'new_message' then 'messages'
    when p_kind in ('incoming_call', 'missed_call') then 'calls'
    when p_kind = 'channel_post' then 'channels'
    else null
  end;
  if v_pref is not null then
    select (us.notifications ->> v_pref)::boolean into v_enabled
      from public.user_settings us where us.user_id = p_user_id;
    v_enabled := coalesce(v_enabled, true);
  end if;
  if v_enabled then
    insert into public.notifications (user_id, kind, title, body, data)
    values (p_user_id, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. New message notifications (skips muted members, the sender, system messages)
-- ---------------------------------------------------------------------------
create or replace function public.on_message_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_preview text;
  r record;
begin
  if new.kind = 'system' or new.deleted_at is not null then
    return new;
  end if;
  select coalesce(nullif(display_name, ''), username) into v_name
    from public.profiles where id = new.sender_id;
  v_preview := case new.kind
    when 'text' then left(coalesce(new.body, ''), 120)
    when 'image' then 'Sent a photo'
    when 'video' then 'Sent a video'
    when 'voice' then 'Sent a voice message'
    when 'audio' then 'Sent an audio file'
    when 'document' then 'Sent a document'
    when 'gif' then 'Sent a GIF'
    when 'sticker' then 'Sent a sticker'
    when 'location' then 'Shared a location'
    when 'contact' then 'Shared a contact'
    else 'New message'
  end;
  for r in
    select m.user_id from public.conversation_members m
     where m.conversation_id = new.conversation_id
       and m.left_at is null
       and not m.muted
       and m.user_id is distinct from new.sender_id
  loop
    perform public.notify_user(r.user_id, 'new_message', coalesce(v_name, 'New message'), v_preview,
      jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id));
  end loop;
  return new;
end;
$$;

create trigger messages_notify after insert on public.messages
  for each row execute function public.on_message_notify();

-- ---------------------------------------------------------------------------
-- 5. Calls (direct chats). Group calls are out of scope for this release.
-- ---------------------------------------------------------------------------
create table if not exists public.calls (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  caller_id       uuid not null references public.profiles (id) on delete cascade,
  callee_id       uuid not null references public.profiles (id) on delete cascade,
  media           text not null check (media in ('voice', 'video')),
  status          text not null default 'ringing'
                  check (status in ('ringing', 'answered', 'ended', 'missed', 'declined', 'cancelled')),
  started_at      timestamptz not null default now(),
  answered_at     timestamptz,
  ended_at        timestamptz,
  constraint calls_distinct_parties check (caller_id <> callee_id)
);
create index if not exists calls_caller_time on public.calls (caller_id, started_at desc);
create index if not exists calls_callee_time on public.calls (callee_id, started_at desc);
-- A user can take part in at most one live call (ringing or answered), in either role.
create unique index if not exists calls_live_caller on public.calls (caller_id) where status in ('ringing', 'answered');
create unique index if not exists calls_live_callee on public.calls (callee_id) where status in ('ringing', 'answered');

alter table public.calls enable row level security;
create policy calls_participant_select on public.calls for select to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid());
grant select on public.calls to authenticated;
revoke all on public.calls from anon;

create or replace function public.start_call(p_conversation_id uuid, p_media text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_kind text;
  v_callee uuid;
  v_call uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if p_media not in ('voice', 'video') then
    raise exception 'Unsupported call type';
  end if;
  select kind into v_kind from public.conversations where id = p_conversation_id;
  if v_kind is distinct from 'direct' then
    raise exception 'Calls are available in direct chats only';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;
  select m.user_id into v_callee
    from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.user_id <> v_me and m.left_at is null;
  if v_callee is null then
    raise exception 'There is no one to call in this conversation';
  end if;
  if public.is_blocked_between(v_me, v_callee) then
    raise exception 'You cannot call this account' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.calls c
     where c.status in ('ringing', 'answered')
       and (c.caller_id in (v_me, v_callee) or c.callee_id in (v_me, v_callee))
  ) then
    raise exception 'A call is already in progress';
  end if;

  insert into public.calls (conversation_id, caller_id, callee_id, media)
  values (p_conversation_id, v_me, v_callee, p_media)
  returning id into v_call;

  perform public.notify_user(v_callee, 'incoming_call',
    case when p_media = 'video' then 'Incoming video call' else 'Incoming voice call' end,
    'Tap to answer', jsonb_build_object('call_id', v_call, 'media', p_media));
  return v_call;
end;
$$;

create or replace function public.answer_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call_id for update;
  if not found or v_call.callee_id <> auth.uid() then
    raise exception 'Call not found' using errcode = '42501';
  end if;
  if v_call.status <> 'ringing' then
    raise exception 'This call is no longer ringing';
  end if;
  update public.calls set status = 'answered', answered_at = now() where id = p_call_id;
end;
$$;

create or replace function public.decline_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call_id for update;
  if not found or v_call.callee_id <> auth.uid() then
    raise exception 'Call not found' using errcode = '42501';
  end if;
  if v_call.status <> 'ringing' then
    raise exception 'This call is no longer ringing';
  end if;
  update public.calls set status = 'declined', ended_at = now() where id = p_call_id;
end;
$$;

-- Either participant ends the call. Ending a ringing call as the caller cancels it and
-- the callee receives a missed-call notification.
create or replace function public.end_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call_id for update;
  if not found or auth.uid() not in (v_call.caller_id, v_call.callee_id) then
    raise exception 'Call not found' using errcode = '42501';
  end if;
  if v_call.status = 'ringing' then
    if auth.uid() = v_call.caller_id then
      update public.calls set status = 'cancelled', ended_at = now() where id = p_call_id;
      perform public.notify_user(v_call.callee_id, 'missed_call', 'Missed call',
        'You missed a call', jsonb_build_object('call_id', p_call_id));
    else
      update public.calls set status = 'declined', ended_at = now() where id = p_call_id;
    end if;
  elsif v_call.status = 'answered' then
    update public.calls set status = 'ended', ended_at = now() where id = p_call_id;
  else
    raise exception 'This call has already finished';
  end if;
end;
$$;

-- Marks ringing calls that were never answered as missed. Run every minute by a scheduler
-- (pg_cron or a scheduled Edge Function using the service role). Not callable by clients.
create or replace function public.expire_stale_calls()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    update public.calls
       set status = 'missed', ended_at = now()
     where status = 'ringing' and started_at < now() - interval '45 seconds'
    returning id, callee_id
  loop
    perform public.notify_user(r.callee_id, 'missed_call', 'Missed call', 'You missed a call',
      jsonb_build_object('call_id', r.id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Channel post notifications (subscribers with the channels preference enabled)
-- ---------------------------------------------------------------------------
alter table public.channel_posts add column if not exists notified_at timestamptz;

create or replace function public.dispatch_channel_post(p_post_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post public.channel_posts%rowtype;
  v_channel_name text;
  v_count integer;
begin
  select * into v_post from public.channel_posts where id = p_post_id;
  if not found or v_post.notified_at is not null or v_post.hidden_at is not null
     or v_post.publish_at > now() then
    return 0;
  end if;
  select name into v_channel_name from public.channels where id = v_post.channel_id;

  with recipients as (
    select s.user_id
      from public.channel_subscribers s
     where s.channel_id = v_post.channel_id
       and s.is_active
       and s.user_id is distinct from v_post.author_id
       and coalesce((select (us.notifications ->> 'channels')::boolean
                       from public.user_settings us where us.user_id = s.user_id), true)
  ), inserted as (
    insert into public.notifications (user_id, kind, title, body, data)
    select r.user_id, 'channel_post', coalesce(v_channel_name, 'Channel'),
           left(coalesce(v_post.body, 'New post'), 120),
           jsonb_build_object('channel_id', v_post.channel_id, 'post_id', v_post.id)
      from recipients r
    returning 1
  )
  select count(*) into v_count from inserted;

  update public.channel_posts set notified_at = now() where id = p_post_id;
  return v_count;
end;
$$;

-- Sweep for scheduled posts whose publish time has arrived (scheduler-driven).
create or replace function public.dispatch_due_channel_posts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_total integer := 0;
begin
  for r in
    select id from public.channel_posts
     where notified_at is null and hidden_at is null and publish_at <= now()
     order by publish_at
     limit 500
  loop
    v_total := v_total + public.dispatch_channel_post(r.id);
  end loop;
  return v_total;
end;
$$;

create or replace function public.on_channel_post_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.publish_at <= now() then
    perform public.dispatch_channel_post(new.id);
  end if;
  return new;
end;
$$;

create trigger channel_posts_notify after insert on public.channel_posts
  for each row execute function public.on_channel_post_insert();

-- ---------------------------------------------------------------------------
-- 7. Status change notifications: verification, partner, stories
-- ---------------------------------------------------------------------------
create or replace function public.on_verification_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    perform public.notify_user(new.applicant_id, 'verification_status', 'Verification update',
      'Your verification request is now: ' || replace(new.status, '_', ' ') || '.',
      jsonb_build_object('application_id', new.id, 'status', new.status));
  end if;
  return new;
end;
$$;

create trigger verification_status_notify after update of status on public.verification_applications
  for each row execute function public.on_verification_status();

create or replace function public.on_partner_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    perform public.notify_user(new.applicant_id, 'partner_status', 'Partner application update',
      'Your partner application is now: ' || replace(new.status, '_', ' ') || '.',
      jsonb_build_object('application_id', new.id, 'status', new.status));
  end if;
  return new;
end;
$$;

create trigger partner_status_notify after update of status on public.partner_applications
  for each row execute function public.on_partner_status();

create or replace function public.on_story_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
begin
  select author_id into v_author from public.stories where id = new.story_id;
  if v_author is not null and v_author <> new.user_id then
    perform public.notify_user(v_author, 'story_reaction', 'New story reaction',
      'Someone reacted to your story', jsonb_build_object('story_id', new.story_id));
  end if;
  return new;
end;
$$;

create trigger story_reactions_notify after insert on public.story_reactions
  for each row execute function public.on_story_reaction();

-- ---------------------------------------------------------------------------
-- 8. Security events and security alerts (role and account status changes)
-- ---------------------------------------------------------------------------
create table if not exists public.security_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('role_granted', 'role_revoked', 'account_status_changed')),
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists security_events_user_time on public.security_events (user_id, created_at desc);
alter table public.security_events enable row level security;
create policy security_events_own_select on public.security_events for select to authenticated
  using (user_id = auth.uid());
grant select on public.security_events to authenticated;
revoke all on public.security_events from anon;

create or replace function public.on_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.security_events (user_id, kind, detail)
    values (new.user_id, 'role_granted', jsonb_build_object('role', new.role_key));
    perform public.notify_user(new.user_id, 'security_alert', 'Account role updated',
      'You were given the role: ' || new.role_key || '.', jsonb_build_object('role', new.role_key));
  elsif old.revoked_at is null and new.revoked_at is not null then
    insert into public.security_events (user_id, kind, detail)
    values (new.user_id, 'role_revoked', jsonb_build_object('role', new.role_key));
    perform public.notify_user(new.user_id, 'security_alert', 'Account role updated',
      'The role ' || new.role_key || ' was removed from your account.', jsonb_build_object('role', new.role_key));
  end if;
  return new;
end;
$$;

create trigger user_roles_security_event after insert or update of revoked_at on public.user_roles
  for each row execute function public.on_role_change();

create or replace function public.on_account_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.account_status is distinct from old.account_status then
    insert into public.security_events (user_id, kind, detail)
    values (new.id, 'account_status_changed',
            jsonb_build_object('from', old.account_status, 'to', new.account_status));
    perform public.notify_user(new.id, 'security_alert', 'Account status changed',
      'Your account status is now: ' || new.account_status || '.', jsonb_build_object('status', new.account_status));
  end if;
  return new;
end;
$$;

create trigger profiles_security_event after update of account_status on public.profiles
  for each row execute function public.on_account_status_change();

-- ---------------------------------------------------------------------------
-- 9. Owner statistics: add total conversations (from 0008, plus one key)
-- ---------------------------------------------------------------------------
create or replace function public.owner_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('analytics.read') then
    raise exception 'Permission denied: analytics.read' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'total_users',        (select count(*) from public.profiles),
    'active_users_30d',   (select count(*) from public.profiles where last_seen_at >= now() - interval '30 days'),
    'online_users',       (select count(*) from public.profiles where last_seen_at >= now() - interval '5 minutes'),
    'personal_accounts',  (select count(*) from public.account_modes where mode = 'personal'),
    'business_accounts',  (select count(*) from public.businesses where is_setup_complete),
    'verified_users',     (select count(*) from public.profiles where is_verified),
    'verified_businesses',(select count(*) from public.businesses where is_verified),
    'verified_channels',  (select count(*) from public.channels where is_verified),
    'total_partners',     (select count(*) from public.partner_profiles),
    'active_partners',    (select count(*) from public.partner_profiles where partner_status = 'active'),
    'total_administrators',(select count(*) from public.admin_assignments where status = 'active'),
    'total_channels',     (select count(*) from public.channels),
    'total_subscribers',  (select count(*) from public.channel_subscribers where is_active),
    'total_conversations',(select count(*) from public.conversations),
    'total_messages',     (select count(*) from public.messages),
    'total_communities',  (select count(*) from public.communities),
    'total_reports',      (select count(*) from public.reports),
    'open_reports',       (select count(*) from public.reports where status in ('open', 'reviewing', 'escalated')),
    'pending_verifications', (select count(*) from public.verification_applications
                              where status in ('pending', 'under_review', 'info_requested')),
    'pending_partner_applications', (select count(*) from public.partner_applications
                                     where status in ('pending', 'reviewing')),
    'premium_active',     (select count(*) from public.premium_subscriptions
                           where status = 'active' and ends_at > now()),
    'generated_at',       now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Privileges for the new functions
-- ---------------------------------------------------------------------------
revoke execute on function
  public.on_message_notify(), public.dispatch_channel_post(uuid), public.dispatch_due_channel_posts(),
  public.on_channel_post_insert(), public.on_verification_status(), public.on_partner_status(),
  public.on_story_reaction(), public.on_role_change(), public.on_account_status_change(),
  public.expire_stale_calls()
from public, anon, authenticated;

revoke execute on function public.set_message_pinned(uuid, boolean), public.start_call(uuid, text),
  public.answer_call(uuid), public.decline_call(uuid), public.end_call(uuid)
from public, anon;
grant execute on function public.set_message_pinned(uuid, boolean), public.start_call(uuid, text),
  public.answer_call(uuid), public.decline_call(uuid), public.end_call(uuid) to authenticated;

-- Realtime for call state (only where the Supabase realtime publication exists).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.calls;
    exception when duplicate_object then null;
    end;
  end if;
end $$;
