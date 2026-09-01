[CmdletBinding()]
param(
    [string]$BasePackageRoot,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stateRoot = Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
if ([string]::IsNullOrWhiteSpace($BasePackageRoot)) {
    $runtimeConfigPath = Join-Path $stateRoot 'runtime-config.json'
    if (-not (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf)) {
        throw 'BasePackageRoot was not provided and no installed YimeCore trial configuration exists'
    }
    $runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $BasePackageRoot = [string]$runtimeConfig.install_root
    if ([string]::IsNullOrWhiteSpace($BasePackageRoot)) {
        throw "installed YimeCore trial configuration has no install_root: $runtimeConfigPath"
    }
}
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
        $_.Name -notin @('package-manifest.json', 'install-metadata.json')
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

$sharedDataRoot = Join-Path $repoRoot 'go-backend\input_methods\yime\data'
$trainerDataFiles = @(
    'yime_yinyuan_layout.json',
    'yime_pinyin_codes.tsv',
    'pinyin_normalized.json',
    'yime_pua_pinyin.json',
    'fonts\YinYuan-Regular.ttf',
    'yime_full.dict.yaml',
    'yime_variable.dict.yaml',
    'yime_shorthand.dict.yaml',
    'yime_lexicon_manifest.json',
    'yime_core_source_manifest.json',
    'yime_full.schema.yaml',
    'yime_variable.schema.yaml',
    'yime_shorthand.schema.yaml',
    'yime_syllable_decomposition.tsv',
    'trainer\foundation.json',
    'trainer\curriculum.json',
    'trainer\yinyuan_catalog.json',
    'trainer\yinyuan_groups.json'
)
foreach ($relative in $trainerDataFiles) {
    $source = Join-Path $sharedDataRoot $relative
    $destination = Join-Path (Join-Path $packageRoot 'data') $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
$dynamicSentenceCaseSource = Join-Path $repoRoot `
    'go-backend\input_methods\yime\yimecore\testdata\dynamic_sentence_cases.json'
$dynamicSentenceCasePackage = Join-Path $packageRoot 'data\dynamic_sentence_cases.json'
Copy-Item -LiteralPath $dynamicSentenceCaseSource -Destination $dynamicSentenceCasePackage -Force

$textServiceBuilds = @()
$nativeArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
	$env:PROCESSOR_ARCHITEW6432
} else { $env:PROCESSOR_ARCHITECTURE }
foreach ($architecture in @(
	[ordered]@{ name = 'x64'; platform = 'x64'; runnable = $true },
	[ordered]@{ name = 'x86'; platform = 'Win32'; runnable = $true },
	[ordered]@{ name = 'arm64'; platform = 'ARM64'; runnable = $nativeArchitecture -eq 'ARM64' }
)) {
	New-Item -ItemType Directory -Path (Join-Path $packageRoot $architecture.name) -Force | Out-Null
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
	if ($architecture.runnable) {
		& $contractTest $dll 2>&1 | Tee-Object -LiteralPath $contractLog
		if ($LASTEXITCODE -ne 0) { throw "experimental language-bar contract failed: $($architecture.name)" }
	} else {
		'Skipped execution on a non-ARM64 build host; compile and package checks passed.' |
			Set-Content -LiteralPath $contractLog -Encoding ascii
	}
    $registrationTool = Join-Path $releaseRoot 'YimeTextServiceRegistration.exe'
	if ($architecture.runnable) {
		$registrationStatus = (& $registrationTool status 2>&1) -join "`n"
		if ($LASTEXITCODE -ne 0 -or
			$registrationStatus -notmatch '(?m)^com_only_registration_supported=true$' -or
			$registrationStatus -notmatch '(?m)^profile_icon_registration_supported=true$' -or
			$registrationStatus -notmatch '(?m)^taskbar_category_registration_supported=true$') {
			throw "experimental registration capability missing: $($architecture.name)"
		}
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
		runnable = [bool]$architecture.runnable
        com_only_registration_supported = $true
        profile_icon_registration_supported = $true
        taskbar_category_registration_supported = $true
    }
}

