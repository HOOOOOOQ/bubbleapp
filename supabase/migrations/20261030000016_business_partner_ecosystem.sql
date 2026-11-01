-- =============================================================================
-- BubbleApp :: 0016 Business & Partner Ecosystem (Part 8)
-- Extends 0001-0015. No duplicate role/account systems are introduced:
--   * Business identity stays in public.businesses / business_members / account_modes
--   * Business verification reuses verification_applications + verification_documents
--   * Messaging reuses conversations/messages/attachments (new conversation kind 'business')
--   * Partner program reuses partner_profiles/partner_applications/partner_permissions
--   * Owner/Admin governance reuses has_permission/write_audit/platform_settings
-- All privileged operations are SECURITY DEFINER functions that check the caller's
-- business permission (or platform permission) before writing, and audit the change.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Business permission model (business-scoped, independent of platform RBAC)
-- ---------------------------------------------------------------------------
create table if not exists public.business_permissions (
  key         text primary key,
  label       text not null,
  category    text not null default 'general',
  description text not null default '',
  owner_only  boolean not null default false,
  sort_order  int not null default 0
);

insert into public.business_permissions (key, label, category, description, owner_only, sort_order) values
  ('profile.edit',      'Edit business profile',      'profile',   'Change name, description, category, contact and visibility', false, 10),
  ('profile.media',     'Manage logo and cover',      'profile',   'Upload or replace the business logo and cover image',        false, 20),
  ('catalog.manage',    'Manage catalog',             'catalog',   'Create, edit, publish, archive and delete listings',         false, 30),
  ('inquiries.reply',   'Reply to inquiries',         'inbox',     'Read and reply to customer conversations',                   false, 40),
  ('inquiries.manage',  'Manage inquiries',           'inbox',     'Assign, prioritise, resolve and close inquiries',            false, 50),
  ('customers.view',    'View customers',             'inbox',     'See the customer list and conversation history',             false, 60),
  ('customers.manage',  'Manage customers',           'inbox',     'Edit internal labels, notes and follow-up status',           false, 70),
  ('team.manage',       'Manage team',                'team',      'Invite, change roles and remove business team members',      false, 80),
  ('analytics.view',    'View business analytics',    'analytics', 'Open the business dashboard and metrics',                    false, 90),
  ('settings.manage',   'Manage business settings',   'settings',  'Change operating hours, messaging and business preferences', false, 100),
  ('posts.publish',     'Publish business posts',     'social',    'Create posts and promotions as the business',                false, 110),
  ('verification.apply','Apply for verification',     'profile',   'Submit and follow business verification applications',       false, 120),
  ('business.delete',   'Delete the business',        'settings',  'Permanently delete the business and its data',               true,  200)
on conflict (key) do nothing;

create table if not exists public.business_role_permissions (
  role           text not null check (role in ('owner', 'admin', 'manager', 'support', 'operator', 'catalog', 'analyst')),
  permission_key text not null references public.business_permissions (key) on delete cascade,
  primary key (role, permission_key)
);

insert into public.business_role_permissions (role, permission_key)
  select 'owner', key from public.business_permissions
on conflict do nothing;

insert into public.business_role_permissions (role, permission_key) values
  ('admin', 'profile.edit'), ('admin', 'profile.media'), ('admin', 'catalog.manage'),
  ('admin', 'inquiries.reply'), ('admin', 'inquiries.manage'), ('admin', 'customers.view'),
  ('admin', 'customers.manage'), ('admin', 'team.manage'), ('admin', 'analytics.view'),
  ('admin', 'settings.manage'), ('admin', 'posts.publish'), ('admin', 'verification.apply'),
  ('manager', 'profile.edit'), ('manager', 'profile.media'), ('manager', 'catalog.manage'),
  ('manager', 'inquiries.reply'), ('manager', 'inquiries.manage'), ('manager', 'customers.view'),
  ('manager', 'customers.manage'), ('manager', 'team.manage'), ('manager', 'analytics.view'),
  ('manager', 'settings.manage'), ('manager', 'posts.publish'), ('manager', 'verification.apply'),
  ('support', 'inquiries.reply'), ('support', 'inquiries.manage'), ('support', 'customers.view'),
  ('support', 'customers.manage'),
  ('operator', 'inquiries.reply'), ('operator', 'inquiries.manage'), ('operator', 'customers.view'),
  ('operator', 'customers.manage'),
  ('catalog', 'catalog.manage'), ('catalog', 'analytics.view'), ('catalog', 'posts.publish'),
  ('analyst', 'analytics.view')
on conflict do nothing;

-- Per-member overrides. Only used to *narrow* or extend inside the platform's
-- business permission catalog; owner rows are never overridable.
create table if not exists public.business_member_permissions (
  business_id    uuid not null,
  user_id        uuid not null,
  permission_key text not null references public.business_permissions (key) on delete cascade,
  granted        boolean not null,
  granted_by     uuid references public.profiles (id) on delete set null,
  granted_at     timestamptz not null default now(),
  primary key (business_id, user_id, permission_key),
  foreign key (business_id, user_id) references public.business_members (business_id, user_id) on delete cascade
);

-- Role vocabulary: existing owner/manager/operator values keep working.
alter table public.business_members drop constraint if exists business_members_role_check;
alter table public.business_members add constraint business_members_role_check
  check (role in ('owner', 'admin', 'manager', 'support', 'operator', 'catalog', 'analyst'));
alter table public.business_members add column if not exists status text not null default 'active'
  check (status in ('active', 'suspended'));
alter table public.business_members add column if not exists last_active_at timestamptz;
alter table public.business_members add column if not exists updated_at timestamptz not null default now();

create or replace function public.has_business_permission(p_business_id uuid, p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_status text;
  v_override boolean;
  v_owner_only boolean;
begin
  if v_uid is null or p_business_id is null then
    return false;
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.account_status = 'active') then
    return false;
  end if;
  select m.role, m.status into v_role, v_status
    from public.business_members m
   where m.business_id = p_business_id and m.user_id = v_uid;
  if v_role is null or v_status <> 'active' then
    return false;
  end if;
  if v_role = 'owner' then
    return true;
  end if;
  select b.owner_only into v_owner_only from public.business_permissions b where b.key = p_permission;
  if coalesce(v_owner_only, false) then
    return false;
  end if;
  select mp.granted into v_override
    from public.business_member_permissions mp
   where mp.business_id = p_business_id and mp.user_id = v_uid and mp.permission_key = p_permission;
  if v_override is not null then
    return v_override;
  end if;
  return exists (
    select 1 from public.business_role_permissions rp
     where rp.role = v_role and rp.permission_key = p_permission
  );
end;
$$;

create or replace function public.business_permissions_for(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_keys text[] := array[]::text[];
begin
  if public.is_business_member(p_business_id) then
    select coalesce(array_agg(b.key order by b.sort_order), array[]::text[]) into v_keys
      from public.business_permissions b
     where public.has_business_permission(p_business_id, b.key);
  end if;
  return to_jsonb(v_keys);
end;
$$;

-- Direct writes to membership are never allowed from a client session.
create or replace function public.guard_business_member_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.privileged_write_enabled() or current_user not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Business membership changes must go through the business administration functions'
    using errcode = '42501';
end;
$$;
drop trigger if exists business_members_guard on public.business_members;
create trigger business_members_guard before insert or update or delete on public.business_members
  for each row execute function public.guard_business_member_write();

create or replace function public.guard_business_member_permission_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.privileged_write_enabled() or current_user not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Business permission changes must go through the business administration functions'
    using errcode = '42501';
end;
$$;
drop trigger if exists business_member_permissions_guard on public.business_member_permissions;
create trigger business_member_permissions_guard before insert or update or delete on public.business_member_permissions
  for each row execute function public.guard_business_member_permission_write();

alter table public.business_permissions         enable row level security;
alter table public.business_role_permissions    enable row level security;
alter table public.business_member_permissions  enable row level security;

revoke all on public.business_permissions, public.business_role_permissions,
  public.business_member_permissions from anon, authenticated;
grant select on public.business_permissions, public.business_role_permissions to authenticated;
grant select on public.business_member_permissions to authenticated;

drop policy if exists business_permissions_read on public.business_permissions;
create policy business_permissions_read on public.business_permissions for select to authenticated using (true);
drop policy if exists business_role_permissions_read on public.business_role_permissions;
create policy business_role_permissions_read on public.business_role_permissions for select to authenticated using (true);
drop policy if exists business_member_permissions_read on public.business_member_permissions;
create policy business_member_permissions_read on public.business_member_permissions for select to authenticated
  using (user_id = auth.uid() or public.has_business_permission(business_id, 'team.manage'));

-- ---------------------------------------------------------------------------
-- 2. Business profile: professional fields, visibility, status
-- ---------------------------------------------------------------------------
alter table public.businesses
  add column if not exists status text not null default 'open',
  add column if not exists social_links jsonb not null default '{}'::jsonb,
  add column if not exists visibility jsonb not null default
    '{"show_email":true,"show_phone":false,"show_address":true,"show_working_hours":true,"show_location":true,"show_social_links":true,"listed":true,"accept_messages":true,"public_catalog":true}'::jsonb,
  add column if not exists accepts_inquiries boolean not null default true,
  add column if not exists response_note text,
  add column if not exists followers_count int not null default 0,
  add column if not exists catalog_updated_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'businesses_status_check') then
    alter table public.businesses add constraint businesses_status_check
      check (status in ('open', 'temporarily_closed', 'closed'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'businesses_response_note_len') then
    alter table public.businesses add constraint businesses_response_note_len
      check (response_note is null or char_length(response_note) <= 200);
  end if;
end $$;

create or replace function public.guard_business_privileged_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.privileged_write_enabled() or current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.created_by is distinct from old.created_by
     or new.is_verified is distinct from old.is_verified
     or new.verified_at is distinct from old.verified_at
     or new.followers_count is distinct from old.followers_count then
    raise exception 'This business field can only be changed by BubbleApp administration'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists businesses_guard on public.businesses;
create trigger businesses_guard before update on public.businesses
  for each row execute function public.guard_business_privileged_columns();

-- Private contact fields are no longer readable through PostgREST for everyone.
-- Members read them through business_profile_full(); visitors get a filtered view.
revoke select on public.businesses from anon, authenticated;
grant select (id, created_by, name, username, logo_url, cover_url, description, category, website,
              location, working_hours, greeting_message, away_message, is_setup_complete,
              is_verified, verified_at, status, social_links, visibility, accepts_inquiries,
              response_note, followers_count, catalog_updated_at, created_at, updated_at)
  on public.businesses to authenticated;

drop policy if exists businesses_select on public.businesses;
create policy businesses_select on public.businesses for select to authenticated using (
  public.is_business_member(id)
  or (is_setup_complete and coalesce((visibility ->> 'listed')::boolean, true))
  or public.has_permission('users.read')
);
drop policy if exists businesses_update_managers on public.businesses;
drop policy if exists businesses_update_perm on public.businesses;
create policy businesses_update_perm on public.businesses for update to authenticated
  using (public.has_business_permission(id, 'profile.edit'))
  with check (public.has_business_permission(id, 'profile.edit'));

create or replace function public.business_badge_visible(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select b.is_verified from public.businesses b where b.id = p_business_id), false);
$$;

-- ---------------------------------------------------------------------------
-- 3. Business team: invites, role changes, custom permissions
-- ---------------------------------------------------------------------------
create table if not exists public.business_team_invites (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses (id) on delete cascade,
  invited_user_id uuid not null references public.profiles (id) on delete cascade,
  invited_by      uuid references public.profiles (id) on delete set null,
  role            text not null check (role in ('admin', 'manager', 'support', 'operator', 'catalog', 'analyst')),
  note            text check (note is null or char_length(note) <= 500),
  status          text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired')),
  expires_at      timestamptz not null default (now() + interval '7 days'),
  responded_at    timestamptz,
  created_at      timestamptz not null default now()
);
create unique index if not exists business_invites_one_pending
  on public.business_team_invites (business_id, invited_user_id) where status = 'pending';
create index if not exists business_invites_user_idx
  on public.business_team_invites (invited_user_id, status);
alter table public.business_team_invites enable row level security;
revoke all on public.business_team_invites from anon, authenticated;
grant select on public.business_team_invites to authenticated;

drop policy if exists business_invites_select on public.business_team_invites;
create policy business_invites_select on public.business_team_invites for select to authenticated
  using (
    invited_user_id = auth.uid()
    or public.has_business_permission(business_id, 'team.manage')
    or public.has_permission('users.read')
  );

create or replace function public.business_team_invite(
  p_business_id uuid,
  p_username text,
  p_role text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_target uuid;
  v_id uuid;
  v_business_name text;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if not public.has_business_permission(p_business_id, 'team.manage') then
    raise exception 'Permission denied: team.manage' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('admin', 'manager', 'support', 'operator', 'catalog', 'analyst') then
    raise exception 'Invalid business role';
  end if;
  select id into v_target from public.profiles
   where lower(username) = lower(trim(coalesce(p_username, ''))) and account_status = 'active';
  if v_target is null then
    raise exception 'No active BubbleApp account found with that username';
  end if;
  if v_target = v_uid then
    raise exception 'You cannot invite yourself';
  end if;
  if exists (select 1 from public.business_members where business_id = p_business_id and user_id = v_target) then
    raise exception 'This account is already a member of the business';
  end if;
  if exists (select 1 from public.business_team_invites
              where business_id = p_business_id and invited_user_id = v_target and status = 'pending') then
    raise exception 'This account already has a pending invitation';
  end if;

  insert into public.business_team_invites (business_id, invited_user_id, invited_by, role, note)
  values (p_business_id, v_target, v_uid, p_role, nullif(trim(coalesce(p_note, '')), ''))
  returning id into v_id;

  select name into v_business_name from public.businesses where id = p_business_id;
  perform public.notify_user(
    v_target, 'business_invite', 'Business team invitation',
    'You were invited to join ' || coalesce(v_business_name, 'a business') || ' as ' || p_role,
    jsonb_build_object('business_id', p_business_id, 'invite_id', v_id, 'role', p_role),
    'business_invite:' || v_id::text);
  perform public.write_audit('business.team.invite', 'business', p_business_id::text,
    jsonb_build_object('user_id', v_target, 'role', p_role, 'invite_id', v_id));
  return v_id;
end;
$$;

create or replace function public.business_invite_respond(p_invite_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite public.business_team_invites%rowtype;
  v_business_name text;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  select * into v_invite from public.business_team_invites where id = p_invite_id for update;
  if not found or v_invite.invited_user_id <> v_uid then
    raise exception 'Invitation not found' using errcode = '42501';
  end if;
  if v_invite.status <> 'pending' then
    raise exception 'This invitation is no longer open';
  end if;
  if v_invite.expires_at < now() then
    update public.business_team_invites set status = 'expired', responded_at = now() where id = p_invite_id;
    raise exception 'This invitation has expired';
  end if;

  if p_accept then
    perform set_config('bubble.privileged', 'on', true);
    insert into public.business_members (business_id, user_id, role, added_by)
    values (v_invite.business_id, v_uid, v_invite.role, v_invite.invited_by)
    on conflict (business_id, user_id) do update set role = excluded.role, status = 'active';
    perform set_config('bubble.privileged', 'off', true);
    update public.business_team_invites set status = 'accepted', responded_at = now() where id = p_invite_id;
  else
    update public.business_team_invites set status = 'declined', responded_at = now() where id = p_invite_id;
  end if;

  select name into v_business_name from public.businesses where id = v_invite.business_id;
  perform public.write_audit('business.team.' || case when p_accept then 'accept' else 'decline' end,
    'business', v_invite.business_id::text, jsonb_build_object('invite_id', p_invite_id));
  if v_invite.invited_by is not null then
    perform public.notify_user(
      v_invite.invited_by, 'business_team_update', 'Invitation ' || case when p_accept then 'accepted' else 'declined' end,
      coalesce((select 'A teammate responded for ' || v_business_name), 'A business invitation was answered'),
      jsonb_build_object('business_id', v_invite.business_id, 'accepted', p_accept),
      'business_invite_response:' || p_invite_id::text);
  end if;
end;
$$;

create or replace function public.business_team_set_role(p_business_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current text;
begin
  if not public.has_business_permission(p_business_id, 'team.manage') then
    raise exception 'Permission denied: team.manage' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('admin', 'manager', 'support', 'operator', 'catalog', 'analyst') then
    raise exception 'Invalid business role';
  end if;
  select role into v_current from public.business_members
   where business_id = p_business_id and user_id = p_user_id;
  if v_current is null then
    raise exception 'This account is not a business member';
  end if;
  if v_current = 'owner' then
    raise exception 'The business owner role cannot be changed here' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501';
  end if;
  perform set_config('bubble.privileged', 'on', true);
  update public.business_members
     set role = p_role, updated_at = now()
   where business_id = p_business_id and user_id = p_user_id;
  -- Role change invalidates any custom overrides that were granted for the old role.
  delete from public.business_member_permissions
   where business_id = p_business_id and user_id = p_user_id;
  perform set_config('bubble.privileged', 'off', true);
  perform public.write_audit('business.team.role', 'business', p_business_id::text,
    jsonb_build_object('user_id', p_user_id, 'from', v_current, 'to', p_role));
  perform public.notify_user(
    p_user_id, 'business_team_update', 'Business role updated',
    'Your role is now ' || p_role,
    jsonb_build_object('business_id', p_business_id, 'role', p_role),
    'business_role:' || p_business_id::text || ':' || p_user_id::text || ':' || p_role);
end;
$$;

create or replace function public.business_team_remove(p_business_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select role into v_role from public.business_members
   where business_id = p_business_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'This account is not a business member';
  end if;
  if v_role = 'owner' then
    raise exception 'The business owner cannot be removed' using errcode = '42501';
  end if;
  if p_user_id <> auth.uid() and not public.has_business_permission(p_business_id, 'team.manage') then
    raise exception 'Permission denied: team.manage' using errcode = '42501';
  end if;
  perform set_config('bubble.privileged', 'on', true);
  delete from public.business_members where business_id = p_business_id and user_id = p_user_id;
  perform set_config('bubble.privileged', 'off', true);
  perform public.write_audit('business.team.remove', 'business', p_business_id::text,
    jsonb_build_object('user_id', p_user_id, 'role', v_role));
  perform public.notify_user(
    p_user_id, 'business_team_update', 'Removed from a business team',
    'Your access to the business was revoked',
    jsonb_build_object('business_id', p_business_id),
    'business_removed:' || p_business_id::text || ':' || p_user_id::text);
end;
$$;

create or replace function public.business_team_set_permission(
  p_business_id uuid,
  p_user_id uuid,
  p_permission text,
  p_granted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if not public.has_business_permission(p_business_id, 'team.manage') then
    raise exception 'Permission denied: team.manage' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot change your own permissions' using errcode = '42501';
  end if;
  if not exists (select 1 from public.business_permissions b where b.key = p_permission and not b.owner_only) then
    raise exception 'Unknown business permission';
  end if;
  select role into v_role from public.business_members
   where business_id = p_business_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'This account is not a business member';
  end if;
  if v_role = 'owner' then
    raise exception 'The business owner always keeps full access' using errcode = '42501';
  end if;
  if p_granted and not public.has_business_permission(p_business_id, p_permission) then
    raise exception 'You cannot grant a permission you do not hold' using errcode = '42501';
  end if;
  perform set_config('bubble.privileged', 'on', true);
  insert into public.business_member_permissions (business_id, user_id, permission_key, granted, granted_by)
  values (p_business_id, p_user_id, p_permission, p_granted, auth.uid())
  on conflict (business_id, user_id, permission_key) do update
    set granted = excluded.granted, granted_by = excluded.granted_by, granted_at = now();
  perform set_config('bubble.privileged', 'off', true);
  perform public.write_audit('business.team.permission', 'business', p_business_id::text,
    jsonb_build_object('user_id', p_user_id, 'permission', p_permission, 'granted', p_granted));
  perform public.notify_user(
    p_user_id, 'business_team_update', 'Business permissions updated',
    (case when p_granted then 'Granted: ' else 'Revoked: ' end) || p_permission,
    jsonb_build_object('business_id', p_business_id, 'permission', p_permission, 'granted', p_granted),
    'business_perm:' || p_business_id::text || ':' || p_user_id::text || ':' || p_permission || ':' || p_granted::text);
end;
$$;

create or replace function public.business_team_list(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_can_manage boolean := public.has_business_permission(p_business_id, 'team.manage');
begin
  if not public.is_business_member(p_business_id) then
    raise exception 'Not a member of this business' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'role', m.role,
        'status', m.status,
        'joined_at', m.created_at,
        'display_name', p.display_name,
        'username', p.username,
        'avatar_url', p.avatar_url,
        'is_verified', p.is_verified,
        'permissions', coalesce((
          select jsonb_agg(b.key order by b.sort_order)
            from public.business_permissions b
           where (
             m.role = 'owner'
             or (
               not b.owner_only
               and coalesce(
                 (select mp.granted from public.business_member_permissions mp
                   where mp.business_id = m.business_id and mp.user_id = m.user_id
                     and mp.permission_key = b.key),
                 exists (select 1 from public.business_role_permissions rp
                          where rp.role = m.role and rp.permission_key = b.key)
               )
             )
           )
        ), '[]'::jsonb)
      ) order by case m.role when 'owner' then 0 when 'admin' then 1 when 'manager' then 2 else 3 end, p.display_name)
      from public.business_members m
      join public.profiles p on p.id = m.user_id
      where m.business_id = p_business_id
    ), '[]'::jsonb),
    'invites', case when v_can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'role', i.role, 'status', i.status, 'created_at', i.created_at,
        'expires_at', i.expires_at, 'display_name', p.display_name, 'username', p.username))
        from public.business_team_invites i
        join public.profiles p on p.id = i.invited_user_id
       where i.business_id = p_business_id and i.status = 'pending'
    ), '[]'::jsonb) else '[]'::jsonb end,
    'can_manage', v_can_manage,
    'permission_catalog', coalesce((
      select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'category', category,
                                          'owner_only', owner_only, 'description', description)
                       order by sort_order)
        from public.business_permissions
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.business_team_revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.business_team_invites%rowtype;
begin
  select * into v_invite from public.business_team_invites where id = p_invite_id;
  if not found then
    raise exception 'Invitation not found';
  end if;
  if not public.has_business_permission(v_invite.business_id, 'team.manage') then
    raise exception 'Permission denied: team.manage' using errcode = '42501';
  end if;
  update public.business_team_invites set status = 'revoked', responded_at = now()
   where id = p_invite_id and status = 'pending';
  perform public.write_audit('business.team.invite_revoke', 'business', v_invite.business_id::text,
    jsonb_build_object('invite_id', p_invite_id));
