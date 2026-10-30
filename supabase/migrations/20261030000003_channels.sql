-- =============================================================================
-- BubbleApp :: 0003 channels, subscriptions, posts, mandatory official follow
-- =============================================================================

create table if not exists public.channels (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid references public.profiles (id) on delete set null,
  name               text not null check (char_length(name) between 2 and 64),
  username           text not null check (username ~ '^[a-z][a-z0-9_]{3,31}$'),
  description        text not null default '' check (char_length(description) <= 1000),
  avatar_url         text,
  cover_url          text,
  is_public          boolean not null default true,
  comments_enabled   boolean not null default false,
  is_verified        boolean not null default false,
  verified_at        timestamptz,
  is_official        boolean not null default false,
  is_mandatory       boolean not null default false,
  invite_hash        text not null default replace(gen_random_uuid()::text, '-', ''),
  subscriber_count   integer not null default 0 check (subscriber_count >= 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint channels_mandatory_is_official check (not is_mandatory or is_official),
  constraint channels_official_has_no_owner check (not is_official or owner_id is null),
  constraint channels_verified_consistency check (is_verified = false or verified_at is not null)
);
create unique index if not exists channels_username_key on public.channels (lower(username));
create unique index if not exists channels_one_official on public.channels (is_official) where is_official;
create unique index if not exists channels_invite_key on public.channels (invite_hash);
create index if not exists channels_owner_idx on public.channels (owner_id);
create trigger channels_touch before update on public.channels
  for each row execute function public.touch_updated_at();

create table if not exists public.channel_subscribers (
  id            uuid primary key default gen_random_uuid(),
  channel_id    uuid not null references public.channels (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  subscribed_at timestamptz not null default now(),
  is_active     boolean not null default true,
  constraint channel_subscribers_unique unique (channel_id, user_id)
);
create index if not exists channel_subscribers_user_idx on public.channel_subscribers (user_id) where is_active;
create index if not exists channel_subscribers_channel_idx on public.channel_subscribers (channel_id) where is_active;

create table if not exists public.channel_posts (
  id                    uuid primary key default gen_random_uuid(),
  channel_id            uuid not null references public.channels (id) on delete cascade,
  author_id             uuid references public.profiles (id) on delete set null,
  kind                  text not null default 'text' check (kind in ('text', 'image', 'video', 'document', 'voice')),
  body                  text check (char_length(body) <= 4000),
  media_path            text,
  media_mime            text,
  is_pinned             boolean not null default false,
  publish_at            timestamptz not null default now(),
  forwarded_from_post_id uuid references public.channel_posts (id) on delete set null,
  views_count           integer not null default 0,
  hidden_at             timestamptz,
  created_at            timestamptz not null default now(),
  constraint channel_posts_content check (
    (kind = 'text' and body is not null and char_length(body) > 0)
    or (kind <> 'text' and media_path is not null)
  )
);
create unique index if not exists channel_posts_one_pinned on public.channel_posts (channel_id) where is_pinned;
create index if not exists channel_posts_channel_time on public.channel_posts (channel_id, publish_at desc);

create table if not exists public.channel_post_reactions (
  post_id     uuid not null references public.channel_posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  emoji       text not null check (char_length(emoji) between 1 and 16),
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id, emoji)
);

create table if not exists public.channel_post_views (
  post_id  uuid not null references public.channel_posts (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.channel_comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.channel_posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index if not exists channel_comments_post_idx on public.channel_comments (post_id, created_at);

create table if not exists public.channel_invitations (
  id           uuid primary key default gen_random_uuid(),
  channel_id   uuid not null references public.channels (id) on delete cascade,
  code         text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_by   uuid references public.profiles (id) on delete set null,
  expires_at   timestamptz,
  max_uses     integer check (max_uses is null or max_uses > 0),
  uses         integer not null default 0,
  revoked_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Authorization helpers for channels
-- ---------------------------------------------------------------------------
create or replace function public.is_active_subscriber(p_channel_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.channel_subscribers s
    where s.channel_id = p_channel_id and s.user_id = auth.uid() and s.is_active
  );
$$;

create or replace function public.can_manage_channel(p_channel_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.channels c
    where c.id = p_channel_id
      and public.is_active_user()
      and (c.owner_id = auth.uid() or public.has_permission('channels.manage'))
  );
$$;

create or replace function public.mandatory_subscription_enforced()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.setting_bool('mandatory_channel_subscription', true);
$$;

-- ---------------------------------------------------------------------------
-- Mandatory official subscription
-- ---------------------------------------------------------------------------

-- Idempotent: creates or re-activates the mandatory subscription(s) for a user.
create or replace function public.enroll_mandatory_subscriptions(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  if not public.mandatory_subscription_enforced() then
    return 0;
  end if;
  insert into public.channel_subscribers (channel_id, user_id, is_active)
  select c.id, p_user_id, true
  from public.channels c
  where c.is_mandatory and c.is_official
  on conflict (channel_id, user_id) do update
    set is_active = true
    where public.channel_subscribers.is_active = false;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.ensure_my_mandatory_subscriptions()
returns integer
language sql
security definer
set search_path = public
as $$
  select public.enroll_mandatory_subscriptions(auth.uid());
$$;

create or replace function public.guard_mandatory_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.channel_subscribers%rowtype;
  v_mandatory boolean;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;

  -- Cascade from a deleted profile is allowed.
  if tg_op = 'DELETE' and not exists (select 1 from public.profiles p where p.id = old.user_id) then
    return old;
  end if;
  if tg_op = 'UPDATE' and not (old.is_active and not new.is_active) then
    return new;
  end if;
  if public.privileged_write_enabled() then
    return v_row;
  end if;

  select c.is_mandatory into v_mandatory from public.channels c where c.id = v_row.channel_id;
  if coalesce(v_mandatory, false) and public.mandatory_subscription_enforced() then
    raise exception 'The official BubbleApp channel is required'
      using errcode = 'P0001',
            hint = 'It delivers platform announcements, security notices and account updates, so it cannot be unfollowed.';
  end if;
  return v_row;
end;
$$;

create trigger channel_subscribers_mandatory_guard
  before update or delete on public.channel_subscribers
  for each row execute function public.guard_mandatory_subscription();

-- Keep subscriber_count accurate (trigger runs as definer; column is not client-writable).
create or replace function public.sync_subscriber_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel uuid := coalesce(new.channel_id, old.channel_id);
begin
  update public.channels c
     set subscriber_count = (
       select count(*) from public.channel_subscribers s
       where s.channel_id = v_channel and s.is_active
     )
   where c.id = v_channel;
  return null;
end;
$$;

create trigger channel_subscribers_count
  after insert or update of is_active or delete on public.channel_subscribers
  for each row execute function public.sync_subscriber_count();

-- Owners follow their own channel.
create or replace function public.on_channel_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.owner_id is not null then
    insert into public.channel_subscribers (channel_id, user_id, is_active)
    values (new.id, new.owner_id, true)
    on conflict (channel_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger channels_owner_subscribes after insert on public.channels
  for each row execute function public.on_channel_created();

-- Guard privileged channel flags.
create or replace function public.guard_channel_flags()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.privileged_write_enabled() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.is_official or new.is_mandatory or new.is_verified or new.owner_id is distinct from auth.uid() then
      raise exception 'Only BubbleApp administration can set this channel attribute' using errcode = '42501';
    end if;
  elsif new.is_official is distinct from old.is_official
     or new.is_mandatory is distinct from old.is_mandatory
     or new.is_verified is distinct from old.is_verified
     or new.verified_at is distinct from old.verified_at
     or new.owner_id is distinct from old.owner_id
     or new.invite_hash is distinct from old.invite_hash then
    raise exception 'Only BubbleApp administration can change this channel attribute' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger channels_guard before insert or update on public.channels
  for each row execute function public.guard_channel_flags();

-- Official channel must never be deleted by application code.
create or replace function public.protect_official_channel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.is_official and not public.privileged_write_enabled() then
    raise exception 'The official BubbleApp channel cannot be deleted' using errcode = '42501';
  end if;
  return old;
end;
$$;

create trigger channels_protect_official before delete on public.channels
  for each row execute function public.protect_official_channel();

-- ---------------------------------------------------------------------------
-- Post-level triggers
-- ---------------------------------------------------------------------------
create or replace function public.enforce_pin_rules()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_pinned and not public.privileged_write_enabled() then
    -- pin changes must use set_channel_post_pinned()
    if tg_op = 'INSERT' or old.is_pinned is distinct from new.is_pinned then
      raise exception 'Use set_channel_post_pinned() to pin posts' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create trigger channel_posts_pin_rules before insert or update on public.channel_posts
  for each row execute function public.enforce_pin_rules();

-- ---------------------------------------------------------------------------
-- RPCs: subscriptions
-- ---------------------------------------------------------------------------
create or replace function public.subscribe_to_channel(p_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel public.channels%rowtype;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  select * into v_channel from public.channels where id = p_channel_id;
  if not found then
    raise exception 'Channel not found';
  end if;
  if not v_channel.is_public then
    raise exception 'This channel is private. Use an invite link to join.' using errcode = '42501';
  end if;
  insert into public.channel_subscribers (channel_id, user_id, is_active)
  values (p_channel_id, auth.uid(), true)
  on conflict (channel_id, user_id) do update
    set is_active = true where public.channel_subscribers.is_active = false;
end;
$$;

create or replace function public.unsubscribe_from_channel(p_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The guard trigger rejects unsubscribing from the mandatory official channel.
  update public.channel_subscribers
     set is_active = false
   where channel_id = p_channel_id and user_id = auth.uid() and is_active;
end;
$$;

create or replace function public.join_channel_by_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.channel_invitations%rowtype;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  select * into v_inv from public.channel_invitations where code = p_code for update;
  if not found or v_inv.revoked_at is not null then
    raise exception 'This invite link is no longer valid';
  end if;
  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    raise exception 'This invite link has expired';
  end if;
  if v_inv.max_uses is not null and v_inv.uses >= v_inv.max_uses then
    raise exception 'This invite link has reached its usage limit';
  end if;
  insert into public.channel_subscribers (channel_id, user_id, is_active)
  values (v_inv.channel_id, auth.uid(), true)
  on conflict (channel_id, user_id) do update
    set is_active = true where public.channel_subscribers.is_active = false;
  update public.channel_invitations set uses = uses + 1 where id = v_inv.id;
  return v_inv.channel_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs: channel management
-- ---------------------------------------------------------------------------
create or replace function public.delete_channel(p_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel public.channels%rowtype;
begin
  select * into v_channel from public.channels where id = p_channel_id for update;
  if not found then
    raise exception 'Channel not found';
  end if;
  if v_channel.is_official then
    raise exception 'The official BubbleApp channel cannot be deleted' using errcode = '42501';
  end if;
  if not public.can_manage_channel(p_channel_id) then
    raise exception 'Only the channel owner or an authorized administrator can delete this channel'
      using errcode = '42501';
  end if;
  perform public.write_audit('channel.delete', 'channel', p_channel_id::text,
    jsonb_build_object('username', v_channel.username));
  delete from public.channels where id = p_channel_id;
end;
$$;

create or replace function public.set_channel_post_pinned(p_post_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel uuid;
begin
  select channel_id into v_channel from public.channel_posts where id = p_post_id;
  if v_channel is null then
    raise exception 'Post not found';
  end if;
  if not public.can_manage_channel(v_channel) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  perform set_config('bubble.privileged', 'on', true);
  if p_pinned then
    update public.channel_posts set is_pinned = false
     where channel_id = v_channel and is_pinned and id <> p_post_id;
  end if;
  update public.channel_posts set is_pinned = p_pinned where id = p_post_id;
  perform set_config('bubble.privileged', 'off', true);
end;
$$;

create or replace function public.forward_channel_post(p_post_id uuid, p_target_channel uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_src public.channel_posts%rowtype;
  v_src_channel public.channels%rowtype;
  v_new uuid;
begin
  select * into v_src from public.channel_posts where id = p_post_id;
  if not found or v_src.hidden_at is not null then
    raise exception 'Post not found';
  end if;
  select * into v_src_channel from public.channels where id = v_src.channel_id;
  if not (v_src_channel.is_public or public.is_active_subscriber(v_src_channel.id)
          or public.can_manage_channel(v_src_channel.id)) then
    raise exception 'Post not found';
  end if;
  if not public.can_manage_channel(p_target_channel) then
    raise exception 'You can only forward into channels you manage' using errcode = '42501';
  end if;
  insert into public.channel_posts (channel_id, author_id, kind, body, media_path, media_mime, forwarded_from_post_id)
  values (p_target_channel, auth.uid(), v_src.kind, v_src.body, v_src.media_path, v_src.media_mime, v_src.id)
  returning id into v_new;
  return v_new;
end;
$$;

create or replace function public.record_channel_post_view(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel uuid;
  v_inserted integer;
begin
  select p.channel_id into v_channel
  from public.channel_posts p
  where p.id = p_post_id and p.publish_at <= now() and p.hidden_at is null;
  if v_channel is null then
    return;
  end if;
  if not exists (select 1 from public.channels c where c.id = v_channel and c.is_public)
     and not public.is_active_subscriber(v_channel) then
    return;
  end if;
  insert into public.channel_post_views (post_id, user_id) values (p_post_id, auth.uid())
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    update public.channel_posts set views_count = views_count + 1 where id = p_post_id;
  end if;
end;
$$;

create or replace function public.channel_stats(p_channel_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.can_manage_channel(p_channel_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'subscribers', (select count(*) from public.channel_subscribers s where s.channel_id = p_channel_id and s.is_active),
    'posts', (select count(*) from public.channel_posts p where p.channel_id = p_channel_id),
    'views', (select coalesce(sum(p.views_count), 0) from public.channel_posts p where p.channel_id = p_channel_id),
    'reactions', (select count(*) from public.channel_post_reactions r
                  join public.channel_posts p on p.id = r.post_id where p.channel_id = p_channel_id),
    'scheduled', (select count(*) from public.channel_posts p where p.channel_id = p_channel_id and p.publish_at > now())
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Signup: auth.users -> profile -> mandatory subscription
-- ---------------------------------------------------------------------------
create or replace function public.on_profile_created_enroll()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enroll_mandatory_subscriptions(new.id);
  return new;
end;
$$;

create trigger profiles_enroll_mandatory after insert on public.profiles
  for each row execute function public.on_profile_created_enroll();

-- Generates a valid default username such as user_3f9a1c0b2d4e5f60 (64-bit hash of the id).
-- Users can change it in Edit Profile; the unique index prevents collisions.
create or replace function public.generate_default_username(p_user_id uuid)
returns text
language sql
immutable
set search_path = public
as $$
  select 'user_' || substr(md5(p_user_id::text), 1, 16);
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_display text;
begin
  if not public.setting_bool('registration_enabled', true) then
    raise exception 'New registrations are temporarily disabled' using errcode = 'P0001';
  end if;

  v_display := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(new.email, 'bubble'), '@', 1)
  );

  insert into public.profiles (id, email, username, display_name)
  values (new.id, lower(new.email), public.generate_default_username(new.id), left(v_display, 64))
  on conflict (id) do nothing;

  insert into public.user_settings (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.account_modes (user_id, mode) values (new.id, 'personal')
  on conflict do nothing;
  return new;
end;
$$;

-- Supabase Auth triggers are the only supported entry point for new accounts.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Platform initialization: the official BubbleApp channel (@BubbleApp)
-- ---------------------------------------------------------------------------
insert into public.channels (owner_id, name, username, description, is_public, is_verified, verified_at,
                             is_official, is_mandatory)
select null, 'BubbleApp', 'bubbleapp',
       'The official BubbleApp announcement channel: platform updates, new features, maintenance notices, security announcements, events and community news.',
       true, true, now(), true, true
where not exists (select 1 from public.channels where is_official);

-- Backfill: enroll every existing account in the mandatory channel (idempotent).
insert into public.channel_subscribers (channel_id, user_id, is_active)
select c.id, p.id, true
from public.channels c cross join public.profiles p
where c.is_mandatory and c.is_official
on conflict (channel_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
alter table public.channels               enable row level security;
alter table public.channel_subscribers    enable row level security;
alter table public.channel_posts          enable row level security;
alter table public.channel_post_reactions enable row level security;
alter table public.channel_post_views     enable row level security;
alter table public.channel_comments       enable row level security;
alter table public.channel_invitations    enable row level security;

revoke all on public.channels, public.channel_subscribers, public.channel_posts,
  public.channel_post_reactions, public.channel_post_views, public.channel_comments,
  public.channel_invitations from anon, authenticated;

grant select on public.channels to authenticated;
grant insert (name, username, description, is_public, comments_enabled, owner_id) on public.channels to authenticated;
grant update (name, username, description, avatar_url, cover_url, is_public, comments_enabled) on public.channels to authenticated;
grant select on public.channel_subscribers to authenticated;
grant select on public.channel_posts to authenticated;
grant insert (channel_id, author_id, kind, body, media_path, media_mime, publish_at) on public.channel_posts to authenticated;
grant update (body, media_path, media_mime, publish_at) on public.channel_posts to authenticated;
grant select, insert, delete on public.channel_post_reactions to authenticated;
grant select on public.channel_post_views to authenticated;
grant select, insert, update on public.channel_comments to authenticated;
grant select, insert, update on public.channel_invitations to authenticated;

create policy channels_select on public.channels for select to authenticated using (
  is_public
  or owner_id = auth.uid()
  or public.is_active_subscriber(id)
  or public.has_permission('channels.manage')
);
create policy channels_insert_own on public.channels for insert to authenticated with check (
  owner_id = auth.uid() and public.is_active_user() and is_official = false and is_mandatory = false
);
create policy channels_update_managers on public.channels for update to authenticated
  using (public.can_manage_channel(id)) with check (public.can_manage_channel(id));

create policy channel_subscribers_select on public.channel_subscribers for select to authenticated using (
  user_id = auth.uid() or public.can_manage_channel(channel_id)
);
-- Subscriptions are changed only through subscribe_/unsubscribe_/join_ functions.

create policy channel_posts_select on public.channel_posts for select to authenticated using (
  public.can_manage_channel(channel_id)
  or (
    publish_at <= now() and hidden_at is null and (
      exists (select 1 from public.channels c where c.id = channel_id and c.is_public)
      or public.is_active_subscriber(channel_id)
    )
  )
);
create policy channel_posts_insert on public.channel_posts for insert to authenticated with check (
  author_id = auth.uid() and public.can_manage_channel(channel_id)
);
create policy channel_posts_update on public.channel_posts for update to authenticated
  using (public.can_manage_channel(channel_id)) with check (public.can_manage_channel(channel_id));
create policy channel_posts_delete on public.channel_posts for delete to authenticated
  using (public.can_manage_channel(channel_id));

create policy channel_post_reactions_select on public.channel_post_reactions for select to authenticated using (
  exists (select 1 from public.channel_posts p where p.id = post_id)
);
create policy channel_post_reactions_insert on public.channel_post_reactions for insert to authenticated with check (
  user_id = auth.uid() and public.is_active_user() and exists (
    select 1 from public.channel_posts p
    where p.id = post_id and p.publish_at <= now() and p.hidden_at is null
      and public.is_active_subscriber(p.channel_id)
  )
);
create policy channel_post_reactions_delete on public.channel_post_reactions for delete to authenticated using (
  user_id = auth.uid()
);

create policy channel_post_views_select on public.channel_post_views for select to authenticated using (
  user_id = auth.uid()
);

create policy channel_comments_select on public.channel_comments for select to authenticated using (
  exists (select 1 from public.channel_posts p where p.id = post_id)
);
create policy channel_comments_insert on public.channel_comments for insert to authenticated with check (
  author_id = auth.uid() and public.is_active_user() and exists (
    select 1 from public.channel_posts p
    join public.channels c on c.id = p.channel_id
    where p.id = post_id and c.comments_enabled and p.publish_at <= now() and p.hidden_at is null
      and public.is_active_subscriber(c.id)
  )
);
create policy channel_comments_update_own on public.channel_comments for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy channel_invitations_select on public.channel_invitations for select to authenticated using (
  public.can_manage_channel(channel_id)
);
create policy channel_invitations_insert on public.channel_invitations for insert to authenticated with check (
  created_by = auth.uid() and public.can_manage_channel(channel_id)
);
create policy channel_invitations_update on public.channel_invitations for update to authenticated
  using (public.can_manage_channel(channel_id)) with check (public.can_manage_channel(channel_id));
