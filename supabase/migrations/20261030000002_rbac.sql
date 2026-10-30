-- =============================================================================
-- BubbleApp :: 0002 RBAC, admin assignments, immutable audit logs
-- Permission-based access: every sensitive action calls has_permission() or a
-- rank check inside a SECURITY DEFINER function. Role names are never trusted
-- from the client.
-- =============================================================================

create table if not exists public.permissions (
  key          text primary key,
  description  text not null,
  scope        text not null default 'platform' check (scope in ('platform', 'partner')),
  owner_only   boolean not null default false
);

create table if not exists public.platform_roles (
  key           text primary key,
  display_name  text not null,
  rank          integer not null,
  is_staff      boolean not null default false,
  is_protected  boolean not null default false
);

create table if not exists public.role_permissions (
  role_key        text not null references public.platform_roles (key) on delete cascade,
  permission_key  text not null references public.permissions (key) on delete cascade,
  primary key (role_key, permission_key)
);

create table if not exists public.user_roles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role_key     text not null references public.platform_roles (key),
  assigned_by  uuid references auth.users (id) on delete set null,
  assigned_at  timestamptz not null default now(),
  revoked_at   timestamptz,
  revoked_by   uuid references auth.users (id) on delete set null
);
create unique index if not exists user_roles_active_key
  on public.user_roles (user_id, role_key) where revoked_at is null;
create index if not exists user_roles_user_idx on public.user_roles (user_id);
-- Exactly one active Owner at any time (the protected root of the permission model).
create unique index if not exists user_roles_single_owner
  on public.user_roles (role_key) where role_key = 'owner' and revoked_at is null;

create table if not exists public.admin_assignments (
  user_id          uuid primary key references public.profiles (id) on delete cascade,
  status           text not null default 'active' check (status in ('active', 'suspended', 'revoked')),
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  status_changed_at timestamptz not null default now(),
  status_reason    text
);

-- Per-administrator overrides. granted = true adds a permission, false denies one.
create table if not exists public.user_permission_grants (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  permission_key  text not null references public.permissions (key) on delete cascade,
  granted         boolean not null,
  granted_by      uuid references auth.users (id) on delete set null,
  granted_at      timestamptz not null default now(),
  unique (user_id, permission_key)
);

