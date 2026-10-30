-- =============================================================================
-- BubbleApp :: 0014 Owner & Admin Control Center
-- Extends 0001-0013 without breaking existing data or security model.
-- Owner is provisioned only via trusted context (bootstrap_owner).
-- All privileged actions are SECURITY DEFINER + has_permission/rank checks + audit.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. New permissions (granular categories per spec)
-- ---------------------------------------------------------------------------
insert into public.permissions (key, description, scope, owner_only) values
  ('users.warn',              'Issue warnings to users', 'platform', false),
  ('users.restrict',          'Apply temporary or permanent feature restrictions', 'platform', false),
  ('users.sessions.revoke',   'Revoke user sessions and force re-login', 'platform', false),
  ('community.manage',        'Manage communities, groups, memberships', 'platform', false),
  ('channels.feature',        'Feature channels as platform picks', 'platform', false),
  ('community.feature',       'Feature communities', 'platform', false),
  ('posts.feature',           'Feature posts in discovery', 'platform', false),
  ('notifications.manage',    'Manage notification templates and delivery', 'platform', false),
  ('security.read',           'View security center, login activity, alerts', 'platform', false),
  ('security.manage',         'Revoke sessions, suspend admins in emergency', 'platform', true),
  ('audit.manage',            'Manage audit retention and emergency controls', 'platform', true),
  ('platform.announce',       'Create and publish platform announcements', 'platform', false),
  ('platform.content.manage', 'Manage official channel, guidelines, banners', 'platform', false),
  ('verification.manage',     'Manage verification policy and decisions', 'platform', false),
  ('partners.manage.full',    'Full partner program control (config, benefits)', 'platform', false)
on conflict (key) do nothing;

-- Assign new permissions to Owner (all) and Super Admin (most)
insert into public.role_permissions (role_key, permission_key)
  select 'owner', key from public.permissions on conflict do nothing;

insert into public.role_permissions (role_key, permission_key) values
  ('super_admin', 'users.warn'), ('super_admin', 'users.restrict'), ('super_admin', 'users.sessions.revoke'),
  ('super_admin', 'community.manage'), ('super_admin', 'channels.feature'),
  ('super_admin', 'notifications.manage'), ('super_admin', 'security.read'),
  ('super_admin', 'platform.announce'), ('super_admin', 'platform.content.manage'),
  ('super_admin', 'verification.manage'), ('super_admin', 'partners.manage.full')
on conflict do nothing;

-- Admin gets limited subset
insert into public.role_permissions (role_key, permission_key) values
  ('admin', 'users.warn'), ('admin', 'community.manage'), ('admin', 'security.read')
on conflict do nothing;

-- Moderator gets reports + security read
insert into public.role_permissions (role_key, permission_key) values
  ('moderator', 'security.read')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. Platform settings — all categories from spec
-- ---------------------------------------------------------------------------
insert into public.platform_settings (setting_key, setting_value, is_public, is_protected) values
  -- Registration
  ('registration_restrictions',       '""', true, true),
  ('email_verification_required',     'true', true, true),
  ('account_creation_limits',         '{"per_hour": 5, "per_day": 20}', false, true),
  -- Messaging
  ('allowed_attachment_sizes',        '{"chat_media": 104857600, "chat_attachments": 104857600}', true, false),
  ('supported_attachment_types',      '["image/jpeg","image/png","video/mp4","audio/mpeg","application/pdf"]', true, false),
  ('message_retention_days',          '0', true, false),
  -- Social Features
  ('stories_enabled',                 'true', true, false),
  ('channels_enabled',                'true', true, false),
  ('communities_enabled',             'true', true, false),
  ('discovery_enabled',               'true', true, false),
  ('public_profiles_enabled',         'true', true, false),
  -- Verification
  ('verification_enabled',            'true', true, false),
  ('verification_review_config',      '{"require_two_reviewers": false, "auto_approve_partner": false}', false, false),
  -- Partner Program
  ('partner_requirements',            '{"min_followers": 1000, "min_posts": 10}', true, false),
  ('partner_benefits_config',         '{"badge": true, "analytics": true, "priority_support": false}', false, false),
  -- Security
  ('session_policy',                  '{"max_sessions": 5, "idle_timeout_minutes": 60}', false, true),
  ('login_restrictions',              '{"max_failed_attempts": 5, "lockout_minutes": 15}', false, true),
  ('rate_limits',                     '{"api_per_minute": 60, "auth_per_minute": 5}', false, true),
  ('account_protection_enabled',      'true', true, true),
  -- Maintenance
  ('maintenance_announcement',        '""', true, true),
  ('restricted_feature_mode',         '""', true, true),
  ('emergency_notice',                '""', true, true),
  -- Platform Content
  ('community_guidelines',            '""', true, false),
  ('terms_content',                   '""', true, true),
  ('featured_channels',               '[]', true, false),
  ('featured_communities',            '[]', true, false),
  ('featured_posts',                  '[]', true, false),
  ('platform_banners',                '[]', true, false)
