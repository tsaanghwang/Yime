[CmdletBinding()]
param([switch]$Execute,[Parameter(Mandatory)][string]$AttemptId)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'native-rollback-collection.psm1')
if($Execute){Invoke-YimeCoreNativeRollbackCollection -Execute -AttemptId $AttemptId | ConvertTo-Json -Depth 12}
else{Get-YimeCoreNativeRollbackCollectionPlan -AttemptId $AttemptId | ConvertTo-Json -Depth 12}
