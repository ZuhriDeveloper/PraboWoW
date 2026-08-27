<#
.SYNOPSIS
    Configures and builds the PraboWoW core (CPP TrinityCore 4.3.4) with Ninja.

.DESCRIPTION
    CMake is pinned to 3.31 (see docs/adr/0002-version-pinning.md), which has no
    generator for the installed Visual Studio 2026 toolset. Ninja sidesteps that:
    it just uses whatever cl.exe the environment provides -- so this script primes
    the MSVC environment first, then hands a clean environment to CMake.

    Nothing is hardcoded to a Visual Studio path: the Insiders channel moves, and
    18.10 already removed vcvars64.bat and relocated bundled tools once.
    See docs/adr/0003-build-generator.md.

.PARAMETER Clean
    Delete the build directory first and configure from scratch.

.PARAMETER ConfigureOnly
    Run the CMake configure step and stop. Useful for checking dependency detection.

.PARAMETER Prabobots
    Enable the playerbot target (Phase 2 onwards). Off by default so the core can be
    built clean when chasing a regression.

.EXAMPLE
    .\tools\build-core.ps1 -ConfigureOnly

.EXAMPLE
    .\tools\build-core.ps1 -Clean
#>

[CmdletBinding()]
param(
    [string] $SourceDir  = (Join-Path $PSScriptRoot '..\core'),
    [string] $BuildDir   = (Join-Path $PSScriptRoot '..\build'),
    [string] $InstallDir = (Join-Path $PSScriptRoot '..\server'),
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string] $Config = 'Release',
    [int]    $Jobs = 0,
    [switch] $Clean,
    [switch] $ConfigureOnly,
    [switch] $Prabobots
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string] $Path)
    return [System.IO.Path]::GetFullPath($Path)
}

# Invoke-Native lives in lib\Native.ps1 -- it works around two PowerShell 5.1 traps
# around native processes that are subtle enough to be worth stating once, in one
# place, rather than re-deriving per script.
. (Join-Path $PSScriptRoot 'lib\Native.ps1')

$SourceDir  = Resolve-FullPath $SourceDir
$BuildDir   = Resolve-FullPath $BuildDir
$InstallDir = Resolve-FullPath $InstallDir

if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }

Write-Host ''
Write-Host '=== PraboWoW core build ===' -ForegroundColor Cyan
Write-Host ("  source : {0}" -f $SourceDir)
Write-Host ("  build  : {0}" -f $BuildDir)
Write-Host ("  install: {0}" -f $InstallDir)
Write-Host ("  config : {0}   jobs: {1}" -f $Config, $Jobs)
Write-Host ''

if (-not (Test-Path (Join-Path $SourceDir 'CMakeLists.txt'))) {
    throw "No CMakeLists.txt in $SourceDir. Clone the core first (Phase 1, step 1)."
}

# --- Locate the Visual Studio C++ toolchain ----------------------------------
function Get-VisualStudioWithCpp {
    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vsWhere)) { throw 'vswhere.exe not found; is Visual Studio installed?' }

    $raw = & $vsWhere -all -prerelease -products * -format json 2>$null | Out-String
    $parsed = $raw | ConvertFrom-Json

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($inst in @($parsed)) {
        if (-not $inst) { continue }
        if (-not (Test-Path (Join-Path $inst.installationPath 'VC\Tools\MSVC'))) { continue }
        $ver = $null
        [void][Version]::TryParse($inst.installationVersion, [ref]$ver)
        if (-not $ver) { continue }
        # The fork requires MSVC 19.32 == VS 17.2. Anything below that is unusable.
        if ($ver.Major -lt 17) { continue }
        if ($ver.Major -eq 17 -and $ver -lt ([Version]'17.2')) { continue }
        $candidates.Add([pscustomobject]@{ Name = $inst.displayName; Path = $inst.installationPath; Version = $ver })
    }

    if ($candidates.Count -eq 0) { throw 'No Visual Studio install with a C++ toolset at MSVC 19.32 or newer.' }
    return ($candidates | Sort-Object Version -Descending | Select-Object -First 1)
}

$vs = Get-VisualStudioWithCpp
Write-Host ("--> toolchain: {0} {1}" -f $vs.Name, $vs.Version) -ForegroundColor Cyan

# VS2026 18.10 removed the per-architecture vcvars scripts; only vcvarsall.bat
# remains, and it takes the architecture as an argument.
$buildDirVc  = Join-Path $vs.Path 'VC\Auxiliary\Build'
$vcvarsAll   = Join-Path $buildDirVc 'vcvarsall.bat'
$vcvars64    = Join-Path $buildDirVc 'vcvars64.bat'

if (Test-Path $vcvarsAll) {
    $vcvarsInvoke = '"{0}" x64' -f $vcvarsAll
} elseif (Test-Path $vcvars64) {
    $vcvarsInvoke = '"{0}"' -f $vcvars64
} else {
    throw "Neither vcvarsall.bat nor vcvars64.bat found under $buildDirVc"
}

