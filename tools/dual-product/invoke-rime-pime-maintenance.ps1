[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('ValidateInstall','ValidateExisting','Stop','ValidateRegistration','ValidateRegistrationForRemoval','ValidateRegistrationVacant','CleanupTargetUserProfile','ValidateTargetUserProfileAbsent','ValidateNativeRegistrationAbsent')][string]$Action,
    [Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
    [string]$ArchitectureSet)
$ErrorActionPreference='Stop'
try {
    $helper=Join-Path $PSScriptRoot 'rime-pime-ownership.ps1'
    if(-not (Test-Path -LiteralPath $helper -PathType Leaf)){throw 'Independent Rime/PIME ownership helper is missing.'}
    . $helper
    Invoke-YimePimeMaintenanceGuard -Action $Action -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid `
        -ArchitectureSet $ArchitectureSet
    exit 0
} catch {
    Write-Error ('Rime/PIME maintenance was not admitted. '+$_.Exception.Message) -ErrorAction Continue
    exit 41
}
