[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $rejected $Name}
foreach($name in @('Require-CutoverValue','Assert-CutoverRegistry','Assert-AcceptanceOriginRecord')) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$root='C:\Program Files\YimeCore Experimental Trial\fixture'
$state='C:\Users\fixture\AppData\Local\YimeCore Experimental Trial'
$sid='S-1-5-21-111-222-333-1001'
$display='local-product-fixture'
$uninstall='"'+(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'maintenance\Manage-YimeCoreTrial.ps1')+'" -Action Uninstall -StateRoot "'+$state+'" -TargetUserSid "'+$sid+'" -NativeX64Only'
$languageBefore=@{exists=$true;values=@();children=@{'zh-Hans-CN'=@{exists=$true;values=@(@{name='old-tip';kind=4;value=1});children=@{}}}}
$languageAfter=$languageBefore|ConvertTo-Json -Depth 8|ConvertFrom-Json
$languageAfter.children.'zh-Hans-CN'.values+=@{name='0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}';kind=4;value=4}
$before=[ordered]@{protected=[ordered]@{production='unchanged';frozen='unchanged';user_tip='unchanged';default_override='original'};language_profile=$languageBefore;mirrored_tip=@{exists=$false}}
$good=[ordered]@{protected=$before.protected;
    language_profile=$languageAfter;
    native_com=@{values=@(@{name='';kind=1;value=(Join-Path $root 'x64\YimeTextServiceExperiment.dll')})};
    native_tip=@{exists=$true;children=@{LanguageProfile=@{children=@{'0x00000804'=@{children=@{
        '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'=@{exists=$true;values=@(
            @{name='Description';kind=1;value=$display},@{name='IconFile';kind=1;value=(Join-Path $root 'profile-icon.ico')})}
    }}}}}};
    trial_run=@(@{name='YimeCoreExperimentalTrial';kind=1;value=('"'+(Join-Path $root 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')});
    uninstall=@{values=@(@{name='InstallLocation';kind=1;value=$root},@{name='DisplayName';kind=1;value=$display},@{name='UninstallString';kind=1;value=$uninstall})}}
$good.mirrored_tip=$good.native_tip
Assert-CutoverRegistry $before $good $root $display $sid $state
Check $true 'expected independent registry values accepted'
foreach($case in @('production','frozen','user_tip','default_override','missing_language_tip','extra_language_change','missing_mirror','changed_mirror','com_path','missing_tip','profile_name','profile_icon','run_path','run_kind','missing_run','duplicate_run','uninstall_sid','uninstall_state','uninstall_mode','install_location','display_name')) {
    $bad=$good|ConvertTo-Json -Depth 10|ConvertFrom-Json
    switch($case) {
        'production' {$bad.protected.production='changed'}
        'frozen' {$bad.protected.frozen='changed'}
        'user_tip' {$bad.protected.user_tip='changed'}
        'default_override' {$bad.protected.default_override='changed'}
        'missing_language_tip' {$bad.language_profile.children.'zh-Hans-CN'.values=@($bad.language_profile.children.'zh-Hans-CN'.values|Where-Object{$_.name -eq 'old-tip'})}
        'extra_language_change' {$bad.language_profile.children.'zh-Hans-CN'.values[0].value=2}
        'missing_mirror' {$bad.mirrored_tip.exists=$false}
        'changed_mirror' {$bad.mirrored_tip.children.LanguageProfile.children.'0x00000804'.children.'{126F54C6-E9B1-4E22-8652-03224CBD49F9}'.values[0].value='wrong'}
        'com_path' {$bad.native_com.values[0].value='C:\wrong.dll'}
        'missing_tip' {$bad.native_tip.exists=$false}
        'profile_name' {$bad.native_tip.children.LanguageProfile.children.'0x00000804'.children.'{126F54C6-E9B1-4E22-8652-03224CBD49F9}'.values[0].value='wrong'}
        'profile_icon' {$bad.native_tip.children.LanguageProfile.children.'0x00000804'.children.'{126F54C6-E9B1-4E22-8652-03224CBD49F9}'.values[1].value='C:\wrong.ico'}
        'run_path' {$bad.trial_run[0].value='wrong'}
        'run_kind' {$bad.trial_run[0].kind=2}
        'missing_run' {$bad.trial_run=@()}
        'duplicate_run' {$bad.trial_run=@($bad.trial_run[0],$bad.trial_run[0])}
        'uninstall_sid' {$bad.uninstall.values[2].value=$uninstall.Replace($sid,'wrong')}
        'uninstall_state' {$bad.uninstall.values[2].value=$uninstall.Replace($state,'C:\wrong')}
        'uninstall_mode' {$bad.uninstall.values[2].value=$uninstall.Replace(' -NativeX64Only','')}
        'install_location' {$bad.uninstall.values[0].value='C:\wrong'}
        'display_name' {$bad.uninstall.values[1].value='wrong'}
    }
    Reject {Assert-CutoverRegistry $before $bad $root $display $sid $state} "reject $case"
}
$text=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
Check ($text.IndexOf('Assert-YimeCoreUnpackagedDataMaintenance') -lt $text.IndexOf('New-Item -ItemType Directory -Path $archive')) 'context guard precedes archive writes and transactions'
Check ($text.IndexOf('if(-not $Execute -and -not $LaunchProbeOnly)') -lt $text.IndexOf('$config=Get-Content')) 'default mode avoids live AppData access'
Check ($text.Contains("ParameterSetName='Install'") -and $text.Contains("ParameterSetName='Probe'")) 'install and probe switches are mutually exclusive'
Check ($text.Contains('$expectedLauncher=') -and $text.Contains('.Hash -ine $expectedLauncher')) 'candidate must contain the natively proven launcher'
Check ($text.IndexOf('if($LaunchProbeOnly){') -lt $text.IndexOf("`$stage='fresh-backup'") -and
    $text.Substring($text.IndexOf('if($LaunchProbeOnly){'),$text.IndexOf("`$stage='fresh-backup'")-$text.IndexOf('if($LaunchProbeOnly){')).Contains('return')) 'probe exits before backup or stop even when launch succeeds'
Check ($text.Contains('install_acceptance_passed=($passed -and -not $LaunchProbeOnly)')) 'successful diagnostic never claims installation acceptance'
Check ($text.Contains('exception_chain=$chain;native_error_code=') -and $text.Contains('Get-YimeCoreExceptionEvidence $_.Exception')) 'nested native failures are recorded with Windows error code'
Check ($text.IndexOf("`$stage='fresh-backup'") -lt $text.IndexOf("`$stage='install'")) 'fresh backup precedes installer'
Check ($text.Contains("-BackupRoot `$backup -InstalledPackageRoot `$previous")) 'upgrade backup validates and stops the configured installed package rather than the candidate'
Check ($text.IndexOf("`$stage='standard-user-launch-preflight'") -lt $text.IndexOf("`$stage='fresh-backup'") -and
    $text.Contains('$probe=[YimeCore.LocalMaintenance.StandardUserLauncher]::Start(')) 'actual medium-token probe precedes stopping the old runtime'
Check ($text.IndexOf('Assert-YimeCoreArchiveRecords (Join-Path $backup') -lt $text.IndexOf("`$stage='install'")) 'both archive payloads verified before install'
Check ($text.Contains('foreach($frozenRoot in $frozenRoots)') -and $text.Contains('Frozen payload mismatch:') -and $text.Contains("@('package-manifest.json','install-metadata.json')")) 'actual frozen-reference packages are checked byte-for-byte after install'
Check ($text.Contains('Assert-LocalProductLiveRuntime $context')) 'new live identities and standard tokens are mandatory'
Check ($text.Contains("Join-Path `$previous 'bin\YimeCoreIndependenceAudit.exe'") -and
    -not $text.Contains("Join-Path `$package 'bin\YimeCoreIndependenceAudit.exe') -package `$previous")) `
    'pinned previous package is checked by its compatible manifest-covered auditor'
Check ($text.Contains("`$trial='{E40FA752-BB96-461D-A51D-F40EB437EC65}'") -and
    $text.Contains("`$legacyTrial='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'")) `
    'acceptance separates active local identity from frozen legacy identity'
Check ($text.Contains('actual_failed_upgrade_rollback_tested=$false') -and $text.Contains('live_host_acceptance=$false')) 'install acceptance does not claim rollback or host acceptance'
$fixtureHash='a'*64;$fixtureManifest='b'*64
$origin=[ordered]@{initiator='42:12345';sid=$sid;source_set_sha256=$fixtureHash;candidate_manifest_sha256=$fixtureManifest}
Assert-AcceptanceOriginRecord $origin '42:12345' $fixtureHash $sid $fixtureManifest
Check $true 'matching retained origin and payload accepted'
foreach($field in @('initiator','sid','source_set_sha256','candidate_manifest_sha256')) {
    $badOrigin=$origin|ConvertTo-Json|ConvertFrom-Json
    $badOrigin.$field='changed'
    Reject {Assert-AcceptanceOriginRecord $badOrigin '42:12345' $fixtureHash $sid $fixtureManifest} "worker rejects altered $field"
}
Reject {Assert-AcceptanceOriginRecord $origin '0:12345' $fixtureHash $sid $fixtureManifest} 'worker rejects malformed reference'
Reject {Assert-AcceptanceOriginRecord $origin '42:12345' '' $sid $fixtureManifest} 'worker rejects missing source digest'
Check ($text.Contains('if(-not $StandardUserInitiator -and $administrator)') -and $text.Contains('Use normal double-click from File Explorer')) 'direct elevated entry is refused before mutation'
Check ($text.Contains("[Parameter(ParameterSetName='Probe')][string]`$StandardUserInitiator")) 'worker token reference cannot be bound to Execute'
Check ($text.Contains('$worker.WaitForExit()') -and $text.Contains('-Verb RunAs -WindowStyle Hidden')) 'native parent remains alive across its own hidden UAC probe'
$workerStart=$text.IndexOf('if($StandardUserInitiator) {')
$workerEnd=$text.IndexOf('if($EvidenceRoot -or $ExpectedSourcesHash)')
$workerText=$text.Substring($workerStart,$workerEnd-$workerStart)
Check ($workerText.Contains('exit 0') -and $workerText.Contains('if(-not $LaunchProbeOnly -or -not $administrator)') -and
    $workerText -notmatch 'backup-local-trial-state|Install-YimeCore-Local.cmd|Stop-Process') 'elevated worker exits without stop backup or install'
Check ($text.Contains('[int]$liveBefore.status.runtime_pid') -and $text.Contains('[int]$liveBefore.status.broker_pid') -and
    $text.Contains('Previous runtime must already be ordinary same-user')) 'legacy baseline process IDs use actual live evidence status and require ordinary tokens'
Check ($text.Contains('Assert-YimeCoreMaintenanceInitiator') -and $text.Contains('Assert-AcceptanceWorkerOrigin $EvidenceRoot')) 'worker requires native initiator ancestry and a fresh pinned archive'
Check ($text.Contains('::LastLaunchAttempt') -and $text.Contains('IsExpectedStandardPrimaryToken($attempt.ChildToken') -and
    -not $text.Contains('::InspectProcess($probe.Id)')) 'short-lived audit token is captured before resume without a PID reopen race'
Check ($text.Contains("`$errorPath=Join-Path `$state 'maintenance-last-error.txt'") -and $text.Contains('installer-maintenance-last-error.txt')) 'hidden installer failure details use the real transaction error file'
$entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Install-YimeCore-Local-Dev.cmd') -Raw -Encoding UTF8
Check ($entry.Contains('-File "%~dp0tools\yimecore\invoke-local-product-native-install.ps1" -Execute') -and $entry -notmatch '%\*|-Verb\s+RunAs|runas\.exe|__COMPAT_LAYER|schtasks') 'one-click acceptance has a fixed target and no elevation bypass or arbitrary argument forwarding'
Check ($entry.Contains('set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"') -and
    $entry.Contains('set "YIME_LOCAL_INSTALL_EXIT=%ERRORLEVEL%"') -and $entry.Contains('exit /b %YIME_LOCAL_INSTALL_EXIT%')) 'one-click acceptance keeps native module lookup and exit code'
$out=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-local-product\native-install-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();actual_install_executed=$false;actual_registry_writes=$false}|ConvertTo-Json -Depth 6|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) native install acceptance contracts. Evidence: $out"
