begin;

alter table public.cooking_sessions add column version bigint not null default 1 check (version > 0);
alter table public.cooking_sessions add column requested_portions integer not null default 1 check (requested_portions between 1 and 20);
create function public.start_my_cooking_session(p_session_id uuid, p_recipe_id uuid, p_portions integer)
returns public.cooking_sessions language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; recipe_row public.recipes; saved public.cooking_sessions; snapshot jsonb; ingredient_rows jsonb; step_rows jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_session_id is null or p_recipe_id is null or p_portions is null or p_portions not between 1 and 20 then
    raise exception 'La sesión de cocina no es válida.' using errcode='22023';
  end if;
  select * into saved from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if found then
    if saved.recipe_id is distinct from p_recipe_id or saved.requested_portions is distinct from p_portions then raise exception 'La clave de sesión ya fue utilizada.' using errcode='23505'; end if;
    return saved;
  end if;
  select * into recipe_row from public.recipes r where r.id=p_recipe_id and r.active and not r.is_deleted
    and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
    for share;
  if not found then raise exception 'La receta no está disponible.' using errcode='42501'; end if;
  -- Trusted writers that add/remove recipe children must lock the parent recipe
  -- FOR UPDATE first. Clients have read-only catalog grants; this lock order
  -- makes the multi-query snapshot consistent with future write RPCs.
  perform 1 from public.recipe_ingredients ri where ri.recipe_id=p_recipe_id order by ri.id for share;
  perform 1 from public.recipe_steps s where s.recipe_id=p_recipe_id order by s.id for share;
  perform 1 from public.recipe_step_ingredients x join public.recipe_steps s on s.id=x.step_id
    where s.recipe_id=p_recipe_id order by x.step_id,x.recipe_ingredient_id for share of x;
  -- Lock every referenced catalog row in stable order before snapshotting. This
  -- prevents a concurrent admin edit from invalidating the future stock refs.
  perform 1 from public.recipe_ingredients ri
    join public.ingredients i on i.id=ri.ingredient_id
    join public.categories c on c.id=i.category_id
    join public.units u on u.id=ri.unit_id
    join public.units recipe_root on recipe_root.id=coalesce(u.base_unit_id,u.id)
    join public.units ingredient_base on ingredient_base.id=i.base_unit_id
    join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
    where ri.recipe_id=p_recipe_id order by ri.id
    for share of i,c,u,recipe_root,ingredient_base,ingredient_root;
  if exists(select 1 from public.recipe_ingredients ri
    join public.ingredients i on i.id=ri.ingredient_id join public.categories c on c.id=i.category_id
    join public.units u on u.id=ri.unit_id join public.units recipe_root on recipe_root.id=coalesce(u.base_unit_id,u.id)
    join public.units ingredient_base on ingredient_base.id=i.base_unit_id
    join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
    where ri.recipe_id=p_recipe_id and (not i.active or i.is_deleted or not c.active or c.is_deleted
      or not u.active or u.is_deleted or not recipe_root.active or recipe_root.is_deleted
      or not ingredient_base.active or ingredient_base.is_deleted or not ingredient_root.active or ingredient_root.is_deleted
      or recipe_root.id<>ingredient_root.id or recipe_root.dimension<>ingredient_root.dimension)) then
    raise exception 'La receta contiene referencias de catálogo no disponibles.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',ri.quantity,'unit',u.abbreviation,
    'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,'unitFactor',coalesce(u.equivalence_multiplier,1),
    'category',c.name) order by ri.position),'[]'::jsonb)
    into ingredient_rows from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
    join public.units u on u.id=ri.unit_id join public.units root on root.id=coalesce(u.base_unit_id,u.id)
    join public.categories c on c.id=i.category_id where ri.recipe_id=p_recipe_id;
  select coalesce(jsonb_agg(jsonb_build_object('instruction',s.instruction,'durationMinutes',coalesce(s.duration_minutes,0),
    'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',to_jsonb(s.utensils),
    'specialInstructions',s.special_instructions,'stepIngredients',coalesce(si.ingredients,'[]'::jsonb)) order by s.position),'[]'::jsonb)
    into step_rows from public.recipe_steps s left join lateral (
      select jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',coalesce(x.quantity_override,ri.quantity),
        'unit',u.abbreviation,'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,
        'unitFactor',coalesce(u.equivalence_multiplier,1),'category',c.name) order by ri.position) ingredients
      from public.recipe_step_ingredients x join public.recipe_ingredients ri on ri.id=x.recipe_ingredient_id
      join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id
      join public.units root on root.id=coalesce(u.base_unit_id,u.id) join public.categories c on c.id=i.category_id
      where x.step_id=s.id
    ) si on true where s.recipe_id=p_recipe_id;
  if jsonb_array_length(step_rows)=0 then raise exception 'La receta no tiene pasos.' using errcode='22023'; end if;
  snapshot := jsonb_build_object('id',recipe_row.id,'name',recipe_row.title,'description',recipe_row.description,
    'category',recipe_row.category_label,'minutes',recipe_row.total_minutes,'portions',recipe_row.portions,
    'difficulty',recipe_row.difficulty,'ingredients',ingredient_rows,'steps',step_rows,
    'symbol',recipe_row.symbol,'color',recipe_row.color,'image',recipe_row.image_path,
    'imageAlt',recipe_row.image_alt,'crossContaminationNote',recipe_row.cross_contamination_note);
  insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,recipe_version,portions,requested_portions,client_idempotency_key)
    values(p_session_id,actor,p_recipe_id,snapshot,null,p_portions,p_portions,p_session_id) returning * into saved;
  insert into public.cooking_session_steps(session_id,step_position) select p_session_id,n from generate_series(1,jsonb_array_length(step_rows)) n;
  return saved;