-- Audit logs are append-only. Updates and deletes are rejected for everyone.
create table if not exists public.admin_audit_logs (
  id           bigint generated always as identity primary key,
  actor_id     uuid,
  action       text not null,
  target_type  text not null,
  target_id    text,
  metadata     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create table if not exists public.owner_audit_logs (
  id           bigint generated always as identity primary key,
  actor_id     uuid,
  action       text not null,
  target_type  text not null,
  target_id    text,
  metadata     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists admin_audit_logs_actor_idx on public.admin_audit_logs (actor_id, created_at desc);
create index if not exists owner_audit_logs_created_idx on public.owner_audit_logs (created_at desc);

create or replace function public.reject_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Audit log rows are immutable' using errcode = '42501';
end;
$$;
create trigger admin_audit_immutable before update or delete on public.admin_audit_logs
  for each row execute function public.reject_audit_mutation();
create trigger owner_audit_immutable before update or delete on public.owner_audit_logs
  for each row execute function public.reject_audit_mutation();

-- ---------------------------------------------------------------------------
-- Seed: permissions, roles, role→permission mapping
-- ---------------------------------------------------------------------------
insert into public.permissions (key, description, scope, owner_only) values
  ('owner.manage',          'Full platform ownership: protected settings, owner-only roles', 'platform', true),
  ('admins.create',         'Promote existing accounts to administrator roles',             'platform', false),
  ('admins.manage',         'Edit administrator status and individual permissions',         'platform', false),
  ('users.read',            'View user directory and account details',                      'platform', false),
  ('users.manage',          'Suspend, ban or restore user accounts',                        'platform', false),
  ('users.verify',          'Review user, business and organization verification',          'platform', false),
  ('verification.approve',  'Approve, reject, suspend, revoke or restore verification',     'platform', false),
  ('channels.manage',       'Manage all channels and the official BubbleApp channel',       'platform', false),
  ('channels.verify',       'Review channel verification applications',                     'platform', false),
  ('partners.approve',      'Review and decide partner applications',                       'platform', false),
  ('partners.manage',       'Suspend, terminate, restore partners and set partner rights',  'platform', false),
  ('reports.manage',        'Review and resolve user reports',                              'platform', false),
  ('content.moderate',      'Hide content and handle moderation cases',                     'platform', false),
  ('settings.manage',       'Change non-protected platform settings',                       'platform', false),
  ('analytics.read',        'View platform analytics and dashboards',                       'platform', false),
  ('announcements.manage',  'Publish platform announcements',                               'platform', false),
  ('audit.read',            'Read the administrator audit log',                             'platform', false),
  ('system.read',           'View system health and configuration',                         'platform', false),
  ('partner.portal',        'Access the partner dashboard',                                 'partner',  false),
  ('partner.announcements.read', 'Read partner announcements',                              'partner',  false),
  ('partner.resources.read',     'Access approved partner resources',                       'partner',  false),
  ('partner.profile.manage',     'Manage own partner profile',                              'partner',  false)
on conflict (key) do nothing;

insert into public.platform_roles (key, display_name, rank, is_staff, is_protected) values
  ('owner',             'Owner',             100, true,  true),
  ('super_admin',       'Super Admin',        90, true,  false),
  ('admin',             'Admin',              50, true,  false),
  ('moderator',         'Moderator',          30, true,  false),
  ('partner',           'Partner',             5, false, false),
  ('verified_business', 'Verified Business',   1, false, false),
  ('verified_channel',  'Verified Channel',    1, false, false),
  ('verified_user',     'Verified User',       1, false, false),
  ('user',              'Normal User',         0, false, false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
  select 'owner', key from public.permissions
on conflict do nothing;

insert into public.role_permissions (role_key, permission_key) values
  ('super_admin', 'admins.create'), ('super_admin', 'admins.manage'),
  ('super_admin', 'users.read'), ('super_admin', 'users.manage'), ('super_admin', 'users.verify'),
  ('super_admin', 'verification.approve'), ('super_admin', 'channels.manage'), ('super_admin', 'channels.verify'),
  ('super_admin', 'partners.approve'), ('super_admin', 'partners.manage'),
  ('super_admin', 'reports.manage'), ('super_admin', 'content.moderate'), ('super_admin', 'settings.manage'),
  ('super_admin', 'analytics.read'), ('super_admin', 'announcements.manage'),
  ('super_admin', 'audit.read'), ('super_admin', 'system.read'),
  ('admin', 'users.read'), ('admin', 'reports.manage'), ('admin', 'content.moderate'),
  ('admin', 'analytics.read'), ('admin', 'announcements.manage'),
  ('moderator', 'users.read'), ('moderator', 'reports.manage'), ('moderator', 'content.moderate'),
  ('partner', 'partner.portal'), ('partner', 'partner.announcements.read'),
  ('partner', 'partner.resources.read'), ('partner', 'partner.profile.manage')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Authorization primitives
-- ---------------------------------------------------------------------------
create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_status = 'active'
  );
$$;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role_key = 'owner' and ur.revoked_at is null
  );
$$;

-- Highest active rank of a user. Staff roles only count while the admin assignment is active.
create or replace function public.current_rank(p_user_id uuid default auth.uid())
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(max(r.rank), 0)
  from public.user_roles ur
  join public.platform_roles r on r.key = ur.role_key
  where ur.user_id = p_user_id
    and ur.revoked_at is null
    and (
      not r.is_staff
      or r.key = 'owner'
      or exists (
        select 1 from public.admin_assignments a
        where a.user_id = p_user_id and a.status = 'active'
      )
    );
$$;

create or replace function public.has_permission(p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean;
begin
  if v_uid is null then
    return false;
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.account_status = 'active') then
    return false;
  end if;
  if exists (select 1 from public.user_roles ur
             where ur.user_id = v_uid and ur.role_key = 'owner' and ur.revoked_at is null) then
    return true;
  end if;

  v_is_admin := exists (select 1 from public.admin_assignments a
                        where a.user_id = v_uid and a.status = 'active');

  -- Explicit per-administrator denial always wins.
  if v_is_admin and exists (select 1 from public.user_permission_grants g
                            where g.user_id = v_uid and g.permission_key = p_permission and g.granted = false) then
    return false;
  end if;
  -- Explicit per-administrator grant.
  if v_is_admin and exists (select 1 from public.user_permission_grants g
                            where g.user_id = v_uid and g.permission_key = p_permission and g.granted = true) then
    return true;
  end if;
  -- Role-derived permission (staff roles require an active admin assignment).
  if exists (
    select 1
    from public.user_roles ur
    join public.platform_roles r on r.key = ur.role_key
    join public.role_permissions rp on rp.role_key = ur.role_key
    where ur.user_id = v_uid
      and ur.revoked_at is null
      and rp.permission_key = p_permission
      and (r.is_staff = false or v_is_admin)
  ) then
    return true;
  end if;
  -- Partner-scoped permissions, only while the partner profile is active.
  if exists (
    select 1
    from public.partner_permissions pp
    join public.partner_profiles pr on pr.user_id = pp.user_id
    where pp.user_id = v_uid
      and pp.permission_key = p_permission
      and pp.granted
      and pr.partner_status = 'active'
  ) then
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.write_audit(
  p_action text,
  p_target_type text,
  p_target_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_owner() then
    insert into public.owner_audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_metadata, '{}'::jsonb));
  else
    insert into public.admin_audit_logs (actor_id, action, target_type, target_id, metadata)
    values (auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_metadata, '{}'::jsonb));
  end if;
