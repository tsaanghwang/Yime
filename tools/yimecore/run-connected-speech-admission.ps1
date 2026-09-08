[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [string]$Python = 'C:\Users\tsaan\AppData\Local\Programs\Python\Python312\python.exe'
)
# Current-source, Stage5C-only admission and owned anonymous-stdio Broker trial.
# No installed binary, TSF host, Rime session, installer or user text is opened.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5') {
    throw 'Speech admission execution requires PowerShell 7.5+ for exact environment restoration.'
}

# Reuse only these reviewed function definitions. Never execute/dot-source the
# old SR0 entry point, whose independent trial must not run as a side effect.
$helperPath = Join-Path $PSScriptRoot 'run-connected-speech-reconnect.ps1'
$helperLoadedSHA = (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant()
$helperTokens = $null; $helperErrors = $null
$helperAst = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$helperTokens, [ref]$helperErrors)
if (@($helperErrors).Count) { throw 'Speech helper parse failed; no trial started.' }
$helperAllowlist = @('Assert-SpeechPlainPath','Resolve-SpeechChild','Write-SpeechJson','Set-SpeechEnvironmentValue',
    'Get-SpeechRecord','Assert-SpeechSameRecords','Assert-SpeechBaseline','Get-SpeechBaselineIdentity',
    'Assert-SpeechBaselineUnchanged','Get-SpeechDefinitions','Get-SpeechLockedInputs')
foreach ($helperName in $helperAllowlist) {
    $helperMatches = @($helperAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) | Where-Object Name -CEQ $helperName)
    if ($helperMatches.Count -ne 1) { throw 'Speech helper allowlist is ambiguous or incomplete.' }
    . ([scriptblock]::Create($helperMatches[0].Extent.Text))
}
if ((Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $helperLoadedSHA) { throw 'Speech helper changed while definitions were loaded.' }
. (Join-Path $PSScriptRoot 'development-scope.ps1')

function Get-AdmissionSourceRecords([string]$Repo) {
    $paths = @('AGENTS.md','go-backend/go.mod','docs/project/MANDARIN_CONNECTED_SPEECH_PLAN.md',
        'tools/yimecore/development-scope.json','tools/yimecore/development-scope.ps1','tools/yimecore/local-maintenance-safety.ps1',
        'tools/yimecore/get-l5-daily-use-baseline.ps1','tools/yimecore/run-connected-speech-reconnect.ps1',
        'tools/yimecore/run-connected-speech-admission.ps1','tools/yimecore/run-connected-speech-package.ps1',
        'tools/yimecore/test-connected-speech-package.ps1','tools/lexicon/validate_connected_speech_forward.py',
        'tools/yimecore/local-product.json','tools/yimecore/local-product-build-common.ps1',
        'tools/yimecore/build-local-product.ps1','tools/yimecore/local-product-speech-build.ps1',
        'tools/yimecore/test-local-product-speech-build.ps1','tools/yimecore/test-speech-maintenance-data.ps1',
        'tools/yimecore/test-local-maintenance-config-data.ps1',
        'tools/yimecore/test-speech-symlink-evidence.ps1',
        'tools/yimecore/run-connected-speech-product-package.ps1','tools/yimecore/speech-product-contract.json',
        'tools/yimecore/run-connected-speech-product-source.ps1',
        'go-backend/input_methods/yime/data/yime_full.dict.yaml','go-backend/input_methods/yime/data/yime_variable.dict.yaml',
        'go-backend/input_methods/yime/data/yime_shorthand.dict.yaml','tools/lexicon/data/yime_core_target.lock.json',
        'tools/lexicon/tests/test_validate_connected_speech_forward.py',
        'docs/testing/connected-speech/2026-09-05-isolated-reconnect.json',
        'docs/project/connected_speech/third_tone_stage5b_review.tsv','docs/project/connected_speech/third_tone_stage5b_decisions.tsv',
        'docs/project/connected_speech/third_tone_stage5b_sources.tsv','docs/project/connected_speech/third_tone_sandhi_scope.tsv',
        'internal_data/phrase_pinyin/phrase_pinyin.txt','internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json',
        'internal_data/yime_syllable_decomposition.tsv','go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv',
        'internal_data/manual_key_layout.json','go-backend/input_methods/yime/data/yime_yinyuan_layout.json',
        'syllable/yinyuan/zaoyin_yinyuan_enhanced.json','syllable/yinyuan/yueyin_yinyuan_enhanced.json',
        'internal_data/key_to_symbol.json','syllable/yinyuan/shouyin_codepoint.json','syllable/pianyin/zaoyin_pianyin.json',
        'syllable/yinyuan/variables_of_attributes.json','internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json',
        'syllable/yinyuan/ganyin.json','internal_data/pinyin_source_db/neutral_tone_encoding_exceptions.json')
    # File-name inventory only; content reads remain limited to source code.
    # Capture additions/removals as well as hashes, including every new package.
    foreach ($tree in @('go-backend/input_methods/yime','go-backend/cmd','go-backend/internal','syllable','yime')) {
        $directory = Resolve-SpeechChild $Repo $tree
        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -Force) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Indirect source tree rejected.' }
            if (-not $file.PSIsContainer -and $file.Extension -cin @('.go','.py')) {
                $paths += $file.FullName.Substring($Repo.Length + 1).Replace('\','/')
            }
        }
    }
    @($paths | Sort-Object -Unique | ForEach-Object { Get-SpeechRecord $Repo $_ })
}

