[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$package='C:\dev\Yime\.tmp\yimecore-local-product\local6-tip-preservation-rc1\package'
$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$expectedPreviousManifest='2631aeb3634f6bc103771e12e3a8d6748bd87123f890afb2ae874b1d06706c7a'
$expectedManager='6186fb760686b64411c9f3ad774c0ab814a51bf7b91a1381f7aca9a91398e41a'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$manifestPath=Join-Path $package 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'local.6 candidate manifest changed; refuse upgrade.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $package "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Unverified local.6 helper: $name"}
    . $path
}
$manager=Join-Path $package 'maintenance\Manage-YimeCoreTrial.ps1'
if((Get-FileHash -LiteralPath $manager).Hash -ine $expectedManager){throw 'local.6 does not contain the reviewed TIP-preservation manager.'}
$managerText=Get-Content -LiteralPath $manager -Raw -Encoding UTF8
if(-not $managerText.Contains('Restore-FrozenUserTipSnapshot $migrationLegacyUserTipSnapshot')){throw 'local.6 final frozen-user-TIP restoration is missing.'}
$validated=Assert-LocalProductPackage $package
$null=Get-YimeCoreDevelopmentScope
$planText=(& (Join-Path $package 'Maintain-YimeCore-Local.cmd') -Action Plan) -join "`n"
if($LASTEXITCODE -ne 0){throw "local.6 Plan failed: $planText"}
$plan=$planText|ConvertFrom-Json
if([string]$plan.install_root -cne 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-42e28f7d'){throw 'Unexpected local.6 target root.'}
if(-not $Execute){
    [ordered]@{action='local6-native-upgrade-plan';candidate_manifest_sha256=$expectedManifest;expected_previous_manifest_sha256=$expectedPreviousManifest;
        target_sid=$expectedSid;plan=$plan;writes_requested=$false;repeats_identity_migration=$false;reboot_requested=$false;
        next_action='normal Explorer double-click Upgrade-YimeCore-Local6.cmd'}|ConvertTo-Json -Depth 10
    exit 0
}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the Windows account that owns the current local product.'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
Assert-YimeCorePlainPath $state
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$previous=[IO.Path]::GetFullPath([string]$config.install_root).TrimEnd('\')
Assert-YimeCorePlainPath $previous
if((Get-FileHash -LiteralPath (Join-Path $previous 'package-manifest.json')).Hash -ine $expectedPreviousManifest){throw 'Current install is no longer the repaired local.5 baseline; stop and re-plan.'}
if(Test-Path -LiteralPath ([string]$plan.install_root)){throw 'Planned local.6 target is occupied; preserve it and re-plan.'}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word before the native upgrade.'}
$otherProcesses=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and
    $_.ExecutablePath.StartsWith($previous+'\',[StringComparison]::OrdinalIgnoreCase) -and
    $_.Name -notin @('YimeCoreTrialRuntime.exe','YimeBroker.exe')})
if($otherProcesses.Count){throw 'Close input-method tools from local.5 before the native upgrade.'}
$liveBefore=Get-YimeCoreLiveRuntimeEvidence $state
if(-not $liveBefore.passed){throw 'Current local.5 Runtime/Broker identity is not live and verified.'}

# Reuse only the read-only system-view snapshot helpers from the closed local.5
# migration acceptance. Its install path and mutation flow are never invoked.
$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Read-only registry validator changed; review before upgrading.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue')){
    $fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(-not $fn){throw "Missing read-only registry helper: $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Write-AcceptanceJson($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Get-AcceptanceExceptionEvidence([Exception]$Exception){
    $result=@();$current=$Exception
    while($current){
        $nativeCode=$null
        if($current -is [ComponentModel.Win32Exception]){$nativeCode=$current.NativeErrorCode}
        $result+=[ordered]@{type=$current.GetType().FullName;message=$current.Message;hresult=$current.HResult;native_error_code=$nativeCode}
        $current=$current.InnerException
    }
    return $result
}
function Assert-ProductRegistry($Snapshot,[string]$Root,[string]$DisplayName){
    if(-not $Snapshot.native_tip.exists){throw 'Active native TIP is missing.'}
    if(-not $Snapshot.mirrored_tip.exists -or -not (Same $Snapshot.mirrored_tip $Snapshot.native_tip)){throw 'Required native/WOW TSF profile mirror differs.'}
    $profile=$Snapshot.native_tip.children.LanguageProfile.children.'0x00000804'.children.'{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
    if(-not $profile -or -not $profile.exists){throw 'Local product language profile is missing.'}
    Require-CutoverValue $profile.values 'Description' 1 $DisplayName
    Require-CutoverValue $profile.values 'IconFile' 1 (Join-Path $Root 'profile-icon.ico')
    Require-CutoverValue $Snapshot.native_com.values '' 1 (Join-Path $Root 'x64\YimeTextServiceExperiment.dll')
    Require-CutoverValue $Snapshot.trial_run 'YimeCoreExperimentalTrial' 1 ('"'+(Join-Path $Root 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')
    Require-CutoverValue $Snapshot.uninstall.values 'InstallLocation' 1 $Root
    Require-CutoverValue $Snapshot.uninstall.values 'DisplayName' 1 $DisplayName
}
function Assert-FrozenPayloads($Plan){
    $roots=@($Plan.frozen_registration_references|ForEach-Object{[IO.Path]::GetFullPath([string]$_.install_root)}|Sort-Object -Unique)
    foreach($root in $roots){
        Assert-YimeCorePlainPath $root
        $frozenManifestPath=Join-Path $root 'package-manifest.json'
        $frozenManifest=Get-Content -LiteralPath $frozenManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($record in $frozenManifest.files){
            $payload=[IO.Path]::GetFullPath((Join-Path $root $record.path))
            if(-not $payload.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $payload -PathType Leaf) -or
                (Get-Item -LiteralPath $payload).Length -ne $record.bytes -or (Get-FileHash -LiteralPath $payload).Hash -ine $record.sha256){throw "Frozen payload mismatch: $($record.path)"}
        }
        $expected=@($frozenManifest.files.path)+@('package-manifest.json','install-metadata.json')
        $actual=@(Get-ChildItem -LiteralPath $root -Recurse -File|ForEach-Object{$_.FullName.Substring($root.Length+1).Replace('\','/')})
        if(Compare-Object $expected $actual){throw "Frozen payload inventory changed: $root"}
    }
    return $roots
}

$archive=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local6-native-upgrade-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-YimeCorePlainPath $archive
New-Item -ItemType Directory -Path $archive|Out-Null
$backup=Join-Path $archive 'preinstall-backup'
$sourceHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
Write-AcceptanceJson ([ordered]@{sid=$expectedSid;acceptance_script_sha256=$sourceHash;registry_validator_sha256=$expectedValidator;candidate_manifest_sha256=$expectedManifest;
    previous_manifest_sha256=$expectedPreviousManifest;plan=$plan}) (Join-Path $archive 'preflight.json')
$stage='capture-before';$passed=$false;$upgradeSucceeded=$false;$failure=$null;$frozenRoots=@()
Start-Transcript -LiteralPath (Join-Path $archive 'transcript.txt')|Out-Null
try{
    $before=Get-CutoverRegistrySnapshot
    Assert-ProductRegistry $before $previous ([string]$validated.descriptor.display_name)
    Write-AcceptanceJson $before (Join-Path $archive 'system-before.json')
    & (Join-Path $previous 'bin\YimeCoreIndependenceAudit.exe') -package $previous -output (Join-Path $archive 'previous-package-audit.json')
    if($LASTEXITCODE -ne 0){throw 'Current local.5 package integrity audit failed.'}
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $archive 'candidate-package-audit.json')
    if($LASTEXITCODE -ne 0){throw 'local.6 candidate integrity audit failed.'}
    $stage='fresh-backup'
    & (Join-Path $package 'maintenance\backup-local-trial-state.ps1') -BackupRoot $backup -InstalledPackageRoot $previous
    $saved=Get-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $saved.passed -or -not $saved.native_context_verified -or $saved.source_install_root -ine $previous){throw 'Fresh pre-upgrade backup identity mismatch.'}
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $saved.state_files
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'previous-package') $saved.package_files
    Assert-YimeCoreUnchangedData $saved.data_files @(Get-YimeCoreDataRecords $state)
    $stage='upgrade'
    & (Join-Path $package 'Maintain-YimeCore-Local.cmd') -Action Upgrade
    if($LASTEXITCODE -ne 0){throw "local.6 package upgrade failed with exit code $LASTEXITCODE; its transaction owns rollback."}
    $upgradeSucceeded=$true
    $stage='verify-installed'
    $context=Assert-LocalProductInstalledContext ([string]$plan.install_root) $state
    if($context.package.manifest_sha256 -ine $expectedManifest){throw 'Installed package is not the reviewed local.6 candidate.'}
    $liveAfter=Assert-LocalProductLiveRuntime $context
    Write-AcceptanceJson $liveAfter (Join-Path $archive 'live-runtime-after.json')
    & (Join-Path $context.package.root 'Maintain-YimeCore-Local.cmd') -Action Verify
    if($LASTEXITCODE -ne 0){throw 'Installed local.6 three-mode verification failed.'}
    $stage='compare-data-and-system-registry'
    $after=Get-CutoverRegistrySnapshot
    Write-AcceptanceJson $after (Join-Path $archive 'system-after.json')
    if(-not (Same $before.protected $after.protected)){throw 'Protected production, frozen, default-input, or unrelated Run registry changed.'}
    if(-not (Same $before.language_profile $after.language_profile)){throw 'Windows user language profile changed during same-identity upgrade.'}
    Assert-ProductRegistry $after $context.package.root ([string]$validated.descriptor.display_name)
    Assert-YimeCoreUnchangedData $saved.data_files @(Get-YimeCoreDataRecords $state)
    $frozenRoots=@(Assert-FrozenPayloads $plan)
    $passed=$true;$stage='local6-native-upgrade-accepted'
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace;
        exception_chain=@(Get-AcceptanceExceptionEvidence $_.Exception)}
    Write-AcceptanceJson $failure (Join-Path $archive 'failure.json')
}finally{
    try{
        Write-AcceptanceJson ([ordered]@{schema_version='yimecore-local6-native-upgrade-v1';passed=$passed;stage=$stage;failure=$failure;
            upgrade_command_succeeded=$upgradeSucceeded;candidate_manifest_sha256=$expectedManifest;previous_manifest_sha256=$expectedPreviousManifest;
            source_install_root=$previous;planned_install_root=$plan.install_root;backup_root=$backup;frozen_payload_roots_verified=$frozenRoots;
            user_data_preserved=$passed;protected_registry_preserved=$passed;ordinary_runtime_verified=$passed;reboot_requested=$false;
            live_host_acceptance=$false;local_product_ready=$false;public_release_ready=$false}) (Join-Path $archive 'summary.json')
    }finally{Stop-Transcript|Out-Null}
}
if(-not $passed){Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $archive";exit 1}
Write-Host "PASS: local.6 native upgrade, ordinary runtime, data and protected registration verified. Evidence: $archive"
Write-Host 'Do not reboot yet; return the PASS line for the next acceptance step.'
