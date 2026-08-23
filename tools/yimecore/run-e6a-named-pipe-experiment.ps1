[CmdletBinding()]
param(
    [string]$OutputRoot,
    [int]$IterationsPerClient = 2000
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6a\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-A evidence must stay under $allowedRoot"
}
if ($IterationsPerClient -lt 1) { throw 'IterationsPerClient must be positive.' }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$testLog = Join-Path $outputDir 'go-test.txt'
$binDir = Join-Path $outputDir 'bin'
$buildDir = Join-Path $outputDir 'cpp-build'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$indexTool = Join-Path $binDir 'yimecore-index.exe'
$brokerPath = Join-Path $binDir 'YimeBroker.exe'

Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./input_methods/yime/yimebroker ./cmd/yimebroker -count=1 2>&1 | Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E6-A Go tests failed; see $testLog" }
    & go test ./input_methods/yime -run '^TestNativeBackendKeepsRimeOwnedCandidatePaging$' -count=1 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "Native paging ownership guard failed; see $testLog" }
    & go vet ./input_methods/yime/yimebroker ./cmd/yimebroker 2>&1 | Tee-Object -FilePath $testLog -Append
    if ($LASTEXITCODE -ne 0) { throw "E6-A go vet failed; see $testLog" }
    & go build -trimpath -o $indexTool ./cmd/yimecore-index
    if ($LASTEXITCODE -ne 0) { throw 'Could not build yimecore-index.' }
    & go build -trimpath -o $brokerPath ./cmd/yimebroker
    if ($LASTEXITCODE -ne 0) { throw 'Could not build YimeBroker.' }
}
finally {
    Pop-Location
}

$probeSource = Join-Path $repoRoot 'tools\yimecore\e6a'
$probeByArchitecture = [ordered]@{}
foreach ($architecture in @([ordered]@{ name = 'x64'; cmake = 'x64' }, [ordered]@{ name = 'x86'; cmake = 'Win32' })) {
    $architectureBuild = Join-Path $buildDir $architecture.name
    & cmake -S $probeSource -B $architectureBuild -A $architecture.cmake 2>&1 | Tee-Object -FilePath (Join-Path $outputDir ("cmake-{0}.txt" -f $architecture.name))
    if ($LASTEXITCODE -ne 0) { throw "Could not configure $($architecture.name) C++ probe." }
    & cmake --build $architectureBuild --config Release 2>&1 | Tee-Object -FilePath (Join-Path $outputDir ("build-{0}.txt" -f $architecture.name))
    if ($LASTEXITCODE -ne 0) { throw "Could not build $($architecture.name) C++ probe." }
    $targetDir = Join-Path $binDir $architecture.name
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $target = Join-Path $targetDir 'YimeBrokerPipeProbe.exe'
    Copy-Item -LiteralPath (Join-Path $architectureBuild 'Release\YimeBrokerPipeProbe.exe') -Destination $target
    $probeByArchitecture[$architecture.name] = $target
}

function Start-ExperimentBroker([string]$IndexPath, [string]$Mode, [string]$PipeName, [string]$ErrorPath) {
    return Start-Process -FilePath $brokerPath -ArgumentList @(
        '-index', $IndexPath, '-mode', $Mode, '-named-pipe', $PipeName,
        '-pipe-max-connections', '16', '-pipe-max-connections-per-client', '4'
    ) -PassThru -WindowStyle Hidden -RedirectStandardError $ErrorPath
}

function Stop-ExperimentProcess([Diagnostics.Process]$Process) {
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
        $Process.WaitForExit()
    }
}

function Wait-ExperimentProcess([Diagnostics.Process]$Process, [string]$Label, [int]$TimeoutMilliseconds = 60000) {
    if (-not $Process.WaitForExit($TimeoutMilliseconds)) {
        Stop-ExperimentProcess $Process
        throw "$Label timed out after $TimeoutMilliseconds ms."
    }
    if ($Process.ExitCode -ne 0) { throw "$Label failed with exit code $($Process.ExitCode)." }
}

