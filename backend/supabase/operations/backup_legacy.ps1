[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
$legacyTables = @('pantry_items', 'personal_data', 'user_roles', 'catalog_core', 'shared_recipes', 'account_status', 'admin_audit_log')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path.TrimEnd('\', '/')

function Fail([string] $Message) { throw $Message }

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    Fail 'OutputDirectory must already exist. Choose a secured directory outside the repository.'
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path.TrimEnd('\', '/')
if ($resolvedOutput.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedOutput.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'OutputDirectory must be outside the repository.'
}

$pgDump = Get-Command pg_dump -ErrorAction SilentlyContinue
$pgRestore = Get-Command pg_restore -ErrorAction SilentlyContinue
if (-not $pgDump -or -not $pgRestore) { Fail 'pg_dump and pg_restore must both be on PATH.' }

# Prefer a libpq service definition; otherwise require explicit host/database/user configuration.
$hasService = -not [string]::IsNullOrWhiteSpace($env:PGSERVICE)
$hasDirectConfig = -not [string]::IsNullOrWhiteSpace($env:PGHOST) -and
    -not [string]::IsNullOrWhiteSpace($env:PGDATABASE) -and
    -not [string]::IsNullOrWhiteSpace($env:PGUSER)
if (-not ($hasService -or $hasDirectConfig)) {
    Fail 'Configure PGSERVICE or PGHOST, PGDATABASE, and PGUSER. Supply passwords only through PGPASSFILE or a protected libpq service file.'
}
if ($hasService) {
    $serviceFile = $env:PGSERVICEFILE
    if ([string]::IsNullOrWhiteSpace($serviceFile)) {
        $serviceFile = Join-Path $env:APPDATA 'postgresql\.pg_service.conf'
    }
    if (-not (Test-Path -LiteralPath $serviceFile -PathType Leaf)) {
        Fail 'PGSERVICE is set, but the libpq service file was not found. Set PGSERVICEFILE or create the standard per-user service file.'
    }
}
if (-not [string]::IsNullOrWhiteSpace($env:PGPASSFILE) -and
    -not (Test-Path -LiteralPath $env:PGPASSFILE -PathType Leaf)) {
    Fail 'PGPASSFILE is set but does not identify an existing file.'
}
if (-not [string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    Fail 'PGPASSWORD is not accepted. Use PGPASSFILE or a protected libpq service file.'
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$base = "cocinapp-legacy-public-$stamp"
$archive = Join-Path $resolvedOutput "$base.dump"
$toc = Join-Path $resolvedOutput "$base.list.txt"
$manifest = Join-Path $resolvedOutput "$base.sha256.txt"
foreach ($path in @($archive, $toc, $manifest)) {
    if (Test-Path -LiteralPath $path) { Fail "Refusing to overwrite existing output: $([IO.Path]::GetFileName($path))" }
}

if ($ValidateOnly) {
    Write-Output 'Validation passed: tools, output location, and libpq configuration are present; no database connection was made.'
    exit 0
}

# Never echo the connection arguments or raw client output, which might contain sensitive connection details.
& $pgDump.Source --no-password --format=custom --schema=public --file=$archive *> $null
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Fail "pg_dump failed with exit code $LASTEXITCODE. Client output was suppressed; inspect local PostgreSQL configuration."
}

$tocLines = & $pgRestore.Source --list $archive 2>$null
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Fail "pg_restore --list failed with exit code $LASTEXITCODE; archive was removed."
}
$tocText = $tocLines -join [Environment]::NewLine
$tocText | Set-Content -LiteralPath $toc -Encoding UTF8
foreach ($table in $legacyTables) {
    # Require both the relation definition and its data entry; a schema-only archive is not enough.
    $definition = '(?m)^\d+;\s+\d+\s+\d+\s+TABLE\s+public\s+' + [Regex]::Escape($table) + '(?:\s|$)'
    $data = '(?m)^\d+;\s+\d+\s+\d+\s+TABLE DATA\s+public\s+' + [Regex]::Escape($table) + '(?:\s|$)'
    if ($tocText -notmatch $definition -or $tocText -notmatch $data) {
        Remove-Item -LiteralPath $archive, $toc -Force -ErrorAction SilentlyContinue
        Fail "Archive TOC is missing required legacy table '$table'; unverified artifacts were removed."
    }
}

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath $manifest -Encoding ASCII
Write-Output "Backup created: $([IO.Path]::GetFileName($archive))"
Write-Output "TOC list: $([IO.Path]::GetFileName($toc))"
Write-Output "SHA-256 manifest: $([IO.Path]::GetFileName($manifest))"
Write-Output 'The archive and TOC checks do not prove that a restore will succeed.'
