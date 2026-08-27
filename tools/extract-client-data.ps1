<#
.SYNOPSIS
    Extracts maps, DBC, vmaps and mmaps from a World of Warcraft 4.3.4 client.

.DESCRIPTION
    Runs the four TrinityCore extractors in the order they depend on each other:

        mapextractor      -> dbc\  maps\  Cameras\
        vmap4extractor    -> Buildings\   (raw)
        vmap4assembler    -> vmaps\       (from Buildings\)
        mmaps_generator   -> mmaps\       (needs dbc\, maps\ and vmaps\)

    Two of these tools ignore any output path and simply write into the current
    working directory, so every step runs with its working directory set to -DataDir
    rather than wherever you happened to invoke the script from.

    Every step is skipped if its output already exists, so the script can be
    re-run after an interruption. Use -Force to redo a step from scratch.

    Nothing here is copied out of the client except derived data. The client itself
    is never modified.

.PARAMETER ClientPath
    Root of the 4.3.4 client (the folder containing Wow.exe and Data\).

.PARAMETER SkipMmaps
    Skip mmaps generation. It is by far the longest step (1-3 hours) and the server
    will start without it, but bots and creatures cannot path properly, so this is
    only for getting to a first login quickly.

.EXAMPLE
    .\tools\extract-client-data.ps1 -ClientPath "C:\Games\Cataclysm-4.3.4.15595-enUS-x64"

.EXAMPLE
    .\tools\extract-client-data.ps1 -ClientPath "C:\Games\..." -SkipMmaps
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ClientPath,
    [string] $DataDir  = (Join-Path $PSScriptRoot '..\server\data'),
    [string] $BuildDir = (Join-Path $PSScriptRoot '..\build'),
    [string] $ServerDir = (Join-Path $PSScriptRoot '..\server'),
    [int]    $Threads = 0,
    [switch] $SkipMmaps,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Native.ps1')

$ExpectedBuild = '15595'

