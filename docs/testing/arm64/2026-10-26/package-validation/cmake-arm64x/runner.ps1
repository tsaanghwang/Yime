[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gitDir='C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd'
$cmake='C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$dumpbin='C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostarm64\arm64\dumpbin.exe'
$env:PATH=$gitDir+';'+$env:PATH
. (Join-Path $repo 'tools/yimecore/development-scope.ps1')
. (Join-Path $repo 'tools/yimecore/build-system-observation.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-build-common.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-test-isolation.ps1')
$scope=Get-YimeCoreExperimentBuildScope arm64
$base=Join-Path $repo '.tmp/yimecore-platform-experiments'
$out=Join-Path $base ('arm64x-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
if(-not ([IO.Path]::GetFullPath($out)).StartsWith([IO.Path]::GetFullPath($base)+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'New isolated output required'}
Assert-LocalProductPlainPath $out
$null=New-Item -ItemType Directory -Path $out
Write-LocalProductJson ([ordered]@{root=$out;generated_at=[DateTime]::UtcNow.ToString('o')}) (Join-Path $repo '.generated/arm64x-build-location.json')
$before=Get-LocalProductProtectionEvidence
$success=$false;$failure=$null;$protected=$false
function Invoke-CmakeStage([string]$Name,[string[]]$Arguments){
    & $cmake @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $out ($Name+'.txt'))
    if($LASTEXITCODE -ne 0){throw "CMake stage failed: $Name ($LASTEXITCODE)"}
}
try {
    $native=Join-Path $out 'native'
    $ec=Join-Path $out 'ec'
    $x64=Join-Path $out 'x64'
    $src=Join-Path $repo 'YimeTextServiceExperiment'
    Invoke-CmakeStage native-configure @('-S',$src,'-B',$native,'-G','Visual Studio 17 2022','-A','ARM64','-DYIME_LOCAL_PRODUCT=ON','-DYIME_ARM64X_STAGE=ARM64')
    Invoke-CmakeStage native-build @('--build',$native,'--config','Release','--parallel','4')
    $rsp=Join-Path $native 'arm64x/YimeTextServiceExperiment.rsp'
    Invoke-CmakeStage ec-configure @('-S',$src,'-B',$ec,'-G','Visual Studio 17 2022','-A','ARM64EC','-DYIME_LOCAL_PRODUCT=ON','-DYIME_ARM64X_STAGE=ARM64EC',('-DYIME_ARM64X_NATIVE_LINK_RSP='+$rsp))
    Invoke-CmakeStage ec-build @('--build',$ec,'--config','Release','--target','YimeTextServiceExperiment','--parallel','4')
    $dll=Join-Path $ec 'Release/YimeTextServiceExperiment.dll'
    & $dumpbin /headers /loadconfig /exports $dll 2>&1 | Out-File -LiteralPath (Join-Path $out 'arm64x-dumpbin.txt') -Encoding utf8
    if($LASTEXITCODE -ne 0){throw 'dumpbin failed'}
    Get-Content -LiteralPath (Join-Path $out 'arm64x-dumpbin.txt') | Select-String -Pattern 'machine |hybrid metadata|Hybrid code|Dynamic value|ARM64X' | ForEach-Object {$_.Line}
    Invoke-CmakeStage x64-configure @('-S',$src,'-B',$x64,'-G','Visual Studio 17 2022','-A','x64','-DYIME_LOCAL_PRODUCT=ON')
    Invoke-CmakeStage x64-build @('--build',$x64,'--config','Release','--parallel','4')
    Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $native 'Release/YimeTextServiceContractTests.exe') -Arguments @($dll) -BuildRoot $out -EvidenceRoot $out -LogName 'arm64-contracts.txt'
    Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $x64 'Release/YimeTextServiceContractTests.exe') -Arguments @($dll) -BuildRoot $out -EvidenceRoot $out -LogName 'x64-contracts.txt'
    $success=$true
} catch {$failure=$_.Exception.Message;throw}
finally {
    $after=Get-LocalProductProtectionEvidence
    $protected=($before|ConvertTo-Json -Depth 30 -Compress) -ceq ($after|ConvertTo-Json -Depth 30 -Compress)
    Write-LocalProductJson ([ordered]@{schema_version='yimecore-arm64x-build-contract-v1';generated_at=[DateTime]::UtcNow.ToString('o');output_root=$out;scope=$scope;passed=($success -and $protected);failure=$failure;protected_registration_unchanged=$protected;installed=$false}) (Join-Path $out 'summary.json')
    if(-not $protected){throw 'Protected registration/default changed during build/contracts'}
}
Write-Output "ARM64X native+x64 isolated contracts complete: $out"
