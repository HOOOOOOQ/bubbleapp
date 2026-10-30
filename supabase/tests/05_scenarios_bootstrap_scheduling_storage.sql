-- ---------------------------------------------------------------------------
-- 15. Storage buckets: names, privacy, MIME allow-lists, folder helper
-- ---------------------------------------------------------------------------
select tst.ok(
  (select count(*) from storage.buckets where id in ('avatars','profile-covers','business-media','chat-media',
     'chat-attachments','story-media','channel-media','verification-documents','wallpapers')) = 9,
  'all nine spec buckets exist');
select tst.ok(not exists (select 1 from storage.buckets where id = 'verification-docs'), 'old verification bucket name is gone');
select tst.ok(exists (select 1 from storage.buckets where id = 'verification-documents' and public = false
                      and 'image/jpeg' = any(allowed_mime_types) and not ('video/mp4' = any(allowed_mime_types))),
  'verification documents are private and MIME-restricted');
select tst.ok(exists (select 1 from storage.buckets where id = 'chat-attachments' and public = false), 'chat attachments are private');
select tst.ok(exists (select 1 from storage.buckets where id = 'avatars' and public = true), 'avatars are public');
select tst.ok(public.storage_folder_uuid('not-a-uuid/file.png') is null, 'folder helper returns null for non-uuid folders');
select tst.ok(public.storage_folder_uuid('00000000-0000-4000-8000-0000000000b1/x.png') = '00000000-0000-4000-8000-0000000000b1'::uuid,
  'folder helper parses uuid folders');

-- ---------------------------------------------------------------------------
-- 16. Owner-role guard uses the vetted privilege flag
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error($$insert into public.user_roles (user_id, role_key) values ('00000000-0000-4000-8000-0000000000b1', 'owner')$$,
  'permission denied|trusted server-side setup|row-level security', 'ordinary user cannot insert an owner role');
select tst.expect_error($$select public.redeem_owner_bootstrap('this-token-is-long-enough-but-wrong-000')$$,
  'verified|Owner already exists', 'redeem fails for an unverified account or while an owner exists');
select tst.expect_error($$select public.issue_owner_bootstrap_token('attack')$$, 'permission denied|trusted server context',
  'users cannot issue bootstrap tokens');
select tst.as_anon();
select tst.expect_error($$select public.redeem_owner_bootstrap('x')$$, 'permission denied', 'anon cannot redeem bootstrap');

-- ---------------------------------------------------------------------------
-- 17. Owner bootstrap lifecycle. Setup: the seeded owner is revoked in this
--     disposable database so the one-time path can be exercised. Carol becomes
--     the only owner at the end, through the token flow.
-- ---------------------------------------------------------------------------
select tst.as_trusted();
update public.user_roles set revoked_at = now() where role_key = 'owner' and revoked_at is null;
select public.issue_owner_bootstrap_token('suite-05-primary', interval '1 hour') as tok_primary \gset
select public.issue_owner_bootstrap_token('suite-05-expired', interval '1 hour') as tok_expired \gset
update public.owner_bootstrap_tokens set expires_at = now() - interval '1 minute' where label = 'suite-05-expired';
select tst.ok(not exists (select 1 from public.owner_bootstrap_tokens where token_hash = sha256(convert_to('plaintext-check', 'UTF8'))),
  'token table never stores plaintext (sanity)');
select tst.ok(exists (select 1 from public.owner_bootstrap_tokens where token_hash = sha256(convert_to(:'tok_primary', 'UTF8'))
                      and consumed_at is null), 'token is stored only as a hash and is unconsumed');
select tst.ok(not exists (select 1 from public.owner_bootstrap_tokens where token_hash = convert_to(:'tok_primary', 'UTF8')),
  'stored value is not the plaintext token');
select tst.ok(exists (select 1 from public.owner_audit_logs where action = 'owner.bootstrap_token_issued'),
  'token issuance is audited');

-- Carol has not verified her email yet.
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error(format($$select public.redeem_owner_bootstrap(%L)$$, :'tok_primary'), 'must be verified',
  'unverified email cannot redeem');

select tst.as_trusted();
update auth.users set email_confirmed_at = now() where id = '00000000-0000-4000-8000-0000000000b3';
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error($$select public.redeem_owner_bootstrap('wrong-token-value-that-is-long-enough-123')$$,
  'Invalid or expired', 'wrong token is rejected');
select tst.expect_error(format($$select public.redeem_owner_bootstrap(%L)$$, :'tok_expired'),
  'Invalid or expired', 'expired token is rejected');
select tst.expect_error($$select public.redeem_owner_bootstrap('short')$$, 'Invalid or expired', 'short token is rejected');
select tst.expect_ok(format($$select public.redeem_owner_bootstrap(%L)$$, :'tok_primary'), 'verified account redeems the valid token');
select tst.expect_error(format($$select public.redeem_owner_bootstrap(%L)$$, :'tok_primary'),
  'Owner already exists', 'a redeemed token cannot be used again');

select tst.as_trusted();
select tst.ok((select count(*) from public.user_roles where role_key = 'owner' and revoked_at is null) = 1, 'exactly one owner exists');
select tst.ok(exists (select 1 from public.user_roles where role_key = 'owner' and revoked_at is null
                      and user_id = '00000000-0000-4000-8000-0000000000b3'), 'Carol is the owner');
select tst.ok(exists (select 1 from public.owner_audit_logs where action = 'owner.bootstrap_redeemed'
                      and actor_id = '00000000-0000-4000-8000-0000000000b3'), 'redemption is audited');
select tst.ok(exists (select 1 from public.owner_bootstrap_tokens where label = 'suite-05-primary' and consumed_at is not null),
  'token is consumed');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error(format($$select public.redeem_owner_bootstrap(%L)$$, :'tok_primary'), 'Owner already exists|must be verified',
  'once an owner exists, the bootstrap path is closed for everyone');

