[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope = Get-YimeCoreDevelopmentScope
$policy = Get-Content (Join-Path $PSScriptRoot 'development-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$results = [Collections.Generic.List[object]]::new()
function Assert-ScopeTest([bool]$Passed, [string]$Name) {
    if (-not $Passed) { throw "Development scope regression failed: $Name" }
    $results.Add([ordered]@{ name = $Name; passed = $true })
}
Assert-ScopeTest (@($policy.active_architectures).Count -eq 2 -and
    $policy.active_architectures[0] -eq 'x64' -and $policy.active_architectures[1] -eq 'x86' -and
    @($policy.frozen_targets) -notcontains 'x86') 'x86_wow64_surface_resumed'
Assert-ScopeTest (@($policy.frozen_targets) -notcontains 'arm64' -and
    @($policy.experiment_targets).Count -eq 2 -and
    @($policy.frozen_targets) -contains 'simulated_hardware_tiers') 'approved_platform_experiments_resumed'
Assert-ScopeTest ((Get-YimeCoreExperimentTarget 'arm64').go_arch -eq 'arm64') 'arm64_native_mapping'
Assert-ScopeTest ((Get-YimeCoreExperimentTarget 'mainstream_x64').cmake_platform -eq 'x64') 'mainstream_native_mapping'
$mainstreamHost=(Get-YimeCoreExperimentTarget 'mainstream_x64').physical_host
Assert-ScopeTest ($mainstreamHost.computer_name -ceq '计算机' -and $mainstreamHost.owner -ceq 'developer' -and
    (@($mainstreamHost.approved_uses) -join '|') -ceq 'source_build|isolated_native_contracts|target_package_transactions') 'mainstream_physical_host_identified'
foreach ($target in @('unlisted', 'x86', 'forward_looking', '')) {
    $rejected=$false
    try { $null=Get-YimeCoreExperimentTarget $target } catch { $rejected=$true }
    Assert-ScopeTest $rejected ('unlisted_target_rejected_' + $target)
}
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

$x86BuilderPath = Join-Path $PSScriptRoot 'build-local-x86-surface.ps1'
$x86Builder = Get-Content -LiteralPath $x86BuilderPath -Raw
$x86Tokens = $null; $x86ParseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($x86BuilderPath, [ref]$x86Tokens, [ref]$x86ParseErrors)
Assert-ScopeTest ($x86ParseErrors.Count -eq 0 -and $x86Builder -match "-A Win32" -and
    $x86Builder -match "-DYIME_LOCAL_PRODUCT=ON" -and
    $x86Builder -match "local-product-build-common.ps1" -and
    $x86Builder -notmatch "register-com|Manage-YimeCoreTrial") 'current_identity_x86_build_isolated_from_registration'
$performanceScript = Get-Content (Join-Path $PSScriptRoot 'run-yimecore-tier-performance.ps1') -Raw
Assert-ScopeTest ($performanceScript -notmatch '& \$tierRunner|-core-percent|-affinity-mask' -and
    $performanceScript -match '& \$benchTool' -and $performanceScript -match '& \$rimeTool') 'no_hardware_simulation'
$profiles = Get-Content (Join-Path $PSScriptRoot 'performance-tiers.json') -Raw | ConvertFrom-Json
Assert-ScopeTest (@($profiles.profiles).Count -eq 1 -and $profiles.profiles[0].id -eq 'development_host_x64') 'single_native_profile'
Assert-ScopeTest (@($profiles.experiment_profiles).Count -eq 2 -and
    ($profiles.experiment_profiles.id -join '|') -eq 'mainstream|arm64') 'physical_experiment_profiles'
Write-Output ("PASS: development source target policy checks: " + $results.Count)
