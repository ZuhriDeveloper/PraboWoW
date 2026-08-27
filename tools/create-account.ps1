<#
.SYNOPSIS
    Creates (or resets) a game account directly in the auth database.

.DESCRIPTION
    The worldserver console can do this, but driving it from a script is fragile:
    it reads all of stdin while still initialising, so commands sent up front are
    swallowed, and its startup writes thousands of data-quality lines to stderr,
    which fills the pipe buffer and deadlocks a naive reader.

    Computing the SRP6 credentials ourselves is deterministic and needs no console.
    This mirrors TrinityCore's SRP6::MakeRegistrationData exactly:

        s = 32 random bytes
        x = SHA1(s || SHA1(UPPER(user) || ':' || UPPER(pass)))
        v = g^x mod N        with g = 7 and TrinityCore's 256-bit N

    Every BigNumber in TrinityCore is little-endian on the wire, so both the SHA1
    digest going in and the verifier coming out are treated little-endian here.

.PARAMETER GmLevel
    0 = player. 3 = full GM. Written to auth.account_access with RealmID -1
    (meaning: applies to every realm).

.EXAMPLE
    .\tools\create-account.ps1 -Username admin -Password secret123 -GmLevel 3
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Username,
    [Parameter(Mandatory = $true)][string] $Password,
    [int]    $GmLevel    = 0,
    [string] $MySqlDir   = 'C:\MySQL\MySQL Server 8.0',
    [string] $DbUser     = 'trinity',
    [string] $DbPassword = 'trinity',
    [string] $DbHost     = '127.0.0.1',
    [int]    $DbPort     = 3306
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Native.ps1')

if ($Username.Length -gt 32) { throw 'username must be 32 characters or fewer' }
if ($Password.Length -gt 16) { throw 'the 4.3.4 client truncates passwords beyond 16 characters' }

# TrinityCore SRP6 parameters.
$gValue = [System.Numerics.BigInteger]::Parse('7')
$nHex   = '894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7'

function ConvertFrom-HexBigEndian {
    <# Hex string (big-endian) -> positive BigInteger. #>
    param([string] $Hex)
    $bytes = for ($i = 0; $i -lt $Hex.Length; $i += 2) {
        [Convert]::ToByte($Hex.Substring($i, 2), 16)
    }
    $le = [byte[]]$bytes
    [array]::Reverse($le)
    # A trailing zero byte keeps .NET from reading the top bit as a sign bit.
    return [System.Numerics.BigInteger]::new(($le + [byte]0))
}

function ConvertFrom-BytesLittleEndian {
    <# Little-endian byte array -> positive BigInteger. #>
    param([byte[]] $Bytes)
    return [System.Numerics.BigInteger]::new(($Bytes + [byte]0))
}

function ConvertTo-FixedLittleEndian {
    <# BigInteger -> little-endian byte array of exactly $Length bytes. #>
    param([System.Numerics.BigInteger] $Value, [int] $Length)
    $raw = $Value.ToByteArray()          # little-endian, possibly with a sign byte
    if ($raw.Length -gt $Length) {
        $raw = $raw[0..($Length - 1)]    # drop the sign byte
    }
    $out = New-Object byte[] $Length
    [array]::Copy($raw, $out, [Math]::Min($raw.Length, $Length))
    return $out
}

$N = ConvertFrom-HexBigEndian $nHex

$sha1 = [System.Security.Cryptography.SHA1]::Create()
$rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()

# s: 32 random bytes
$salt = New-Object byte[] 32
$rng.GetBytes($salt)

# inner = SHA1(UPPER(user):UPPER(pass))
$inner = $sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes(($Username.ToUpperInvariant() + ':' + $Password.ToUpperInvariant())))

# x = SHA1(s || inner), read little-endian
$x = ConvertFrom-BytesLittleEndian ($sha1.ComputeHash($salt + $inner))

# v = g^x mod N
$v = [System.Numerics.BigInteger]::ModPow($gValue, $x, $N)
$verifier = ConvertTo-FixedLittleEndian -Value $v -Length 32

function ConvertTo-SqlHex {
    param([byte[]] $Bytes)
    return '0x' + (($Bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

$saltHex     = ConvertTo-SqlHex $salt
$verifierHex = ConvertTo-SqlHex $verifier

Write-Host ''
Write-Host ("--> account '{0}', gmlevel {1}" -f $Username, $GmLevel) -ForegroundColor Cyan

$escapedUser = $Username -replace "'", "''"
$sql = @"
INSERT INTO auth.account (username, salt, verifier, email, reg_mail, expansion)
VALUES (UPPER('$escapedUser'), $saltHex, $verifierHex, '', '', 3)
ON DUPLICATE KEY UPDATE salt = VALUES(salt), verifier = VALUES(verifier);
SET @aid := (SELECT id FROM auth.account WHERE username = UPPER('$escapedUser'));
DELETE FROM auth.account_access WHERE AccountID = @aid;
INSERT INTO auth.account_access (AccountID, SecurityLevel, RealmID)
  SELECT @aid, $GmLevel, -1 WHERE $GmLevel > 0;
SELECT a.id, a.username, LENGTH(a.salt) AS salt_len, LENGTH(a.verifier) AS verifier_len,
       COALESCE(aa.SecurityLevel, 0) AS gmlevel
FROM auth.account a LEFT JOIN auth.account_access aa ON aa.AccountID = a.id
WHERE a.username = UPPER('$escapedUser');
"@

$sqlFile = Join-Path $env:TEMP ("prabowow-account-" + [Guid]::NewGuid().ToString('N') + '.sql')
Set-Content -Path $sqlFile -Value $sql -Encoding ASCII
try {
    # Via Invoke-Native: mysql.exe writes its "password on the command line is
    # insecure" notice to stderr, which PowerShell 5.1 turns into a terminating
    # error under $ErrorActionPreference = 'Stop' even though the command succeeds.
    $mysql = Join-Path $MySqlDir 'bin\mysql.exe'
    $code = Invoke-Native -Executable $mysql -Arguments @(
        "--user=$DbUser", "--password=$DbPassword", "--host=$DbHost",
        "--port=$DbPort", '--table', "--execute=source $sqlFile")
    Assert-NativeSuccess -ExitCode $code -What 'account insert'
} finally {
    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Account written. Verify by logging in with the game client.' -ForegroundColor Green
Write-Host ''
