<#
.SYNOPSIS
    Installs the build toolchain for PraboWoW.

.DESCRIPTION
    Installs the dependencies decided in docs/adr/0002-version-pinning.md.

    Hard lesson from the first run: upstream vendors delete old releases, so a pinned
    version whose download URL has been retired simply 404s. Oracle keeps only the
    current 8.0.x installer, slproweb keeps only the newest OpenSSL, and SourceForge
    answers a direct file request with an HTML interstitial page. Every download here
    therefore goes to a URL that was verified reachable, and every downloaded file is
    checked for its magic bytes before being executed -- an HTML error page must never
    be run as if it were an installer.

    Requires an elevated shell. Run tools\check-prereqs.ps1 afterwards to verify.

.PARAMETER InstallVisualStudio2022
    Opt-in fallback. This project builds on the Visual Studio Insiders toolset that is
    already installed, so no Visual Studio is installed by default. Use this only if
    the Insiders compiler turns out to reject the 2022-era core sources.

.PARAMETER SkipDownloads
    Only run the winget packages; skip the two direct downloads (Boost and MySQL).

.EXAMPLE
    .\tools\install-prereqs.ps1 -WhatIf

.EXAMPLE
    .\tools\install-prereqs.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $InstallVisualStudio2022,
    [switch] $SkipDownloads,
    [string] $BoostVersion     = '1.83.0',
    [string] $BoostInstallDir  = 'C:\local\boost_1_83_0',
    [string] $MySqlVersion     = '8.0.44',
    [string] $MySqlInstallDir  = 'C:\MySQL\MySQL Server 8.0',
    [string] $OpenSslVersion   = '3.6.2'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- winget packages ---------------------------------------------------------
$packages = @(
    [pscustomobject]@{
        Id      = 'Kitware.CMake'
        Version = '3.31.8'
        Name    = 'CMake'
        Why     = 'CMake 4.x rejects cmake_minimum_required < 3.5, which bundled deps still use'
    },
    [pscustomobject]@{
        Id      = 'Ninja-build.Ninja'
        Version = $null
        Name    = 'Ninja'
        Why     = 'CMake 3.31 has no VS2026 generator, and VS2026 18.10 dropped the bundled copy'
    },
    [pscustomobject]@{
        Id      = '7zip.7zip'
        Version = $null
        Name    = '7-Zip'
        Why     = 'the TDB world database is published as a .7z and Windows cannot unpack that natively'
    },
    [pscustomobject]@{
        Id      = 'FireDaemon.OpenSSL'
        Version = $OpenSslVersion
        Name    = "OpenSSL $OpenSslVersion"
        Why     = 'slproweb retired every 3.x installer and now serves only 4.0.x, which this fork cannot compile against; FireDaemon still publishes 3.x with headers'
    }
)

if ($InstallVisualStudio2022) {
    $packages = @(
        [pscustomobject]@{
            Id      = 'Microsoft.VisualStudio.2022.Community'
            Version = $null
            Name    = 'Visual Studio 2022 Community (Desktop C++)'
            Why     = 'opt-in fallback only, if the Insiders toolset breaks the build'
        }
    ) + $packages
}

# --- Helpers -----------------------------------------------------------------
function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileMagic {
    param([string] $Path, [int] $Count = 2)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -lt $Count) { return '' }
        return -join ($buffer | ForEach-Object { [char]$_ })
    } finally {
        $stream.Dispose()
    }
}

<#
    Downloads a file and refuses to return unless it really is the kind of file we
    asked for. This is the guard that the first run lacked: SourceForge answered a
    direct .exe request with a 143 KB HTML page, which was then handed straight to
    Start-Process and failed with a misleading "corrupted and unreadable" error.
#>
function Invoke-VerifiedDownload {
    param(
        [string] $Url,
        [string] $Destination,
        [string] $ExpectedMagic,
        [int]    $MinimumBytes = 1MB
    )

    Write-Host ("    downloading {0}" -f $Url)
    & curl.exe -L --fail --progress-bar -o $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed (curl exit $LASTEXITCODE): $Url" }
    if (-not (Test-Path $Destination)) { throw "download produced no file: $Url" }

    $size = (Get-Item $Destination).Length
    if ($size -lt $MinimumBytes) {
        $kb = [math]::Round($size / 1KB, 1)
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        throw "download is only $kb KB, far too small to be the real file. The vendor most likely served an error or interstitial page: $Url"
    }

    $magic = Get-FileMagic -Path $Destination -Count $ExpectedMagic.Length
    if ($magic -ne $ExpectedMagic) {
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        throw "download does not look like the expected file type (magic '$magic', expected '$ExpectedMagic'): $Url"
    }

    Write-Host ("    verified {0} MB, magic '{1}'" -f [math]::Round($size / 1MB, 1), $magic) -ForegroundColor DarkGray
}

