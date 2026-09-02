[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$E6CSummaryPath,
    [Parameter(Mandatory)] [string]$E6DSummaryPath,
    [Parameter(Mandatory)] [string]$PerformanceSummaryPath,
    [string]$ExternalEvidencePath,
    [string]$SignedPackageRoot,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$developmentScope = Get-YimeCoreDevelopmentScope
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment\e7-readiness'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and
    -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E7 readiness evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Read-JsonEvidence([string]$Path, [string]$Label) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "$Label evidence is missing: $absolute"
    }
    try {
        return Get-Content -LiteralPath $absolute -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "$Label evidence is invalid JSON: $absolute"
    }
}

function Test-EvidenceHash([string]$Path, [string]$Expected) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Expected) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Equals(
        $Expected, [StringComparison]::OrdinalIgnoreCase)
}

$checks = [Collections.Generic.List[object]]::new()
$blockers = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$deferredChecks = [Collections.Generic.List[object]]::new()
function Add-DeferredCheck([string]$Name, [string]$Detail) {
    $deferredChecks.Add([ordered]@{ name = $Name; status = 'deferred'; passed = $null; detail = $Detail })
}
function Add-ReadinessCheck(
    [string]$Name,
    [bool]$Passed,
    [string]$Detail,
    [string]$Blocker
) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
    if (-not $Passed -and -not [string]::IsNullOrWhiteSpace($Blocker)) {
        $blockers.Add($Blocker)
    }
}

