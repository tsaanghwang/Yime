[CmdletBinding()]
param(
    [ValidateSet('Plan','Install','Upgrade','Uninstall','Backup','Restore','Verify')][string]$Action='Plan',
    [string]$BackupRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-package-contract.ps1')
. (Join-Path $PSScriptRoot 'local-product-runtime.ps1')
$null=Get-YimeCoreDevelopmentScope
# Verify writes evidence and opens broker sessions, so only Plan is read-only.
if ($Action -ne 'Plan') { Assert-YimeCoreUnpackagedDataMaintenance }
$packageRoot=Split-Path -Parent $PSScriptRoot
$package=Assert-LocalProductPackage $packageRoot
$stateRoot=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($Action -in @('Plan','Install','Upgrade','Uninstall')) {
    $managerAction=if($Action -eq 'Upgrade'){'Install'}else{$Action}
    # Same SID and state root survive UAC in the shared transaction manager.
    & (Join-Path $PSScriptRoot 'Manage-YimeCoreTrial.ps1') -Action $managerAction -PackageRoot $packageRoot `
        -StateRoot $stateRoot -TargetUserSid $sid -NativeDesktop
    exit $LASTEXITCODE
}
$context=Assert-LocalProductInstalledContext $packageRoot $stateRoot
Initialize-LocalProductLauncher $context
$null=Assert-LocalProductLiveRuntime $context
switch($Action) {
    'Backup' {
        if (-not $BackupRoot) { $BackupRoot=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local-product-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
        & (Join-Path $PSScriptRoot 'backup-local-trial-state.ps1') -BackupRoot $BackupRoot -LocalProduct
    }
    'Restore' {
        if (-not $BackupRoot) { throw 'Restore requires -BackupRoot pointing to a fresh native recovery archive.' }
        & (Join-Path $PSScriptRoot 'restore-local-trial-state.ps1') -BackupRoot $BackupRoot `
            -RecoveryProbe (Join-Path $packageRoot 'bin\YimeCoreRecoveryProbe.exe') -LocalProduct
    }
    'Verify' { & (Join-Path $PSScriptRoot 'verify-e6c-trial-runtime.ps1') -StateRoot $stateRoot -LocalProduct }
}