# --- Preflight ---------------------------------------------------------------
Write-Host ''
Write-Host '=== PraboWoW toolchain install ===' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store first.'
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'curl.exe not found. It ships with Windows 10 1803 and later.'
}
if (-not (Test-Elevated)) {
    Write-Host 'This script must run from an ELEVATED PowerShell window.' -ForegroundColor Red
    Write-Host 'Right-click Windows Terminal / PowerShell, choose "Run as administrator", then re-run.' -ForegroundColor Red
    exit 1
}

$failures = New-Object System.Collections.Generic.List[string]

# --- winget installs ---------------------------------------------------------
foreach ($p in $packages) {
    if (-not $PSCmdlet.ShouldProcess($p.Name, 'winget install')) { continue }

    Write-Host ("--> {0}" -f $p.Name) -ForegroundColor Cyan
    Write-Host ("    why: {0}" -f $p.Why) -ForegroundColor DarkGray

    $wingetArgs = @('install', '--id', $p.Id, '--exact',
                    '--accept-package-agreements', '--accept-source-agreements',
                    '--source', 'winget')
    if ($p.Version) { $wingetArgs += @('--version', $p.Version) }

    & winget @wingetArgs
    $code = $LASTEXITCODE

    # Both of these mean "the pinned version is already on the machine", not failure:
    #   -1978335135 (0x8A150061) APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
    #   -1978335189 (0x8A15002B) APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
    if ($code -eq 0) {
        Write-Host ("    {0}: installed" -f $p.Name) -ForegroundColor Green
    } elseif ($code -eq -1978335135 -or $code -eq -1978335189) {
        Write-Host ("    {0}: already present, nothing to do" -f $p.Name) -ForegroundColor DarkGray
    } elseif ($code -eq -1978335209) {
        # NO_APPLICABLE_INSTALLER / no such version. Vendors renumber and retire
        # releases constantly, so show what this package actually offers today
        # instead of leaving the reader to guess.
        Write-Host ("    {0}: version {1} does not exist in this package" -f $p.Name, $p.Version) -ForegroundColor Red
        Write-Host '    versions currently offered:' -ForegroundColor Yellow
        & winget show --id $p.Id --versions --source winget | Select-Object -Skip 2 -First 12 | ForEach-Object { Write-Host ("      " + $_) }
        $failures.Add($p.Name)
    } else {
        Write-Host ("    {0}: FAILED (winget exit {1})" -f $p.Name, $code) -ForegroundColor Red
        $failures.Add($p.Name)
    }
    Write-Host ''
}

# --- Boost -------------------------------------------------------------------
# archives.boost.io is Boost's own archive and serves the installer directly.
# Do NOT use sourceforge.net/projects/.../download -- it returns an HTML page.
$boostShort = $BoostVersion -replace '\.', '_'
$boostExe   = "boost_${boostShort}-msvc-14.3-64.exe"
$boostUrl   = "https://archives.boost.io/release/$BoostVersion/binaries/$boostExe"

Write-Host '--> Boost' -ForegroundColor Cyan
if (Test-Path (Join-Path $BoostInstallDir 'boost\version.hpp')) {
    Write-Host ("    already present at {0}" -f $BoostInstallDir) -ForegroundColor DarkGray
} elseif ($SkipDownloads) {
    Write-Host '    skipped (-SkipDownloads)' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($boostUrl, 'download and install Boost')) {
    try {
        $dest = Join-Path $env:TEMP $boostExe
        Invoke-VerifiedDownload -Url $boostUrl -Destination $dest -ExpectedMagic 'MZ' -MinimumBytes 100MB
        Write-Host ("    installing to {0}" -f $BoostInstallDir)
        Start-Process -FilePath $dest -ArgumentList '/VERYSILENT', "/DIR=$BoostInstallDir" -Wait
        if (-not (Test-Path (Join-Path $BoostInstallDir 'boost\version.hpp'))) {
            throw "installer finished but $BoostInstallDir\boost\version.hpp is missing"
        }
        Write-Host '    Boost: installed' -ForegroundColor Green
    } catch {
        Write-Host ("    Boost: FAILED - {0}" -f $_.Exception.Message) -ForegroundColor Red
        $failures.Add('Boost')
    }
}
Write-Host ''

