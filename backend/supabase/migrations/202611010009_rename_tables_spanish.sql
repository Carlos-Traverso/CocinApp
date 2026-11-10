begin;

-- Keep the original migrations immutable. This final cutover renames tables only;
-- columns, RPC names, enum values, JSON keys, and auth.users remain unchanged.
alter table public.pantry_items rename to articulos_despensa;
alter table public.personal_data rename to datos_personales;
alter table public.user_roles rename to roles_usuario;
alter table public.catalog_core rename to catalogo_base;
alter table public.shared_recipes rename to recetas_compartidas;
alter table public.account_status rename to estado_cuenta;
alter table public.admin_audit_log rename to registro_auditoria;

alter table public.dietary_tags rename to etiquetas_dieteticas;
alter table public.nutrition_config rename to configuracion_nutricional;
alter table public.profiles rename to perfiles;
alter table public.user_dietary_preferences rename to preferencias_dieteticas_usuario;
alter table public.categories rename to categorias;
alter table public.units rename to unidades;
alter table public.ingredients rename to ingredientes;
alter table public.ingredient_dietary_tags rename to etiquetas_dieteticas_ingrediente;
alter table public.recipes rename to recetas;
alter table public.recipe_meal_shifts rename to turnos_comida_receta;
alter table public.recipe_dietary_tags rename to etiquetas_dieteticas_receta;
alter table public.recipe_ingredients rename to ingredientes_receta;
alter table public.recipe_steps rename to pasos_receta;
alter table public.recipe_step_ingredients rename to ingredientes_paso_receta;
alter table public.favorite_recipes rename to recetas_favoritas;
alter table public.meal_plans rename to planes_comida;
alter table public.meal_plan_slots rename to turnos_plan_comida;
alter table public.pantry_receipts rename to comprobantes_despensa;
alter table public.shopping_lists rename to listas_compras;
alter table public.shopping_items rename to articulos_compra;
alter table public.shopping_item_sources rename to origenes_articulo_compra;
alter table public.pantry_receipt_items rename to articulos_comprobante_despensa;
alter table public.cooking_sessions rename to sesiones_cocina;
alter table public.cooking_session_steps rename to pasos_sesion_cocina;
alter table public.cooking_events rename to eventos_cocina;
alter table public.cooking_event_ingredients rename to ingredientes_evento_cocina;
alter table public.recipe_generation_requests rename to solicitudes_generacion_receta;
alter table public.receipt_recognition_requests rename to solicitudes_reconocimiento_ticket;
alter table public.admin_recipe_write_state rename to estado_escritura_receta_admin;

-- PL/pgSQL stores relation references as source text. Replace only qualified table
-- references and the two documented trigger-table-name dispatch lists. Function
-- names, argument names, JSON keys, and column names are intentionally untouched.
do $rename_function_bodies$
declare
  routine record;
  definition text;
