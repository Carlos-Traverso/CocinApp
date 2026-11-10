begin;

-- Dietary tags have stable keys because recipes and user preferences refer to
-- them. Ingredient links use the existing ingredient version as their write token.
alter table public.dietary_tags add column version bigint not null default 1 check (version > 0);

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed',
  'catalog.dietary_tag_saved','catalog.ingredient_dietary_tags_saved'
));

create or replace function public.admin_put_dietary_tag(p_tag jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_id uuid;
  v_tag_key text;
  v_label text;
  v_description text;
  v_active boolean;
  v_version bigint;
  v_saved jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();

  if jsonb_typeof(p_tag) is distinct from 'object' or p_expected_version is null or p_expected_version < 0
    or exists(select 1 from jsonb_object_keys(p_tag) k where k not in ('id','tag_key','label','description','active'))
    or jsonb_typeof(p_tag->'id') is distinct from 'string'
    or jsonb_typeof(p_tag->'tag_key') is distinct from 'string'
    or jsonb_typeof(p_tag->'label') is distinct from 'string'
    or jsonb_typeof(p_tag->'description') is distinct from 'string'
    or jsonb_typeof(p_tag->'active') is distinct from 'boolean' then
    raise exception 'La solicitud de etiqueta dietaria no es válida.' using errcode='22023';
  end if;
  v_id := (p_tag->>'id')::uuid;
  v_tag_key := p_tag->>'tag_key';
  v_label := regexp_replace(trim(p_tag->>'label'), '\s+', ' ', 'g');
  v_description := p_tag->>'description';
  v_active := (p_tag->>'active')::boolean;
  if v_tag_key !~ '^[a-z0-9-]{2,50}$' or length(v_label) not between 1 and 80 or length(v_description)>2000 then
    raise exception 'Los datos de la etiqueta dietaria están fuera de rango.' using errcode='22023';
  end if;

  select t.version into v_version from public.dietary_tags t where t.id=v_id for update;
  if p_expected_version=0 then
    if found then
      select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
        into v_saved from public.dietary_tags t where t.id=v_id;
      if v_version=1 and v_saved->>'tag_key'=v_tag_key and v_saved->>'label'=v_label
        and v_saved->>'description'=v_description and v_saved->>'active'=v_active::text then return v_saved; end if;
      raise exception 'La etiqueta ya existe con cambios; recargá el catálogo.' using errcode='40001';
    end if;
    insert into public.dietary_tags(id,tag_key,label,description,active)
      values(v_id,v_tag_key,v_label,v_description,v_active) returning version into v_version;
  else
    if not found or v_version<>p_expected_version then
      raise exception 'La etiqueta cambió; recargá el catálogo.' using errcode='40001';
    end if;
    select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
      into v_saved from public.dietary_tags t where t.id=v_id;
    if v_saved->>'tag_key' is distinct from v_tag_key then
      raise exception 'La clave de una etiqueta dietaria es inmutable.' using errcode='22023';
    end if;
    if v_saved->>'label'=v_label and v_saved->>'description'=v_description and v_saved->>'active'=v_active::text then return v_saved; end if;
    update public.dietary_tags set label=v_label,description=v_description,active=v_active,
      updated_at=clock_timestamp(),version=version+1 where id=v_id returning version into v_version;
  end if;
  select jsonb_build_object('id',t.id,'tag_key',t.tag_key,'label',t.label,'description',t.description,'active',t.active,'version',t.version)
    into v_saved from public.dietary_tags t where t.id=v_id;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'catalog.dietary_tag_saved',jsonb_build_object('entity_id',v_id,'version',v_version));
  return v_saved;
exception
  when unique_violation then raise exception 'Ya existe una etiqueta dietaria con esa clave o identificador.' using errcode='23505';
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'Los datos de la etiqueta dietaria no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_put_dietary_tag(jsonb,bigint) from public,anon;
grant execute on function public.admin_put_dietary_tag(jsonb,bigint) to authenticated;