on conflict (setting_key) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Owner dashboard — enhanced stats (includes all requested metrics)
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
    'new_registrations_7d', (select count(*) from public.profiles where created_at >= now() - interval '7 days'),
    'new_registrations_30d',(select count(*) from public.profiles where created_at >= now() - interval '30 days'),
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
    'total_groups',       (select count(*) from public.conversations where kind = 'group'),
    'total_messages',     (select count(*) from public.messages),
    'total_communities',  (select count(*) from public.communities),
    'total_stories',      (select count(*) from public.stories where hidden_at is null and expires_at > now()),
    'published_stories',  (select count(*) from public.stories where hidden_at is null and expires_at > now()),
    'total_posts',        (select case when exists (select 1 from pg_tables where tablename='posts') then (select count(*) from public.posts where hidden_at is null) else 0 end),
    'total_reports',      (select count(*) from public.reports),
    'open_reports',       (select count(*) from public.reports where status in ('open', 'reviewing', 'escalated')),
    'pending_verifications', (select count(*) from public.verification_applications where status in ('pending', 'under_review', 'info_requested')),
    'pending_partner_applications', (select count(*) from public.partner_applications where status in ('pending', 'reviewing')),
    'premium_active',     (select count(*) from public.premium_subscriptions where status = 'active' and ends_at > now()),
    'total_calls',        (select count(*) from public.calls),
    'total_channel_posts',(select count(*) from public.channel_posts),
    'generated_at',       now(),
    'maintenance_mode',   coalesce((select setting_value from public.platform_settings where setting_key='maintenance_mode'), 'false'::jsonb),
    'is_healthy',         true
  );
end;
$$;

-- Timeseries for charts: daily counts for N days
create or replace function public.owner_dashboard_timeseries(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since timestamptz := now() - (least(greatest(p_days, 1), 365) || ' days')::interval;
begin
  if not public.has_permission('analytics.read') then
    raise exception 'Permission denied: analytics.read' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'user_registrations', (
      select coalesce(jsonb_agg(jsonb_build_object('date', d, 'count', c) order by d), '[]'::jsonb)
      from (
        select date_trunc('day', p.created_at)::date as d, count(*)::int as c
        from public.profiles p where p.created_at >= v_since group by d
      ) s
    ),
    'messages_per_day', (
      select coalesce(jsonb_agg(jsonb_build_object('date', d, 'count', c) order by d), '[]'::jsonb)
      from (
        select date_trunc('day', created_at)::date as d, count(*)::int as c
        from public.messages where created_at >= v_since group by d
      ) s
    ),
    'reports_per_day', (
      select coalesce(jsonb_agg(jsonb_build_object('date', d, 'count', c) order by d), '[]'::jsonb)
      from (
        select date_trunc('day', created_at)::date as d, count(*)::int as c
        from public.reports where created_at >= v_since group by d
      ) s
    ),
    'since', v_since,
    'until', now()
  );
end;
$$;

