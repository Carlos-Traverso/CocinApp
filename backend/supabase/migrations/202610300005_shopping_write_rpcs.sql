begin;

alter table public.shopping_lists add column version bigint not null default 1 check (version > 0);

-- All shopping mutations share the account authorization/serialization protocol.
-- Clients cannot call this helper or directly mutate the underlying tables.
create function public.lock_my_active_shopping_list(p_list_id uuid, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; selected public.shopping_lists;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'Lista o versión inválida.' using errcode = '22023';
  end if;
  select * into selected from public.shopping_lists
    where id=p_list_id and owner_user_id=actor and status='active' for update;
  if not found then
    raise exception 'La lista no está disponible para esta cuenta.' using errcode = '42501';
  end if;
  if selected.version <> p_expected_version then
    raise exception 'La lista cambió en otra sesión. Recargala antes de guardar.' using errcode = '40001';
  end if;
  return selected;
end;
$$;
revoke all on function public.lock_my_active_shopping_list(uuid,bigint) from public, anon, authenticated;

-- Stable client UUID is the creation idempotency key. Retrying an old request
-- returns that list, including its archived state; it never reactivates it.
create function public.create_my_shopping_list(p_list_id uuid, p_name text, p_plan_id uuid default null)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare actor uuid; selected public.shopping_lists;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_name is null or length(trim(p_name)) not between 1 and 120 then
    raise exception 'El identificador y el nombre de lista son obligatorios.' using errcode = '22023';
  end if;
  select * into selected from public.shopping_lists where id=p_list_id for update;
  if found then
    if selected.owner_user_id<>actor then
      raise exception 'La lista no está disponible para esta cuenta.' using errcode = '42501';
    end if;
    if selected.name is distinct from trim(p_name) or selected.plan_id is distinct from p_plan_id then
      raise exception 'El identificador de lista ya corresponde a otra solicitud.' using errcode = '22023';
    end if;
    return selected;
  end if;
  if p_plan_id is not null then
    perform 1 from public.meal_plans where id=p_plan_id and owner_user_id=actor for share;
    if not found then raise exception 'El plan no está disponible para esta cuenta.' using errcode = '42501'; end if;
  end if;
  update public.shopping_lists set status='archived',version=version+1,updated_at=clock_timestamp()
    where owner_user_id=actor and status='active';
  insert into public.shopping_lists(id,owner_user_id,plan_id,name)
    values(p_list_id,actor,p_plan_id,trim(p_name)) returning * into selected;
  return selected;
exception when unique_violation or foreign_key_violation or check_violation or not_null_violation or data_exception then
  raise exception 'No se pudo crear la lista con esos datos.' using errcode = '22023';
end;
$$;
revoke all on function public.create_my_shopping_list(uuid,text,uuid) from public, anon;
grant execute on function public.create_my_shopping_list(uuid,text,uuid) to authenticated;

-- Item and all provenance links are one atomic replacement. Known catalog
-- ingredients derive their name/category snapshots on the server. Free-text
-- manual entries keep their own labels and have no inferred ingredient link.
-- checked defaults false; note defaults empty. Ownership, transfer state and
-- timestamps are server-controlled and are not accepted in this JSON contract.
create function public.put_my_shopping_item(p_list_id uuid, p_item jsonb, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; selected public.shopping_lists; previous public.shopping_items;
  item_id uuid; ingredient_id uuid; unit_id uuid; qty numeric; checked_value boolean;
  item_name text; category_name text; item_note text; primary_source text;
  links jsonb; link jsonb; link_source text; link_recipe uuid; link_plan uuid;
  ingredient public.ingredients; unit public.units; base_unit public.units;
  category public.categories; recipe public.recipes; lock_id uuid;
  unit_root public.units; ingredient_root public.units; changed bigint;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  actor := selected.owner_user_id;
  if jsonb_typeof(p_item) is distinct from 'object' or exists(
    select 1 from jsonb_object_keys(p_item) k where k not in (
      'id','ingredient_id','name_snapshot','category_snapshot','quantity','unit_id','note','checked','source','sources')) then
    raise exception 'Formato de artículo inválido.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_item->'id') is distinct from 'string'
    or jsonb_typeof(p_item->'unit_id') is distinct from 'string'
    or jsonb_typeof(p_item->'quantity') is distinct from 'number'
    or jsonb_typeof(p_item->'source') is distinct from 'string'
    or jsonb_typeof(p_item->'sources') is distinct from 'array' then
    raise exception 'Faltan campos del artículo o sus tipos son inválidos.' using errcode = '22023';
  end if;
  if p_item ? 'ingredient_id' and jsonb_typeof(p_item->'ingredient_id') not in ('null','string')
    or p_item ? 'checked' and jsonb_typeof(p_item->'checked') is distinct from 'boolean'
    or p_item ? 'note' and jsonb_typeof(p_item->'note') is distinct from 'string'
    or p_item ? 'name_snapshot' and jsonb_typeof(p_item->'name_snapshot') is distinct from 'string'
    or p_item ? 'category_snapshot' and jsonb_typeof(p_item->'category_snapshot') is distinct from 'string' then
    raise exception 'Tipo de campo de artículo inválido.' using errcode = '22023';
  end if;
  item_id := (p_item->>'id')::uuid;
  ingredient_id := (p_item->>'ingredient_id')::uuid;
  unit_id := (p_item->>'unit_id')::uuid;
  qty := (p_item->>'quantity')::numeric;
  checked_value := coalesce((p_item->>'checked')::boolean,false);
  item_note := coalesce(p_item->>'note','');
  primary_source := p_item->>'source';
  links := p_item->'sources';
  if qty<=0 or qty>1000000 or round(qty,4)<=0 or length(item_note)>1000
    or primary_source not in ('manual','recipe','plan','favorites','pantry')
    or jsonb_array_length(links) not between 1 and 20
    or p_item ? 'name_snapshot' and length(trim(p_item->>'name_snapshot')) not between 1 and 120
    or p_item ? 'category_snapshot' and length(trim(p_item->>'category_snapshot')) not between 1 and 100 then
    raise exception 'Los datos del artículo están fuera del rango admitido.' using errcode = '22023';
  end if;
  -- Item identity spans accounts and survives removal in receipt history.
  -- Transfer RPCs must take this same lock before creating that history.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  select * into previous from public.shopping_items where id=item_id for update;
  if found and previous.list_id<>p_list_id then
    raise exception 'El artículo no está disponible en esta lista.' using errcode = '42501';
  end if;
  if previous.transferred_at is not null or exists(
    select 1 from public.pantry_receipt_items r where r.original_shopping_item_id=item_id) then
    raise exception 'No se puede modificar o reutilizar un artículo ya transferido.' using errcode = '22023';
  end if;
  -- Catalog locks protect the validation until commit. Lock units in ID order.
  if ingredient_id is not null then
    select * into ingredient from public.ingredients i where i.id=ingredient_id and i.active and not i.is_deleted for share;
    if not found then raise exception 'El ingrediente no está disponible.' using errcode = '22023'; end if;
  end if;
  perform 1 from public.units u where u.id=unit_id or u.id=ingredient.base_unit_id order by u.id for share;
  select * into unit from public.units u where u.id=unit_id;
  if not found or not unit.active or unit.is_deleted then
    raise exception 'La unidad no está disponible.' using errcode = '22023';
  end if;
  if ingredient_id is not null then
    select * into base_unit from public.units u where u.id=ingredient.base_unit_id;
  end if;
  perform 1 from public.units u where u.id=coalesce(unit.base_unit_id,unit.id)
    or u.id=coalesce(base_unit.base_unit_id,base_unit.id) order by u.id for share;
  select * into unit_root from public.units u where u.id=coalesce(unit.base_unit_id,unit.id);
  if not found or not unit_root.active or unit_root.is_deleted then
    raise exception 'La unidad base no está disponible.' using errcode = '22023';
  end if;
  if ingredient_id is not null then
    select * into ingredient_root from public.units u where u.id=coalesce(base_unit.base_unit_id,base_unit.id);
    select * into category from public.categories c where c.id=ingredient.category_id and c.active and not c.is_deleted for share;
    if not found or not base_unit.active or base_unit.is_deleted or base_unit.dimension<>unit.dimension
      or ingredient_root.id is distinct from unit_root.id or not ingredient_root.active or ingredient_root.is_deleted then
      raise exception 'Categoría o unidad incompatible con el ingrediente.' using errcode = '22023';
    end if;
    item_name := ingredient.name; category_name := category.name;
  else
    item_name := trim(p_item->>'name_snapshot');
    category_name := coalesce(trim(p_item->>'category_snapshot'),'Otros');
    if item_name is null then raise exception 'El artículo manual necesita un nombre.' using errcode = '22023'; end if;
  end if;
  -- Validate every provenance object before touching the current item/links.
  for link in select value from jsonb_array_elements(links) loop
    if jsonb_typeof(link) is distinct from 'object' or exists(
      select 1 from jsonb_object_keys(link) k where k not in ('source','recipe_id','plan_id')) then
      raise exception 'Origen de compra inválido.' using errcode = '22023';
    end if;
    link_source := link->>'source';
    if jsonb_typeof(link->'source') is distinct from 'string'
      or link_source not in ('manual','recipe','plan','favorites','pantry')
      or link ? 'recipe_id' and jsonb_typeof(link->'recipe_id') not in ('null','string')
      or link ? 'plan_id' and jsonb_typeof(link->'plan_id') not in ('null','string') then
      raise exception 'Tipo de origen de compra inválido.' using errcode = '22023';
    end if;
    link_recipe := (link->>'recipe_id')::uuid; link_plan := (link->>'plan_id')::uuid;
    if (link_source='recipe') is distinct from (link_recipe is not null)
      or (link_source='plan') is distinct from (link_plan is not null) then
      raise exception 'Las referencias no corresponden al origen de compra.' using errcode = '22023';
    end if;
  end loop;
  if not exists(select 1 from jsonb_array_elements(links) l where l->>'source'=primary_source)
    or (select count(distinct jsonb_build_array(l->>'source',(l->>'recipe_id')::uuid,(l->>'plan_id')::uuid)) from jsonb_array_elements(links) l)<>jsonb_array_length(links) then
    raise exception 'Los orígenes están repetidos o falta el origen principal.' using errcode = '22023';
  end if;
  for lock_id in select distinct (l->>'recipe_id')::uuid from jsonb_array_elements(links) l where l->>'recipe_id' is not null order by 1 loop
    select * into recipe from public.recipes r where r.id=lock_id for share;
    if not found or not recipe.active or recipe.is_deleted or (
      recipe.owner_user_id=actor or (recipe.recipe_source='official' and recipe.publication_status='published')) is not true then
      raise exception 'La receta de origen no está disponible para esta cuenta.' using errcode = '42501';
    end if;
  end loop;
  for lock_id in select distinct (l->>'plan_id')::uuid from jsonb_array_elements(links) l where l->>'plan_id' is not null order by 1 loop
    perform 1 from public.meal_plans p where p.id=lock_id and p.owner_user_id=actor for share;
    if not found then raise exception 'El plan de origen no está disponible para esta cuenta.' using errcode = '42501'; end if;
  end loop;
  insert into public.shopping_items(id,list_id,ingredient_id,name_snapshot,category_snapshot,quantity,unit_id,note,checked,source,updated_at)
    values(item_id,p_list_id,ingredient_id,item_name,category_name,qty,unit_id,item_note,checked_value,primary_source,clock_timestamp())
  on conflict(id) do update set ingredient_id=excluded.ingredient_id,name_snapshot=excluded.name_snapshot,
    category_snapshot=excluded.category_snapshot,quantity=excluded.quantity,unit_id=excluded.unit_id,
    note=excluded.note,checked=excluded.checked,source=excluded.source,updated_at=excluded.updated_at
    where shopping_items.list_id=excluded.list_id and shopping_items.transferred_at is null;
  get diagnostics changed = row_count;
  -- Existence checks cannot see another account's uncommitted insertion. This
  -- predicate also protects the conflict path after waiting for that insertion.
  if changed<>1 then raise exception 'El artículo no está disponible en esta lista.' using errcode = '42501'; end if;
  delete from public.shopping_item_sources s where s.shopping_item_id=item_id;
  insert into public.shopping_item_sources(shopping_item_id,source,recipe_id,plan_id)
    select item_id,l->>'source',(l->>'recipe_id')::uuid,(l->>'plan_id')::uuid from jsonb_array_elements(links) l;
  update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  return selected;
exception when data_exception or check_violation or not_null_violation or unique_violation or foreign_key_violation then
  raise exception 'Los datos del artículo de compra no son válidos.' using errcode = '22023';
end;
$$;
revoke all on function public.put_my_shopping_item(uuid,jsonb,bigint) from public, anon;
grant execute on function public.put_my_shopping_item(uuid,jsonb,bigint) to authenticated;

create function public.set_my_shopping_checked(p_list_id uuid, p_item_ids uuid[], p_checked boolean, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare selected public.shopping_lists; changed bigint; item_id uuid;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  if p_item_ids is null or p_checked is null or cardinality(p_item_ids)>1000 or coalesce(array_ndims(p_item_ids),1)<>1
    or exists(select 1 from unnest(p_item_ids) i where i is null)
    or (select count(distinct i) from unnest(p_item_ids) i)<>cardinality(p_item_ids) then
    raise exception 'Selección de artículos inválida.' using errcode = '22023';
  end if;
  for item_id in select i from unnest(p_item_ids) i order by i loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  end loop;
  if (select count(*) from public.shopping_items where list_id=p_list_id and id=any(p_item_ids))<>cardinality(p_item_ids) then
    raise exception 'Hay artículos que no están disponibles en esta lista.' using errcode = '42501';
  end if;
  if exists(select 1 from public.shopping_items where list_id=p_list_id and id=any(p_item_ids)
    and transferred_at is not null and checked is distinct from p_checked) then
    raise exception 'No se puede cambiar el estado de un artículo transferido.' using errcode = '22023';
  end if;
  update public.shopping_items set checked=p_checked,updated_at=clock_timestamp()
    where list_id=p_list_id and id=any(p_item_ids) and checked is distinct from p_checked;
  get diagnostics changed = row_count;
  if changed>0 then
    update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  end if;
  return selected;
end;
$$;
revoke all on function public.set_my_shopping_checked(uuid,uuid[],boolean,bigint) from public, anon;
grant execute on function public.set_my_shopping_checked(uuid,uuid[],boolean,bigint) to authenticated;

-- Removal may include transferred rows: receipt snapshots and the unique
-- original_shopping_item_id remain, and the nullable item FK becomes NULL.
create function public.remove_my_shopping_item(p_list_id uuid, p_item_id uuid, p_expected_version bigint)
returns public.shopping_lists language plpgsql volatile security definer set search_path = ''
as $$
declare selected public.shopping_lists; changed bigint;
begin
  selected := public.lock_my_active_shopping_list(p_list_id,p_expected_version);
  if p_item_id is null then raise exception 'Falta el artículo.' using errcode = '22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || p_item_id::text,0));
  delete from public.shopping_items where list_id=p_list_id and id=p_item_id;
  get diagnostics changed = row_count;
  if changed>0 then
    update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id returning * into selected;
  end if;
  return selected;
end;
$$;
revoke all on function public.remove_my_shopping_item(uuid,uuid,bigint) from public, anon;
grant execute on function public.remove_my_shopping_item(uuid,uuid,bigint) to authenticated;

commit;
