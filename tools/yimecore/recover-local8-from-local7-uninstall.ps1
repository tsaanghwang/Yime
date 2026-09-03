[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$candidate='C:\dev\Yime\.tmp\yimecore-local-product\local8-build-20260903-1705\package'
$expectedManifest='0354fd33fcae9171004ecd7c9a33f2e56bcf27c2cc99e58fbf857bc67e8e1fc2'
$expectedManager='70d6c04c85d35d018c69510b7158198f13d08efb1d12dffb707972d3e762d4df'
$failedEvidence='C:\Users\tsaan\YimeCore Recovery Archives\local7-uninstall-reinstall-20260903-165714-7550706e'
$failedManifest='0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$tip="0804:$clsid$profile"
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'

$manifestPath=Join-Path $candidate 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'Pinned local.8 recovery candidate is missing or changed.'}
$candidateManifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $candidate "maintenance\$name"
    $record=@($candidateManifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Unverified local.8 helper: $name"}
    . $path
}
$validated=Assert-LocalProductPackage $candidate
$manager=Join-Path $candidate 'maintenance\Manage-YimeCoreTrial.ps1'
if((Get-FileHash -LiteralPath $manager).Hash -ine $expectedManager){throw 'Pinned local.8 maintenance manager changed.'}
$managerText=Get-Content -LiteralPath $manager -Raw -Encoding UTF8
if(-not $managerText.Contains('Remove-TargetUserTipState') -or
    -not $managerText.Contains('Test-RestorablePreviousUserTipSnapshot $previousRoot $previousUserTipSnapshot')){
    throw 'Pinned local.8 candidate lacks the reviewed uninstall and fresh-install TIP fixes.'
}
$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Pinned read-only registry validator changed.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue')){
    $fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(-not $fn){throw "Missing read-only registry helper: $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Write-Evidence($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Get-ChildNames($Node){
    if($null -eq $Node -or $null -eq $Node.children){return @()}
    if($Node.children -is [Collections.IDictionary]){return @($Node.children.Keys|ForEach-Object{[string]$_})}
    return @($Node.children.PSObject.Properties|ForEach-Object{$_.Name})
}
function Get-ChildNode($Node,[string]$Name){
    if($null -eq $Node -or $null -eq $Node.children){return $null}
    if($Node.children -is [Collections.IDictionary]){return $Node.children[$Name]}
    $property=$Node.children.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}
