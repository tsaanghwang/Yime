$ErrorActionPreference='Stop'
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-manage-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$log=Join-Path $work 'calls.txt'
$runner=Join-Path $PSScriptRoot 'Manage-Products.ps1'
foreach($id in @('yimecore','rime-pime')){
    $dir=Join-Path $work $id;$null=[IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'product-package.json'),('{"product":"'+$id+'"}'))
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
Write-Output 'PASS: single/both install/uninstall dispatch, all-package precheck, stop on failure. Synthetic packages only.'
exit 0
