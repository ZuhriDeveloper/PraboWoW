<#
.SYNOPSIS
    Initialises MySQL and prepares the four PraboWoW databases.

.DESCRIPTION
    MySQL was installed from Oracle's zip archive rather than the MySQL Installer
    (see docs/adr/0002-version-pinning.md), so there is no service, no data
    directory and no root account yet. This script does all of that, then creates
    the databases the core expects and fetches the TDB world data.

    Cataclysm needs FOUR databases, not the three a WotLK setup would use:
    auth, characters, world and hotfixes. The hotfixes one is easy to miss.

    The TDB .sql files are placed in the server directory because DBUpdater
    resolves the base file name relative to the worldserver working directory.

    Requires an elevated shell (installing a Windows service).

.PARAMETER DbPassword
    Password for the `trinity` MySQL account. Defaults to `trinity`, which is what
    the shipped .conf.dist files expect. Fine while the server is bound to
    localhost; change it before the server is ever exposed to a network.

.EXAMPLE
    .\tools\bootstrap-db.ps1

.EXAMPLE
    .\tools\bootstrap-db.ps1 -SkipTdb
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $MySqlDir    = 'C:\MySQL\MySQL Server 8.0',
    [string] $MySqlData   = 'C:\MySQL\MySQL Server 8.0\data',
    [string] $ServerDir   = (Join-Path $PSScriptRoot '..\server'),
    [string] $ServiceName = 'PraboWoWMySQL',
    [string] $DbUser      = 'trinity',
    [string] $DbPassword  = 'trinity',
    [int]    $Port        = 3306,
    [string] $TdbVersion  = '434.22011',
    [string] $TdbAsset    = 'TDB_full_434.22011_2022_01_09.7z',
    [switch] $SkipTdb
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Native.ps1')

$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$mysqld    = Join-Path $MySqlDir 'bin\mysqld.exe'
$mysql     = Join-Path $MySqlDir 'bin\mysql.exe'

$Databases = @('auth', 'characters', 'world', 'hotfixes')

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host ''
Write-Host '=== PraboWoW database bootstrap ===' -ForegroundColor Cyan
Write-Host ("  mysql  : {0}" -f $MySqlDir)
Write-Host ("  data   : {0}" -f $MySqlData)
Write-Host ("  service: {0}  port {1}" -f $ServiceName, $Port)
Write-Host ''

if (-not (Test-Path $mysqld)) {
    throw "mysqld.exe not found at $mysqld. Run tools\install-prereqs.ps1 first."
}
if (-not (Test-Elevated)) {
    Write-Host 'This script must run from an ELEVATED PowerShell window (it installs a service).' -ForegroundColor Red
    exit 1
}

# --- my.ini ------------------------------------------------------------------
# Written next to the install rather than into C:\Windows so the whole MySQL setup
# stays self-contained and removable.
$iniPath = Join-Path $MySqlDir 'my.ini'
if (-not (Test-Path $iniPath)) {
    if ($PSCmdlet.ShouldProcess($iniPath, 'write my.ini')) {
        @"
[mysqld]
basedir=$MySqlDir
datadir=$MySqlData
port=$Port
# TrinityCore issues large multi-statement imports when populating the world DB.
max_allowed_packet=1G
innodb_buffer_pool_size=1G
sql_mode=NO_ENGINE_SUBSTITUTION

[client]
port=$Port
"@ | Set-Content -Path $iniPath -Encoding ASCII
        Write-Host ("--> wrote {0}" -f $iniPath) -ForegroundColor Green
    }
} else {
    Write-Host ("--> my.ini already present at {0}" -f $iniPath) -ForegroundColor DarkGray
}

# --- Initialise the data directory -------------------------------------------
$alreadyInitialised = (Test-Path $MySqlData) -and
                      (@(Get-ChildItem $MySqlData -ErrorAction SilentlyContinue) | Select-Object -First 1)

