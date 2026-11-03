$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force

function MustReject([scriptblock]$Case){
    $rejected=$false
    try{& $Case | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe ARM64 stage accepted'}
}

$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('YimeArm64Stage-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($sandbox)
$sid='offline-user'
$identity=[pscustomobject]@{source='IsWow64Process2';nativeMachine=0xaa64;processMachine=0;
    is64BitProcess=$true;administrator=$true;sid=$sid;shellPath='C:\Program Files\PowerShell\7\pwsh.exe'}
$goodIdentity={ $identity }.GetNewClosure()
$protected={param([string]$Path) if(-not (Test-Path -LiteralPath $Path)){throw 'missing protected fixture'}}
function New-Case {
    $base=Join-Path $sandbox ([guid]::NewGuid().ToString('N'))
    $source=Join-Path $base 'source';$stage=Join-Path $base 'stage'
    $approval=Join-Path $base 'approval.json'
    $null=[IO.Directory]::CreateDirectory((Join-Path $source 'payload'))
    $manifest=@{format='yime-simple-package-18u-1';product='yimecore-18u';target='windows-arm64';host_architecture='arm64';tsf64_architecture='arm64'}
    $descriptor=@{schema='installed-18u-product-v1';sourceCommit='2bc222d92321daa29cea9951761cc1063db5f045';architecture='native-arm64';identity=@{clsid='{6DFACE1F-562E-4773-A9D6-D5753A314711}';profile='{1BD904AC-3194-4419-B70A-5574100F18B3}'}}
    [IO.File]::WriteAllText((Join-Path $source 'product-package.json'),($manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'payload/installed-18u-product.json'),($descriptor|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'Setup.ps1'),'approved setup',[Text.UTF8Encoding]::new($false))
    $rows=@(Get-ProductFiles $source | ForEach-Object {
        @{path=$_.FullName.Substring($source.Length+1).Replace('\','/');bytes=$_.Length;sha256=Get-ContentHash $_.FullName}
    })
    $record=@{schema='yime-18u-arm64-manual-approval-v1';product='yimecore-18u';target='windows-arm64';approvedUserSid=$sid;sourceCommit='2bc222d92321daa29cea9951761cc1063db5f045';archiveSha256=('a'*64);files=$rows}
    [IO.File]::WriteAllText($approval,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{source=$source;stage=$stage;approval=$approval;base=$base}
}
function Stage($Case,[scriptblock]$Observe=$goodIdentity,[scriptblock]$Protection=$protected){
    New-Arm64ProtectedStage $Case.source $Case.stage $Case.stage $Case.approval $Case.approval $sid $Observe $Protection
}
try{
    $valid=New-Case
    $seal=Stage $valid
    Assert-Arm64ProtectedStageBoundary $seal $goodIdentity $protected
    [IO.File]::WriteAllText((Join-Path $valid.source 'Setup.ps1'),'source changed after staging')
    Assert-Arm64ProtectedStageBoundary $seal $goodIdentity $protected

    $replaced=New-Case
    [IO.File]::WriteAllText((Join-Path $replaced.source 'Setup.ps1'),'different package')
    MustReject {Stage $replaced}

    $extra=New-Case
    [IO.File]::WriteAllText((Join-Path $extra.source 'unapproved.ps1'),'extra')
    MustReject {Stage $extra}
    if(Test-Path -LiteralPath $extra.stage){throw 'Extra source file created a stage'}

    $badParent=New-Case
    $denyParent={param([string]$Path) if($Path -ceq $badParent.base){throw 'simulated writable parent'}}.GetNewClosure()
    MustReject {Stage $badParent $goodIdentity $denyParent}
    if(Test-Path -LiteralPath $badParent.stage){throw 'Bad parent permissions created a stage'}

    $reparse=New-Case
    $denyReparse={param([string]$Path) if($Path -ceq $reparse.base){throw 'simulated reparse parent'}}.GetNewClosure()
    MustReject {Stage $reparse $goodIdentity $denyReparse}
    if(Test-Path -LiteralPath $reparse.stage){throw 'Reparse parent created a stage'}

    $tampered=New-Case
    $tamperedSeal=Stage $tampered
    [IO.File]::WriteAllText((Join-Path $tampered.stage 'extra.ps1'),'extra after staging')
    MustReject {Assert-Arm64ProtectedStageBoundary $tamperedSeal $goodIdentity $protected}

    $changedDuring=New-Case
    $state=[pscustomobject]@{calls=0}
    $changing={
        $state.calls++
        if($state.calls -eq 1){$identity}
        else{[pscustomobject]@{source='IsWow64Process2';nativeMachine=0xaa64;processMachine=0;
            is64BitProcess=$true;administrator=$true;sid='different-user';shellPath=$identity.shellPath}}
    }.GetNewClosure()
    MustReject {Stage $changedDuring $changing $protected}

    $state2=[pscustomobject]@{calls=0}
    $changedAtBoundary={
        $state2.calls++
        if($state2.calls -eq 1){$identity}
        else{[pscustomobject]@{source='IsWow64Process2';nativeMachine=0xaa64;processMachine=0;
            is64BitProcess=$true;administrator=$false;sid=$sid;shellPath=$identity.shellPath}}
    }.GetNewClosure()
    MustReject {Assert-Arm64ProtectedStageBoundary $seal $changedAtBoundary $protected}
    Write-Output 'PASS ARM64 protected staging candidate: 1 valid stage, 7 fault refusals and source separation'
}finally{
    [IO.Directory]::Delete($sandbox,$true)
}
