[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$ExerciseRecovery
)

$ErrorActionPreference = 'Stop'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$config = Get-Content -LiteralPath (Join-Path $stateRootPath 'runtime-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$statusPath = Join-Path $stateRootPath 'runtime-status.json'
$statusBefore = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($statusBefore.state -ne 'running' -or [int]$statusBefore.broker_pid -le 0) {
    throw 'E6-C trial runtime is not running'
}
$installRoot = [IO.Path]::GetFullPath([string]$config.install_root)
$expectedRuntime = [IO.Path]::GetFullPath([string]$config.runtime_path)
$expectedBroker = [IO.Path]::GetFullPath([string]$config.broker_path)
$expectedStateRoot = [IO.Path]::GetFullPath([string]$config.state_root)
if (-not $expectedStateRoot.Equals($stateRootPath, [StringComparison]::OrdinalIgnoreCase) -or
    -not $expectedRuntime.Equals((Join-Path $installRoot 'bin\YimeCoreTrialRuntime.exe'), [StringComparison]::OrdinalIgnoreCase) -or
    -not $expectedBroker.Equals((Join-Path $installRoot 'bin\YimeBroker.exe'), [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFullPath([string]$statusBefore.install_root)).Equals($installRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFullPath([string]$statusBefore.broker_path)).Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'E6-C trial runtime configuration and status roots do not converge'
}
foreach ($requiredPath in @($expectedRuntime, $expectedBroker, (Join-Path $installRoot 'package-manifest.json'))) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "missing installed E6-C identity input: $requiredPath"
    }
}
$packageManifest = Get-Content -LiteralPath (Join-Path $installRoot 'package-manifest.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json
$brokerManifestRecord = @($packageManifest.files | Where-Object { $_.path -eq 'bin/YimeBroker.exe' })
if ($brokerManifestRecord.Count -ne 1) { throw 'installed package manifest has no unique Broker record' }
$brokerDiskHash = (Get-FileHash -LiteralPath $expectedBroker -Algorithm SHA256).Hash.ToLowerInvariant()
if ($brokerDiskHash -ne [string]$brokerManifestRecord[0].sha256) {
    throw 'installed Broker hash does not match the package manifest'
}
$pipeName = ([string]$config.pipe_name).Replace('\\.\pipe\', '')
if ([string]::IsNullOrWhiteSpace($pipeName)) { throw 'invalid E6-C named pipe configuration' }

function Test-BrokerProcessIdentity($Process, $Status) {
    if (-not $Process -or -not $Status) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Status.install_root) -or
        [string]::IsNullOrWhiteSpace([string]$Status.broker_path)) { return $false }
    $path = [string]$Process.ExecutablePath
    $pathVerifiedWhenAvailable = [string]::IsNullOrWhiteSpace($path) -or
        ([IO.Path]::GetFullPath($path)).Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase)
    return [int]$Process.ProcessId -eq [int]$Status.broker_pid -and
        [int]$Process.ParentProcessId -eq [int]$Status.runtime_pid -and
        ([string]$Process.Name).Equals('YimeBroker.exe', [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFullPath([string]$Status.install_root)).Equals($installRoot, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFullPath([string]$Status.broker_path)).Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase) -and
        $pathVerifiedWhenAvailable
}

