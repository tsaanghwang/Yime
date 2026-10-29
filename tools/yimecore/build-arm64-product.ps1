[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GoExecutable,
    [Parameter(Mandatory)][ValidateSet('Visual Studio 17 2022','Visual Studio 18 2026')][string]$NativeGenerator,
    [Parameter(Mandatory)][string]$SpeechAdmissionRoot,
    [Parameter(Mandatory)][string]$ExpectedSpeechAdmissionSummarySha256,
    [Parameter(Mandatory)][string]$ExpectedSpeechSourceInventorySha256,
    [string]$OutputRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'build-system-observation.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
. (Join-Path $PSScriptRoot 'local-product-test-isolation.ps1')
. (Join-Path $PSScriptRoot 'local-product-speech-build.ps1')
. (Join-Path $PSScriptRoot 'arm64-go-environment.ps1')
# Includes preflight failures before a build root/transcript exists.
Invoke-Arm64ProductGoEnvironment {
$scope=Get-YimeCoreExperimentBuildScope arm64
if($scope.build_lane -cne 'arm64_native_source_build'){throw 'ARM64 product packaging requires the identified native ARM64 host.'}
$target=Get-YimeCoreExperimentTarget arm64
if(@($target.physical_host.approved_uses) -cnotcontains 'target_package_transactions'){throw 'ARM64 package work is not in this identified host scope.'}
$generator=Resolve-YimeCorePlatformGenerator arm64 $scope $NativeGenerator
Assert-YimeCoreNativeGo -ExperimentTarget arm64 -GoExecutable $GoExecutable
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$product=Get-LocalProductDescriptor (Join-Path $PSScriptRoot 'local-product.json')
$null=Assert-LocalProductSpeechBuildInputs $product $SpeechAdmissionRoot $ExpectedSpeechAdmissionSummarySha256 $ExpectedSpeechSourceInventorySha256 -ExpectedTarget arm64
if(-not $OutputRoot){$OutputRoot=Join-Path $repo ('.tmp\yimecore-platform-experiments\arm64-package-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
$out=New-LocalProductBuildRoot $repo $OutputRoot arm64
$envNames=@('PATH','GOOS','GOARCH','CGO_ENABLED','GOCACHE','GOTMPDIR')
$previous=@{};foreach($name in $envNames){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$passed=$false;$before=$null;$failure=$null
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt')|Out-Null
try {
    $before=Get-LocalProductProtectionEvidence -HashesOnly
    Write-LocalProductJson $before (Join-Path $out 'protection-before.json')
    $env:PATH=(Split-Path -Parent $GoExecutable)+';'+$env:PATH
    $env:GOOS='windows';$env:GOARCH='arm64';$env:CGO_ENABLED='0'
    $env:GOCACHE=Join-Path $out 'go-cache';$env:GOTMPDIR=Join-Path $out 'go-tmp'
    $package=Join-Path $out 'package';$tools=Join-Path $out 'build-tools'
    foreach($path in @($tools,$env:GOCACHE,$env:GOTMPDIR)){New-Item -ItemType Directory -Path $path|Out-Null}
    foreach($name in @('bin','arm64','x86','data','indexes','build')){New-Item -ItemType Directory -Path (Join-Path $package $name)|Out-Null}
    $commit=(& git -C $repo rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0){throw 'Source commit unavailable.'}
    $status=@(& git -C $repo status --porcelain=v1 --untracked-files=all)
    if($LASTEXITCODE -ne 0){throw 'Source status unavailable.'}
    $sourcePaths=@(Get-LocalProductSourcePaths $repo $product)
    $sourceRecords=@($sourcePaths|ForEach-Object{Get-LocalProductFileRecord $repo $_})
    Write-LocalProductJson ([ordered]@{schema_version='yimecore-local-source-v1';git_commit=$commit;dirty=[bool]$status.Count;git_status=$status;files=$sourceRecords;scope='Standard product sources and explicit assets; no installed or lab payload.'}) (Join-Path $package 'build/source-manifest.json')
    foreach($asset in $product.assets){
        $source=Resolve-LocalProductChild $repo $asset.source
        & {Set-StrictMode -Off;& (Join-Path $repo 'tools/assert-data-source-boundary.ps1') -Path $source -InputId $asset.path}
        $destination=Resolve-LocalProductChild $package $asset.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    # Project the one product descriptor onto this explicitly supported platform.
    # The canonical x64 descriptor and all standard layout/data assets stay intact.
    $product.package_contract='yimecore-arm64-product-package-v1'
    $product.scope=[pscustomobject]@{computer_name=$scope.computer_name;target='windows-arm64';active_architectures=@('arm64','x86');tsf64_architecture='arm64x'}
    $product.identity.display_name_activation='Native ARM64 Runtime/Broker, shared ARM64X TSF for ARM64/x64 hosts, independent x86 TSF'
    Write-LocalProductJson $product (Join-Path $package 'local-product.json')
    $releases=@{}
    foreach($native in @(@{name='arm64';platform='ARM64'},@{name='x86';platform='Win32'},@{name='x64-test';platform='x64'})){
        $build=Join-Path $out ('native-'+$native.name)
        $args=@('-S',(Join-Path $repo 'YimeTextServiceExperiment'),'-B',$build,'-G',$generator,'-A',$native.platform,'-DYIME_LOCAL_PRODUCT=ON')
        if($native.name -eq 'arm64'){$args+='-DYIME_ARM64X_STAGE=ARM64'}
        & cmake @args 2>&1|Tee-Object -FilePath (Join-Path $out ('configure-'+$native.name+'.txt'))
        if($LASTEXITCODE -ne 0){throw ('CMake configure failed: '+$native.name)}
        & cmake --build $build --config Release --parallel 2>&1|Tee-Object -FilePath (Join-Path $out ('build-'+$native.name+'.txt'))
        if($LASTEXITCODE -ne 0){throw ('CMake build failed: '+$native.name)}
        $releases[$native.name]=Join-Path $build 'Release'
    }
    $mixedBuild=Join-Path $out 'native-arm64ec'
    $rsp=Join-Path $out 'native-arm64/arm64x/YimeTextServiceExperiment.rsp'
    & cmake -S (Join-Path $repo 'YimeTextServiceExperiment') -B $mixedBuild -G $generator -A ARM64EC -DYIME_LOCAL_PRODUCT=ON -DYIME_ARM64X_STAGE=ARM64EC "-DYIME_ARM64X_NATIVE_LINK_RSP=$rsp" 2>&1|Tee-Object -FilePath (Join-Path $out 'configure-arm64ec.txt')
    if($LASTEXITCODE -ne 0){throw 'ARM64EC configure failed.'}
    & cmake --build $mixedBuild --config Release --target YimeTextServiceExperiment --parallel 2>&1|Tee-Object -FilePath (Join-Path $out 'build-arm64ec.txt')
    if($LASTEXITCODE -ne 0){throw 'ARM64X link failed.'}
    foreach($arch in @('arm64','x86')){
        foreach($file in $product.native_binaries){
            $source=Join-Path $releases[$arch] $file
            if($arch -eq 'arm64' -and $file -eq 'YimeTextServiceExperiment.dll'){$source=Join-Path $mixedBuild ('Release/'+$file)}
            Copy-Item -LiteralPath $source -Destination (Join-Path $package ($arch+'/'+$file))
        }
    }
    foreach($arch in @('arm64','x64-test','x86')){
        $dllArch=if($arch -eq 'x86'){'x86'}else{'arm64'}
        Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $releases[$arch] 'YimeTextServiceContractTests.exe') -Arguments @((Join-Path $package ($dllArch+'/YimeTextServiceExperiment.dll'))) -BuildRoot $out -EvidenceRoot $out -LogName ('native-contract-'+$arch+'.txt')
        Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $releases[$arch] 'YimeFocusCancellationTests.exe') -BuildRoot $out -EvidenceRoot $out -LogName ('native-focus-'+$arch+'.txt')
    }
    Push-Location (Join-Path $repo 'go-backend')
    try {
        $goVersion=(& $GoExecutable version)-join ' '
        $goEnvironment=(& $GoExecutable env -json GOOS GOARCH GOHOSTOS GOHOSTARCH GOVERSION CGO_ENABLED GOENV GOFLAGS GOTOOLCHAIN GOWORK)-join "`n"|ConvertFrom-Json
        if($LASTEXITCODE -ne 0){throw 'Go toolchain identity unavailable.'}
        $sources=@($product.go_binaries|ForEach-Object{$_.source}|Sort-Object -Unique)
        $dependencies=@(& $GoExecutable list -deps @sources);if($LASTEXITCODE -ne 0){throw 'Runtime dependency enumeration failed.'}
        Assert-LocalProductDependencies $dependencies
        $coreDeps=@(& $GoExecutable list -deps ./cmd/yimebroker ./cmd/yimecore-trial-runtime ./input_methods/yime/yimecore ./input_methods/yime/engineapi)
        if($LASTEXITCODE -ne 0){throw 'Core dependency enumeration failed.'}
        Assert-LocalProductDependencies $coreDeps -Core
        $dependencies|Sort-Object -Unique|Set-Content -LiteralPath (Join-Path $package 'build/go-runtime-dependencies.txt') -Encoding UTF8
        Invoke-LocalProductIsolatedTestTool -Tool go -Arguments @('test','-count=1','./cmd/settings-tool','./cmd/yimecore-independence-audit','./cmd/yimecore-trial-runtime','./input_methods/yime/yimecore','./input_methods/yime/yimebroker') -BuildRoot $out -EvidenceRoot $out -LogName 'go-tests.txt'
        foreach($binary in $product.go_binaries){
            $args=@('build','-trimpath','-buildvcs=false','-o',(Resolve-LocalProductChild $package $binary.path))
            if($binary.gui){$args+=@('-ldflags','-H=windowsgui')}
            & $GoExecutable @args $binary.source
            if($LASTEXITCODE -ne 0){throw ('Go build failed: '+$binary.source)}
        }
        foreach($tool in @(@{name='IndexBuilder';source='./cmd/yimecore-index'},@{name='SpeechProductExporter';source='./cmd/yimecore-speech-admission'})){
            & $GoExecutable build -trimpath -buildvcs=false -o (Join-Path $tools ($tool.name+'.exe')) $tool.source
            if($LASTEXITCODE -ne 0){throw ('Build tool failed: '+$tool.name)}
        }
    } finally {Pop-Location}
    $indexEvidence=@()
    foreach($mode in @('full','variable','shorthand')){
        $index=Join-Path $package ('indexes/'+$mode+'.yidx')
        $report=Join-Path $out ('index-'+$mode+'.json')
        & (Join-Path $tools 'IndexBuilder.exe') -mode $mode -source (Join-Path $package ('data/yime_'+$mode+'.dict.yaml')) -output $index -manifest $report -allowed-source-root (Join-Path $package 'data') -allowed-output-root $out
        if($LASTEXITCODE -ne 0){throw ('Standard index failed: '+$mode)}
        $indexEvidence+=Get-Content -LiteralPath $report -Raw -Encoding UTF8|ConvertFrom-Json
        $repeat=Join-Path $out ('rebuild-'+$mode+'.yidx')
        & (Join-Path $tools 'IndexBuilder.exe') -mode $mode -source (Join-Path $package ('data/yime_'+$mode+'.dict.yaml')) -output $repeat -manifest (Join-Path $out ('rebuild-'+$mode+'.json')) -allowed-source-root (Join-Path $package 'data') -allowed-output-root $out
        if($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $index).Hash -ne (Get-FileHash -LiteralPath $repeat).Hash){throw ('Non-deterministic standard index: '+$mode)}
    }
    $speech=Add-LocalProductSpeechPayload -RepoRoot $repo -PackageRoot $package -BuildRoot $out -Exporter (Join-Path $tools 'SpeechProductExporter.exe') -AdmissionRoot $SpeechAdmissionRoot -SummarySHA256 $ExpectedSpeechAdmissionSummarySha256 -SourceInventorySHA256 $ExpectedSpeechSourceInventorySha256
    Write-LocalProductJson ([ordered]@{go_version=$goVersion;go_environment=$goEnvironment;generator=$generator;native_platforms=@('ARM64','ARM64EC','Win32');x64_test_host_only=$true;speech=$speech;indexes=$indexEvidence}) (Join-Path $package 'build/build-inputs.json')
    Write-LocalProductJson ([ordered]@{schema_version='yimecore-local-package-v1';package_contract=$product.package_contract;tool_version='yimecore-arm64-builder-v1';git_commit=$commit;scope='Identified ARM64 source build, ARM64X/x86 TSF, complete standard product assets; installed acceptance pending';files=@(Get-LocalProductPayloadRecords $package)}) (Join-Path $package 'package-manifest.json')
    & (Join-Path $package 'bin/YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $out 'independence-audit.json')
    if($LASTEXITCODE -ne 0){throw 'ARM64 product integrity/independence audit failed.'}
    $simple=Join-Path $out 'YimeCore-ARM64'
    & (Join-Path $repo 'installer/simple/Build-Package.ps1') -Product yimecore -Target windows-arm64 -PayloadRoot $package -OutputRoot $simple -Version ($product.version+'-arm64')
    if($LASTEXITCODE -ne 0){throw 'Simple ARM64 package failed.'}
    & (Join-Path $package 'bin/YimeCoreIndependenceAudit.exe') -package (Join-Path $simple 'payload') -output (Join-Path $out 'simple-payload-audit.json')
    if($LASTEXITCODE -ne 0){throw 'Complete simple-package payload differs from the audited source bundle.'}
    Assert-LocalProductSourceUnchanged $repo $sourceRecords
    Assert-LocalProductSourceSet $sourcePaths @(Get-LocalProductSourcePaths $repo $product)
    $passed=$true
} catch {$failure=$_.Exception.Message;throw}
finally {
    try {
        foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
        $after=Get-LocalProductProtectionEvidence -HashesOnly
        Write-LocalProductJson $after (Join-Path $out 'protection-after.json')
        $preserved=$null -ne $before -and ($before|ConvertTo-Json -Depth 30 -Compress) -ceq ($after|ConvertTo-Json -Depth 30 -Compress)
        Write-LocalProductJson ([ordered]@{schema_version='yimecore-arm64-product-build-v1';passed=[bool]($passed -and $preserved);generated_at=[DateTime]::UtcNow.ToString('o');failure=$failure;output_root=$out;registration_and_default_preserved=$preserved;installed=$false;registered_host_passed=$null;live_host_passed=$null;release_ready=$false}) (Join-Path $out 'summary.json')
        if(-not $preserved){throw 'Registration/default protection comparison failed.'}
    } finally {Stop-Transcript|Out-Null}
}
Write-Output ('PASS: complete ARM64 source package; CI, fixed package delivery and installed acceptance still required. '+$out)
}
