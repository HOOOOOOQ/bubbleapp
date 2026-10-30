-- =============================================================================
-- Scenario suite. Identities:
--   owner  a1 | super admin a3 | admin a2 | moderator a4 | partner candidate c1
--   users  b1 (Alice) b2 (Bob) b3 (Carol)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Accounts & automatic mandatory follow
-- ---------------------------------------------------------------------------
select tst.as_trusted();
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000a1',   'owner@bubble.test',   '{"display_name":"Platform Owner"}'),
  ('00000000-0000-4000-8000-0000000000a2',   'admin@bubble.test',   '{"display_name":"Admin"}'),
  ('00000000-0000-4000-8000-0000000000a3',   'super@bubble.test',   '{"display_name":"Super"}'),
  ('00000000-0000-4000-8000-0000000000a4',     'mod@bubble.test',     '{"display_name":"Moderator"}'),
  ('00000000-0000-4000-8000-0000000000b1',   'alice@bubble.test',   '{"display_name":"Alice"}'),
  ('00000000-0000-4000-8000-0000000000b2',     'bob@bubble.test',     '{"display_name":"Bob"}'),
  ('00000000-0000-4000-8000-0000000000b3',   'carol@bubble.test',   '{"display_name":"Carol"}'),
  ('00000000-0000-4000-8000-0000000000c1', 'partner@bubble.test', '{"display_name":"Partner Candidate"}');

select tst.ok((select count(*) from public.channel_subscribers s join public.channels c on c.id = s.channel_id
               where c.is_official and s.user_id = '00000000-0000-4000-8000-0000000000b1' and s.is_active) = 1,
  'new account is subscribed exactly once to @BubbleApp');