end;
$$;

create or replace function public.my_business_invites()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'business_id', i.business_id, 'role', i.role, 'note', i.note,
    'created_at', i.created_at, 'expires_at', i.expires_at,
    'business_name', b.name, 'business_username', b.username, 'business_logo', b.logo_url,
    'business_verified', b.is_verified, 'invited_by', p.display_name)), '[]'::jsonb)
  from public.business_team_invites i
  join public.businesses b on b.id = i.business_id
  left join public.profiles p on p.id = i.invited_by
  where i.invited_user_id = auth.uid() and i.status = 'pending' and i.expires_at > now();
$$;

-- ---------------------------------------------------------------------------
-- 4. Catalog: professional listings, statuses, validation
-- ---------------------------------------------------------------------------
alter table public.business_catalog_items
  add column if not exists status text not null default 'published',
  add column if not exists category text,
  add column if not exists gallery jsonb not null default '[]'::jsonb,
  add column if not exists stock_quantity int,
  add column if not exists external_url text,
  add column if not exists variants jsonb not null default '[]'::jsonb,
  add column if not exists view_count bigint not null default 0,
  add column if not exists published_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists created_by uuid references public.profiles (id) on delete set null,
  add column if not exists updated_by uuid references public.profiles (id) on delete set null,
  add column if not exists share_count int not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'business_catalog_status_check') then
    alter table public.business_catalog_items add constraint business_catalog_status_check
      check (status in ('draft', 'published', 'archived', 'out_of_stock'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'business_catalog_kind_check') then
    alter table public.business_catalog_items drop constraint if exists business_catalog_items_kind_check;
    alter table public.business_catalog_items add constraint business_catalog_kind_check
      check (kind in ('product', 'service', 'digital'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'business_catalog_stock_check') then
    alter table public.business_catalog_items add constraint business_catalog_stock_check
      check (stock_quantity is null or stock_quantity >= 0);
  end if;
end $$;
update public.business_catalog_items set status = case when is_active then 'published' else 'archived' end
 where status is null or (status = 'published' and is_active = false);
update public.business_catalog_items set published_at = created_at where published_at is null and status = 'published';
alter table public.business_catalog_items alter column status set default 'draft';
create index if not exists business_catalog_public_idx
  on public.business_catalog_items (business_id, status, created_at desc);

create or replace function public.sync_business_catalog_status()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.is_active := (new.status = 'published');
  if new.status = 'published' then
    new.published_at := coalesce(new.published_at, now());
    new.archived_at := null;
  elsif new.status = 'archived' then
    new.archived_at := coalesce(new.archived_at, now());
  end if;
  new.updated_by := coalesce(new.updated_by, auth.uid());
  return new;
end;
$$;
drop trigger if exists business_catalog_status_sync on public.business_catalog_items;
create trigger business_catalog_status_sync before insert or update on public.business_catalog_items
  for each row execute function public.sync_business_catalog_status();

drop policy if exists catalog_select on public.business_catalog_items;
create policy catalog_select on public.business_catalog_items for select to authenticated using (
  public.is_business_member(business_id)
  or (
    status = 'published'
    and exists (
      select 1 from public.businesses b
      where b.id = business_id
        and b.is_setup_complete
        and coalesce((b.visibility ->> 'public_catalog')::boolean, true)
    )
  )
);
drop policy if exists catalog_write on public.business_catalog_items;
create policy catalog_write on public.business_catalog_items for all to authenticated
  using (public.has_business_permission(business_id, 'catalog.manage'))
  with check (public.has_business_permission(business_id, 'catalog.manage'));

-- ---------------------------------------------------------------------------
-- 5. Real business metrics: events and followers (no fabricated numbers)
-- ---------------------------------------------------------------------------
create table if not exists public.business_events (
  id          bigint generated always as identity primary key,
  business_id uuid not null references public.businesses (id) on delete cascade,
  kind        text not null check (kind in ('profile_view', 'catalog_view', 'inquiry_created',
                                            'inquiry_resolved', 'follow', 'post_published')),
  actor_id    uuid references public.profiles (id) on delete set null,
  subject_id  uuid,
  day         date not null default ((now() at time zone 'utc')::date),
  created_at  timestamptz not null default now()
);
create index if not exists business_events_business_day on public.business_events (business_id, day desc);
create unique index if not exists business_events_dedupe on public.business_events
  (business_id, kind, actor_id, coalesce(subject_id, '00000000-0000-0000-0000-000000000000'::uuid), day)
  where actor_id is not null;
alter table public.business_events enable row level security;
revoke all on public.business_events from anon, authenticated;
grant select on public.business_events to authenticated;
drop policy if exists business_events_read on public.business_events;
create policy business_events_read on public.business_events for select to authenticated
  using (public.has_business_permission(business_id, 'analytics.view'));

create table if not exists public.business_followers (
  business_id uuid not null references public.businesses (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (business_id, user_id)
);
create index if not exists business_followers_user_idx on public.business_followers (user_id);
alter table public.business_followers enable row level security;
revoke all on public.business_followers from anon, authenticated;
grant select on public.business_followers to authenticated;
drop policy if exists business_followers_read on public.business_followers;
create policy business_followers_read on public.business_followers for select to authenticated
  using (user_id = auth.uid() or public.has_business_permission(business_id, 'analytics.view'));

create or replace function public.sync_business_follower_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.businesses set followers_count = followers_count + 1 where id = new.business_id;
    return new;
  end if;
  update public.businesses set followers_count = greatest(followers_count - 1, 0) where id = old.business_id;
  return old;
end;
$$;
drop trigger if exists business_followers_count on public.business_followers;
create trigger business_followers_count after insert or delete on public.business_followers
  for each row execute function public.sync_business_follower_count();

create or replace function public.business_record_event(
  p_business_id uuid,
  p_kind text,
  p_subject_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_inserted int := 0;
  v_item public.business_catalog_items%rowtype;
begin
  if v_uid is null then
    return false;
  end if;
  if p_kind not in ('profile_view', 'catalog_view') then
    raise exception 'Unsupported business event';
  end if;
  if not exists (select 1 from public.businesses b where b.id = p_business_id and b.is_setup_complete) then
    return false;
  end if;
  if p_kind = 'catalog_view' then
    select * into v_item from public.business_catalog_items
     where id = p_subject_id and business_id = p_business_id and status = 'published';
    if not found then
      return false;
    end if;
  end if;

  insert into public.business_events (business_id, kind, actor_id, subject_id)
  values (p_business_id, p_kind, v_uid, p_subject_id)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted > 0 and p_kind = 'catalog_view' then
    update public.business_catalog_items set view_count = view_count + 1 where id = p_subject_id;
  end if;
  return v_inserted > 0;
end;
$$;

create or replace function public.business_follow(p_business_id uuid, p_follow boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if exists (select 1 from public.business_members where business_id = p_business_id and user_id = v_uid) then
    raise exception 'Business members cannot follow their own business';
  end if;
  if not exists (select 1 from public.businesses b
                  where b.id = p_business_id and b.is_setup_complete
                    and coalesce((b.visibility ->> 'listed')::boolean, true)) then
    raise exception 'Business not available';
  end if;
  if p_follow then
    insert into public.business_followers (business_id, user_id) values (p_business_id, v_uid)
    on conflict do nothing;
    insert into public.business_events (business_id, kind, actor_id) values (p_business_id, 'follow', v_uid)
    on conflict do nothing;
  else
    delete from public.business_followers where business_id = p_business_id and user_id = v_uid;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Business profile reads/writes (server-validated)
-- ---------------------------------------------------------------------------
create or replace function public.business_my_businesses()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'name', b.name, 'username', b.username, 'category', b.category,
    'description', b.description, 'logo_url', b.logo_url, 'cover_url', b.cover_url,
    'is_verified', b.is_verified, 'is_setup_complete', b.is_setup_complete,
    'status', b.status, 'followers_count', b.followers_count,
    'role', m.role, 'member_status', m.status,
    'permissions', public.business_permissions_for(b.id),
    'open_inquiries', (select count(*) from public.business_inquiries i
                        where i.business_id = b.id and i.status in ('new', 'open')),
    'pending_invites', (select count(*) from public.business_team_invites ti
                         where ti.business_id = b.id and ti.status = 'pending')
  ) order by b.name), '[]'::jsonb)
    into v_result
    from public.business_members m
    join public.businesses b on b.id = m.business_id
    where m.user_id = auth.uid() and m.status = 'active';
  return coalesce(v_result, '[]'::jsonb);
end;
$$;

create or replace function public.business_public_profile(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b public.businesses%rowtype;
  v_member boolean;
  v_visibility jsonb;
begin
  select * into b from public.businesses where id = p_business_id;
  if not found then
    return null;
  end if;
  v_member := public.is_business_member(p_business_id);
  v_visibility := coalesce(b.visibility, '{}'::jsonb);
  if not v_member and (not b.is_setup_complete or not coalesce((v_visibility ->> 'listed')::boolean, true)) then
    return null;
  end if;

  return jsonb_build_object(
    'id', b.id,
    'name', b.name,
    'username', b.username,
    'logo_url', b.logo_url,
    'cover_url', b.cover_url,
    'description', b.description,
    'category', b.category,
    'website', b.website,
    'status', b.status,
    'is_setup_complete', b.is_setup_complete,
    'is_verified', b.is_verified,
    'verified_at', b.verified_at,
    'followers_count', b.followers_count,
    'response_note', b.response_note,
    'accepts_inquiries', b.accepts_inquiries
      and coalesce((v_visibility ->> 'accept_messages')::boolean, true),
    'social_links', case when coalesce((v_visibility ->> 'show_social_links')::boolean, true)
                         then coalesce(b.social_links, '{}'::jsonb) else '{}'::jsonb end,
    'working_hours', case when coalesce((v_visibility ->> 'show_working_hours')::boolean, true)
                          then b.working_hours else '{}'::jsonb end,
    'location', case when coalesce((v_visibility ->> 'show_location')::boolean, true)
                     then b.location else null end,
    'address', case when coalesce((v_visibility ->> 'show_address')::boolean, true)
                    then b.address else null end,
    'contact_email', case when v_member or coalesce((v_visibility ->> 'show_email')::boolean, true)
                          then b.business_email else null end,
    'contact_phone', case when v_member or coalesce((v_visibility ->> 'show_phone')::boolean, false)
                          then b.business_phone else null end,
    'greeting_message', case when coalesce((v_visibility ->> 'accept_messages')::boolean, true)
                             then b.greeting_message else null end,
    'member_since', b.created_at,
    'catalog_count', (select count(*) from public.business_catalog_items ci
                       where ci.business_id = b.id and ci.status = 'published'),
    'is_member', v_member,
    'is_following', exists (select 1 from public.business_followers f
                             where f.business_id = b.id and f.user_id = auth.uid()),
    'my_role', (select role from public.business_members mm
                 where mm.business_id = b.id and mm.user_id = auth.uid()),
    'my_permissions', public.business_permissions_for(b.id)
  );
end;
$$;

create or replace function public.business_update_profile(p_business_id uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.businesses%rowtype;
  v_username text;
  v_email text;
  v_website text;
begin
  if not public.has_business_permission(p_business_id, 'profile.edit') then
    raise exception 'Permission denied: profile.edit' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Invalid profile update';
  end if;
  select * into b from public.businesses where id = p_business_id for update;

  if p_patch ? 'name' then
    if char_length(trim(coalesce(p_patch ->> 'name', ''))) not between 2 and 80 then
      raise exception 'Business name must be 2-80 characters';
    end if;
  end if;
  if p_patch ? 'username' then
    v_username := lower(trim(coalesce(p_patch ->> 'username', '')));
    if v_username !~ '^[a-z0-9_]{3,32}$' then
      raise exception 'Business username must be 3-32 characters: letters, numbers or underscores';
    end if;
    if exists (select 1 from public.businesses x where lower(x.username) = v_username and x.id <> p_business_id) then
      raise exception 'This business username is already taken';
    end if;
  end if;
  if p_patch ? 'category' and char_length(trim(coalesce(p_patch ->> 'category', ''))) not between 2 and 60 then
    raise exception 'Business category is required';
  end if;
  if p_patch ? 'business_email' then
    v_email := lower(trim(coalesce(p_patch ->> 'business_email', '')));
    if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'A valid business email is required';
    end if;
  end if;
  if p_patch ? 'website' then
    v_website := nullif(trim(coalesce(p_patch ->> 'website', '')), '');
    if v_website is not null and v_website !~* '^https?://' then
      raise exception 'Website must start with http:// or https://';
    end if;
  end if;
  if p_patch ? 'description' and char_length(coalesce(p_patch ->> 'description', '')) > 1000 then
    raise exception 'Description is too long (max 1000 characters)';
  end if;
  if p_patch ? 'greeting_message' and char_length(coalesce(p_patch ->> 'greeting_message', '')) > 500 then
    raise exception 'Greeting message is too long (max 500 characters)';
  end if;
  if p_patch ? 'away_message' and char_length(coalesce(p_patch ->> 'away_message', '')) > 500 then
    raise exception 'Away message is too long (max 500 characters)';
  end if;
  if p_patch ? 'response_note' and char_length(coalesce(p_patch ->> 'response_note', '')) > 200 then
    raise exception 'Response note is too long (max 200 characters)';
  end if;
  if p_patch ? 'status' and (p_patch ->> 'status') not in ('open', 'temporarily_closed', 'closed') then
    raise exception 'Invalid business status';
  end if;
  if p_patch ? 'working_hours' and jsonb_typeof(p_patch -> 'working_hours') <> 'object' then
    raise exception 'Working hours must be an object keyed by weekday';
  end if;
  if p_patch ? 'location' and jsonb_typeof(p_patch -> 'location') <> 'object' then
    raise exception 'Location must be an object';
  end if;
  if p_patch ? 'social_links' then
    if jsonb_typeof(p_patch -> 'social_links') <> 'object' then
      raise exception 'Social links must be an object';
    end if;
    if exists (
      select 1 from jsonb_each_text(p_patch -> 'social_links') as s(k, v)
       where k not in ('instagram', 'facebook', 'tiktok', 'x', 'linkedin', 'youtube', 'threads')
          or char_length(v) > 300
    ) then
      raise exception 'Unsupported social link';
    end if;
  end if;
  if p_patch ? 'visibility' then
    if jsonb_typeof(p_patch -> 'visibility') <> 'object' then
      raise exception 'Visibility must be an object';
    end if;
    if exists (
      select 1 from jsonb_each(p_patch -> 'visibility') as s(k, v)
       where k not in ('show_email', 'show_phone', 'show_address', 'show_working_hours',
                       'show_location', 'show_social_links', 'listed', 'accept_messages', 'public_catalog')
          or jsonb_typeof(v) <> 'boolean'
    ) then
      raise exception 'Unsupported visibility setting';
    end if;
  end if;

  update public.businesses set
    name = coalesce(nullif(trim(p_patch ->> 'name'), ''), name),
    username = coalesce(v_username, username),
    logo_url = case when p_patch ? 'logo_url' then nullif(trim(p_patch ->> 'logo_url'), '') else logo_url end,
    cover_url = case when p_patch ? 'cover_url' then nullif(trim(p_patch ->> 'cover_url'), '') else cover_url end,
    description = coalesce(p_patch ->> 'description', description),
    category = coalesce(nullif(trim(p_patch ->> 'category'), ''), category),
    website = case when p_patch ? 'website' then v_website else website end,
    business_email = coalesce(v_email, business_email),
    business_phone = case when p_patch ? 'business_phone' then nullif(trim(p_patch ->> 'business_phone'), '') else business_phone end,
    address = case when p_patch ? 'address' then nullif(trim(p_patch ->> 'address'), '') else address end,
    location = case when p_patch ? 'location' then p_patch -> 'location' else location end,
    working_hours = case when p_patch ? 'working_hours' then p_patch -> 'working_hours' else working_hours end,
    greeting_message = case when p_patch ? 'greeting_message' then nullif(trim(p_patch ->> 'greeting_message'), '') else greeting_message end,
    away_message = case when p_patch ? 'away_message' then nullif(trim(p_patch ->> 'away_message'), '') else away_message end,
    status = coalesce(p_patch ->> 'status', status),
    social_links = case when p_patch ? 'social_links' then p_patch -> 'social_links' else social_links end,
    visibility = case when p_patch ? 'visibility' then visibility || (p_patch -> 'visibility') else visibility end,
    accepts_inquiries = coalesce((p_patch ->> 'accepts_inquiries')::boolean, accepts_inquiries),
    response_note = case when p_patch ? 'response_note' then nullif(trim(p_patch ->> 'response_note'), '') else response_note end,
    is_setup_complete = is_setup_complete or coalesce((p_patch ->> 'is_setup_complete')::boolean, false),
    updated_at = now()
  where id = p_business_id;

  perform public.write_audit('business.profile.update', 'business', p_business_id::text,
    jsonb_build_object('fields', (select jsonb_agg(k) from jsonb_object_keys(p_patch) as k)));

  select * into b from public.businesses where id = p_business_id;
  return jsonb_build_object(
    'id', b.id, 'name', b.name, 'username', b.username, 'logo_url', b.logo_url,
    'cover_url', b.cover_url, 'description', b.description, 'category', b.category,
    'website', b.website, 'business_email', b.business_email, 'business_phone', b.business_phone,
    'address', b.address, 'location', b.location, 'working_hours', b.working_hours,
    'greeting_message', b.greeting_message, 'away_message', b.away_message,
    'status', b.status, 'social_links', b.social_links, 'visibility', b.visibility,
    'accepts_inquiries', b.accepts_inquiries, 'response_note', b.response_note,
    'is_verified', b.is_verified, 'is_setup_complete', b.is_setup_complete,
    'followers_count', b.followers_count, 'category_updated_at', b.catalog_updated_at);
end;
$$;

create or replace function public.business_setup_progress(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b public.businesses%rowtype;
  v_missing text[] := array[]::text[];
  v_total int := 9;
  v_done int := 0;
begin
  if not public.is_business_member(p_business_id) then
    raise exception 'Not a member of this business' using errcode = '42501';
  end if;
  select * into b from public.businesses where id = p_business_id;
  v_done := 3; -- name, username and category are required at creation
  if char_length(b.description) >= 20 then v_done := v_done + 1; else v_missing := array_append(v_missing, 'Add a description of at least 20 characters'); end if;
  if b.logo_url is not null then v_done := v_done + 1; else v_missing := array_append(v_missing, 'Upload a business logo'); end if;
  if b.cover_url is not null then v_done := v_done + 1; else v_missing := array_append(v_missing, 'Upload a cover image'); end if;
  if coalesce(b.working_hours, '{}'::jsonb) <> '{}'::jsonb then v_done := v_done + 1; else v_missing := array_append(v_missing, 'Set your operating hours'); end if;
  if exists (select 1 from public.business_catalog_items ci where ci.business_id = b.id and ci.status = 'published') then
    v_done := v_done + 1;
  else
    v_missing := array_append(v_missing, 'Publish at least one catalog listing');
  end if;
  if b.is_verified then v_done := v_done + 1; else v_missing := array_append(v_missing, 'Complete business verification for the blue badge'); end if;
  return jsonb_build_object(
    'percent', round((v_done::numeric / v_total) * 100),
    'completed', v_done,
    'total', v_total,
    'missing', to_jsonb(v_missing),
    'is_verified', b.is_verified,
    'status', b.status
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Business analytics (only real, recorded data; unavailable metrics flagged)
-- ---------------------------------------------------------------------------
create or replace function public.business_analytics(p_business_id uuid, p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  v_since timestamptz := now() - make_interval(days => v_days);
  v_prev_since timestamptz := now() - make_interval(days => v_days * 2);
  v_answered int;
  v_total_inquiries int;
  v_avg numeric;
  v_business public.businesses%rowtype;
begin
  if not public.has_business_permission(p_business_id, 'analytics.view') then
    raise exception 'Permission denied: analytics.view' using errcode = '42501';
  end if;
  select * into v_business from public.businesses where id = p_business_id;

  select count(*) filter (where first_response_at is not null),
         count(*),
         round(avg(extract(epoch from (first_response_at - created_at)) / 60.0) filter (where first_response_at is not null), 1)
    into v_answered, v_total_inquiries, v_avg
    from public.business_inquiries
   where business_id = p_business_id and created_at >= v_since;

  return jsonb_build_object(
    'period_days', v_days,
    'generated_at', now(),
    'business', jsonb_build_object(
      'id', v_business.id, 'name', v_business.name, 'username', v_business.username,
      'is_verified', v_business.is_verified, 'is_setup_complete', v_business.is_setup_complete,
      'status', v_business.status, 'followers_count', v_business.followers_count
    ),
    'metrics', jsonb_build_object(
      'profile_views', (select count(*) from public.business_events e
                         where e.business_id = p_business_id and e.kind = 'profile_view' and e.created_at >= v_since),
      'catalog_views', (select count(*) from public.business_events e
                         where e.business_id = p_business_id and e.kind = 'catalog_view' and e.created_at >= v_since),
      'product_views', (select count(*) from public.business_events e
                         join public.business_catalog_items ci on ci.id = e.subject_id
                        where e.business_id = p_business_id and e.kind = 'catalog_view'
                          and ci.kind = 'product' and e.created_at >= v_since),
      'service_views', (select count(*) from public.business_events e
                         join public.business_catalog_items ci on ci.id = e.subject_id
                        where e.business_id = p_business_id and e.kind = 'catalog_view'
                          and ci.kind in ('service', 'digital') and e.created_at >= v_since),
      'conversations', (select count(distinct i.conversation_id) from public.business_inquiries i
                         where i.business_id = p_business_id and i.last_message_at >= v_since),
      'inquiries', v_total_inquiries,
      'new_inquiries', (select count(*) from public.business_inquiries i
                         where i.business_id = p_business_id and i.created_at >= v_since),
      'open_inquiries', (select count(*) from public.business_inquiries i
                          where i.business_id = p_business_id and i.status in ('new', 'open')),
      'resolved_inquiries', (select count(*) from public.business_inquiries i
                              where i.business_id = p_business_id and i.status = 'resolved'
                                and i.resolved_at >= v_since),
      'service_inquiries', (select count(*) from public.business_inquiries i
                             join public.business_catalog_items ci on ci.id = i.catalog_item_id
                            where i.business_id = p_business_id and ci.kind in ('service', 'digital')
                              and i.created_at >= v_since),
      'business_messages', (select count(*) from public.messages m
                             join public.conversations c on c.id = m.conversation_id
                            where c.business_id = p_business_id and m.created_at >= v_since
                              and m.deleted_at is null),
      'business_replies', (select count(*) from public.messages m
                            join public.conversations c on c.id = m.conversation_id
                           where c.business_id = p_business_id and m.created_at >= v_since
                             and m.sender_id is not null
                             and exists (select 1 from public.business_inquiries i
                                          where i.conversation_id = c.id and i.customer_id <> m.sender_id)),
      'customers', (select count(*) from public.business_customers bc where bc.business_id = p_business_id),
      'new_customers', (select count(*) from public.business_customers bc
                         where bc.business_id = p_business_id and bc.created_at >= v_since),
      'followers', v_business.followers_count,
      'catalog_items', (select count(*) from public.business_catalog_items ci where ci.business_id = p_business_id),
      'published_items', (select count(*) from public.business_catalog_items ci
                           where ci.business_id = p_business_id and ci.status = 'published'),
      'draft_items', (select count(*) from public.business_catalog_items ci
                       where ci.business_id = p_business_id and ci.status = 'draft'),
      'archived_items', (select count(*) from public.business_catalog_items ci
                          where ci.business_id = p_business_id and ci.status = 'archived'),
      'posts', (select count(*) from public.posts p
                 where p.business_id = p_business_id and p.hidden_at is null and p.created_at >= v_since),
      'post_reactions', (select count(*) from public.post_reactions r
                          join public.posts p on p.id = r.post_id
                         where p.business_id = p_business_id and p.hidden_at is null
                           and p.created_at >= v_since),
      'post_comments', (select count(*) from public.comments cm
                         join public.posts p on p.id = cm.post_id
                        where p.business_id = p_business_id and p.hidden_at is null
                          and p.created_at >= v_since)
    ),
    'previous_period', jsonb_build_object(
      'profile_views', (select count(*) from public.business_events e
                         where e.business_id = p_business_id and e.kind = 'profile_view'
                           and e.created_at >= v_prev_since and e.created_at < v_since),
      'catalog_views', (select count(*) from public.business_events e
                         where e.business_id = p_business_id and e.kind = 'catalog_view'
                           and e.created_at >= v_prev_since and e.created_at < v_since),
      'inquiries', (select count(*) from public.business_inquiries i
                     where i.business_id = p_business_id
                       and i.created_at >= v_prev_since and i.created_at < v_since)
    ),
    'response', jsonb_build_object(
      'available', v_answered > 0,
      'answered', v_answered,
      'unanswered', greatest(v_total_inquiries - v_answered, 0),
      'avg_first_response_minutes', v_avg,
      'resolution_rate', case when v_total_inquiries = 0 then null
        else round(100.0 * (select count(*) from public.business_inquiries i
                             where i.business_id = p_business_id and i.created_at >= v_since
                               and i.status = 'resolved') / v_total_inquiries, 1) end
    ),
    'series', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', d::date,
        'profile_views', (select count(*) from public.business_events e
                           where e.business_id = p_business_id and e.kind = 'profile_view' and e.day = d::date),
        'catalog_views', (select count(*) from public.business_events e
                           where e.business_id = p_business_id and e.kind = 'catalog_view' and e.day = d::date),
        'inquiries', (select count(*) from public.business_inquiries i
                       where i.business_id = p_business_id and (i.created_at at time zone 'utc')::date = d::date)
      ) order by d)
      from generate_series((v_since at time zone 'utc')::date, (now() at time zone 'utc')::date, interval '1 day') as d
    ), '[]'::jsonb),
    'unavailable', jsonb_build_array(
      jsonb_build_object('metric', 'paid_ad_reach', 'reason', 'Paid advertising and billing are not implemented'),
      jsonb_build_object('metric', 'checkout_revenue', 'reason', 'In-app checkout is not implemented; catalog supports external links only')
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Catalog RPCs (validated on the server; no client-trusted business ids)
-- ---------------------------------------------------------------------------
create or replace function public.business_catalog_save(
  p_business_id uuid,
  p_item_id uuid default null,
  p_kind text default 'product',
  p_name text default null,
  p_description text default '',
  p_category text default null,
  p_price_minor integer default null,
  p_currency text default 'IDR',
  p_image_url text default null,
  p_gallery jsonb default '[]'::jsonb,
  p_status text default 'draft',
  p_stock_quantity integer default null,
  p_external_url text default null,
  p_variants jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_status text := coalesce(p_status, 'draft');
  v_currency text := upper(trim(coalesce(p_currency, 'IDR')));
begin
  if not public.has_business_permission(p_business_id, 'catalog.manage') then
    raise exception 'Permission denied: catalog.manage' using errcode = '42501';
  end if;
  if p_kind not in ('product', 'service', 'digital') then
    raise exception 'Invalid listing type';
  end if;
  if char_length(v_name) not between 1 and 120 then
    raise exception 'Listing name must be 1-120 characters';
  end if;
  if char_length(coalesce(p_description, '')) > 1000 then
    raise exception 'Listing description is too long (max 1000 characters)';
  end if;
  if p_category is not null and char_length(trim(p_category)) > 60 then
    raise exception 'Category is too long (max 60 characters)';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency must be a 3-letter ISO code';
  end if;
  if p_price_minor is not null and p_price_minor < 0 then
    raise exception 'Price cannot be negative';
  end if;
  if v_status not in ('draft', 'published', 'archived', 'out_of_stock') then
    raise exception 'Invalid listing status';
  end if;
  if p_stock_quantity is not null and p_stock_quantity < 0 then
    raise exception 'Stock cannot be negative';
  end if;
  if p_external_url is not null and trim(p_external_url) <> ''
     and trim(p_external_url) !~* '^https?://' then
    raise exception 'External link must start with http:// or https://';
  end if;
  if p_external_url is not null and char_length(p_external_url) > 2048 then
    raise exception 'External link is too long';
  end if;
  if jsonb_typeof(coalesce(p_gallery, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_gallery, '[]'::jsonb)) > 10 then
    raise exception 'Gallery must be an array of at most 10 images';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_gallery, '[]'::jsonb)) g
              where jsonb_typeof(g) <> 'string' or char_length(g #>> '{}') > 500) then
    raise exception 'Invalid gallery entry';
  end if;
  if jsonb_typeof(coalesce(p_variants, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_variants, '[]'::jsonb)) > 20 then
    raise exception 'Variants must be an array of at most 20 entries';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_variants, '[]'::jsonb)) v
              where jsonb_typeof(v) <> 'object'
                 or char_length(coalesce(v ->> 'name', '')) not between 1 and 60
                 or (v ? 'price_minor' and (v ->> 'price_minor')::numeric < 0)) then
    raise exception 'Every variant needs a name (1-60 chars) and a non-negative price';
  end if;

  if p_item_id is null then
    insert into public.business_catalog_items (
      business_id, kind, name, description, category, price_minor, currency, image_url,
      gallery, status, stock_quantity, external_url, variants, created_by, updated_by
    ) values (
      p_business_id, p_kind, v_name, coalesce(p_description, ''), nullif(trim(coalesce(p_category, '')), ''),
      p_price_minor, v_currency, nullif(trim(coalesce(p_image_url, '')), ''),
      coalesce(p_gallery, '[]'::jsonb), v_status, p_stock_quantity,
      nullif(trim(coalesce(p_external_url, '')), ''), coalesce(p_variants, '[]'::jsonb),
      auth.uid(), auth.uid()
    )
    returning id into v_id;
  else
    update public.business_catalog_items set
      kind = p_kind,
      name = v_name,
      description = coalesce(p_description, ''),
      category = nullif(trim(coalesce(p_category, '')), ''),
      price_minor = p_price_minor,
      currency = v_currency,
      image_url = nullif(trim(coalesce(p_image_url, '')), ''),
      gallery = coalesce(p_gallery, '[]'::jsonb),
      status = v_status,
      stock_quantity = p_stock_quantity,
      external_url = nullif(trim(coalesce(p_external_url, '')), ''),
      variants = coalesce(p_variants, '[]'::jsonb),
      updated_by = auth.uid()
    where id = p_item_id and business_id = p_business_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Listing not found in this business';
    end if;
  end if;

  update public.businesses set catalog_updated_at = now() where id = p_business_id;
  perform public.write_audit('business.catalog.save', 'business', p_business_id::text,
    jsonb_build_object('item_id', v_id, 'name', v_name, 'status', v_status, 'created', p_item_id is null));
  return v_id;
end;
$$;

create or replace function public.business_catalog_set_status(p_item_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
begin
  select business_id into v_business from public.business_catalog_items where id = p_item_id;
  if v_business is null then
    raise exception 'Listing not found';
  end if;
  if not public.has_business_permission(v_business, 'catalog.manage') then
    raise exception 'Permission denied: catalog.manage' using errcode = '42501';
  end if;
  if p_status not in ('draft', 'published', 'archived', 'out_of_stock') then
    raise exception 'Invalid listing status';
  end if;
  update public.business_catalog_items set status = p_status, updated_by = auth.uid() where id = p_item_id;
  update public.businesses set catalog_updated_at = now() where id = v_business;
  perform public.write_audit('business.catalog.status', 'business', v_business::text,
    jsonb_build_object('item_id', p_item_id, 'status', p_status));
end;
$$;

create or replace function public.business_catalog_delete(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_name text;
begin
  select business_id, name into v_business, v_name from public.business_catalog_items where id = p_item_id;
  if v_business is null then
    raise exception 'Listing not found';
  end if;
  if not public.has_business_permission(v_business, 'catalog.manage') then
    raise exception 'Permission denied: catalog.manage' using errcode = '42501';
  end if;
  delete from public.business_catalog_items where id = p_item_id;
  update public.businesses set catalog_updated_at = now() where id = v_business;
  perform public.write_audit('business.catalog.delete', 'business', v_business::text,
    jsonb_build_object('item_id', p_item_id, 'name', v_name));
end;
$$;

create or replace function public.business_catalog_share(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.business_catalog_items%rowtype;
  v_biz public.businesses%rowtype;
begin
  select * into v_item from public.business_catalog_items where id = p_item_id and status = 'published';
  if not found then
    raise exception 'Listing not found';
  end if;
  select * into v_biz from public.businesses where id = v_item.business_id;
  if not public.is_business_member(v_item.business_id)
     and (not v_biz.is_setup_complete or not coalesce((v_biz.visibility ->> 'public_catalog')::boolean, true)) then
    raise exception 'Listing not available';
  end if;
  update public.business_catalog_items set share_count = share_count + 1 where id = p_item_id;
  return jsonb_build_object(
    'id', v_item.id,
    'name', v_item.name,
    'kind', v_item.kind,
    'price_minor', v_item.price_minor,
    'currency', v_item.currency,
    'business_name', v_biz.name,
    'business_username', v_biz.username,
    'business_verified', v_biz.is_verified,
    'path', '/business/' || v_biz.id::text || '?item=' || v_item.id::text
  );
end;
$$;

create or replace function public.business_catalog_list(
  p_business_id uuid,
  p_search text default null,
  p_kind text default null,
  p_category text default null,
  p_status text default null,
  p_sort text default 'recent',
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  if not public.is_business_member(p_business_id) then
    raise exception 'Not a member of this business' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb)
    from (
      select ci.id, ci.business_id, ci.kind, ci.name, ci.description, ci.category, ci.price_minor,
             ci.currency, ci.image_url, ci.gallery, ci.variants, ci.status, ci.stock_quantity,
             ci.external_url, ci.view_count, ci.share_count, ci.is_active, ci.created_at, ci.updated_at
        from public.business_catalog_items ci
       where ci.business_id = p_business_id
         and (p_kind is null or ci.kind = p_kind)
         and (p_category is null or ci.category = p_category)
         and (p_status is null or ci.status = p_status)
         and (p_search is null or ci.name ilike '%' || p_search || '%'
              or ci.description ilike '%' || p_search || '%')
       order by case
         when p_sort = 'name' then ci.name
         when p_sort = 'price_low' then lpad(ci.price_minor::text, 12, '0')
         when p_sort = 'price_high' then lpad(ci.price_minor::text, 12, '0')
         else null end asc nulls last,
         case when p_sort = 'price_high' then ci.price_minor end desc,
         case when p_sort = 'views' then ci.view_count end desc,
         ci.created_at desc
       limit v_limit offset v_offset
    ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.business_catalog_public(
  p_business_id uuid,
  p_search text default null,
  p_kind text default null,
  p_category text default null,
  p_sort text default 'recent',
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_biz public.businesses%rowtype;
begin
  select * into v_biz from public.businesses where id = p_business_id;
  if not found or (not v_biz.is_setup_complete and not public.is_business_member(p_business_id))
     or (not public.is_business_member(p_business_id)
         and not coalesce((v_biz.visibility ->> 'public_catalog')::boolean, true)) then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb)
    from (
      select ci.id, ci.business_id, ci.kind, ci.name, ci.description, ci.category, ci.price_minor,
             ci.currency, ci.image_url, ci.gallery, ci.variants, ci.status, ci.stock_quantity,
             ci.external_url, ci.view_count, ci.created_at
        from public.business_catalog_items ci
       where ci.business_id = p_business_id
         and (ci.status = 'published' or public.is_business_member(p_business_id))
         and (p_kind is null or ci.kind = p_kind)
         and (p_category is null or ci.category = p_category)
         and (p_search is null or ci.name ilike '%' || p_search || '%'
              or ci.description ilike '%' || p_search || '%')
       order by case when p_sort = 'name' then ci.name end asc nulls last,
                case when p_sort = 'price_low' then ci.price_minor end asc nulls last,
                case when p_sort = 'price_high' then ci.price_minor end desc nulls last,
                case when p_sort = 'views' then ci.view_count end desc nulls last,
                ci.created_at desc
       limit v_limit offset v_offset
    ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.business_catalog_detail(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.business_catalog_items%rowtype;
  v_biz public.businesses%rowtype;
  v_member boolean;
begin
  select * into v_item from public.business_catalog_items where id = p_item_id;
  if not found then
    return null;
  end if;
  v_member := public.is_business_member(v_item.business_id);
  select * into v_biz from public.businesses where id = v_item.business_id;
  if not v_member and (v_item.status <> 'published' or not v_biz.is_setup_complete
                       or not coalesce((v_biz.visibility ->> 'public_catalog')::boolean, true)) then
    return null;
  end if;
  perform public.business_record_event(v_item.business_id, 'catalog_view', v_item.id);
  return jsonb_build_object(
    'id', v_item.id,
    'business_id', v_item.business_id,
    'kind', v_item.kind,
    'name', v_item.name,
    'description', v_item.description,
    'category', v_item.category,
    'price_minor', v_item.price_minor,
    'currency', v_item.currency,
    'image_url', v_item.image_url,
    'gallery', v_item.gallery,
    'variants', v_item.variants,
    'status', v_item.status,
    'stock_quantity', v_item.stock_quantity,
    'external_url', v_item.external_url,
    'view_count', v_item.view_count,
    'share_count', v_item.share_count,
    'created_at', v_item.created_at,
    'business', jsonb_build_object(
      'id', v_biz.id, 'name', v_biz.name, 'username', v_biz.username,
      'logo_url', v_biz.logo_url, 'is_verified', v_biz.is_verified,
      'category', v_biz.category, 'status', v_biz.status,
      'accepts_inquiries', v_biz.accepts_inquiries
    ),
    'can_manage', public.has_business_permission(v_item.business_id, 'catalog.manage'),
    'can_message', v_biz.accepts_inquiries
      and coalesce((v_biz.visibility ->> 'accept_messages')::boolean, true)
      and not v_member
  );
end;
$$;

create or replace function public.business_catalog_categories(p_business_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(distinct ci.category) filter (where ci.category is not null), '[]'::jsonb)
  from public.business_catalog_items ci
  where ci.business_id = p_business_id
    and (ci.status = 'published' or public.is_business_member(p_business_id));
$$;

-- ---------------------------------------------------------------------------
-- 9. Business posts (reuses posts/comments/reactions + moderation)
-- ---------------------------------------------------------------------------
alter table public.posts add column if not exists business_id uuid references public.businesses (id) on delete cascade;
alter table public.posts add column if not exists catalog_item_id uuid references public.business_catalog_items (id) on delete set null;
create index if not exists posts_business_idx on public.posts (business_id, created_at desc) where business_id is not null;

drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.is_active_user()
    and (business_id is null or public.has_business_permission(business_id, 'posts.publish'))
  );

create or replace function public.business_post_create(
  p_business_id uuid,
  p_body text,
  p_kind text default 'text',
  p_media_paths text[] default '{}',
  p_catalog_item_id uuid default null,
  p_visibility text default 'public'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_kind text := coalesce(p_kind, 'text');
begin
  if not public.has_business_permission(p_business_id, 'posts.publish') then
    raise exception 'Permission denied: posts.publish' using errcode = '42501';
  end if;
  if v_kind not in ('text', 'image', 'images', 'video') then
    raise exception 'Unsupported business post type';
  end if;
  if char_length(coalesce(p_body, '')) > 4000 then
    raise exception 'Post body is too long';
  end if;
  if coalesce(array_length(p_media_paths, 1), 0) > 10 then
    raise exception 'At most 10 media files per post';
  end if;
  if p_visibility not in ('public', 'followers', 'private') then
    raise exception 'Invalid post visibility';
  end if;
  if p_catalog_item_id is not null and not exists (
    select 1 from public.business_catalog_items ci
     where ci.id = p_catalog_item_id and ci.business_id = p_business_id) then
    raise exception 'Catalog listing does not belong to this business';
  end if;
  if v_kind <> 'text' and coalesce(array_length(p_media_paths, 1), 0) = 0 then
    raise exception 'Media posts need at least one file';
  end if;
  if v_kind = 'text' and coalesce(trim(p_body), '') = '' then
    raise exception 'Write something before posting';
  end if;

  insert into public.posts (author_id, business_id, catalog_item_id, kind, body, media_paths, visibility)
  values (auth.uid(), p_business_id, p_catalog_item_id, v_kind, nullif(trim(p_body), ''),
          coalesce(p_media_paths, '{}'), p_visibility)
  returning id into v_id;

  insert into public.business_events (business_id, kind, actor_id, subject_id)
  values (p_business_id, 'post_published', auth.uid(), v_id)
  on conflict do nothing;
  perform public.write_audit('business.post.create', 'business', p_business_id::text,
    jsonb_build_object('post_id', v_id, 'kind', v_kind));
  return v_id;
end;
$$;

create or replace function public.business_post_delete(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_author uuid;
begin
  select business_id, author_id into v_business, v_author from public.posts where id = p_post_id;
  if v_business is null then
    raise exception 'Post not found';
  end if;
  if v_author <> auth.uid() and not public.has_business_permission(v_business, 'posts.publish') then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  delete from public.posts where id = p_post_id;
  perform public.write_audit('business.post.delete', 'business', v_business::text,
    jsonb_build_object('post_id', p_post_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Notifications: preference-aware kinds + duplicate suppression
-- ---------------------------------------------------------------------------
alter table public.notifications add column if not exists dedupe_key text;
create unique index if not exists notifications_dedupe
  on public.notifications (user_id, dedupe_key) where dedupe_key is not null;

drop function if exists public.notify_user(uuid, text, text, text, jsonb);
create or replace function public.notify_user(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pref text;
  v_enabled boolean := true;
begin
  if p_user_id is null then
    return;
  end if;
  v_pref := case
    when p_kind = 'new_message' then 'messages'
    when p_kind in ('business_inquiry', 'business_invite', 'business_team_update',
                    'business_verification', 'catalog_update') then 'business'
    when p_kind in ('partner_application', 'partner_announcement', 'partner_benefit') then 'partner'
    when p_kind in ('incoming_call', 'missed_call') then 'calls'
    when p_kind = 'channel_post' then 'channels'
    else null
  end;
  if v_pref is not null then
    select coalesce((us.notifications ->> v_pref)::boolean, true) into v_enabled
      from public.user_settings us where us.user_id = p_user_id;
    v_enabled := coalesce(v_enabled, true);
  end if;
  if not v_enabled then
    return;
  end if;
  insert into public.notifications (user_id, kind, title, body, data, dedupe_key)
  values (p_user_id, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb),
          nullif(trim(coalesce(p_dedupe_key, '')), ''))
  on conflict do nothing;
end;
$$;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 11. Business inquiries: real conversations (one thread per customer)
-- ---------------------------------------------------------------------------
alter table public.conversations add column if not exists business_id uuid references public.businesses (id) on delete cascade;
alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations add constraint conversations_kind_check
  check (kind in ('direct', 'group', 'community', 'business'));
create index if not exists conversations_business_idx
  on public.conversations (business_id, last_message_at desc) where business_id is not null;

-- Business members participate in business conversations without per-user rows.
-- plpgsql (never inlined) so the business membership lookup cannot be flattened
-- into another table's RLS policy and cause policy recursion.
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = auth.uid() and m.left_at is null
  ) then
    return true;
  end if;
  return exists (
    select 1 from public.conversations c
    join public.business_members bm on bm.business_id = c.business_id
    where c.id = p_conversation_id and c.business_id is not null
      and bm.user_id = auth.uid() and bm.status = 'active'
  );
end;
$$;

create table if not exists public.business_inquiries (
  id                uuid primary key default gen_random_uuid(),
  business_id       uuid not null references public.businesses (id) on delete cascade,
  customer_id       uuid not null references public.profiles (id) on delete cascade,
  conversation_id   uuid not null unique references public.conversations (id) on delete cascade,
  catalog_item_id   uuid references public.business_catalog_items (id) on delete set null,
  subject           text not null check (char_length(subject) between 1 and 200),
  status            text not null default 'new' check (status in ('new', 'open', 'resolved', 'closed')),
  priority          text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  assigned_to       uuid references public.profiles (id) on delete set null,
  first_response_at timestamptz,
  resolved_at       timestamptz,
  resolved_by       uuid references public.profiles (id) on delete set null,
  last_message_at   timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists business_inquiries_board
  on public.business_inquiries (business_id, status, last_message_at desc);
create index if not exists business_inquiries_customer on public.business_inquiries (customer_id);
create unique index if not exists business_inquiries_one_open
  on public.business_inquiries (business_id, customer_id) where status in ('new', 'open');
create trigger business_inquiries_touch before update on public.business_inquiries
  for each row execute function public.touch_updated_at();

create table if not exists public.business_customers (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references public.businesses (id) on delete cascade,
  user_id             uuid not null references public.profiles (id) on delete cascade,
  internal_note       text check (internal_note is null or char_length(internal_note) <= 2000),
  follow_up_status    text not null default 'none' check (follow_up_status in ('none', 'follow_up', 'waiting', 'closed')),
  last_interaction_at timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (business_id, user_id)
);
create trigger business_customers_touch before update on public.business_customers
  for each row execute function public.touch_updated_at();

create table if not exists public.business_customer_labels (
  customer_id uuid not null references public.business_customers (id) on delete cascade,
  label_id    uuid not null references public.business_labels (id) on delete cascade,
  assigned_by uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (customer_id, label_id)
);

alter table public.business_inquiries      enable row level security;
alter table public.business_customers      enable row level security;
alter table public.business_customer_labels enable row level security;
revoke all on public.business_inquiries, public.business_customers, public.business_customer_labels
  from anon, authenticated;
grant select on public.business_inquiries, public.business_customers, public.business_customer_labels
  to authenticated;

drop policy if exists business_inquiries_select on public.business_inquiries;
create policy business_inquiries_select on public.business_inquiries for select to authenticated
  using (
    customer_id = auth.uid()
    or public.has_business_permission(business_id, 'inquiries.reply')
  );
drop policy if exists business_customers_team on public.business_customers;
create policy business_customers_team on public.business_customers for select to authenticated
  using (public.has_business_permission(business_id, 'customers.view'));
drop policy if exists business_customer_labels_team on public.business_customer_labels;
create policy business_customer_labels_team on public.business_customer_labels for select to authenticated
  using (exists (select 1 from public.business_customers bc
                  where bc.id = customer_id
                    and public.has_business_permission(bc.business_id, 'customers.view')));

-- Role check that does not depend on auth.uid() (used by triggers and loops).
create or replace function public.business_user_has_permission(
  p_business_id uuid,
  p_user_id uuid,
  p_permission text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
  v_status text;
  v_override boolean;
  v_owner_only boolean;
begin
  if p_user_id is null or p_business_id is null then
    return false;
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.account_status = 'active') then
    return false;
  end if;
  select m.role, m.status into v_role, v_status
    from public.business_members m
   where m.business_id = p_business_id and m.user_id = p_user_id;
  if v_role is null or v_status <> 'active' then
    return false;
  end if;
  if v_role = 'owner' then
    return true;
  end if;
  select b.owner_only into v_owner_only from public.business_permissions b where b.key = p_permission;
  if coalesce(v_owner_only, false) then
    return false;
  end if;
  select mp.granted into v_override
    from public.business_member_permissions mp
   where mp.business_id = p_business_id and mp.user_id = p_user_id and mp.permission_key = p_permission;
  if v_override is not null then
    return v_override;
  end if;
  return exists (select 1 from public.business_role_permissions rp
                  where rp.role = v_role and rp.permission_key = p_permission);
end;
$$;

create or replace function public.has_business_permission(p_business_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.business_user_has_permission(p_business_id, auth.uid(), p_permission);
$$;

-- Inquiry lifecycle from real messages: first response, reopen, last activity.
create or replace function public.on_business_message_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_inquiry public.business_inquiries%rowtype;
  v_is_business_side boolean;
  v_name text;
  v_preview text;
  r record;
begin
  select business_id into v_business from public.conversations where id = new.conversation_id;
  if v_business is null then
    return new;
  end if;
  select * into v_inquiry from public.business_inquiries where conversation_id = new.conversation_id;
  if not found then
    return new;
  end if;

  v_is_business_side := new.sender_id is not null
    and new.sender_id <> v_inquiry.customer_id
    and exists (select 1 from public.business_members bm
                 where bm.business_id = v_business and bm.user_id = new.sender_id and bm.status = 'active');

  -- System events (status changes, assignments) are not customer activity and
  -- must never reopen or resolve an inquiry.
  if new.kind = 'system' then
    update public.business_inquiries set last_message_at = new.created_at where id = v_inquiry.id;
    return new;
  end if;

  update public.business_inquiries
     set last_message_at = new.created_at,
         status = case
           when v_is_business_side and status = 'new' then 'open'
           when not v_is_business_side and status in ('resolved', 'closed') then 'open'
           else status end,
         first_response_at = case when v_is_business_side then coalesce(first_response_at, new.created_at)
                                  else first_response_at end,
         resolved_at = case when not v_is_business_side then null else resolved_at end,
         resolved_by = case when not v_is_business_side then null else resolved_by end
   where id = v_inquiry.id;

  update public.business_customers set last_interaction_at = new.created_at
   where business_id = v_business and user_id = v_inquiry.customer_id;

  -- Notify the business team except people who are already conversation members
  -- (they receive the standard new_message notification from on_message_notify).
  if new.sender_id = v_inquiry.customer_id and new.kind <> 'system' then
    select coalesce(nullif(display_name, ''), username) into v_name
      from public.profiles where id = v_inquiry.customer_id;
    v_preview := case new.kind
      when 'text' then left(coalesce(new.body, ''), 120)
      when 'image' then 'Sent a photo'
      when 'video' then 'Sent a video'
      when 'voice' then 'Sent a voice message'
      when 'document' then 'Sent a document'
      else 'Sent a message' end;
    for r in select bm.user_id from public.business_members bm
              where bm.business_id = v_business and bm.status = 'active'
                and not exists (select 1 from public.conversation_members cm
                                 where cm.conversation_id = new.conversation_id
                                   and cm.user_id = bm.user_id)
                and public.business_user_has_permission(v_business, bm.user_id, 'inquiries.reply')
    loop
      perform public.notify_user(
        r.user_id, 'business_inquiry', coalesce(v_name, 'New customer'),
        v_preview,
        jsonb_build_object('business_id', v_business, 'conversation_id', new.conversation_id,
                           'inquiry_id', v_inquiry.id),
        'business_msg:' || new.id::text || ':' || r.user_id::text);
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists messages_business_activity on public.messages;
create trigger messages_business_activity after insert on public.messages
  for each row execute function public.on_business_message_activity();

create or replace function public.business_inquiry_start(
  p_business_id uuid,
  p_message text,
  p_catalog_item_id uuid default null,
  p_subject text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_biz public.businesses%rowtype;
  v_item public.business_catalog_items%rowtype;
  v_conversation uuid;
  v_inquiry uuid;
  v_subject text;
  v_owner uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if coalesce(trim(p_message), '') = '' then
    raise exception 'Write a message before contacting the business';
  end if;
  if char_length(p_message) > 4000 then
    raise exception 'Message is too long';
  end if;
  select * into v_biz from public.businesses where id = p_business_id;
  if not found or not v_biz.is_setup_complete then
    raise exception 'Business not available';
  end if;
  if not public.setting_bool('business_inquiries_enabled', true) then
    raise exception 'Business inquiries are currently disabled';
  end if;
  if not v_biz.accepts_inquiries
     or not coalesce((v_biz.visibility ->> 'accept_messages')::boolean, true)
     or v_biz.status = 'closed' then
    raise exception 'This business is not accepting messages right now';
  end if;
  if public.is_business_member(p_business_id) then
    raise exception 'Business members cannot open an inquiry with their own business';
  end if;
  if v_biz.created_by is not null and public.is_blocked_between(v_uid, v_biz.created_by) then
    raise exception 'This business is not available for messaging';
  end if;
  if p_catalog_item_id is not null then
    select * into v_item from public.business_catalog_items
     where id = p_catalog_item_id and business_id = p_business_id and status = 'published';
    if not found then
      raise exception 'Listing not available';
    end if;
  end if;

  v_subject := coalesce(nullif(trim(coalesce(p_subject, '')), ''),
                        case when v_item.name is not null then 'About ' || v_item.name
                             else 'Message to ' || v_biz.name end);
  v_subject := left(v_subject, 200);

  select c.id into v_conversation
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
   where c.business_id = p_business_id and cm.user_id = v_uid
   limit 1;

  if v_conversation is null then
    select created_by into v_owner from public.businesses where id = p_business_id;
    insert into public.conversations (kind, business_id, created_by, title)
    values ('business', p_business_id, v_uid, v_biz.name)
    returning id into v_conversation;
    insert into public.conversation_members (conversation_id, user_id, role)
    values (v_conversation, v_uid, 'member');
    if v_owner is not null then
      insert into public.conversation_members (conversation_id, user_id, role)
      values (v_conversation, v_owner, 'owner')
      on conflict do nothing;
    end if;
  end if;

  select id into v_inquiry from public.business_inquiries
   where conversation_id = v_conversation and status in ('new', 'open');
  if v_inquiry is null then
    insert into public.business_inquiries (business_id, customer_id, conversation_id, catalog_item_id, subject)
    values (p_business_id, v_uid, v_conversation, p_catalog_item_id, v_subject)
    returning id into v_inquiry;
  else
    update public.business_inquiries
       set subject = v_subject,
           catalog_item_id = coalesce(p_catalog_item_id, catalog_item_id),
           last_message_at = now()
     where id = v_inquiry;
  end if;

  insert into public.business_customers (business_id, user_id, last_interaction_at)
  values (p_business_id, v_uid, now())
  on conflict (business_id, user_id) do update set last_interaction_at = now();

  insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (v_conversation, v_uid, gen_random_uuid(), 'text', p_message);

  insert into public.business_events (business_id, kind, actor_id, subject_id)
  values (p_business_id, 'inquiry_created', v_uid, v_inquiry)
  on conflict do nothing;

  -- Notifications are produced by the message triggers so the same inquiry never
  -- notifies a teammate twice (conversation members get new_message, the rest of
  -- the team gets one business_inquiry per message).
  return jsonb_build_object('conversation_id', v_conversation, 'inquiry_id', v_inquiry,
                            'business_id', p_business_id, 'subject', v_subject);
end;
$$;

create or replace function public.business_inquiry_list(
  p_business_id uuid,
  p_status text default null,
  p_search text default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  if not public.has_business_permission(p_business_id, 'inquiries.reply') then
    raise exception 'Permission denied: inquiries.reply' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb)
    from (
      select i.id, i.business_id, i.customer_id, i.conversation_id, i.catalog_item_id, i.subject,
             i.status, i.priority, i.assigned_to, i.first_response_at, i.resolved_at,
             i.last_message_at, i.created_at,
             p.display_name as customer_name, p.username as customer_username,
             p.avatar_url as customer_avatar, p.is_verified as customer_verified,
             ci.name as catalog_item_name, ci.kind as catalog_item_kind, ci.image_url as catalog_item_image,
             (select left(coalesce(m.body, ''), 160) from public.messages m
               where m.conversation_id = i.conversation_id and m.deleted_at is null
               order by m.created_at desc limit 1) as last_message,
             (select count(*) from public.messages m
               where m.conversation_id = i.conversation_id and m.deleted_at is null) as message_count
        from public.business_inquiries i
        join public.profiles p on p.id = i.customer_id
        left join public.business_catalog_items ci on ci.id = i.catalog_item_id
       where i.business_id = p_business_id
         and (p_status is null or p_status = 'all' or i.status = p_status)
         and (p_search is null or p_search = ''
              or i.subject ilike '%' || p_search || '%'
              or p.display_name ilike '%' || p_search || '%'
              or p.username ilike '%' || p_search || '%'
              or exists (select 1 from public.messages m2
                          where m2.conversation_id = i.conversation_id
                            and m2.body ilike '%' || p_search || '%'))
       order by case i.status when 'new' then 0 when 'open' then 1 else 2 end,
                i.last_message_at desc
       limit v_limit
    ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.business_inquiry_detail(p_inquiry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  i public.business_inquiries%rowtype;
  v_is_customer boolean;
  v_can_view_customers boolean;
begin
  select * into i from public.business_inquiries where id = p_inquiry_id;
  if not found then
    return null;
  end if;
  v_is_customer := (i.customer_id = auth.uid());
  if not v_is_customer and not public.has_business_permission(i.business_id, 'inquiries.reply') then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  v_can_view_customers := public.has_business_permission(i.business_id, 'customers.view');
  return jsonb_build_object(
    'id', i.id, 'business_id', i.business_id, 'customer_id', i.customer_id,
    'conversation_id', i.conversation_id, 'subject', i.subject, 'status', i.status,
    'priority', i.priority, 'assigned_to', i.assigned_to,
    'first_response_at', i.first_response_at, 'resolved_at', i.resolved_at,
    'last_message_at', i.last_message_at, 'created_at', i.created_at,
    'catalog_item', case when i.catalog_item_id is null then null else (
      select jsonb_build_object('id', ci.id, 'name', ci.name, 'kind', ci.kind,
                                'price_minor', ci.price_minor, 'currency', ci.currency,
                                'image_url', ci.image_url, 'status', ci.status)
        from public.business_catalog_items ci where ci.id = i.catalog_item_id) end,
    'customer', case when v_is_customer then null else (
      select jsonb_build_object('user_id', p.id, 'display_name', p.display_name,
                                'username', p.username, 'avatar_url', p.avatar_url,
                                'is_verified', p.is_verified, 'bio', p.bio)
        from public.profiles p where p.id = i.customer_id) end,
    'customer_record', case when v_can_view_customers and not v_is_customer then (
      select jsonb_build_object('internal_note', bc.internal_note,
                                'follow_up_status', bc.follow_up_status,
                                'labels', coalesce((select jsonb_agg(jsonb_build_object(
                                          'id', l.id, 'name', l.name, 'color', l.color))
                                          from public.business_customer_labels cl
                                          join public.business_labels l on l.id = cl.label_id
                                         where cl.customer_id = bc.id), '[]'::jsonb))
        from public.business_customers bc
        where bc.business_id = i.business_id and bc.user_id = i.customer_id) end,
    'is_customer', v_is_customer,
    'can_manage', public.has_business_permission(i.business_id, 'inquiries.manage'),
    'can_view_customer', v_can_view_customers
  );
end;
$$;

create or replace function public.business_inquiry_set_status(
  p_inquiry_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i public.business_inquiries%rowtype;
  v_actor uuid := auth.uid();
begin
  select * into i from public.business_inquiries where id = p_inquiry_id for update;
  if not found then
    raise exception 'Inquiry not found';
  end if;
  if not public.has_business_permission(i.business_id, 'inquiries.manage') then
    raise exception 'Permission denied: inquiries.manage' using errcode = '42501';
  end if;
  if p_status not in ('new', 'open', 'resolved', 'closed') then
    raise exception 'Invalid inquiry status';
  end if;
  update public.business_inquiries
     set status = p_status,
         resolved_at = case when p_status in ('resolved', 'closed') then now() else null end,
         resolved_by = case when p_status in ('resolved', 'closed') then v_actor else null end
   where id = p_inquiry_id;

  insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (i.conversation_id, null, gen_random_uuid(), 'system',
          case p_status when 'resolved' then 'Inquiry marked as resolved'
                        when 'closed' then 'Inquiry closed'
                        when 'open' then 'Inquiry reopened'
                        else 'Inquiry moved back to new' end
          || case when coalesce(nullif(trim(p_note), ''), '') <> '' then ': ' || p_note else '' end);

  if p_status in ('resolved', 'closed') then
    insert into public.business_events (business_id, kind, actor_id, subject_id)
    values (i.business_id, 'inquiry_resolved', v_actor, i.id)
    on conflict do nothing;
    perform public.notify_user(
      i.customer_id, 'business_team_update', 'Inquiry ' || p_status,
      'Your conversation with the business was marked ' || p_status,
      jsonb_build_object('business_id', i.business_id, 'conversation_id', i.conversation_id,
                         'inquiry_id', i.id),
      'inquiry_status:' || i.id::text || ':' || p_status || ':' || to_char(now(), 'YYYYMMDDHH24'));
  end if;
  perform public.write_audit('business.inquiry.status', 'business', i.business_id::text,
    jsonb_build_object('inquiry_id', i.id, 'status', p_status));
end;
$$;

create or replace function public.business_inquiry_assign(p_inquiry_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i public.business_inquiries%rowtype;
begin
  select * into i from public.business_inquiries where id = p_inquiry_id;
  if not found then
    raise exception 'Inquiry not found';
  end if;
  if not public.has_business_permission(i.business_id, 'inquiries.manage') then
    raise exception 'Permission denied: inquiries.manage' using errcode = '42501';
  end if;
  if p_user_id is not null and not public.business_user_has_permission(i.business_id, p_user_id, 'inquiries.reply') then
    raise exception 'Assignee must be an active teammate who can reply to inquiries';
  end if;
  update public.business_inquiries set assigned_to = p_user_id where id = p_inquiry_id;
  perform public.write_audit('business.inquiry.assign', 'business', i.business_id::text,
    jsonb_build_object('inquiry_id', i.id, 'assignee', p_user_id));
  if p_user_id is not null and p_user_id <> auth.uid() then
    perform public.notify_user(
      p_user_id, 'business_team_update', 'Inquiry assigned to you',
      i.subject,
      jsonb_build_object('business_id', i.business_id, 'inquiry_id', i.id,
                         'conversation_id', i.conversation_id),
      'inquiry_assign:' || i.id::text || ':' || p_user_id::text);
  end if;
end;
$$;

create or replace function public.business_inquiry_set_priority(p_inquiry_id uuid, p_priority text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i public.business_inquiries%rowtype;
begin
  select * into i from public.business_inquiries where id = p_inquiry_id;
  if not found then
    raise exception 'Inquiry not found';
  end if;
  if not public.has_business_permission(i.business_id, 'inquiries.manage') then
    raise exception 'Permission denied: inquiries.manage' using errcode = '42501';
  end if;
  if p_priority not in ('low', 'normal', 'high') then
    raise exception 'Invalid priority';
  end if;
  update public.business_inquiries set priority = p_priority where id = p_inquiry_id;
  perform public.write_audit('business.inquiry.priority', 'business', i.business_id::text,
    jsonb_build_object('inquiry_id', i.id, 'priority', p_priority));
end;
$$;

create or replace function public.my_business_inquiries()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'business_id', i.business_id, 'business_name', b.name,
    'business_logo', b.logo_url, 'business_verified', b.is_verified,
    'conversation_id', i.conversation_id, 'subject', i.subject, 'status', i.status,
    'last_message_at', i.last_message_at, 'created_at', i.created_at)), '[]'::jsonb)
  from public.business_inquiries i
  join public.businesses b on b.id = i.business_id
  where i.customer_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 12. Customer management (tenant isolated; internal notes never exposed)
-- ---------------------------------------------------------------------------
-- Labels are permission-aware for support/catalog roles, reusing business_labels.
drop policy if exists business_labels_write on public.business_labels;
create policy business_labels_write on public.business_labels for all to authenticated
  using (public.has_business_permission(business_id, 'customers.manage'))
  with check (public.has_business_permission(business_id, 'customers.manage'));
drop policy if exists business_label_assignments_write on public.business_label_assignments;
create policy business_label_assignments_write on public.business_label_assignments for all to authenticated
  using (exists (select 1 from public.business_labels l
                  where l.id = label_id and public.has_business_permission(l.business_id, 'inquiries.manage')))
  with check (exists (select 1 from public.business_labels l
                       where l.id = label_id and public.has_business_permission(l.business_id, 'inquiries.manage')));

create or replace function public.business_customer_list(
  p_business_id uuid,
  p_search text default null,
  p_label_id uuid default null,
  p_follow_up text default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  if not public.has_business_permission(p_business_id, 'customers.view') then
    raise exception 'Permission denied: customers.view' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb)
    from (
      select bc.id, bc.business_id, bc.user_id, bc.internal_note, bc.follow_up_status,
             bc.last_interaction_at, bc.created_at,
             p.display_name, p.username, p.avatar_url, p.is_verified,
             (select count(*) from public.business_inquiries i
               where i.business_id = p_business_id and i.customer_id = bc.user_id) as inquiry_count,
             (select count(*) from public.business_inquiries i
               where i.business_id = p_business_id and i.customer_id = bc.user_id
                 and i.status in ('new', 'open')) as open_inquiries,
             (select max(i.last_message_at) from public.business_inquiries i
               where i.business_id = p_business_id and i.customer_id = bc.user_id) as last_message_at,
             coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'color', l.color))
                        from public.business_customer_labels cl
                        join public.business_labels l on l.id = cl.label_id
                       where cl.customer_id = bc.id), '[]'::jsonb) as labels
        from public.business_customers bc
        join public.profiles p on p.id = bc.user_id
       where bc.business_id = p_business_id
         and (p_follow_up is null or p_follow_up = 'all' or bc.follow_up_status = p_follow_up)
         and (p_search is null or p_search = ''
              or p.display_name ilike '%' || p_search || '%'
              or p.username ilike '%' || p_search || '%'
              or bc.internal_note ilike '%' || p_search || '%')
         and (p_label_id is null or exists (select 1 from public.business_customer_labels cl2
                                             where cl2.customer_id = bc.id and cl2.label_id = p_label_id))
       order by bc.last_interaction_at desc
       limit v_limit
    ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.business_customer_detail(p_customer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bc public.business_customers%rowtype;
begin
  select * into bc from public.business_customers where id = p_customer_id;
  if not found then
    return null;
  end if;
  if not public.has_business_permission(bc.business_id, 'customers.view') then
    raise exception 'Permission denied: customers.view' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'id', bc.id, 'business_id', bc.business_id, 'user_id', bc.user_id,
    'internal_note', bc.internal_note, 'follow_up_status', bc.follow_up_status,
    'last_interaction_at', bc.last_interaction_at, 'created_at', bc.created_at,
    'profile', (select jsonb_build_object('display_name', p.display_name, 'username', p.username,
                                          'avatar_url', p.avatar_url, 'is_verified', p.is_verified,
                                          'bio', p.bio)
                  from public.profiles p where p.id = bc.user_id),
    'labels', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'color', l.color))
                         from public.business_customer_labels cl
                         join public.business_labels l on l.id = cl.label_id
                        where cl.customer_id = bc.id), '[]'::jsonb),
    'inquiries', coalesce((select jsonb_agg(jsonb_build_object(
                            'id', i.id, 'subject', i.subject, 'status', i.status,
                            'conversation_id', i.conversation_id, 'last_message_at', i.last_message_at)
                            order by i.last_message_at desc)
                            from public.business_inquiries i
                           where i.business_id = bc.business_id and i.customer_id = bc.user_id), '[]'::jsonb),
    'can_manage', public.has_business_permission(bc.business_id, 'customers.manage')
  );
end;
$$;

create or replace function public.business_customer_update(p_customer_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bc public.business_customers%rowtype;
  v_note text;
  v_follow text;
begin
  select * into bc from public.business_customers where id = p_customer_id for update;
  if not found then
    raise exception 'Customer not found';
  end if;
  if not public.has_business_permission(bc.business_id, 'customers.manage') then
    raise exception 'Permission denied: customers.manage' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Invalid customer update';
  end if;
  if exists (select 1 from jsonb_object_keys(p_patch) k
              where k not in ('internal_note', 'follow_up_status')) then
    raise exception 'Unsupported customer field';
  end if;
  v_note := case when p_patch ? 'internal_note' then nullif(trim(p_patch ->> 'internal_note'), '') else bc.internal_note end;
  if v_note is not null and char_length(v_note) > 2000 then
    raise exception 'Internal note is too long (max 2000 characters)';
  end if;
  v_follow := coalesce(p_patch ->> 'follow_up_status', bc.follow_up_status);
  if v_follow not in ('none', 'follow_up', 'waiting', 'closed') then
    raise exception 'Invalid follow-up status';
  end if;
  update public.business_customers
     set internal_note = v_note, follow_up_status = v_follow
   where id = p_customer_id;
  perform public.write_audit('business.customer.update', 'business', bc.business_id::text,
    jsonb_build_object('customer_id', p_customer_id, 'fields', (select jsonb_agg(k) from jsonb_object_keys(p_patch) k)));
end;
$$;

create or replace function public.business_customer_set_labels(p_customer_id uuid, p_label_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bc public.business_customers%rowtype;
  v_label uuid;
begin
  select * into bc from public.business_customers where id = p_customer_id for update;
  if not found then
    raise exception 'Customer not found';
  end if;
  if not public.has_business_permission(bc.business_id, 'customers.manage') then
    raise exception 'Permission denied: customers.manage' using errcode = '42501';
  end if;
  if coalesce(array_length(p_label_ids, 1), 0) > 10 then
    raise exception 'At most 10 labels per customer';
  end if;
  delete from public.business_customer_labels where customer_id = p_customer_id;
  if p_label_ids is not null then
    foreach v_label in array p_label_ids loop
      if not exists (select 1 from public.business_labels l
                      where l.id = v_label and l.business_id = bc.business_id) then
        raise exception 'Label does not belong to this business';
      end if;
      insert into public.business_customer_labels (customer_id, label_id, assigned_by)
      values (p_customer_id, v_label, auth.uid()) on conflict do nothing;
    end loop;
  end if;
  perform public.write_audit('business.customer.labels', 'business', bc.business_id::text,
    jsonb_build_object('customer_id', p_customer_id, 'labels', p_label_ids));
end;
$$;

create or replace function public.business_label_list(p_business_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'color', l.color,
                                                       'usage', (select count(*) from public.business_customer_labels cl
                                                                 where cl.label_id = l.id))
                                     order by l.name)
                     from public.business_labels l where l.business_id = p_business_id), '[]'::jsonb)
  where public.is_business_member(p_business_id);
$$;

create or replace function public.business_label_save(p_business_id uuid, p_name text, p_color text default '#2563EB')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text := trim(coalesce(p_name, ''));
begin
  if not public.has_business_permission(p_business_id, 'customers.manage') then
    raise exception 'Permission denied: customers.manage' using errcode = '42501';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'Label name must be 1-40 characters';
  end if;
  if coalesce(p_color, '') !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Label colour must be a hex value like #2563EB';
  end if;
  insert into public.business_labels (business_id, name, color, created_by)
  values (p_business_id, v_name, p_color, auth.uid())
  on conflict (business_id, name) do update set color = excluded.color
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.business_label_delete(p_label_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
begin
  select business_id into v_business from public.business_labels where id = p_label_id;
  if v_business is null then
    raise exception 'Label not found';
  end if;
  if not public.has_business_permission(v_business, 'customers.manage') then
    raise exception 'Permission denied: customers.manage' using errcode = '42501';
  end if;
  delete from public.business_labels where id = p_label_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Business verification (reuses verification_applications engine)
-- ---------------------------------------------------------------------------
create or replace function public.business_verification_state(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app public.verification_applications%rowtype;
  v_has_app boolean := false;
  v_is_verified boolean;
begin
  if not public.is_business_member(p_business_id) then
    raise exception 'Not a member of this business' using errcode = '42501';
  end if;
  select is_verified into v_is_verified from public.businesses where id = p_business_id;
  select * into v_app from public.verification_applications
   where business_id = p_business_id and application_type = 'business'
   order by submitted_at desc limit 1;
  v_has_app := found;

  return jsonb_build_object(
    'business_id', p_business_id,
    'is_verified', coalesce(v_is_verified, false),
    'can_submit', v_is_verified = false and not exists (
      select 1 from public.verification_applications a
       where a.business_id = p_business_id and a.application_type = 'business'
         and a.status in ('pending', 'under_review', 'info_requested')),
    'requirements', coalesce(
      (select setting_value from public.platform_settings
        where setting_key = 'business_verification_requirements'),
      '{"require_documents":true,"min_documents":1,"accepted_doc_types":["business_registration","authorization","website_proof"],"sla_hours":72}'::jsonb),
    'application', case when not v_has_app then null else jsonb_build_object(
      'id', v_app.id, 'status', v_app.status, 'full_name', v_app.full_name,
      'category', v_app.category, 'description', v_app.description, 'reason', v_app.reason,
      'links', v_app.links, 'submitted_at', v_app.submitted_at, 'reviewed_at', v_app.reviewed_at,
      'decision_note', v_app.decision_note, 'recommendation', v_app.recommendation
    ) end,
    'history', case when not v_has_app then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', h.id, 'action', h.action, 'from_status', h.from_status,
                                          'to_status', h.to_status, 'note', h.note, 'created_at', h.created_at)
                       order by h.created_at desc)
        from public.verification_history h where h.application_id = v_app.id), '[]'::jsonb) end,
    'documents', case when not v_has_app then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'doc_type', d.doc_type, 'mime_type', d.mime_type,
                                          'size_bytes', d.size_bytes, 'created_at', d.created_at,
                                          'storage_path', d.storage_path)
                       order by d.created_at desc)
        from public.verification_documents d where d.application_id = v_app.id), '[]'::jsonb) end,
    'can_manage', public.has_business_permission(p_business_id, 'verification.apply')
  );
end;
$$;

create or replace function public.verification_respond_info(p_application_id uuid, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.verification_applications%rowtype;
  v_uid uuid := auth.uid();
  v_allowed boolean := false;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if coalesce(trim(p_message), '') = '' then
    raise exception 'Write the requested information before sending it';
  end if;
  if char_length(p_message) > 2000 then
    raise exception 'Response is too long (max 2000 characters)';
  end if;
  select * into v_app from public.verification_applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.application_type = 'business' then
    v_allowed := public.has_business_permission(v_app.business_id, 'verification.apply');
  elsif v_app.application_type = 'channel' then
    v_allowed := exists (select 1 from public.channels c where c.id = v_app.channel_id and c.owner_id = v_uid);
  else
    v_allowed := v_app.applicant_id = v_uid;
  end if;
  if not v_allowed then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if v_app.status <> 'info_requested' then
    raise exception 'This application is not waiting for information';
  end if;

  insert into public.verification_history (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, v_uid, 'info_provided', v_app.status, 'under_review', left(p_message, 2000));
  update public.verification_applications
     set status = 'under_review', submitted_at = submitted_at, updated_at = now()
   where id = p_application_id;

  if v_app.reviewed_by is not null then
    perform public.notify_user(
      v_app.reviewed_by, 'verification_update', 'Verification information received',
      'The applicant answered the additional information request',
      jsonb_build_object('application_id', p_application_id, 'application_type', v_app.application_type),
      'verification_info:' || p_application_id::text || ':' || to_char(now(), 'YYYYMMDDHH24'));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Partner platform: profile, benefits, resources, support, activity
-- ---------------------------------------------------------------------------
alter table public.partner_profiles
  add column if not exists logo_url text,
  add column if not exists cover_url text,
  add column if not exists headline text,
  add column if not exists specialties text[] not null default '{}',
  add column if not exists is_featured boolean not null default false,
  add column if not exists featured_until timestamptz,
  add column if not exists featured_by uuid references public.profiles (id) on delete set null,
  add column if not exists directory_visible boolean not null default true;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'partner_profiles_headline_len') then
    alter table public.partner_profiles add constraint partner_profiles_headline_len
      check (headline is null or char_length(headline) <= 120);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'partner_profiles_specialties_len') then
    alter table public.partner_profiles add constraint partner_profiles_specialties_len
      check (coalesce(array_length(specialties, 1), 0) <= 8);
  end if;
