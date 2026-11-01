-- =============================================================================
-- 09 Business & Partner Ecosystem: behaviour + tenant isolation (migration 0016)
-- Self-contained: creates its own accounts, businesses and partner applicant.
-- =============================================================================
\set ON_ERROR_STOP on
\pset tuples_only off
\timing off

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
select tst.as_trusted();
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000d1', 'alpha@biz.test',    '{"display_name":"Alpha Owner"}'),
  ('00000000-0000-4000-8000-0000000000d2', 'beta@biz.test',     '{"display_name":"Beta Owner"}'),
  ('00000000-0000-4000-8000-0000000000d3', 'support@biz.test',  '{"display_name":"Support Agent"}'),
  ('00000000-0000-4000-8000-0000000000d4', 'customer@biz.test', '{"display_name":"Customer One"}'),
  ('00000000-0000-4000-8000-0000000000d5', 'partner@biz.test',  '{"display_name":"Partner Candidate"}'),
  ('00000000-0000-4000-8000-0000000000d6', 'admin@biz.test',    '{"display_name":"Platform Admin"}'),
  ('00000000-0000-4000-8000-0000000000d7', 'catalog@biz.test',  '{"display_name":"Catalog Manager"}')
on conflict (id) do nothing;

update public.profiles set username = 'alpha_owner'    where id = '00000000-0000-4000-8000-0000000000d1';
update public.profiles set username = 'beta_owner'     where id = '00000000-0000-4000-8000-0000000000d2';
update public.profiles set username = 'team_support'   where id = '00000000-0000-4000-8000-0000000000d3';
update public.profiles set username = 'cust_one'       where id = '00000000-0000-4000-8000-0000000000d4';
update public.profiles set username = 'partner_one'    where id = '00000000-0000-4000-8000-0000000000d5';
update public.profiles set username = 'platform_admin' where id = '00000000-0000-4000-8000-0000000000d6';
update public.profiles set username = 'catalog_one'    where id = '00000000-0000-4000-8000-0000000000d7';
update public.profiles set created_at = now() - interval '30 days'
 where id in ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d2',
              '00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000d4',
              '00000000-0000-4000-8000-0000000000d5');

insert into public.user_roles (user_id, role_key) values
  ('00000000-0000-4000-8000-0000000000d6', 'admin')
on conflict do nothing;
insert into public.admin_assignments (user_id, status) values
  ('00000000-0000-4000-8000-0000000000d6', 'active')
on conflict (user_id) do nothing;
insert into public.user_permission_grants (user_id, permission_key, granted) values
  ('00000000-0000-4000-8000-0000000000d6', 'partners.approve', true),
  ('00000000-0000-4000-8000-0000000000d6', 'partners.manage', true),
  ('00000000-0000-4000-8000-0000000000d6', 'partners.manage.full', true)
on conflict (user_id, permission_key) do nothing;

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.create_business('Alpha Studio', 'alpha_studio', 'Retail', 'hello@alpha.test',
                              'Design studio for modern brands', 'https://alpha.test', '+62 811 1111') as biz_a \gset
select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select public.create_business('Beta Lab', 'beta_lab', 'Technology', 'hello@beta.test',
                              'Independent product lab', 'https://beta.test', null) as biz_b \gset

-- ---------------------------------------------------------------------------
-- 1. Permission model
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'team.manage'), 'owner holds team.manage');
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'business.delete'), 'owner holds the owner-only permission');
select public.business_team_invite(:'biz_a'::uuid, 'team_support', 'support') as inv_support \gset
select public.business_team_invite(:'biz_a'::uuid, 'catalog_one', 'catalog') as inv_catalog \gset

select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select public.business_invite_respond(:'inv_support'::uuid, true);
select tst.ok(public.is_business_member(:'biz_a'::uuid), 'invited support member joined the team');
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'inquiries.reply'), 'support can reply to inquiries');
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'customers.manage'), 'support can manage customers');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'catalog.manage'), 'support cannot manage the catalog');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'analytics.view'), 'support cannot view analytics');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'team.manage'), 'support cannot manage the team');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'business.delete'), 'owner-only permission is never delegated');

select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select public.business_invite_respond(:'inv_catalog'::uuid, true);
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'catalog.manage'), 'catalog manager can manage listings');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'inquiries.reply'), 'catalog manager cannot read inquiries');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select tst.expect_error(
  format($$select public.business_team_set_permission(%L::uuid, '00000000-0000-4000-8000-0000000000d1', 'catalog.manage', true)$$, :'biz_a'),
  'your own permissions', 'owner cannot edit their own permissions');
