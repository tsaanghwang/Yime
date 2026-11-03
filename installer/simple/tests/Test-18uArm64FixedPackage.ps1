$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force

function MustReject([scriptblock]$Case){
    $rejected=$false
    try{& $Case | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Damaged or unapproved ARM64 package accepted'}
}

$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('YimeArm64FixedPackage-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $sandbox 'package'
$approval=Join-Path $sandbox 'independent-approval.json'
$null=[IO.Directory]::CreateDirectory((Join-Path $root 'payload'))
try{
    $manifest=@{format='yime-simple-package-18u-1';product='yimecore-18u';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64'}
    $descriptor=@{schema='installed-18u-product-v1';sourceCommit='2bc222d92321daa29cea9951761cc1063db5f045';architecture='native-arm64';identity=@{clsid='{6DFACE1F-562E-4773-A9D6-D5753A314711}';profile='{1BD904AC-3194-4419-B70A-5574100F18B3}'}}
    [IO.File]::WriteAllText((Join-Path $root 'product-package.json'),($manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'payload/installed-18u-product.json'),($descriptor|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $sid='S-1-5-21-100-200-300-400'
    $rows=@(Get-ProductFiles $root | ForEach-Object {
        @{path=$_.FullName.Substring($root.Length+1).Replace('\','/');bytes=$_.Length;sha256=Get-ContentHash $_.FullName}
    })
    $record=@{schema='yime-18u-arm64-manual-approval-v1';product='yimecore-18u';target='windows-arm64';approvedUserSid=$sid;sourceCommit='2bc222d92321daa29cea9951761cc1063db5f045';archiveSha256=('a'*64);files=$rows}
    [IO.File]::WriteAllText($approval,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $protected={param([string]$Path) if(-not (Test-Path -LiteralPath $Path)){throw 'missing protected test member'}}
    Assert-Arm64FixedPackage $root $root $approval $approval $sid $true $protected
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval $sid $false $protected}
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval 'S-1-5-21-999-200-300-400' $true $protected}
    MustReject {Assert-Arm64FixedPackage $root (Join-Path $sandbox 'other') $approval $approval $sid $true $protected}
    MustReject {Assert-Arm64FixedPackage $root $root $approval (Join-Path $sandbox 'other.json') $sid $true $protected}
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval $sid $true {throw 'writable path'}}
    [IO.File]::AppendAllText((Join-Path $root 'product-package.json'),' ')
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval $sid $true $protected}
    [IO.File]::WriteAllText((Join-Path $root 'product-package.json'),($manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'unexpected.ps1'),'write-host unsafe')
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval $sid $true $protected}
    [IO.File]::Delete((Join-Path $root 'unexpected.ps1'))
    $record.approvedUserSid='S-1-5-21-999-200-300-400'
    [IO.File]::WriteAllText($approval,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    MustReject {Assert-Arm64FixedPackage $root $root $approval $approval $sid $true $protected}
    Write-Output 'PASS ARM64 fixed package preflight: 1 valid fixture, 8 pre-mutation refusals'
}finally{
    [IO.Directory]::Delete($sandbox,$true)
}
