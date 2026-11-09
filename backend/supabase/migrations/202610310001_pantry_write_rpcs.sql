begin;

-- Every pantry mutation advances this row's version, including writes made by
-- trusted transfer/cooking RPCs. Clients use the version as an optimistic lock.
alter table public.pantry_items add column version bigint not null default 1 check (version > 0);
alter table public.pantry_items alter column quantity type numeric(14,4),
  alter column minimum type numeric(14,4);

create function public.advance_pantry_item_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;
revoke all on function public.advance_pantry_item_version() from public, anon, authenticated;
create trigger advance_pantry_item_version before update on public.pantry_items
  for each row execute function public.advance_pantry_item_version();

-- Full snapshot upsert. The caller supplies a stable UUID and expected version
-- (0 for create). Empty or omitted expiry stays NULL; catalog refs stay NULL
-- unless explicitly selected by the caller.
create function public.put_my_pantry_item(p_item jsonb, p_expected_version bigint)
returns public.pantry_items language plpgsql volatile security definer set search_path = ''
as $$
declare
  actor uuid; item_id uuid; saved public.pantry_items; existing public.pantry_items;
  ingredient public.ingredients; unit_row public.units; category_row public.categories;
  amount numeric; minimum_amount numeric; expiry_date date; name_value text; category_value text;
  unit_value text; ingredient_ref_value uuid; unit_ref_value uuid; ingredient_id_value text;
begin
  actor := public.lock_my_relational_account();
  if jsonb_typeof(p_item) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_item) k where k not in
      ('id','name','category','quantity','unit','minimum','expiry','ingredient_ref','ingredient_id')) then
    raise exception 'Formato del ingrediente inválido.' using errcode='22023';
  end if;
  if jsonb_typeof(p_item->'id') is distinct from 'string'
    or jsonb_typeof(p_item->'name') is distinct from 'string'
    or jsonb_typeof(p_item->'category') is distinct from 'string'
    or jsonb_typeof(p_item->'unit') is distinct from 'string'
    or jsonb_typeof(p_item->'quantity') is distinct from 'number'
    or jsonb_typeof(p_item->'minimum') is distinct from 'number'
    or (p_item ? 'expiry' and jsonb_typeof(p_item->'expiry') not in ('null','string'))
    or (p_item ? 'ingredient_ref' and jsonb_typeof(p_item->'ingredient_ref') not in ('null','string'))
    or (p_item ? 'ingredient_id' and jsonb_typeof(p_item->'ingredient_id') not in ('null','string')) then
    raise exception 'Faltan datos o hay tipos inválidos.' using errcode='22023';
  end if;
  item_id := (p_item->>'id')::uuid;
  name_value := regexp_replace(trim(p_item->>'name'), '\s+', ' ', 'g');
  category_value := trim(p_item->>'category'); unit_value := trim(p_item->>'unit');
  amount := (p_item->>'quantity')::numeric; minimum_amount := (p_item->>'minimum')::numeric;
  if length(name_value) not between 1 and 120 or length(category_value) not between 1 and 80
    or length(unit_value) not between 1 and 24
    or amount < 0 or amount > 1000000 or amount <> round(amount,4)
    or minimum_amount < 0 or minimum_amount > 1000000 or minimum_amount <> round(minimum_amount,4)
    then
    raise exception 'El nombre o las cantidades están fuera del rango admitido.' using errcode='22023';
  end if;
  if nullif(p_item->>'expiry','') is not null then
    if (p_item->>'expiry') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'La fecha de vencimiento es inválida.' using errcode='22023';
    end if;
    expiry_date := (p_item->>'expiry')::date;
  end if;
  if nullif(p_item->>'ingredient_ref','') is not null then ingredient_ref_value := (p_item->>'ingredient_ref')::uuid; end if;
  if p_item ? 'ingredient_id' then ingredient_id_value := nullif(p_item->>'ingredient_id',''); end if;
  if ingredient_id_value is not null and length(ingredient_id_value)>200 then
    raise exception 'El vínculo histórico del ingrediente no es válido.' using errcode='22023';
  end if;
  select * into unit_row from public.units where abbreviation=unit_value and active and not is_deleted for share;
  if not found or not exists(select 1 from public.units root where root.id=coalesce(unit_row.base_unit_id,unit_row.id)
    and root.active and not root.is_deleted and root.base_unit_id is null) then
    raise exception 'La unidad no está disponible.' using errcode='22023';
  end if;
  unit_ref_value := unit_row.id;
  select * into category_row from public.categories where name=category_value and active and not is_deleted for share;
  if not found then raise exception 'La categoría no está disponible.' using errcode='22023'; end if;
  if ingredient_ref_value is not null then
    select * into ingredient from public.ingredients where id=ingredient_ref_value and active and not is_deleted for share;
    if not found or ingredient.name is distinct from name_value or ingredient.category_id is distinct from category_row.id
      or not exists(select 1 from public.units base where base.id=ingredient.base_unit_id and base.active and not base.is_deleted
        and base.dimension=unit_row.dimension and coalesce(base.base_unit_id,base.id)=coalesce(unit_row.base_unit_id,unit_row.id)) then
      raise exception 'El ingrediente o su unidad no están disponibles.' using errcode='22023';
    end if;
    if p_item ? 'ingredient_id' and nullif(p_item->>'ingredient_id','') is not null
      and p_item->>'ingredient_id' is distinct from coalesce(ingredient.legacy_id,ingredient.id::text) then
      raise exception 'El identificador legado no corresponde al ingrediente.' using errcode='22023';
    end if;
    ingredient_id_value:=coalesce(ingredient.legacy_id,ingredient.id::text);
  end if;

  select * into existing from public.pantry_items where id=item_id and user_id=actor for update;
  if not (p_item ? 'ingredient_id') then
    if found then ingredient_id_value:=existing.ingredient_id;
    elsif ingredient_ref_value is not null then ingredient_id_value:=coalesce(ingredient.legacy_id,ingredient.id::text);
    end if;
  end if;
  if p_expected_version=0 then
    if found then
      -- Safe retry after a lost create response: same UUID and same payload.
      if existing.version=1 and existing.name=name_value and existing.category=category_value
        and existing.quantity=amount and existing.unit=unit_value and existing.minimum=minimum_amount
        and existing.expiry is not distinct from expiry_date
        and existing.ingredient_ref is not distinct from ingredient_ref_value
        and existing.ingredient_id is not distinct from ingredient_id_value then return existing; end if;
      raise exception 'El ingrediente ya existe; recargá la despensa.' using errcode='40001';
    end if;
    insert into public.pantry_items(id,user_id,name,category,quantity,unit,minimum,expiry,ingredient_id,ingredient_ref,unit_ref)
      values(item_id,actor,name_value,category_value,amount,unit_value,minimum_amount,expiry_date,
        ingredient_id_value,
        ingredient_ref_value,unit_ref_value) returning * into saved;
    return saved;
  end if;
  if not found or existing.version<>p_expected_version then
    raise exception 'El ingrediente cambió en otra sesión. Recargalo antes de guardar.' using errcode='40001';
  end if;
  update public.pantry_items set name=name_value,category=category_value,quantity=amount,unit=unit_value,
    minimum=minimum_amount,expiry=expiry_date,ingredient_id=ingredient_id_value,
    ingredient_ref=ingredient_ref_value,unit_ref=unit_ref_value,updated_at=clock_timestamp()
    where id=item_id and user_id=actor returning * into saved;
  return saved;
