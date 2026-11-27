begin;

create table public.configuraciones_iniciales_pendientes (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.configuraciones_iniciales_pendientes enable row level security;
revoke all on table public.configuraciones_iniciales_pendientes from public, anon, authenticated, service_role;

-- Only accounts created after installation enter the setup flow.
create function public.mark_new_account_onboarding_pending()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.configuraciones_iniciales_pendientes(user_id) values (new.id);
  return new;
end;
$$;
revoke all on function public.mark_new_account_onboarding_pending() from public, anon, authenticated, service_role;

create trigger mark_new_account_onboarding_pending
after insert on auth.users
for each row execute function public.mark_new_account_onboarding_pending();

create function public.get_my_onboarding_required()
returns boolean language plpgsql volatile security definer set search_path = '' set lock_timeout = '3s' as $$
declare actor uuid;
begin
  actor := public.lock_my_relational_account();
  return public.current_app_role() = 'USER' and exists (
    select 1 from public.configuraciones_iniciales_pendientes where user_id = actor
  );
end;
$$;

create function public.complete_my_onboarding(
  p_profile jsonb, p_preference_keys text[], p_expected_version bigint, p_relational boolean
)
returns void language plpgsql volatile security definer set search_path = '' set lock_timeout = '3s' as $$
declare
  actor uuid;
  account_email text;
  display_name text;
  birth_date date;
  legacy_profile jsonb;
begin
  actor := public.lock_my_relational_account();
  if public.current_app_role() is distinct from 'USER' then
    raise exception 'La configuración inicial requiere una cuenta de usuario.' using errcode = '42501';
  end if;

  -- Removing the marker first makes retries safe. A failed profile write
  -- rolls back the marker deletion within the same transaction.
  delete from public.configuraciones_iniciales_pendientes where user_id = actor;
  if not found then return; end if;
  if jsonb_typeof(p_profile) is distinct from 'object' or p_relational is null
    or p_profile->>'goal' is null or p_profile->>'goal' not in ('lose', 'maintain', 'gain', 'gain-muscle') then
    raise exception 'Seleccioná un objetivo válido antes de continuar.' using errcode = '22023';
  end if;

  if p_relational then
    perform public.save_my_profile(p_profile, p_preference_keys, p_expected_version);
    return;
  end if;

  -- Legacy clients still read the JSON profile. Match the relational input
  -- bounds before storing the same optional fields in the legacy format.
  display_name := trim(p_profile->>'display_name');
  if jsonb_typeof(p_profile->'display_name') is distinct from 'string'
    or length(display_name) not between 1 and 120
    or coalesce(jsonb_typeof(p_profile->'weight_kg'), 'null') not in ('number', 'null')
    or coalesce(jsonb_typeof(p_profile->'height_cm'), 'null') not in ('number', 'null')
    or (p_profile->>'weight_kg')::numeric not between 30 and 300
    or (p_profile->>'height_cm')::numeric not between 100 and 250
    or p_profile->>'activity_level' not in ('sedentary', 'light', 'moderate', 'active', 'very-active')
    or p_profile->>'metabolic_sex' not in ('female', 'male')
    or p_preference_keys is null
    or coalesce(array_ndims(p_preference_keys), 1) <> 1
    or not (p_preference_keys <@ array['gluten-free', 'vegetarian', 'vegan', 'lactose-free', 'nut-free']) then
    raise exception 'Los datos del perfil no son válidos.' using errcode = '22023';
  end if;
  if p_profile->>'birth_date' is not null then
    if p_profile->>'birth_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'Fecha de nacimiento inválida.' using errcode = '22023';
    end if;
    birth_date := (p_profile->>'birth_date')::date;
    if birth_date > current_date then
      raise exception 'Fecha de nacimiento inválida.' using errcode = '22023';
    end if;
  end if;

  select email into account_email from auth.users where id = actor;
  legacy_profile := jsonb_strip_nulls(jsonb_build_object(
    'name', display_name, 'email', account_email, 'birthDate', birth_date,
    'weightKg', p_profile->'weight_kg', 'heightCm', p_profile->'height_cm',
    'metabolicSex', p_profile->>'metabolic_sex', 'activityLevel', p_profile->>'activity_level',
    'goal', p_profile->>'goal', 'preferences', p_preference_keys
  ));
  insert into public.datos_personales(user_id, data_key, value)
  values (actor, 'profile', legacy_profile)
  on conflict (user_id, data_key)
  do update set value = excluded.value, updated_at = clock_timestamp();
exception
  when data_exception or check_violation or not_null_violation then
    raise exception 'Los datos del perfil no son válidos.' using errcode = '22023';
end;
$$;

revoke all on function public.get_my_onboarding_required() from public, anon, service_role;
revoke all on function public.complete_my_onboarding(jsonb, text[], bigint, boolean) from public, anon, service_role;
grant execute on function public.get_my_onboarding_required() to authenticated;
grant execute on function public.complete_my_onboarding(jsonb, text[], bigint, boolean) to authenticated;

commit;
