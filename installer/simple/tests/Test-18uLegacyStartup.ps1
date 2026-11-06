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
$script:removed=0;$script:reads=0;$script:reply=@{ReturnValue=0;sValue=$expected}
function Invoke-CimMethod($Namespace,$ClassName,$MethodName,$Arguments){
    if($Namespace -cne 'root/default' -or $ClassName -cne 'StdRegProv' -or $MethodName -cne 'GetStringValue' -or
       $Arguments.hDefKey -ne [uint32]2147483651 -or $Arguments.sSubKeyName -cne ($sid+'\'+$runKey) -or $Arguments.sValueName -cne $runName){throw 'Wrong startup query boundary'}
    $script:reads++;return [pscustomobject]$script:reply
}
function Set-UserStartup([string]$Value){if($Value){throw 'Unexpected startup write'};$script:removed++}
Clear-Owned18uLegacyStartup $expected -CheckOnly
if($script:removed -ne 0 -or $script:reads -ne 1){throw 'Preflight changed startup'}
Clear-Owned18uLegacyStartup $expected
if($script:removed -ne 1 -or $script:reads -ne 2){throw 'Exact old startup not removed'}
foreach($case in @('foreign-path','other-hash','provider-failure','missing')){
    $script:removed=0
    $script:reply=@{ReturnValue=0;sValue=$expected}
    switch($case){
        'foreign-path' {$script:reply.sValue=$expected.Replace('C:\synthetic','C:\foreign')}
        'other-hash' {$script:reply.sValue=$expected.Replace(('a'*64),('b'*64))}
        'provider-failure' {$script:reply.ReturnValue=5}
        'missing' {$script:reply.ReturnValue=2;$script:reply.Remove('sValue')}
    }
    $failed=$false;try{Clear-Owned18uLegacyStartup $expected}catch{$failed=$true}
    if($script:removed -ne 0 -or $failed -ne ($case -ne 'missing')){throw ('Wrong startup refusal: '+$case)}
}
Write-Output 'PASS legacy startup: exact initiating-user command removal, preflight read-only, absent value no-op, foreign path/hash and provider error refusal; registry mocked'