end;
$$;

-- Owner role can never be granted or revoked through the API (no client grants and
-- this guard for defence in depth).
create or replace function public.guard_owner_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (tg_op = 'INSERT' and new.role_key = 'owner')
     or (tg_op = 'UPDATE' and (old.role_key = 'owner' or new.role_key = 'owner')) then
    if not public.is_trusted_context() then
      raise exception 'The Owner role is provisioned only through trusted server-side setup'
        using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger user_roles_guard_owner before insert or update on public.user_roles
  for each row execute function public.guard_owner_role();

-- ---------------------------------------------------------------------------
-- Administrator management
-- ---------------------------------------------------------------------------

-- Creates or re-activates an administrator for an EXISTING account. Replaces the
-- account's staff role and per-admin permission overrides.
create or replace function public.admin_create_admin(
  p_user_id uuid,
  p_role_key text,
  p_permissions text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role public.platform_roles%rowtype;
  v_perm text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.has_permission('admins.create') then
    raise exception 'Permission denied: admins.create' using errcode = '42501';
  end if;
  if p_user_id = v_actor then
    raise exception 'You cannot change your own administrator assignment';
  end if;
  select * into v_role from public.platform_roles where key = p_role_key;
  if not found or not v_role.is_staff or v_role.is_protected then
    raise exception 'Invalid administrator role: %', p_role_key;
  end if;
  -- Nobody can grant a role at or above their own rank (Owner is the only super_admin creator).
  if v_role.rank >= public.current_rank() then
    raise exception 'You cannot assign a role at or above your own level' using errcode = '42501';
  end if;
  if public.current_rank(p_user_id) >= public.current_rank() then
    raise exception 'You cannot modify a user with an equal or higher role' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.account_status = 'active') then
    raise exception 'The target account must be active';
  end if;

  insert into public.admin_assignments (user_id, status, created_by, status_changed_at)
  values (p_user_id, 'active', v_actor, now())
  on conflict (user_id) do update
    set status = 'active', status_changed_at = now(), status_reason = null, created_by = excluded.created_by;

  -- Single staff role per administrator.
  update public.user_roles ur
     set revoked_at = now(), revoked_by = v_actor
   where ur.user_id = p_user_id
     and ur.revoked_at is null
     and ur.role_key in (select key from public.platform_roles where is_staff)
     and ur.role_key <> p_role_key;

  if not exists (select 1 from public.user_roles ur
                 where ur.user_id = p_user_id and ur.role_key = p_role_key and ur.revoked_at is null) then
    insert into public.user_roles (user_id, role_key, assigned_by)
    values (p_user_id, p_role_key, v_actor);
  end if;

  delete from public.user_permission_grants where user_id = p_user_id;
  foreach v_perm in array coalesce(p_permissions, '{}') loop
    if not exists (select 1 from public.permissions where key = v_perm and scope = 'platform') then
      raise exception 'Unknown platform permission: %', v_perm;
    end if;
    if exists (select 1 from public.permissions where key = v_perm and owner_only)
       and not public.is_owner() then
      raise exception 'Only the Owner can grant %', v_perm using errcode = '42501';
    end if;
    if not public.is_owner() and not public.has_permission(v_perm) then
      raise exception 'You cannot grant a permission you do not hold: %', v_perm using errcode = '42501';
    end if;
    insert into public.user_permission_grants (user_id, permission_key, granted, granted_by)
    values (p_user_id, v_perm, true, v_actor);
  end loop;

  perform public.write_audit('admin.create', 'profile', p_user_id::text,
    jsonb_build_object('role', p_role_key, 'permissions', coalesce(p_permissions, '{}')));
