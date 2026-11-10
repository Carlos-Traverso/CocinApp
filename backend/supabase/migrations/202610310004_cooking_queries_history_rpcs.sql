begin;

alter table public.cooking_events add column hidden_at timestamptz;
drop policy cooking_events_owner_read on public.cooking_events;
create policy cooking_events_owner_read on public.cooking_events for select to authenticated
  using (owner_user_id=(select auth.uid()) and hidden_at is null and (select public.current_account_is_active()));
create index cooking_events_owner_visible_page_idx
  on public.cooking_events(owner_user_id,cooked_at desc,id desc) where hidden_at is null;

create function public.get_my_cooking_history(p_limit integer default 30,p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 100 or ((p_before is null)<>(p_before_id is null)) then
    raise exception 'La página del historial no es válida.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(row_data order by cooked_at desc,id desc),'[]'::jsonb) into result from (
    select e.cooked_at,e.id,to_jsonb(e)||jsonb_build_object('ingredients',coalesce((
      select jsonb_agg(to_jsonb(i) order by i.name_snapshot,i.unit_abbreviation_snapshot)
      from public.cooking_event_ingredients i where i.event_id=e.id),'[]'::jsonb)) row_data
    from public.cooking_events e where e.owner_user_id=actor and e.hidden_at is null
      and (p_before is null or (e.cooked_at,e.id)<(p_before,p_before_id))
    order by e.cooked_at desc,e.id desc limit p_limit
  ) page;
  return result;
end; $$;

create function public.hide_my_cooking_history_entry(p_event_id uuid)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid;
begin
  actor:=public.lock_my_relational_account();
  if p_event_id is null then raise exception 'El evento no es válido.' using errcode='22023'; end if;
  update public.cooking_events set hidden_at=clock_timestamp()
    where id=p_event_id and owner_user_id=actor and hidden_at is null;
  return found;
end; $$;

create function public.clear_my_cooking_history()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; changed integer;
begin
  actor:=public.lock_my_relational_account();
  update public.cooking_events set hidden_at=clock_timestamp()
    where owner_user_id=actor and hidden_at is null;
  get diagnostics changed=row_count;
  return changed;
end; $$;