end $$;

create table if not exists public.partner_benefits (
  key                 text primary key,
  title               text not null,
  description         text not null default '',
  is_enabled          boolean not null default true,
  is_public           boolean not null default true,
  requires_permission text,
  sort_order          int not null default 0,
  updated_by          uuid references public.profiles (id) on delete set null,
  updated_at          timestamptz not null default now()
);
insert into public.partner_benefits (key, title, description, is_enabled, is_public, requires_permission, sort_order) values
  ('badge',           'Partner badge',        'The BubbleApp Partner badge on your profile and directory card.', true, true, null, 10),
  ('directory_listing', 'Partner directory',  'Your public partner profile is listed in the partner directory.', true, true, null, 20),
  ('announcements',   'Partner announcements','Read announcements published for the partner program.',            true, true, 'partner.announcements.read', 30),
  ('resources',       'Partner resources',    'Access the partner resource library (guides, brand assets, playbooks).', true, true, 'partner.resources.read', 40),
  ('support_channel', 'Partner support',      'Open support requests directly to the BubbleApp team.',            true, true, 'partner.portal', 50),
  ('featured_profile','Featured eligibility', 'Eligible to be selected as a Featured Partner by BubbleApp.',      true, true, null, 60)
on conflict (key) do nothing;

-- Partner-scoped permissions are granted to the partner role once (platform RBAC).
insert into public.role_permissions (role_key, permission_key)
  select 'partner', key from public.permissions where scope = 'partner'