select tst.ok((select count(*) from public.profiles where id in ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000c1')) = 4,
  'profile rows created for every auth account');
select tst.ok((select count(*) from public.account_modes where mode = 'personal') = 8,
  'every account gets a personal account mode');
select tst.ok((select count(*) from public.channels where is_official and username = 'bubbleapp' and is_verified and is_mandatory) = 1,
  'official BubbleApp channel is seeded once, verified and mandatory');
select tst.expect_ok($$select public.enroll_mandatory_subscriptions('00000000-0000-4000-8000-0000000000b1')$$, 'mandatory enrollment can be re-run');
select tst.ok((select count(*) from public.channel_subscribers where user_id = '00000000-0000-4000-8000-0000000000b1') = 1,
  'repeat enrollment does not create duplicate subscriptions');
select tst.expect_error($$insert into public.channel_subscribers (channel_id, user_id) select id, '00000000-0000-4000-8000-0000000000b1' from public.channels where is_official$$,
  'duplicate key|unique', 'database rejects duplicate subscription rows');
select tst.expect_error($$insert into public.channel_subscribers (channel_id, user_id) select id, '00000000-0000-4000-8000-0000000000b2' from public.channels where is_official$$,
  'duplicate key|unique', 'duplicate subscription for another user is also rejected (unique constraint)');

-- Owner bootstrap (trusted, one time)
select public.bootstrap_owner('owner@bubble.test');
select tst.expect_error($$select public.bootstrap_owner('admin@bubble.test')$$, 'Owner already exists', 'second Owner bootstrap is refused');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error($$insert into public.user_roles (user_id, role_key) values ('00000000-0000-4000-8000-0000000000b2', 'owner')$$, 'permission denied', 'a user cannot insert the Owner role');
select tst.expect_error($$update public.user_roles set role_key = 'owner'$$, 'permission denied', 'a user cannot update roles into Owner');
select tst.as_trusted();
select tst.expect_error($$insert into public.user_roles (user_id, role_key) values ('00000000-0000-4000-8000-0000000000b2', 'owner')$$, 'duplicate key|Owner already exists', 'database allows exactly one active Owner');

-- ---------------------------------------------------------------------------
-- 2. Ordinary users: privileged columns and mandatory subscription
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error($$select public.unsubscribe_from_channel((select id from public.channels where is_official))$$,
  'official BubbleApp channel is required', 'unsubscribe from @BubbleApp is refused with explanation');
select tst.expect_error($$update public.channel_subscribers set is_active = false where channel_id = (select id from public.channels where is_official)$$,
  'official BubbleApp channel is required|permission denied', 'direct update cannot deactivate the mandatory subscription');
select tst.expect_error($$delete from public.channel_subscribers where channel_id = (select id from public.channels where is_official)$$,
  'official BubbleApp channel is required|permission denied', 'direct delete cannot remove the mandatory subscription');
select tst.expect_error($$insert into public.channel_subscribers (channel_id, user_id) select id, '00000000-0000-4000-8000-0000000000b2' from public.channels where is_official$$,
  'permission denied|row-level', 'clients cannot write subscriptions directly');
select tst.expect_error($$update public.profiles set is_verified = true, verified_at = now() where id = '00000000-0000-4000-8000-0000000000b1'$$,
  'permission denied', 'user cannot grant themselves the blue checkmark');
select tst.expect_error($$update public.profiles set account_status = 'active' where id = '00000000-0000-4000-8000-0000000000b1'$$,
  'permission denied', 'user cannot write account_status');
select tst.expect_error($$select email from public.profiles$$, 'permission denied', 'email is not readable through the API');
select tst.expect_error($$insert into public.user_roles (user_id, role_key) values ('00000000-0000-4000-8000-0000000000b1', 'super_admin')$$,
  'permission denied', 'user cannot assign themselves a role');
select tst.expect_error($$select public.grant_role('00000000-0000-4000-8000-0000000000b1', 'partner', null)$$, 'permission denied', 'role grant helper is not callable by users');
select tst.expect_error($$select public.write_audit('fake', 'x', 'y', '{}')$$, 'permission denied', 'users cannot forge audit entries');
select tst.expect_error($$select public.notify_user('00000000-0000-4000-8000-0000000000b2', 'x', 'fake', 'fake', '{}')$$, 'permission denied', 'users cannot send notifications to others');
select tst.expect_error($$select public.apply_verification_badge(null::public.verification_applications, true)$$, 'permission denied', 'users cannot call the badge writer');
select tst.expect_error($$select public.enroll_mandatory_subscriptions('00000000-0000-4000-8000-0000000000b2')$$, 'permission denied', 'users cannot run enrollment for others');
select tst.expect_error($$update public.profiles set username = 'Bad Name!' where id = '00000000-0000-4000-8000-0000000000b1'$$, 'permission denied|violates check', 'invalid username is rejected');
update public.profiles set display_name = 'Alice Liddell' where id = '00000000-0000-4000-8000-0000000000b1';
select tst.ok((select display_name from public.profiles where id = '00000000-0000-4000-8000-0000000000b1') = 'Alice Liddell', 'user can update own display name');
update public.profiles set display_name = 'Hacked' where id = '00000000-0000-4000-8000-0000000000b2';
select tst.as_trusted();
select tst.ok((select display_name from public.profiles where id = '00000000-0000-4000-8000-0000000000b2') = 'Bob', 'updating another profile affects no rows (RLS)');

-- ---------------------------------------------------------------------------
-- 3. Administrator hierarchy
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select tst.ok(public.is_owner() and public.has_permission('owner.manage'), 'owner has owner.manage');
select tst.expect_ok($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000a3'::uuid, 'super_admin',
    array['admins.create','admins.manage','users.read','users.manage','users.verify','verification.approve',
          'channels.manage','channels.verify','partners.approve','partners.manage','reports.manage',
          'content.moderate','settings.manage','analytics.read','announcements.manage','audit.read'])$$,
  'owner creates a super admin');
select tst.expect_ok($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000a2'::uuid, 'admin', array['users.read','reports.manage','content.moderate','analytics.read'])$$,
  'owner creates an admin');
