[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$null=Get-YimeCoreDevelopmentScope
Add-Type -Path (Join-Path $PSScriptRoot 'local-runtime-launcher.cs')
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Name}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$session=(Get-Process -Id $PID).SessionId
$facts=[YimeCore.LocalMaintenance.TokenEvidence]::new()
$facts.Sid=$sid;$facts.Session=$session;$facts.Integrity=8192;$facts.TokenType=1
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($facts,$sid,$session)) 'medium primary token accepted'
foreach($tokenType in @(0,2,3)) {
    $facts.TokenType=$tokenType
    Check (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($facts,$sid,$session)) "token type $tokenType cannot authorize a process launch"
}
$facts.TokenType=2
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardToken($facts,$sid,$session) -and
    -not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($facts,$sid,$session)) 'real 1346 failure shape: matching identity still does not authorize launch'
$actual=[YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess($PID)
Check ($actual.TokenType -eq 1 -and $actual.Sid -ceq $sid) 'actual current process has a primary token'
foreach($reference in @('42:12345','1:134000000000000001')) {
    $parsedId=0;[long]$parsedTime=0
    Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::TryParseInitiatorReference($reference,[ref]$parsedId,[ref]$parsedTime)) "valid explicit process reference $reference"
}
foreach($reference in @('','0:1','1:0','-1:1','1:-1','+1:1',' 1:1','1:1 ','1:1:1','2147483648:1','1:9223372036854775808','abc:1','1:abc')) {
    $parsedId=0;[long]$parsedTime=0
    Check (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::TryParseInitiatorReference($reference,[ref]$parsedId,[ref]$parsedTime)) "reject invalid process reference [$reference]"
}
$oldReference=$env:YIMECORE_MAINTENANCE_INITIATOR
try {
    $script:seenRoot=0
    function Assert-YimeCoreUnpackagedDataMaintenance {param([int]$RootProcessId=$PID) $script:seenRoot=$RootProcessId;if($RootProcessId -eq 99){throw 'fixture packaged ancestor'}}
    $env:YIMECORE_MAINTENANCE_INITIATOR='42:12345'
    Assert-YimeCoreMaintenanceInitiator
    Check ($script:seenRoot -eq 42) 'ancestry check targets explicitly retained initiating process'
    $env:YIMECORE_MAINTENANCE_INITIATOR='99:12345'
    Reject {Assert-YimeCoreMaintenanceInitiator} 'packaged initiating ancestry rejected even if current worker is native'
    $env:YIMECORE_MAINTENANCE_INITIATOR='bad-reference'
    Reject {Assert-YimeCoreMaintenanceInitiator} 'malformed reference rejected before ancestry lookup'
} finally {$env:YIMECORE_MAINTENANCE_INITIATOR=$oldReference}
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-runtime-launcher.cs') -Raw -Encoding UTF8
Check ($source -notmatch 'Information\(current.Token,\s*19\)') 'linked identification token is never queried for launch authority'
Check ($source.Contains('created != expectedCreated') -and $source.Contains('WaitForSingleObject(process,0) != 258')) 'retained process identity includes creation time and liveness'
Check ($source.Contains('GetPackageFullName(process,ref packageLength,IntPtr.Zero) != 15700') -and $source.Contains('String.Equals(image.ToString(),expected')) 'native process image and package identity are checked'
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::PrimaryLaunchAccess -eq 0x018b) 'launch handle includes adjust-default and adjust-session rights without all-access'
foreach($access in @(0x000b,0x008b,0x010b)) {
    Check (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::HasRequiredPrimaryLaunchAccess($access)) "reject incomplete launch handle rights 0x$($access.ToString('x4'))"
}
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::HasRequiredPrimaryLaunchAccess(0x018b)) 'complete bounded primary launch handle rights accepted'
Check ($source.Contains('DuplicateTokenEx(initiator, PrimaryLaunchAccess') -and -not $source.Contains('0x02000000') -and -not $source.Contains('AdjustTokenPrivileges(')) 'only copied-token handle rights change; no maximum-access or privilege enablement'
Check ($source.Contains('RequireStandard(primary,targetSid,session);')) 'duplicated primary token is independently validated'
Check ($source.IndexOf('attempt.ChildToken=InspectProcessHandle(created.process)') -lt $source.IndexOf('ResumeThread(created.thread)') -and
    $source.Contains('IsExpectedStandardPrimaryToken(attempt.ChildToken, targetSid, session)')) 'actual child token verified while suspended before user code'
