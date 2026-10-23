begin;

-- A monotonically increasing version lets each save prove it is based on the
-- latest row, preventing stale tabs from replacing newer catalog data.
alter table public.catalog_core
  add column version integer not null default 1 check (version > 0);
alter table public.shared_recipes
  add column version integer not null default 1 check (version > 0);

create or replace function public.bump_shared_catalog_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.bump_shared_catalog_version() from public, anon, authenticated;

-- All remote writes must pass through the version-aware functions below.
revoke insert, update on table public.catalog_core from authenticated;
revoke insert, update on table public.shared_recipes from authenticated;

create trigger catalog_core_bump_version
before update on public.catalog_core
for each row execute function public.bump_shared_catalog_version();

create trigger shared_recipes_bump_version
before update on public.shared_recipes
for each row execute function public.bump_shared_catalog_version();

create or replace function public.admin_save_catalog_core(p_expected_version integer, p_payload jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare saved_version integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  -- Serialize catalog writes with admin role and account-status changes.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if (select auth.uid()) is null
    or (select public.current_app_role()) <> 'ADMIN'
    or not (select public.current_account_is_active()) then
    raise exception 'Solo un administrador activo puede guardar el catálogo.' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or jsonb_typeof(p_payload -> 'categories') <> 'array'
    or jsonb_typeof(p_payload -> 'units') <> 'array'
    or jsonb_typeof(p_payload -> 'ingredients') <> 'array' then
    raise exception 'El catálogo tiene un formato inválido.' using errcode = '22023';
  end if;

  if p_expected_version is null then
    insert into public.catalog_core(catalog_key, payload)
      values ('main', p_payload)
      on conflict (catalog_key) do nothing
      returning version into saved_version;
  else
    update public.catalog_core set payload = p_payload
      where catalog_key = 'main' and version = p_expected_version
      returning version into saved_version;
  end if;
  if saved_version is null then
    raise exception 'El catálogo cambió desde que lo abriste. Recargá la página y volvé a aplicar tu cambio.' using errcode = '40001';
  end if;
  return saved_version;
end;
$$;
revoke all on function public.admin_save_catalog_core(integer, jsonb) from public, anon;
grant execute on function public.admin_save_catalog_core(integer, jsonb) to authenticated;

create or replace function public.admin_save_shared_recipes(p_expected_version integer, p_recipes jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare saved_version integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  -- Serialize recipe writes with admin role and account-status changes.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if (select auth.uid()) is null
    or (select public.current_app_role()) <> 'ADMIN'
    or not (select public.current_account_is_active()) then
    raise exception 'Solo un administrador activo puede guardar recetas.' using errcode = '42501';
  end if;
  if p_recipes is null or jsonb_typeof(p_recipes) <> 'array' then
    raise exception 'El catálogo de recetas tiene un formato inválido.' using errcode = '22023';
  end if;

  if p_expected_version is null then
    insert into public.shared_recipes(catalog_key, recipes)
      values ('main', p_recipes)
      on conflict (catalog_key) do nothing
      returning version into saved_version;
  else
    update public.shared_recipes set recipes = p_recipes
      where catalog_key = 'main' and version = p_expected_version
      returning version into saved_version;
  end if;
  if saved_version is null then
    raise exception 'Las recetas cambiaron desde que las abriste. Recargá la página y volvé a aplicar tu cambio.' using errcode = '40001';
  end if;
  return saved_version;
end;
$$;
revoke all on function public.admin_save_shared_recipes(integer, jsonb) from public, anon;
grant execute on function public.admin_save_shared_recipes(integer, jsonb) to authenticated;

commit;
