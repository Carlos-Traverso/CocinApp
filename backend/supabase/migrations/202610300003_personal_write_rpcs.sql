begin;

-- A complete profile + preference save uses optimistic concurrency.
alter table public.profiles add column version bigint not null default 1 check (version > 0);

-- Authorization point: after the account/ban locks and a fresh active check.
-- Shared advisory lock orders writes with existing admin role/status RPCs,
-- while allowing different accounts to write concurrently. Auth ban updates
-- conflict with FOR SHARE. Locks stay held until the calling transaction ends.
create function public.lock_my_relational_account()
returns uuid language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Se requiere una sesión activa.' using errcode = '42501';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(74539, 1);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.personal:' || actor::text, 0));
  perform 1 from auth.users where id = actor for share;
  if not found then raise exception 'Se requiere una sesión activa.' using errcode = '42501'; end if;
  perform 1 from public.account_status where user_id = actor for share;
  if not public.current_account_is_active() then
    raise exception 'La cuenta no está activa.' using errcode = '42501';
  end if;
  return actor;
end;
$$;
revoke all on function public.lock_my_relational_account() from public, anon, authenticated;

-- Full snapshot, not a patch: omitted optional fields become NULL. Version 0
-- means create only; an existing row requires its exact current version.
-- Preferences are saved in the same transaction and use stable tag_key values.
-- Email remains in Auth and is deliberately not a writable profile field.
create function public.save_my_profile(p_profile jsonb, p_preference_keys text[], p_expected_version bigint)
returns public.profiles language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; saved public.profiles; existing_version bigint;
  field text; tag_ids uuid[]; birth date;
begin
  actor := public.lock_my_relational_account();
  if jsonb_typeof(p_profile) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or p_preference_keys is null or cardinality(p_preference_keys) > 50
    or coalesce(array_ndims(p_preference_keys), 1) <> 1 then
    raise exception 'Formato de perfil o preferencias inválido.' using errcode = '22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_profile) k where k not in (
    'display_name','birth_date','weight_kg','height_cm','metabolic_sex','activity_level','goal')) then
    raise exception 'El perfil contiene campos no admitidos.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_profile->'display_name') is distinct from 'string'
    or length(trim(p_profile->>'display_name')) not between 1 and 120 then
    raise exception 'El nombre de perfil es obligatorio y admite hasta 120 caracteres.' using errcode = '22023';
  end if;
  foreach field in array array['birth_date','metabolic_sex','activity_level','goal'] loop
    if p_profile ? field and jsonb_typeof(p_profile->field) not in ('null','string') then
      raise exception 'Tipo de campo de perfil inválido.' using errcode = '22023';
    end if;
  end loop;
  foreach field in array array['weight_kg','height_cm'] loop
    if p_profile ? field and jsonb_typeof(p_profile->field) not in ('null','number') then
      raise exception 'Tipo de medida de perfil inválido.' using errcode = '22023';
    end if;
  end loop;
  -- Validate before numeric(6,2) rounds: values outside the domain must not
  -- become valid merely because the column rounds them toward a boundary.
  if (p_profile->>'weight_kg')::numeric not between 30 and 300
    or (p_profile->>'height_cm')::numeric not between 100 and 250 then
    raise exception 'Las medidas del perfil están fuera del rango admitido.' using errcode = '22023';
  end if;
  if p_profile->>'birth_date' is not null then
    if (p_profile->>'birth_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Fecha de nacimiento inválida.' using errcode = '22023';
    end if;
    birth := (p_profile->>'birth_date')::date;
    if birth > current_date then raise exception 'Fecha de nacimiento inválida.' using errcode = '22023'; end if;
  end if;
  if exists(select 1 from unnest(p_preference_keys) k where k is null or length(k) not between 2 and 50)
    or (select count(distinct k) from unnest(p_preference_keys) k) <> cardinality(p_preference_keys) then
    raise exception 'Preferencias inválidas o repetidas.' using errcode = '22023';
  end if;
  -- Lock definitions so a tag cannot be deactivated midway through this save.
  select coalesce(array_agg(id), '{}'::uuid[]) into tag_ids from (
    select id from public.dietary_tags where tag_key = any(p_preference_keys) and active order by id for share
  ) tags;
  if cardinality(tag_ids) <> cardinality(p_preference_keys) then
    raise exception 'Hay preferencias no disponibles.' using errcode = '22023';
  end if;
  select version into existing_version from public.profiles where user_id = actor for update;
  if coalesce(existing_version, 0) <> p_expected_version then
    raise exception 'El perfil cambió en otra sesión. Recargalo antes de guardar.' using errcode = '40001';
  end if;
  insert into public.profiles(user_id,display_name,birth_date,weight_kg,height_cm,metabolic_sex,activity_level,goal,version,updated_at)
  values(actor,trim(p_profile->>'display_name'),birth,(p_profile->>'weight_kg')::numeric,
    (p_profile->>'height_cm')::numeric,p_profile->>'metabolic_sex',p_profile->>'activity_level',p_profile->>'goal',1,clock_timestamp())
  on conflict (user_id) do update set display_name=excluded.display_name,birth_date=excluded.birth_date,
    weight_kg=excluded.weight_kg,height_cm=excluded.height_cm,metabolic_sex=excluded.metabolic_sex,
    activity_level=excluded.activity_level,goal=excluded.goal,version=profiles.version+1,updated_at=excluded.updated_at
  returning * into saved;
  delete from public.user_dietary_preferences where user_id=actor;
  insert into public.user_dietary_preferences(user_id,dietary_tag_id) select actor,unnest(tag_ids);
  return saved;
exception
  when data_exception or check_violation or not_null_violation then
    -- Suppress database DETAIL, which otherwise can include personal values.
    raise exception 'Los datos del perfil no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.save_my_profile(jsonb,text[],bigint) from public, anon;
grant execute on function public.save_my_profile(jsonb,text[],bigint) to authenticated;

-- Set desired state instead of toggling: retrying a request cannot reverse it.
create function public.set_my_favorite(p_recipe_id uuid, p_is_favorite boolean)
returns boolean language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; recipe public.recipes;
begin
  actor := public.lock_my_relational_account();
  if p_recipe_id is null or p_is_favorite is null then
    raise exception 'La receta y el estado de favorito son obligatorios.' using errcode = '22023';
  end if;
  if not p_is_favorite then
    delete from public.favorite_recipes where user_id=actor and recipe_id=p_recipe_id;
    return false;
  end if;
  select * into recipe from public.recipes where id=p_recipe_id for share;
  if not found or not recipe.active or recipe.is_deleted or (
    recipe.owner_user_id=actor or (recipe.recipe_source='official' and recipe.publication_status='published')
  ) is not true then
    raise exception 'La receta no está disponible para favoritos.' using errcode = '42501';
  end if;
  insert into public.favorite_recipes(user_id,recipe_id) values(actor,p_recipe_id) on conflict do nothing;
  return true;
end;
$$;
revoke all on function public.set_my_favorite(uuid,boolean) from public, anon;
grant execute on function public.set_my_favorite(uuid,boolean) to authenticated;

-- Table privileges remain SELECT-only; clients write only through these RPCs.
commit;