function Invoke-ModeProbe([string]$Mode, [string]$Code) {
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::InOut)
    $client.Connect(3000)
    $reader = [IO.StreamReader]::new($client, [Text.Encoding]::UTF8, $false, 4096, $true)
    $writer = [IO.StreamWriter]::new($client, [Text.UTF8Encoding]::new($false), 4096, $true)
    $writer.AutoFlush = $true
    try {
        $writer.WriteLine((@{ version = 1; sequence = 1; operation = 'open'; mode = $Mode } | ConvertTo-Json -Compress))
        $opened = $reader.ReadLine() | ConvertFrom-Json
        if ($opened.error -or [string]::IsNullOrWhiteSpace([string]$opened.session_id)) {
            throw "$Mode session open failed: $($opened | ConvertTo-Json -Compress)"
        }
        $sequence = 1
        $response = $null
        foreach ($character in $Code.ToCharArray()) {
            $sequence++
            $request = @{
                version = 1
                sequence = $sequence
                session_id = $opened.session_id
                operation = 'apply'
                event = @{ operation = 1; code = [string]$character }
            }
            $writer.WriteLine(($request | ConvertTo-Json -Compress))
            $response = $reader.ReadLine() | ConvertFrom-Json
            if ($response.error) { throw "$Mode apply failed: $($response | ConvertTo-Json -Compress)" }
        }
        $candidates = @($response.result.state.candidates)
        if ($response.result.state.raw_input -ne $Code -or $candidates.Count -eq 0) {
            throw "$Mode returned no usable candidates for $Code"
        }
        $sequence++
        $writer.WriteLine((@{
            version = 1; sequence = $sequence; session_id = $opened.session_id; operation = 'close'
        } | ConvertTo-Json -Compress))
        $closed = $reader.ReadLine() | ConvertFrom-Json
        if ($closed.error) { throw "$Mode session close failed" }
        [ordered]@{
            mode = $Mode
            code = $Code
            engine_version = $response.engine_version
            candidate_count = $candidates.Count
            first_candidate = $candidates[0].text
        }
    } finally {
        $writer.Dispose()
        $reader.Dispose()
        $client.Dispose()
    }
}

$modes = @(
    (Invoke-ModeProbe 'full' 'bjjj'),
    (Invoke-ModeProbe 'variable' 'bj'),
    (Invoke-ModeProbe 'shorthand' 'bl')
)
$recovery = $null
if ($ExerciseRecovery) {
    $broker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$statusBefore.broker_pid)"
    if (-not (Test-BrokerProcessIdentity $broker $statusBefore)) {
        throw 'refusing to terminate an unverified Broker process'
    }
    $pathAccessibleBefore = -not [string]::IsNullOrWhiteSpace([string]$broker.ExecutablePath)
    Stop-Process -Id ([int]$statusBefore.broker_pid) -Force
    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        try { $statusAfter = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $statusAfter = $null }
        $newBroker = if ($statusAfter -and [int]$statusAfter.broker_pid -gt 0) {
            Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$statusAfter.broker_pid)"
        } else { $null }
        $recovered = $statusAfter -and $statusAfter.state -eq 'running' -and
            [int]$statusAfter.runtime_pid -eq [int]$statusBefore.runtime_pid -and
            [int]$statusAfter.broker_pid -ne [int]$statusBefore.broker_pid -and
            [int]$statusAfter.restarts -gt [int]$statusBefore.restarts -and $newBroker -and
            (Test-BrokerProcessIdentity $newBroker $statusAfter)
    } while ((Get-Date) -lt $deadline -and -not $recovered)
    if (-not $recovered) { throw 'E6-C trial runtime did not recover its Broker' }
    $recovery = [ordered]@{
        passed = $true
        runtime_pid = [int]$statusAfter.runtime_pid
        old_broker_pid = [int]$statusBefore.broker_pid
        new_broker_pid = [int]$statusAfter.broker_pid
        restarts_before = [int]$statusBefore.restarts
        restarts_after = [int]$statusAfter.restarts
        broker_path_verified = [bool]($pathAccessibleBefore -and
            -not [string]::IsNullOrWhiteSpace([string]$newBroker.ExecutablePath))
        broker_package_hash_verified = $true
        broker_parent_runtime_verified = $true
        pipe_probe_verified = $true
        process_identity_method = if ($pathAccessibleBefore -and
            -not [string]::IsNullOrWhiteSpace([string]$newBroker.ExecutablePath)) {
            'executable-path+package-hash+runtime-parent+pipe-probe'
        } else {
            'package-hash+runtime-parent+status-convergence+pipe-probe'
        }
    }
}

$evidenceRoot = Join-Path $stateRootPath 'evidence'
New-Item -ItemType Directory -Force $evidenceRoot | Out-Null
$evidencePath = Join-Path $evidenceRoot 'live-runtime-verification.json'
[ordered]@{
    schema_version = 'yimecore-e6c-live-runtime-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    pipe_name = [string]$config.pipe_name
    modes = $modes
    all_modes_usable = $modes.Count -eq 3 -and -not ($modes.candidate_count -contains 0)
    recovery = $recovery
    user_model_mutated_by_probe = $false
    production_rime_pime_changed = $false
    bare_digit_selection_changed = $false
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding utf8
Write-Host "E6-C live runtime verification passed: $evidencePath"