end;
$$;

create or replace function public.admin_set_admin_status(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not public.has_permission('admins.manage') then
    raise exception 'Permission denied: admins.manage' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended', 'revoked') then
    raise exception 'Invalid status';
  end if;
  if p_user_id = v_actor then
    raise exception 'You cannot change your own administrator status';
  end if;
  if not exists (select 1 from public.admin_assignments where user_id = p_user_id) then
    raise exception 'Target is not an administrator';
  end if;
  if public.current_rank(p_user_id) >= public.current_rank() then
    raise exception 'You cannot modify a user with an equal or higher role' using errcode = '42501';
  end if;

  if p_status = 'active' and not exists (
    select 1 from public.user_roles ur
    join public.platform_roles r on r.key = ur.role_key
    where ur.user_id = p_user_id and ur.revoked_at is null and r.is_staff
  ) then
    raise exception 'Assign a staff role with admin_create_admin before re-activating';
  end if;

  update public.admin_assignments
     set status = p_status, status_changed_at = now(), status_reason = p_reason
   where user_id = p_user_id;

  if p_status = 'revoked' then
    update public.user_roles ur
       set revoked_at = now(), revoked_by = v_actor
     where ur.user_id = p_user_id and ur.revoked_at is null
       and ur.role_key in (select key from public.platform_roles where is_staff);
  end if;

  perform public.write_audit('admin.status.' || p_status, 'profile', p_user_id::text,
    jsonb_build_object('reason', p_reason));
end;
$$;

create or replace function public.admin_set_permission(
  p_user_id uuid,
  p_permission text,
  p_mode text   -- 'grant' | 'deny' | 'inherit'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not public.has_permission('admins.manage') then
    raise exception 'Permission denied: admins.manage' using errcode = '42501';
  end if;
  if p_user_id = v_actor then
    raise exception 'You cannot change your own permissions';
  end if;
  if not exists (select 1 from public.admin_assignments where user_id = p_user_id and status <> 'revoked') then
    raise exception 'Target is not an administrator';
  end if;
  if not exists (select 1 from public.permissions where key = p_permission and scope = 'platform') then
    raise exception 'Unknown platform permission: %', p_permission;
  end if;
  if public.current_rank(p_user_id) >= public.current_rank() then
    raise exception 'You cannot modify a user with an equal or higher role' using errcode = '42501';
  end if;
  if exists (select 1 from public.permissions where key = p_permission and owner_only)
     and not public.is_owner() then
    raise exception 'Only the Owner can manage %', p_permission using errcode = '42501';
  end if;

  if p_mode = 'inherit' then
    delete from public.user_permission_grants where user_id = p_user_id and permission_key = p_permission;
  elsif p_mode in ('grant', 'deny') then
    if p_mode = 'grant' and not public.is_owner() and not public.has_permission(p_permission) then
      raise exception 'You cannot grant a permission you do not hold' using errcode = '42501';
    end if;
    insert into public.user_permission_grants (user_id, permission_key, granted, granted_by)
    values (p_user_id, p_permission, p_mode = 'grant', v_actor)
    on conflict (user_id, permission_key) do update
      set granted = excluded.granted, granted_by = excluded.granted_by, granted_at = now();
  else
    raise exception 'Invalid mode';
  end if;

  perform public.write_audit('admin.permission.' || p_mode, 'profile', p_user_id::text,
    jsonb_build_object('permission', p_permission));
end;
$$;

-- Suspend / ban / restore a normal account. Rank rule: target rank must be strictly lower.
create or replace function public.admin_set_account_status(
  p_user_id uuid,
  p_status text,      -- 'active' | 'suspended' | 'banned'
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not public.has_permission('users.manage') then
    raise exception 'Permission denied: users.manage' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended', 'banned') then
    raise exception 'Invalid account status';
  end if;
  if p_user_id = v_actor then
    raise exception 'You cannot change your own account status here';
  end if;
  if public.current_rank(p_user_id) >= public.current_rank() then
    raise exception 'Protected account: this user holds an equal or higher role' using errcode = '42501';
  end if;

  perform set_config('bubble.privileged', 'on', true);
  update public.profiles
     set account_status = p_status, status_reason = p_reason
   where id = p_user_id;
  perform set_config('bubble.privileged', 'off', true);

  perform public.write_audit('user.status.' || p_status, 'profile', p_user_id::text,
    jsonb_build_object('reason', p_reason));
end;
$$;

-- Owner-only bootstrap. Not granted to any API role. Run from SQL editor or a
-- service_role Edge Function with the operator's email address.
create or replace function public.bootstrap_owner(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  if not public.is_trusted_context() then
    raise exception 'bootstrap_owner must run in a trusted server context' using errcode = '42501';
  end if;
  if exists (select 1 from public.user_roles where role_key = 'owner' and revoked_at is null) then
    raise exception 'An Owner already exists';
  end if;
  select id into v_user from public.profiles where lower(email) = lower(trim(p_email));
  if v_user is null then
    raise exception 'Create the account with Email OTP first, then bootstrap it';
  end if;
  insert into public.user_roles (user_id, role_key, assigned_by) values (v_user, 'owner', null);
  insert into public.owner_audit_logs (actor_id, action, target_type, target_id, metadata)
  values (null, 'owner.bootstrap', 'profile', v_user::text, jsonb_build_object('email', p_email));
  return v_user;
end;
$$;

-- ---------------------------------------------------------------------------
-- Platform settings (protected keys require owner.manage)
-- ---------------------------------------------------------------------------
create or replace function public.set_platform_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_setting public.platform_settings%rowtype;
begin
  select * into v_setting from public.platform_settings where setting_key = p_key for update;
  if not found then
    raise exception 'Unknown setting: %', p_key;
  end if;
  if v_setting.is_protected then
    if not public.has_permission('owner.manage') then
      raise exception 'Only the Owner can change %', p_key using errcode = '42501';
    end if;
  elsif not public.has_permission('settings.manage') then
    raise exception 'Permission denied: settings.manage' using errcode = '42501';
  end if;
  if jsonb_typeof(v_setting.setting_value) <> jsonb_typeof(p_value) then
    raise exception 'Value type mismatch for %', p_key;
  end if;

  update public.platform_settings
     set setting_value = p_value, updated_by = auth.uid(), updated_at = now()
   where id = v_setting.id;

  perform public.write_audit('settings.update', 'platform_setting', p_key,
    jsonb_build_object('old', v_setting.setting_value, 'new', p_value));
end;
$$;

create or replace function public.setting_bool(p_key text, p_default boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (setting_value)::text::boolean from public.platform_settings where setting_key = p_key),
    p_default
  );
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security + grants for RBAC tables
-- ---------------------------------------------------------------------------
alter table public.permissions             enable row level security;
alter table public.platform_roles          enable row level security;
alter table public.role_permissions        enable row level security;
alter table public.user_roles              enable row level security;
alter table public.admin_assignments       enable row level security;
alter table public.user_permission_grants  enable row level security;
alter table public.admin_audit_logs        enable row level security;
alter table public.owner_audit_logs        enable row level security;

revoke all on public.permissions, public.platform_roles, public.role_permissions,
  public.user_roles, public.admin_assignments, public.user_permission_grants,
  public.admin_audit_logs, public.owner_audit_logs from anon, authenticated;

grant select on public.permissions, public.platform_roles, public.role_permissions to authenticated;
grant select on public.user_roles, public.admin_assignments, public.user_permission_grants,
  public.admin_audit_logs to authenticated;
grant select on public.owner_audit_logs to authenticated;

create policy permissions_read on public.permissions for select to authenticated using (true);
create policy platform_roles_read on public.platform_roles for select to authenticated using (true);
create policy role_permissions_read on public.role_permissions for select to authenticated using (true);

create policy user_roles_read on public.user_roles for select to authenticated using (
  user_id = auth.uid() or public.has_permission('users.read') or public.has_permission('admins.manage')
);
create policy admin_assignments_read on public.admin_assignments for select to authenticated using (
  user_id = auth.uid() or public.has_permission('admins.manage')
);
create policy user_permission_grants_read on public.user_permission_grants for select to authenticated using (
  user_id = auth.uid() or public.has_permission('admins.manage')
);
create policy admin_audit_logs_read on public.admin_audit_logs for select to authenticated using (
  actor_id = auth.uid() or public.has_permission('audit.read')
);
create policy owner_audit_logs_read on public.owner_audit_logs for select to authenticated using (
  public.has_permission('owner.manage')
);

-- Core table RLS (0001) — enabled here so every table is covered in one place.
alter table public.profiles       enable row level security;
alter table public.businesses     enable row level security;
alter table public.business_members enable row level security;
alter table public.account_modes  enable row level security;
alter table public.user_settings  enable row level security;
alter table public.devices        enable row level security;
alter table public.platform_settings enable row level security;

revoke all on public.profiles, public.businesses, public.business_members, public.account_modes,
  public.user_settings, public.devices, public.platform_settings from anon, authenticated;

-- Profiles: public directory columns only. email is never granted to clients.
grant select (id, username, display_name, avatar_url, cover_url, bio, account_status,
              is_verified, verified_at, created_at, last_seen_at)
  on public.profiles to authenticated;
grant update (username, display_name, avatar_url, cover_url, bio) on public.profiles to authenticated;

create policy profiles_select on public.profiles for select to authenticated using (
  account_status = 'active' or id = auth.uid() or public.has_permission('users.read')
);
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Platform settings: public keys readable, everything else staff only.
grant select on public.platform_settings to authenticated;
create policy platform_settings_read on public.platform_settings for select to authenticated using (
  is_public or public.has_permission('settings.manage')
);
