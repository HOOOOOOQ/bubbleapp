-- =============================================================================
-- BubbleApp :: 0008 remaining RLS, dashboards, presence, storage, realtime
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Remaining policies for core tables (0001 enabled RLS but granted nothing yet)
-- ---------------------------------------------------------------------------
grant select on public.businesses to authenticated;
grant update (name, logo_url, cover_url, description, category, website, business_email,
              business_phone, address, location, working_hours, greeting_message, away_message)
  on public.businesses to authenticated;
grant select on public.business_members to authenticated;
grant select on public.account_modes to authenticated;
grant select, update (theme, language, privacy, notifications) on public.user_settings to authenticated;
grant select, insert, update, delete on public.devices to authenticated;

-- Business profiles are public once set up; only members may edit (owner/manager).
create policy businesses_select on public.businesses for select to authenticated using (
  is_setup_complete or public.is_business_member(id)
);
create policy businesses_update_managers on public.businesses for update to authenticated
  using (public.is_business_member(id, array['owner', 'manager']))
  with check (public.is_business_member(id, array['owner', 'manager']));

create policy business_members_select on public.business_members for select to authenticated using (
  user_id = auth.uid() or public.is_business_member(business_id)
);

create policy account_modes_own on public.account_modes for select to authenticated using (user_id = auth.uid());

create policy user_settings_own_select on public.user_settings for select to authenticated using (user_id = auth.uid());
create policy user_settings_own_update on public.user_settings for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy devices_own on public.devices for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Presence (privacy-aware last seen is enforced in the app; column is not client-writable)
-- ---------------------------------------------------------------------------
create or replace function public.touch_presence()
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles set last_seen_at = now() where id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Owner / analytics dashboards (live PostgreSQL statistics)
-- ---------------------------------------------------------------------------
create or replace function public.owner_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('analytics.read') then
    raise exception 'Permission denied: analytics.read' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'total_users',        (select count(*) from public.profiles),
    'active_users_30d',   (select count(*) from public.profiles where last_seen_at >= now() - interval '30 days'),
    'online_users',       (select count(*) from public.profiles where last_seen_at >= now() - interval '5 minutes'),
    'personal_accounts',  (select count(*) from public.account_modes where mode = 'personal'),
    'business_accounts',  (select count(*) from public.businesses where is_setup_complete),
    'verified_users',     (select count(*) from public.profiles where is_verified),
    'verified_businesses',(select count(*) from public.businesses where is_verified),
    'verified_channels',  (select count(*) from public.channels where is_verified),
    'total_partners',     (select count(*) from public.partner_profiles),
    'active_partners',    (select count(*) from public.partner_profiles where partner_status = 'active'),
    'total_administrators',(select count(*) from public.admin_assignments where status = 'active'),
    'total_channels',     (select count(*) from public.channels),
    'total_subscribers',  (select count(*) from public.channel_subscribers where is_active),
    'total_messages',     (select count(*) from public.messages),
    'total_communities',  (select count(*) from public.communities),
    'total_reports',      (select count(*) from public.reports),
    'open_reports',       (select count(*) from public.reports where status in ('open', 'reviewing', 'escalated')),
    'pending_verifications', (select count(*) from public.verification_applications
                              where status in ('pending', 'under_review', 'info_requested')),
    'pending_partner_applications', (select count(*) from public.partner_applications
                                     where status in ('pending', 'reviewing')),
    'premium_active',     (select count(*) from public.premium_subscriptions
                           where status = 'active' and ends_at > now()),
    'generated_at',       now()
  );
end;
$$;