function Test-TipSnapshotSemanticallyAbsent($Snapshot,[string]$Clsid){
    if($null -eq $Snapshot -or -not $Snapshot.exists){return $true}
    $language=Get-ChildNode (Get-ChildNode $Snapshot 'LanguageProfile') '0x00000804'
    if(@(Get-ChildNames $language).Count -ne 0){return $false}
    $category=Get-ChildNode $Snapshot 'Category'
    $categories=Get-ChildNode $category 'Category'
    foreach($categoryName in @(Get-ChildNames $categories)){
        if(@(Get-ChildNames (Get-ChildNode $categories $categoryName)) -contains $Clsid){return $false}
    }
    $item=Get-ChildNode (Get-ChildNode $category 'Item') $Clsid
    if(@(Get-ChildNames $item).Count -ne 0){return $false}
    return $true
}
function Read-ActiveUserTip {
    Read-YimeCoreSystemKey ([uint32]2147483651) "$expectedSid\Software\Microsoft\CTF\TIP\$clsid"
}
function Get-EnableRecord($Snapshot){
    $leaf=Get-ChildNode (Get-ChildNode (Get-ChildNode $Snapshot 'LanguageProfile') '0x00000804') $profile
    if($null -eq $leaf -or -not $leaf.exists){return $null}
    $values=@($leaf.values|Where-Object{$_.name -ceq 'Enable'})
    if($values.Count -ne 1){return $null}
    return $values[0]
}
function Assert-Enable($Snapshot,[int]$Expected){
    $value=Get-EnableRecord $Snapshot
    if($null -eq $value -or [int]$value.kind -ne 4 -or [int]$value.value -ne $Expected){throw "Active per-user TIP is not DWORD Enable=$Expected."}
}
function Assert-ProductRegistry($Snapshot,[string]$Root,[string]$DisplayName){
    if(-not $Snapshot.native_tip.exists){throw 'Active native TIP is missing.'}
    if(-not $Snapshot.mirrored_tip.exists -or -not (Same $Snapshot.mirrored_tip $Snapshot.native_tip)){throw 'Required native/WOW TSF profile mirror differs.'}
    $node=$Snapshot.native_tip.children.LanguageProfile.children.'0x00000804'.children.$profile
    if(-not $node -or -not $node.exists){throw 'Local product language profile is missing.'}
    Require-CutoverValue $node.values 'Description' 1 $DisplayName
    Require-CutoverValue $node.values 'IconFile' 1 (Join-Path $Root 'profile-icon.ico')
    Require-CutoverValue $Snapshot.native_com.values '' 1 (Join-Path $Root 'x64\YimeTextServiceExperiment.dll')
    Require-CutoverValue $Snapshot.trial_run 'YimeCoreExperimentalTrial' 1 ('"'+(Join-Path $Root 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')
    Require-CutoverValue $Snapshot.uninstall.values 'InstallLocation' 1 $Root
    Require-CutoverValue $Snapshot.uninstall.values 'DisplayName' 1 $DisplayName
}
function Assert-FrozenPayloads($Plan){
    $roots=@($Plan.frozen_registration_references|ForEach-Object{[IO.Path]::GetFullPath([string]$_.install_root)}|Sort-Object -Unique)
    foreach($root in $roots){
        Assert-YimeCorePlainPath $root
        $frozenManifest=Get-Content -LiteralPath (Join-Path $root 'package-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
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

$failedSummary=Get-Content -LiteralPath (Join-Path $failedEvidence 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($failedSummary.passed -or -not $failedSummary.uninstalled -or $failedSummary.reinstalled -or
    [string]$failedSummary.stage -cne 'uninstall-preserve-data' -or
    [string]$failedSummary.candidate_manifest_sha256 -cne $failedManifest){throw 'The pinned local.7 failed-uninstall evidence no longer matches the reviewed state.'}
$backup=[string]$failedSummary.fresh_backup
$archivedPackage=Join-Path $backup 'previous-package'
$reinstallPackage=Join-Path $backup 'reinstall-package'
foreach($root in @($archivedPackage,$reinstallPackage)){
    if((Get-FileHash -LiteralPath (Join-Path $root 'package-manifest.json')).Hash -ine $failedManifest){throw 'Pinned local.7 recovery media changed.'}
}
$backupManifestPath=Join-Path $backup 'backup-manifest.json'
$backupManifest=Get-Content -LiteralPath $backupManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $backupManifest.passed -or -not $backupManifest.native_context_verified){throw 'Pinned pre-uninstall backup is not valid native recovery media.'}
$planText=(& (Join-Path $candidate 'Maintain-YimeCore-Local.cmd') -Action Plan) -join "`n"
if($LASTEXITCODE -ne 0){throw "local.8 Plan failed: $planText"}
$plan=$planText|ConvertFrom-Json
if([string]$plan.install_root -cne 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-efb172e72ec7-0354fd33'){throw 'Unexpected local.8 recovery target root.'}
if(-not $Execute){
    [ordered]@{action='recover-local8-from-pinned-local7-uninstall';failed_evidence=$failedEvidence;candidate_manifest_sha256=$expectedManifest;
        expected_stale_enable=0;expected_installed_enable=1;user_data_preserved=$true;production_components_changed=$false;
        default_input_method_changed=$false;reboot_requested=$false;plan=$plan;writes_requested=$false}|ConvertTo-Json -Depth 10
    exit 0
}

Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -cne $expectedSid){throw 'Use the Windows account that owns the failed local.7 acceptance.'}
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word before local.8 recovery.'}
if(Test-Path -LiteralPath ([string]$plan.install_root)){throw 'Planned local.8 recovery target is occupied.'}
$output=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local8-recovery-from-local7-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $output|Out-Null
$passed=$false;$installed=$false;$failure=$null;$newRoot=$null;$frozenRoots=@();$stage='verify-failed-uninstall'
$backupManifestHash=(Get-FileHash -LiteralPath $backupManifestPath).Hash.ToLowerInvariant()
Start-Transcript -LiteralPath (Join-Path $output 'transcript.txt')|Out-Null
try{
    $beforeData=Get-Content -LiteralPath (Join-Path $failedEvidence 'data-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $originalSystem=Get-Content -LiteralPath (Join-Path $failedEvidence 'system-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $expectedStaleTip=Get-Content -LiteralPath (Join-Path $failedEvidence 'active-user-tip-uninstalled.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $expectedEnabledTip=Get-Content -LiteralPath (Join-Path $failedEvidence 'active-user-tip-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-Enable $expectedStaleTip 0
    Assert-Enable $expectedEnabledTip 1
    $currentSystem=Get-CutoverRegistrySnapshot
    $currentTip=Read-ActiveUserTip
    Assert-Enable $currentTip 0
    if(-not (Same $currentTip $expectedStaleTip)){throw 'Current stale user TIP differs from the reviewed failed-uninstall evidence.'}
    if(-not (Same $currentSystem.protected $originalSystem.protected)){throw 'Protected registry changed after the failed local.7 uninstall.'}
    if($currentSystem.native_com.exists -or -not (Test-TipSnapshotSemanticallyAbsent $currentSystem.native_tip $clsid) -or
        -not (Test-TipSnapshotSemanticallyAbsent $currentSystem.mirrored_tip $clsid) -or @($currentSystem.trial_run).Count -ne 0 -or $currentSystem.uninstall.exists){throw 'Current machine state is not the reviewed uninstalled local product state.'}
    foreach($relative in @('runtime-config.json','runtime-status.json')){if(Test-Path -LiteralPath (Join-Path $state $relative)){throw "Failed uninstall state unexpectedly has $relative."}}
    $unexpectedRuntime=@(Get-CimInstance Win32_Process|Where-Object{
        $_.Name -in @('YimeCoreTrialRuntime.exe','YimeBroker.exe') -and $_.ExecutablePath
    })
    if($unexpectedRuntime.Count){
        throw ('Close leftover YimeCore runtime processes before recovery: '+
            (($unexpectedRuntime|ForEach-Object{"$($_.ProcessId)=$($_.ExecutablePath)"}) -join '; '))
    }
    $language=Get-WinUserLanguageList|Where-Object{$_.LanguageTag -eq 'zh-Hans-CN'}|Select-Object -First 1
    if($null -eq $language -or @($language.InputMethodTips) -contains $tip){throw 'Failed uninstall language list is not clean.'}
    Assert-YimeCoreUnchangedData $beforeData @(Get-YimeCoreDataRecords $state)
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords $archivedPackage $backupManifest.package_files
    & (Join-Path $candidate 'bin\YimeCoreIndependenceAudit.exe') -package $candidate -output (Join-Path $output 'candidate-audit-before.json')
    if($LASTEXITCODE -ne 0){throw 'Pinned local.8 candidate audit failed.'}
    Write-Evidence $currentSystem (Join-Path $output 'system-before.json')
    Write-Evidence $currentTip (Join-Path $output 'active-user-tip-before.json')
    Write-Evidence ([ordered]@{failed_evidence=$failedEvidence;candidate_manifest_sha256=$expectedManifest;candidate_plan=$plan}) (Join-Path $output 'preflight.json')

    $stage='install-local8'
    & (Join-Path $candidate 'Install-YimeCore-Local.cmd')
    $installExit=$LASTEXITCODE
    @('command=Install',"exit_code=$installExit")|Set-Content -LiteralPath (Join-Path $output 'install-output.txt') -Encoding ASCII
    if($installExit -ne 0){throw "Local.8 recovery install failed with exit $installExit; its transaction owns rollback."}
    $installed=$true
    $stage='verify-local8'
    $config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $newRoot=[IO.Path]::GetFullPath([string]$config.install_root).TrimEnd('\')
    if($newRoot -cne [string]$plan.install_root -or (Get-FileHash -LiteralPath (Join-Path $newRoot 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Installed local.8 identity mismatch.'}
    $context=Assert-LocalProductInstalledContext $newRoot $state
    $live=Assert-LocalProductLiveRuntime $context
    & (Join-Path $newRoot 'Maintain-YimeCore-Local.cmd') -Action Verify
    $verifyExit=$LASTEXITCODE
    @('command=Verify',"exit_code=$verifyExit")|Set-Content -LiteralPath (Join-Path $output 'verify-output.txt') -Encoding ASCII
    if($verifyExit -ne 0){throw "Installed local.8 three-mode verification failed with exit $verifyExit."}
    $afterSystem=Get-CutoverRegistrySnapshot
    $afterTip=Read-ActiveUserTip
    Assert-Enable $afterTip 1
    if(-not (Same $afterTip $expectedEnabledTip)){throw 'Fresh local.8 install did not restore the exact enabled user TIP state.'}
    if(-not (Same $afterSystem.protected $originalSystem.protected)){throw 'Protected registry changed during local.8 recovery.'}
    if(-not (Same $afterSystem.language_profile $originalSystem.language_profile)){throw 'Windows user language profile did not return to the pre-uninstall state.'}
    Assert-ProductRegistry $afterSystem $newRoot ([string]$validated.descriptor.display_name)
    $language=Get-WinUserLanguageList|Where-Object{$_.LanguageTag -eq 'zh-Hans-CN'}|Select-Object -First 1
    if($null -eq $language -or @($language.InputMethodTips) -notcontains $tip){throw 'Fresh local.8 install did not restore the TIP to zh-Hans-CN.'}
    Assert-YimeCoreUnchangedData $beforeData @(Get-YimeCoreDataRecords $state)
    $frozenRoots=@(Assert-FrozenPayloads $plan)
    if((Get-FileHash -LiteralPath $backupManifestPath).Hash -ine $backupManifestHash){throw 'Pinned recovery manifest changed during local.8 install.'}
    Assert-YimeCoreArchiveRecords (Join-Path $backup 'state') $backupManifest.state_files
    Assert-YimeCoreArchiveRecords $archivedPackage $backupManifest.package_files
    & (Join-Path $newRoot 'bin\YimeCoreIndependenceAudit.exe') -package $newRoot -output (Join-Path $output 'installed-audit-after.json')
    if($LASTEXITCODE -ne 0){throw 'Installed local.8 package audit failed.'}
    Write-Evidence $afterSystem (Join-Path $output 'system-after.json')
    Write-Evidence $afterTip (Join-Path $output 'active-user-tip-after.json')
    Write-Evidence $live (Join-Path $output 'live-after.json')
    $passed=$true;$stage='local8-recovery-accepted'
}catch{
    $failure=[ordered]@{stage=$stage;message=$_.Exception.Message;type=$_.Exception.GetType().FullName;stack=$_.ScriptStackTrace}
    Write-Evidence $failure (Join-Path $output 'failure.json')
}finally{
    try{
        Write-Evidence ([ordered]@{schema_version='yimecore-local8-recovery-from-local7-v1';passed=$passed;stage=$stage;failure=$failure;
            source_failed_evidence=$failedEvidence;candidate_manifest_sha256=$expectedManifest;installed=$installed;install_root=$newRoot;
            user_data_preserved=$passed;protected_registry_preserved=$passed;active_user_tip_enable_before=0;active_user_tip_enable_after=if($passed){1}else{$null};
            taskbar_visibility_user_confirmation_required=$passed;frozen_payload_roots_verified=$frozenRoots;reboot_requested=$false;
            local_product_ready=$false;public_release_ready=$false}) (Join-Path $output 'summary.json')
    }finally{Stop-Transcript|Out-Null}
}
if(-not $passed){Write-Host "BLOCKED: $stage; $($failure.message) Evidence: $output";exit 1}
Write-Host "PASS: local.8 recovered from the pinned local.7 uninstall, with data preserved and active user TIP DWORD Enable=1. Evidence: $output"
Write-Host 'Do not reboot yet; confirm that the taskbar lists the local product input method.'
