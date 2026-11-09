param([string]$PostgresBin = 'C:/Program Files/PostgreSQL/18/bin', [int]$Port = 55440, [switch]$RecipeReads, [switch]$ResumeDates, [switch]$ProfileAdmin, [switch]$AuditNames, [switch]$Inventory, [switch]$ConversionData, [switch]$ApplyCutover, [string]$SchemaExportPath, [switch]$SchemaOnly)
$ErrorActionPreference = 'Stop'
if ($ApplyCutover) { $ConversionData = $true }
$taskTemp = Join-Path $env:TEMP ('cocinapp-rename-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$cluster = Join-Path $taskTemp 'data'
$psql = Join-Path $PostgresBin 'psql.exe'
$translator = Join-Path $PSScriptRoot 'translate_table_names.py'
& (Join-Path $PostgresBin 'initdb.exe') -D $cluster -U postgres --auth=trust --encoding=UTF8 --no-locale --no-sync | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Temporary database initialization failed' }
& (Join-Path $PostgresBin 'pg_ctl.exe') -D $cluster -l (Join-Path $taskTemp 'server.log') -o "-h 127.0.0.1 -p $Port" -w start
if ($LASTEXITCODE -ne 0) { throw 'Temporary database could not start' }
try {
  $bootstrap = Join-Path $taskTemp 'auth.sql'
  @'
create role anon; create role authenticated; create role service_role;
create schema auth;
create table auth.users(id uuid primary key, email text, banned_until timestamptz, created_at timestamptz default now(), raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
grant usage on schema auth to anon, authenticated, service_role;
'@ | Set-Content -LiteralPath $bootstrap -Encoding utf8
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $bootstrap
  if ($LASTEXITCODE -ne 0) { throw 'Local Auth bootstrap failed' }

  $migrations = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../migrations') -Filter '*.sql' | Sort-Object Name
  $renameMigration = Join-Path $PSScriptRoot '../migrations/202611010009_rename_tables_spanish.sql'
  foreach ($migration in $migrations) {
    if ($migration.Name -ge '202610300001_' -or $migration.Name -eq '202611010009_rename_tables_spanish.sql') { continue }
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $migration.FullName
    if ($LASTEXITCODE -ne 0) { throw "Historical migration failed: $($migration.Name)" }
  }

  $seed = Join-Path $taskTemp 'legacy-seed.sql'
  @'
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','rename-test@example.invalid'),('22222222-2222-2222-2222-222222222222','rename-test-2@example.invalid');
insert into public.pantry_items(user_id,name,category,quantity,unit) values ('11111111-1111-1111-1111-111111111111','rename fixture','Otros',3,'u');
insert into public.personal_data(user_id,data_key,value) values ('11111111-1111-1111-1111-111111111111','profile','{"displayName":"Synthetic"}'::jsonb);
insert into public.catalog_core(catalog_key,payload) values ('main','{"categories":[],"units":[],"ingredients":[]}'::jsonb);
insert into public.shared_recipes(catalog_key,recipes) values ('main','[]'::jsonb);
'@ | Set-Content -LiteralPath $seed -Encoding utf8
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $seed
  if ($LASTEXITCODE -ne 0) { throw 'Legacy rename fixture seeding failed' }

  # Pantry reads are explicitly exercised by a stage; other RPC-only tables keep their grants.
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -c 'grant select on public.pantry_items to authenticated'
  if ($LASTEXITCODE -ne 0) { throw 'Local pantry read grant setup failed' }

  if ($ConversionData) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/cutover_data_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Cutover local fixture setup failed' }
  }
  if ($Inventory) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot '../diagnostics/cutover_inventory.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Legacy read-only inventory failed' }
  }
  python (Join-Path $PSScriptRoot 'build_table_rename_rehearsal.py')
  if ($LASTEXITCODE -ne 0) { throw 'Remote rollback rehearsal build failed' }
  $rehearsalName = 'table_rename_rehearsal.sql'
  if ($ConversionData) {
    python (Join-Path $PSScriptRoot '../backfill/build_cutover_data_rehearsal.py')
    if ($LASTEXITCODE -ne 0) { throw 'Cutover data rehearsal build failed' }
    $rehearsalName = '../backfill/cutover_data_rehearsal.sql'
  } elseif ($AuditNames) {
    python (Join-Path $PSScriptRoot 'build_admin_audit_names_rehearsal.py')
    $rehearsalName = 'admin_audit_names_rehearsal.sql'
  } elseif ($ProfileAdmin) {
    python (Join-Path $PSScriptRoot 'build_profile_admin_rehearsal.py')
    if ($LASTEXITCODE -ne 0) { throw 'Profile/admin rehearsal build failed' }
    $rehearsalName = 'profile_admin_rehearsal.sql'
  } elseif ($ResumeDates) {
    python (Join-Path $PSScriptRoot 'build_resume_dates_rehearsal.py')
    if ($LASTEXITCODE -ne 0) { throw 'Resume/date rehearsal build failed' }
    $rehearsalName = 'resume_dates_rehearsal.sql'
  } elseif ($RecipeReads) {
    python (Join-Path $PSScriptRoot 'build_recipe_read_contract_rehearsal.py')
    if ($LASTEXITCODE -ne 0) { throw 'Recipe read rehearsal build failed' }
    $rehearsalName = 'recipe_read_contract_rehearsal.sql'
  }
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot $rehearsalName)
  if ($LASTEXITCODE -ne 0) { throw 'Complete rollback-only rename rehearsal failed' }
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -c "DO 'BEGIN IF to_regclass(''public.pantry_items'') IS NULL OR to_regclass(''public.articulos_despensa'') IS NOT NULL OR to_regclass(''public.dietary_tags'') IS NOT NULL OR to_regclass(''public.profiles'') IS NOT NULL OR to_regclass(''public.recipes'') IS NOT NULL OR to_regclass(''public.admin_recipe_write_state'') IS NOT NULL OR to_regnamespace(''rename_rehearsal'') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=''public'' AND p.proname IN (''save_my_profile'',''admin_save_recipe'',''get_my_dashboard_summary'')) OR (SELECT count(*) FROM public.pantry_items WHERE name=''rename fixture'') <> 1 OR (SELECT count(*) FROM public.personal_data WHERE data_key=''profile'') <> 1 OR (SELECT count(*) FROM public.catalog_core WHERE catalog_key=''main'') <> 1 OR (SELECT count(*) FROM public.shared_recipes WHERE catalog_key=''main'') <> 1 THEN RAISE EXCEPTION ''Legacy-only rehearsal did not roll back cleanly''; END IF; END';"
  if ($LASTEXITCODE -ne 0) { throw 'Rename rehearsal rollback verification failed' }

  if ($ApplyCutover) {
    python (Join-Path $PSScriptRoot '../backfill/build_cutover_apply.py')
    if ($LASTEXITCODE -ne 0) { throw 'Permanent cutover generation failed' }
    $applySql = Join-Path $PSScriptRoot '../backfill/cutover_apply.sql'
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $applySql
    if ($LASTEXITCODE -ne 0) { throw 'Permanent LOCAL cutover failed' }
    # A separate connection confirms COMMIT persisted. A second apply must fail closed.
    $countSql = "select count(*) from pg_tables where schemaname='public';"
    $tableCount = & $psql -h 127.0.0.1 -p $Port -U postgres -At -c $countSql
    if ($LASTEXITCODE -ne 0 -or [int]$tableCount -ne 36) { throw 'Committed schema verification failed' }
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $applySql 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { throw 'Permanent cutover incorrectly allowed replay' }
    Write-Output 'PASS: LOCAL permanent conversion committed, 36 tables persisted, replay rejected; no remote changes'
    return
  }

  $pendingMigrations = $migrations | Where-Object { $_.Name -ge '202610300001_' -and $_.Name -lt '202611010009_' }
  foreach ($migration in $pendingMigrations) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $migration.FullName
    if ($LASTEXITCODE -ne 0) { throw "Pending migration failed after rehearsal: $($migration.Name)" }
  }

  $snapshot = Join-Path $taskTemp 'snapshot-before.sql'
  @'
