[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupRoot,[switch]$LocalProduct,[string]$InstalledPackageRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreUnpackagedDataMaintenance
$stateRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))
$localProductBackup = [bool]($LocalProduct -or -not [string]::IsNullOrWhiteSpace($InstalledPackageRoot))
if ($localProductBackup) {
    . (Join-Path $PSScriptRoot 'local-package-contract.ps1')
    . (Join-Path $PSScriptRoot 'local-product-runtime.ps1')
    $contextRoot = if ($LocalProduct) { Split-Path -Parent $PSScriptRoot } else { $InstalledPackageRoot }
    $localContext = Assert-LocalProductInstalledContext $contextRoot $stateRoot
    Initialize-LocalProductLauncher $localContext
    $null = Assert-LocalProductLiveRuntime $localContext
}
$backup = [IO.Path]::GetFullPath($BackupRoot)
$allowed = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives')) + '\'
if (-not $backup.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $backup)) {
    throw 'Backup must be a new child of USERPROFILE/YimeCore Recovery Archives, outside AppData.'
}
Assert-YimeCorePlainPath $backup
Assert-YimeCorePlainPath $stateRoot
if (Get-Process WINWORD -ErrorAction SilentlyContinue) { throw 'Close Word before taking the maintenance snapshot.' }
$config = Get-Content -Encoding UTF8 (Join-Path $stateRoot 'runtime-config.json') -Raw | ConvertFrom-Json
$status = Get-Content -Encoding UTF8 (Join-Path $stateRoot 'runtime-status.json') -Raw | ConvertFrom-Json
$liveBefore=Get-YimeCoreLiveRuntimeEvidence $stateRoot
if (-not $liveBefore.passed) { throw 'Expected verified live runtime/Broker identities before maintenance.' }
function Records([string]$root) {
    @(Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point rejected: $($_.FullName)" }
        if (-not $_.PSIsContainer) {
            [ordered]@{ path=$_.FullName.Substring($root.Length+1).Replace('\','/'); bytes=$_.Length;
                sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
    } | Sort-Object { $_.path })
}
function Assert-Records($expected,$actual) {
    if (($expected|ConvertTo-Json -Depth 4 -Compress) -cne ($actual|ConvertTo-Json -Depth 4 -Compress)) {
        throw 'Snapshot changed while copying or copied bytes differ.'
    }
}
$archiveState = Join-Path $backup 'state'
New-Item -ItemType Directory -Path $archiveState -Force | Out-Null
$stopped = $false
try {
    $stopScript = if ($localProductBackup) {
        Join-Path $localContext.package.root 'maintenance\stop-e6c-trial-runtime.ps1'
    } else { Join-Path $PSScriptRoot 'stop-e6c-trial-runtime.ps1' }
    & $stopScript -StateRoot $stateRoot | Out-Null
    $stopped = $true
    foreach ($id in @([int]$status.runtime_pid,[int]$status.broker_pid)) {
        if (Get-Process -Id $id -ErrorAction SilentlyContinue) { throw "Writer still running: $id" }
    }
    $writers = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith([string]$config.install_root+'\',[StringComparison]::OrdinalIgnoreCase)
    })
    if ($writers.Count) { throw 'An installed trial tool is still running; close it before backup.' }
    $before = Records $stateRoot
    foreach ($item in Get-ChildItem -LiteralPath $stateRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $archiveState -Recurse
    }
    Assert-Records $before (Records $stateRoot)
    Assert-Records $before (Records $archiveState)
    $package = [IO.Path]::GetFullPath([string]$config.install_root)
    Assert-YimeCorePlainPath $package
    $packageBefore = Records $package
    $archivePackage = Join-Path $backup 'previous-package'
    New-Item -ItemType Directory -Path $archivePackage | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $package -Force) { Copy-Item -LiteralPath $item.FullName -Destination $archivePackage -Recurse }
    Assert-Records $packageBefore (Records $archivePackage)
    [ordered]@{schema_version='yimecore-quiesced-backup-v1'; generated_at=(Get-Date).ToUniversalTime().ToString('o');
        development_scope=$scope; source_state_root=$stateRoot; source_install_root=$package;
        runtime_pid_before=$status.runtime_pid; broker_pid_before=$status.broker_pid;
        writers_stopped=$true; source_stable_during_copy=$true; state_files=$before; package_files=$packageBefore;
        native_context_verified=$true;live_runtime_before=$liveBefore;
        data_files=@(Get-YimeCoreDataRecords $archiveState);backup_root=$backup; passed=$true} | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Encoding utf8
} finally {
    if ($stopped) {
        if ($localProductBackup) { Start-LocalProductRuntime $localContext | Out-Null }
        else { & (Join-Path $PSScriptRoot 'start-e6c-trial-runtime.ps1') | Out-Null }
    }
}
$liveAfter=Get-YimeCoreLiveRuntimeEvidence $stateRoot
if(-not $liveAfter.passed){throw 'Backup saved, but runtime did not recover with verified live identities.'}
$null=Assert-YimeCoreNativeFile (Join-Path $backup 'backup-manifest.json')
Write-Host "Quiesced state and package backup complete: $backup"
