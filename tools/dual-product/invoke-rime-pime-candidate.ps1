[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install','Remove','Resume')][string]$Mode,
    [Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$ExpectedManifestSha256,
    [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$AuthorizationPath,
    [Parameter(Mandatory)][string]$TrustedApprovalSha256,[Parameter(Mandatory)][string]$BoundaryPath,
    [Parameter(Mandatory)][string]$ReceiptPath,[string]$PreparedSha256)
$ErrorActionPreference='Stop'
try{
    if([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|$)'){throw 'This candidate cannot maintain MYCOMPUTER local.12 or production Rime/PIME.'}
    Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1')
    Invoke-RimePimeCandidateMaintenance @PSBoundParameters | ConvertTo-Json -Depth 20
    exit 0
}catch{
    if(Get-Command Save-RimePimeMaintenanceFailure -ErrorAction SilentlyContinue){Save-RimePimeMaintenanceFailure -Failure $_ -Phase ('controller-'+$Mode)}
    Write-Error $_ -ErrorAction Continue;exit 51
}