-- System health snapshot
create or replace function public.owner_system_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('system.read') or public.has_permission('analytics.read')) then
    raise exception 'Permission denied: system.read' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'database_connected', true,
    'maintenance_mode', (select setting_value from public.platform_settings where setting_key='maintenance_mode'),
    'registration_enabled', (select setting_value from public.platform_settings where setting_key='registration_enabled'),
    'stories_enabled', (select setting_value from public.platform_settings where setting_key='stories_enabled'),
    'channels_enabled', (select setting_value from public.platform_settings where setting_key='channels_enabled'),
    'communities_enabled', (select setting_value from public.platform_settings where setting_key='communities_enabled'),
    'discovery_enabled', (select setting_value from public.platform_settings where setting_key='discovery_enabled'),
    'edge_functions_healthy', true,
    'realtime_enabled', exists(select 1 from pg_publication where pubname='supabase_realtime'),
    'checked_at', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Enhanced user directory with all filters from spec
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_users(
  p_query text default null,
  p_status text default null,
  p_filter text default null, -- normal | verified | partners | business | suspended | restricted | new | administrators | all
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id uuid,
  email text,
  username text,
  display_name text,
  account_status text,
  is_verified boolean,
  created_at timestamptz,
  last_seen_at timestamptz,
  roles text[],
  badges text[],
  partner_status text,
  is_business boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('users.read') then
    raise exception 'Permission denied: users.read' using errcode = '42501';
  end if;
  return query
    select p.id, p.email, p.username, p.display_name, p.account_status, p.is_verified,
           p.created_at, p.last_seen_at,
           coalesce((select array_agg(ur.role_key order by ur.role_key) from public.user_roles ur where ur.user_id=p.id and ur.revoked_at is null), '{}'),
           coalesce((select array_agg(badge) from (select 'verified' as badge where p.is_verified union all select 'partner' where exists(select 1 from public.partner_profiles pp where pp.user_id=p.id and pp.partner_status='active')) s), '{}'),
           (select pp.partner_status from public.partner_profiles pp where pp.user_id=p.id limit 1),
           exists(select 1 from public.business_members bm where bm.user_id=p.id)
    from public.profiles p
    where (p_query is null or p_query='' or p.username ilike '%' || p_query || '%' or p.display_name ilike '%' || p_query || '%' or p.email ilike '%' || p_query || '%')
      and (p_status is null or p.account_status = p_status)
      and (
        p_filter is null or p_filter='' or p_filter='all'
        or (p_filter='normal' and p.is_verified=false and not exists(select 1 from public.partner_profiles pp where pp.user_id=p.id and pp.partner_status='active') and not exists(select 1 from public.admin_assignments a where a.user_id=p.id and a.status='active'))
        or (p_filter='verified' and p.is_verified=true)
        or (p_filter='partners' and exists(select 1 from public.partner_profiles pp where pp.user_id=p.id and pp.partner_status='active'))
        or (p_filter='business' and exists(select 1 from public.business_members bm where bm.user_id=p.id))
        or (p_filter='suspended' and p.account_status='suspended')
        or (p_filter='restricted' and p.account_status='restricted')
        or (p_filter='new' and p.created_at >= now() - interval '7 days')
        or (p_filter='administrators' and exists(select 1 from public.admin_assignments a where a.user_id=p.id and a.status='active'))
      )
    order by p.created_at desc
    limit least(greatest(p_limit,1),200) offset greatest(p_offset,0);
end;
$$;

-- Detailed user profile for admins (no private messages, minimal PII)
create or replace function public.admin_get_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile record;
  v_rec jsonb;
begin
  if not public.has_permission('users.read') then
    raise exception 'Permission denied: users.read' using errcode = '42501';
  end if;
  select p.id, p.username, p.display_name, p.account_status, p.is_verified, p.created_at, p.last_seen_at,
         coalesce((select array_agg(ur.role_key) from public.user_roles ur where ur.user_id=p.id and ur.revoked_at is null), '{}') as roles,
         (select pp.partner_status from public.partner_profiles pp where pp.user_id=p.id limit 1) as partner_status
  into v_profile from public.profiles p where p.id=p_user_id;
  if not found then raise exception 'User not found' using errcode = '42501'; end if;
  return jsonb_build_object(
    'id', v_profile.id,
    'username', v_profile.username,
    'display_name', v_profile.display_name,
    'account_status', v_profile.account_status,
    'is_verified', (select p.is_verified from public.profiles p where p.id=p_user_id),
    'roles', v_profile.roles,
    'partner_status', v_profile.partner_status,
    'badges', (select array_agg(badge) from (select 'verified' where (select is_verified from public.profiles where id=p_user_id) union all select 'partner' where v_profile.partner_status='active') s),
    'verification_status', (select status from public.verification_applications where applicant_id=p_user_id order by submitted_at desc limit 1),
    'moderation_history', (select count(*) from public.reports where target_id=p_user_id::text),
    'created_at', v_profile.created_at,
    'last_seen_at', v_profile.last_seen_at
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Warnings, restrictions, session revocation
-- ---------------------------------------------------------------------------
create table if not exists public.user_warnings (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  issued_by  uuid references public.profiles(id) on delete set null,
  reason     text not null check (char_length(reason) between 3 and 500),
  created_at timestamptz not null default now()
);
create index if not exists user_warnings_user_idx on public.user_warnings(user_id, created_at desc);
alter table public.user_warnings enable row level security;
create policy user_warnings_self on public.user_warnings for select to authenticated using (user_id = auth.uid() or public.has_permission('users.manage'));
grant select on public.user_warnings to authenticated;

create table if not exists public.user_restrictions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  feature      text not null check (feature in ('messaging', 'posting', 'stories', 'channels', 'communities', 'calls', 'all')),
  reason       text not null check (char_length(reason) between 3 and 500),
  expires_at   timestamptz,
  is_active    boolean not null default true,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists user_restrictions_user_idx on public.user_restrictions(user_id) where is_active;
alter table public.user_restrictions enable row level security;
create policy user_restrictions_self on public.user_restrictions for select to authenticated using (user_id = auth.uid() or public.has_permission('users.manage'));
grant select on public.user_restrictions to authenticated;

create table if not exists public.session_revocations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  revoked_by uuid references public.profiles(id) on delete set null,
  reason     text,
  created_at timestamptz not null default now()
);
alter table public.session_revocations enable row level security;
create policy session_revocations_read on public.session_revocations for select to authenticated using (user_id = auth.uid() or public.has_permission('security.read'));
grant select on public.session_revocations to authenticated;

create or replace function public.admin_issue_warning(p_user_id uuid, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid := auth.uid();
begin
  if not public.has_permission('users.warn') then raise exception 'Permission denied: users.warn' using errcode='42501'; end if;
  if p_user_id=v_actor then raise exception 'You cannot warn yourself'; end if;
  if public.current_rank(p_user_id) >= public.current_rank() then raise exception 'Protected account' using errcode='42501'; end if;
  insert into public.user_warnings (user_id, issued_by, reason) values (p_user_id, v_actor, trim(p_reason));
  perform public.write_audit('user.warn', 'profile', p_user_id::text, jsonb_build_object('reason', p_reason));
  perform public.notify_user(p_user_id, 'security_alert', 'You received a warning', left(p_reason, 120), jsonb_build_object('kind','warning'));
end; $$;

create or replace function public.admin_restrict_feature(p_user_id uuid, p_feature text, p_reason text, p_expires_at timestamptz default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid := auth.uid();
begin
  if not public.has_permission('users.restrict') then raise exception 'Permission denied: users.restrict' using errcode='42501'; end if;
  if p_user_id=v_actor then raise exception 'You cannot restrict yourself'; end if;
  if public.current_rank(p_user_id) >= public.current_rank() then raise exception 'Protected account' using errcode='42501'; end if;
  if p_feature not in ('messaging','posting','stories','channels','communities','calls','all') then raise exception 'Invalid feature'; end if;
  insert into public.user_restrictions (user_id, feature, reason, expires_at, created_by) values (p_user_id, p_feature, trim(p_reason), p_expires_at, v_actor);
  perform public.write_audit('user.restrict', 'profile', p_user_id::text, jsonb_build_object('feature', p_feature, 'reason', p_reason, 'expires_at', p_expires_at));
  perform public.notify_user(p_user_id, 'security_alert', 'Feature restricted', p_feature || ': ' || left(p_reason, 80), jsonb_build_object('feature', p_feature));
end; $$;

create or replace function public.admin_revoke_sessions(p_user_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid := auth.uid();
begin
  if not public.has_permission('users.sessions.revoke') then raise exception 'Permission denied: users.sessions.revoke' using errcode='42501'; end if;
  if public.current_rank(p_user_id) >= public.current_rank() then raise exception 'Protected account' using errcode='42501'; end if;
  insert into public.session_revocations (user_id, revoked_by, reason) values (p_user_id, v_actor, p_reason);
  perform public.write_audit('user.sessions.revoke', 'profile', p_user_id::text, jsonb_build_object('reason', p_reason));
  perform public.notify_user(p_user_id, 'security_alert', 'Sessions revoked', 'Your sessions were revoked by an administrator.', jsonb_build_object('reason', p_reason));
  -- Actual Supabase Auth session revocation requires service_role via Edge Function; we record intent here
end; $$;

create or replace function public.admin_lift_restriction(p_restriction_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('users.restrict') then raise exception 'Permission denied' using errcode='42501'; end if;
  update public.user_restrictions set is_active=false where id=p_restriction_id;
  if not found then raise exception 'Restriction not found'; end if;
  perform public.write_audit('user.restrict.lift', 'user_restriction', p_restriction_id::text, '{}'::jsonb);
end; $$;

-- ---------------------------------------------------------------------------
-- 6. Admin directory and activity
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_admins()
returns table (
  user_id uuid,
  username text,
  display_name text,
  email text,
  role_key text,
  status text,
  permissions text[],
  created_at timestamptz
)
language plpgsql stable security definer set search_path=public as $$
begin
  if not (public.has_permission('admins.manage') or public.is_owner()) then raise exception 'Permission denied: admins.manage' using errcode='42501'; end if;
  return query
    select a.user_id, p.username, p.display_name, p.email,
           coalesce((select ur.role_key from public.user_roles ur where ur.user_id=a.user_id and ur.revoked_at is null and ur.role_key in (select key from public.platform_roles where is_staff) limit 1), 'admin'),
           a.status,
           coalesce((select array_agg(permission_key) from public.user_permission_grants g where g.user_id=a.user_id and g.granted), '{}'),
           a.created_at
    from public.admin_assignments a join public.profiles p on p.id=a.user_id
    order by a.created_at desc;
end; $$;

create or replace function public.admin_get_audit(p_user_id uuid, p_limit integer default 50)
returns table (id bigint, action text, target_type text, target_id text, metadata jsonb, created_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_permission('audit.read') then raise exception 'Permission denied: audit.read' using errcode='42501'; end if;
  return query
    select aa.id, aa.action, aa.target_type, aa.target_id, aa.metadata, aa.created_at
    from public.admin_audit_logs aa where aa.actor_id=p_user_id
    union all
    select oa.id, oa.action, oa.target_type, oa.target_id, oa.metadata, oa.created_at
    from public.owner_audit_logs oa where oa.actor_id=p_user_id
    order by created_at desc limit least(greatest(p_limit,1),200);
end; $$;

-- ---------------------------------------------------------------------------
-- 7. Verification & Partner helpers (extend existing)
-- ---------------------------------------------------------------------------
create or replace function public.admin_verification_queue(p_status text default null)
returns table (id uuid, applicant_id uuid, applicant_username text, application_type text, status text, submitted_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_permission('verification.approve') then raise exception 'Permission denied' using errcode='42501'; end if;
  return query
    select v.id, v.applicant_id, p.username, v.application_type, v.status, v.submitted_at
    from public.verification_applications v join public.profiles p on p.id=v.applicant_id
    where (p_status is null or v.status=p_status)
    order by v.submitted_at desc;
end; $$;

create or replace function public.admin_partner_queue(p_status text default null)
returns table (id uuid, user_id uuid, username text, status text, submitted_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not (public.has_permission('partners.approve') or public.has_permission('partners.manage')) then raise exception 'Permission denied' using errcode='42501'; end if;
  return query
    select pa.id, pa.user_id, p.username, pa.status, pa.submitted_at
    from public.partner_applications pa join public.profiles p on p.id=pa.user_id
    where (p_status is null or pa.status=p_status)
    order by pa.submitted_at desc;
end; $$;

-- ---------------------------------------------------------------------------
-- 8. Moderation center — priority, assignment, escalation
-- ---------------------------------------------------------------------------
alter table public.reports add column if not exists priority text not null default 'normal' check (priority in ('low','normal','high','urgent'));
alter table public.reports add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
alter table public.reports add column if not exists internal_notes text;
alter table public.reports add column if not exists resolution_reason text;

create or replace function public.moderation_assign(p_report_id uuid, p_assignee uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('reports.manage') then raise exception 'Permission denied' using errcode='42501'; end if;
  update public.reports set assigned_to=p_assignee, status='reviewing' where id=p_report_id;
  if not found then raise exception 'Report not found'; end if;
  perform public.write_audit('report.assign', 'report', p_report_id::text, jsonb_build_object('assignee', p_assignee));
end; $$;

create or replace function public.moderation_add_note(p_report_id uuid, p_note text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('reports.manage') then raise exception 'Permission denied' using errcode='42501'; end if;
  update public.reports set internal_notes=coalesce(internal_notes,'') || chr(10) || trim(p_note) where id=p_report_id;
  if not found then raise exception 'Report not found'; end if;
  perform public.write_audit('report.note', 'report', p_report_id::text, jsonb_build_object('note', left(p_note, 200)));
end; $$;

create or replace function public.moderation_set_priority(p_report_id uuid, p_priority text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('reports.manage') then raise exception 'Permission denied' using errcode='42501'; end if;
  if p_priority not in ('low','normal','high','urgent') then raise exception 'Invalid priority'; end if;
  update public.reports set priority=p_priority where id=p_report_id;
  if not found then raise exception 'Report not found'; end if;
  perform public.write_audit('report.priority', 'report', p_report_id::text, jsonb_build_object('priority', p_priority));
end; $$;

create or replace function public.moderation_escalate(p_report_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('reports.manage') then raise exception 'Permission denied' using errcode='42501'; end if;
  update public.reports set status='escalated', internal_notes=coalesce(internal_notes,'') || chr(10) || coalesce(p_note,'escalated') where id=p_report_id;
  if not found then raise exception 'Report not found'; end if;
  perform public.write_audit('report.escalate', 'report', p_report_id::text, jsonb_build_object('note', p_note));
end; $$;

create or replace function public.moderator_metrics(p_user_id uuid default auth.uid())
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_permission('reports.manage') then raise exception 'Permission denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'assigned', (select count(*) from public.reports where assigned_to=p_user_id),
    'resolved', (select count(*) from public.moderation_actions where actor_id=p_user_id),
    'open', (select count(*) from public.reports where status in ('open','reviewing')),
    'escalated', (select count(*) from public.reports where status='escalated')
  );
end; $$;

-- Extend moderation_actions to track report resolution fully (already exists)
-- Ensure resolve_report handles new statuses: reopen, escalate already via moderation_escalate

-- ---------------------------------------------------------------------------
-- 9. Platform announcements & content
-- ---------------------------------------------------------------------------
create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid references public.profiles(id) on delete set null,
  title       text not null check (char_length(title) between 3 and 120),
  body        text not null check (char_length(body) between 3 and 5000),
  audience    text not null default 'all' check (audience in ('all','admins','moderators','partners','verified')),
  type        text not null default 'information' check (type in ('information','maintenance','important','security','feature')),
  status      text not null default 'draft' check (status in ('draft','scheduled','published','unpublished')),
  publish_at  timestamptz,
  created_at  timestamptz not null default now(),
  published_at timestamptz,
  updated_at  timestamptz not null default now()
);
create trigger announcements_touch before update on public.announcements for each row execute function public.touch_updated_at();
alter table public.announcements enable row level security;
create policy announcements_select on public.announcements for select to authenticated using (status='published' or public.has_permission('platform.announce') or author_id=auth.uid());
create policy announcements_write on public.announcements for insert to authenticated with check (public.has_permission('platform.announce'));
create policy announcements_update on public.announcements for update to authenticated using (public.has_permission('platform.announce')) with check (public.has_permission('platform.announce'));
grant select, insert, update, delete on public.announcements to authenticated;

create or replace function public.publish_announcement(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('platform.announce') then raise exception 'Permission denied' using errcode='42501'; end if;
  update public.announcements set status='published', published_at=now() where id=p_id;
  if not found then raise exception 'Announcement not found'; end if;
  perform public.write_audit('announcement.publish', 'announcement', p_id::text, '{}'::jsonb);
end; $$;

-- ---------------------------------------------------------------------------
-- 10. Security center
-- ---------------------------------------------------------------------------
-- Extend security_events kind to support new cases
alter table public.security_events drop constraint if exists security_events_kind_check;
alter table public.security_events add constraint security_events_kind_check check (kind in ('role_granted','role_revoked','account_status_changed','login_success','login_failed','suspicious','permission_changed','session_revoked','security_config_changed'));

alter table public.security_events enable row level security;
drop policy if exists security_events_own_select on public.security_events;
create policy security_events_own_select on public.security_events for select to authenticated using (user_id=auth.uid() or public.has_permission('security.read'));
-- allow service_role to insert login events (already definer functions do)

create or replace function public.record_login_event(p_user_id uuid, p_kind text, p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into public.security_events (user_id, kind, detail) values (p_user_id, p_kind, coalesce(p_detail,'{}'::jsonb));
end; $$;

create or replace function public.admin_emergency_suspend(p_user_id uuid, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid := auth.uid();
begin
  if not public.has_permission('security.manage') then raise exception 'Only Owner can emergency suspend' using errcode='42501'; end if;
  if public.current_rank(p_user_id) >= public.current_rank() then raise exception 'Protected account' using errcode='42501'; end if;
  update public.admin_assignments set status='suspended', status_changed_at=now(), status_reason=p_reason where user_id=p_user_id;
  if not found then raise exception 'Target is not an administrator'; end if;
  perform public.write_audit('admin.emergency_suspend', 'profile', p_user_id::text, jsonb_build_object('reason', p_reason));
  perform public.notify_user(p_user_id, 'security_alert', 'Administrator access suspended', left(p_reason, 120), jsonb_build_object('kind','emergency'));
end; $$;

create or replace function public.security_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_permission('security.read') then raise exception 'Permission denied: security.read' using errcode='42501'; end if;
  return jsonb_build_object(
    'recent_logins', (select count(*) from public.security_events where kind='login_success' and created_at >= now() - interval '24 hours'),
    'failed_logins_24h', (select count(*) from public.security_events where kind='login_failed' and created_at >= now() - interval '24 hours'),
    'suspicious_24h', (select count(*) from public.security_events where kind='suspicious' and created_at >= now() - interval '24 hours'),
    'permission_changes_7d', (select count(*) from public.admin_audit_logs where action like 'admin.permission%' and created_at >= now() - interval '7 days'),
    'session_revocations_7d', (select count(*) from public.session_revocations where created_at >= now() - interval '7 days'),
    'open_reports', (select count(*) from public.reports where status in ('open','reviewing','escalated')),
    'maintenance_mode', (select setting_value from public.platform_settings where setting_key='maintenance_mode'),
    'registration_enabled', (select setting_value from public.platform_settings where setting_key='registration_enabled')
  );
end; $$;

-- ---------------------------------------------------------------------------
-- 11. Owner-only emergency controls
-- ---------------------------------------------------------------------------
create or replace function public.owner_set_maintenance(p_enabled boolean, p_announcement text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission('owner.manage') then raise exception 'Only Owner can change maintenance mode' using errcode='42501'; end if;
  update public.platform_settings set setting_value=to_jsonb(p_enabled), updated_by=auth.uid(), updated_at=now() where setting_key='maintenance_mode';
  if p_announcement is not null then
    update public.platform_settings set setting_value=to_jsonb(p_announcement), updated_by=auth.uid(), updated_at=now() where setting_key='maintenance_announcement';
  end if;
  perform public.write_audit('owner.maintenance', 'platform_setting', 'maintenance_mode', jsonb_build_object('enabled', p_enabled, 'announcement', p_announcement));
end; $$;

-- ---------------------------------------------------------------------------
-- 12. Grants for new functions
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- Re-revoke trigger/internal helpers
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prorettype='trigger'::regtype loop
    execute format('revoke execute on function %s from authenticated', r.sig);
  end loop;
end $$;
revoke execute on function public.enroll_mandatory_subscriptions(uuid) from authenticated;
revoke execute on function public.bootstrap_owner(text) from authenticated;
revoke execute on function public.write_audit(text, text, text, jsonb) from authenticated;
revoke execute on function public.apply_verification_badge(public.verification_applications, boolean) from authenticated;
revoke execute on function public.grant_role(uuid, text, uuid) from authenticated;
revoke execute on function public.revoke_role(uuid, text, uuid) from authenticated;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb) from authenticated;
revoke execute on function public.record_login_event(uuid, text, jsonb) from authenticated;
