-- READ ONLY. Run the whole query in Supabase SQL Editor before any backfill.
-- Reports structure/counts only: no names, emails, health values, tokens or IDs.
with personal as (
  select 'personal_data.' || data_key as dataset,
    jsonb_typeof(value) as value_type, value
  from public.personal_data
), documents as (
  select dataset, value_type, value from personal
  union all select 'catalog_core.payload', jsonb_typeof(payload), payload from public.catalog_core
  union all select 'shared_recipes.recipes', jsonb_typeof(recipes), recipes from public.shared_recipes
), elements as (
  select dataset, element
  from documents d
  cross join lateral jsonb_array_elements(case when value_type = 'array' then value else '[]'::jsonb end) element
), fields as (
  select dataset, key as field_name, jsonb_typeof(field_value) as field_type
  from documents d
  cross join lateral jsonb_each(case when value_type = 'object' then value else '{}'::jsonb end) kv(key, field_value)
  union all
  select dataset, key, jsonb_typeof(field_value)
  from elements e
  cross join lateral jsonb_each(case when jsonb_typeof(element) = 'object' then element else '{}'::jsonb end) kv(key, field_value)
)
select 'documents' as section, dataset, value_type as detail, count(*) as total
from documents group by dataset, value_type
union all
select 'array_elements', dataset, jsonb_typeof(element), count(*)
from elements group by dataset, jsonb_typeof(element)
union all
select 'fields', dataset, field_name || ' (' || field_type || ')', count(*)
from fields group by dataset, field_name, field_type
union all
select 'pantry', 'pantry_items', 'rows', count(*) from public.pantry_items
union all
select 'pantry', 'pantry_items', 'with_legacy_ingredient_id', count(*)
from public.pantry_items where ingredient_id is not null
order by section, dataset, detail;
