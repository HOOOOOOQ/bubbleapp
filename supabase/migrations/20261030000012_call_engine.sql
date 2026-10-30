-- =============================================================================
-- 0012 Voice & Video Call Engine (WebRTC signaling + group + history)
-- Extends 0009 calls for production-grade calling. Preserves existing rows.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend calls table for group, reconnect, and metadata
-- ---------------------------------------------------------------------------
alter table public.calls
  add column if not exists is_group boolean not null default false,
  add column if not exists group_host_id uuid references public.profiles (id) on delete set null,
  add column if not exists ended_reason text
    check (ended_reason in ('completed','cancelled','declined','missed','failed','busy','timeout')),
  add column if not exists duration_seconds integer,
  add column if not exists sfu_room_id text,
  add column if not exists max_participants integer default 8 check (max_participants is null or max_participants between 2 and 50),
  add column if not exists updated_at timestamptz not null default now();

-- Allow callee_id null for group invitations (initiator does not target single callee)
alter table public.calls alter column callee_id drop not null;

-- Track who created/updated
create trigger calls_touch before update on public.calls
  for each row execute function public.touch_updated_at();

-- Status extension: add failed,busy,timeout,reconnecting to cover spec
-- Existing check: ringing,answered,ended,missed,declined,cancelled
-- We add new statuses via constraint replacement
alter table public.calls drop constraint if exists calls_status_check;
alter table public.calls add constraint calls_status_check
  check (status in ('ringing','connecting','connected','reconnecting','answered','ended','missed','declined','cancelled','failed','busy','timeout'));

-- Duration helper
create or replace function public.calls_compute_duration()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.ended_at is not null and new.started_at is not null then
    new.duration_seconds := extract(epoch from (new.ended_at - coalesce(new.answered_at, new.started_at)))::int;
  end if;
  return new;
end;
$$;
create trigger calls_duration before update of ended_at on public.calls
  for each row execute function public.calls_compute_duration();

-- ---------------------------------------------------------------------------
-- 2. Call participants (for group and 1-1 history fidelity)
-- ---------------------------------------------------------------------------
create table if not exists public.call_participants (
  call_id     uuid not null references public.calls (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        text not null default 'member' check (role in ('host','member')),
  status      text not null default 'invited' check (status in ('invited','joined','left','declined','missed','failed')),
  joined_at   timestamptz,
  left_at     timestamptz,
  is_muted    boolean not null default false,
  is_camera_on boolean not null default true,
  is_deafened boolean not null default false,
  created_at  timestamptz not null default now(),
  primary key (call_id, user_id)
);
create index if not exists call_participants_user_idx on public.call_participants (user_id, created_at desc);

alter table public.call_participants enable row level security;
create policy call_participants_self_select on public.call_participants for select to authenticated
  using ( user_id = auth.uid() or exists (select 1 from public.calls c where c.id = call_id and (c.caller_id = auth.uid() or c.callee_id = auth.uid() or c.group_host_id = auth.uid())) );
-- More permissive select for group members: any member of conversation can see participants
drop policy if exists call_participants_group_select on public.call_participants;
create policy call_participants_group_select on public.call_participants for select to authenticated
  using ( public.is_conversation_member((select conversation_id from public.calls where id = call_id)) );

grant select on public.call_participants to authenticated;
revoke insert, update, delete on public.call_participants from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Signaling (transient SDP/ICE) — TTL 5 min, not permanent storage
-- ---------------------------------------------------------------------------
create table if not exists public.call_signals (
  id          uuid primary key default gen_random_uuid(),
  call_id     uuid not null references public.calls (id) on delete cascade,
  sender_id   uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('offer','answer','ice-candidate','join','leave','end','decline','cancel','busy','reconnect','media-update')),
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '5 minutes'
);
create index if not exists call_signals_call_time on public.call_signals (call_id, created_at desc);
create index if not exists call_signals_expires on public.call_signals (expires_at) where expires_at is not null;

alter table public.call_signals enable row level security;
create policy call_signals_member_select on public.call_signals for select to authenticated
  using ( public.is_conversation_member((select conversation_id from public.calls where id = call_id)) );
create policy call_signals_member_insert on public.call_signals for insert to authenticated
  with check ( sender_id = auth.uid() and public.is_conversation_member((select conversation_id from public.calls where id = call_id)) );