# --- Import the MSVC environment into this PowerShell session ----------------
# cmd is the only thing that can run vcvarsall, so run it there and copy back
# every variable it set. The && below is cmd syntax, not PowerShell.
function Import-VcVars {
    param([string] $Invocation)

    Write-Host ("--> priming MSVC environment: {0}" -f $Invocation) -ForegroundColor Cyan
    $output = & cmd.exe /c "call $Invocation >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) { throw "vcvars invocation failed with exit code $LASTEXITCODE" }

    $imported = 0
    foreach ($line in $output) {
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $name  = $line.Substring(0, $idx)
        $value = $line.Substring($idx + 1)
        Set-Item -Path ("Env:" + $name) -Value $value -ErrorAction SilentlyContinue
        $imported++
    }
    Write-Host ("    imported {0} environment variables" -f $imported) -ForegroundColor DarkGray
}

Import-VcVars -Invocation $vcvarsInvoke

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $cl) { throw 'cl.exe still not on PATH after priming the MSVC environment.' }
Write-Host ("    cl.exe : {0}" -f $cl.Source) -ForegroundColor DarkGray

# --- Locate Ninja ------------------------------------------------------------
# Prefer a standalone install; fall back to whatever VS happens to bundle today.
$ninja = Get-Command ninja -ErrorAction SilentlyContinue
$ninjaPath = ''
if ($ninja) {
    $ninjaPath = $ninja.Source
} else {
    $bundled = Join-Path $vs.Path 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
    if (Test-Path $bundled) { $ninjaPath = $bundled }
}
if (-not $ninjaPath) { throw 'ninja.exe not found. Run: winget install Ninja-build.Ninja' }
Write-Host ("--> ninja  : {0}" -f $ninjaPath) -ForegroundColor Cyan

# --- Clean -------------------------------------------------------------------
if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host ("--> removing {0}" -f $BuildDir) -ForegroundColor Yellow
    Remove-Item -Path $BuildDir -Recurse -Force
}
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
}

# --- Configure ---------------------------------------------------------------
$cmakeArgs = @(
    '-S', $SourceDir,
    '-B', $BuildDir,
    '-G', 'Ninja',
    "-DCMAKE_BUILD_TYPE=$Config",
    "-DCMAKE_INSTALL_PREFIX=$InstallDir",
    "-DCMAKE_MAKE_PROGRAM=$ninjaPath",
    '-DTOOLS=1',
    '-DSCRIPTS=static',
    '-DSERVERS=1'
)

if ($Prabobots) { $cmakeArgs += '-DPRABOBOTS=1' }

# Give CMake explicit hints for the dependencies we pinned by hand, so a wrong
# copy elsewhere on the machine cannot win the search.
# Fall back to the machine scope: a shell opened before install-prereqs.ps1 ran will
# not have BOOST_ROOT in its own environment yet.
$boostRoot = $env:BOOST_ROOT
if (-not $boostRoot) { $boostRoot = [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine') }
if ($boostRoot -and (Test-Path (Join-Path $boostRoot 'boost\version.hpp'))) {
    Write-Host ("--> boost  : {0}" -f $boostRoot) -ForegroundColor Cyan
    $env:BOOST_ROOT = $boostRoot
    $cmakeArgs += "-DBOOST_ROOT=$boostRoot"
}
# OpenSSL may come from slproweb (OpenSSL-Win64) or FireDaemon (its own versioned
# folder), so search both rather than assuming a layout. Headers decide the match.
$sslRoots = New-Object System.Collections.Generic.List[string]
if ($env:OPENSSL_ROOT_DIR) { $sslRoots.Add($env:OPENSSL_ROOT_DIR) }
$sslRoots.Add('C:\Program Files\OpenSSL-Win64')
foreach ($base in @('C:\Program Files', 'C:\Program Files (x86)')) {
    if (Test-Path $base) {
        foreach ($d in (Get-ChildItem $base -Directory -Filter 'FireDaemon OpenSSL*' -ErrorAction SilentlyContinue)) {
            $sslRoots.Add($d.FullName)
        }
    }
}
foreach ($sslCandidate in $sslRoots) {
    if ($sslCandidate -and (Test-Path (Join-Path $sslCandidate 'include\openssl\ssl.h'))) {
        Write-Host ("--> openssl: {0}" -f $sslCandidate) -ForegroundColor Cyan
        $cmakeArgs += "-DOPENSSL_ROOT_DIR=$sslCandidate"
        break
    }
}

# FindMySQL.cmake globs "$ENV{SystemDrive}/MySQL/MySQL Server *", which is exactly
# where install-prereqs.ps1 unpacks the zip -- but point at it explicitly anyway so
# no other copy on the machine can win the search.
foreach ($base in @('C:\MySQL', 'C:\Program Files\MySQL')) {
    if (-not (Test-Path $base)) { continue }
    $hit = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path (Join-Path $_.FullName 'include\mysql.h') } |
             Sort-Object Name -Descending) | Select-Object -First 1
    if ($hit) {
        Write-Host ("--> mysql  : {0}" -f $hit.FullName) -ForegroundColor Cyan
        $cmakeArgs += "-DMYSQL_INCLUDE_DIR=$($hit.FullName)\include"
        $cmakeArgs += "-DMYSQL_LIBRARY=$($hit.FullName)\lib\libmysql.lib"
        break
    }
}