on conflict do nothing;

create table if not exists public.partner_resources (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (char_length(title) between 3 and 160),
  description  text not null default '' check (char_length(description) <= 1000),
  category     text not null default 'general' check (char_length(category) between 2 and 60),
  url          text not null check (url ~* '^https?://'),
  is_published boolean not null default false,
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists partner_resources_published on public.partner_resources (is_published, created_at desc);

create table if not exists public.partner_support_requests (
  id              uuid primary key default gen_random_uuid(),
  partner_user_id uuid not null references public.profiles (id) on delete cascade,
  subject         text not null check (char_length(subject) between 3 and 160),
  body            text not null check (char_length(body) between 5 and 4000),
  status          text not null default 'open' check (status in ('open', 'answered', 'closed')),
  response        text check (response is null or char_length(response) <= 4000),
  responded_by    uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists partner_support_status on public.partner_support_requests (status, created_at desc);

create table if not exists public.partner_activity (
  id              bigint generated always as identity primary key,
  partner_user_id uuid not null references public.profiles (id) on delete cascade,
  kind            text not null,
  summary         text not null check (char_length(summary) between 1 and 300),
  actor_id        uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists partner_activity_user on public.partner_activity (partner_user_id, created_at desc);

alter table public.partner_benefits          enable row level security;
alter table public.partner_resources         enable row level security;
alter table public.partner_support_requests  enable row level security;
alter table public.partner_activity          enable row level security;

revoke all on public.partner_benefits, public.partner_resources, public.partner_support_requests,
  public.partner_activity from anon, authenticated;
grant select on public.partner_benefits, public.partner_resources, public.partner_support_requests,
  public.partner_activity to authenticated;

drop policy if exists partner_benefits_read on public.partner_benefits;
create policy partner_benefits_read on public.partner_benefits for select to authenticated using (true);

drop policy if exists partner_resources_read on public.partner_resources;
create policy partner_resources_read on public.partner_resources for select to authenticated using (
  public.has_permission('partners.manage')
  or public.has_permission('partners.approve')
  or (
    is_published
    and coalesce((select is_enabled from public.partner_benefits where key = 'resources'), false)
    and exists (select 1 from public.partner_profiles pp
                 where pp.user_id = auth.uid() and pp.partner_status = 'active')
    and public.has_permission('partner.resources.read')
  )
);

drop policy if exists partner_support_read on public.partner_support_requests;
create policy partner_support_read on public.partner_support_requests for select to authenticated
  using (partner_user_id = auth.uid() or public.has_permission('partners.manage'));

drop policy if exists partner_activity_read on public.partner_activity;
create policy partner_activity_read on public.partner_activity for select to authenticated
  using (partner_user_id = auth.uid() or public.has_permission('partners.manage'));

create or replace function public.partner_badge_visible(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_enabled from public.partner_benefits where key = 'badge'), true)
     and exists (select 1 from public.partner_profiles pp
                  where pp.user_id = p_user_id and pp.partner_status = 'active' and pp.badge_enabled)
     and exists (select 1 from public.user_roles ur
                  where ur.user_id = p_user_id and ur.role_key = 'partner' and ur.revoked_at is null);
$$;

create or replace function public.partner_directory(
  p_search text default null,
  p_category text default null,
  p_featured_only boolean default false,
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  if not public.setting_bool('partner_directory_enabled', true) then
    return jsonb_build_object('partners', '[]'::jsonb, 'categories', '[]'::jsonb, 'enabled', false);
  end if;
  if not coalesce((select is_enabled from public.partner_benefits where key = 'directory_listing'), true) then
    return jsonb_build_object('partners', '[]'::jsonb, 'categories', '[]'::jsonb, 'enabled', false);
  end if;
  return jsonb_build_object(
    'enabled', true,
    'partners', coalesce((
      select jsonb_agg(row_to_json(t)::jsonb)
      from (
        select pp.user_id, pp.display_name, pp.bio, pp.website, pp.partner_category,
               pp.logo_url, pp.cover_url, pp.headline, pp.specialties, pp.approved_at,
               public.partner_badge_visible(pp.user_id) as is_badge_visible,
               (pp.is_featured and (pp.featured_until is null or pp.featured_until > now())) as is_featured,
               p.username, p.is_verified
          from public.partner_profiles pp
          join public.profiles p on p.id = pp.user_id
         where pp.partner_status = 'active'
           and pp.directory_visible
           and (p_search is null or p_search = ''
                or pp.display_name ilike '%' || p_search || '%'
                or pp.bio ilike '%' || p_search || '%'
                or pp.partner_category ilike '%' || p_search || '%'
                or coalesce(pp.headline, '') ilike '%' || p_search || '%')
           and (p_category is null or p_category = '' or pp.partner_category = p_category)
           and (not coalesce(p_featured_only, false)
                or (pp.is_featured and (pp.featured_until is null or pp.featured_until > now())))
         order by (pp.featured_until is null or pp.featured_until > now()) desc, pp.is_featured desc,
                  pp.approved_at desc
         limit v_limit offset v_offset
      ) t
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(distinct pp.partner_category)
        from public.partner_profiles pp
       where pp.partner_status = 'active' and pp.directory_visible), '[]'::jsonb)
  );
end;
$$;

create or replace function public.partner_public_profile(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  pp public.partner_profiles%rowtype;
begin
  select * into pp from public.partner_profiles where user_id = p_user_id;
  if not found or pp.partner_status <> 'active' then
    return null;
  end if;
  if not pp.directory_visible and not public.has_permission('partners.manage') then
    return null;
  end if;
  return jsonb_build_object(
    'user_id', pp.user_id,
    'display_name', pp.display_name,
    'bio', pp.bio,
    'website', pp.website,
    'partner_category', pp.partner_category,
    'logo_url', pp.logo_url,
    'cover_url', pp.cover_url,
    'headline', pp.headline,
    'specialties', pp.specialties,
    'approved_at', pp.approved_at,
    'is_badge_visible', public.partner_badge_visible(pp.user_id),
    'is_featured', pp.is_featured and (pp.featured_until is null or pp.featured_until > now()),
    'profile', (select jsonb_build_object('display_name', p.display_name, 'username', p.username,
                                          'avatar_url', p.avatar_url, 'is_verified', p.is_verified)
                  from public.profiles p where p.id = pp.user_id),
    'can_message', exists (select 1 from public.profiles p
                            where p.id = pp.user_id and p.account_status = 'active')
  );
end;
$$;

create or replace function public.partner_profile_update(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  pp public.partner_profiles%rowtype;
  v_name text;
  v_website text;
begin
  select * into pp from public.partner_profiles where user_id = v_uid for update;
  if not found or pp.partner_status <> 'active' then
    raise exception 'Active partner account required' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Invalid partner profile update';
  end if;
  if exists (select 1 from jsonb_object_keys(p_patch) k
              where k not in ('display_name', 'bio', 'website', 'headline', 'specialties',
                              'logo_url', 'cover_url', 'badge_enabled', 'directory_visible')) then
    raise exception 'This partner field cannot be changed from the app';
  end if;
  v_name := coalesce(nullif(trim(p_patch ->> 'display_name'), ''), pp.display_name);
  if char_length(v_name) not between 2 and 80 then
    raise exception 'Partner display name must be 2-80 characters';
  end if;
  if p_patch ? 'website' then
    v_website := nullif(trim(p_patch ->> 'website'), '');
    if v_website is not null and v_website !~* '^https?://' then
      raise exception 'Website must start with http:// or https://';
    end if;
  end if;
  if p_patch ? 'bio' and char_length(coalesce(p_patch ->> 'bio', '')) > 500 then
    raise exception 'Bio is too long (max 500 characters)';
  end if;
  if p_patch ? 'headline' and char_length(coalesce(p_patch ->> 'headline', '')) > 120 then
    raise exception 'Headline is too long (max 120 characters)';
  end if;
  if p_patch ? 'specialties' then
    if jsonb_typeof(p_patch -> 'specialties') <> 'array' or jsonb_array_length(p_patch -> 'specialties') > 8 then
      raise exception 'At most 8 specialties';
    end if;
    if exists (select 1 from jsonb_array_elements(p_patch -> 'specialties') s
                where jsonb_typeof(s) <> 'string' or char_length(s #>> '{}') > 40) then
      raise exception 'Invalid specialty entry';
    end if;
  end if;

  update public.partner_profiles set
    display_name = v_name,
    bio = coalesce(p_patch ->> 'bio', bio),
    website = case when p_patch ? 'website' then v_website else website end,
    headline = case when p_patch ? 'headline' then nullif(trim(p_patch ->> 'headline'), '') else headline end,
    specialties = case when p_patch ? 'specialties'
      then coalesce((select array_agg(value) from jsonb_array_elements_text(p_patch -> 'specialties') as value), '{}')
      else specialties end,
    logo_url = case when p_patch ? 'logo_url' then nullif(trim(p_patch ->> 'logo_url'), '') else logo_url end,
    cover_url = case when p_patch ? 'cover_url' then nullif(trim(p_patch ->> 'cover_url'), '') else cover_url end,
    badge_enabled = case when p_patch ? 'badge_enabled' then coalesce((p_patch ->> 'badge_enabled')::boolean, badge_enabled) else badge_enabled end,
    directory_visible = case when p_patch ? 'directory_visible' then coalesce((p_patch ->> 'directory_visible')::boolean, directory_visible) else directory_visible end
  where user_id = v_uid;

  insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
  values (v_uid, 'profile_updated', 'Updated the partner profile', v_uid);
  perform public.write_audit('partner.profile.update', 'profile', v_uid::text,
    jsonb_build_object('fields', (select jsonb_agg(k) from jsonb_object_keys(p_patch) k)));
  return public.partner_public_profile(v_uid);
end;
$$;

create or replace function public.partner_my_benefits()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  pp public.partner_profiles%rowtype;
begin
  select * into pp from public.partner_profiles where user_id = v_uid;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'partner_status', pp.partner_status,
    'is_badge_visible', public.partner_badge_visible(v_uid),
    'is_featured', pp.is_featured and (pp.featured_until is null or pp.featured_until > now()),
    'featured_until', pp.featured_until,
    'benefits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', b.key, 'title', b.title, 'description', b.description,
        'enabled', b.is_enabled, 'is_public', b.is_public,
        'granted', b.is_enabled and (b.requires_permission is null
                                      or public.has_permission(b.requires_permission)))
        order by b.sort_order)
      from public.partner_benefits b where b.is_public), '[]'::jsonb),
    'resources_count', (select count(*) from public.partner_resources r where r.is_published),
    'open_support_requests', (select count(*) from public.partner_support_requests s
                               where s.partner_user_id = v_uid and s.status <> 'closed'),
    'announcements', (select count(*) from public.partner_announcements),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'summary', a.summary,
                                                              'created_at', a.created_at)
                                            order by a.created_at desc)
                           from (select * from public.partner_activity pa
                                  where pa.partner_user_id = v_uid
                                  order by pa.created_at desc limit 20) a), '[]'::jsonb),
    'not_implemented', jsonb_build_array(
      jsonb_build_object('key', 'early_access', 'reason', 'Partner early-access feature flags are not implemented'),
      jsonb_build_object('key', 'revenue_share', 'reason', 'Partner revenue sharing and payouts are not implemented')
    )
  );
