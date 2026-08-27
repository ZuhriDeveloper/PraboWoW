<#
.SYNOPSIS
    Generates worldserver.conf and authserver.conf from the shipped .dist files.

.DESCRIPTION
    Rewrites only the keys this project needs to change and leaves every other line
    of the .dist untouched, so upgrading the core is a matter of regenerating rather
    than hand-merging a 1400 line config.

    The generated .conf files are gitignored: they are the ones that will eventually
    hold credentials.

    The database connection strings in the .dist already match what
    tools\bootstrap-db.ps1 creates (trinity/trinity on 127.0.0.1:3306), so they are
    only rewritten when a non-default password is supplied.

.PARAMETER EnableMmaps
    Turn pathfinding on. Leave it off until tools\extract-client-data.ps1 has been
    run without -SkipMmaps, otherwise the world loads but every creature and bot
    falls back to straight-line movement.

.EXAMPLE
    .\tools\configure-server.ps1

.EXAMPLE
    .\tools\configure-server.ps1 -EnableMmaps
#>

[CmdletBinding()]
param(
    [string] $ServerDir  = (Join-Path $PSScriptRoot '..\server'),
    [string] $DbUser     = 'trinity',
    [string] $DbPassword = 'trinity',
    [string] $DbHost     = '127.0.0.1',
    [int]    $DbPort     = 3306,
    [switch] $EnableMmaps,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)

$dataDir = Join-Path $ServerDir 'data'
$logsDir = Join-Path $ServerDir 'logs'

# TrinityCore's config parser is happier with forward slashes on Windows.
$dataDirConf = $dataDir -replace '\\', '/'
$logsDirConf = $logsDir -replace '\\', '/'

$mmapsValue = '0'
if ($EnableMmaps) { $mmapsValue = '1' }

function New-DbInfo {
    param([string] $Database)
    return "$DbHost;$DbPort;$DbUser;$DbPassword;$Database"
}

$overrides = @{
    'worldserver.conf' = [ordered]@{
        'DataDir'                = "`"$dataDirConf`""
        'LogsDir'                = "`"$logsDirConf`""
        'LoginDatabaseInfo'      = "`"$(New-DbInfo 'auth')`""
        'WorldDatabaseInfo'      = "`"$(New-DbInfo 'world')`""
        'CharacterDatabaseInfo'  = "`"$(New-DbInfo 'characters')`""
        'HotfixDatabaseInfo'     = "`"$(New-DbInfo 'hotfixes')`""
        # Off until mmaps are generated -- see -EnableMmaps.
        'mmap.enablePathFinding' = $mmapsValue
    }
    'authserver.conf' = [ordered]@{
        'LogsDir'           = "`"$logsDirConf`""
        'LoginDatabaseInfo' = "`"$(New-DbInfo 'auth')`""
    }
}

Write-Host ''
Write-Host '=== PraboWoW server configuration ===' -ForegroundColor Cyan
Write-Host ("  server : {0}" -f $ServerDir)
Write-Host ("  data   : {0}" -f $dataDirConf)
Write-Host ("  mmaps  : {0}" -f $(if ($EnableMmaps) { 'enabled' } else { 'disabled (no mmaps generated yet)' }))
Write-Host ''

if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

foreach ($confName in $overrides.Keys) {
    $distPath = Join-Path $ServerDir "$confName.dist"
    $confPath = Join-Path $ServerDir $confName

    if (-not (Test-Path $distPath)) { throw "missing $distPath -- run tools\build-core.ps1 first" }
    if ((Test-Path $confPath) -and -not $Force) {
        Write-Host ("--> {0} already exists, leaving it alone (use -Force to regenerate)" -f $confName) -ForegroundColor DarkGray
        continue
    }

    $keys = $overrides[$confName]
    $applied = @{}
    $lines = Get-Content $distPath

    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($key in $keys.Keys) {
            # Match the real setting line only: key at the start, optional spaces, '='.
            # Commented documentation lines start with '#' and must survive untouched.
            if ($lines[$i] -match ("^" + [regex]::Escape($key) + "\s*=")) {
                $lines[$i] = "$key = $($keys[$key])"
                $applied[$key] = $true
            }
        }
    }

    $missing = @($keys.Keys | Where-Object { -not $applied.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        throw "$confName.dist has no setting line for: $($missing -join ', '). The core config format changed; update this script."
    }

    Set-Content -Path $confPath -Value $lines -Encoding ASCII
    Write-Host ("--> wrote {0}" -f $confName) -ForegroundColor Green
    foreach ($key in $keys.Keys) {
        $shown = $keys[$key]
        # Never echo the password back to the terminal.
        if ($shown -match ';') { $shown = ($shown -replace ";$([regex]::Escape($DbPassword));", ';********;') }
        Write-Host ("      {0} = {1}" -f $key, $shown) -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host 'Done. Both .conf files are gitignored.' -ForegroundColor Green
Write-Host 'First worldserver run will import the TDB world data -- expect several minutes.'
Write-Host ''
