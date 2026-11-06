# Execute Setup's actual registration orchestration against a stateful native mock.
# No installed files, registry, TSF API, or Setup entry point are touched.
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
$contract=[pscustomobject]@{nativeDirectory='x64'}
$root='C:\synthetic-18u'
$script:dll='C:\synthetic-18u\x64\YimeTextService18u.dll'
$script:tool='C:\synthetic-package\x64\Yime18uProductRegistration.exe'
function New-OldState {
    $script:state=@{com=$true;tip=$true;profile=1;categories=5;oldFiles='old-payload';userData='user-lexicon';evidence='original-failure-logs';newFiles=$false}
    $script:calls=[Collections.Generic.List[string]]::new()
    $script:processes=[Collections.Generic.List[int]]::new()
    $script:fail=''
}
function Assert-State([bool]$com,[bool]$tip,[int]$profile,[int]$categories,[string]$label) {
    if($script:state.com -ne $com -or $script:state.tip -ne $tip -or
       $script:state.profile -ne $profile -or $script:state.categories -ne $categories){throw ('Wrong state: '+$label)}
    if($script:state.oldFiles -cne 'old-payload' -or $script:state.userData -cne 'user-lexicon' -or
       $script:state.evidence -cne 'original-failure-logs' -or $script:state.newFiles){throw ('Protected data changed: '+$label)}
}
function Run-Native([string]$Path,[string[]]$Arguments){
    if($Path -cne $script:tool){throw 'Wrong registration tool'}
    $action=$Arguments[0]
    if($action -ne 'verify-absent' -and ($Arguments.Count -ne 2 -or $Arguments[1] -cne $script:dll)){throw 'Wrong DLL binding'}
    if($action -eq 'verify-absent' -and $Arguments.Count -ne 1){throw 'Wrong absence arguments'}
    $script:calls.Add($action)
    # Every Run-Native invocation stands for one new process. Only a later process
    # sees the post-removal TSF state when the first process has a stale snapshot.
    $script:processes.Add($script:processes.Count+1)
    if($script:fail -eq $action -or ($script:fail -eq 'stale-final-api' -and $action -eq 'unregister')){throw 'synthetic-native-failure'}
    switch($action){
        'unregister-tip' {
            if(-not $script:state.com){throw 'COM deleted before TIP removal'}
            $script:state.tip=$false;$script:state.profile=0;$script:state.categories=0
        }
        'unregister' {
            if($script:state.tip -or $script:state.profile -or $script:state.categories){throw 'COM removal attempted with TIP present'}
            if($script:processes.Count -lt 2){throw 'Final API absence was not checked in a fresh process'}
            $script:state.com=$false
        }
        'verify-absent' {
            if($script:state.com -or $script:state.tip -or $script:state.profile -or $script:state.categories){throw 'Final absence failed'}
        }
        'register' {
            if($script:state.com -or $script:state.tip){throw 'Installation started before complete removal'}
            $script:state.com=$true;$script:state.tip=$true;$script:state.profile=1;$script:state.categories=5
        }
        default {throw 'Unexpected native action'}
    }
}
# Local names deliberately shadow the fixture values, as Set-Registration's do.
# Each negative case must fail on its own path check before changing mock state.
function Invoke-WrongToolPath {
    $tool='C:\synthetic-wrong-package\x64\Yime18uProductRegistration.exe'
    Run-Native $tool @('unregister-tip',$script:dll)
}
function Invoke-WrongDllPath {
    $dll='C:\synthetic-wrong-18u\x64\YimeTextService18u.dll'
    Run-Native $script:tool @('unregister-tip',$dll)
}
foreach($case in @('tool','dll')){
    New-OldState
    $expected=if($case -eq 'tool'){'Wrong registration tool'}else{'Wrong DLL binding'}
    $rejected=$false
    try{
        if($case -eq 'tool'){Invoke-WrongToolPath}else{Invoke-WrongDllPath}
    }catch{
        if($_.Exception.Message -cne $expected){throw}
        $rejected=$true
    }
    if(-not $rejected -or $script:calls.Count -ne 0 -or $script:processes.Count -ne 0){throw ('Wrong path accepted: '+$case)}
    Assert-State $true $true 1 5 ('wrong-'+$case)
}
foreach($case in @('success','unregister-tip','unregister','stale-final-api','verify-absent')){
    New-OldState
    if($case -ne 'success'){$script:fail=$case}
    $failed=$false
    try{Set-Registration $false 'C:\synthetic-package'}catch{
        if($_.Exception.Message -ne 'synthetic-native-failure'){throw}
        $failed=$true
    }
    $expected=@('unregister-tip','unregister','verify-absent')
    if($case -eq 'unregister-tip'){$expected=$expected[0..0]}
    if($case -in @('unregister','stale-final-api')){$expected=$expected[0..1]}
    if(($script:calls -join ',') -cne ($expected -join ',') -or $failed -ne ($case -ne 'success')){throw ('Wrong stop/phase order: '+$case)}
    if($case -eq 'unregister-tip'){Assert-State $true $true 1 5 $case}
    elseif($case -in @('unregister','stale-final-api')){Assert-State $true $false 0 0 $case}
    else{Assert-State $false $false 0 0 $case}
    if($script:processes.Count -ne $script:calls.Count){throw ('Native process reused: '+$case)}
}
# Complete old-state removal must allow a new registration only after absence.
New-OldState
Set-Registration $false 'C:\synthetic-package'
Set-Registration $true 'C:\synthetic-package'
if(($script:calls -join ',') -cne 'unregister-tip,unregister,verify-absent,register'){throw 'Full upgrade registration order changed'}
Assert-State $true $true 1 5 'successful-registration'
# Incoming install failure cannot erase the old evidence or user data.
New-OldState
Set-Registration $false 'C:\synthetic-package'
$script:fail='register';$failed=$false
try{Set-Registration $true 'C:\synthetic-package'}catch{
    if($_.Exception.Message -ne 'synthetic-native-failure'){throw}
    $failed=$true
}
if(-not $failed -or ($script:calls -join ',') -cne 'unregister-tip,unregister,verify-absent,register'){throw 'Install failure was not propagated after old removal'}
Assert-State $false $false 0 0 'register-failure'
foreach($arch in @('x64','arm64')){
    $contract.nativeDirectory=$arch
    $script:dll='C:\synthetic-18u\'+$arch+'\YimeTextService18u.dll'
    $script:tool='C:\synthetic-package\'+$arch+'\Yime18uProductRegistration.exe'
    New-OldState
    Set-Registration $false 'C:\synthetic-package'
    Set-Registration $true 'C:\synthetic-package'
    if(($script:calls -join ',') -cne 'unregister-tip,unregister,verify-absent,register'){throw ('Architecture upgrade order changed: '+$arch)}
    Assert-State $true $true 1 5 $arch
}
Write-Output 'PASS 18u full-old-state mock: wrong tool/DLL paths rejected, three fresh removal phases, failures stop, COM last, install failure preserves evidence/user data; native operations simulated'
