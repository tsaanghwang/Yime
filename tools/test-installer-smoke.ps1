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
$failure = $null
try {
    & $installer /S
    if ($LASTEXITCODE -ne 0) { throw "Installer failed with exit code $LASTEXITCODE" }
    Start-Sleep -Seconds 3
    & $verifyScript -RepoRoot $RepoRoot -InstallRoot $InstallRoot -RequireRunningLauncher
} catch {
    $failure = $_
} finally {
    $uninstaller = Join-Path $InstallRoot 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        & $uninstaller /S
        if ($LASTEXITCODE -ne 0 -and -not $failure) {
            $failure = [Runtime.Exception]::new("Uninstaller failed with exit code $LASTEXITCODE")
        }
    }
}
if ($failure) { throw $failure }
Write-Host 'Unsigned installer smoke test passed and the ephemeral installation was removed.'
