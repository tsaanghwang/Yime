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
    -X86AcceptanceRecord (Join-Path $repo 'docs\YIMECORE_LOCAL11_X86_ACCEPTANCE_2026-09-04.md') `
    -Local12ManualEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-manual-pre-reboot.json') `
    -PreviousPackageBackupEvidence (Join-Path $repo 'docs\testing\l5\2026-09-05-local12-native-backup.json') `
    -CurrentCandidateRecoveryEvidence $CurrentCandidateRecoveryEvidence `
    -RepositoryRoot $repo
$json = $result | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
}
$json
if (-not $result.local_product_ready) { exit 2 }