end;
$$;

create or replace function public.partner_resources_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.partner_profiles pp
                  where pp.user_id = auth.uid() and pp.partner_status = 'active') then
    raise exception 'Active partner account required' using errcode = '42501';
  end if;
  if not coalesce((select is_enabled from public.partner_benefits where key = 'resources'), true) then
    raise exception 'Partner resources are currently disabled';
  end if;
  if not public.has_permission('partner.resources.read') then
    raise exception 'Permission denied: partner.resources.read' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'description', r.description,
                                        'category', r.category, 'url', r.url, 'created_at', r.created_at)
                     order by r.created_at desc)
    from public.partner_resources r where r.is_published), '[]'::jsonb);
end;
$$;

create or replace function public.partner_support_create(p_subject text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if not exists (select 1 from public.partner_profiles pp
                  where pp.user_id = v_uid and pp.partner_status = 'active') then
    raise exception 'Active partner account required' using errcode = '42501';
  end if;
  if not coalesce((select is_enabled from public.partner_benefits where key = 'support_channel'), true)
     or not public.has_permission('partner.portal') then
    raise exception 'Partner support is not available for this account' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_subject, ''))) not between 3 and 160 then
    raise exception 'Subject must be 3-160 characters';
  end if;
  if char_length(trim(coalesce(p_body, ''))) not between 5 and 4000 then
    raise exception 'Describe your request (5-4000 characters)';
  end if;
  insert into public.partner_support_requests (partner_user_id, subject, body)
  values (v_uid, trim(p_subject), trim(p_body))
  returning id into v_id;
  insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
  values (v_uid, 'support_opened', left('Support request: ' || trim(p_subject), 300), v_uid);
  perform public.write_audit('partner.support.open', 'profile', v_uid::text,
    jsonb_build_object('request_id', v_id));
  return v_id;
