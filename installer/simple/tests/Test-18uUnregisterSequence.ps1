# Execute the actual Setup registration function with native calls mocked.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup syntax error'}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-Registration'},$true)
if(-not $function){throw 'Registration function missing'}
. ([scriptblock]::Create($function.Extent.Text))
$product=[pscustomobject]@{id='yimecore-18u';dll='YimeTextService18u.dll'}
$root='C:\synthetic-18u'
function Run-Native([string]$Path,[string[]]$Arguments){
    if($Path -cne ('C:\synthetic-package\'+$contract.nativeDirectory+'\Yime18uProductRegistration.exe')){throw 'Wrong registration tool'}
    $script:calls.Add(($Arguments -join '|'))
    if($Arguments[0] -eq $script:fail){throw 'synthetic-native-failure'}
}
foreach($arch in @('x64','arm64')){
$contract=[pscustomobject]@{nativeDirectory=$arch}
foreach($failAt in @('','unregister-tip','unregister','verify-absent')){
    $script:fail=$failAt;$script:calls=[Collections.Generic.List[string]]::new();$failed=$false
    try{Set-Registration $false 'C:\synthetic-package'}catch{
        if($_.Exception.Message -ne 'synthetic-native-failure'){throw}
        $failed=$true
    }
    $dll='C:\synthetic-18u\'+$arch+'\YimeTextService18u.dll'
    $expected=@(('unregister-tip|'+$dll),('unregister|'+$dll),'verify-absent')
    if($failAt -eq 'unregister-tip'){$expected=$expected[0..0]}
    if($failAt -eq 'unregister'){$expected=$expected[0..1]}
    if(($script:calls -join ',') -cne ($expected -join ',') -or $failed -ne [bool]$failAt){throw 'Wrong phase order or failure propagation'}
}
$script:fail='';$script:calls=[Collections.Generic.List[string]]::new()
Set-Registration $true 'C:\synthetic-package'
if(($script:calls -join ',') -cne ('register|C:\synthetic-18u\'+$arch+'\YimeTextService18u.dll')){throw 'Install path changed'}
}
Write-Output 'PASS 18u unregister: separate TIP and final COM processes; all phase failures stop; install unchanged; native operations mocked'
