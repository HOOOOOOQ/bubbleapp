-- =============================================================================
-- BubbleApp :: 0006 messaging + social graph
-- conversations / members / messages / receipts / reactions / attachments
-- contacts / blocked users / stories / story views / replies / communities
-- Realtime (postgres_changes) is enabled for messages and receipts in 0008.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null check (kind in ('direct', 'group', 'community')),
  title            text check (char_length(title) <= 100),
  avatar_url       text,
  direct_key       text unique,           -- "uidA:uidB" (sorted) for 1:1 chats
  created_by       uuid references public.profiles (id) on delete set null,
  last_message_at  timestamptz,
  created_at       timestamptz not null default now(),
  constraint conversations_direct_key check ((kind = 'direct') = (direct_key is not null))
);

create table if not exists public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  role             text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at        timestamptz not null default now(),
  left_at          timestamptz,
  muted            boolean not null default false,
  archived         boolean not null default false,
  pinned           boolean not null default false,
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx on public.conversation_members (user_id) where left_at is null;

create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = auth.uid() and m.left_at is null
  );
$$;

-- Creates (or returns) the 1:1 conversation with another active user.
create or replace function public.create_direct_conversation(p_other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_key text;
  v_id uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if p_other_user = v_uid then
    raise exception 'You cannot start a chat with yourself';
  end if;
  if not exists (select 1 from public.profiles where id = p_other_user and account_status = 'active') then
    raise exception 'This account is not available';
  end if;
  if public.is_blocked_between(v_uid, p_other_user) then
    raise exception 'You cannot message this account';
  end if;
  v_key := least(v_uid::text, p_other_user::text) || ':' || greatest(v_uid::text, p_other_user::text);
  insert into public.conversations (kind, direct_key, created_by)
  values ('direct', v_key, v_uid)
  on conflict (direct_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.conversations where direct_key = v_key;
  else
    insert into public.conversation_members (conversation_id, user_id, role)
    values (v_id, v_uid, 'member'), (v_id, p_other_user, 'member');
  end if;
  return v_id;
end;
$$;

create or replace function public.create_group_conversation(p_title text, p_member_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_member uuid;
  v_max integer := coalesce((select (setting_value)::text::integer from public.platform_settings where setting_key = 'max_group_members'), 1024);
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if array_length(p_member_ids, 1) is null or array_length(p_member_ids, 1) + 1 > v_max then
    raise exception 'Group size must be between 2 and % members', v_max;
  end if;
  insert into public.conversations (kind, title, created_by)
  values ('group', trim(p_title), v_uid) returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id, role) values (v_id, v_uid, 'owner');
  foreach v_member in array p_member_ids loop
    if v_member <> v_uid
       and exists (select 1 from public.profiles where id = v_member and account_status = 'active')
       and not public.is_blocked_between(v_uid, v_member) then
      insert into public.conversation_members (conversation_id, user_id, role)
      values (v_id, v_member, 'member') on conflict do nothing;
    end if;
  end loop;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id                 uuid primary key default gen_random_uuid(),
  conversation_id    uuid not null references public.conversations (id) on delete cascade,
  sender_id          uuid references public.profiles (id) on delete set null,
  client_message_id  uuid not null,
  kind               text not null default 'text'
                     check (kind in ('text', 'image', 'video', 'voice', 'document', 'location', 'contact', 'system')),
  body               text check (char_length(body) <= 4000),
  reply_to_id        uuid references public.messages (id) on delete set null,
  forwarded_from_id  uuid references public.messages (id) on delete set null,
  edited_at          timestamptz,
  deleted_at         timestamptz,
  hidden_at          timestamptz,
  expires_at         timestamptz,
  created_at         timestamptz not null default now(),
  constraint messages_body_required check (kind not in ('text') or body is not null or deleted_at is not null),
  constraint messages_client_unique unique (sender_id, client_message_id)
);
create index if not exists messages_conversation_time on public.messages (conversation_id, created_at desc);

create table if not exists public.message_receipts (
  message_id  uuid not null references public.messages (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  status      text not null check (status in ('delivered', 'read')),
  updated_at  timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table if not exists public.message_reactions (
  message_id  uuid not null references public.messages (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  emoji       text not null check (char_length(emoji) between 1 and 16),
  created_at  timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create table if not exists public.attachments (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  message_id       uuid references public.messages (id) on delete cascade,
  uploader_id      uuid not null references public.profiles (id) on delete cascade,
  storage_path     text not null unique,
  mime_type        text not null,
  size_bytes       bigint not null check (size_bytes > 0),
  width            integer,
  height           integer,
  duration_ms      integer,
  created_at       timestamptz not null default now()
);

-- Keep conversation.last_message_at in sync (definer, column not client-writable).
create or replace function public.touch_conversation_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end;
$$;
create trigger messages_touch_conversation after insert on public.messages
  for each row execute function public.touch_conversation_on_message();

-- Sender-only edits and deletes (tombstones keep ordering).
create or replace function public.edit_message(p_message_id uuid, p_body text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.messages
     set body = trim(p_body), edited_at = now()
   where id = p_message_id and sender_id = auth.uid() and kind = 'text'
     and deleted_at is null and public.is_conversation_member(conversation_id);
  if not found then
    raise exception 'This message cannot be edited' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.delete_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.messages
     set body = null, deleted_at = now()
   where id = p_message_id and sender_id = auth.uid() and deleted_at is null;
  if not found then
    raise exception 'This message cannot be deleted' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'Not a member of this conversation' using errcode = '42501';
  end if;
  insert into public.message_receipts (message_id, user_id, status)
  select m.id, auth.uid(), 'read'
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.sender_id is distinct from auth.uid()
  on conflict (message_id, user_id) do update set status = 'read', updated_at = now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Social graph
-- ---------------------------------------------------------------------------
create table if not exists public.contacts (
  owner_id     uuid not null references public.profiles (id) on delete cascade,
  contact_id   uuid not null references public.profiles (id) on delete cascade,
  nickname     text check (char_length(nickname) <= 64),
  is_favorite  boolean not null default false,
  created_at   timestamptz not null default now(),
  primary key (owner_id, contact_id),
  constraint contacts_not_self check (owner_id <> contact_id)
);

create table if not exists public.blocked_users (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_not_self check (blocker_id <> blocked_id)
);

create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocked_users b
    where (b.blocker_id = p_a and b.blocked_id = p_b) or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

create or replace function public.is_contact_of(p_owner uuid, p_contact uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.contacts c where c.owner_id = p_owner and c.contact_id = p_contact);
$$;

create table if not exists public.stories (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('text', 'photo', 'video')),
  body         text check (char_length(body) <= 500),
  media_path   text,
  background   text,
  privacy      text not null default 'contacts' check (privacy in ('contacts', 'everyone')),
  hidden_at    timestamptz,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '24 hours'),
  constraint stories_24h check (expires_at <= created_at + interval '24 hours'),
  constraint stories_content check (kind = 'text' and body is not null or kind <> 'text' and media_path is not null)
);
create index if not exists stories_author_idx on public.stories (author_id, created_at desc);

create table if not exists public.story_views (
  story_id   uuid not null references public.stories (id) on delete cascade,
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create table if not exists public.story_reactions (
  story_id   uuid not null references public.stories (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  primary key (story_id, user_id)
);

create table if not exists public.story_replies (
  id         uuid primary key default gen_random_uuid(),
  story_id   uuid not null references public.stories (id) on delete cascade,
  author_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create or replace function public.can_view_story(p_story_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and s.expires_at > now()
      and s.hidden_at is null
      and (
        s.author_id = auth.uid()
        or (
          not public.is_blocked_between(auth.uid(), s.author_id)
          and (s.privacy = 'everyone' or public.is_contact_of(s.author_id, auth.uid()))
        )
      )
  );
$$;

-- Communities (group chat is backed by a conversation of kind 'community')
create table if not exists public.communities (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(name) between 2 and 80),
  description      text not null default '' check (char_length(description) <= 1000),
  avatar_url       text,
  cover_url        text,
  visibility       text not null default 'private' check (visibility in ('public', 'private')),
  owner_id         uuid not null references public.profiles (id) on delete cascade,
  conversation_id  uuid unique references public.conversations (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger communities_touch before update on public.communities
  for each row execute function public.touch_updated_at();

create table if not exists public.community_members (
  community_id  uuid not null references public.communities (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  role          text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at     timestamptz not null default now(),
  primary key (community_id, user_id)
);

create table if not exists public.community_announcements (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities (id) on delete cascade,
  author_id     uuid references public.profiles (id) on delete set null,
  body          text not null check (char_length(body) between 1 and 4000),
  created_at    timestamptz not null default now()
);

-- SECURITY DEFINER helpers avoid RLS recursion between communities and community_members.
create or replace function public.is_community_member(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.community_members m
    where m.community_id = p_community_id and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_community_admin(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.community_members m
    where m.community_id = p_community_id and m.user_id = auth.uid() and m.role in ('owner', 'admin')
  );
$$;

create or replace function public.create_community(p_name text, p_description text, p_visibility text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_conv uuid;
  v_community uuid;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  if p_visibility not in ('public', 'private') then
    raise exception 'Invalid visibility';
  end if;
  insert into public.conversations (kind, title, created_by) values ('community', trim(p_name), v_uid)
  returning id into v_conv;
  insert into public.communities (name, description, visibility, owner_id, conversation_id)
  values (trim(p_name), coalesce(p_description, ''), p_visibility, v_uid, v_conv)
  returning id into v_community;
  insert into public.community_members (community_id, user_id, role) values (v_community, v_uid, 'owner');
  insert into public.conversation_members (conversation_id, user_id, role) values (v_conv, v_uid, 'owner');
  return v_community;
end;
$$;

create or replace function public.join_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.communities%rowtype;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;
  select * into v_c from public.communities where id = p_community_id;
  if not found or v_c.visibility <> 'public' then
    raise exception 'This community is private. Ask an admin for an invitation.' using errcode = '42501';
  end if;
  insert into public.community_members (community_id, user_id) values (p_community_id, auth.uid())
  on conflict do nothing;
  if v_c.conversation_id is not null then
    insert into public.conversation_members (conversation_id, user_id) values (v_c.conversation_id, auth.uid())
    on conflict (conversation_id, user_id) do update set left_at = null;
  end if;
end;
$$;

create or replace function public.leave_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.communities%rowtype;
begin
  select * into v_c from public.communities where id = p_community_id;
  if not found then raise exception 'Community not found'; end if;
  if v_c.owner_id = auth.uid() then
    raise exception 'Transfer ownership before leaving your community' using errcode = '42501';
  end if;
  delete from public.community_members where community_id = p_community_id and user_id = auth.uid();
  if v_c.conversation_id is not null then
    update public.conversation_members set left_at = now()
     where conversation_id = v_c.conversation_id and user_id = auth.uid();
  end if;
end;
$$;

-- Community admins add members directly (invitation notification is sent by the app).
create or replace function public.add_community_member(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.communities%rowtype;
  v_max integer := coalesce((select (setting_value)::text::integer from public.platform_settings where setting_key = 'max_group_members'), 1024);
begin
  select * into v_c from public.communities where id = p_community_id;
  if not found or not (v_c.owner_id = auth.uid() or public.is_community_admin(p_community_id)) then
    raise exception 'Only community admins can add members' using errcode = '42501';
  end if;
  if public.is_blocked_between(auth.uid(), p_user_id) then
    raise exception 'This account cannot be added';
  end if;
  if (select count(*) from public.community_members where community_id = p_community_id) >= v_max then
    raise exception 'Community is full (% members)', v_max;
  end if;
  insert into public.community_members (community_id, user_id) values (p_community_id, p_user_id)
  on conflict do nothing;
  if v_c.conversation_id is not null then
    insert into public.conversation_members (conversation_id, user_id) values (v_c.conversation_id, p_user_id)
    on conflict (conversation_id, user_id) do update set left_at = null;
  end if;
end;
$$;

create or replace function public.set_community_member_role(p_community_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c public.communities%rowtype;
begin
  select * into v_c from public.communities where id = p_community_id;
  if not found or v_c.owner_id <> auth.uid() then
    raise exception 'Only the community owner can manage roles' using errcode = '42501';
  end if;
  if p_user_id = v_c.owner_id then
    raise exception 'The owner role cannot be changed here';
  end if;
  if p_role not in ('admin', 'member') then
    raise exception 'Invalid role';
  end if;
  update public.community_members set role = p_role where community_id = p_community_id and user_id = p_user_id;
  if v_c.conversation_id is not null then
    update public.conversation_members set role = p_role
     where conversation_id = v_c.conversation_id and user_id = p_user_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['conversations', 'conversation_members', 'messages', 'message_receipts',
    'message_reactions', 'attachments', 'contacts', 'blocked_users', 'stories', 'story_views',
    'story_reactions', 'story_replies', 'communities', 'community_members', 'community_announcements']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- Conversations & members
grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant update (muted, archived, pinned) on public.conversation_members to authenticated;
grant update (title, avatar_url) on public.conversations to authenticated;

create policy conversations_select on public.conversations for select to authenticated using (
  public.is_conversation_member(id)
);
create policy conversations_update_admin on public.conversations for update to authenticated using (
  exists (select 1 from public.conversation_members m
          where m.conversation_id = id and m.user_id = auth.uid() and m.left_at is null and m.role in ('owner', 'admin'))
) with check (true);

create policy conversation_members_select on public.conversation_members for select to authenticated using (
  public.is_conversation_member(conversation_id)
);
create policy conversation_members_update_own on public.conversation_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Messages: members write; blocked pairs cannot exchange direct messages.
grant select on public.messages to authenticated;
grant insert (id, conversation_id, sender_id, client_message_id, kind, body, reply_to_id, forwarded_from_id, expires_at)
  on public.messages to authenticated;
grant select on public.message_receipts to authenticated;
grant select, insert, delete on public.message_reactions to authenticated;
grant select, insert on public.attachments to authenticated;
grant select, insert, update, delete on public.contacts to authenticated;
grant update (nickname, is_favorite) on public.contacts to authenticated;
grant select, insert, delete on public.blocked_users to authenticated;
grant select, insert, delete on public.stories to authenticated;
grant select on public.story_views to authenticated;
grant insert on public.story_views to authenticated;
grant select, insert, delete on public.story_reactions to authenticated;
grant select, insert, delete on public.story_replies to authenticated;
grant select, insert, update on public.communities to authenticated;
grant select on public.community_members to authenticated;
grant select on public.community_announcements to authenticated;
grant insert on public.community_announcements to authenticated;

create policy messages_select on public.messages for select to authenticated using (
  public.is_conversation_member(conversation_id)
  and (hidden_at is null or sender_id = auth.uid())
);
create policy messages_insert on public.messages for insert to authenticated with check (
  sender_id = auth.uid()
  and public.is_active_user()
  and public.is_conversation_member(conversation_id)
  and not exists (
    select 1 from public.conversations c
    join public.conversation_members m on m.conversation_id = c.id and m.user_id <> auth.uid() and m.left_at is null
    where c.id = conversation_id and c.kind = 'direct'
      and public.is_blocked_between(auth.uid(), m.user_id)
  )
);

create policy message_receipts_select on public.message_receipts for select to authenticated using (
  exists (select 1 from public.messages m where m.id = message_id)
);
create policy message_receipts_upsert_delivered on public.message_receipts for insert to authenticated with check (
  user_id = auth.uid() and status = 'delivered'
  and exists (select 1 from public.messages m where m.id = message_id and m.sender_id <> auth.uid())
);

create policy message_reactions_select on public.message_reactions for select to authenticated using (
  exists (select 1 from public.messages m where m.id = message_id)
);
create policy message_reactions_insert on public.message_reactions for insert to authenticated with check (
  user_id = auth.uid() and exists (select 1 from public.messages m where m.id = message_id)
);
create policy message_reactions_delete on public.message_reactions for delete to authenticated using (
  user_id = auth.uid()
);

create policy attachments_select on public.attachments for select to authenticated using (
  public.is_conversation_member(conversation_id)
);
create policy attachments_insert on public.attachments for insert to authenticated with check (
  uploader_id = auth.uid() and public.is_conversation_member(conversation_id)
  and split_part(storage_path, '/', 1) = conversation_id::text
);

create policy contacts_own on public.contacts for all to authenticated
  using (owner_id = auth.uid()) with check (
    owner_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = contact_id and p.account_status = 'active')
    and not public.is_blocked_between(owner_id, contact_id)
  );

create policy blocked_users_own on public.blocked_users for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- Authors always see their own stories directly (also covers INSERT ... RETURNING in the
-- same statement, which a STABLE helper cannot see); viewers go through can_view_story().
create policy stories_select on public.stories for select to authenticated using (
  author_id = auth.uid() or public.can_view_story(id)
);
create policy stories_insert on public.stories for insert to authenticated with check (
  author_id = auth.uid() and public.is_active_user()
);
create policy stories_delete on public.stories for delete to authenticated using (author_id = auth.uid());

create policy story_views_select on public.story_views for select to authenticated using (
  viewer_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
);
create policy story_views_insert on public.story_views for insert to authenticated with check (
  viewer_id = auth.uid() and public.can_view_story(story_id)
);
create policy story_reactions_select on public.story_reactions for select to authenticated using (
  user_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
);
create policy story_reactions_insert on public.story_reactions for insert to authenticated with check (
  user_id = auth.uid() and public.can_view_story(story_id)
);
create policy story_reactions_delete on public.story_reactions for delete to authenticated using (user_id = auth.uid());
create policy story_replies_select on public.story_replies for select to authenticated using (
  author_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
);
create policy story_replies_insert on public.story_replies for insert to authenticated with check (
  author_id = auth.uid() and public.can_view_story(story_id)
);

create policy communities_select on public.communities for select to authenticated using (
  visibility = 'public' or public.is_community_member(id)
);
create policy communities_insert on public.communities for insert to authenticated with check (
  owner_id = auth.uid() and false  -- creation goes through create_community()
);
create policy communities_update_admin on public.communities for update to authenticated using (
  owner_id = auth.uid() or public.is_community_admin(id)
) with check (owner_id = auth.uid() or public.is_community_admin(id));

create policy community_members_select on public.community_members for select to authenticated using (
  public.is_community_member(community_id)
  or exists (select 1 from public.communities c where c.id = community_id and c.visibility = 'public')
);
create policy community_announcements_select on public.community_announcements for select to authenticated using (
  public.is_community_member(community_id)
);
create policy community_announcements_insert on public.community_announcements for insert to authenticated with check (
  author_id = auth.uid() and public.is_community_admin(community_id)
);