exception when data_exception or check_violation or not_null_violation or foreign_key_violation or unique_violation then
  raise exception 'Los datos del ingrediente no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.put_my_pantry_item(jsonb,bigint) from public,anon;
grant execute on function public.put_my_pantry_item(jsonb,bigint) to authenticated;

-- Atomic confirmation for starter kits and reviewed receipt proposals. Each
-- entry is {item: <same full snapshot>, expected_version: bigint}; stable item
-- UUIDs make a completed batch safe to retry after a lost response.
create function public.put_my_pantry_items(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare entry jsonb; item_id uuid; expected bigint; saved public.pantry_items; output_rows jsonb:='[]'::jsonb;
begin
  perform public.lock_my_relational_account();
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200
    or exists(select 1 from jsonb_array_elements(p_items) as entries(e) where jsonb_typeof(e) is distinct from 'object'
      or jsonb_typeof(e->'item') is distinct from 'object' or jsonb_typeof(e->'expected_version') is distinct from 'number'
      or exists(select 1 from jsonb_object_keys(e) as keys(k) where k not in ('item','expected_version'))
      or (e->>'expected_version')::numeric < 0
      or (e->>'expected_version')::numeric > 9223372036854775807
      or (e->>'expected_version')::numeric <> trunc((e->>'expected_version')::numeric)) then
    raise exception 'La confirmación de ingredientes no es válida.' using errcode='22023';
  end if;
  if (select count(distinct ((e->'item'->>'id')::uuid)) from jsonb_array_elements(p_items) as entries(e))<>jsonb_array_length(p_items)
    or exists(select 1 from jsonb_array_elements(p_items) as entries(e) where e->'item'->>'id' is null) then
    raise exception 'La confirmación contiene ingredientes repetidos o incompletos.' using errcode='22023';
  end if;
  -- Stable UUID order avoids lock-order inversions when batches overlap.
  for entry in select e from jsonb_array_elements(p_items) as entries(e) order by (e->'item'->>'id') loop
    item_id := (entry->'item'->>'id')::uuid;
    expected := (entry->>'expected_version')::bigint;
    select * into saved from public.put_my_pantry_item(entry->'item',expected);
    output_rows := output_rows || jsonb_build_array(to_jsonb(saved));
  end loop;
  return output_rows;
exception when data_exception or check_violation or not_null_violation or foreign_key_violation or unique_violation then
  raise exception 'No se pudieron confirmar los ingredientes.' using errcode='22023';
end;
$$;
revoke all on function public.put_my_pantry_items(jsonb) from public,anon;
grant execute on function public.put_my_pantry_items(jsonb) to authenticated;

create function public.delete_my_pantry_item(p_item_id uuid, p_expected_version bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; existing public.pantry_items;
begin
  actor:=public.lock_my_relational_account();
  if p_item_id is null or p_expected_version is null or p_expected_version<1 then
    raise exception 'Solicitud de eliminación inválida.' using errcode='22023';
  end if;
  select * into existing from public.pantry_items where id=p_item_id and user_id=actor for update;
  if not found then return false; end if;
  if existing.version<>p_expected_version then
    raise exception 'El ingrediente cambió en otra sesión. Recargalo antes de eliminar.' using errcode='40001';
  end if;
  delete from public.pantry_items where id=p_item_id and user_id=actor;
  return true;
end;
$$;
revoke all on function public.delete_my_pantry_item(uuid,bigint) from public,anon;
grant execute on function public.delete_my_pantry_item(uuid,bigint) to authenticated;

-- Retain owner-scoped reads. All client writes now go through validated RPCs;
-- trusted SECURITY DEFINER transfer/cooking routines retain their behavior.
revoke insert,update,delete on public.pantry_items from anon,authenticated;
commit;
