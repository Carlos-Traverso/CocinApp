begin;

alter table public.meal_plans add column version bigint not null default 1 check (version > 0);

-- Replace one complete week, preserving the plan ID and its shopping references.
-- Slot IDs are server-generated; date/shift/position identify a slot in a save.
create function public.save_my_meal_plan(p_week_start date, p_slots jsonb, p_expected_version bigint)
returns public.meal_plans language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; slot jsonb; field text; recipe public.recipes;
  saved public.meal_plans; existing_version bigint; matched bigint := 0;
begin
  actor := public.lock_my_relational_account();
  if p_week_start is null or not isfinite(p_week_start) or extract(isodow from p_week_start) <> 1
    or p_expected_version is null or p_expected_version < 0
    or jsonb_typeof(p_slots) is distinct from 'array' then
    raise exception 'La semana, la versión o la planificación no son válidas.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_slots) > 140 then
    raise exception 'La planificación admite hasta 140 entradas por semana.' using errcode = '22023';
  end if;
  for slot in select value from jsonb_array_elements(p_slots) loop
    if jsonb_typeof(slot) is distinct from 'object' then
      raise exception 'Formato de entrada de planificación inválido.' using errcode = '22023';
    end if;
    if exists(select 1 from jsonb_object_keys(slot) k where k not in
      ('meal_date','meal_shift','recipe_id','portions','position')) then
      raise exception 'La planificación contiene campos no admitidos.' using errcode = '22023';
    end if;
    foreach field in array array['meal_date','meal_shift','recipe_id'] loop
      if jsonb_typeof(slot->field) is distinct from 'string' then
        raise exception 'Falta una fecha, turno o receta válida.' using errcode = '22023';
      end if;
    end loop;
    if (slot->>'meal_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or (slot->>'meal_date')::date < p_week_start or (slot->>'meal_date')::date >= p_week_start + 7
      or slot->>'meal_shift' not in ('breakfast','lunch','snack','dinner') then
      raise exception 'La fecha o el turno no corresponden a esta semana.' using errcode = '22023';
    end if;
    if jsonb_typeof(slot->'portions') is distinct from 'number' then
      raise exception 'Las porciones deben ser un número entero.' using errcode = '22023';
    end if;
    if (slot->>'portions')::numeric not between 1 and 20
      or trunc((slot->>'portions')::numeric) <> (slot->>'portions')::numeric then
      raise exception 'Las porciones deben estar entre 1 y 20.' using errcode = '22023';
    end if;
    if slot ? 'position' then
      if jsonb_typeof(slot->'position') is distinct from 'number' then
        raise exception 'La posición debe ser un número entero.' using errcode = '22023';
      end if;
      if (slot->>'position')::numeric not between 1 and 100
        or trunc((slot->>'position')::numeric) <> (slot->>'position')::numeric then
        raise exception 'La posición debe estar entre 1 y 100.' using errcode = '22023';
      end if;
    end if;
    -- Validate the UUID before passing it to the lock/visibility query.
    perform (slot->>'recipe_id')::uuid;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_slots) s
    group by s->>'meal_date',s->>'meal_shift',coalesce((s->>'position')::numeric::integer,1) having count(*) > 1) then
    raise exception 'Hay posiciones repetidas en la planificación.' using errcode = '22023';
  end if;

  -- Stable lock order; validate the locked rows, so publication/archival changes
  -- cannot race between validation and the final slot inserts.
  for recipe in select r.* from public.recipes r
    where r.id in (select (s->>'recipe_id')::uuid from jsonb_array_elements(p_slots) s)
    order by r.id for share
  loop
    if not recipe.active or recipe.is_deleted or (
      recipe.owner_user_id = actor or (recipe.recipe_source='official' and recipe.publication_status='published')
    ) is not true then
      raise exception 'Hay recetas no disponibles para esta cuenta.' using errcode = '42501';
    end if;
    matched := matched + 1;
  end loop;
  if matched <> (select count(distinct (s->>'recipe_id')::uuid) from jsonb_array_elements(p_slots) s) then
    raise exception 'Hay recetas no disponibles para esta cuenta.' using errcode = '42501';
  end if;
  select version into existing_version from public.meal_plans
    where owner_user_id=actor and week_start=p_week_start for update;
  if coalesce(existing_version,0) <> p_expected_version then
    raise exception 'La planificación cambió en otra sesión. Recargala antes de guardar.' using errcode = '40001';
  end if;
  insert into public.meal_plans(owner_user_id,week_start,updated_at)
    values(actor,p_week_start,clock_timestamp())
  on conflict (owner_user_id,week_start) do update set
    version=meal_plans.version+1,updated_at=excluded.updated_at
  returning * into saved;
  delete from public.meal_plan_slots where plan_id=saved.id;
  insert into public.meal_plan_slots(plan_id,meal_date,meal_shift,recipe_id,portions,position)
    select saved.id,(s->>'meal_date')::date,s->>'meal_shift',(s->>'recipe_id')::uuid,
      (s->>'portions')::numeric::integer,coalesce((s->>'position')::numeric::integer,1)
    from jsonb_array_elements(p_slots) s;
  return saved;
exception
  when data_exception or integrity_constraint_violation then
    raise exception 'Los datos de planificación no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.save_my_meal_plan(date,jsonb,bigint) from public, anon;
grant execute on function public.save_my_meal_plan(date,jsonb,bigint) to authenticated;

commit;
