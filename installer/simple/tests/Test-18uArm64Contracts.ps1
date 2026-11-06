# Architecture, legacy schema and ownership contracts. Filesystem/metadata only;
# synthetic PEs are parsed, never loaded. Setup and registry are never executed.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$module=Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force -PassThru
$base=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../.generated'))) ('arm64-contract-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($base)
$script:checks=0
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Work,[string]$Label){$failed=$false;try{& $Work|Out-Null}catch{$failed=$true};Require $failed ('Expected rejection: '+$Label)}
function Json($Path,$Value){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))}
function Write-Pe($Path,[int]$Machine){
    [byte[]]$b=New-Object byte[] 1024
    [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($b,0);[BitConverter]::GetBytes([uint32]0x80).CopyTo($b,0x3c)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($b,0x80);[BitConverter]::GetBytes([uint16]$Machine).CopyTo($b,0x84)
    [BitConverter]::GetBytes([uint16]240).CopyTo($b,0x94);[BitConverter]::GetBytes([uint16]$(if($Path.EndsWith('.dll')){0x2002}else{2})).CopyTo($b,0x96)
    [BitConverter]::GetBytes([uint16]0x20b).CopyTo($b,0x98)
    [IO.File]::WriteAllBytes($Path,$b)
}
$outer=[pscustomobject]@{format='yime-simple-package-18u-1';product='yimecore-18u';version='fixture';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64';files=@()}
Require ((Get-PackageContract $outer).nativeDirectory -ceq 'arm64') 'ARM64 contract unavailable'
foreach($field in @('target','host_architecture','tsf64_architecture','format')){
    $bad=$outer|ConvertTo-Json -Depth 6|ConvertFrom-Json;$bad.$field='wrong';Reject {Get-PackageContract $bad} $field
}
$bad=$outer|ConvertTo-Json -Depth 6|ConvertFrom-Json;$bad.tsf64_architecture='arm64x';Reject {Get-PackageContract $bad} '18u is native ARM64, not ARM64X'
$pe=Join-Path $base 'fixture.dll';Write-Pe $pe 0xaa64;Assert-ProductPe $pe 'arm64';$script:checks++
Reject {Assert-ProductPe $pe 'x64'} 'ARM relabeled x64'
Write-Pe $pe 0x8664;Reject {Assert-ProductPe $pe 'arm64'} 'x64 relabeled ARM'

# Validate exact old v2 metadata using the real identity function. The declared
# dictionary rows come from the canonical lock; this is a schema/contract test,
# not a claim that synthetic dictionary content is a real delivered corpus.
$identityRoot=Join-Path $base 'identity'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$lock=Get-Content -LiteralPath (Join-Path $repo 'prototypes/touch-terminal/desktop/resources.lock.json') -Raw|ConvertFrom-Json
$product=Get-Product 'yimecore-18u'
$capabilities=@('installed-tsf-frontend','composition','candidates','literal','host-editing')
$source=[ordered]@{schema_version='yimecore-18u-touch-product-v2';installable=$true;identity=@{clsid=$product.clsid;profile=$product.profile};
    scope=@{architecture='arm64';installed_frontend=$true;languages=@('CN','EN');modes=@('full','variable','shorthand');capabilities=$capabilities};
    data=@{layout_sha256=$lock.layoutProjectionSHA256;dictionary_sha256=$lock.files.'yime_variable.dict.yaml'.sha256;standard_index_fallback=$false;
        dictionary_sha256_by_mode=@{full=$lock.files.'yime_full.dict.yaml'.sha256;variable=$lock.files.'yime_variable.dict.yaml'.sha256;shorthand=$lock.files.'yime_shorthand.dict.yaml'.sha256}}}
Json (Join-Path $identityRoot 'source/tools/yimecore/18u-touch-product-arm64.json') $source
Json (Join-Path $identityRoot 'source/prototypes/touch-terminal/desktop/resources.lock.json') $lock
Json (Join-Path $identityRoot 'source/prototypes/touch-terminal/data/physical-layout.json') @{layoutId=$lock.layoutProjectionSHA256}
$legacyNames=@('arm64/YimeTextService18u.dll','arm64/Yime18uProductRegistration.exe','arm64/YimeTouchRegisteredFormalHostTests.exe',
    'bin/Yime18uInstalledRuntime.exe','bin/YimeBroker18u.exe','profile-icon.ico','source/tools/yimecore/18u-touch-product-arm64.json',
    'source/prototypes/touch-terminal/desktop/resources.lock.json','source/prototypes/touch-terminal/data/physical-layout.json',
    'source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json','source/internal_data/yime_syllable_decomposition.tsv')+@(Get-Legacy18uArm64FrontendMembers)
$rows=@(foreach($name in $legacyNames){[pscustomobject]@{path=$name;bytes=7;sha256=('a'*64)}})
$rows+=@(foreach($entry in $lock.files.PSObject.Properties){[pscustomobject]@{path=('data/'+$entry.Name);bytes=$entry.Value.bytes;sha256=$entry.Value.sha256}})
$descriptor=[ordered]@{schema='installed-18u-product-v2';product='yimecore-18u';sourceCommit=('a'*40);identity=@{clsid=$product.clsid;profile=$product.profile};
    architecture='native-arm64';autostart=$true;languages=@('CN','EN');modes=@('full','variable','shorthand');capabilities=$capabilities;files=$rows}
$outer.files=$rows+@([pscustomobject]@{path='installed-18u-product.json';bytes=7;sha256=('a'*64)})
$members=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($row in $outer.files){$null=$members.Add($row.path)}
Json (Join-Path $identityRoot 'installed-18u-product.json') $descriptor
Assert-18uPackageIdentity $identityRoot $outer $product $members -AllowLegacyArm64Maintenance;$script:checks++
Reject {Assert-18uPackageIdentity $identityRoot $outer $product $members} 'legacy v2 cannot enter a new package'
foreach($case in @('autostart','languages','modes','capabilities','architecture','schema','extra-field','source-architecture','source-mode-hash')){
    $changed=$descriptor|ConvertTo-Json -Depth 15|ConvertFrom-Json
    $changedSource=$source|ConvertTo-Json -Depth 15|ConvertFrom-Json
    switch($case){
        'autostart' {$changed.autostart=$false}
        'languages' {$changed.languages=@('EN','CN')}
        'modes' {$changed.modes=@('variable')}
        'capabilities' {$changed.capabilities=@('installed-tsf-frontend')}
        'architecture' {$changed.architecture='native-x64'}
        'schema' {$changed.schema='installed-18u-product-v3'}
        'extra-field' {$changed|Add-Member -NotePropertyName language -NotePropertyValue 'CN'}
        'source-architecture' {$changedSource.scope.architecture='x64'}
        'source-mode-hash' {$changedSource.data.dictionary_sha256_by_mode.full='b'*64}
    }
    Json (Join-Path $identityRoot 'installed-18u-product.json') $changed
    Json (Join-Path $identityRoot 'source/tools/yimecore/18u-touch-product-arm64.json') $changedSource
    Reject {Assert-18uPackageIdentity $identityRoot $outer $product $members -AllowLegacyArm64Maintenance} $case
}

# Current v1 ARM metadata must pair with a complete matching-source Frontend v2.
$currentRoot=Join-Path $base 'current-identity'
$currentSource=Get-Content -LiteralPath (Join-Path $repo 'tools/yimecore/18u-touch-product.json') -Raw|ConvertFrom-Json
$currentSource.scope.architecture='arm64'
Json (Join-Path $currentRoot 'source/tools/yimecore/18u-touch-product-arm64.json') $currentSource
Json (Join-Path $currentRoot 'source/prototypes/touch-terminal/desktop/resources.lock.json') $lock
Json (Join-Path $currentRoot 'source/prototypes/touch-terminal/data/physical-layout.json') @{layoutId=$lock.layoutProjectionSHA256}
$legacyExtra=@(Get-Legacy18uArm64FrontendMembers)
$currentRows=@($rows|Where-Object {$_.path -cnotin $legacyExtra})
$frontFiles=[ordered]@{}
$frontNames=@('YimeTouchKeyboard.exe','resources.json','resources.lock.json','USER_GUIDE.zh-CN.md','Start Installed Touch Keyboard.cmd','Start Local Preview.cmd',
    'data/ascii_keyboard_manifest.json','data/yime_full.dict.yaml','data/yime_variable.dict.yaml','data/yime_shorthand.dict.yaml',
    'prototypes/touch-terminal/data/physical-layout.json','prototypes/touch-terminal/encoding/yime_yinyuan_layout.json')
foreach($name in $frontNames){
    $origin=if($name.StartsWith('prototypes/')){'source/'+$name}else{$name}
    $record=@($currentRows|Where-Object {$_.path -ceq $origin})
    $hash=if($record.Count){$record[0].sha256}else{'a'*64};$bytes=if($record.Count){$record[0].bytes}else{7}
    $frontFiles[$name]=$hash
    $currentRows+=[pscustomobject]@{path=('frontend/'+$name);bytes=$bytes;sha256=$hash}
}
$currentRows+=[pscustomobject]@{path='frontend/manifest.json';bytes=7;sha256=('a'*64)}
$front=[ordered]@{schemaVersion=2;scope='installed-18u-tsf-frontend-candidate';architecture='windows-arm64';sourceCommit=('a'*40);sourceChanges=$false;sendInputFallback=$false;frontendProtocol=@{version=2;pipePrefix='Yime18u.Frontend.v2.'};files=$frontFiles}
Json (Join-Path $currentRoot 'frontend/manifest.json') $front
$currentDescriptor=[ordered]@{schema='installed-18u-product-v1';product='yimecore-18u';sourceCommit=('a'*40);identity=@{clsid=$product.clsid;profile=$product.profile};architecture='native-arm64';language='CN';mode='variable';autostart=$false;files=$currentRows}
Json (Join-Path $currentRoot 'installed-18u-product.json') $currentDescriptor
$currentOuter=$outer|ConvertTo-Json -Depth 15|ConvertFrom-Json
$currentOuter.files=$currentRows+@([pscustomobject]@{path='installed-18u-product.json';bytes=7;sha256=('a'*64)})
$currentMembers=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($row in $currentOuter.files){$null=$currentMembers.Add($row.path)}
Assert-18uPackageIdentity $currentRoot $currentOuter $product $currentMembers;$script:checks++
$null=$currentMembers.Remove('frontend/YimeTouchKeyboard.exe')
Reject {Assert-18uPackageIdentity $currentRoot $currentOuter $product $currentMembers} 'current ARM package missing shared frontend'
$null=$currentMembers.Add('frontend/YimeTouchKeyboard.exe')
$currentDescriptor['extra']='unreviewed';Json (Join-Path $currentRoot 'installed-18u-product.json') $currentDescriptor
Reject {Assert-18uPackageIdentity $currentRoot $currentOuter $product $currentMembers} 'current schema must keep exactly nine fields'

# Full old-directory hashing and maintenance ownership use synthetic bytes while
# identity/resource validation is separately covered above. No old package bytes
# or installed data are copied into a mutable fixture.
& $module {
    function script:Assert-18uPackageIdentity { param($Root,$Manifest,$Product,$Members,[switch]$AllowLegacyArm64Maintenance)
        if(-not $AllowLegacyArm64Maintenance){throw 'Legacy maintenance scope was not explicit'}
    }
}
function New-OwnedLegacy([string]$Label){
    $root=Join-Path $base $Label
    foreach($name in @($legacyNames)+@($lock.files.PSObject.Properties|ForEach-Object {'data/'+$_.Name})){
        $path=Join-Path $root $name;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        if($name -match '\.(exe|dll)$'){Write-Pe $path 0xaa64}else{[IO.File]::WriteAllText($path,('fixture:'+ $name))}
    }
    Json (Join-Path $root 'installed-18u-product.json') $descriptor
    $payloadRows=@(foreach($file in Get-ProductFiles $root){[ordered]@{path=$file.FullName.Substring($root.Length+1).Replace('\','/');bytes=$file.Length;sha256=(Get-ContentHash $file.FullName)}})
    $manifest=$outer|ConvertTo-Json -Depth 15|ConvertFrom-Json;$manifest.files=$payloadRows
    Json (Join-Path $root '.setup/product-package.json') $manifest
    Json (Join-Path $root '.yime-product.json') @{format='yime-simple-install-1';product='yimecore-18u';version='fixture';target='windows-arm64'}
    $maintenance=Join-Path $root '.setup/native/arm64';$null=[IO.Directory]::CreateDirectory($maintenance)
    [IO.File]::Copy((Join-Path $root 'arm64/Yime18uProductRegistration.exe'),(Join-Path $maintenance 'Yime18uProductRegistration.exe'))
    return $root
}
$old=New-OwnedLegacy 'old-owned'
Require ((Assert-Installed18uOwnership $old) -match 'payload_count=20') 'Old ARM inventory was not recognized'
foreach($case in @('hash','unknown','maintenance','marker-target','missing')){
    $old=New-OwnedLegacy $case
    switch($case){
        'hash' {[IO.File]::WriteAllText((Join-Path $old 'bin/YimeTouchKeyboard.exe'),'tampered')}
        'unknown' {[IO.File]::WriteAllText((Join-Path $old 'foreign.txt'),'preserve')}
        'maintenance' {[IO.File]::WriteAllText((Join-Path $old '.setup/native/arm64/Yime18uProductRegistration.exe'),'tampered')}
        'marker-target' {Json (Join-Path $old '.yime-product.json') @{format='yime-simple-install-1';product='yimecore-18u';version='fixture';target='windows-amd64'}}
        'missing' {[IO.File]::Delete((Join-Path $old 'source/prototypes/touch-terminal/desktop/profiles/main-only.json'))}
    }
    Reject {Assert-Installed18uOwnership $old} ('old ownership '+$case)
    Require (Test-Path -LiteralPath $old) 'Validation unexpectedly removed old files'
}
# Exercise the actual filesystem replacement sequence on a verified synthetic
# old root. This checks bin -> frontend cleanup and external state preservation;
# native registration and installation are not part of this fixture.
$old=New-OwnedLegacy 'migration'
$null=Assert-Installed18uOwnership $old
$state=Join-Path $base 'user-state';$peer=Join-Path $base 'other-product'
$null=[IO.Directory]::CreateDirectory($state);$null=[IO.Directory]::CreateDirectory($peer)
$protected=@((Join-Path $state 'calibration.json'),(Join-Path $state 'user-lexicon.json'),(Join-Path $peer 'runtime.exe'))
foreach($path in $protected){[IO.File]::WriteAllText($path,('must-remain:'+ $path))}
$before=@($protected|ForEach-Object {Get-ContentHash $_})
$incoming=Join-Path $base 'incoming';$newFrontend=Join-Path $incoming 'payload/frontend/YimeTouchKeyboard.exe'
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($newFrontend));Write-Pe $newFrontend 0xaa64
$newPackage=[pscustomobject]@{root=$incoming;product=$product;manifest=[pscustomobject]@{version='new-v1';target='windows-arm64';files=@([pscustomobject]@{path='frontend/YimeTouchKeyboard.exe'})}}
if(-not ([IO.Path]::GetFullPath($old)).StartsWith(([IO.Path]::GetFullPath($base)+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture removal escaped its generated root'}
Remove-ProductDirectory $old 'yimecore-18u'
Copy-ProductPayload $newPackage $old
Require (-not (Test-Path -LiteralPath (Join-Path $old 'bin/YimeTouchKeyboard.exe'))) 'Old bin frontend survived replacement'
Require (Test-Path -LiteralPath (Join-Path $old 'frontend/YimeTouchKeyboard.exe')) 'New frontend not copied'
Require ((Get-ContentHash (Join-Path $old 'frontend/YimeTouchKeyboard.exe')) -ceq (Get-ContentHash $newFrontend)) 'New frontend copy differs'
Require ((@($protected|ForEach-Object {Get-ContentHash $_}) -join ',') -ceq ($before -join ',')) 'Calibration/user state/peer product changed'
Write-Output ('PASS '+$script:checks+' ARM64 package/schema/legacy-maintenance checks; synthetic PE and filesystem/metadata only, no installation/registry/process changes. '+$base)
Remove-Module $module.Name -Force