# --- MySQL -------------------------------------------------------------------
# Oracle blocks scripted access to dev.mysql.com and downloads.mysql.com (403), and
# keeps only the current release of each line on cdn.mysql.com. The zip archive
# avoids the interactive installer entirely and still provides include\mysql.h plus
# lib\libmysql.lib, which is all CMake needs. C:\MySQL\MySQL Server 8.0 is chosen
# deliberately: cmake/macros/FindMySQL.cmake globs "$ENV{SystemDrive}/MySQL/MySQL Server *".
$mysqlZip = "mysql-$MySqlVersion-winx64.zip"
$mysqlUrl = "https://cdn.mysql.com/Downloads/MySQL-8.0/$mysqlZip"

Write-Host '--> MySQL' -ForegroundColor Cyan
if (Test-Path (Join-Path $MySqlInstallDir 'include\mysql.h')) {
    Write-Host ("    already present at {0}" -f $MySqlInstallDir) -ForegroundColor DarkGray
} elseif ($SkipDownloads) {
    Write-Host '    skipped (-SkipDownloads)' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($mysqlUrl, 'download and unpack MySQL')) {
    try {
        $dest = Join-Path $env:TEMP $mysqlZip
        Invoke-VerifiedDownload -Url $mysqlUrl -Destination $dest -ExpectedMagic 'PK' -MinimumBytes 100MB

        $staging = Join-Path $env:TEMP ("mysql-unpack-" + [Guid]::NewGuid().ToString('N'))
        Write-Host '    extracting'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($dest, $staging)

        # The archive contains a single mysql-<version>-winx64 folder; lift its contents up.
        $inner = Get-ChildItem $staging -Directory | Select-Object -First 1
        if (-not $inner) { throw 'archive did not contain the expected top-level folder' }

        $parent = Split-Path $MySqlInstallDir -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Move-Item -Path $inner.FullName -Destination $MySqlInstallDir -Force
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path (Join-Path $MySqlInstallDir 'include\mysql.h'))) {
            throw "unpacked but $MySqlInstallDir\include\mysql.h is missing"
        }
        Write-Host ("    MySQL: unpacked to {0}" -f $MySqlInstallDir) -ForegroundColor Green
        Write-Host '    note: the server is not initialised yet - tools\bootstrap-db.ps1 does that' -ForegroundColor DarkGray
    } catch {
        Write-Host ("    MySQL: FAILED - {0}" -f $_.Exception.Message) -ForegroundColor Red
        $failures.Add('MySQL')
    }
}
Write-Host ''

# --- BOOST_ROOT --------------------------------------------------------------
if (Test-Path (Join-Path $BoostInstallDir 'boost\version.hpp')) {
    $current = [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine')
    if ($current -eq $BoostInstallDir) {
        Write-Host ("--> BOOST_ROOT already set to {0}" -f $BoostInstallDir) -ForegroundColor DarkGray
    } elseif ($PSCmdlet.ShouldProcess('BOOST_ROOT (machine scope)', "set to $BoostInstallDir")) {
        [Environment]::SetEnvironmentVariable('BOOST_ROOT', $BoostInstallDir, 'Machine')
        $env:BOOST_ROOT = $BoostInstallDir
        Write-Host ("--> BOOST_ROOT set to {0}" -f $BoostInstallDir) -ForegroundColor Green
    }
}
Write-Host ''

# --- Summary -----------------------------------------------------------------
if ($failures.Count -gt 0) {
    Write-Host ("{0} item(s) did not complete: {1}" -f $failures.Count, ($failures -join ', ')) -ForegroundColor Yellow
} else {
    Write-Host 'All dependencies processed.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. Close and reopen your shell so PATH and BOOST_ROOT are picked up.'
Write-Host '  2. Run: .\tools\check-prereqs.ps1'
Write-Host ''