-- Checks against either a currently visible recipe or an owner's immutable session snapshot.
-- No client-provided quantities, unit factors, ingredient refs, or pantry amounts are trusted.
create function public.check_my_cooking_stock(p_recipe_id uuid default null,p_portions integer default null,p_session_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid; ingredients jsonb; base_portions integer; recipe_row public.recipes; session_row public.cooking_sessions;
  item jsonb; v_id uuid; v_ids uuid[]; v_root uuid; v_unit uuid; v_name text; v_dimension text; v_factor numeric;
  demand numeric; available_root numeric; required_root numeric; pantry public.pantry_items;
  pantry_unit public.units; pantry_factor numeric; output jsonb:='[]'::jsonb; row_result jsonb;
begin
  actor:=auth.uid();
  if actor is null or not public.current_account_is_active() then raise exception 'Se requiere una sesión activa.' using errcode='42501'; end if;
  if (p_session_id is null and (p_portions is null or p_portions not between 1 and 20)) or (p_session_id is null and p_recipe_id is null)
    or (p_session_id is not null and p_recipe_id is not null) then raise exception 'La consulta de despensa no es válida.' using errcode='22023'; end if;
  if p_session_id is not null then
    select * into session_row from public.cooking_sessions s where s.id=p_session_id and s.owner_user_id=actor;
    if not found then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
    ingredients:=session_row.recipe_snapshot->'ingredients';
    base_portions:=coalesce((session_row.recipe_snapshot->>'portions')::integer,0);
    if base_portions<1 then raise exception 'La sesión no está disponible.' using errcode='P0002'; end if;
    if p_portions is not null and p_portions<>session_row.portions then raise exception 'La consulta debe usar las porciones de la sesión.' using errcode='22023'; end if;
    p_portions:=session_row.portions;
  else
    select * into recipe_row from public.recipes r where r.id=p_recipe_id and r.active and not r.is_deleted
      and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor);
    if not found then raise exception 'La receta no está disponible.' using errcode='P0002'; end if;
    base_portions:=recipe_row.portions;
    select coalesce(jsonb_agg(jsonb_build_object('ingredientId',i.id,'name',i.name,'quantity',ri.quantity,'unit',u.abbreviation,
      'unitId',u.id,'unitRootId',root.id,'unitDimension',u.dimension,'unitFactor',coalesce(u.equivalence_multiplier,1)) order by ri.position),'[]'::jsonb)
      into ingredients from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
      join public.units u on u.id=ri.unit_id join public.units root on root.id=coalesce(u.base_unit_id,u.id)
      join public.categories c on c.id=i.category_id where ri.recipe_id=p_recipe_id;
    if exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
      join public.categories c on c.id=i.category_id join public.units u on u.id=ri.unit_id
      join public.units root on root.id=coalesce(u.base_unit_id,u.id)
      join public.units ingredient_base on ingredient_base.id=i.base_unit_id
      join public.units ingredient_root on ingredient_root.id=coalesce(ingredient_base.base_unit_id,ingredient_base.id)
      where ri.recipe_id=p_recipe_id and (not i.active or i.is_deleted or not c.active or c.is_deleted
        or not u.active or u.is_deleted or not root.active or root.is_deleted
        or not ingredient_base.active or ingredient_base.is_deleted or not ingredient_root.active or ingredient_root.is_deleted
        or root.id<>ingredient_root.id or root.dimension<>ingredient_root.dimension))
      then raise exception 'La receta contiene referencias de catálogo no disponibles.' using errcode='22023'; end if;
  end if;
  if jsonb_typeof(ingredients) is distinct from 'array' or jsonb_array_length(ingredients)>200 then raise exception 'La receta guardada no es válida.' using errcode='22023'; end if;
  -- Aggregate duplicate catalog ingredients and normalized manual labels before computing stock.
  for item in with grouped as (
    select min(e.value->>'ingredientId') ingredient_id,
      coalesce(to_jsonb(array_agg(distinct nullif(e.value->>'ingredientId','')::uuid)
        filter(where nullif(e.value->>'ingredientId','') is not null)),'[]'::jsonb) ingredient_ids,
      min(e.value->>'name') ingredient_name,(e.value->>'unitRootId')::uuid root_id,
      count(distinct nullif(e.value->>'ingredientId','')) ingredient_count,
      e.value->>'unitDimension' unit_dimension,
      sum((e.value->>'quantity')::numeric*(e.value->>'unitFactor')::numeric) quantity
    from jsonb_array_elements(ingredients) as e(value)
    group by lower(regexp_replace(trim(e.value->>'name'),'\s+',' ','g')),
      (e.value->>'unitRootId')::uuid,e.value->>'unitDimension'
  ) select jsonb_build_object('ingredientId',coalesce(g.ingredient_id,''),'ingredientIds',g.ingredient_ids,
      'name',g.ingredient_name,'ingredientCount',g.ingredient_count,'unitId',g.root_id,'unitRootId',g.root_id,'unitDimension',g.unit_dimension,
      'unitFactor','1','unit',root.abbreviation,'quantity',g.quantity)
    from grouped g join public.units root on root.id=g.root_id
  loop
    if coalesce((item->>'ingredientCount')::integer,0)>1 then
      raise exception 'La receta contiene nombres ambiguos de ingredientes.' using errcode='22023';
    end if;
    v_id:=nullif(item->>'ingredientId','')::uuid; v_name:=item->>'name'; v_unit:=(item->>'unitId')::uuid;
    select array_agg(x::uuid) into v_ids from jsonb_array_elements_text(item->'ingredientIds') as ids(x);
    v_root:=(item->>'unitRootId')::uuid; v_dimension:=item->>'unitDimension'; v_factor:=(item->>'unitFactor')::numeric;
    if v_factor<=0 or v_name is null or jsonb_typeof(item->'quantity') is distinct from 'number'
      or not exists(select 1 from public.units u join public.units root on root.id=coalesce(u.base_unit_id,u.id)
        where u.id=v_unit and root.id=v_root and u.dimension=v_dimension and u.active and not u.is_deleted
          and root.active and not root.is_deleted)
      then raise exception 'La receta guardada no es válida.' using errcode='22023'; end if;
    demand:=(item->>'quantity')::numeric*p_portions/base_portions;
    required_root:=demand*v_factor; available_root:=0;
    for pantry in select p.* from public.pantry_items p where p.user_id=actor and p.quantity>0
      and (p.expiry is null or p.expiry>=current_date) and
      (p.ingredient_ref=any(v_ids) or (p.ingredient_ref is null and lower(regexp_replace(trim(p.name),'\s+',' ','g'))=lower(regexp_replace(trim(v_name),'\s+',' ','g'))))
      order by p.expiry nulls last,p.id
    loop
      select * into pantry_unit from public.units u where u.id=coalesce(pantry.unit_ref,(select id from public.units where abbreviation=pantry.unit))
        and u.abbreviation=pantry.unit and u.active and not u.is_deleted;
      if found and coalesce(pantry_unit.base_unit_id,pantry_unit.id)=v_root and pantry_unit.dimension=v_dimension then
        pantry_factor:=coalesce(pantry_unit.equivalence_multiplier,1); available_root:=available_root+pantry.quantity*pantry_factor;
      end if;
    end loop;
    row_result:=jsonb_build_object('ingredientId',v_id,'ingredientIds',to_jsonb(v_ids),'name',v_name,'unit',item->>'unit','required',demand,
      'available',available_root/v_factor,'missing',greatest(0,required_root-available_root)/v_factor,
      'sufficient',available_root>=required_root);
    output:=output||jsonb_build_array(row_result);
  end loop;
  return jsonb_build_object('recipeId',case when p_session_id is null then p_recipe_id else session_row.recipe_id end,
    'sessionId',p_session_id,'portions',p_portions,'ingredients',output,
    'sufficient',coalesce((select bool_and((x->>'sufficient')::boolean) from jsonb_array_elements(output) x),true),
    'asOf',current_date,'preview',true);
exception when invalid_text_representation or numeric_value_out_of_range or check_violation or data_exception then
  raise exception 'La consulta de despensa no es válida.' using errcode='22023';
end; $$;

revoke all on function public.get_my_cooking_history(integer,timestamptz,uuid),public.hide_my_cooking_history_entry(uuid),public.clear_my_cooking_history(),public.check_my_cooking_stock(uuid,integer,uuid) from public,anon;
grant execute on function public.get_my_cooking_history(integer,timestamptz,uuid),public.hide_my_cooking_history_entry(uuid),public.clear_my_cooking_history(),public.check_my_cooking_stock(uuid,integer,uuid) to authenticated;
commit;
