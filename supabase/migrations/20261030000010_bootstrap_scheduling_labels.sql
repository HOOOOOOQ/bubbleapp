-- =============================================================================
-- 0010: Owner bootstrap via one-time token, scheduled messages, business labels,
--       and a corrected owner-role guard.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Owner-role guard. The earlier guard checked only is_trusted_context(). It now
-- uses privileged_write_enabled(), which is true in trusted server contexts AND
-- inside the single vetted definer function that redeems a bootstrap token
-- (it sets bubble.privileged for the current transaction only).
-- ---------------------------------------------------------------------------
create or replace function public.guard_owner_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (tg_op = 'INSERT' and new.role_key = 'owner')
     or (tg_op = 'UPDATE' and (old.role_key = 'owner' or new.role_key = 'owner')) then
    if not public.privileged_write_enabled() then
      raise exception 'The Owner role is provisioned only through trusted server-side setup'
        using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner bootstrap tokens. Only a SHA-256 hash is stored. The plaintext is shown
-- once to the operator by issue_owner_bootstrap_token(), which runs only in a
-- trusted context (direct database session as the operator, never via the API).
-- ---------------------------------------------------------------------------
create table if not exists public.owner_bootstrap_tokens (
  id           uuid primary key default gen_random_uuid(),
  token_hash   bytea not null unique,
  label        text not null check (char_length(label) between 1 and 80),
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  consumed_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
alter table public.owner_bootstrap_tokens enable row level security;
revoke all on public.owner_bootstrap_tokens from public, anon, authenticated;

create or replace function public.issue_owner_bootstrap_token(
  p_label text default 'initial-owner',
  p_ttl interval default interval '24 hours'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if not public.is_trusted_context() then
    raise exception 'Owner bootstrap tokens are issued only in a trusted server context' using errcode = '42501';
  end if;
  if p_ttl <= interval '0' or p_ttl > interval '7 days' then
    raise exception 'Token lifetime must be between 1 second and 7 days';
  end if;
  -- 256 bits of randomness from two version-4 UUIDs (122 random bits each, plus the 12 fixed bits ignored).
  v_token := encode(
    decode(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 'hex'),
    'base64');
  insert into public.owner_bootstrap_tokens (token_hash, label, expires_at)
  values (sha256(convert_to(v_token, 'UTF8')), p_label, now() + p_ttl);
  insert into public.owner_audit_logs (actor_id, action, target_type, target_id, metadata)
  values (null, 'owner.bootstrap_token_issued', 'owner_bootstrap_token', p_label,
          jsonb_build_object('expires_at', now() + p_ttl));
  return v_token;
end;
$$;

-- Redeems a token for the SIGNED-IN, EMAIL-CONFIRMED caller. Only succeeds when no
-- Owner exists. The token is consumed atomically; repeats and expired tokens fail.
create or replace function public.redeem_owner_bootstrap(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_token_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in with Email OTP before redeeming the bootstrap token' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users u where u.id = v_uid and u.email_confirmed_at is not null) then
    raise exception 'The account email must be verified' using errcode = '42501';
  end if;
  if exists (select 1 from public.user_roles where role_key = 'owner' and revoked_at is null) then
    raise exception 'An Owner already exists';
  end if;
  if p_token is null or char_length(p_token) < 32 then
    raise exception 'Invalid or expired bootstrap token' using errcode = '42501';
  end if;

  select t.id into v_token_id
  from public.owner_bootstrap_tokens t
  where t.token_hash = sha256(convert_to(p_token, 'UTF8'))
    and t.consumed_at is null
    and t.expires_at > now()
  for update;

  if v_token_id is null then
    raise exception 'Invalid or expired bootstrap token' using errcode = '42501';
  end if;

  perform set_config('bubble.privileged', 'on', true);
  insert into public.user_roles (user_id, role_key, assigned_by) values (v_uid, 'owner', null);
  update public.owner_bootstrap_tokens
     set consumed_at = now(), consumed_by = v_uid
   where id = v_token_id;
  insert into public.owner_audit_logs (actor_id, action, target_type, target_id, metadata)
  values (v_uid, 'owner.bootstrap_redeemed', 'profile', v_uid::text,
          jsonb_build_object('token_id', v_token_id));
  return v_uid;
end;
$$;

revoke execute on function public.issue_owner_bootstrap_token(text, interval) from public, anon, authenticated;
revoke execute on function public.redeem_owner_bootstrap(text) from public, anon;
grant execute on function public.redeem_owner_bootstrap(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Scheduled messages. Clients schedule and cancel through RPCs; a scheduler
-- (pg_cron or an Edge Function on a schedule, service role) calls
-- dispatch_due_scheduled_messages().
-- ---------------------------------------------------------------------------
create table if not exists public.scheduled_messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null check (char_length(body) between 1 and 4000),
  send_at          timestamptz not null,
  status           text not null default 'pending'
                   check (status in ('pending', 'sent', 'cancelled', 'failed')),
  sent_message_id  uuid references public.messages (id) on delete set null,
  error            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists scheduled_messages_due_idx on public.scheduled_messages (status, send_at);
alter table public.scheduled_messages enable row level security;

drop policy if exists scheduled_messages_read_own on public.scheduled_messages;
create policy scheduled_messages_read_own on public.scheduled_messages for select to authenticated
  using (sender_id = auth.uid());
revoke insert, update, delete on public.scheduled_messages from anon, authenticated;
grant select on public.scheduled_messages to authenticated;

create or replace function public.schedule_message(
  p_conversation_id uuid,
  p_body text,
  p_send_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;
  if p_send_at <= now() + interval '30 seconds' then
    raise exception 'Scheduled time must be at least 30 seconds in the future';
  end if;
  if p_send_at > now() + interval '365 days' then
    raise exception 'Scheduled time must be within 365 days';
  end if;
  insert into public.scheduled_messages (conversation_id, sender_id, body, send_at)
  values (p_conversation_id, auth.uid(), trim(p_body), p_send_at)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.cancel_scheduled_message(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.scheduled_messages
     set status = 'cancelled', updated_at = now()
   where id = p_id and sender_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'Scheduled message not found or already sent' using errcode = 'P0002';
  end if;
end;
$$;

-- Service-role only. Inserts due messages as their sender and records the outcome.
create or replace function public.dispatch_due_scheduled_messages(p_limit int default 50)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_msg uuid;
  v_count int := 0;
begin
  for r in
    select s.* from public.scheduled_messages s
    where s.status = 'pending' and s.send_at <= now()
    order by s.send_at
    limit greatest(p_limit, 1)
    for update skip locked
  loop
    begin
      -- Membership is checked against the stored sender, not auth.uid(): the scheduler runs with the service role.
      if not exists (select 1 from public.conversation_members m
                     where m.conversation_id = r.conversation_id
                       and m.user_id = r.sender_id and m.left_at is null) then
        raise exception 'Sender is no longer a member of the conversation';
      end if;
      -- Insert as the sender. This runs as the definer, so the sender identity is set explicitly.
      insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
      values (r.conversation_id, r.sender_id, gen_random_uuid(), 'text', r.body)
      returning id into v_msg;
      update public.scheduled_messages
         set status = 'sent', sent_message_id = v_msg, updated_at = now()
       where id = r.id;
      v_count := v_count + 1;
    exception when others then
      update public.scheduled_messages
         set status = 'failed', error = left(sqlerrm, 300), updated_at = now()
       where id = r.id;
    end;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.schedule_message(uuid, text, timestamptz) from public, anon;
revoke execute on function public.cancel_scheduled_message(uuid) from public, anon;
revoke execute on function public.dispatch_due_scheduled_messages(int) from public, anon, authenticated;
grant execute on function public.schedule_message(uuid, text, timestamptz) to authenticated;
grant execute on function public.cancel_scheduled_message(uuid) to authenticated;
grant execute on function public.dispatch_due_scheduled_messages(int) to service_role;

-- ---------------------------------------------------------------------------
-- Business labels (owner/manager manage; members read) and assignments to chats.
-- ---------------------------------------------------------------------------
create table if not exists public.business_labels (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 40),
  color        text not null default '#2563EB' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (business_id, name)
);

create table if not exists public.business_label_assignments (
  label_id         uuid not null references public.business_labels (id) on delete cascade,
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  assigned_by      uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  primary key (label_id, conversation_id)
);

alter table public.business_labels enable row level security;
alter table public.business_label_assignments enable row level security;

drop policy if exists business_labels_read on public.business_labels;
create policy business_labels_read on public.business_labels for select to authenticated
  using (public.is_business_member(business_id));
drop policy if exists business_labels_write on public.business_labels;
create policy business_labels_write on public.business_labels for all to authenticated
  using (public.is_business_member(business_id, array['owner', 'manager']))
  with check (public.is_business_member(business_id, array['owner', 'manager']));

drop policy if exists business_label_assignments_read on public.business_label_assignments;
create policy business_label_assignments_read on public.business_label_assignments for select to authenticated
  using (exists (select 1 from public.business_labels l
                 where l.id = label_id and public.is_business_member(l.business_id)));
drop policy if exists business_label_assignments_write on public.business_label_assignments;
create policy business_label_assignments_write on public.business_label_assignments for all to authenticated
  using (exists (select 1 from public.business_labels l
                 where l.id = label_id and public.is_business_member(l.business_id, array['owner', 'manager'])))
  with check (exists (select 1 from public.business_labels l
                 where l.id = label_id and public.is_business_member(l.business_id, array['owner', 'manager'])));

grant select, insert, update, delete on public.business_labels to authenticated;
grant select, insert, update, delete on public.business_label_assignments to authenticated;
