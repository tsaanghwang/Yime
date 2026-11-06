# Actual frontend inventory and installed ownership functions; memory/file fixtures.
# PE parsing and canonical resource assertions are mocked, never lifecycle actions.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force -PassThru
& $module {
    function script:Assert-ProductPe { param($Path,$Architecture) }
    function script:Assert-18uPackageIdentity { param($Root,$Manifest,$Product,$Members) }
}
$base=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../.generated'))) ('frontend-ownership-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($base)
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))}
function New-Fixture([string]$label,[string]$arch='x64'){
    $root=Join-Path $base $label
    $target=if($arch -ceq 'arm64'){'windows-arm64'}else{'windows-amd64'}
    $hostArch=if($arch -ceq 'arm64'){'arm64'}else{'amd64'}
    $sourceName=if($arch -ceq 'arm64'){'18u-touch-product-arm64.json'}else{'18u-touch-product.json'}
    $names=@(($arch+'/YimeTextService18u.dll'),($arch+'/Yime18uProductRegistration.exe'),($arch+'/YimeTouchRegisteredFormalHostTests.exe'),
        'bin/YimeBroker18u.exe','bin/Yime18uInstalledRuntime.exe','profile-icon.ico','installed-18u-product.json',
        'source/prototypes/touch-terminal/desktop/resources.lock.json',('source/tools/yimecore/'+$sourceName),
        'source/prototypes/touch-terminal/data/physical-layout.json','source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
        'source/internal_data/yime_syllable_decomposition.tsv','data/ascii_keyboard_manifest.json','data/yime_variable.dict.yaml',
        'data/yime_full.dict.yaml','data/yime_shorthand.dict.yaml')
    foreach($name in $names){
        $path=Join-Path $root $name;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllText($path,('fixture:'+ $name))
    }
    Write-Json (Join-Path $root 'installed-18u-product.json') @{schema='installed-18u-product-v1';sourceCommit=('a'*40)}
    $frontNames=@('YimeTouchKeyboard.exe','resources.json','resources.lock.json','USER_GUIDE.zh-CN.md',
        'Start Installed Touch Keyboard.cmd','Start Local Preview.cmd','data/ascii_keyboard_manifest.json',
        'data/yime_variable.dict.yaml','data/yime_full.dict.yaml','data/yime_shorthand.dict.yaml',
        'prototypes/touch-terminal/data/physical-layout.json','prototypes/touch-terminal/encoding/yime_yinyuan_layout.json')
    $inventory=[ordered]@{}
    foreach($name in $frontNames){
        $path=Join-Path $root ('frontend/'+$name);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        if($name.StartsWith('data/')){[IO.File]::Copy((Join-Path $root $name),$path)}
        elseif($name.StartsWith('prototypes/')){[IO.File]::Copy((Join-Path $root ('source/'+$name)),$path)}
        else{[IO.File]::WriteAllText($path,('fixture:'+ $name))}
        $inventory[$name]=Get-ContentHash $path
    }
    Write-Json (Join-Path $root 'frontend/manifest.json') ([ordered]@{schemaVersion=2;scope='installed-18u-tsf-frontend-candidate';architecture=$target;sourceCommit=('a'*40);sourceChanges=$false;sendInputFallback=$false;frontendProtocol=@{version=2;pipePrefix='Yime18u.Frontend.v2.'};files=$inventory})
    $rows=@(foreach($file in Get-ProductFiles $root){[ordered]@{path=$file.FullName.Substring($root.Length+1).Replace('\','/');bytes=$file.Length;sha256=(Get-ContentHash $file.FullName)}})
    $maintenance=Join-Path $root '.setup';$null=[IO.Directory]::CreateDirectory((Join-Path $maintenance ('native/'+$arch)))
    [IO.File]::Copy((Join-Path $root ($arch+'/Yime18uProductRegistration.exe')),(Join-Path $maintenance ('native/'+$arch+'/Yime18uProductRegistration.exe')))
    Write-Json (Join-Path $maintenance 'product-package.json') ([ordered]@{format='yime-simple-package-18u-1';product='yimecore-18u';version='test7-fixture';target=$target;host_architecture=$hostArch;tsf64_architecture=$arch;files=$rows})
    Write-Json (Join-Path $root '.yime-product.json') ([ordered]@{format='yime-simple-install-1';product='yimecore-18u';version='test7-fixture';target=$target})
    return $root
}
try {
  foreach($arch in @('x64','arm64')){
    $root=New-Fixture ($arch+'-valid') $arch
    $result=Assert-Installed18uOwnership $root
    if($result -notmatch 'payload_count=29'){throw 'Complete frontend not owned'}
    foreach($case in @('source','architecture','dirty','fallback','traversal','missing','hash','dictionary','extra','old-bin')){
        $root=New-Fixture ($arch+'-'+$case) $arch
        $path=Join-Path $root 'frontend/manifest.json';$front=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        $mp=Join-Path $root '.setup/product-package.json';$manifest=Get-Content -LiteralPath $mp -Raw -Encoding UTF8|ConvertFrom-Json
        switch($case){
            'source' {$front.sourceCommit='b'*40}
            'architecture' {$front.architecture=if($arch -ceq 'arm64'){'windows-amd64'}else{'windows-arm64'}}
            'dirty' {$front.sourceChanges=$true}
            'fallback' {$front.sendInputFallback=$true}
            'traversal' {$front.files|Add-Member -NotePropertyName '../foreign' -NotePropertyValue ('a'*64)}
            'missing' {$front.files.PSObject.Properties.Remove('YimeTouchKeyboard.exe')}
            'hash' {$front.files.'YimeTouchKeyboard.exe'='a'*64}
            'dictionary' {
                $front.files.'data/yime_full.dict.yaml'='b'*64
                foreach($row in $manifest.files){if($row.path -ceq 'frontend/data/yime_full.dict.yaml'){$row.sha256='b'*64}}
            }
            'extra' {[IO.File]::WriteAllText((Join-Path $root 'frontend/unlisted.txt'),'unowned')}
            'old-bin' {[IO.File]::WriteAllText((Join-Path $root 'bin/YimeTouchKeyboard.exe'),'unowned-old-frontend')}
        }
        Write-Json $path $front
        foreach($row in $manifest.files){if($row.path -ceq 'frontend/manifest.json'){$row.sha256=Get-ContentHash $path;$row.bytes=(Get-Item -LiteralPath $path).Length}}
        Write-Json $mp $manifest
        $refused=$false;try{$null=Assert-Installed18uOwnership $root}catch{$refused=$true}
        if(-not $refused){throw ('Unexpected frontend acceptance: '+$case)}
    }
    if($arch -ceq 'arm64'){
        $root=New-Fixture 'arm64-wrong-protocol' $arch
        $path=Join-Path $root 'frontend/manifest.json';$front=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        $front.frontendProtocol.pipePrefix='YimeBroker.18uTouch.v1.desktop-'
        Write-Json $path $front
        $manifest=Get-Content -LiteralPath (Join-Path $root '.setup/product-package.json') -Raw|ConvertFrom-Json
        $refused=$false;try{$null=Get-18uFrontendMembers $root $manifest}catch{$refused=$true}
        if(-not $refused){throw 'ARM Broker v1 marker accepted as Frontend v2'}
    }
  }
    Write-Output 'PASS frontend ownership: x64 and ARM64 complete inventories plus 21 refusal cases; actual inventory/ownership, PE and canonical locks mocked; no installation'
} finally {
    # Preserve fixture evidence under the repository; no recursive deletion.
    Remove-Module $module.Name -Force
}
