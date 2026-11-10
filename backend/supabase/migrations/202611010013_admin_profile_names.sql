begin;

-- Preserve preferences for tags that have since been retired. A caller may
-- keep an inactive key already attached to their account, but cannot add one.
create or replace function public.save_my_profile(p_profile jsonb, p_preference_keys text[], p_expected_version bigint)
returns public.perfiles language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid; saved public.perfiles; existing_version bigint;
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
  select coalesce(array_agg(id), '{}'::uuid[]) into tag_ids from (
    select tags.id from public.etiquetas_dieteticas tags
    where tags.tag_key = any(p_preference_keys)
      and (tags.active or exists(select 1 from public.preferencias_dieteticas_usuario pref
        where pref.user_id=actor and pref.dietary_tag_id=tags.id))
    order by tags.id for share of tags
  ) selected_tags;
  if cardinality(tag_ids) <> cardinality(p_preference_keys) then
    raise exception 'Hay preferencias no disponibles.' using errcode = '22023';
  end if;
  select version into existing_version from public.perfiles where user_id=actor for update;
  if coalesce(existing_version,0) <> p_expected_version then
    raise exception 'El perfil cambió en otra sesión. Recargalo antes de guardar.' using errcode = '40001';
  end if;
  insert into public.perfiles(user_id,display_name,birth_date,weight_kg,height_cm,metabolic_sex,activity_level,goal,version,updated_at)
  values(actor,trim(p_profile->>'display_name'),birth,(p_profile->>'weight_kg')::numeric,
    (p_profile->>'height_cm')::numeric,p_profile->>'metabolic_sex',p_profile->>'activity_level',p_profile->>'goal',1,clock_timestamp())
  on conflict (user_id) do update set display_name=excluded.display_name,birth_date=excluded.birth_date,
    weight_kg=excluded.weight_kg,height_cm=excluded.height_cm,metabolic_sex=excluded.metabolic_sex,
    activity_level=excluded.activity_level,goal=excluded.goal,version=perfiles.version+1,updated_at=excluded.updated_at
  returning * into saved;
  delete from public.preferencias_dieteticas_usuario where user_id=actor;
  insert into public.preferencias_dieteticas_usuario(user_id,dietary_tag_id) select actor,unnest(tag_ids);
  return saved;
exception
  when data_exception or check_violation or not_null_violation then
    raise exception 'Los datos del perfil no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.save_my_profile(jsonb,text[],bigint) from public, anon, service_role;
grant execute on function public.save_my_profile(jsonb,text[],bigint) to authenticated;

-- Profile names are relational data. Keep the legacy JSON document untouched
-- for clients that have not yet cut over.
create or replace function public.admin_set_profile_name(
  p_user_id uuid,
  p_display_name text
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  existing_name text;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La operación requiere aislamiento READ COMMITTED.' using errcode = '25000';
  end if;
  if actor is null then
    raise exception 'Se requiere una sesión activa.' using errcode = '42501';
  end if;
  if p_user_id is null or p_display_name is null
    or length(trim(p_display_name)) not between 1 and 80 then
    raise exception 'El nombre debe tener entre 1 y 80 caracteres.' using errcode = '22023';
  end if;

  -- Order with role/status changes, then serialize against the target's own
  -- profile saves. Re-check authorization after both locks are held.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cocinapp.personal:' || p_user_id::text, 0)
  );
  perform 1 from auth.users as users where users.id = actor for share;
  if not found or not public.current_account_is_active()
    or public.current_app_role() <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora activa puede cambiar nombres de perfil.' using errcode = '42501';
  end if;

  perform 1 from auth.users as users where users.id = p_user_id for share;
  if not found then
    raise exception 'No existe la cuenta indicada.' using errcode = 'P0002';
  end if;

  select display_name into existing_name from public.perfiles where user_id = p_user_id for update;
  if found and existing_name = trim(p_display_name) then
    return;
  end if;

  if found then
    update public.perfiles set display_name = trim(p_display_name),
      version = version + 1, updated_at = clock_timestamp()
      where user_id = p_user_id;
  else
    insert into public.perfiles(user_id, display_name, version, updated_at)
      values (p_user_id, trim(p_display_name), 1, clock_timestamp());
  end if;

  insert into public.registro_auditoria(actor_user_id, action, target_user_id)
    values (actor, 'user.name_updated', p_user_id);
end;
$$;
revoke all on function public.admin_set_profile_name(uuid, text) from public, anon, service_role;
grant execute on function public.admin_set_profile_name(uuid, text) to authenticated;

-- Preserve the existing return contract and role/active semantics while making
-- perfiles the canonical source. Auth metadata is fallback only when no row
-- with a usable relational display name exists.
create or replace function public.admin_list_users()
returns table(email text, display_name text, role text, active boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo una cuenta administradora puede consultar los usuarios.' using errcode = '42501';
  end if;
  return query
    select users.email::text,
      coalesce(nullif(trim(profiles.display_name), ''),
        nullif(trim(coalesce(users.raw_user_meta_data ->> 'name', users.raw_user_meta_data ->> 'full_name')), ''),
        split_part(users.email, '@', 1))::text,
      coalesce(roles.role, 'USER')::text,
      coalesce(status.active, true) and (users.banned_until is null or users.banned_until <= now())
    from auth.users as users
    left join public.roles_usuario as roles on roles.user_id = users.id
    left join public.estado_cuenta as status on status.user_id = users.id
    left join public.perfiles as profiles on profiles.user_id = users.id
    where users.email is not null
    order by users.created_at desc;
end;
$$;
revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

commit;
