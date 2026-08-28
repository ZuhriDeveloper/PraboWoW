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

    Pathfinding is decided by looking at server\data\mmaps rather than by a flag.
    An earlier version had an -EnableMmaps switch that defaulted to off, which meant
    regenerating with -Force silently turned pathfinding back off: the world still
    loaded, but every creature and bot moved in straight lines through walls, and the
    symptom showed up nowhere near the cause. What is on disk is the source of truth.

.PARAMETER NoMmaps
    Force pathfinding off even though mmaps are present. For isolating movement
    behaviour during debugging; not something a normal setup needs.

.PARAMETER RateXp
    Multiplier for kill, quest and exploration experience.

.PARAMETER RateDropItem
    Multiplier for item drop chance across every quality tier.
    Note this does NOT touch Rate.Drop.Item.ReferencedAmount, which multiplies the
    *number* of items rolled from a referenced loot template rather than the chance;
    raising that produces absurd stacks from a single kill.

.EXAMPLE
    .\tools\configure-server.ps1

.EXAMPLE
    .\tools\configure-server.ps1 -Force -RateXp 1 -RateDropItem 1 -RateDropMoney 1
#>

[CmdletBinding()]
param(
    [string] $ServerDir  = (Join-Path $PSScriptRoot '..\server'),
    [string] $DbUser     = 'trinity',
    [string] $DbPassword = 'trinity',
    [string] $DbHost     = '127.0.0.1',
    [int]    $DbPort     = 3306,
    [double] $RateXp        = 5,
    [double] $RateDropItem  = 5,
    [double] $RateDropMoney = 5,
    [switch] $NoMmaps,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)

$dataDir = Join-Path $ServerDir 'data'
$logsDir = Join-Path $ServerDir 'logs'

# TrinityCore's config parser is happier with forward slashes on Windows.
$dataDirConf = $dataDir -replace '\\', '/'
$logsDirConf = $logsDir -replace '\\', '/'

# Decide pathfinding from what is actually on disk, not from a flag someone has to
# remember to pass. mmaps_generator writes one .mmtile per tile plus a .mmap per map,
# so "the directory has files in it" is a sound test.
$mmapsDir     = Join-Path $dataDir 'mmaps'
$mmapsPresent = $false
if (Test-Path $mmapsDir) {
    $mmapsPresent = $null -ne (@(Get-ChildItem $mmapsDir -File -ErrorAction SilentlyContinue) | Select-Object -First 1)
}

$mmapsValue  = '0'
$mmapsReason = 'no mmaps in ' + $mmapsDir
if ($NoMmaps) {
    $mmapsReason = 'disabled explicitly with -NoMmaps'
} elseif ($mmapsPresent) {
    $mmapsValue  = '1'
    $mmapsReason = 'mmaps detected'
}

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
        'mmap.enablePathFinding' = $mmapsValue

        'Rate.XP.Kill'            = $RateXp
        'Rate.XP.Quest'           = $RateXp
        'Rate.XP.Explore'         = $RateXp

        'Rate.Drop.Item.Poor'      = $RateDropItem
        'Rate.Drop.Item.Normal'    = $RateDropItem
        'Rate.Drop.Item.Uncommon'  = $RateDropItem
        'Rate.Drop.Item.Rare'      = $RateDropItem
        'Rate.Drop.Item.Epic'      = $RateDropItem
        'Rate.Drop.Item.Legendary' = $RateDropItem
        'Rate.Drop.Item.Artifact'  = $RateDropItem
        'Rate.Drop.Item.Referenced' = $RateDropItem
        'Rate.Drop.Money'          = $RateDropMoney
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
$mmapsLabel = 'off'
if ($mmapsValue -eq '1') { $mmapsLabel = 'on' }
Write-Host ("  mmaps  : {0} ({1})" -f $mmapsLabel, $mmapsReason)
Write-Host ("  rates  : xp {0}x, item drop {1}x, money {2}x" -f $RateXp, $RateDropItem, $RateDropMoney)
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
