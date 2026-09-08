[CmdletBinding()]
param([Parameter(Mandatory)][string]$Version)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:RUNNER_OS -cne 'Windows' -or -not $env:RUNNER_TEMP -or -not $env:GITHUB_PATH) {
    throw 'Locked NSIS installation is restricted to GitHub-hosted Windows CI.'
}

$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.lock.json') -Raw | ConvertFrom-Json
$records = @($lock.tools | Where-Object { $_.id -ceq 'nsis' })
if ($records.Count -ne 1 -or [string]$records[0].version -cne $Version) {
    throw 'Requested NSIS version differs from the toolchain lock.'
}
$acquisition = $records[0].acquisition
$expectedUrl = "https://downloads.sourceforge.net/project/nsis/NSIS%203/$Version/nsis-$Version-setup.exe"
if ($Version -cnotmatch '^[0-9]+\.[0-9]+$' -or [string]$acquisition.url -cne $expectedUrl -or
    [string]$acquisition.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$acquisition.size -le 0) {
    throw 'NSIS setup acquisition metadata is invalid.'
}

Import-Module (Join-Path $PSScriptRoot 'dual-product\rime-pime-nsis-toolchain-closure.psm1')
$closureLock = Read-RimePimeNsisCompilerToolchainLockDocument
$nsisRoot = ([string]$closureLock.Document.nsis.root).Replace('/','\')
$runId = [Guid]::NewGuid().ToString('N')
$downloadRoot = Join-Path $env:RUNNER_TEMP "yime-nsis-$runId"
New-Item -ItemType Directory -Path $downloadRoot | Out-Null
$setupPath = Join-Path $downloadRoot 'nsis-setup.exe'
Invoke-WebRequest -Uri ([string]$acquisition.url) -OutFile $setupPath

# Keep the verified installer read-leased through execution.
$setupLease = [IO.File]::Open($setupPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    if ($setupLease.Length -ne [long]$acquisition.size) { throw 'NSIS setup size differs from the toolchain lock.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($setupLease))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($digest -cne [string]$acquisition.sha256) { throw 'NSIS setup SHA-256 differs from the toolchain lock.' }

    # Hosted images already contain NSIS. Preserve it under a same-volume name
    # so older files or third-party plugins cannot enter the new distribution.
    if (Test-Path -LiteralPath $nsisRoot) {
        $existing = Get-Item -LiteralPath $nsisRoot -Force
        if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Existing NSIS root is not a normal directory.'
        }
        [IO.Directory]::Move($nsisRoot,($nsisRoot+'-yime-previous-'+$runId))
    }
    # NSIS requires /D to be last and unquoted, including paths with spaces.
    $process = Start-Process -FilePath $setupPath -ArgumentList @('/S',"/D=$nsisRoot") -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Locked NSIS setup failed with exit code $($process.ExitCode)." }
} finally {
    $setupLease.Dispose()
}

# Validate the complete code-pinned distribution before any package build.
$closure = Open-RimePimeNsisCompilerInputClosure
try { $null = Test-RimePimeNsisCompilerInputClosure $closure }
finally { Close-RimePimeNsisCompilerInputClosure $closure }
Add-Content -LiteralPath $env:GITHUB_PATH -Value (Join-Path $nsisRoot 'Bin') -Encoding utf8
Add-Content -LiteralPath $env:GITHUB_PATH -Value $nsisRoot -Encoding utf8
Write-Host "PASS: original NSIS $Version setup and compiler input closure match repository locks."