create schema rename_audit;
create table rename_audit.relations as
select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class
where relnamespace='public'::regnamespace and relkind in ('r','p') and relname=any(array[
  'pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log',
  'dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients',
  'ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps',
  'recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists',
  'shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps',
  'cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests','admin_recipe_write_state']);
create table rename_audit.columns as
select c.oid, a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated
from pg_class c join pg_attribute a on a.attrelid=c.oid
where c.oid in (select oid from rename_audit.relations) and a.attnum>0 and not a.attisdropped;
create table rename_audit.constraints as
select oid,conrelid,conname,contype,convalidated,conkey,confrelid,confkey,
  case when contype='c' then pg_get_constraintdef(oid) end as definition
from pg_constraint where conrelid in (select oid from rename_audit.relations);
create table rename_audit.indexes as
select i.indexrelid,i.indrelid,i.indisunique,i.indisprimary,i.indkey,i.indclass,i.indnatts,i.indnkeyatts
from pg_index i where i.indrelid in (select oid from rename_audit.relations);
create table rename_audit.policies as
select polrelid,polname,polcmd,polpermissive,polroles,polqual,polwithcheck
from pg_policy where polrelid in (select oid from rename_audit.relations);
create table rename_audit.triggers as
select tgrelid,tgname,tgenabled,tgfoid,tgtype,tgattr
from pg_trigger where tgrelid in (select oid from rename_audit.relations) and not tgisinternal;
create table rename_audit.grants as
select c.oid as relid,x.grantor,x.grantee,x.privilege_type,x.is_grantable
from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
where c.oid in (select oid from rename_audit.relations);
create table rename_audit.routines as
select p.oid,p.proowner,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public';
'@ | Set-Content -LiteralPath $snapshot -Encoding utf8
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $snapshot
  if ($LASTEXITCODE -ne 0) { throw 'Before-rename catalog snapshot failed' }

  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $renameMigration
  if ($LASTEXITCODE -ne 0) { throw 'Final table rename migration failed' }
  $assertions = Join-Path $taskTemp 'assert-rename.sql'
  @'