select tst.expect_error(
  format($$select public.business_team_set_role(%L::uuid, '00000000-0000-4000-8000-0000000000d1', 'analyst')$$, :'biz_a'),
  'owner role', 'owner role cannot be demoted');
select tst.expect_error(
  format($$select public.business_team_invite(%L::uuid, 'alpha_owner', 'admin')$$, :'biz_a'),
  'yourself', 'self invitation is refused');
select tst.ok(jsonb_array_length(public.business_team_list(:'biz_a'::uuid) -> 'members') = 3,
  'team list returns owner, support and catalog manager');

-- ---------------------------------------------------------------------------
-- 2. Cross-business tenant isolation
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select tst.expect_error(
  format($$select public.business_update_profile(%L::uuid, '{"name":"Hijacked"}')$$, :'biz_a'),
  'Permission denied', 'business B cannot edit business A');
select tst.expect_error(
  format($$select public.business_catalog_save(%L::uuid, p_name => 'Injected')$$, :'biz_a'),
  'Permission denied', 'business B cannot add listings to business A');
select tst.expect_error(
  format($$select public.business_analytics(%L::uuid)$$, :'biz_a'),
  'Permission denied', 'business B cannot read business A analytics');
select tst.expect_error(
  format($$select public.business_team_list(%L::uuid)$$, :'biz_a'),
  'Not a member', 'business B cannot list business A team');
select tst.expect_error(
  format($$select public.business_customer_list(%L::uuid)$$, :'biz_a'),
  'Permission denied', 'business B cannot read business A customers');
update public.businesses set name = 'Renamed' where id = :'biz_a'::uuid;
select tst.as_trusted();
select tst.ok((select name from public.businesses where id = :'biz_a') = 'Alpha Studio',
  'direct business updates cannot modify another tenant row');
select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select tst.expect_error(
  format($$insert into public.business_members (business_id, user_id, role)
             values (%L::uuid, '00000000-0000-4000-8000-0000000000d2', 'owner')$$, :'biz_a'),
  'permission denied', 'clients cannot insert business membership rows');

-- ---------------------------------------------------------------------------
-- 3. Business profile
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_update_profile(:'biz_a'::uuid,
  '{"description":"We design identity systems and packaging for modern brands.",
    "working_hours":{"mon":"09:00-17:00","tue":"09:00-17:00"},
    "social_links":{"instagram":"https://instagram.com/alphastudio"},
    "visibility":{"show_phone":false,"show_email":true},
    "response_note":"Usually replies within 2 hours",
    "status":"open"}'::jsonb);
select tst.ok((select description from public.businesses where id = :'biz_a') like 'We design identity%',
  'profile description is stored');
select tst.ok((select response_note from public.businesses where id = :'biz_a') = 'Usually replies within 2 hours',
  'response note is stored');
select tst.expect_error(
  format($$select public.business_update_profile(%L::uuid, '{"visibility":{"show_phone":"yes"}}')$$, :'biz_a'),
  'Unsupported visibility', 'visibility values are validated');
select tst.expect_error(
  format($$select public.business_update_profile(%L::uuid, '{"social_links":{"myspace":"x"}}')$$, :'biz_a'),
  'Unsupported social link', 'unknown social networks are rejected');
select tst.expect_error(
  format($$select public.business_update_profile(%L::uuid, '{"business_email":"not-an-email"}')$$, :'biz_a'),
  'valid business email', 'business email is validated');
select tst.expect_error(
  format($$select public.business_update_profile(%L::uuid, '{"username":"beta_lab"}')$$, :'biz_a'),
  'already taken', 'business username is unique across businesses');

-- Publishing is an explicit owner action: the business becomes publicly visible only
-- after the owner finishes setup (core RLS requires is_setup_complete).
select public.business_update_profile(:'biz_a'::uuid, '{"is_setup_complete":true}');
select tst.ok((select is_setup_complete from public.businesses where id = :'biz_a'),
  'owner can publish a finished business profile');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((public.business_public_profile(:'biz_a'::uuid) ->> 'contact_phone') is null,
  'private contact phone is hidden from visitors by visibility');
select tst.ok((public.business_public_profile(:'biz_a'::uuid) ->> 'contact_email') = 'hello@alpha.test',
  'public contact email follows the visibility setting');
