[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$ActualArchiveRoot=''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$outer=Join-Path $repo '.tmp\dual-product'
$out=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if(-not $out.StartsWith($outer+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $out) -cnotmatch '^dp1-t-actual-adapter-test-[A-Za-z0-9._-]+$' -or
    (Test-Path -LiteralPath $out)) {throw 'Use a fresh .tmp/dual-product/dp1-t-actual-adapter-test-* output.'}
New-Item -ItemType Directory -Path $out | Out-Null

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true;error=''})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}

$adapter=Join-Path $PSScriptRoot 'invoke-rime-pime-actual-canonical-migration.ps1'
$transaction=Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.ps1'
$modulePath=Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.psm1'
$review=Join-Path $PSScriptRoot 'rime-pime-actual-migration-review.psm1'
$adapterSource=Get-Content -Raw -LiteralPath $adapter
$transactionSource=Get-Content -Raw -LiteralPath $transaction
$reviewSource=Get-Content -Raw -LiteralPath $review

Check 'adapter-parses-under-current-powershell' {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($adapter,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) (($errors | ForEach-Object Message)-join '; ')
}
Check 'dp1n-public-api-remains-exact-and-fixture-only' {
    $m=Import-Module $modulePath -Force -PassThru
    try{
        $exports=@($m.ExportedCommands.Keys|Sort-Object)
        Assert-True (($exports-join ',') -ceq 'Publish-RimePimeInstallerReceiptTransaction,Resume-RimePimeInstallerReceiptTransaction') 'DP1-N exports changed.'
        $rejected=$false
        try{Resume-RimePimeInstallerReceiptTransaction -RepoRoot $repo|Out-Null}catch{$rejected=$_.Exception.Message.Contains('allowed only in fresh')}
        Assert-True $rejected 'Public fixture API admitted the actual checkout.'
    }finally{Remove-Module $m -Force -ErrorAction SilentlyContinue}
}
Check 'actual-capability-is-private-and-finally-scoped' {
    foreach($anchor in @('Publish-RimePimeInstallerReceiptTransactionActual','Resume-RimePimeInstallerReceiptTransactionActual',
        '$script:RimePimeInstallerReceiptActualRootEnabled=$true','finally{$script:RimePimeInstallerReceiptActualRootEnabled=$false}')){
        Assert-True $transactionSource.Contains($anchor) "Missing private-capability anchor: $anchor"
    }
}
Check 'adapter-is-exact-checkout-and-fixed-external-archive-bound' {
    foreach($anchor in @("'Yime Rime-PIME Evidence Archives\DP1-S'",'outside the fixed DP1-T authorization directory',
        "'.git'",'bound to the checkout containing this adapter')){
        Assert-True $adapterSource.Contains($anchor) "Missing root boundary: $anchor"
    }
}
Check 'adapter-write-set-is-exact-and-bounded' {
    foreach($role in @('unique-staging-leaves','retained-evidence-objects','retained-evidence-sidecars',
        'successor-installer-stage','successor-installer','pending-intent','canonical-receipt','canonical-sidecar','completed-intent')){
        Assert-True $adapterSource.Contains("'$role'") "Missing write role: $role"
    }
    Assert-True $adapterSource.Contains("'installer\receipt-evidence\sha256\'") 'Retained store target is missing.'
}
Check 'authorization-binds-exact-user-scope-and-all-identities' {
    foreach($anchor in @('one-time-actual-canonical-artifact-migration','actual-canonical-artifacts-only',
        'migration_plan_sha256','actual_snapshot_sha256','archive_manifest_sha256','adapter_source_set_sha256',
        '按顺序完成 DP1-S 仓外证据归档、DP1-T 实际迁移适配器、DP1-U 注册/回滚/卸载/Runtime 门禁')){
        Assert-True $adapterSource.Contains($anchor) "Missing authorization binding: $anchor"
    }
}
Check 'apply-requires-both-full-fault-matrix-results' {
    foreach($anchor in @('Both PS5 and PS7 full fault-matrix results are required together.',
        'full_suite_executed','all_executed_checks_passed','fault_matrix_sha256',
        'Apply and Resume require passing full PS5 and PS7 fault matrices.')){
        Assert-True $adapterSource.Contains($anchor) "Missing fault-matrix binding: $anchor"
    }
}
Check 'resume-reuses-the-authorized-pre-migration-plan' {
    foreach($anchor in @('$authorizationCandidate=Assert-Dp1TAuthorization $AuthorizationPath $null',
        '$snapshot=[string]$authorizationCandidate.Value.actual_snapshot_sha256',
        'Recovery old receipt object differs from authorization.',
        '[string]$current.Digest -ceq [string]$archive.Receipt.sha256')){
        Assert-True $adapterSource.Contains($anchor) "Missing stable-resume anchor: $anchor"
    }
}
Check 'archive-objects-are-hash-checked-and-copied-no-replace' {
    foreach($anchor in @('Archive object differs from its manifest.','Copy-Dp1TNoReplace','MoveFileEx($temp,$Destination,8)',
        'Existing retained object differs.','Seeded successor receipt differs from the archive.')){
        Assert-True $adapterSource.Contains($anchor) "Missing archive/CAS anchor: $anchor"
    }
}
Check 'adapter-has-no-product-or-installer-execution-surface' {
    foreach($forbidden in @('Start-Process','Invoke-Expression','& reg.exe','msiexec','PIMELauncher.exe','server.exe')){
        Assert-True (-not $adapterSource.Contains($forbidden)) "Forbidden action surface: $forbidden"
    }
}
Check 'physical-closure-fields-remain-honestly-false' {
    foreach($name in @('hardware_power_loss_recovery_verified','directory_metadata_durability_verified','hostile_same_sid_replacement_prevented')){
        Assert-True $adapterSource.Contains($name+'=$false') "Adapter nonclaim missing: $name"
    }
    Assert-True $reviewSource.Contains("Test-RimePimeMigrationReviewBoolean `$AdapterEvidence `$name `$false 'adapter' `$reasons") 'Review does not require physical nonclaims to remain false.'
}
Check 'plan-mode-is-read-only-for-canonical-artifacts' {
    Assert-True $adapterSource.Contains("if(`$Mode -ne 'Plan')") 'Mutation is not below the Plan guard.'
    Assert-True $adapterSource.Contains("actual_canonical_migration_admitted=[bool](`$Mode -ne 'Plan')") 'Admission result is not mode bound.'
}

