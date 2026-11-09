-- READ ONLY: public catalog structure and aggregate reference counts.
-- No profile values, user identifiers, or private recipe identifiers are returned.
with core as (
  select payload from public.catalog_core where catalog_key = 'main'
), catalog_arrays as (
  select key as dataset, case when jsonb_typeof(value) = 'array' then value else '[]'::jsonb end as entries
  from core cross join lateral jsonb_each(payload)
  where key in ('categories','units','ingredients')
), catalog as (
  select dataset, entry from catalog_arrays cross join lateral jsonb_array_elements(entries) entry
), recipes as (
  select entry from public.shared_recipes r
  cross join lateral jsonb_array_elements(case when jsonb_typeof(r.recipes) = 'array' then r.recipes else '[]'::jsonb end) entry
  where catalog_key = 'main'
), recipe_ingredients as (
  select entry ->> 'id' as recipe_id, item from recipes
  cross join lateral jsonb_array_elements(case when jsonb_typeof(entry -> 'ingredients') = 'array' then entry -> 'ingredients' else '[]'::jsonb end) item
), private_refs as (
  select data_key, case when data_key = 'favorites' then item #>> '{}' else item ->> 'recipeId' end as recipe_id
  from public.personal_data
  cross join lateral jsonb_array_elements(case when jsonb_typeof(value) = 'array' then value else '[]'::jsonb end) item
  where data_key in ('favorites','meal_plan','cooking_history','cooking_progress')
), nested_objects as (
  select dataset, entry from catalog
  union all select 'recipe_ingredients', item from recipe_ingredients
  union all
  select 'recipe_step_metadata', item from recipes
  cross join lateral jsonb_array_elements(case when jsonb_typeof(entry -> 'stepMeta') = 'array' then entry -> 'stepMeta' else '[]'::jsonb end) item
)
select 'catalog_count' as section, dataset, 'rows' as detail, count(*) as total from catalog group by dataset
union all
select 'catalog_check', dataset, 'duplicate_or_missing_ids', count(*) - count(distinct nullif(entry ->> 'id',''))
from catalog group by dataset
union all
select 'references', data_key, 'not_in_shared_recipes', count(*) from private_refs p
where not exists(select 1 from recipes r where r.entry ->> 'id' = p.recipe_id)
group by data_key
union all
select 'references', 'catalog.ingredients', 'missing_category', count(*) from catalog i
where i.dataset = 'ingredients' and not exists(select 1 from catalog c where c.dataset = 'categories' and c.entry ->> 'id' = i.entry ->> 'categoryId')
union all
select 'references', 'catalog.ingredients', 'missing_base_unit', count(*) from catalog i
where i.dataset = 'ingredients' and not exists(select 1 from catalog u where u.dataset = 'units' and u.entry ->> 'id' = i.entry ->> 'baseUnitId')
union all
select 'references', 'recipe_ingredients', 'missing_catalog_ingredient', count(*) from recipe_ingredients i
where not exists(select 1 from catalog c where c.dataset = 'ingredients' and c.entry ->> 'id' = i.item ->> 'ingredientId')
union all
select 'references', 'recipe_ingredients', 'missing_catalog_unit', count(*) from recipe_ingredients i
where not exists(select 1 from catalog c where c.dataset = 'units' and c.entry ->> 'id' = i.item ->> 'unitId')
union all
select 'nested_field', dataset, key || ' (' || jsonb_typeof(value) || ')', count(*)
from nested_objects
cross join lateral jsonb_each(case when jsonb_typeof(entry) = 'object' then entry else '{}'::jsonb end)
group by dataset, key, jsonb_typeof(value)
order by section, dataset, detail;