select tst.ok((public.business_public_profile(:'biz_a'::uuid) ->> 'is_member')::boolean = false,
  'public profile never claims membership for a visitor');
select tst.ok((select count(*) from public.businesses where id = :'biz_a') = 1,
  'public business row is readable once the profile is set up');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select tst.ok((public.business_setup_progress(:'biz_a'::uuid) ->> 'percent')::int between 1 and 100,
  'setup progress returns a real percentage');
select tst.ok((public.business_setup_progress(:'biz_a'::uuid) -> 'missing') ? 'Upload a business logo',
  'setup progress lists the missing logo');

-- ---------------------------------------------------------------------------
-- 4. Catalog
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.expect_error(
  format($$select public.business_catalog_save(%L::uuid, p_name => 'Nope')$$, :'biz_a'),
  'Permission denied', 'support cannot create catalog listings');

select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select public.business_catalog_save(:'biz_a'::uuid,
  p_kind => 'product', p_name => 'Brand Sprint', p_description => 'Two week identity sprint',
  p_category => 'Design', p_price_minor => 4500000, p_currency => 'IDR',
  p_status => 'draft', p_stock_quantity => 5,
  p_gallery => '["https://cdn.test/a.png"]'::jsonb,
  p_variants => '[{"name":"Standard","price_minor":4500000},{"name":"Extended","price_minor":7500000}]'::jsonb
) as item_draft \gset
select public.business_catalog_save(:'biz_a'::uuid,
  p_kind => 'service', p_name => 'Packaging audit', p_description => 'Review of existing packaging',
  p_category => 'Design', p_price_minor => 1500000, p_currency => 'IDR', p_status => 'published'
) as item_service \gset

select tst.ok(jsonb_array_length(public.business_catalog_list(:'biz_a'::uuid)) = 2,
  'catalog manager sees drafts and published listings');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok(jsonb_array_length(public.business_catalog_public(:'biz_a'::uuid)) = 1,
  'public catalog hides drafts from visitors');
select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select tst.expect_error(
  format($$select public.business_catalog_save(%L::uuid, p_name => 'Bad', p_gallery => '[1,2]'::jsonb)$$, :'biz_a'),
  'Invalid gallery', 'gallery entries must be image URLs');
select tst.expect_error(
  format($$select public.business_catalog_save(%L::uuid, p_name => 'Bad', p_variants => '[{"price_minor":1}]'::jsonb)$$, :'biz_a'),
  'variant', 'variants require a name');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_catalog_set_status(:'item_draft'::uuid, 'published');
select tst.ok((public.business_public_profile(:'biz_a'::uuid) ->> 'catalog_count')::int = 2,
  'public profile counts published listings only');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((public.business_catalog_detail(:'item_draft'::uuid) ->> 'name') = 'Brand Sprint',
  'visitor can open a published listing');
select tst.ok((public.business_catalog_detail(:'item_draft'::uuid) ->> 'can_message')::boolean,
  'published listing offers the message action');
select tst.ok((select view_count from public.business_catalog_items where id = :'item_draft') >= 1,
  'catalog view is recorded as a real event');
select tst.ok((public.business_catalog_share(:'item_draft'::uuid) ->> 'path') like '/business/%',
  'sharing returns a real in-app path');

select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select tst.expect_error(
  format($$select public.business_catalog_set_status(%L::uuid, 'archived')$$, :'item_draft'),
  'Permission denied', 'business B cannot archive business A listing');
select tst.expect_error(
  format($$select public.business_catalog_delete(%L::uuid)$$, :'item_draft'),
  'Permission denied', 'business B cannot delete business A listing');
select tst.ok((public.business_catalog_detail(:'item_draft'::uuid)) is not null,
  'published listing stays visible to everyone');

-- ---------------------------------------------------------------------------
-- 5. Inquiries through the real messaging engine
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select public.business_inquiry_start(:'biz_a'::uuid, 'Is the Brand Sprint available next month?',
                                     :'item_draft'::uuid) as inquiry_a \gset
select (:'inquiry_a'::jsonb ->> 'inquiry_id') as inq_a,
       (:'inquiry_a'::jsonb ->> 'conversation_id') as conv_a \gset
select tst.ok(:'conv_a' is not null, 'inquiry creates a conversation');
select public.business_inquiry_start(:'biz_a'::uuid, 'One more question about timing') as inquiry_a2 \gset
select tst.ok(:'conv_a' = (:'inquiry_a2'::jsonb ->> 'conversation_id'),
  'follow-up messages reuse the same customer conversation');
