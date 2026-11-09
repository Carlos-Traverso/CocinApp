-- READ ONLY: classify legacy references against the shipped recipe seed.
-- Returns aggregate counts only. Remote recipes override seed recipes by ID.
with seed_ids(id) as (values
    ('quinoa-bowl'),
    ('pumpkin-pasta'),
    ('chickpea-salad'),
    ('chicken-rice'),
    ('yogurt-fruit'),
    ('apple-toast'),
    ('vegetable-omelette'),
    ('lentil-stew'),
    ('avocado-toast'),
    ('banana-pancakes'),
    ('scrambled-eggs-toast'),
    ('overnight-oats'),
    ('caprese-sandwich'),
    ('tuna-rice-salad'),
    ('vegetable-wrap'),
    ('tomato-risotto'),
    ('baked-fish-potatoes'),
    ('spinach-pie'),
    ('pear-yogurt-cup'),
    ('cheese-scones'),
    ('banana-smoothie'),
    ('roasted-vegetable-soup')
), remote_ids as (
  select item ->> 'id' as id from public.shared_recipes
  cross join lateral jsonb_array_elements(case when jsonb_typeof(recipes)='array' then recipes else '[]'::jsonb end) item
  where catalog_key='main'
), refs as (
  select data_key, case when data_key='favorites' then item #>> '{}' else item ->> 'recipeId' end as id
  from public.personal_data
  cross join lateral jsonb_array_elements(case when jsonb_typeof(value)='array' then value else '[]'::jsonb end) item
  where data_key in ('favorites','meal_plan','cooking_history','cooking_progress')
)
select data_key,
  count(*) filter(where exists(select 1 from remote_ids r where r.id=refs.id)) as remote_references,
  count(*) filter(where not exists(select 1 from remote_ids r where r.id=refs.id)
    and exists(select 1 from seed_ids s where s.id=refs.id)) as seed_only_references,
  count(*) filter(where not exists(select 1 from remote_ids r where r.id=refs.id)
    and not exists(select 1 from seed_ids s where s.id=refs.id)) as unresolved_references
from refs group by data_key order by data_key;