select tst.expect_ok($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000a4'::uuid, 'moderator', array[]::text[])$$, 'owner creates a moderator');
select public.admin_set_permission('00000000-0000-4000-8000-0000000000a2'::uuid, 'users.manage', 'grant');
select tst.expect_error($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000b3'::uuid, 'owner', '{}')$$, 'Invalid administrator role', 'Owner role can never be assigned through the API');
select tst.expect_error($$select public.admin_set_account_status('00000000-0000-4000-8000-0000000000a1'::uuid, 'suspended', 'x')$$, 'cannot change your own', 'owner cannot suspend self through the API');

select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.expect_error($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000b3'::uuid, 'super_admin', '{}')$$, 'at or above|Invalid|Permission denied', 'admin cannot create a super admin');
select tst.expect_error($$select public.admin_set_account_status('00000000-0000-4000-8000-0000000000a3'::uuid, 'suspended', 'x')$$, 'equal or higher|Protected', 'admin cannot suspend a super admin');
select tst.expect_error($$select public.admin_set_account_status('00000000-0000-4000-8000-0000000000a1'::uuid, 'suspended', 'x')$$, 'equal or higher|Protected', 'admin cannot suspend the Owner');
select tst.expect_error($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000b3'::uuid, 'moderator', array['settings.manage'])$$, 'do not hold|Permission denied|cannot grant', 'admin cannot grant a permission they do not hold');
select tst.expect_error($$select public.set_platform_setting('maintenance_mode', 'true'::jsonb)$$, 'Only the Owner', 'admin cannot change protected settings');
select tst.expect_error($$select public.set_platform_setting('max_file_size_mb', '200'::jsonb)$$, 'Permission denied: settings.manage', 'admin without settings.manage cannot change regular settings');
select tst.expect_error($$select public.admin_set_permission('00000000-0000-4000-8000-0000000000a4'::uuid, 'users.read', 'grant')$$, 'Permission denied', 'admin cannot manage admins without admins.manage');
select tst.ok(public.has_permission('users.read') and public.has_permission('users.manage') and not public.has_permission('admins.manage'), 'admin holds users.read and an explicit users.manage grant, but not admins.manage');
select tst.expect_ok($$select public.admin_set_account_status('00000000-0000-4000-8000-0000000000b3'::uuid, 'suspended', 'policy test')$$, 'administrator with users.manage can suspend an ordinary account');
select tst.expect_ok($$select public.admin_set_account_status('00000000-0000-4000-8000-0000000000b3'::uuid, 'active', 'restored')$$, 'administrator can restore the account');

select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select tst.ok(public.has_permission('admins.manage') and not public.has_permission('owner.manage'), 'super admin manages admins but is not Owner');
select tst.expect_error($$select public.admin_create_admin('00000000-0000-4000-8000-0000000000b3'::uuid, 'super_admin', '{}')$$, 'at or above', 'super admin cannot create another super admin');
select tst.expect_error($$select public.admin_set_permission('00000000-0000-4000-8000-0000000000a1'::uuid, 'users.read', 'deny')$$, 'equal or higher|Only the Owner|not an administrator', 'super admin cannot modify the Owner');
select tst.expect_error($$select public.set_platform_setting('registration_enabled', 'false'::jsonb)$$, 'Only the Owner', 'super admin cannot change protected registration setting');

select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.admin_set_permission('00000000-0000-4000-8000-0000000000a2'::uuid, 'content.moderate', 'deny');
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.ok(not public.has_permission('content.moderate'), 'per-admin deny overrides the role default');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.admin_set_permission('00000000-0000-4000-8000-0000000000a2'::uuid, 'content.moderate', 'inherit');
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.ok(public.has_permission('content.moderate'), 'inherit restores the role default');

select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.admin_set_admin_status('00000000-0000-4000-8000-0000000000a4'::uuid, 'suspended', 'test suspension');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.ok(not public.has_permission('content.moderate'), 'suspended administrator loses staff permissions');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.admin_set_admin_status('00000000-0000-4000-8000-0000000000a4'::uuid, 'active', 'restored');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.ok(public.has_permission('content.moderate'), 'restored administrator regains permissions');

select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.ok((select count(*) from public.owner_audit_logs) = 0, 'administrator cannot read the owner audit log');
select tst.expect_error($$update public.admin_audit_logs set action = 'tampered'$$, 'immutable|permission denied', 'audit rows cannot be updated');
select tst.as_trusted();
select tst.expect_error($$delete from public.admin_audit_logs$$, 'immutable', 'audit rows cannot be deleted even by trusted SQL');
select tst.ok((select count(*) from public.admin_audit_logs) > 0, 'administrative actions are recorded in the audit log');

-- ---------------------------------------------------------------------------
-- 4. Channels: creation, posts, reactions, privacy, invites, pins, deletion
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.channels (owner_id, name, username, description, is_public, comments_enabled)
values ('00000000-0000-4000-8000-0000000000b1', 'Alice News', 'alice_news', 'Daily notes', true, true);
select tst.expect_error($$insert into public.channels (owner_id, name, username, is_verified, verified_at) values ('00000000-0000-4000-8000-0000000000b1','Fake','fake_badge',true,now())$$,
  'permission denied|row-level', 'user cannot create a verified channel');
select tst.expect_error($$insert into public.channels (owner_id, name, username, is_official) values ('00000000-0000-4000-8000-0000000000b1','Fake Official','fake_official',true)$$,
  'permission denied|row-level', 'user cannot create an official channel');
select tst.expect_error($$update public.channels set is_verified = true, verified_at = now() where username = 'alice_news'$$,
  'permission denied', 'channel owner cannot self-verify');
select tst.ok((select subscriber_count from public.channels where username = 'alice_news') = 1, 'owner auto-follows own channel (count 1)');

insert into public.channel_posts (channel_id, author_id, kind, body)
select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'Hello subscribers' from public.channels where username = 'alice_news';
select tst.expect_error($$insert into public.channel_posts (channel_id, author_id, kind, body) select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'x' from public.channels where is_official$$,
  'row-level|permission denied', 'owner cannot post into the official channel');
select tst.expect_error($$insert into public.channel_posts (channel_id, author_id, kind) select id, '00000000-0000-4000-8000-0000000000b1', 'image' from public.channels where username = 'alice_news'$$,
  'constraint|violates|null', 'media post without media is rejected');

select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error($$insert into public.channel_posts (channel_id, author_id, kind, body) select id, '00000000-0000-4000-8000-0000000000b2', 'text', 'spam' from public.channels where username = 'alice_news'$$,
  'row-level|permission denied', 'non-manager cannot post');
select public.subscribe_to_channel((select id from public.channels where username = 'alice_news'));
select public.subscribe_to_channel((select id from public.channels where username = 'alice_news'));
select tst.ok((select count(*) from public.channel_subscribers s join public.channels c on c.id = s.channel_id
               where c.username = 'alice_news' and s.user_id = '00000000-0000-4000-8000-0000000000b2') = 1, 'subscribing twice creates one subscription row');
select tst.ok((select subscriber_count from public.channels where username = 'alice_news') = 2, 'subscriber count updates (2)');
select tst.ok((select count(*) from public.channel_posts where body = 'Hello subscribers') = 1, 'public channel posts are readable');

select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error($$insert into public.channel_post_reactions (post_id, user_id, emoji) select p.id, '00000000-0000-4000-8000-0000000000b3', '👍' from public.channel_posts p where body = 'Hello subscribers'$$,
  'row-level|permission denied', 'reaction requires an active subscription');
select public.subscribe_to_channel((select id from public.channels where username = 'alice_news'));
insert into public.channel_post_reactions (post_id, user_id, emoji) select p.id, '00000000-0000-4000-8000-0000000000b3', '👍' from public.channel_posts p where body = 'Hello subscribers';
select public.record_channel_post_view((select id from public.channel_posts where body = 'Hello subscribers'));
select public.record_channel_post_view((select id from public.channel_posts where body = 'Hello subscribers'));
select tst.as_trusted();
select tst.ok((select views_count from public.channel_posts where body = 'Hello subscribers') = 1, 'view counts increment once per viewer');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.channels (owner_id, name, username, is_public) values ('00000000-0000-4000-8000-0000000000b1', 'Secret Club', 'secret_club', false);
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(tst.count_q($$select id from public.channels where username = 'secret_club'$$) = 0, 'private channel is invisible to non-members');
select tst.expect_error($$select public.subscribe_to_channel((select id from public.channels where username = 'secret_club'))$$, 'private|not found', 'private channel cannot be joined directly');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.channel_invitations (channel_id, created_by, max_uses)
select id, '00000000-0000-4000-8000-0000000000b1', 1 from public.channels where username = 'secret_club' returning code \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select public.join_channel_by_invite(:'code');
select tst.expect_error(format('select public.join_channel_by_invite(%L)', :'code'), 'usage limit', 'invite respects max uses');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error($$update public.channel_posts set is_pinned = true where body = 'Hello subscribers'$$, 'permission denied|set_channel_post_pinned', 'pin must use set_channel_post_pinned');
insert into public.channel_posts (channel_id, author_id, kind, body) select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'Second post' from public.channels where username = 'alice_news';
select public.set_channel_post_pinned((select id from public.channel_posts where body = 'Hello subscribers'), true);
select public.set_channel_post_pinned((select id from public.channel_posts where body = 'Second post'), true);
select tst.as_trusted();
select tst.ok((select count(*) from public.channel_posts where is_pinned) = 1
              and (select is_pinned from public.channel_posts where body = 'Second post'), 'pinning a second post unpins the first');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.channel_posts (channel_id, author_id, kind, body, publish_at)
select id, '00000000-0000-4000-8000-0000000000b1', 'text', 'Future post', now() + interval '1 day' from public.channels where username = 'alice_news';
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(tst.count_q($$select id from public.channel_posts where body = 'Future post'$$) = 0, 'scheduled post hidden until publish time');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q($$select id from public.channel_posts where body = 'Future post'$$) = 1, 'owner sees scheduled post');
select tst.ok((public.channel_stats((select id from public.channels where username = 'alice_news')) ->> 'scheduled')::int = 1,
  'channel analytics count scheduled posts');

select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error($$select public.delete_channel((select id from public.channels where username = 'alice_news'))$$, 'Only the channel owner', 'non-owner cannot delete a channel');
select tst.expect_error($$select public.delete_channel((select id from public.channels where is_official))$$, 'cannot be deleted', 'official channel cannot be deleted');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.delete_channel((select id from public.channels where username = 'secret_club'));
select tst.ok(tst.count_q($$select id from public.channels where username = 'secret_club'$$) = 0, 'owner can delete own channel');

-- ---------------------------------------------------------------------------
-- 5. Owner toggles mandatory subscription; users re-sync on session
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.expect_error($$select public.set_platform_setting('mandatory_channel_subscription', 'false'::jsonb)$$, 'Only the Owner', 'administrator cannot disable mandatory subscription');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.set_platform_setting('mandatory_channel_subscription', 'false'::jsonb);
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select public.unsubscribe_from_channel((select id from public.channels where is_official));
select tst.as_trusted();
select tst.ok(not exists (select 1 from public.channel_subscribers s join public.channels c on c.id = s.channel_id
                          where c.is_official and s.user_id = '00000000-0000-4000-8000-0000000000b2' and s.is_active),
  'with owner setting disabled, the user may leave @BubbleApp');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.set_platform_setting('mandatory_channel_subscription', 'true'::jsonb);
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select public.ensure_my_mandatory_subscriptions();
select tst.expect_error($$select public.unsubscribe_from_channel((select id from public.channels where is_official))$$, 'official BubbleApp channel is required', 'session sync restored the mandatory subscription and guard is active');

select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.set_platform_setting('registration_enabled', 'false'::jsonb);
select tst.as_trusted();
select tst.expect_error($$insert into auth.users (email) values ('late@bubble.test')$$, 'registrations are temporarily disabled', 'owner can close registration');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select public.set_platform_setting('registration_enabled', 'true'::jsonb);
select tst.as_trusted();

-- ---------------------------------------------------------------------------
-- 6. Verification: user, channel; documents; decisions; badge lifecycle
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error($$select public.submit_verification_application('channel','Carol','carol','Art','x','A reason long enough','[]', null, (select id from public.channels where is_official))$$,
  'Only the channel owner', 'cannot apply to verify a channel you do not own');
select public.submit_verification_application('user', 'Carol Example', 'carol', 'Artist', 'Digital artist', 'Public figure with press coverage', '[{"url":"https://example.com"}]');
select tst.expect_error($$select public.submit_verification_application('user','Carol Example','carol','Artist','x','Another reason here okay','[]')$$, 'already have an open', 'duplicate open application refused');
select tst.as_trusted();
select id as app_user from public.verification_applications where applicant_id = '00000000-0000-4000-8000-0000000000b3' and application_type = 'user' \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error(format($$select public.add_verification_document(%L::uuid, 'someone-else/%s/id.pdf', 'identity', 'application/pdf', 1000)$$, :'app_user', :'app_user'),
  'Invalid document path', 'document must live in the applicant folder');
select public.add_verification_document(:'app_user'::uuid, '00000000-0000-4000-8000-0000000000b3' || '/' || :'app_user' || '/id.pdf', 'identity', 'application/pdf', 1000);
select tst.expect_error(format($$select public.review_verification_application(%L::uuid, 'approve', null)$$, :'app_user'), 'cannot review your own', 'applicant cannot review their own application');
select tst.expect_error($$select public.review_verification_application((select id from public.verification_applications limit 1), 'approve', null)$$, 'not found|cannot review|Permission', 'applicant cannot act on other applications');

select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error(format($$select public.review_verification_application(%L::uuid, 'start_review', null)$$, :'app_user'), 'Permission denied', 'moderator cannot review user verification');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.admin_set_permission('00000000-0000-4000-8000-0000000000a2'::uuid, 'users.verify', 'grant') ;
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.expect_ok(format($$select public.review_verification_application(%L::uuid, 'start_review', null)$$, :'app_user'), 'reviewer with users.verify starts review');
select tst.expect_error(format($$select public.review_verification_application(%L::uuid, 'approve', null)$$, :'app_user'), 'Only authorized decision makers', 'reviewer without verification.approve cannot approve');
select tst.expect_ok(format($$select public.review_verification_application(%L::uuid, 'recommend_approve', null)$$, :'app_user'), 'reviewer can recommend approval');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_verification_application(:'app_user'::uuid, 'approve', null);
select tst.as_trusted();
select tst.ok((select is_verified from public.profiles where id = '00000000-0000-4000-8000-0000000000b3') = true, 'approval turns on the blue checkmark');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_verification_application(:'app_user'::uuid, 'suspend', 'Temporary review of claims');
select tst.as_trusted();
select tst.ok((select is_verified from public.profiles where id = '00000000-0000-4000-8000-0000000000b3') = false, 'suspension removes the badge');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_verification_application(:'app_user'::uuid, 'restore', null);
select tst.as_trusted();
select tst.ok((select is_verified from public.profiles where id = '00000000-0000-4000-8000-0000000000b3') = true, 'restore brings the badge back');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_verification_application(:'app_user'::uuid, 'revoke', 'Impersonation complaint confirmed');
select tst.as_trusted();
select tst.ok((select is_verified from public.profiles where id = '00000000-0000-4000-8000-0000000000b3') = false, 'revocation removes the badge');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select tst.expect_error(format($$select public.review_verification_application(%L::uuid, 'restore', null)$$, :'app_user'), 'Only suspended', 'revoked verification cannot be restored directly');

-- Channel verification (owner applies, reviewer approves)
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.submit_verification_application('channel', 'Alice News Desk', 'alice_news', 'News', 'Community news channel', 'Official news coverage for our city', '[]', null,
  (select id from public.channels where username = 'alice_news'));
select tst.as_trusted();
select id as app_ch from public.verification_applications where application_type = 'channel' \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.add_verification_document(:'app_ch'::uuid, '00000000-0000-4000-8000-0000000000b1' || '/' || :'app_ch' || '/proof.pdf', 'website_proof', 'application/pdf', 2048);
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_verification_application(:'app_ch'::uuid, 'start_review', null);
select public.review_verification_application(:'app_ch'::uuid, 'approve', null);
select tst.as_trusted();
select tst.ok((select is_verified from public.channels where username = 'alice_news') = true, 'approved channel displays verified badge');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.ok(tst.count_q($$select id from public.verification_applications where id = '$$ || :'app_ch' || $$'$$) = 0, 'moderator cannot even see channel verification application');

-- ---------------------------------------------------------------------------
-- 7. Partners
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000c1');
select public.submit_partner_application('Pat Partner', 'pat_partner', 'pat@partner.test', 'Partner Labs', 'https://partner.test', '{"x":"@pat"}',
  'Education', 'We propose co-hosted learning sessions for students across the city.', 'Edtech organization');
select tst.as_trusted();
select id as app_partner from public.partner_applications where applicant_id = '00000000-0000-4000-8000-0000000000c1' \gset
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.expect_error(format($$select public.review_partner_application(%L::uuid, 'approve', 'Education', null)$$, :'app_partner'), 'Permission denied: partners.approve', 'admin without partners.approve cannot approve partners');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_partner_application(:'app_partner'::uuid, 'start_review', null, null);
select tst.expect_error(format($$select public.review_partner_application(%L::uuid, 'approve', null, null)$$, :'app_partner'), 'category', 'partner approval requires a category');
select public.review_partner_application(:'app_partner'::uuid, 'approve', 'Education', null);
select tst.as_user('00000000-0000-4000-8000-0000000000c1');
select tst.ok(public.has_permission('partner.portal'), 'approved partner gets the partner portal');
select tst.ok(not public.has_permission('users.manage') and not public.has_permission('admins.manage'), 'partner does not become an administrator');
select tst.expect_error($$select public.set_partner_permission('00000000-0000-4000-8000-0000000000c1', 'users.manage', true)$$, 'Permission denied', 'partner cannot grant themselves permissions');
select tst.expect_error($$select public.submit_partner_application('Again','again','a@b.test','Org','','{}','Education','A proposal long enough to pass validation rules here.','d')$$,
  'already an active', 'active partner cannot re-apply');
select tst.ok(public.partner_dashboard() ->> 'partner_status' = 'active', 'partner dashboard reports active status');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.set_partner_permission('00000000-0000-4000-8000-0000000000c1'::uuid, 'partner.announcements.read', true);
select tst.expect_error(format($$select public.set_partner_permission(%L::uuid, 'users.manage', true)$$, '00000000-0000-4000-8000-0000000000c1'), 'Not a partner-scoped', 'partner rights are limited to partner-scoped permissions');
select public.publish_partner_announcement('Welcome partners', 'Partner portal is live.', null);
select public.review_partner_application(:'app_partner'::uuid, 'suspend', null, 'Review pending');
select tst.as_user('00000000-0000-4000-8000-0000000000c1');
select tst.ok(not public.has_permission('partner.portal'), 'suspended partner loses the portal');
select tst.as_user('00000000-0000-4000-8000-0000000000a3');
select public.review_partner_application(:'app_partner'::uuid, 'restore', null, null);
select tst.as_user('00000000-0000-4000-8000-0000000000c1');
select tst.ok(public.has_permission('partner.portal'), 'restored partner regains the portal');

-- ---------------------------------------------------------------------------
-- 8. Messaging, blocking, receipts
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_direct_conversation('00000000-0000-4000-8000-0000000000b2') as conv \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_direct_conversation('00000000-0000-4000-8000-0000000000b2') as conv2 \gset
select tst.ok(:'conv' = :'conv2', 'direct conversation is unique per pair');
insert into public.messages (conversation_id, sender_id, client_message_id, body)
values (:'conv', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'Hi Bob') returning id as msg_id \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q($$select id from public.messages where conversation_id = '$$ || :'conv' || $$'$$) = 0, 'non-member cannot read messages');
select tst.expect_error(format($$insert into public.messages (conversation_id, sender_id, client_message_id, body) values (%L, %L, gen_random_uuid(), 'intrude')$$, :'conv', '00000000-0000-4000-8000-0000000000b3'),
  'row-level', 'non-member cannot send messages');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(tst.count_q($$select id from public.messages where conversation_id = '$$ || :'conv' || $$'$$) = 1, 'member reads conversation messages');
select tst.expect_ok(format($$select public.mark_conversation_read(%L::uuid)$$, :'conv'), 'member marks conversation read');
select tst.expect_error(format($$insert into public.messages (conversation_id, sender_id, client_message_id, body) values (%L, %L, gen_random_uuid(), 'spoof')$$, :'conv', '00000000-0000-4000-8000-0000000000b1'),
  'row-level', 'cannot send as another user');
select tst.expect_error($$update public.messages set body = 'tamper'$$, 'permission denied', 'clients cannot update messages directly');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.blocked_users (blocker_id, blocked_id) values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2');
select tst.expect_error(format($$select public.create_direct_conversation(%L::uuid)$$, '00000000-0000-4000-8000-0000000000b2'), 'cannot message this account', 'blocked users cannot start chats');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error(format($$insert into public.messages (conversation_id, sender_id, client_message_id, body) values (%L, %L, gen_random_uuid(), 'after block')$$, :'conv', '00000000-0000-4000-8000-0000000000b2'),
  'row-level', 'blocked user cannot message in an existing direct chat');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
delete from public.blocked_users where blocker_id = '00000000-0000-4000-8000-0000000000b1' and blocked_id = '00000000-0000-4000-8000-0000000000b2';

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_group_conversation('Study group', array['00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b3']::uuid[]) as grp \gset
select tst.ok(tst.count_q($$select user_id from public.conversation_members where conversation_id = '$$ || :'grp' || $$'$$) = 3, 'group created with three members');
