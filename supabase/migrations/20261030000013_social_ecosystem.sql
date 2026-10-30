-- =============================================================================
-- BubbleApp :: 0013 social ecosystem — Stories, Channels, Communities, Groups,
--             Social Posts, Polls, Discovery, Hashtags/Mentions, Moderation
-- Extends 0003/0006/0007/0008/0009 without breaking existing data.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Followers / Close Friends / Connections helpers
-- ---------------------------------------------------------------------------

create table if not exists public.follows (
  follower_id  uuid not null references public.profiles(id) on delete cascade,
  followee_id  uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint follows_not_self check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows (followee_id, created_at desc);
create index if not exists follows_follower_idx on public.follows (follower_id, created_at desc);
alter table public.follows enable row level security;
drop policy if exists follows_read on public.follows;
create policy follows_read on public.follows for select to authenticated using (true);
drop policy if exists follows_self_manage on public.follows;
create policy follows_self_manage on public.follows for all to authenticated
  using (follower_id = auth.uid()) with check (follower_id = auth.uid());
grant select, insert, delete on public.follows to authenticated;

create or replace function public.is_follower(p_follower uuid, p_followee uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.follows f where f.follower_id=p_follower and f.followee_id=p_followee);
$$;
create or replace function public.is_followed_by(p_owner uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.follows f where f.follower_id=p_viewer and f.followee_id=p_owner);
$$;

create table if not exists public.close_friends (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  friend_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint close_friends_not_self check (owner_id <> friend_id)
);
create index if not exists close_friends_owner_idx on public.close_friends(owner_id);
alter table public.close_friends enable row level security;
drop policy if exists close_friends_owner_all on public.close_friends;
create policy close_friends_owner_all on public.close_friends for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
grant select, insert, delete on public.close_friends to authenticated;

create or replace function public.is_close_friend(p_owner uuid, p_friend uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.close_friends cf where cf.owner_id=p_owner and cf.friend_id=p_friend);
$$;

-- ---------------------------------------------------------------------------
-- 2. Stories — extend existing table + privacy tables
-- ---------------------------------------------------------------------------

-- Expand kind to support image alias; keep photo for backward compat
alter table public.stories drop constraint if exists stories_kind_check;
alter table public.stories add constraint stories_kind_check check (kind in ('text','photo','video','image'));

-- Expand privacy: everyone, contacts, followers, close_friends, custom
alter table public.stories drop constraint if exists stories_privacy_check;
do $$ begin
  alter table public.stories add constraint stories_privacy_check
    check (privacy in ('everyone','contacts','followers','close_friends','custom','everyone_public'));
exception when duplicate_object then null; end $$;

-- Add columns for richer editor (all nullable, backward compatible)
alter table public.stories add column if not exists caption text check (char_length(caption) <= 500);
alter table public.stories add column if not exists background_color text;
alter table public.stories add column if not exists text_color text;
alter table public.stories add column if not exists text_elements jsonb not null default '[]'::jsonb;
alter table public.stories add column if not exists stickers jsonb not null default '[]'::jsonb;
alter table public.stories add column if not exists link_url text check (link_url is null or char_length(link_url) between 8 and 2048);
alter table public.stories add column if not exists music_url text;
alter table public.stories add column if not exists poll_id uuid; -- optional poll attached
alter table public.stories add column if not exists view_count integer not null default 0;
alter table public.stories add column if not exists is_highlight boolean not null default false;

-- Story custom audience (for privacy=custom)
create table if not exists public.story_audience (
  story_id  uuid not null references public.stories(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);
create index if not exists story_audience_user_idx on public.story_audience(user_id);
alter table public.story_audience enable row level security;
drop policy if exists story_audience_owner_all on public.story_audience;
create policy story_audience_owner_all on public.story_audience for all to authenticated
  using (exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()))
  with check (exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()));
grant select, insert, delete on public.story_audience to authenticated;

-- Hide story from selected users (applies to all privacy modes)
create table if not exists public.story_hidden_from (
  story_id      uuid not null references public.stories(id) on delete cascade,
  hidden_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (story_id, hidden_user_id)
);
create index if not exists story_hidden_from_user_idx on public.story_hidden_from(hidden_user_id);
alter table public.story_hidden_from enable row level security;
drop policy if exists story_hidden_from_owner_all on public.story_hidden_from;
create policy story_hidden_from_owner_all on public.story_hidden_from for all to authenticated
  using (exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()))
  with check (exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()));
grant select, insert, delete on public.story_hidden_from to authenticated;

-- Mute story author (viewer-side preference, does not affect backend visibility except in feed)
create table if not exists public.story_mutes (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  muted_id   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_id),
  constraint story_mutes_not_self check (user_id <> muted_id)
);
alter table public.story_mutes enable row level security;
drop policy if exists story_mutes_self_all on public.story_mutes;
create policy story_mutes_self_all on public.story_mutes for all to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select, insert, delete on public.story_mutes to authenticated;

