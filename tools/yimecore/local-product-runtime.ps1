# Reused by package-local backup/restore. No mutation on dot-source.
function Get-LocalProductStartupHealthRequired($Package) {
    $descriptor=$Package.descriptor
    if($null -eq $descriptor){throw 'Validated local package descriptor required for startup.'}
    $field=$descriptor.PSObject.Properties['maintenance_health']
    if($null -eq $field){return $false} # Historical packages retain their original startup contract.
    if($field.Name -cne 'maintenance_health'){throw 'Startup health declaration must use its canonical field name.'}
    $policy=$field.Value
    if($policy -isnot [pscustomobject] -or @($policy.PSObject.Properties).Count -ne 2 -or
        @($policy.PSObject.Properties.Name) -cnotcontains 'protocol' -or
        @($policy.PSObject.Properties.Name) -cnotcontains 'required_on_start' -or
        $policy.protocol -isnot [string] -or $policy.protocol -cne 'yimecore-maintenance-health-v1' -or
        $policy.required_on_start -isnot [bool] -or -not $policy.required_on_start){
        throw 'Unsupported or malformed required startup health declaration.'
    }
    return $true
}

function Get-LocalProductHealthImageHash($Package,[string]$Relative) {
    $rows=@($Package.manifest.files|Where-Object {$_.path -ceq $Relative})
    if($rows.Count -ne 1 -or $rows[0].sha256 -isnot [string] -or $rows[0].sha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'Startup health requires the exact manifest-bound image hash.'
    }
    return $rows[0].sha256
}

function Assert-LocalProductStartedHealth($Package,$Config,$RuntimeProcess,$BrokerPid,[string]$TargetUserSid) {
    if(-not (Get-LocalProductStartupHealthRequired $Package)){return $null}
    if($RuntimeProcess -isnot [Diagnostics.Process] -or $RuntimeProcess.HasExited -or
        ($BrokerPid -isnot [int] -and $BrokerPid -isnot [long]) -or
        $BrokerPid -le 0 -or $BrokerPid -gt [int]::MaxValue -or $BrokerPid -eq $RuntimeProcess.Id -or
        $Config.install_root -ine $Package.root -or
        $Config.runtime_path -ine (Join-Path $Package.root 'bin\YimeCoreTrialRuntime.exe') -or
        $Config.broker_path -ine (Join-Path $Package.root 'bin\YimeBroker.exe')){
        throw 'Startup health requires this launch and its exact package paths.'
    }
    $runtimeHash=Get-LocalProductHealthImageHash $Package 'bin/YimeCoreTrialRuntime.exe'
    $brokerHash=Get-LocalProductHealthImageHash $Package 'bin/YimeBroker.exe'
    $processModule=$null;$healthModule=$null;$broker=$null;$observation=$null
    try {
        # Load only this already audited package's self-contained helpers. Never
        # Force-import: the health module must reuse the live observation registry.
        $processModule=Import-Module (Join-Path $Package.root 'maintenance\native-maintenance-processes.psm1') -Scope Local -PassThru
        $healthModule=Import-Module (Join-Path $Package.root 'maintenance\native-maintenance-health.psm1') -Scope Local -PassThru
        # Status supplies a discovery hint only. Pin this reference immediately;
        # the native observer verifies parent, creation, image/hash and SID.
        $broker=[Diagnostics.Process]::GetProcessById([int]$BrokerPid)
        $null=$broker.Handle
        $observation=& $processModule {param($sid,$root,$rh,$bh,$runtime,$broker)
            Open-YimeCoreNativeMaintenanceProcesses -TargetUserSid $sid -ExpectedInstallRoot $root `
                -ExpectedRuntimeSha256 $rh -ExpectedBrokerSha256 $bh -RuntimeProcess $runtime -BrokerProcess $broker
        } $TargetUserSid $Package.root $runtimeHash $brokerHash $RuntimeProcess $broker
        $health=& $healthModule {param($lease,$pipe)
            Get-YimeCoreNativeMaintenanceHealth -ProcessObservation $lease -BrokerPipeName $pipe
        } $observation $Config.pipe_name
        if($null -eq $health -or $health.schema_version -cne 'yimecore-native-maintenance-health-v1'){
            throw 'Startup health returned no current protocol result.'
        }
        foreach($name in @('health_service_responsive','nonce_verified','pipe_server_identity_bound','retained_process_observation_rechecked')){
            if($health.$name -isnot [bool] -or -not $health.$name){throw 'Startup health did not confirm both bound services.'}
        }
        return $health # Transport responsiveness only, not engine/E7/L6 readiness.
    } finally {
        if($null -ne $observation){
            try{& $processModule {param($o)Close-YimeCoreNativeMaintenanceProcesses -Observation $o} $observation}
            finally{if($null -ne $broker){$broker.Dispose()}}
        }elseif($null -ne $broker){$broker.Dispose()}
        # Do not unload shared modules and invalidate a caller's other leases.
    }
}

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
                $live=Assert-LocalProductLiveRuntime $Context
                $health=Assert-LocalProductStartedHealth $Context.package $config $process $status.broker_pid `
                    ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
                if($null -ne $health){$live['startup_health']=$health}
                return $live
            }
            Start-Sleep -Milliseconds 100
        } while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline)
        throw 'Local runtime failed to become ready with a verified standard-user identity.'
    } catch {
        if (-not $process.HasExited) { $process.Kill() }
        throw
    } finally { $process.Dispose() }
}
