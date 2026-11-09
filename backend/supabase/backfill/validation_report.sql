-- One result table: SQL Editor shows only the last non-empty result set.
select 'catalog' as section, 'categories' as dataset, count(*) as total from public.categories
union all select 'catalog','units',count(*) from public.units
union all select 'catalog','ingredients',count(*) from public.ingredients
union all select 'catalog','recipes',count(*) from public.recipes
union all select 'catalog','recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'catalog','recipe_steps',count(*) from public.recipe_steps
union all select 'personal','profiles',count(*) from public.profiles
union all select 'personal','preferences',count(*) from public.user_dietary_preferences
union all select 'personal','favorites',count(*) from public.favorite_recipes
union all select 'personal','plan_slots',count(*) from public.meal_plan_slots
union all select 'personal','cooking_history',count(*) from public.cooking_events
union all select 'personal','empty_active_shopping_lists',count(*) from public.shopping_lists
union all select 'security','domain_tables_with_rls',count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity and c.relname in ('dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests')
union all select 'pantry','rows',count(*) from public.pantry_items
union all select 'pantry','ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'pantry','unmatched_explicit_id',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is not null
union all select 'pantry','unmatched_name',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is null
union all select 'pantry','unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'pantry','dimension_mismatch',count(*) from public.pantry_items p join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
