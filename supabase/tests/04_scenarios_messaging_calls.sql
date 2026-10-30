-- =============================================================================
-- Scenario suite 04: message kinds, pin/star, calls, preference-aware notifications,
-- status and activity notifications, security events, owner statistics.
-- Identities: owner a1, admin a2, super admin a3, moderator a4, partner c1, users b1 b2 b3.
-- Note: b1 blocks b2 in suite 02, so calls and new chats here use b1 and b3.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 11. Message kinds
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.create_direct_conversation('00000000-0000-4000-8000-0000000000b3') as c13 \gset
insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'audio', null);
insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'gif', null);
insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'sticker', null);
select tst.expect_error(format($$insert into public.messages (conversation_id, sender_id, client_message_id, kind, body) values (%L, '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'hologram', 'x')$$, :'c13'),
  'violates check', 'unknown message kinds are rejected');

-- ---------------------------------------------------------------------------
-- 12. Pin (conversation-wide) and star (personal)
-- ---------------------------------------------------------------------------
insert into public.messages (conversation_id, sender_id, client_message_id, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'Meeting at 10') returning id as pin_msg \gset
select tst.expect_ok(format($$select public.set_message_pinned(%L::uuid, true)$$, :'pin_msg'), 'member pins a message');
select tst.ok((select pinned_at is not null from public.messages where id = :'pin_msg'), 'pinned message is marked');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_ok(format($$select public.set_message_pinned(%L::uuid, false)$$, :'pin_msg'), 'other member can unpin in a shared chat');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error(format($$select public.set_message_pinned(%L::uuid, true)$$, :'pin_msg'), 'not found', 'non-member cannot pin');
select tst.expect_error($$update public.messages set pinned_at = now()$$, 'permission denied', 'clients cannot write pin columns directly');

select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_ok(format($$insert into public.message_stars (user_id, message_id) values (%L, %L)$$, '00000000-0000-4000-8000-0000000000b3', :'pin_msg'), 'member stars a message');
select tst.expect_error(format($$insert into public.message_stars (user_id, message_id) values (%L, %L)$$, '00000000-0000-4000-8000-0000000000b1', :'pin_msg'), 'row-level', 'cannot star as another user');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error(format($$insert into public.message_stars (user_id, message_id) values (%L, %L)$$, '00000000-0000-4000-8000-0000000000a4', :'pin_msg'), 'row-level', 'non-member cannot star a message they cannot see');
select tst.ok(tst.count_q('select 1 from public.message_stars') = 0, 'stars are private to their owner');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q('select 1 from public.message_stars') = 1, 'owner sees own stars');
select tst.expect_ok(format($$delete from public.message_stars where message_id = %L$$, :'pin_msg'), 'owner removes a star');

-- ---------------------------------------------------------------------------
-- 13. Calls: ringing, answer, decline, cancel, missed, single live call
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.start_call(:'c13'::uuid, 'voice') as call1 \gset
select tst.ok(tst.count_q(format($$select id from public.calls where id = %L and status = 'ringing'$$, :'call1')) = 1, 'call starts ringing');
select tst.expect_error(format($$select public.start_call(%L::uuid, 'video')$$, :'c13'), 'already in progress', 'a second call is refused while one rings');
select tst.expect_error(format($$select public.answer_call(%L::uuid)$$, :'call1'), 'Call not found', 'caller cannot answer their own call');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q(format($$select id from public.notifications where kind = 'incoming_call' and user_id = '00000000-0000-4000-8000-0000000000b3'$$)) >= 1, 'callee receives an incoming-call notification');
select tst.expect_ok(format($$select public.answer_call(%L::uuid)$$, :'call1'), 'callee answers');
select tst.expect_error(format($$select public.decline_call(%L::uuid)$$, :'call1'), 'no longer ringing', 'answered call cannot be declined');
select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error(format($$select public.answer_call(%L::uuid)$$, :'call1'), 'Call not found', 'a third party cannot answer');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_ok(format($$select public.end_call(%L::uuid)$$, :'call1'), 'callee ends the answered call');
select tst.ok((select status from public.calls where id = :'call1') = 'ended', 'ended call is recorded');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.start_call(:'c13'::uuid, 'video') as call2 \gset
select tst.expect_ok(format($$select public.end_call(%L::uuid)$$, :'call2'), 'caller cancels a ringing call');
select tst.ok((select status from public.calls where id = :'call2') = 'cancelled', 'cancelled call is recorded');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q(format($$select id from public.notifications where kind = 'missed_call' and data ->> 'call_id' = %L$$, :'call2')) = 1, 'cancelled call notifies the callee as missed');
select tst.expect_error(format($$select public.decline_call(%L::uuid)$$, :'call2'), 'no longer ringing', 'cancelled call cannot be declined');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select public.start_call(:'c13'::uuid, 'voice') as call3 \gset
select tst.as_trusted();
update public.calls set started_at = now() - interval '2 minutes' where id = :'call3';
select tst.ok(public.expire_stale_calls() >= 1, 'unanswered calls expire');
select tst.ok((select status from public.calls where id = :'call3') = 'missed', 'expired call is missed');
select tst.ok(tst.count_q(format($$select id from public.notifications where kind = 'missed_call' and data ->> 'call_id' = %L$$, :'call3')) = 1, 'missed call notifies the callee once');