create or replace function public.admin_save_ingredient_dietary_tags(p_ingredient_id uuid,p_tags jsonb,p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_variable
declare
  v_actor uuid := (select auth.uid());
  v_ingredient public.ingredients;
  v_tag jsonb;
  v_key text;
  v_compatibility text;
  v_note text;
  v_tag_id uuid;
  v_changed boolean := false;
  v_new_version bigint;
  v_result jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not (select public.current_account_is_active())
    or (select public.current_app_role()) <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar el catálogo.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_ingredient_id is null or p_expected_version is null or p_expected_version<1
    or jsonb_typeof(p_tags) is distinct from 'array' or jsonb_array_length(p_tags)>100 then
    raise exception 'La solicitud de etiquetas del ingrediente no es válida.' using errcode='22023';
  end if;

  select i.* into v_ingredient from public.ingredients i where i.id=p_ingredient_id for update;
  if not found or v_ingredient.version<>p_expected_version then
    raise exception 'El ingrediente cambió o no existe; recargá el catálogo.' using errcode='40001';
  end if;

  for v_tag in select value from jsonb_array_elements(p_tags) loop
    if jsonb_typeof(v_tag) is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(v_tag) k where k not in ('tag_key','compatibility','note'))
      or jsonb_typeof(v_tag->'tag_key') is distinct from 'string'
      or jsonb_typeof(v_tag->'compatibility') is distinct from 'string'
      or jsonb_typeof(v_tag->'note') is distinct from 'string' then
      raise exception 'Una etiqueta del ingrediente no es válida.' using errcode='22023';
    end if;
    v_key:=v_tag->>'tag_key'; v_compatibility:=v_tag->>'compatibility'; v_note:=v_tag->>'note';
    if v_key !~ '^[a-z0-9-]{2,50}$' or v_compatibility not in ('suitable','contains','unknown') or length(v_note)>1000 then
      raise exception 'Una etiqueta del ingrediente está fuera de rango.' using errcode='22023';
    end if;
    if (select count(*) from jsonb_array_elements(p_tags) x where x->>'tag_key'=v_key)>1 then
      raise exception 'Las etiquetas del ingrediente no pueden repetirse.' using errcode='22023';
    end if;
    select t.id into v_tag_id from public.dietary_tags t where t.tag_key=v_key and t.active;
    if v_tag_id is null then
      if not exists(select 1 from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id
        where it.ingredient_id=p_ingredient_id and t.tag_key=v_key and it.compatibility=v_compatibility and it.note=v_note) then
        raise exception 'Etiqueta dietaria inactiva o inexistente.' using errcode='22023';
      end if;
    end if;
    if (not v_ingredient.active or v_ingredient.is_deleted) and not exists(
      select 1 from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id
      where it.ingredient_id=p_ingredient_id and t.tag_key=v_key and it.compatibility=v_compatibility and it.note=v_note) then
      raise exception 'Un ingrediente inactivo solo admite conservar o quitar sus etiquetas.' using errcode='22023';
    end if;
  end loop;

  select exists(
    (select t.tag_key,it.compatibility,it.note from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id
      except select x->>'tag_key',x->>'compatibility',x->>'note' from jsonb_array_elements(p_tags) x)
    union all
    (select x->>'tag_key',x->>'compatibility',x->>'note' from jsonb_array_elements(p_tags) x
      except select t.tag_key,it.compatibility,it.note from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id)
  ) into v_changed;
  if not v_changed then
    select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'compatibility',it.compatibility,'note',it.note) order by t.tag_key),'[]'::jsonb)
      into v_result from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id;
    return jsonb_build_object('ingredient_id',p_ingredient_id,'version',v_ingredient.version,'tags',v_result);
  end if;

  delete from public.ingredient_dietary_tags it where it.ingredient_id=p_ingredient_id;
  for v_tag in select value from jsonb_array_elements(p_tags) loop
    select t.id into v_tag_id from public.dietary_tags t where t.tag_key=v_tag->>'tag_key';
    insert into public.ingredient_dietary_tags(ingredient_id,dietary_tag_id,compatibility,note)
      values(p_ingredient_id,v_tag_id,v_tag->>'compatibility',v_tag->>'note');
  end loop;
  update public.ingredients set version=version+1,updated_at=clock_timestamp() where id=p_ingredient_id returning version into v_new_version;
  select coalesce(jsonb_agg(jsonb_build_object('tag_key',t.tag_key,'compatibility',it.compatibility,'note',it.note) order by t.tag_key),'[]'::jsonb)
    into v_result from public.ingredient_dietary_tags it join public.dietary_tags t on t.id=it.dietary_tag_id where it.ingredient_id=p_ingredient_id;
  insert into public.admin_audit_log(actor_user_id,action,details)
    values(v_actor,'catalog.ingredient_dietary_tags_saved',jsonb_build_object('entity_id',p_ingredient_id,'version',v_new_version));
  return jsonb_build_object('ingredient_id',p_ingredient_id,'version',v_new_version,'tags',v_result);
exception
  when unique_violation then raise exception 'Las etiquetas del ingrediente no pueden repetirse.' using errcode='23505';
  when data_exception or check_violation or not_null_violation or foreign_key_violation then
    raise exception 'Los datos de las etiquetas del ingrediente no son válidos.' using errcode='22023';
end;
$$;
revoke all on function public.admin_save_ingredient_dietary_tags(uuid,jsonb,bigint) from public,anon;
grant execute on function public.admin_save_ingredient_dietary_tags(uuid,jsonb,bigint) to authenticated;

revoke insert,update,delete on public.dietary_tags,public.ingredient_dietary_tags from public,anon,authenticated;
grant select on public.dietary_tags,public.ingredient_dietary_tags to authenticated;
commit;