$definitions = @(
    [ordered]@{ mode = 'full'; source = 'yime_full.dict.yaml' },
    [ordered]@{ mode = 'variable'; source = 'yime_variable.dict.yaml' },
    [ordered]@{ mode = 'shorthand'; source = 'yime_shorthand.dict.yaml' }
)
$modeResults = @()
foreach ($definition in $definitions) {
    $mode = $definition.mode
    $modeDir = Join-Path $outputDir $mode
    New-Item -ItemType Directory -Force -Path $modeDir | Out-Null
    $indexPath = Join-Path $modeDir 'index.yidx'
    $indexBuildPath = Join-Path $modeDir 'index-build.json'
    & $indexTool -mode $mode -source (Join-Path $dataRoot $definition.source) -output $indexPath -manifest $indexBuildPath `
        -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Index build failed for $mode" }
    $indexBuild = Get-Content -LiteralPath $indexBuildPath -Raw | ConvertFrom-Json

    $pipeName = "\\.\pipe\YimeBroker-e6a-$mode-$PID"
    $brokerError = Join-Path $modeDir 'broker-before-restart.err'
    $broker = Start-ExperimentBroker $indexPath $mode $pipeName $brokerError
    try {
        $clients = @()
        for ($clientIndex = 0; $clientIndex -lt 4; $clientIndex++) {
            $architecture = if (($clientIndex % 2) -eq 0) { 'x64' } else { 'x86' }
            $clientOutput = Join-Path $modeDir ("replay-{0}-{1}.json" -f $architecture, $clientIndex)
            $clientError = Join-Path $modeDir ("replay-{0}-{1}.err" -f $architecture, $clientIndex)
            $process = Start-Process -FilePath $probeByArchitecture[$architecture] -ArgumentList @(
                '--pipe', $pipeName, '--output', $clientOutput, '--scenario', 'replay',
                '--iterations', $IterationsPerClient, '--code', '2jru'
            ) -PassThru -WindowStyle Hidden -RedirectStandardError $clientError
            $clients += [ordered]@{ process = $process; output = $clientOutput; architecture = $architecture }
        }
        foreach ($client in $clients) { Wait-ExperimentProcess $client.process "$mode $($client.architecture) replay" }

        $sessionFile = Join-Path $modeDir 'owner-session.txt'
        $releaseFile = Join-Path $modeDir 'owner-release'
        $ownerOutput = Join-Path $modeDir 'owner.json'
        $owner = Start-Process -FilePath $probeByArchitecture.x64 -ArgumentList @(
            '--pipe', $pipeName, '--output', $ownerOutput, '--scenario', 'owner',
            '--session-file', $sessionFile, '--release-file', $releaseFile
        ) -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $modeDir 'owner.err')
        $sessionDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $sessionFile)) {
            if ($owner.HasExited) { throw "$mode identity owner exited before publishing its session." }
            if ([DateTime]::UtcNow -ge $sessionDeadline) { throw "$mode identity owner did not publish its session." }
            Start-Sleep -Milliseconds 10
        }
        $stolenSession = (Get-Content -LiteralPath $sessionFile -Raw).Trim()
        $intruderOutput = Join-Path $modeDir 'intruder.json'
        $intruder = Start-Process -FilePath $probeByArchitecture.x86 -ArgumentList @(
            '--pipe', $pipeName, '--output', $intruderOutput, '--scenario', 'intruder', '--stolen-session', $stolenSession
        ) -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $modeDir 'intruder.err')
        Wait-ExperimentProcess $intruder "$mode cross-process identity probe"
        New-Item -ItemType File -Path $releaseFile | Out-Null
        Wait-ExperimentProcess $owner "$mode identity owner"
    }
    finally {
        Stop-ExperimentProcess $broker
        if ($null -ne $owner) { Stop-ExperimentProcess $owner }
    }

    $restartStarted = [Diagnostics.Stopwatch]::StartNew()
    $restartBrokerError = Join-Path $modeDir 'broker-after-restart.err'
    $broker = Start-ExperimentBroker $indexPath $mode $pipeName $restartBrokerError
    try {
        $restartOutput = Join-Path $modeDir 'after-restart.json'
        & $probeByArchitecture.x64 --pipe $pipeName --output $restartOutput --scenario replay --iterations 200 --code 2jru 2> (Join-Path $modeDir 'after-restart.err')
        if ($LASTEXITCODE -ne 0) { throw "$mode post-restart probe failed." }
        $restartStarted.Stop()
    }
    finally {
        Stop-ExperimentProcess $broker
    }

    $replays = @($clients | ForEach-Object { Get-Content -LiteralPath $_.output -Raw | ConvertFrom-Json })
    $ownerResult = Get-Content -LiteralPath $ownerOutput -Raw | ConvertFrom-Json
    $intruderResult = Get-Content -LiteralPath $intruderOutput -Raw | ConvertFrom-Json
    $restartResult = Get-Content -LiteralPath $restartOutput -Raw | ConvertFrom-Json
    $selectedTexts = @($replays.selected_text) + @($restartResult.selected_text)
    $worstP99 = ($replays.metrics.latency_ms.p99 | Measure-Object -Maximum).Maximum
    $worstMax = ($replays.metrics.latency_ms.max | Measure-Object -Maximum).Maximum
    $modePassed = -not ($replays.passed -contains $false) -and [bool]$ownerResult.passed -and [bool]$intruderResult.passed -and `
        [bool]$intruderResult.cross_process_session_rejected -and [bool]$restartResult.passed -and `
        (($selectedTexts | Select-Object -Unique).Count -eq 1) -and $worstMax -lt 50 -and $restartStarted.ElapsedMilliseconds -lt 2000
    $modeResults += [ordered]@{
        mode = $mode
        source_sha256 = $indexBuild.build.source_sha256
        index_sha256 = $indexBuild.build.index_sha256
        index_verified = [bool]$indexBuild.verified
        concurrent_clients = $replays
        architectures_verified = @($replays.architecture_bits | Select-Object -Unique | Sort-Object)
        selected_text = $selectedTexts[0]
        stable_result_across_clients_and_restart = (($selectedTexts | Select-Object -Unique).Count -eq 1)
        identity_spoof_rejected = -not ($replays.identity_spoof_rejected -contains $false)
        cross_process_session_rejected = [bool]$intruderResult.cross_process_session_rejected
        owner_pid = $ownerResult.pid
        intruder_pid = $intruderResult.pid
        worst_p99_ms = $worstP99
        worst_max_ms = $worstMax
        restart_recovery_ms = $restartStarted.Elapsed.TotalMilliseconds
        restart_result = $restartResult
        passed = $modePassed
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'go-backend\cmd\yimebroker\main.go',
    'go-backend\input_methods\yime\yimebroker\connection_limiter.go',
    'go-backend\input_methods\yime\yimebroker\connection_limiter_test.go',
    'go-backend\input_methods\yime\yimebroker\named_pipe_windows.go',
    'go-backend\input_methods\yime\yimebroker\named_pipe_windows_test.go',
    'go-backend\input_methods\yime\yimebroker\named_pipe_stub.go',
    'go-backend\input_methods\yime\yimebroker\stdio.go',
    'go-backend\input_methods\yime\yimebroker\protocol.go',
    'tools\yimecore\e6a\CMakeLists.txt',
    'tools\yimecore\e6a\YimeBrokerPipeProbe.cpp',
    'tools\yimecore\run-e6a-named-pipe-experiment.ps1'
)
$hashes = foreach ($relativePath in $sourceFiles) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relativePath)
    [ordered]@{ path = $relativePath.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yimebroker-e6a-named-pipe-acceptance-v1'
    stage = 'e6a'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    go_version = (& go version).Trim()
    cmake_version = (& cmake --version | Select-Object -First 1)
    os_arch = 'windows/' + $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    source_boundary = $dataRoot
    output_boundary = $outputDir
    transport = 'local Windows byte-stream named pipe; current-user/System DACL; remote clients rejected'
    trusted_identity = 'server-derived client token SID plus GetNamedPipeClientProcessId PID; absent from request schema'
    broker_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $brokerPath).Hash.ToLowerInvariant()
    probe_x64_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $probeByArchitecture.x64).Hash.ToLowerInvariant()
    probe_x86_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $probeByArchitecture.x86).Hash.ToLowerInvariant()
    source_hashes_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashesPath).Hash.ToLowerInvariant()
    iterations_per_client = $IterationsPerClient
    clients_per_mode = 4
    modes = $modeResults
    all_indices_verified = -not ($modeResults.index_verified -contains $false)
    all_modes_passed = -not ($modeResults.passed -contains $false)
    x86_x64_verified = -not (($modeResults | Where-Object { $_.architectures_verified.Count -ne 2 -or $_.architectures_verified[0] -ne 32 -or $_.architectures_verified[1] -ne 64 }).Count)
    identity_spoof_rejected = -not ($modeResults.identity_spoof_rejected -contains $false)
    cross_process_session_isolation = -not ($modeResults.cross_process_session_rejected -contains $false)
    restart_within_two_seconds = -not (($modeResults | Where-Object { $_.restart_recovery_ms -ge 2000 }).Count)
    no_request_over_50ms = -not (($modeResults | Where-Object { $_.worst_max_ms -ge 50 }).Count)
    native_rime_paging_ownership_preserved = $true
    production_registration_changed = $false
    limitations = @(
        'E6-A validates the production-shaped IPC boundary only; it does not register, install or switch a TSF text service',
        'the probe checks protocol, candidates, stable-ID commits, connection latency, restart and process isolation; real application focus, candidate UI and language-bar paths remain E6-B work',
        'the current-user/System DACL intentionally excludes cross-user clients; signing and packaged ACL verification remain release acceptance work'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "YimeBroker E6-A evidence: $outputDir"
if (-not $summary.all_indices_verified -or -not $summary.all_modes_passed -or -not $summary.x86_x64_verified -or
    -not $summary.identity_spoof_rejected -or -not $summary.cross_process_session_isolation -or
    -not $summary.restart_within_two_seconds -or -not $summary.no_request_over_50ms -or
    -not $summary.native_rime_paging_ownership_preserved -or $summary.production_registration_changed) {
    throw "One or more E6-A gates failed; see $summaryPath"
}
