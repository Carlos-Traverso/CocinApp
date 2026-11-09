begin;

-- The request is preserved independently of nullable historical foreign keys.
alter table public.pantry_receipts
  add column shopping_list_id uuid references public.shopping_lists(id) on delete set null,
  add column requested_list_id uuid,
  add column requested_item_ids uuid[],
  add column resulting_list_version bigint;
alter table public.pantry_receipt_items
  add column ingredient_id_snapshot uuid,
  add column name_snapshot text,
  add column category_snapshot text,
  add column purchased_quantity numeric(14,4),
  add column purchased_unit_id_snapshot uuid,
  add column purchased_unit_abbreviation_snapshot text,
  add column pantry_unit_id_snapshot uuid;

-- Existing inventory has three decimal places. Retain it without silently
-- rounding four-decimal shopping amounts when converting into stored units.
alter table public.pantry_items alter column quantity type numeric(14,4),
  alter column minimum type numeric(14,4);

create function public.transfer_my_shopping_to_pantry(
  p_list_id uuid, p_item_ids uuid[], p_idempotency_key uuid, p_expected_version bigint)
returns public.pantry_receipts language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; selected public.shopping_lists; receipt public.pantry_receipts;
  ids uuid[]; item_id uuid; item public.shopping_items; ingredient public.ingredients;
  source_unit public.units; target_unit public.units; ingredient_unit public.units;
  category public.categories; stock public.pantry_items; candidate public.pantry_items;
  addition numeric; target_id uuid; target_abbreviation text; item_name text; item_category text;
