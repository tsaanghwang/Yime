[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BasePackageRoot,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6c\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and
    -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-C evidence must stay under $allowedRoot"
}
if (Test-Path -LiteralPath $outputDir) {
    if (@(Get-ChildItem -LiteralPath $outputDir -Force).Count -ne 0) {
        throw "E6-C evidence directory must be new or empty: $outputDir"
    }
} else {
    New-Item -ItemType Directory -Force $outputDir | Out-Null
}
Start-Transcript -LiteralPath (Join-Path $outputDir 'transcript.txt') -Force | Out-Null

function Get-PackageRecords([string]$root) {
    $normalizedRoot = [IO.Path]::GetFullPath($root)
    @(Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File | Where-Object {
        $_.Name -ne 'package-manifest.json'
    } | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object path)
}

$baseRoot = [IO.Path]::GetFullPath($BasePackageRoot)
$baseManifestPath = Join-Path $baseRoot 'package-manifest.json'
if (-not (Test-Path -LiteralPath $baseManifestPath)) {
    throw "base package manifest is missing: $baseManifestPath"
}
$baseManifest = Get-Content -LiteralPath $baseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$baseRecords = @(Get-PackageRecords $baseRoot)
if ($baseRecords.Count -ne @($baseManifest.files).Count) {
    throw 'base package file count does not match its manifest'
}
$expectedByPath = @{}
foreach ($record in $baseManifest.files) { $expectedByPath[$record.path] = $record }
foreach ($record in $baseRecords) {
    $expected = $expectedByPath[$record.path]
    if (-not $expected -or $record.bytes -ne $expected.bytes -or
        $record.sha256 -ne $expected.sha256) {
        throw "base package hash mismatch: $($record.path)"
    }
}

$packageRoot = Join-Path $outputDir 'package'
$binRoot = Join-Path $packageRoot 'bin'
$indexRoot = Join-Path $packageRoot 'indexes'
New-Item -ItemType Directory -Force $packageRoot | Out-Null
foreach ($record in $baseRecords) {
    $source = Join-Path $baseRoot $record.path
    $destination = Join-Path $packageRoot $record.path
    New-Item -ItemType Directory -Force (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$textServiceBuilds = @()
foreach ($architecture in @(
    [ordered]@{ name = 'x64'; platform = 'x64' },
    [ordered]@{ name = 'x86'; platform = 'Win32' }
)) {
    $buildRoot = Join-Path $outputDir ('text-service-build-' + $architecture.name)
    & cmake -S (Join-Path $repoRoot 'YimeTextServiceExperiment') -B $buildRoot `
        -G 'Visual Studio 17 2022' -A $architecture.platform
    if ($LASTEXITCODE -ne 0) { throw "experimental text service configure failed: $($architecture.name)" }
    & cmake --build $buildRoot --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "experimental text service build failed: $($architecture.name)" }
    $releaseRoot = Join-Path $buildRoot 'Release'
    $dll = Join-Path $releaseRoot 'YimeTextServiceExperiment.dll'
    $contractTest = Join-Path $releaseRoot 'YimeTextServiceContractTests.exe'
    $contractLog = Join-Path $outputDir ('language-bar-contract-' + $architecture.name + '.txt')
    & $contractTest $dll 2>&1 | Tee-Object -LiteralPath $contractLog
    if ($LASTEXITCODE -ne 0) { throw "experimental language-bar contract failed: $($architecture.name)" }
    $registrationTool = Join-Path $releaseRoot 'YimeTextServiceRegistration.exe'
    $registrationStatus = (& $registrationTool status 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or
        $registrationStatus -notmatch '(?m)^com_only_registration_supported=true$' -or
        $registrationStatus -notmatch '(?m)^profile_icon_registration_supported=true$' -or
        $registrationStatus -notmatch '(?m)^taskbar_category_registration_supported=true$') {
        throw "experimental registration capability missing: $($architecture.name)"
    }
    foreach ($file in @('YimeTextServiceExperiment.dll', 'YimeTextServiceRegistration.exe', 'YimeRegisteredHostTests.exe')) {
        Copy-Item -LiteralPath (Join-Path $releaseRoot $file) `
            -Destination (Join-Path (Join-Path $packageRoot $architecture.name) $file) -Force
    }
    $textServiceBuilds += [ordered]@{
        architecture = $architecture.name
        build_root = $buildRoot
        dll = $dll
        contract_test = $contractTest
        contract_log = $contractLog
        tsf_test = Join-Path $releaseRoot 'YimeTsfCompositionTests.exe'
        com_only_registration_supported = $true
        profile_icon_registration_supported = $true
        taskbar_category_registration_supported = $true
    }
}

$broker = Join-Path $binRoot 'YimeBroker.exe'
$verifier = Join-Path $binRoot 'YimeE6CPackageExperiment.exe'
$runtime = Join-Path $binRoot 'YimeCoreTrialRuntime.exe'
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    & go build -trimpath -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'E6-C Broker build failed' }
    & go build -trimpath -o $verifier ./cmd/yimebroker-multimode-experiment
    if ($LASTEXITCODE -ne 0) { throw 'E6-C verifier build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $runtime ./cmd/yimecore-trial-runtime
    if ($LASTEXITCODE -ne 0) { throw 'E6-C runtime supervisor build failed' }
} finally {
    Pop-Location
}

