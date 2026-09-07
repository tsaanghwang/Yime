param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$ActualResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$runnerPath = Join-Path $PSScriptRoot 'publish-rime-pime-dp1s-off-repository-archive.ps1'
$archiveSourcePath = Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.ps1'
$candidateModulePath = Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.psm1'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ($output -ieq $workspaceRoot -or -not $output.StartsWith($workspaceRoot+'\.tmp\dual-product\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'DP1-S test output must be a fresh directory below .tmp/dual-product.'
}
if ([IO.Directory]::Exists($output)) { throw 'DP1-S test output must be fresh.' }
[IO.Directory]::CreateDirectory($output) | Out-Null

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true}); Write-Host "PASS: $Name" }
    catch { $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message}); Write-Host "FAIL: $Name - $($_.Exception.Message)" }
}
function Assert-True($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$runner = [IO.File]::ReadAllText($runnerPath)
$archiveSource = [IO.File]::ReadAllText($archiveSourcePath)
Check 'runner-parses-under-current-powershell' {
    $errors=$null;$tokens=$null
    [Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$errors)|Out-Null
    Assert-True (@($errors).Count -eq 0) 'DP1-S runner has parser errors.'
}
Check 'destination-is-fixed-outside-appdata-and-git' {
    Assert-True ($runner.Contains("'Yime Rime-PIME Evidence Archives\DP1-S'")) 'Fixed user-profile archive root is missing.'
    Assert-True ($runner.Contains('Assert-OutsideWorktrees $archiveBase $worktrees')) 'Worktree exclusion is missing.'
    Assert-True (-not $runner.Contains('APPDATA')) 'DP1-S archive must not use AppData.'
}
Check 'source-and-output-are-restricted-to-repository-tmp' {
    Assert-True ($runner.Contains("Join-Path `$workspaceRoot '.tmp\dual-product'")) 'Repository transient root is not explicit.'
    Assert-True ($runner.Contains("'^dp1-o-candidate-[A-Za-z0-9._-]+$'")) 'Actual candidate source leaf is not restricted.'
    Assert-True ($runner.Contains("'DP1-S output root'")) 'Output containment is not checked.'
}
Check 'actual-candidate-is-not-rewritten-for-missing-sidecar' {
    Assert-True ($runner.Contains('New-ArchiveSourceProjection')) 'Source projection is missing.'
    Assert-True ($runner.Contains('source_candidate_bytes_changed=$false')) 'Source immutability result is missing.'
    Assert-True ($runner.Contains('derived_build_manifest_sidecar')) 'Derived sidecar disclosure is missing.'
}
Check 'source-independent-reopen-uses-both-shells-and-strict-reader' {
    foreach ($anchor in @('WindowsPowerShell\v1.0\powershell.exe','Get-Command pwsh.exe','Read-RimePimePackageBuildReceiptV2',
        'strict_receipt_read_ps5_without_source=$true','strict_receipt_read_ps7_without_source=$true')) {
        Assert-True ($runner.Contains($anchor)) "Missing source-independent verification anchor: $anchor"
    }
}
Check 'withheld-source-is-restored-through-finally' {
    Assert-True ($runner.Contains("Move-Item -LiteralPath `$source -Destination `$withheld")) 'Source withholding move is missing.'
    Assert-True ($runner.Contains('} finally {')) 'Withholding does not have a finally boundary.'
    Assert-True ($runner.Contains("Move-Item -LiteralPath `$withheld -Destination `$source")) 'Source restoration move is missing.'
}
Check 'verification-files-are-create-new-and-never-overwritten' {
    Assert-True ($runner.Contains('[IO.FileMode]::CreateNew')) 'CreateNew evidence publication is missing.'
    Assert-True (-not $runner.Contains('[IO.File]::Delete($ResultPath)')) 'Archived verification result can be deleted.'
    Assert-True ($runner.Contains('archived verification is a partial JSON/sidecar pair')) 'Partial verifier pair is not rejected.'
}
Check 'package-context-is-reported-without-overclaim' {
    Assert-True ($runner.Contains('GetCurrentPackageFullName')) 'Worker package identity probe is missing.'
    Assert-True ($runner.Contains('child_processes_have_packaged_codex_ancestor=$true')) 'Packaged ancestor disclosure is missing.'
    Assert-True ($runner.Contains('explorer_launched_independent_reopen_verified=$false')) 'Explorer-independent non-claim is missing.'
}
Check 'durability-and-hostile-sid-nonclaims-remain-false' {
    foreach ($anchor in @('directory_metadata_durability_verified=$false','hardware_power_loss_verified=$false',
        'active_hostile_same_sid_physical_replacement_prevented=$false')) {
        Assert-True ($runner.Contains($anchor)) "Missing honest DP1-S non-claim: $anchor"
    }
}
Check 'migration-installation-and-local12-remain-out-of-scope' {
    foreach ($anchor in @('actual_canonical_migration_admitted=$false','actual_canonical_migrated=$false',
        'installer_or_uninstaller_executed=$false','installed_yimecore_local12_touched=$false')) {
        Assert-True ($runner.Contains($anchor)) "Missing downstream boundary: $anchor"
    }
}
Check 'candidate-archive-canonical-receipt-path-matches-real-build' {
    Assert-True ($archiveSource.Contains("'repo/installer/package-build-receipt.json'")) 'Candidate archive still uses a fixture-only receipt path.'
    Assert-True (-not $archiveSource.Contains('YIME-package-build-receipt-v2.json')) 'Fixture-only receipt path remains in archive implementation.'
}

$actualChecked = $false
if (-not [string]::IsNullOrWhiteSpace($ActualResultPath)) {
    $actualChecked = $true
    Check 'actual-off-repository-archive-and-verifications-reopen' {
        $resultFull = [IO.Path]::GetFullPath($ActualResultPath)
        $digest = Hash $resultFull
        Assert-True ([IO.File]::ReadAllText($resultFull+'.sha256') -ceq $digest+'  '+[IO.Path]::GetFileName($resultFull)+"`n") 'Actual result sidecar is invalid.'
        $result = Get-Content -Raw -LiteralPath $resultFull | ConvertFrom-Json
        foreach ($name in @('actual_archive_root_published','actual_evidence_archived_outside_repository_tmp','outside_repository',
            'outside_outer_tmp','outside_all_git_worktrees','source_temporarily_unavailable_during_reverification',
            'fresh_process_reopen_ps5','fresh_process_reopen_ps7','strict_receipt_read_ps5_without_source',
            'strict_receipt_read_ps7_without_source','candidate_hash_verified_without_source')) {
            Assert-True ($result.$name -is [bool] -and [bool]$result.$name) "Actual result did not prove $name."
        }
        foreach ($name in @('explorer_launched_independent_reopen_verified','directory_metadata_durability_verified',
            'hardware_power_loss_verified','active_hostile_same_sid_physical_replacement_prevented',
            'actual_canonical_migration_admitted','actual_canonical_migrated')) {
            Assert-True ($result.$name -is [bool] -and -not [bool]$result.$name) "Actual result overclaimed $name."
        }
        $module = Import-Module -Name $candidateModulePath -Force -PassThru
        try {
            $status = & $module { param($Root)
                $context=[pscustomobject]@{case_root=Split-Path -Parent $Root;source_root='not-used';archive_root=$Root;lock_path=Join-Path (Split-Path -Parent $Root) '.rime-pime-dp1s-archive.lock'}
                Read-RimePimeCandidateArchiveAtRoot $context $Root
            } ([string]$result.archive_root)
        } finally { Remove-Module $module -Force }
        Assert-True ([string]$status.archive_id -ceq [string]$result.archive_id) 'Actual capsule identity changed.'
        foreach ($verification in @($result.ps5_verification,$result.ps7_verification)) {
            Assert-True ((Hash ([string]$verification.path)) -ceq [string]$verification.sha256) 'Archived verifier digest changed.'
            Assert-True ([IO.File]::ReadAllText(([string]$verification.path)+'.sha256') -ceq [string]$verification.sha256+'  '+[IO.Path]::GetFileName([string]$verification.path)+"`n") 'Archived verifier sidecar changed.'
        }
    }
}

$failed = @($checks | Where-Object { -not $_.passed })
$result = [pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1s-off-repository-archive-test-v1'
    powershell_edition=[string]$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    passed=($failed.Count -eq 0);check_count=$checks.Count;passed_count=$checks.Count-$failed.Count;failed_count=$failed.Count
    checks=@($checks);actual_evidence_checked=$actualChecked
    installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_read_or_written=$false
    directory_metadata_durability_verified=$false;hardware_power_loss_verified=$false
    active_hostile_same_sid_physical_replacement_prevented=$false;actual_canonical_migration_admitted=$false
    runner_sha256=Hash $runnerPath;archive_source_sha256=Hash $archiveSourcePath
}
$json=(ConvertTo-Json $result -Depth 10 -Compress)+"`n"
$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
$resultPath=Join-Path $output 'result.json'
[IO.File]::WriteAllBytes($resultPath,$bytes)
$resultDigest=Hash $resultPath
[IO.File]::WriteAllText($resultPath+'.sha256',$resultDigest+'  result.json'+"`n",[Text.Encoding]::ASCII)
if ($failed.Count -ne 0) { throw "$($failed.Count) DP1-S checks failed. Result: $resultPath" }
Write-Host "PASS: $($checks.Count) DP1-S archive checks under $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion). $resultPath ($resultDigest)"
