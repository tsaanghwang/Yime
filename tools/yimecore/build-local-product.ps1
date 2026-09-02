[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$scope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$descriptorPath = Join-Path $PSScriptRoot 'local-product.json'
$product = Get-LocalProductDescriptor $descriptorPath
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot ('.tmp\yimecore-local-product\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$out = New-LocalProductBuildRoot $repoRoot $OutputRoot
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt') | Out-Null
$passed = $false
$before = $null
try {
    $before = Get-LocalProductProtectionEvidence
    Write-LocalProductJson $before (Join-Path $out 'protection-before.json')
    $package = Join-Path $out 'package'
    foreach ($directory in @('bin', 'x64', 'indexes', 'data', 'build')) {
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

    $nativeBuild = Join-Path $out 'native-x64'
    & cmake -S (Join-Path $repoRoot 'YimeTextServiceExperiment') -B $nativeBuild -G 'Visual Studio 17 2022' -A x64 -DYIME_LOCAL_PRODUCT=ON
    if ($LASTEXITCODE -ne 0) { throw 'Native x64 configure failed' }
    & cmake --build $nativeBuild --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Native x64 build failed' }
    $release = Join-Path $nativeBuild 'Release'
    & (Join-Path $release 'YimeTextServiceContractTests.exe') (Join-Path $release 'YimeTextServiceExperiment.dll') 2>&1 |
        Tee-Object -LiteralPath (Join-Path $out 'native-contract.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Native contract failed' }
    foreach ($file in $product.native_binaries) {
        if ($file -notmatch '^Yime[A-Za-z]+\.(dll|exe)$') { throw "Unexpected native target: $file" }
        Copy-Item -LiteralPath (Join-Path $release $file) -Destination (Join-Path $package "x64\$file")
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
        & go test ./cmd/yimecore-independence-audit ./cmd/yimecore-trial-runtime ./input_methods/yime/yimecore ./input_methods/yime/yimebroker 2>&1 |
            Tee-Object -LiteralPath (Join-Path $out 'go-tests.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Local product Go regressions failed' }
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
    $nativeCompiler = @(Get-ChildItem -LiteralPath (Join-Path $nativeBuild 'CMakeFiles') -Filter CMakeCXXCompiler.cmake -Recurse -File |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Encoding UTF8 } | Where-Object { $_ -match 'CMAKE_CXX_COMPILER(_VERSION|_ID|_ARCHITECTURE_ID)? ' } |
        ForEach-Object { Convert-LocalProductPlainText $_ })
    $inputs = [ordered]@{
        schema_version = 'yimecore-local-build-inputs-v1'; product_version = $product.version
        source_manifest_sha256 = $sourceHash; go_version = $goVersion; go_environment = $goEnvironment
        go_flags = @('-trimpath', '-buildvcs=false'); cmake_version = @(& cmake --version)[0]
        native_generator = 'Visual Studio 17 2022'; native_platform = 'x64'; native_compiler = $nativeCompiler
        index_builds = $indexEvidence; indexes_rebuilt_byte_identical = $true
        source_archive_sha256 = (Get-FileHash -LiteralPath (Join-Path $out 'source-snapshot.zip')).Hash.ToLowerInvariant()
        reproducibility = 'Go trimpath and explicit source content; indexes verified twice. PE/linker timestamps, archive timestamps, generated metadata and absolute build evidence are not claimed byte reproducible.'
        installed_package_used_as_input = $false
    }
    Write-LocalProductJson $inputs (Join-Path $package 'build\build-inputs.json')
    $manifest = [ordered]@{
        tool_version = 'yimecore-local-builder-v1'; package_contract = $product.package_contract
        product_version = $product.version; package_id = "yimecore-local-$($product.version)-$($sourceHash.Substring(0,12))"
        generated_at = [DateTime]::UtcNow.ToString('o'); git_commit = $commit
        scope = 'MYCOMPUTER native x64 local product candidate; native acceptance pending; frozen targets untouched'
        development_scope = $scope; source_manifest_sha256 = $sourceHash
        files = @(Get-LocalProductPayloadRecords $package)
    }
    Write-LocalProductJson $manifest (Join-Path $package 'package-manifest.json')
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $out 'independence-audit.json')
    if ($LASTEXITCODE -ne 0) { throw 'New local runtime bundle independence/contract audit failed' }
    & (Join-Path $PSScriptRoot 'test-local-product-package.ps1') -PackageRoot $package -OutputRoot (Join-Path $out 'package-verification')
    & (Join-Path $PSScriptRoot 'test-local-product-runtime.ps1') -PackageRoot $package -OutputRoot (Join-Path $out 'runtime-verification') `
        -MultimodeVerifier (Join-Path $buildTools 'MultimodeVerifier.exe') -TsfTest (Join-Path $release 'YimeTsfCompositionTests.exe')
    Assert-LocalProductSourceUnchanged $repoRoot $sourceRecords
    Assert-LocalProductSourceSet $paths @(Get-LocalProductSourcePaths $repoRoot $product)
    # Re-audit after execution: runtime/test output must not mutate package payload.
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $out 'independence-after-tests.json')
    if ($LASTEXITCODE -ne 0) { throw 'Package changed during verification' }
    $passed = $true
} finally {
    try {
        $after = Get-LocalProductProtectionEvidence
        Write-LocalProductJson $after (Join-Path $out 'protection-after.json')
        $preserved = ($before | ConvertTo-Json -Depth 30 -Compress) -ceq ($after | ConvertTo-Json -Depth 30 -Compress)
        Write-LocalProductJson ([ordered]@{
            schema_version = 'yimecore-local-build-result-v1'; passed = [bool]($passed -and $preserved)
            registration_and_default_preserved = $preserved; output_root = $out
            installable = [bool]$product.installable; local_product_ready = $false; public_release_ready = $false
            completed_scope = 'Source-built x64 product candidate and isolated tests, not installed host acceptance'
            next_step = 'Native same-user install, medium-token runtime, data restore, rollback and host acceptance'
        }) (Join-Path $out 'summary.json')
        if (-not $preserved) { throw 'System registration/default changed during build; review before/after evidence' }
    } finally { Stop-Transcript | Out-Null }
}
Write-Output "PASS: source-built native x64 local product candidate (native acceptance pending). Evidence: $out"
