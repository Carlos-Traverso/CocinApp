begin;

-- Keep version checks and transaction locks, but return 55P03 on prolonged contention.
-- Scope the setting to these functions so unrelated database work keeps its own limits.
alter function public.lock_my_relational_account() set lock_timeout = '3s';
alter function public.save_my_profile(jsonb, text[], bigint) set lock_timeout = '3s';
alter function public.save_my_meal_plan(date, jsonb, bigint) set lock_timeout = '3s';
alter function public.put_my_pantry_item(jsonb, bigint) set lock_timeout = '3s';
alter function public.put_my_pantry_items(jsonb) set lock_timeout = '3s';
alter function public.delete_my_pantry_item(uuid, bigint) set lock_timeout = '3s';
alter function public.create_my_shopping_list(uuid, text, uuid) set lock_timeout = '3s';
alter function public.put_my_shopping_item(uuid, jsonb, bigint) set lock_timeout = '3s';
alter function public.remove_my_shopping_item(uuid, uuid, bigint) set lock_timeout = '3s';
alter function public.set_my_shopping_checked(uuid, uuid[], boolean, bigint) set lock_timeout = '3s';
alter function public.transfer_my_shopping_to_pantry(uuid, uuid[], uuid, bigint) set lock_timeout = '3s';
alter function public.transfer_my_legacy_shopping_to_pantry(jsonb, jsonb) set lock_timeout = '3s';
alter function public.start_my_cooking_session(uuid, uuid, integer) set lock_timeout = '3s';
alter function public.update_my_cooking_session(uuid, bigint, text, integer, integer) set lock_timeout = '3s';
alter function public.finish_my_cooking_session(uuid, bigint, boolean) set lock_timeout = '3s';
alter function public.admin_save_catalog_core(integer, jsonb) set lock_timeout = '3s';
alter function public.admin_save_shared_recipes(integer, jsonb) set lock_timeout = '3s';
alter function public.admin_put_catalog_entity(text, jsonb, bigint) set lock_timeout = '3s';
alter function public.admin_save_recipe(uuid, jsonb, bigint) set lock_timeout = '3s';
alter function public.admin_duplicate_recipe(uuid, uuid, bigint) set lock_timeout = '3s';
alter function public.admin_set_recipe_flags(uuid, bigint, boolean, boolean, boolean, boolean) set lock_timeout = '3s';
alter function public.admin_put_dietary_tag(jsonb, bigint) set lock_timeout = '3s';
alter function public.admin_save_ingredient_dietary_tags(uuid, jsonb, bigint) set lock_timeout = '3s';
alter function public.admin_publish_nutrition_config(jsonb, integer) set lock_timeout = '3s';

commit;
