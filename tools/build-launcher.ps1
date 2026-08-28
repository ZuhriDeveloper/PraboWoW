<#
.SYNOPSIS
    Builds PraboWoW.exe, the one-click launcher handed to players.

.DESCRIPTION
    Compiles tools\launcher\PraboWoW.cpp into a single self-contained executable and stages
    it in dist\ together with the two TrinityCore client tools players need.

    Statically linked (/MT) on purpose: players run this on their own machines, and a
    missing Visual C++ redistributable would produce a dialog about a missing DLL that says
    nothing about the actual cause. The cost is a slightly larger binary, which is
    irrelevant at this size.

    The realm address is baked in at compile time rather than read from a config file, so
    there is one fewer file to explain and one fewer thing a player can get wrong. Rebuild
    with -Realm to point a bundle at a different server.

.PARAMETER Realm
    Hostname the client is pointed at. Baked into the binary.

.EXAMPLE
    .\tools\build-launcher.ps1

.EXAMPLE
    .\tools\build-launcher.ps1 -Realm 10.0.0.5
#>

[CmdletBinding()]
param(
    [string] $Realm,
    [string] $OutDir,
    [string] $ServerDir
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty inside a param() default when a [CmdletBinding()] script is launched
# with `powershell -File`. Resolving the defaults here works under every invocation style;
# see tools\upload-client-data.ps1 for the full explanation.
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $Realm)     { $Realm     = 'wow.zuhri-dev.com' }
if (-not $OutDir)    { $OutDir    = Join-Path $scriptDir '..\dist' }
if (-not $ServerDir) { $ServerDir = Join-Path $scriptDir '..\server' }

$OutDir    = [System.IO.Path]::GetFullPath($OutDir)
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$source    = Join-Path $scriptDir 'launcher\PraboWoW.cpp'

if (-not (Test-Path $source)) { throw "missing $source" }

Write-Host ''
Write-Host '=== PraboWoW launcher build ===' -ForegroundColor Cyan
Write-Host ("  realm  : {0}" -f $Realm)
Write-Host ("  output : {0}" -f $OutDir)
Write-Host ''

# --- MSVC environment --------------------------------------------------------------------
# Same approach as tools\build-core.ps1: find the newest install with a C++ toolset through
# vswhere rather than hardcoding a path, because VS Insiders relocates its bundled tools
# between updates.

function Get-VisualStudioWithCpp {
    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vsWhere)) { throw 'vswhere.exe not found; is Visual Studio installed?' }

    $parsed = & $vsWhere -all -prerelease -products * -format json 2>$null | Out-String | ConvertFrom-Json

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($inst in @($parsed)) {
        if (-not $inst) { continue }
        if (-not (Test-Path (Join-Path $inst.installationPath 'VC\Tools\MSVC'))) { continue }
        $ver = $null
        [void][Version]::TryParse($inst.installationVersion, [ref]$ver)
        if (-not $ver) { continue }
        $candidates.Add([pscustomobject]@{ Name = $inst.displayName; Path = $inst.installationPath; Version = $ver })
    }

    if ($candidates.Count -eq 0) { throw 'No Visual Studio install with a C++ toolset found.' }
    return ($candidates | Sort-Object Version -Descending | Select-Object -First 1)
}

$vs = Get-VisualStudioWithCpp
Write-Host ("--> toolchain: {0} {1}" -f $vs.Name, $vs.Version) -ForegroundColor Cyan

$buildDirVc = Join-Path $vs.Path 'VC\Auxiliary\Build'
$vcvarsAll  = Join-Path $buildDirVc 'vcvarsall.bat'
$vcvars64   = Join-Path $buildDirVc 'vcvars64.bat'

if (Test-Path $vcvarsAll) {
    $vcvarsInvoke = '"{0}" x64' -f $vcvarsAll
} elseif (Test-Path $vcvars64) {
    $vcvarsInvoke = '"{0}"' -f $vcvars64
} else {
    throw "Neither vcvarsall.bat nor vcvars64.bat found under $buildDirVc"
}

Write-Host ("--> priming MSVC environment: {0}" -f $vcvarsInvoke) -ForegroundColor Cyan
$envDump = & cmd.exe /c "call $vcvarsInvoke >nul 2>&1 && set"
if ($LASTEXITCODE -ne 0) { throw "vcvars invocation failed with exit code $LASTEXITCODE" }
foreach ($line in $envDump) {
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    Set-Item -Path ("Env:" + $line.Substring(0, $idx)) -Value $line.Substring($idx + 1) -ErrorAction SilentlyContinue
}