end;
$$;

create or replace function public.partner_support_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select jsonb_agg(jsonb_build_object(
                      'id', s.id, 'subject', s.subject, 'body', s.body, 'status', s.status,
                      'response', s.response, 'created_at', s.created_at, 'updated_at', s.updated_at)
                      order by s.created_at desc)
                    from public.partner_support_requests s
                   where s.partner_user_id = auth.uid()), '[]'::jsonb);
$$;

create or replace function public.partner_activity_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'summary', a.summary,
                                                        'created_at', a.created_at)
                                    order by a.created_at desc)
                    from (select * from public.partner_activity pa
                           where pa.partner_user_id = auth.uid()
                           order by pa.created_at desc limit 100) a), '[]'::jsonb);
$$;

create or replace function public.admin_partner_support_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('partners.manage') or public.has_permission('partners.approve')) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'partner_user_id', s.partner_user_id, 'subject', s.subject, 'body', s.body,
      'status', s.status, 'response', s.response, 'created_at', s.created_at,
      'partner_name', p.display_name, 'partner_username', p.username)
      order by case s.status when 'open' then 0 when 'answered' then 1 else 2 end, s.created_at desc)
    from public.partner_support_requests s
    join public.profiles p on p.id = s.partner_user_id), '[]'::jsonb);
