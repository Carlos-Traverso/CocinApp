-- Run the WHOLE script in Supabase SQL Editor after migration 202610230001.
-- Requires one active administrator and initialized shared catalog rows.
-- It simulates two tabs that both read the same version; all writes roll back.
begin;
do $$
declare
  admin_id uuid;
  core_payload jsonb;
  recipes_payload jsonb;
  core_version integer;
  recipes_version integer;
begin
  select users.id into admin_id
  from auth.users as users
  join public.user_roles as roles on roles.user_id = users.id and roles.role = 'ADMIN'
  left join public.account_status as status on status.user_id = users.id
  where coalesce(status.active, true)
    and (users.banned_until is null or users.banned_until <= now())
  order by users.created_at limit 1;
  if admin_id is null then raise exception 'Se necesita una cuenta administradora activa.'; end if;

  select payload, version into core_payload, core_version
    from public.catalog_core where catalog_key = 'main';
  select recipes, version into recipes_payload, recipes_version
    from public.shared_recipes where catalog_key = 'main';
  if core_version is null or recipes_version is null then
    raise exception 'Primero inicializá el catálogo y las recetas en CocinAPP.';
  end if;
  perform set_config('test.core_payload', core_payload::text, true);
  perform set_config('test.recipes_payload', recipes_payload::text, true);
  perform set_config('test.core_version', core_version::text, true);
  perform set_config('test.recipes_version', recipes_version::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
end;
$$;

set local role authenticated;

do $$
declare base_core integer := current_setting('test.core_version')::integer;
  base_recipes integer := current_setting('test.recipes_version')::integer;
  current_core integer;
  current_recipes integer;
begin
  -- First tab saves; a second save based on the old version must be rejected.
  current_core := public.admin_save_catalog_core(base_core, current_setting('test.core_payload')::jsonb);
  if current_core <> base_core + 1 then raise exception 'FAIL: the catalog version did not advance'; end if;
  begin
    perform public.admin_save_catalog_core(base_core, current_setting('test.core_payload')::jsonb);
    raise exception 'FAIL: a stale catalog save was accepted';
  exception when sqlstate '40001' then null;
  end;
  if (select version from public.catalog_core where catalog_key = 'main') <> current_core
    or (select payload from public.catalog_core where catalog_key = 'main') <> current_setting('test.core_payload')::jsonb then
    raise exception 'FAIL: a stale catalog save changed stored data';
  end if;

  current_recipes := public.admin_save_shared_recipes(base_recipes, current_setting('test.recipes_payload')::jsonb);
  if current_recipes <> base_recipes + 1 then raise exception 'FAIL: the recipe version did not advance'; end if;
  begin
    perform public.admin_save_shared_recipes(base_recipes, current_setting('test.recipes_payload')::jsonb);
    raise exception 'FAIL: a stale recipe save was accepted';
  exception when sqlstate '40001' then null;
  end;
  if (select version from public.shared_recipes where catalog_key = 'main') <> current_recipes
    or (select recipes from public.shared_recipes where catalog_key = 'main') <> current_setting('test.recipes_payload')::jsonb then
    raise exception 'FAIL: a stale recipe save changed stored data';
  end if;

  begin
    update public.catalog_core set payload = current_setting('test.core_payload')::jsonb
      where catalog_key = 'main';
    raise exception 'FAIL: direct catalog writes were allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
