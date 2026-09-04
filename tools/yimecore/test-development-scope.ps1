[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope = Get-YimeCoreDevelopmentScope
$policy = Get-Content (Join-Path $PSScriptRoot 'development-scope.json') -Raw | ConvertFrom-Json
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$results = [Collections.Generic.List[object]]::new()
function Assert-ScopeTest([bool]$Passed, [string]$Name) {
    if (-not $Passed) { throw "Development scope regression failed: $Name" }
    $results.Add([ordered]@{ name = $Name; passed = $true })
}
Assert-ScopeTest (@($policy.active_architectures).Count -eq 2 -and
    $policy.active_architectures[0] -eq 'x64' -and $policy.active_architectures[1] -eq 'x86' -and
    @($policy.frozen_targets) -notcontains 'x86') 'x86_wow64_surface_resumed'
Assert-ScopeTest (@($policy.frozen_targets) -contains 'arm64' -and
    @($policy.frozen_targets) -contains 'other_physical_pcs' -and
    @($policy.frozen_targets) -contains 'simulated_hardware_tiers') 'unavailable_targets_remain_frozen'
foreach ($case in @(
    @{ name = 'approved_host'; hostName = $policy.computer_name; arch = 'AMD64'; bits = $true; reject = $false },
    @{ name = 'other_pc'; hostName = 'NOT-THE-DEVELOPMENT-PC'; arch = 'AMD64'; bits = $true; reject = $true },
    @{ name = 'arm64'; hostName = $policy.computer_name; arch = 'ARM64'; bits = $true; reject = $true },
    @{ name = 'x86_orchestration_shell'; hostName = $policy.computer_name; arch = 'x86'; bits = $false; reject = $true },
    @{ name = 'wow64_shell'; hostName = $policy.computer_name; arch = 'AMD64'; bits = $false; reject = $true }
)) {
    $rejected = $false
    try { Assert-YimeCoreDevelopmentHost $policy $case.hostName $case.arch $case.bits } catch { $rejected = $true }
    Assert-ScopeTest ($rejected -eq $case.reject) $case.name
}
foreach ($target in @(@('windows', 'amd64'), @('windows', '386'), @('windows', 'arm64'), @('linux', 'amd64'))) {
    # The Go core remains native amd64. Resumed x86 is a Win32 TSF surface.
    function go { $global:LASTEXITCODE = 0; $target }
    $rejected = $false
    try { Assert-YimeCoreNativeGo } catch { $rejected = $true }
    Assert-ScopeTest ($rejected -eq ($target[0] -ne 'windows' -or $target[1] -ne 'amd64')) ($target -join '/')
    Remove-Item Function:go
}

$builder = Get-Content (Join-Path $PSScriptRoot 'run-e6c-package-experiment.ps1') -Raw
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($builder, [ref]$tokens, [ref]$parseErrors)
Assert-ScopeTest ($parseErrors.Count -eq 0) 'builder_parses'
$loop = @($ast.FindAll({ param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'architecture'
}, $true))
Assert-ScopeTest ($loop.Count -eq 1 -and $loop[0].Condition.Extent.Text -match "name = 'x64'" -and
    $loop[0].Condition.Extent.Text -notmatch 'x86|Win32|arm64') 'legacy_e6c_builder_remains_archival_x64'
$x86BuilderPath = Join-Path $PSScriptRoot 'build-local-x86-surface.ps1'
$x86Builder = Get-Content -LiteralPath $x86BuilderPath -Raw
$x86Tokens = $null; $x86ParseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($x86BuilderPath, [ref]$x86Tokens, [ref]$x86ParseErrors)
Assert-ScopeTest ($x86ParseErrors.Count -eq 0 -and $x86Builder -match "-A Win32" -and
    $x86Builder -match "-DYIME_LOCAL_PRODUCT=ON" -and
    $x86Builder -match "local-product-build-common.ps1" -and
    $x86Builder -notmatch "register-com|Manage-YimeCoreTrial") 'current_identity_x86_build_isolated_from_registration'
$upgrade = Get-Content (Join-Path $repoRoot 'Build-Install-YimeCore-Trial-v3.cmd') -Raw
Assert-ScopeTest ($upgrade -match 'package\\x64\\YimeRegisteredHostTests.exe' -and
    $upgrade -notmatch 'package\\(x86|arm64)\\YimeRegisteredHostTests.exe') 'upgrade_x64_only'
$performanceScript = Get-Content (Join-Path $PSScriptRoot 'run-yimecore-tier-performance.ps1') -Raw
Assert-ScopeTest ($performanceScript -notmatch '& \$tierRunner|-core-percent|-affinity-mask' -and
    $performanceScript -match '& \$benchTool' -and $performanceScript -match '& \$rimeTool') 'no_hardware_simulation'
$profiles = Get-Content (Join-Path $PSScriptRoot 'performance-tiers.json') -Raw | ConvertFrom-Json
Assert-ScopeTest (@($profiles.profiles).Count -eq 1 -and $profiles.profiles[0].id -eq 'development_host_x64') 'single_native_profile'
foreach ($entry in @('run-e6c-package-experiment.ps1', 'run-e6d-independence-readiness.ps1',
    'run-e7-cutover-readiness.ps1', 'run-yimecore-tier-performance.ps1')) {
    $source = Get-Content (Join-Path $PSScriptRoot $entry) -Raw
    Assert-ScopeTest ($source -match '\$developmentScope = Get-YimeCoreDevelopmentScope') ($entry + '_guarded')
}

# Derived fixtures test the readiness reducer only, never live acceptance.
$outputRoot = Join-Path $repoRoot ('.tmp\yimecore-experiment\e7-readiness\scope-regression-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
foreach ($case in @('local', 'old_unscoped', 'foreign_host', 'dual_tier', 'throttled', 'missing_mode')) {
    $caseRoot = Join-Path $outputRoot $case
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $fixtureScope = $scope | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    if ($case -eq 'old_unscoped') { $fixtureScope = $null }
    if ($case -eq 'foreign_host') { $fixtureScope.computer_name = 'OTHER-PC' }
    foreach ($name in @('e6c', 'e6d')) {
        @{ development_scope = $fixtureScope } | ConvertTo-Json -Depth 8 |
            Set-Content (Join-Path $caseRoot "$name.json") -Encoding utf8
    }
    $rows = @(foreach ($stage in @('e1', 'e2', 'e3')) {
        foreach ($mode in @('full', 'variable', 'shorthand')) {
            @{ stage = $stage; mode = $mode; profile = $(if ($stage -eq 'e3') { 'native_host_interleaved' } else { 'development_host_x64' }) }
        }
    })
    if ($case -eq 'dual_tier') { $rows[0].profile = 'mainstream'; $rows[1].profile = 'forward_looking' }
    if ($case -eq 'missing_mode') { $rows = @($rows | Where-Object mode -ne 'shorthand') }
    $measurement = if ($case -eq 'throttled') { 'simulated' } else { 'native-unthrottled-no-affinity-override' }
    @{ development_scope = $fixtureScope; rows = $rows; measurement_policy = $measurement } |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $caseRoot 'performance.json') -Encoding utf8
    @{ schema_version = 'yimecore-e7-external-evidence-v1'; development_scope = $fixtureScope } |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $caseRoot 'external.json') -Encoding utf8
    try {
        & (Join-Path $PSScriptRoot 'run-e7-cutover-readiness.ps1') -E6CSummaryPath (Join-Path $caseRoot 'e6c.json') `
            -E6DSummaryPath (Join-Path $caseRoot 'e6d.json') -PerformanceSummaryPath (Join-Path $caseRoot 'performance.json') `
            -ExternalEvidencePath (Join-Path $caseRoot 'external.json') -OutputRoot (Join-Path $caseRoot 'readiness')
    } catch {
        if ($_.Exception.Message -notmatch '^E7 cutover readiness is blocked by') { throw }
    }
    $result = Get-Content (Join-Path $caseRoot 'readiness\summary.json') -Raw | ConvertFrom-Json
    $scopeChecks = @($result.checks | Where-Object name -match '_development_scope$')
    $expectScope = $case -notin @('old_unscoped', 'foreign_host')
    Assert-ScopeTest ($scopeChecks.Count -eq 4 -and @($scopeChecks | Where-Object { $_.passed -ne $expectScope }).Count -eq 0) ($case + '_evidence_scope')
    $profileCheck = $result.checks | Where-Object name -eq 'active_performance_profiles_only'
    Assert-ScopeTest ($profileCheck.passed -eq ($case -notin @('dual_tier', 'throttled'))) ($case + '_performance_policy')
    $coverageCheck = $result.checks | Where-Object name -eq 'development_host_performance_coverage'
    Assert-ScopeTest ($coverageCheck.passed -eq ($case -ne 'missing_mode')) ($case + '_mode_coverage')
    Assert-ScopeTest (@($result.deferred_checks).Count -eq 6 -and
        @($result.deferred_checks | Where-Object { $null -ne $_.passed -or $_.status -ne 'deferred' }).Count -eq 0 -and
        @($result.deferred_checks | Where-Object name -eq 'x86_desktop_host_passed').Count -eq 0 -and
        ($result.blockers -join ',') -notmatch 'ARM64|mainstream|forward/high-end|signing:') ($case + '_frozen_not_blocked_or_passed')
    foreach ($name in @('broader_third_party_host_matrix_passed', 'x86_desktop_host_passed',
        'rollback_rehearsal_passed', 'first_release_retention_plan_approved')) {
        $check = @($result.checks | Where-Object name -eq $name)
        Assert-ScopeTest ($check.Count -eq 1 -and -not $check[0].passed) ($case + '_' + $name)
    }
    Assert-ScopeTest (-not $result.ready_for_development_host_milestone -and -not $result.ready_for_cutover_proposal -and
        -not $result.production_rime_pime_changed -and -not $result.cutover_or_registration_command_executed) ($case + '_no_false_approval')
}
@{ schema_version = 'yimecore-development-scope-regression-v1'; passed = $true; cases = @($results.ToArray());
    development_scope = $scope; fixture_evidence_only = $true } | ConvertTo-Json -Depth 8 |
    Set-Content (Join-Path $outputRoot 'summary.json') -Encoding utf8
Write-Host "Development scope regressions passed ($($results.Count)): $outputRoot"
