[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'tools/yimecore/development-scope.ps1')
. (Join-Path $repo 'tools/yimecore/build-system-observation.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-build-common.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-test-isolation.ps1')
if((Get-YimeCoreExperimentBuildScope arm64).build_lane -ne 'arm64_native_source_build'){throw 'Require the identified ARM64 host.'}
# Reuse only the reviewed private-Broker ownership helpers, without executing
# the historical MYCOMPUTER runner's top-level body.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tools/yimecore/test-focus-cancellation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Cannot parse existing Broker isolation helpers.'}
foreach($name in @('Wait-IsolatedBroker','Stop-IsolatedBroker')){
    $function=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
    if(@($function).Count -ne 1){throw 'Expected exactly one reviewed ownership helper.'}
    . ([scriptblock]::Create($function.Extent.Text))
}
$pointer=Get-Content -LiteralPath (Join-Path $repo '.generated/arm64-toolchain/native-build-location.json') -Raw -Encoding utf8|ConvertFrom-Json
$build=[IO.Path]::GetFullPath($pointer.build_root)
$allowed=Join-Path $repo '.tmp\yimecore-platform-experiments\'
if(-not $build.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected source build location.'}
$summary=Get-Content -LiteralPath (Join-Path $build 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
if(-not $summary.source_build_passed -or $summary.target -ne 'arm64'){throw 'Require completed ARM64 build.'}
foreach($artifact in $summary.artifacts){
    if($artifact.pe_machine -ne '0xaa64' -or (Get-FileHash -LiteralPath (Resolve-LocalProductChild $build $artifact.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $artifact.sha256){throw 'Source artifact changed.'}
}
$release=Join-Path $build 'tsf-build\Release'
$evidence=Join-Path $build 'tsf-three-modes-retry1'
if(Test-Path -LiteralPath $evidence){throw 'Preserve earlier TSF evidence.'}
New-Item -ItemType Directory -Path $evidence|Out-Null
$dataRoot=Join-Path $repo 'go-backend\input_methods\yime\data'
$go=Join-Path $repo '.generated/arm64-toolchain/go1.25.14/go/bin/go.exe'
$env:GOOS='windows';$env:GOARCH='arm64';$env:CGO_ENABLED='0';$env:GOTOOLCHAIN='local';$env:GOFLAGS='';$env:GOWORK='off'
$env:GOCACHE=Join-Path $repo '.tmp/arm64-go-native-20261026/gocache'
$env:GOMODCACHE=Join-Path $repo '.tmp/arm64-go-native-20261026/gomodcache'
$env:GOTMPDIR=Join-Path $repo '.tmp/arm64-go-native-20261026/gotmpdir'
foreach($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA')){
    $path=Join-Path $evidence ('state\'+$name)
    New-Item -ItemType Directory -Path $path -Force|Out-Null
    [Environment]::SetEnvironmentVariable($name,$path,'Process')
}
$indexer=Join-Path $build 'bin\YimeCoreIndexArm64Retry1.exe'
if(Test-Path -LiteralPath $indexer){throw 'Preserve earlier indexer.'}
$broker=Join-Path $build 'bin\YimeBroker.exe'
$before=Get-LocalProductProtectionEvidence -HashesOnly
$sourceRecords=Get-Content -LiteralPath (Join-Path $build 'source-hashes.json') -Raw -Encoding utf8|ConvertFrom-Json
$runs=@();$processes=@();$passed=$false;$failure=$null
try {
    Assert-LocalProductSourceUnchanged $repo $sourceRecords
    Push-Location (Join-Path $repo 'go-backend')
    try {
        & $go build -trimpath -buildvcs=false -o $indexer ./cmd/yimecore-index 2>&1|Tee-Object -FilePath (Join-Path $evidence 'build-indexer.txt')
        if($LASTEXITCODE -ne 0){throw 'ARM64 test indexer build failed.'}
    } finally {Pop-Location}
    foreach($mode in @('full','variable','shorthand')){
        $modeRoot=Join-Path $evidence $mode
        New-Item -ItemType Directory -Path $modeRoot|Out-Null
        $dictionary=Join-Path $dataRoot ('yime_'+$mode+'.dict.yaml')
        & {
            # Match the existing focus-cancellation runner: the boundary helper
            # traverses FileInfo.Parent and predates strict-mode callers.
            Set-StrictMode -Off
            & (Join-Path $repo 'tools/assert-data-source-boundary.ps1') -Path $dictionary -InputId ('arm64-tsf-'+$mode)
        }
        if($LASTEXITCODE -ne 0){throw 'Product dictionary boundary rejected.'}
        $index=Join-Path $modeRoot 'index.yidx'
        $manifest=Join-Path $modeRoot 'index-build.json'
        & $indexer -mode $mode -source $dictionary -output $index -manifest $manifest -allowed-source-root $dataRoot -allowed-output-root $build 2>&1|Tee-Object -FilePath (Join-Path $modeRoot 'index-build.txt')
        if($LASTEXITCODE -ne 0 -or -not (Get-Content -LiteralPath $manifest -Raw -Encoding utf8|ConvertFrom-Json).verified){throw 'Fresh product index failed verification.'}
        $pipe='\\.\pipe\YimeBroker.Arm64Source.'+[guid]::NewGuid().ToString('N')
        $arguments='-index "{0}" -mode {1} -named-pipe "{2}"' -f $index,$mode,$pipe
        $process=Start-Process -FilePath $broker -ArgumentList $arguments -WorkingDirectory $modeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $modeRoot 'broker-out.txt') -RedirectStandardError (Join-Path $modeRoot 'broker-err.txt')
        $started=$process.StartTime
        $record=[ordered]@{mode=$mode;pid=$process.Id;image=$broker;started_at_utc=$started.ToUniversalTime().ToString('o');pipe=$pipe;stopped=$false}
        $processes+=$record
        try {
            Wait-IsolatedBroker $process $broker $started $pipe
            $longCode=if($mode -eq 'full'){'bjjjbjjjbjjj'}else{'bjbjbj'}
            Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $release 'YimeTsfCompositionTests.exe') -Arguments @((Join-Path $release 'YimeTextServiceExperiment.dll'),$pipe,$longCode) -BuildRoot $build -EvidenceRoot $modeRoot -LogName 'tsf-arm64.txt'
            $runs+=[ordered]@{mode=$mode;architecture='arm64';passed=$true}
        } finally {
            try {Stop-IsolatedBroker $process $broker $started;$record.stopped=$true}finally{$process.Dispose()}
        }
    }
    Assert-LocalProductSourceUnchanged $repo $sourceRecords
    $passed=$true
} catch {$failure=$_.Exception.Message;throw}
finally {
    $after=Get-LocalProductProtectionEvidence -HashesOnly
    $protected=($before|ConvertTo-Json -Depth 8 -Compress) -ceq ($after|ConvertTo-Json -Depth 8 -Compress)
    $result=[ordered]@{scope='ARM64 current-source direct TSF documents with private in-memory Broker; standard product dictionaries';generated_at=[DateTime]::UtcNow.ToString('o');passed=($passed -and $protected);failure=$failure;protected_registration_unchanged=$protected;runs=$runs;brokers=$processes;registered_host_acceptance=$null;physical_acceptance=$false;installation_performed=$false}
    Write-LocalProductJson $result (Join-Path $evidence 'summary.json')
    $result|ConvertTo-Json -Depth 8
    if(-not $protected){throw 'Protected registration changed.'}
}