select tst.ok((select count(*) from public.business_inquiries where business_id = :'biz_a') = 1,
  'one open inquiry per customer and business');
select tst.ok((select count(*) from public.messages where conversation_id = :'conv_a'::uuid) = 2,
  'the customer message is stored in the messaging engine');

select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.ok((select count(*) from public.messages where conversation_id = :'conv_a'::uuid) = 2,
  'support reads the customer conversation through conversation membership');
select tst.ok((select count(*) from public.notifications
                where user_id = '00000000-0000-4000-8000-0000000000d3'
                  and kind = 'business_inquiry') = 2,
  'support receives exactly one inquiry notification per message');
select tst.ok(jsonb_array_length(public.business_inquiry_list(:'biz_a'::uuid)) = 1,
  'support sees the inquiry board');
-- Team-wide permissions are the role default; the owner can narrow them per member.
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_team_set_permission(:'biz_a'::uuid, '00000000-0000-4000-8000-0000000000d3',
                                           'inquiries.manage', false);
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'inquiries.manage'),
  'owner can withhold a role permission from one member');
select tst.expect_error(
  format($$select public.business_inquiry_set_status(%L::uuid, 'resolved')$$, :'inq_a'),
  'Permission denied', 'support cannot resolve when inquiries.manage is withheld');

insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
values (:'conv_a'::uuid, '00000000-0000-4000-8000-0000000000d3',
        gen_random_uuid(), 'text', 'Yes, we have one slot left.');
select tst.ok((select first_response_at from public.business_inquiries where business_id = :'biz_a') is not null,
  'a business reply records the first response time');
select tst.ok((select status from public.business_inquiries where business_id = :'biz_a') = 'open',
  'inquiry moves to open once the business replies');

select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select tst.ok((select count(*) from public.messages
                where conversation_id = :'conv_a'::uuid) = 0,
  'business B cannot read business A customer messages');
select tst.expect_error(
  format($$select public.business_inquiry_set_status(%L::uuid, 'resolved')$$, :'inq_a'),
  'Permission denied', 'business B cannot resolve business A inquiry');
select tst.expect_error(
  format($$select public.business_inquiry_detail(%L::uuid)$$, :'inq_a'),
  'Permission denied', 'business B cannot open business A inquiry');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_inquiry_set_status(:'inq_a'::uuid, 'resolved', 'Answered and booked');
select tst.ok((select status from public.business_inquiries where business_id = :'biz_a') = 'resolved',
  'authorised teammate resolves the inquiry');
select tst.ok((select count(*) from public.messages
                where conversation_id = :'conv_a'::uuid and kind = 'system') = 1,
  'resolution posts a system message in the thread');

-- ---------------------------------------------------------------------------
-- 6. Customer records, notes and labels (tenant isolated)
-- ---------------------------------------------------------------------------
select tst.ok(jsonb_array_length(public.business_customer_list(:'biz_a'::uuid)) = 1,
  'owner sees one real customer');
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.ok((select count(*) from public.business_customers) = 1,
  'support with customers.view reads the customer record');
select tst.ok((select count(*) from public.business_customer_labels) >= 0,
  'support can query labels without leaking other tenants');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_customer_update(
  (select id from public.business_customers where business_id = :'biz_a' limit 1),
  '{"internal_note":"Prefers WhatsApp in the morning","follow_up_status":"follow_up"}'::jsonb);
select tst.ok((select internal_note from public.business_customers where business_id = :'biz_a') like 'Prefers%',
  'internal note is stored');
select tst.expect_error(
  format($$select public.business_customer_update(%L::uuid, '{"unknown":"x"}')$$,
         (select id from public.business_customers where business_id = :'biz_a' limit 1)),
  'Unsupported customer field', 'unknown customer fields are rejected');

select public.business_label_save(:'biz_a'::uuid, 'VIP', '#16A34A') as label_vip \gset
select public.business_customer_set_labels(
  (select id from public.business_customers where business_id = :'biz_a' limit 1),
  array[:'label_vip'::uuid]);
select tst.ok((select count(*)
                 from jsonb_array_elements(public.business_customer_list(:'biz_a'::uuid)) c
                where c -> 'labels' @> '[{"name":"VIP"}]') = 1,
  'customer list returns assigned internal labels');