function Get-AdmissionLegacyRecords {
    # Exactly six retained payloads and their manifest, read-only static hashes.
    # These pins are historical integrity evidence, never current-product input.
    $root = 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-45b389e530c0-8d48953a'
    $pins = @(
        @{path='package-manifest.json';sha256='8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64';bytes=$null},
        @{path='x86/YimeRegisteredHostTests.exe';sha256='5edb34d7b3c75cf24dec7dae65e01aa9c4e02a29aa66d5be1b304a0ddb455e18';bytes=371712},
        @{path='arm64/YimeRegisteredHostTests.exe';sha256='ec6bc1dd792301c8778db6881ee49d3193509baf711bdbbfc2dc44ad9ee16ca2';bytes=437248},
        @{path='arm64/YimeTextServiceExperiment.dll';sha256='d5dc84c87dae608e0ff1e65b5d98fb1a33ab6424da91da2263636e1efbd1b18e';bytes=654336},
        @{path='arm64/YimeTextServiceRegistration.exe';sha256='6683e3ff27eaa0379604fc7263d9b46e7457b8ebd7d29b2848a637d7cbbb675a';bytes=268800},
        @{path='x86/YimeTextServiceExperiment.dll';sha256='0dfe2bb5617c65bd1e94c62ff9ee8cb23eb912fa68ca21a7705083022f2a8f95';bytes=578560},
        @{path='x86/YimeTextServiceRegistration.exe';sha256='ccd08ef8270893fbf136f38c2891353900a9dd12b1476a15e2858fb1c4127024';bytes=228352}
    )
    foreach ($pin in $pins) {
        $record = Get-SpeechRecord $root $pin.path
        if ($record.sha256 -cne $pin.sha256 -or ($null -ne $pin.bytes -and $record.bytes -ne $pin.bytes)) { throw 'Retained payload static integrity failed.' }
        $record
    }
}

function Invoke-AdmissionLogged([string]$Program, [string[]]$Arguments, [string]$LogPath) {
    # Only fixed source tests, build/dependency commands and owned fixture tools.
    # No installed/runtime-log/user-data command is allowed at call sites below.
    & $Program @Arguments 2>&1 | Set-Content -LiteralPath $LogPath -Encoding UTF8
    $childExit = $LASTEXITCODE
    if ($childExit -ne 0) { throw "Isolated child exit $childExit; inspect the fixed fixture log." }
}

