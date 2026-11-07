# Actual Setup startup function against a StdRegProv mock; never execute Setup.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax error'}
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Clear-Owned18uLegacyStartup'},$true)
. ([scriptblock]::Create($node.Extent.Text))
$sid='S-1-5-21-fixture';$runKey='Software\Microsoft\Windows\CurrentVersion\Run';$runName='YimeSimple-yimecore-18u'
$expected='"C:\synthetic\bin\Yime18uInstalledRuntime.exe" --installed-18u-run --install-root "C:\synthetic" --manifest-sha256 '+('a'*64)
$script:removed=0;$script:reads=0;$script:enumerations=0;$script:calls=@()
$script:listed=@{ReturnValue=0;sNames=@($runName)};$script:reply=@{ReturnValue=0;sValue=$expected}
function Invoke-CimMethod($Namespace,$ClassName,$MethodName,$Arguments){
    if($Namespace -cne 'root/default' -or $ClassName -cne 'StdRegProv' -or
       $Arguments.hDefKey -ne [uint32]2147483651 -or $Arguments.sSubKeyName -cne ($sid+'\'+$runKey)){throw 'Wrong startup query boundary'}
    $script:calls+=@($MethodName)
    if($MethodName -ceq 'EnumValues'){
        if($Arguments.ContainsKey('sValueName')){throw 'Enumeration must address the Run key'}
        $script:enumerations++;return [pscustomobject]$script:listed
    }
    if($MethodName -cne 'GetStringValue' -or $Arguments.sValueName -cne $runName){throw 'Wrong startup value query'}
    $script:reads++;return [pscustomobject]$script:reply
}
function Set-UserStartup([string]$Value){if($Value){throw 'Unexpected startup write'};$script:calls+=@('Remove');$script:removed++}
Clear-Owned18uLegacyStartup $expected -CheckOnly
if($script:removed -ne 0 -or $script:enumerations -ne 1 -or $script:reads -ne 1 -or ($script:calls -join ',') -cne 'EnumValues,GetStringValue'){throw 'Preflight changed startup or did not establish presence first'}
$script:calls=@()
Clear-Owned18uLegacyStartup $expected
if($script:removed -ne 1 -or $script:enumerations -ne 2 -or $script:reads -ne 2 -or ($script:calls -join ',') -cne 'EnumValues,GetStringValue,Remove'){throw 'Exact old startup not removed after presence and ownership checks'}
foreach($checkOnly in @($true,$false)){
    foreach($case in @('foreign-path','other-hash','enum-failure-1','enum-failure-5','read-failure-1','read-failure-2','read-failure-5','absent-value-code1','absent-empty-key','absent-run-key')){
        $script:removed=0;$script:reads=0;$script:enumerations=0;$script:calls=@()
        $script:listed=@{ReturnValue=0;sNames=@($runName)};$script:reply=@{ReturnValue=0;sValue=$expected}
        $wantFailure=$true;$wantReads=1
        switch($case){
            'foreign-path' {$script:reply.sValue=$expected.Replace('C:\synthetic','C:\foreign')}
            'other-hash' {$script:reply.sValue=$expected.Replace(('a'*64),('b'*64))}
            'enum-failure-1' {$script:listed.ReturnValue=1;$wantReads=0}
            'enum-failure-5' {$script:listed.ReturnValue=5;$wantReads=0}
            'read-failure-1' {$script:reply=@{ReturnValue=1}}
            'read-failure-2' {$script:reply=@{ReturnValue=2}}
            'read-failure-5' {$script:reply=@{ReturnValue=5}}
            # ASUS reported code 1 for an absent value. It must never be read
            # after EnumValues has proved only other products' names exist.
            'absent-value-code1' {$script:listed.sNames=@('YimeSimple-yimecore','YimeSimple-rime-pime');$script:reply=@{ReturnValue=1};$wantFailure=$false;$wantReads=0}
            'absent-empty-key' {$script:listed.sNames=$null;$script:reply=@{ReturnValue=2};$wantFailure=$false;$wantReads=0}
            'absent-run-key' {$script:listed=@{ReturnValue=2};$wantFailure=$false;$wantReads=0}
        }
        $failed=$false;try{Clear-Owned18uLegacyStartup $expected -CheckOnly:$checkOnly}catch{$failed=$true}
        if($script:removed -ne 0 -or $script:enumerations -ne 1 -or $script:reads -ne $wantReads -or $failed -ne $wantFailure){throw ('Wrong startup refusal: '+$case+'; CheckOnly='+$checkOnly)}
    }
}
$script:calls=@();Clear-Owned18uLegacyStartup '';if($script:calls.Count){throw 'Empty legacy ownership must not query startup'}
Write-Output 'PASS legacy startup: presence before exact initiating-user command removal, preflight read-only, absent value/key no-op without a read, foreign path/hash and enumeration/read error refusal; registry mocked'
