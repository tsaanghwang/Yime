[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256
)
# SR4-B1 source/fixture validation only. No package builder, installer or TIP.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5') { throw 'PowerShell 7.5+ required for exact environment restoration.' }

function Import-ProductSourceFunctions([string]$Path, [string[]]$Names) {
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count) { throw 'Source validation helper parse failed.' }
    foreach ($name in $Names) {
        $found=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -CEQ $name)
        if ($found.Count -ne 1) { throw 'Source helper allowlist is ambiguous.' }
        [scriptblock]::Create($found[0].Extent.Text)
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $hash) { throw 'Source helper changed while loading.' }
}
$common=@('Assert-SpeechPlainPath','Resolve-SpeechChild','Write-SpeechJson','Set-SpeechEnvironmentValue','Get-SpeechRecord',
    'Assert-SpeechSameRecords','Assert-SpeechBaseline','Get-SpeechBaselineIdentity','Assert-SpeechBaselineUnchanged','Get-SpeechDefinitions','Get-SpeechLockedInputs')
foreach ($definition in @(Import-ProductSourceFunctions (Join-Path $PSScriptRoot 'run-connected-speech-reconnect.ps1') $common)) { . $definition }
foreach ($definition in @(Import-ProductSourceFunctions (Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1') @('Get-AdmissionSourceRecords','Get-AdmissionLegacyRecords','Invoke-AdmissionLogged','Read-AdmissionTestOutcomes'))) { . $definition }
. (Join-Path $PSScriptRoot 'development-scope.ps1')

function Get-ProductSourceRecords([string]$Repo) {
    $records = @(Get-AdmissionSourceRecords $Repo)
    $records
    foreach ($path in @('tools/yimecore/run-connected-speech-product-source.ps1','tools/yimecore/speech-product-contract.json','tools/yimecore/local-product.json')) {
        if ($path -cnotin @($records.path)) { Get-SpeechRecord $Repo $path }
    }
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$scope=Get-YimeCoreDevelopmentScope
if ($scope.computer_name -cne 'MYCOMPUTER' -or $env:COMPUTERNAME -ine $scope.computer_name) { throw 'Source validation is pinned to MYCOMPUTER.' }
$install=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$out=Join-Path $repo ('.tmp\yimecore-experiment\speech-product-source-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
Assert-SpeechPlainPath $out
if (Test-Path -LiteralPath $out) { throw 'Preserve prior evidence.' }
New-Item -ItemType Directory -Path $out,(Join-Path $out 'logs'),(Join-Path $out 'bin') | Out-Null
$baselineScript=Join-Path $PSScriptRoot 'get-l5-daily-use-baseline.ps1'
$environment=[ordered]@{
    TEMP=(Join-Path $out 'private\temp');TMP=(Join-Path $out 'private\tmp');APPDATA=(Join-Path $out 'private\appdata');LOCALAPPDATA=(Join-Path $out 'private\localappdata');
    GOCACHE=(Join-Path $out 'private\gocache');GOMODCACHE=(Join-Path $out 'private\gomodcache');GOPATH=(Join-Path $out 'private\gopath');
    GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOWORK='off';GOENV='off';GOTELEMETRY='off';
    GOFLAGS='-mod=readonly -trimpath -buildvcs=false';GOPRIVATE=$null;GONOPROXY='none';GONOSUMDB='none';GOEXPERIMENT=$null;GOAMD64='v1';
    YIME_RUN_REAL_RIME_TESTS=$null;YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE=$null;YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST=$null;YIME_TEXTSERVICE_EXPERIMENT_PIPE=$null;
    YIMECORE_TEST_PIPE_NAME=$null;YIMECORE_TEST_STATE_ROOT=$null;YIMECORE_TOOL_SMOKE_TEST=$null;YIME_RUNTIME_JOB_HELPER=$null;
    YIME_SPEECH_LATENCY_ROOT=$null;YIME_SPEECH_LATENCY_OUTPUT=$null;YIME_SYNTHETIC_PRODUCT_TEST_CHILD=$null
}
$original=@{}; foreach ($name in $environment.Keys) { $original[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$before=$null; $sourcesBefore=@(); $legacyBefore=@(); $inputsBefore=@(); $tests=@(); $tools=@()
$complete=$false; $baselineOK=$false; $sourceOK=$false; $legacyOK=$false; $inputsOK=$false; $depsOK=$false; $failure=$null; $stage='baseline'; $restoreFailures=@()
try {
    $before=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json
    Assert-SpeechBaseline $before $install $ExpectedManifestSha256
    $sourcesBefore=@(Get-ProductSourceRecords $repo); $legacyBefore=@(Get-AdmissionLegacyRecords); $inputsBefore=@(Get-SpeechLockedInputs $repo)
    foreach ($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA','GOCACHE','GOMODCACHE','GOPATH')) { New-Item -ItemType Directory -Path $environment[$name] -Force | Out-Null }
    foreach ($name in $environment.Keys) { Set-SpeechEnvironmentValue $name $environment[$name] }
    $go=(Get-Command go -CommandType Application -ErrorAction Stop).Source
    $goVersion=(& $go version) -join ''
    if ($LASTEXITCODE -ne 0 -or $goVersion -notmatch '^go version go[0-9][A-Za-z0-9.]* windows/amd64$') { throw 'Expected local Windows AMD64 Go.' }
    Push-Location (Join-Path $repo 'go-backend')
    try {
        $jobs=@(
            @{id='speech';package='./input_methods/yime/speechruntime'},
            @{id='broker-command';package='./cmd/yimebroker'},
            @{id='runtime';package='./cmd/yimecore-trial-runtime'},
            @{id='settings';package='./cmd/settings-tool'},
            @{id='core';package='./input_methods/yime/yimecore'},
            @{id='broker';package='./input_methods/yime/yimebroker'},
            @{id='professional';package='./input_methods/yime/professionallexicon'},
            @{id='annotation';package='./input_methods/yime/candidateannotation'},
            @{id='filter';package='./input_methods/yime/candidatefilter'},
            @{id='backup';package='./input_methods/yime/userbackup'},
            @{id='package-regression';package='./cmd/yimecore-speech-admission';pattern='^TestSpeech(Exercise|Package)'}
        )
        foreach ($job in $jobs) {
            $stage='test-'+$job.id; $log=Join-Path $out ('logs/'+$job.id+'.jsonl')
            $pattern='^Test'; if ($job.ContainsKey('pattern')) { $pattern=$job.pattern }
            Invoke-AdmissionLogged $go @('test','-json','-count=1','-timeout=10m',$job.package,'-run',$pattern) $log
            $tests+=Read-AdmissionTestOutcomes $log $job.package $pattern
        }
        $stage='normal-runtime-dependencies'; $depLog=Join-Path $out 'logs/dependencies.log'
        Invoke-AdmissionLogged $go @('list','-deps','-f','{{.ImportPath}}|{{len .CgoFiles}}','./cmd/yimebroker','./cmd/yimecore-trial-runtime') $depLog
        foreach ($line in Get-Content -LiteralPath $depLog) {
            if ($line -notmatch '^([^|]+)\|([0-9]+)$') { throw 'Unexpected dependency record.' }
            if ([int]$Matches[2] -ne 0 -or $Matches[1] -ceq 'runtime/cgo' -or $Matches[1] -ceq 'github.com/tsaanghwang/Yime/go-backend/input_methods/yime' -or $Matches[1] -match '(^|/)(librime|rime|pime)($|/)') { throw 'Normal runtime dependency crossed product boundary.' }
        }
        $depsOK=$true
        foreach ($build in @(@{name='YimeBroker.exe';package='./cmd/yimebroker'},@{name='YimeCoreTrialRuntime.exe';package='./cmd/yimecore-trial-runtime'},@{name='YimeCoreSettingsTool.exe';package='./cmd/settings-tool'})) {
            $stage='build-'+$build.name
            Invoke-AdmissionLogged $go @('build','-o',(Join-Path $out ('bin/'+$build.name)),$build.package) (Join-Path $out ('logs/build-'+$build.name+'.log'))
            $tools+=Get-SpeechRecord $out ('bin/'+$build.name)
        }
    } finally { Pop-Location }
    $complete=$true
} catch { $failure=[ordered]@{stage=$stage;code='source_validation_failed';detail='See fixed synthetic logs; no installed repair attempted.'} }
finally {
    foreach ($name in $environment.Keys) { try { Set-SpeechEnvironmentValue $name $original[$name] } catch { $restoreFailures+=$name } }
    foreach ($check in @('sources','legacy','inputs','baseline')) {
        try {
            switch ($check) {
                'sources' { $v=@(Get-ProductSourceRecords $repo); Write-SpeechJson $v (Join-Path $out 'source-hashes-after.json'); if (-not $sourcesBefore.Count) { throw 'Missing source baseline.' }; Assert-SpeechSameRecords $sourcesBefore $v; $sourceOK=$true }
                'legacy' { $v=@(Get-AdmissionLegacyRecords); Write-SpeechJson $v (Join-Path $out 'legacy-static-after.json'); if ($legacyBefore.Count -ne 7) { throw 'Missing historical baseline.' }; Assert-SpeechSameRecords $legacyBefore $v; $legacyOK=$true }
                'inputs' { $v=@(Get-SpeechLockedInputs $repo); Write-SpeechJson $v (Join-Path $out 'locked-inputs-after.json'); if (-not $inputsBefore.Count) { throw 'Missing locked input baseline.' }; Assert-SpeechSameRecords $inputsBefore $v; $inputsOK=$true }
                'baseline' { $v=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json; Write-SpeechJson $v (Join-Path $out 'installed-after.json'); Assert-SpeechBaseline $v $install $ExpectedManifestSha256; if ($null -eq $before) { throw 'Missing installed baseline.' }; Assert-SpeechBaselineUnchanged $before $v; $baselineOK=$true }
            }
        } catch { if ($null -eq $failure) { $failure=[ordered]@{stage='after-'+$check;code='protection_verification_failed'} } }
    }
    Write-SpeechJson $before (Join-Path $out 'installed-before.json')
    Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
    Write-SpeechJson $legacyBefore (Join-Path $out 'legacy-static-before.json')
    Write-SpeechJson $inputsBefore (Join-Path $out 'locked-inputs-before.json')
    $passed=$complete -and $baselineOK -and $sourceOK -and $legacyOK -and $inputsOK -and $depsOK -and $restoreFailures.Count -eq 0
    $sourceDigest=(Get-FileHash -LiteralPath (Join-Path $out 'source-hashes-after.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-SpeechJson ([ordered]@{schema_version='yimecore-speech-product-source-v1';phase='SR4-B1';generated_at=(Get-Date).ToString('o');passed=$passed;failure=$failure;
        source_inventory_sha256=$sourceDigest;source_set_unchanged=$sourceOK;locked_inputs_unchanged=$inputsOK;legacy_static_unchanged=$legacyOK;installed_baseline_unchanged=$baselineOK;
        install_root=$install;installed_manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();directed_tests=$tests;tools=$tools;dependency_boundary_passed=$depsOK;
        environment_restored=($restoreFailures.Count -eq 0);environment_restore_failures=$restoreFailures;installable=$false;default_enabled=$false;
        level='Source contracts, synthetic state and hidden native settings controls; normal binaries built but not installed.';
        real_rime_executed=$false;registered_hosts_executed=$false;frozen_targets_executed=$false;user_text_read=$false;live_learning_data_read=$false;default_input_method_changed=$false;
        new_package_built=$false;new_package_installed=$false;windows_reboot_tested=$false;local_product_ready=$false;public_release_ready=$false}) (Join-Path $out 'summary.json')
}
if (-not $passed) { throw "SR4-B1 source validation did not pass. Evidence: $out" }
Write-Output "PASS: SR4-B1 source/fixture gates only; no install or live-host gate inferred. Evidence: $out"