select tst.as_user('00000000-0000-4000-8000-0000000000a4');
select tst.expect_error(format($$select public.start_call(%L::uuid, 'voice')$$, :'c13'), 'Conversation not found', 'non-member cannot start a call');
select tst.expect_error(format($$insert into public.calls (conversation_id, caller_id, callee_id, media) values (%L, %L, %L, 'voice')$$, :'c13', '00000000-0000-4000-8000-0000000000a4', '00000000-0000-4000-8000-0000000000a4'), 'permission denied', 'clients cannot insert call records directly');
select tst.ok(tst.count_q('select id from public.calls') = 0, 'non-participants cannot read call records');

-- ---------------------------------------------------------------------------
-- 14. Preference-aware notifications
-- ---------------------------------------------------------------------------
select tst.as_trusted();
update public.user_settings set notifications = jsonb_set(notifications, '{messages}', 'false')
  where user_id = '00000000-0000-4000-8000-0000000000b3';
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.messages (conversation_id, sender_id, client_message_id, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'You there?');
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'new_message' and body = 'You there?'$$, '00000000-0000-4000-8000-0000000000b3')) = 0,
  'message notifications respect the disabled preference');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.as_trusted();
update public.user_settings set notifications = jsonb_set(notifications, '{messages}', 'true')
  where user_id = '00000000-0000-4000-8000-0000000000b3';
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.messages (conversation_id, sender_id, client_message_id, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'Lunch?');
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'new_message' and body = 'Lunch?'$$, '00000000-0000-4000-8000-0000000000b3')) = 1,
  'message notifications arrive when enabled');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'image', null);
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'new_message' and body = 'Sent a photo'$$, '00000000-0000-4000-8000-0000000000b3')) = 1,
  'media messages produce a readable preview');
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'new_message'$$, '00000000-0000-4000-8000-0000000000b1')) = 0,
  'the sender is not notified about their own message');

-- Security alerts are never suppressed by preferences.
update public.user_settings set notifications = '{"messages":false,"calls":false,"channels":false}'::jsonb
  where user_id = '00000000-0000-4000-8000-0000000000b3';
select public.notify_user('00000000-0000-4000-8000-0000000000b3', 'security_alert', 'Test alert', 'Still delivered', '{}');
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and title = 'Test alert'$$, '00000000-0000-4000-8000-0000000000b3')) = 1,
  'security alerts ignore disabled preferences');
update public.user_settings set notifications = '{"messages":true,"calls":true,"channels":true}'::jsonb
  where user_id = '00000000-0000-4000-8000-0000000000b3';

-- Muted conversations do not notify.
update public.conversation_members set muted = true
  where conversation_id = :'c13' and user_id = '00000000-0000-4000-8000-0000000000b3';
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
insert into public.messages (conversation_id, sender_id, client_message_id, body)
  values (:'c13', '00000000-0000-4000-8000-0000000000b1', gen_random_uuid(), 'Muted text');
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and body = 'Muted text'$$, '00000000-0000-4000-8000-0000000000b3')) = 0,
  'muted conversations do not notify');
update public.conversation_members set muted = false
  where conversation_id = :'c13' and user_id = '00000000-0000-4000-8000-0000000000b3';

-- ---------------------------------------------------------------------------
-- 15. Channel post notifications (official channel announcements)
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select tst.ok((select count(*) from public.channels where is_official) = 1, 'official channel exists exactly once');
insert into public.channel_posts (channel_id, author_id, kind, body)
  select id, '00000000-0000-4000-8000-0000000000a1', 'text', 'Security notice: enable two-step verification'
    from public.channels where is_official;
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'channel_post' and body like 'Security notice%%'$$, '00000000-0000-4000-8000-0000000000b3')) = 1,
  'official announcements notify subscribers');
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'channel_post' and body like 'Security notice%%'$$, '00000000-0000-4000-8000-0000000000a1')) = 0,
  'the publisher is not notified about their own post');
select tst.ok(public.dispatch_channel_post((select id from public.channel_posts where body like 'Security notice%' limit 1)) = 0,
  'a post is dispatched only once');