function Read-AdmissionTestOutcomes([string]$Path, [string]$Package, [string]$Pattern) {
    $passedNames = @(); $failedNames = @(); $skippedNames = @(); $packagePassed = $false
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if (-not $line.Trim()) { continue }
        $event = $line | ConvertFrom-Json -ErrorAction Stop
        $hasTest = $null -ne $event.PSObject.Properties['Test'] -and $event.Test
        if ($event.Action -eq 'pass' -and $hasTest) { $passedNames += [string]$event.Test }
        if ($event.Action -eq 'fail' -and $hasTest) { $failedNames += [string]$event.Test }
        if ($event.Action -eq 'skip' -and $hasTest) { $skippedNames += [string]$event.Test }
        if ($event.Action -eq 'pass' -and -not $hasTest) { $packagePassed = $true }
    }
    if (-not $packagePassed -or $passedNames.Count -eq 0 -or $failedNames.Count -gt 0) { throw 'Required directed test package did not pass or matched no tests.' }
    [ordered]@{package=$Package;selector=$Pattern;passed_count=$passedNames.Count;failed_count=$failedNames.Count;skipped_count=$skippedNames.Count;skipped_tests=$skippedNames;passed=$true}
}

function Assert-AdmissionForward($Report, $Before) {
    if ($Report.schema_version -cne 'yimecore-speech-forward-source-v1' -or $Report.passed -ne $true -or
        $Report.record_count -ne 24 -or $Report.syllable_count -ne 50 -or @($Report.record_ids).Count -ne 24) { throw 'Forward-source receipt did not pass the reviewed scope.' }
    foreach ($gate in @('canonical_phrase_source','canonical_inventory_membership','formal_four_id_decomposition','semantic_tone_substitutions','canonical_layout_projection','inputs_unchanged')) {
        if ($Report.checks.$gate -ne $true) { throw 'Required forward-source gate missing.' }
    }
    if ($Report.checks.rime_executed -ne $false -or $Report.checks.aliases_generated -ne $false) { throw 'Forward-source checker exceeded scope.' }
    $byPath = @{}; foreach ($record in $Before) { $byPath[$record.path] = $record.sha256 }
    $properties = @($Report.input_sha256.PSObject.Properties)
    if ($properties.Count -ne 56) { throw 'Forward source closure is incomplete.' }
    foreach ($property in $properties) {
        if (-not $byPath.ContainsKey($property.Name) -or $byPath[$property.Name] -cne [string]$property.Value) { throw 'Forward input was not captured before execution, or its hash changed.' }
    }
}

