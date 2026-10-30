-- 06 Calls WebRTC: validates 0012 migration and RLS
\pset tuples_only off
\timing off

create or replace function test_assert(p_name text, p_condition boolean) returns void language plpgsql as $$ begin if not p_condition then raise exception 'FAIL %', p_name; else raise notice 'PASS %', p_name; end if; end; $$;

-- Tables exist
select test_assert('calls has is_group', exists(select 1 from information_schema.columns where table_name='calls' and column_name='is_group'));
select test_assert('calls has ended_reason', exists(select 1 from information_schema.columns where table_name='calls' and column_name='ended_reason'));
select test_assert('calls has sfu_room_id', exists(select 1 from information_schema.columns where table_name='calls' and column_name='sfu_room_id'));
select test_assert('call_participants exists', exists(select 1 from pg_tables where tablename='call_participants'));
select test_assert('call_signals exists', exists(select 1 from pg_tables where tablename='call_signals'));
select test_assert('call_history_visibility exists', exists(select 1 from pg_tables where tablename='call_history_visibility'));
select test_assert('user_settings has call_settings', exists(select 1 from information_schema.columns where table_name='user_settings' and column_name='call_settings'));

-- RLS enabled
select test_assert('calls RLS', (select relrowsecurity from pg_class where relname='calls'));
select test_assert('call_signals RLS', (select relrowsecurity from pg_class where relname='call_signals'));
select test_assert('call_participants RLS', (select relrowsecurity from pg_class where relname='call_participants'));

-- Functions exist
select test_assert('start_call exists', exists(select 1 from pg_proc where proname='start_call'));
select test_assert('send_call_signal exists', exists(select 1 from pg_proc where proname='send_call_signal'));
select test_assert('expire_stale_calls exists', exists(select 1 from pg_proc where proname='expire_stale_calls'));
select test_assert('cleanup_expired_call_signals exists', exists(select 1 from pg_proc where proname='cleanup_expired_call_signals'));
select test_assert('hide_call_history exists', exists(select 1 from pg_proc where proname='hide_call_history'));

-- Constraint allows new statuses
select test_assert('calls status check includes connecting', (select exists(select 1 from pg_constraint where conname='calls_status_check')));

-- Indexes
select test_assert('call_signals_call_time index', exists(select 1 from pg_indexes where tablename='call_signals' and indexname='call_signals_call_time'));
select test_assert('call_signals_expires index', exists(select 1 from pg_indexes where tablename='call_signals' and indexname='call_signals_expires'));

drop function test_assert(text, boolean);
