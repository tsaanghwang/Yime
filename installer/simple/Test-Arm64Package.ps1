$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-arm64-package-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$script:checks=0
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Work,[string]$Message){
    $failure='';try{& $Work | Out-Null}catch{$failure=$_.Exception.Message}
    Require ([bool]$failure) ('Expected rejection: '+$Message)
}
function Write-Pe([string]$Path,[int]$Machine=0xaa64,[switch]$Arm64X){
    # Byte fixtures are never executable code and are never launched or loaded.
    [byte[]]$bytes=New-Object byte[] 4096
    function U16([int]$Offset,[uint16]$Value){[BitConverter]::GetBytes($Value).CopyTo($bytes,$Offset)}
    function U32([int]$Offset,[uint32]$Value){[BitConverter]::GetBytes($Value).CopyTo($bytes,$Offset)}
    function U64([int]$Offset,[uint64]$Value){[BitConverter]::GetBytes($Value).CopyTo($bytes,$Offset)}
    U16 0 0x5a4d;U32 0x3c 0x80;U32 0x80 0x4550;U16 0x84 $Machine;U16 0x86 1
    $wide=$Machine -ne 0x14c;$optional=0x98;$optionalSize=if($wide){240}else{224}
    U16 0x94 $optionalSize;U16 0x96 $(if($Path.EndsWith('.dll')){0x2002}else{2})
    U16 $optional $(if($wide){0x20b}else{0x10b});U32 ($optional+60) 0x400
    if($wide){U64 ($optional+24) 0x180000000;U32 ($optional+108) 16}else{U32 ($optional+28) 0x400000;U32 ($optional+92) 16}
    $section=$optional+$optionalSize
    U32 ($section+8) 0xc00;U32 ($section+12) 0x1000;U32 ($section+16) 0xc00;U32 ($section+20) 0x400
    if($Arm64X){
        U32 ($optional+192) 0x1100;U32 ($optional+196) 232;U32 0x500 232
        U64 (0x500+200) 0x180001300;U32 (0x500+224) 0x500;U16 (0x500+228) 1
        U32 0x700 1;U32 0x900 1;U32 0x904 24;U64 0x908 6;U32 0x910 12
        U32 0x914 0x1000;U32 0x918 12;U16 0x91c 1;U16 0x91e 1
    }
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllBytes($Path,$bytes)
}
function Save-Manifest([string]$Root,$Manifest){
    [IO.File]::WriteAllText((Join-Path $Root 'product-package.json'),($Manifest|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
function Refresh-Member([string]$Root,[string]$Member){
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'product-package.json') -Raw|ConvertFrom-Json
    $row=@($manifest.files|Where-Object {$_.path -ceq $Member})[0]
    $path=Join-Path $Root ('payload/'+$Member)
    $row.bytes=(Get-Item -LiteralPath $path).Length;$row.sha256=Get-ContentHash $path
    Save-Manifest $Root $manifest
}
function New-Fixture {
    $root=Join-Path $work ([guid]::NewGuid().ToString('N'))
    $info=Get-Product 'yimecore'
    $go=@('YimeCoreTrialRuntime.exe','YimeBroker.exe','YimeCoreInputToolbar.exe','YimeCoreTrainer.exe','YimeCoreToolCenter.exe')
    $assets=@('profile-icon.ico','indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx','data/yime_pinyin_codes.tsv','data/fonts/YinYuan-Regular.ttf')
    $native=@('YimeTextServiceExperiment.dll','YimeTextServiceRegistration.exe','YimeRegisteredHostTests.exe')
    $names=@('local-product.json','package-manifest.json','build/source-manifest.json','speech-capability.json',
        'speech/product.json','speech/admission.json','speech/forward-source.json','speech/admitted-records.json')+$assets
    foreach($mode in @('full','variable','shorthand')){foreach($stage in @('core','stage5c')){$names+=('speech/indexes/'+$mode+'-'+$stage+'.yidx')}}
    foreach($name in $go){$names+=('bin/'+$name)}
    foreach($arch in @('arm64','x86')){foreach($name in $native){$names+=($arch+'/'+$name)}}
    $descriptor=@{package_contract='yimecore-arm64-product-package-v1';identity=@{clsid=$info.clsid;profile=$info.profile};
        scope=@{target='windows-arm64';tsf64_architecture='arm64x';active_architectures=@('arm64','x86')};
        go_binaries=@($go|ForEach-Object {@{path=('bin/'+$_)}});assets=@($assets|ForEach-Object {@{path=$_}});native_binaries=$native}
    $files=@(foreach($name in $names){
        $path=Join-Path $root ('payload/'+$name)
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        if($name -match '\.(exe|dll)$'){
            $machine=if($name.StartsWith('x86/')){0x14c}else{0xaa64}
            Write-Pe $path $machine -Arm64X:($name -ceq 'arm64/YimeTextServiceExperiment.dll')
        }elseif($name -ceq 'local-product.json'){
            [IO.File]::WriteAllText($path,($descriptor|ConvertTo-Json -Depth 8))
        }else{[IO.File]::WriteAllText($path,'isolated fixture only: '+$name)}
        @{path=$name;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-ContentHash $path)}
    })
    $manifest=@{format='yime-simple-package-2';product='yimecore';version='fixture';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64x';files=$files}
    Save-Manifest $root $manifest
    return $root
}
$valid=New-Fixture;$package=Read-Package $valid
Require ($package.contract.nativeDirectory -ceq 'arm64') 'ARM64 package did not select its native registration tool'
$legacy=Get-PackageContract ([pscustomobject]@{format='yime-simple-package-1';product='yimecore'})
Require ($legacy.target -ceq 'windows-amd64') 'Legacy x64 contract changed'
foreach($mutation in @('wrong-target','wrong-host','wrong-tsf','rime','legacy-arm')){
    $manifest=Get-Content -LiteralPath (Join-Path $valid 'product-package.json') -Raw|ConvertFrom-Json
    switch($mutation){'wrong-target'{$manifest.target='windows-amd64'}'wrong-host'{$manifest.host_architecture='amd64'}'wrong-tsf'{$manifest.tsf64_architecture='arm64'}'rime'{$manifest.product='rime-pime'}'legacy-arm'{$manifest.format='yime-simple-package-1'}}
    Reject {Get-PackageContract $manifest} $mutation
}
foreach($case in @('plain-arm64','arm64ec','wrong-runtime','wrong-x86','missing-chpe','missing-fixups','truncated-table')){
    $root=New-Fixture;$member='arm64/YimeTextServiceExperiment.dll';$path=Join-Path $root ('payload/'+$member)
    switch($case){
        'plain-arm64'{Write-Pe $path 0xaa64}
        'arm64ec'{Write-Pe $path 0x8664 -Arm64X}
        'wrong-runtime'{$member='bin/YimeBroker.exe';$path=Join-Path $root ('payload/'+$member);Write-Pe $path 0x8664}
        'wrong-x86'{$member='x86/YimeTextServiceExperiment.dll';$path=Join-Path $root ('payload/'+$member);Write-Pe $path 0xaa64}
        default {
            $bytes=[IO.File]::ReadAllBytes($path)
            if($case -eq 'missing-chpe'){[BitConverter]::GetBytes([uint64]0).CopyTo($bytes,0x500+200)}
            if($case -eq 'missing-fixups'){[BitConverter]::GetBytes([uint64]5).CopyTo($bytes,0x908)}
            if($case -eq 'truncated-table'){[BitConverter]::GetBytes([uint32]::MaxValue).CopyTo($bytes,0x904)}
            [IO.File]::WriteAllBytes($path,$bytes)
        }
    }
    Refresh-Member $root $member
    Reject {Read-Package $root} $case
}
foreach($missing in @('speech/indexes/full-stage5c.yidx','arm64/YimeRegisteredHostTests.exe','data/fonts/YinYuan-Regular.ttf')){
    $root=New-Fixture;$manifest=Get-Content -LiteralPath (Join-Path $root 'product-package.json') -Raw|ConvertFrom-Json
    # Delete only this known test member, with a matching manifest, so integrity
    # alone succeeds and the required-resource contract must reject it.
    [IO.File]::Delete((Join-Path $root ('payload/'+$missing)))
    $manifest.files=@($manifest.files|Where-Object {$_.path -cne $missing});Save-Manifest $root $manifest
    Reject {Read-Package $root} ('missing '+$missing)
}
$output=Join-Path $work 'built'
& (Join-Path $PSScriptRoot 'Build-Package.ps1') -Product yimecore -PayloadRoot (Join-Path $valid 'payload') -OutputRoot $output -Version test -Target windows-arm64
$built=Read-Package $output
Require (Test-Path -LiteralPath (Join-Path $output 'payload/build/source-manifest.json')) 'ARM64 build evidence was dropped'
Require ($built.manifest.format -ceq 'yime-simple-package-2') 'Builder did not emit the ARM64 contract'
Reject {& (Join-Path $PSScriptRoot 'Build-Package.ps1') -Product yimecore -PayloadRoot (Join-Path $valid 'payload') -OutputRoot (Join-Path $work 'wrong-default') -Version test} 'ARM64 relabeled as default x64'
Reject {& (Join-Path $PSScriptRoot 'Build-Package.ps1') -Product rime-pime -PayloadRoot (Join-Path $valid 'payload') -OutputRoot (Join-Path $work 'wrong-rime') -Version test -Target windows-arm64} 'Rime ARM64'
# Exercise the production P/Invoke path before replacing it with fixtures.
# PowerShell type aliases can differ between PS5 and PS7; a mocked OS query
# cannot catch those invocation errors. This API only reads process/OS metadata.
$observedHost=Get-NativeHostMachine
Require ($observedHost.source -ceq 'IsWow64Process2') 'Real host probe did not use IsWow64Process2'
Require ($observedHost.nativeMachine -in @(0xaa64,0x8664)) 'Real host probe did not identify a supported native Windows architecture'
Require ($observedHost.is64BitProcess -eq [Environment]::Is64BitProcess -and $observedHost.processMachine -ge 0 -and $observedHost.processMachine -le 65535) 'Real host probe returned invalid process metadata'
Write-Output ('Read-only native host probe: nativeMachine=0x{0:x4}; processMachine=0x{1:x4}; is64BitProcess={2}' -f $observedHost.nativeMachine,$observedHost.processMachine,$observedHost.is64BitProcess)
$module=Get-Module Product
& $module {
    $script:fixtureMachine=[pscustomobject]@{source='IsWow64Process2';nativeMachine=0xaa64;processMachine=0x8664;is64BitProcess=$true}
    $script:probeFailure=$false
    function script:Get-NativeHostMachine {if($script:probeFailure){throw 'synthetic API failure'};return $script:fixtureMachine}
}
$oldEnvironment=$env:PROCESSOR_ARCHITECTURE
try{
    $env:PROCESSOR_ARCHITECTURE='AMD64'
    Assert-PackageHost $package.contract;$script:checks++
    Reject {Assert-PackageHost $legacy} 'x64 package on ARM64 with misleading AMD64 environment'
    & $module {$script:fixtureMachine.nativeMachine=0x8664}
    Reject {Assert-PackageHost $package.contract} 'ARM64 package on AMD64'
    Assert-PackageHost $legacy;$script:checks++
    & $module {$script:fixtureMachine.nativeMachine=0xaa64;$script:fixtureMachine.is64BitProcess=$false}
    Reject {Assert-PackageHost $package.contract} '32-bit setup process'
    & $module {$script:fixtureMachine.is64BitProcess=$true;$script:probeFailure=$true}
    Reject {Assert-PackageHost $package.contract} 'OS API failure'
}finally{$env:PROCESSOR_ARCHITECTURE=$oldEnvironment}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
Require ($errors.Count -eq 0) 'Setup does not parse'
$registration=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-Registration'},$true)
. ([scriptblock]::Create($registration.Extent.Text))
$product=Get-Product yimecore;$root='C:\synthetic-install'
function Run-Native([string]$Path,[string[]]$Arguments){$script:calls.Add(($Path+'|'+($Arguments -join '|')))}
foreach($contract in @($package.contract,$legacy)){
    $script:calls=[Collections.Generic.List[string]]::new()
    Set-Registration $true 'C:\synthetic-payload'
    Require ($calls.Count -eq 2 -and $calls[0] -ceq ('C:\synthetic-payload\'+$contract.nativeDirectory+'\YimeTextServiceRegistration.exe|register|C:\synthetic-install\'+$contract.nativeDirectory+'\YimeTextServiceExperiment.dll') -and $calls[1] -ceq 'C:\synthetic-payload\x86\YimeTextServiceRegistration.exe|register-com|C:\synthetic-install\x86\YimeTextServiceExperiment.dll') 'Wrong 64-bit/shared or x86 registration sequence'
    $calls.Clear();Set-Registration $false 'C:\synthetic-maintenance'
    Require (($calls -join ',') -ceq ('C:\synthetic-maintenance\x86\YimeTextServiceRegistration.exe|unregister,C:\synthetic-maintenance\'+$contract.nativeDirectory+'\YimeTextServiceRegistration.exe|unregister')) 'Wrong uninstall registration tools'
}
$maintenance=Join-Path $work '.setup';$null=[IO.Directory]::CreateDirectory($maintenance)
[IO.File]::Copy((Join-Path $valid 'product-package.json'),(Join-Path $maintenance 'product-package.json'))
foreach($member in Get-MaintenanceMembers $product $package.contract){
    $destination=Join-Path $maintenance ('native/'+$member)
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy((Join-Path $valid ('payload/'+$member)),$destination)
}
$installed=Read-MaintenancePackage $maintenance
Require ($installed.contract.nativeDirectory -ceq 'arm64') 'Installed uninstaller lost ARM64 contract'
[IO.File]::WriteAllText((Join-Path $maintenance 'native/arm64/YimeTextServiceRegistration.exe'),'damaged fixture')
Reject {Read-MaintenancePackage $maintenance} 'tampered installed maintenance tool'
Write-Output ('PASS: '+$script:checks+' ARM64 package/PE/host/registration/maintenance checks. Read-only native OS query, byte fixtures and mocked maintenance calls; no product binary executed, no installed product, registry, UI or user data changed. '+$work)
