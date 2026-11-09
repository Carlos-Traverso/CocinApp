-- REHEARSAL ONLY. Requires 202610300002 in a TEST copy, not the live project.
-- The final ROLLBACK preserves both legacy and relational destinations.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
lock table public.catalog_core, public.shared_recipes in share mode;
-- Private staging objects belong to this transaction and disappear on ROLLBACK.
create schema cocinapp_rehearsal;
revoke all on schema cocinapp_rehearsal from public, anon, authenticated;
create function cocinapp_rehearsal.norm(t text) returns text language sql immutable
as $$ select lower(translate(regexp_replace(trim(t), '\s+', ' ', 'g'), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) $$;
create function cocinapp_rehearsal.key_id(kind text, old_id text) returns uuid language sql immutable
as $$ select md5('cocinapp-v1|' || kind || '|' || old_id)::uuid $$;
do $$ begin
  if exists(select 1 from public.categories) or exists(select 1 from public.units)
    or exists(select 1 from public.ingredients) or exists(select 1 from public.recipes)
    or exists(select 1 from public.dietary_tags) then
    raise exception 'El ensayo requiere destinos relacionales vacíos. No sobrescribe datos nuevos.';
  end if;
  if (select count(*) from public.catalog_core where catalog_key='main') <> 1
    or (select count(*) from public.shared_recipes where catalog_key='main') <> 1 then
    raise exception 'Faltan los catálogos fuente main.';
  end if;
end $$;
create table cocinapp_rehearsal.src_core as select payload from public.catalog_core where catalog_key='main';
create table cocinapp_rehearsal.src_recipes(legacy_id text primary key, body jsonb not null, origin text not null);
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'seed'
from jsonb_array_elements($seed$SEED_JSON_PAYLOAD$seed$::jsonb) x;
-- Remote objects override seed objects exactly as mergeRecipeSeed does.
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'remote'
from public.shared_recipes r cross join lateral jsonb_array_elements(r.recipes) x where catalog_key='main'
on conflict(legacy_id) do update set body=excluded.body, origin=excluded.origin;

insert into public.categories(id,legacy_id,name,normalized_name,active,is_deleted)
select cocinapp_rehearsal.key_id('category',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'categories') x;
-- Roots first, then derived units; the trigger requires a root of the same dimension.
insert into public.units(id,legacy_id,name,abbreviation,dimension,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is null;
insert into public.units(id,legacy_id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),(x->>'equivalenceMultiplier')::numeric,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is not null;
insert into public.ingredients(id,legacy_id,name,normalized_name,category_id,base_unit_id,active,is_deleted)
select cocinapp_rehearsal.key_id('ingredient',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  cocinapp_rehearsal.key_id('category',x->>'categoryId'),cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'ingredients') x;

create table cocinapp_rehearsal.src_ingredients as
select r.legacy_id, n::integer as position, x,
  case when r.origin='remote' then (select id from public.ingredients where legacy_id=x->>'ingredientId')
    else (select id from public.ingredients where normalized_name=cocinapp_rehearsal.norm(x->>'name')) end as ingredient_id,
  case when r.origin='remote' then (select id from public.units where legacy_id=x->>'unitId')
    else (select id from public.units where abbreviation=x->>'unit') end as unit_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'ingredients') with ordinality a(x,n);
-- This public-catalog report identifies mappings requiring review; never invent them.
select legacy_id as recipe_legacy_id, x->>'name' as seed_ingredient_name,
  case when ingredient_id is null then 'missing ingredient' else 'missing unit' end as blocker
from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null;
do $$ begin
  if exists(select 1 from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null) then
    raise exception 'Hay ingredientes o unidades sin asociación. Revisar el reporte; el ensayo se revierte.';
  end if;
end $$;

insert into public.recipes(id,legacy_id,recipe_source,title,author,description,category_label,total_minutes,
  preparation_minutes,cooking_minutes,portions,difficulty,calories_per_portion,publication_status,
  active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt,created_at,updated_at)
select cocinapp_rehearsal.key_id('recipe',legacy_id),legacy_id,'official',coalesce(body->>'title',body->>'name'),
  coalesce(body->>'author','CocinAPP'),coalesce(body->>'description',''),coalesce(body->>'category',''),
  (body->>'minutes')::integer,(body->>'preparationMinutes')::integer,(body->>'cookingMinutes')::integer,
  (body->>'portions')::integer,
  case body->>'difficulty' when 'Fácil' then 'easy' when 'Intermedia' then 'intermediate' when 'Avanzada' then 'advanced' else body->>'difficulty' end,
  (body->>'calories')::numeric,coalesce(body->>'status','published'),coalesce((body->>'active')::boolean,true),
  coalesce((body->>'isDeleted')::boolean,false),coalesce((body->>'featured')::boolean,false),
  coalesce(body->>'symbol',''),coalesce(body->>'color','green'),body->>'crossContaminationNote',body->>'image',body->>'imageAlt',
  coalesce((body->>'createdAt')::timestamptz,transaction_timestamp()),coalesce((body->>'updatedAt')::timestamptz,transaction_timestamp())
from cocinapp_rehearsal.src_recipes;
insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,note,position)
select cocinapp_rehearsal.key_id('recipe-ingredient',legacy_id||':'||position),cocinapp_rehearsal.key_id('recipe',legacy_id),
  ingredient_id,(x->>'quantity')::numeric,unit_id,coalesce(x->>'note',''),position from cocinapp_rehearsal.src_ingredients;
