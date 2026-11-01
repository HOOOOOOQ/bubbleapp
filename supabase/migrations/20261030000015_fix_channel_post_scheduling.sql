-- =============================================================================
-- BubbleApp :: 0015 Restore channel managers' visibility of scheduled posts
-- Regression introduced by 0013: the channel_posts SELECT policy required
-- publish_at <= now() for every caller, including channel owners/managers.
-- A manager could therefore not see a scheduled post in the app after creating
-- it (suite 02 asserts this behaviour). Public/subscriber visibility is kept
-- exactly as in 0013: only published, non-hidden posts.
-- =============================================================================

drop policy if exists channel_posts_select on public.channel_posts;
create policy channel_posts_select on public.channel_posts for select to authenticated
  using (
    hidden_at is null
    and (
      public.can_manage_channel(channel_id)
      or (
        publish_at <= now()
        and exists (
          select 1 from public.channels c
          where c.id = channel_id
            and (c.is_public or public.is_active_subscriber(c.id))
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Also in this fix migration:
--  * calls <-> call_participants RLS policies referenced each other through
--    sub-selects, which PostgreSQL rejects as "infinite recursion detected in
--    policy" as soon as a row needs the last OR branch. The lookups now go
--    through SECURITY DEFINER helpers so policies never re-enter themselves.
--  * 0014 added a 5-argument admin_list_users next to the 4-argument one, making
--    every call ambiguous. The superseded overload is removed.
-- ---------------------------------------------------------------------------
create or replace function public.is_call_participant(p_call_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return exists (select 1 from public.call_participants cp
                  where cp.call_id = p_call_id and cp.user_id = auth.uid());
end;
$$;

create or replace function public.call_conversation_id(p_call_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_conversation uuid;
begin
  select conversation_id into v_conversation from public.calls where id = p_call_id;
  return v_conversation;
end;
$$;

drop policy if exists calls_participant_select on public.calls;
create policy calls_participant_select on public.calls for select to authenticated
  using (
    caller_id = auth.uid()
    or callee_id = auth.uid()
    or group_host_id = auth.uid()
    or public.is_call_participant(id)
    or public.is_conversation_member(conversation_id)
  );

drop policy if exists call_participants_group_select on public.call_participants;
create policy call_participants_group_select on public.call_participants for select to authenticated
  using (public.is_conversation_member(public.call_conversation_id(call_id)));

drop policy if exists call_signals_member_select on public.call_signals;
create policy call_signals_member_select on public.call_signals for select to authenticated
  using (public.is_conversation_member(public.call_conversation_id(call_id)));

drop policy if exists call_signals_member_insert on public.call_signals;
create policy call_signals_member_insert on public.call_signals for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_conversation_member(public.call_conversation_id(call_id))
  );

-- 0014 overload cleanup.
drop function if exists public.admin_list_users(text, text, integer, integer);

-- ---------------------------------------------------------------------------
-- Close an over-grant introduced by 0014 ("grant execute on all functions in
-- schema public to authenticated"). Schedulers and bootstrap helpers must never
-- be callable from a user session.
-- ---------------------------------------------------------------------------
revoke execute on function public.dispatch_due_scheduled_messages(integer) from public, anon, authenticated;
revoke execute on function public.dispatch_due_channel_posts() from public, anon, authenticated;
revoke execute on function public.dispatch_channel_post(uuid) from public, anon, authenticated;
revoke execute on function public.expire_stale_calls() from public, anon, authenticated;
revoke execute on function public.cleanup_expired_call_signals() from public, anon, authenticated;
revoke execute on function public.cleanup_expired_stories() from public, anon, authenticated;
revoke execute on function public.cleanup_expired_stories_job() from public, anon, authenticated;
revoke execute on function public.issue_owner_bootstrap_token(text, interval) from public, anon, authenticated;
-- redeem_owner_bootstrap stays callable by the signed-in applicant: the bootstrap-owner Edge
-- Function forwards the user JWT and the function performs every check itself.
revoke execute on function public.redeem_owner_bootstrap(text) from public, anon;
grant execute on function public.dispatch_due_scheduled_messages(integer) to service_role;
grant execute on function public.dispatch_due_channel_posts() to service_role;
grant execute on function public.dispatch_channel_post(uuid) to service_role;
grant execute on function public.expire_stale_calls() to service_role;
grant execute on function public.cleanup_expired_call_signals() to service_role;
grant execute on function public.cleanup_expired_stories() to service_role;
grant execute on function public.cleanup_expired_stories_job() to service_role;
grant execute on function public.redeem_owner_bootstrap(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- expire_stale_calls() overwrote its result counter with the row count of the
-- final UPDATE, so it always returned 0 even when calls were expired. The
-- counter is now accumulated (this also made the sweeper's return value usable
-- for scheduler metrics).
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_calls()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expired int := 0;
  v_failed int := 0;
  r record;
begin
  for r in select id, caller_id, callee_id, conversation_id, is_group
             from public.calls
            where status = 'ringing' and started_at < now() - interval '60 seconds'
  loop
    update public.calls set status = 'missed', ended_at = now(), ended_reason = 'timeout', updated_at = now()
     where id = r.id;
    update public.call_participants set status = 'missed' where call_id = r.id and status = 'invited';
    if not r.is_group and r.callee_id is not null then
      perform public.notify_user(r.callee_id, 'missed_call', 'Missed call', 'You missed a call',
        jsonb_build_object('call_id', r.id));
    end if;
    insert into public.messages (conversation_id, sender_id, client_message_id, kind, body)
    values (r.conversation_id, r.caller_id, gen_random_uuid(), 'system', 'Missed call');
    v_expired := v_expired + 1;
  end loop;

  update public.calls set status = 'failed', ended_at = now(), ended_reason = 'failed', updated_at = now()
   where status = 'connecting' and started_at < now() - interval '2 minutes';
  get diagnostics v_failed = row_count;

  return v_expired + v_failed;
end;
$$;
revoke execute on function public.expire_stale_calls() from public, anon, authenticated;
grant execute on function public.expire_stale_calls() to service_role;
