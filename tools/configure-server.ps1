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

.PARAMETER RateDropItemCommon
    Multiplier for grey and white (Poor, Normal) drop chance. Kept separate from the
    tiers below because multiplying vendor trash fills bags without moving progression.

.PARAMETER RateDropItemQuality
    Multiplier for green and above (Uncommon through Artifact) drop chance.

    This governs UNGROUPED loot only. LootTemplate::LootGroup::Roll
    (core/src/server/game/Loot/LootMgr.cpp:395) picks one item from a group by raw
    chance and never consults the quality modifier, and boss and dungeon loot is almost
    entirely grouped. Boosting that means editing loot templates, not this number.

    Neither of these touches Rate.Drop.Item.ReferencedAmount, which multiplies the
    *number* of items rolled from a referenced loot template rather than the chance;
    raising that produces absurd stacks from a single kill.

.PARAMETER IgnoreDoodadLos
    Restore the upstream behaviour where spells pass straight through M2 doodads --
    trees, fences, wagons, crates -- so only WMO buildings block a shot. Left off here
    because that let a player fire from behind a tree. Terrain never blocks either way:
    line of sight is vmap models plus game objects and nothing else, see
    core/src/server/game/Maps/Map.cpp Map::isInLineOfSight.

.PARAMETER RateQuestMoney
    Multiplier for gold from quest rewards. Also applied to the gold handed out in place
    of experience at the level cap, so "quest gold" means one thing at every level.

.EXAMPLE
    .\tools\configure-server.ps1

.EXAMPLE
    .\tools\configure-server.ps1 -Force -RateXp 1 -RateDropItemQuality 1 -RateDropMoney 1
#>

[CmdletBinding()]
param(
    [string] $ServerDir  = (Join-Path $PSScriptRoot '..\server'),
    [string] $DbUser     = 'trinity',
    [string] $DbPassword = 'trinity',
    [string] $DbHost     = '127.0.0.1',
    [int]    $DbPort     = 3306,
    [double] $RateXp                 = 5,
    [double] $RateDropItemCommon     = 1,
    [double] $RateDropItemQuality    = 50,
    [double] $RateDropItemReferenced = 1,
    [double] $RateDropMoney          = 5,
    [double] $RateQuestMoney         = 5,
    [switch] $IgnoreDoodadLos,
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

# Against the upstream default of 1. See the -IgnoreDoodadLos help above; the container
# twin carries the same decision as LOS_IGNORE_M2 in deploy/entrypoint.sh.
$losIgnoreM2 = '0'
if ($IgnoreDoodadLos) { $losIgnoreM2 = '1' }

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
        'LineOfSight.IgnoreM2'   = $losIgnoreM2

        'Rate.XP.Kill'            = $RateXp
        'Rate.XP.Quest'           = $RateXp
        'Rate.XP.Explore'         = $RateXp

        'Rate.Drop.Item.Poor'       = $RateDropItemCommon
        'Rate.Drop.Item.Normal'     = $RateDropItemCommon

        'Rate.Drop.Item.Uncommon'   = $RateDropItemQuality
        'Rate.Drop.Item.Rare'       = $RateDropItemQuality
        'Rate.Drop.Item.Epic'       = $RateDropItemQuality
        'Rate.Drop.Item.Legendary'  = $RateDropItemQuality
        'Rate.Drop.Item.Artifact'   = $RateDropItemQuality

        # Left at 1 by default. LootMgr.cpp:616 passes the rate flag into the referenced
        # template, so items inside still get their own quality modifier -- raising both
        # would apply the boost twice to the same drop.
        'Rate.Drop.Item.Referenced' = $RateDropItemReferenced

        'Rate.Drop.Money'                   = $RateDropMoney
        'Rate.Quest.Money.Reward'           = $RateQuestMoney
        'Rate.Quest.Money.Max.Level.Reward' = $RateQuestMoney
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
$losLabel = 'blocking (trees and props stop spells)'
if ($losIgnoreM2 -eq '1') { $losLabel = 'ignored (upstream default)' }
Write-Host ("  doodads: {0}" -f $losLabel)
Write-Host ("  rates  : xp {0}x | drop grey/white {1}x, green+ {2}x (ungrouped loot only)" -f $RateXp, $RateDropItemCommon, $RateDropItemQuality)
Write-Host ("           money kill {0}x, quest {1}x" -f $RateDropMoney, $RateQuestMoney)
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
