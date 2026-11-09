begin;

-- Nutrition configuration is an informational, versioned singleton. Values are
-- supplied by an administrator and are deliberately not seeded here.
alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved','nutrition.config_published'
));

create policy nutrition_config_admin_read_all on public.nutrition_config for select to authenticated
  using ((select public.current_app_role()) = 'ADMIN' and (select public.current_account_is_active()));

create function public.prevent_nutrition_config_rewrite()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.updated_by is not null and new.updated_by is null
    and new.config_version is not distinct from old.config_version
    and new.activity_factors is not distinct from old.activity_factors
    and new.goal_adjustments is not distinct from old.goal_adjustments
    and new.source_note is not distinct from old.source_note
    and new.effective_at is not distinct from old.effective_at
    and new.created_at is not distinct from old.created_at then
    return new;
  end if;
  raise exception 'Las versiones de configuración nutricional son inmutables.' using errcode='42501';
end;
$$;
revoke all on function public.prevent_nutrition_config_rewrite() from public,anon,authenticated;
create trigger nutrition_config_immutable_rows
  before update or delete on public.nutrition_config
  for each row execute function public.prevent_nutrition_config_rewrite();

create function public.admin_publish_nutrition_config(p_config jsonb, p_expected_latest_version integer)
returns public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_version integer;
  v_latest integer;
  v_activity jsonb;
  v_goals jsonb;
  v_note text;
  v_effective_at timestamptz;
  v_activity_key text;
  v_goal_key text;
  v_goal jsonb;
  v_number numeric;
  v_bound numeric;
  v_saved public.nutrition_config;
begin
  -- All admin mutations use the catalog lock before personal-account locks.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede publicar la configuración.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();

  if p_expected_latest_version is null or p_expected_latest_version < 0
    or jsonb_typeof(p_config) is distinct from 'object'
    or exists(select 1 from jsonb_object_keys(p_config) k where k not in ('activity_factors','goal_adjustments','source_note','effective_at'))
    or jsonb_typeof(p_config->'activity_factors') is distinct from 'object'
    or jsonb_typeof(p_config->'goal_adjustments') is distinct from 'object'
    or jsonb_typeof(p_config->'source_note') is distinct from 'string'
    or jsonb_typeof(p_config->'effective_at') is distinct from 'string' then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  v_activity := p_config->'activity_factors';
  v_goals := p_config->'goal_adjustments';
  v_note := p_config->>'source_note';
  if length(trim(v_note)) not between 1 and 2000
    or (select count(*) from jsonb_object_keys(v_activity)) <> 5
    or exists(select 1 from jsonb_object_keys(v_activity) k where k not in ('sedentary','light','moderate','active','very-active'))
    or (select count(*) from jsonb_object_keys(v_goals)) <> 4
    or exists(select 1 from jsonb_object_keys(v_goals) k where k not in ('lose','maintain','gain','gain-muscle')) then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  foreach v_activity_key in array array['sedentary','light','moderate','active','very-active'] loop
    if jsonb_typeof(v_activity->v_activity_key) is distinct from 'number' then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
    v_number := (v_activity->>v_activity_key)::numeric;
    if v_number <= 0 or v_number > 10 or scale(v_number) > 6 then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
  end loop;

  foreach v_goal_key in array array['lose','maintain','gain','gain-muscle'] loop
    v_goal := v_goals->v_goal_key;
    if jsonb_typeof(v_goal) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(v_goal)) <> 2
      or exists(select 1 from jsonb_object_keys(v_goal) k where k not in ('minimum','maximum'))
      or jsonb_typeof(v_goal->'minimum') is distinct from 'number'
      or jsonb_typeof(v_goal->'maximum') is distinct from 'number' then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
    v_number := (v_goal->>'minimum')::numeric;
    v_bound := (v_goal->>'maximum')::numeric;
    if v_number <> trunc(v_number) or v_bound <> trunc(v_bound)
      or v_number < -10000 or v_number > 10000 or v_bound < -10000 or v_bound > 10000 or v_number > v_bound then
      raise exception 'La configuración nutricional no es válida.' using errcode='22023';
    end if;
  end loop;

  -- Require an explicit, timezone-bearing ISO value so retries preserve the
  -- originally requested effective date instead of inheriting a new default.
  if p_config->>'effective_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;
  v_effective_at := (p_config->>'effective_at')::timestamptz;
  if not isfinite(v_effective_at) then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
  end if;

  v_version := p_expected_latest_version + 1;
  -- Slot comparison precedes latest-version validation for retry idempotency.
  select n.* into v_saved from public.nutrition_config n where n.config_version=v_version;
  if found then
    if v_saved.activity_factors=v_activity and v_saved.goal_adjustments=v_goals
      and v_saved.source_note=v_note and v_saved.effective_at=v_effective_at and v_saved.updated_by=v_actor then
      return v_saved;
    end if;
    raise exception 'La versión solicitada ya existe con otros datos; recargá la configuración.' using errcode='40001';
  end if;
  select max(n.config_version) into v_latest from public.nutrition_config n;
  if coalesce(v_latest,0) <> p_expected_latest_version then
    raise exception 'La configuración cambió; recargá antes de publicar.' using errcode='40001';
  end if;

  insert into public.nutrition_config(config_version,activity_factors,goal_adjustments,source_note,effective_at,updated_by)
    values(v_version,v_activity,v_goals,v_note,v_effective_at,v_actor) returning * into v_saved;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'nutrition.config_published',jsonb_build_object('version',v_version,'effective_at',v_effective_at));
  return v_saved;
exception
  when serialization_failure or deadlock_detected then raise;
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'La configuración nutricional no es válida.' using errcode='22023';
end;
$$;
revoke all on function public.admin_publish_nutrition_config(jsonb,integer) from public,anon;
grant execute on function public.admin_publish_nutrition_config(jsonb,integer) to authenticated;

create function public.get_current_nutrition_config()
returns public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_saved public.nutrition_config;
begin
  if v_actor is null or not (select public.current_account_is_active()) then
    raise exception 'Se requiere una cuenta activa.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  select n.* into v_saved from public.nutrition_config n
    where n.effective_at <= statement_timestamp()
    order by n.effective_at desc,n.config_version desc limit 1;
  if not found then return null; end if;
  return v_saved;
end;
$$;
revoke all on function public.get_current_nutrition_config() from public,anon;
grant execute on function public.get_current_nutrition_config() to authenticated;

create function public.admin_list_nutrition_configs()
returns setof public.nutrition_config
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.lock_my_relational_account();
  if (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede consultar las versiones.' using errcode='42501';
  end if;
  return query select n.* from public.nutrition_config n order by n.config_version desc;
end;
$$;
revoke all on function public.admin_list_nutrition_configs() from public,anon;
grant execute on function public.admin_list_nutrition_configs() to authenticated;

revoke insert,update,delete on public.nutrition_config from public,anon,authenticated;
grant select on public.nutrition_config to authenticated;

commit;
