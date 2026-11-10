param(
  [string]$PostgresBin = 'C:/Program Files/PostgreSQL/18/bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$seedDirectory = Join-Path $repoRoot 'backend/supabase/seeds'
$fixturePath = Join-Path $PSScriptRoot 'fixtures/recipe_admin_schema_local.sql'
$baseFixturePath = Join-Path $PSScriptRoot 'fixtures/relational_backfill_local.sql'
$permissionFixturePath = Join-Path $PSScriptRoot 'fixtures/relational_permissions_local.sql'
$pantryFixturePath = Join-Path $PSScriptRoot 'fixtures/shopping_transfer_pantry_local.sql'
$auditFixturePath = Join-Path $PSScriptRoot 'fixtures/catalog_admin_local.sql'
$renamePath = Join-Path $repoRoot 'backend/supabase/migrations/202611010009_rename_tables_spanish.sql'
$rehearsalPath = Join-Path $seedDirectory 'recipe_expansion_v4_rehearsal.sql'
$applyPath = Join-Path $seedDirectory 'recipe_expansion_v4.sql'

foreach ($path in @($baseFixturePath, $permissionFixturePath, $pantryFixturePath, $auditFixturePath, $fixturePath, $renamePath, $rehearsalPath, $applyPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required local fixture/seed file is missing: $path" }
}

$initdb = Join-Path $PostgresBin 'initdb.exe'
$pgCtl = Join-Path $PostgresBin 'pg_ctl.exe'
$psql = Join-Path $PostgresBin 'psql.exe'
foreach ($path in @($initdb, $pgCtl, $psql)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "PostgreSQL 18 executable is missing: $path" }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$taskTemp = Join-Path $env:TEMP ('cocinapp-recipe-expansion-' + [guid]::NewGuid().ToString('N'))
$cluster = Join-Path $taskTemp 'data'
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$savedPgEnvironment = @{}
foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
  if ($entry.Key.ToString().StartsWith('PG', [System.StringComparison]::OrdinalIgnoreCase)) {
    $savedPgEnvironment[$entry.Key.ToString()] = $entry.Value
    [System.Environment]::SetEnvironmentVariable($entry.Key.ToString(), $null, 'Process')
  }
}
[System.Environment]::SetEnvironmentVariable('PGCLIENTENCODING', 'UTF8', 'Process')

function Invoke-LocalPsql {
  param([string[]]$Arguments, [switch]$ExpectFailure)
  # Windows PowerShell wraps native stderr (including NOTICE) in error records.
  # SQL success is determined by psql's exit code and ON_ERROR_STOP instead.
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $psql @Arguments 2>&1
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  $message = ($output | Out-String).Trim()
  if ($ExpectFailure) {
    if ($code -eq 0) { throw "Expected local SQL to fail, but it succeeded. Output: $message" }
    return $message
  }
  if ($code -ne 0) { throw "Local PostgreSQL command failed (exit $code): $message" }
  return $message
}

function Invoke-File([string]$Path) {
  Invoke-LocalPsql -Arguments @('-X', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q', '-f', $Path) | Out-Null
}

function Get-Snapshot {
  $query = @'
select concat_ws('|',
  (select count(*) from public.categorias),
  (select count(*) from public.unidades),
  (select count(*) from public.ingredientes),
  (select count(*) from public.etiquetas_dieteticas),
  (select count(*) from public.recetas),
  (select count(*) from public.turnos_comida_receta),
  (select count(*) from public.etiquetas_dieteticas_receta),
  (select count(*) from public.ingredientes_receta),
  (select count(*) from public.pasos_receta),
  (select count(*) from public.ingredientes_paso_receta),
  (select count(*) from public.estado_escritura_receta_admin),
  (select count(*) from public.registro_auditoria));
'@
  Invoke-LocalPsql -Arguments @('-X', '-qAt', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', $query)
}

function Assert-Scalar([string]$Query, [string]$Expected, [string]$Message) {
  $actual = Invoke-LocalPsql -Arguments @('-X', '-qAt', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', $Query)
  if ($actual.Trim() -ne $Expected) { throw "$Message Expected '$Expected', got '$($actual.Trim())'." }
}

try {
  Write-Output "Initializing temporary PostgreSQL 18 cluster on 127.0.0.1:$port"
  & $initdb -D $cluster -U postgres --auth=trust --encoding=UTF8 --no-locale --no-sync | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Temporary PostgreSQL 18 cluster initialization failed.' }
  & $pgCtl -D $cluster -l (Join-Path $taskTemp 'server.log') -o "-h 127.0.0.1 -p $port" -w start
  if ($LASTEXITCODE -ne 0) { throw 'Temporary PostgreSQL cluster failed to start on localhost.' }
  Write-Output 'Installing synthetic legacy/Auth helpers and recipe schema fixture.'

  Invoke-File $baseFixturePath
  Invoke-File $permissionFixturePath
  Invoke-File $pantryFixturePath
  Invoke-File $auditFixturePath
  Invoke-File $fixturePath
  Write-Output 'Applying final Spanish table-name migration.'
  Invoke-File $renamePath

  # Synthetic pre-existing catalog records exercise preservation without production data.
  $sentinelPath = Join-Path $taskTemp 'sentinel.sql'
  @'
insert into public.categorias(id, name, normalized_name) values ('11111111-1111-4111-8111-111111111111','Sentinel category','sentinel category');
insert into public.unidades(id,name,abbreviation,dimension) values ('22222222-2222-4222-8222-222222222222','Sentinel unit','sentinel-u','count');
insert into public.ingredientes(id,name,normalized_name,category_id,base_unit_id) values ('33333333-3333-4333-8333-333333333333','Sentinel ingredient','sentinel ingredient','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222');
insert into public.recetas(id,recipe_source,title,author,description,category_label,total_minutes,portions,difficulty,publication_status)
values ('44444444-4444-4444-8444-444444444444','official','Sentinel recipe','Local fixture','preserve me','Sentinel',5,1,'easy','published');
-- A partial existing catalog forces name/key resolution to preserve master rows.
insert into public.categorias(id,name,normalized_name) values ('66666666-6666-4666-8666-666666666666','Granos y legumbres','granos y legumbres');
insert into public.unidades(id,name,normalized_name,abbreviation,dimension) values ('77777777-7777-4777-8777-777777777777','Gramo','gramo','g','mass');
insert into public.ingredientes(id,name,normalized_name,category_id,base_unit_id) values ('88888888-8888-4888-8888-888888888888','quinoa','quinoa','66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777');
insert into public.etiquetas_dieteticas(tag_key,label,description) values
 ('gluten-free','Gluten free localized',''),('vegetarian','Vegetarian localized',''),('vegan','Vegan localized',''),('lactose-free','Lactose free localized',''),('nut-free','Nut free localized','');
'@ | Set-Content -LiteralPath $sentinelPath -Encoding utf8
  Invoke-File $sentinelPath
  $sentinelBefore = Invoke-LocalPsql -Arguments @('-X', '-qAt', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "select concat_ws('|', id, title, description, version, active, is_deleted) from public.recetas where id='44444444-4444-4444-8444-444444444444'")
  $initial = Get-Snapshot

  Write-Output 'Running rollback rehearsal.'
  Invoke-File $rehearsalPath
  $afterRehearsal = Get-Snapshot
  if ($afterRehearsal.Trim() -ne $initial.Trim()) { throw "Rehearsal changed persisted row counts. Before=$initial After=$afterRehearsal" }

  # Inject a title collision from the new lot; its failed apply must leave all rows untouched.
  $conflictPath = Join-Path $taskTemp 'collision.sql'
  @'
insert into public.recetas(id,recipe_source,title,author,description,category_label,total_minutes,portions,difficulty,publication_status)
values ('55555555-5555-4555-8555-555555555555','official','Porridge de quinoa y manzana','Collision fixture','','Desayuno',1,1,'easy','published');
'@ | Set-Content -LiteralPath $conflictPath -Encoding utf8
  Invoke-File $conflictPath
  $withConflict = Get-Snapshot
  $failure = Invoke-LocalPsql -ExpectFailure -Arguments @('-X', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q', '-f', $applyPath)
  Write-Output 'Verified expected collision failure; checking rollback before clean apply.'
  $afterConflict = Get-Snapshot
  if ($afterConflict.Trim() -ne $withConflict.Trim()) { throw "Failed collision apply changed rows. Before=$withConflict After=$afterConflict" }
  Invoke-LocalPsql -Arguments @('-X', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q', '-c', "delete from public.recetas where id='55555555-5555-4555-8555-555555555555'") | Out-Null

  Invoke-File $applyPath
  Write-Output 'Permanent apply succeeded; checking replay idempotence.'
  Assert-Scalar -Query "select count(*) from public.recetas where id<>'44444444-4444-4444-8444-444444444444' and recipe_source='official' and owner_user_id is null and publication_status='published' and active and not is_deleted and title<>'Sentinel recipe'" -Expected '20' -Message 'Permanent seed did not create exactly 20 published recipes.'
  Assert-Scalar -Query "select count(*) from public.recetas r where r.id<>'44444444-4444-4444-8444-444444444444' and (select count(*) from public.ingredientes_receta i where i.recipe_id=r.id)>0 and (select count(*) from public.pasos_receta s where s.recipe_id=r.id)>0 and exists(select 1 from public.turnos_comida_receta t where t.recipe_id=r.id)" -Expected '20' -Message 'One or more recipes are missing ingredients, steps, or meal shifts.'
  $afterApply = Get-Snapshot
  Invoke-File $applyPath
  $afterReplay = Get-Snapshot
  if ($afterReplay.Trim() -ne $afterApply.Trim()) { throw "Second apply was not idempotent. First=$afterApply Replay=$afterReplay" }
  $sentinelAfter = Invoke-LocalPsql -Arguments @('-X', '-qAt', '-h', '127.0.0.1', '-p', "$port", '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "select concat_ws('|', id, title, description, version, active, is_deleted) from public.recetas where id='44444444-4444-4444-8444-444444444444'")
  if ($sentinelAfter.Trim() -ne $sentinelBefore.Trim()) { throw "Pre-existing sentinel recipe was modified. Before=$sentinelBefore After=$sentinelAfter" }

  Write-Output 'PASS: localhost PostgreSQL 18 rehearsal rolled back all rows; title collision failed without partial writes; permanent seed created 20 complete recipes; replay preserved counts; pre-existing sentinel recipe unchanged.'
  Write-Output "Counts: rehearsal=$initial; applied=$afterApply; replay=$afterReplay"
} finally {
  if (Test-Path -LiteralPath $cluster) {
    & $pgCtl -D $cluster -m immediate -w stop 2>$null
  }
  if (Test-Path -LiteralPath $taskTemp) {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    $resolvedTaskTemp = [System.IO.Path]::GetFullPath($taskTemp)
    $expectedPrefix = $resolvedTempRoot + 'cocinapp-recipe-expansion-'
    if ($resolvedTaskTemp.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedTaskTemp -Recurse -Force
    } else {
      Write-Warning "Leaving unexpected temporary directory untouched: $resolvedTaskTemp"
    }
  }
  foreach ($key in @($savedPgEnvironment.Keys)) { [System.Environment]::SetEnvironmentVariable($key, [string]$savedPgEnvironment[$key], 'Process') }
}