-- Staff user directory (includes email; never exposed through the profiles table).
create or replace function public.admin_list_users(
  p_query text default null,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id uuid,
  email text,
  username text,
  display_name text,
  account_status text,
  is_verified boolean,
  created_at timestamptz,
  last_seen_at timestamptz,
  roles text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('users.read') then
    raise exception 'Permission denied: users.read' using errcode = '42501';
  end if;
  return query
    select p.id, p.email, p.username, p.display_name, p.account_status, p.is_verified,
           p.created_at, p.last_seen_at,
           coalesce((select array_agg(ur.role_key order by ur.role_key)
                     from public.user_roles ur
                     where ur.user_id = p.id and ur.revoked_at is null), '{}')
    from public.profiles p
    where (p_query is null or p_query = ''
           or p.username ilike '%' || p_query || '%'
           or p.display_name ilike '%' || p_query || '%'
           or p.email ilike '%' || p_query || '%')
      and (p_status is null or p.account_status = p_status)
    order by p.created_at desc
    limit least(greatest(p_limit, 1), 200)
    offset greatest(p_offset, 0);
end;
$$;

-- The caller's effective access, used by the app to decide which dashboards to show.
create or replace function public.my_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'is_owner', public.is_owner(),
    'roles', coalesce((select jsonb_agg(ur.role_key) from public.user_roles ur
                       where ur.user_id = auth.uid() and ur.revoked_at is null), '[]'::jsonb),
    'is_admin', exists (select 1 from public.admin_assignments a where a.user_id = auth.uid() and a.status = 'active'),
    'permissions', coalesce((
      select jsonb_agg(p.key order by p.key)
      from public.permissions p
      where p.scope = 'platform' and public.has_permission(p.key)
    ), '[]'::jsonb),
    'partner_permissions', coalesce((
      select jsonb_agg(p.key order by p.key)
      from public.permissions p
      where p.scope = 'partner' and public.has_permission(p.key)
    ), '[]'::jsonb),
    'rank', public.current_rank(auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Function execute grants.
-- Every public function is executable by authenticated users (RLS policies call
-- helpers), but each sensitive one checks authorization itself. Internal-only
-- helpers, trigger functions and privileged writers are revoked below.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;

-- Trigger functions are never callable through the API.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from authenticated', r.sig);
  end loop;
end $$;

-- Internal writers: callable only from other SECURITY DEFINER functions or trusted context.
revoke execute on function public.enroll_mandatory_subscriptions(uuid) from authenticated;
revoke execute on function public.bootstrap_owner(text) from authenticated;
revoke execute on function public.write_audit(text, text, text, jsonb) from authenticated;
revoke execute on function public.apply_verification_badge(public.verification_applications, boolean) from authenticated;
revoke execute on function public.grant_role(uuid, text, uuid) from authenticated;
revoke execute on function public.revoke_role(uuid, text, uuid) from authenticated;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb) from authenticated;
revoke execute on function public.reject_audit_mutation() from authenticated;
revoke execute on function public.guard_owner_role() from authenticated;

-- ---------------------------------------------------------------------------
-- Storage buckets. Limits and MIME allow-lists are enforced by Supabase Storage.
-- Private buckets are read only through signed URLs issued to authorised users.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',              'avatars',              true,  5242880,
     array['image/jpeg','image/png','image/webp']),
  ('profile-covers',       'profile-covers',       true,  10485760,
     array['image/jpeg','image/png','image/webp']),
  ('business-media',       'business-media',       true,  20971520,
     array['image/jpeg','image/png','image/webp','video/mp4']),
  ('chat-media',           'chat-media',           false, 104857600,
     array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','audio/mp4','audio/aac','audio/ogg','audio/mpeg','audio/wav','application/octet-stream']),
  ('chat-attachments',     'chat-attachments',     false, 104857600,
     array['application/pdf','application/zip','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']),
  ('story-media',          'story-media',          false, 104857600,
     array['image/jpeg','image/png','image/webp','video/mp4']),
  ('channel-media',        'channel-media',        false, 104857600,
     array['image/jpeg','image/png','image/webp','video/mp4','application/pdf']),
  ('verification-documents','verification-documents', false, 20971520,
     array['image/jpeg','image/png','application/pdf']),
  ('wallpapers',           'wallpapers',           false, 10485760,
     array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Remove the earlier bucket name if a previous draft created it (no production data exists for it).
delete from storage.buckets where id = 'verification-docs'
  and not exists (select 1 from storage.objects where bucket_id = 'verification-docs');

-- Helper: folder segment as uuid, or null when it is not a valid uuid (never raises).
create or replace function public.storage_folder_uuid(p_name text)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
declare
  v_seg text := (string_to_array(p_name, '/'))[1];
begin
  return v_seg::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;
revoke execute on function public.storage_folder_uuid(text) from public, anon;
grant execute on function public.storage_folder_uuid(text) to authenticated;

-- Drops every policy previously created on storage.objects for BubbleApp buckets.
do $$
declare
  r record;
begin
  for r in select policyname from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and policyname like 'bubble_%'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

-- avatars / profile-covers: public read; write only inside the owner's {uid}/ folder.
create policy bubble_public_media_read on storage.objects for select to anon, authenticated
  using (bucket_id in ('avatars', 'profile-covers', 'business-media'));
create policy bubble_profile_media_write on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'profile-covers')
              and (storage.foldername(name))[1] = auth.uid()::text);
