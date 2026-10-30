-- 07 Social Ecosystem: validates 0013 migration
\pset tuples_only off
\timing off

create or replace function test_assert(p_name text, p_condition boolean) returns void language plpgsql as $$ begin if not p_condition then raise exception 'FAIL %', p_name; else raise notice 'PASS %', p_name; end if; end; $$;

-- Follows / close friends
select test_assert('follows exists', exists(select 1 from pg_tables where tablename='follows'));
select test_assert('close_friends exists', exists(select 1 from pg_tables where tablename='close_friends'));
select test_assert('is_follower fn exists', exists(select 1 from pg_proc where proname='is_follower'));
select test_assert('is_close_friend fn exists', exists(select 1 from pg_proc where proname='is_close_friend'));

-- Stories extended
select test_assert('stories has caption', exists(select 1 from information_schema.columns where table_name='stories' and column_name='caption'));
select test_assert('stories has background_color', exists(select 1 from information_schema.columns where table_name='stories' and column_name='background_color'));
select test_assert('stories has text_elements', exists(select 1 from information_schema.columns where table_name='stories' and column_name='text_elements'));
select test_assert('stories has link_url', exists(select 1 from information_schema.columns where table_name='stories' and column_name='link_url'));
select test_assert('story_audience exists', exists(select 1 from pg_tables where tablename='story_audience'));
select test_assert('story_hidden_from exists', exists(select 1 from pg_tables where tablename='story_hidden_from'));
select test_assert('story_mutes exists', exists(select 1 from pg_tables where tablename='story_mutes'));
select test_assert('can_view_story handles followers', (select pg_get_functiondef((select oid from pg_proc where proname='can_view_story')) ilike '%followers%'));
select test_assert('cleanup_expired_stories exists', exists(select 1 from pg_proc where proname='cleanup_expired_stories'));

-- Channels roles
select test_assert('channels has category', exists(select 1 from information_schema.columns where table_name='channels' and column_name='category'));
select test_assert('channel_members exists', exists(select 1 from pg_tables where tablename='channel_members'));
select test_assert('can_publish_channel exists', exists(select 1 from pg_proc where proname='can_publish_channel'));
select test_assert('channel_posts has poll_id', exists(select 1 from information_schema.columns where table_name='channel_posts' and column_name='poll_id'));

-- Communities extended
select test_assert('communities has username', exists(select 1 from information_schema.columns where table_name='communities' and column_name='username'));
select test_assert('community_join_requests exists', exists(select 1 from pg_tables where tablename='community_join_requests'));
select test_assert('community_groups exists', exists(select 1 from pg_tables where tablename='community_groups'));
select test_assert('community_members handles moderator', (select exists(select 1 from pg_constraint where conname='community_members_role_check' and pg_get_constraintdef(oid) ilike '%moderator%')));

-- Groups
select test_assert('group_settings exists', exists(select 1 from pg_tables where tablename='group_settings'));
select test_assert('group_invites exists', exists(select 1 from pg_tables where tablename='group_invites'));

-- Posts / feed
select test_assert('posts exists', exists(select 1 from pg_tables where tablename='posts'));
select test_assert('post_reactions exists', exists(select 1 from pg_tables where tablename='post_reactions'));
select test_assert('post_bookmarks exists', exists(select 1 from pg_tables where tablename='post_bookmarks'));
select test_assert('comments exists', exists(select 1 from pg_tables where tablename='comments'));
select test_assert('comment_reactions exists', exists(select 1 from pg_tables where tablename='comment_reactions'));

-- Polls
select test_assert('polls exists', exists(select 1 from pg_tables where tablename='polls'));
select test_assert('poll_options exists', exists(select 1 from pg_tables where tablename='poll_options'));
select test_assert('poll_votes exists', exists(select 1 from pg_tables where tablename='poll_votes'));
select test_assert('cast_poll_vote exists', exists(select 1 from pg_proc where proname='cast_poll_vote'));
select test_assert('poll_votes has guard trigger', exists(select 1 from pg_trigger where tgname='poll_votes_guard'));

-- Hashtags / mentions
select test_assert('hashtags exists', exists(select 1 from pg_tables where tablename='hashtags'));
select test_assert('post_hashtags exists', exists(select 1 from pg_tables where tablename='post_hashtags'));
select test_assert('mentions exists', exists(select 1 from pg_tables where tablename='mentions'));

-- Discovery
select test_assert('recent_searches exists', exists(select 1 from pg_tables where tablename='recent_searches'));
select test_assert('search_all exists', exists(select 1 from pg_proc where proname='search_all'));
select test_assert('trending_hashtags exists', exists(select 1 from pg_proc where proname='trending_hashtags'));

-- Reports extended
select test_assert('reports has category', exists(select 1 from information_schema.columns where table_name='reports' and column_name='category'));
select test_assert('reports target includes post', (select pg_get_constraintdef(oid) ilike '%post%' from pg_constraint where conname='reports_target_type_check'));

-- Storage buckets
select test_assert('community-media bucket', exists(select 1 from storage.buckets where id='community-media'));
select test_assert('post-media bucket', exists(select 1 from storage.buckets where id='post-media'));

-- RLS enabled on new tables
select test_assert('posts RLS', (select relrowsecurity from pg_class where relname='posts'));
select test_assert('stories RLS', (select relrowsecurity from pg_class where relname='stories'));
select test_assert('polls RLS', (select relrowsecurity from pg_class where relname='polls'));

-- Mandatory official still enforced (from 0003)
select test_assert('mandatory enforced fn exists', exists(select 1 from pg_proc where proname='mandatory_subscription_enforced'));
select test_assert('enroll_mandatory exists', exists(select 1 from pg_proc where proname='enroll_mandatory_subscriptions'));

drop function test_assert(text, boolean);
