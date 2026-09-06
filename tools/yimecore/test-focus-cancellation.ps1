[CmdletBinding()]
param(
    [string]$OutputRoot,
    [ValidateSet('full','variable','shorthand')][string[]]$Modes = @('full','variable','shorthand')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$scope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = Join-Path $repoRoot '.tmp\yimecore-focus-cancellation'
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $allowedRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$out = [IO.Path]::GetFullPath($OutputRoot)
if (-not $out.StartsWith($allowedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $out)) {
    throw 'Focus cancellation tests require a new isolated output child.'
}
Assert-LocalProductPlainPath $out
$null = Get-Command cmake, go -ErrorAction Stop
if ($Modes.Count -eq 0 -or @($Modes | Select-Object -Unique).Count -ne $Modes.Count) {
    throw 'Select one or more distinct supported modes.'
}
$product = Get-LocalProductDescriptor (Join-Path $PSScriptRoot 'local-product.json')
New-Item -ItemType Directory -Path $out | Out-Null
$bin = Join-Path $out 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null
$sourceRoot = Join-Path $repoRoot 'YimeTextServiceExperiment'
$dataRoot = Join-Path $repoRoot 'go-backend\input_methods\yime\data'
$passed = $false
$failure = $null
$protectionBefore = $null
$protectionAfter = $null
$protectionError = $null
$sourceRecords = @()
$artifactRecords = @()
$runs = @()
$native = @{}
$brokerProcesses = @()
$directTsfExecuted = $false
$mockExecuted = $false
$nativeBuilt = @()
$testFixtures = [Collections.Generic.List[object]]::new()

function Get-ProtectionDigest {
    # Preserve the independent system view, but emit only its digest, not
    # registry contents, application names, user text, or private model data.
    $json = Get-LocalProductProtectionEvidence | ConvertTo-Json -Depth 30 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Invoke-TestTool([string]$Tool, [string[]]$Arguments, [string]$LogPath) {
    $testNames = @('YimeTextServiceContractTests.exe', 'YimeFocusCancellationTests.exe', 'YimeTsfCompositionTests.exe')
    $testName = Split-Path -Leaf $Tool
    if ($testName -notin $testNames) {
        & $Tool @Arguments 2>&1 | Tee-Object -FilePath $LogPath
        if ($LASTEXITCODE -ne 0) { throw "Tool failed with exit code $LASTEXITCODE; inspect $LogPath" }
        return
    }
    $testImage = [IO.Path]::GetFullPath($Tool)
    if (-not $testImage.StartsWith($out + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test executable must belong to this fresh source-validation output.'
    }
    Assert-LocalProductPlainPath $testImage
    $fixtureRoot = Join-Path $out ('fixtures\' + [guid]::NewGuid().ToString('N'))
    Assert-LocalProductPlainPath $fixtureRoot
    if (Test-Path -LiteralPath $fixtureRoot) { throw 'Test fixture already exists; never reuse private-state fixtures.' }
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $fixtureTemp = Join-Path $fixtureRoot 'temp'
    $fixtureLocal = Join-Path $fixtureRoot 'local-app-data'
    if ($fixtureTemp.Length -gt 120) { throw 'Test TEMP is too long for the native fixture state-file APIs.' }
    New-Item -ItemType Directory -Path $fixtureTemp, $fixtureLocal | Out-Null
    Assert-LocalProductPlainPath $fixtureTemp
    Assert-LocalProductPlainPath $fixtureLocal
    $environment = [ordered]@{ TEMP=$fixtureTemp; TMP=$fixtureTemp; LOCALAPPDATA=$fixtureLocal }
    $previousEnvironment = @{}
    foreach ($name in $environment.Keys) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $fixture = [ordered]@{
        executable=$testImage; fixture_root=$fixtureRoot; environment=$environment
        environment_isolated=$false; environment_restored=$false; executed=$false; exit_code=$null; passed=$false
        log=$LogPath; scope='Fresh per-invocation TEMP/TMP/LOCALAPPDATA; no live settings or earlier PID fixture reuse.'
    }
    $testFixtures.Add($fixture)
    try {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, [string]$environment[$name], 'Process')
        }
        foreach ($name in $environment.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $environment[$name]) {
                throw 'Test fixture environment could not be isolated.'
            }
        }
        $fixture.environment_isolated = $true
        $fixture.executed = $true
        & $Tool @Arguments 2>&1 | Tee-Object -FilePath $LogPath
        $fixture.exit_code = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) { throw "Tool failed with exit code $LASTEXITCODE; inspect $LogPath" }
        $fixture.passed = $true
    } finally {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
        }
        $restored = $true
        foreach ($name in $environment.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $previousEnvironment[$name]) { $restored = $false }
        }
        $fixture.environment_restored = $restored
        if (-not $restored) { throw 'Process-only test environment did not restore; stop this runner.' }
    }
}

