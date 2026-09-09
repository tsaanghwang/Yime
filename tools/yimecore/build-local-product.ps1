[CmdletBinding()]
param([string]$OutputRoot,[string]$SpeechAdmissionRoot,[string]$ExpectedSpeechAdmissionSummarySha256,[string]$ExpectedSpeechSourceInventorySha256)

$ErrorActionPreference = 'Stop'
function Assert-LocalProductMaintenanceHealthBuildInputs($Product) {
    $declarations=@($Product.PSObject.Properties|Where-Object {$_.Name -ieq 'maintenance_health'})
    if($declarations.Count -eq 0){return $false} # Existing descriptors keep their original catalog.
    if($declarations.Count -ne 1 -or $declarations[0].Name -cne 'maintenance_health'){
        throw 'Maintenance health declaration must use its canonical field name.'
    }
    $health=$declarations[0].Value
    if($health -isnot [pscustomobject] -or @($health.PSObject.Properties).Count -ne 2 -or
        @($health.PSObject.Properties.Name) -cnotcontains 'protocol' -or
        @($health.PSObject.Properties.Name) -cnotcontains 'required_on_start' -or
        $health.protocol -isnot [string] -or $health.protocol -cne 'yimecore-maintenance-health-v1' -or
        $health.required_on_start -isnot [bool] -or -not $health.required_on_start -or
        $Product.package_contract -cne 'yimecore-local-product-package-v1' -or
        $Product.installable -isnot [bool] -or -not $Product.installable){
        throw 'Declared maintenance health requires the fixed protocol and literal required_on_start true in an installable package.'
    }
    # Preserve the process observer's existing relative source path and bytes.
    # This is a repository source copied inside this package, not an installed
    # Rime/PIME dependency or a lookup outside the candidate.
    $required=[ordered]@{
        'maintenance/local-product-runtime.ps1'='tools/yimecore/local-product-runtime.ps1'
        'maintenance/native-maintenance-processes.psm1'='tools/yimecore/native-maintenance-processes.psm1'
        'maintenance/native-maintenance-process-facts.cs'='tools/yimecore/native-maintenance-process-facts.cs'
        'dual-product/rime-pime-dp1u-native-facts.cs'='tools/dual-product/rime-pime-dp1u-native-facts.cs'
        'maintenance/native-maintenance-health.psm1'='tools/yimecore/native-maintenance-health.psm1'
        'maintenance/native-maintenance-health-client.cs'='tools/yimecore/native-maintenance-health-client.cs'
    }
    if($Product.maintenance_assets -isnot [array]){throw 'Declared health requires an explicit maintenance asset array.'}
    foreach($path in $required.Keys){
        $matches=@($Product.maintenance_assets|Where-Object {$_.path -is [string] -and $_.path -ceq $path})
        if($matches.Count -ne 1 -or $matches[0].source -isnot [string] -or $matches[0].source -cne $required[$path]){
            throw "Declared health lacks its exact self-contained helper source: $path"
        }
    }
    return $true
}
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
. (Join-Path $PSScriptRoot 'local-product-speech-build.ps1')
. (Join-Path $PSScriptRoot 'local-product-test-isolation.ps1')
$scope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$descriptorPath = Join-Path $PSScriptRoot 'local-product.json'
$product = Get-LocalProductDescriptor $descriptorPath
$maintenanceHealthRequested = Assert-LocalProductMaintenanceHealthBuildInputs $product
$speechRequested = Assert-LocalProductSpeechBuildInputs $product $SpeechAdmissionRoot $ExpectedSpeechAdmissionSummarySha256 $ExpectedSpeechSourceInventorySha256
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot ('.tmp\yimecore-local-product\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$out = New-LocalProductBuildRoot $repoRoot $OutputRoot
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt') | Out-Null
$passed = $false
$before = $null
try {
    $before = Get-LocalProductProtectionEvidence -HashesOnly
    Write-LocalProductJson $before (Join-Path $out 'protection-before.json')
    & (Join-Path $PSScriptRoot 'test-local-registry-preservation.ps1') 2>&1 |
        Tee-Object -LiteralPath (Join-Path $out 'registry-preservation.txt')
    $package = Join-Path $out 'package'
    foreach ($directory in @('bin', 'x64', 'x86', 'indexes', 'data', 'build')) {
        New-Item -ItemType Directory -Path (Join-Path $package $directory) -Force | Out-Null
    }
    $buildTools = Join-Path $out 'build-tools'
    New-Item -ItemType Directory -Path $buildTools | Out-Null

    # Capture dirty and untracked source content, not merely HEAD. No old package
    # or runtime-config.json is ever used as a build input.
    $commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit' }
    $status = @(& git -C $repoRoot -c core.quotepath=false status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify dirty source' }
    $paths = @(Get-LocalProductSourcePaths $repoRoot $product)
    $sourceRecords = @($paths | ForEach-Object { Get-LocalProductFileRecord $repoRoot $_ })
    $sourceManifest = [ordered]@{
        schema_version = 'yimecore-local-source-v1'; git_commit = $commit
        dirty = [bool]($status.Count -gt 0); git_status = $status; files = $sourceRecords
        scope = 'Build source plus explicit generated data; deleted paths recorded in git_status. No installed/user data.'
    }
    $sourceManifestPath = Join-Path $package 'build\source-manifest.json'
    Write-LocalProductJson $sourceManifest $sourceManifestPath
    $sourceHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    # Git writes its binary-safe patch itself; no PowerShell encoding conversion.
    $patchPath = Join-Path $out 'working-tree.patch'
    & git -C $repoRoot diff --binary --no-ext-diff "--output=$patchPath" HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Could not preserve working-tree patch' }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open((Join-Path $out 'source-snapshot.zip'), [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($record in $sourceRecords) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,
                (Resolve-LocalProductChild $repoRoot $record.path), $record.path,
                [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $zip.Dispose() }

    foreach ($asset in @($product.assets) + @($product.maintenance_assets)) {
        $source = Resolve-LocalProductChild $repoRoot $asset.source
        # The existing data-boundary policy is mandatory for each data input.
        & {
            # The existing boundary script predates strict-mode FileInfo access.
            # Isolate that calling convention; do not weaken its path policy.
            Set-StrictMode -Off
            & (Join-Path $repoRoot 'tools\assert-data-source-boundary.ps1') -Path $source -InputId $asset.path
        }
        $destination = Resolve-LocalProductChild $package $asset.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    Copy-Item -LiteralPath $descriptorPath -Destination (Join-Path $package 'local-product.json')

    $nativeReleases = @{}
    $nativeBuilds = @{}
    foreach ($native in @(
        [ordered]@{ name='x64'; platform='x64' },
        [ordered]@{ name='x86'; platform='Win32' }
    )) {
        $name = [string]$native.name
        $nativeBuild = Join-Path $out "native-$name"
        & cmake -S (Join-Path $repoRoot 'YimeTextServiceExperiment') -B $nativeBuild `
            -G 'Visual Studio 17 2022' -A ([string]$native.platform) -DYIME_LOCAL_PRODUCT=ON
        if ($LASTEXITCODE -ne 0) { throw "Native $name configure failed" }
        & cmake --build $nativeBuild --config Release --parallel
        if ($LASTEXITCODE -ne 0) { throw "Native $name build failed" }
        $release = Join-Path $nativeBuild 'Release'
        Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $release 'YimeTextServiceContractTests.exe') `
            -Arguments @((Join-Path $release 'YimeTextServiceExperiment.dll')) `
            -BuildRoot $out -EvidenceRoot $out -LogName "native-contract-$name.txt"
        Invoke-LocalProductIsolatedTestTool -Tool (Join-Path $release 'YimeFocusCancellationTests.exe') `
            -BuildRoot $out -EvidenceRoot $out -LogName "native-focus-cancellation-$name.txt"
        foreach ($file in $product.native_binaries) {
            if ($file -notmatch '^Yime[A-Za-z]+\.(dll|exe)$') { throw "Unexpected native target: $file" }
            Copy-Item -LiteralPath (Join-Path $release $file) -Destination (Join-Path $package "$name\$file")
        }
        $nativeBuilds[$name] = $nativeBuild
        $nativeReleases[$name] = $release
    }

    Push-Location (Join-Path $repoRoot 'go-backend')
    try {
        $goVersion = (& go version) -join ' '
        $goEnvironment = (& go env -json GOOS GOARCH GOVERSION CGO_ENABLED GOAMD64 GOFLAGS GOTOOLCHAIN GOWORK) -join "`n" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot capture Go toolchain' }
        # Reject ambient build flags rather than silently changing the environment.
        if ($goEnvironment.GOFLAGS) { throw 'Use an empty GOFLAGS for an attributable local product build' }
        if ($goEnvironment.GOWORK -and $goEnvironment.GOWORK -ne 'off') { throw 'External Go workspace overrides are not allowed for this build' }
        $commandSources = @($product.go_binaries | Where-Object { $_.source.StartsWith('./cmd/') } | ForEach-Object { $_.source } | Sort-Object -Unique)
        $dependencies = @(& go list -deps @commandSources)
        if ($LASTEXITCODE -ne 0) { throw 'Go runtime dependency enumeration failed' }
        Assert-LocalProductDependencies $dependencies
        $coreDependencies = @(& go list -deps ./cmd/yimebroker ./cmd/yimecore-trial-runtime ./input_methods/yime/yimecore ./input_methods/yime/engineapi)
        if ($LASTEXITCODE -ne 0) { throw 'Core dependency enumeration failed' }
        Assert-LocalProductDependencies $coreDependencies -Core
        $coreDependencies | Set-Content -LiteralPath (Join-Path $out 'core-dependencies.txt') -Encoding UTF8
        $dependencies | Sort-Object -Unique | Set-Content -LiteralPath (Join-Path $package 'build\go-runtime-dependencies.txt') -Encoding UTF8
        Invoke-LocalProductIsolatedTestTool -Tool go -Arguments @('test', '-count=1', './cmd/settings-tool',
            './cmd/yimecore-independence-audit', './cmd/yimecore-trial-runtime',
            './input_methods/yime/yimecore', './input_methods/yime/yimebroker') `
            -BuildRoot $out -EvidenceRoot $out -LogName 'go-tests.txt'
        foreach ($binary in $product.go_binaries) {
            $buildArgs = @('build', '-trimpath', '-buildvcs=false', '-o', (Resolve-LocalProductChild $package $binary.path))
            if ($binary.gui) { $buildArgs += @('-ldflags', '-H=windowsgui') }
            & go @buildArgs $binary.source
            if ($LASTEXITCODE -ne 0) { throw "Go build failed: $($binary.source)" }
        }
        & go build -trimpath -buildvcs=false -o (Join-Path $buildTools 'IndexBuilder.exe') ./cmd/yimecore-index
        if ($LASTEXITCODE -ne 0) { throw 'Index builder failed' }
        & go build -trimpath -buildvcs=false -o (Join-Path $buildTools 'MultimodeVerifier.exe') ./cmd/yimebroker-multimode-experiment
        if ($LASTEXITCODE -ne 0) { throw 'Multimode verifier build failed' }
        if ($speechRequested) {
            & go build -trimpath -buildvcs=false -o (Join-Path $buildTools 'SpeechProductExporter.exe') ./cmd/yimecore-speech-admission
            if ($LASTEXITCODE -ne 0) { throw 'Build-only speech exporter build failed' }
        }
    } finally { Pop-Location }

    $indexEvidence = @()
    foreach ($mode in @('full', 'variable', 'shorthand')) {
        $indexPath = Join-Path $package "indexes\$mode.yidx"
        $indexReport = Join-Path $out "index-$mode.json"
        & (Join-Path $buildTools 'IndexBuilder.exe') -mode $mode -source (Join-Path $package "data\yime_$mode.dict.yaml") `
            -output $indexPath -manifest $indexReport -allowed-source-root (Join-Path $package 'data') -allowed-output-root $out
        if ($LASTEXITCODE -ne 0) { throw "Fresh index build failed: $mode" }
        $indexEvidence += Get-Content -LiteralPath $indexReport -Raw -Encoding UTF8 | ConvertFrom-Json
        # A second independent write proves the index bytes are deterministic.
        $repeat = Join-Path $out "rebuild-$mode.yidx"
        & (Join-Path $buildTools 'IndexBuilder.exe') -mode $mode -source (Join-Path $package "data\yime_$mode.dict.yaml") `
            -output $repeat -manifest (Join-Path $out "rebuild-$mode.json") -allowed-source-root (Join-Path $package 'data') -allowed-output-root $out
        if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $repeat).Hash -ne (Get-FileHash -LiteralPath $indexPath).Hash) {
            throw "Index rebuild not byte-identical: $mode"
        }
    }
    $speechBinding = $null
    if ($speechRequested) {
        $speechBinding = Add-LocalProductSpeechPayload -RepoRoot $repoRoot -PackageRoot $package -BuildRoot $out `
            -Exporter (Join-Path $buildTools 'SpeechProductExporter.exe') -AdmissionRoot $SpeechAdmissionRoot `
            -SummarySHA256 $ExpectedSpeechAdmissionSummarySha256 -SourceInventorySHA256 $ExpectedSpeechSourceInventorySha256
    }
    $nativePlatforms = @()
    foreach ($native in @(
        [ordered]@{ name='x64'; platform='x64' },
        [ordered]@{ name='x86'; platform='Win32' }
    )) {
        $nativeCompiler = @(Get-ChildItem -LiteralPath (Join-Path $nativeBuilds[[string]$native.name] 'CMakeFiles') `
            -Filter CMakeCXXCompiler.cmake -Recurse -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Encoding UTF8 } |
            Where-Object { $_ -match 'CMAKE_CXX_COMPILER(_VERSION|_ID|_ARCHITECTURE_ID)? ' } |
            ForEach-Object { Convert-LocalProductPlainText $_ })
        $nativePlatforms += [ordered]@{ name=[string]$native.name; cmake_platform=[string]$native.platform;
            compiler=$nativeCompiler }
    }
    $inputs = [ordered]@{
        schema_version = 'yimecore-local-build-inputs-v1'; product_version = $product.version
        source_manifest_sha256 = $sourceHash; go_version = $goVersion; go_environment = $goEnvironment
        go_flags = @('-trimpath', '-buildvcs=false'); cmake_version = @(& cmake --version)[0]
        native_generator = 'Visual Studio 17 2022'; native_platforms = $nativePlatforms
        index_builds = $indexEvidence; indexes_rebuilt_byte_identical = $true
        source_archive_sha256 = (Get-FileHash -LiteralPath (Join-Path $out 'source-snapshot.zip')).Hash.ToLowerInvariant()
        reproducibility = 'Go trimpath and explicit source content; indexes verified twice. PE/linker timestamps, archive timestamps, generated metadata and absolute build evidence are not claimed byte reproducible.'
        installed_package_used_as_input = $false
    }
    if ($speechRequested) { $inputs.speech = $speechBinding }
    Write-LocalProductJson $inputs (Join-Path $package 'build\build-inputs.json')
    $manifest = [ordered]@{
        tool_version = 'yimecore-local-builder-v1'; package_contract = $product.package_contract
        product_version = $product.version; package_id = "yimecore-local-$($product.version)-$($sourceHash.Substring(0,12))"
        generated_at = [DateTime]::UtcNow.ToString('o'); git_commit = $commit
        scope = 'MYCOMPUTER native x64 runtime with current-identity x64 and x86 TSF surfaces; installed acceptance pending; frozen targets untouched'
        development_scope = $scope; source_manifest_sha256 = $sourceHash
        files = @(Get-LocalProductPayloadRecords $package)
    }
    Write-LocalProductJson $manifest (Join-Path $package 'package-manifest.json')
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $out 'independence-audit.json')
    if ($LASTEXITCODE -ne 0) { throw 'New local runtime bundle independence/contract audit failed' }
    & (Join-Path $PSScriptRoot 'test-local-product-package.ps1') -PackageRoot $package -OutputRoot (Join-Path $out 'package-verification')
    & (Join-Path $PSScriptRoot 'test-local-product-runtime.ps1') -PackageRoot $package -OutputRoot (Join-Path $out 'runtime-verification') -BuildRoot $out `
        -MultimodeVerifier (Join-Path $buildTools 'MultimodeVerifier.exe') -TsfTests @{
            x64=(Join-Path $nativeReleases['x64'] 'YimeTsfCompositionTests.exe')
            x86=(Join-Path $nativeReleases['x86'] 'YimeTsfCompositionTests.exe')
        }
    Assert-LocalProductSourceUnchanged $repoRoot $sourceRecords
    Assert-LocalProductSourceSet $paths @(Get-LocalProductSourcePaths $repoRoot $product)
    # Re-audit after execution: runtime/test output must not mutate package payload.
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $out 'independence-after-tests.json')
    if ($LASTEXITCODE -ne 0) { throw 'Package changed during verification' }
    $passed = $true
} finally {
    try {
        $after = Get-LocalProductProtectionEvidence -HashesOnly
        Write-LocalProductJson $after (Join-Path $out 'protection-after.json')
        $preserved = ($before | ConvertTo-Json -Depth 30 -Compress) -ceq ($after | ConvertTo-Json -Depth 30 -Compress)
        $resultPassed = [bool]($passed -and $preserved)
        # The descriptor records the requested product type. A result describes
        # this build's artifact, which is not installable after any failed gate.
        $requestedInstallable = [bool]($product.installable -is [bool] -and $product.installable)
        $artifactInstallable = [bool]($resultPassed -and $requestedInstallable)
        Write-LocalProductJson ([ordered]@{
            schema_version = 'yimecore-local-build-result-v1'; passed = $resultPassed
            registration_and_default_preserved = $preserved; output_root = $out
            requested_installable = $requestedInstallable; installable = $artifactInstallable
            local_product_ready = $false; public_release_ready = $false
            completed_scope = if ($resultPassed) {
                'Source-built x64 runtime plus x64/x86 TSF candidate and isolated tests, not installed host acceptance'
            } else { 'Build or protection gates incomplete; no installable candidate claimed' }
            next_step = if ($artifactInstallable) {
                'Native same-user dual-architecture install, medium-token runtime, data restore, rollback and x64/x86 host acceptance'
            } elseif ($resultPassed) { 'Review the verified runtime bundle; this output is not an installable product' }
            else { 'Review failure evidence, correct the build issue and rebuild into fresh output; do not install this output' }
        }) (Join-Path $out 'summary.json')
        if (-not $preserved) { throw 'System registration/default changed during build; review before/after evidence' }
    } finally { Stop-Transcript | Out-Null }
}
Write-Output "PASS: source-built x64 runtime plus x64/x86 TSF local product candidate (installed acceptance pending). Evidence: $out"