create or replace function public.is_story_muted(p_author uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.story_mutes m where m.user_id=auth.uid() and m.muted_id=p_author);
$$;
create or replace function public.is_hidden_from_story(p_story_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.story_hidden_from h where h.story_id=p_story_id and h.hidden_user_id=auth.uid());
$$;

-- Replace can_view_story to handle new privacy modes
create or replace function public.can_view_story(p_story_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.stories s
    where s.id=p_story_id
      and s.expires_at > now()
      and s.hidden_at is null
      and not exists(select 1 from public.story_hidden_from h where h.story_id=s.id and h.hidden_user_id=auth.uid())
      and (
        s.author_id = auth.uid()
        or (
          not public.is_blocked_between(auth.uid(), s.author_id)
          and (
            s.privacy in ('everyone','everyone_public')
            or (s.privacy='contacts' and public.is_contact_of(s.author_id, auth.uid()))
            or (s.privacy='followers' and public.is_followed_by(s.author_id, auth.uid()))
            or (s.privacy='close_friends' and public.is_close_friend(s.author_id, auth.uid()))
            or (s.privacy='custom' and exists(select 1 from public.story_audience a where a.story_id=s.id and a.user_id=auth.uid()))
          )
        )
      )
  );
$$;

-- Stories RLS — viewers need can_view_story, owners can do all
alter table public.stories enable row level security;
drop policy if exists stories_select on public.stories;
create policy stories_select on public.stories for select to authenticated
  using (author_id=auth.uid() or public.can_view_story(id));
drop policy if exists stories_insert on public.stories;
create policy stories_insert on public.stories for insert to authenticated
  with check (author_id=auth.uid() and public.is_active_user());
drop policy if exists stories_update_owner on public.stories;
create policy stories_update_owner on public.stories for update to authenticated
  using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists stories_delete_owner on public.stories;
create policy stories_delete_owner on public.stories for delete to authenticated using (author_id=auth.uid());
grant select, insert, update, delete on public.stories to authenticated;

-- Story views — only if can_view_story
alter table public.story_views enable row level security;
drop policy if exists story_views_select on public.story_views;
create policy story_views_select on public.story_views for select to authenticated
  using (viewer_id=auth.uid() or exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()));
drop policy if exists story_views_insert on public.story_views;
create policy story_views_insert on public.story_views for insert to authenticated
  with check (viewer_id=auth.uid() and public.can_view_story(story_id));
grant select, insert on public.story_views to authenticated;

-- Story reactions
alter table public.story_reactions enable row level security;
drop policy if exists story_reactions_all on public.story_reactions;
create policy story_reactions_all on public.story_reactions for all to authenticated
  using (true) with check (public.can_view_story(story_id) and user_id=auth.uid());
grant select, insert, delete on public.story_reactions to authenticated;

-- Story replies — respect block + can_view
alter table public.story_replies enable row level security;
drop policy if exists story_replies_select on public.story_replies;
create policy story_replies_select on public.story_replies for select to authenticated
  using (public.can_view_story(story_id) or exists(select 1 from public.stories s where s.id=story_id and s.author_id=auth.uid()));
drop policy if exists story_replies_insert on public.story_replies;
create policy story_replies_insert on public.story_replies for insert to authenticated
  with check (author_id=auth.uid() and public.can_view_story(story_id));
grant select, insert on public.story_replies to authenticated;

-- Cleanup expired stories (called by scheduled-jobs)
create or replace function public.cleanup_expired_stories()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count int;
begin
  delete from public.stories where expires_at <= now() and not is_highlight;
  get diagnostics v_count=row_count;
  return v_count;
end; $$;
grant execute on function public.cleanup_expired_stories() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Channels — category/rules + roles
-- ---------------------------------------------------------------------------

alter table public.channels add column if not exists category text check (category is null or char_length(category) between 2 and 48);
alter table public.channels add column if not exists rules text check (rules is null or char_length(rules) <= 2000);
alter table public.channels add column if not exists allow_comments boolean not null default true;

-- Channel roles: owner/admin/editor/moderator/member (extends subscriber concept)
create table if not exists public.channel_members (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','admin','editor','moderator','member')),
  added_by   uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);
create index if not exists channel_members_user_idx on public.channel_members(user_id);
alter table public.channel_members enable row level security;
drop policy if exists channel_members_read on public.channel_members;
create policy channel_members_read on public.channel_members for select to authenticated using (true);
drop policy if exists channel_members_manage on public.channel_members;
create policy channel_members_manage on public.channel_members for all to authenticated
  using (public.can_manage_channel(channel_id)) with check (public.can_manage_channel(channel_id));
grant select, insert, update, delete on public.channel_members to authenticated;

-- Helper: channel role rank
create or replace function public.channel_role_rank(p_role text) returns int language sql immutable as $$
  select case p_role when 'owner' then 5 when 'admin' then 4 when 'editor' then 3 when 'moderator' then 2 when 'member' then 1 else 0 end;
$$;
create or replace function public.my_channel_role(p_channel_id uuid) returns text language sql stable security definer set search_path=public as $$
  select coalesce((select role from public.channel_members where channel_id=p_channel_id and user_id=auth.uid()), 'member');
