<#
.SYNOPSIS
    Uploads the extracted client data to the VPS.

.DESCRIPTION
    server\data is 6,0 GB on disk but only 5,2 GB of it is needed at runtime. The
    difference is `Buildings`, the intermediate output of vmap4extractor that
    vmap4assembler has already consumed into `vmaps`; the server never reads it, so it
    is excluded here rather than paying an extra 876 MB of upload.

    This data is client-derived and therefore never in git and never in the Docker image
    (see .gitignore and .dockerignore). The VPS gets it exactly once, through this script.

    Transport, in order of preference:

      1. rsync inside WSL. Resumable (--partial), delta-aware on a re-run, and by far the
         best behaviour for the 5.086 small files in mmaps. This is why WSL is preferred
         even though Windows has a native scp: Windows has no rsync.
      2. tar streamed over ssh. Not resumable, but it is one connection per folder rather
         than one per file, so a dropped link costs one folder instead of the whole run.
         Plain `scp -r` is deliberately not used: 23.000 individual file transfers over a
         home connection is hours of latency alone.

    Upload order is deliberate: dbc, maps and vmaps (2,3 GB) are enough for the server to
    start and for a character to log in. mmaps (2,9 GB) may follow later — the container
    entrypoint decides pathfinding from what is on disk, so it switches on by itself the
    next time the world server restarts.

.PARAMETER Folders
    Which of the data folders to send. Defaults to all four plus Cameras.

.EXAMPLE
    .\tools\upload-client-data.ps1

.EXAMPLE
    # Get the server playable first, leave the 2,9 GB of pathfinding data for tonight.
    .\tools\upload-client-data.ps1 -Folders dbc,maps,vmaps,Cameras
#>

[CmdletBinding()]
param(
    [string]   $VpsHost    = '145.79.10.227',
    [string]   $VpsUser    = 'root',
    [string]   $RemotePath = '/srv/renowow/data',
    [string]   $DataDir,
    [string[]] $Folders    = @('dbc', 'maps', 'vmaps', 'mmaps', 'Cameras'),
    [switch]   $NoWsl
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty inside a param() default when BOTH conditions hold: the script
# declares [CmdletBinding()] and it is launched with `powershell -File`. Either one alone is
# fine, which is why the same pattern in configure-server.ps1 never failed -- that one gets
# run as `tools\configure-server.ps1` from a session. Resolving the default here instead
# sidesteps the combination, and $MyInvocation.MyCommand.Path is populated either way.
if (-not $DataDir) {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $DataDir = Join-Path $scriptDir '..\server\data'
}

$DataDir = [System.IO.Path]::GetFullPath($DataDir)
$target  = "$VpsUser@$VpsHost"

if (-not (Test-Path $DataDir)) {
    throw "$DataDir not found. Run tools\extract-client-data.ps1 first."
}

# --- pick a transport -------------------------------------------------------------------

function Test-WslRsync {
    if ($NoWsl) { return $false }
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $wsl) { return $false }
    # `command -v` writes nothing and exits non-zero when rsync is absent.
    & wsl.exe -e sh -c 'command -v rsync' *> $null
    return ($LASTEXITCODE -eq 0)
}

$useRsync = Test-WslRsync

Write-Host ''
Write-Host '=== PraboWoW client data upload ===' -ForegroundColor Cyan
Write-Host ("  from   : {0}" -f $DataDir)
Write-Host ("  to     : {0}:{1}" -f $target, $RemotePath)
if ($useRsync) {
    Write-Host '  method : rsync via WSL (resumable, delta on re-run)' -ForegroundColor Green
} else {
    Write-Host '  method : tar over ssh (not resumable)' -ForegroundColor Yellow
    Write-Host '           For a resumable upload install rsync in WSL once:' -ForegroundColor DarkGray
    Write-Host '             wsl -e sudo apt-get update; wsl -e sudo apt-get install -y rsync' -ForegroundColor DarkGray
}
Write-Host ''

# --- sizes, so the plan is visible before hours are spent -------------------------------

