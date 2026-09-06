[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [Parameter(Mandatory)][string]$SpeechAdmissionRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSpeechAdmissionSummarySha256,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSpeechSourceInventorySha256,
    [Parameter(Mandatory)][string]$ProcessFixtureRoot
)
# SR4-B2: build-only, explicit fresh admission -> normal package -> owned runtime.
# No installer, installed maintenance command, registration or default pipe call.
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5') { throw 'PowerShell 7.5+ required for exact environment restoration.' }
$tokens=$null; $errors=$null
$loaderPath=Join-Path $PSScriptRoot 'run-connected-speech-product-source.ps1'
$loaderSHA=(Get-FileHash -LiteralPath $loaderPath -Algorithm SHA256).Hash
$ast=[Management.Automation.Language.Parser]::ParseFile($loaderPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count) { throw 'Helper source parse failed.' }
$found=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -CEQ 'Import-ProductSourceFunctions')
if ($found.Count -ne 1) { throw 'Unique definition-only helper loader required.' }
. ([scriptblock]::Create($found[0].Extent.Text))
if ((Get-FileHash -LiteralPath $loaderPath -Algorithm SHA256).Hash -cne $loaderSHA) { throw 'Loader changed while reading.' }
$common=@('Assert-SpeechPlainPath','Resolve-SpeechChild','Write-SpeechJson','Set-SpeechEnvironmentValue','Get-SpeechRecord',
    'Assert-SpeechSameRecords','Assert-SpeechBaseline','Get-SpeechBaselineIdentity','Assert-SpeechBaselineUnchanged','Get-SpeechDefinitions','Get-SpeechLockedInputs')