end;
$$;

create or replace function public.admin_partner_support_respond(p_request_id uuid, p_response text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.partner_support_requests%rowtype;
begin
  if not (public.has_permission('partners.manage') or public.has_permission('partners.approve')) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_response, ''))) not between 2 and 4000 then
    raise exception 'Write a response (2-4000 characters)';
  end if;
  select * into s from public.partner_support_requests where id = p_request_id for update;
  if not found then
    raise exception 'Support request not found';
  end if;
  update public.partner_support_requests
     set response = trim(p_response), responded_by = auth.uid(),
         status = 'answered', updated_at = now()
   where id = p_request_id;
  perform public.notify_user(
    s.partner_user_id, 'partner_benefit', 'Partner support replied',
    left(trim(p_response), 120),
    jsonb_build_object('request_id', p_request_id),
    'partner_support:' || p_request_id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
  perform public.write_audit('partner.support.respond', 'profile', s.partner_user_id::text,
    jsonb_build_object('request_id', p_request_id));
end;
$$;

create or replace function public.admin_set_partner_benefit(p_key text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('partners.manage.full') or public.is_owner()) then
    raise exception 'Permission denied: partners.manage.full' using errcode = '42501';
  end if;
  if not exists (select 1 from public.partner_benefits where key = p_key) then
    raise exception 'Unknown partner benefit';
  end if;
  update public.partner_benefits
     set is_enabled = p_enabled, updated_by = auth.uid(), updated_at = now()
   where key = p_key;
  update public.platform_settings
     set setting_value = coalesce(setting_value, '{}'::jsonb) || jsonb_build_object(p_key, p_enabled),
         updated_at = now()
   where setting_key = 'partner_benefits_config';
  perform public.write_audit('partner.benefit.set', 'partner_benefit', p_key,
    jsonb_build_object('enabled', p_enabled));
end;
$$;

create or replace function public.admin_set_partner_featured(
  p_user_id uuid,
  p_featured boolean,
  p_until timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('partners.manage.full') or public.has_permission('partners.manage')) then
    raise exception 'Permission denied: partners.manage' using errcode = '42501';
  end if;
  if not exists (select 1 from public.partner_profiles where user_id = p_user_id and partner_status = 'active') then
    raise exception 'Target is not an active partner';
  end if;
  if p_featured
     and not coalesce((select is_enabled from public.partner_benefits where key = 'featured_profile'), true) then
    raise exception 'Featured partner placement is disabled in the partner benefit settings';
  end if;
  perform set_config('bubble.privileged', 'on', true);
  update public.partner_profiles
     set is_featured = p_featured,
         featured_until = case when p_featured then p_until else null end,
         featured_by = case when p_featured then auth.uid() else null end
   where user_id = p_user_id;
  perform set_config('bubble.privileged', 'off', true);
  perform public.write_audit('partner.featured', 'profile', p_user_id::text,
    jsonb_build_object('featured', p_featured, 'until', p_until));
  insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
  values (p_user_id, case when p_featured then 'featured' else 'unfeatured' end,
          case when p_featured then 'Selected as a Featured Partner' else 'Featured placement ended' end,
          auth.uid());
  if p_featured then
    perform public.notify_user(
      p_user_id, 'partner_benefit', 'You are a Featured Partner',
      'BubbleApp selected your partner profile for featured placement',
      jsonb_build_object('until', p_until),
      'partner_featured:' || p_user_id::text || ':' || to_char(now(), 'YYYYMMDD'));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Partner application workflow (draft → submitted → review → decision)
-- ---------------------------------------------------------------------------
alter table public.partner_applications
  add column if not exists submitted_at timestamptz,
  add column if not exists withdrawn_at timestamptz,
  add column if not exists info_requested text,
  add column if not exists info_response text,
  add column if not exists last_resubmitted_at timestamptz;

-- Drafts may be incomplete; submitted applications keep the original validation.
alter table public.partner_applications drop constraint if exists partner_applications_status_check;
alter table public.partner_applications add constraint partner_applications_status_check
  check (status in ('draft', 'pending', 'reviewing', 'additional_info_required', 'approved',
                    'rejected', 'withdrawn', 'suspended', 'terminated'));
alter table public.partner_applications drop constraint if exists partner_applications_full_name_check;
alter table public.partner_applications add constraint partner_applications_full_name_check
  check (char_length(full_name) <= 120 and (status = 'draft' or char_length(full_name) >= 2));
alter table public.partner_applications drop constraint if exists partner_applications_email_check;
alter table public.partner_applications add constraint partner_applications_email_check
  check (char_length(email) <= 320 and (status = 'draft' or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'));
alter table public.partner_applications drop constraint if exists partner_applications_organization_check;
alter table public.partner_applications add constraint partner_applications_organization_check
  check (char_length(organization) <= 120 and (status = 'draft' or char_length(organization) >= 2));
alter table public.partner_applications drop constraint if exists partner_applications_partnership_category_check;
alter table public.partner_applications add constraint partner_applications_partnership_category_check
  check (char_length(partnership_category) <= 60 and (status = 'draft' or char_length(partnership_category) >= 2));
alter table public.partner_applications drop constraint if exists partner_applications_proposal_check;
alter table public.partner_applications add constraint partner_applications_proposal_check
  check (char_length(proposal) <= 4000 and (status = 'draft' or char_length(proposal) >= 30));

update public.partner_applications
   set submitted_at = coalesce(submitted_at, created_at)
 where submitted_at is null and status <> 'draft';

drop index if exists partner_applications_one_open;
create unique index if not exists partner_applications_one_open
  on public.partner_applications (applicant_id)
  where status in ('pending', 'reviewing', 'additional_info_required');
create unique index if not exists partner_applications_one_draft
  on public.partner_applications (applicant_id) where status = 'draft';

create table if not exists public.partner_application_events (
  id             bigint generated always as identity primary key,
  application_id uuid not null references public.partner_applications (id) on delete cascade,
  actor_id       uuid references public.profiles (id) on delete set null,
  action         text not null,
  from_status    text,
  to_status      text,
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists partner_application_events_app
  on public.partner_application_events (application_id, created_at);
create trigger partner_application_events_immutable before update or delete on public.partner_application_events
  for each row execute function public.reject_audit_mutation();

create table if not exists public.partner_application_documents (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.partner_applications (id) on delete cascade,
  uploaded_by    uuid not null references public.profiles (id) on delete cascade,
  storage_path   text not null unique,
  doc_type       text not null check (doc_type in ('business_registration', 'identity', 'authorization', 'portfolio', 'other')),
  mime_type      text not null,
  size_bytes     bigint not null check (size_bytes > 0),
  created_at     timestamptz not null default now()
);
create index if not exists partner_application_documents_app on public.partner_application_documents (application_id);
alter table public.partner_application_documents enable row level security;
revoke all on public.partner_application_documents from anon, authenticated;
grant select on public.partner_application_documents to authenticated;
drop policy if exists partner_application_documents_read on public.partner_application_documents;
create policy partner_application_documents_read on public.partner_application_documents for select to authenticated
  using (
    uploaded_by = auth.uid()
    or public.has_permission('partners.approve')
    or public.has_permission('partners.manage')
  );

alter table public.partner_application_events enable row level security;
revoke all on public.partner_application_events from anon, authenticated;
grant select on public.partner_application_events to authenticated;
drop policy if exists partner_application_events_read on public.partner_application_events;
create policy partner_application_events_read on public.partner_application_events for select to authenticated
  using (
    exists (select 1 from public.partner_applications a
             where a.id = application_id and a.applicant_id = auth.uid())
    or public.has_permission('partners.approve')
    or public.has_permission('partners.manage')
  );

create or replace function public.partner_application_requirements()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'is_open', public.setting_bool('partner_applications_open', true)
      and not exists (select 1 from public.partner_profiles pp
                       where pp.user_id = auth.uid() and pp.partner_status = 'active'),
    'requirements', coalesce(
      (select setting_value #>> '{}' from public.platform_settings where setting_key = 'partner_application_guidance'),
      'Introduce yourself and your organisation, describe how you work with creators and businesses, and share links that prove your track record. Applications are reviewed by the BubbleApp team.'),
    'categories', coalesce(
      (select setting_value from public.platform_settings where setting_key = 'partner_categories'),
      '["Creator","Agency","Technology","Retail","Education","Media","Nonprofit","Other"]'::jsonb),
    'min_account_age_days', coalesce(
      (select (setting_value)::text::int from public.platform_settings where setting_key = 'partner_min_account_age_days'), 7),
    'max_applications_per_90_days', coalesce(
      (select (setting_value)::text::int from public.platform_settings where setting_key = 'partner_max_applications_per_90_days'), 3),
    'cooldown_days', coalesce(
      (select (setting_value)::text::int from public.platform_settings where setting_key = 'partner_application_cooldown_days'), 7),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'title', title,
                                                              'description', description))
                           from public.partner_benefits where is_public and is_enabled), '[]'::jsonb)
  );
$$;

create or replace function public.partner_application_save_draft(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_profile public.profiles%rowtype;
  v_full_name text;
  v_username text;
  v_email text;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'terminated') then
    raise exception 'Your partner status was terminated and cannot be re-applied for';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'active') then
    raise exception 'You are already an active BubbleApp Partner';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Invalid partner application draft';
  end if;
  select * into v_profile from public.profiles where id = v_uid;
  v_full_name := left(coalesce(nullif(trim(p_payload ->> 'full_name'), ''),
                               nullif(v_profile.display_name, ''), v_profile.username), 120);
  v_username := left(lower(coalesce(nullif(trim(p_payload ->> 'username'), ''), v_profile.username)), 32);
  v_email := left(coalesce(nullif(trim(p_payload ->> 'email'), ''), nullif(v_profile.email, ''), ''), 320);

  if char_length(coalesce(p_payload ->> 'organization', '')) > 120
     or char_length(coalesce(p_payload ->> 'proposal', '')) > 4000
     or char_length(coalesce(p_payload ->> 'description', '')) > 2000
     or char_length(coalesce(p_payload ->> 'partnership_category', '')) > 60
     or char_length(coalesce(p_payload ->> 'website', '')) > 300 then
    raise exception 'One of the application fields is too long';
  end if;
  if coalesce(p_payload ->> 'social_media', '') <> '' and jsonb_typeof(p_payload -> 'social_media') <> 'object' then
    raise exception 'Supporting links must be an object';
  end if;

  select id into v_id from public.partner_applications where applicant_id = v_uid and status = 'draft';
  if v_id is null then
    insert into public.partner_applications (
      applicant_id, full_name, username, email, organization, website, social_media,
      partnership_category, proposal, description, status
    ) values (
      v_uid, v_full_name, v_username, v_email,
      coalesce(trim(p_payload ->> 'organization'), ''),
      nullif(trim(coalesce(p_payload ->> 'website', '')), ''),
      case when jsonb_typeof(p_payload -> 'social_media') = 'object'
           then p_payload -> 'social_media' else '{}'::jsonb end,
      coalesce(trim(p_payload ->> 'partnership_category'), ''),
      coalesce(p_payload ->> 'proposal', ''),
      coalesce(p_payload ->> 'description', ''),
      'draft'
    ) returning id into v_id;
    insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status)
    values (v_id, v_uid, 'draft_created', null, 'draft');
  else
    update public.partner_applications set
      full_name = v_full_name,
      username = v_username,
      email = v_email,
      organization = coalesce(p_payload ->> 'organization', organization),
      website = case when p_payload ? 'website' then nullif(trim(p_payload ->> 'website'), '') else website end,
      social_media = case when p_payload ? 'social_media' and jsonb_typeof(p_payload -> 'social_media') = 'object'
                          then p_payload -> 'social_media' else social_media end,
      partnership_category = coalesce(p_payload ->> 'partnership_category', partnership_category),
      proposal = coalesce(p_payload ->> 'proposal', proposal),
      description = coalesce(p_payload ->> 'description', description)
    where id = v_id and applicant_id = v_uid;
  end if;
  return v_id;
end;
$$;

create or replace function public.partner_application_submit(p_application_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_app public.partner_applications%rowtype;
  v_max int;
  v_cooldown int;
  v_min_age int;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if not public.setting_bool('partner_applications_open', true) then
    raise exception 'Partner applications are currently closed';
  end if;
  select * into v_app from public.partner_applications
   where id = p_application_id and applicant_id = v_uid for update;
  if not found then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if v_app.status <> 'draft' then
    raise exception 'Only a draft can be submitted';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'active') then
    raise exception 'You are already an active BubbleApp Partner';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'terminated') then
    raise exception 'Your partner status was terminated and cannot be re-applied for';
  end if;

  v_min_age := coalesce((select (setting_value)::text::int from public.platform_settings
                          where setting_key = 'partner_min_account_age_days'), 7);
  if exists (select 1 from public.profiles p
              where p.id = v_uid and p.created_at > now() - make_interval(days => v_min_age)) then
    raise exception 'Your account must be at least % days old before applying', v_min_age;
  end if;
  v_max := coalesce((select (setting_value)::text::int from public.platform_settings
                      where setting_key = 'partner_max_applications_per_90_days'), 3);
  if (select count(*) from public.partner_applications
       where applicant_id = v_uid and status <> 'draft'
         and submitted_at >= now() - interval '90 days') >= v_max then
    raise exception 'Application limit reached. Contact BubbleApp support if you need to re-apply.';
  end if;
  v_cooldown := coalesce((select (setting_value)::text::int from public.platform_settings
                           where setting_key = 'partner_application_cooldown_days'), 7);
  if exists (select 1 from public.partner_applications
              where applicant_id = v_uid and status in ('rejected', 'withdrawn')
                and coalesce(withdrawn_at, reviewed_at, updated_at) > now() - make_interval(days => v_cooldown)) then
    raise exception 'Please wait % days after a rejected or withdrawn application before re-applying', v_cooldown;
  end if;

  if char_length(trim(v_app.full_name)) < 2 then raise exception 'Your full name is required'; end if;
  if v_app.email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid contact email is required'; end if;
  if char_length(trim(v_app.organization)) < 2 then raise exception 'Organisation is required'; end if;
  if char_length(trim(v_app.partnership_category)) < 2 then raise exception 'Partnership category is required'; end if;
  if char_length(trim(v_app.proposal)) < 30 then raise exception 'Describe your proposal in at least 30 characters'; end if;

  update public.partner_applications
     set status = 'pending', submitted_at = now(), updated_at = now()
   where id = p_application_id;
  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status)
  values (p_application_id, v_uid, 'submitted', 'draft', 'pending');
  perform public.write_audit('partner.application.submit', 'partner_application', p_application_id::text, '{}'::jsonb);
  perform public.notify_user(
    v_uid, 'partner_application', 'Partner application submitted',
    'Your application is queued for review',
    jsonb_build_object('application_id', p_application_id),
    'partner_app_submitted:' || p_application_id::text);
  return 'pending';
end;
$$;

create or replace function public.partner_application_withdraw(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_app public.partner_applications%rowtype;
begin
  select * into v_app from public.partner_applications
   where id = p_application_id and applicant_id = v_uid for update;
  if not found then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if v_app.status not in ('draft', 'pending', 'reviewing', 'additional_info_required') then
    raise exception 'This application can no longer be withdrawn';
  end if;
  update public.partner_applications
     set status = 'withdrawn', withdrawn_at = now(), updated_at = now()
   where id = p_application_id;
  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status)
  values (p_application_id, v_uid, 'withdrawn', v_app.status, 'withdrawn');
  perform public.write_audit('partner.application.withdraw', 'partner_application', p_application_id::text, '{}'::jsonb);
end;
$$;