$plan = @()
foreach ($folder in $Folders) {
    $path = Join-Path $DataDir $folder
    if (-not (Test-Path $path)) {
        Write-Host ("--> {0}: not present locally, skipping" -f $folder) -ForegroundColor DarkGray
        continue
    }
    $measure = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum
    $plan += [pscustomobject]@{
        Name  = $folder
        Path  = $path
        Files = $measure.Count
        GiB   = [math]::Round($measure.Sum / 1GB, 2)
    }
}

if ($plan.Count -eq 0) { throw "nothing to upload from $DataDir" }

$plan | Format-Table -AutoSize
Write-Host ("  total  : {0} GiB in {1} files" -f `
    [math]::Round(($plan | Measure-Object -Property GiB -Sum).Sum, 2), `
    ($plan | Measure-Object -Property Files -Sum).Sum)
Write-Host ''

# --- prepare the destination ------------------------------------------------------------

Write-Host '--> preparing remote directory' -ForegroundColor Cyan
& ssh $target "mkdir -p '$RemotePath'"
if ($LASTEXITCODE -ne 0) { throw "could not prepare $RemotePath on $target (ssh exit $LASTEXITCODE)" }

# --- transfer ----------------------------------------------------------------------------

function ConvertTo-WslPath {
    param([string] $WindowsPath)
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $full.Substring(0, 1).ToLower()
    return '/mnt/' + $drive + ($full.Substring(2) -replace '\\', '/')
}

foreach ($item in $plan) {
    Write-Host ''
    Write-Host ("--> {0} ({1} GiB, {2} files)" -f $item.Name, $item.GiB, $item.Files) -ForegroundColor Cyan
    $started = Get-Date

    if ($useRsync) {
        # Trailing slash on the source: copy the CONTENTS into <remote>/<folder>, so a
        # re-run does not nest the folder inside itself.
        $src = (ConvertTo-WslPath $item.Path) + '/'
        $dst = "${target}:$RemotePath/$($item.Name)/"
        & wsl.exe -e rsync -a --partial --info=progress2 --human-readable $src $dst
    } else {
        # The pipeline runs inside cmd.exe on purpose. PowerShell 5.1 pipes native command
        # output through its OBJECT pipeline as text, which corrupts a binary tar stream;
        # cmd keeps it a byte pipe. ssh -C compresses in flight -- worth it for dbc and
        # maps, near-free for mmaps (already packed).
        $parent = Split-Path -Parent $item.Path
        $inner  = "tar -xf - -C '$RemotePath'"
        & cmd.exe /c "tar -C ""$parent"" -cf - $($item.Name) | ssh -C $target ""$inner"""
    }

    if ($LASTEXITCODE -ne 0) {
        throw "transfer of $($item.Name) failed (exit $LASTEXITCODE). Re-run this script to resume; finished folders are skipped by rsync and re-sent by tar."
    }

    $elapsed = (Get-Date) - $started
    Write-Host ("    done in {0:hh\:mm\:ss}" -f $elapsed) -ForegroundColor Green
}

# --- ownership --------------------------------------------------------------------------

Write-Host ''
Write-Host '--> fixing ownership to uid 1000 (the container user)' -ForegroundColor Cyan
& ssh $target "chown -R 1000:1000 '$RemotePath'"
if ($LASTEXITCODE -ne 0) { throw "chown failed on $target (ssh exit $LASTEXITCODE)" }

Write-Host ''
Write-Host '--> remote contents:' -ForegroundColor Cyan
& ssh $target "du -sh '$RemotePath'/* 2>/dev/null"

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
if ($Folders -notcontains 'mmaps') {
    Write-Host 'mmaps was not uploaded, so pathfinding stays off. Send it later and restart' -ForegroundColor Yellow
    Write-Host 'the world container -- the entrypoint turns pathfinding on by itself once' -ForegroundColor Yellow
    Write-Host 'the folder has files in it.' -ForegroundColor Yellow
}
Write-Host ''
