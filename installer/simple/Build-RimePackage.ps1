[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$out=Assert-PlainPath $OutputRoot
if(Test-Path -LiteralPath $out){throw 'Choose a fresh output directory'}
$payload=Join-Path $out 'source-payload'
$null=[IO.Directory]::CreateDirectory($payload)
function Copy-Tree([string]$Source,[string]$Target){
    foreach($file in Get-ProductFiles $Source){
        $path=Join-Path $Target $file.FullName.Substring($Source.Length+1)
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::Copy($file.FullName,$path,$false)
    }
}
foreach($arch in @('x86','x64')){
    $build=if($arch -eq 'x86'){'build'}else{'build64'}
    $dest=Join-Path $payload $arch;$null=[IO.Directory]::CreateDirectory($dest)
    foreach($name in @('PIMETextService.dll','PIMERegistrationStatus.exe')){
        [IO.File]::Copy((Join-Path $repo ($build+'\PIMETextService\Release\'+$name)),(Join-Path $dest $name),$false)
    }
}
[IO.File]::Copy((Join-Path $repo 'build\PIMELauncher\PIMELauncher.exe'),(Join-Path $payload 'PIMELauncher.exe'),$false)
Copy-Tree (Join-Path $repo 'go-backend\build\go-backend') (Join-Path $payload 'go-backend')
if(Test-Path -LiteralPath (Join-Path $repo 'licenses')){Copy-Tree (Join-Path $repo 'licenses') (Join-Path $payload 'licenses')}
[IO.File]::WriteAllText((Join-Path $payload 'backends.json'),'[{"name":"go-backend","command":"go-backend\\server.exe","workingDir":"go-backend","params":""}]',[Text.UTF8Encoding]::new($false))
$version=(Get-Content -LiteralPath (Join-Path $repo 'version.txt') -Raw).Trim()
& (Join-Path $PSScriptRoot 'Build-Package.ps1') -Product rime-pime -PayloadRoot $payload -OutputRoot (Join-Path $out 'rime-pime') -Version $version
