begin;

-- Preview only: the user confirms individual suggestions through put_my_shopping_item.
-- No list, stock, favorites or plan is changed by this operation.
create function public.suggest_my_shopping(p_source text, p_plan_id uuid default null, p_as_of date default current_date)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; result jsonb; invalid boolean;
begin
  actor := public.lock_my_relational_account();
  if p_source is null or p_source not in ('plan','favorites','pantry') or p_as_of is null
    or not isfinite(p_as_of) or (p_source='plan') <> (p_plan_id is not null) then
    raise exception 'Origen, plan o fecha de sugerencias inválidos.' using errcode='22023';
  end if;
  if p_source='plan' and not exists(select 1 from public.meal_plans where id=p_plan_id and owner_user_id=actor) then
    raise exception 'El plan no está disponible para esta cuenta.' using errcode='42501';
  end if;

  -- One statement gives the preview a consistent snapshot of every input.
  with unit_map as materialized (
    select u.id,u.abbreviation,coalesce(u.base_unit_id,u.id) root_id,
      coalesce(u.equivalence_multiplier,1) factor
    from public.units u join public.units r on r.id=coalesce(u.base_unit_id,u.id)
    where u.active and not u.is_deleted and r.active and not r.is_deleted
      and r.base_unit_id is null and r.dimension=u.dimension
  ), selected_recipes as (
    select r.id,r.portions,s.portions::numeric planned_portions
    from public.meal_plan_slots s join public.recipes r on r.id=s.recipe_id
    where p_source='plan' and s.plan_id=p_plan_id
      and r.active and not r.is_deleted
      and (r.owner_user_id=actor or (r.recipe_source='official' and r.publication_status='published'))
    union all
    select r.id,r.portions,r.portions::numeric
    from public.favorite_recipes f join public.recipes r on r.id=f.recipe_id
    where p_source='favorites' and f.user_id=actor and r.active and not r.is_deleted
      and (r.owner_user_id=actor or (r.recipe_source='official' and r.publication_status='published'))
  ), requirements as (
    select i.id ingredient_id,i.name,i.category_id,i.base_unit_id unit_id,base.root_id,
      sum(ri.quantity*requested.planned_portions/requested.portions*used.factor/base.factor) required,
      bool_and(i.active and not i.is_deleted and c.active and not c.is_deleted
        and used.id is not null and base.id is not null and used.root_id=base.root_id) valid
    from selected_recipes requested join public.recipe_ingredients ri on ri.recipe_id=requested.id
    join public.ingredients i on i.id=ri.ingredient_id join public.categories c on c.id=i.category_id
    left join unit_map used on used.id=ri.unit_id left join unit_map base on base.id=i.base_unit_id
    group by i.id,i.name,i.category_id,i.base_unit_id,base.root_id
  ), stock as materialized (
    select p.*,u.id resolved_unit_id,u.root_id,u.factor,
      lower(regexp_replace(regexp_replace(normalize(trim(p.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')) normalized_name,
      case when p.expiry is null or p.expiry>=p_as_of then p.quantity else 0 end usable
    from public.pantry_items p left join unit_map u
      on (u.id=p.unit_ref and u.abbreviation=p.unit) or (p.unit_ref is null and u.abbreviation=p.unit)
    where p.user_id=actor
  ), recipe_proposals as (
    select r.ingredient_id,r.name,c.name category,r.unit_id,
      greatest(0,r.required-coalesce((select sum(s.usable*s.factor/base.factor) from stock s
        where s.root_id=r.root_id and (s.ingredient_ref=r.ingredient_id or
          (s.ingredient_ref is null and s.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(r.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))))),0)) quantity,
      r.valid and not exists(select 1 from stock s where (s.resolved_unit_id is null or s.root_id is distinct from r.root_id)
        and (s.ingredient_ref=r.ingredient_id or (s.ingredient_ref is null
          and s.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(r.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))))) valid
    from requirements r join public.categories c on c.id=r.category_id
    left join unit_map base on base.id=r.unit_id
  ), restock_groups as (
    -- Manual rows stay manual. Never persist a guessed catalog association.
    select s.ingredient_ref ingredient_id,s.normalized_name,s.root_id,
      (array_agg(s.name order by s.id))[1] name,(array_agg(s.category order by s.id))[1] category,
      (array_agg(s.resolved_unit_id order by s.id))[1] unit_id,
      sum(s.usable*s.factor) usable,max(s.minimum*s.factor) minimum,
      max(s.quantity*s.factor) previous_quantity,
      bool_or(s.quantity=0 or s.expiry<p_as_of) exhausted,
      bool_and(s.resolved_unit_id is not null) valid
    from stock s where p_source='pantry'
    group by s.ingredient_ref,s.normalized_name,s.root_id
  ), restock_proposals as (
    select g.ingredient_id,g.name,g.category,g.unit_id,
      case when g.minimum>0 then greatest(0,g.minimum-g.usable)/u.factor
        when g.usable=0 and g.exhausted then greatest(u.factor,g.previous_quantity)/u.factor else 0 end quantity,
      g.valid and exists(select 1 from public.categories c where c.name=g.category and c.active and not c.is_deleted)
        and (g.ingredient_id is null or exists(select 1 from public.ingredients i join unit_map b on b.id=i.base_unit_id
          where i.id=g.ingredient_id and i.active and not i.is_deleted and b.root_id=g.root_id)) valid
    from restock_groups g left join unit_map u on u.id=g.unit_id
  ), proposals as (
    select * from recipe_proposals where p_source in ('plan','favorites')
    union all select * from restock_proposals
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ingredient_id',ingredient_id,'name_snapshot',name,'category_snapshot',category,
    'quantity',ceil(quantity*10000)/10000,'unit_id',unit_id,'source',p_source,
    'sources',jsonb_build_array(case when p_source='plan' then jsonb_build_object('source','plan','plan_id',p_plan_id)
      else jsonb_build_object('source',p_source) end)) order by lower(name),unit_id,ingredient_id)
      filter(where quantity>0),'[]'::jsonb),
    coalesce(bool_or(valid is distinct from true or quantity is null or quantity>1000000),false)
  into result,invalid from proposals;
  if invalid then
    raise exception 'No se pueden calcular sugerencias con el catálogo, unidades o cantidades actuales.' using errcode='22023';
  end if;
  return result;
end;
$$;
revoke all on function public.suggest_my_shopping(text,uuid,date) from public,anon;
grant execute on function public.suggest_my_shopping(text,uuid,date) to authenticated;

commit;
