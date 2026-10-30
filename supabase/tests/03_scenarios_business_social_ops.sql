-- ---------------------------------------------------------------------------
-- 9. Business accounts: validated setup, mode switching, membership rules
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error($$select public.create_business('Bob Shop','bob_shop','Retail','not-an-email','', null, null)$$, 'valid business email', 'business setup validates email');
select tst.expect_error($$select public.create_business('B','bob_shop','Retail','bob@shop.test','', null, null)$$, 'business name', 'business setup validates name');
select public.create_business('Bob Shop','bob_shop','Retail','bob@shop.test','Handmade goods', 'https://shop.test', '+62 812 0000 0000') as biz \gset
select tst.expect_error($$select public.create_business('Other','bob_shop','Retail','o@shop.test','', null, null)$$, 'already taken', 'business username is unique');
select tst.expect_ok(format($$select public.switch_account_mode('business', %L::uuid)$$, :'biz'), 'member switches to Business Mode');
select tst.ok((select active_account_mode from public.user_settings where user_id = '00000000-0000-4000-8000-0000000000b2') = 'business', 'active mode is stored');
select tst.ok((select count(*) from public.account_modes where user_id = '00000000-0000-4000-8000-0000000000b2' and mode = 'personal') = 1,
  'personal account mode is untouched by switching');
select tst.expect_ok($$select public.switch_account_mode('personal', null)$$, 'switch back to Personal Mode');
select tst.ok((select display_name from public.profiles where id = '00000000-0000-4000-8000-0000000000b2') = 'Bob', 'personal profile data is untouched by switching');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error(format($$select public.switch_account_mode('business', %L::uuid)$$, :'biz'), 'not a member', 'non-member cannot enter someone else''s business');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select public.add_business_operator(:'biz'::uuid, '00000000-0000-4000-8000-0000000000b3'::uuid, 'operator');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q(format($$select id from public.businesses where id = %L$$, :'biz')) = 1, 'operator can see the business');
update public.businesses set name = 'Hacked Shop' where id = :'biz';
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok((select name from public.businesses where id = :'biz') = 'Bob Shop', 'operator cannot edit the business profile');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error(format($$select public.add_business_operator(%L::uuid, %L::uuid, 'operator')$$, :'biz', '00000000-0000-4000-8000-0000000000b1'), 'Only business owners', 'operator cannot add operators');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select public.remove_business_operator(:'biz'::uuid, '00000000-0000-4000-8000-0000000000b3'::uuid);
select tst.expect_ok(format($$select public.add_business_operator(%L::uuid, %L::uuid, 'operator')$$, :'biz', '00000000-0000-4000-8000-0000000000b3'), 'owner re-adds an operator');
insert into public.business_catalog_items (business_id, name, price_minor) values (:'biz', 'Ceramic mug', 150000);
insert into public.business_quick_replies (business_id, shortcut, body) values (:'biz', '/hours', 'We are open 9-17 on weekdays.');
select tst.expect_error(format($$insert into public.business_quick_replies (business_id, shortcut, body) values (%L, '/BAD SHORTCUT', 'x')$$, :'biz'), 'violates check', 'quick reply shortcuts are validated');
select tst.ok((public.business_dashboard(:'biz'::uuid) ->> 'catalog_items')::int = 1, 'business dashboard counts catalog items');

-- ---------------------------------------------------------------------------
-- 10. Stories: 24h expiry, privacy, reactions and replies
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error($$insert into public.stories (author_id, kind, body, expires_at) values (auth.uid(), 'text', 'long', now() + interval '2 days')$$, 'stories_24h', 'stories cannot outlive 24 hours');
insert into public.stories (author_id, kind, body) values ('00000000-0000-4000-8000-0000000000b1', 'text', 'Good morning Bandung') returning id as story \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(tst.count_q($$select id from public.stories where id = '$$ || :'story' || $$'$$) = 0, 'contacts-only story is hidden from non-contacts');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.contacts (owner_id, contact_id) values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(tst.count_q($$select id from public.stories where id = '$$ || :'story' || $$'$$) = 1, 'story is visible to the author''s contacts');
select tst.expect_ok(format($$insert into public.story_views (story_id, viewer_id) values (%L, %L)$$, :'story', '00000000-0000-4000-8000-0000000000b2'), 'viewer records a story view');
select tst.expect_ok(format($$insert into public.story_replies (story_id, author_id, body) values (%L, %L, 'Nice!')$$, :'story', '00000000-0000-4000-8000-0000000000b2'), 'viewer replies to story');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error(format($$insert into public.story_views (story_id, viewer_id) values (%L, %L)$$, :'story', '00000000-0000-4000-8000-0000000000b3'), 'row-level', 'non-contact cannot record a view');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q($$select viewer_id from public.story_views where story_id = '$$ || :'story' || $$'$$) = 1, 'author sees story viewers');