do $$
declare old_names text[] := array['pantry_items','personal_data','user_roles','catalog_core','shared_recipes','account_status','admin_audit_log','dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests','admin_recipe_write_state'];
new_names text[] := array['articulos_despensa','datos_personales','roles_usuario','catalogo_base','recetas_compartidas','estado_cuenta','registro_auditoria','etiquetas_dieteticas','configuracion_nutricional','perfiles','preferencias_dieteticas_usuario','categorias','unidades','ingredientes','etiquetas_dieteticas_ingrediente','recetas','turnos_comida_receta','etiquetas_dieteticas_receta','ingredientes_receta','pasos_receta','ingredientes_paso_receta','recetas_favoritas','planes_comida','turnos_plan_comida','comprobantes_despensa','listas_compras','articulos_compra','origenes_articulo_compra','articulos_comprobante_despensa','sesiones_cocina','pasos_sesion_cocina','eventos_cocina','ingredientes_evento_cocina','solicitudes_generacion_receta','solicitudes_reconocimiento_ticket','estado_escritura_receta_admin'];
begin
  if cardinality(old_names) <> 36 or cardinality(new_names) <> 36 then raise exception 'Table map cardinality mismatch'; end if;
  for i in 1..36 loop
    if to_regclass('public.' || old_names[i]) is not null or to_regclass('public.' || new_names[i]) is null then raise exception 'Rename missing for %', old_names[i]; end if;
  end loop;
  if to_regclass('auth.users') is null then raise exception 'auth.users was altered'; end if;
  if (select count(*) from public.articulos_despensa where name='rename fixture') <> 1
     or (select count(*) from public.datos_personales where data_key='profile') <> 1
     or (select count(*) from public.catalogo_base where catalog_key='main') <> 1
     or (select count(*) from public.recetas_compartidas where catalog_key='main') <> 1 then raise exception 'Legacy data did not survive rename'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~ 'public\.(pantry_items|personal_data|user_roles|catalog_core|shared_recipes|account_status|admin_audit_log|dietary_tags|nutrition_config|profiles|user_dietary_preferences|categories|units|ingredients|ingredient_dietary_tags|recipes|recipe_meal_shifts|recipe_dietary_tags|recipe_ingredients|recipe_steps|recipe_step_ingredients|favorite_recipes|meal_plans|meal_plan_slots|pantry_receipts|shopping_lists|shopping_items|shopping_item_sources|pantry_receipt_items|cooking_sessions|cooking_session_steps|cooking_events|cooking_event_ingredients|recipe_generation_requests|receipt_recognition_requests|admin_recipe_write_state)([^a-z0-9_]|$)') then raise exception 'Stale qualified relation reference remains in a routine'; end if;
  if exists(select 1 from rename_audit.relations before_row full join (select oid,relkind,relrowsecurity,relforcerowsecurity from pg_class where oid in(select oid from rename_audit.relations)) after_row using(oid) where before_row.oid is null or after_row.oid is null or (before_row.relkind,before_row.relrowsecurity,before_row.relforcerowsecurity) is distinct from (after_row.relkind,after_row.relrowsecurity,after_row.relforcerowsecurity)) then raise exception 'Table OID or RLS metadata changed'; end if;
  if exists((select * from rename_audit.columns except select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_audit.relations) and a.attnum>0 and not a.attisdropped) union all (select c.oid,a.attnum,a.attname,a.atttypid,a.atttypmod,a.attnotnull,a.attidentity,a.attgenerated from pg_class c join pg_attribute a on a.attrelid=c.oid where c.oid in(select oid from rename_audit.relations) and a.attnum>0 and not a.attisdropped except select * from rename_audit.columns)) then raise exception 'Table columns changed'; end if;
  if exists((select * from rename_audit.constraints except select oid,conrelid,conname,contype,convalidated,conkey,confrelid,confkey,case when contype='c' then pg_get_constraintdef(oid) end from pg_constraint where conrelid in(select oid from rename_audit.relations)) union all (select oid,conrelid,conname,contype,convalidated,conkey,confrelid,confkey,case when contype='c' then pg_get_constraintdef(oid) end from pg_constraint where conrelid in(select oid from rename_audit.relations) except select * from rename_audit.constraints)) then raise exception 'Constraints changed'; end if;
  if exists((select * from rename_audit.indexes except select i.indexrelid,i.indrelid,i.indisunique,i.indisprimary,i.indkey,i.indclass,i.indnatts,i.indnkeyatts from pg_index i where i.indrelid in(select oid from rename_audit.relations)) union all (select i.indexrelid,i.indrelid,i.indisunique,i.indisprimary,i.indkey,i.indclass,i.indnatts,i.indnkeyatts from pg_index i where i.indrelid in(select oid from rename_audit.relations) except select * from rename_audit.indexes)) then raise exception 'Indexes changed'; end if;
  if exists((select * from rename_audit.policies except select polrelid,polname,polcmd,polpermissive,polroles,polqual,polwithcheck from pg_policy where polrelid in(select oid from rename_audit.relations)) union all (select polrelid,polname,polcmd,polpermissive,polroles,polqual,polwithcheck from pg_policy where polrelid in(select oid from rename_audit.relations) except select * from rename_audit.policies)) then raise exception 'Policies changed'; end if;
  if exists((select * from rename_audit.triggers except select tgrelid,tgname,tgenabled,tgfoid,tgtype,tgattr from pg_trigger where tgrelid in(select oid from rename_audit.relations) and not tgisinternal) union all (select tgrelid,tgname,tgenabled,tgfoid,tgtype,tgattr from pg_trigger where tgrelid in(select oid from rename_audit.relations) and not tgisinternal except select * from rename_audit.triggers)) then raise exception 'Triggers changed'; end if;
  if exists((select * from rename_audit.grants except select c.oid,x.grantor,x.grantee,x.privilege_type,x.is_grantable from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x where c.oid in(select oid from rename_audit.relations)) union all (select c.oid,x.grantor,x.grantee,x.privilege_type,x.is_grantable from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x where c.oid in(select oid from rename_audit.relations) except select * from rename_audit.grants)) then raise exception 'Table grants changed'; end if;
  if exists((select * from rename_audit.routines except select p.oid,p.proowner,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') union all (select p.oid,p.proowner,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' except select * from rename_audit.routines)) then raise exception 'Routine OIDs, owners, or grants changed'; end if;