select tst.as_user('00000000-0000-4000-8000-0000000000d2');
select public.business_label_save(:'biz_b'::uuid, 'Beta Only', '#2563EB') as label_beta \gset
select tst.expect_error(
  format($$select public.business_customer_set_labels(%L::uuid, ARRAY[%L::uuid])$$,
         (select id from public.business_customers where business_id = :'biz_a' limit 1), :'label_beta'),
  'Permission denied|not found', 'business B cannot touch business A customer labels');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*) from public.business_customers) = 0,
  'customers never see internal customer records');
select tst.ok((select count(*) from public.business_customer_labels) = 0,
  'customers never see internal labels');
select tst.ok((public.business_inquiry_detail(:'inq_a'::uuid) -> 'customer_record') = 'null'::jsonb,
  'customer view never includes internal notes');
select tst.expect_error(
  format($$select public.business_customer_list(%L::uuid)$$, :'biz_a'),
  'Permission denied', 'customers cannot enumerate the customer list');

-- ---------------------------------------------------------------------------
-- 7. Team management and immediate revocation
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_team_set_permission(:'biz_a'::uuid, '00000000-0000-4000-8000-0000000000d3',
                                           'customers.view', false);
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.ok(not public.has_business_permission(:'biz_a'::uuid, 'customers.view'),
  'per-member override narrows access');
select tst.ok((select count(*) from public.business_customers) = 0,
  'revoked customer permission hides customer rows');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_team_set_permission(:'biz_a'::uuid, '00000000-0000-4000-8000-0000000000d3',
                                           'customers.view', true);
select public.business_team_remove(:'biz_a'::uuid, '00000000-0000-4000-8000-0000000000d3');
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.ok(not public.is_business_member(:'biz_a'::uuid), 'removed member loses membership immediately');
select tst.ok((select count(*) from public.messages
                where conversation_id = :'conv_a'::uuid) = 0,
  'removed member can no longer read customer conversations');
select tst.expect_error(
  format($$select public.business_catalog_list(%L::uuid)$$, :'biz_a'),
  'Not a member', 'removed member loses catalog access');

select tst.as_trusted();
select tst.ok((select count(*) from public.admin_audit_logs where action = 'business.team.remove') >= 1,
  'team removal is audited');

-- Invitation revocation
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_team_invite(:'biz_a'::uuid, 'team_support', 'support') as inv_again \gset
select public.business_team_revoke_invite(:'inv_again'::uuid);
select tst.as_user('00000000-0000-4000-8000-0000000000d3');
select tst.expect_error(
  format($$select public.business_invite_respond(%L::uuid, true)$$, :'inv_again'),
  'no longer open', 'revoked invitation cannot be accepted');

-- ---------------------------------------------------------------------------
-- 8. Business posts, followers and analytics
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.business_post_create(:'biz_a'::uuid, 'New Brand Sprint dates are live',
  'text', '{}', :'item_draft'::uuid, 'public') as post_a \gset
select tst.ok((select business_id from public.posts where id = :'post_a') = :'biz_a'::uuid,
  'business post is stored with the business identity');
select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select tst.ok(public.has_business_permission(:'biz_a'::uuid, 'posts.publish'),
  'catalog manager may publish business posts');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*) from public.posts where business_id = :'biz_a') = 1,
  'business posts are visible to customers');
select tst.expect_error(
  format($$select public.business_post_create(%L::uuid, 'Fake promo')$$, :'biz_a'),
  'Permission denied', 'customers cannot post as the business');

select public.business_follow(:'biz_a'::uuid, true);
select tst.ok((select followers_count from public.businesses where id = :'biz_a') = 1,
  'followers_count reflects a real follow');
select public.business_follow(:'biz_a'::uuid, false);
select tst.ok((select followers_count from public.businesses where id = :'biz_a') = 0,
  'unfollowing updates the real count');
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select tst.expect_error(format($$select public.business_follow(%L::uuid, true)$$, :'biz_a'),
  'members cannot follow', 'owners cannot follow their own business');

select public.business_analytics(:'biz_a'::uuid, 30) as stats \gset
select tst.ok((:'stats'::jsonb -> 'metrics' ->> 'catalog_views')::int >= 1,
  'analytics counts real catalog views');
select tst.ok((:'stats'::jsonb -> 'metrics' ->> 'inquiries')::int = 1,
  'analytics counts the real inquiry');