if ($alreadyInitialised) {
    Write-Host ("--> data directory already initialised: {0}" -f $MySqlData) -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($MySqlData, 'initialise MySQL data directory')) {
    Write-Host '--> initialising data directory (root will have an empty password)' -ForegroundColor Cyan
    $code = Invoke-Native -Executable $mysqld -Arguments @(
        "--defaults-file=$iniPath", '--initialize-insecure',
        "--basedir=$MySqlDir", "--datadir=$MySqlData")
    Assert-NativeSuccess -ExitCode $code -What 'mysqld --initialize-insecure'
    Write-Host '    initialised' -ForegroundColor Green
}

# --- Service -----------------------------------------------------------------
# The project was renamed from RenoWoW to PraboWoW after the first bootstrap, so an
# earlier install may have registered the service under the old name. Adopt whatever
# service already points at this mysqld rather than silently registering a second one
# against the same data directory -- two servers on one datadir corrupts it.
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    $existing = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
                  Where-Object { $_.PathName -and $_.PathName -like "*$([regex]::Escape($MySqlDir))*" })
    if ($existing.Count -gt 0) {
        $found = $existing[0].Name
        Write-Host ("--> found an existing service '{0}' already serving {1}" -f $found, $MySqlDir) -ForegroundColor Yellow
        Write-Host    '    Using it instead of registering a second one against the same data directory.'
        Write-Host   ("    To rename it, run elevated:  sc.exe stop {0} ; sc.exe delete {0}" -f $found)
        Write-Host   ("    then re-run this script to register it as {0}." -f $ServiceName)
        $ServiceName = $found
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }
}
if (-not $service) {
    if ($PSCmdlet.ShouldProcess($ServiceName, 'install MySQL service')) {
        Write-Host ("--> installing service {0}" -f $ServiceName) -ForegroundColor Cyan
        $code = Invoke-Native -Executable $mysqld -Arguments @("--install", $ServiceName, "--defaults-file=$iniPath")
        Assert-NativeSuccess -ExitCode $code -What "mysqld --install $ServiceName"
    }
} else {
    Write-Host ("--> service {0} already installed" -f $ServiceName) -ForegroundColor DarkGray
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne 'Running') {
    if ($PSCmdlet.ShouldProcess($ServiceName, 'start service')) {
        Write-Host '--> starting service' -ForegroundColor Cyan
        Start-Service -Name $ServiceName
        # The service reports Running before the server accepts connections, so poll.
        $deadline = (Get-Date).AddSeconds(60)
        do {
            Start-Sleep -Milliseconds 500
            $ping = Invoke-Native -Executable (Join-Path $MySqlDir 'bin\mysqladmin.exe') `
                                  -Arguments @('--user=root', "--port=$Port", '--host=127.0.0.1', 'ping')
        } while ($ping -ne 0 -and (Get-Date) -lt $deadline)
        if ($ping -ne 0) { throw 'MySQL service started but never accepted connections' }
        Write-Host '    accepting connections' -ForegroundColor Green
    }
} elseif ($service) {
    Write-Host '--> service already running' -ForegroundColor DarkGray
}

# --- Databases and account ---------------------------------------------------
# Escaping note: the password is interpolated into SQL, so keep it simple or
# quote-escape it here if you change the default.
$sql = @()
foreach ($db in $Databases) {
    $sql += "CREATE DATABASE IF NOT EXISTS ``$db`` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
}
$sql += "CREATE USER IF NOT EXISTS '$DbUser'@'localhost' IDENTIFIED BY '$DbPassword';"
$sql += "CREATE USER IF NOT EXISTS '$DbUser'@'127.0.0.1' IDENTIFIED BY '$DbPassword';"
foreach ($db in $Databases) {
    $sql += "GRANT ALL PRIVILEGES ON ``$db``.* TO '$DbUser'@'localhost';"
    $sql += "GRANT ALL PRIVILEGES ON ``$db``.* TO '$DbUser'@'127.0.0.1';"
}
$sql += "FLUSH PRIVILEGES;"

if ($PSCmdlet.ShouldProcess('MySQL', 'create databases and trinity account')) {
    Write-Host '--> creating databases and account' -ForegroundColor Cyan
    $sqlFile = Join-Path $env:TEMP 'prabowow-bootstrap.sql'
    $sql -join "`n" | Set-Content -Path $sqlFile -Encoding ASCII
    $code = Invoke-Native -Executable $mysql -Arguments @('--user=root', '--host=127.0.0.1', "--port=$Port", "--execute=source $sqlFile")
    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
    Assert-NativeSuccess -ExitCode $code -What 'database creation'
    Write-Host ("    created: {0}" -f ($Databases -join ', ')) -ForegroundColor Green
}

# --- TDB world data ----------------------------------------------------------
# DBUpdater resolves the world/hotfixes base file names relative to the process
# working directory, so the .sql files belong next to worldserver.exe.
if ($SkipTdb) {
    Write-Host '--> TDB: skipped (-SkipTdb)' -ForegroundColor Yellow
} else {
    $worldSql = Join-Path $ServerDir 'TDB_full_world_434.22011_2022_01_09.sql'
    if (Test-Path $worldSql) {
        Write-Host '--> TDB already extracted' -ForegroundColor DarkGray
    } elseif ($PSCmdlet.ShouldProcess($TdbAsset, 'download and extract TDB')) {
        $sevenZip = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') |
                    Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $sevenZip) {
            throw 'TDB ships as .7z and 7-Zip was not found. Install it (winget install 7zip.7zip) and re-run, or pass -SkipTdb.'
        }

        $url  = "https://github.com/The-Cataclysm-Preservation-Project/TrinityCore/releases/download/TDB$TdbVersion/$TdbAsset"
        $dest = Join-Path $env:TEMP $TdbAsset
        Write-Host ("--> downloading {0}" -f $TdbAsset) -ForegroundColor Cyan
        & curl.exe -L --fail --progress-bar -o $dest $url
        if ($LASTEXITCODE -ne 0) { throw "TDB download failed (curl exit $LASTEXITCODE)" }

        # Same guard as install-prereqs: never unpack something that is not the
        # archive we asked for. '7z' is the 7-Zip magic.
        $magic = -join ([System.IO.File]::ReadAllBytes($dest)[0..1] | ForEach-Object { [char]$_ })
        if ($magic -ne '7z') { throw "downloaded file is not a 7z archive (magic '$magic')" }

        Write-Host ("--> extracting into {0}" -f $ServerDir) -ForegroundColor Cyan
        $code = Invoke-Native -Executable $sevenZip -Arguments @('x', $dest, "-o$ServerDir", '-y')
        Assert-NativeSuccess -ExitCode $code -What '7z extraction'
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
    }
}

# --- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host 'Databases:' -ForegroundColor Cyan
foreach ($db in $Databases) { Write-Host ("  {0}" -f $db) }
Write-Host ''
Write-Host 'TDB files in the server directory:' -ForegroundColor Cyan
$tdbFiles = @(Get-ChildItem $ServerDir -Filter 'TDB_*.sql' -ErrorAction SilentlyContinue)
if ($tdbFiles.Count -eq 0) {
    Write-Host '  none -- the world database cannot auto-populate without them' -ForegroundColor Yellow
} else {
    foreach ($f in $tdbFiles) { Write-Host ("  {0}  ({1} MB)" -f $f.Name, [math]::Round($f.Length / 1MB, 1)) }
}
Write-Host ''
Write-Host 'Next: copy the .conf.dist files, point them at these databases, then run' -ForegroundColor Cyan
Write-Host 'worldserver once -- it imports the base SQL and applies updates itself.'
Write-Host ''