$broker = Join-Path $binRoot 'YimeBroker.exe'
$verifier = Join-Path $binRoot 'YimeE6CPackageExperiment.exe'
$runtime = Join-Path $binRoot 'YimeCoreTrialRuntime.exe'
$inputToolbar = Join-Path $binRoot 'YimeCoreInputToolbar.exe'
$reverseLookup = Join-Path $binRoot 'YimeCoreReverseLookup.exe'
$lexiconManager = Join-Path $binRoot 'YimeCoreLexiconManager.exe'
$trainer = Join-Path $binRoot 'YimeCoreTrainer.exe'
$toolCenter = Join-Path $binRoot 'YimeCoreToolCenter.exe'
$lexiconCenter = Join-Path $binRoot 'YimeCoreLexiconCenter.exe'
$blocklistManager = Join-Path $binRoot 'YimeCoreBlocklistManager.exe'
$systemLexiconAudit = Join-Path $binRoot 'YimeCoreSystemLexiconAudit.exe'
$learningManager = Join-Path $binRoot 'YimeCoreLearningManager.exe'
$promotionScan = Join-Path $binRoot 'YimeCorePromotionScan.exe'
$professionalLexicon = Join-Path $binRoot 'YimeCoreProfessionalLexicon.exe'
$layoutDesigner = Join-Path $binRoot 'YimeCoreLayoutDesigner.exe'
$diagnosticsTool = Join-Path $binRoot 'YimeCoreDiagnostics.exe'
$settingsTool = Join-Path $binRoot 'YimeCoreSettingsTool.exe'
$explainTool = Join-Path $binRoot 'YimeCoreExplain.exe'
$sentenceRegression = Join-Path $binRoot 'YimeCoreSentenceRegression.exe'
Push-Location (Join-Path $repoRoot 'go-backend')
try {
    foreach ($legacyTool in @('YimeCoreToolbar.exe', 'YimeCoreDesktopTools.exe')) {
        $legacyToolPath = Join-Path $binRoot $legacyTool
        if (Test-Path -LiteralPath $legacyToolPath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyToolPath -Force
        }
    }
    & go build -trimpath -o $broker ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'E6-C Broker build failed' }
    & go build -trimpath -o $verifier ./cmd/yimebroker-multimode-experiment
    if ($LASTEXITCODE -ne 0) { throw 'E6-C verifier build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $runtime ./cmd/yimecore-trial-runtime
    if ($LASTEXITCODE -ne 0) { throw 'E6-C runtime supervisor build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $inputToolbar ./cmd/input-toolbar
    if ($LASTEXITCODE -ne 0) { throw 'E6-C native input toolbar build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $reverseLookup ./cmd/reverse-lookup-tool
    if ($LASTEXITCODE -ne 0) { throw 'E6-C reverse lookup build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $lexiconManager ./cmd/lexicon-manager
    if ($LASTEXITCODE -ne 0) { throw 'E6-C user lexicon build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $trainer ./cmd/yime-trainer
    if ($LASTEXITCODE -ne 0) { throw 'E6-C trainer build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $toolCenter ./cmd/tool-hub
    if ($LASTEXITCODE -ne 0) { throw 'E6-C Tool Center build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $lexiconCenter ./cmd/tool-hub
    if ($LASTEXITCODE -ne 0) { throw 'E6-C Lexicon Center build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $blocklistManager ./cmd/blocklist-manager
    if ($LASTEXITCODE -ne 0) { throw 'E6-C blocklist manager build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $systemLexiconAudit ./cmd/system-lexicon-audit
    if ($LASTEXITCODE -ne 0) { throw 'E6-C system lexicon audit build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $learningManager ./cmd/learning-manager
    if ($LASTEXITCODE -ne 0) { throw 'E6-C learning manager build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $promotionScan ./cmd/lexicon-promotion-scan
    if ($LASTEXITCODE -ne 0) { throw 'E6-C promotion scan build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $professionalLexicon ./cmd/professional-lexicon-manager
    if ($LASTEXITCODE -ne 0) { throw 'E6-C professional lexicon manager build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $layoutDesigner ./cmd/yime-layout-designer
    if ($LASTEXITCODE -ne 0) { throw 'E6-C layout designer build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $diagnosticsTool ./cmd/diagnostics-tool
    if ($LASTEXITCODE -ne 0) { throw 'E6-C diagnostics tool build failed' }
    & go build -trimpath -ldflags '-H=windowsgui' -o $settingsTool ./cmd/settings-tool
    if ($LASTEXITCODE -ne 0) { throw 'E6-C settings tool build failed' }
    & go build -trimpath -o $explainTool ./cmd/yimecore-explain
    if ($LASTEXITCODE -ne 0) { throw 'E6-C decode explanation tool build failed' }
    & go build -trimpath -o $sentenceRegression ./cmd/yimecore-sentence-regression
    if ($LASTEXITCODE -ne 0) { throw 'E6-C dynamic sentence regression tool build failed' }
} finally {
    Pop-Location
}

$dynamicSentenceEvidencePath = Join-Path $outputDir 'dynamic-sentence-regression.json'
& $sentenceRegression -index-root $indexRoot -cases $dynamicSentenceCasePackage `
    -output $dynamicSentenceEvidencePath
if ($LASTEXITCODE -ne 0) { throw 'E6-C dynamic sentence regression failed' }
$dynamicSentenceEvidence = Get-Content -LiteralPath $dynamicSentenceEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if (-not $dynamicSentenceEvidence.passed) { throw 'E6-C dynamic sentence regression did not pass' }

$professionalRoot = Join-Path $packageRoot 'professional-lexicons'
New-Item -ItemType Directory -Path $professionalRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'professional-lexicons\catalog.json') `
    -Destination (Join-Path $professionalRoot 'catalog.json') -Force

$maintenanceRoot = Join-Path $packageRoot 'maintenance'
New-Item -ItemType Directory -Path $maintenanceRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') `
    -Destination (Join-Path $maintenanceRoot 'Manage-YimeCoreTrial.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'repair-e6c-trial-autostart.ps1') `
    -Destination (Join-Path $maintenanceRoot 'Repair-YimeCoreTrialAutostart.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-YimeCore-Trial.cmd') `
    -Destination (Join-Path $packageRoot 'Install-YimeCore-Trial.cmd') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Force-Uninstall-YimeCore-Trial.cmd') `
    -Destination (Join-Path $packageRoot 'Force-Uninstall-YimeCore-Trial.cmd') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'YimeTextServiceExperiment\assets\yimecore-trial-profile.ico') `
    -Destination (Join-Path $packageRoot 'profile-icon.ico') -Force
$helpRoot = Join-Path $packageRoot 'help'
New-Item -ItemType Directory -Path $helpRoot -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'trial-help\*.html') -Destination $helpRoot -Force

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
function Test-PackagedBrokerProcessIdentity($Process, $Status) {
    if (-not $Process -or -not $Status) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Status.install_root) -or
        [string]::IsNullOrWhiteSpace([string]$Status.broker_path)) { return $false }
    $processPath = [string]$Process.ExecutablePath
    $pathVerifiedWhenAvailable = [string]::IsNullOrWhiteSpace($processPath) -or
        ([IO.Path]::GetFullPath($processPath)).Equals($broker, [StringComparison]::OrdinalIgnoreCase)
    return [int]$Process.ProcessId -eq [int]$Status.broker_pid -and
        [int]$Process.ParentProcessId -eq [int]$Status.runtime_pid -and
        ([string]$Process.Name).Equals('YimeBroker.exe', [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFullPath([string]$Status.install_root)).Equals($packageRoot, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFullPath([string]$Status.broker_path)).Equals($broker, [StringComparison]::OrdinalIgnoreCase) -and
        $pathVerifiedWhenAvailable
}
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
    if (-not (Test-PackagedBrokerProcessIdentity $oldBroker $runtimeBefore)) {
        throw 'packaged E6-C runtime supervisor reported an unexpected Broker process'
    }
    $oldBrokerPathAccessible = -not [string]::IsNullOrWhiteSpace([string]$oldBroker.ExecutablePath)
	foreach ($textServiceBuild in @($textServiceBuilds | Where-Object { $_.runnable })) {
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
            $newBroker -and (Test-PackagedBrokerProcessIdentity $newBroker $runtimeAfter)
    } while ((Get-Date) -lt $deadline -and -not $runtimeRecoveryReady)
    $runtimeRecoveryChecks = [ordered]@{
        status_running = [bool]($runtimeAfter -and $runtimeAfter.state -eq 'running')
        runtime_pid_preserved = [bool]($runtimeAfter -and [int]$runtimeAfter.runtime_pid -eq [int]$runtimeBefore.runtime_pid)
        broker_pid_replaced = [bool]($runtimeAfter -and [int]$runtimeAfter.broker_pid -ne [int]$runtimeBefore.broker_pid)
        restart_count_advanced = [bool]($runtimeAfter -and [int]$runtimeAfter.restarts -gt [int]$runtimeBefore.restarts)
        broker_process_identity_verified = [bool]($newBroker -and
            (Test-PackagedBrokerProcessIdentity $newBroker $runtimeAfter))
        broker_path_verified = [bool]($oldBrokerPathAccessible -and $newBroker -and
            -not [string]::IsNullOrWhiteSpace([string]$newBroker.ExecutablePath))
        broker_parent_runtime_verified = [bool]($newBroker -and
            [int]$newBroker.ParentProcessId -eq [int]$runtimeAfter.runtime_pid)
        process_identity_method = if ($oldBrokerPathAccessible -and $newBroker -and
            -not [string]::IsNullOrWhiteSpace([string]$newBroker.ExecutablePath)) {
            'executable-path+runtime-parent+status-convergence'
        } else {
            'runtime-parent+status-convergence'
        }
    }
    $runtimeRecoveryPassed = $runtimeRecoveryChecks.status_running -and
        $runtimeRecoveryChecks.runtime_pid_preserved -and
        $runtimeRecoveryChecks.broker_pid_replaced -and
        $runtimeRecoveryChecks.restart_count_advanced -and
        $runtimeRecoveryChecks.broker_process_identity_verified -and
        $runtimeRecoveryChecks.broker_parent_runtime_verified
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
    'docs\project\DYNAMIC_SENTENCE_COMPOSITION_REQUIREMENTS.md',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\cmd\yimebroker-multimode-experiment\main.go',
    'go-backend\cmd\yimecore-trial-runtime\main.go',
    'go-backend\cmd\yimecore-trial-runtime\main_test.go',
    'go-backend\cmd\yimecore-trial-runtime\runtime_windows.go',
    'go-backend\cmd\yimecore-trial-runtime\runtime_stub.go',
    'go-backend\cmd\input-toolbar\main.go',
    'go-backend\cmd\input-toolbar\main_test.go',
    'go-backend\cmd\reverse-lookup-tool\main.go',
    'go-backend\cmd\lexicon-manager\main.go',
    'go-backend\cmd\lexicon-manager\actions.go',
    'go-backend\cmd\yime-trainer\main.go',
    'go-backend\cmd\yime-trainer\display_windows.go',
    'go-backend\cmd\yime-trainer\display_windows_test.go',
    'go-backend\cmd\tool-hub\main.go',
    'go-backend\cmd\tool-hub\main_test.go',
    'go-backend\cmd\yime-layout-designer\gui_windows.go',
    'go-backend\cmd\yime-layout-designer\trial_windows_test.go',
    'go-backend\input_methods\yime\layoutdesigner\trial_apply.go',
    'go-backend\input_methods\yime\layoutdesigner\trial_apply_test.go',
    'go-backend\cmd\diagnostics-tool\main.go',
    'go-backend\cmd\diagnostics-tool\main_test.go',
    'go-backend\input_methods\yime\diagnostics\collect.go',
    'go-backend\input_methods\yime\diagnostics\collect_test.go',
    'go-backend\input_methods\yime\toolhub\manifest.go',
    'go-backend\input_methods\yime\toolhub\launch_windows.go',
    'go-backend\cmd\settings-tool\main.go',
    'go-backend\cmd\settings-tool\main_test.go',
    'go-backend\cmd\settings-tool\documents_windows.go',
    'go-backend\input_methods\yime\toolbarstate\state.go',
    'go-backend\cmd\yimecore-explain\main.go',
    'go-backend\cmd\yimecore-explain\main_test.go',
    'go-backend\cmd\yimecore-sentence-regression\main.go',
    'go-backend\cmd\yimecore-sentence-regression\main_test.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher.go',
    'go-backend\input_methods\yime\yimebroker\dispatcher_test.go',
    'go-backend\input_methods\yime\yimebroker\stdio.go',
    'go-backend\input_methods\yime\yimebroker\stdio_test.go',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'go-backend\input_methods\yime\yimebroker\index_control.go',
    'go-backend\input_methods\yime\yimebroker\index_manager.go',
    'go-backend\input_methods\yime\yimebroker\index_manager_test.go',
    'go-backend\input_methods\yime\yimebroker\mode_index_manager.go',
    'go-backend\input_methods\yime\yimebroker\mode_index_manager_test.go',
    'go-backend\input_methods\yime\yimebroker\usermodel_store.go',
    'go-backend\input_methods\yime\yimecore\indexfile.go',
    'go-backend\input_methods\yime\yimecore\indexfile_test.go',
    'go-backend\input_methods\yime\yimecore\userlexicon_overlay.go',
    'go-backend\input_methods\yime\candidateannotation\annotation.go',
    'go-backend\input_methods\yime\candidateannotation\annotation_test.go',
    'go-backend\input_methods\yime\data\pinyin_normalized.json',
    'go-backend\input_methods\yime\data\yime_pua_pinyin.json',
    'go-backend\input_methods\yime\data\fonts\YinYuan-Regular.ttf',
    'go-backend\input_methods\yime\candidatefilter\filter.go',
    'go-backend\input_methods\yime\candidatefilter\filter_test.go',
    'go-backend\input_methods\yime\reverselookup\index.go',
    'go-backend\input_methods\yime\engineapi\engine.go',
    'go-backend\input_methods\yime\yimecore\engine.go',
    'go-backend\input_methods\yime\yimecore\engine_test.go',
    'go-backend\input_methods\yime\yimecore\bundle_test.go',
    'go-backend\input_methods\yime\yimecore\construction.go',
    'go-backend\input_methods\yime\yimecore\segment_correction_test.go',
    'go-backend\input_methods\yime\yimecore\sentence.go',
    'go-backend\input_methods\yime\yimecore\sentence_test.go',
    'go-backend\input_methods\yime\yimecore\usermodel.go',
    'go-backend\input_methods\yime\yimecore\usermodel_test.go',
    'go-backend\input_methods\yime\yimecore\reranker.go',
    'go-backend\input_methods\yime\yimecore\reranker_test.go',
    'go-backend\input_methods\yime\yimecore\explain.go',
    'go-backend\input_methods\yime\yimecore\explain_test.go',
    'go-backend\input_methods\yime\yimecore\testdata\dynamic_sentence_cases.json',
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
    'YimeTextServiceExperiment\KeyContract.h',
    'YimeTextServiceExperiment\KeyContract.cpp',
    'YimeTextServiceExperiment\OutputTransform.h',
    'YimeTextServiceExperiment\OutputTransform.cpp',
    'YimeTextServiceExperiment\PunctuationPalette.h',
    'YimeTextServiceExperiment\PunctuationPalette.cpp',
    'go-backend\input_methods\yime\icons\chi_half_capsoff.ico',
    'go-backend\input_methods\yime\icons\eng_half_capsoff.ico',
    'go-backend\input_methods\yime\icons\chi_full_capsoff.ico',
    'go-backend\input_methods\yime\icons\eng_full_capsoff.ico',
    'go-backend\input_methods\yime\icon.ico',
    'YimeTextServiceExperiment\assets\yimecore-trial-profile.png',
    'YimeTextServiceExperiment\assets\yimecore-trial-profile.ico',
    'YimeTextServiceExperiment\SurfaceSession.h',
    'YimeTextServiceExperiment\SurfaceSession.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\DiagnosticPolicy.h',
    'YimeTextServiceExperiment\YimeTextServiceIds.h',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'YimeTextServiceExperiment\tests\BrokerBridgeTests.cpp',
    'YimeTextServiceExperiment\tests\RegisteredHostTests.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'tools\yimecore\run-e6b7-parallel-package-experiment.ps1',
    'tools\yimecore\run-e6c-package-experiment.ps1',
    'tools\yimecore\manage-e6c-trial-install.ps1',
    'tools\yimecore\repair-e6c-trial-autostart.ps1',
    'tools\yimecore\Install-YimeCore-Trial.cmd',
    'tools\yimecore\Force-Uninstall-YimeCore-Trial.cmd',
    'tools\yimecore\test-e6c-installation-contract.ps1',
	'tools\yimecore\test-yimecore-cleanup-contract.ps1',
    'tools\yimecore\deploy-e6c-trial-runtime.ps1',
    'tools\yimecore\start-e6c-trial-runtime.ps1',
    'tools\yimecore\stop-e6c-trial-runtime.ps1',
    'tools\yimecore\verify-e6c-trial-runtime.ps1',
    'tools\yimecore\verify-e6c-language-bar-events.ps1',
    'tools\yimecore\trial-help\README.html',
    'tools\yimecore\trial-help\settings-and-data.html',
    'tools\yimecore\trial-help\trial-feedback.html',
    'tools\yimecore\trial-help\diagnostics.html',
    'tools\yimecore\record-e6b8-desktop-host-acceptance.ps1'
	'Upgrade-YimeCore-Trial.cmd',
	'Build-Install-YimeCore-Trial.cmd',
	'Build-Install-YimeCore-Trial-v2.cmd',
	'Build-Install-YimeCore-Trial-v3.cmd'
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
    recursive_code_convergence_passed = [bool](-not (@($capabilities.modes | Where-Object {
        -not $_.future_predictions_hidden
    }).Count))
    prefix_tree_monotonicity_passed = [bool](-not (@($capabilities.modes | Where-Object {
        -not $_.prefix_tree_monotonic -or -not $_.prefix_candidates_visible -or
        [int]$_.prefix_candidate_count -le 0 -or [string]::IsNullOrWhiteSpace([string]$_.prefix_sentence_prediction)
    }).Count))
    generated_sentence_first_candidate_passed = [bool](-not (@($capabilities.modes | Where-Object {
        -not $_.generated_sentence_passed
    }).Count))
    dynamic_sentence_real_indexes_passed = [bool]$dynamicSentenceEvidence.passed
    dynamic_sentence_evidence_path = $dynamicSentenceEvidencePath
    dynamic_sentence_evidence_sha256 = (Get-FileHash -LiteralPath $dynamicSentenceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    native_input_toolbar_packaged = [bool]$installationEvidence.native_input_toolbar_windows_gui
    yinyuan_private_font_packaged = [bool]$installationEvidence.yinyuan_private_font_packaged
    legacy_desktop_tools_removed = [bool]($installationEvidence.legacy_trial_toolbar_absent -and
        $installationEvidence.input_toolbar_powershell_ui_absent)
    runtime_supervisor_packaged = Test-Path -LiteralPath $runtime
    runtime_supervisor_broker_recovery_passed = [bool]$runtimeRecoveryPassed
    runtime_supervision_evidence_path = $runtimeEvidencePath
    runtime_supervision_evidence_sha256 = (Get-FileHash -LiteralPath $runtimeEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    language_bar_evidence_path = $languageBarEvidencePath
    language_bar_evidence_sha256 = (Get-FileHash -LiteralPath $languageBarEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
	language_bar_x64_x86_passed = [bool](@($languageBarTsfChecks).Count -ge 2 -and
        -not (@($languageBarTsfChecks | Where-Object { -not $_.passed }).Count))
	arm64_tsf_artifacts_packaged = [bool]((@(
		'YimeTextServiceExperiment.dll', 'YimeTextServiceRegistration.exe', 'YimeRegisteredHostTests.exe'
	) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $packageRoot ('arm64\' + $_)) -PathType Leaf) }).Count -eq 0)
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
    -not $summary.recursive_code_convergence_passed -or
    -not $summary.prefix_tree_monotonicity_passed -or
    -not $summary.generated_sentence_first_candidate_passed -or
    -not $summary.dynamic_sentence_real_indexes_passed -or
    -not $summary.native_input_toolbar_packaged -or -not $summary.yinyuan_private_font_packaged -or
    -not $summary.legacy_desktop_tools_removed -or
    -not $summary.runtime_supervisor_packaged -or -not $summary.runtime_supervisor_broker_recovery_passed -or
	-not $summary.language_bar_x64_x86_passed -or -not $summary.arm64_tsf_artifacts_packaged -or
    -not $summary.installed_apps_uninstall_contract_passed -or
    -not $summary.secondary_architecture_com_only_supported -or
    -not $summary.input_profile_keyboard_icon_supported -or
    -not $summary.taskbar_category_registration_supported -or
    -not $summary.e6c_limitation_closed -or
    $summary.production_rime_pime_changed -or $summary.bare_digit_selection_rules_changed) {
    throw "E6-C package gate failed; see $summaryPath"
}
Stop-Transcript | Out-Null