Write-Host '--> configuring' -ForegroundColor Cyan
Write-Host ("    cmake {0}" -f ($cmakeArgs -join ' ')) -ForegroundColor DarkGray
$code = Invoke-Native -Executable 'cmake' -Arguments $cmakeArgs
if ($code -ne 0) {
    Write-Host ''
    Write-Host 'Configure failed. Common causes for this project:' -ForegroundColor Yellow
    Write-Host '  - Boost not found: the prebuilt libs are named -vc143 but MSVC 19.51 makes'
    Write-Host '    CMake look for -vc145. Try adding -DBoost_COMPILER=-vc143 to this script.'
    Write-Host '  - MySQL not found: pass -DMYSQL_INCLUDE_DIR and -DMYSQL_LIBRARY explicitly.'
    Write-Host '  - See docs/adr/0003-build-generator.md for the accepted risks.'
    throw "cmake configure failed with exit code $code"
}

if ($ConfigureOnly) {
    Write-Host ''
    Write-Host 'Configure succeeded. Stopping because -ConfigureOnly was given.' -ForegroundColor Green
    exit 0
}

# --- Build -------------------------------------------------------------------
Write-Host ''
Write-Host ("--> building with {0} jobs (this takes a while)" -f $Jobs) -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
$code = Invoke-Native -Executable 'cmake' -Arguments @("--build", $BuildDir, "--parallel", "$Jobs")
if ($code -ne 0) { throw "build failed with exit code $code" }
$sw.Stop()
Write-Host ("    build finished in {0:hh\:mm\:ss}" -f $sw.Elapsed) -ForegroundColor Green

# --- Install -----------------------------------------------------------------
Write-Host ''
Write-Host ("--> installing to {0}" -f $InstallDir) -ForegroundColor Cyan
$code = Invoke-Native -Executable 'cmake' -Arguments @("--install", $BuildDir)
if ($code -ne 0) { throw "install failed with exit code $code" }

# --- Runtime dependencies the install step does not handle -------------------
# CMake installs the binaries but not these two, and both fail in ways that look
# like something else entirely:
#
#   libmysql.dll  -- authserver/worldserver exit with 0xC0000135 (DLL_NOT_FOUND)
#                    immediately, which reads as a crash rather than a missing file.
#   legacy.dll    -- OpenSSL 3 moved RC4 into the legacy provider, which is not
#                    loaded by default. Without it the world server starts fine and
#                    then dies on ASSERTION FAILED in ARC4 the moment a client
#                    connects, because world packet encryption is RC4.
#                    threadsSetup() sets the provider search path to the worldserver
#                    directory, so the module has to sit right next to the binary.
Write-Host ''
Write-Host '--> copying runtime dependencies' -ForegroundColor Cyan

$runtimeDeps = New-Object System.Collections.Generic.List[string]

foreach ($base in @('C:\MySQL', 'C:\Program Files\MySQL')) {
    if (-not (Test-Path $base)) { continue }
    $hit = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
             ForEach-Object { Join-Path $_.FullName 'lib\libmysql.dll' } |
             Where-Object { Test-Path $_ }) | Select-Object -First 1
    if ($hit) { $runtimeDeps.Add($hit); break }
}

# OpenSSL: copy BOTH the runtime DLLs and the legacy provider module.
#
# Copying libcrypto/libssl is not redundant. Windows searches the application
# directory before PATH, and other software ships its own OpenSSL -- Git for Windows
# puts libcrypto-3-x64.dll in mingw64\bin, and that is what worldserver picked up.
# A provider module only binds to the libcrypto instance it was built against, so
# with the wrong libcrypto loaded the legacy provider silently never registers and
# RC4 fails at the first client connection. Shipping our own next to the binary
# makes the install self-contained and immune to whatever else is on PATH.
foreach ($sslRoot in $sslRoots) {
    if (-not $sslRoot) { continue }
    if (-not (Test-Path (Join-Path $sslRoot 'include\openssl\ssl.h'))) { continue }
    foreach ($pattern in @('libcrypto-*.dll', 'libssl-*.dll', 'legacy.dll')) {
        foreach ($hit in (Get-ChildItem $sslRoot -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue)) {
            $runtimeDeps.Add($hit.FullName)
        }
    }
    break
}

foreach ($dep in $runtimeDeps) {
    $target = Join-Path $InstallDir (Split-Path $dep -Leaf)
    Copy-Item -Path $dep -Destination $target -Force
    Write-Host ("    {0}" -f (Split-Path $dep -Leaf)) -ForegroundColor DarkGray
}
if ($runtimeDeps.Count -eq 0) {
    Write-Host '    none found -- the server will very likely fail to start' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ("Binaries are in {0}" -f $InstallDir)
Write-Host ''
