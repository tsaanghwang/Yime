[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$configPath = Join-Path $stateRootPath 'runtime-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "missing E6-C trial runtime configuration: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($property in @('runtime_path', 'broker_path', 'install_root', 'state_root')) {
    if ([string]::IsNullOrWhiteSpace([string]$config.$property)) {
        throw "invalid E6-C trial runtime configuration: missing $property"
    }
}
foreach ($required in @($config.runtime_path, $config.broker_path, $config.install_root)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "configured E6-C trial path is unavailable: $required"
    }
}

$argumentLine = '-install-root "{0}" -broker "{1}" -state-root "{2}" -no-toolbar' -f
    ([string]$config.install_root), ([string]$config.broker_path), ([string]$config.state_root)
$runtime = Start-Process -FilePath ([string]$config.runtime_path) -ArgumentList $argumentLine -WindowStyle Hidden -PassThru
$statusPath = Join-Path ([string]$config.state_root) 'runtime-status.json'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Milliseconds 100
    if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
        try {
            $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($status.state -eq 'running' -and [int]$status.broker_pid -gt 0) {
                $broker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$status.broker_pid)"
                if ($broker -and
                    $broker.ExecutablePath.Equals([string]$config.broker_path, [StringComparison]::OrdinalIgnoreCase) -and
                    $broker.CommandLine.IndexOf('-index-root', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $broker.CommandLine.IndexOf('-user-model-snapshot', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $broker.CommandLine.IndexOf('-index-control-manifest', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $status
                    return
                }
            }
            if ($status.state -eq 'failed') {
                throw "E6-C trial runtime failed: $($status.last_error)"
            }
        } catch [System.Management.Automation.RuntimeException] {
            throw
        } catch {
            # The status file is atomically replaced; retry a transient read/parse race.
        }
    }
} while ((Get-Date) -lt $deadline)

if ($runtime.HasExited) {
    throw "E6-C trial runtime exited before becoming ready (exit $($runtime.ExitCode))"
}
throw "E6-C trial runtime did not become ready within $TimeoutSeconds seconds"
