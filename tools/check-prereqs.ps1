<#
.SYNOPSIS
    Verifies every build prerequisite for PraboWoW (TrinityCore 4.3.4 + playerbots).

.DESCRIPTION
    Checks Visual Studio, CMake, Git, Boost, OpenSSL, MySQL and free disk space.

    This project targets The-Cataclysm-Preservation-Project/TrinityCore, a fork whose
    codebase is 2022-era (cmake_minimum_required 3.18). Dependencies that are too NEW
    are as much of a problem as ones that are too old, so this script reports three
    states: OK, WARN (usable but risky / untested) and MISSING.

    Read-only: installs nothing, changes nothing.

.EXAMPLE
    .\tools\check-prereqs.ps1
#>

[CmdletBinding()]
param(
    [string] $DiskDrive = 'C',
    [int]    $RequiredFreeGB = 80
)

$ErrorActionPreference = 'Continue'

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string] $Component,
        [string] $Required,
        [string] $Found,
        [ValidateSet('OK', 'WARN', 'MISSING')]
        [string] $Status,
        [string] $Hint
    )
    $results.Add([pscustomobject]@{
        Component = $Component
        Required  = $Required
        Found     = $Found
        Status    = $Status
        Hint      = $Hint
    })
}

function ConvertTo-VersionOrNull {
    param([string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $v = $null
    if ([Version]::TryParse($Text, [ref]$v)) { return $v }
    return $null
}

function Test-VersionAtLeast {
    param([string] $Found, [string] $Minimum)
    $f = ConvertTo-VersionOrNull $Found
    $m = ConvertTo-VersionOrNull $Minimum
    if ($null -eq $f) { return $false }
    if ($null -eq $m) { return $false }
    return ($f -ge $m)
}

Write-Host ''
Write-Host '=== PraboWoW prerequisite check ===' -ForegroundColor Cyan
Write-Host ''

# --- Visual Studio -----------------------------------------------------------
# cmake/compiler/msvc/settings.cmake in this fork hard-requires MSVC 19.32, i.e.
# Visual Studio 2022 17.2. That is a floor, not a ceiling, so VS2026 Insiders
# (MSVC 19.51) passes. This project deliberately builds on Insiders -- see
# docs/adr/0003-build-generator.md. VS Build Tools 2019 (v142) is below the floor
# and is ignored.
$vsInstalls = New-Object System.Collections.Generic.List[object]
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vsWhere) {
    $raw = & $vsWhere -all -prerelease -products * -format json 2>$null | Out-String
    if ($raw.Trim()) {
        $parsed = $null
        try { $parsed = $raw | ConvertFrom-Json } catch { $parsed = $null }
        foreach ($inst in @($parsed)) {
            if (-not $inst) { continue }
            $msvcDir = Join-Path $inst.installationPath 'VC\Tools\MSVC'
            if (Test-Path $msvcDir) {
                $toolsets = @(Get-ChildItem $msvcDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                $vsInstalls.Add([pscustomobject]@{
                    Name     = $inst.displayName
                    Path     = $inst.installationPath
                    Version  = ConvertTo-VersionOrNull $inst.installationVersion
                    Toolsets = ($toolsets -join ', ')
                })
            }
        }
    }
}

$vsUsable = @($vsInstalls | Where-Object {
    $_.Version -and ($_.Version.Major -ge 18 -or ($_.Version.Major -eq 17 -and $_.Version -ge ([Version]'17.2')))
} | Sort-Object Version -Descending)

$script:VsChosen = $null
if ($vsUsable.Count -gt 0) {
    $script:VsChosen = $vsUsable[0]
    Add-Result -Component 'Visual Studio (C++)' -Required '>= VS2022 17.2 (MSVC 19.32)' -Found ("$($script:VsChosen.Name) $($script:VsChosen.Version), MSVC $($script:VsChosen.Toolsets)") -Status 'OK' -Hint ''
} else {
    $foundText = 'no C++ toolset found'
    $best = @($vsInstalls | Sort-Object Version -Descending) | Select-Object -First 1
    if ($best) { $foundText = "only $($best.Name) $($best.Version) - below the MSVC 19.32 floor" }
    Add-Result -Component 'Visual Studio (C++)' -Required '>= VS2022 17.2 (MSVC 19.32)' -Found $foundText -Status 'MISSING' -Hint 'Install a C++ workload ("Desktop development with C++") into a VS2022 or newer install'
}

# --- Ninja -------------------------------------------------------------------
# CMake 3.31 tops out at the "Visual Studio 17 2022" generator, so a VS2026 toolset
# cannot be driven by any VS generator. Ninja does not care about generator support:
# it uses whatever cl.exe the environment provides. See docs/adr/0003-build-generator.md
# Ninja used to ride along in the VS "C++ CMake tools" component, but VS2026 18.10
# dropped it. Install it standalone rather than depending on VS component churn.
$ninjaPath = ''
$ninjaCmd = Get-Command ninja -ErrorAction SilentlyContinue
if ($ninjaCmd) {
    $ninjaPath = $ninjaCmd.Source
} elseif ($script:VsChosen) {
    $bundled = Join-Path $script:VsChosen.Path 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
    if (Test-Path $bundled) { $ninjaPath = $bundled }
}
if ($ninjaPath) {
    $onPath = 'bundled with VS, not on PATH'
    if ($ninjaCmd) { $onPath = 'on PATH' }
    Add-Result -Component 'Ninja' -Required 'any (build generator)' -Found ("$ninjaPath ($onPath)") -Status 'OK' -Hint ''
} else {
    Add-Result -Component 'Ninja' -Required 'any (build generator)' -Found 'not found' -Status 'MISSING' -Hint 'winget install Ninja-build.Ninja  --  required because CMake 3.31 has no VS2026 generator'
}

# --- MSVC environment script -------------------------------------------------
# The Ninja generator has no idea where MSVC lives; the environment must be primed.
# VS2026 18.10 dropped the per-architecture convenience scripts (vcvars64.bat and
# friends), leaving only vcvarsall.bat, which takes the architecture as an argument.
$script:VcVarsAll = ''
$script:VcVarsCmd = ''
if ($script:VsChosen) {
    $buildDir  = Join-Path $script:VsChosen.Path 'VC\Auxiliary\Build'
    $vcvarsAll = Join-Path $buildDir 'vcvarsall.bat'
    $vcvars64  = Join-Path $buildDir 'vcvars64.bat'
    if (Test-Path $vcvarsAll) {
        $script:VcVarsAll = $vcvarsAll
        $script:VcVarsCmd = """$vcvarsAll"" x64"
        Add-Result -Component 'MSVC env script' -Required 'vcvarsall.bat or vcvars64.bat' -Found "vcvarsall.bat x64" -Status 'OK' -Hint ''
    } elseif (Test-Path $vcvars64) {
        $script:VcVarsAll = $vcvars64
        $script:VcVarsCmd = """$vcvars64"""
        Add-Result -Component 'MSVC env script' -Required 'vcvarsall.bat or vcvars64.bat' -Found 'vcvars64.bat' -Status 'OK' -Hint ''
    } else {
        Add-Result -Component 'MSVC env script' -Required 'vcvarsall.bat or vcvars64.bat' -Found 'neither found' -Status 'MISSING' -Hint 'The chosen Visual Studio install has no C++ build environment script; re-run the VS installer and add the "Desktop development with C++" workload'
    }
}

# --- CMake -------------------------------------------------------------------
# CMake 4.x hard-errors on any project declaring cmake_minimum_required < 3.5.
# The core itself declares 3.18, but bundled deps in dep/ are older and may trip it.
# The cost of staying on 3.31 is that its newest VS generator is "Visual Studio 17
# 2022" -- hence Ninja. Do not "fix" a generator error by upgrading to CMake 4.
$cmakeVersion = ''
if (Get-Command cmake -ErrorAction SilentlyContinue) {
    $line = & cmake --version 2>$null | Select-Object -First 1
    if ($line -match '(\d+\.\d+\.\d+)') { $cmakeVersion = $Matches[1] }
}
if (-not $cmakeVersion) {
    Add-Result -Component 'CMake' -Required '3.24 - 3.31' -Found 'not on PATH' -Status 'MISSING' -Hint 'winget install Kitware.CMake --version 3.31.8  --  pin to 3.x, do NOT take 4.x'
} elseif (-not (Test-VersionAtLeast -Found $cmakeVersion -Minimum '3.24.0')) {
    Add-Result -Component 'CMake' -Required '3.24 - 3.31' -Found $cmakeVersion -Status 'MISSING' -Hint 'winget install Kitware.CMake --version 3.31.8'
} elseif ((ConvertTo-VersionOrNull $cmakeVersion).Major -ge 4) {
    Add-Result -Component 'CMake' -Required '3.24 - 3.31' -Found $cmakeVersion -Status 'WARN' -Hint 'CMake 4.x rejects projects declaring cmake_minimum_required < 3.5, which bundled deps in dep/ may still do. Safer: winget install Kitware.CMake --version 3.31.8'
} else {
    Add-Result -Component 'CMake' -Required '3.24 - 3.31' -Found $cmakeVersion -Status 'OK' -Hint ''
}

# --- Git ---------------------------------------------------------------------
$gitVersion = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
    $raw = & git --version 2>$null
    if ($raw -match '(\d+\.\d+\.\d+)') { $gitVersion = $Matches[1] }
}
if ($gitVersion) {
    Add-Result -Component 'Git' -Required 'any recent' -Found $gitVersion -Status 'OK' -Hint ''
} else {
    Add-Result -Component 'Git' -Required 'any recent' -Found 'not on PATH' -Status 'MISSING' -Hint 'winget install Git.Git'
}

# --- Boost -------------------------------------------------------------------
$boostVersion = ''
$boostRoot    = ''
$boostCandidates = New-Object System.Collections.Generic.List[string]
if ($env:BOOST_ROOT) { $boostCandidates.Add($env:BOOST_ROOT) }
foreach ($base in @('C:\local', 'C:\Boost', 'C:\Program Files')) {
    if (Test-Path $base) {
        foreach ($d in (Get-ChildItem -Path $base -Directory -Filter 'boost*' -ErrorAction SilentlyContinue)) {
            $boostCandidates.Add($d.FullName)
        }
    }
}
foreach ($cand in $boostCandidates) {
    $hpp = Join-Path $cand 'boost\version.hpp'
    if (Test-Path $hpp) {
        $line = Select-String -Path $hpp -Pattern 'define\s+BOOST_LIB_VERSION\s+"(.+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($line) {
            $boostRoot    = $cand
            $boostVersion = $line.Matches[0].Groups[1].Value -replace '_', '.'
            break
        }
    }
}
# BOOST_LIB_VERSION reads like 1_80 -- normalise to 1.80.0 before comparing
$boostComparable = $boostVersion
if ($boostComparable -and ($boostComparable.Split('.').Count -eq 2)) { $boostComparable = "$boostComparable.0" }
if (Test-VersionAtLeast -Found $boostComparable -Minimum '1.78.0') {
    Add-Result -Component 'Boost' -Required '>= 1.78 (msvc-14.3-64)' -Found "$boostVersion at $boostRoot" -Status 'OK' -Hint ''
} else {
    $bf = 'not found'
    if ($boostVersion) { $bf = "$boostVersion at $boostRoot - too old" }
    Add-Result -Component 'Boost' -Required '>= 1.78 (msvc-14.3-64)' -Found $bf -Status 'MISSING' -Hint 'Run tools\install-prereqs.ps1 -- it downloads from archives.boost.io. Do NOT use the SourceForge /download link: it returns an HTML page, not the installer.'
}

# --- BOOST_ROOT env var ------------------------------------------------------
# A shell started before the variable was set still has a stale environment, so
# consult the machine scope too rather than reporting a false failure.
$boostEnvProcess = $env:BOOST_ROOT
$boostEnvMachine = [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine')
$boostEnvValue   = $boostEnvProcess
$boostEnvStale   = $false
if (-not $boostEnvValue -and $boostEnvMachine) {
    $boostEnvValue = $boostEnvMachine
    $boostEnvStale = $true
}

$boostEnvOk = $false
if ($boostEnvValue) { $boostEnvOk = Test-Path (Join-Path $boostEnvValue 'boost\version.hpp') }

if ($boostEnvOk -and $boostEnvStale) {
    Add-Result -Component 'BOOST_ROOT env var' -Required 'points at Boost' -Found "$boostEnvValue (machine scope; this shell has not picked it up yet)" -Status 'WARN' -Hint 'Harmless for the build scripts, which read the machine scope directly. Open a new shell to get it in your interactive session.'
} elseif ($boostEnvOk) {
    Add-Result -Component 'BOOST_ROOT env var' -Required 'points at Boost' -Found $boostEnvValue -Status 'OK' -Hint ''
} else {
    $bef = 'not set'
    if ($boostEnvValue) { $bef = "$boostEnvValue (no boost\version.hpp there)" }
    Add-Result -Component 'BOOST_ROOT env var' -Required 'points at Boost' -Found $bef -Status 'MISSING' -Hint 'Run tools\install-prereqs.ps1 elevated -- it sets BOOST_ROOT at machine scope'
}

# --- OpenSSL -----------------------------------------------------------------
# TrinityCore supports the 1.1.x and 3.x lines. OpenSSL 4.x is far newer than this
# fork and its API changes will not compile. The "Light" packages ship no headers.
$sslVersion = ''
$sslRoot    = ''
$sslHasHeaders = $false
$sslCandidates = New-Object System.Collections.Generic.List[string]
if ($env:OPENSSL_ROOT_DIR) { $sslCandidates.Add($env:OPENSSL_ROOT_DIR) }
foreach ($p in @('C:\Program Files\OpenSSL-Win64', 'C:\Program Files\OpenSSL', 'C:\OpenSSL-Win64')) {
    $sslCandidates.Add($p)
}
# FireDaemon is the fallback vendor for OpenSSL 3.x now that slproweb serves only 4.x;
# it installs under its own versioned folder name.
foreach ($base in @('C:\Program Files', 'C:\Program Files (x86)')) {
    if (Test-Path $base) {
        foreach ($d in (Get-ChildItem $base -Directory -Filter 'FireDaemon OpenSSL*' -ErrorAction SilentlyContinue)) {
            $sslCandidates.Add($d.FullName)
        }
    }
}
foreach ($cand in $sslCandidates) {
    if (-not $cand) { continue }
    # Headers are what actually matter -- a runtime-only install is useless to CMake.
    $header = Join-Path $cand 'include\openssl\ssl.h'
    if (-not (Test-Path $header)) { continue }

    $sslRoot = $cand
    $sslHasHeaders = $true

    $exe = Join-Path $cand 'bin\openssl.exe'
    if (Test-Path $exe) {
        $raw = & $exe version 2>$null
        if ($raw -match 'OpenSSL\s+(\d+\.\d+\.\d+)') { $sslVersion = $Matches[1] }
    }
    if (-not $sslVersion) {
        # No binary to ask, so read the version straight out of the headers.
        $vh = Join-Path $cand 'include\openssl\opensslv.h'
        if (Test-Path $vh) {
            $m = Select-String -Path $vh -Pattern 'OPENSSL_VERSION_STR\s+"(\d+\.\d+\.\d+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m) { $sslVersion = $m.Matches[0].Groups[1].Value }
        }
    }
    break
}
# Nothing with headers was found; fall back to reporting a runtime-only install.
if (-not $sslRoot) {
    foreach ($cand in $sslCandidates) {
        if (-not $cand) { continue }
        $exe = Join-Path $cand 'bin\openssl.exe'
        if (Test-Path $exe) {
            $sslRoot = $cand
            $raw = & $exe version 2>$null
            if ($raw -match 'OpenSSL\s+(\d+\.\d+\.\d+)') { $sslVersion = $Matches[1] }
            break
        }
    }
}
$sslMajor = 0
$sslParsed = ConvertTo-VersionOrNull $sslVersion
if ($sslParsed) { $sslMajor = $sslParsed.Major }

if (-not $sslVersion) {
    Add-Result -Component 'OpenSSL' -Required '3.x with headers' -Found 'not found' -Status 'MISSING' -Hint 'winget install FireDaemon.OpenSSL --version 3.6.2  --  slproweb retired all 3.x installers and now serves only 4.x, which this fork cannot compile against'
} elseif (-not $sslHasHeaders) {
    Add-Result -Component 'OpenSSL' -Required '3.x with headers' -Found "$sslVersion - LIGHT build, no headers" -Status 'MISSING' -Hint 'winget install FireDaemon.OpenSSL --version 3.6.2'
} elseif ($sslMajor -ge 4) {
    Add-Result -Component 'OpenSSL' -Required '3.x with headers' -Found "$sslVersion - too new" -Status 'WARN' -Hint 'This fork targets the OpenSSL 1.1/3.x API. Install 3.x instead: winget install FireDaemon.OpenSSL --version 3.6.2'
} elseif ($sslMajor -eq 3) {
    Add-Result -Component 'OpenSSL' -Required '3.x with headers' -Found "$sslVersion at $sslRoot" -Status 'OK' -Hint ''
} else {
    Add-Result -Component 'OpenSSL' -Required '3.x with headers' -Found "$sslVersion - old (1.1.x line)" -Status 'WARN' -Hint 'Works with TrinityCore but out of support upstream. Prefer 3.x: winget install FireDaemon.OpenSSL --version 3.6.2'
}

# --- MySQL -------------------------------------------------------------------
# 8.0.34+ is the floor; 8.4 changed auth plugin defaults and reshuffled the client
# libraries, and this 2022-era fork has never been tested against it.
#
# The server is installed from Oracle's zip archive rather than the MySQL Installer,
# so nothing lands on PATH and there is no registry entry. Search the same roots that
# cmake/macros/FindMySQL.cmake globs, and judge an install by its headers -- those are
# what the build actually consumes.
$mysqlRoot    = ''
$mysqlVersion = ''
$mysqlHasDev  = $false

$mysqlCandidates = New-Object System.Collections.Generic.List[string]
foreach ($base in @('C:\MySQL', 'C:\Program Files\MySQL', 'C:\Program Files (x86)\MySQL')) {
    if (Test-Path $base) {
        foreach ($d in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
            $mysqlCandidates.Add($d.FullName)
        }
    }
}
foreach ($cand in $mysqlCandidates) {
    if (-not (Test-Path (Join-Path $cand 'include\mysql.h'))) { continue }
    $mysqlRoot   = $cand
    $mysqlHasDev = $true
    $vh = Join-Path $cand 'include\mysql_version.h'
    if (Test-Path $vh) {
        $m = Select-String -Path $vh -Pattern 'MYSQL_SERVER_VERSION\s+"(\d+\.\d+\.\d+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { $mysqlVersion = $m.Matches[0].Groups[1].Value }
    }
    break
}
# Last resort: a client on PATH from some other install.
if (-not $mysqlVersion -and (Get-Command mysql -ErrorAction SilentlyContinue)) {
    $raw = & mysql --version 2>$null
    if ($raw -match 'Ver\s+(\d+\.\d+\.\d+)') { $mysqlVersion = $Matches[1] }
}

$mysqlParsed = ConvertTo-VersionOrNull $mysqlVersion
$mysqlHint   = 'Run tools\install-prereqs.ps1 -- it fetches the 8.0 zip from cdn.mysql.com and unpacks it to C:\MySQL\MySQL Server 8.0'

if (-not $mysqlParsed) {
    Add-Result -Component 'MySQL' -Required '8.0.34 - 8.0.x' -Found 'not found' -Status 'MISSING' -Hint $mysqlHint
} elseif (-not (Test-VersionAtLeast -Found $mysqlVersion -Minimum '8.0.34')) {
    Add-Result -Component 'MySQL' -Required '8.0.34 - 8.0.x' -Found "$mysqlVersion - too old" -Status 'MISSING' -Hint $mysqlHint
} elseif ($mysqlParsed -ge ([Version]'8.4.0')) {
    Add-Result -Component 'MySQL' -Required '8.0.34 - 8.0.x' -Found "$mysqlVersion - newer than tested" -Status 'WARN' -Hint '8.4 dropped mysql_native_password and reshuffled the client libs. Prefer the 8.0 line.'
} else {
    Add-Result -Component 'MySQL' -Required '8.0.34 - 8.0.x' -Found "$mysqlVersion at $mysqlRoot" -Status 'OK' -Hint ''
}

# --- MySQL dev components (headers + import library) --------------------------
if ($mysqlHasDev) {
    $libOk = (Test-Path (Join-Path $mysqlRoot 'lib\libmysql.lib'))
    if ($libOk) {
        Add-Result -Component 'MySQL dev files' -Required 'mysql.h + libmysql.lib' -Found $mysqlRoot -Status 'OK' -Hint ''
    } else {
        Add-Result -Component 'MySQL dev files' -Required 'mysql.h + libmysql.lib' -Found "headers only at $mysqlRoot" -Status 'MISSING' -Hint 'lib\libmysql.lib is missing; the install is incomplete'
    }
} else {
    Add-Result -Component 'MySQL dev files' -Required 'mysql.h + libmysql.lib' -Found 'mysql.h not found' -Status 'MISSING' -Hint $mysqlHint
}

# --- Free disk space ---------------------------------------------------------
$freeGB = 0
try {
    $drive  = Get-PSDrive -Name $DiskDrive -ErrorAction Stop
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
} catch {
    $freeGB = 0
}
if ($freeGB -ge $RequiredFreeGB) {
    Add-Result -Component "Free disk on ${DiskDrive}:" -Required ">= $RequiredFreeGB GB" -Found "$freeGB GB" -Status 'OK' -Hint ''
} else {
    Add-Result -Component "Free disk on ${DiskDrive}:" -Required ">= $RequiredFreeGB GB" -Found "$freeGB GB" -Status 'MISSING' -Hint 'Source plus build is roughly 15 GB; extracted client data (mmaps dominate) adds another 40-50 GB'
}

# --- Report ------------------------------------------------------------------
$results | Format-Table -AutoSize -Property Component, Required, Found, Status | Out-String | Write-Host

if ($vsInstalls.Count -gt 0) {
    Write-Host 'C++-capable Visual Studio installs detected:' -ForegroundColor DarkGray
    foreach ($v in $vsInstalls) {
        Write-Host ("  - {0}  {1}  (MSVC {2})" -f $v.Name, $v.Version, $v.Toolsets) -ForegroundColor DarkGray
    }
    Write-Host ''
}

$missing = @($results | Where-Object { $_.Status -eq 'MISSING' })
$warned  = @($results | Where-Object { $_.Status -eq 'WARN' })

foreach ($group in @(
    [pscustomobject]@{ Items = $missing; Label = 'must be fixed'; Colour = 'Red' },
    [pscustomobject]@{ Items = $warned;  Label = 'risky, review'; Colour = 'Yellow' }
)) {
    if ($group.Items.Count -eq 0) { continue }
    Write-Host ("{0} item(s) {1}:" -f $group.Items.Count, $group.Label) -ForegroundColor $group.Colour
    Write-Host ''
    foreach ($f in $group.Items) {
        Write-Host ("  - " + $f.Component) -ForegroundColor $group.Colour
        Write-Host ("      required : " + $f.Required)
        Write-Host ("      found    : " + $f.Found)
        if ($f.Hint) { Write-Host ("      fix      : " + $f.Hint) }
        Write-Host ''
    }
}

if ($missing.Count -eq 0) {
    if ($warned.Count -eq 0) {
        Write-Host 'All prerequisites satisfied. Ready for Phase 1 (build core).' -ForegroundColor Green
    } else {
        Write-Host 'No blockers, but review the warnings above before building.' -ForegroundColor Yellow
    }
    exit 0
}

exit 1
