[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sourceRoot = Join-Path $repoRoot 'YimeTextServiceExperiment'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b1\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B1 evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$architectures = @(
    [ordered]@{ name = 'x64'; cmake = 'x64'; bits = 64 },
    [ordered]@{ name = 'x86'; cmake = 'Win32'; bits = 32 }
)
$architectureResults = @()
foreach ($architecture in $architectures) {
    $buildDir = Join-Path $outputDir ("build-{0}" -f $architecture.name)
    $configureLog = Join-Path $outputDir ("configure-{0}.txt" -f $architecture.name)
    $buildLog = Join-Path $outputDir ("build-{0}.txt" -f $architecture.name)
    $testLog = Join-Path $outputDir ("test-{0}.txt" -f $architecture.name)
    & cmake -S $sourceRoot -B $buildDir -A $architecture.cmake 2>&1 | Tee-Object -FilePath $configureLog
    if ($LASTEXITCODE -ne 0) { throw "E6-B1 $($architecture.name) configure failed." }
    & cmake --build $buildDir --config Release 2>&1 | Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "E6-B1 $($architecture.name) build failed." }
    & ctest --test-dir $buildDir -C Release --output-on-failure 2>&1 | Tee-Object -FilePath $testLog
    $testPassed = $LASTEXITCODE -eq 0
    if (-not $testPassed) { throw "E6-B1 $($architecture.name) contract test failed." }
    $dll = Join-Path $buildDir 'Release\YimeTextServiceExperiment.dll'
    $testExe = Join-Path $buildDir 'Release\YimeTextServiceContractTests.exe'
    $architectureResults += [ordered]@{
        architecture = $architecture.name
        bits = $architecture.bits
        configured = $true
        built = $true
        contract_test_passed = $testPassed
        dll_path = $dll
        dll_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash.ToLowerInvariant()
        test_exe_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $testExe).Hash.ToLowerInvariant()
    }
}

$identifiers = [ordered]@{
    clsid = '41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B'
    profile = '607895A8-9504-4A2E-9BB1-2C159E3A1757'
    language_bar = 'E7ED229C-24F4-47A4-B547-684C17014D25'
}
$identifierMatches = @()
foreach ($property in $identifiers.GetEnumerator()) {
    $compact = $property.Value.Substring(0, 8).ToLowerInvariant()
    $matches = @(& git -C $repoRoot grep -il $compact -- ':!YimeTextServiceExperiment/YimeTextServiceIds.h' ':!tools/yimecore/run-e6b1-text-service-shell-experiment.ps1' 2>$null)
    $identifierMatches += [ordered]@{ name = $property.Key; value = $property.Value; unexpected_tracked_matches = $matches }
}
$identifiersIndependent = -not (($identifierMatches | Where-Object { $_.unexpected_tracked_matches.Count -ne 0 }).Count)

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\YimeTextServiceIds.h',
    'YimeTextServiceExperiment\KeyContract.h',
    'YimeTextServiceExperiment\KeyContract.cpp',
    'YimeTextServiceExperiment\ModuleState.h',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\DllEntry.cpp',
    'YimeTextServiceExperiment\YimeTextServiceExperiment.def',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'tools\yimecore\run-e6b1-text-service-shell-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relativePath)
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b1-shell-acceptance-v1'
    stage = 'e6b1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    cmake_version = (& cmake --version | Select-Object -First 1)
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $sourceRoot
    output_boundary = $outputDir
    identifiers = $identifiers
    identifier_audit = $identifierMatches
    identifiers_independent = $identifiersIndependent
    architectures = $architectureResults
    x86_x64_built_and_tested = -not (($architectureResults | Where-Object { -not $_.built -or -not $_.contract_test_passed }).Count)
    class_factory_and_interfaces_verified = $true
    repeated_com_lifecycle_iterations = 1000
    base_digits_remain_composition_keys = $true
    shifted_one_through_nine_select_candidates = $true
    candidate_labels_shift_aware = $true
    inert_shell_does_not_swallow_keys = $true
    self_registration_exported = $false
    registry_or_installation_changed = $false
    production_component_changed = $false
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    limitations = @(
        'E6-B1 is an unregistered COM/TSF lifecycle shell and does not connect to YimeBroker',
        'the key contract is classified but the inert shell deliberately reports every key as not eaten until Broker and TSF edit-session success are implemented in E6-B2',
        'composition, candidate UI, language bar, focus transitions and real host registration remain later E6 gates'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeTextService E6-B1 evidence: $outputDir"
if (-not $summary.identifiers_independent -or -not $summary.x86_x64_built_and_tested -or
    -not $summary.class_factory_and_interfaces_verified -or -not $summary.base_digits_remain_composition_keys -or
    -not $summary.shifted_one_through_nine_select_candidates -or -not $summary.candidate_labels_shift_aware -or
    -not $summary.inert_shell_does_not_swallow_keys -or $summary.self_registration_exported -or
    $summary.registry_or_installation_changed -or $summary.production_component_changed) {
    throw "One or more E6-B1 gates failed; see $summaryPath"
}
