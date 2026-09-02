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
$installRootPath = [IO.Path]::GetFullPath([string]$config.install_root)
$expectedRuntimePath = Join-Path $installRootPath 'bin\YimeCoreTrialRuntime.exe'
$expectedBrokerPath = Join-Path $installRootPath 'bin\YimeBroker.exe'
if (-not ([IO.Path]::GetFullPath([string]$config.runtime_path)).Equals($expectedRuntimePath, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFullPath([string]$config.broker_path)).Equals($expectedBrokerPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'configured E6-C runtime binaries are outside their fixed install locations'
}
$manifestPath = Join-Path $installRootPath 'package-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "missing E6-C package manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.PSObject.Properties['package_contract'] -and $manifest.package_contract -eq 'yimecore-local-product-package-v1') {
    . (Join-Path $PSScriptRoot 'development-scope.ps1')
    . (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
    . (Join-Path $PSScriptRoot 'local-package-contract.ps1')
    . (Join-Path $PSScriptRoot 'local-product-runtime.ps1')
    $null = Get-YimeCoreDevelopmentScope
    Assert-YimeCoreUnpackagedDataMaintenance
    $context = Assert-LocalProductInstalledContext (Split-Path -Parent $PSScriptRoot) $stateRootPath
    Start-LocalProductRuntime $context
    return
}
$brokerRecord = @($manifest.files | Where-Object { $_.path -eq 'bin/YimeBroker.exe' })
if ($brokerRecord.Count -ne 1 -or
    (Get-FileHash -LiteralPath $expectedBrokerPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        [string]$brokerRecord[0].sha256) {
    throw 'configured E6-C Broker does not match the package manifest'
}

$argumentLine = '-install-root "{0}" -broker "{1}" -state-root "{2}" -no-toolbar' -f
    ([string]$config.install_root), ([string]$config.broker_path), ([string]$config.state_root)
$runtime = Start-Process -FilePath ([string]$config.runtime_path) -ArgumentList $argumentLine -WindowStyle Hidden -PassThru
try {
	$statusPath = Join-Path ([string]$config.state_root) 'runtime-status.json'
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	do {
		Start-Sleep -Milliseconds 100
		if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
			try {
				$status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
				if ($status.state -eq 'running' -and [int]$status.broker_pid -gt 0) {
					$broker = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$status.broker_pid)"
					$path = if ($broker) { [string]$broker.ExecutablePath } else { '' }
					$commandLine = if ($broker) { [string]$broker.CommandLine } else { '' }
					$pathMatchesWhenAvailable = [string]::IsNullOrWhiteSpace($path) -or
						([IO.Path]::GetFullPath($path)).Equals($expectedBrokerPath, [StringComparison]::OrdinalIgnoreCase)
					$commandLineMatchesWhenAvailable = [string]::IsNullOrWhiteSpace($commandLine) -or
						($commandLine.IndexOf('-index-root', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
						 $commandLine.IndexOf('-user-model-snapshot', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
						 $commandLine.IndexOf('-index-control-manifest', [StringComparison]::OrdinalIgnoreCase) -ge 0)
					if ($broker -and [int]$status.runtime_pid -eq $runtime.Id -and
						[int]$broker.ParentProcessId -eq $runtime.Id -and
						([string]$broker.Name).Equals('YimeBroker.exe', [StringComparison]::OrdinalIgnoreCase) -and
						$pathMatchesWhenAvailable -and $commandLineMatchesWhenAvailable) {
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
} catch {
	$startupFailure = $_
	# Only the exact process created by this invocation is eligible for rollback.
	# Its kill-on-close Job owns any Broker/toolbar children.
	if (-not $runtime.HasExited) {
		Stop-Process -Id $runtime.Id -Force -ErrorAction SilentlyContinue
		$runtime.WaitForExit(5000) | Out-Null
	}
	if (-not $runtime.HasExited) {
		throw "${startupFailure}; cleanup could not terminate runtime PID $($runtime.Id)"
	}
	throw $startupFailure
}