function Resolve-FullPath {
    param([string] $Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$ClientPath = Resolve-FullPath $ClientPath
$DataDir    = Resolve-FullPath $DataDir
$BuildDir   = Resolve-FullPath $BuildDir
$ServerDir  = Resolve-FullPath $ServerDir

if ($Threads -le 0) { $Threads = [Environment]::ProcessorCount }

Write-Host ''
Write-Host '=== PraboWoW client data extraction ===' -ForegroundColor Cyan
Write-Host ("  client : {0}" -f $ClientPath)
Write-Host ("  output : {0}" -f $DataDir)
Write-Host ("  threads: {0}" -f $Threads)
Write-Host ''

# --- Validate the client -----------------------------------------------------
# Getting this wrong produces maps that load but are subtly incorrect, so check the
# build number rather than trusting the folder name.
$wowExe = Join-Path $ClientPath 'Wow.exe'
if (-not (Test-Path $wowExe)) {
    $wowExe = Join-Path $ClientPath 'Wow-64.exe'
}
if (-not (Test-Path $wowExe)) {
    throw "No Wow.exe or Wow-64.exe in $ClientPath -- is this the client root?"
}
if (-not (Test-Path (Join-Path $ClientPath 'Data'))) {
    throw "No Data folder in $ClientPath -- is this the client root?"
}

$fileVersion = (Get-Item $wowExe).VersionInfo.FileVersion
$normalised  = ($fileVersion -replace '[,\s]', '')
if ($normalised -notmatch [regex]::Escape($ExpectedBuild)) {
    throw "Client reports version '$fileVersion', which is not build $ExpectedBuild. This project targets 4.3.4.$ExpectedBuild exactly."
}
Write-Host ("--> client verified: {0} (build {1})" -f (Split-Path $wowExe -Leaf), $ExpectedBuild) -ForegroundColor Green

# --- Locate the extractors ---------------------------------------------------
# Prefer the installed copies; fall back to the build tree so extraction can start
# before `cmake --install` has run.
function Find-Tool {
    param([string] $Name)

    $exe = "$Name.exe"
    foreach ($root in @($ServerDir, $BuildDir)) {
        if (-not (Test-Path $root)) { continue }
        $hit = @(Get-ChildItem -Path $root -Filter $exe -Recurse -File -ErrorAction SilentlyContinue) |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "$exe not found under $ServerDir or $BuildDir. Build the core first: .\tools\build-core.ps1"
}

$mapExtractor  = Find-Tool 'mapextractor'
$vmapExtractor = Find-Tool 'vmap4extractor'
$vmapAssembler = Find-Tool 'vmap4assembler'
$mmapsGenerator = $null
if (-not $SkipMmaps) { $mmapsGenerator = Find-Tool 'mmaps_generator' }

Write-Host ("--> tools  : {0}" -f (Split-Path $mapExtractor -Parent)) -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }

function Test-StepDone {
    param([string] $Folder)
    $path = Join-Path $DataDir $Folder
    if ($Force) { return $false }
    if (-not (Test-Path $path)) { return $false }
    return (@(Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue) | Select-Object -First 1) -ne $null
}

function Invoke-Step {
    param(
        [string]   $Name,
        [string]   $Produces,
        [string]   $Executable,
        [string[]] $Arguments
    )

    if (Test-StepDone -Folder $Produces) {
        Write-Host ("--> {0}: already present in {1}\, skipping (use -Force to redo)" -f $Name, $Produces) -ForegroundColor DarkGray
        return
    }

    Write-Host ("--> {0}" -f $Name) -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # DataDir as the working directory is load-bearing: vmap4extractor,
    # vmap4assembler and mmaps_generator all write relative to it.
    $code = Invoke-Native -Executable $Executable -Arguments $Arguments -WorkingDirectory $DataDir
    $sw.Stop()
    Assert-NativeSuccess -ExitCode $code -What $Name
    Write-Host ("    {0} finished in {1:hh\:mm\:ss}" -f $Name, $sw.Elapsed) -ForegroundColor Green
    Write-Host ''
}

# --- 1. maps + DBC + cameras -------------------------------------------------
# -e 7 = MAP(1) | DBC(2) | Camera(4); -f 1 keeps heights as ints (smaller maps).
Invoke-Step -Name 'mapextractor (dbc, maps, cameras)' -Produces 'maps' `
    -Executable $mapExtractor `
    -Arguments @('-i', $ClientPath, '-o', $DataDir, '-e', '7', '-f', '1')

# --- 2. raw vmap data --------------------------------------------------------
# -l requests precise vector data, which is what the assembler expects.
Invoke-Step -Name 'vmap4extractor (raw buildings)' -Produces 'Buildings' `
    -Executable $vmapExtractor `
    -Arguments @('-l', '-d', $ClientPath)

# --- 3. assemble vmaps -------------------------------------------------------
Invoke-Step -Name 'vmap4assembler (vmaps)' -Produces 'vmaps' `
    -Executable $vmapAssembler `
    -Arguments @('Buildings', 'vmaps')

# --- 4. mmaps ----------------------------------------------------------------
if ($SkipMmaps) {
    Write-Host '--> mmaps: skipped (-SkipMmaps)' -ForegroundColor Yellow
    Write-Host '    The server will start, but pathfinding will not work -- bots and' -ForegroundColor Yellow
    Write-Host '    creatures need mmaps. Re-run without -SkipMmaps before Phase 2.' -ForegroundColor Yellow
} else {
    foreach ($needed in @('dbc', 'maps', 'vmaps')) {
        if (-not (Test-Path (Join-Path $DataDir $needed))) {
            throw "mmaps_generator needs $needed\ in $DataDir but it is missing"
        }
    }
    Write-Host '    mmaps is the long one: expect 1-3 hours.' -ForegroundColor DarkGray
    Invoke-Step -Name 'mmaps_generator (mmaps)' -Produces 'mmaps' `
        -Executable $mmapsGenerator `
        -Arguments @('--threads', "$Threads")
}

# --- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host 'Extraction summary:' -ForegroundColor Cyan
foreach ($folder in @('dbc', 'maps', 'Cameras', 'vmaps', 'mmaps')) {
    $path = Join-Path $DataDir $folder
    if (Test-Path $path) {
        $files = @(Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue)
        $sizeGb = 0
        if ($files.Count -gt 0) {
            $sizeGb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1GB, 2)
        }
        Write-Host ("  {0,-10} {1,7} files  {2,6} GB" -f $folder, $files.Count, $sizeGb)
    } else {
        Write-Host ("  {0,-10} missing" -f $folder) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ("Data is in {0}" -f $DataDir) -ForegroundColor Green
Write-Host 'Point DataDir in worldserver.conf at that folder.'
Write-Host ''
Write-Host 'Buildings\ is intermediate output and can be deleted once vmaps\ exists.' -ForegroundColor DarkGray
Write-Host ''
