-- Run the WHOLE script in Supabase SQL Editor after migration 202610170002.
-- Requires three existing accounts. All account/role fixture changes roll back.
begin;
do $$
declare ids uuid[];
begin
  select array_agg(id) into ids from (select id from auth.users order by created_at, id limit 3) u;
  if coalesce(array_length(ids, 1), 0) < 3 then
    raise exception 'Se necesitan tres cuentas existentes para ejecutar la prueba.';
  end if;
  perform set_config('test.admin_a', ids[1]::text, true);
  perform set_config('test.admin_b', ids[2]::text, true);
  perform set_config('test.user_c', ids[3]::text, true);
  update auth.users set banned_until = null where id = any(ids);
  insert into public.account_status(user_id, active) select unnest(ids), true
    on conflict(user_id) do update set active = true;
  insert into public.user_roles(user_id, role) values (ids[1], 'ADMIN'), (ids[2], 'ADMIN'), (ids[3], 'USER')
    on conflict(user_id) do update set role = excluded.role;
  insert into public.personal_data(user_id, data_key, value) values (ids[2], 'favorites', '[]')
    on conflict(user_id, data_key) do update set value = excluded.value;
end;
$$;

-- A normal user cannot invoke either administrative mutation or write status.
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_c'), 'role', 'authenticated')::text, true);
do $$
begin
  begin
    perform public.admin_set_user_active(current_setting('test.admin_a')::uuid, false);
    raise exception 'FAIL: USER can disable administrator';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_user_role(current_setting('test.user_c')::uuid, 'ADMIN');
    raise exception 'FAIL: USER can promote account';
  exception when insufficient_privilege then null; end;
  begin
    update public.account_status set active = false where user_id = current_setting('test.admin_a')::uuid;
    if found then raise exception 'FAIL: client can write account status'; end if;
  exception when insufficient_privilege then null; end;
end;
$$;

-- Administrator A can manage C but cannot disable itself/change its own role.
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_a'), 'role', 'authenticated')::text, true);
do $$
begin
  begin
    perform public.admin_set_user_active(current_setting('test.admin_a')::uuid, false);
    raise exception 'FAIL: self-disable accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_user_role(current_setting('test.admin_a')::uuid, 'USER');
    raise exception 'FAIL: self role change accepted';
  exception when insufficient_privilege then null; end;
  perform public.admin_set_user_active(current_setting('test.user_c')::uuid, false);
end;
$$;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_c'), 'role', 'authenticated')::text, true);
do $$ begin
  if public.current_account_is_active() then raise exception 'FAIL: disabled USER remains active'; end if;
end; $$;

-- Simulate the second request using a JWT issued before A disabled B.
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_b'), 'role', 'authenticated')::text, true);
do $$ begin
  if not exists (select 1 from public.personal_data where user_id = current_setting('test.admin_b')::uuid and data_key = 'favorites') then
    raise exception 'FAIL: active administrator cannot read own RLS fixture';
  end if;
end; $$;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_a'), 'role', 'authenticated')::text, true);
select public.admin_set_user_active(current_setting('test.admin_b')::uuid, false);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_b'), 'role', 'authenticated')::text, true);
do $$
begin
  if public.current_account_is_active() or public.current_app_role() <> 'USER' then
    raise exception 'FAIL: disabled administrator retains authority';
  end if;
  if exists (select 1 from public.personal_data) or exists (select 1 from public.pantry_items)
    or exists (select 1 from public.catalog_core) or exists (select 1 from public.shared_recipes) then
    raise exception 'FAIL: application-disabled account can read protected data';
  end if;
  begin
    insert into public.personal_data(user_id, data_key, value)
      values (current_setting('test.admin_b')::uuid, 'favorites', '[]')
      on conflict(user_id, data_key) do update set value = excluded.value;
    raise exception 'FAIL: application-disabled account can write own data';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_user_active(current_setting('test.admin_a')::uuid, false);
    raise exception 'FAIL: stale JWT can disable A';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_user_role(current_setting('test.admin_a')::uuid, 'USER');
    raise exception 'FAIL: disabled administrator can change roles';
  exception when insufficient_privilege then null; end;
end;
$$;

-- Re-enable B, then remove its role. The same old JWT must lose authority.
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_a'), 'role', 'authenticated')::text, true);
select public.admin_set_user_active(current_setting('test.admin_b')::uuid, true);
select public.admin_set_user_role(current_setting('test.admin_b')::uuid, 'USER');
select public.admin_set_user_active(current_setting('test.user_c')::uuid, true);
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin_b'), 'role', 'authenticated')::text, true);
do $$
begin
  begin
    perform public.admin_set_user_active(current_setting('test.admin_a')::uuid, false);
    raise exception 'FAIL: demoted actor can disable administrator';
  exception when insufficient_privilege then null; end;
  begin
    perform public.admin_set_user_role(current_setting('test.user_c')::uuid, 'ADMIN');
    raise exception 'FAIL: demoted actor can promote USER';
  exception when insufficient_privilege then null; end;
end;
$$;

-- Auth bans must also reject a role ADMIN whose application status is active.
reset role;
update public.user_roles set role = 'ADMIN' where user_id = current_setting('test.admin_b')::uuid;
update auth.users set banned_until = now() + interval '1 day' where id = current_setting('test.admin_b')::uuid;
set local role authenticated;
do $$ begin
  if public.current_account_is_active() then raise exception 'FAIL: Auth ban ignored'; end if;
  begin
    perform public.admin_set_user_active(current_setting('test.user_c')::uuid, false);
    raise exception 'FAIL: Auth-banned actor can change status';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
-- Absence of a status row preserves access for newly registered Auth accounts.
update auth.users set banned_until = null where id = current_setting('test.user_c')::uuid;
delete from public.account_status where user_id = current_setting('test.user_c')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_c'), 'role', 'authenticated')::text, true);
do $$ begin
  if not public.current_account_is_active() then raise exception 'FAIL: missing status denies active new account'; end if;
end; $$;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$ begin
  begin
    perform public.admin_set_user_active(current_setting('test.admin_a')::uuid, false);
    raise exception 'FAIL: anonymous status RPC allowed';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
rollback;
select 'PASS: atomic account-status assertions completed; fixtures rolled back' as result;
