$ErrorActionPreference='Stop'
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-manage-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$log=Join-Path $work 'calls.txt'
$runner=Join-Path $work 'Manage-Products.ps1'
[IO.File]::Copy((Join-Path $PSScriptRoot 'Manage-Products.ps1'),$runner)
$moduleSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Product.psm1') -Raw
function Set-FixtureHost([int]$Machine){
    # Override the OS query only in the temporary copied module. No actual
    # Setup, product binary, registry operation or host-dependent install runs.
    $probe='function Get-NativeHostMachine { [pscustomobject]@{source="IsWow64Process2";nativeMachine='+$Machine+';processMachine=0;is64BitProcess=$true} }; Export-ModuleMember -Function *-*'
    [IO.File]::WriteAllText((Join-Path $work 'Product.psm1'),($moduleSource+"`n"+$probe),[Text.UTF8Encoding]::new($true))
}
Set-FixtureHost 0x8664
foreach($id in @('yimecore','rime-pime')){
    $dir=Join-Path $work $id;$null=[IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'product-package.json'),('{"format":"yime-simple-package-1","product":"'+$id+'"}'))
    $fixture=@'
param([string]$Action,[switch]$ResetData)
$id=Split-Path $PSScriptRoot -Leaf
Add-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'calls.txt') -Value ($id+':'+$Action)
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot ($Action+'.fail'))){exit 7}
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $dir 'Setup.ps1'),$fixture)
}
function Expect([string]$Expected){
    $actual=(Get-Content -LiteralPath $log)-join ','
    if($actual -cne $Expected){throw ('Unexpected orchestration: '+$actual)}
    [IO.File]::WriteAllText($log,'')
}
foreach($action in @('Install','Uninstall')){
    & $runner -Action $action -Product both -PackageDirectory $work
    Expect ('rime-pime:Check,yimecore:Check,rime-pime:'+$action+',yimecore:'+$action)
    foreach($id in @('yimecore','rime-pime')){
        & $runner -Action $action -Product $id -PackageDirectory $work
        Expect ($id+':Check,'+$id+':'+$action)
    }
}
[IO.File]::WriteAllText((Join-Path $work 'yimecore\Check.fail'),'')
$failed=$false
try{& $runner -Action Install -Product both -PackageDirectory $work}catch{$failed=$true}
if(-not $failed){throw 'Bad second package must prevent both installs'}
Expect 'rime-pime:Check,yimecore:Check'
[IO.File]::Delete((Join-Path $work 'yimecore\Check.fail'))
[IO.File]::WriteAllText((Join-Path $work 'rime-pime\Uninstall.fail'),'')
$failed=$false
try{& $runner -Action Uninstall -Product both -PackageDirectory $work}catch{$failed=$true}
if(-not $failed){throw 'First uninstall failure must stop the sequence'}
Expect 'rime-pime:Check,yimecore:Check,rime-pime:Uninstall'
[IO.File]::Delete((Join-Path $work 'rime-pime\Uninstall.fail'))
[IO.File]::WriteAllText((Join-Path $work 'yimecore\product-package.json'),'{"format":"yime-simple-package-2","product":"yimecore","target":"windows-arm64","host_architecture":"arm64","tsf64_architecture":"arm64x"}')
$failed=$false;try{& $runner -Action Install -Product both -PackageDirectory $work}catch{$failed=$true}
if(-not $failed){throw 'ARM64 package accepted on an AMD64 native host'}
Expect ''
Set-FixtureHost 0xaa64
$failed=$false;try{& $runner -Action Install -Product both -PackageDirectory $work}catch{$failed=$true}
if(-not $failed){throw 'Rime/PIME x64 package accepted on an ARM64 native host'}
Expect ''
& $runner -Action Install -Product yimecore -PackageDirectory $work
Expect 'yimecore:Check,yimecore:Install'
Write-Output 'PASS: single/both dispatch, all-package precheck, stop on failure, architecture mismatch before any setup, ARM64 core-only dispatch. Synthetic packages and mocked OS query only.'
exit 0
