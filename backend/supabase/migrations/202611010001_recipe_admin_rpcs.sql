begin;

-- Relational official recipes get optimistic versions. The default preserves
-- old importers and backfills that do not know about versions.
alter table public.recipes add column version bigint not null default 1 check (version > 0);

-- Open cooking sessions pin the recipe version at insert. The existing start
-- RPC already holds a FOR SHARE lock on the recipe parent, so this value is
-- consistent with its immutable snapshot; old closed sessions stay untouched.
create or replace function public.pin_open_cooking_recipe_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.finished_at is null and new.recipe_id is not null then
    select r.version::integer into new.recipe_version from public.recipes r where r.id=new.recipe_id;
  end if;
  return new;
end;
$$;
revoke all on function public.pin_open_cooking_recipe_version() from public, anon, authenticated;
create trigger pin_open_cooking_recipe_version_before_insert
before insert on public.cooking_sessions
for each row execute function public.pin_open_cooking_recipe_version();

create table public.admin_recipe_write_state (
  recipe_id uuid primary key references public.recipes(id) on delete cascade,
  create_payload jsonb check (create_payload is null or jsonb_typeof(create_payload) = 'object'),
  last_payload jsonb check (last_payload is null or jsonb_typeof(last_payload) = 'object'),
  last_version bigint,
  duplicate_source_id uuid,
  duplicate_source_version bigint
);
alter table public.admin_recipe_write_state enable row level security;
revoke all on public.admin_recipe_write_state from public, anon, authenticated;

alter table public.admin_audit_log drop constraint if exists admin_audit_log_action_check;
alter table public.admin_audit_log add constraint admin_audit_log_action_check check (action in (
  'user.created','user.name_updated','user.role_changed','user.activated','user.deactivated',
  'catalog.core_saved','catalog.recipes_saved','catalog.category_saved','catalog.unit_saved','catalog.ingredient_saved',
  'catalog.recipe_saved','catalog.recipe_duplicated','catalog.recipe_flags_changed'
));

