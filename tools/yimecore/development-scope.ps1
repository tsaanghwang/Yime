# Shared guard for the current, explicitly limited development phase.
function Assert-YimeCoreUnpackagedDataMaintenance {
    param([int]$RootProcessId=$PID)
    $processId=$RootProcessId
    $seen=@{}
    $prefix=Join-Path $env:ProgramFiles 'WindowsApps\'
    for($depth=0;$depth -lt 32 -and $processId -gt 0;$depth++) {
        if($seen.ContainsKey($processId)){break}
        $seen[$processId]=$true
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$processId"
        if(-not $process){break}
        if(([string]$process.ExecutablePath).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Backup/restore must run from standalone Windows PowerShell launched from Explorer, not a packaged application. AppData virtualization can hide the archive or restored files.'
        }
        if($process.Name -ieq 'explorer.exe'){return}
        $processId=[int]$process.ParentProcessId
    }
    throw 'Could not verify an unpackaged Explorer-launched maintenance context; no data mutation allowed.'
}

function Assert-YimeCoreMaintenanceInitiator {
    # The C# launcher independently verifies the retained process handle, exact
    # creation time/image, primary token, SID and session. Check ancestry as well:
    # NO_PACKAGE on a command child does not exclude a packaged application parent.
    $reference=[Environment]::GetEnvironmentVariable('YIMECORE_MAINTENANCE_INITIATOR','Process')
    if([string]::IsNullOrEmpty($reference)){return} # elevated launcher fails closed
    if($reference -notmatch '^([1-9][0-9]*):([1-9][0-9]*)$'){throw 'Invalid native maintenance initiator reference.'}
    Assert-YimeCoreUnpackagedDataMaintenance -RootProcessId ([int]$Matches[1])
}

function Get-YimeCoreDevelopmentScope {
    $policyPath = Join-Path $PSScriptRoot 'development-scope.json'
    $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else { $env:PROCESSOR_ARCHITECTURE }
    Assert-YimeCoreDevelopmentHost $policy $env:COMPUTERNAME $nativeArchitecture ([Environment]::Is64BitProcess)
    [ordered]@{
        id = $policy.id
        computer_name = $env:COMPUTERNAME
        native_architecture = $nativeArchitecture
        active_architectures = @($policy.active_architectures)
        performance_profile = $policy.performance_profile
        frozen_targets = @($policy.frozen_targets)
        experiment_targets = @($policy.experiment_targets)
        policy_sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-YimeCoreDevelopmentHost($Policy, [string]$ComputerName, [string]$NativeArchitecture, [bool]$Is64BitProcess) {
    $active = @($Policy.active_architectures)
    if ($Policy.schema_version -ne 'yimecore-development-scope-v1' -or
        $Policy.native_architecture -ne 'AMD64' -or
        $active.Count -ne 2 -or $active[0] -ne 'x64' -or $active[1] -ne 'x86' -or
        $Policy.performance_profile -ne 'development_host_x64' -or
        $ComputerName -ne $Policy.computer_name -or $NativeArchitecture -ne 'AMD64' -or -not $Is64BitProcess) {
        throw 'This local-product lane requires the pinned AMD64 development host and 64-bit PowerShell. Use the separate approved platform-experiment lane for resumed targets.'
    }
}

function Get-YimeCoreExperimentTarget([string]$Target) {
    $policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'development-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $match = @($policy.experiment_targets | Where-Object { $_.id -ceq $Target -and $_.status -eq 'active' })
    if ($match.Count -ne 1 -or $Target -cnotin @('mainstream_x64', 'arm64')) {
        throw 'Target is not in the approved experiment allowlist.'
    }
    $expected = if ($Target -eq 'arm64') { 'arm64|arm64|ARM64' } else { 'x64|amd64|x64' }
    if ((@($match[0].architecture, $match[0].go_arch, $match[0].cmake_platform) -join '|') -cne $expected) {
        throw 'Experiment target architecture mapping is invalid.'
    }
    return $match[0]
}

function Get-YimeCoreExperimentBuildScope([string]$Target) {
    $targetConfig = Get-YimeCoreExperimentTarget $Target
    if ($Target -eq 'arm64') { return Get-YimeCoreDevelopmentScope }
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $physicalHost = $targetConfig.physical_host
    if ($Target -ne 'mainstream_x64' -or $null -eq $physicalHost -or $physicalHost.computer_name -cne $env:COMPUTERNAME -or
        $physicalHost.owner -cne 'developer' -or @($physicalHost.approved_uses).Count -ne 3 -or
        (@($physicalHost.approved_uses) -join '|') -cne 'source_build|isolated_native_contracts|target_package_transactions' -or
        $nativeArchitecture -ne 'AMD64' -or -not [Environment]::Is64BitProcess) {
        throw 'The mainstream_x64 experiment build requires its identified developer-owned AMD64 physical host and 64-bit PowerShell.'
    }
    [ordered]@{
        id = 'yimecore-mainstream-x64-experiment-build-v1'; target = $Target; computer_name = $env:COMPUTERNAME
        native_architecture = $nativeArchitecture; active_architectures = @('x64', 'x86'); target_architecture = $targetConfig.architecture
        output_policy = 'Separate platform-experiment output only; no installation, registration, or default-input mutation.'
    }
}

function Assert-YimeCoreNativeGo {
    $target = @(& go env GOOS GOARCH)
    if ($LASTEXITCODE -ne 0 -or $target.Count -ne 2 -or $target[0] -ne 'windows' -or $target[1] -ne 'amd64') {
        throw 'The shared YimeCore runtime/Broker must remain windows/amd64. Resumed x86 applies only to the Win32 TSF surface, not a second Go core.'
    }
}

function Test-YimeCoreScopeEvidence($Evidence, $Scope) {
    $expectedArchitectures = @($Scope.active_architectures)
    $actualArchitectures = @($Evidence.active_architectures)
    return [bool]($null -ne $Evidence -and $Evidence.id -eq $Scope.id -and
        $Evidence.computer_name -eq $Scope.computer_name -and $Evidence.native_architecture -eq 'AMD64' -and
        $actualArchitectures.Count -eq $expectedArchitectures.Count -and
        ($actualArchitectures -join '|') -ceq ($expectedArchitectures -join '|') -and
        $Evidence.policy_sha256 -eq $Scope.policy_sha256)
}