$actualChecked=$false
if($ActualArchiveRoot){
    Check 'actual-dry-run-plan-converges-with-current-shell' {
        $planOut=Join-Path $outer ('dp1-t-plan-from-test-'+[guid]::NewGuid().ToString('N'))
        & $adapter -Mode Plan -RepoRoot $repo -ArchiveRoot $ActualArchiveRoot -OutputRoot $planOut
        $result=Get-Content -Raw -LiteralPath (Join-Path $planOut 'result.json')|ConvertFrom-Json
        Assert-True ($result.status -ceq 'pass' -and $result.mode -ceq 'Plan' -and
            -not $result.actual_canonical_migration_admitted -and -not $result.actual_canonical_migrated) `
            'Actual dry-run result is not an honest Plan result.'
    }
    $actualChecked=$true
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[ordered]@{
    schema_version='yime-rime-pime-actual-canonical-adapter-test-v1'
    powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    passed=$failed.Count -eq 0;check_count=$checks.Count;passed_count=$checks.Count-$failed.Count
    failed_count=$failed.Count;checks=@($checks);actual_dry_run_checked=$actualChecked
    installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_read_or_written=$false
    hardware_power_loss_recovery_verified=$false;directory_metadata_durability_verified=$false
    hostile_same_sid_replacement_prevented=$false
}
$json=ConvertTo-Json -InputObject $result -Depth 10 -Compress
$path=Join-Path $out 'result.json'
[IO.File]::WriteAllText($path,$json+"`n",[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($path+'.sha256',$hash+'  result.json'+"`n",[Text.UTF8Encoding]::new($false))
if($failed.Count){throw "DP1-T adapter test failed: $($failed.Count). Evidence: $path ($hash)"}
Write-Host "PASS: DP1-T adapter test $($checks.Count)/$($checks.Count). Evidence: $path ($hash)"
