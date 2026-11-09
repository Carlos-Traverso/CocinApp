-- Inventario READ ONLY para decidir el corte legacy JSON -> modelo relacional.
-- Ejecutar el archivo completo como una sola sesión. Solo emite agregados/flags;
-- muestra solo líneas agregadas; no nombres, emails, UUIDs ni JSON personal.
begin;
set transaction read only;

do $inventory$
declare
  report jsonb := '[]'::jsonb;
  r record;
  n bigint;
  detail text;
  legacy text[] := array['pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log'];
  final_names text[] := array['articulos_despensa','datos_personales','roles_usuario','catalogo_base','recetas_compartidas','estado_cuenta','registro_auditoria','etiquetas_dieteticas','configuracion_nutricional','perfiles','preferencias_dieteticas_usuario','categorias','unidades','ingredientes','etiquetas_dieteticas_ingrediente','recetas','turnos_comida_receta','etiquetas_dieteticas_receta','ingredientes_receta','pasos_receta','ingredientes_paso_receta','recetas_favoritas','planes_comida','turnos_plan_comida','comprobantes_despensa','listas_compras','articulos_compra','origenes_articulo_compra','articulos_comprobante_despensa','sesiones_cocina','pasos_sesion_cocina','eventos_cocina','ingredientes_evento_cocina','solicitudes_generacion_receta','solicitudes_reconocimiento_ticket','estado_escritura_receta_admin'];
  t text;