create or replace function public.partner_application_respond_info(p_application_id uuid, p_response text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_app public.partner_applications%rowtype;
begin
  if char_length(trim(coalesce(p_response, ''))) not between 2 and 2000 then
    raise exception 'Write your response (2-2000 characters)';
  end if;
  select * into v_app from public.partner_applications
   where id = p_application_id and applicant_id = v_uid for update;
  if not found then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if v_app.status <> 'additional_info_required' then
    raise exception 'This application is not waiting for information';
  end if;
  update public.partner_applications
     set status = 'reviewing', info_response = trim(p_response),
         last_resubmitted_at = now(), updated_at = now()
   where id = p_application_id;
  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, v_uid, 'info_provided', v_app.status, 'reviewing', left(trim(p_response), 2000));
  perform public.write_audit('partner.application.info', 'partner_application', p_application_id::text, '{}'::jsonb);
end;
$$;

create or replace function public.partner_application_add_document(
  p_application_id uuid,
  p_storage_path text,
  p_doc_type text,
  p_mime_type text,
  p_size_bytes bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_app public.partner_applications%rowtype;
  v_id uuid;
begin
  select * into v_app from public.partner_applications
   where id = p_application_id and applicant_id = v_uid;
  if not found then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if v_app.status not in ('draft', 'pending', 'additional_info_required') then
    raise exception 'Documents can no longer be added to this application';
  end if;
  if coalesce(p_storage_path, '') not like v_uid::text || '/%' or p_storage_path like '%..%' then
    raise exception 'Invalid storage path';
  end if;
  if p_doc_type not in ('business_registration', 'identity', 'authorization', 'portfolio', 'other') then
    raise exception 'Invalid document type';
  end if;
  if p_mime_type not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') then
    raise exception 'Only JPEG, PNG, WebP or PDF documents are accepted';
  end if;
  if p_size_bytes is null or p_size_bytes <= 0 or p_size_bytes > 10485760 then
    raise exception 'Documents must be smaller than 10 MB';
  end if;
  insert into public.partner_application_documents (application_id, uploaded_by, storage_path,
                                                    doc_type, mime_type, size_bytes)
  values (p_application_id, v_uid, p_storage_path, p_doc_type, p_mime_type, p_size_bytes)
  on conflict (storage_path) do update set doc_type = excluded.doc_type
  returning id into v_id;
  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status)
  values (p_application_id, v_uid, 'document_added', v_app.status, v_app.status);
  return v_id;
end;
$$;

create or replace function public.partner_request_information(p_application_id uuid, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.partner_applications%rowtype;
begin
  if not public.has_permission('partners.approve') then
    raise exception 'Permission denied: partners.approve' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_message, ''))) not between 5 and 2000 then
    raise exception 'Describe the information you need (5-2000 characters)';
  end if;
  select * into v_app from public.partner_applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.applicant_id = auth.uid() then
    raise exception 'You cannot review your own partner application' using errcode = '42501';
  end if;
  if v_app.status not in ('pending', 'reviewing') then
    raise exception 'Information can only be requested for an open application';
  end if;
  update public.partner_applications
     set status = 'additional_info_required', info_requested = trim(p_message),
         reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
   where id = p_application_id;
  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, auth.uid(), 'info_requested', v_app.status, 'additional_info_required',
          left(trim(p_message), 2000));
  perform public.write_audit('partner.application.request_info', 'partner_application',
    p_application_id::text, jsonb_build_object('applicant_id', v_app.applicant_id));
  perform public.notify_user(
    v_app.applicant_id, 'partner_application', 'More information needed',
    left(trim(p_message), 160),
    jsonb_build_object('application_id', p_application_id),
    'partner_info:' || p_application_id::text || ':' || to_char(now(), 'YYYYMMDDHH24'));
end;
$$;

-- Reviewer decisions: extended for the new statuses, notifications and activity.
create or replace function public.review_partner_application(
  p_application_id uuid,
  p_action text,
  p_category text default null,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_app public.partner_applications%rowtype;
  v_new text;
  v_display text;
begin
  select * into v_app from public.partner_applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.applicant_id = v_actor then
    raise exception 'You cannot review your own partner application' using errcode = '42501';
  end if;

  if p_action in ('start_review', 'approve', 'reject', 'request_info') then
    if not public.has_permission('partners.approve') then
      raise exception 'Permission denied: partners.approve' using errcode = '42501';
    end if;
  elsif p_action in ('suspend', 'terminate', 'restore') then
    if not public.has_permission('partners.manage') then
      raise exception 'Permission denied: partners.manage' using errcode = '42501';
    end if;
  else
    raise exception 'Unknown action';
  end if;

  -- partner_profiles status/category/featured columns are guard-protected.
  perform set_config('bubble.privileged', 'on', true);

  case p_action
    when 'start_review' then
      if v_app.status not in ('pending', 'additional_info_required') then
        raise exception 'Only open applications can start review';
      end if;
      v_new := 'reviewing';
    when 'approve' then
      if v_app.status not in ('pending', 'reviewing') then raise exception 'Application is closed'; end if;
      if p_category is null or char_length(trim(p_category)) < 2 then
        raise exception 'Assign a partner category before approval';
      end if;
      v_new := 'approved';
    when 'reject' then
      if v_app.status not in ('pending', 'reviewing', 'additional_info_required') then
        raise exception 'Application is closed';
      end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'A rejection reason is required'; end if;
      v_new := 'rejected';
    when 'request_info' then
      if v_app.status not in ('pending', 'reviewing') then
        raise exception 'Information can only be requested for an open application';
      end if;
      if p_note is null or char_length(trim(p_note)) < 5 then
        raise exception 'Describe the information you need';
      end if;
      v_new := 'additional_info_required';
    when 'suspend' then
      if v_app.status <> 'approved' then raise exception 'Only approved partners can be suspended'; end if;
      v_new := 'suspended';
    when 'terminate' then
      if v_app.status not in ('approved', 'suspended') then raise exception 'Only active partners can be terminated'; end if;
      v_new := 'terminated';
    when 'restore' then
      if v_app.status <> 'suspended' then raise exception 'Only suspended partners can be restored'; end if;
      v_new := 'approved';
  end case;

  update public.partner_applications
     set status = v_new, reviewed_by = v_actor, reviewed_at = now(),
         decision_note = coalesce(p_note, decision_note),
         info_requested = case when p_action = 'request_info' then trim(p_note) else info_requested end
   where id = p_application_id;

  if p_action = 'approve' then
    v_display := coalesce(nullif(v_app.full_name, ''), v_app.username);
    insert into public.partner_profiles (user_id, partner_category, partner_status, display_name, website, approved_by)
    values (v_app.applicant_id, trim(p_category), 'active', left(v_display, 80), v_app.website, v_actor)
    on conflict (user_id) do update
      set partner_category = excluded.partner_category, partner_status = 'active',
          status_reason = null, approved_by = excluded.approved_by, approved_at = now();
    perform public.grant_role(v_app.applicant_id, 'partner', v_actor);
    insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
    values (v_app.applicant_id, 'approved', 'Partner application approved', v_actor);
  elsif p_action in ('suspend', 'terminate') then
    update public.partner_profiles
       set partner_status = case when p_action = 'suspend' then 'suspended' else 'terminated' end,
           status_reason = p_note
     where user_id = v_app.applicant_id;
    perform public.revoke_role(v_app.applicant_id, 'partner', v_actor);
    insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
    values (v_app.applicant_id, p_action, 'Partner account ' || v_new, v_actor);
  elsif p_action = 'restore' then
    update public.partner_profiles set partner_status = 'active', status_reason = null
     where user_id = v_app.applicant_id;
    perform public.grant_role(v_app.applicant_id, 'partner', v_actor);
    insert into public.partner_activity (partner_user_id, kind, summary, actor_id)
    values (v_app.applicant_id, 'restored', 'Partner account restored', v_actor);
  end if;

  insert into public.partner_application_events (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, v_actor, p_action, v_app.status, v_new, left(p_note, 2000));

  perform public.write_audit('partner.' || p_action, 'partner_application', p_application_id::text,
    jsonb_build_object('applicant_id', v_app.applicant_id, 'from', v_app.status, 'to', v_new, 'category', p_category));

  if p_action in ('approve', 'reject', 'request_info', 'suspend', 'terminate', 'restore') then
    perform public.notify_user(
      v_app.applicant_id, 'partner_application',
      case p_action
        when 'approve' then 'Partner application approved'
        when 'reject' then 'Partner application not approved'
        when 'request_info' then 'More information needed'
        when 'suspend' then 'Partner account suspended'
        when 'terminate' then 'Partner account terminated'
        else 'Partner account restored' end,
      coalesce(nullif(trim(p_note), ''),
               case p_action when 'approve' then 'Welcome to the BubbleApp Partner Program' else 'Status updated' end),
      jsonb_build_object('application_id', p_application_id, 'status', v_new),
      'partner_decision:' || p_application_id::text || ':' || v_new);
  end if;
  perform set_config('bubble.privileged', 'off', true);
  return v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. Partner profile guards + directory visibility
-- ---------------------------------------------------------------------------
create or replace function public.guard_partner_profile_privileged()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.privileged_write_enabled() or current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if new.partner_status is distinct from old.partner_status
     or new.partner_category is distinct from old.partner_category
     or new.is_featured is distinct from old.is_featured
     or new.featured_until is distinct from old.featured_until
     or new.featured_by is distinct from old.featured_by
     or new.approved_by is distinct from old.approved_by
     or new.approved_at is distinct from old.approved_at then
    raise exception 'Partner status, category and featured placement are controlled by BubbleApp'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists partner_profiles_guard on public.partner_profiles;
create trigger partner_profiles_guard before update on public.partner_profiles
  for each row execute function public.guard_partner_profile_privileged();

drop policy if exists partner_profiles_select on public.partner_profiles;
create policy partner_profiles_select on public.partner_profiles for select to authenticated using (
  (partner_status = 'active' and (directory_visible or badge_enabled))
  or user_id = auth.uid()
  or public.has_permission('partners.manage')
  or public.has_permission('partners.approve')
);

-- ---------------------------------------------------------------------------
-- 17. Plan limits (settings-driven, enforced server-side)
-- ---------------------------------------------------------------------------
create or replace function public.enforce_business_team_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_limit int := coalesce((select (setting_value)::text::int from public.platform_settings
                            where setting_key = 'business_team_max_members'), 10);
begin
  if (select count(*) from public.business_members where business_id = new.business_id) >= v_limit then
    raise exception 'Business team limit reached (% members)', v_limit;
  end if;
  return new;
end;
$$;
drop trigger if exists business_members_limit on public.business_members;
create trigger business_members_limit before insert on public.business_members
  for each row execute function public.enforce_business_team_limit();

create or replace function public.enforce_catalog_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_limit int := coalesce((select (setting_value)::text::int from public.platform_settings
                            where setting_key = 'business_catalog_max_items'), 200);
begin
  if (select count(*) from public.business_catalog_items where business_id = new.business_id) >= v_limit then
    raise exception 'Catalog limit reached (% listings)', v_limit;
  end if;
  return new;
end;
$$;
drop trigger if exists business_catalog_limit on public.business_catalog_items;
create trigger business_catalog_limit before insert on public.business_catalog_items
  for each row execute function public.enforce_catalog_limit();

-- ---------------------------------------------------------------------------
-- 18. Platform settings for Part 8
-- ---------------------------------------------------------------------------
insert into public.platform_settings (setting_key, setting_value, is_public, is_protected) values
  ('business_inquiries_enabled',   'true',  true,  false),
  ('business_team_max_members',    '10',    false, false),
  ('business_catalog_max_items',   '200',   false, false),
  ('business_verification_requirements',
    '{"require_documents":true,"min_documents":1,"accepted_doc_types":["business_registration","authorization","website_proof"],"sla_hours":72}',
    true, false),
  ('partner_directory_enabled',    'true',  true,  false),
  ('partner_min_account_age_days', '7',     false, false),
  ('partner_max_applications_per_90_days', '3', false, false),
  ('partner_application_cooldown_days', '7', false, false),
  ('partner_categories',
    '["Creator","Agency","Technology","Retail","Education","Media","Nonprofit","Other"]', true, false),
  ('partner_application_guidance',
    '"Introduce yourself and your organisation, describe how you work with creators and businesses, and share links that prove your track record. Applications are reviewed by the BubbleApp team."',
    true, false)
on conflict (setting_key) do nothing;

-- ---------------------------------------------------------------------------
-- 19. Storage: partner media/documents + permission-aware business media
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('partner-media',     'partner-media',     true,  10485760,
     array['image/jpeg', 'image/png', 'image/webp']),
  ('partner-documents', 'partner-documents', false, 10485760,
     array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bubble_public_media_read on storage.objects;
create policy bubble_public_media_read on storage.objects for select to anon, authenticated
  using (bucket_id in ('avatars', 'profile-covers', 'business-media', 'partner-media', 'hashtags'));

drop policy if exists bubble_business_media_write on storage.objects;
create policy bubble_business_media_write on storage.objects for insert to authenticated
  with check (
    bucket_id = 'business-media'
    and (
      public.has_business_permission(public.storage_folder_uuid(name), 'profile.media')
      or public.has_business_permission(public.storage_folder_uuid(name), 'catalog.manage')
    )
  );
drop policy if exists bubble_business_media_delete on storage.objects;
create policy bubble_business_media_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'business-media'
    and (
      public.has_business_permission(public.storage_folder_uuid(name), 'profile.media')
      or public.has_business_permission(public.storage_folder_uuid(name), 'catalog.manage')
    )
  );

drop policy if exists bubble_partner_media_write on storage.objects;
create policy bubble_partner_media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'partner-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists bubble_partner_media_delete on storage.objects;
create policy bubble_partner_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'partner-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists bubble_partner_documents_read on storage.objects;
create policy bubble_partner_documents_read on storage.objects for select to authenticated
  using (
    bucket_id = 'partner-documents'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.has_permission('partners.approve')
      or public.has_permission('partners.manage')
    )
  );
drop policy if exists bubble_partner_documents_write on storage.objects;
create policy bubble_partner_documents_write on storage.objects for insert to authenticated
  with check (bucket_id = 'partner-documents' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists bubble_partner_documents_delete on storage.objects;
create policy bubble_partner_documents_delete on storage.objects for delete to authenticated
  using (bucket_id = 'partner-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 20. Realtime for live business inbox / invites / partner queue
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['business_inquiries', 'business_team_invites', 'business_customers',
                             'partner_applications', 'partner_support_requests'] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception when duplicate_object then null;
                  when others then null;
      end;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 21. Function grants (client-callable API surface)
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
  fns text[] := array[
    'public.business_my_businesses()',
    'public.business_public_profile(uuid)',
    'public.business_update_profile(uuid, jsonb)',
    'public.business_setup_progress(uuid)',
    'public.business_analytics(uuid, int)',
    'public.business_record_event(uuid, text, uuid)',
    'public.business_follow(uuid, boolean)',
    'public.business_badge_visible(uuid)',
    'public.has_business_permission(uuid, text)',
    'public.business_permissions_for(uuid)',
    'public.business_team_invite(uuid, text, text, text)',
    'public.business_invite_respond(uuid, boolean)',
    'public.business_team_set_role(uuid, uuid, text)',
    'public.business_team_remove(uuid, uuid)',
    'public.business_team_set_permission(uuid, uuid, text, boolean)',
    'public.business_team_list(uuid)',
    'public.business_team_revoke_invite(uuid)',
    'public.my_business_invites()',
    'public.business_catalog_save(uuid, uuid, text, text, text, text, int, text, text, jsonb, text, int, text, jsonb)',
    'public.business_catalog_set_status(uuid, text)',
    'public.business_catalog_delete(uuid)',
    'public.business_catalog_share(uuid)',
    'public.business_catalog_list(uuid, text, text, text, text, text, int, int)',
    'public.business_catalog_public(uuid, text, text, text, text, int, int)',
    'public.business_catalog_detail(uuid)',
    'public.business_catalog_categories(uuid)',
    'public.business_post_create(uuid, text, text, text[], uuid, text)',
    'public.business_post_delete(uuid)',
    'public.business_inquiry_start(uuid, text, uuid, text)',
    'public.business_inquiry_list(uuid, text, text, int)',
    'public.business_inquiry_detail(uuid)',
    'public.business_inquiry_set_status(uuid, text, text)',
    'public.business_inquiry_assign(uuid, uuid)',
    'public.business_inquiry_set_priority(uuid, text)',
    'public.my_business_inquiries()',
    'public.business_customer_list(uuid, text, uuid, text, int)',
    'public.business_customer_detail(uuid)',
    'public.business_customer_update(uuid, jsonb)',
    'public.business_customer_set_labels(uuid, uuid[])',
    'public.business_label_list(uuid)',
    'public.business_label_save(uuid, text, text)',
    'public.business_label_delete(uuid)',
    'public.business_verification_state(uuid)',
    'public.verification_respond_info(uuid, text)',
    'public.partner_application_requirements()',
    'public.partner_application_save_draft(jsonb)',
    'public.partner_application_submit(uuid)',
    'public.partner_application_withdraw(uuid)',
    'public.partner_application_respond_info(uuid, text)',
    'public.partner_application_add_document(uuid, text, text, text, bigint)',
    'public.partner_directory(text, text, boolean, int, int)',
    'public.partner_public_profile(uuid)',
    'public.partner_profile_update(jsonb)',
    'public.partner_my_benefits()',
    'public.partner_badge_visible(uuid)',
    'public.partner_resources_list()',
    'public.partner_support_create(text, text)',
    'public.partner_support_list()',
    'public.partner_activity_list()',
    'public.admin_partner_support_list()',
    'public.admin_partner_support_respond(uuid, text)',
    'public.admin_set_partner_benefit(text, boolean)',
    'public.admin_set_partner_featured(uuid, boolean, timestamptz)',
    'public.partner_request_information(uuid, text)'
  ];
begin
  foreach f in array fns loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- Internal helpers stay server-side.
revoke execute on function public.business_user_has_permission(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.guard_business_member_write() from public, anon, authenticated;
revoke execute on function public.guard_business_member_permission_write() from public, anon, authenticated;
revoke execute on function public.guard_business_privileged_columns() from public, anon, authenticated;
revoke execute on function public.guard_partner_profile_privileged() from public, anon, authenticated;
revoke execute on function public.sync_business_follower_count() from public, anon, authenticated;
revoke execute on function public.on_business_message_activity() from public, anon, authenticated;
revoke execute on function public.sync_business_catalog_status() from public, anon, authenticated;
