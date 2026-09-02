# Reused by package-local backup/restore. No mutation on dot-source.
function Initialize-LocalProductLauncher($Context) {
    Assert-YimeCoreMaintenanceInitiator
    if (-not ('YimeCore.LocalMaintenance.StandardUserLauncher' -as [type])) {
        Add-Type -Path (Join-Path $Context.package.root 'maintenance\local-runtime-launcher.cs')
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $null = [YimeCore.LocalMaintenance.StandardUserLauncher]::ValidateLaunchToken($sid)
}

function Assert-LocalProductLiveRuntime($Context) {
    $evidence = Get-YimeCoreLiveRuntimeEvidence $Context.state_root
    if (-not $evidence.passed) { throw 'Local runtime/Broker live identity is not verified.' }
    Initialize-LocalProductLauncher $Context
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $tokens = @()
    foreach ($childPid in @([int]$evidence.status.runtime_pid,[int]$evidence.status.broker_pid)) {
        $token = [YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess($childPid)
        if (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardToken($token,$sid,$session)) {
            throw "Local runtime/Broker is not running with the initiating standard-user token: $childPid"
        }
        $tokens += $token
    }
    return [ordered]@{passed=$true; live=$evidence; standard_user_tokens=$tokens}
}

function Start-LocalProductRuntime($Context) {
    Assert-YimeCoreUnpackagedDataMaintenance
    # Revalidate after the copy/restore transaction and before executing payload.
    $Context = Assert-LocalProductInstalledContext $Context.package.root $Context.state_root
    Initialize-LocalProductLauncher $Context
    $config = $Context.config
    $arguments = '-install-root "{0}" -broker "{1}" -state-root "{2}" -no-toolbar' -f
        $config.install_root, $config.broker_path, $config.state_root
    $process = [YimeCore.LocalMaintenance.StandardUserLauncher]::Start(
        $config.runtime_path, $arguments, $config.install_root,
        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            $status = $null
            try { $status = Get-Content -LiteralPath (Join-Path $Context.state_root 'runtime-status.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
            if ($status -and $status.state -eq 'running' -and [int]$status.runtime_pid -eq $process.Id) {
                return Assert-LocalProductLiveRuntime $Context
            }
            Start-Sleep -Milliseconds 100
        } while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline)
        throw 'Local runtime failed to become ready with a verified standard-user identity.'
    } catch {
        if (-not $process.HasExited) { $process.Kill() }
        throw
    } finally { $process.Dispose() }
}