exception when unique_violation then raise exception 'La sesión ya existe.' using errcode='23505';
  when check_violation or not_null_violation or foreign_key_violation or data_exception then raise exception 'La solicitud de cocina no es válida.' using errcode='22023';
end; $$;

create function public.get_my_cooking_session(p_session_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  select to_jsonb(s) || jsonb_build_object('steps',coalesce((select jsonb_agg(to_jsonb(cs) || jsonb_build_object(
      'remaining_ms',case when cs.timer_state='running' then greatest(0,(extract(epoch from (cs.timer_deadline_at-clock_timestamp()))*1000)::bigint) else cs.remaining_ms end
    ) order by cs.step_position) from public.cooking_session_steps cs where cs.session_id=s.id),'[]'::jsonb))
    into result from public.cooking_sessions s where s.id=p_session_id and s.owner_user_id=actor and s.finished_at is null;
  if result is null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  return result;
end; $$;

create function public.update_my_cooking_session(p_session_id uuid,p_expected_version bigint,p_action text,p_step integer default null,p_portions integer default null)
returns public.cooking_sessions language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; saved public.cooking_sessions; step_count integer; timer_row public.cooking_session_steps; duration_ms bigint; remaining bigint; timer_now timestamptz;
begin
  actor:=public.lock_my_relational_account();
  if p_session_id is null or p_expected_version is null or p_expected_version<1 or p_action is null
    or p_action not in ('move','complete','uncomplete','timer_start','timer_pause','timer_resume','timer_reset','timer_finish','portions')
    or (p_action='portions' and (p_portions is null or p_portions not between 1 and 20 or p_step is not null))
    or (p_action<>'portions' and p_portions is not null) then
    raise exception 'La actualización de cocina no es válida.' using errcode='22023';
  end if;
  select * into saved from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if not found or saved.finished_at is not null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  if saved.version<>p_expected_version then raise exception 'La sesión cambió. Recargala antes de continuar.' using errcode='40001'; end if;
  step_count:=jsonb_array_length(saved.recipe_snapshot->'steps');
  if p_action='portions' then
    update public.cooking_sessions set portions=p_portions,version=version+1 where id=p_session_id returning * into saved;
  elsif p_action='move' then
    if p_step is null or p_step<0 or p_step>=step_count then raise exception 'El paso indicado no es válido.' using errcode='22023'; end if;
    if p_step<>saved.current_step then
      select * into timer_row from public.cooking_session_steps where session_id=p_session_id and step_position=saved.current_step+1 for update;
      if timer_row.timer_state='running' then
        timer_now:=clock_timestamp();
        remaining:=greatest(0,(extract(epoch from (timer_row.timer_deadline_at-timer_now))*1000)::bigint);
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=null,
          timer_state=case when remaining=0 then 'finished' else 'paused' end
          where session_id=p_session_id and step_position=saved.current_step+1;
      end if;
    end if;
    update public.cooking_sessions set current_step=p_step,version=version+1 where id=p_session_id returning * into saved;
  else
    if p_step is null or p_step<0 or p_step>=step_count then raise exception 'El paso indicado no es válido.' using errcode='22023'; end if;
    if p_action in ('timer_start','timer_pause','timer_resume','timer_reset','timer_finish') and p_step<>saved.current_step then
      raise exception 'El temporizador solo se puede cambiar para el paso actual.' using errcode='22023';
    end if;
    select * into timer_row from public.cooking_session_steps where session_id=p_session_id and step_position=p_step+1 for update;
    if p_action='complete' then update public.cooking_session_steps set completed_at=coalesce(completed_at,clock_timestamp()) where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='uncomplete' then update public.cooking_session_steps set completed_at=null where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='timer_start' then
      duration_ms:=coalesce((saved.recipe_snapshot->'steps'->p_step->>'durationMinutes')::bigint,0)*60000;
      if duration_ms not between 1 and 86400000 then raise exception 'El paso no tiene una duración de temporizador válida.' using errcode='22023'; end if;
      if timer_row.timer_state='running' then return saved;
      else
        if timer_row.timer_state='idle' or timer_row.timer_state='finished' then remaining:=duration_ms; else remaining:=timer_row.remaining_ms; end if;
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=clock_timestamp()+remaining*interval '1 millisecond',timer_state='running' where session_id=p_session_id and step_position=p_step+1;
      end if;
    elsif p_action='timer_pause' then
      if timer_row.timer_state='running' then remaining:=greatest(0,(extract(epoch from (timer_row.timer_deadline_at-clock_timestamp()))*1000)::bigint);
        update public.cooking_session_steps set remaining_ms=remaining,timer_deadline_at=null,timer_state=case when remaining=0 then 'finished' else 'paused' end where session_id=p_session_id and step_position=p_step+1;
      end if;
    elsif p_action='timer_resume' then
      if timer_row.timer_state='paused' and timer_row.remaining_ms>0 then update public.cooking_session_steps set timer_deadline_at=clock_timestamp()+remaining_ms*interval '1 millisecond',timer_state='running' where session_id=p_session_id and step_position=p_step+1; end if;
    elsif p_action='timer_reset' then update public.cooking_session_steps set remaining_ms=null,timer_deadline_at=null,timer_state='idle' where session_id=p_session_id and step_position=p_step+1;
    elsif p_action='timer_finish' then update public.cooking_session_steps set remaining_ms=0,timer_deadline_at=null,timer_state='finished' where session_id=p_session_id and step_position=p_step+1;
    end if;
    update public.cooking_sessions set version=version+1 where id=p_session_id returning * into saved;
  end if;
  return saved;
exception when unique_violation then raise exception 'No se pudo actualizar la sesión.' using errcode='23505';
  when check_violation or not_null_violation or foreign_key_violation or data_exception then raise exception 'La actualización de cocina no es válida.' using errcode='22023';
end; $$;

revoke all on function public.start_my_cooking_session(uuid,uuid,integer),public.get_my_cooking_session(uuid),public.update_my_cooking_session(uuid,bigint,text,integer,integer) from public,anon;
grant execute on function public.start_my_cooking_session(uuid,uuid,integer),public.get_my_cooking_session(uuid),public.update_my_cooking_session(uuid,bigint,text,integer,integer) to authenticated;
revoke insert,update,delete on public.cooking_sessions,public.cooking_session_steps from anon,authenticated;
commit;
