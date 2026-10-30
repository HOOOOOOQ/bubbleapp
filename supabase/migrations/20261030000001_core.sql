-- =============================================================================
-- BubbleApp :: 0001 core
-- profiles, businesses, account modes, user settings, devices, platform settings
-- Security model: every table has RLS enabled; clients receive column-level
-- grants only. Privileged columns (is_verified, account_status, ...) can only be
-- changed by SECURITY DEFINER functions that perform authorization first.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- TRUE for direct database sessions (SQL editor, migrations, break-glass admin)
-- and for requests authenticated with the service_role key (Edge Functions).
-- FALSE for any PostgREST request made with an anon or user JWT.
create or replace function public.is_trusted_context()
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_claims text := current_setting('request.jwt.claims', true);
begin
  if v_claims is null or v_claims = '' then
    return true;
  end if;
  return (v_claims::jsonb ->> 'role') = 'service_role';
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Allowed only inside SECURITY DEFINER functions that already checked authorization.
create or replace function public.privileged_write_enabled()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(current_setting('bubble.privileged', true), '') = 'on'
      or public.is_trusted_context();
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  email           text,
  username        text not null,
  display_name    text not null default '',
  avatar_url      text,
  cover_url       text,
  bio             text not null default '' check (char_length(bio) <= 500),
  account_status  text not null default 'active'
                  check (account_status in ('active', 'suspended', 'banned', 'deleted')),
  status_reason   text,
  is_verified     boolean not null default false,
  verified_at     timestamptz,
  last_seen_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,32}$'),
  constraint profiles_verified_consistency check (is_verified = false or verified_at is not null),
  constraint profiles_display_name_len check (char_length(display_name) <= 64)
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));
create index if not exists profiles_status_idx on public.profiles (account_status);
create index if not exists profiles_last_seen_idx on public.profiles (last_seen_at desc);
create index if not exists profiles_verified_idx on public.profiles (is_verified) where is_verified;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Guard: clients may only change their own presentational fields.
create or replace function public.guard_profile_privileged_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.privileged_write_enabled() then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.is_verified is distinct from old.is_verified
     or new.verified_at is distinct from old.verified_at
     or new.account_status is distinct from old.account_status
     or new.status_reason is distinct from old.status_reason then
    raise exception 'This profile field can only be changed by BubbleApp administration'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_privileged_columns();

-- ---------------------------------------------------------------------------
-- businesses + members (business account mode)
-- ---------------------------------------------------------------------------
create table if not exists public.businesses (
  id                  uuid primary key default gen_random_uuid(),
  created_by          uuid not null references public.profiles (id) on delete cascade,
  name                text not null check (char_length(name) between 2 and 80),
  username            text not null check (username ~ '^[a-z0-9_]{3,32}$'),
  logo_url            text,
  cover_url           text,
  description         text not null default '' check (char_length(description) <= 1000),
  category            text not null check (char_length(category) between 2 and 60),
  website             text,
  business_email      text not null check (business_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  business_phone      text,
  address             text,
  location            jsonb,
  working_hours       jsonb not null default '{}'::jsonb,
  greeting_message    text check (char_length(greeting_message) <= 500),
  away_message        text check (char_length(away_message) <= 500),
  is_setup_complete   boolean not null default false,
  is_verified         boolean not null default false,
  verified_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint businesses_verified_consistency check (is_verified = false or verified_at is not null)
);
create unique index if not exists businesses_username_key on public.businesses (lower(username));
create trigger businesses_touch before update on public.businesses
  for each row execute function public.touch_updated_at();

create table if not exists public.business_members (
  business_id uuid not null references public.businesses (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        text not null check (role in ('owner', 'manager', 'operator')),
  added_by    uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (business_id, user_id)
);
create index if not exists business_members_user_idx on public.business_members (user_id);

-- Business owners are always members with role 'owner'. Created by create_business().
create or replace function public.is_business_member(p_business_id uuid, p_roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_members m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and (p_roles is null or m.role = any (p_roles))
  );
$$;

-- ---------------------------------------------------------------------------
-- account_modes: each user has a personal mode; business mode exists per business
-- ---------------------------------------------------------------------------
create table if not exists public.account_modes (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  mode        text not null check (mode in ('personal', 'business')),
  business_id uuid references public.businesses (id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint account_modes_business_link check (
    (mode = 'personal' and business_id is null) or (mode = 'business' and business_id is not null)
  )
);
create unique index if not exists account_modes_personal_key
  on public.account_modes (user_id) where mode = 'personal';
create unique index if not exists account_modes_business_key
  on public.account_modes (user_id, business_id) where mode = 'business';

-- ---------------------------------------------------------------------------
-- user_settings (one row per user; pointer to the active account mode)
-- ---------------------------------------------------------------------------
create table if not exists public.user_settings (
  user_id              uuid primary key references public.profiles (id) on delete cascade,
  active_account_mode  text not null default 'personal' check (active_account_mode in ('personal', 'business')),
  active_business_id   uuid references public.businesses (id) on delete set null,
  theme                text not null default 'system' check (theme in ('system', 'light', 'dark')),
  language             text not null default 'en',
  privacy              jsonb not null default '{"last_seen":"everyone","profile_photo":"everyone","stories":"contacts"}'::jsonb,
  notifications        jsonb not null default '{"messages":true,"calls":true,"channels":true}'::jsonb,
  updated_at           timestamptz not null default now(),
  constraint user_settings_business_pointer check (
    active_account_mode = 'personal' or active_business_id is not null
  )
);
create trigger user_settings_touch before update on public.user_settings
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- devices (FCM tokens + active sessions list)
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  platform      text not null check (platform in ('android', 'ios', 'web', 'macos', 'windows', 'linux')),
  fcm_token     text unique,
  device_name   text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index if not exists devices_user_idx on public.devices (user_id);

-- ---------------------------------------------------------------------------
-- platform_settings (owner-managed; protected keys need owner.manage)
-- ---------------------------------------------------------------------------
create table if not exists public.platform_settings (
  id             bigint generated always as identity primary key,
  setting_key    text not null unique,
  setting_value  jsonb not null,
  is_public      boolean not null default false,
  is_protected   boolean not null default false,
  updated_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now()
);

insert into public.platform_settings (setting_key, setting_value, is_public, is_protected) values
  ('platform_name',                 '"BubbleApp"',  true,  false),
  ('maintenance_mode',              'false',        true,  true),
  ('registration_enabled',          'true',         true,  true),
  ('mandatory_channel_subscription','true',         true,  true),
  ('business_accounts_enabled',     'true',         true,  false),
  ('partner_applications_open',     'true',         true,  false),
  ('max_group_members',             '1024',         true,  false),
  ('max_file_size_mb',              '100',          true,  false),
  ('verification_requirements',     '{"require_documents": true, "min_documents": 1}', true, false),
  ('premium_features', '{"scheduled_messages":true,"advanced_search":true,"message_translation":true,"ai_assistant":true,"smart_replies":true,"voice_transcription":true,"custom_themes":true,"custom_stickers":true,"advanced_privacy":true,"unlimited_folders":true,"cloud_backup":true,"hidden_conversations":true,"chat_lock":true,"auto_delete":true,"advanced_analytics":true,"custom_notification_sounds":true}', false, false)
on conflict (setting_key) do nothing;