insert into public.recipe_steps(id,recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
select cocinapp_rehearsal.key_id('recipe-step',legacy_id||':'||n),cocinapp_rehearsal.key_id('recipe',legacy_id),n::integer,x #>> '{}',
  coalesce((m->>'durationMinutes')::integer,(m->>'minutes')::integer),m->>'temperature',m->>'tip',m->>'warning',
  coalesce(array(select jsonb_array_elements_text(m->'utensils')),'{}'),m->>'specialInstructions'
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements(body->'steps') with ordinality a(x,n)
cross join lateral (select body->'stepMeta'->(n::integer-1) as m) metadata;
insert into public.recipe_meal_shifts(recipe_id,meal_shift)
select distinct cocinapp_rehearsal.key_id('recipe',legacy_id),case x when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch' when 'Merienda' then 'snack' when 'Cena' then 'dinner' else x end
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(coalesce(body->'mealShifts',jsonb_build_array(coalesce(body->>'mealShift',body->>'category')))) x;

insert into public.dietary_tags(tag_key,label) values
 ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos');
create table cocinapp_rehearsal.src_tags as
select legacy_id,x as label,case cocinapp_rehearsal.norm(x) when 'sin tacc' then 'gluten-free'
 when 'vegetariana' then 'vegetarian' when 'vegetariano' then 'vegetarian'
 when 'vegana' then 'vegan' when 'vegano' then 'vegan' when 'sin lactosa' then 'lactose-free'
 when 'sin frutos secos' then 'nut-free' else 'label-'||md5(x) end as tag_key
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(body->'dietaryTags') x;
insert into public.dietary_tags(tag_key,label) select distinct tag_key,label from cocinapp_rehearsal.src_tags
on conflict(tag_key) do nothing;
insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id)
select distinct cocinapp_rehearsal.key_id('recipe',s.legacy_id),t.id from cocinapp_rehearsal.src_tags s join public.dietary_tags t using(tag_key);

-- Link per-step metadata to ingredients without dropping unresolvable links.
create table cocinapp_rehearsal.src_step_links as
select r.legacy_id, n::integer as step_position, value as old_ingredient_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements_text(m->'ingredientIds') value;
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_step_links s where not exists(select 1 from cocinapp_rehearsal.src_ingredients i
   join public.ingredients g on g.id=i.ingredient_id where i.legacy_id=s.legacy_id and g.legacy_id=s.old_ingredient_id)) then
   raise exception 'Metadatos de pasos con ingredientes sin resolver.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id)
select distinct cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),
 cocinapp_rehearsal.key_id('recipe-ingredient',i.legacy_id||':'||i.position)
from cocinapp_rehearsal.src_step_links s join cocinapp_rehearsal.src_ingredients i on i.legacy_id=s.legacy_id
join public.ingredients g on g.id=i.ingredient_id and g.legacy_id=s.old_ingredient_id;

-- Seed step metadata uses named ingredients rather than legacy ingredient IDs.
create table cocinapp_rehearsal.src_seed_steps as
select r.legacy_id,n::integer as step_position,item
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements(m->'stepIngredients') item where origin='seed';
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_seed_steps s where (select count(*) from public.recipe_ingredients ri
   join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id
   where ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
   and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name') and u.abbreviation=s.item->>'unit') <> 1) then
   raise exception 'Ingredientes por paso del catálogo incluido sin asociación inequívoca.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override)
select cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),ri.id,(s.item->>'quantity')::numeric
from cocinapp_rehearsal.src_seed_steps s join public.recipe_ingredients ri on ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
join public.ingredients i on i.id=ri.ingredient_id and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name')
join public.units u on u.id=ri.unit_id and u.abbreviation=s.item->>'unit';


-- Explicit staging RLS avoids SQL Editor appending ALTERs after ROLLBACK.
alter table cocinapp_rehearsal.src_core enable row level security;
alter table cocinapp_rehearsal.src_recipes enable row level security;
alter table cocinapp_rehearsal.src_ingredients enable row level security;
alter table cocinapp_rehearsal.src_tags enable row level security;
alter table cocinapp_rehearsal.src_step_links enable row level security;
alter table cocinapp_rehearsal.src_seed_steps enable row level security;

select 'categories' as dataset,count(*) as converted from public.categories
union all select 'units',count(*) from public.units
union all select 'ingredients',count(*) from public.ingredients
union all select 'recipes',count(*) from public.recipes
union all select 'recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'recipe_steps',count(*) from public.recipe_steps;
rollback;