grant select, insert on public.call_signals to authenticated;
revoke update, delete on public.call_signals from anon, authenticated;

-- Auto-cleanup expired signals (pg_cron or Edge Function will call)
create or replace function public.cleanup_expired_call_signals()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v int;
begin
  delete from public.call_signals where expires_at <= now();
  get diagnostics v = row_count;
  return v;
end;
$$;
revoke execute on function public.cleanup_expired_call_signals() from public, anon, authenticated;
grant execute on function public.cleanup_expired_call_signals() to service_role;

-- ---------------------------------------------------------------------------
-- 4. Personal call history visibility (soft delete per user, does not affect others)
-- ---------------------------------------------------------------------------
create table if not exists public.call_history_visibility (
  call_id  uuid not null references public.calls (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (call_id, user_id)
);
alter table public.call_history_visibility enable row level security;
create policy call_history_visibility_own on public.call_history_visibility for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, delete on public.call_history_visibility to authenticated;
revoke all on public.call_history_visibility from anon;

-- ---------------------------------------------------------------------------
-- 5. Settings extension for call preferences
-- ---------------------------------------------------------------------------
-- user_settings already has privacy/notifications jsonb; we add calls prefs column
alter table public.user_settings
  add column if not exists call_settings jsonb not null default '{"mic_muted":false,"speaker_on":false,"camera_front":true,"video_quality":"auto","noise_suppression":true,"echo_cancellation":true,"data_saver":false,"incoming_notifications":true}'::jsonb;

-- ---------------------------------------------------------------------------
-- 6. Update RLS for calls to support group and participant visibility
-- ---------------------------------------------------------------------------
drop policy if exists calls_participant_select on public.calls;
create policy calls_participant_select on public.calls for select to authenticated
  using (
    caller_id = auth.uid()
    or callee_id = auth.uid()
    or group_host_id = auth.uid()
    or exists (select 1 from public.call_participants cp where cp.call_id = calls.id and cp.user_id = auth.uid())
    or public.is_conversation_member(conversation_id)
  );

-- Only participant can update (for status changes via functions, not direct)
-- Keep grant select only; mutations go through RPCs (security definer)
grant select on public.calls to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RPCs: secure, membership-checked, rate-limited
-- ---------------------------------------------------------------------------

-- Helper: rate limit 20 calls per hour per user (simple count window)
create or replace function public.check_call_rate_limit()
returns void
language plpgsql
set search_path = public
as $$
begin
  if (select count(*) from public.calls where caller_id = auth.uid() and started_at > now() - interval '1 hour') >= 20 then
    raise exception 'Call rate limit exceeded. Try again later' using errcode = '42501';
  end if;
end;
$$;

-- Start 1-1 or group call (group = conversation kind group with members)
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
  v_is_group boolean := false;
  r record;
begin
  if not public.is_active_user() then raise exception 'Active account required' using errcode = '42501'; end if;
  if p_media not in ('voice','video') then raise exception 'Unsupported call type'; end if;
  perform public.check_call_rate_limit();
  select kind into v_kind from public.conversations where id = p_conversation_id;
  if v_kind is null then raise exception 'Conversation not found' using errcode = '42501'; end if;
  if not public.is_conversation_member(p_conversation_id) then raise exception 'Conversation not found' using errcode = '42501'; end if;

  if v_kind = 'group' then
    v_is_group := true;
    -- Group: host is caller, callee stays null, participants = all active members
    if exists (select 1 from public.calls c where c.conversation_id = p_conversation_id and c.status in ('ringing','connecting','connected','reconnecting','answered')) then
      raise exception 'A group call is already in progress' using errcode = '42501';
    end if;
    if (select count(*) from public.conversation_members where conversation_id = p_conversation_id and left_at is null) > 50 then
      raise exception 'Group call participant limit exceeded';
    end if;
    insert into public.calls (conversation_id, caller_id, callee_id, media, status, is_group, group_host_id, max_participants)
    values (p_conversation_id, v_me, null, p_media, 'ringing', true, v_me, 8)
    returning id into v_call;
    -- Insert participants (host joined, others invited)
    insert into public.call_participants (call_id, user_id, role, status, joined_at)
    values (v_call, v_me, 'host', 'joined', now());
    for r in select user_id from public.conversation_members where conversation_id = p_conversation_id and left_at is null and user_id <> v_me loop
      if not public.is_blocked_between(v_me, r.user_id) then
        insert into public.call_participants (call_id, user_id, role, status) values (v_call, r.user_id, 'member', 'invited')
        on conflict do nothing;
        perform public.notify_user(r.user_id, 'incoming_call', case when p_media='video' then 'Incoming group video call' else 'Incoming group voice call' end, 'Tap to join', jsonb_build_object('call_id', v_call, 'media', p_media, 'is_group', true));
      end if;
    end loop;
    -- Also create system message
    insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
    values (p_conversation_id, v_me, gen_random_uuid(), 'system', case when p_media='video' then 'Started a group video call' else 'Started a group voice call' end);
    return v_call;
  else
    -- Direct 1-1 (preserve original behavior)
    select m.user_id into v_callee from public.conversation_members m where m.conversation_id = p_conversation_id and m.user_id <> v_me and m.left_at is null;
    if v_callee is null then raise exception 'There is no one to call in this conversation'; end if;
    if public.is_blocked_between(v_me, v_callee) then raise exception 'You cannot call this account' using errcode = '42501'; end if;
    if exists (select 1 from public.calls c where c.status in ('ringing','connecting','connected','reconnecting','answered') and (c.caller_id in (v_me, v_callee) or c.callee_id in (v_me, v_callee) or exists (select 1 from public.call_participants cp where cp.call_id=c.id and cp.user_id in (v_me, v_callee) and cp.status='joined'))) then
      raise exception 'A call is already in progress' using errcode = '42501';
    end if;
    insert into public.calls (conversation_id, caller_id, callee_id, media, is_group, status)
    values (p_conversation_id, v_me, v_callee, p_media, false, 'ringing') returning id into v_call;
    insert into public.call_participants (call_id, user_id, role, status, joined_at) values (v_call, v_me, 'host', 'joined', now()) on conflict do nothing;
    insert into public.call_participants (call_id, user_id, role, status) values (v_call, v_callee, 'member', 'invited') on conflict do nothing;
    perform public.notify_user(v_callee, 'incoming_call', case when p_media='video' then 'Incoming video call' else 'Incoming voice call' end, 'Tap to answer', jsonb_build_object('call_id', v_call, 'media', p_media));
    insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
    values (p_conversation_id, v_me, gen_random_uuid(), 'system', case when p_media='video' then 'Video call started' else 'Voice call started' end);
    return v_call;
  end if;
end;
$$;

create or replace function public.answer_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call_id for update;
  if not found then raise exception 'Call not found' using errcode = '42501'; end if;
  if v_call.status not in ('ringing','connecting') then raise exception 'This call is no longer ringing'; end if;
  -- Verify membership
  if not (exists (select 1 from public.call_participants where call_id=p_call_id and user_id=auth.uid()) or v_call.callee_id=auth.uid() or v_call.caller_id=auth.uid() or public.is_conversation_member(v_call.conversation_id)) then
    raise exception 'Not a participant of this call' using errcode = '42501';
  end if;
  update public.calls set status='answered', answered_at=now(), updated_at=now() where id=p_call_id;
  update public.call_participants set status='joined', joined_at=now() where call_id=p_call_id and user_id=auth.uid();
  insert into public.call_signals (call_id, sender_id, kind, payload) values (p_call_id, auth.uid(), 'join', jsonb_build_object('user_id', auth.uid()));
end;
$$;

create or replace function public.decline_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id=p_call_id for update;
  if not found then raise exception 'Call not found' using errcode = '42501'; end if;
  if v_call.status not in ('ringing','connecting') then raise exception 'This call is no longer ringing'; end if;
  if not (exists (select 1 from public.call_participants where call_id=p_call_id and user_id=auth.uid())) then
    if v_call.callee_id <> auth.uid() then raise exception 'Call not found' using errcode = '42501'; end if;
  end if;
  update public.call_participants set status='declined', left_at=now() where call_id=p_call_id and user_id=auth.uid();
  -- If 1-1 and callee declines, mark declined; if group, only participant declines
  if not v_call.is_group then
    update public.calls set status='declined', ended_at=now(), ended_reason='declined', updated_at=now() where id=p_call_id;
  else
    -- If all invited declined, end group call
    if not exists (select 1 from public.call_participants where call_id=p_call_id and status in ('invited','joined')) then
      update public.calls set status='ended', ended_at=now(), ended_reason='declined', updated_at=now() where id=p_call_id;
    end if;
  end if;
  insert into public.call_signals (call_id, sender_id, kind, payload) values (p_call_id, auth.uid(), 'decline', jsonb_build_object('user_id', auth.uid()));
end;
$$;

create or replace function public.end_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id=p_call_id for update;
  if not found or auth.uid() not in (v_call.caller_id, v_call.callee_id, coalesce(v_call.group_host_id, '00000000-0000-0000-0000-000000000000'::uuid)) and not exists (select 1 from public.call_participants where call_id=p_call_id and user_id=auth.uid()) then
    if not public.is_conversation_member(v_call.conversation_id) then raise exception 'Call not found' using errcode = '42501'; end if;
  end if;
  if v_call.status = 'ringing' then
    if auth.uid() = v_call.caller_id or auth.uid() = v_call.group_host_id then
      update public.calls set status='cancelled', ended_at=now(), ended_reason='cancelled', updated_at=now() where id=p_call_id;
      update public.call_participants set status='left', left_at=now() where call_id=p_call_id and status='invited';
      perform public.notify_user(coalesce(v_call.callee_id, v_call.caller_id), 'missed_call', 'Missed call', 'You missed a call', jsonb_build_object('call_id', p_call_id));
    else
      update public.call_participants set status='left', left_at=now() where call_id=p_call_id and user_id=auth.uid();
    end if;
  elsif v_call.status in ('answered','connecting','connected','reconnecting') then
    update public.calls set status='ended', ended_at=now(), ended_reason='completed', updated_at=now() where id=p_call_id;
    update public.call_participants set left_at=now(), status='left' where call_id=p_call_id and user_id=auth.uid();
    -- If group and host leaves, keep call for others unless empty
  else
    -- Already ended
    null;
  end if;
  insert into public.call_signals (call_id, sender_id, kind, payload) values (p_call_id, auth.uid(), 'end', jsonb_build_object('user_id', auth.uid()));
  insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (v_call.conversation_id, auth.uid(), gen_random_uuid(), 'system', case when v_call.media='video' then 'Video call ended' else 'Voice call ended' end);
end;
$$;

-- Join/leave group helpers
create or replace function public.join_group_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id=p_call_id for update;
  if not found then raise exception 'Call not found' using errcode = '42501'; end if;
  if not v_call.is_group then raise exception 'Not a group call'; end if;
  if v_call.status not in ('ringing','answered','connecting','connected','reconnecting') then raise exception 'Call not available'; end if;
  if not public.is_conversation_member(v_call.conversation_id) then raise exception 'Not a member' using errcode='42501'; end if;
  update public.call_participants set status='joined', joined_at=now() where call_id=p_call_id and user_id=auth.uid();
  if not found then
    insert into public.call_participants (call_id, user_id, role, status, joined_at) values (p_call_id, auth.uid(), 'member','joined', now());
  end if;
  insert into public.call_signals (call_id, sender_id, kind, payload) values (p_call_id, auth.uid(), 'join', jsonb_build_object('user_id', auth.uid()));
end;
$$;

create or replace function public.leave_group_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id=p_call_id for update;
  if not found then raise exception 'Call not found' using errcode='42501'; end if;
  update public.call_participants set status='left', left_at=now() where call_id=p_call_id and user_id=auth.uid();
  insert into public.call_signals (call_id, sender_id, kind, payload) values (p_call_id, auth.uid(), 'leave', jsonb_build_object('user_id', auth.uid()));
  if v_call.is_group and not exists (select 1 from public.call_participants where call_id=p_call_id and status='joined') then
    update public.calls set status='ended', ended_at=now(), ended_reason='completed', updated_at=now() where id=p_call_id;
  end if;
end;
$$;

-- Signaling: verified, rate-limited
create or replace function public.send_call_signal(p_call_id uuid, p_kind text, p_receiver uuid default null, p_payload jsonb default '{}')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_call public.calls%rowtype;
begin
  if p_kind not in ('offer','answer','ice-candidate','join','leave','end','decline','cancel','busy','reconnect','media-update') then raise exception 'Invalid signal kind'; end if;
  select * into v_call from public.calls where id=p_call_id;
  if not found then raise exception 'Call not found' using errcode='42501'; end if;
  if not (exists (select 1 from public.call_participants where call_id=p_call_id and user_id=auth.uid()) or v_call.caller_id=auth.uid() or v_call.callee_id=auth.uid() or public.is_conversation_member(v_call.conversation_id)) then
    raise exception 'Not a participant' using errcode='42501';
  end if;
  -- Rate limit signals
  if (select count(*) from public.call_signals where sender_id=auth.uid() and created_at > now() - interval '1 minute') > 300 then
    raise exception 'Signal rate limit exceeded' using errcode='42501';
  end if;
  insert into public.call_signals (call_id, sender_id, receiver_id, kind, payload) values (p_call_id, auth.uid(), p_receiver, p_kind, coalesce(p_payload,'{}')) returning id into v_id;
  return v_id;
end;
$$;

-- Expire stale ringing>60s, connecting>2min
create or replace function public.expire_stale_calls()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v int :=0; r record;
begin
  for r in select id, caller_id, callee_id, conversation_id, is_group from public.calls where status='ringing' and started_at < now() - interval '60 seconds' loop
    update public.calls set status='missed', ended_at=now(), ended_reason='timeout', updated_at=now() where id=r.id;
    update public.call_participants set status='missed' where call_id=r.id and status='invited';
    if not r.is_group and r.callee_id is not null then
      perform public.notify_user(r.callee_id, 'missed_call', 'Missed call', 'You missed a call', jsonb_build_object('call_id', r.id));
    end if;
    insert into public.messages (conversation_id, sender_id, client_message_id, kind, body) values (r.conversation_id, r.caller_id, gen_random_uuid(), 'system', 'Missed call');
    v:=v+1;
  end loop;
  update public.calls set status='failed', ended_at=now(), ended_reason='failed', updated_at=now() where status='connecting' and started_at < now() - interval '2 minutes';
  get diagnostics v = row_count;
  return v;
end;
$$;

-- Call history: hide personal entry
create or replace function public.hide_call_history(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.call_history_visibility (call_id, user_id) values (p_call_id, auth.uid()) on conflict do nothing;
end;
$$;
create or replace function public.clear_call_history()
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.call_history_visibility (call_id, user_id)
  select c.id, auth.uid() from public.calls c
  where (c.caller_id=auth.uid() or c.callee_id=auth.uid() or exists (select 1 from public.call_participants cp where cp.call_id=c.id and cp.user_id=auth.uid()))
  on conflict do nothing;
end;
$$;

-- Update myCalls view helper already exists via RLS select

-- Grants
revoke execute on function public.start_call(uuid,text) from public, anon;
revoke execute on function public.answer_call(uuid) from public, anon;
revoke execute on function public.decline_call(uuid) from public, anon;
revoke execute on function public.end_call(uuid) from public, anon;
revoke execute on function public.join_group_call(uuid) from public, anon;
revoke execute on function public.leave_group_call(uuid) from public, anon;
revoke execute on function public.send_call_signal(uuid,text,uuid,jsonb) from public, anon;
revoke execute on function public.hide_call_history(uuid) from public, anon;
revoke execute on function public.clear_call_history() from public, anon;

grant execute on function public.start_call(uuid,text) to authenticated;
grant execute on function public.answer_call(uuid) to authenticated;
grant execute on function public.decline_call(uuid) to authenticated;
grant execute on function public.end_call(uuid) to authenticated;
grant execute on function public.join_group_call(uuid) to authenticated;
grant execute on function public.leave_group_call(uuid) to authenticated;
grant execute on function public.send_call_signal(uuid,text,uuid,jsonb) to authenticated;
grant execute on function public.hide_call_history(uuid) to authenticated;
grant execute on function public.clear_call_history() to authenticated;

revoke execute on function public.expire_stale_calls() from public, anon, authenticated;
grant execute on function public.expire_stale_calls() to service_role;
revoke execute on function public.check_call_rate_limit() from public, anon, authenticated;

-- Realtime publication additions
do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') then
    begin alter publication supabase_realtime add table public.call_signals; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.call_participants; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.call_history_visibility; exception when duplicate_object then null; end;
  end if;
end $$;