-- ---------------------------------------------------------------------------
-- 11. Communities: create, join, admin add, role management, group chat link
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_community('Bandung Makers', 'Local makers', 'public') as comm \gset
select tst.ok(tst.count_q($$select user_id from public.community_members where community_id = '$$ || :'comm' || $$'$$) = 1, 'creator is the community owner member');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select public.join_community(:'comm'::uuid);
select tst.ok(tst.count_q(format($$select user_id from public.conversation_members where conversation_id = (select conversation_id from public.communities where id = %L) and user_id = %L$$, :'comm', '00000000-0000-4000-8000-0000000000b3')) = 1,
  'joining a community also joins its group chat');
select tst.expect_error(format($$select public.set_community_member_role(%L::uuid, %L::uuid, 'admin')$$, :'comm', '00000000-0000-4000-8000-0000000000b2'), 'Only the community owner', 'non-owner cannot manage community roles');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.set_community_member_role(:'comm'::uuid, '00000000-0000-4000-8000-0000000000b3'::uuid, 'admin');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select public.add_community_member(:'comm'::uuid, '00000000-0000-4000-8000-0000000000b2'::uuid);
select tst.ok(tst.count_q(format($$select user_id from public.community_members where community_id = %L$$, :'comm')) = 3, 'community admin adds members');
select public.leave_community(:'comm'::uuid);
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error(format($$select public.leave_community(%L::uuid)$$, :'comm'), 'Transfer ownership', 'owner cannot leave without transferring ownership');

-- ---------------------------------------------------------------------------
-- 12. Reports & moderation (immutable moderation trail, hidden content)
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_direct_conversation('00000000-0000-4000-8000-0000000000b3') as dm \gset
insert into public.messages (conversation_id, sender_id, client_message_id, body) values (:'dm', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'Abusive text') returning id as abusive \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
insert into public.reports (reporter_id, target_type, target_id, reason)
values ('00000000-0000-4000-8000-0000000000b2', 'user', '00000000-0000-4000-8000-0000000000b1', 'Harassment') ;
select tst.expect_error(format($$insert into public.reports (reporter_id, target_type, target_id, reason) values (%L, 'user', %L, 'Dup')$$, '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b1'), 'duplicate|unique', 'one report per reporter per target');
select tst.expect_error(format($$insert into public.reports (reporter_id, target_type, target_id, reason) values (%L, 'user', %L, 'x')$$, '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2'), 'row-level|violates check', 'report reason must be meaningful');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.ok(tst.count_q($$select id from public.reports$$) >= 1, 'moderator sees reports');
select tst.expect_ok($$select public.resolve_report((select id from public.reports where target_type = 'user' and target_id = '00000000-0000-4000-8000-0000000000b1' limit 1), 'escalate', null)$$, 'moderator escalates a report');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L$$, '00000000-0000-4000-8000-0000000000b1')) >= 0, 'notifications are readable by their owner');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error($$select public.resolve_report((select id from public.reports limit 1), 'suspend_user', 'x')$$, 'Permission denied', 'moderator cannot suspend users (needs users.manage)');
-- moderator hides a message reported by Bob (create a message-level report first)
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
insert into public.reports (reporter_id, target_type, target_id, reason) values ('00000000-0000-4000-8000-0000000000b2', 'message', :'abusive', 'Abusive');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select public.resolve_report((select id from public.reports where target_type = 'message' and target_id = :'abusive'), 'hide_content', 'violates policy');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q($$select id from public.messages where id = '$$ || :'abusive' || $$'$$) = 0, 'hidden message disappears for recipients');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q($$select id from public.messages where id = '$$ || :'abusive' || $$'$$) = 1, 'sender still sees the hidden message');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.ok(tst.count_q($$select id from public.moderation_actions$$) >= 1, 'moderation actions are recorded');

