begin;

alter table public.cooking_events add column deduct_stock boolean not null default false;

create function public.finish_my_cooking_session(p_session_id uuid, p_expected_version bigint, p_deduct_stock boolean)
returns public.cooking_events language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid; session_row public.cooking_sessions; event_row public.cooking_events;
  ingredient_row jsonb; lot public.pantry_items; used_rows jsonb := '[]'::jsonb;
  v_recipe_id uuid; v_ingredient_id uuid; root_id uuid; pantry_unit public.units; recipe_unit public.units;
  factor numeric; recipe_factor numeric; needed_root numeric; used_root numeric; lot_root numeric;
  take_root numeric; take_stock numeric; remaining numeric; snapshot_name text; snapshot_unit text;
  demand numeric; today date := current_date;
begin
  actor := public.lock_my_relational_account();
  if p_session_id is null or p_expected_version is null or p_expected_version < 1 or p_deduct_stock is null then
    raise exception 'La finalización de cocina no es válida.' using errcode='22023';
  end if;
  select * into session_row from public.cooking_sessions where id=p_session_id and owner_user_id=actor for update;
  if not found then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  select * into event_row from public.cooking_events where session_id=p_session_id;
  if found then
    if event_row.deduct_stock is distinct from p_deduct_stock then
      raise exception 'La decisión de descuento no coincide con la finalización guardada.' using errcode='22023';
    end if;
    return event_row;
  end if;
  if session_row.finished_at is not null then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
  if session_row.version<>p_expected_version then raise exception 'La sesión cambió. Recargala antes de continuar.' using errcode='40001'; end if;
  if jsonb_typeof(session_row.recipe_snapshot->'ingredients') is distinct from 'array'
    or jsonb_array_length(session_row.recipe_snapshot->'ingredients')>200
    or coalesce((session_row.recipe_snapshot->>'portions')::integer,0)<1 then
    raise exception 'La receta guardada no se puede finalizar.' using errcode='22023';
  end if;

  -- Lock every pantry lot up front in a stable order. Writes from pantry RPCs
  -- serialize here, so a shortage rolls back without partial deductions.
  if p_deduct_stock then
    perform 1 from public.pantry_items p where p.user_id=actor order by p.id for update;
    perform 1 from public.units u where u.id in (
      select (value->>'unitId')::uuid from jsonb_array_elements(session_row.recipe_snapshot->'ingredients')
      union select (value->>'unitRootId')::uuid from jsonb_array_elements(session_row.recipe_snapshot->'ingredients')
    ) order by u.id for share;
    for ingredient_row in select value from jsonb_array_elements(session_row.recipe_snapshot->'ingredients') loop
      if jsonb_typeof(ingredient_row->'ingredientId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitRootId') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unitFactor') is distinct from 'number'
        or jsonb_typeof(ingredient_row->'quantity') is distinct from 'number'
        or jsonb_typeof(ingredient_row->'name') is distinct from 'string'
        or jsonb_typeof(ingredient_row->'unit') is distinct from 'string' then
        raise exception 'La receta guardada contiene un ingrediente inválido.' using errcode='22023';
      end if;
      v_ingredient_id := (ingredient_row->>'ingredientId')::uuid;
      root_id := (ingredient_row->>'unitRootId')::uuid;
      recipe_factor := (ingredient_row->>'unitFactor')::numeric;
      demand := (ingredient_row->>'quantity')::numeric*session_row.portions::numeric
        /(session_row.recipe_snapshot->>'portions')::numeric;
      if demand<=0 or recipe_factor<=0 then raise exception 'La cantidad de receta no es válida.' using errcode='22023'; end if;
      needed_root := demand*recipe_factor; used_root:=0;
      for lot in
        select p.* from public.pantry_items p
        where p.user_id=actor and (p.expiry is null or p.expiry>=today) and p.quantity>0
          and (p.ingredient_ref=v_ingredient_id or (p.ingredient_ref is null
            and lower(regexp_replace(trim(p.name),'\s+',' ','g'))=lower(regexp_replace(trim(ingredient_row->>'name'),'\s+',' ','g'))))
        order by p.expiry nulls last,p.id
      loop
        select * into pantry_unit from public.units u where u.id=coalesce(lot.unit_ref,(select id from public.units where abbreviation=lot.unit))
          and u.abbreviation=lot.unit and u.active and not u.is_deleted for share;
        if not found then continue; end if;
        if not exists(select 1 from public.units root where root.id=root_id and root.active and not root.is_deleted and root.base_unit_id is null)
          or coalesce(pantry_unit.base_unit_id,pantry_unit.id)<>root_id
          or pantry_unit.dimension<>ingredient_row->>'unitDimension' then continue; end if;
        factor:=coalesce(pantry_unit.equivalence_multiplier,1);
        lot_root:=lot.quantity*factor;
        remaining:=needed_root-used_root;
        take_root:=least(remaining,lot_root);
        take_stock:=take_root/factor;
        if take_stock<>round(take_stock,4) then
          -- Use a whole representable lot amount only when it exactly advances
          -- the demand; otherwise fail instead of rounding through a deficit.
          take_stock:=least(lot.quantity,trunc(take_stock,4));
          take_root:=take_stock*factor;
        end if;
        if take_stock<=0 or take_root<=0 then continue; end if;
        update public.pantry_items set quantity=quantity-take_stock,updated_at=clock_timestamp() where id=lot.id;
        used_root:=used_root+take_root;
        if used_root>=needed_root then exit; end if;
      end loop;
      if used_root<>needed_root then raise exception 'La despensa no tiene cantidad suficiente o compatible.' using errcode='22023'; end if;
      select * into recipe_unit from public.units u where u.id=(ingredient_row->>'unitId')::uuid;
      if not found or coalesce(recipe_unit.base_unit_id,recipe_unit.id)<>root_id
        or used_root/recipe_factor<>round(used_root/recipe_factor,4) then
        raise exception 'La cantidad no se puede representar con la unidad de receta.' using errcode='22023';
      end if;
      snapshot_name:=ingredient_row->>'name'; snapshot_unit:=ingredient_row->>'unit';
      used_rows:=used_rows||jsonb_build_array(jsonb_build_object('ingredient_id',v_ingredient_id,
        'name_snapshot',snapshot_name,'quantity_used',used_root/recipe_factor,'unit_abbreviation_snapshot',snapshot_unit));
    end loop;
  end if;
  v_recipe_id:=session_row.recipe_id;
  insert into public.cooking_events(owner_user_id,session_id,recipe_id,recipe_snapshot,portions,deduct_stock)
    values(actor,p_session_id,v_recipe_id,session_row.recipe_snapshot,session_row.portions,p_deduct_stock) returning * into event_row;
  insert into public.cooking_event_ingredients(event_id,ingredient_id,name_snapshot,quantity_used,unit_abbreviation_snapshot)
    select event_row.id,
      case when count(distinct (r.value->>'ingredient_id')::uuid)=1 then (array_agg(distinct (r.value->>'ingredient_id')::uuid))[1] else null end,
      r.value->>'name_snapshot',sum((r.value->>'quantity_used')::numeric),r.value->>'unit_abbreviation_snapshot'
    from jsonb_array_elements(used_rows) r
    group by r.value->>'name_snapshot',r.value->>'unit_abbreviation_snapshot';
  update public.cooking_sessions set finished_at=clock_timestamp(),version=version+1 where id=p_session_id;
  update public.cooking_session_steps set remaining_ms=case when timer_state='running' then
      greatest(0,(extract(epoch from (timer_deadline_at-clock_timestamp()))*1000)::bigint) else remaining_ms end,
    timer_deadline_at=null,timer_state=case when timer_state='running' then 'paused' else timer_state end
    where session_id=p_session_id;
  return event_row;
exception when unique_violation then
  select * into event_row from public.cooking_events where session_id=p_session_id and owner_user_id=actor;
  if found and event_row.deduct_stock is not distinct from p_deduct_stock then return event_row; end if;
  raise exception 'La finalización de cocina no es válida.' using errcode='23505';
when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation or foreign_key_violation or data_exception then
  raise exception 'La finalización de cocina no es válida.' using errcode='22023';
end; $$;

revoke all on function public.finish_my_cooking_session(uuid,bigint,boolean) from public,anon;
grant execute on function public.finish_my_cooking_session(uuid,bigint,boolean) to authenticated;
revoke insert,update,delete on public.cooking_events,public.cooking_event_ingredients from anon,authenticated;
commit;
