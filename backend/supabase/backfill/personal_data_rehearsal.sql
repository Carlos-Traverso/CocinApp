-- REHEARSAL ONLY. Requires the relational schema and merged recipe backfill.
-- Run on an isolated copy as the database operator; never as an application user.
-- No legacy rows or pantry quantities are modified. All inserts roll back.
begin;
set local timezone = 'UTC';
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A consistent source snapshot is required for reconciliation.
lock table public.personal_data in share mode;
lock table public.recipes in share mode;

do $$
declare row_data record; item jsonb; p jsonb; target_recipe uuid; event_id uuid;
  session_id uuid; target_plan uuid; meal_date date; week_start date;
  meal_shift text; cooked_at timestamptz; started_at timestamptz;
  expected_count bigint; actual_count bigint;
begin
  if exists(select 1 from public.profiles)
    or exists(select 1 from public.user_dietary_preferences)
    or exists(select 1 from public.favorite_recipes)
    or exists(select 1 from public.meal_plans)
    or exists(select 1 from public.meal_plan_slots)
    or exists(select 1 from public.shopping_lists)
    or exists(select 1 from public.cooking_sessions)
    or exists(select 1 from public.cooking_events) then
    raise exception 'Destino personal no vacío: se rechaza sobrescribir registros.';
  end if;
  if exists(select 1 from public.personal_data where
    (data_key = 'profile' and jsonb_typeof(value) <> 'object')
    or (data_key <> 'profile' and jsonb_typeof(value) <> 'array')) then
    raise exception 'Formato de documento personal no soportado.';
  end if;
  if exists(select 1 from public.personal_data
    where data_key in ('cooking_progress','shopping') and jsonb_array_length(value) > 0) then
    raise exception 'Hay compras o sesiones activas nuevas: requieren su conversor antes de continuar.';
  end if;
  if exists(select 1 from public.personal_data d
    where not exists(select 1 from auth.users u where u.id = d.user_id)) then
    raise exception 'Documento personal sin cuenta Auth correspondiente.';
  end if;

  -- Stable canonical tag keys. Existing tag rows remain authoritative.
  insert into public.dietary_tags(id, tag_key, label)
  select md5('cocinapp:dietary:' || key)::uuid, key, label
  from (values ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),
    ('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos')) v(key,label)
  on conflict (tag_key) do nothing;

  for row_data in select user_id, value, updated_at from public.personal_data where data_key='profile' loop
    p := row_data.value;
    if jsonb_typeof(p -> 'name') is distinct from 'string'
      or length(trim(p ->> 'name')) not between 1 and 120 then
      raise exception 'Perfil sin nombre válido.';
    end if;
    if exists(select 1 from jsonb_object_keys(p) key where key not in
      ('name','email','birthDate','weightKg','heightCm','metabolicSex','activityLevel','goal','preferences')) then
      raise exception 'Perfil con campos no contemplados por el conversor.';
    end if;
    if (p ? 'weightKg' and jsonb_typeof(p -> 'weightKg') <> 'number')
      or (p ? 'heightCm' and jsonb_typeof(p -> 'heightCm') <> 'number')
      or (p ? 'preferences' and jsonb_typeof(p -> 'preferences') <> 'array') then
      raise exception 'Tipos de campos de perfil incompatibles.';
    end if;
    insert into public.profiles(user_id,display_name,birth_date,weight_kg,height_cm,
      metabolic_sex,activity_level,goal,created_at,updated_at)
    values(row_data.user_id,p ->> 'name',nullif(p ->> 'birthDate','')::date,
      (p ->> 'weightKg')::numeric,(p ->> 'heightCm')::numeric,p ->> 'metabolicSex',
      p ->> 'activityLevel',p ->> 'goal',row_data.updated_at,row_data.updated_at);
    -- Email stays in Auth; no second email source is introduced.
    for item in select value from jsonb_array_elements(coalesce(p -> 'preferences','[]'::jsonb)) loop
      if jsonb_typeof(item) <> 'string' or not exists(select 1 from public.dietary_tags where tag_key=item #>> '{}') then
        raise exception 'Preferencia dietética no reconocida.';
      end if;
      insert into public.user_dietary_preferences(user_id,dietary_tag_id,created_at)
      select row_data.user_id,id,row_data.updated_at from public.dietary_tags where tag_key=item #>> '{}'
      on conflict (user_id,dietary_tag_id) do nothing;
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='favorites' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'string' then raise exception 'Favorito con identificador inválido.'; end if;
      select id into target_recipe from public.recipes where legacy_id=item #>> '{}';
      if target_recipe is null then raise exception 'Favorito sin receta migrada.'; end if;
      insert into public.favorite_recipes(user_id,recipe_id,created_at)
      values(row_data.user_id,target_recipe,row_data.updated_at);
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='meal_plan' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object'
        or jsonb_typeof(item -> 'recipeId') is distinct from 'string'
        or jsonb_typeof(item -> 'portions') is distinct from 'number' then
        raise exception 'Asignación del plan con formato inválido.';
      end if;
      meal_date := (item ->> 'date')::date;
      week_start := meal_date - (extract(isodow from meal_date)::integer - 1);
      meal_shift := case item ->> 'meal' when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch'
        when 'Merienda' then 'snack' when 'Cena' then 'dinner' end;
      if meal_date is null or meal_shift is null
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Fecha, turno o porciones del plan inválidos.';
      end if;
      target_plan := md5('cocinapp:plan:' || row_data.user_id::text || ':' || week_start::text)::uuid;
      insert into public.meal_plans(id,owner_user_id,week_start,created_at,updated_at)
      values(target_plan,row_data.user_id,week_start,row_data.updated_at,row_data.updated_at)
      on conflict on constraint meal_plans_owner_user_id_week_start_key do nothing;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Plan sin receta migrada.'; end if;
      insert into public.meal_plan_slots(id,plan_id,meal_date,meal_shift,recipe_id,portions,created_at)
      values(md5('cocinapp:slot:' || row_data.user_id::text || ':' || meal_date::text || ':' || meal_shift)::uuid,
        target_plan,meal_date,meal_shift,target_recipe,(item ->> 'portions')::integer,row_data.updated_at);
    end loop;
  end loop;

  -- Each legacy history event has its own closed synthetic session. The recipe
  -- snapshot reflects the catalog available during migration, not an invented
  -- historical recipe version. No consumption/stock deductions are fabricated.
  for row_data in select user_id,value,updated_at from public.personal_data where data_key='cooking_history' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object' or nullif(item ->> 'id','') is null
        or jsonb_typeof(item -> 'portions') is distinct from 'number'
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Evento de cocina con formato inválido.';
      end if;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Historial sin receta migrada.'; end if;
      cooked_at := (item ->> 'cookedAt')::timestamptz;
      started_at := coalesce((item ->> 'sessionStartedAt')::timestamptz,cooked_at);
      if cooked_at is null or started_at > cooked_at then raise exception 'Fechas del historial inválidas.'; end if;
      event_id := md5('cocinapp:history:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      session_id := md5('cocinapp:history-session:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      select jsonb_build_object('legacyRecipeId',r.legacy_id,'title',r.title,
        'snapshotOrigin','migration_catalog','legacyEvent',item,
        'ingredients',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.recipe_ingredients i where i.recipe_id=r.id),
        'steps',(select coalesce(jsonb_agg(to_jsonb(s) order by s.position),'[]'::jsonb) from public.recipe_steps s where s.recipe_id=r.id))
        into p from public.recipes r where r.id=target_recipe;
      insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,
        client_idempotency_key,started_at,finished_at)
      values(session_id,row_data.user_id,target_recipe,p,(item ->> 'portions')::integer,
        session_id,started_at,cooked_at);
      insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
      values(event_id,row_data.user_id,session_id,target_recipe,p,(item ->> 'portions')::integer,cooked_at);
    end loop;
  end loop;

  -- Empty legacy shopping documents become empty active lists; their rows remain
  -- untouched. Non-empty lists/progress were rejected before inserting anything.
  insert into public.shopping_lists(id,owner_user_id,created_at,updated_at)
  select md5('cocinapp:shopping:' || user_id::text)::uuid,user_id,updated_at,updated_at
  from public.personal_data where data_key='shopping';

  select count(*) into expected_count from public.personal_data where data_key='profile';
  select count(*) into actual_count from public.profiles;
  if expected_count <> actual_count then raise exception 'Reconciliación de perfiles fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='favorites';
  select count(*) into actual_count from public.favorite_recipes;
  if expected_count <> actual_count then raise exception 'Reconciliación de favoritos fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='meal_plan';
  select count(*) into actual_count from public.meal_plan_slots;
  if expected_count <> actual_count then raise exception 'Reconciliación del plan fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='cooking_history';
  select count(*) into actual_count from public.cooking_events;
  if expected_count <> actual_count then raise exception 'Reconciliación del historial fallida.'; end if;
exception when others then
  -- Do not include SQLERRM/DETAIL: database cast errors can contain private values.
  raise exception 'Conversión personal cancelada; datos inválidos, destino ocupado o referencias no migradas. SQLSTATE %.',sqlstate;
end;
$$;

select 'profiles' as dataset,count(*) as converted from public.profiles
union all select 'preferences',count(*) from public.user_dietary_preferences
union all select 'favorites',count(*) from public.favorite_recipes
union all select 'plan_slots',count(*) from public.meal_plan_slots
union all select 'cooking_history',count(*) from public.cooking_events
union all select 'empty_active_shopping_lists',count(*) from public.shopping_lists;

rollback;
select 'REHEARSAL COMPLETE: all personal conversion inserts rolled back' as result;