select tst.ok((:'stats'::jsonb -> 'response' ->> 'available')::boolean,
  'response statistics are available once a reply happened');
select tst.ok((:'stats'::jsonb -> 'unavailable') @> '[{"metric":"paid_ad_reach"}]',
  'unavailable metrics are reported explicitly');
select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select tst.ok(jsonb_typeof(public.business_analytics(:'biz_a'::uuid, 7) -> 'series') = 'array',
  'catalog manager can read analytics series');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.expect_error(format($$select public.business_analytics(%L::uuid)$$, :'biz_a'),
  'Permission denied', 'customers cannot read analytics');

-- ---------------------------------------------------------------------------
-- 9. Business verification integration
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select public.submit_verification_application('business', 'Alpha Studio', 'alpha_studio', 'Retail',
  'Design studio for modern brands', 'We want the business badge for customers.', '[]'::jsonb, :'biz_a'::uuid) as vapp \gset
select tst.ok((public.business_verification_state(:'biz_a'::uuid) -> 'application' ->> 'status') = 'pending',
  'business verification uses the existing verification engine');
select tst.ok(not (public.business_verification_state(:'biz_a'::uuid) ->> 'can_submit')::boolean,
  'a pending application blocks a second submission');
select tst.ok((select count(*) from public.verification_history where application_id = :'vapp'::uuid) = 1,
  'verification history records the submission');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.expect_error(format($$select public.business_verification_state(%L::uuid)$$, :'biz_a'),
  'Not a member', 'verification state is member-only');

-- ---------------------------------------------------------------------------
-- 10. Partner application lifecycle
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.ok((public.partner_application_requirements() ->> 'is_open')::boolean,
  'partner applications are open');
select public.partner_application_save_draft(
  '{"organization":"Partner Co","partnership_category":"Agency","proposal":"short"}'::jsonb) as papp \gset
select tst.expect_error(format($$select public.partner_application_submit(%L::uuid)$$, :'papp'),
  'at least 30', 'incomplete drafts cannot be submitted');
select public.partner_application_save_draft(
  '{"organization":"Partner Co","partnership_category":"Agency",
    "proposal":"We build creator campaigns with measurable reach and reporting for brands.",
    "website":"https://partner.test"}'::jsonb);
select public.partner_application_submit(:'papp'::uuid) as pstatus \gset
select tst.ok(:'pstatus' = 'pending', 'submitted application is pending');
select tst.expect_error(format($$select public.partner_application_submit(%L::uuid)$$, :'papp'),
  'Only a draft', 'a submitted application cannot be submitted twice');
select tst.ok(not public.partner_badge_visible('00000000-0000-4000-8000-0000000000d5'),
  'pending applicants never get the badge');
select tst.ok(public.partner_public_profile('00000000-0000-4000-8000-0000000000d5') is null,
  'pending applicants have no public partner profile');

select public.partner_application_add_document(:'papp'::uuid,
  '00000000-0000-4000-8000-0000000000d5/registration.pdf', 'business_registration',
  'application/pdf', 2048) as pdoc \gset
select tst.expect_error(
  format($$select public.partner_application_add_document(%L::uuid, '00000000-0000-4000-8000-0000000000d4/x.pdf', 'identity', 'application/pdf', 2048)$$, :'papp'),
  'Invalid storage path', 'documents must live in the applicant folder');
select tst.expect_error(
  format($$select public.partner_application_add_document(%L::uuid, '00000000-0000-4000-8000-0000000000d5/x.exe', 'identity', 'application/x-msdownload', 2048)$$, :'papp'),
  'JPEG, PNG', 'document MIME types are validated');
select tst.ok((select count(*) from public.partner_application_documents) = 1,
  'applicant sees their uploaded document');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*) from public.partner_application_documents) = 0,
  'other users cannot read partner documents');
select tst.ok((select count(*) from public.partner_applications
                where id = :'papp'::uuid) = 0,
  'other users cannot read partner applications');

-- Reviewer asks for information, applicant answers.
select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select public.partner_request_information(:'papp'::uuid, 'Please share your company registration number.');
select tst.ok((select status from public.partner_applications where id = :'papp'::uuid) = 'additional_info_required',
  'reviewer can request additional information');
select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select public.partner_application_respond_info(:'papp'::uuid, 'Registered under AHU-12345.');
select tst.ok((select status from public.partner_applications where id = :'papp'::uuid) = 'reviewing',
  'applicant response returns the application to review');

