# Windows filesystem-only tests of the ACTUAL exported ownership function.
# Invoke via tools/powershell/run_checked.py --edition ps5. Never execute Setup.
# PE/resource-lock helpers are deliberately mocked; these tests prove ownership
# and old-manifest/hash boundaries, NOT PE validity or full resource provenance.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force -PassThru
& $module {
    function script:Assert-ProductPe { param($Path,$Architecture) }
    function script:Assert-18uPackageIdentity { param($Root,$Manifest,$Product,$Members) }
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('yime-18u-ownership-test-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($base)
$names=@('x64/YimeTextService18u.dll','x64/Yime18uProductRegistration.exe','x64/YimeTouchRegisteredFormalHostTests.exe',
    'bin/YimeBroker18u.exe','bin/Yime18uInstalledRuntime.exe','profile-icon.ico','installed-18u-product.json',
    'source/prototypes/touch-terminal/desktop/resources.lock.json','source/tools/yimecore/18u-touch-product.json',
    'source/prototypes/touch-terminal/data/physical-layout.json','source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
    'source/internal_data/yime_syllable_decomposition.tsv','data/ascii_keyboard_manifest.json','data/yime_variable.dict.yaml',
    'data/yime_full.dict.yaml','data/yime_shorthand.dict.yaml')
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
function New-Fixture([string]$label){
    $root=Join-Path $base $label
    $null=[IO.Directory]::CreateDirectory($root)
    $rows=@(foreach($name in $names){
        $path=Join-Path $root $name
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        if($name -ceq 'installed-18u-product.json'){
            # The current ownership reader uses the old installed descriptor to
            # select v1/v2 inventory. Hash the real fixture JSON, not placeholder text.
            Write-Json $path ([ordered]@{schema='installed-18u-product-v1'})
        }else{[IO.File]::WriteAllText($path,('synthetic-old-payload:'+ $name))}
        [ordered]@{path=$name;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-ContentHash $path)}
    })
    $maintenance=Join-Path $root '.setup'
    $null=[IO.Directory]::CreateDirectory((Join-Path $maintenance 'native/x64'))
    [IO.File]::Copy((Join-Path $root 'x64/Yime18uProductRegistration.exe'),(Join-Path $maintenance 'native/x64/Yime18uProductRegistration.exe'))
    Write-Json (Join-Path $maintenance 'product-package.json') ([ordered]@{format='yime-simple-package-18u-1';product='yimecore-18u';version='old-version';target='windows-amd64';host_architecture='amd64';tsf64_architecture='x64';files=$rows})
    Write-Json (Join-Path $root '.yime-product.json') ([ordered]@{format='yime-simple-install-1';product='yimecore-18u';version='old-version';target='windows-amd64'})
    return $root
}
function Assert-Refused([string]$root,[string]$label){
    $refused=$false
    try{$null=Assert-Installed18uOwnership $root}catch{$refused=$true}
    if(-not $refused){throw ('Unexpected ownership acceptance: '+$label)}
}
try{
    $root=New-Fixture 'old-not-new'
    # A caller's incoming/new package is intentionally unrelated to this OLD root.
    & $module { $script:package=[pscustomobject]@{manifest=[pscustomobject]@{version='NEW-version';files=@()}} }
    $result=Assert-Installed18uOwnership $root
    if($result -notmatch 'version=old-version; payload_count=16'){throw 'Old installed manifest was not used'}
    foreach($case in @('marker-product','marker-version','marker-target','marker-format','foreign-manifest','path-escape','extra-file','wrong-hash','maintenance-hash','missing-member')){
        $root=New-Fixture $case
        $markerPath=Join-Path $root '.yime-product.json'
        $manifestPath=Join-Path $root '.setup/product-package.json'
        $marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json
        $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
        switch($case){
            'marker-product' {$marker.product='yimecore'}
            'marker-version' {$marker.version='new-version'}
            'marker-target' {$marker.target='windows-arm64'}
            'marker-format' {$marker.format='foreign'}
            'foreign-manifest' {$manifest.product='rime-pime'}
            'path-escape' {$manifest.files[0].path='../foreign.dll'}
            'extra-file' {[IO.File]::WriteAllText((Join-Path $root 'unowned.txt'),'retain')}
            'wrong-hash' {[IO.File]::WriteAllText((Join-Path $root 'data/yime_full.dict.yaml'),'modified')}
            'maintenance-hash' {[IO.File]::WriteAllText((Join-Path $root '.setup/native/x64/Yime18uProductRegistration.exe'),'modified')}
            'missing-member' {$manifest.files=@($manifest.files|Where-Object {$_.path -ne 'data/yime_full.dict.yaml'})}
        }
        Write-Json $markerPath $marker
        Write-Json $manifestPath $manifest
        Assert-Refused $root $case
        if(-not (Test-Path -LiteralPath $root)){throw 'Ownership test unexpectedly removed files'}
    }
    Write-Output 'PASS actual ownership function: 1 old-manifest acceptance and 10 refusal cases; PE/resource helpers mocked; no system lifecycle execution'
}finally{
    # Delete only the newly-created GUID fixture tree, never any installation.
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
    Remove-Module $module.Name -Force
}
