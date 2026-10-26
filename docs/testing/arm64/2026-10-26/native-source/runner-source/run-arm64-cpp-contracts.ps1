[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'tools/yimecore/development-scope.ps1')
. (Join-Path $repo 'tools/yimecore/build-system-observation.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-build-common.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-test-isolation.ps1')
$scope=Get-YimeCoreExperimentBuildScope arm64
if($scope.build_lane -ne 'arm64_native_source_build'){throw 'Require the identified native ARM64 host.'}
$pointer=Get-Content -LiteralPath (Join-Path $repo '.generated/arm64-toolchain/native-build-location.json') -Raw -Encoding utf8|ConvertFrom-Json
$build=[IO.Path]::GetFullPath($pointer.build_root)
$allowed=Join-Path $repo '.tmp\yimecore-platform-experiments\'
if(-not $build.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected build location.'}
$summary=Get-Content -LiteralPath (Join-Path $build 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
if(-not $summary.source_build_passed -or $summary.target -ne 'arm64' -or $summary.current_product_identity.clsid -ne '{E40FA752-BB96-461D-A51D-F40EB437EC65}') {throw 'Require the completed current-identity ARM64 source build.'}
foreach($artifact in $summary.artifacts){
    $path=Resolve-LocalProductChild $build $artifact.path
    if($artifact.pe_machine -ne '0xaa64' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $artifact.sha256){throw 'Source artifact changed after the successful build.'}
}
$release=Join-Path $build 'tsf-build\Release'
$before=Get-LocalProductProtectionEvidence -HashesOnly
$passed=$false
try {
    Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $release 'YimeTextServiceContractTests.exe') -Arguments @((Join-Path $release 'YimeTextServiceExperiment.dll')) -BuildRoot $build -EvidenceRoot $build -LogName 'native-contract-arm64.txt'
    Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $release 'YimeFocusCancellationTests.exe') -BuildRoot $build -EvidenceRoot $build -LogName 'native-focus-cancellation-arm64.txt'
    $passed=$true
} finally {
    $after=Get-LocalProductProtectionEvidence -HashesOnly
    $unchanged=($before|ConvertTo-Json -Depth 8 -Compress) -ceq ($after|ConvertTo-Json -Depth 8 -Compress)
    $record=[ordered]@{scope='ARM64 source DLL/COM contracts and focus-cancellation fakes; own test UI may appear';generated_at=[DateTime]::UtcNow.ToString('o');build_root=$build;passed=($passed -and $unchanged);protected_registration_unchanged=$unchanged;installation_performed=$false;registered_host_acceptance=$null;physical_acceptance=$false}
    $report=Join-Path $build 'native-contract-summary.json'
    if(Test-Path -LiteralPath $report){throw 'Preserve prior native contract evidence.'}
    Write-LocalProductJson $record $report
    $record|ConvertTo-Json -Depth 6
    if(-not $unchanged){throw 'Protected registration changed.'}
}