$e6cSummaryPathValue = [IO.Path]::GetFullPath($E6CSummaryPath)
$e6dSummaryPathValue = [IO.Path]::GetFullPath($E6DSummaryPath)
$performanceSummaryPathValue = [IO.Path]::GetFullPath($PerformanceSummaryPath)
$e6c = Read-JsonEvidence $e6cSummaryPathValue 'E6-C'
$e6d = Read-JsonEvidence $e6dSummaryPathValue 'E6-D'
$performance = Read-JsonEvidence $performanceSummaryPathValue 'performance tier'
$currentCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
$workingTreeClean = -not [bool]((& git -C $repoRoot status --porcelain).Count)
foreach ($entry in @(
    @{ name = 'e6c'; evidence = $e6c }, @{ name = 'e6d'; evidence = $e6d },
    @{ name = 'performance'; evidence = $performance }
)) {
    Add-ReadinessCheck ($entry.name + '_development_scope') `
        (Test-YimeCoreScopeEvidence $entry.evidence.development_scope $developmentScope) `
        'current development host, x64, matching scope policy hash' `
        ($entry.name + ': evidence is missing or does not match the current development scope')
}

Add-ReadinessCheck 'source_worktree_clean' $workingTreeClean `
    "HEAD=$currentCommit" 'source: working tree is not clean'
Add-ReadinessCheck 'e6c_current_clean_commit' `
    ([bool](-not $e6c.git_dirty -and [string]$e6c.git_commit -eq $currentCommit)) `
    "evidence_commit=$($e6c.git_commit)" 'e6c: staged-package evidence is not from the current clean commit'
Add-ReadinessCheck 'e6d_current_clean_commit' `
    ([bool](-not $e6d.git_dirty -and [string]$e6d.git_commit -eq $currentCommit)) `
    "evidence_commit=$($e6d.git_commit)" 'e6d: installed-package evidence is not from the current clean commit'
Add-ReadinessCheck 'performance_current_clean_commit' `
    ([bool](-not $performance.git_dirty -and [string]$performance.git_commit -eq $currentCommit)) `
    "evidence_commit=$($performance.git_commit)" `
    'performance: active-tier evidence is not from the current clean commit'

$performanceProfiles = @($performance.rows | Where-Object { $_.stage -in @('e1', 'e2') } |
    Select-Object -ExpandProperty profile | Sort-Object -Unique)
$activeProfilesOnly = $performanceProfiles.Count -eq 1 -and
    $performanceProfiles[0] -eq 'development_host_x64' -and
    $performance.measurement_policy -eq 'native-unthrottled-no-affinity-override'
Add-ReadinessCheck 'active_performance_profiles_only' $activeProfilesOnly `
    ($performanceProfiles -join ', ') `
    'performance: evidence must contain only this native, unthrottled development-host profile'
$learningProfiles = @($performance.rows | Where-Object { $_.stage -eq 'e3' } |
    Select-Object -ExpandProperty profile | Sort-Object -Unique)
$nativeLearningProfileOnly = $learningProfiles.Count -eq 1 -and
    $learningProfiles[0] -eq 'native_host_interleaved'
Add-ReadinessCheck 'native_interleaved_learning_profile' $nativeLearningProfileOnly `
    ($learningProfiles -join ', ') `
    'performance: E3 evidence is not the native-host interleaved measurement'
$modeCoveragePassed = @($performance.rows).Count -eq 9
foreach ($stage in @('e1', 'e2', 'e3')) {
    foreach ($mode in @('full', 'variable', 'shorthand')) {
        if (@($performance.rows | Where-Object { $_.stage -eq $stage -and $_.mode -eq $mode }).Count -ne 1) {
            $modeCoveragePassed = $false
        }
    }
}
Add-ReadinessCheck 'development_host_performance_coverage' $modeCoveragePassed `
    'exactly one full/variable/shorthand row per E1/E2/E3 stage' `
    'performance: current-machine mode coverage is missing or duplicated'
$performanceBudgetsPassed = [bool]($performance.all_correctness_passed -and
    $performance.all_interaction_budgets_passed -and $performance.all_memory_budgets_passed)
Add-ReadinessCheck 'development_host_performance_budgets' $performanceBudgetsPassed `
    'correctness, interaction and memory budgets' `
    'performance: a development-host correctness, interaction or memory budget failed'

$requiredE6C = @(
    'base_package_hash_handoff_verified',
    'package_manifest_integrity_passed',
    'install_metadata_consistency_passed',
    'required_independent_components_passed',
    'x64_x86_arm64_pe_architecture_passed',
    'forbidden_rime_pime_artifacts_absent',
    'forbidden_rime_pime_pe_imports_absent',
    'full_variable_shorthand_learning_persistence_passed',
    'failed_switch_rollback_and_composition_affinity_passed',
    'clean_broker_restart_passed',
    'crash_journal_recovery_passed',
    'system_lexicon_all_modes_resident',
    'system_lexicon_restart_modes_resident',
    'system_lexicon_no_severe_latency_or_stickiness',
    'dynamic_sentence_real_indexes_passed',
    'runtime_supervisor_broker_recovery_passed',
    'language_bar_x64_passed',
    'installed_apps_uninstall_contract_passed',
    'e6c_limitation_closed'
)
$failedE6C = @($requiredE6C | Where-Object { -not [bool]$e6c.$_ })
Add-ReadinessCheck 'e6c_required_gates' ($failedE6C.Count -eq 0) `
    $(if ($failedE6C.Count) { $failedE6C -join ', ' } else { 'all required E6-C gates passed' }) `
    'e6c: one or more required package/runtime/TSF gates failed'
Add-ReadinessCheck 'e6c_preserved_production' `
    ([bool](-not $e6c.production_rime_pime_changed -and -not $e6c.bare_digit_selection_rules_changed)) `
    'production and bare-digit contracts must remain unchanged' `
    'e6c: production registration or bare-digit candidate contract changed'

$e6cAuditPath = [string]$e6c.independence_audit_path
$e6cAuditHashValid = Test-EvidenceHash $e6cAuditPath ([string]$e6c.independence_audit_sha256)
$e6cAudit = if ($e6cAuditHashValid) { Read-JsonEvidence $e6cAuditPath 'E6-C independence audit' } else { $null }
Add-ReadinessCheck 'e6c_audit_hash' $e6cAuditHashValid $e6cAuditPath `
    'e6c: independence audit is missing or its SHA-256 does not match the summary'
Add-ReadinessCheck 'e6c_audit_passed' `
    ([bool]($null -ne $e6cAudit -and $e6cAudit.passed -and
        [string]$e6cAudit.manifest_sha256 -eq [string]$e6c.package_manifest_sha256)) `
    'staged package audit and manifest identity' `
    'e6c: staged package independence audit or manifest identity failed'

$requiredE6D = @(
    'passed',
    'package_integrity_passed',
    'install_metadata_consistency_passed',
    'required_independent_components_passed',
    'x64_x86_arm64_machine_types_passed',
    'forbidden_rime_pime_artifacts_absent',
    'forbidden_rime_pime_pe_imports_absent',
    'forbidden_go_runtime_dependencies_absent',
    'runtime_package_convergence_passed',
    'current_user_autostart_convergence_passed',
    'production_registration_unchanged'
)
$failedE6D = @($requiredE6D | Where-Object { -not [bool]$e6d.$_ })
Add-ReadinessCheck 'e6d_required_gates' ($failedE6D.Count -eq 0) `
    $(if ($failedE6D.Count) { $failedE6D -join ', ' } else { 'all required E6-D gates passed' }) `
    'e6d: one or more installed package, dependency or registration gates failed'
Add-ReadinessCheck 'e6d_read_only' ([bool](-not $e6d.installer_or_registration_command_executed)) `
    'read-only audit required' 'e6d: readiness evidence performed an installer or registration mutation'

$autostartPath = [string]$e6d.autostart_evidence_path
$autostartHashValid = Test-EvidenceHash $autostartPath ([string]$e6d.autostart_evidence_sha256)
$autostart = if ($autostartHashValid) { Read-JsonEvidence $autostartPath 'E6-D autostart' } else { $null }
Add-ReadinessCheck 'e6d_autostart_evidence' `
    ([bool]($null -ne $autostart -and
        [string]$autostart.schema_version -eq 'yimecore-e6c-autostart-repair-v1' -and
        [string]$autostart.registry_reader -eq 'StdRegProv/HKEY_USERS' -and
        $autostart.system_registry_verified -and
        $autostart.passed -and $autostart.validated_only -and
        -not $autostart.registry_mutation_requested -and $autostart.after.exists -and
        [string]$autostart.after.kind -eq 'String' -and
        [string]$autostart.after.value -ceq [string]$autostart.expected_value -and
        [string]$autostart.expected_value -ceq ('"{0}" -no-toolbar' -f [string]$e6d.runtime_executable) -and
        [string]$autostart.package_manifest_sha256 -eq [string]$e6d.package_manifest_sha256 -and
        [string]$autostart.install_root -eq [string]$e6d.package_root)) `
    $autostartPath 'e6d: matching read-only current-user autostart evidence is missing or invalid'

$e6dAuditPath = [string]$e6d.package_audit_path
$e6dAuditHashValid = Test-EvidenceHash $e6dAuditPath ([string]$e6d.package_audit_sha256)
$e6dAudit = if ($e6dAuditHashValid) { Read-JsonEvidence $e6dAuditPath 'E6-D package audit' } else { $null }
Add-ReadinessCheck 'e6d_audit_hash' $e6dAuditHashValid $e6dAuditPath `
    'e6d: package audit is missing or its SHA-256 does not match the summary'
Add-ReadinessCheck 'e6d_audit_passed' `
    ([bool]($null -ne $e6dAudit -and $e6dAudit.passed -and
        [string]$e6dAudit.manifest_sha256 -eq [string]$e6d.package_manifest_sha256)) `
    'installed package audit and manifest identity' `
    'e6d: installed package audit or manifest identity failed'

$activeMatchesStaged = [string]$e6c.package_manifest_sha256 -eq [string]$e6d.package_manifest_sha256
Add-ReadinessCheck 'active_package_matches_clean_staged_package' $activeMatchesStaged `
    "staged=$($e6c.package_manifest_sha256); active=$($e6d.package_manifest_sha256)" `
    'deployment: the active trial package is not the latest clean staged package'

$external = $null
if (-not [string]::IsNullOrWhiteSpace($ExternalEvidencePath)) {
    $external = Read-JsonEvidence $ExternalEvidencePath 'E7 external'
}
$externalSchemaValid = $null -ne $external -and
    [string]$external.schema_version -eq 'yimecore-e7-external-evidence-v1'
$approvedSignerThumbprint = if ($externalSchemaValid) {
    ([string]$external.approved_signer_thumbprint).Replace(' ', '').ToUpperInvariant()
} else { '' }

$signatureEvidence = @()
$signedPackageSupplied = -not [string]::IsNullOrWhiteSpace($SignedPackageRoot)
$signedPackageValid = $false
$signatureBlocker = 'signing: 签名证书正在申请，等候审批，暂缓相关事项'
if ($signedPackageSupplied) {
    $signedRoot = [IO.Path]::GetFullPath($SignedPackageRoot)
    if (Test-Path -LiteralPath $signedRoot -PathType Container) {
        $peFiles = @(Get-ChildItem -LiteralPath $signedRoot -Recurse -File | Where-Object {
            $_.Extension -in @('.exe', '.dll')
        })
        $signatureEvidence = @($peFiles | ForEach-Object {
            $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
            [ordered]@{
                path = [IO.Path]::GetRelativePath($signedRoot, $_.FullName).Replace('\', '/')
                status = [string]$signature.Status
                signer_thumbprint = if ($signature.SignerCertificate) {
                    [string]$signature.SignerCertificate.Thumbprint
                } else { '' }
            }
        })
        $invalidSignatures = @($signatureEvidence | Where-Object { $_.status -ne 'Valid' })
        $signerThumbprints = @($signatureEvidence.signer_thumbprint | Where-Object { $_ } | Sort-Object -Unique)
        $signedPackageValid = $signatureEvidence.Count -gt 0 -and $invalidSignatures.Count -eq 0 -and
            $signerThumbprints.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($approvedSignerThumbprint) -and
            $signerThumbprints[0].Equals($approvedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)
        $signatureBlocker = if ($signatureEvidence.Count -eq 0) {
            'signing: signed package root contains no PE files'
        } elseif ($invalidSignatures.Count -ne 0) {
            "signing: $($invalidSignatures.Count) package PE file(s) have missing or invalid Authenticode signatures"
        } elseif ([string]::IsNullOrWhiteSpace($approvedSignerThumbprint)) {
            'signing: approved signer thumbprint is missing from reviewed external evidence'
        } elseif ($signerThumbprints.Count -ne 1 -or
            -not $signerThumbprints[0].Equals($approvedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)) {
            'signing: package signer does not match the approved publisher certificate'
        } else { '' }
    } else {
        $signatureBlocker = 'signing: signed package root does not exist'
    }
}
if ($signedPackageSupplied) {
    Add-ReadinessCheck 'trusted_signed_package' $signedPackageValid `
        "checked $($signatureEvidence.Count) PE files" $signatureBlocker
} else {
    Add-DeferredCheck 'trusted_signed_package' '签名证书正在申请，等候审批，暂缓相关事项'
}

