[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $HostName,
    [ValidateRange(1, 65535)] [int] $Port = 5432,
    [string] $Database = 'postgres',
    [Parameter(Mandatory = $true)] [string] $UserName,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [string] $PostgresBin = 'C:/Program Files/PostgreSQL/18/bin',
    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
foreach ($field in @($HostName, $Database, $UserName)) {
    if ([string]::IsNullOrWhiteSpace($field) -or $field.Contains("`n") -or $field.Contains("`r")) {
        throw 'Connection fields must be nonempty and may not contain line breaks.'
    }
}
$backupScript = Join-Path $PSScriptRoot 'backup_legacy.ps1'
$binPath = (Resolve-Path -LiteralPath $PostgresBin -ErrorAction Stop).Path
foreach ($tool in @('pg_dump.exe', 'pg_restore.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $binPath $tool) -PathType Leaf)) {
        throw "Required PostgreSQL tool is missing from PostgresBin: $tool"
    }
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    throw 'OutputDirectory must already exist.'
}

$saved = @{}
foreach ($name in @('PATH','PGHOST','PGPORT','PGDATABASE','PGUSER','PGSSLMODE','PGSERVICE','PGSERVICEFILE','PGPASSWORD','PGPASSFILE')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$tempDirectory = $null
$securePassword = $null
$password = $null
try {
    $env:PATH = "$binPath;$($saved['PATH'])"
    $env:PGHOST = $HostName
    $env:PGPORT = [string]$Port
    $env:PGDATABASE = $Database
    $env:PGUSER = $UserName
    $env:PGSSLMODE = 'require'
    $env:PGSERVICE = ''
    $env:PGSERVICEFILE = ''
    $env:PGPASSWORD = ''
    $env:PGPASSFILE = ''

    & $backupScript -OutputDirectory $OutputDirectory -ValidateOnly
    if ($ValidateOnly) { return }

    $securePassword = Read-Host 'PostgreSQL password' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if ($password.Contains("`n") -or $password.Contains("`r")) { throw 'Password may not contain line breaks.' }

    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ('cocinapp-pgpass-' + [Guid]::NewGuid().ToString('N'))
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    [void]$security.AddAccessRule($rule)
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($tempDirectory), $security)
    } else {
        [void][IO.Directory]::CreateDirectory($tempDirectory, $security)
    }
    $passFile = Join-Path $tempDirectory 'pgpass.conf'
    function Escape-PgPassField([string] $Value) { $Value.Replace('\', '\\').Replace(':', '\:') }
    $line = (@(
        (Escape-PgPassField $HostName),
        (Escape-PgPassField ([string]$Port)),
        (Escape-PgPassField $Database),
        (Escape-PgPassField $UserName),
        (Escape-PgPassField $password)
    ) -join ':')
    [IO.File]::WriteAllText($passFile, $line + "`n", [Text.UTF8Encoding]::new($false))
    $env:PGPASSFILE = $passFile
    $password = $null
    $line = $null
    & $backupScript -OutputDirectory $OutputDirectory
}
finally {
    if ($null -ne $password) { $password = $null }
    if ($null -ne $securePassword) { $securePassword.Dispose() }
    if ($tempDirectory -and (Test-Path -LiteralPath $tempDirectory)) {
        Remove-Item -LiteralPath (Join-Path $tempDirectory 'pgpass.conf') -Force -ErrorAction SilentlyContinue
        [IO.Directory]::Delete($tempDirectory, $false)
    }
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
