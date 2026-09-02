[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$MaintenanceBoundaryPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
function Convert-ObservationUtc($Value) {
    # PS 7 can materialize JSON dates as DateTime; parsing its display string
    # again loses the UTC kind and incorrectly applies the local offset.
    if($Value -is [DateTimeOffset]){return $Value.UtcDateTime}
    if($Value -is [DateTime]){return $Value.ToUniversalTime()}
    return [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}
function Copy-SharedLogPrefix([string]$Source,[string]$Destination) {
    # Get-FileHash's sharing mode conflicts with the native runtime's writer.
    # Read a bounded prefix with writer-compatible sharing, then hash our own
    # immutable evidence file. Do not stop or change the observed service.
    $inputStream=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length=$inputStream.Length
        $remaining=$length
        $outputStream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $buffer=New-Object byte[] 65536
            while($remaining -gt 0) {
                $read=$inputStream.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length))
                if($read -eq 0){throw 'Live runtime log was truncated during snapshot; preserve incomplete evidence.'}
                $outputStream.Write($buffer,0,$read)
                $remaining-=$read
            }
        }finally{$outputStream.Dispose()}
        return @{source_length_at_open=$length;source_length_after=$inputStream.Length;copied_bytes=$length}
    }finally{$inputStream.Dispose()}
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowed=(Join-Path $repo '.tmp\yimecore-experiment\')
$baseline=[IO.Path]::GetFullPath($BaselineRoot)
$output=[IO.Path]::GetFullPath($OutputRoot)
foreach($path in @($baseline,$output)) {
    if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence must remain under .tmp/yimecore-experiment.'}
}
$summaryPath=Join-Path $output 'reboot-summary.json'
if(Test-Path -LiteralPath $summaryPath){throw 'Refusing to overwrite an existing reboot observation.'}
$before=Get-Content (Join-Path $baseline 'post-acceptance-state.json') -Raw|ConvertFrom-Json
$priorClosure=Get-Content (Join-Path $baseline 'closure-summary.json') -Raw|ConvertFrom-Json
$after=Get-Content (Join-Path $output 'observed-state.json') -Raw|ConvertFrom-Json
$autostart=Get-Content (Join-Path $output 'autostart-observed.json') -Raw|ConvertFrom-Json
$package=Get-Content (Join-Path $output 'package-audit.json') -Raw|ConvertFrom-Json
$os=Get-CimInstance Win32_OperatingSystem
$boot=$os.LastBootUpTime.ToUniversalTime()
$processes=@(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @('YimeCoreTrialRuntime.exe','YimeBroker.exe','PIMELauncher.exe','explorer.exe')
} | Select-Object Name,ProcessId,ParentProcessId,CreationDate,ExecutablePath,CommandLine)
$runtime=@($processes|Where-Object { $_.Name -eq 'YimeCoreTrialRuntime.exe' })
$broker=@($processes|Where-Object { $_.Name -eq 'YimeBroker.exe' })
function Test-LiveIdentity($Candidates,[string]$ExpectedPath,[int]$StatusPid) {
    return [bool](@($Candidates|Where-Object {
        $_.ProcessId -eq $StatusPid -and $_.ExecutablePath -ieq $ExpectedPath -and
        $_.CreationDate.ToUniversalTime() -ge $boot
    }).Count -eq 1)
}
function Same-Json($Left,$Right) {
    return (($Left|ConvertTo-Json -Depth 35 -Compress) -ceq ($Right|ConvertTo-Json -Depth 35 -Compress))
}
$checks=[ordered]@{
    boot_after_pre_reboot_acceptance=($boot -gt (Convert-ObservationUtc $priorClosure.generated_at))
    same_user_sid=($before.sid -eq $after.sid -and $after.sid -eq $autostart.target_user_sid)
    same_package_manifest=($before.manifest_sha256 -eq $after.manifest_sha256 -and $after.manifest_sha256 -eq $package.manifest_sha256)
    installed_payload_integrity=[bool]$package.passed
    runtime_config_unchanged=($before.runtime_config_sha256 -eq $after.runtime_config_sha256)
    run_unchanged_and_valid=((Same-Json $before.user.trial_run $after.user.trial_run) -and $autostart.passed -and $autostart.validated_only -and -not $autostart.registry_mutation_requested)
    system_registry_independently_verified=($autostart.registry_reader -eq 'StdRegProv/HKEY_USERS' -and [bool]$autostart.system_registry_verified)
    production_registration_unchanged=$true
    trial_registration_unchanged=$true
    trial_user_tip_unchanged=(Same-Json $before.user.trial_tip $after.user.trial_tip)
    language_profile_unchanged=(Same-Json $before.user.language_profile $after.user.language_profile)
    keyboard_preload_unchanged=(Same-Json $before.user.keyboard_preload $after.user.keyboard_preload)
    default_input_method_unchanged=$false
    runtime_status_from_this_boot=((Convert-ObservationUtc $after.runtime_status.updated_at) -ge $boot)
    live_runtime_matches_status_and_package=(Test-LiveIdentity $runtime (Join-Path $after.runtime_config.install_root 'bin\YimeCoreTrialRuntime.exe') ([int]$after.runtime_status.runtime_pid))
    live_broker_matches_status_and_package=(Test-LiveIdentity $broker (Join-Path $after.runtime_config.install_root 'bin\YimeBroker.exe') ([int]$after.runtime_status.broker_pid))
}
if($MaintenanceBoundaryPath) {
    $maintenance=Get-Content -LiteralPath $MaintenanceBoundaryPath -Raw|ConvertFrom-Json
    $checks.boot_after_latest_maintenance=($boot -gt (Convert-ObservationUtc $maintenance.generated_at))
}
foreach($view in @('Registry64','Registry32')) {
    foreach($kind in @('com','tip')) {
        if(-not (Same-Json $before.registration.$view."production_$kind" $after.registration.$view."production_$kind")){$checks.production_registration_unchanged=$false}
        if(-not (Same-Json $before.registration.$view."trial_$kind" $after.registration.$view."trial_$kind")){$checks.trial_registration_unchanged=$false}
    }
}
$default=Get-WinDefaultInputMethodOverride
$checks.default_input_method_unchanged=($default.InputMethodTip -eq $priorClosure.current_default_input_method.InputMethodTip)
$eventEvidence=@()
foreach($logName in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/EXE and DLL',
    'Microsoft-Windows-Windows Defender/Operational','Microsoft-Windows-Shell-Core/Operational','Application')) {
    try {
        $log=Get-WinEvent -ListLog $logName
        $events=@()
        if($log.IsEnabled) {
            $events=@(Get-WinEvent -FilterHashtable @{LogName=$logName;StartTime=$os.LastBootUpTime} -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match 'YimeCore|YimeBroker|YimeTextService' -or $_.ToXml() -match 'YimeCore|YimeBroker|YimeTextService' } |
                ForEach-Object { [ordered]@{time=$_.TimeCreated.ToUniversalTime().ToString('o');id=$_.Id;message=$_.Message;xml=$_.ToXml()} })
        }
        $eventEvidence+=@{log=$logName;enabled=$log.IsEnabled;matching_events=$events}
    }catch { $eventEvidence+=@{log=$logName;query_error=$_.Exception.Message} }
}
$stateRoot=[string]$after.runtime_config.state_root
# A manual restart during this boot must not be relabeled as successful logon
# autostart. Require the actual Shell-Core startup completion for this PID/SID.
$startupEventMatched=$false
foreach($entry in @($eventEvidence|Where-Object {$_.log -eq 'Microsoft-Windows-Shell-Core/Operational'})) {
    foreach($event in @($entry.matching_events|Where-Object {$_.id -eq 9708})) {
        $xml=[xml]$event.xml
        $fields=@{}
        foreach($data in $xml.Event.EventData.Data){$fields[[string]$data.Name]=[string]$data.'#text'}
        if($fields.Command -match 'YimeCoreTrialRuntime\.exe' -and
            [int]$fields.PID -eq [int]$after.runtime_status.runtime_pid -and
            [string]$xml.Event.System.Security.UserID -eq $after.sid){$startupEventMatched=$true}
    }
}
$checks.shell_logon_start_event_matches_live_runtime=$startupEventMatched
$runtimeLog=Join-Path $stateRoot 'logs\runtime.log'
$logItem=Get-Item -LiteralPath $runtimeLog
$logSnapshotPath=Join-Path $output 'runtime-log-snapshot.txt'
$logCopy=Copy-SharedLogPrefix $runtimeLog $logSnapshotPath
$startupEntries=@()
foreach($hive in @('HKCU','HKLM')) {
    foreach($section in @('Run','Run32','StartupFolder')) {
        $keyPath="${hive}:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$section"
        if(Test-Path -LiteralPath $keyPath) {
            $key=Get-Item -LiteralPath $keyPath
            try {
                foreach($name in $key.GetValueNames()|Where-Object {$_ -match 'Yime|PIME'}) {
                    $startupEntries+=@{key=$keyPath;name=$name;kind=[string]$key.GetValueKind($name);value=$key.GetValue($name)}
                }
            }finally{$key.Dispose()}
        }
    }
}
$references=@()
foreach($path in @((Join-Path $output 'observed-state.json'),(Join-Path $output 'autostart-observed.json'),
    (Join-Path $output 'package-audit.json'),(Join-Path $baseline 'post-acceptance-state.json'),(Join-Path $baseline 'closure-summary.json'))) {
    $references+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
}
[ordered]@{
    schema_version='yimecore-local-reboot-verification-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    development_scope=$scope;boot_time_utc=$boot.ToString('o');checks=$checks;passed=(-not ($checks.Values -contains $false));
    runtime_process_count=$runtime.Count;broker_process_count=$broker.Count;processes=$processes;
    current_default_input_method=$default;startup_approved_matching_entries=$startupEntries;
    runtime_log=@{last_write_utc=$logItem.LastWriteTimeUtc.ToString('o');length=$logItem.Length;
        snapshot_file=$logSnapshotPath;snapshot_sha256=(Get-FileHash -LiteralPath $logSnapshotPath).Hash.ToLowerInvariant();
        copy=$logCopy;tail=@(Get-Content -LiteralPath $logSnapshotPath -Tail 14)};
    events=$eventEvidence;references=$references;
    runtime_started_by_verifier=$false;registry_mutated_by_verifier=$false;installer_executed=$false;
    limitations=@('Absent log events do not prove that startup was never attempted or exclude a pre-log failure.','Persisted runtime status is not live evidence; match actual process paths and this boot.','Static frozen-architecture payload checks are not execution acceptance.')
}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $summaryPath -Encoding utf8
$checks|Format-Table -AutoSize
Write-Host "Reboot observation saved: $summaryPath"
if($checks.Values -contains $false){throw 'Post-reboot acceptance failed; observed state was not repaired.'}
