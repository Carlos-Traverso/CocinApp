begin;

-- Aggregate selected dates together so pantry is subtracted exactly once.
create function public.suggest_my_shopping_for_dates(p_dates date[], p_as_of date default current_date)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; result jsonb; invalid boolean;
begin
  actor := public.lock_my_relational_account();
  if p_dates is null or cardinality(p_dates) not between 1 and 42 or array_ndims(p_dates) is distinct from 1 or p_as_of is null
    or not isfinite(p_as_of) or exists(select 1 from unnest(p_dates) as dates(selected_date) where selected_date is null or not isfinite(selected_date))
    or (select count(*) from unnest(p_dates) as dates(selected_date))<>(select count(distinct selected_date) from unnest(p_dates) as dates(selected_date)) then
    raise exception 'Las fechas deben ser unicas y contener entre 1 y 42 fechas validas.' using errcode='22023';
  end if;
  if (select count(distinct s.plan_id) from public.turnos_plan_comida s join public.planes_comida p on p.id=s.plan_id
      where p.owner_user_id=actor and s.meal_date=any(p_dates))>20 then
    raise exception 'Las fechas seleccionadas abarcan demasiados planes.' using errcode='22023';
  end if;

  -- One statement gives the preview a consistent snapshot of every input.
  with unit_map as materialized (
    select u.id,u.abbreviation,coalesce(u.base_unit_id,u.id) root_id,
      coalesce(u.equivalence_multiplier,1) factor
    from public.unidades u join public.unidades r on r.id=coalesce(u.base_unit_id,u.id)
    where u.active and not u.is_deleted and r.active and not r.is_deleted
      and r.base_unit_id is null and r.dimension=u.dimension
  ), selected_recipes as (
    select r.id,r.portions,s.portions::numeric planned_portions,s.plan_id
    from public.turnos_plan_comida s join public.recetas r on r.id=s.recipe_id
    join public.planes_comida p on p.id=s.plan_id
    where s.meal_date=any(p_dates) and p.owner_user_id=actor
      and r.active and not r.is_deleted
      and (r.owner_user_id=actor or (r.recipe_source='official' and r.publication_status='published'))

  ), requirements as (
    select i.id ingredient_id,i.name,i.category_id,i.base_unit_id unit_id,base.root_id,
      sum(ri.quantity*requested.planned_portions/requested.portions*used.factor/base.factor) required,
      bool_and(i.active and not i.is_deleted and c.active and not c.is_deleted
        and used.id is not null and base.id is not null and used.root_id=base.root_id) valid
    from selected_recipes requested join public.ingredientes_receta ri on ri.recipe_id=requested.id
    join public.ingredientes i on i.id=ri.ingredient_id join public.categorias c on c.id=i.category_id
    left join unit_map used on used.id=ri.unit_id left join unit_map base on base.id=i.base_unit_id
    group by i.id,i.name,i.category_id,i.base_unit_id,base.root_id
  ), stock as materialized (
    select p.*,u.id resolved_unit_id,u.root_id,u.factor,
      lower(regexp_replace(regexp_replace(normalize(trim(p.name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')) normalized_name,
      case when p.expiry is null or p.expiry>=p_as_of then p.quantity else 0 end usable
    from public.articulos_despensa p left join unit_map u
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
    from requirements r join public.categorias c on c.id=r.category_id
    left join unit_map base on base.id=r.unit_id
  ), proposals as (
    select * from recipe_proposals
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ingredient_id',ingredient_id,'name_snapshot',name,'category_snapshot',category,
    'quantity',ceil(quantity*10000)/10000,'unit_id',unit_id,'source','plan',
    'sources',(select jsonb_agg(jsonb_build_object('source','plan','plan_id',x.plan_id) order by x.plan_id)
      from (select distinct q.plan_id from selected_recipes q join public.ingredientes_receta ri2 on ri2.recipe_id=q.id
        where ri2.ingredient_id=proposals.ingredient_id) x)) order by lower(name),unit_id,ingredient_id)
      filter(where quantity>0),'[]'::jsonb),
    coalesce(bool_or(valid is distinct from true or quantity is null or quantity>1000000),false)
  into result,invalid from proposals;
  if invalid then
    raise exception 'No se pueden calcular sugerencias con el catalogo, unidades o cantidades actuales.' using errcode='22023';
  end if;
  return result;
end;
$$;
revoke all on function public.suggest_my_shopping_for_dates(date[],date) from public,anon;
grant execute on function public.suggest_my_shopping_for_dates(date[],date) to authenticated;
commit;
