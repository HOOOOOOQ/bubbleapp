-- =============================================================================
-- BubbleApp :: 0004 verification (blue checkmark)
-- Badge state (profiles.is_verified, businesses.is_verified, channels.is_verified)
-- is written ONLY by review_verification_application(), after permission checks.
-- Clients can read their own applications, can never write badge columns.
-- =============================================================================

create table if not exists public.verification_applications (
  id                uuid primary key default gen_random_uuid(),
  applicant_id      uuid not null references public.profiles (id) on delete cascade,
  application_type  text not null check (application_type in ('user', 'business', 'channel', 'organization')),
  status            text not null default 'pending'
                    check (status in ('pending', 'under_review', 'info_requested', 'approved',
                                      'rejected', 'suspended', 'revoked')),
  full_name         text not null check (char_length(full_name) between 2 and 120),
  username          text,
  category          text not null check (char_length(category) between 2 and 60),
  description       text not null default '' check (char_length(description) <= 2000),
  reason            text not null check (char_length(reason) between 10 and 2000),
  links             jsonb not null default '[]'::jsonb,
  business_id       uuid references public.businesses (id) on delete cascade,
  channel_id        uuid references public.channels (id) on delete cascade,
  recommendation    text check (recommendation in ('approve', 'reject')),
  reviewed_by       uuid references public.profiles (id) on delete set null,
  reviewed_at       timestamptz,
  decision_note     text,
  submitted_at      timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint verification_target_matches_type check (
    (application_type in ('user', 'organization') and business_id is null and channel_id is null)
    or (application_type = 'business' and business_id is not null and channel_id is null)
    or (application_type = 'channel' and channel_id is not null and business_id is null)
  ),
  constraint verification_not_self_reviewed check (reviewed_by is null or reviewed_by <> applicant_id)
);
create index if not exists verification_applications_status_idx on public.verification_applications (status, submitted_at);
create index if not exists verification_applications_applicant_idx on public.verification_applications (applicant_id);

-- Only one open application per applicant + target.
create unique index if not exists verification_one_open_per_target
  on public.verification_applications (applicant_id, application_type, (coalesce(business_id, channel_id, applicant_id)))
  where status in ('pending', 'under_review', 'info_requested');

-- Only one live (approved or suspended) grant per target.
create unique index if not exists verification_one_live_per_target
  on public.verification_applications (application_type, (coalesce(business_id, channel_id, applicant_id)))
  where status in ('approved', 'suspended');

create table if not exists public.verification_documents (
  id              uuid primary key default gen_random_uuid(),
  application_id  uuid not null references public.verification_applications (id) on delete cascade,
  uploaded_by     uuid not null references public.profiles (id) on delete cascade,
  storage_path    text not null unique,
  doc_type        text not null check (doc_type in ('identity', 'business_registration', 'authorization', 'website_proof', 'other')),
  mime_type       text not null,
  size_bytes      bigint not null check (size_bytes > 0),
  created_at      timestamptz not null default now()
);
create index if not exists verification_documents_app_idx on public.verification_documents (application_id);

create table if not exists public.verification_history (
  id              bigint generated always as identity primary key,
  application_id  uuid not null references public.verification_applications (id) on delete cascade,
  actor_id        uuid,
  action          text not null,
  from_status     text,
  to_status       text,
  note            text,
  created_at      timestamptz not null default now()
);
create index if not exists verification_history_app_idx on public.verification_history (application_id, created_at);

create trigger verification_history_immutable before update or delete on public.verification_history
  for each row execute function public.reject_audit_mutation();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.verification_review_permission(p_type text)
returns text
language sql
immutable
as $$
  select case when p_type = 'channel' then 'channels.verify' else 'users.verify' end;
$$;