begin
  report := report || jsonb_build_array(format('CUTOVER INVENTORY | section=relation | table | exists | rows | rls | force_rls | grants(select/insert/update/delete anon,authenticated)'));
  foreach t in array legacy || final_names loop
    if to_regclass(format('public.%I',t)) is null then
      report := report || jsonb_build_array(format('relation | %s | absent | - | - | - | -',t));
    else
      execute format('select count(*) from public.%I',t) into n;
      select format('%s/%s/%s/%s,%s/%s/%s/%s',
        has_table_privilege('anon',format('public.%I',t),'select'),has_table_privilege('anon',format('public.%I',t),'insert'),has_table_privilege('anon',format('public.%I',t),'update'),has_table_privilege('anon',format('public.%I',t),'delete'),
        has_table_privilege('authenticated',format('public.%I',t),'select'),has_table_privilege('authenticated',format('public.%I',t),'insert'),has_table_privilege('authenticated',format('public.%I',t),'update'),has_table_privilege('authenticated',format('public.%I',t),'delete')) into detail;
      select format('%s | %s | %s',c.relrowsecurity,c.relforcerowsecurity,detail) into detail from pg_class c where c.oid=to_regclass(format('public.%I',t));
      report := report || jsonb_build_array(format('relation | %s | present | %s | %s',t,n,detail));
    end if;
  end loop;

  report := report || jsonb_build_array(format('CUTOVER INVENTORY | section=personal_key | key | rows | nonempty | json_type'));
  if to_regclass('public.personal_data') is not null then
    for r in execute $q$select data_key, count(*)::bigint rows,
      count(*) filter(where value is not null and value <> 'null'::jsonb and value <> '{}'::jsonb and value <> '[]'::jsonb)::bigint nonempty,
      coalesce(string_agg(distinct jsonb_typeof(value),',' order by jsonb_typeof(value)),'(null)') types
      from public.personal_data group by data_key order by data_key$q$ loop
      report := report || jsonb_build_array(format('personal_key | %s | %s | %s | %s',r.data_key,r.rows,r.nonempty,r.types));
    end loop;
    execute $q$select count(*) filter(where data_key='shopping' and case when jsonb_typeof(value)='array' then jsonb_array_length(value)>0 else false end) as shopping,
      count(*) filter(where data_key='cooking_progress' and value <> 'null'::jsonb and value <> '{}'::jsonb and value <> '[]'::jsonb) as progress,
      count(*) filter(where data_key='cooking_history' and value <> 'null'::jsonb and value <> '{}'::jsonb and value <> '[]'::jsonb) as history
      from public.personal_data$q$ into r;
    report := report || jsonb_build_array(format('personal_payload | nonempty_shopping_arrays=%s | nonempty_cooking_progress=%s | nonempty_cooking_history=%s',r.shopping,r.progress,r.history));
    -- Shape counters. JSON values are never cast to SQL numeric/date/UUID.
    execute $q$select
      count(*) filter(where data_key='profile' and jsonb_typeof(value)<>'object') as profile_bad_shape,
      count(*) filter(where data_key='profile' and jsonb_typeof(value)='object' and (nullif(value->>'weightKg','') is not null and (value->>'weightKg') !~ '^[0-9]+([.][0-9]+)?$' or nullif(value->>'heightCm','') is not null and (value->>'heightCm') !~ '^[0-9]+([.][0-9]+)?$' or nullif(value->>'birthDate','') is not null and (value->>'birthDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')) as profile_bad_fields,
      count(*) filter(where data_key='meal_plan' and jsonb_typeof(value)='array' and exists(select 1 from jsonb_array_elements(case when jsonb_typeof(value)='array' then value else '[]'::jsonb end) e where coalesce(e->>'date',e->>'mealDate','')<>'' and coalesce(e->>'date',e->>'mealDate','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')) as plan_bad_dates,
      count(*) filter(where data_key='meal_plan' and jsonb_typeof(value)<>'array') as plan_bad_shape,
      count(*) filter(where data_key='favorites' and jsonb_typeof(value)<>'array') as favorites_bad_shape,
      count(*) filter(where data_key='cooking_progress' and jsonb_typeof(value) is distinct from 'array') as progress_bad_shape,
      count(*) filter(where data_key='cooking_history' and jsonb_typeof(value)<>'array') as history_bad_shape
      from public.personal_data$q$ into r;
    report := report || jsonb_build_array(format('malformed | profile_shape=%s | profile_numeric_or_date_format=%s | meal_plan_shape=%s | meal_plan_date_format_rows=%s | favorites_shape=%s | cooking_progress_shape=%s | cooking_history_shape=%s',r.profile_bad_shape,r.profile_bad_fields,r.plan_bad_shape,r.plan_bad_dates,r.favorites_bad_shape,r.progress_bad_shape,r.history_bad_shape));
    execute $q$with slots as (select p.user_id, coalesce(e->>'date',e->>'mealDate') d, coalesce(nullif(e->>'meal',''),nullif(e->>'mealShift',''),'') m
      from public.personal_data p cross join lateral jsonb_array_elements(case when jsonb_typeof(value)='array' then value else '[]'::jsonb end)e where data_key='meal_plan'), dup as
      (select user_id,d,m,count(*) n from slots where coalesce(d,'')<>'' and m<>'' group by user_id,d,m having count(*)>1)
      select count(*) duplicate_date_meal_groups, coalesce(sum(n),0) duplicate_slots from dup$q$ into r;
    report := report || jsonb_build_array(format('meal_plan_duplicates | duplicate_date_meal_groups=%s | slots_in_duplicate_groups=%s',r.duplicate_date_meal_groups,r.duplicate_slots));
    execute $q$select count(*) filter(where data_key='profile' and jsonb_typeof(value)='object' and nullif(value->>'version','') is not null and (value->>'version') !~ '^[0-9]+$') as profile_version_bad,
      count(*) filter(where data_key='meal_plan' and jsonb_typeof(value)='array' and exists(select 1 from jsonb_array_elements(case when jsonb_typeof(value)='array' then value else '[]'::jsonb end)e where nullif(e->>'version','') is not null and (e->>'version') !~ '^[0-9]+$')) as plan_version_bad
      from public.personal_data$q$ into r;
    report := report || jsonb_build_array(format('malformed_version | profile=%s | meal_plan_item=%s',r.profile_version_bad,r.plan_version_bad));
    -- Recipe reference counts, retaining no key/ID values in output.
    if to_regclass('public.shared_recipes') is not null then
      execute $q$with recipes as (select e->>'id' id from public.shared_recipes s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.recipes)='array' then s.recipes else '[]'::jsonb end)e), refs as (
        select case when data_key='favorites' then e#>>'{}' else e->>'recipeId' end id
        from public.personal_data p cross join lateral jsonb_array_elements(case when jsonb_typeof(value)='array' then value else '[]'::jsonb end)e where data_key in ('favorites','meal_plan','cooking_history','cooking_progress'))
        select count(*) filter(where id is null or id='') missing_id, count(*) filter(where id is not null and not exists(select 1 from recipes x where x.id=refs.id)) unmatched from refs$q$ into r;
      report := report || jsonb_build_array(format('recipe_refs | missing_id=%s | unmatched_to_legacy_recipe_catalog=%s',r.missing_id,r.unmatched));
    end if;
  end if;

  -- Relational direct-table measurements, guarded by column presence via to_jsonb.
  foreach t in array array['perfiles','profiles','articulos_compra','shopping_items','turnos_plan_comida','meal_plan_slots','sesiones_cocina','cooking_sessions','recetas','recipes','unidades','units','ingredientes_receta','recipe_ingredients'] loop
    if to_regclass(format('public.%I',t)) is not null then
      execute format('select count(*) from public.%I',t) into n;
      report := report || jsonb_build_array(format('relational_rows | %s | %s',t,n));
    end if;
  end loop;
  foreach t in array array['articulos_compra','shopping_items'] loop
    if to_regclass(format('public.%I',t)) is not null then
      execute format('select count(*) from public.%I x where coalesce(to_jsonb(x)->>''source_shopping_id'',to_jsonb(x)->>''legacy_shopping_id'') is not null',t) into n;
      report := report || jsonb_build_array(format('provenance | %s | rows_with_source_shopping_id=%s',t,n));
      execute format('select count(*) from public.%I x where coalesce(to_jsonb(x)->>''quantity'','''') !~ ''^-?[0-9]+([.][0-9]+)?$''',t) into n;
      report := report || jsonb_build_array(format('malformed_quantity | %s | invalid_or_null=%s',t,n));
    end if;
  end loop;
  foreach t in array array['articulos_despensa','pantry_items'] loop
    if to_regclass(format('public.%I',t)) is not null then
      execute format('select count(*) from public.%I x where jsonb_typeof(coalesce(to_jsonb(x)->''source_shopping_ids'',to_jsonb(x)->''sourceShoppingIds''))=''array''',t) into n;
      report := report || jsonb_build_array(format('provenance | %s | rows_with_sourceShoppingIds_array=%s',t,n));
    end if;
  end loop;
  if to_regclass('public.shared_recipes') is not null then
    execute $q$with items as (select i from public.shared_recipes s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.recipes)='array' then s.recipes else '[]'::jsonb end) rec cross join lateral jsonb_array_elements(case when jsonb_typeof(rec->'ingredients')='array' then rec->'ingredients' else '[]'::jsonb end)i), labels as
      (select lower(trim(coalesce(i->>'name',i->>'ingredient',''))) ingredient_label, lower(trim(coalesce(nullif(i->>'unit',''),i->>'unitName',''))) unit_label from items where coalesce(i->>'name',i->>'ingredient','')<>'')
      select count(*) filter(where coalesce(i->>'unitId','')='') missing_unit_id,
        (select count(*) from (select ingredient_label from labels group by ingredient_label having count(distinct unit_label)>1) a) ingredient_labels_with_multiple_unit_labels
      from items i$q$ into r;
    report := report || jsonb_build_array(format('legacy_recipe_unit | ingredient_entries_without_unit_id=%s | ingredient_labels_with_multiple_unit_labels=%s',r.missing_unit_id,r.ingredient_labels_with_multiple_unit_labels));
  end if;
  -- Migration markers and function presence only; no project URL/env/secrets are read.
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select count(*), min(version::text), max(version::text) from supabase_migrations.schema_migrations' into r;
    report := report || jsonb_build_array(format('migration_marker | supabase_migrations.schema_migrations | rows=%s | min_version=%s | max_version=%s',r.count,r.min,r.max));
  elsif to_regclass('public.schema_migrations') is not null then
    execute 'select count(*), min(version::text), max(version::text) from public.schema_migrations' into r;
    report := report || jsonb_build_array(format('migration_marker | public.schema_migrations | rows=%s | min_version=%s | max_version=%s',r.count,r.min,r.max));
  else
    report := report || jsonb_build_array(format('migration_marker | schema_migrations | absent_or_not_visible'));
  end if;
  foreach t in array array['public.admin_recipe_write_state','public.estado_escritura_receta_admin'] loop
    report := report || jsonb_build_array(format('auxiliary_table | %s | exists=%s',t,to_regclass(t) is not null));
  end loop;
  foreach t in array array['public.get_my_profile()','public.save_my_profile(jsonb,text[],bigint)','public.get_my_meal_plan(date)','public.save_my_meal_plan(date,jsonb,bigint)','public.create_my_shopping_list(uuid,text,uuid)','public.start_my_cooking_session(uuid,uuid,integer)','public.get_my_dashboard_summary(date,integer)','public.admin_search_audit_events(text,integer)'] loop
    report := report || jsonb_build_array(format('routine_presence | %s | exists=%s',t,to_regprocedure(t) is not null));
  end loop;
  report := report || jsonb_build_array(format('NOTE | Missing objects are reported as absent; inaccessible table counts may fail under caller permissions. Run as Supabase SQL Editor owner/admin for complete counts.'));
  perform set_config('cocinapp.cutover_inventory_report', report::text, true);
end;
$inventory$;

select value as inventory_report
from jsonb_array_elements_text(current_setting('cocinapp.cutover_inventory_report')::jsonb);

rollback;
