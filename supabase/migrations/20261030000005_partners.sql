-- =============================================================================
-- BubbleApp :: 0005 partner program
-- Partner is a separate platform role. It never grants administrator rights.
-- The partner role is granted on approval and removed on suspension/termination.
-- =============================================================================

create table if not exists public.partner_profiles (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null unique references public.profiles (id) on delete cascade,
  partner_category text not null check (char_length(partner_category) between 2 and 60),
  partner_status   text not null default 'active' check (partner_status in ('active', 'suspended', 'terminated')),
  badge_enabled    boolean not null default true,
  display_name     text not null check (char_length(display_name) between 2 and 80),
  bio              text not null default '' check (char_length(bio) <= 500),
  website          text,
  status_reason    text,
  approved_by      uuid references auth.users (id) on delete set null,
  approved_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger partner_profiles_touch before update on public.partner_profiles
  for each row execute function public.touch_updated_at();

create table if not exists public.partner_applications (
  id                   uuid primary key default gen_random_uuid(),
  applicant_id         uuid not null references public.profiles (id) on delete cascade,
  full_name            text not null check (char_length(full_name) between 2 and 120),
  username             text not null,
  email                text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  organization         text not null check (char_length(organization) between 2 and 120),
  website              text,
  social_media         jsonb not null default '{}'::jsonb,
  partnership_category text not null check (char_length(partnership_category) between 2 and 60),
  proposal             text not null check (char_length(proposal) between 30 and 4000),
  description          text not null default '' check (char_length(description) <= 2000),
  status               text not null default 'pending'
                       check (status in ('pending', 'reviewing', 'approved', 'rejected', 'suspended', 'terminated')),
  decision_note        text,
  reviewed_by          uuid references public.profiles (id) on delete set null,
  reviewed_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create unique index if not exists partner_applications_one_open
  on public.partner_applications (applicant_id) where status in ('pending', 'reviewing');
create index if not exists partner_applications_status_idx on public.partner_applications (status, created_at);
create trigger partner_applications_touch before update on public.partner_applications
  for each row execute function public.touch_updated_at();

create table if not exists public.partner_permissions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  permission_key  text not null references public.permissions (key) on delete cascade,
  granted         boolean not null default true,
  granted_by      uuid references auth.users (id) on delete set null,
  granted_at      timestamptz not null default now(),
  unique (user_id, permission_key)
);

-- Only partner-scoped permissions can be attached to partners.
create or replace function public.guard_partner_permission_scope()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (select 1 from public.permissions p where p.key = new.permission_key and p.scope = 'partner') then
    raise exception 'Partners can only receive partner-scoped permissions' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger partner_permissions_scope before insert or update on public.partner_permissions
  for each row execute function public.guard_partner_permission_scope();

create table if not exists public.partner_announcements (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid references public.profiles (id) on delete set null,
  title       text not null check (char_length(title) between 3 and 120),
  body        text not null check (char_length(body) between 1 and 4000),
  category    text,            -- null = all partners
  created_at  timestamptz not null default now()
);
create index if not exists partner_announcements_created_idx on public.partner_announcements (created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.grant_role(p_user_id uuid, p_role text, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.user_roles
                 where user_id = p_user_id and role_key = p_role and revoked_at is null) then
    insert into public.user_roles (user_id, role_key, assigned_by) values (p_user_id, p_role, p_actor);
  end if;
end;
$$;

create or replace function public.revoke_role(p_user_id uuid, p_role text, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_roles
     set revoked_at = now(), revoked_by = p_actor
   where user_id = p_user_id and role_key = p_role and revoked_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: applicant
-- ---------------------------------------------------------------------------
create or replace function public.submit_partner_application(
  p_full_name text,
  p_username text,
  p_email text,
  p_organization text,
  p_website text,
  p_social_media jsonb,
  p_partnership_category text,
  p_proposal text,
  p_description text
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
  if not public.setting_bool('partner_applications_open', true) then
    raise exception 'Partner applications are currently closed';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'terminated') then
    raise exception 'Your partner status was terminated and cannot be re-applied for';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = v_uid and partner_status = 'active') then
    raise exception 'You are already an active BubbleApp Partner';
  end if;

  insert into public.partner_applications (
    applicant_id, full_name, username, email, organization, website, social_media,
    partnership_category, proposal, description
  ) values (
    v_uid, trim(p_full_name), lower(trim(p_username)), lower(trim(p_email)), trim(p_organization),
    nullif(trim(coalesce(p_website, '')), ''), coalesce(p_social_media, '{}'::jsonb),
    trim(p_partnership_category), trim(p_proposal), coalesce(p_description, '')
  ) returning id into v_id;

  perform public.write_audit('partner.application.submit', 'partner_application', v_id::text, '{}'::jsonb);
  return v_id;
exception
  when unique_violation then
    raise exception 'You already have a partner application under review';
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: reviewers
--   start_review, approve, reject  -> partners.approve
--   suspend, terminate, restore    -> partners.manage
-- ---------------------------------------------------------------------------
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
  v_profile public.partner_profiles%rowtype;
  v_display text;
begin
  select * into v_app from public.partner_applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.applicant_id = v_actor then
    raise exception 'You cannot review your own partner application' using errcode = '42501';
  end if;

  if p_action in ('start_review', 'approve', 'reject') then
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

  select * into v_profile from public.partner_profiles where user_id = v_app.applicant_id;

  case p_action
    when 'start_review' then
      if v_app.status <> 'pending' then raise exception 'Only pending applications can start review'; end if;
      v_new := 'reviewing';
    when 'approve' then
      if v_app.status not in ('pending', 'reviewing') then raise exception 'Application is closed'; end if;
      if p_category is null or char_length(trim(p_category)) < 2 then
        raise exception 'Assign a partner category before approval';
      end if;
      v_new := 'approved';
    when 'reject' then
      if v_app.status not in ('pending', 'reviewing') then raise exception 'Application is closed'; end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'A rejection reason is required'; end if;
      v_new := 'rejected';
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
         decision_note = coalesce(p_note, decision_note)
   where id = p_application_id;

  if p_action = 'approve' then
    v_display := coalesce(nullif(v_app.full_name, ''), v_app.username);
    insert into public.partner_profiles (user_id, partner_category, partner_status, display_name, website, approved_by)
    values (v_app.applicant_id, trim(p_category), 'active', left(v_display, 80), v_app.website, v_actor)
    on conflict (user_id) do update
      set partner_category = excluded.partner_category, partner_status = 'active',
          status_reason = null, approved_by = excluded.approved_by, approved_at = now();
    perform public.grant_role(v_app.applicant_id, 'partner', v_actor);
  elsif p_action in ('suspend', 'terminate') then
    update public.partner_profiles
       set partner_status = case when p_action = 'suspend' then 'suspended' else 'terminated' end,
           status_reason = p_note
     where user_id = v_app.applicant_id;
    perform public.revoke_role(v_app.applicant_id, 'partner', v_actor);
  elsif p_action = 'restore' then
    update public.partner_profiles set partner_status = 'active', status_reason = null
     where user_id = v_app.applicant_id;
    perform public.grant_role(v_app.applicant_id, 'partner', v_actor);
  end if;

  perform public.write_audit('partner.' || p_action, 'partner_application', p_application_id::text,
    jsonb_build_object('applicant_id', v_app.applicant_id, 'from', v_app.status, 'to', v_new, 'category', p_category));
  return v_new;
end;
$$;

create or replace function public.set_partner_permission(p_user_id uuid, p_permission text, p_granted boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('partners.manage') then
    raise exception 'Permission denied: partners.manage' using errcode = '42501';
  end if;
  if not exists (select 1 from public.partner_profiles where user_id = p_user_id and partner_status = 'active') then
    raise exception 'Target is not an active partner';
  end if;
  if not exists (select 1 from public.permissions where key = p_permission and scope = 'partner') then
    raise exception 'Not a partner-scoped permission';
  end if;
  insert into public.partner_permissions (user_id, permission_key, granted, granted_by)
  values (p_user_id, p_permission, p_granted, auth.uid())
  on conflict (user_id, permission_key) do update
    set granted = excluded.granted, granted_by = excluded.granted_by, granted_at = now();
  perform public.write_audit('partner.permission', 'profile', p_user_id::text,
    jsonb_build_object('permission', p_permission, 'granted', p_granted));
end;
$$;

create or replace function public.publish_partner_announcement(p_title text, p_body text, p_category text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_permission('partners.manage') then
    raise exception 'Permission denied: partners.manage' using errcode = '42501';
  end if;
  insert into public.partner_announcements (author_id, title, body, category)
  values (auth.uid(), trim(p_title), trim(p_body), p_category)
  returning id into v_id;
  perform public.write_audit('partner.announcement', 'partner_announcement', v_id::text, '{}'::jsonb);
  return v_id;
end;
$$;

-- Partner dashboard snapshot for the signed-in partner.
create or replace function public.partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile public.partner_profiles%rowtype;
begin
  select * into v_profile from public.partner_profiles where user_id = auth.uid();
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'partner_status', v_profile.partner_status,
    'partner_category', v_profile.partner_category,
    'display_name', v_profile.display_name,
    'approved_at', v_profile.approved_at,
    'announcements', (select count(*) from public.partner_announcements),
    'permissions', coalesce((select jsonb_agg(pp.permission_key) from public.partner_permissions pp
                             where pp.user_id = auth.uid() and pp.granted), '[]'::jsonb),
    'status_reason', v_profile.status_reason
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
alter table public.partner_profiles      enable row level security;
alter table public.partner_applications  enable row level security;
alter table public.partner_permissions   enable row level security;
alter table public.partner_announcements enable row level security;

revoke all on public.partner_profiles, public.partner_applications, public.partner_permissions,
  public.partner_announcements from anon, authenticated;
grant select on public.partner_profiles to authenticated;
grant select on public.partner_applications to authenticated;
grant select on public.partner_permissions to authenticated;
grant select on public.partner_announcements to authenticated;

-- Partner badges are public while active and enabled; the rest is private.
create policy partner_profiles_select on public.partner_profiles for select to authenticated using (
  (partner_status = 'active' and badge_enabled)
  or user_id = auth.uid()
  or public.has_permission('partners.manage')
  or public.has_permission('partners.approve')
);
create policy partner_applications_select on public.partner_applications for select to authenticated using (
  applicant_id = auth.uid() or public.has_permission('partners.approve')
);
create policy partner_permissions_select on public.partner_permissions for select to authenticated using (
  user_id = auth.uid() or public.has_permission('partners.manage')
);
create policy partner_announcements_select on public.partner_announcements for select to authenticated using (
  public.has_permission('partners.manage')
  or (
    exists (select 1 from public.user_roles ur
            where ur.user_id = auth.uid() and ur.role_key = 'partner' and ur.revoked_at is null)
    and public.has_permission('partner.announcements.read')
  )
);