begin
  for routine in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p')
      and p.prosrc is not null
  loop
    definition := pg_get_functiondef(routine.oid);
    definition := regexp_replace(definition, 'public\.pantry_items([^a-z0-9_]|$)', 'public.articulos_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.personal_data([^a-z0-9_]|$)', 'public.datos_personales\1', 'g');
    definition := regexp_replace(definition, 'public\.user_roles([^a-z0-9_]|$)', 'public.roles_usuario\1', 'g');
    definition := regexp_replace(definition, 'public\.catalog_core([^a-z0-9_]|$)', 'public.catalogo_base\1', 'g');
    definition := regexp_replace(definition, 'public\.shared_recipes([^a-z0-9_]|$)', 'public.recetas_compartidas\1', 'g');
    definition := regexp_replace(definition, 'public\.account_status([^a-z0-9_]|$)', 'public.estado_cuenta\1', 'g');
    definition := regexp_replace(definition, 'public\.admin_audit_log([^a-z0-9_]|$)', 'public.registro_auditoria\1', 'g');
    definition := regexp_replace(definition, 'public\.dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas\1', 'g');
    definition := regexp_replace(definition, 'public\.nutrition_config([^a-z0-9_]|$)', 'public.configuracion_nutricional\1', 'g');
    definition := regexp_replace(definition, 'public\.profiles([^a-z0-9_]|$)', 'public.perfiles\1', 'g');
    definition := regexp_replace(definition, 'public\.user_dietary_preferences([^a-z0-9_]|$)', 'public.preferencias_dieteticas_usuario\1', 'g');
    definition := regexp_replace(definition, 'public\.categories([^a-z0-9_]|$)', 'public.categorias\1', 'g');
    definition := regexp_replace(definition, 'public\.units([^a-z0-9_]|$)', 'public.unidades\1', 'g');
    definition := regexp_replace(definition, 'public\.ingredients([^a-z0-9_]|$)', 'public.ingredientes\1', 'g');
    definition := regexp_replace(definition, 'public\.ingredient_dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas_ingrediente\1', 'g');
    definition := regexp_replace(definition, 'public\.recipes([^a-z0-9_]|$)', 'public.recetas\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_meal_shifts([^a-z0-9_]|$)', 'public.turnos_comida_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_dietary_tags([^a-z0-9_]|$)', 'public.etiquetas_dieteticas_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_ingredients([^a-z0-9_]|$)', 'public.ingredientes_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_steps([^a-z0-9_]|$)', 'public.pasos_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_step_ingredients([^a-z0-9_]|$)', 'public.ingredientes_paso_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.favorite_recipes([^a-z0-9_]|$)', 'public.recetas_favoritas\1', 'g');
    definition := regexp_replace(definition, 'public\.meal_plans([^a-z0-9_]|$)', 'public.planes_comida\1', 'g');
    definition := regexp_replace(definition, 'public\.meal_plan_slots([^a-z0-9_]|$)', 'public.turnos_plan_comida\1', 'g');
    definition := regexp_replace(definition, 'public\.pantry_receipts([^a-z0-9_]|$)', 'public.comprobantes_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_lists([^a-z0-9_]|$)', 'public.listas_compras\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_items([^a-z0-9_]|$)', 'public.articulos_compra\1', 'g');
    definition := regexp_replace(definition, 'public\.shopping_item_sources([^a-z0-9_]|$)', 'public.origenes_articulo_compra\1', 'g');
    definition := regexp_replace(definition, 'public\.pantry_receipt_items([^a-z0-9_]|$)', 'public.articulos_comprobante_despensa\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_sessions([^a-z0-9_]|$)', 'public.sesiones_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_session_steps([^a-z0-9_]|$)', 'public.pasos_sesion_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_events([^a-z0-9_]|$)', 'public.eventos_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.cooking_event_ingredients([^a-z0-9_]|$)', 'public.ingredientes_evento_cocina\1', 'g');
    definition := regexp_replace(definition, 'public\.recipe_generation_requests([^a-z0-9_]|$)', 'public.solicitudes_generacion_receta\1', 'g');
    definition := regexp_replace(definition, 'public\.receipt_recognition_requests([^a-z0-9_]|$)', 'public.solicitudes_reconocimiento_ticket\1', 'g');
    definition := regexp_replace(definition, 'public\.admin_recipe_write_state([^a-z0-9_]|$)', 'public.estado_escritura_receta_admin\1', 'g');

    -- These table-qualified row references are used by ON CONFLICT and RETURNING.
    definition := replace(definition, 'profiles.version+1', 'perfiles.version+1');
    definition := replace(definition, 'meal_plans.version+1', 'planes_comida.version+1');
    definition := replace(definition, 'shopping_items.list_id=', 'articulos_compra.list_id=');
    definition := replace(definition, 'shopping_items.transferred_at', 'articulos_compra.transferred_at');
    definition := replace(definition, 'to_jsonb(categories.*)', 'to_jsonb(categorias.*)');
    definition := replace(definition, 'to_jsonb(units.*)', 'to_jsonb(unidades.*)');
    definition := replace(definition, 'to_jsonb(ingredients.*)', 'to_jsonb(ingredientes.*)');

    definition := replace(definition, 'tg_table_name = ''units''', 'tg_table_name = ''unidades''');
    definition := replace(definition, 'tg_table_name = ''recipe_ingredients''', 'tg_table_name = ''ingredientes_receta''');
    definition := replace(definition, 'tg_table_name = ''recipe_step_ingredients''', 'tg_table_name = ''ingredientes_paso_receta''');
    definition := replace(definition, 'tg_table_name = ''meal_plan_slots''', 'tg_table_name = ''turnos_plan_comida''');
    definition := replace(definition, 'tg_table_name = ''favorite_recipes''', 'tg_table_name = ''recetas_favoritas''');
    definition := replace(definition, 'tg_table_name = ''cooking_sessions''', 'tg_table_name = ''sesiones_cocina''');
    definition := replace(definition, 'tg_table_name = ''shopping_lists''', 'tg_table_name = ''listas_compras''');
    definition := replace(definition, 'tg_table_name = ''shopping_item_sources''', 'tg_table_name = ''origenes_articulo_compra''');
    definition := replace(definition, 'tg_table_name = ''user_roles''', 'tg_table_name = ''roles_usuario''');
    definition := replace(definition, 'tg_table_name = ''account_status''', 'tg_table_name = ''estado_cuenta''');
    definition := replace(definition, 'tg_table_name = ''catalog_core''', 'tg_table_name = ''catalogo_base''');
    definition := replace(definition, 'tg_table_name = ''shared_recipes''', 'tg_table_name = ''recetas_compartidas''');

    if definition <> pg_get_functiondef(routine.oid) then
      execute definition;
    end if;
  end loop;
end;
$rename_function_bodies$;

commit;
