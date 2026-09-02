[CmdletBinding()]
param(
    [ValidateRange(10, 10000)]
    [int]$Iterations = 100,
    [ValidateRange(10, 10000)]
    [int]$LearningIterations = 100,
    [string]$OutputRoot,
    [string]$InstalledRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$developmentScope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$testDataRoot = Join-Path $goBackend 'input_methods\yime\yimecore\testdata'
$profilePath = Join-Path $PSScriptRoot 'performance-tiers.json'
$profiles = (Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json)
if (@($profiles.profiles).Count -ne 1 -or $profiles.profiles[0].id -ne $developmentScope.performance_profile) {
    throw 'Only the development-host x64 performance profile is active; other hardware tiers are frozen.'
}
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-tier-performance'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [System.IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Performance evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if ([string]::IsNullOrWhiteSpace($InstalledRoot)) {
    $runtimeConfigPath = Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial\runtime-config.json'
    $runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $InstalledRoot = [string]$runtimeConfig.install_root
    if ([string]::IsNullOrWhiteSpace($InstalledRoot)) { throw 'Active runtime configuration has no install_root.' }
}
$InstalledRoot = [System.IO.Path]::GetFullPath($InstalledRoot)

$binDir = Join-Path $outputDir 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$benchTool = Join-Path $binDir 'yimecore-index-bench.exe'
$rimeTool = Join-Path $binDir 'yimecore-rime-compare.exe'
$learningTool = Join-Path $binDir 'yimecore-learning-experiment.exe'
$testLog = Join-Path $outputDir 'go-test.txt'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-index-bench ./cmd/yimecore-rime-compare ./cmd/yimecore-learning-experiment 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "Performance prerequisite tests failed; see $testLog" }
    & go build -o $benchTool ./cmd/yimecore-index-bench
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index-bench.' }
    & go build -o $rimeTool ./cmd/yimecore-rime-compare
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-rime-compare.' }
    & go build -o $learningTool ./cmd/yimecore-learning-experiment
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-learning-experiment.' }
}
finally {
    Pop-Location
}

$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, BusType, Size
$powerPlan = (& powercfg /getactivescheme) -join ''
$hostEvidence = [ordered]@{
    development_scope = $developmentScope
    measurement_policy = 'native-unthrottled-no-affinity-override'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    computer_model = $computer.Model
    cpu = $processor.Name
    physical_cores = $processor.NumberOfCores
    logical_processors = $processor.NumberOfLogicalProcessors
    memory_bytes = [uint64]$computer.TotalPhysicalMemory
    os_caption = $os.Caption
    os_version = $os.Version
    os_build = $os.BuildNumber
    power_plan = $powerPlan.Trim()
    disks = @($disks)
    go_version = (& go version)
    installed_root = $InstalledRoot
    installed_manifest_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $InstalledRoot 'package-manifest.json')).Hash.ToLowerInvariant()
}
$hostEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDir 'host.json') -Encoding utf8
Copy-Item -LiteralPath $profilePath -Destination (Join-Path $outputDir 'performance-tiers.json')