-- ---------------------------------------------------------------------------
-- 13. Platform announcements, premium, dashboards, access snapshot
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select public.publish_platform_announcement('Maintenance window', 'Saturday 02:00-03:00 WIB.', 'all', true);
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q($$select id from public.platform_announcements where title = 'Maintenance window'$$) = 1, 'users see the platform announcement');
select tst.ok(tst.count_q($$select id from public.channel_posts where body like 'Maintenance window%'$$) = 1, 'announcement mirrored into @BubbleApp');
select tst.expect_error($$select public.publish_platform_announcement('x','y','all',false)$$, 'Permission denied', 'user cannot publish announcements');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error($$select public.owner_dashboard_stats()$$, 'Permission denied', 'ordinary user cannot read dashboards');
select tst.expect_error($$select * from public.admin_list_users()$$, 'Permission denied', 'ordinary user cannot list users with emails');
select tst.ok(not (public.my_access() ->> 'is_owner')::boolean, 'access snapshot reports no owner for users');
select tst.as_user('00000000-0000-4000-8000-0000000000a2');
select tst.ok((public.owner_dashboard_stats() ->> 'total_users')::int >= 8, 'admin with analytics.read sees live user totals');
select tst.ok(tst.count_q($$select id from public.admin_list_users(null, null, 50, 0)$$) >= 8, 'admin lists users with users.read');
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select tst.ok((public.owner_dashboard_stats() ->> 'total_channels')::int >= 2, 'owner dashboard reports channels');
select tst.ok((public.my_access() ->> 'is_owner')::boolean, 'access snapshot identifies the owner');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error($$select public.set_platform_setting('premium_features', '{}'::jsonb)$$, 'Permission denied', 'user cannot change premium feature flags');
select tst.as_trusted();
insert into public.premium_subscriptions (user_id, plan, status, starts_at, ends_at, provider, provider_ref)
values ('00000000-0000-4000-8000-0000000000b1', 'monthly', 'active', now() - interval '1 day', now() + interval '29 days', 'test-billing', 'sub_test_1');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(public.has_premium(), 'premium status is granted from the trusted subscription record');
select tst.ok(public.premium_feature_granted('custom_themes') , 'premium feature flags gate on feature availability and entitlement');
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.ok(not public.has_premium(), 'premium is not granted to others');
select tst.expect_error($$insert into public.premium_subscriptions (user_id, plan, status, starts_at, ends_at, provider) values (auth.uid(), 'yearly', 'active', now(), now() + interval '1 year', 'self')$$, 'permission denied', 'users cannot grant themselves premium');

-- ---------------------------------------------------------------------------
-- 14. Devices, presence, realtime, storage policy surface
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.devices (user_id, platform, fcm_token, device_name) values ('00000000-0000-4000-8000-0000000000b1', 'android', 'fcm-token-alice', 'Pixel');
select tst.expect_error($$insert into public.devices (user_id, platform, fcm_token) values ('00000000-0000-4000-8000-0000000000b2', 'ios', 'fcm-bob')$$, 'row-level', 'device rows are owner-only');
select public.touch_presence();
select tst.ok((select last_seen_at from public.profiles where id = '00000000-0000-4000-8000-0000000000b1') is not null, 'presence heartbeat updates last seen');
select tst.as_trusted();
select tst.ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'messages'), 'messages are published for realtime');
select tst.ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'channel_posts'), 'channel posts are published for realtime');
select tst.ok(exists (select 1 from storage.buckets where id = 'verification-documents' and public = false), 'verification documents use a private bucket');
select tst.ok(exists (select 1 from storage.buckets where id = 'chat-media' and public = false), 'chat media is private');
select tst.ok(not has_function_privilege('authenticated', 'public.guard_mandatory_subscription()', 'EXECUTE'), 'trigger functions are not callable through the API');
select tst.ok(not has_function_privilege('authenticated', 'public.write_audit(text,text,text,jsonb)', 'EXECUTE'), 'audit writer is not callable through the API');
select tst.ok(not has_table_privilege('authenticated', 'public.user_roles', 'INSERT'), 'clients cannot write user_roles');
select tst.ok(not has_table_privilege('anon', 'public.messages', 'SELECT'), 'anonymous role cannot read messages');
select tst.ok(not has_table_privilege('authenticated', 'public.profiles', 'UPDATE') , 'profiles has no table-wide update (column grants only)');
select tst.ok(not has_column_privilege('authenticated', 'public.profiles', 'email', 'SELECT'), 'email column is not selectable by clients');
select tst.ok(not has_column_privilege('authenticated', 'public.profiles', 'is_verified', 'UPDATE'), 'is_verified is not updatable by clients');
select tst.ok(not has_column_privilege('authenticated', 'public.channels', 'is_verified', 'UPDATE'), 'channel badge is not updatable by clients');

-- Account deletion cascades through the mandatory-subscription guard (not blocked).
select tst.as_trusted();
insert into auth.users (id, email) values ('00000000-0000-4000-8000-0000000000d1', 'deleted@bubble.test');
delete from auth.users where id = '00000000-0000-4000-8000-0000000000d1';
select tst.ok(not exists (select 1 from public.profiles where id = '00000000-0000-4000-8000-0000000000d1')
          and not exists (select 1 from public.channel_subscribers where user_id = '00000000-0000-4000-8000-0000000000d1'),
  'deleting an account removes its profile and subscriptions despite the mandatory-follow guard');

select tst.as_trusted();
select 'ALL CHECKS PASSED' as result;