update public.user_settings set notifications = jsonb_set(notifications, '{channels}', 'false')
  where user_id = '00000000-0000-4000-8000-0000000000b3';
insert into public.channel_posts (channel_id, author_id, kind, body)
  select id, '00000000-0000-4000-8000-0000000000a1', 'text', 'Quiet update'
    from public.channels where is_official;
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and body = 'Quiet update'$$, '00000000-0000-4000-8000-0000000000b3')) = 0,
  'channel notifications respect the disabled preference');
update public.user_settings set notifications = jsonb_set(notifications, '{channels}', 'true')
  where user_id = '00000000-0000-4000-8000-0000000000b3';

-- ---------------------------------------------------------------------------
-- 16. Status notifications: verification, partner, story reactions
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select public.submit_verification_application('user', 'Carol Example', 'carol_again', 'Artist', 'Digital artist', 'Public figure with press coverage again', '[]');
select tst.as_trusted();
update public.verification_applications set status = 'under_review'
  where applicant_id = '00000000-0000-4000-8000-0000000000b3' and status = 'pending';
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'verification_status'$$, '00000000-0000-4000-8000-0000000000b3')) >= 1,
  'verification status changes notify the applicant');

insert into public.stories (author_id, kind, body, privacy) values ('00000000-0000-4000-8000-0000000000b1', 'text', 'Story for reactions', 'everyone') returning id as story \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_ok(format($$insert into public.story_reactions (story_id, user_id, emoji) values (%L, %L, '🔥')$$, :'story', '00000000-0000-4000-8000-0000000000b3'), 'viewer reacts to a story');
select tst.as_trusted();
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'story_reaction'$$, '00000000-0000-4000-8000-0000000000b1')) >= 1,
  'story authors are notified of reactions');

-- ---------------------------------------------------------------------------
-- 17. Security events: role and account activity
-- ---------------------------------------------------------------------------
select tst.ok(tst.count_q(format($$select id from public.security_events where user_id = %L and kind = 'role_granted'$$, '00000000-0000-4000-8000-0000000000a2')) >= 1,
  'admin role grant is recorded as a security event');
select tst.count_q(format($$select id from public.security_events where user_id = %L and kind = 'account_status_changed'$$, '00000000-0000-4000-8000-0000000000b3')) as before_events \gset
update public.profiles set account_status = 'suspended' where id = '00000000-0000-4000-8000-0000000000b3';
select tst.ok(tst.count_q(format($$select id from public.security_events where user_id = %L and kind = 'account_status_changed'$$, '00000000-0000-4000-8000-0000000000b3')) = :before_events + 1,
  'account status changes are recorded');
select tst.ok(tst.count_q(format($$select id from public.notifications where user_id = %L and kind = 'security_alert' and title = 'Account status changed'$$, '00000000-0000-4000-8000-0000000000b3')) >= 1,
  'account status changes produce a security alert');
update public.profiles set account_status = 'active' where id = '00000000-0000-4000-8000-0000000000b3';
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q('select id from public.security_events') >= 2, 'users can read their own security events');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q(format($$select id from public.security_events where user_id = %L$$, '00000000-0000-4000-8000-0000000000b3')) = 0,
  'users cannot read another user''s security events');
select tst.expect_error($$insert into public.security_events (user_id, kind) values (auth.uid(), 'role_granted')$$, 'permission denied', 'clients cannot forge security events');

-- ---------------------------------------------------------------------------
-- 18. Privileges of the new functions
-- ---------------------------------------------------------------------------
select tst.as_anon();
select tst.expect_error('select public.start_call(null::uuid, ''voice'')', 'permission denied', 'anonymous users cannot start calls');
select tst.expect_error('select public.expire_stale_calls()', 'permission denied', 'anonymous users cannot expire calls');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error('select public.expire_stale_calls()', 'permission denied', 'users cannot run the call sweeper');
select tst.expect_error('select public.dispatch_due_channel_posts()', 'permission denied', 'users cannot run the channel sweeper');
select tst.expect_error('select public.on_message_notify()', 'permission denied', 'users cannot call notification trigger functions');

-- ---------------------------------------------------------------------------
-- 19. Owner statistics include conversations (real count, not hardcoded)
-- ---------------------------------------------------------------------------
select tst.as_trusted();
select count(*) as conv_total from public.conversations \gset
select tst.as_user('00000000-0000-4000-8000-0000000000a1');
select tst.ok((public.owner_dashboard_stats() ->> 'total_conversations')::int = :conv_total,
  'owner statistics count conversations from the database');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error('select public.owner_dashboard_stats()', 'Permission denied', 'ordinary users cannot read owner statistics');

select tst.as_trusted();
select 'ALL CHECKS PASSED (suite 04)' as result;