$definitions = @(
    [ordered]@{ mode = 'full'; index = 'full.yidx' },
    [ordered]@{ mode = 'variable'; index = 'variable.yidx' },
    [ordered]@{ mode = 'shorthand'; index = 'shorthand.yidx' }
)
$previousPath = $env:PATH
$env:PATH = (Join-Path $goBackend 'input_methods\yime') + ';' + $env:PATH
$rows = @()
try {
    foreach ($profile in $profiles.profiles) {
        $profileDir = Join-Path $outputDir $profile.id
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
        foreach ($stage in @('e1', 'e2')) {
            $probePath = Join-Path $testDataRoot ($(if ($stage -eq 'e1') { 'e1_probes.json' } else { 'e2_sentence_probes.json' }))
            foreach ($definition in $definitions) {
                $mode = $definition.mode
                $indexPath = Join-Path $InstalledRoot ('indexes\' + $definition.index)
                if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { throw "Missing installed index: $indexPath" }
                $prefix = "$stage-$mode"
                $yimePath = Join-Path $profileDir "$prefix-yime.json"
                & $benchTool -index $indexPath -probes $probePath -mode $mode -iterations $Iterations -output $yimePath
                $yimeExit = $LASTEXITCODE
                if (-not (Test-Path -LiteralPath $yimePath)) { throw "YimeCore $prefix did not emit evidence (exit $yimeExit)." }

                $rimePath = Join-Path $profileDir "$prefix-rime.json"
                & $rimeTool -data-root $dataRoot -probes $probePath -mode $mode -iterations $Iterations -output $rimePath
                $rimeExit = $LASTEXITCODE
                if (-not (Test-Path -LiteralPath $rimePath)) { throw "Rime $prefix did not emit evidence (exit $rimeExit)." }

                $yime = Get-Content -LiteralPath $yimePath -Raw | ConvertFrom-Json
                $rime = Get-Content -LiteralPath $rimePath -Raw | ConvertFrom-Json
                $rimeMode = $rime.modes[0]
                $budgetName = if ($stage -eq 'e1') { 'e1_complete_9_probe_set_p95' } else { 'e2_complete_5_probe_set_p95' }
                $budgetMS = [double]$profiles.provisional_interaction_budgets_ms.$budgetName
                $privateBudget = [uint64]$profile.private_memory_budget_mb * 1MB
                $rows += [ordered]@{
                    profile = $profile.id
                    stage = $stage
                    mode = $mode
                    yime_p95_ns = [int64]$yime.latency.p95_ns
                    rime_p95_ns = [int64]$rimeMode.latency.p95_ns
                    p95_ratio_yime_over_rime = [double]$yime.latency.p95_ns / [double]$rimeMode.latency.p95_ns
                    yime_private_bytes = [uint64]$yime.process_memory.private_bytes
                    rime_private_bytes = [uint64]$rime.process_memory.private_bytes
                    correctness_passed = [bool]$yime.passed -and [bool]$rime.passed
                    interaction_budget_passed = ([double]$yime.latency.p95_ns / 1e6) -le $budgetMS
                    memory_budget_passed = [uint64]$yime.process_memory.private_bytes -le $privateBudget
                    yime_evidence = $yimePath
                    rime_evidence = $rimePath
                }
            }
        }

    }

    # A Job Object enforces quota at process scheduling intervals, so charging
    # those waits to either the static or learned half creates arbitrary ratio
    # spikes. Keep E3's relative-cost gate on the native host with interleaved
    # samples. E1/E2 also run naturally on this host in the current phase.
    $learningDir = Join-Path $outputDir 'e3-native-host'
    New-Item -ItemType Directory -Force -Path $learningDir | Out-Null
    foreach ($definition in $definitions) {
        $mode = $definition.mode
        $modeDir = Join-Path $learningDir $mode
        New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
        $learningPath = Join-Path $modeDir 'learning.json'
        $modelPath = Join-Path $modeDir 'model.json'
        & $learningTool -index (Join-Path $InstalledRoot ('indexes\' + $definition.index)) -mode $mode `
            -model $modelPath -iterations $LearningIterations -batch-size 5000 -output $learningPath
        $learningExit = $LASTEXITCODE
        if (-not (Test-Path -LiteralPath $learningPath)) { throw "Learning $mode did not emit evidence (exit $learningExit)." }
        $learning = Get-Content -LiteralPath $learningPath -Raw | ConvertFrom-Json
        $rows += [ordered]@{
            profile = 'native_host_interleaved'
            stage = 'e3'
            mode = $mode
            static_p95_ns = [int64]$learning.static_latency.p95_ns
            learned_p95_ns = [int64]$learning.learned_latency.p95_ns
            p95_overhead_ratio = [double]$learning.p95_overhead_ratio
            p99_overhead_ratio = [double]$learning.p99_overhead_ratio
            correctness_passed = [bool]$learning.promotion_passed -and [bool]$learning.persistence_passed -and [bool]$learning.context_passed -and [bool]$learning.forget_passed
            latency_gate_passed = [bool]$learning.latency_gate_passed
            evidence = $learningPath
        }
    }
}
finally {
    $env:PATH = $previousPath
}

$summary = [ordered]@{
    tool_version = 'yimecore-tier-performance-v1'
    development_scope = $developmentScope
    measurement_policy = 'native-unthrottled-no-affinity-override'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    iterations = $Iterations
    learning_iterations = $LearningIterations
    profile_source = $profilePath
    host_evidence = (Join-Path $outputDir 'host.json')
    rows = $rows
    all_correctness_passed = -not ($rows.correctness_passed -contains $false)
    all_interaction_budgets_passed = -not (($rows | Where-Object stage -in @('e1', 'e2')).interaction_budget_passed -contains $false)
    all_memory_budgets_passed = -not (($rows | Where-Object stage -in @('e1', 'e2')).memory_budget_passed -contains $false)
    all_learning_latency_gates_passed = -not (($rows | Where-Object stage -eq 'e3').latency_gate_passed -contains $false)
    limitations = $profiles.limitations
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$sourceFiles = @(
    'go-backend/input_methods/yime/yimecore/indexfile.go',
    'go-backend/input_methods/yime/yimecore/engine.go',
    'go-backend/input_methods/yime/yimecore/sentence.go',
    'go-backend/input_methods/yime/yimecore/construction.go',
    'go-backend/input_methods/yime/yimecore/model_read_cache.go',
    'go-backend/input_methods/yime/yimecore/usermodel.go',
    'go-backend/input_methods/yime/yimecore/indexfile_test.go',
    'go-backend/cmd/yimecore-learning-experiment/main.go',
    'go-backend/cmd/yimecore-tier-runner/main_windows.go',
    'tools/yimecore/performance-tiers.json',
    'tools/yimecore/development-scope.ps1',
    'tools/yimecore/development-scope.json',
    'tools/yimecore/run-yimecore-tier-performance.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $absolute = Join-Path $repoRoot $relative
    [ordered]@{ path = $relative; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToLowerInvariant() }
}
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $outputDir 'source-hashes.json') -Encoding utf8
Write-Host "YimeCore tier performance evidence: $outputDir"
Write-Host "Summary: $summaryPath"