function Wait-IsolatedBroker([Diagnostics.Process]$Process, [string]$ExpectedImage, [DateTime]$ExpectedStart, [string]$PipeName) {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        if ($Process.HasExited) { throw "Disposable Broker exited before readiness: $($Process.ExitCode)" }
        # Start-Process can return before its Process object's module metadata
        # is populated. Query a fresh object; an unavailable image is not proof
        # of identity and must not permit the pipe/test step.
        $current = Get-Process -Id $Process.Id -ErrorAction Stop
        try {
            $observedImage = $current.Path
            $observedStart = $current.StartTime
        } finally { $current.Dispose() }
        if ($observedStart.ToUniversalTime().Ticks -ne $ExpectedStart.ToUniversalTime().Ticks) {
            throw 'Disposable Broker start identity changed before readiness.'
        }
        if (-not $observedImage) {
            Start-Sleep -Milliseconds 50
            continue
        }
        if ($observedImage -ine $ExpectedImage) { throw 'Disposable Broker image did not match the freshly built executable.' }
        $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $PipeName.Substring('\\.\pipe\'.Length), [IO.Pipes.PipeDirection]::InOut)
        try {
            $pipe.Connect(100)
            return
        } catch [TimeoutException] {
            Start-Sleep -Milliseconds 50
        } finally { $pipe.Dispose() }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Disposable Broker pipe did not become ready.'
}

function Stop-IsolatedBroker([Diagnostics.Process]$Process, [string]$ExpectedImage, [DateTime]$ExpectedStart) {
    if ($Process.HasExited) { return }
    $current = Get-Process -Id $Process.Id -ErrorAction Stop
    try {
        if ($current.Path -ine $ExpectedImage -or $current.StartTime.ToUniversalTime().Ticks -ne $ExpectedStart.ToUniversalTime().Ticks) {
            throw 'Refusing to stop a process whose exact test image/start identity changed.'
        }
        # This is cleanup of the fresh, private, in-memory-only test Broker.
        # No installed Runtime/Broker or globally selected process is stopped.
        $current.Kill()
        if (-not $current.WaitForExit(10000)) { throw 'Owned disposable Broker did not exit.' }
    } finally { $current.Dispose() }
}

try {
    $protectionBefore = Get-ProtectionDigest
    $goEnvironment = (& go env -json GOOS GOARCH GOFLAGS GOWORK GOVERSION CGO_ENABLED) -join "`n" | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $goEnvironment.GOFLAGS -or
        ($goEnvironment.GOWORK -and $goEnvironment.GOWORK -ne 'off')) {
        throw 'Use native amd64 Go without external workspace overrides or ambient GOFLAGS.'
    }
    Write-LocalProductJson $goEnvironment (Join-Path $out 'go-environment.json')
    $sourcePaths = @(Get-LocalProductSourcePaths $repoRoot $product)
    $sourceRecords = @($sourcePaths | ForEach-Object { Get-LocalProductFileRecord $repoRoot $_ })
    Write-LocalProductJson $sourceRecords (Join-Path $out 'source-hashes.json')
    foreach ($mode in $Modes) {
        $dictionary = Join-Path $dataRoot ("yime_$mode.dict.yaml")
        & {
            # Existing boundary helper accesses FileInfo.Parent without strict
            # mode; preserve that calling convention, not a policy exception.
            Set-StrictMode -Off
            & (Join-Path $repoRoot 'tools\assert-data-source-boundary.ps1') -Path $dictionary -InputId ("focus-cancellation-$mode")
        }
    }
    foreach ($architecture in @('x64','x86')) {
        $platform = if ($architecture -eq 'x64') { 'x64' } else { 'Win32' }
        $build = Join-Path $out ("native-$architecture")
        Invoke-TestTool 'cmake' @('-S', $sourceRoot, '-B', $build, '-G', 'Visual Studio 17 2022', '-A', $platform, '-DYIME_LOCAL_PRODUCT=ON') (Join-Path $out "configure-$architecture.txt")
        Invoke-TestTool 'cmake' @('--build', $build, '--config', 'Release', '--parallel', '--target', 'YimeTextServiceExperiment', 'YimeTextServiceContractTests', 'YimeFocusCancellationTests', 'YimeTsfCompositionTests', 'YimeRegisteredHostTests') (Join-Path $out "build-$architecture.txt")
        $release = Join-Path $build 'Release'
        $native[$architecture] = $release
        $nativeBuilt += $architecture
        Invoke-TestTool (Join-Path $release 'YimeTextServiceContractTests.exe') @((Join-Path $release 'YimeTextServiceExperiment.dll')) (Join-Path $out "contract-$architecture.txt")
        $mockExecuted = $true
        Invoke-TestTool (Join-Path $release 'YimeFocusCancellationTests.exe') @() (Join-Path $out "focus-cancellation-mock-$architecture.txt")
    }
    Push-Location (Join-Path $repoRoot 'go-backend')
    try {
        Invoke-TestTool 'go' @('build', '-trimpath', '-buildvcs=false', '-o', (Join-Path $bin 'YimeBroker.exe'), './cmd/yimebroker') (Join-Path $out 'build-broker.txt')
        Invoke-TestTool 'go' @('build', '-trimpath', '-buildvcs=false', '-o', (Join-Path $bin 'YimeCoreIndex.exe'), './cmd/yimecore-index') (Join-Path $out 'build-indexer.txt')
    } finally { Pop-Location }
    $broker = Join-Path $bin 'YimeBroker.exe'
    foreach ($mode in $Modes) {
        $modeRoot = Join-Path $out $mode
        New-Item -ItemType Directory -Path $modeRoot | Out-Null
        $index = Join-Path $modeRoot 'index.yidx'
        $indexManifest = Join-Path $modeRoot 'index-build.json'
        Invoke-TestTool (Join-Path $bin 'YimeCoreIndex.exe') @('-mode', $mode, '-source', (Join-Path $dataRoot "yime_$mode.dict.yaml"), '-output', $index, '-manifest', $indexManifest, '-allowed-source-root', $dataRoot, '-allowed-output-root', $out) (Join-Path $modeRoot 'index-build.txt')
        $indexEvidence = Get-Content -LiteralPath $indexManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $indexEvidence.verified) { throw "Fresh $mode index did not verify." }
        $pipeName = '\\.\pipe\YimeBroker.FocusCancellation.' + [guid]::NewGuid().ToString('N')
        $arguments = '-index "{0}" -mode {1} -named-pipe "{2}"' -f $index, $mode, $pipeName
        $process = Start-Process -FilePath $broker -ArgumentList $arguments -WorkingDirectory $modeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $modeRoot 'broker-out.txt') -RedirectStandardError (Join-Path $modeRoot 'broker-err.txt')
        $started = $process.StartTime
        $record = [ordered]@{ mode=$mode; pid=$process.Id; image=$broker; started_at=$started.ToUniversalTime().ToString('o'); pipe=$pipeName; stopped=$false }
        $brokerProcesses += $record
        try {
            Wait-IsolatedBroker $process $broker $started $pipeName
            foreach ($architecture in @('x64','x86')) {
                $release = $native[$architecture]
                $longCode = if ($mode -eq 'full') { 'bjjjbjjjbjjj' } else { 'bjbjbj' }
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $directTsfExecuted = $true
                Invoke-TestTool (Join-Path $release 'YimeTsfCompositionTests.exe') @((Join-Path $release 'YimeTextServiceExperiment.dll'), $pipeName, $longCode) (Join-Path $modeRoot "tsf-$architecture.txt")
                $timer.Stop()
                $runs += [ordered]@{ mode=$mode; architecture=$architecture; passed=$true; elapsed_ms=$timer.Elapsed.TotalMilliseconds }
            }
        } finally {
            try {
                Stop-IsolatedBroker $process $broker $started
                $record.stopped = $true
            } finally { $process.Dispose() }
        }
    }
    Assert-LocalProductSourceUnchanged $repoRoot $sourceRecords
    Assert-LocalProductSourceSet $sourcePaths @(Get-LocalProductSourcePaths $repoRoot $product)
    $passed = $true
} catch {
    $failure = $_.Exception.Message
} finally {
    try { $protectionAfter = Get-ProtectionDigest } catch { $protectionError = $_.Exception.Message }
    $protected = $null -ne $protectionBefore -and $null -ne $protectionAfter -and $protectionBefore -ceq $protectionAfter
    $artifactFiles = @(Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -in @('.exe','.dll','.yidx') })
    $artifactRecords = @($artifactFiles | ForEach-Object { Get-LocalProductFileRecord $out $_.FullName.Substring($out.Length+1) })
    Write-LocalProductJson $artifactRecords (Join-Path $out 'artifact-hashes.json')
    Write-LocalProductJson @($testFixtures.ToArray()) (Join-Path $out 'test-fixtures.json')
    Write-LocalProductJson ([ordered]@{
        schema_version='yimecore-focus-cancellation-source-validation-v1'; generated_at=[DateTime]::UtcNow.ToString('o')
        passed=[bool]($passed -and $protected); failure=$failure; protection_error=$protectionError
        development_scope=$scope; current_product_identity=$product.identity; modes=@($Modes); runs=$runs
        protection_provider='StdRegProv'; protected_before_sha256=$protectionBefore; protected_after_sha256=$protectionAfter; protected_registration_and_default_unchanged=[bool]$protected
        broker_processes=$brokerProcesses; source_hashes='source-hashes.json'; artifact_hashes='artifact-hashes.json'
        test_fixture_evidence='test-fixtures.json'; test_executable_environment_isolation='per-invocation TEMP/TMP/LOCALAPPDATA under fresh output root, restored in finally'
        direct_test_language_bar_launchers='injected no-launch callbacks; not runtime autostart or tool-launch acceptance'
        source_validation_only=$true; direct_tsf_test_executed=$directTsfExecuted; cancellation_mock_test_executed=$mockExecuted; native_architectures_built=$nativeBuilt
        registered_host_test_executed=$false; registered_host_executable_build_only=[bool]($nativeBuilt.Count -gt 0)
        installed_candidate_changed=$false; live_host_acceptance_passed=$null; daily_use_accepted=$false; public_release_ready=$false
        durable_user_model_used=$false; installed_config_read=$false; user_text_recorded=$false
        note='Fresh current-identity x64/x86 source and direct in-process TSF tests with approved dictionaries and disposable in-memory Broker only. No registration, install, default-input change or production/user data mutation. Registered/live-host acceptance remains pending.'
    }) (Join-Path $out 'summary.json')
}
if (-not $passed -or -not $protected) { throw "Focus cancellation source validation failed; preserved evidence: $out; $failure; $protectionError" }
Write-Output "PASS: isolated source validation only. Evidence: $out"