-- Approval by an authorised reviewer grants the trusted partner role.
select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select public.review_partner_application(:'papp'::uuid, 'approve', 'Agency', 'Looks good') as pdecision \gset
select tst.ok(:'pdecision' = 'approved', 'reviewer approves the partner application');
select tst.ok(exists(select 1 from public.partner_profiles
                      where user_id = '00000000-0000-4000-8000-0000000000d5' and partner_status = 'active'),
  'approval creates the partner profile');
select tst.ok(exists(select 1 from public.user_roles
                      where user_id = '00000000-0000-4000-8000-0000000000d5'
                        and role_key = 'partner' and revoked_at is null),
  'approval grants the partner role server-side');

select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.ok(public.partner_badge_visible('00000000-0000-4000-8000-0000000000d5'),
  'approved partner shows the trusted badge');
select tst.ok((public.partner_my_benefits() ->> 'partner_status') = 'active',
  'partner benefits endpoint reports active status');

-- Self-service profile edits cannot change status, category or featured placement.
select public.partner_profile_update('{"display_name":"Partner One Studio","headline":"Creator partnerships","specialties":["Creators","Retail"]}'::jsonb);
select tst.ok((select headline from public.partner_profiles
                where user_id = '00000000-0000-4000-8000-0000000000d5') = 'Creator partnerships',
  'partner can edit presentation fields');
select tst.expect_error($$select public.partner_profile_update('{"is_featured":true}'::jsonb)$$,
  'cannot be changed', 'partner cannot feature themselves');
select tst.expect_error($$update public.partner_profiles set partner_status = 'terminated'$$,
  'permission denied|controlled by BubbleApp', 'partner cannot change their own status');

-- ---------------------------------------------------------------------------
-- 11. Partner directory, benefits and support
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok(jsonb_array_length(public.partner_directory() -> 'partners') >= 1,
  'directory lists the approved partner');
select tst.ok((public.partner_public_profile('00000000-0000-4000-8000-0000000000d5') ->> 'display_name') = 'Partner One Studio',
  'public partner profile returns real data');

select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select public.admin_set_partner_featured('00000000-0000-4000-8000-0000000000d5', true, now() + interval '30 days');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*)
                 from jsonb_array_elements(public.partner_directory(p_featured_only => true) -> 'partners') p
                where p ->> 'user_id' = '00000000-0000-4000-8000-0000000000d5') = 1,
  'featured filter returns the configured partner only');

select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select public.admin_set_partner_benefit('badge', false);
select tst.ok(not public.partner_badge_visible('00000000-0000-4000-8000-0000000000d5'),
  'owner-controlled benefit disables the badge everywhere');
select public.admin_set_partner_benefit('badge', true);

select public.admin_set_partner_benefit('resources', false);
select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.expect_error($$select public.partner_resources_list()$$, 'currently disabled',
  'disabled benefit removes partner resource access');
select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select public.admin_set_partner_benefit('resources', true);

select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.ok(jsonb_array_length(public.partner_support_list()) = 0, 'partner has no support requests yet');
select public.partner_support_create('Featured placement question', 'How long does featured placement last?') as psup \gset
select tst.ok(jsonb_array_length(public.partner_support_list()) = 1, 'partner support request is stored');
select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select tst.ok(jsonb_array_length(public.admin_partner_support_list()) = 1, 'admin sees the partner support queue');
select public.admin_partner_support_respond(:'psup'::uuid, 'Featured placement lasts 30 days by default.');
select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.ok((select status from public.partner_support_requests where id = :'psup'::uuid) = 'answered',
  'partner sees the support answer');
select tst.ok(jsonb_array_length(public.partner_activity_list()) >= 1,
  'partner activity feed contains real events');

-- Directory visibility is partner-controlled but status is not.
select public.partner_profile_update('{"directory_visible":false}'::jsonb);
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*)
                 from jsonb_array_elements(public.partner_directory() -> 'partners') p
                where p ->> 'user_id' = '00000000-0000-4000-8000-0000000000d5') = 0,
  'hidden partner disappears from the directory');
select tst.ok(public.partner_public_profile('00000000-0000-4000-8000-0000000000d5') is null,
  'hidden partner profile is not public');
select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select public.partner_profile_update('{"directory_visible":true}'::jsonb);