end;
$$;
'@ | Set-Content -LiteralPath $assertions -Encoding utf8
  & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $assertions
  if ($LASTEXITCODE -ne 0) { throw 'Rename migration assertions failed' }

  # Later migrations use the final Spanish relation names and must follow 009.
  foreach ($migration in ($migrations | Where-Object { $_.Name -gt '202611010009_rename_tables_spanish.sql' })) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $migration.FullName
    if ($LASTEXITCODE -ne 0) { throw "Post-rename migration failed: $($migration.Name)" }
  }
  if ($Inventory) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot '../diagnostics/cutover_inventory.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Relational read-only inventory failed' }
  }
  if ($SchemaExportPath) {
    $schemaSql = Join-Path $PSScriptRoot 'export_schema.sql'
    $schemaJson = & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -At -f $schemaSql
    if ($LASTEXITCODE -ne 0) { throw 'Schema catalog export failed' }
    $schemaDirectory = Split-Path -Parent $SchemaExportPath
    if ($schemaDirectory) { New-Item -ItemType Directory -Force -Path $schemaDirectory | Out-Null }
    [System.IO.File]::WriteAllText($SchemaExportPath, [string]$schemaJson, [System.Text.UTF8Encoding]::new($false))
    Write-Output "PASS: schema catalog exported to $SchemaExportPath"
    if ($SchemaOnly) { return }
  }
  $stageFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.stage.sql' | Sort-Object Name
  foreach ($stage in $stageFiles) {
    $stageSql = Join-Path $taskTemp $stage.Name
    Copy-Item -LiteralPath $stage.FullName -Destination $stageSql
    python $translator $stageSql
    if ($LASTEXITCODE -ne 0) { throw "Stage translation failed: $($stage.Name)" }
    $body = Get-Content -Raw -LiteralPath $stageSql
    if ($stage.Name -eq 'nutrition_config.stage.sql') {
      $parameters = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'nutrition_config_parameters.json') | ConvertFrom-Json
      $activity = ConvertTo-Json -InputObject $parameters.activity_factors -Compress
      $goals = ConvertTo-Json -InputObject $parameters.goal_adjustments -Compress
      $body = $body.Replace('__ACTIVITY_FACTORS__', $activity).Replace('__GOAL_ADJUSTMENTS__', $goals)
    }
    $batch = Join-Path $taskTemp ('run-' + $stage.Name)
    "begin;`n$body`nrollback;`n" | Set-Content -LiteralPath $batch -Encoding utf8
    & $psql -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $batch
    if ($LASTEXITCODE -ne 0) { throw "Post-rename stage failed: $($stage.Name)" }
    Write-Output "PASS: post-rename stage $($stage.Name)"
  }
  Write-Output 'PASS: actual 202611010009 migration and all rollback-only SQL stages verified locally; no remote connection used'
} finally {
  & (Join-Path $PostgresBin 'pg_ctl.exe') -D $cluster -m fast -w stop
}
