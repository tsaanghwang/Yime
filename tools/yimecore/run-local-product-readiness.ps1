[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$CurrentCandidateRecoveryEvidence,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $PackageRoot) { $PackageRoot = Join-Path $env:USERPROFILE 'YimeCore Recovery Archives\local12-l6-sealed-20260908\package' }
Import-Module (Join-Path $PSScriptRoot 'local-product-readiness.psm1') -Force
$result = Get-YimeCoreLocalProductReadiness `
    -PackageRoot $PackageRoot `
    -DailyUseEvidence (Join-Path $repo 'docs\testing\l5\2026-09-08-local12-final-daily-use.json') `
    -RegisteredHostEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-registered-acceptance.json') `
    -RebootEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-reboot-outcomes.json') `
    -X86AcceptanceRecord (Join-Path $repo 'docs\testing\l6\local12-evidence-20260908\x86_live_hosts.json') `
    -Local12ManualEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-manual-pre-reboot.json') `
    -PreviousPackageBackupEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-native-backup.json') `
    -CurrentCandidateRecoveryEvidence $CurrentCandidateRecoveryEvidence `
    -RepositoryRoot $repo
$json = $result | ConvertTo-Json -Depth 20
if ($OutputPath) {
    Write-YimeCoreReadinessResult -Result $result -OutputPath $OutputPath -RepositoryRoot $repo
}
$json
if (-not $result.local_product_ready) { exit 2 }