Check ($source.Contains('attempt.TokenAccess=PrimaryLaunchAccess;') -and $source.Contains('attempt.DuplicatedToken=Inspect(primary);')) 'failure evidence records access mask and actual duplicated token'
Check ($source.Contains('TerminateProcess(created.process, 1)') -and $source.Contains('if (initiator != IntPtr.Zero) CloseHandle(initiator)')) 'failed owned launch and source token are cleaned up'
$manager=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') -Raw -Encoding UTF8
Check ($manager.Contains("@('-StandardUserInitiator',(Quote-Argument `$reference))") -and $manager.Contains('$process.WaitForExit()')) 'UAC explicitly forwards initiator and retains its lifetime'
$runtime=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product-runtime.ps1') -Raw -Encoding UTF8
Check ($runtime.Contains('Assert-YimeCoreMaintenanceInitiator')) 'package backup and restore launcher also checks initiating ancestry'
$probe=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-native-standard-user-launch.ps1') -Raw -Encoding UTF8
Check ($probe.IndexOf('Assert-YimeCoreUnpackagedDataMaintenance') -lt $probe.IndexOf('Start-Process')) 'native launch probe cannot elevate out of a packaged app'
Check ($probe.Contains('if($administrator){throw') -and $probe.Contains('-Verb RunAs -WindowStyle Hidden')) 'probe begins ordinary and requests only its own hidden UAC worker'
Check ($probe.Contains('ExpectedSourcesHash -cne $sourceHash') -and $probe.Contains('manifestHash')) 'source snapshot and frozen audit payload are pinned'
Check ($probe.IndexOf("`$parentStage='ordinary-audit-baseline'") -lt $probe.IndexOf('$worker=Start-Process') -and $probe.Contains("'ordinary-baseline.json'")) 'same-image ordinary execution is checked and recorded before UAC'
Check ($probe.Contains("stage=`$parentStage;exception_chain=") -and $probe.Contains('launch_attempt=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt')) 'both ordinary and elevated failures retain distinct launch evidence'
Check ($probe.Contains('::LastLaunchAttempt.ChildToken') -and -not $probe.Contains('::InspectProcess($probe.Id)')) 'short-lived child evidence comes from the retained handle before resume, not PID reopening'
Reject {[YimeCore.LocalMaintenance.StandardUserLauncher]::Start('relative.exe','','relative',$sid)} 'invalid launch target fails before process creation'
Check ([YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt.Stage -ceq 'validate-caller') 'fresh failure snapshot does not reuse an earlier successful attempt'
Check ($probe -notmatch '\b(Stop-Process|Restart-Computer|Set-ItemProperty|Remove-ItemProperty|Manage-YimeCoreTrial|Install-YimeCore-Local\.cmd)\b') 'probe does not stop runtime install change registration or reboot'
$clickEntry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Test-YimeCore-Standard-Launch.cmd') -Raw -Encoding UTF8
Check ($clickEntry.Contains('-File "%~dp0tools\yimecore\test-native-standard-user-launch.ps1"')) 'double-click entry targets only the native read-only launch probe'
Check ($clickEntry.Contains('setlocal') -and $clickEntry.Contains('set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"')) 'double-click entry isolates native module lookup to its own process'
Check ($clickEntry -notmatch '(?i)(__COMPAT_LAYER|schtasks|runas\.exe|-Verb\s+RunAs|-Execute|%\*)') 'entry cannot auto-elevate bypass guards or forward hidden worker arguments'
Check ($clickEntry.Contains('set "YIME_STANDARD_PROBE_EXIT=%ERRORLEVEL%"') -and $clickEntry.Contains('exit /b %YIME_STANDARD_PROBE_EXIT%')) 'entry preserves probe exit status across its visible pause'
foreach($path in @('test-native-standard-user-launch.ps1','manage-e6c-trial-install.ps1','local-product-runtime.ps1','development-scope.ps1')) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $path),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "parse $path"
}
$out=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-local-product\standard-primary-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();actual_current_token=$actual;
    actual_elevated_launch_tested=$false;actual_install_executed=$false}|
    ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) standard-primary launch contracts. Evidence: $out"
