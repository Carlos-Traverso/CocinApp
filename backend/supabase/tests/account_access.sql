-- Run manually in Supabase SQL Editor AFTER migration 202610170001.
-- Requires at least two existing Auth accounts. All fixture changes roll back.
-- The editor must execute the whole script in one connection/transaction.
begin;
do $$
declare
  account_ids uuid[];
begin
  select array_agg(id) into account_ids from (select id from auth.users order by created_at limit 2) accounts;
  if coalesce(array_length(account_ids, 1), 0) < 2 then
    raise exception 'Se necesitan dos cuentas existentes para ejecutar la prueba.';
  end if;
  perform set_config('test.user_a', account_ids[1]::text, true);
  perform set_config('test.user_b', account_ids[2]::text, true);
  update auth.users set banned_until = null where id = any(account_ids);
  -- Also reset application state when migration 002 is installed. Dynamic SQL
  -- keeps this script usable immediately after migration 001 as well.
  if to_regclass('public.account_status') is not null then
    execute 'insert into public.account_status(user_id, active) select unnest($1), true
      on conflict(user_id) do update set active = true' using account_ids;
  end if;
  insert into public.user_roles(user_id, role) values (account_ids[1], 'USER'), (account_ids[2], 'ADMIN')
    on conflict (user_id) do update set role = excluded.role;
  insert into public.personal_data(user_id, data_key, value) values
    (account_ids[1], 'favorites', '[]'), (account_ids[2], 'favorites', '[]')
    on conflict (user_id, data_key) do update set value = excluded.value;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_a'), 'role', 'authenticated')::text, true);
do $$
begin
  if not public.current_account_is_active() or public.current_app_role() <> 'USER' then
    raise exception 'FAIL: active USER role';
  end if;
  if not exists (select 1 from public.personal_data where user_id = current_setting('test.user_a')::uuid) then
    raise exception 'FAIL: own data inaccessible';
  end if;
  if exists (select 1 from public.personal_data where user_id = current_setting('test.user_b')::uuid) then
    raise exception 'FAIL: another account data exposed';
  end if;
  begin
    update public.user_roles set role = 'ADMIN' where user_id = current_setting('test.user_a')::uuid;
    raise exception 'FAIL: direct role escalation accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_user_role(current_setting('test.user_b')::uuid, 'USER');
    raise exception 'FAIL: USER administrative RPC accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_users();
    raise exception 'FAIL: USER can list accounts';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.personal_data(user_id, data_key, value)
      values (current_setting('test.user_b')::uuid, 'profile', '{}');
    raise exception 'FAIL: cross-account insert accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
update auth.users set banned_until = now() + interval '1 day' where id = current_setting('test.user_b')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_b'), 'role', 'authenticated')::text, true);
do $$
begin
  if public.current_account_is_active() or public.current_app_role() <> 'USER' then
    raise exception 'FAIL: banned administrator retained authorization';
  end if;
  if exists (select 1 from public.personal_data) or exists (select 1 from public.pantry_items)
    or exists (select 1 from public.user_roles) or exists (select 1 from public.catalog_core)
    or exists (select 1 from public.shared_recipes) then
    raise exception 'FAIL: banned account can read application data';
  end if;
  begin
    perform public.admin_list_users();
    raise exception 'FAIL: banned administrator can list users';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_user_role(current_setting('test.user_a')::uuid, 'ADMIN');
    raise exception 'FAIL: banned administrator can change roles';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.personal_data(user_id, data_key, value)
      values (current_setting('test.user_b')::uuid, 'cooking_progress', '{}');
    raise exception 'FAIL: banned account can write';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  begin
    perform public.current_app_role();
    raise exception 'FAIL: anonymous role RPC allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_users();
    raise exception 'FAIL: anonymous directory RPC allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    if exists (select 1 from public.personal_data) then raise exception 'FAIL: anonymous data exposed'; end if;
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
rollback;
select 'PASS: security assertions completed; fixtures rolled back' as result;
