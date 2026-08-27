<#
    Shared helper for invoking native executables from Windows PowerShell 5.1.

    Dot-source this file; do not run it directly:

        . (Join-Path $PSScriptRoot 'lib\Native.ps1')

    Two PowerShell 5.1 traps are handled here, both of which cost real debugging time
    on this project and are subtle enough that copy-pasting the workaround invites
    divergence:

    1. Windows PowerShell wraps every stderr line from a native process in an
       ErrorRecord. Under $ErrorActionPreference = 'Stop' that becomes a TERMINATING
       error the moment the tool writes anything to stderr -- even mere progress
       output from a tool that goes on to succeed. CMake does exactly this, which
       made a successful configure look like a failure and swallowed its output.

    2. A PowerShell function returns EVERYTHING written to the pipeline, not just the
       value passed to `return`. Letting the child's stdout fall through means the
       caller receives an array of every output line with the exit code appended, so
       `if ($code -ne 0)` compares an array against 0 and misbehaves silently.

    The exit code is the only trustworthy success signal for a native process.
#>

function Invoke-Native {
    <#
    .SYNOPSIS
        Runs a native executable, streams its output, and returns only its exit code.

    .PARAMETER Executable
        Path to (or name of) the executable.

    .PARAMETER Arguments
        Arguments to pass through.

    .PARAMETER WorkingDirectory
        Directory to run in. Several TrinityCore extractors write their output to the
        current directory rather than to a path given on the command line, so this is
        load-bearing, not a convenience.

    .OUTPUTS
        [int] the process exit code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]   $Executable,
        [string[]] $Arguments = @(),
        [string]   $WorkingDirectory
    )

    $previousPreference = $ErrorActionPreference
    $previousLocation   = $null

    if ($WorkingDirectory) {
        if (-not (Test-Path $WorkingDirectory)) {
            throw "working directory does not exist: $WorkingDirectory"
        }
        $previousLocation = Get-Location
        Set-Location -Path $WorkingDirectory
    }

    $ErrorActionPreference = 'Continue'
    try {
        # Consume stdout here so the function's only pipeline output is the exit code.
        & $Executable @Arguments | ForEach-Object { Write-Host $_ }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        if ($previousLocation) { Set-Location -Path $previousLocation }
    }
}

function Assert-NativeSuccess {
    <#
    .SYNOPSIS
        Throws with a readable message when an exit code is non-zero.
    #>
    param(
        [int]    $ExitCode,
        [string] $What
    )
    if ($ExitCode -ne 0) {
        throw "$What failed with exit code $ExitCode"
    }
}