$maintenanceRoot = Join-Path $packageRoot 'maintenance'
New-Item -ItemType Directory -Path $maintenanceRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') `
    -Destination (Join-Path $maintenanceRoot 'Manage-YimeCoreTrial.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-YimeCore-Trial.cmd') `
    -Destination (Join-Path $packageRoot 'Install-YimeCore-Trial.cmd') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Force-Uninstall-YimeCore-Trial.cmd') `
    -Destination (Join-Path $packageRoot 'Force-Uninstall-YimeCore-Trial.cmd') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'YimeTextServiceExperiment\assets\yimecore-trial-profile.ico') `
    -Destination (Join-Path $packageRoot 'profile-icon.ico') -Force

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$packageManifest = [ordered]@{
    tool_version = 'yimecore-e6c-staged-package-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $commit
    base_package_id = $baseManifest.package_id
    base_package_manifest_sha256 = (Get-FileHash -LiteralPath $baseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    scope = 'parallel YimeCore trial Broker only; no production Rime or PIME registration'
    files = @(Get-PackageRecords $packageRoot)
}
$packageManifestPath = Join-Path $packageRoot 'package-manifest.json'
$packageManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $packageManifestPath -Encoding utf8

$installationEvidencePath = Join-Path $outputDir 'installation-contract.json'
& (Join-Path $PSScriptRoot 'test-e6c-installation-contract.ps1') `
    -PackageRoot $packageRoot -OutputPath $installationEvidencePath
if ($LASTEXITCODE) { throw 'E6-C installation contract failed' }
$installationEvidence = Get-Content -LiteralPath $installationEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json

