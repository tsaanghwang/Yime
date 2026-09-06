[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AdmissionRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedAdmissionSummarySha256,
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256
)
# SR4-A: build and relocate a NON-INSTALLABLE, default-off speech bundle.
# Execute only newly built, hash-bound tools and their private stdio children.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5') {
    throw 'Speech package execution requires PowerShell 7.5+.'
}

function Import-PackageFunctions([string]$Path, [string[]]$Names) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $tokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count) { throw 'Package helper parsing failed.' }
    foreach ($name in $Names) {
        $matches=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -CEQ $name)
        if ($matches.Count -ne 1) { throw 'Package helper allowlist is incomplete or ambiguous.' }
        # Return definitions to be dot-sourced in the caller's script scope.
        [scriptblock]::Create($matches[0].Extent.Text)
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) { throw 'Package helper changed while loading.' }
}
$sr0Names=@('Assert-SpeechPlainPath','Resolve-SpeechChild','Write-SpeechJson','Set-SpeechEnvironmentValue',
    'Get-SpeechRecord','Assert-SpeechSameRecords','Assert-SpeechBaseline','Get-SpeechBaselineIdentity',
    'Assert-SpeechBaselineUnchanged','Get-SpeechDefinitions','Get-SpeechLockedInputs')
foreach ($definition in @(Import-PackageFunctions (Join-Path $PSScriptRoot 'run-connected-speech-reconnect.ps1') $sr0Names)) { . $definition }
$admissionNames=@('Get-AdmissionSourceRecords','Get-AdmissionLegacyRecords','Invoke-AdmissionLogged','Assert-AdmissionProcessOutcome')
foreach ($definition in @(Import-PackageFunctions (Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1') $admissionNames)) { . $definition }
. (Join-Path $PSScriptRoot 'development-scope.ps1')

function Resolve-PackageAdmission([string]$Repo, [string]$Requested) {
    if (-not [IO.Path]::IsPathRooted($Requested) -or $Requested -match '(^|[\\/])\.\.?([\\/]|$)|[. ]([\\/]|$)') { throw 'Explicit canonical admission root required.' }
    $path=[IO.Path]::GetFullPath($Requested).TrimEnd('\')
    if ((Split-Path -Parent $path) -ine (Join-Path $Repo '.tmp\yimecore-experiment') -or
        (Split-Path -Leaf $path) -cnotmatch '^speech-admission-[0-9]{8}-[0-9]{6}-[a-f0-9]{32}$') { throw 'Use a fixed completed current-source admission run, not an installed or arbitrary directory.' }
    Assert-SpeechPlainPath $path
    return $path
}

function Assert-PackageAdmission($Report, [string]$Root, [string]$Install, [string]$Hash) {
    if ($Report.schema_version -cne 'yimecore-speech-admission-isolated-v1' -or $Report.passed -ne $true -or
        $Report.trial_root -ine $Root -or $Report.install_root -ine $Install -or $Report.installed_manifest_sha256 -ine $Hash -or
        $Report.module -cne 'third-tone-stage5c' -or $Report.reviewed_records -ne 24 -or $Report.mode_alias_rows -ne 72) { throw 'Admission result is not the pinned complete Stage5C run.' }
    foreach ($field in @('forward_source_passed','admission_prepare_passed','owned_process_acceptance_passed','dependency_boundary_passed',
        'python_contracts_passed','installed_baseline_unchanged','locked_inputs_unchanged','source_set_unchanged','legacy_static_unchanged','environment_restored')) {
        if ($Report.$field -ne $true) { throw 'Admission gate missing.' }
    }
    foreach ($field in @('real_rime_executed','registered_hosts_executed','frozen_targets_executed','default_input_method_changed',
        'new_package_installed','daily_broker_connected','user_text_read','live_learning_data_read','live_config_read','product_or_registry_mutated')) {
        if ($Report.$field -ne $false) { throw 'Admission exceeded the isolated scope.' }
    }
    $jobs=@($Report.directed_tests | Where-Object { $_.package -ceq './cmd/yimecore-speech-admission' })
    if ($jobs.Count -ne 1 -or $jobs[0].selector -cne '^TestSpeech(Exercise|Package)' -or $jobs[0].passed -ne $true -or $jobs[0].passed_count -le 0 -or $jobs[0].failed_count -ne 0) {
        throw 'Fresh package contract tests are required; old exercise-only evidence is insufficient.'
    }
}

$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$admission=Resolve-PackageAdmission $repo $AdmissionRoot
$install=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$scope=Get-YimeCoreDevelopmentScope
if ($scope.computer_name -cne 'MYCOMPUTER') { throw 'This package experiment is scoped to MYCOMPUTER.' }
$summaryPath=Resolve-SpeechChild $admission 'summary.json'
if ((Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash -ine $ExpectedAdmissionSummarySha256) { throw 'Admission summary hash mismatch.' }
$admissionSummary=Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
Assert-PackageAdmission $admissionSummary $admission $install $ExpectedManifestSha256
$runID=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')
$out=Join-Path $repo ('.tmp\yimecore-experiment\speech-package-'+$runID)
$package=Join-Path $out ('speech-admission-package-'+$runID)
$profileRoot=[Environment]::GetFolderPath('UserProfile')
if (-not $profileRoot -or -not [IO.Path]::IsPathRooted($profileRoot)) { throw 'The current Windows account profile is required for isolated fixtures.' }
# Do not trust an inherited TEMP that might point into either installed product
# or writable learning directory. This fixed test-only sibling is never recovery media.
$tempBase=Join-Path $profileRoot 'YimeCore Isolated Fixtures\SR4'
if ($tempBase -ieq $repo -or $tempBase.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or
    $tempBase -ieq $install -or $tempBase.StartsWith($install+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'A temporary relocation root outside repository and installation is required.' }
$relocated=Join-Path $tempBase ('speech-admission-package-'+$runID)
$exerciseRoot=Join-Path $tempBase ('speech-admission-exercise-'+$runID)
$externalEnvironmentRoot=Join-Path $tempBase ('speech-admission-environment-'+$runID)
foreach ($path in @($out,$relocated,$exerciseRoot,$externalEnvironmentRoot)) {
    Assert-SpeechPlainPath $path
    if (Test-Path -LiteralPath $path) { throw 'Fresh package and evidence roots required; existing output is preserved.' }
}
New-Item -ItemType Directory -Path $out | Out-Null
$before=$null; $sourcesBefore=@(); $legacyBefore=@(); $inputsBefore=@()
$baselineUnchanged=$false; $sourcesUnchanged=$false; $legacyUnchanged=$false; $inputsUnchanged=$false
$completed=$false; $failure=$null; $stage='baseline'; $packageSHA=$null; $manifest=$null; $processOutcome=$null
$relocationVerified=$false; $sealedUnchanged=$false; $runnerContractsPassed=$false
$baselineScript=Join-Path $PSScriptRoot 'get-l5-daily-use-baseline.ps1'
$environment=[ordered]@{APPDATA=(Join-Path $out 'private\appdata');LOCALAPPDATA=(Join-Path $out 'private\localappdata');
    TEMP=(Join-Path $out 'private\temp');TMP=(Join-Path $out 'private\tmp');
    YIME_RUN_REAL_RIME_TESTS=$null;YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE=$null;YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST=$null;
    YIME_TEXTSERVICE_EXPERIMENT_PIPE=$null;YIMECORE_TEST_PIPE_NAME=$null;YIMECORE_TEST_STATE_ROOT=$null;YIMECORE_TOOL_SMOKE_TEST=$null}
$original=@{}; foreach ($name in $environment.Keys) { $original[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$restoreFailures=@()
try {
    $before=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json
    Assert-SpeechBaseline $before $install $ExpectedManifestSha256
    $sourcesBefore=@(Get-AdmissionSourceRecords $repo)
    $admissionSources=Get-Content -LiteralPath (Join-Path $admission 'source-hashes-after.json') -Raw | ConvertFrom-Json
    Assert-SpeechSameRecords $admissionSources $sourcesBefore
    $legacyBefore=@(Get-AdmissionLegacyRecords); $inputsBefore=@(Get-SpeechLockedInputs $repo)
    $stage='runner-contracts'
    Invoke-AdmissionLogged (Join-Path $PSHOME 'pwsh.exe') @('-NoProfile','-File',(Join-Path $PSScriptRoot 'test-connected-speech-package.ps1')) (Join-Path $out 'runner-contracts.log')
    $runnerContractsPassed=$true
    $tool=Resolve-SpeechChild $admission 'bin/YimeSpeechAdmission.exe'
    $broker=Resolve-SpeechChild $admission 'bin/YimeBroker-speech.exe'
    foreach ($relative in @('bin/YimeSpeechAdmission.exe','bin/YimeBroker-speech.exe')) {
        $pins=@($admissionSummary.tools | Where-Object path -CEQ $relative)
        if ($pins.Count -ne 1) { throw 'Required current build identity missing.' }
        Assert-SpeechSameRecords $pins @(Get-SpeechRecord $admission $relative)
    }
    $brokerSHA=(Get-FileHash -LiteralPath $broker -Algorithm SHA256).Hash.ToLowerInvariant()
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) { New-Item -ItemType Directory -Path $environment[$name] -Force | Out-Null }
    foreach ($name in $environment.Keys) { Set-SpeechEnvironmentValue $name $environment[$name] }
    $stage='package'
    Invoke-AdmissionLogged $tool @('-action','package','-repo',$repo,'-root',$admission,'-output-root',$package,'-broker',$broker,'-broker-sha256',$brokerSHA) (Join-Path $out 'package.log')
    $packageSHA=(Get-FileHash -LiteralPath (Join-Path $package 'package-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $stage='verify-sealed-package'
    Invoke-AdmissionLogged $tool @('-action','verify-package','-root',$package,'-package-sha256',$packageSHA) (Join-Path $out 'verify-original.log')
    $manifest=Get-Content -LiteralPath (Join-Path $package 'package-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.installable -ne $false -or $manifest.default_enabled -ne $false -or $manifest.default_bundle -cne 'bundle-off.json' -or @($manifest.files).Count -ne 69) { throw 'Sealed package scope or closure differs from SR4-A.' }
    $stage='relocate-exact-files'
    New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
    New-Item -ItemType Directory -Path $relocated | Out-Null
    foreach ($relative in @($manifest.files.path)+@('package-manifest.json')) {
        $source=Resolve-SpeechChild $package $relative; $destination=Resolve-SpeechChild $relocated $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    $relocatedTool=Resolve-SpeechChild $relocated 'bin/YimeSpeechAdmission.exe'
    $toolPin=@($manifest.files | Where-Object path -CEQ 'bin/YimeSpeechAdmission.exe')
    if ($toolPin.Count -ne 1 -or (Get-FileHash -LiteralPath $relocatedTool -Algorithm SHA256).Hash -ine $toolPin[0].sha256) { throw 'Relocated tool identity mismatch before execution.' }
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) {
        $privatePath=Join-Path $externalEnvironmentRoot $name.ToLowerInvariant()
        New-Item -ItemType Directory -Path $privatePath -Force | Out-Null
        Set-SpeechEnvironmentValue $name $privatePath
    }
    # No -repo, build tool, installed path or network dependency is passed here.
    Push-Location $relocated
    try {
        $stage='verify-relocated-package'
        Invoke-AdmissionLogged $relocatedTool @('-action','verify-package','-root',$relocated,'-package-sha256',$packageSHA) (Join-Path $out 'verify-relocated.log')
        $relocationVerified=$true; $stage='exercise-relocated-package'
        Invoke-AdmissionLogged $relocatedTool @('-action','exercise-package','-root',$relocated,'-package-sha256',$packageSHA,'-output-root',$exerciseRoot) (Join-Path $out 'exercise-relocated.log')
        $processOutcome=Get-Content -LiteralPath (Join-Path $exerciseRoot 'process-outcome.json') -Raw | ConvertFrom-Json
        Assert-AdmissionProcessOutcome $processOutcome $brokerSHA
        $packageOutcome=Get-Content -LiteralPath (Join-Path $exerciseRoot 'package-exercise-outcome.json') -Raw | ConvertFrom-Json
        if ($packageOutcome.schema_version -cne 'yimecore-speech-package-exercise-v1' -or $packageOutcome.passed -ne $true -or
            $packageOutcome.package_manifest_sha256 -cne $packageSHA -or $packageOutcome.package_unchanged -ne $true -or
            $packageOutcome.payload_files -ne 69 -or $packageOutcome.forward_source_files -ne 56 -or
            $packageOutcome.installable -ne $false -or $packageOutcome.source_repository_required -ne $false -or
            $packageOutcome.rime_executed -ne $false -or $packageOutcome.registered_or_live_host_tested -ne $false) { throw 'Package exercise scope or sealed identity evidence incomplete.' }
        $stage='verify-sealed-after-exercise'
        Invoke-AdmissionLogged $relocatedTool @('-action','verify-package','-root',$relocated,'-package-sha256',$packageSHA) (Join-Path $out 'verify-relocated-after.log')
        Invoke-AdmissionLogged $tool @('-action','verify-package','-root',$package,'-package-sha256',$packageSHA) (Join-Path $out 'verify-original-after.log')
        $sealedUnchanged=$true
    } finally { Pop-Location }
    $completed=$true
} catch { $failure=[ordered]@{stage=$stage;code='isolated_package_stage_failed';detail='Inspect only fixed fixture logs; no installed repair or cleanup attempted.'} }
finally {
    foreach ($name in $environment.Keys) { try { Set-SpeechEnvironmentValue $name $original[$name] } catch { $restoreFailures+=$name } }
    foreach ($check in @('sources','legacy','inputs','baseline')) {
        try {
            switch ($check) {
                'sources' { $value=@(Get-AdmissionSourceRecords $repo); Write-SpeechJson $value (Join-Path $out 'source-hashes-after.json'); if (-not $sourcesBefore.Count) { throw 'Missing initial sources.' }; Assert-SpeechSameRecords $sourcesBefore $value; $sourcesUnchanged=$true }
                'legacy' { $value=@(Get-AdmissionLegacyRecords); Write-SpeechJson $value (Join-Path $out 'legacy-static-after.json'); if ($legacyBefore.Count -ne 7) { throw 'Missing retained payload baseline.' }; Assert-SpeechSameRecords $legacyBefore $value; $legacyUnchanged=$true }
                'inputs' { $value=@(Get-SpeechLockedInputs $repo); Write-SpeechJson $value (Join-Path $out 'locked-inputs-after.json'); if (-not $inputsBefore.Count) { throw 'Missing locked inputs.' }; Assert-SpeechSameRecords $inputsBefore $value; $inputsUnchanged=$true }
                'baseline' { $after=& $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256 | ConvertFrom-Json; Write-SpeechJson $after (Join-Path $out 'installed-after.json'); Assert-SpeechBaseline $after $install $ExpectedManifestSha256; if ($null -eq $before) { throw 'Missing installed baseline.' }; Assert-SpeechBaselineUnchanged $before $after; $baselineUnchanged=$true }
            }
        } catch { if ($null -eq $failure) { $failure=[ordered]@{stage='after-'+$check;code='protection_verification_failed'} } }
    }
    Write-SpeechJson $before (Join-Path $out 'installed-before.json')
    Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
    Write-SpeechJson $legacyBefore (Join-Path $out 'legacy-static-before.json')
    Write-SpeechJson $inputsBefore (Join-Path $out 'locked-inputs-before.json')
    $passed=$completed -and $runnerContractsPassed -and $relocationVerified -and $sealedUnchanged -and $baselineUnchanged -and $sourcesUnchanged -and $legacyUnchanged -and $inputsUnchanged -and $restoreFailures.Count -eq 0
    $summary=[ordered]@{schema_version='yimecore-speech-package-isolated-v1';generated_at=(Get-Date).ToString('o');passed=$passed;failure=$failure;
        phase='SR4-A';package_root=$package;package_manifest_sha256=$packageSHA;relocated_package_root=$relocated;exercise_root=$exerciseRoot;external_environment_root=$externalEnvironmentRoot;
        admission_root=$admission;admission_summary_sha256=$ExpectedAdmissionSummarySha256.ToLowerInvariant();install_root=$install;installed_manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();
        default_enabled=$false;installable=$false;reviewed_records=24;mode_alias_rows=72;runner_contracts_passed=$runnerContractsPassed;relocation_verified=$relocationVerified;sealed_package_unchanged=$sealedUnchanged;
        owned_process_outcome=$processOutcome;source_set_unchanged=$sourcesUnchanged;locked_inputs_unchanged=$inputsUnchanged;legacy_static_unchanged=$legacyUnchanged;installed_baseline_unchanged=$baselineUnchanged;
        environment_restored=($restoreFailures.Count -eq 0);environment_restore_failures=$restoreFailures;
        new_package_installed=$false;real_rime_executed=$false;frozen_targets_executed=$false;registered_hosts_executed=$false;user_text_read=$false;live_learning_data_read=$false;
        default_input_method_changed=$false;local_product_ready=$false;public_release_ready=$false;
        limitations=@('Non-installable SR4-A bundle only: no TSF, installed Runtime/UI, product maintenance transaction or live-host acceptance.',
            'Relocated execution is not a clean-machine Rime-absent or architecture acceptance test.',
            'Temporary relocation and synthetic-state copies are retained as experiment evidence, not durable user recovery media.',
            'The original directed-test SKIP list remains unchanged; no skipped path is inferred passed.')}
    Write-SpeechJson $summary (Join-Path $out 'summary.json')
}
if (-not $passed) { throw "SR4-A isolated package did not pass. Evidence: $out" }
Write-Output "PASS: non-installable SR4-A package and relocated private lifecycle only. Evidence: $out"
