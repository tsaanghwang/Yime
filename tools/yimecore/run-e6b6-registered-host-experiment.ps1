[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b6\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B6 evidence must stay under $allowedRoot"
}
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'E6-B6 requires an elevated token before building or registering'
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'p'
& (Join-Path $PSScriptRoot 'run-e6b5-owned-candidate-popup-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B6 B5 payload failed' }

function Convert-KeyValue([string]$text) {
    $result = [ordered]@{}
    foreach ($line in ($text -split "`r?`n")) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $result[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return $result
}

function Wait-RegistrationState([string]$tool, [bool]$registered, [string]$logPath) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $text = (& $tool status 2>&1) -join "`n"
        $values = Convert-KeyValue $text
        $expectedBoolean = if ($registered) { 'true' } else { 'false' }
        $expectedCategories = if ($registered) { 5 } else { 0 }
        if ($LASTEXITCODE -eq 0 -and
            $values.com_registered_current_view -eq $expectedBoolean -and
            $values.profile_registered -eq $expectedBoolean -and
            [int]$values.categories_registered_count -eq $expectedCategories) {
            $timer.Stop()
            $text | Set-Content $logPath -Encoding utf8
            return $timer.Elapsed.TotalMilliseconds
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    $timer.Stop()
    $text | Set-Content $logPath -Encoding utf8
    throw "TSF registration state did not converge to registered=$registered within 10 seconds"
}

function Start-Broker([string]$broker, [string]$index, [string]$mode,
                      [string]$pipe, [string]$errorLog) {
    Start-Process -FilePath $broker -ArgumentList @('-index', $index, '-mode', $mode, '-named-pipe', $pipe) `
        -PassThru -WindowStyle Hidden -RedirectStandardError $errorLog
}

function Stop-Broker([Diagnostics.Process]$process) {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}

$b5Payload = Join-Path $payload 'p'
$profileIconSource = Join-Path $repoRoot 'YimeTextServiceExperiment\assets\yimecore-trial-profile.ico'
if (-not (Test-Path -LiteralPath $profileIconSource -PathType Leaf)) {
    throw "missing E6-B6 profile icon source: $profileIconSource"
}
$broker = Join-Path $b5Payload 'bin\YimeBroker.exe'
$modeDefinitions = @(
    [ordered]@{ mode = 'full'; index = (Join-Path $b5Payload 'full\index.yidx') },
    [ordered]@{ mode = 'variable'; index = (Join-Path $b5Payload 'variable\index.yidx') },
    [ordered]@{ mode = 'shorthand'; index = (Join-Path $b5Payload 'shorthand\index.yidx') }
)
$architectures = @()
foreach ($architecture in @([ordered]@{ name = 'x64'; bits = 64 },
                             [ordered]@{ name = 'x86'; bits = 32 })) {
    $releaseRoot = Join-Path $b5Payload ("build-$($architecture.name)\Release")
    $profileIcon = Join-Path (Split-Path -Parent $releaseRoot) 'profile-icon.ico'
    Copy-Item -LiteralPath $profileIconSource -Destination $profileIcon -Force
    $tool = Join-Path $releaseRoot 'YimeTextServiceRegistration.exe'
    $dll = Join-Path $releaseRoot 'YimeTextServiceExperiment.dll'
    $hostTest = Join-Path $releaseRoot 'YimeRegisteredHostTests.exe'
    foreach ($artifact in @($tool, $dll, $hostTest, $broker, $profileIcon)) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "missing E6-B6 artifact: $artifact" }
    }
    $architectureDir = Join-Path $outputDir $architecture.name
    New-Item -ItemType Directory -Force $architectureDir | Out-Null
    $null = Wait-RegistrationState $tool $false (Join-Path $architectureDir 'status-before.txt')
    $registerText = (& $tool register $dll 2>&1) -join "`n"
    $registerExit = $LASTEXITCODE
    $registerText | Set-Content (Join-Path $architectureDir 'register.txt') -Encoding utf8
    $registrationVisibilityMs = $null
    $rollbackVisibilityMs = $null
    $modeResults = @()
    try {
        if ($registerExit -ne 0) { throw "$($architecture.name) registration failed with $registerExit" }
        $registrationVisibilityMs = Wait-RegistrationState $tool $true (Join-Path $architectureDir 'status-registered.txt')
        foreach ($definition in $modeDefinitions) {
            $pipe = "\\.\pipe\YimeBroker-e6b6-$($architecture.name)-$($definition.mode)-$PID"
            $brokerError = Join-Path $architectureDir ("broker-$($definition.mode).err")
            $process = Start-Broker $broker $definition.index $definition.mode $pipe $brokerError
            $timer = [Diagnostics.Stopwatch]::StartNew()
            try {
                Start-Sleep -Milliseconds 200
                $testText = (& $hostTest $pipe 2>&1) -join "`n"
                $testExit = $LASTEXITCODE
            } finally {
                Stop-Broker $process
                $timer.Stop()
            }
            $testLog = Join-Path $architectureDir ("$($definition.mode).txt")
            $testText | Set-Content $testLog -Encoding utf8
            if ($testExit -ne 0) { throw "$($architecture.name) $($definition.mode) registered host failed: $testText" }
            $observed = Convert-KeyValue $testText
            foreach ($required in @('registered_key_sink_verified', 'registered_text_extent_anchor',
                                     'punctuation_text_extent_anchor_verified',
                                     'registered_focus_callbacks_verified', 'registered_candidate_commit',
                                     'registered_default_candidate_keys_verified',
                                     'registered_invalid_code_backspace_recovery_verified',
                                     'registered_direction_and_page_keys_verified')) {
                if ($observed[$required] -ne 'true') { throw "$testLog missing $required=true" }
            }
            if ([int]$observed.architecture_bits -ne $architecture.bits) {
                throw "$testLog architecture mismatch"
            }
            $modeResults += [ordered]@{
                mode = $definition.mode
                elapsed_ms = $timer.Elapsed.TotalMilliseconds
                registered_key_sink_verified = $true
                registered_text_extent_anchor = $true
                punctuation_text_extent_anchor_verified = $true
                registered_focus_callbacks_verified = $true
                registered_candidate_commit = $true
                registered_default_candidate_keys_verified = $true
                registered_invalid_code_backspace_recovery_verified = $true
                registered_direction_and_page_keys_verified = $true
                registered_language_bar_accepted = $observed.registered_language_bar_accepted -eq 'true'
            }
        }
    } finally {
        $unregisterText = (& $tool unregister 2>&1) -join "`n"
        $unregisterExit = $LASTEXITCODE
        $unregisterText | Set-Content (Join-Path $architectureDir 'unregister.txt') -Encoding utf8
        if ($unregisterExit -ne 0) { throw "$($architecture.name) rollback failed with $unregisterExit" }
        $rollbackVisibilityMs = Wait-RegistrationState $tool $false (Join-Path $architectureDir 'status-after.txt')
        $absentText = (& $tool verify-absent 2>&1) -join "`n"
        $absentExit = $LASTEXITCODE
        $absentText | Set-Content (Join-Path $architectureDir 'verify-absent-after.txt') -Encoding utf8
        if ($absentExit -ne 0) { throw "$($architecture.name) registration residue detected" }
    }
    $architectures += [ordered]@{
        architecture = $architecture.name
        bits = $architecture.bits
        registration_tool_sha256 = (Get-FileHash $tool -Algorithm SHA256).Hash.ToLowerInvariant()
        dll_sha256 = (Get-FileHash $dll -Algorithm SHA256).Hash.ToLowerInvariant()
        registered_host_test_sha256 = (Get-FileHash $hostTest -Algorithm SHA256).Hash.ToLowerInvariant()
        registration_visibility_ms = $registrationVisibilityMs
        rollback_visibility_ms = $rollbackVisibilityMs
        modes = $modeResults
        no_residue_after_test = $true
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\RegistrationTool.cpp',
    'YimeTextServiceExperiment\BrokerClient.h',
    'YimeTextServiceExperiment\BrokerClient.cpp',
    'YimeTextServiceExperiment\KeyContract.h',
    'YimeTextServiceExperiment\KeyContract.cpp',
    'YimeTextServiceExperiment\SurfaceSession.h',
    'YimeTextServiceExperiment\SurfaceSession.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\CandidateListUIElement.h',
    'YimeTextServiceExperiment\CandidateListUIElement.cpp',
    'YimeTextServiceExperiment\CandidatePopup.h',
    'YimeTextServiceExperiment\CandidatePopup.cpp',
    'YimeTextServiceExperiment\ExperimentSettings.h',
    'YimeTextServiceExperiment\ExperimentSettings.cpp',
    'YimeTextServiceExperiment\tests\RegisteredHostTests.cpp',
    'tools\yimecore\run-e6b6-registered-host-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$allModes = @($architectures | ForEach-Object { $_.modes })
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b6-registered-host-v2'
    stage = 'e6b6'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    elevated = $true
    output_boundary = $outputDir
    b5_payload_summary_path = (Join-Path $payload 'summary.json')
    b5_payload_summary_sha256 = (Get-FileHash (Join-Path $payload 'summary.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    broker_sha256 = (Get-FileHash $broker -Algorithm SHA256).Hash.ToLowerInvariant()
    architectures = $architectures
    all_x86_x64_three_mode_registered_paths_passed = $allModes.Count -eq 6
    registered_key_sink_verified = -not ($allModes.registered_key_sink_verified -contains $false)
    registered_text_extent_anchor_verified = -not ($allModes.registered_text_extent_anchor -contains $false)
    punctuation_text_extent_anchor_verified = -not ($allModes.punctuation_text_extent_anchor_verified -contains $false)
    registered_focus_callbacks_verified = -not ($allModes.registered_focus_callbacks_verified -contains $false)
    registered_candidate_commit_verified = -not ($allModes.registered_candidate_commit -contains $false)
    language_bar_manager_acceptance_observations = @($architectures | ForEach-Object {
        $architectureName = $_.architecture
        $_.modes | ForEach-Object {
            [ordered]@{
                architecture = $architectureName
                mode = $_.mode
                accepted = $_.registered_language_bar_accepted
            }
        }
    })
    all_no_residue = -not ($architectures.no_residue_after_test -contains $false)
    production_registration_changed = $false
    installation_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    blockers = @()
    limitations = @(
        'the registered host is a purpose-built in-memory ITextStoreACP application rather than a third-party desktop application',
        'Windows may silently ignore the custom language-bar item even when AddItem returns S_OK; this is recorded but does not block the key, composition, candidate, focus or positioning paths',
        'parallel package installation and uninstall rollback remain the next E6 gate'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B6 evidence: $outputDir"
if (-not $summary.all_x86_x64_three_mode_registered_paths_passed -or
    -not $summary.registered_key_sink_verified -or
    -not $summary.registered_text_extent_anchor_verified -or
    -not $summary.punctuation_text_extent_anchor_verified -or
    -not $summary.registered_focus_callbacks_verified -or
    -not $summary.registered_candidate_commit_verified -or
    -not $summary.all_no_residue -or
    $summary.production_registration_changed -or $summary.installation_changed) {
    throw "E6-B6 gate failed; see $summaryPath"
}