create policy bubble_profile_media_delete on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'profile-covers')
         and (storage.foldername(name))[1] = auth.uid()::text);

-- business-media: {business_id}/... ; managers of the business write, anyone reads.
create policy bubble_business_media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'business-media'
              and public.is_business_member(public.storage_folder_uuid(name), array['owner','manager']));
create policy bubble_business_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'business-media'
         and public.is_business_member(public.storage_folder_uuid(name), array['owner','manager']));

-- wallpapers: private, {uid}/... only.
create policy bubble_wallpapers_all on storage.objects for all to authenticated
  using (bucket_id = 'wallpapers' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'wallpapers' and (storage.foldername(name))[1] = auth.uid()::text);

-- chat-media / chat-attachments: {conversation_id}/... ; conversation members only.
create policy bubble_chat_media_read on storage.objects for select to authenticated
  using (bucket_id in ('chat-media', 'chat-attachments')
         and public.is_conversation_member(public.storage_folder_uuid(name)));
create policy bubble_chat_media_write on storage.objects for insert to authenticated
  with check (bucket_id in ('chat-media', 'chat-attachments')
              and public.is_conversation_member(public.storage_folder_uuid(name)));

-- channel-media: {channel_id}/... ; channel managers write; public or subscribers read.
create policy bubble_channel_media_read on storage.objects for select to authenticated
  using (bucket_id = 'channel-media' and (
    public.can_manage_channel(public.storage_folder_uuid(name))
    or public.is_active_subscriber(public.storage_folder_uuid(name))
    or exists (select 1 from public.channels c
               where c.id = public.storage_folder_uuid(name) and c.is_public)
  ));
create policy bubble_channel_media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'channel-media'
              and public.can_manage_channel(public.storage_folder_uuid(name)));

-- story-media: {author_uid}/... ; author writes; viewers read through can_view_story.
create policy bubble_story_media_read on storage.objects for select to authenticated
  using (bucket_id = 'story-media' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.stories s
               where s.media_path = name and public.can_view_story(s.id))
  ));
create policy bubble_story_media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- verification-documents: PRIVATE. {uid}/{application_id}/... Applicant uploads and reads own files;
-- reviewers with the review permission read. Never public.
create policy bubble_verification_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy bubble_verification_read on storage.objects for select to authenticated
  using (bucket_id = 'verification-documents' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.has_permission('users.verify')
    or public.has_permission('channels.verify')
  ));

-- ---------------------------------------------------------------------------
-- Realtime (Postgres Changes). RLS applies to every subscriber.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['messages', 'message_receipts', 'message_reactions', 'conversations',
                             'conversation_members', 'channel_posts', 'channel_post_reactions',
                             'channel_subscribers', 'verification_applications', 'partner_applications',
                             'notifications']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