-- Applies the badge for a decision. Runs with privileged flag enabled.
create or replace function public.apply_verification_badge(p_app public.verification_applications, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('bubble.privileged', 'on', true);
  if p_app.application_type in ('user', 'organization') then
    update public.profiles
       set is_verified = p_verified,
           verified_at = case when p_verified then now() else null end
     where id = p_app.applicant_id;
  elsif p_app.application_type = 'business' then
    update public.businesses
       set is_verified = p_verified,
           verified_at = case when p_verified then now() else null end
     where id = p_app.business_id;
  elsif p_app.application_type = 'channel' then
    update public.channels
       set is_verified = p_verified,
           verified_at = case when p_verified then now() else null end
     where id = p_app.channel_id;
  end if;
  perform set_config('bubble.privileged', 'off', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: applicant submits
-- ---------------------------------------------------------------------------
create or replace function public.submit_verification_application(
  p_application_type text,
  p_full_name text,
  p_username text,
  p_category text,
  p_description text,
  p_reason text,
  p_links jsonb default '[]'::jsonb,
  p_business_id uuid default null,
  p_channel_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_already_verified boolean;
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = '42501';
  end if;

  if p_application_type = 'user' or p_application_type = 'organization' then
    select is_verified into v_already_verified from public.profiles where id = v_uid;
    p_business_id := null;
    p_channel_id := null;
  elsif p_application_type = 'business' then
    if not public.is_business_member(p_business_id, array['owner', 'manager']) then
      raise exception 'Only business owners or managers can apply for business verification' using errcode = '42501';
    end if;
    select is_verified into v_already_verified from public.businesses where id = p_business_id;
    p_channel_id := null;
  elsif p_application_type = 'channel' then
    if not exists (select 1 from public.channels c where c.id = p_channel_id and c.owner_id = v_uid) then
      raise exception 'Only the channel owner can apply for channel verification' using errcode = '42501';
    end if;
    select is_verified into v_already_verified from public.channels where id = p_channel_id;
    p_business_id := null;
  else
    raise exception 'Unknown application type';
  end if;

  if v_already_verified then
    raise exception 'This account is already verified';
  end if;

  insert into public.verification_applications (
    applicant_id, application_type, status, full_name, username, category, description, reason,
    links, business_id, channel_id
  ) values (
    v_uid, p_application_type, 'pending', trim(p_full_name), lower(nullif(trim(p_username), '')),
    trim(p_category), coalesce(p_description, ''), trim(p_reason), coalesce(p_links, '[]'::jsonb),
    p_business_id, p_channel_id
  )
  returning id into v_id;

  insert into public.verification_history (application_id, actor_id, action, from_status, to_status)
  values (v_id, v_uid, 'submitted', null, 'pending');

  return v_id;
exception
  when unique_violation then
    raise exception 'You already have an open or active verification request for this account';
end;
$$;

-- Applicant attaches a document uploaded to the private 'verification-docs' bucket.
-- Storage path convention: {applicant_uid}/{application_id}/{filename}
create or replace function public.add_verification_document(
  p_application_id uuid,
  p_storage_path text,
  p_doc_type text,
  p_mime_type text,
  p_size_bytes bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.verification_applications%rowtype;
  v_id uuid;
begin
  select * into v_app from public.verification_applications where id = p_application_id;
  if not found or v_app.applicant_id <> auth.uid() then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if v_app.status not in ('pending', 'under_review', 'info_requested') then
    raise exception 'Documents can no longer be added to this application';
  end if;
  if split_part(p_storage_path, '/', 1) <> auth.uid()::text
     or split_part(p_storage_path, '/', 2) <> p_application_id::text then
    raise exception 'Invalid document path' using errcode = '42501';
  end if;
  insert into public.verification_documents (application_id, uploaded_by, storage_path, doc_type, mime_type, size_bytes)
  values (p_application_id, auth.uid(), p_storage_path, p_doc_type, p_mime_type, p_size_bytes)
  returning id into v_id;
  insert into public.verification_history (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, auth.uid(), 'document_added', v_app.status, v_app.status, p_doc_type);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: reviewers act. Actions and required permissions:
--   start_review, request_info, recommend_approve, recommend_reject -> users.verify | channels.verify
--   approve, reject, suspend, revoke, restore                      -> the above AND verification.approve
-- ---------------------------------------------------------------------------
create or replace function public.review_verification_application(
  p_application_id uuid,
  p_action text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_app public.verification_applications%rowtype;
  v_new_status text;
  v_doc_count integer;
  v_requires_docs boolean;
  v_min_docs integer;
begin
  select * into v_app from public.verification_applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.applicant_id = v_actor then
    raise exception 'You cannot review your own application' using errcode = '42501';
  end if;
  if not public.has_permission(public.verification_review_permission(v_app.application_type)) then
    raise exception 'Permission denied for this verification type' using errcode = '42501';
  end if;
  if p_action in ('approve', 'reject', 'suspend', 'revoke', 'restore')
     and not public.has_permission('verification.approve') then
    raise exception 'Only authorized decision makers can perform %', p_action using errcode = '42501';
  end if;

  case p_action
    when 'start_review' then
      if v_app.status <> 'pending' then raise exception 'Only pending applications can start review'; end if;
      v_new_status := 'under_review';
    when 'request_info' then
      if v_app.status not in ('pending', 'under_review') then raise exception 'Information can be requested only while open'; end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'Explain what information is needed'; end if;
      v_new_status := 'info_requested';
    when 'recommend_approve' then
      if v_app.status not in ('pending', 'under_review', 'info_requested') then raise exception 'Application is closed'; end if;
      update public.verification_applications set recommendation = 'approve', updated_at = now() where id = p_application_id;
      v_new_status := v_app.status;
    when 'recommend_reject' then
      if v_app.status not in ('pending', 'under_review', 'info_requested') then raise exception 'Application is closed'; end if;
      update public.verification_applications set recommendation = 'reject', updated_at = now() where id = p_application_id;
      v_new_status := v_app.status;
    when 'approve' then
      if v_app.status not in ('pending', 'under_review', 'info_requested') then
        raise exception 'Only open applications can be approved';
      end if;
      select coalesce((setting_value ->> 'require_documents')::boolean, true),
             coalesce((setting_value ->> 'min_documents')::integer, 1)
        into v_requires_docs, v_min_docs
        from public.platform_settings where setting_key = 'verification_requirements';
      select count(*) into v_doc_count from public.verification_documents where application_id = p_application_id;
      if coalesce(v_requires_docs, true) and v_doc_count < coalesce(v_min_docs, 1) then
        raise exception 'At least % supporting document(s) are required before approval', coalesce(v_min_docs, 1);
      end if;
      v_new_status := 'approved';
    when 'reject' then
      if v_app.status not in ('pending', 'under_review', 'info_requested') then
        raise exception 'Only open applications can be rejected';
      end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'A rejection reason is required'; end if;
      v_new_status := 'rejected';
    when 'suspend' then
      if v_app.status <> 'approved' then raise exception 'Only approved verifications can be suspended'; end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'A reason is required'; end if;
      v_new_status := 'suspended';
    when 'revoke' then
      if v_app.status not in ('approved', 'suspended') then raise exception 'Only active verifications can be revoked'; end if;
      if p_note is null or char_length(trim(p_note)) < 5 then raise exception 'A reason is required'; end if;
      v_new_status := 'revoked';
    when 'restore' then
      if v_app.status <> 'suspended' then raise exception 'Only suspended verifications can be restored'; end if;
      v_new_status := 'approved';
    else
      raise exception 'Unknown action: %', p_action;
  end case;

  if v_new_status <> v_app.status then
    update public.verification_applications
       set status = v_new_status,
           reviewed_by = v_actor,
           reviewed_at = now(),
           decision_note = coalesce(p_note, decision_note),
           updated_at = now()
     where id = p_application_id;
  end if;

  -- Badge follows the decision.
  if v_new_status = 'approved' and v_app.status <> 'approved' then
    perform public.apply_verification_badge(v_app, true);
  elsif v_new_status in ('suspended', 'revoked', 'rejected') and v_app.status in ('approved') then
    perform public.apply_verification_badge(v_app, false);
  end if;

  insert into public.verification_history (application_id, actor_id, action, from_status, to_status, note)
  values (p_application_id, v_actor, p_action, v_app.status, v_new_status, p_note);

  perform public.write_audit('verification.' || p_action, v_app.application_type, p_application_id::text,
    jsonb_build_object('applicant_id', v_app.applicant_id, 'from', v_app.status, 'to', v_new_status));

  return v_new_status;
end;
$$;

-- Verification reviewer queue (owner / admins see all types they may review).
create or replace function public.list_verification_queue(p_type text default null, p_status text default null)
returns setof public.verification_applications
language sql
stable
security definer
set search_path = public
as $$
  select a.*
  from public.verification_applications a
  where (p_type is null or a.application_type = p_type)
    and (p_status is null or a.status = p_status)
    and public.has_permission(public.verification_review_permission(a.application_type))
  order by a.submitted_at desc
  limit 200;
$$;

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
alter table public.verification_applications enable row level security;
alter table public.verification_documents   enable row level security;
alter table public.verification_history     enable row level security;

revoke all on public.verification_applications, public.verification_documents, public.verification_history
  from anon, authenticated;
grant select on public.verification_applications to authenticated;
grant select on public.verification_documents to authenticated;
grant select on public.verification_history to authenticated;

create policy verification_applications_select on public.verification_applications for select to authenticated using (
  applicant_id = auth.uid()
  or public.has_permission(public.verification_review_permission(application_type))
);
create policy verification_documents_select on public.verification_documents for select to authenticated using (
  uploaded_by = auth.uid()
  or exists (
    select 1 from public.verification_applications a
    where a.id = application_id
      and public.has_permission(public.verification_review_permission(a.application_type))
  )
);
create policy verification_history_select on public.verification_history for select to authenticated using (
  exists (
    select 1 from public.verification_applications a
    where a.id = application_id
      and (a.applicant_id = auth.uid()
           or public.has_permission(public.verification_review_permission(a.application_type)))
  )
);