# --- compile -----------------------------------------------------------------------------

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$objDir = Join-Path $OutDir 'obj'
if (-not (Test-Path $objDir)) { New-Item -ItemType Directory -Path $objDir -Force | Out-Null }

$exePath = Join-Path $OutDir 'PraboWoW.exe'

# /MT static CRT, /O2 size-and-speed, /EHsc standard exception model. The realm is passed as
# a macro; the extra quoting is because it has to survive both PowerShell and cl.exe.
$clArgs = @(
    '/nologo', '/std:c++17', '/O2', '/MT', '/EHsc', '/DNDEBUG', '/W4',
    ('/DPRABOWOW_REALM=\"{0}\"' -f $Realm),
    $source,
    ('/Fo{0}\' -f $objDir),
    ('/Fe:{0}' -f $exePath),
    '/link', 'kernel32.lib'
)

Write-Host '--> compiling' -ForegroundColor Cyan
& cl.exe @clArgs
if ($LASTEXITCODE -ne 0) { throw "cl.exe failed with exit code $LASTEXITCODE" }

Remove-Item $objDir -Recurse -Force -ErrorAction SilentlyContinue

# --- stage the bundle --------------------------------------------------------------------
# The TrinityCore tools come from the local install rather than being rebuilt here;
# tools\build-core.ps1 already put them in server\.

Copy-Item (Join-Path $scriptDir 'launcher\BACA-DULU.txt') (Join-Path $OutDir 'BACA-DULU.txt') -Force

# The OpenSSL pair is NOT optional, and leaving it out fails in the most misleading way
# possible: it works on this machine and nowhere else. client_launcher_64.exe imports
# libssl-3-x64.dll and libcrypto-3-x64.dll (confirmed with dumpbin /dependents), and a
# developer box happens to have libcrypto on PATH because Git for Windows ships one in
# mingw64\bin. A player without Git gets "libcrypto-3-x64.dll was not found" instead.
# This is the client-side twin of the server-side trap in docs/phase-1-checklist.md.
$bundled = @(
    'client_launcher_64.exe',
    'client_patcher_64.dll',
    'libssl-3-x64.dll',
    'libcrypto-3-x64.dll'
)
$missing = @()
foreach ($file in $bundled) {
    $src = Join-Path $ServerDir $file
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $OutDir $file) -Force
    } else {
        $missing += $file
    }
}

# Both TrinityCore tools are built against the dynamic CRT, so they need the Visual C++
# runtime. PraboWoW.exe itself is /MT and does not, which is exactly why this gap stays
# invisible until a player without the redistributable installed runs the bundle.
# App-local deployment of these three is a supported Microsoft deployment model and saves
# every player from being told to download and run an installer first.
$crtNames = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$crtSource = Get-ChildItem (Join-Path $vs.Path 'VC\Redist\MSVC') -Recurse -Include $crtNames -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -match '\\x64\\' -and $_.FullName -notmatch 'onecore|debug|spectre' }

foreach ($name in $crtNames) {
    $file = $crtSource | Where-Object { $_.Name -eq $name } |
            Sort-Object { $_.VersionInfo.FileVersionRaw } -Descending | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName (Join-Path $OutDir $name) -Force
    } else {
        $missing += $name
    }
}

Write-Host ''
Write-Host ("--> {0}" -f $exePath) -ForegroundColor Green
Get-ChildItem $OutDir -File | Select-Object Name, @{ n = 'KiB'; e = { [math]::Round($_.Length / 1KB) } } | Format-Table -AutoSize

if ($missing.Count -gt 0) {
    Write-Host ("WARNING: not found in {0}: {1}" -f $ServerDir, ($missing -join ', ')) -ForegroundColor Yellow
    Write-Host '         Run tools\build-core.ps1 first, or copy them in by hand.' -ForegroundColor Yellow
    Write-Host ''
}

Write-Host 'Send the whole dist\ folder to players. It contains no Blizzard game data --' -ForegroundColor Cyan
Write-Host 'each player supplies their own 4.3.4.15595 client.' -ForegroundColor Cyan
Write-Host ''
