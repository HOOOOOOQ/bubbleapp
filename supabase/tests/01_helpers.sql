-- Test helpers: impersonate PostgREST roles and assert outcomes. Failing checks raise.
create schema if not exists tst;
grant usage on schema tst to anon, authenticated;

create or replace function tst.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
  execute 'set role authenticated';
end $$;

create or replace function tst.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, false);
  execute 'set role anon';
end $$;

create or replace function tst.as_trusted() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', false);
end $$;

create or replace function tst.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'ASSERTION FAILED: %', p_msg;
  end if;
  raise notice 'PASS: %', p_msg;
end $$;

-- Runs p_sql and requires it to fail with an error matching p_pattern (regex).
create or replace function tst.expect_error(p_sql text, p_pattern text, p_msg text) returns void language plpgsql as $$
declare
  v_failed boolean := false;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ~* p_pattern then
      v_failed := true;
    else
      raise exception 'ASSERTION FAILED (%): wrong error "%" (expected /%/)', p_msg, sqlerrm, p_pattern;
    end if;
  end;
  if not v_failed then
    raise exception 'ASSERTION FAILED (%): statement succeeded but must fail', p_msg;
  end if;
  raise notice 'PASS: %', p_msg;
end $$;

-- Runs p_sql and requires success.
create or replace function tst.expect_ok(p_sql text, p_msg text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise notice 'PASS: %', p_msg;
end $$;

create or replace function tst.count_q(p_sql text) returns bigint language plpgsql as $$
declare v bigint;
begin
  execute 'select count(*) from (' || p_sql || ') q' into v;
  return v;
end $$;

grant execute on all functions in schema tst to anon, authenticated;
