begin;

-- Admin-owned relational catalog. Stable ids plus expected_version=0 make
-- creates safely replayable; updates use the current row version as a lock.
alter table public.categories add column version bigint not null default 1 check (version > 0);
alter table public.units add column version bigint not null default 1 check (version > 0);
alter table public.ingredients add column version bigint not null default 1 check (version > 0);
alter table public.categories drop constraint if exists categories_normalized_name_key;
alter table public.units add column normalized_name text;
update public.units set normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(name),NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));
alter table public.units alter column normalized_name set not null;
create unique index if not exists categories_non_deleted_normalized_name_uidx on public.categories(normalized_name) where not is_deleted;
create unique index if not exists units_non_deleted_normalized_name_uidx on public.units(normalized_name) where not is_deleted;

-- Existing backfill writers predate normalized_name. Keep them compatible and
-- ensure every unit write uses the same accent/whitespace folding as the UI.
create or replace function public.normalize_catalog_unit_name()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.normalized_name := lower(regexp_replace(regexp_replace(normalize(trim(new.name),NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));
  return new;
end;
$$;
revoke all on function public.normalize_catalog_unit_name() from public,anon,authenticated;
create trigger normalize_catalog_unit_name_before_write
before insert or update of name,normalized_name on public.units
for each row execute function public.normalize_catalog_unit_name();

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved', 'catalog.category_saved',
  'catalog.unit_saved','catalog.ingredient_saved'
));

