begin;

-- Read helpers retain archived ingredient/unit/category references and recipe
-- versions. The established payload helper already returns inactive FK rows.
create function public.recipe_read_payload(p_recipe public.recetas)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_set(public.recipe_discovery_payload(p_recipe,null)->'recipe','{ingredients}',
    coalesce((select jsonb_agg(x.value || jsonb_build_object('category_id',c.id,'category',c.name)
      order by (x.value->>'position')::integer)
      from jsonb_array_elements(public.recipe_discovery_payload(p_recipe,null)->'recipe'->'ingredients') x(value)
      join public.ingredientes i on i.id=(x.value->>'ingredient_id')::uuid
      left join public.categorias c on c.id=i.category_id),'[]'::jsonb));
$$;

create function public.list_known_recipes(p_limit integer default 500,p_offset integer default 0)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if p_limit is null or p_limit not between 1 and 500 or p_offset is null or p_offset not between 0 and 5000 then
    raise exception 'El límite o desplazamiento no es válido.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(public.recipe_read_payload(q) order by lower(q.title),q.id),'[]'::jsonb)
    into result from (
      select r.* from public.recetas r
      where (r.recipe_source='official' and r.owner_user_id is null and r.publication_status='published')
         or (r.recipe_source in ('user','ai') and r.owner_user_id=actor)
      order by lower(r.title),r.id offset p_offset limit p_limit
    ) q;
  return result;
end; $$;

-- UUID and legacy identifiers are separate named arguments. This keeps UUID
-- parsing deterministic while still supporting historical UUID-shaped keys.
create function public.get_my_recipe_detail(p_recipe_id uuid default null,p_legacy_id text default null,p_include_inactive boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; found_recipe public.recetas;
begin
  actor := public.lock_my_relational_account();
  if p_include_inactive is null or (p_recipe_id is null) = (p_legacy_id is null)
    or p_legacy_id is not null and (length(trim(p_legacy_id))=0 or length(p_legacy_id)>500) then
    raise exception 'Indicá un único identificador de receta válido.' using errcode='22023';
  end if;
  select r.* into found_recipe from public.recetas r
   where (p_recipe_id is not null and r.id=p_recipe_id)
      or (p_legacy_id is not null and r.legacy_id=p_legacy_id);
  if not found then return null; end if;
  if not ((found_recipe.recipe_source='official' and found_recipe.owner_user_id is null and found_recipe.publication_status='published')
       or (found_recipe.recipe_source in ('user','ai') and found_recipe.owner_user_id=actor)) then return null; end if;
  if not p_include_inactive and (not found_recipe.active or found_recipe.is_deleted) then return null; end if;
  return jsonb_build_object('recipe',public.recipe_read_payload(found_recipe),
    'stock',null,'percentage',null,'label','Disponibilidad no calculable');
end; $$;

-- The editor can read official drafts/inactive records with their version.
-- ADMIN does not gain access to another user's private recipe through this API.
create function public.admin_get_recipe(p_recipe_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid; result jsonb;
begin
  actor := public.lock_my_relational_account();
  if not exists(select 1 from public.roles_usuario ur where ur.user_id=actor and ur.role='ADMIN') then
    raise exception 'Se requiere rol ADMIN.' using errcode='42501';
  end if;
  if p_recipe_id is null then raise exception 'El identificador de receta es obligatorio.' using errcode='22023'; end if;
  select public.admin_recipe_export(p_recipe_id) into result
   from public.recetas r where r.id=p_recipe_id and r.recipe_source='official' and r.owner_user_id is null;
  return result;
end; $$;

revoke all on function public.recipe_read_payload(public.recetas) from public,anon,authenticated;
revoke all on function public.list_known_recipes(integer,integer),
  public.get_my_recipe_detail(uuid,text,boolean),public.admin_get_recipe(uuid) from public,anon;
grant execute on function public.list_known_recipes(integer,integer),
  public.get_my_recipe_detail(uuid,text,boolean),public.admin_get_recipe(uuid) to authenticated;
commit;