create or replace function public.admin_save_recipe(p_recipe_id uuid, p_recipe jsonb, p_expected_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_old public.recipes; v_out jsonb; v_new_version bigint;
  v_title text; v_author text; v_description text; v_category text; v_minutes integer;
  v_preparation integer; v_cooking integer; v_portions integer; v_difficulty text; v_calories numeric;
  v_status text; v_active boolean; v_featured boolean; v_symbol text; v_color text;
  v_cross_note text; v_image text; v_image_alt text;
  v_ingredient jsonb; v_step jsonb; v_ref jsonb; v_i integer; v_j integer;
  v_ing_id uuid; v_unit_id uuid; v_step_id uuid; v_ing_row_id uuid; v_tag_id uuid;
  v_qty numeric; v_override numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539, 1);
  if v_actor is null or not public.current_account_is_active() or public.current_app_role() <> 'ADMIN' then
    raise exception 'Solo un administrador activo puede modificar recetas.' using errcode='42501';
  end if;
  perform public.lock_my_relational_account();
  if p_recipe_id is null or p_expected_version is null or p_expected_version < 0 or jsonb_typeof(p_recipe) is distinct from 'object' then
    raise exception 'La solicitud de receta no es válida.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_recipe) k where k not in
    ('title','author','description','category_label','meal_shifts','total_minutes','preparation_minutes','cooking_minutes','portions','difficulty','calories_per_portion','dietary_tags','featured','symbol','color','cross_contamination_note','image_path','image_alt','publication_status','active','ingredients','steps')) then
    raise exception 'La receta contiene campos no permitidos.' using errcode='22023';
  end if;
  if jsonb_typeof(p_recipe->'title') is distinct from 'string' or jsonb_typeof(p_recipe->'author') is distinct from 'string'
    or jsonb_typeof(p_recipe->'description') is distinct from 'string' or jsonb_typeof(p_recipe->'category_label') is distinct from 'string'
    or jsonb_typeof(p_recipe->'total_minutes') is distinct from 'number' or jsonb_typeof(p_recipe->'portions') is distinct from 'number'
    or jsonb_typeof(p_recipe->'difficulty') is distinct from 'string' or jsonb_typeof(p_recipe->'publication_status') is distinct from 'string'
    or jsonb_typeof(p_recipe->'active') is distinct from 'boolean' or jsonb_typeof(p_recipe->'featured') is distinct from 'boolean'
    or jsonb_typeof(p_recipe->'meal_shifts') is distinct from 'array' or jsonb_typeof(p_recipe->'dietary_tags') is distinct from 'array'
    or jsonb_typeof(p_recipe->'ingredients') is distinct from 'array' or jsonb_typeof(p_recipe->'steps') is distinct from 'array' then
    raise exception 'Faltan datos requeridos o hay tipos inválidos.' using errcode='22023';
  end if;
  v_title := regexp_replace(trim(p_recipe->>'title'), '\s+', ' ', 'g');
  v_author := p_recipe->>'author'; v_description := p_recipe->>'description'; v_category := p_recipe->>'category_label';
  v_minutes := (p_recipe->>'total_minutes')::integer; v_portions := (p_recipe->>'portions')::integer;
  v_difficulty := p_recipe->>'difficulty'; v_status := p_recipe->>'publication_status'; v_active := (p_recipe->>'active')::boolean;
  v_featured := (p_recipe->>'featured')::boolean;
  if jsonb_typeof(p_recipe->'preparation_minutes') not in ('number','null') and p_recipe ? 'preparation_minutes' then raise exception 'Tiempo de preparación inválido.' using errcode='22023'; end if;
  if jsonb_typeof(p_recipe->'cooking_minutes') not in ('number','null') and p_recipe ? 'cooking_minutes' then raise exception 'Tiempo de cocción inválido.' using errcode='22023'; end if;
  if jsonb_typeof(p_recipe->'calories_per_portion') not in ('number','null') and p_recipe ? 'calories_per_portion' then raise exception 'Calorías inválidas.' using errcode='22023'; end if;
  if p_recipe ? 'symbol' and jsonb_typeof(p_recipe->'symbol') is distinct from 'string' or p_recipe ? 'color' and jsonb_typeof(p_recipe->'color') is distinct from 'string'
    or p_recipe ? 'image_path' and jsonb_typeof(p_recipe->'image_path') not in ('string','null') or p_recipe ? 'image_alt' and jsonb_typeof(p_recipe->'image_alt') not in ('string','null')
    or p_recipe ? 'cross_contamination_note' and jsonb_typeof(p_recipe->'cross_contamination_note') not in ('string','null') then raise exception 'Metadatos inválidos.' using errcode='22023'; end if;
  v_preparation := case when jsonb_typeof(p_recipe->'preparation_minutes')='number' then (p_recipe->>'preparation_minutes')::integer end;
  v_cooking := case when jsonb_typeof(p_recipe->'cooking_minutes')='number' then (p_recipe->>'cooking_minutes')::integer end;
  v_calories := case when jsonb_typeof(p_recipe->'calories_per_portion')='number' then (p_recipe->>'calories_per_portion')::numeric end;
  v_symbol := coalesce(p_recipe->>'symbol',''); v_color := coalesce(p_recipe->>'color','green');
  v_image := nullif(p_recipe->>'image_path',''); v_image_alt := nullif(p_recipe->>'image_alt','');
  v_cross_note := p_recipe->>'cross_contamination_note';
  if (p_recipe->>'total_minutes')::numeric<>trunc((p_recipe->>'total_minutes')::numeric)
    or (p_recipe->>'portions')::numeric<>trunc((p_recipe->>'portions')::numeric)
    or jsonb_typeof(p_recipe->'preparation_minutes')='number' and (p_recipe->>'preparation_minutes')::numeric<>trunc((p_recipe->>'preparation_minutes')::numeric)
    or jsonb_typeof(p_recipe->'cooking_minutes')='number' and (p_recipe->>'cooking_minutes')::numeric<>trunc((p_recipe->>'cooking_minutes')::numeric)
    or length(v_title) not between 1 and 180 or length(v_author)>180 or length(v_description)>10000 or length(v_category)>120 or length(v_symbol)>80
    or v_minutes not between 1 and 1440 or v_portions not between 1 and 100 or v_difficulty not in ('easy','intermediate','advanced')
    or v_status not in ('draft','published') or v_color not in ('green','gold','pink','blue') or v_calories < 0
    or v_preparation < 0 or v_cooking < 0 or cardinality(array(select jsonb_array_elements_text(p_recipe->'meal_shifts'))) not between 1 and 4
    or jsonb_array_length(p_recipe->'ingredients') not between 1 and 200 or jsonb_array_length(p_recipe->'steps') not between 1 and 100
    or (v_image is not null and v_image_alt is null) or length(v_image)>500 or length(v_image_alt)>500 or length(v_cross_note)>2000 then
    raise exception 'La receta tiene valores fuera de rango.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_recipe->'meal_shifts') x where jsonb_typeof(x) <> 'string' or x #>> '{}' not in ('breakfast','lunch','snack','dinner'))
    or exists(select 1 from (select value, count(*) over(partition by value) n from jsonb_array_elements_text(p_recipe->'meal_shifts') value) q where n>1) then
    raise exception 'Los turnos de comida no son válidos.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_recipe->'dietary_tags') x where jsonb_typeof(x) <> 'string' or length(x #>> '{}') not between 2 and 50) then
    raise exception 'Las etiquetas dietarias no son válidas.' using errcode='22023';
  end if;
  if exists(select 1 from (select value,count(*) over(partition by value) n from jsonb_array_elements_text(p_recipe->'dietary_tags') value) q where n>1) then
    raise exception 'Las etiquetas dietarias no pueden repetirse.' using errcode='22023';
  end if;
  if p_expected_version > 0 then
    select * into v_old from public.recipes r where r.id=p_recipe_id for update;
    if not found or v_old.recipe_source <> 'official' or v_old.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
    if v_old.version <> p_expected_version then raise exception 'La receta cambió; recargá los datos.' using errcode='40001'; end if;
    if exists(select 1 from public.admin_recipe_write_state q where q.recipe_id=p_recipe_id and q.last_version=v_old.version and q.last_payload=p_recipe) then
      return public.admin_recipe_export(p_recipe_id);
    end if;
  else
    perform 1 from public.recipes r where r.id=p_recipe_id for update;
    if found then
      if exists(select 1 from public.admin_recipe_write_state q where q.recipe_id=p_recipe_id and q.create_payload=p_recipe)
        and exists(select 1 from public.recipes r where r.id=p_recipe_id and r.recipe_source='official' and r.owner_user_id is null and r.version=1) then
        return public.admin_recipe_export(p_recipe_id);
      end if;
      raise exception 'La receta ya existe con otros datos.' using errcode='40001';
    end if;
  end if;
  if exists(select 1 from public.recipes r where r.id<>p_recipe_id and r.recipe_source='official' and r.owner_user_id is null and not r.is_deleted
    and lower(regexp_replace(regexp_replace(normalize(trim(r.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
      =lower(regexp_replace(regexp_replace(normalize(trim(v_title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))) then
    raise exception 'Ya existe una receta con ese título.' using errcode='23505';
  end if;
  -- All catalog references are checked before mutating the parent/children.
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'ingredients') loop
    if jsonb_typeof(v_ingredient) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_ingredient) k where k not in ('ingredient_id','quantity','unit_id','note'))
      or jsonb_typeof(v_ingredient->'ingredient_id') is distinct from 'string' or jsonb_typeof(v_ingredient->'unit_id') is distinct from 'string'
      or jsonb_typeof(v_ingredient->'quantity') is distinct from 'number' or v_ingredient ? 'note' and jsonb_typeof(v_ingredient->'note') is distinct from 'string' then raise exception 'Ingrediente de receta inválido.' using errcode='22023'; end if;
    v_ing_id := (v_ingredient->>'ingredient_id')::uuid; v_unit_id := (v_ingredient->>'unit_id')::uuid; v_qty := (v_ingredient->>'quantity')::numeric;
    if v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,4) or length(coalesce(v_ingredient->>'note',''))>500
      or not exists(select 1 from public.ingredients i join public.units base on base.id=i.base_unit_id join public.units useu on useu.id=v_unit_id join public.categories c on c.id=i.category_id
        where i.id=v_ing_id and not i.is_deleted and not base.is_deleted and not useu.is_deleted
        and base.dimension=useu.dimension and coalesce(useu.base_unit_id,useu.id)=base.id
        and ((i.active and base.active and useu.active and c.active and not c.is_deleted) or (p_expected_version>0 and exists(
          select 1 from public.recipe_ingredients oldri where oldri.recipe_id=p_recipe_id and oldri.ingredient_id=i.id and oldri.unit_id=useu.id)))) then
      raise exception 'Ingrediente o unidad incompatible/inactiva.' using errcode='22023';
    end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_recipe->'dietary_tags') tag where not exists(select 1 from public.dietary_tags t where t.tag_key=tag #>> '{}' and t.active)) then raise exception 'Etiqueta dietaria inactiva o inexistente.' using errcode='22023'; end if;
  if p_expected_version=0 then
    insert into public.recipes(id,owner_user_id,recipe_source,title,author,description,category_label,total_minutes,preparation_minutes,cooking_minutes,portions,difficulty,calories_per_portion,publication_status,active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt)
    values(p_recipe_id,null,'official',v_title,v_author,v_description,v_category,v_minutes,v_preparation,v_cooking,v_portions,v_difficulty,v_calories,v_status,v_active,false,v_featured,v_symbol,v_color,v_cross_note,v_image,v_image_alt);
    insert into public.admin_recipe_write_state(recipe_id,create_payload,last_payload,last_version) values(p_recipe_id,p_recipe,p_recipe,1);
  else
    update public.recipes set title=v_title,author=v_author,description=v_description,category_label=v_category,total_minutes=v_minutes,preparation_minutes=v_preparation,cooking_minutes=v_cooking,portions=v_portions,difficulty=v_difficulty,calories_per_portion=v_calories,publication_status=v_status,active=case when v_old.is_deleted then false else v_active end,featured=v_featured,symbol=v_symbol,color=v_color,cross_contamination_note=v_cross_note,image_path=v_image,image_alt=v_image_alt,updated_at=clock_timestamp(),version=version+1 where id=p_recipe_id returning version into v_new_version;
    insert into public.admin_recipe_write_state(recipe_id,last_payload,last_version) values(p_recipe_id,p_recipe,v_new_version)
      on conflict(recipe_id) do update set last_payload=excluded.last_payload,last_version=excluded.last_version;
  end if;
  delete from public.recipe_meal_shifts where recipe_id=p_recipe_id;
  delete from public.recipe_dietary_tags where recipe_id=p_recipe_id;
  delete from public.recipe_ingredients where recipe_id=p_recipe_id;
  delete from public.recipe_steps where recipe_id=p_recipe_id;
  for v_i in 1..jsonb_array_length(p_recipe->'meal_shifts') loop
    insert into public.recipe_meal_shifts(recipe_id,meal_shift) values(p_recipe_id,p_recipe->'meal_shifts'->>(v_i-1));
  end loop;
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'dietary_tags') loop
    select id into v_tag_id from public.dietary_tags where tag_key=v_ingredient #>> '{}';
    insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id) values(p_recipe_id,v_tag_id);
  end loop;
  v_i:=0;
  for v_ingredient in select value from jsonb_array_elements(p_recipe->'ingredients') loop
    v_i:=v_i+1;
    insert into public.recipe_ingredients(recipe_id,ingredient_id,quantity,unit_id,note,position)
    values(p_recipe_id,(v_ingredient->>'ingredient_id')::uuid,(v_ingredient->>'quantity')::numeric,(v_ingredient->>'unit_id')::uuid,coalesce(v_ingredient->>'note',''),v_i);
  end loop;
  v_i:=0;
  for v_step in select value from jsonb_array_elements(p_recipe->'steps') loop
    v_i:=v_i+1;
    if jsonb_typeof(v_step) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_step) k where k not in ('instruction','duration_minutes','temperature','tip','warning','utensils','special_instructions','ingredients'))
      or jsonb_typeof(v_step->'instruction') is distinct from 'string' or length(trim(v_step->>'instruction')) not between 1 and 5000
      or v_step ? 'duration_minutes' and jsonb_typeof(v_step->'duration_minutes') not in ('number','null')
      or v_step ? 'utensils' and jsonb_typeof(v_step->'utensils') is distinct from 'array'
      or v_step ? 'ingredients' and jsonb_typeof(v_step->'ingredients') is distinct from 'array' then raise exception 'Paso de receta inválido.' using errcode='22023'; end if;
    if v_step ? 'duration_minutes' and v_step->>'duration_minutes' is not null and (((v_step->>'duration_minutes')::numeric<>trunc((v_step->>'duration_minutes')::numeric) or (v_step->>'duration_minutes')::integer not between 0 and 1440)) then raise exception 'Duración de paso inválida.' using errcode='22023'; end if;
    if (v_step ? 'temperature' and jsonb_typeof(v_step->'temperature') not in ('string','null'))
      or (v_step ? 'tip' and jsonb_typeof(v_step->'tip') not in ('string','null'))
      or (v_step ? 'warning' and jsonb_typeof(v_step->'warning') not in ('string','null'))
      or (v_step ? 'special_instructions' and jsonb_typeof(v_step->'special_instructions') not in ('string','null'))
      or length(coalesce(v_step->>'temperature',''))>80 or length(coalesce(v_step->>'tip',''))>240
      or length(coalesce(v_step->>'warning',''))>240 or length(coalesce(v_step->>'special_instructions',''))>400
      or (v_step ? 'utensils' and (jsonb_array_length(v_step->'utensils')>30 or exists(select 1 from jsonb_array_elements(v_step->'utensils') u where jsonb_typeof(u)<>'string' or length(u #>> '{}')>80))) then
      raise exception 'Los metadatos del paso están fuera de rango.' using errcode='22023';
    end if;
    insert into public.recipe_steps(recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
    values(p_recipe_id,v_i,v_step->>'instruction',nullif(v_step->>'duration_minutes','')::integer,nullif(v_step->>'temperature',''),nullif(v_step->>'tip',''),nullif(v_step->>'warning',''),coalesce(array(select jsonb_array_elements_text(coalesce(v_step->'utensils','[]'::jsonb))),'{}'),nullif(v_step->>'special_instructions','')) returning id into v_step_id;
    if jsonb_typeof(v_step->'ingredients')='array' then
      for v_ref in select value from jsonb_array_elements(v_step->'ingredients') loop
        if jsonb_typeof(v_ref) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_ref) k where k not in ('ingredient_position','quantity_override'))
          or jsonb_typeof(v_ref->'ingredient_position') is distinct from 'number' or v_ref ? 'quantity_override' and jsonb_typeof(v_ref->'quantity_override') not in ('number','null') then raise exception 'Referencia de ingrediente de paso inválida.' using errcode='22023'; end if;
        if (v_ref->>'ingredient_position')::numeric<>trunc((v_ref->>'ingredient_position')::numeric) then raise exception 'Posición de ingrediente inválida.' using errcode='22023'; end if;
        v_j:=(v_ref->>'ingredient_position')::integer;
        select id into v_ing_row_id from public.recipe_ingredients where recipe_id=p_recipe_id and position=v_j;
        if v_ing_row_id is null then raise exception 'Referencia de ingrediente inexistente.' using errcode='22023'; end if;
        v_override:=nullif(v_ref->>'quantity_override','')::numeric;
        if v_override is not null and (v_override<=0 or v_override>1000000 or v_override<>round(v_override,4)) then raise exception 'Cantidad de paso inválida.' using errcode='22023'; end if;
        insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override) values(v_step_id,v_ing_row_id,v_override);
      end loop;
    end if;
  end loop;
  insert into public.admin_audit_log(actor_user_id,action,details) values(v_actor,'catalog.recipe_saved',jsonb_build_object('entity_id',p_recipe_id,'version',case when p_expected_version=0 then 1 else v_new_version end));
  return public.admin_recipe_export(p_recipe_id);
exception when unique_violation then raise exception 'Ya existe una receta con ese título o identificador.' using errcode='23505';
when data_exception or check_violation or not_null_violation or foreign_key_violation then raise exception 'Los datos de la receta no son válidos.' using errcode='22023';
end;
$$;

create or replace function public.admin_recipe_export(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
select to_jsonb(r) || jsonb_build_object(
 'ingredients',coalesce((select jsonb_agg(jsonb_build_object('ingredient_id',i.ingredient_id,'quantity',i.quantity,'unit_id',i.unit_id,'note',i.note,'position',i.position) order by i.position) from public.recipe_ingredients i where i.recipe_id=r.id),'[]'::jsonb),
 'steps',coalesce((select jsonb_agg(jsonb_build_object('instruction',s.instruction,'duration_minutes',s.duration_minutes,'temperature',s.temperature,'tip',s.tip,'warning',s.warning,'utensils',s.utensils,'special_instructions',s.special_instructions,'ingredients',coalesce((select jsonb_agg(jsonb_build_object('ingredient_position',ri.position,'quantity_override',si.quantity_override) order by ri.position) from public.recipe_step_ingredients si join public.recipe_ingredients ri on ri.id=si.recipe_ingredient_id where si.step_id=s.id),'[]'::jsonb)) order by s.position) from public.recipe_steps s where s.recipe_id=r.id),'[]'::jsonb),
 'meal_shifts',coalesce((select jsonb_agg(ms.meal_shift order by ms.meal_shift) from public.recipe_meal_shifts ms where ms.recipe_id=r.id),'[]'::jsonb),
 'dietary_tags',coalesce((select jsonb_agg(t.tag_key order by t.tag_key) from public.recipe_dietary_tags dt join public.dietary_tags t on t.id=dt.dietary_tag_id where dt.recipe_id=r.id),'[]'::jsonb),
 'category_label',r.category_label,'total_minutes',r.total_minutes,'calories_per_portion',r.calories_per_portion,'publication_status',r.publication_status,'image_path',r.image_path,'image_alt',r.image_alt,'cross_contamination_note',r.cross_contamination_note)
from public.recipes r where r.id=p_id and r.recipe_source='official' and r.owner_user_id is null;
$$;

-- Duplicate target ids are idempotency keys; provenance persists independently
-- of source edits, so retry always resolves to the same draft.
create or replace function public.admin_duplicate_recipe(p_source_id uuid,p_target_id uuid,p_expected_version bigint default 0)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_source public.recipes; v_payload jsonb; v_result jsonb; v_copy_number integer:=1; v_copy_title text; v_copy_prefix text;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539,1);
  if auth.uid() is null or not public.current_account_is_active() or public.current_app_role()<>'ADMIN' then raise exception 'Solo un administrador activo puede duplicar recetas.' using errcode='42501'; end if;
  perform public.lock_my_relational_account();
  if p_source_id is null or p_target_id is null or p_source_id=p_target_id or p_expected_version is distinct from 0 then raise exception 'Solicitud de duplicación inválida.' using errcode='22023'; end if;
  select * into v_source from public.recipes where id=p_source_id for update;
  if not found or v_source.recipe_source<>'official' or v_source.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
  if exists(select 1 from public.admin_recipe_write_state d where d.recipe_id=p_target_id and d.duplicate_source_id is not null) then
    if exists(select 1 from public.admin_recipe_write_state d where d.recipe_id=p_target_id and d.duplicate_source_id=p_source_id) then return public.admin_recipe_export(p_target_id); end if;
    raise exception 'El identificador de duplicación ya fue usado.' using errcode='40001';
  end if;
  if exists(select 1 from public.recipes where id=p_target_id) then raise exception 'El identificador de duplicación ya fue usado.' using errcode='40001'; end if;
  v_payload:=public.admin_recipe_export(p_source_id);
  v_payload:=v_payload || jsonb_build_object('publication_status','draft','active',true,'featured',false);
  -- Reserve a unique title with the frontend's normalized copy sequence.
  loop
    v_copy_prefix:=case when v_copy_number=1 then 'Copia de ' else 'Copia '||v_copy_number::text||' de ' end;
    v_copy_title:=v_copy_prefix||left(v_source.title,180-char_length(v_copy_prefix));
    exit when not exists(select 1 from public.recipes r where r.recipe_source='official' and r.owner_user_id is null and not r.is_deleted
      and lower(regexp_replace(regexp_replace(trim(normalize(r.title,NFD)),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
        =lower(regexp_replace(regexp_replace(trim(normalize(v_copy_title,NFD)),U&'[\0300-\036f]','','g'),'\s+',' ','g')));
    v_copy_number:=v_copy_number+1;
  end loop;
  if v_copy_number>100000 then raise exception 'No se pudo reservar un título de copia.' using errcode='23505'; end if;
  v_payload:=jsonb_set(v_payload,'{title}',to_jsonb(v_copy_title));
  -- Convert exported DB names and row objects into the save RPC input shape.
  v_payload:=jsonb_build_object('title',v_payload->>'title','author',v_payload->>'author','description',v_payload->>'description','category_label',v_payload->>'category_label','meal_shifts',v_payload->'meal_shifts','total_minutes',v_payload->'total_minutes','preparation_minutes',v_payload->'preparation_minutes','cooking_minutes',v_payload->'cooking_minutes','portions',v_payload->'portions','difficulty',v_payload->'difficulty','calories_per_portion',v_payload->'calories_per_portion','dietary_tags',v_payload->'dietary_tags','featured',false,'symbol',v_payload->'symbol','color',v_payload->'color','cross_contamination_note',v_payload->'cross_contamination_note','image_path',v_payload->'image_path','image_alt',v_payload->'image_alt','publication_status','draft','active',true,
   'ingredients',(select jsonb_agg(jsonb_build_object('ingredient_id',x->'ingredient_id','quantity',x->'quantity','unit_id',x->'unit_id','note',x->'note') order by (x->>'position')::integer) from jsonb_array_elements(v_payload->'ingredients') x),
   'steps',(select jsonb_agg(jsonb_build_object('instruction',x->'instruction','duration_minutes',x->'duration_minutes','temperature',x->'temperature','tip',x->'tip','warning',x->'warning','utensils',x->'utensils','special_instructions',x->'special_instructions','ingredients',x->'ingredients') order by n) from jsonb_array_elements(v_payload->'steps') with ordinality q(x,n)));
  v_result:=public.admin_save_recipe(p_target_id,v_payload,0);
  update public.admin_recipe_write_state set duplicate_source_id=p_source_id,duplicate_source_version=v_source.version where recipe_id=p_target_id;
  update public.admin_audit_log e set action='catalog.recipe_duplicated'
    where e.id=(select e2.id from public.admin_audit_log e2 where e2.actor_user_id=auth.uid() and e2.action='catalog.recipe_saved'
      and e2.details->>'entity_id'=p_target_id::text and e2.occurred_at>=transaction_timestamp() order by e2.occurred_at desc,e2.id desc limit 1);
  return v_result;
end;
$$;

create or replace function public.admin_set_recipe_flags(p_recipe_id uuid,p_expected_version bigint,p_active boolean default null,p_featured boolean default null,p_archived boolean default null,p_restored boolean default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_row public.recipes; v_deleted boolean; v_desired_active boolean; v_desired_featured boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(74539,1);
  if auth.uid() is null or not public.current_account_is_active() or public.current_app_role()<>'ADMIN' then raise exception 'Solo un administrador activo puede cambiar recetas.' using errcode='42501'; end if;
  perform public.lock_my_relational_account();
  if p_recipe_id is null or p_expected_version is null or p_expected_version<=0
    or p_archived is true and p_restored is true or p_archived is false and p_restored is not true
    or p_active is true and (p_archived is true or p_restored is not true and p_archived is null) then
    raise exception 'Solicitud de estado inválida.' using errcode='22023';
  end if;
  select * into v_row from public.recipes where id=p_recipe_id for update;
  if not found or v_row.recipe_source<>'official' or v_row.owner_user_id is not null then raise exception 'La receta oficial no existe.' using errcode='42501'; end if;
  if v_row.version<>p_expected_version then raise exception 'La receta cambió; recargá los datos.' using errcode='40001'; end if;
  v_deleted:=case when p_restored is true then false when p_archived is true then true else v_row.is_deleted end;
  if v_row.is_deleted and not v_deleted and exists(select 1 from public.recipes other_recipe
    where other_recipe.id<>p_recipe_id and other_recipe.recipe_source='official' and other_recipe.owner_user_id is null and not other_recipe.is_deleted
      and lower(regexp_replace(regexp_replace(normalize(trim(other_recipe.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
        =lower(regexp_replace(regexp_replace(normalize(trim(v_row.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))) then
    raise exception 'Ya existe una receta con ese título.' using errcode='23505';
  end if;
  v_desired_active:=case when v_deleted then false when p_active is not null then p_active when p_restored is true then true else v_row.active end;
  v_desired_featured:=coalesce(p_featured,v_row.featured);
  if v_desired_active=v_row.active and v_desired_featured=v_row.featured and v_deleted=v_row.is_deleted then return public.admin_recipe_export(p_recipe_id); end if;
  update public.recipes set active=v_desired_active,featured=v_desired_featured,is_deleted=v_deleted,updated_at=clock_timestamp(),version=version+1 where id=p_recipe_id;
  insert into public.admin_audit_log(actor_user_id,action,details) values(auth.uid(),'catalog.recipe_flags_changed',jsonb_build_object('entity_id',p_recipe_id,'version',p_expected_version+1));
  return public.admin_recipe_export(p_recipe_id);
end;
$$;

revoke all on function public.admin_save_recipe(uuid,jsonb,bigint),public.admin_duplicate_recipe(uuid,uuid,bigint),public.admin_set_recipe_flags(uuid,bigint,boolean,boolean,boolean,boolean),public.admin_recipe_export(uuid) from public,anon,authenticated;
grant execute on function public.admin_save_recipe(uuid,jsonb,bigint),public.admin_duplicate_recipe(uuid,uuid,bigint),public.admin_set_recipe_flags(uuid,bigint,boolean,boolean,boolean,boolean) to authenticated;
commit;