Add-ReadinessCheck 'external_evidence_schema' $externalSchemaValid `
    $(if ($null -eq $external) { 'not supplied' } else { [string]$external.schema_version }) `
    'external-evidence: reviewed current-machine host and rollback evidence is missing or has the wrong schema'

$externalRequirements = [ordered]@{
    broader_third_party_host_matrix_passed = 'host-matrix: broader native-x64 desktop-host acceptance on this development machine is pending'
    rollback_rehearsal_passed = 'rollback: independent package to production fallback rehearsal is pending'
    first_release_retention_plan_approved = 'rollback: first independent release retention plan for RimeAdapter and old installer is pending'
}
foreach ($name in $externalRequirements.Keys) {
    $passed = [bool]($externalSchemaValid -and $external.$name)
    Add-ReadinessCheck $name $passed $(if ($passed) { 'passed' } else { 'missing or false' }) `
        $externalRequirements[$name]
}
foreach ($name in @('arm64_desktop_host_passed', 'x86_desktop_host_passed',
    'mainstream_physical_host_passed', 'forward_physical_host_passed', 'legacy_x64_host_passed',
    'simulated_hardware_tiers_passed')) {
    Add-DeferredCheck $name 'Frozen by user decision; no execution or compatibility claim until explicit resumption after local independent-core usability.'
}
Add-ReadinessCheck 'external_development_scope' `
    (Test-YimeCoreScopeEvidence $external.development_scope $developmentScope) `
    'host/rollback approvals must identify this machine and the current scope' `
    'external-evidence: approvals do not identify the current development scope'

$warnings.Add('E3 per-run 1.10 microbenchmark tail remains a non-blocking warning; use supplied measurements for current absolute deltas.')
$warnings.Add("E3 strict learning ratio gate in supplied performance evidence: $([bool]$performance.all_learning_latency_gates_passed).")
$warnings.Add('The retired legacy Windows 10/SATA tier is not part of the active release blocker set.')
$ready = $blockers.Count -eq 0
$summaryPath = Join-Path $outputDir 'summary.json'
[ordered]@{
    schema_version = 'yimecore-e7-cutover-readiness-v1'
    development_scope = $developmentScope
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $currentCommit
    git_dirty = -not $workingTreeClean
    e6c_summary_path = $e6cSummaryPathValue
    e6c_summary_sha256 = (Get-FileHash -LiteralPath $e6cSummaryPathValue -Algorithm SHA256).Hash.ToLowerInvariant()
    e6d_summary_path = $e6dSummaryPathValue
    e6d_summary_sha256 = (Get-FileHash -LiteralPath $e6dSummaryPathValue -Algorithm SHA256).Hash.ToLowerInvariant()
    performance_summary_path = $performanceSummaryPathValue
    performance_summary_sha256 = (Get-FileHash -LiteralPath $performanceSummaryPathValue -Algorithm SHA256).Hash.ToLowerInvariant()
    staged_package_root = [string]$e6c.package_root
    active_package_root = [string]$e6d.package_root
    signed_package_root = if ($signedPackageSupplied) { [IO.Path]::GetFullPath($SignedPackageRoot) } else { '' }
    external_evidence_path = if ($external) { [IO.Path]::GetFullPath($ExternalEvidencePath) } else { '' }
    checks = $checks
    deferred_checks = $deferredChecks
    signature_evidence = $signatureEvidence
    approved_signer_thumbprint = $approvedSignerThumbprint
    blockers = $blockers
    warnings = $warnings
    ready_for_development_host_milestone = $ready
    ready_for_cutover_proposal = $false # Local development readiness does not approve a public/production cutover.
    production_rime_pime_changed = $false
    cutover_or_registration_command_executed = $false
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeCore E7 cutover readiness evidence: $summaryPath"
if (-not $ready) {
    throw "E7 cutover readiness is blocked by $($blockers.Count) item(s); see $summaryPath"
}
