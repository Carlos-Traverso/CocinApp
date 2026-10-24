-- Run the WHOLE script in Supabase SQL Editor after migrations 001-009,
-- 202610170001-002, 202610170004, and 202610230001. Requires two existing
-- Auth accounts. The first is temporarily USER and the second ADMIN; all
-- changes roll back.
begin;

do $$
declare
  ids uuid[];
  pantry_a uuid := gen_random_uuid();
  pantry_b uuid := gen_random_uuid();
  missing_tables text[];
begin
  select array_agg(id order by created_at, id)
    into ids
    from (select id, created_at from auth.users order by created_at, id limit 2) accounts;
  if coalesce(array_length(ids, 1), 0) < 2 then
    raise exception 'Se necesitan dos cuentas existentes en Authentication → Users.';
  end if;

  select array_agg(required.name)
    into missing_tables
    from (values ('pantry_items'), ('personal_data'), ('user_roles'), ('account_status'), ('catalog_core'), ('shared_recipes')) as required(name)
    where not exists (
      select 1 from pg_class as relation
      join pg_namespace as schema on schema.oid = relation.relnamespace
      where schema.nspname = 'public' and relation.relname = required.name
        and relation.relkind = 'r' and relation.relrowsecurity
    );
  if missing_tables is not null then
    raise exception 'Falta una tabla o RLS no está activo en: %', array_to_string(missing_tables, ', ');
  end if;

  if not exists (select 1 from public.catalog_core where catalog_key = 'main')
    or not exists (select 1 from public.shared_recipes where catalog_key = 'main') then
    raise exception 'Inicializá el catálogo y las recetas en CocinAPP antes de probar.';
  end if;

  perform set_config('test.user_a', ids[1]::text, true);
  perform set_config('test.admin', ids[2]::text, true);

  update auth.users set banned_until = null where id = any(ids);
  insert into public.account_status(user_id, active)
    select unnest(ids), true
    on conflict (user_id) do update set active = true;
  insert into public.user_roles(user_id, role)
    values (ids[1], 'USER'), (ids[2], 'ADMIN')
    on conflict (user_id) do update set role = excluded.role;

  delete from public.personal_data where user_id = any(ids) and data_key = 'favorites';
  insert into public.personal_data(user_id, data_key, value)
    values (ids[1], 'favorites', '{"permission_test":"user-a"}'),
      (ids[2], 'favorites', '{"permission_test":"admin"}');
  insert into public.pantry_items(id, user_id, name, category, quantity, unit, minimum)
    values (pantry_a, ids[1], 'Prueba permiso A', 'Pruebas', 1, 'unidad', 0),
      (pantry_b, ids[2], 'Prueba permiso ADMIN', 'Pruebas', 1, 'unidad', 0);
  perform set_config('test.pantry_a', pantry_a::text, true);
  perform set_config('test.pantry_b', pantry_b::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user_a'), 'role', 'authenticated')::text, true);

do $$
declare affected integer;
begin
  if current_app_role() <> 'USER' or not current_account_is_active() then
    raise exception 'FAIL: active account A should be an active USER';
  end if;
  if (select count(*) from public.personal_data where data_key = 'favorites') <> 1
    or (select value ->> 'permission_test' from public.personal_data where data_key = 'favorites') <> 'user-a' then
    raise exception 'FAIL: USER A cannot read only its own personal data';
  end if;
  if (select count(*) from public.pantry_items where id in (current_setting('test.pantry_a')::uuid, current_setting('test.pantry_b')::uuid)) <> 1
    or not exists (select 1 from public.pantry_items where id = current_setting('test.pantry_a')::uuid) then
    raise exception 'FAIL: USER A can see another account pantry row or cannot see its own';
  end if;
  if exists (select 1 from public.personal_data where user_id = current_setting('test.admin')::uuid)
    or exists (select 1 from public.user_roles where user_id = current_setting('test.admin')::uuid) then
    raise exception 'FAIL: USER A can read another account personal data or role';
  end if;
  if not exists (select 1 from public.catalog_core where catalog_key = 'main')
    or not exists (select 1 from public.shared_recipes where catalog_key = 'main') then
    raise exception 'FAIL: authenticated users should be able to read shared catalogs';
  end if;

  update public.personal_data set value = '{"permission_test":"updated"}' where user_id = auth.uid() and data_key = 'favorites';
  if not found then raise exception 'FAIL: USER A cannot update its own personal data'; end if;
  update public.pantry_items set quantity = 2 where id = current_setting('test.pantry_a')::uuid;
  if not found then raise exception 'FAIL: USER A cannot update its own pantry row'; end if;

  update public.pantry_items set quantity = 99 where id = current_setting('test.pantry_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: USER A modified USER B pantry row'; end if;
  delete from public.pantry_items where id = current_setting('test.pantry_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: USER A deleted USER B pantry row'; end if;

  begin
    insert into public.personal_data(user_id, data_key, value)
      values (current_setting('test.admin')::uuid, 'profile', '{}');
    raise exception 'FAIL: cross-account personal data insert succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.pantry_items(user_id, name, category, quantity, unit, minimum)
      values (current_setting('test.admin')::uuid, 'Producto ajeno', 'Pruebas', 1, 'unidad', 0);
    raise exception 'FAIL: cross-account pantry insert succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_users();
    raise exception 'FAIL: USER can list accounts';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_save_catalog_core(1, '{"categories":[],"units":[],"ingredients":[]}'::jsonb);
    raise exception 'FAIL: USER can call the administrator catalog write';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_save_shared_recipes(1, '[]'::jsonb);
    raise exception 'FAIL: USER can call the administrator recipe write';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.catalog_core set payload = payload where catalog_key = 'main';
    raise exception 'FAIL: direct catalog write was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.shared_recipes set recipes = recipes where catalog_key = 'main';
    raise exception 'FAIL: direct recipe write was allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', json_build_object('sub', current_setting('test.admin'), 'role', 'authenticated')::text, true);
do $$
declare
  existing_payload jsonb;
  existing_version integer;
  new_version integer;
  existing_recipes jsonb;
  recipe_version integer;
begin
  if current_app_role() <> 'ADMIN' or not current_account_is_active() then
    raise exception 'FAIL: ADMIN account should be active and recognized as ADMIN';
  end if;
  if (select count(*) from public.admin_list_users()) < 2 then
    raise exception 'FAIL: ADMIN cannot list managed users';
  end if;
  if exists (select 1 from public.personal_data where user_id = current_setting('test.user_a')::uuid)
    or exists (select 1 from public.pantry_items where user_id = current_setting('test.user_a')::uuid) then
    raise exception 'FAIL: ADMIN can read users’ private data';
  end if;

  select payload, version into existing_payload, existing_version
    from public.catalog_core where catalog_key = 'main';
  new_version := public.admin_save_catalog_core(existing_version, existing_payload);
  if new_version <> existing_version + 1 then raise exception 'FAIL: ADMIN cannot save the shared catalog'; end if;

  select recipes, version into existing_recipes, recipe_version
    from public.shared_recipes where catalog_key = 'main';
  if public.admin_save_shared_recipes(recipe_version, existing_recipes) <> recipe_version + 1 then
    raise exception 'FAIL: ADMIN cannot save shared recipes';
  end if;
  begin
    update public.catalog_core set payload = payload where catalog_key = 'main';
    raise exception 'FAIL: ADMIN bypassed the version-aware write function';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.shared_recipes set recipes = recipes where catalog_key = 'main';
    raise exception 'FAIL: ADMIN bypassed the version-aware recipe function';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
select 'PASS: user, administrator, RLS, and version-aware write checks completed; all test changes rolled back' as result;