function Assert-AdmissionProcessOutcome($Report, [string]$BrokerHash) {
    if ($Report.schema_version -cne 'yimecore-speech-process-acceptance-v1' -or $Report.passed -ne $true -or
        $Report.broker_sha256 -cne $BrokerHash -or $Report.rime_executed -ne $false -or
        $Report.installed_broker_connected -ne $false -or $Report.user_data_read -ne $false -or
        $Report.windows_reboot_tested -ne $false -or $Report.registered_or_live_host_tested -ne $false) { throw 'Owned Broker process acceptance failed or exceeded scope.' }
    $names = @('disabled-before','enabled-train','enabled-restart','disabled-after','reenabled','invalid-generation-rejected','valid-generation-recovery')
    if ((@($Report.stages.name) -join '|') -cne ($names -join '|')) { throw 'Incomplete process lifecycle matrix.' }
    $pids = @()
    for ($i=0; $i -lt 7; $i++) {
        $item = $Report.stages[$i]
        if ($item.passed -ne $true -or $item.pid -le 0) { throw 'Process stage did not pass.' }
        $pids += $item.pid
        if ($i -lt 5) {
            $generation = if ($i -eq 0) { 0 } else { 6 }
            if ($item.modes_passed -ne 3 -or $item.canonical_checks -ne 72 -or $item.alias_or_disabled_source_checks -ne 72 -or
                $item.learning_generation -ne $generation -or $item.exit_code -ne 0) { throw 'Mode, canonical, alias or durable restart evidence incomplete.' }
        } elseif ($i -eq 5) {
            if ($item.state_unchanged -ne $true -or $item.exit_code -ne 42) { throw 'Rejected generation lacks the dedicated pre-state rejection code.' }
        } elseif ($item.modes_passed -ne 3 -or $item.canonical_checks -ne 3 -or $item.learned_alias_checks -ne 3 -or
            $item.learning_generation -ne 6 -or $item.exit_code -ne 0) { throw 'Valid generation did not actually recover after rejection.' }
    }
    if (@($pids | Sort-Object -Unique).Count -ne 7) { throw 'Independent process starts were not identified uniquely.' }
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$install = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$scope = Get-YimeCoreDevelopmentScope
if ($scope.computer_name -cne 'MYCOMPUTER') { throw 'This isolated admission lane is pinned to MYCOMPUTER.' }
Assert-SpeechPlainPath $install
Assert-SpeechPlainPath $Python
if (-not [IO.Path]::IsPathRooted($Python) -or -not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'An explicit installed Python executable is required.' }
$go = 'C:\Program Files\Go\bin\go.exe'
Assert-SpeechPlainPath $go
if (-not (Test-Path -LiteralPath $go -PathType Leaf)) { throw 'Pinned local Go executable is unavailable.' }
$outParent = Join-Path $repo '.tmp\yimecore-experiment'
$runID = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
$out = Join-Path $outParent ('speech-admission-' + $runID)
Assert-SpeechPlainPath $out
if (Test-Path -LiteralPath $out) { throw 'Preserve existing evidence; fresh output is required.' }
$baselineScript = Join-Path $PSScriptRoot 'get-l5-daily-use-baseline.ps1'
$before=$null; $after=$null; $inputsBefore=@(); $sourcesBefore=@(); $legacyBefore=@()
$inputsUnchanged=$false; $sourcesUnchanged=$false; $legacyUnchanged=$false; $baselineUnchanged=$false
$completed=$false; $failure=$null; $stage='baseline'; $tests=@(); $toolRecords=@(); $dependencyRecords=@(); $goVersion=$null
$preparePassed=$false; $processPassed=$false; $forwardPassed=$false; $dependencyPassed=$false; $processSummary=$null
$pythonTestsPassed=$false
$environment = [ordered]@{
    TEMP=(Join-Path $out 'private\temp');TMP=(Join-Path $out 'private\tmp');APPDATA=(Join-Path $out 'private\appdata');LOCALAPPDATA=(Join-Path $out 'private\localappdata');
    GOCACHE=(Join-Path $out 'private\gocache');GOMODCACHE=(Join-Path $out 'private\gomodcache');GOPATH=(Join-Path $out 'private\gopath');
    GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOWORK='off';GOENV='off';GOTELEMETRY='off';
    GOFLAGS='-mod=readonly -trimpath -buildvcs=false';GOPRIVATE=$null;GONOPROXY='none';GONOSUMDB='none';GOEXPERIMENT=$null;GOAMD64='v1';
    PYTHONDONTWRITEBYTECODE='1';PYTHONNOUSERSITE='1';PYTHONPATH=$null;PYTHONHOME=$null;
    YIME_RUN_REAL_RIME_TESTS=$null;YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE=$null;YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST=$null;YIME_TEXTSERVICE_EXPERIMENT_PIPE=$null;
    YIMECORE_TEST_PIPE_NAME=$null;YIMECORE_TEST_STATE_ROOT=$null;YIMECORE_TOOL_SMOKE_TEST=$null;YIME_RUNTIME_JOB_HELPER=$null;
    YIME_SPEECH_LATENCY_ROOT=$null;YIME_SPEECH_LATENCY_OUTPUT=$null;YIME_SYNTHETIC_PRODUCT_TEST_CHILD=$null
}
$original = @{}; foreach ($name in $environment.Keys) { $original[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$restoreFailures=@(); $environmentRestored=$false; $pythonOutput=@()
try {
    $before = & $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256.ToLowerInvariant() | ConvertFrom-Json
    Assert-SpeechBaseline $before $install $ExpectedManifestSha256
    $stage='input-snapshots'
    $inputsBefore = @(Get-SpeechLockedInputs $repo)
    $sourcesBefore = @(Get-AdmissionSourceRecords $repo)
    if (@($sourcesBefore | Where-Object { $_.path -ceq 'tools/yimecore/run-connected-speech-reconnect.ps1' -and $_.sha256 -ceq $helperLoadedSHA }).Count -ne 1) { throw 'Loaded helper no longer matches the source snapshot.' }
    $legacyBefore = @(Get-AdmissionLegacyRecords)
    $stage='forward-source'
    # -I ignores ambient Python paths/user-site; -B and the checker prohibit
    # bytecode writes. The checker alone exclusively creates this new root.
    $pythonOutput = @(& $Python -I -B (Join-Path $repo 'tools\lexicon\validate_connected_speech_forward.py') --repo $repo --output (Join-Path $out 'forward-source.json') 2>&1)
    $pythonExit=$LASTEXITCODE
    if (-not (Test-Path -LiteralPath $out -PathType Container)) { throw 'Forward checker did not reserve the new trial root.' }
    Assert-SpeechPlainPath $out
    $pythonOutput | Set-Content -LiteralPath (Join-Path $out 'forward-tool.log') -Encoding UTF8
    if ($pythonExit -ne 0) { throw 'Forward-source checker failed.' }
    $forward = Get-Content -LiteralPath (Join-Path $out 'forward-source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AdmissionForward $forward $sourcesBefore
    $forwardPassed=$true
    Write-SpeechJson $before (Join-Path $out 'installed-before.json')
    Write-SpeechJson $inputsBefore (Join-Path $out 'locked-inputs-before.json')
    Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
    Write-SpeechJson $legacyBefore (Join-Path $out 'legacy-static-before.json')
    $stage='private-environment'
    foreach ($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA','GOCACHE','GOMODCACHE','GOPATH')) { New-Item -ItemType Directory -Path $environment[$name] -Force | Out-Null }
    foreach ($name in $environment.Keys) { Set-SpeechEnvironmentValue $name $environment[$name] }
    $bin=Join-Path $out 'bin'; $logs=Join-Path $out 'logs'
    New-Item -ItemType Directory -Path $bin,$logs | Out-Null
    $stage='python-contracts'
    Push-Location $repo
    try {
        Invoke-AdmissionLogged $Python @('-B','-m','unittest','tools.lexicon.tests.test_validate_connected_speech_forward','-v') (Join-Path $logs 'python-contracts.log')
        $pythonTestsPassed=$true
    } finally { Pop-Location }
    $versionLines=@(& $go version)
    if ($LASTEXITCODE -ne 0 -or $versionLines.Count -ne 1 -or [string]$versionLines[0] -notmatch '^go version go[0-9][A-Za-z0-9.]* windows/amd64$') { throw 'Expected a local Windows AMD64 Go toolchain.' }
    $goVersion=[string]$versionLines[0]
    Push-Location (Join-Path $repo 'go-backend')
    try {
        $testJobs=@(
            @{id='admission';package='./input_methods/yime/connectedspeech';pattern='^TestStage5CAdmission'},
            @{id='projection';package='./input_methods/yime/layoutdesigner';pattern='^Test(ProjectIDRecord|ReencodeUsesYinyuanIDsAndSemanticShorthand$|ReencodePreservesVirtualShouyinAsSyllableBoundary$|DescribeIDDistinguishesRealAndVirtualShouyin$|ValidateRejectsReservedCandidateKey$)'},
            @{id='core';package='./input_methods/yime/yimecore';pattern='^Test'},
            @{id='broker';package='./input_methods/yime/yimebroker';pattern='^Test(BundleGenerationManager|ConnectedSpeechReconnectBrokerBundleDurableLifecycle|ServeLines|ConnectionLimiter)'},
            @{id='manifest';package='./input_methods/yime/speechruntime';pattern='^TestSpeech(Manifest|Forward)'},
            @{id='broker-flags';package='./cmd/yimebroker';pattern='^Test(SpeechExperiment|EnabledUserModelHonorsLearningConfigWithoutDeletingModel$)'},
            @{id='exercise-contract';package='./cmd/yimecore-speech-admission';pattern='^TestSpeech(Exercise|Package|ProductExport)'}
        )
        foreach ($job in $testJobs) {
            $stage='test-'+$job.id; $log=Join-Path $logs ($job.id+'.jsonl')
            Invoke-AdmissionLogged $go @('test','-json','-count=1','-timeout=10m',$job.package,'-run',$job.pattern) $log
            $tests += Read-AdmissionTestOutcomes $log $job.package $job.pattern
        }
        $stage='broker-dependencies'; $depLog=Join-Path $logs 'broker-dependencies.log'
        Invoke-AdmissionLogged $go @('list','-deps','-f','{{.ImportPath}}|{{len .CgoFiles}}','./cmd/yimebroker') $depLog
        foreach ($line in Get-Content -LiteralPath $depLog -Encoding UTF8) {
            if ($line -notmatch '^([^|]+)\|([0-9]+)$') { throw 'Dependency evidence has an unexpected line.' }
            $importPath=$Matches[1]; $cgoFiles=[int]$Matches[2]
            if ($cgoFiles -ne 0 -or $importPath -ceq 'runtime/cgo' -or $importPath -ceq 'github.com/tsaanghwang/Yime/go-backend/input_methods/yime' -or $importPath -match '(^|/)(librime|rime|pime)($|/)') {
                throw 'Broker dependency boundary includes CGo, Rime/PIME or the parent host runtime.'
            }
            $dependencyRecords += [ordered]@{import_path=$importPath;cgo_files=$cgoFiles}
        }
        if ($dependencyRecords.Count -eq 0) { throw 'Broker dependency inventory is empty.' }
        $dependencyPassed=$true
        foreach ($tool in @(@{package='./cmd/yimebroker';name='YimeBroker-speech.exe'},@{package='./cmd/yimecore-speech-admission';name='YimeSpeechAdmission.exe'})) {
            $stage='build-'+$tool.name
            Invoke-AdmissionLogged $go @('build','-o',(Join-Path $bin $tool.name),$tool.package) (Join-Path $logs ($tool.name+'-build.log'))
            $toolRecords += Get-SpeechRecord $out ('bin/'+$tool.name)
        }
    } finally { Pop-Location }
    $stage='prepare'
    $admissionTool=Join-Path $bin 'YimeSpeechAdmission.exe'; $broker=Join-Path $bin 'YimeBroker-speech.exe'
    $brokerHash=(Get-FileHash -LiteralPath $broker -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-AdmissionLogged $admissionTool @('-action','prepare','-repo',$repo,'-root',$out) (Join-Path $logs 'prepare.log')
    $prepare=Get-Content -LiteralPath (Join-Path $out 'prepare-outcome.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($prepare.schema_version -cne 'yimecore-speech-prepare-v1' -or $prepare.passed -ne $true -or $prepare.records -ne 24 -or
        $prepare.mode_rows -ne 72 -or $prepare.rime_executed -ne $false -or $prepare.runtime_rule_inference -ne $false -or
        $prepare.installed_product_changed -ne $false -or @($prepare.builds.PSObject.Properties).Count -ne 3) { throw 'Preparation receipt is incomplete or exceeded scope.' }
    $preparePassed=$true
    $stage='owned-process-lifecycle'
    Invoke-AdmissionLogged $admissionTool @('-action','exercise','-root',$out,'-broker',$broker,'-broker-sha256',$brokerHash) (Join-Path $logs 'exercise.log')
    $processSummary=Get-Content -LiteralPath (Join-Path $out 'process-outcome.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AdmissionProcessOutcome $processSummary $brokerHash
    $processPassed=$true; $completed=$true
} catch { $failure=[ordered]@{stage=$stage;code='isolated_admission_stage_failed';detail='Inspect fixed fixture logs only; no repair attempted.'} }
finally {
    foreach ($name in $environment.Keys) { try { Set-SpeechEnvironmentValue $name $original[$name] } catch { $restoreFailures += $name } }
    $environmentRestored=$restoreFailures.Count -eq 0
    # A preflight failure must not manufacture the Python-owned trial root.
    # Keep it separate from any runnable/prepared admission directory.
    $evidenceRoot=$out
    if (-not (Test-Path -LiteralPath $out -PathType Container)) {
        $evidenceRoot=Join-Path $outParent ('speech-admission-runner-failure-'+$runID)
        Assert-SpeechPlainPath $evidenceRoot
        New-Item -ItemType Directory -Path $evidenceRoot -ErrorAction Stop | Out-Null
    }
    Write-SpeechJson $before (Join-Path $evidenceRoot 'installed-before.json')
    Write-SpeechJson $inputsBefore (Join-Path $evidenceRoot 'locked-inputs-before.json')
    Write-SpeechJson $sourcesBefore (Join-Path $evidenceRoot 'source-hashes-before.json')
    Write-SpeechJson $legacyBefore (Join-Path $evidenceRoot 'legacy-static-before.json')
    foreach ($check in @('inputs','sources','legacy','baseline')) {
        try {
            switch ($check) {
                'inputs' { $value=@(Get-SpeechLockedInputs $repo); Write-SpeechJson $value (Join-Path $evidenceRoot 'locked-inputs-after.json'); if ($inputsBefore.Count -eq 0) { throw 'No initial lock snapshot.' }; Assert-SpeechSameRecords $inputsBefore $value; $inputsUnchanged=$true }
                'sources' { $value=@(Get-AdmissionSourceRecords $repo); Write-SpeechJson $value (Join-Path $evidenceRoot 'source-hashes-after.json'); if ($sourcesBefore.Count -eq 0) { throw 'No initial source snapshot.' }; Assert-SpeechSameRecords $sourcesBefore $value; $sourcesUnchanged=$true }
                'legacy' { $value=@(Get-AdmissionLegacyRecords); Write-SpeechJson $value (Join-Path $evidenceRoot 'legacy-static-after.json'); if ($legacyBefore.Count -ne 7) { throw 'No complete retained payload snapshot.' }; Assert-SpeechSameRecords $legacyBefore $value; $legacyUnchanged=$true }
                'baseline' { $after=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256.ToLowerInvariant() | ConvertFrom-Json; Write-SpeechJson $after (Join-Path $evidenceRoot 'installed-after.json'); Assert-SpeechBaseline $after $install $ExpectedManifestSha256; if ($null -eq $before) { throw 'No initial installed baseline.' }; Assert-SpeechBaselineUnchanged $before $after; $baselineUnchanged=$true }
            }
        } catch { if ($null -eq $failure) { $failure=[ordered]@{stage='after-'+$check;code='protection_verification_failed';detail='Preserve isolated evidence; no repair attempted.'} } }
    }
    if (-not $environmentRestored -and $null -eq $failure) { $failure=[ordered]@{stage='environment-restore';code='exact_environment_restore_failed'} }
    $passed=$completed -and $forwardPassed -and $pythonTestsPassed -and $preparePassed -and $processPassed -and $dependencyPassed -and $inputsUnchanged -and $sourcesUnchanged -and $legacyUnchanged -and $baselineUnchanged -and $environmentRestored
    $artifactRecords=@()
    $sourceInventory=$null; $sourceInventoryBefore=$null
    try {
        $sourceInventory=Get-SpeechRecord $evidenceRoot 'source-hashes-after.json'
        $sourceInventoryBefore=Get-SpeechRecord $evidenceRoot 'source-hashes-before.json'
    } catch { $passed=$false; if ($null -eq $failure) { $failure=[ordered]@{stage='source-inventory-binding';code='incomplete_source_inventory'} } }
    if ($passed) { try {
        $artifactPaths=@('bundle-off.json','bundle-on.json','admission.json','forward-source.json','admitted-records.json',
            'prepare-outcome.json','process-outcome.json')
        foreach ($mode in @('full','variable','shorthand')) { $artifactPaths+=@("indexes/$mode-core.yidx","indexes/$mode-stage5c.yidx") }
        $artifactRecords=@($artifactPaths | Sort-Object | ForEach-Object { Get-SpeechRecord $evidenceRoot $_ })
    } catch { $passed=$false; $artifactRecords=@(); if ($null -eq $failure) { $failure=[ordered]@{stage='admission-artifact-binding';code='incomplete_admission_artifacts'} } } }
    $summary=[ordered]@{schema_version='yimecore-speech-admission-isolated-v1';generated_at=(Get-Date).ToString('o');passed=$passed;failure=$failure;
        stage=$(if($passed){'complete'}else{'incomplete'});
        source_inventory=$sourceInventory;
        source_inventory_before=$sourceInventoryBefore;admission_artifacts=$artifactRecords;
        development_scope=$scope;trial_root=$out;install_root=$install;installed_manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();
        module='third-tone-stage5c';reviewed_records=24;mode_alias_rows=72;forward_source_passed=$forwardPassed;admission_prepare_passed=$preparePassed;owned_process_acceptance_passed=$processPassed;
        dependency_boundary_passed=$dependencyPassed;dependencies=$dependencyRecords;directed_tests=$tests;tools=$toolRecords;go_toolchain=$go;go_version=$goVersion;python=$Python;
        python_contracts_passed=$pythonTestsPassed;
        helper_definition_allowlist=$helperAllowlist;helper_source_sha256=$helperLoadedSHA;
        installed_baseline_unchanged=$baselineUnchanged;locked_inputs_unchanged=$inputsUnchanged;source_set_unchanged=$sourcesUnchanged;legacy_static_unchanged=$legacyUnchanged;
        private_environment_names=@($environment.Keys);environment_restored=$environmentRestored;environment_restore_failures=$restoreFailures;
        real_rime_executed=$false;registered_hosts_executed=$false;frozen_targets_executed=$false;default_input_method_changed=$false;new_package_installed=$false;
        daily_broker_connected=$false;user_text_read=$false;live_learning_data_read=$false;live_config_read=$false;product_or_registry_mutated=$false;
        synthetic_learning_data_used=$true;local_product_ready=$false;public_release_ready=$false;windows_reboot_gate_passed=$null;installed_speech_gate_passed=$null;
        limitations=@('Only the 24 previously reviewed Stage5C records are admitted; other reserved modules remain unconnected.',
            'Static dictionary syntax may be imported by YimeCore; no Rime library, generator, deployer or runtime is executed.',
            'Process restarts, selection, paging, cancellation and learning use owned anonymous-pipe fixture processes and private state, not installed TSF or live hosts.',
            'Skipped directed tests remain explicitly listed; no skipped path is inferred passed.',
            'L5 final user confirmation, installed candidate acceptance, L6 sealing and ARM64 native hosts remain separate gates.')}
    Write-SpeechJson $summary (Join-Path $evidenceRoot 'summary.json')
}
if (-not $passed) { throw "Isolated speech admission did not pass. Outcome evidence: $evidenceRoot" }
Write-Output "PASS: Stage5C admission and owned Broker process lifecycle only. Evidence: $evidenceRoot"