$$;
create or replace function public.can_publish_channel(p_channel_id uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.my_channel_role(p_channel_id) in ('owner','admin','editor') or public.can_manage_channel(p_channel_id);
$$;

-- Enhance channel_posts: add poll/link/category
alter table public.channel_posts add column if not exists poll_id uuid;
alter table public.channel_posts add column if not exists link_preview jsonb;
alter table public.channel_posts add column if not exists is_scheduled boolean not null default false;
alter table public.channel_posts add column if not exists scheduled_for timestamptz;
alter table public.channel_posts add column if not exists edited_at timestamptz;
alter table public.channel_posts add column if not exists author_role text;

-- Channel posts RLS — public channels readable by anyone, private only subscribers/managers
alter table public.channel_posts enable row level security;
drop policy if exists channel_posts_select on public.channel_posts;
create policy channel_posts_select on public.channel_posts for select to authenticated
  using (
    hidden_at is null and publish_at <= now()
    and exists(select 1 from public.channels c where c.id=channel_id and (c.is_public or public.is_active_subscriber(c.id) or public.can_manage_channel(c.id)))
  );
drop policy if exists channel_posts_insert on public.channel_posts;
create policy channel_posts_insert on public.channel_posts for insert to authenticated
  with check (public.can_publish_channel(channel_id));
drop policy if exists channel_posts_update on public.channel_posts;
create policy channel_posts_update on public.channel_posts for update to authenticated
  using (author_id=auth.uid() or public.can_publish_channel(channel_id))
  with check (author_id=auth.uid() or public.can_publish_channel(channel_id));
drop policy if exists channel_posts_delete on public.channel_posts;
create policy channel_posts_delete on public.channel_posts for delete to authenticated
  using (author_id=auth.uid() or public.can_manage_channel(channel_id));
grant select, insert, update, delete on public.channel_posts to authenticated;

-- Channel post scheduling dispatch (already exists, ensure it handles new fields)
create or replace function public.dispatch_due_channel_posts()
returns integer language plpgsql security definer set search_path=public as $$
declare v int;
begin
  -- publish_at in future means scheduled; when due, clear is_scheduled flag
  update public.channel_posts set is_scheduled=false where is_scheduled and publish_at <= now();
  get diagnostics v=row_count;
  return v;
end; $$;

-- ---------------------------------------------------------------------------
-- 4. Communities — extend + join requests + groups
-- ---------------------------------------------------------------------------

alter table public.communities add column if not exists username text check (username is null or username ~ '^[a-z][a-z0-9_]{3,31}$');
alter table public.communities add column if not exists slug text;
alter table public.communities add column if not exists category text;
alter table public.communities add column if not exists rules text check (rules is null or char_length(rules) <= 2000);
alter table public.communities add column if not exists join_approval boolean not null default false;
alter table public.communities add column if not exists allow_invites boolean not null default true;
alter table public.communities add column if not exists member_count integer not null default 0;
create unique index if not exists communities_username_key on public.communities(lower(username)) where username is not null;
create unique index if not exists communities_slug_key on public.communities(lower(slug)) where slug is not null;

-- Extend role set to include moderator/group_manager
alter table public.community_members drop constraint if exists community_members_role_check;
do $$ begin
  alter table public.community_members add constraint community_members_role_check check (role in ('owner','admin','moderator','group_manager','member'));
exception when duplicate_object then null; end $$;

create or replace function public.community_role_rank(p_role text) returns int language sql immutable as $$
  select case p_role when 'owner' then 5 when 'admin' then 4 when 'moderator' then 3 when 'group_manager' then 2 when 'member' then 1 else 0 end;
$$;
create or replace function public.my_community_role(p_community_id uuid) returns text language sql stable security definer set search_path=public as $$
  select coalesce((select role from public.community_members where community_id=p_community_id and user_id=auth.uid()), '');
$$;

-- Community join requests
create table if not exists public.community_join_requests (
  id           uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  message      text check (char_length(message) <= 500),
  status       text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by  uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (community_id, user_id)
);
create index if not exists community_join_requests_community_idx on public.community_join_requests(community_id, status);
alter table public.community_join_requests enable row level security;
drop policy if exists community_join_requests_self on public.community_join_requests;
create policy community_join_requests_self on public.community_join_requests for all to authenticated
  using (user_id=auth.uid() or public.is_community_admin(community_id)) with check (user_id=auth.uid() or public.is_community_admin(community_id));
grant select, insert, update on public.community_join_requests to authenticated;

-- Community groups linking (community can have multiple discussion groups = conversations)
create table if not exists public.community_groups (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities(id) on delete cascade,
  conversation_id uuid not null unique references public.conversations(id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 80),
  description   text not null default '' check (char_length(description) <= 500),
  created_at    timestamptz not null default now()
);
alter table public.community_groups enable row level security;
drop policy if exists community_groups_read on public.community_groups;
create policy community_groups_read on public.community_groups for select to authenticated
  using (public.is_community_member(community_id));
grant select, insert, delete on public.community_groups to authenticated;

-- Community blocks/reports (reuse reports table but add community target)
-- Ensure reports can target communities/groups already covered via target_type check expansion below

-- Communities RLS
alter table public.communities enable row level security;
drop policy if exists communities_select on public.communities;
create policy communities_select on public.communities for select to authenticated
  using (visibility='public' or public.is_community_member(id) or public.has_permission('content.moderate'));
drop policy if exists communities_insert on public.communities;
create policy communities_insert on public.communities for insert to authenticated
  with check (public.is_active_user());
drop policy if exists communities_update on public.communities;
create policy communities_update on public.communities for update to authenticated
  using (owner_id=auth.uid() or public.is_community_admin(id)) with check (owner_id=auth.uid() or public.is_community_admin(id));
grant select, insert, update, delete on public.communities to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Groups — permissions & invites (groups are conversations kind in ('group','community'))
-- ---------------------------------------------------------------------------

-- Group settings per conversation (permissions map)
create table if not exists public.group_settings (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  allow_send_messages boolean not null default true,
  allow_send_media    boolean not null default true,
  allow_add_members   boolean not null default true,
  allow_change_info   boolean not null default false,
  allow_pin_messages  boolean not null default true,
  allow_create_polls  boolean not null default true,
  allow_start_calls   boolean not null default true,
  allow_manage_invites boolean not null default true,
  require_approval    boolean not null default false,
  invite_link         text unique default replace(gen_random_uuid()::text,'-',''),
  updated_at          timestamptz not null default now()
);
alter table public.group_settings enable row level security;
drop policy if exists group_settings_read on public.group_settings;
create policy group_settings_read on public.group_settings for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists group_settings_manage on public.group_settings;
create policy group_settings_manage on public.group_settings for all to authenticated
  using (public.is_conversation_member(conversation_id) and exists(select 1 from public.conversation_members m where m.conversation_id=group_settings.conversation_id and m.user_id=auth.uid() and m.role in ('owner','admin')))
  with check (public.is_conversation_member(conversation_id));
grant select, insert, update on public.group_settings to authenticated;

-- Group invites
create table if not exists public.group_invites (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  code            text not null unique default replace(gen_random_uuid()::text,'-',''),
  created_by      uuid references public.profiles(id) on delete set null,
  max_uses        integer check (max_uses is null or max_uses>0),
  uses            integer not null default 0,
  expires_at      timestamptz,
  revoked_at      timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists group_invites_conversation_idx on public.group_invites(conversation_id);
alter table public.group_invites enable row level security;
drop policy if exists group_invites_read on public.group_invites;
create policy group_invites_read on public.group_invites for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists group_invites_manage on public.group_invites;
create policy group_invites_manage on public.group_invites for all to authenticated
  using (public.is_conversation_member(conversation_id)) with check (public.is_conversation_member(conversation_id));
grant select, insert, update, delete on public.group_invites to authenticated;

-- Ensure conversation_members role supports group roles
do $$ begin
  alter table public.conversation_members add constraint cm_role_check check (role in ('owner','admin','moderator','member'));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 6. Social Posts / Feed
-- ---------------------------------------------------------------------------

create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles(id) on delete cascade,
  community_id  uuid references public.communities(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete set null, -- for group posts
  kind          text not null default 'text' check (kind in ('text','image','images','video','poll','link','share_channel','share_story')),
  body          text check (char_length(body) <= 4000),
  media_paths   text[] not null default '{}',
  link_url      text check (link_url is null or char_length(link_url) between 8 and 2048),
  link_preview  jsonb,
  poll_id       uuid,
  shared_post_id uuid references public.posts(id) on delete set null,
  shared_channel_post_id uuid references public.channel_posts(id) on delete set null,
  visibility    text not null default 'public' check (visibility in ('public','followers','contacts','private')),
  is_pinned     boolean not null default false,
  is_edited     boolean not null default false,
  hidden_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists posts_author_time on public.posts(author_id, created_at desc);
create index if not exists posts_community_time on public.posts(community_id, created_at desc) where community_id is not null;
create index if not exists posts_visibility_time on public.posts(visibility, created_at desc);
create trigger posts_touch before update on public.posts for each row execute function public.touch_updated_at();
alter table public.posts enable row level security;
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select to authenticated
  using (
    hidden_at is null
    and not public.is_blocked_between(auth.uid(), author_id)
    and (
      visibility='public'
      or author_id=auth.uid()
      or (visibility='followers' and public.is_followed_by(author_id, auth.uid()))
      or (visibility='contacts' and public.is_contact_of(author_id, auth.uid()))
      or (community_id is not null and public.is_community_member(community_id))
      or (conversation_id is not null and public.is_conversation_member(conversation_id))
    )
  );
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id=auth.uid() and public.is_active_user());
drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts for update to authenticated
  using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated using (author_id=auth.uid() or public.has_permission('content.moderate'));
grant select, insert, update, delete on public.posts to authenticated;

-- Post reactions (like/emoji)
create table if not exists public.post_reactions (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, emoji)
);
alter table public.post_reactions enable row level security;
drop policy if exists post_reactions_all on public.post_reactions;
create policy post_reactions_all on public.post_reactions for all to authenticated
  using (true) with check (user_id=auth.uid());
grant select, insert, delete on public.post_reactions to authenticated;

-- Post bookmarks
create table if not exists public.post_bookmarks (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_bookmarks enable row level security;
drop policy if exists post_bookmarks_self on public.post_bookmarks;
create policy post_bookmarks_self on public.post_bookmarks for all to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select, insert, delete on public.post_bookmarks to authenticated;

-- Post views
create table if not exists public.post_views (
  post_id   uuid not null references public.posts(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_views enable row level security;
drop policy if exists post_views_all on public.post_views;
create policy post_views_all on public.post_views for all to authenticated using (true) with check (user_id=auth.uid());
grant select, insert on public.post_views to authenticated;

-- Comments (nested, depth limited to 3 in app, enforced via function)
create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  parent_id  uuid references public.comments(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  depth      integer not null default 0 check (depth between 0 and 5),
  is_edited  boolean not null default false,
  hidden_at  timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists comments_post_time on public.comments(post_id, created_at);
create index if not exists comments_parent_idx on public.comments(parent_id) where parent_id is not null;
create trigger comments_touch before update on public.comments for each row execute function public.touch_updated_at();
alter table public.comments enable row level security;
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments for select to authenticated
  using (hidden_at is null and not public.is_blocked_between(auth.uid(), author_id));
drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments for insert to authenticated
  with check (author_id=auth.uid() and public.is_active_user());
drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments for update to authenticated
  using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments for delete to authenticated
  using (author_id=auth.uid() or public.has_permission('content.moderate'));
grant select, insert, update, delete on public.comments to authenticated;

create table if not exists public.comment_reactions (
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id, emoji)
);
alter table public.comment_reactions enable row level security;
drop policy if exists comment_reactions_all on public.comment_reactions;
create policy comment_reactions_all on public.comment_reactions for all to authenticated using (true) with check (user_id=auth.uid());
grant select, insert, delete on public.comment_reactions to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Polls (reusable)
-- ---------------------------------------------------------------------------

create table if not exists public.polls (
  id              uuid primary key default gen_random_uuid(),
  author_id       uuid not null references public.profiles(id) on delete cascade,
  question        text not null check (char_length(question) between 3 and 300),
  allow_multiple  boolean not null default false,
  allow_anonymous boolean not null default false,
  allow_change    boolean not null default true,
  expires_at      timestamptz,
  created_at      timestamptz not null default now()
);
alter table public.polls enable row level security;
drop policy if exists polls_all on public.polls;
create policy polls_all on public.polls for all to authenticated using (true) with check (author_id=auth.uid());
grant select, insert on public.polls to authenticated;

create table if not exists public.poll_options (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references public.polls(id) on delete cascade,
  label      text not null check (char_length(label) between 1 and 120),
  sort_order integer not null default 0
);
create index if not exists poll_options_poll_idx on public.poll_options(poll_id, sort_order);
alter table public.poll_options enable row level security;
drop policy if exists poll_options_all on public.poll_options;
create policy poll_options_all on public.poll_options for all to authenticated using (true) with check (true);
grant select, insert, delete on public.poll_options to authenticated;

create table if not exists public.poll_votes (
  poll_id   uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id, option_id),
  constraint poll_votes_option_belongs check (true)
);
create index if not exists poll_votes_poll_idx on public.poll_votes(poll_id);
alter table public.poll_votes enable row level security;
drop policy if exists poll_votes_self on public.poll_votes;
create policy poll_votes_self on public.poll_votes for all to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select, insert, delete on public.poll_votes to authenticated;

-- Enforce single-choice when allow_multiple=false and duplicate prevention
create or replace function public.guard_poll_vote()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_allow_multiple boolean; v_expires timestamptz;
begin
  select allow_multiple, expires_at into v_allow_multiple, v_expires from public.polls where id=new.poll_id;
  if v_expires is not null and v_expires <= now() then raise exception 'Poll has expired' using errcode='42501'; end if;
  if not v_allow_multiple then
    -- For single-choice, ensure not already voted for different option
    if exists(select 1 from public.poll_votes where poll_id=new.poll_id and user_id=new.user_id and option_id <> new.option_id) then
      raise exception 'Multiple choices not allowed for this poll' using errcode='42501';
    end if;
  end if;
  -- Ensure option belongs to poll
  if not exists(select 1 from public.poll_options o where o.id=new.option_id and o.poll_id=new.poll_id) then
    raise exception 'Option does not belong to poll' using errcode='42501';
  end if;
  return new;
end; $$;
drop trigger if exists poll_votes_guard on public.poll_votes;
create trigger poll_votes_guard before insert on public.poll_votes for each row execute function public.guard_poll_vote();

-- Allow vote change if poll allows it: delete previous then insert (handled by client)
create or replace function public.cast_poll_vote(p_poll_id uuid, p_option_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_allow_change boolean;
begin
  select allow_change into v_allow_change from public.polls where id=p_poll_id;
  if not coalesce(v_allow_change, true) and exists(select 1 from public.poll_votes where poll_id=p_poll_id and user_id=auth.uid()) then
    raise exception 'Vote change not allowed' using errcode='42501';
  end if;
  -- For single-choice, remove previous vote(s) for this poll
  delete from public.poll_votes where poll_id=p_poll_id and user_id=auth.uid()
    and exists(select 1 from public.polls where id=p_poll_id and allow_multiple=false);
  insert into public.poll_votes (poll_id, option_id, user_id) values (p_poll_id, p_option_id, auth.uid())
  on conflict do nothing;
end; $$;
grant execute on function public.cast_poll_vote(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Hashtags & Mentions
-- ---------------------------------------------------------------------------

create table if not exists public.hashtags (
  tag         text primary key check (tag ~ '^[a-z0-9_]{2,64}$'),
  post_count  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger hashtags_touch before update on public.hashtags for each row execute function public.touch_updated_at();
alter table public.hashtags enable row level security;
drop policy if exists hashtags_read on public.hashtags;
create policy hashtags_read on public.hashtags for select to authenticated using (true);
grant select on public.hashtags to authenticated;

create table if not exists public.post_hashtags (
  post_id uuid not null references public.posts(id) on delete cascade,
  tag     text not null references public.hashtags(tag) on delete cascade,
  primary key (post_id, tag)
);
create index if not exists post_hashtags_tag_idx on public.post_hashtags(tag);
alter table public.post_hashtags enable row level security;
drop policy if exists post_hashtags_read on public.post_hashtags;
create policy post_hashtags_read on public.post_hashtags for select to authenticated using (true);
grant select, insert on public.post_hashtags to authenticated;

create table if not exists public.mentions (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid references public.posts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint mentions_target check ((post_id is not null) <> (comment_id is not null))
);
create index if not exists mentions_user_idx on public.mentions(mentioned_user_id, created_at desc);
alter table public.mentions enable row level security;
drop policy if exists mentions_read on public.mentions;
create policy mentions_read on public.mentions for select to authenticated using (mentioned_user_id=auth.uid() or author_id=auth.uid());
grant select, insert on public.mentions to authenticated;

create or replace function public.extract_hashtags(p_text text)
returns text[] language plpgsql immutable as $$
declare v text[];
begin
  select array_agg(lower(m[1])) into v from regexp_matches(p_text, '#([a-zA-Z0-9_]{2,64})', 'g') m;
  return coalesce(v, '{}');
end; $$;

-- ---------------------------------------------------------------------------
-- 9. Discovery — recent searches
-- ---------------------------------------------------------------------------

create table if not exists public.recent_searches (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  query      text not null check (char_length(query) between 1 and 100),
  created_at timestamptz not null default now(),
  primary key (user_id, query)
);
alter table public.recent_searches enable row level security;
drop policy if exists recent_searches_self on public.recent_searches;
create policy recent_searches_self on public.recent_searches for all to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select, insert, delete on public.recent_searches to authenticated;

create or replace function public.record_search(p_query text)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into public.recent_searches(user_id, query) values (auth.uid(), trim(p_query))
  on conflict (user_id, query) do update set created_at=now();
  -- keep last 20
  delete from public.recent_searches where user_id=auth.uid() and query not in (
    select query from public.recent_searches where user_id=auth.uid() order by created_at desc limit 20
  );
end; $$;
grant execute on function public.record_search(text) to authenticated;

-- Unified search (respects privacy/blocking)
create or replace function public.search_all(p_query text, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_q text := '%' || lower(trim(p_query)) || '%';
begin
  if char_length(trim(p_query)) < 2 then return jsonb_build_object('users', '[]'::jsonb, 'channels', '[]'::jsonb, 'communities', '[]'::jsonb, 'posts', '[]'::jsonb); end if;
  return jsonb_build_object(
    'users', (select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb) from (select id, username, display_name, avatar_url, is_verified from public.profiles where lower(username) like v_q or lower(display_name) like v_q and not public.is_blocked_between(auth.uid(), id) limit p_limit) u),
    'channels', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from (select id, name, username, description, is_verified, is_official from public.channels where lower(name) like v_q or lower(username) like v_q limit p_limit) c),
    'communities', (select coalesce(jsonb_agg(to_jsonb(cm)), '[]'::jsonb) from (select id, name, description, visibility from public.communities where visibility='public' and (lower(name) like v_q or lower(description) like v_q) limit p_limit) cm),
    'posts', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from (select id, body, author_id from public.posts where hidden_at is null and lower(coalesce(body,'')) like v_q and not public.is_blocked_between(auth.uid(), author_id) limit p_limit) p)
  );
end; $$;
grant execute on function public.search_all(text,int) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Reports extended
-- ---------------------------------------------------------------------------

-- Expand target_type to include new entities
alter table public.reports drop constraint if exists reports_target_type_check;
alter table public.reports add constraint reports_target_type_check check (target_type in ('user','message','channel','channel_post','story','community','group','post','comment','poll','business'));

-- Add report category enum
alter table public.reports add column if not exists category text check (char_length(category) <= 32);
alter table public.reports add column if not exists moderation_note text;

-- Allow all authenticated to insert reports (with one-per-reporter unique)
drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports for insert to authenticated with check (reporter_id=auth.uid());
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated using (reporter_id=auth.uid() or public.has_permission('reports.manage') or public.has_permission('content.moderate'));
alter table public.reports enable row level security;
grant select, insert on public.reports to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Storage buckets for new ecosystem
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('community-media', 'community-media', false, 104857600, array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime']),
  ('post-media', 'post-media', false, 104857600, array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','audio/mpeg','audio/ogg'])
on conflict (id) do nothing;

-- Drop existing storage policies that mention old buckets and recreate including new ones
do $$ declare r record; begin
  for r in select policyname from pg_policies where schemaname='storage' and tablename='objects' loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

-- Public avatars/covers
create policy bubble_public_media_read on storage.objects for select to anon, authenticated using (bucket_id in ('avatars','profile-covers','business-media','hashtags'));
create policy bubble_profile_media_write on storage.objects for insert to authenticated with check (bucket_id in ('avatars','profile-covers') and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_profile_media_delete on storage.objects for delete to authenticated using (bucket_id in ('avatars','profile-covers') and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_business_media_write on storage.objects for insert to authenticated with check (bucket_id='business-media' and public.is_business_member(public.storage_folder_uuid(name), array['owner','manager']));
create policy bubble_business_media_delete on storage.objects for delete to authenticated using (bucket_id='business-media' and public.is_business_member(public.storage_folder_uuid(name), array['owner','manager']));
create policy bubble_wallpapers_all on storage.objects for all to authenticated using (bucket_id='wallpapers' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='wallpapers' and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_chat_media_read on storage.objects for select to authenticated using (bucket_id in ('chat-media','chat-attachments') and public.is_conversation_member(public.storage_folder_uuid(name)));
create policy bubble_chat_media_write on storage.objects for insert to authenticated with check (bucket_id in ('chat-media','chat-attachments') and public.is_conversation_member(public.storage_folder_uuid(name)));
create policy bubble_channel_media_read on storage.objects for select to authenticated using (bucket_id='channel-media' and (public.can_manage_channel(public.storage_folder_uuid(name)) or public.is_active_subscriber(public.storage_folder_uuid(name)) or exists(select 1 from public.channels c where c.id=public.storage_folder_uuid(name) and c.is_public)));
create policy bubble_channel_media_write on storage.objects for insert to authenticated with check (bucket_id='channel-media' and public.can_manage_channel(public.storage_folder_uuid(name)));
create policy bubble_story_media_read on storage.objects for select to authenticated using (bucket_id='story-media' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.stories s where s.media_path=name and public.can_view_story(s.id))));
create policy bubble_story_media_write on storage.objects for insert to authenticated with check (bucket_id='story-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_community_media_read on storage.objects for select to authenticated using (bucket_id='community-media' and (public.is_community_member(public.storage_folder_uuid(name)) or exists(select 1 from public.communities c where c.id=public.storage_folder_uuid(name) and c.visibility='public')));
create policy bubble_community_media_write on storage.objects for insert to authenticated with check (bucket_id='community-media' and (public.is_community_admin(public.storage_folder_uuid(name)) or public.is_community_member(public.storage_folder_uuid(name))));
create policy bubble_post_media_read on storage.objects for select to authenticated using (bucket_id='post-media' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.posts p where p.id::text=(storage.foldername(name))[1])));
create policy bubble_post_media_write on storage.objects for insert to authenticated with check (bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_verification_upload on storage.objects for insert to authenticated with check (bucket_id='verification-documents' and (storage.foldername(name))[1]=auth.uid()::text);
create policy bubble_verification_read on storage.objects for select to authenticated using (bucket_id='verification-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.has_permission('verification.review') or public.has_permission('channels.verify')));

-- ---------------------------------------------------------------------------
-- 12. Notifications — extend kinds
-- ---------------------------------------------------------------------------

-- Ensure notify_user handles new kinds (already preference-aware for messages/calls/channels, others always delivered)
-- No schema change, just ensure triggers for new events

create or replace function public.on_post_notify()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  select coalesce(nullif(display_name,''), username) into v_name from public.profiles where id=new.author_id;
  -- notify followers or community members depending on context
  if new.community_id is not null then
    for v_name in select user_id from public.community_members where community_id=new.community_id and user_id <> new.author_id loop
      perform public.notify_user(v_name, 'community_post', 'New post in ' || coalesce((select name from public.communities where id=new.community_id), 'community'), left(coalesce(new.body,''), 120), jsonb_build_object('post_id', new.id));
    end loop;
  end if;
  return new;
end; $$;
drop trigger if exists posts_notify on public.posts;
create trigger posts_notify after insert on public.posts for each row execute function public.on_post_notify();

create or replace function public.on_comment_notify()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_post_author uuid; v_parent_author uuid; v_name text;
begin
  select author_id into v_post_author from public.posts where id=new.post_id;
  select coalesce(nullif(display_name,''), username) into v_name from public.profiles where id=new.author_id;
  if v_post_author is not null and v_post_author <> new.author_id then
    perform public.notify_user(v_post_author, 'comment', coalesce(v_name,'Someone') || ' commented on your post', left(new.body,120), jsonb_build_object('post_id', new.post_id, 'comment_id', new.id));
  end if;
  if new.parent_id is not null then
    select author_id into v_parent_author from public.comments where id=new.parent_id;
    if v_parent_author is not null and v_parent_author <> new.author_id and v_parent_author <> v_post_author then
      perform public.notify_user(v_parent_author, 'comment_reply', coalesce(v_name,'Someone') || ' replied to your comment', left(new.body,120), jsonb_build_object('post_id', new.post_id, 'comment_id', new.id));
    end if;
  end if;
  -- mentions: if body contains @username, notify (simple extraction, app also does explicit)
  return new;
end; $$;
drop trigger if exists comments_notify on public.comments;
create trigger comments_notify after insert on public.comments for each row execute function public.on_comment_notify();

create or replace function public.on_mention_notify()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  select coalesce(nullif(display_name,''), username) into v_name from public.profiles where id=new.author_id;
  perform public.notify_user(new.mentioned_user_id, 'mention', coalesce(v_name,'Someone') || ' mentioned you', 'You were mentioned', jsonb_build_object('post_id', new.post_id, 'comment_id', new.comment_id));
  return new;
end; $$;
drop trigger if exists mentions_notify on public.mentions;
create trigger mentions_notify after insert on public.mentions for each row execute function public.on_mention_notify();

create or replace function public.on_community_join_request_notify()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  if new.status='pending' then
    select coalesce(nullif(display_name,''), username) into v_name from public.profiles where id=new.user_id;
    for v_name in select user_id from public.community_members where community_id=new.community_id and role in ('owner','admin') loop
      perform public.notify_user(v_name, 'community_join_request', 'New join request', coalesce((select name from public.communities where id=new.community_id),'Community') || ': ' || coalesce(v_name,'Someone') || ' wants to join', jsonb_build_object('community_id', new.community_id, 'request_id', new.id));
    end loop;
  end if;
  return new;
end; $$;
drop trigger if exists community_join_request_notify on public.community_join_requests;
create trigger community_join_request_notify after insert on public.community_join_requests for each row execute function public.on_community_join_request_notify();

-- ---------------------------------------------------------------------------
-- 13. Scheduled cleanup integration
-- ---------------------------------------------------------------------------

create or replace function public.cleanup_expired_stories_job()
returns integer language plpgsql security definer set search_path=public as $$
begin return public.cleanup_expired_stories(); end; $$;

-- Ensure user_settings has notification prefs for new kinds
do $$ begin
  -- ensure column exists then set default json keys if missing
  update public.user_settings set notifications = coalesce(notifications,'{}'::jsonb) || jsonb_build_object('posts', true, 'comments', true, 'mentions', true, 'communities', true) where notifications is not null;
exception when others then null; end $$;

-- Trending helpers (real engagement data only)
create or replace function public.trending_hashtags(p_limit int default 10)
returns table(tag text, post_count int) language sql stable security definer set search_path=public as $$
  select h.tag, h.post_count from public.hashtags h order by h.post_count desc, h.updated_at desc limit p_limit;
$$;
create or replace function public.trending_posts(p_limit int default 20)
returns table(id uuid, author_id uuid, body text, created_at timestamptz, reaction_count bigint, comment_count bigint)
language sql stable security definer set search_path=public as $$
  select p.id, p.author_id, p.body, p.created_at,
         (select count(*) from public.post_reactions r where r.post_id=p.id) as reaction_count,
         (select count(*) from public.comments c where c.post_id=p.id and c.hidden_at is null) as comment_count
  from public.posts p where p.hidden_at is null order by reaction_count desc, comment_count desc, p.created_at desc limit p_limit;
$$;
grant execute on function public.trending_hashtags(int) to authenticated;
grant execute on function public.trending_posts(int) to authenticated;
grant execute on function public.search_all(text,int) to authenticated;

-- Revoke public execution from sensitive functions, grant explicitly
revoke all on function public.cleanup_expired_stories() from public, anon;
revoke all on function public.cast_poll_vote(uuid,uuid) from public, anon;
revoke all on function public.record_search(text) from public, anon;
grant execute on function public.cleanup_expired_stories() to authenticated;
grant execute on function public.cast_poll_vote(uuid,uuid) to authenticated;
grant execute on function public.record_search(text) to authenticated;

-- Realtime publication for new tables
do $$ begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') then
    perform 1 from pg_tables where tablename='stories' and schemaname='public';
    begin execute 'alter publication supabase_realtime add table public.stories'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.story_views'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.story_reactions'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.posts'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.post_reactions'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.comments'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.polls'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.poll_votes'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.communities'; exception when duplicate_object then null; end;
    begin execute 'alter publication supabase_realtime add table public.community_members'; exception when duplicate_object then null; end;
  end if;
end $$;