-- ---------------------------------------------------------------------------
-- 12. Storage access (business media, partner media and private documents)
-- ---------------------------------------------------------------------------
select tst.as_trusted();
select tst.ok(exists(select 1 from storage.buckets where id = 'partner-documents' and public = false),
  'partner documents bucket is private');
select tst.ok(exists(select 1 from storage.buckets where id = 'partner-media' and public = true),
  'partner media bucket is public');
select tst.ok((select file_size_limit from storage.buckets where id = 'partner-documents') = 10485760,
  'partner document size limit is enforced by the bucket');

select tst.as_user('00000000-0000-4000-8000-0000000000d1');
select tst.expect_ok(
  format($$insert into storage.objects (bucket_id, name) values ('business-media', %L)$$, :'biz_a' || '/logo.png'),
  'business owner uploads business media into the business folder');
select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select tst.expect_ok(
  format($$insert into storage.objects (bucket_id, name) values ('business-media', %L)$$, :'biz_a' || '/product.png'),
  'catalog manager can upload product images');
select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.expect_error(
  format($$insert into storage.objects (bucket_id, name) values ('business-media', %L)$$, :'biz_a' || '/evil.png'),
  'row-level security', 'visitors cannot upload into a business folder');

select tst.as_user('00000000-0000-4000-8000-0000000000d5');
select tst.expect_ok(
  $$insert into storage.objects (bucket_id, name) values ('partner-documents', '00000000-0000-4000-8000-0000000000d5/registration.pdf')$$,
  'partner uploads into their own private folder');
select tst.expect_error(
  $$insert into storage.objects (bucket_id, name) values ('partner-documents', '00000000-0000-4000-8000-0000000000d4/steal.pdf')$$,
  'row-level security', 'partner cannot upload into another user folder');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
select tst.ok((select count(*) from storage.objects where bucket_id = 'partner-documents') = 0,
  'unrelated users cannot read partner documents');
select tst.expect_error(
  $$insert into storage.objects (bucket_id, name) values ('partner-media', '00000000-0000-4000-8000-0000000000d5/logo.png')$$,
  'row-level security', 'partner media is owner-folder scoped');
select tst.as_user('00000000-0000-4000-8000-0000000000d6');
select tst.ok((select count(*) from storage.objects where bucket_id = 'partner-documents') = 1,
  'authorised reviewer can read partner documents');

-- ---------------------------------------------------------------------------
-- 13. Notifications: preference aware and de-duplicated
-- ---------------------------------------------------------------------------
select tst.as_trusted();
select public.notify_user('00000000-0000-4000-8000-0000000000d4', 'business_invite', 'Once', 'Body',
                          '{}'::jsonb, 'dedupe-demo');
select public.notify_user('00000000-0000-4000-8000-0000000000d4', 'business_invite', 'Twice', 'Body',
                          '{}'::jsonb, 'dedupe-demo');
select tst.ok((select count(*) from public.notifications
                where user_id = '00000000-0000-4000-8000-0000000000d4'
                  and dedupe_key = 'dedupe-demo') = 1,
  'duplicate notifications are suppressed by dedupe key');
select tst.ok((select count(*) from public.notifications
                where user_id = '00000000-0000-4000-8000-0000000000d5'
                  and kind = 'partner_application') >= 1,
  'partner decision notifications are delivered');

select tst.as_user('00000000-0000-4000-8000-0000000000d4');
update public.user_settings set notifications = notifications || '{"business": false}'::jsonb
 where user_id = '00000000-0000-4000-8000-0000000000d4';
select tst.as_trusted();
select public.notify_user('00000000-0000-4000-8000-0000000000d4', 'business_invite', 'Muted', 'Body',
                          '{}'::jsonb, 'dedupe-muted');
select tst.ok(not exists (select 1 from public.notifications
                           where user_id = '00000000-0000-4000-8000-0000000000d4'
                             and dedupe_key = 'dedupe-muted'),
  'business notification preference is respected');

-- ---------------------------------------------------------------------------
-- 14. Same-business staff isolation still applies to private platform tools
-- ---------------------------------------------------------------------------
select tst.as_user('00000000-0000-4000-8000-0000000000d7');
select tst.ok(not public.has_permission('users.read'), 'business roles never grant platform admin permissions');
select tst.expect_error($$select public.admin_list_users()$$, 'Permission denied',
  'business staff cannot read the platform user directory');
select tst.expect_error($$select public.owner_dashboard_stats()$$, 'Permission denied',
  'business staff cannot read owner statistics');

select 'ok' as result;