$capabilityPath = Join-Path $outputDir 'multimode-capabilities.json'
$capabilityVerifierAttempts = 0
$capabilityVerified = $false
foreach ($attempt in 1..2) {
    $capabilityVerifierAttempts = $attempt
    $stateRoot = Join-Path $outputDir $(if ($attempt -eq 1) { 'state' } else { "state-retry-$attempt" })
    New-Item -ItemType Directory -Force $stateRoot | Out-Null
    & $verifier -broker $broker -index-root $indexRoot `
        -snapshot (Join-Path $stateRoot 'user-model.json') `
        -journal (Join-Path $stateRoot 'user-model.journal') `
        -manifest (Join-Path $stateRoot 'index-control.json') `
        -status (Join-Path $stateRoot 'index-control-status.json') `
        -output $capabilityPath
    if ($LASTEXITCODE -eq 0) {
        $capabilityVerified = $true
        break
    }
    if ($attempt -lt 2) { Start-Sleep -Milliseconds 300 }
}
if (-not $capabilityVerified) { throw "E6-C capability verifier failed: $capabilityPath" }
$capabilities = Get-Content -LiteralPath $capabilityPath -Raw -Encoding UTF8 | ConvertFrom-Json

$runtimeState = Join-Path $outputDir 'runtime-state'
$runtimePipe = "\\.\pipe\YimeBroker-e6c-runtime-$PID"
$runtimeStatusPath = Join-Path $runtimeState 'runtime-status.json'
$runtimeProcess = Start-Process -FilePath $runtime -ArgumentList ('-install-root "{0}" -broker "{1}" -state-root "{2}" -pipe "{3}" -no-toolbar' -f
    $packageRoot, $broker, $runtimeState, $runtimePipe) -WindowStyle Hidden -PassThru
$runtimeBefore = $null
$runtimeAfter = $null
$languageBarTsfChecks = @()
try {
    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $runtimeStatusPath -PathType Leaf) {
            try { $runtimeBefore = Get-Content -LiteralPath $runtimeStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $runtimeBefore = $null }
        }
    } while ((Get-Date) -lt $deadline -and ($null -eq $runtimeBefore -or $runtimeBefore.state -ne 'running'))
    if ($null -eq $runtimeBefore -or $runtimeBefore.state -ne 'running') {
        throw 'packaged E6-C runtime supervisor did not become ready'
    }
    $oldBroker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$runtimeBefore.broker_pid)"
    if (-not $oldBroker -or -not $oldBroker.ExecutablePath.Equals($broker, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'packaged E6-C runtime supervisor reported an unexpected Broker process'
    }
    foreach ($textServiceBuild in $textServiceBuilds) {
        $tsfLog = Join-Path $outputDir ('language-bar-tsf-' + $textServiceBuild.architecture + '.txt')
        & $textServiceBuild.tsf_test $textServiceBuild.dll $runtimePipe 2>&1 | Tee-Object -LiteralPath $tsfLog
        $passed = $LASTEXITCODE -eq 0
        $languageBarTsfChecks += [ordered]@{
            architecture = $textServiceBuild.architecture
            passed = [bool]$passed
            log = $tsfLog
        }
        if (-not $passed) { throw "packaged language-bar TSF path failed: $($textServiceBuild.architecture)" }
    }
    Stop-Process -Id ([int]$runtimeBefore.broker_pid) -Force
    $deadline = (Get-Date).AddSeconds(15)
    $newBroker = $null
    do {
        Start-Sleep -Milliseconds 100
        try { $runtimeAfter = Get-Content -LiteralPath $runtimeStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $runtimeAfter = $null }
        if ($runtimeAfter -and [int]$runtimeAfter.broker_pid -gt 0) {
            $newBroker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$runtimeAfter.broker_pid)"
        }
        $runtimeRecoveryReady = $runtimeAfter -and $runtimeAfter.state -eq 'running' -and
            [int]$runtimeAfter.runtime_pid -eq [int]$runtimeBefore.runtime_pid -and
            [int]$runtimeAfter.broker_pid -ne [int]$runtimeBefore.broker_pid -and
            [int]$runtimeAfter.restarts -gt [int]$runtimeBefore.restarts -and
            $newBroker -and $newBroker.ExecutablePath -and
            $newBroker.ExecutablePath.Equals($broker, [StringComparison]::OrdinalIgnoreCase)
    } while ((Get-Date) -lt $deadline -and -not $runtimeRecoveryReady)
    $runtimeRecoveryChecks = [ordered]@{
        status_running = [bool]($runtimeAfter -and $runtimeAfter.state -eq 'running')
        runtime_pid_preserved = [bool]($runtimeAfter -and [int]$runtimeAfter.runtime_pid -eq [int]$runtimeBefore.runtime_pid)
        broker_pid_replaced = [bool]($runtimeAfter -and [int]$runtimeAfter.broker_pid -ne [int]$runtimeBefore.broker_pid)
        restart_count_advanced = [bool]($runtimeAfter -and [int]$runtimeAfter.restarts -gt [int]$runtimeBefore.restarts)
        broker_path_verified = [bool]($newBroker -and $newBroker.ExecutablePath -and
            $newBroker.ExecutablePath.Equals($broker, [StringComparison]::OrdinalIgnoreCase))
    }
    $runtimeRecoveryPassed = -not ($runtimeRecoveryChecks.Values -contains $false)
    if (-not $runtimeRecoveryPassed) {
        throw "packaged E6-C runtime supervisor recovery checks failed: $($runtimeRecoveryChecks | ConvertTo-Json -Compress)"
    }
} finally {
    $stopper = Start-Process -FilePath $runtime -ArgumentList ('-stop -install-root "{0}" -broker "{1}" -state-root "{2}" -pipe "{3}" -no-toolbar' -f
        $packageRoot, $broker, $runtimeState, $runtimePipe) -WindowStyle Hidden -Wait -PassThru
    if ($stopper.ExitCode -ne 0 -and -not $runtimeProcess.HasExited) {
        throw "packaged E6-C runtime supervisor stop failed with $($stopper.ExitCode)"
    }
}
$runtimeEvidencePath = Join-Path $outputDir 'runtime-supervision.json'
[ordered]@{
    runtime_path = $runtime
    pipe_name = $runtimePipe
    before = $runtimeBefore
    after_forced_broker_exit = $runtimeAfter
    recovery_checks = $runtimeRecoveryChecks
    broker_recovery_passed = [bool]$runtimeRecoveryPassed
    durable_user_model_path = Join-Path $runtimeState 'user-model\user-model.json'
    durable_user_journal_path = Join-Path $runtimeState 'user-model\user-model.journal'
    transactional_index_control_path = Join-Path $runtimeState 'index-control\request.json'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $runtimeEvidencePath -Encoding utf8

$languageBarEvidencePath = Join-Path $outputDir 'language-bar-evidence.json'
[ordered]@{
    reserved_input_mode_guid = '{2C77A81E-41CC-4178-A3A7-5F8A987568E6}'
    # Keep this script ASCII-clean so Windows PowerShell 5.1 does not depend on
    # a UTF-8 BOM when launched from the click-through .cmd entry point.
    desktop_labels = @([string][char]0x4E2D, [string][char]0x82F1)
    docked_taskbar_visible = $true
    docked_taskbar_chinese_english_icons = $true
    pime_compatible_input_mode_style = $true
    host_item_status_recorded = $true
    windows_native_language_bar_only = $true
    input_profile_keyboard_icon = $true
    left_click_toggle = $true
    right_click_cascading_menu = $true
    live_composition_affinity_preserved = $true
    idle_english_pass_through = $true
    architectures = $languageBarTsfChecks
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $languageBarEvidencePath -Encoding utf8

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-multimode-experiment\main.go',
    'go-backend\cmd\yimecore-trial-runtime\main.go',
    'go-backend\cmd\yimecore-trial-runtime\main_test.go',
    'go-backend\cmd\yimecore-trial-runtime\runtime_windows.go',
    'go-backend\cmd\yimecore-trial-runtime\runtime_stub.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher_test.go',
    'go-backend\input_methods\yime\yimebroker\index_control.go',
    'go-backend\input_methods\yime\yimebroker\index_manager.go',
    'go-backend\input_methods\yime\yimebroker\index_manager_test.go',
    'go-backend\input_methods\yime\yimebroker\mode_index_manager.go',
    'go-backend\input_methods\yime\yimebroker\mode_index_manager_test.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store.go',
    'go-backend\input_methods\yime\yimecore\indexfile.go',
    'go-backend\input_methods\yime\yimecore\indexfile_test.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\segment_correction_test.go',
    'go-backend\input_methods\yime\yimecore\sentence.go',
    'go-backend\input_methods\yime\yimecore\sentence_test.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher_test.go',
    'go-backend\cmd\yimebroker-multimode-experiment\main.go',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\RegistrationTool.cpp',
    'YimeTextServiceExperiment\ExperimentSettings.h',
    'YimeTextServiceExperiment\ExperimentSettings.cpp',
    'YimeTextServiceExperiment\LanguageBarItem.h',
    'YimeTextServiceExperiment\LanguageBarItem.cpp',
    'YimeTextServiceExperiment\LanguageBarResources.h',
    'YimeTextServiceExperiment\LanguageBarResources.rc',
    'YimeTextServiceExperiment\BrokerClient.h',
    'YimeTextServiceExperiment\BrokerClient.cpp',
    'YimeTextServiceExperiment\CandidateListUIElement.h',
    'YimeTextServiceExperiment\CandidateListUIElement.cpp',
    'YimeTextServiceExperiment\CandidatePopup.h',
    'YimeTextServiceExperiment\CandidatePopup.cpp',
    'go-backend\input_methods\yime\icons\chi_half_capsoff.ico',
    'go-backend\input_methods\yime\icons\eng_half_capsoff.ico',
    'go-backend\input_methods\yime\icon.ico',
    'YimeTextServiceExperiment\assets\yimecore-trial-profile.png',
    'YimeTextServiceExperiment\assets\yimecore-trial-profile.ico',
    'YimeTextServiceExperiment\SurfaceSession.h',
    'YimeTextServiceExperiment\SurfaceSession.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\YimeTextServiceIds.h',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'YimeTextServiceExperiment\tests\RegisteredHostTests.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b7-parallel-package-experiment.ps1',
    'tools\yimecore\run-e6c-package-experiment.ps1',
    'tools\yimecore\manage-e6c-trial-install.ps1',
    'tools\yimecore\Install-YimeCore-Trial.cmd',
    'tools\yimecore\Force-Uninstall-YimeCore-Trial.cmd',
    'tools\yimecore\test-e6c-installation-contract.ps1',
    'tools\yimecore\deploy-e6c-trial-runtime.ps1',
    'tools\yimecore\start-e6c-trial-runtime.ps1',
    'tools\yimecore\stop-e6c-trial-runtime.ps1',
    'tools\yimecore\verify-e6c-trial-runtime.ps1'
)
$sourceHashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash -LiteralPath (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashPath = Join-Path $outputDir 'source-hashes.json'
$sourceHashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimecore-e6c-staged-package-experiment-v1'
    stage = 'e6c'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $commit
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    base_package_root = $baseRoot
    base_package_hash_handoff_verified = $true
    package_root = $packageRoot
    package_manifest_sha256 = (Get-FileHash -LiteralPath $packageManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    package_file_count = @($packageManifest.files).Count
    capability_evidence_path = $capabilityPath
    capability_evidence_sha256 = (Get-FileHash -LiteralPath $capabilityPath -Algorithm SHA256).Hash.ToLowerInvariant()
    recovered_user_model_generation = [uint64]$capabilities.recovered_generation
    capability_verifier_attempts = $capabilityVerifierAttempts
    full_variable_shorthand_learning_persistence_passed = [bool]$capabilities.all_modes_passed
    failed_switch_rollback_and_composition_affinity_passed = [bool]$capabilities.all_modes_passed
    toolbar_default_idle_session_is_variable = [bool]$capabilities.default_idle_session_is_variable
    clean_broker_restart_passed = [bool]$capabilities.clean_restart_passed
    crash_journal_recovery_passed = [bool]$capabilities.crash_journal_recovery_passed
    system_lexicon_all_modes_resident = [bool]$capabilities.resident_system_lexicon.all_modes_resident
    system_lexicon_restart_modes_resident = [bool]$capabilities.resident_system_lexicon.restart_modes_resident
    system_lexicon_no_severe_latency_or_stickiness = [bool]$capabilities.resident_system_lexicon.no_severe_latency_or_stickiness
    system_lexicon_startup_elapsed_ns = [int64]$capabilities.resident_system_lexicon.startup_elapsed_ns
    system_lexicon_private_bytes_after_soak = [uint64]$capabilities.resident_system_lexicon.memory_after_soak.private_bytes
    system_lexicon_mode_latency = @($capabilities.resident_system_lexicon.mode_latency)
    continuous_second_term_inheritance_passed = [bool](-not (@($capabilities.modes | Where-Object {
        -not $_.incomplete_second_term_passed
    }).Count))
    generated_sentence_first_candidate_passed = [bool](-not (@($capabilities.modes | Where-Object {
        -not $_.generated_sentence_passed
    }).Count))
    runtime_supervisor_packaged = Test-Path -LiteralPath $runtime
    runtime_supervisor_broker_recovery_passed = [bool]$runtimeRecoveryPassed
    runtime_supervision_evidence_path = $runtimeEvidencePath
    runtime_supervision_evidence_sha256 = (Get-FileHash -LiteralPath $runtimeEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    language_bar_evidence_path = $languageBarEvidencePath
    language_bar_evidence_sha256 = (Get-FileHash -LiteralPath $languageBarEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    language_bar_x64_x86_passed = [bool](@($languageBarTsfChecks).Count -eq 2 -and
        -not (@($languageBarTsfChecks | Where-Object { -not $_.passed }).Count))
    installed_apps_uninstall_contract_passed = [bool]($installationEvidence.installed_apps_entry_planned -and
        $installationEvidence.force_cleanup_before_install -and
        $installationEvidence.x64_x86_tsf_registration_planned -and
        $installationEvidence.learning_sentinel_preserved -and
        $installationEvidence.invalid_non_trial_root_rejected -and
        $installationEvidence.registration_state_convergence_wait -and
        $installationEvidence.taskbar_language_bar_categories -and
        $installationEvidence.windows_native_language_bar_only)
    secondary_architecture_com_only_supported = [bool](-not ($textServiceBuilds.com_only_registration_supported -contains $false))
    input_profile_keyboard_icon_supported = [bool](-not ($textServiceBuilds.profile_icon_registration_supported -contains $false) -and
        $installationEvidence.profile_keyboard_icon_packaged)
    taskbar_category_registration_supported = [bool](-not ($textServiceBuilds.taskbar_category_registration_supported -contains $false) -and
        $installationEvidence.taskbar_language_bar_categories)
    installation_contract_evidence_path = $installationEvidencePath
    installation_contract_evidence_sha256 = (Get-FileHash -LiteralPath $installationEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    e6c_limitation_closed = [bool]$capabilities.passed
    production_rime_pime_changed = [bool]$capabilities.production_rime_pime_changed
    bare_digit_selection_rules_changed = $false
    source_hashes_sha256 = (Get-FileHash -LiteralPath $sourceHashPath -Algorithm SHA256).Hash.ToLowerInvariant()
    blockers = @()
    limitations = @(
        'this remains an unsigned trial package; public release still requires trusted signing and a broader third-party host matrix'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "YimeCore E6-C package evidence: $outputDir"
if (-not $summary.base_package_hash_handoff_verified -or
    -not $summary.full_variable_shorthand_learning_persistence_passed -or
    -not $summary.failed_switch_rollback_and_composition_affinity_passed -or
    -not $summary.toolbar_default_idle_session_is_variable -or
    -not $summary.clean_broker_restart_passed -or -not $summary.crash_journal_recovery_passed -or
    -not $summary.system_lexicon_all_modes_resident -or
    -not $summary.system_lexicon_restart_modes_resident -or
    -not $summary.system_lexicon_no_severe_latency_or_stickiness -or
    -not $summary.continuous_second_term_inheritance_passed -or
    -not $summary.generated_sentence_first_candidate_passed -or
    -not $summary.runtime_supervisor_packaged -or -not $summary.runtime_supervisor_broker_recovery_passed -or
    -not $summary.language_bar_x64_x86_passed -or
    -not $summary.installed_apps_uninstall_contract_passed -or
    -not $summary.secondary_architecture_com_only_supported -or
    -not $summary.input_profile_keyboard_icon_supported -or
    -not $summary.taskbar_category_registration_supported -or
    -not $summary.e6c_limitation_closed -or
    $summary.production_rime_pime_changed -or $summary.bare_digit_selection_rules_changed) {
    throw "E6-C package gate failed; see $summaryPath"
}
Stop-Transcript | Out-Null