begin
  actor := public.lock_my_relational_account();
  if p_list_id is null or p_idempotency_key is null or p_expected_version is null or p_expected_version<1
    or p_item_ids is null or cardinality(p_item_ids) not between 1 and 1000
    or coalesce(array_ndims(p_item_ids),1)<>1
    or exists(select 1 from unnest(p_item_ids) i where i is null)
    or (select count(distinct i) from unnest(p_item_ids) i)<>cardinality(p_item_ids) then
    raise exception 'Solicitud de transferencia inválida.' using errcode='22023';
  end if;
  select array_agg(i order by i) into ids from unnest(p_item_ids) i;
  -- A completed retry works after list archival/deletion of transferred items.
  select * into receipt from public.pantry_receipts
    where owner_user_id=actor and idempotency_key=p_idempotency_key;
  if found then
    if receipt.requested_list_id is distinct from p_list_id or receipt.requested_item_ids is distinct from ids then
      raise exception 'La clave de transferencia ya corresponde a otra solicitud.' using errcode='22023';
    end if;
    return receipt;
  end if;
  select * into selected from public.shopping_lists where id=p_list_id and owner_user_id=actor and status='active' for update;
  if not found then raise exception 'La lista no está disponible para esta cuenta.' using errcode='42501'; end if;
  if selected.version<>p_expected_version then
    raise exception 'La lista cambió en otra sesión. Recargala antes de transferir.' using errcode='40001';
  end if;
  foreach item_id in array ids loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cocinapp.shopping-item:' || item_id::text,0));
  end loop;
  if (select count(*) from public.shopping_items where list_id=p_list_id and id=any(ids))<>cardinality(ids) then
    raise exception 'Hay artículos que no están disponibles en esta lista.' using errcode='42501';
  end if;
  -- Catalog rows and conversion roots are locked in a single stable order.
  perform 1 from public.ingredients where id in (
    select ingredient_id from public.shopping_items where id=any(ids)) order by id for share;
  perform 1 from public.units order by id for share;
  perform 1 from public.categories order by id for share;
  insert into public.pantry_receipts(owner_user_id,idempotency_key,shopping_list_id,requested_list_id,requested_item_ids,resulting_list_version)
    values(actor,p_idempotency_key,p_list_id,p_list_id,ids,selected.version+1) returning * into receipt;
  foreach item_id in array ids loop
    select * into item from public.shopping_items where id=item_id and list_id=p_list_id for update;
    if not item.checked or item.transferred_at is not null or exists(
      select 1 from public.pantry_receipt_items where original_shopping_item_id=item_id) then
      raise exception 'El artículo no está comprado o ya fue transferido.' using errcode='22023';
    end if;
    select * into source_unit from public.units where id=item.unit_id and active and not is_deleted;
    if not found or not exists(select 1 from public.units where id=coalesce(source_unit.base_unit_id,source_unit.id) and active and not is_deleted) then
      raise exception 'La unidad no está disponible.' using errcode='22023';
    end if;
    if item.ingredient_id is not null then
      select * into ingredient from public.ingredients where id=item.ingredient_id and active and not is_deleted;
      if not found then raise exception 'El ingrediente no está disponible.' using errcode='22023'; end if;
      select * into ingredient_unit from public.units where id=ingredient.base_unit_id and active and not is_deleted;
      if not found or coalesce(ingredient_unit.base_unit_id,ingredient_unit.id)<>coalesce(source_unit.base_unit_id,source_unit.id)
        or ingredient_unit.dimension<>source_unit.dimension then
        raise exception 'La unidad no es compatible con el ingrediente.' using errcode='22023';
      end if;
      select * into category from public.categories where id=ingredient.category_id and active and not is_deleted;
      if not found then raise exception 'La categoría no está disponible.' using errcode='22023'; end if;
      item_name:=ingredient.name; item_category:=category.name;
    else
      item_name:=trim(item.name_snapshot); item_category:=trim(item.category_snapshot);
      if not exists(select 1 from public.categories where name=item_category and active and not is_deleted) then
        raise exception 'La categoría del artículo manual no está disponible.' using errcode='22023';
      end if;
    end if;
    if length(item_category)>80 or length(source_unit.abbreviation)>24 then
      raise exception 'La etiqueta no cabe en el inventario actual.' using errcode='22023';
    end if;
    -- Do not infer catalog associations. Manual stock only merges with manual
    -- stock of the same normalized name, keeping prior metadata and expiry.
    stock:=null;
    for candidate in select * from public.pantry_items p where p.user_id=actor
      and p.ingredient_ref is not distinct from item.ingredient_id
      and lower(trim(p.name))=lower(trim(item_name))
      and (p.expiry is null or p.expiry>=current_date) order by p.id for update loop
      select * into target_unit from public.units where id=candidate.unit_ref and active and not is_deleted;
      if not found and candidate.unit_ref is null then
        -- Legacy references may be null: an exact unique abbreviation is safe.
        select * into target_unit from public.units where abbreviation=candidate.unit and active and not is_deleted;
      end if;
      if target_unit.id is not null and target_unit.abbreviation=candidate.unit
        and target_unit.dimension=source_unit.dimension
        and coalesce(target_unit.base_unit_id,target_unit.id)=coalesce(source_unit.base_unit_id,source_unit.id) then
        stock:=candidate; exit;
      end if;
    end loop;
    if stock.id is null then
      target_unit:=source_unit;
      addition:=item.quantity;
      insert into public.pantry_items(user_id,ingredient_id,ingredient_ref,unit_ref,name,category,quantity,unit,minimum,expiry,source_shopping_ids)
        values(actor,case when item.ingredient_id is null then null else coalesce(ingredient.legacy_id,ingredient.id::text) end,
          item.ingredient_id,target_unit.id,item_name,item_category,addition,target_unit.abbreviation,0,null,array[item_id::text])
        returning id into target_id;
    else
      addition:=item.quantity*coalesce(source_unit.equivalence_multiplier,1)/coalesce(target_unit.equivalence_multiplier,1);
      if addition<>round(addition,4) then
        raise exception 'La conversión no puede representarse sin perder cantidad.' using errcode='22023';
      end if;
      if addition<=0 or stock.quantity+addition>1000000 then
        raise exception 'La cantidad excede el rango de inventario.' using errcode='22023';
      end if;
      update public.pantry_items set quantity=quantity+addition,unit_ref=target_unit.id,
        source_shopping_ids=array_append(source_shopping_ids,item_id::text),updated_at=clock_timestamp()
        where id=stock.id and user_id=actor returning id into target_id;
    end if;
    insert into public.pantry_receipt_items(receipt_id,original_shopping_item_id,shopping_item_id,pantry_item_id,
      quantity_added,unit_abbreviation_snapshot,ingredient_id_snapshot,name_snapshot,category_snapshot,
      purchased_quantity,purchased_unit_id_snapshot,purchased_unit_abbreviation_snapshot,pantry_unit_id_snapshot)
      values(receipt.id,item_id,item_id,target_id,addition,target_unit.abbreviation,item.ingredient_id,item_name,item_category,
        item.quantity,item.unit_id,source_unit.abbreviation,target_unit.id);
    update public.shopping_items set transferred_at=receipt.created_at,updated_at=clock_timestamp() where id=item_id;
  end loop;
  update public.shopping_lists set version=version+1,updated_at=clock_timestamp() where id=p_list_id;
  return receipt;
exception when data_exception or check_violation or not_null_violation or unique_violation or foreign_key_violation then
  raise exception 'No se pudo transferir la compra con esos datos.' using errcode='22023';
end;
$$;
revoke all on function public.transfer_my_shopping_to_pantry(uuid,uuid[],uuid,bigint) from public,anon;
grant execute on function public.transfer_my_shopping_to_pantry(uuid,uuid[],uuid,bigint) to authenticated;

-- Conversion definitions referenced by stock are historical meaning too.
create function public.protect_pantry_unit_conversion() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if (new.dimension,new.base_unit_id,new.equivalence_multiplier) is distinct from
     (old.dimension,old.base_unit_id,old.equivalence_multiplier)
    and exists(select 1 from public.pantry_items where unit_ref=old.id) then
    raise exception 'No se puede cambiar la conversión de una unidad usada en despensa.' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function public.protect_pantry_unit_conversion() from public,anon,authenticated;
create trigger protect_pantry_unit_conversion before update on public.units for each row execute function public.protect_pantry_unit_conversion();
commit;
