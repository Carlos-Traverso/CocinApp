param([string]$PostgresBin = 'C:/Program Files/PostgreSQL/18/bin', [int]$Port = 55439, [switch]$Permissions, [switch]$CatalogAdmin, [switch]$CatalogAdminConcurrency, [switch]$RecipeAdmin, [switch]$RecipeAdminConcurrency, [switch]$DietaryAdmin, [switch]$DietaryAdminConcurrency, [switch]$NutritionConfig, [switch]$NutritionConfigConcurrency, [switch]$RecipeDiscovery, [switch]$ExternalRequests, [switch]$ExternalRequestsConcurrency, [switch]$PersonalReads, [switch]$InventoryReads, [switch]$DashboardSummary, [switch]$PersonalWrites, [switch]$Concurrency, [switch]$PlanningShopping, [switch]$PlanningShoppingConcurrency, [switch]$ShoppingTransfer, [switch]$ShoppingTransferConcurrency, [switch]$Suggestions, [switch]$PantryWrites, [switch]$PantryConcurrency, [switch]$CookingSessions, [switch]$CookingSessionConcurrency, [switch]$CookingFinish, [switch]$CookingQueries)
$ErrorActionPreference = 'Stop'
$personalMode = $PersonalWrites -or $Concurrency
$catalogMode = $CatalogAdmin -or $CatalogAdminConcurrency
$recipeMode = $RecipeAdmin -or $RecipeAdminConcurrency
$dietaryMode = $DietaryAdmin -or $DietaryAdminConcurrency
$nutritionMode = $NutritionConfig -or $NutritionConfigConcurrency
$discoveryMode = $RecipeDiscovery
$externalRequestsMode = $ExternalRequests -or $ExternalRequestsConcurrency
$personalReadsMode = $PersonalReads
$inventoryReadsMode = $InventoryReads
$dashboardSummaryMode = $DashboardSummary
$transferMode = $ShoppingTransfer -or $ShoppingTransferConcurrency
$planningMode = $PlanningShopping -or $PlanningShoppingConcurrency
$pantryMode = $PantryWrites -or $PantryConcurrency
$cookingMode = $CookingSessions -or $CookingSessionConcurrency
$finishMode = $CookingFinish
$queriesMode = $CookingQueries
if ((@($Permissions,$catalogMode,$recipeMode,$dietaryMode,$nutritionMode,$discoveryMode,$ExternalRequests,$ExternalRequestsConcurrency,$personalReadsMode,$inventoryReadsMode,$dashboardSummaryMode,$personalMode,$planningMode,$transferMode,$Suggestions,$pantryMode,$cookingMode,$finishMode,$queriesMode) | Where-Object { $_ }).Count -gt 1) { throw 'Choose one rehearsal mode' }
$usePermissionFixture = $Permissions -or $catalogMode -or $recipeMode -or $dietaryMode -or $nutritionMode -or $discoveryMode -or $externalRequestsMode -or $personalReadsMode -or $inventoryReadsMode -or $dashboardSummaryMode -or $personalMode -or $planningMode -or $transferMode -or $Suggestions -or $pantryMode -or $cookingMode -or $finishMode -or $queriesMode
$taskTemp = Join-Path $env:TEMP ('cocinapp-backfill-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$cluster = Join-Path $taskTemp 'data'
& (Join-Path $PostgresBin 'initdb.exe') -D $cluster -U postgres --auth=trust --encoding=UTF8 --no-locale --no-sync | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Temporary database initialization failed' }
& (Join-Path $PostgresBin 'pg_ctl.exe') -D $cluster -l (Join-Path $taskTemp 'server.log') -o "-h 127.0.0.1 -p $Port" -w start
if ($LASTEXITCODE -ne 0) { throw 'Temporary database could not start' }
try {
  # Send the whole file in ONE server request, as the SQL Editor does.
  if ($catalogMode) { python (Join-Path $PSScriptRoot 'build_catalog_admin_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Catalog admin rehearsal build failed' } }
  if ($recipeMode) { python (Join-Path $PSScriptRoot 'build_recipe_admin_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Recipe admin rehearsal build failed' } }
  if ($dietaryMode) { python (Join-Path $PSScriptRoot 'build_dietary_admin_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Dietary admin rehearsal build failed' } }
  if ($nutritionMode) { python (Join-Path $PSScriptRoot 'build_nutrition_config_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Nutrition config rehearsal build failed' } }
  if ($discoveryMode) { python (Join-Path $PSScriptRoot 'build_recipe_discovery_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Recipe discovery rehearsal build failed' } }
  if ($externalRequestsMode) { python (Join-Path $PSScriptRoot 'build_external_requests_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'External requests rehearsal build failed' } }
  if ($personalReadsMode) { python (Join-Path $PSScriptRoot 'build_personal_reads_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Personal reads rehearsal build failed' } }
  if ($inventoryReadsMode) { python (Join-Path $PSScriptRoot 'build_inventory_reads_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Inventory reads rehearsal build failed' } }
  if ($dashboardSummaryMode) { python (Join-Path $PSScriptRoot 'build_dashboard_summary_rehearsal.py'); if ($LASTEXITCODE -ne 0) { throw 'Dashboard summary rehearsal build failed' } }
  $scriptPath = if ($dashboardSummaryMode) { 'dashboard_summary_rehearsal.sql' } elseif ($inventoryReadsMode) { 'inventory_reads_rehearsal.sql' } elseif ($personalReadsMode) { 'personal_reads_rehearsal.sql' } elseif ($externalRequestsMode) { 'external_requests_rehearsal.sql' } elseif ($discoveryMode) { 'recipe_discovery_rehearsal.sql' } elseif ($nutritionMode) { 'nutrition_config_rehearsal.sql' } elseif ($dietaryMode) { 'dietary_admin_rehearsal.sql' } elseif ($recipeMode) { 'recipe_admin_rehearsal.sql' } elseif ($catalogMode) { 'catalog_admin_rehearsal.sql' } elseif ($queriesMode) { 'cooking_queries_rehearsal.sql' } elseif ($finishMode) { 'cooking_finish_rehearsal.sql' } elseif ($cookingMode) { 'cooking_session_rehearsal.sql' } elseif ($pantryMode) { 'pantry_write_rpcs_rehearsal.sql' } elseif ($Suggestions) { 'shopping_suggestions_rehearsal.sql' } elseif ($transferMode) { 'shopping_transfer_rehearsal.sql' } elseif ($planningMode) { 'planning_shopping_write_rpcs_rehearsal.sql' } elseif ($personalMode) { 'personal_write_rpcs_rehearsal.sql' } elseif ($Permissions) { 'relational_permissions_rehearsal.sql' } else { '../backfill/supabase_validation_rehearsal.sql' }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $scriptPath) -Destination (Join-Path $taskTemp 'rehearsal.sql')
  $rehearsalPath = (Join-Path $taskTemp 'rehearsal.sql').Replace("'", "''").Replace('\', '/')
  "SELECT pg_read_file('$rehearsalPath') \gexec" | Set-Content -LiteralPath (Join-Path $taskTemp 'single-batch.sql') -Encoding UTF8
  if ($usePermissionFixture) {
    $permissionFixturePath = (Join-Path $taskTemp 'permission-fixture.sql')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/relational_permissions_local.sql') -Destination $permissionFixturePath
    $bootstrapPath = (Join-Path $taskTemp 'bootstrap.sql')
    Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/relational_backfill_local.sql') | Set-Content -LiteralPath $bootstrapPath -Encoding UTF8
    Get-Content -Raw -LiteralPath $permissionFixturePath | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
    if ($transferMode -or $Suggestions -or $pantryMode -or $cookingMode -or $finishMode -or $queriesMode -or $catalogMode -or $recipeMode -or $dietaryMode -or $nutritionMode -or $discoveryMode -or $externalRequestsMode -or $personalReadsMode -or $inventoryReadsMode -or $dashboardSummaryMode) {
      Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/shopping_transfer_pantry_local.sql') | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
    }
    if ($catalogMode -or $recipeMode -or $nutritionMode -or $discoveryMode -or $externalRequestsMode -or $personalReadsMode -or $inventoryReadsMode -or $dashboardSummaryMode) {
      Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/catalog_admin_local.sql') | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
    }
    if ($dietaryMode) {
      Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/catalog_admin_local.sql') | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
      Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/dietary_admin_local.sql') | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
    }
    if ($externalRequestsMode -or $personalReadsMode -or $inventoryReadsMode -or $dashboardSummaryMode) {
      Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/external_requests_local.sql') | Add-Content -LiteralPath $bootstrapPath -Encoding UTF8
    }
  } else { $bootstrapPath = Join-Path $PSScriptRoot 'fixtures/relational_backfill_local.sql' }
  & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f $bootstrapPath -f (Join-Path $taskTemp 'single-batch.sql')
  if ($LASTEXITCODE -ne 0) { throw 'Backfill rehearsal failed' }
  & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -c "DO 'BEGIN IF to_regnamespace(''cocinapp_rehearsal'') IS NOT NULL OR to_regclass(''public.recipes'') IS NOT NULL OR (SELECT quantity FROM public.pantry_items) <> 150 THEN RAISE EXCEPTION ''Rollback verification failed''; END IF; END';"
  if ($LASTEXITCODE -ne 0) { throw 'Rollback verification failed' }
  if ($usePermissionFixture) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -c "DO 'BEGIN IF (SELECT count(*) FROM public.user_roles) <> 0 OR EXISTS(SELECT 1 FROM public.account_status WHERE NOT active) THEN RAISE EXCEPTION ''Role/status rollback verification failed''; END IF; END';"
    if ($LASTEXITCODE -ne 0) { throw 'Role/status rollback verification failed' }
  }
  Write-Output 'PASS: selected rehearsal and complete rollback verified; no remote connection used'
  if ($CatalogAdminConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/catalog_admin_schema_local.sql') -f (Join-Path $PSScriptRoot 'fixtures/catalog_admin_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local catalog admin concurrency installation failed' }
    python (Join-Path $PSScriptRoot 'catalog_admin_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local catalog admin concurrency checks failed' }
  }
  if ($RecipeAdminConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/recipe_admin_schema_local.sql') -f (Join-Path $PSScriptRoot 'fixtures/recipe_admin_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local recipe admin concurrency installation failed' }
    python (Join-Path $PSScriptRoot 'recipe_admin_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local recipe admin concurrency checks failed' }
  }
  if ($DietaryAdminConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/dietary_admin_schema_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local dietary admin RPC installation failed' }
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/dietary_admin_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local dietary concurrency fixtures failed' }
    python (Join-Path $PSScriptRoot 'dietary_admin_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local dietary admin concurrency checks failed' }
  }
  if ($NutritionConfigConcurrency) {
    python (Join-Path $PSScriptRoot 'build_nutrition_config_rehearsal.py')
    if ($LASTEXITCODE -ne 0) { throw 'Nutrition schema installer build failed' }
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/nutrition_config_schema_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local nutrition config schema installation failed' }
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/nutrition_config_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local nutrition concurrency fixture seeding failed' }
    python (Join-Path $PSScriptRoot 'nutrition_config_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local nutrition config concurrency checks failed' }
  }
  if ($Concurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/personal_rpc_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local concurrency installation failed' }
    python (Join-Path $PSScriptRoot 'personal_rpc_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local concurrency checks failed' }
  }
  if ($PlanningShoppingConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/planning_shopping_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local planning/shopping concurrency installation failed' }
    python (Join-Path $PSScriptRoot 'planning_shopping_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local planning/shopping concurrency checks failed' }
  }
  if ($ShoppingTransferConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/shopping_transfer_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local transfer installation failed' }
    python (Join-Path $PSScriptRoot 'shopping_transfer_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local transfer concurrency checks failed' }
  }
  if ($PantryConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/pantry_write_concurrency_install.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local pantry RPC installation failed' }
    python (Join-Path $PSScriptRoot 'pantry_rpc_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local pantry concurrency checks failed' }
  }
  if ($CookingSessionConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/cooking_session_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local cooking session installation failed' }
    python (Join-Path $PSScriptRoot 'cooking_session_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local cooking session concurrency checks failed' }
  }
  if ($finishMode) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/cooking_finish_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local cooking finish installation failed' }
    python (Join-Path $PSScriptRoot 'cooking_finish_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local cooking finish concurrency checks failed' }
  }
  if ($ExternalRequestsConcurrency) {
    & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $Port -U postgres -v ON_ERROR_STOP=1 -q -f (Join-Path $PSScriptRoot 'fixtures/external_requests_schema_local.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Local external request schema installation failed' }
    python (Join-Path $PSScriptRoot 'external_requests_concurrency_local.py') --psql (Join-Path $PostgresBin 'psql.exe') --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Local external request concurrency checks failed' }
  }
} finally {
  & (Join-Path $PostgresBin 'pg_ctl.exe') -D $cluster -m fast -w stop
}