-- ---------------------------------------------------------------------------
-- 18. Scheduled messages (Alice b1 <-> Carol b3 conversation from suite 04)
-- ---------------------------------------------------------------------------
select tst.as_trusted();
select c.id as conv from public.conversations c
 where exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = '00000000-0000-4000-8000-0000000000b1' and m.left_at is null)
   and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = '00000000-0000-4000-8000-0000000000b3' and m.left_at is null)
 and c.kind = 'direct' limit 1 \gset
select tst.ok(:'conv' is not null, 'shared direct conversation exists for scheduling tests');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_error(format($$select public.schedule_message(%L::uuid, 'too soon', now() + interval '5 seconds')$$, :'conv'),
  'at least 30 seconds', 'scheduling too soon is rejected');
select tst.expect_error(format($$select public.schedule_message(%L::uuid, 'far away', now() + interval '400 days')$$, :'conv'),
  'within 365 days', 'scheduling too far ahead is rejected');
select tst.expect_error(format($$select public.schedule_message(%L::uuid, '   ', now() + interval '1 hour')$$, :'conv'),
  'messages_body|scheduled_messages_body|check constraint', 'blank scheduled body is rejected');
select public.schedule_message(:'conv'::uuid, 'Reminder for tomorrow', now() + interval '1 hour') as sched_ok \gset
select tst.ok(:'sched_ok' is not null, 'member schedules a message');

select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_error(format($$select public.schedule_message(%L::uuid, 'intrude', now() + interval '1 hour')$$, :'conv'),
  'not a member', 'non-member cannot schedule into a conversation');
select tst.ok(tst.count_q(format($$select id from public.scheduled_messages where id = %L$$, :'sched_ok')) = 0,
  'scheduled rows are not visible to other users');

select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.expect_ok(format($$select public.cancel_scheduled_message(%L::uuid)$$, :'sched_ok'), 'sender cancels a pending scheduled message');
select tst.expect_error(format($$select public.cancel_scheduled_message(%L::uuid)$$, :'sched_ok'), 'not found or already sent',
  'a cancelled message cannot be cancelled again');
select tst.expect_error($$select public.dispatch_due_scheduled_messages(10)$$, 'permission denied',
  'users cannot run the scheduler');

-- Scheduler (service role semantics): a due message from a member is delivered; a due message from a
-- sender who has left the conversation is marked failed and nothing is posted.
select tst.as_trusted();
insert into public.scheduled_messages (conversation_id, sender_id, body, send_at)
values (:'conv', '00000000-0000-4000-8000-0000000000b1', 'Due now from Alice', now() - interval '1 second')
returning id as due_ok \gset
insert into public.scheduled_messages (conversation_id, sender_id, body, send_at)
values (:'conv', '00000000-0000-4000-8000-0000000000b2', 'Due from a non-member', now() - interval '1 second')
returning id as due_bad \gset
select tst.ok(public.dispatch_due_scheduled_messages(50) = 1, 'scheduler delivers exactly the member-authored due message');
select tst.ok((select status from public.scheduled_messages where id = :'due_ok') = 'sent', 'delivered schedule is marked sent');
select tst.ok(exists (select 1 from public.messages m join public.scheduled_messages s on s.sent_message_id = m.id
                      where s.id = :'due_ok' and m.sender_id = '00000000-0000-4000-8000-0000000000b1'
                        and m.body = 'Due now from Alice'), 'delivered message is authored by the sender');
select tst.ok((select status from public.scheduled_messages where id = :'due_bad') = 'failed', 'non-member schedule fails safely');
select tst.ok(not exists (select 1 from public.messages where body = 'Due from a non-member'), 'failed schedule posts nothing');

-- ---------------------------------------------------------------------------
-- 19. Business labels: members read, owner/manager write, operators cannot write
--     (Bob b2 owns 'bob_shop' with operator Carol b3, from suite 03)
-- ---------------------------------------------------------------------------
select tst.as_trusted();
select id as biz from public.businesses where username = 'bob_shop' \gset
select tst.as_user('00000000-0000-4000-8000-0000000000b2');
select tst.expect_ok(format($$insert into public.business_labels (business_id, name, color) values (%L::uuid, 'VIP', '#16A34A')$$, :'biz'),
  'business owner creates a label');
select tst.expect_error(format($$insert into public.business_labels (business_id, name, color) values (%L::uuid, 'Bad', 'green')$$, :'biz'),
  'check constraint|violates', 'label colour must be a hex value');
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.ok(tst.count_q(format($$select id from public.business_labels where business_id = %L$$, :'biz')) = 1,
  'operator can read business labels');
select tst.ok(tst.count_q($$select id from public.business_labels where name = 'VIP'$$) = 1, 'label read is scoped to members');
select tst.expect_error(format($$insert into public.business_labels (business_id, name) values (%L::uuid, 'Sneaky')$$, :'biz'),
  'row-level security|violates', 'operator cannot create business labels');
select tst.as_user('00000000-0000-4000-8000-0000000000b1');
select tst.ok(tst.count_q($$select id from public.business_labels where name = 'VIP'$$) = 0, 'non-members cannot read business labels');

-- ---------------------------------------------------------------------------
-- 20. Push delivery bookkeeping (migration 0011): clients cannot mark pushes as sent
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000b3');
select tst.expect_error($$update public.notifications set push_sent_at = now()$$, 'permission denied',
  'users cannot mark notifications as pushed');
select tst.as_trusted();
select tst.ok(exists (select 1 from information_schema.columns where table_schema = 'public'
                      and table_name = 'notifications' and column_name = 'push_sent_at'),
  'push delivery column exists');
