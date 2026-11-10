begin;

-- Authenticated discovery returns only public published recipes and the caller's
-- own private recipes, including when the caller has an administrative role.
create function public.search_my_recipes(
  p_search text default null,
  p_meal_shift text default null,
  p_max_minutes integer default null,
  p_difficulty text default null,
  p_dietary_tag_keys text[] default '{}',
  p_pantry_only boolean default false,
  p_portions integer default null,
  p_limit integer default 30,
  p_offset integer default 0
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid; needle text; shift_key text; row_recipe public.recipes; stock jsonb;
  stock_error boolean; item jsonb; items jsonb := '[]'::jsonb; total_count integer;
  result_total integer;
  passed integer := 0; scanned integer := 0;
begin
  actor := public.lock_my_relational_account();
  if p_search is not null and (length(p_search)>120 or length(trim(p_search))=0) then
    raise exception 'El texto de búsqueda no es válido.' using errcode='22023';
  end if;
  if p_meal_shift is not null and p_meal_shift not in ('breakfast','lunch','snack','dinner') then
    raise exception 'El momento de comida no es válido.' using errcode='22023';
  end if;
  if p_max_minutes is not null and p_max_minutes not between 1 and 1440 then raise exception 'El tiempo máximo no es válido.' using errcode='22023'; end if;
  if p_difficulty is not null and p_difficulty not in ('easy','intermediate','advanced') then raise exception 'La dificultad no es válida.' using errcode='22023'; end if;
  if p_portions is not null and p_portions not between 1 and 20 then raise exception 'Las porciones no son válidas.' using errcode='22023'; end if;
  if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 5000
    or p_dietary_tag_keys is null or cardinality(p_dietary_tag_keys)>20
    or exists(select 1 from unnest(p_dietary_tag_keys) k where k is null or k !~ '^[a-z0-9-]{2,50}$')
    or (select count(distinct k) from unnest(p_dietary_tag_keys) k) <> cardinality(p_dietary_tag_keys)
    or p_pantry_only is null then raise exception 'Los filtros o la página no son válidos.' using errcode='22023'; end if;
  needle := nullif(lower(regexp_replace(regexp_replace(normalize(trim(p_search),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')), '');
  shift_key := p_meal_shift;

  -- Keep filtering before pagination. Pantry-only applies the stock RPC to a
  -- bounded candidate set and refuses ambiguous oversized queries.
  if p_pantry_only then
    for row_recipe in
      select r.* from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys))
      order by lower(r.title),r.id limit 501
    loop
      scanned := scanned+1;
      if scanned>500 then raise exception 'Hay demasiadas recetas candidatas; agregá filtros.' using errcode='22023'; end if;
      stock_error := false;
      begin
        stock := public.check_my_cooking_stock(row_recipe.id,coalesce(p_portions,row_recipe.portions),null);
      exception when sqlstate '22023' then stock_error := true; stock := null;
      end;
      if not stock_error and jsonb_array_length(coalesce(stock->'ingredients','[]'::jsonb))>0
        and coalesce((stock->>'sufficient')::boolean,false) then
        passed := passed+1;
        if passed>p_offset and passed<=p_offset+p_limit then
          item := public.recipe_discovery_payload(row_recipe,stock);
          items := items||jsonb_build_array(item);
        end if;
      end if;
    end loop;
    total_count := passed;
  else
    select count(*)::integer into total_count from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys));
    for row_recipe in
      select r.* from public.recipes r
      where r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
        and (shift_key is null or exists(select 1 from public.recipe_meal_shifts ms where ms.recipe_id=r.id and ms.meal_shift=shift_key))
        and (p_max_minutes is null or r.total_minutes<=p_max_minutes)
        and (p_difficulty is null or r.difficulty=p_difficulty)
        and (needle is null or strpos(lower(regexp_replace(regexp_replace(normalize(r.title,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or strpos(lower(regexp_replace(regexp_replace(normalize(r.description,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0
          or exists(select 1 from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id
            where ri.recipe_id=r.id and strpos(lower(regexp_replace(regexp_replace(normalize(i.name,NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')),needle)>0))
        and (cardinality(p_dietary_tag_keys)=0 or (select count(distinct t.tag_key)
          from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id
          where rt.recipe_id=r.id and t.active and t.tag_key=any(p_dietary_tag_keys))=cardinality(p_dietary_tag_keys))
      order by lower(r.title),r.id offset p_offset limit p_limit
    loop
      stock_error := false;
      begin
        stock := public.check_my_cooking_stock(row_recipe.id,coalesce(p_portions,row_recipe.portions),null);
      exception when sqlstate '22023' then stock_error := true; stock := null;
      end;
      item := public.recipe_discovery_payload(row_recipe,case when stock_error then null else stock end);
      items := items||jsonb_build_array(item);
    end loop;
  end if;
  result_total := total_count;
  return jsonb_build_object('items',items,'total',result_total,'limit',p_limit,'offset',p_offset);
end; $$;

-- Shared payload formatter keeps the list and pantry-only paths consistent.
create function public.recipe_discovery_payload(p_recipe public.recipes,p_stock jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare n integer; ready integer; pct integer; label text; recipe_json jsonb;
begin
  select coalesce(jsonb_agg(t.tag_key order by t.tag_key),'[]'::jsonb) into recipe_json
    from public.recipe_dietary_tags rt join public.dietary_tags t on t.id=rt.dietary_tag_id where rt.recipe_id=p_recipe.id;
  recipe_json := to_jsonb(p_recipe)||jsonb_build_object(
    'meal_shifts',coalesce((select jsonb_agg(ms.meal_shift order by ms.meal_shift) from public.recipe_meal_shifts ms where ms.recipe_id=p_recipe.id),'[]'::jsonb),
    'dietary_tags',recipe_json,
    'ingredients',coalesce((select jsonb_agg(jsonb_build_object('id',ri.id,'ingredient_id',i.id,'name',i.name,'quantity',ri.quantity,'unit_id',u.id,'unit',u.abbreviation,'note',ri.note,'position',ri.position) order by ri.position)
      from public.recipe_ingredients ri join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id where ri.recipe_id=p_recipe.id),'[]'::jsonb),
    'steps',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'position',s.position,'instruction',s.instruction,'duration_minutes',s.duration_minutes,'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',to_jsonb(s.utensils),'special_instructions',s.special_instructions,
        'ingredients',coalesce((select jsonb_agg(jsonb_build_object('recipe_ingredient_id',ri.id,'ingredient_position',ri.position,'quantity_override',si.quantity_override) order by ri.position)
          from public.recipe_step_ingredients si join public.recipe_ingredients ri on ri.id=si.recipe_ingredient_id where si.step_id=s.id),'[]'::jsonb)) order by s.position)
      from public.recipe_steps s where s.recipe_id=p_recipe.id),'[]'::jsonb));
  if p_stock is null then pct:=null; label:='Disponibilidad no calculable';
  else
    select count(*)::integer,count(*) filter(where (x->>'sufficient')::boolean)::integer into n,ready from jsonb_array_elements(coalesce(p_stock->'ingredients','[]'::jsonb)) x;
    pct:=case when coalesce(n,0)=0 then 0 when ready=n then 100 else least(99,round(ready::numeric/n*100)::integer) end;
    label:=case when pct=100 then 'Lista para cocinar' when coalesce(ready,0)::numeric/nullif(n,0)>=0.6 then 'Casi lista' else 'Requiere compra' end;
  end if;
  return jsonb_build_object('recipe',recipe_json,'stock',p_stock,'percentage',pct,'label',label);
end; $$;

create function public.get_my_recipe_trends(p_days integer default 30,p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=public.lock_my_relational_account();
  if p_days is null or p_days not between 1 and 365 or p_limit is null or p_limit not between 1 and 50 then
    raise exception 'El período o límite de tendencias no es válido.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('recipeId',recipe_id,'cookCount',cook_count,'lastCookedAt',last_cooked_at)
    order by cook_count desc,recipe_id),'[]'::jsonb) into result from (
      select e.recipe_id,count(*)::integer cook_count,max(e.cooked_at) last_cooked_at
      from public.cooking_events e join public.recipes r on r.id=e.recipe_id
      where e.owner_user_id=actor and e.hidden_at is null and e.cooked_at>=now()-make_interval(days=>p_days)
        and r.active and not r.is_deleted
        and ((r.recipe_source='official' and r.publication_status='published') or r.owner_user_id=actor)
      group by e.recipe_id order by count(*) desc,e.recipe_id limit p_limit
    ) ranked;
  return jsonb_build_object('days',p_days,'items',result);
end; $$;

-- DATA_MODEL.md permits aggregate trends over public recipes. No user identity,
-- private recipe, or individual event data leaves this RPC.
create function public.get_recipe_trends(p_days integer default 30,p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor:=public.lock_my_relational_account();
  if p_days is null or p_days not between 1 and 365 or p_limit is null or p_limit not between 1 and 50 then
    raise exception 'El período o límite de tendencias no es válido.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('recipeId',ranked.id,'cookCount',ranked.cook_count,'featured',ranked.featured)
    order by ranked.cook_count desc,ranked.featured desc,ranked.id),'[]'::jsonb) into result
  from (select r.id,coalesce(e.cook_count,0)::integer cook_count,r.featured
    from public.recipes r left join (
      select ev.recipe_id,count(*)::integer cook_count from public.cooking_events ev
      where ev.hidden_at is null and ev.cooked_at>=now()-make_interval(days=>p_days)
      group by ev.recipe_id
    ) e on e.recipe_id=r.id
    where r.recipe_source='official' and r.publication_status='published' and r.active and not r.is_deleted
    order by coalesce(e.cook_count,0) desc,r.featured desc,r.id limit p_limit) ranked;
  return jsonb_build_object('days',p_days,'items',result);
end; $$;

revoke all on function public.search_my_recipes(text,text,integer,text,text[],boolean,integer,integer,integer),
  public.recipe_discovery_payload(public.recipes,jsonb),public.get_my_recipe_trends(integer,integer),
  public.get_recipe_trends(integer,integer) from public,anon;
revoke all on function public.recipe_discovery_payload(public.recipes,jsonb) from authenticated;
grant execute on function public.search_my_recipes(text,text,integer,text,text[],boolean,integer,integer,integer),
  public.get_my_recipe_trends(integer,integer),public.get_recipe_trends(integer,integer) to authenticated;
commit;
