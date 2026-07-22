param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [switch]$AllowLocalMachine
)

$ErrorActionPreference = 'Stop'
if (-not $env:CI -and -not $AllowLocalMachine) {
    throw 'Installer smoke testing mutates machine-wide registration. Run it on an ephemeral CI runner or pass -AllowLocalMachine explicitly.'
}

$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$verifyScript = Join-Path $PSScriptRoot 'verify-installed-runtime.ps1'

function Invoke-SmokeProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [string]$Description
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(300000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Description timed out after 300 seconds."
    }
    if ($process.ExitCode -ne 0) {
        throw "$Description failed with exit code $($process.ExitCode)"
    }
}

$failure = $null
try {
    Invoke-SmokeProcess -FilePath $installer -Arguments '/S' -Description 'Installer'
    Start-Sleep -Seconds 3
    & $verifyScript -RepoRoot $RepoRoot -InstallRoot $InstallRoot -RequireRunningLauncher
} catch {
    $failure = $_
} finally {
    $uninstaller = Join-Path $InstallRoot 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        try {
            Invoke-SmokeProcess -FilePath $uninstaller -Arguments '/S' -Description 'Uninstaller'
        } catch {
            if (-not $failure) { $failure = $_ }
        }
    }
}
if ($failure) { throw $failure }
Write-Host 'Unsigned installer smoke test passed and the ephemeral installation was removed.'