foreach ($definition in @(Import-ProductSourceFunctions (Join-Path $PSScriptRoot 'run-connected-speech-reconnect.ps1') $common)) { . $definition }
foreach ($definition in @(Import-ProductSourceFunctions (Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1') @('Get-AdmissionSourceRecords','Get-AdmissionLegacyRecords','Invoke-AdmissionLogged','Read-AdmissionTestOutcomes'))) { . $definition }
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
. (Join-Path $PSScriptRoot 'local-product-speech-build.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$scope=Get-YimeCoreDevelopmentScope
if ($scope.computer_name -cne 'MYCOMPUTER' -or $env:COMPUTERNAME -ine 'MYCOMPUTER') { throw 'SR4-B2 is pinned to MYCOMPUTER.' }
$install=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$product=Get-LocalProductDescriptor (Join-Path $PSScriptRoot 'local-product.json')
if (-not (Assert-LocalProductSpeechBuildInputs $product $SpeechAdmissionRoot $ExpectedSpeechAdmissionSummarySha256 $ExpectedSpeechSourceInventorySha256)) { throw 'SR4-B2 requires a declared default-off speech candidate.' }
# Windows special-folder API, not an overridable USERPROFILE trust anchor.
$profile=[Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$fixture=[IO.Path]::GetFullPath($ProcessFixtureRoot).TrimEnd('\')
$fixtureParent=Join-Path $profile 'YimeCore Isolated Fixtures\SR4B2'
if ((Split-Path -Parent $fixture) -ine $fixtureParent -or (Split-Path -Leaf $fixture) -cnotmatch '^speech-product-test-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $fixture)) { throw 'Normal process test requires an explicitly selected new private SR4B2 profile fixture.' }
Assert-SpeechPlainPath $fixture
$runID=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')
$out=Join-Path $repo ('.tmp\yimecore-experiment\speech-product-package-'+$runID)
$build=Join-Path $repo ('.tmp\yimecore-local-product\speech-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
foreach ($path in @($out,$build)) { Assert-SpeechPlainPath $path; if (Test-Path -LiteralPath $path) { throw 'Preserve prior evidence.' } }
New-Item -ItemType Directory -Path $out,(Join-Path $out 'logs'),(Join-Path $out 'bin') | Out-Null
$baselineScript=Join-Path $PSScriptRoot 'get-l5-daily-use-baseline.ps1'
$environment=[ordered]@{
    TEMP=(Join-Path $out 'private\temp');TMP=(Join-Path $out 'private\tmp');APPDATA=(Join-Path $out 'private\appdata');LOCALAPPDATA=(Join-Path $out 'private\localappdata');
    GOCACHE=(Join-Path $out 'private\gocache');GOMODCACHE=(Join-Path $out 'private\gomodcache');GOPATH=(Join-Path $out 'private\gopath');
    GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOWORK='off';GOENV='off';GOTELEMETRY='off';
    GOFLAGS='';GOPRIVATE=$null;GONOPROXY='none';GONOSUMDB='none';GOEXPERIMENT=$null;GOAMD64='v1';
    YIME_RUN_REAL_RIME_TESTS=$null;YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE=$null;YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST=$null;YIME_TEXTSERVICE_EXPERIMENT_PIPE=$null;
    YIMECORE_TEST_PIPE_NAME=$null;YIMECORE_TEST_STATE_ROOT=$null;YIMECORE_TOOL_SMOKE_TEST=$null;YIME_RUNTIME_JOB_HELPER=$null;
    YIME_SPEECH_LATENCY_ROOT=$null;YIME_SPEECH_LATENCY_OUTPUT=$null;YIME_SYNTHETIC_PRODUCT_TEST_CHILD=$null
}
$original=@{}; foreach ($name in $environment.Keys) { $original[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$before=$null; $sourcesBefore=@(); $inputsBefore=@(); $legacyBefore=@(); $tests=@(); $psTests=@(); $tool=$null
$complete=$false; $buildOK=$false; $processOK=$false; $baselineOK=$false; $sourceOK=$false; $inputsOK=$false; $legacyOK=$false
$failure=$null; $restoreFailures=@(); $stage='baseline'; $manifestSHA=$null; $processSummary=$null
try {
    $before=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json
    Assert-SpeechBaseline $before $install $ExpectedManifestSha256
    $sourcesBefore=@(Get-AdmissionSourceRecords $repo); $inputsBefore=@(Get-SpeechLockedInputs $repo); $legacyBefore=@(Get-AdmissionLegacyRecords)
    # Check the actual source inventory before expensive native compilation.
    Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
    if ((Get-FileHash -LiteralPath (Join-Path $out 'source-hashes-before.json') -Algorithm SHA256).Hash -ine $ExpectedSpeechSourceInventorySha256) { throw 'Admission no longer describes current source.' }
    foreach ($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA','GOCACHE','GOMODCACHE','GOPATH')) { New-Item -ItemType Directory -Path $environment[$name] -Force | Out-Null }
    foreach ($name in $environment.Keys) { Set-SpeechEnvironmentValue $name $environment[$name] }
    $go='C:\Program Files\Go\bin\go.exe'
    $stage='powershell-fixture-contracts'
    foreach ($shell in @(@{id='ps7';exe=(Get-Process -Id $PID).Path},@{id='ps5';exe=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')})) {
        foreach ($test in @(
            @{file='test-local-product-speech-build.ps1';prefix='speech-build-contract-'},
            @{file='test-speech-maintenance-data.ps1';prefix='speech-maintenance-data-'},
            @{file='test-local-maintenance-config-data.ps1';prefix='maintenance-config-data-'})) {
            $testOut=Join-Path $repo ('.tmp\yimecore-experiment\'+$test.prefix+$shell.id+'-'+$runID)
            Invoke-AdmissionLogged $shell.exe @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $test.file),'-OutputRoot',$testOut) (Join-Path $out ('logs/'+$shell.id+'-'+$test.file+'.log'))
            $result=Get-Content -LiteralPath (Join-Path $testOut 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $result.passed -or $result.failed_count -ne 0 -or $result.checks_count -le 0) { throw 'PowerShell fixture failed or empty.' }
            $psTests+=@{shell=$shell.id;test=$test.file;root=$testOut;checks_count=$result.checks_count;result_sha256=(Get-FileHash -LiteralPath (Join-Path $testOut 'result.json') -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
    }
    Push-Location (Join-Path $repo 'go-backend')
    try {
        foreach ($job in @(
            @{id='export';package='./cmd/yimecore-speech-admission';pattern='^TestSpeech(Exercise|Package|ProductExport)'},
            @{id='audit';package='./cmd/yimecore-independence-audit';pattern='^Test'},
            @{id='normal-process';package='./cmd/yimecore-speech-product-test';pattern='^Test'},
            @{id='speech-runtime';package='./input_methods/yime/speechruntime';pattern='^Test'},
            @{id='annotations';package='./input_methods/yime/candidateannotation';pattern='^Test'},
            @{id='broker-command';package='./cmd/yimebroker';pattern='^Test'})) {
            $stage='test-'+$job.id; $log=Join-Path $out ('logs/'+$job.id+'.jsonl')
            Invoke-AdmissionLogged $go @('test','-json','-count=1','-timeout=10m',$job.package,'-run',$job.pattern) $log
            $tests+=Read-AdmissionTestOutcomes $log $job.package $job.pattern
        }
        $stage='build-process-harness'
        $harness=Join-Path $out 'bin/YimeSpeechProductTest.exe'
        Invoke-AdmissionLogged $go @('build','-trimpath','-buildvcs=false','-o',$harness,'./cmd/yimecore-speech-product-test') (Join-Path $out 'logs/harness-build.log')
        $tool=Get-SpeechRecord $out 'bin/YimeSpeechProductTest.exe'
    } finally { Pop-Location }
    $stage='fresh-normal-package-build'
    & (Join-Path $PSScriptRoot 'build-local-product.ps1') -OutputRoot $build -SpeechAdmissionRoot $SpeechAdmissionRoot `
        -ExpectedSpeechAdmissionSummarySha256 $ExpectedSpeechAdmissionSummarySha256 -ExpectedSpeechSourceInventorySha256 $ExpectedSpeechSourceInventorySha256 | Out-Host
    $buildResult=Get-Content -LiteralPath (Join-Path $build 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $buildResult.passed -or -not $buildResult.registration_and_default_preserved) { throw 'Fresh normal package did not pass build gates.' }
    $buildOK=$true
    $package=Join-Path $build 'package'
    $manifestSHA=(Get-FileHash -LiteralPath (Join-Path $package 'package-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $stage='normal-runtime-private-process-lifecycle'
    Invoke-AdmissionLogged $harness @('-package',$package,'-package-sha256',$manifestSHA,'-output-root',$fixture) (Join-Path $out 'logs/normal-process.log')
    $processSummary=Get-Content -LiteralPath (Join-Path $fixture 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($processSummary.schema_version -cne 'yimecore-speech-normal-process-v1' -or $processSummary.passed -ne $true -or
        $processSummary.source_package_unchanged -ne $true -or $processSummary.private_package_unchanged -ne $true -or
        (@($processSummary.stages.name) -join '|') -cne 'disabled-before|enabled-train|enabled-restart|disabled-after|reenabled|invalid-generation-rejected|valid-generation-recovered') { throw 'Normal runtime lifecycle did not pass its full seven-stage contract.' }
    foreach ($flag in @('installed_runtime_connected','installation_or_registered_host_tested','windows_reboot_tested','rime_executed','user_data_read')) {
        if ($processSummary.$flag -ne $false) { throw 'Normal process fixture exceeded its privacy or installation boundary.' }
    }
    foreach ($item in $processSummary.stages) {
        if ($item.passed -ne $true) { throw 'A normal process lifecycle phase did not pass.' }
        if ($item.name -ceq 'invalid-generation-rejected') {
            if ($item.rejection_exit_code -ne 1 -or $item.state_unchanged -ne $true -or
                $item.rejection_diagnostic -cne 'capability_product_hash_mismatch' -or
                $item.rejection_diagnostic_sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid generation did not produce the exact capability rejection before durable state mutation.' }
        } else {
            $expectedGeneration=6; if ($item.name -ceq 'disabled-before') { $expectedGeneration=0 }
            if ($item.modes_passed -ne 3 -or $item.canonical_checks -ne 72 -or $item.alias_or_disabled_checks -ne 72 -or
                $item.learning_generation -ne $expectedGeneration -or $item.runtime_stopped -ne $true -or $item.broker_stopped -ne $true -or
                $item.runtime.pid -le 0 -or $item.broker.pid -le 0) { throw 'Normal phase lacks complete mode, durable state or owned process cleanup evidence.' }
        }
    }
    $processOK=$true
    $stage='original-package-after-process-audit'
    Invoke-AdmissionLogged (Join-Path $package 'bin/YimeCoreIndependenceAudit.exe') @('-package',$package,'-output',(Join-Path $out 'independence-after-normal-process.json')) (Join-Path $out 'logs/independence-after-normal-process.log')
    if ((Get-FileHash -LiteralPath (Join-Path $package 'package-manifest.json') -Algorithm SHA256).Hash -ine $manifestSHA) { throw 'Original package manifest changed.' }
    $complete=$true
} catch { $failure=[ordered]@{stage=$stage;code='product_package_gate_failed';detail='Inspect fixed isolated fixture logs; no installed repair attempted.'} }
finally {
    foreach ($name in $environment.Keys) { try { Set-SpeechEnvironmentValue $name $original[$name] } catch { $restoreFailures+=$name } }
    foreach ($check in @('sources','inputs','legacy','baseline')) { try {
        switch ($check) {
            sources { $v=@(Get-AdmissionSourceRecords $repo); Write-SpeechJson $v (Join-Path $out 'source-hashes-after.json'); if (-not $sourcesBefore.Count) { throw 'Missing source baseline.' }; Assert-SpeechSameRecords $sourcesBefore $v; $sourceOK=$true }
            inputs { $v=@(Get-SpeechLockedInputs $repo); Write-SpeechJson $v (Join-Path $out 'locked-inputs-after.json'); if (-not $inputsBefore.Count) { throw 'Missing locked input baseline.' }; Assert-SpeechSameRecords $inputsBefore $v; $inputsOK=$true }
            legacy { $v=@(Get-AdmissionLegacyRecords); Write-SpeechJson $v (Join-Path $out 'legacy-static-after.json'); if ($legacyBefore.Count -ne 7) { throw 'Missing retained payload baseline.' }; Assert-SpeechSameRecords $legacyBefore $v; $legacyOK=$true }
            baseline { $v=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json; Write-SpeechJson $v (Join-Path $out 'installed-after.json'); Assert-SpeechBaseline $v $install $ExpectedManifestSha256; if ($null -eq $before) { throw 'Missing installed baseline.' }; Assert-SpeechBaselineUnchanged $before $v; $baselineOK=$true }
        }
    } catch { if ($null -eq $failure) { $failure=[ordered]@{stage='after-'+$check;code='protection_verification_failed'} } } }
    Write-SpeechJson $before (Join-Path $out 'installed-before.json')
    Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
    Write-SpeechJson $inputsBefore (Join-Path $out 'locked-inputs-before.json')
    Write-SpeechJson $legacyBefore (Join-Path $out 'legacy-static-before.json')
    $passed=$complete -and $buildOK -and $processOK -and $sourceOK -and $inputsOK -and $legacyOK -and $baselineOK -and $restoreFailures.Count -eq 0
    $result=[ordered]@{schema_version='yimecore-speech-product-package-v1';phase='SR4-B2';generated_at=(Get-Date).ToString('o');passed=$passed;failure=$failure;
        candidate_version=$product.version;candidate_build_root=$build;package_manifest_sha256=$manifestSHA;default_enabled=$false;
        admission_root=$SpeechAdmissionRoot;admission_summary_sha256=$ExpectedSpeechAdmissionSummarySha256.ToLowerInvariant();source_inventory_sha256=$ExpectedSpeechSourceInventorySha256.ToLowerInvariant();
        source_set_unchanged=$sourceOK;locked_inputs_unchanged=$inputsOK;legacy_static_unchanged=$legacyOK;installed_baseline_unchanged=$baselineOK;
        install_root=$install;installed_manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();directed_tests=$tests;powershell_tests=$psTests;process_harness=$tool;
        normal_package_build_passed=$buildOK;normal_process_lifecycle_passed=$processOK;process_fixture_root=$fixture;
        environment_restored=($restoreFailures.Count -eq 0);environment_restore_failures=$restoreFailures;
        real_rime_executed=$false;registered_hosts_executed=$false;frozen_targets_executed=$false;user_text_read=$false;live_learning_data_read=$false;default_input_method_changed=$false;
        new_package_installed=$false;installed_maintenance_executed=$false;windows_reboot_tested=$false;local_product_ready=$false;public_release_ready=$false;
        limitations=@('Direct x64/x86 TSF tests are private source-built contracts, not registered or live-host acceptance.',
            'Normal Runtime restart and copied-state recovery probe are not Windows reboot, installed restore or rollback acceptance.',
            'Learning and speech setting maintenance enumeration and restore mapping are fixture-tested; no real backup/restore transaction is executed.',
            'Skipped filesystem privilege paths remain skipped; no capability-removal or old-binary data rollback inferred.')}
    if ($processOK) { $result.process_summary_sha256=(Get-FileHash -LiteralPath (Join-Path $fixture 'summary.json') -Algorithm SHA256).Hash.ToLowerInvariant() }
    Write-SpeechJson $result (Join-Path $out 'summary.json')
}
if (-not $passed) { throw "SR4-B2 package gate did not pass. Preserve evidence: $out" }
Write-Output "PASS: default-off normal speech package and private Runtime lifecycle only; no installed gate inferred. Evidence: $out"
