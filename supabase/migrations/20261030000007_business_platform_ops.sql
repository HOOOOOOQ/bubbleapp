-- =============================================================================
-- BubbleApp :: 0007 business tools, premium entitlements, reports & moderation,
-- notifications, platform announcements
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Business: create (validated setup), mode switch, catalog, quick replies
-- ---------------------------------------------------------------------------
create or replace function public.create_business(
  p_name text,
  p_username text,
  p_category text,
  p_business_email text,
  p_description text default '',
  p_website text default null,
  p_business_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if not public.setting_bool('business_accounts_enabled', true) then
    raise exception 'Business accounts are currently disabled by BubbleApp';
  end if;
  -- Validated business setup (mirrors table constraints with friendlier messages).
  if char_length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Business name is required'; end if;
  if lower(coalesce(p_username, '')) !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'Business username must be 3-32 characters: letters, numbers or underscores';
  end if;
  if char_length(trim(coalesce(p_category, ''))) < 2 then raise exception 'Business category is required'; end if;
  if coalesce(p_business_email, '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'A valid business email is required';
  end if;

  insert into public.businesses (created_by, name, username, category, business_email, description,
                                 website, business_phone, is_setup_complete)
  values (v_uid, trim(p_name), lower(p_username), trim(p_category), lower(trim(p_business_email)),
          coalesce(p_description, ''), nullif(trim(coalesce(p_website, '')), ''),
          nullif(trim(coalesce(p_business_phone, '')), ''), true)
  returning id into v_id;

  insert into public.business_members (business_id, user_id, role, added_by)
  values (v_id, v_uid, 'owner', v_uid);

  insert into public.account_modes (user_id, mode, business_id) values (v_uid, 'business', v_id);
  return v_id;
exception
  when unique_violation then
    raise exception 'This business username is already taken';
end;
$$;

-- Switching is a pointer change only. Personal profile, chats and settings are untouched.
create or replace function public.switch_account_mode(p_mode text, p_business_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_business public.businesses%rowtype;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if p_mode = 'personal' then
    update public.user_settings
       set active_account_mode = 'personal', active_business_id = null
     where user_id = v_uid;
  elsif p_mode = 'business' then
    if p_business_id is null or not public.is_business_member(p_business_id) then
      raise exception 'You are not a member of this business' using errcode = '42501';
    end if;
    select * into v_business from public.businesses where id = p_business_id;
    if not v_business.is_setup_complete then
      raise exception 'Complete the business profile setup before switching to Business Mode';
    end if;
    update public.user_settings
       set active_account_mode = 'business', active_business_id = p_business_id
     where user_id = v_uid;
  else
    raise exception 'Invalid account mode';
  end if;
end;
$$;

create table if not exists public.business_catalog_items (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  kind         text not null default 'product' check (kind in ('product', 'service')),
  name         text not null check (char_length(name) between 1 and 120),
  description  text not null default '' check (char_length(description) <= 1000),
  price_minor  integer check (price_minor is null or price_minor >= 0),
  currency     text not null default 'IDR' check (char_length(currency) = 3),
  image_url    text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger business_catalog_touch before update on public.business_catalog_items
  for each row execute function public.touch_updated_at();

create table if not exists public.business_quick_replies (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  shortcut     text not null check (shortcut ~ '^/[a-z0-9_-]{1,24}$'),
  body         text not null check (char_length(body) between 1 and 1000),
  created_at   timestamptz not null default now(),
  unique (business_id, shortcut)
);

-- Owners/managers add operators (never owners). Owner row is protected.
create or replace function public.add_business_operator(p_business_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_business_member(p_business_id, array['owner', 'manager']) then
    raise exception 'Only business owners or managers can manage operators' using errcode = '42501';
  end if;
  if p_role not in ('manager', 'operator') then
    raise exception 'Invalid business role';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id and account_status = 'active') then
    raise exception 'Target account is not active';
  end if;
  if exists (select 1 from public.business_members where business_id = p_business_id and user_id = p_user_id and role = 'owner') then
    raise exception 'The business owner cannot be changed here' using errcode = '42501';
  end if;
  insert into public.business_members (business_id, user_id, role, added_by)
  values (p_business_id, p_user_id, p_role, auth.uid())
  on conflict (business_id, user_id) do update set role = excluded.role;
end;
$$;

create or replace function public.remove_business_operator(p_business_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_business_member(p_business_id, array['owner', 'manager']) then
    raise exception 'Only business owners or managers can manage operators' using errcode = '42501';
  end if;
  delete from public.business_members
   where business_id = p_business_id and user_id = p_user_id and role <> 'owner';
end;
$$;

create or replace function public.business_dashboard(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_business_member(p_business_id) then
    raise exception 'Not a member of this business' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'operators', (select count(*) from public.business_members where business_id = p_business_id),
    'catalog_items', (select count(*) from public.business_catalog_items where business_id = p_business_id),
    'quick_replies', (select count(*) from public.business_quick_replies where business_id = p_business_id),
    'is_verified', (select is_verified from public.businesses where id = p_business_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Premium entitlements (written only by trusted server context / billing webhook)
-- ---------------------------------------------------------------------------
create table if not exists public.premium_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  plan          text not null check (plan in ('monthly', 'yearly')),
  status        text not null check (status in ('active', 'canceled', 'expired')),
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  provider      text not null,
  provider_ref  text unique,
  created_at    timestamptz not null default now(),
  constraint premium_period check (ends_at > starts_at)
);
create index if not exists premium_user_idx on public.premium_subscriptions (user_id, status);

create or replace function public.has_premium(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.premium_subscriptions s
    where s.user_id = p_user_id and s.status = 'active' and s.ends_at > now()
  );
$$;

-- Feature gate used by clients and other functions.
create or replace function public.premium_feature_granted(p_feature text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
           ((select setting_value from public.platform_settings where setting_key = 'premium_features') ->> p_feature)::boolean,
           false)
     and public.has_premium(auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Notifications (written by server functions only)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text not null default '',
  data        jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

create or replace function public.notify_user(p_user_id uuid, p_kind text, p_title text, p_body text, p_data jsonb default '{}')
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, kind, title, body, data)
  values (p_user_id, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Reports & moderation
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  target_type  text not null check (target_type in ('user', 'message', 'channel_post', 'story', 'community', 'business')),
  target_id    text not null,
  reason       text not null check (char_length(reason) between 3 and 80),
  details      text check (char_length(details) <= 2000),
  status       text not null default 'open' check (status in ('open', 'reviewing', 'escalated', 'resolved', 'dismissed')),
  resolved_by  uuid references public.profiles (id) on delete set null,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  constraint reports_one_per_reporter unique (reporter_id, target_type, target_id)
);
create index if not exists reports_status_idx on public.reports (status, created_at);

create table if not exists public.moderation_actions (
  id           bigint generated always as identity primary key,
  report_id    uuid references public.reports (id) on delete set null,
  actor_id     uuid references public.profiles (id) on delete set null,
  action       text not null,
  target_type  text not null,
  target_id    text not null,
  note         text,
  created_at   timestamptz not null default now()
);
create trigger moderation_actions_immutable before update or delete on public.moderation_actions
  for each row execute function public.reject_audit_mutation();

-- Moderators resolve reports. Hiding content and warnings need content.moderate;
-- suspension needs users.manage (and the usual rank rule).
create or replace function public.resolve_report(p_report_id uuid, p_action text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.reports%rowtype;
  v_owner uuid;
begin
  select * into v_report from public.reports where id = p_report_id for update;
  if not found then raise exception 'Report not found'; end if;
  if not (public.has_permission('reports.manage') or public.has_permission('content.moderate')) then
    raise exception 'Permission denied: reports.manage' using errcode = '42501';
  end if;

  -- Resolve the account responsible for the reported content.
  v_owner := case v_report.target_type
    when 'user' then v_report.target_id::uuid
    when 'message' then (select m.sender_id from public.messages m where m.id = v_report.target_id::uuid)
    when 'channel_post' then (select p.author_id from public.channel_posts p where p.id = v_report.target_id::uuid)
    when 'story' then (select s.author_id from public.stories s where s.id = v_report.target_id::uuid)
    else null
  end;

  case p_action
    when 'dismiss' then
      update public.reports set status = 'dismissed', resolved_by = auth.uid(), resolved_at = now() where id = p_report_id;
    when 'escalate' then
      update public.reports set status = 'escalated' where id = p_report_id;
    when 'warn' then
      if v_owner is null then raise exception 'No responsible account found'; end if;
      perform public.notify_user(v_owner, 'moderation.warning', 'Community guidelines warning',
        coalesce(p_note, 'Your content was reviewed and found to violate BubbleApp guidelines.'),
        jsonb_build_object('report_id', p_report_id));
      update public.reports set status = 'resolved', resolved_by = auth.uid(), resolved_at = now() where id = p_report_id;
    when 'hide_content' then
      case v_report.target_type
        when 'message' then update public.messages set hidden_at = now() where id = v_report.target_id::uuid;
        when 'channel_post' then update public.channel_posts set hidden_at = now() where id = v_report.target_id::uuid;
        when 'story' then update public.stories set hidden_at = now() where id = v_report.target_id::uuid;
        else raise exception 'This content type cannot be hidden';
      end case;
      update public.reports set status = 'resolved', resolved_by = auth.uid(), resolved_at = now() where id = p_report_id;
    when 'suspend_user' then
      if v_owner is null then raise exception 'No responsible account found'; end if;
      perform public.admin_set_account_status(v_owner, 'suspended', coalesce(p_note, 'Suspended after report review'));
      update public.reports set status = 'resolved', resolved_by = auth.uid(), resolved_at = now() where id = p_report_id;
    else
      raise exception 'Unknown moderation action';
  end case;

  insert into public.moderation_actions (report_id, actor_id, action, target_type, target_id, note)
  values (p_report_id, auth.uid(), p_action, v_report.target_type, v_report.target_id, p_note);
  perform public.write_audit('moderation.' || p_action, v_report.target_type, v_report.target_id,
    jsonb_build_object('report_id', p_report_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Platform announcements (optionally mirrored into the official channel)
-- ---------------------------------------------------------------------------
create table if not exists public.platform_announcements (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid references public.profiles (id) on delete set null,
  title        text not null check (char_length(title) between 3 and 120),
  body         text not null check (char_length(body) between 1 and 4000),
  audience     text not null default 'all' check (audience in ('all', 'partners', 'staff')),
  published_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create or replace function public.publish_platform_announcement(
  p_title text,
  p_body text,
  p_audience text default 'all',
  p_post_to_official boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_official uuid;
begin
  if not public.has_permission('announcements.manage') then
    raise exception 'Permission denied: announcements.manage' using errcode = '42501';
  end if;
  if p_audience not in ('all', 'partners', 'staff') then
    raise exception 'Invalid audience';
  end if;
  insert into public.platform_announcements (author_id, title, body, audience)
  values (auth.uid(), trim(p_title), trim(p_body), p_audience)
  returning id into v_id;

  if p_post_to_official then
    select id into v_official from public.channels where is_official;
    insert into public.channel_posts (channel_id, author_id, kind, body)
    values (v_official, auth.uid(), 'text', trim(p_title) || E'\n\n' || trim(p_body));
  end if;

  perform public.write_audit('announcement.publish', 'platform_announcement', v_id::text,
    jsonb_build_object('audience', p_audience, 'official_channel', p_post_to_official));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['business_catalog_items', 'business_quick_replies', 'premium_subscriptions',
    'notifications', 'reports', 'moderation_actions', 'platform_announcements']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select, insert, update, delete on public.business_catalog_items to authenticated;
grant select, insert, update, delete on public.business_quick_replies to authenticated;
grant select on public.premium_subscriptions to authenticated;
grant select, update (read_at) on public.notifications to authenticated;
grant select, insert on public.reports to authenticated;
grant select on public.moderation_actions to authenticated;
grant select on public.platform_announcements to authenticated;

create policy catalog_select on public.business_catalog_items for select to authenticated using (
  is_active or public.is_business_member(business_id)
);
create policy catalog_write on public.business_catalog_items for all to authenticated
  using (public.is_business_member(business_id, array['owner', 'manager']))
  with check (public.is_business_member(business_id, array['owner', 'manager']));

create policy quick_replies_members on public.business_quick_replies for all to authenticated
  using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id, array['owner', 'manager', 'operator']));

create policy premium_own on public.premium_subscriptions for select to authenticated using (user_id = auth.uid());

create policy notifications_own_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_own_read on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy reports_insert_own on public.reports for insert to authenticated with check (
  reporter_id = auth.uid() and public.is_active_user()
);
create policy reports_select on public.reports for select to authenticated using (
  reporter_id = auth.uid() or public.has_permission('reports.manage') or public.has_permission('content.moderate')
);

create policy moderation_actions_select on public.moderation_actions for select to authenticated using (
  actor_id = auth.uid() or public.has_permission('reports.manage') or public.has_permission('content.moderate')
);

create policy platform_announcements_select on public.platform_announcements for select to authenticated using (
  audience = 'all'
  or (audience = 'staff' and exists (select 1 from public.admin_assignments a
                                     where a.user_id = auth.uid() and a.status = 'active'))
  or (audience = 'partners' and exists (select 1 from public.partner_profiles p
                                        where p.user_id = auth.uid() and p.partner_status = 'active'))
  or public.has_permission('announcements.manage')
);

-- Business and channel-side RLS for verification/partner public badges is already in 0003-0005.