create or replace function public.admin_put_catalog_entity(p_kind text, p_entity jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  actor uuid; entity_id uuid; saved jsonb; current_version bigint; normalized text;
  entity_name text; active_value boolean; deleted_value boolean;
  category_id uuid; unit_id uuid; base_id uuid; dim text; mult numeric;
  abbreviation_value text; audit_action text;
begin
  -- Same lock as role changes and account status mutations. Recheck only after
  -- acquiring it, so a concurrent demotion/ban cannot race authorization.
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  actor := (select auth.uid());
  if actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_kind is null or p_kind not in ('category','unit','ingredient') or jsonb_typeof(p_entity) is distinct from 'object'
    or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_entity) k where k not in
      ('id','name','active','is_deleted','abbreviation','dimension','base_unit_id','equivalence_multiplier','category_id')) then
    raise exception 'La solicitud del catálogo no es válida.' using errcode='22023';
  end if;
  if (p_kind='category' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted')))
    or (p_kind='unit' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted','abbreviation','dimension','base_unit_id','equivalence_multiplier')))
    or (p_kind='ingredient' and exists(select 1 from jsonb_object_keys(p_entity) k where k not in ('id','name','active','is_deleted','category_id','base_unit_id'))) then
    raise exception 'La solicitud contiene campos ajenos al tipo de catálogo.' using errcode='22023';
  end if;
  if jsonb_typeof(p_entity->'id') is distinct from 'string' or jsonb_typeof(p_entity->'name') is distinct from 'string'
    or (p_entity ? 'active' and jsonb_typeof(p_entity->'active') <> 'boolean')
    or (p_entity ? 'is_deleted' and jsonb_typeof(p_entity->'is_deleted') <> 'boolean') then
    raise exception 'Faltan datos o hay tipos inválidos.' using errcode='22023';
  end if;
  entity_id := (p_entity->>'id')::uuid;
  entity_name := regexp_replace(trim(p_entity->>'name'), '\s+', ' ', 'g');
  active_value := coalesce((p_entity->>'active')::boolean,true);
  deleted_value := coalesce((p_entity->>'is_deleted')::boolean,false);
  if deleted_value and active_value then raise exception 'Un elemento eliminado debe quedar inactivo.' using errcode='22023'; end if;
  if length(entity_name) < 1 or length(entity_name) > (case p_kind when 'category' then 100 when 'unit' then 60 else 120 end) then
    raise exception 'El nombre está fuera del rango admitido.' using errcode='22023';
  end if;
  normalized := lower(regexp_replace(regexp_replace(normalize(entity_name,NFD), U&'[\0300-\036f]', '', 'g'), '\s+', ' ', 'g'));

  if p_kind='category' then
    audit_action := 'catalog.category_saved';
    select version into current_version from public.categories where id=entity_id for update;
    if p_expected_version=0 then
      if found then
        select to_jsonb(c) into saved from public.categories c where c.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'La categoría ya existe con cambios; recargá el catálogo.' using errcode='40001';
      end if;
      insert into public.categories(id,name,normalized_name,active,is_deleted) values(entity_id,entity_name,normalized,active_value,deleted_value) returning to_jsonb(categories.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'La categoría cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(c) into saved from public.categories c where c.id=entity_id;
      if saved->>'name'=entity_name and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      update public.categories set name=entity_name,normalized_name=normalized,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(categories.*) into saved;
    end if;
  elsif p_kind='unit' then
    audit_action := 'catalog.unit_saved';
    if jsonb_typeof(p_entity->'abbreviation') is distinct from 'string' or jsonb_typeof(p_entity->'dimension') is distinct from 'string'
      or (p_entity ? 'base_unit_id' and jsonb_typeof(p_entity->'base_unit_id') not in ('string','null'))
      or (p_entity ? 'equivalence_multiplier' and jsonb_typeof(p_entity->'equivalence_multiplier') not in ('number','null')) then
      raise exception 'Los datos de la unidad no son válidos.' using errcode='22023'; end if;
    abbreviation_value:=trim(p_entity->>'abbreviation'); dim:=p_entity->>'dimension';
    if length(abbreviation_value) not between 1 and 24 or dim not in ('mass','volume','count') then raise exception 'Unidad fuera de rango.' using errcode='22023'; end if;
    if nullif(p_entity->>'base_unit_id','') is not null then base_id:=(p_entity->>'base_unit_id')::uuid; end if;
    if nullif(p_entity->>'equivalence_multiplier','') is not null then mult:=(p_entity->>'equivalence_multiplier')::numeric; end if;
    if (base_id is null) <> (mult is null) or mult is not null and (mult<=0 or mult>99999999.999999 or mult<>round(mult,6)) then raise exception 'Equivalencia inválida.' using errcode='22023'; end if;
    if base_id is not null and (base_id=entity_id or not exists(select 1 from public.units b where b.id=base_id and b.base_unit_id is null and b.dimension=dim and b.active and not b.is_deleted)) then raise exception 'La unidad base debe ser raíz, activa y compatible.' using errcode='22023'; end if;
    if exists(select 1 from public.units u where u.id<>entity_id and lower(u.abbreviation)=lower(abbreviation_value)) then raise exception 'La abreviatura de unidad ya está reservada.' using errcode='23505'; end if;
    select version into current_version from public.units where id=entity_id for update;
    if p_expected_version=0 then
      if found then select to_jsonb(u) into saved from public.units u where u.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'abbreviation'=abbreviation_value and saved->>'dimension'=dim and saved->>'base_unit_id' is not distinct from base_id::text and (saved->>'equivalence_multiplier')::numeric is not distinct from mult and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'La unidad ya existe con cambios; recargá el catálogo.' using errcode='40001'; end if;
      insert into public.units(id,name,normalized_name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted) values(entity_id,entity_name,normalized,abbreviation_value,dim,base_id,mult,active_value,deleted_value) returning to_jsonb(units.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'La unidad cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(u) into saved from public.units u where u.id=entity_id;
      if saved->>'name'=entity_name and saved->>'abbreviation'=abbreviation_value and saved->>'dimension'=dim and saved->>'base_unit_id' is not distinct from base_id::text and (saved->>'equivalence_multiplier')::numeric is not distinct from mult and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      if exists(select 1 from public.units u where u.id<>entity_id and not u.is_deleted and u.normalized_name=normalized) then raise exception 'Nombre de unidad duplicado.' using errcode='23505'; end if;
      if (abbreviation_value is distinct from saved->>'abbreviation' or dim is distinct from saved->>'dimension' or base_id is distinct from nullif(saved->>'base_unit_id','')::uuid or mult is distinct from (saved->>'equivalence_multiplier')::numeric)
        and (exists(select 1 from public.recipe_ingredients r where r.unit_id=entity_id)
          or exists(select 1 from public.pantry_items p where p.unit_ref=entity_id or p.unit_ref is null and p.unit=saved->>'abbreviation')
          or exists(select 1 from public.shopping_items s where s.unit_id=entity_id)
          or exists(select 1 from public.cooking_sessions cs cross join lateral jsonb_array_elements(case when jsonb_typeof(cs.recipe_snapshot->'ingredients')='array' then cs.recipe_snapshot->'ingredients' else '[]'::jsonb end) as item(value) where item.value->>'unitId'=entity_id::text or item.value->>'unitRootId'=entity_id::text)
          or exists(select 1 from public.cooking_events ce cross join lateral jsonb_array_elements(case when jsonb_typeof(ce.recipe_snapshot->'ingredients')='array' then ce.recipe_snapshot->'ingredients' else '[]'::jsonb end) as item(value) where item.value->>'unitId'=entity_id::text or item.value->>'unitRootId'=entity_id::text)) then
        raise exception 'No se puede cambiar la conversión de una unidad referenciada.' using errcode='23514';
      end if;
      if exists(select 1 from public.ingredients i where i.base_unit_id=entity_id) and (dim is distinct from (select dimension from public.units where id=entity_id) or base_id is not null) then raise exception 'No se puede cambiar la dimensión o raíz de una unidad usada como base.' using errcode='23514'; end if;
      if exists(select 1 from public.units child where child.base_unit_id=entity_id) and (dim is distinct from (select dimension from public.units where id=entity_id) or base_id is not null) then raise exception 'La unidad tiene equivalencias dependientes.' using errcode='23514'; end if;
      update public.units set name=entity_name,normalized_name=normalized,abbreviation=abbreviation_value,dimension=dim,base_unit_id=base_id,equivalence_multiplier=mult,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(units.*) into saved;
    end if;
  else
    audit_action := 'catalog.ingredient_saved';
    if jsonb_typeof(p_entity->'category_id') is distinct from 'string' or jsonb_typeof(p_entity->'base_unit_id') is distinct from 'string' then raise exception 'Faltan categoría y unidad base.' using errcode='22023'; end if;
    category_id:=(p_entity->>'category_id')::uuid; unit_id:=(p_entity->>'base_unit_id')::uuid;
    select version into current_version from public.ingredients where id=entity_id for update;
    if p_expected_version=0 then
      if found then select to_jsonb(i) into saved from public.ingredients i where i.id=entity_id;
        if current_version=1 and saved->>'name'=entity_name and saved->>'category_id'=category_id::text and saved->>'base_unit_id'=unit_id::text and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
        raise exception 'El ingrediente ya existe con cambios; recargá el catálogo.' using errcode='40001'; end if;
      if not exists(select 1 from public.categories where id=category_id and active and not is_deleted) or not exists(select 1 from public.units where id=unit_id and active and not is_deleted and base_unit_id is null) then raise exception 'Categoría o unidad base no disponible.' using errcode='22023'; end if;
      insert into public.ingredients(id,name,normalized_name,category_id,base_unit_id,active,is_deleted) values(entity_id,entity_name,normalized,category_id,unit_id,active_value,deleted_value) returning to_jsonb(ingredients.*) into saved;
    else
      if not found or current_version<>p_expected_version then raise exception 'El ingrediente cambió; recargá el catálogo.' using errcode='40001'; end if;
      select to_jsonb(i) into saved from public.ingredients i where i.id=entity_id;
      if saved->>'name'=entity_name and saved->>'category_id'=category_id::text and saved->>'base_unit_id'=unit_id::text and saved->>'active'=active_value::text and saved->>'is_deleted'=deleted_value::text then return saved; end if;
      if unit_id is distinct from nullif(saved->>'base_unit_id','')::uuid
        and (exists(select 1 from public.pantry_items p where p.ingredient_ref=entity_id)
          or exists(select 1 from public.recipe_ingredients r where r.ingredient_id=entity_id)
          or exists(select 1 from public.shopping_items s where s.ingredient_id=entity_id)) then
        raise exception 'No se puede cambiar la unidad base de un ingrediente referenciado.' using errcode='23514';
      end if;
      if not exists(select 1 from public.categories where id=category_id and (active and not is_deleted or id=(select i.category_id from public.ingredients i where i.id=entity_id))) or not exists(select 1 from public.units where id=unit_id and dimension=(select dimension from public.units where id=(select i.base_unit_id from public.ingredients i where i.id=entity_id)) and base_unit_id is null and (active and not is_deleted or id=(select i.base_unit_id from public.ingredients i where i.id=entity_id))) then raise exception 'Categoría o unidad base no disponible.' using errcode='22023'; end if;
      update public.ingredients set name=entity_name,normalized_name=normalized,category_id=category_id,base_unit_id=unit_id,active=active_value,is_deleted=deleted_value,updated_at=clock_timestamp(),version=version+1 where id=entity_id returning to_jsonb(ingredients.*) into saved;
    end if;
  end if;
  insert into public.admin_audit_log(actor_user_id,action,details) values(actor,audit_action,jsonb_build_object('entity_id',entity_id,'version',(saved->>'version')::bigint));
  return saved;
exception when unique_violation then raise exception 'Ya existe un elemento del catálogo con ese nombre o identificador.' using errcode='23505';
when data_exception or check_violation or not_null_violation or foreign_key_violation then raise exception 'Los datos del catálogo no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_put_catalog_entity(text,jsonb,bigint) from public,anon;

create function public.admin_put_category(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('category',p_entity,p_expected_version) $$;
create function public.admin_put_unit(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('unit',p_entity,p_expected_version) $$;
create function public.admin_put_ingredient(p_entity jsonb,p_expected_version bigint) returns jsonb language sql volatile security definer set search_path='' as $$ select public.admin_put_catalog_entity('ingredient',p_entity,p_expected_version) $$;
revoke all on function public.admin_put_category(jsonb,bigint),public.admin_put_unit(jsonb,bigint),public.admin_put_ingredient(jsonb,bigint) from public,anon;
grant execute on function public.admin_put_category(jsonb,bigint),public.admin_put_unit(jsonb,bigint),public.admin_put_ingredient(jsonb,bigint) to authenticated;

revoke insert,update,delete on public.categories,public.units,public.ingredients from public,anon,authenticated;
grant select on public.categories,public.units,public.ingredients to authenticated;
commit;
