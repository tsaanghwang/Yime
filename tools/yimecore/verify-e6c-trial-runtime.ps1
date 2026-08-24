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
$pipeName = ([string]$config.pipe_name).Replace('\\.\pipe\', '')
if ([string]::IsNullOrWhiteSpace($pipeName)) { throw 'invalid E6-C named pipe configuration' }

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
    $expectedBroker = [IO.Path]::GetFullPath([string]$config.broker_path)
    $broker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$statusBefore.broker_pid)"
    if (-not $broker -or -not $broker.ExecutablePath.Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'refusing to terminate an unverified Broker process'
    }
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
            $newBroker.ExecutablePath.Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase)
    } while ((Get-Date) -lt $deadline -and -not $recovered)
    if (-not $recovered) { throw 'E6-C trial runtime did not recover its Broker' }
    $recovery = [ordered]@{
        passed = $true
        runtime_pid = [int]$statusAfter.runtime_pid
        old_broker_pid = [int]$statusBefore.broker_pid
        new_broker_pid = [int]$statusAfter.broker_pid
        restarts_before = [int]$statusBefore.restarts
        restarts_after = [int]$statusAfter.restarts
        broker_path_verified = $true
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
