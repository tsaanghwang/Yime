[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [string]$ExpectedComputerName,
    [string]$ExpectedManifestSha256,
    [string]$OutputPath
)

# Metadata-only observer. It never starts or stops a process, invokes maintenance,
# reads user-model content, or changes product/registry state. Each probe reports
# pass, fail, or unavailable so one missing PowerShell capability does not discard
# evidence collected by the other probes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')

$checks = [Collections.ArrayList]::new()
function Add-Check([string]$Name, [string]$Status, [string]$Reason) {
    [void]$checks.Add([ordered]@{name=$Name;status=$Status;reason=$Reason})
}
function Get-Sha256Text([string]$Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes($Value)
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally {$sha.Dispose()}
}
function Get-RegistryValue($Record,[string]$Name) {
    @($Record.values | Where-Object {$_.name -eq $Name} | ForEach-Object {$_.value}) | Select-Object -First 1
}

$record=[ordered]@{
    schema_version='yimecore-installed-readonly-evidence-v1'
    generated_at=[DateTime]::UtcNow.ToString('o')
    observer=@{powershell=$PSVersionTable.PSVersion.ToString();process_64bit=[Environment]::Is64BitProcess}
    host=$null
    package=$null
    runtime=$null
    registry=$null
    shell_logon=$null
    current_default_input_method=$null
    checks=$checks
    complete=$false
    passed=$false
    privacy=@{user_text_read=$false;learning_data_read=$false;full_sid_emitted=$false;private_command_line_emitted=$false}
    side_effects=@{installer_executed=$false;maintenance_executed=$false;process_started_or_stopped=$false;registry_mutated=$false;product_state_written=$false}
}

$os=$null
try {
    $os=Get-CimInstance Win32_OperatingSystem -Property Caption,Version,OSArchitecture,LastBootUpTime
    $cpu=Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors | Select-Object -First 1
    $record.host=[ordered]@{computer_name=$env:COMPUTERNAME;os_caption=$os.Caption;os_version=$os.Version;
        os_architecture=$os.OSArchitecture;boot_time_utc=$os.LastBootUpTime.ToUniversalTime().ToString('o');cpu=$cpu.Name;
        cores=$cpu.NumberOfCores;logical_processors=$cpu.NumberOfLogicalProcessors}
    if($ExpectedComputerName) {
        if($env:COMPUTERNAME -ceq $ExpectedComputerName){Add-Check 'expected_computer' 'pass' 'Computer name matches.'}
        else{Add-Check 'expected_computer' 'fail' "Observed computer is $env:COMPUTERNAME."}
    } else {Add-Check 'expected_computer' 'unavailable' 'No expected computer name was supplied.'}
} catch {Add-Check 'host_metadata' 'unavailable' $_.Exception.Message}

$config=$null;$status=$null;$manifest=$null;$metadata=$null;$descriptor=$null;$root=$null
try {
    $state=[IO.Path]::GetFullPath($StateRoot)
    $config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $status=Get-Content -LiteralPath (Join-Path $state 'runtime-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $root=[IO.Path]::GetFullPath([string]$config.install_root)
    $manifestPath=Join-Path $root 'package-manifest.json'
    $metadata=Get-Content -LiteralPath (Join-Path $root 'install-metadata.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $descriptor=Get-Content -LiteralPath (Join-Path $root 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    $manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $record.package=[ordered]@{product_version=$descriptor.version;git_commit=$metadata.git_commit;install_root=$root;
        installed_at=$metadata.installed_at;manifest_sha256=$manifestHash;payload_count=@($manifest.files).Count;payload_mismatches=@()}
    if($ExpectedManifestSha256) {
        if($manifestHash -ceq $ExpectedManifestSha256.ToLowerInvariant()){Add-Check 'expected_manifest' 'pass' 'Manifest hash matches.'}
        else{Add-Check 'expected_manifest' 'fail' "Observed manifest is $manifestHash."}
    } else {Add-Check 'expected_manifest' 'unavailable' 'No expected manifest hash was supplied.'}
    if($metadata.package_manifest_sha256 -ceq $manifestHash -and $metadata.install_root -ieq $root -and
        $config.state_root -ieq $state -and $status.install_root -ieq $root) {
        Add-Check 'package_state_binding' 'pass' 'Manifest, install metadata, runtime config, and status agree.'
    } else {Add-Check 'package_state_binding' 'fail' 'Installed metadata or runtime state is bound to another package.'}
} catch {Add-Check 'installed_package_discovery' 'unavailable' $_.Exception.Message}

if($manifest -and $root) {
    try {
        $prefix=$root.TrimEnd('\')+'\';$bad=@()
        foreach($file in @($manifest.files)) {
            $path=[IO.Path]::GetFullPath((Join-Path $root ([string]$file.path)))
            if(-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "Manifest path escapes package: $($file.path)"}
            Assert-YimeCorePlainPath $path
            if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$file.bytes -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$file.sha256){$bad+=@([string]$file.path)}
        }
        $record.package.payload_mismatches=$bad
        if($bad.Count -eq 0){Add-Check 'payload_integrity' 'pass' "All $(@($manifest.files).Count) payloads match."}
        else{Add-Check 'payload_integrity' 'fail' "$($bad.Count) payloads are missing or changed."}
    } catch {Add-Check 'payload_integrity' 'unavailable' $_.Exception.Message}
}

$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($config -and $status -and $os) {
    try {
        $live=Get-YimeCoreLiveRuntimeEvidence ([string]$config.state_root)
        $ownersMatch=(@($live.owners|Where-Object {$_.return_code -ne 0 -or $_.sid -ne $sid}).Count -eq 0 -and @($live.owners).Count -eq 2)
        $record.runtime=[ordered]@{state=$live.status.state;status_updated_at=$live.status.updated_at;restarts=$live.status.restarts;
            runtime=[ordered]@{pid=$live.runtime.ProcessId;parent_pid=$live.runtime.ParentProcessId;image=$live.runtime.ExecutablePath;started_at=$live.runtime.CreationDate.ToUniversalTime().ToString('o')};
            broker=[ordered]@{pid=$live.broker.ProcessId;parent_pid=$live.broker.ParentProcessId;image=$live.broker.ExecutablePath;started_at=$live.broker.CreationDate.ToUniversalTime().ToString('o')};
            owner_sid_sha256=(Get-Sha256Text $sid);owners_match_current_user=$ownersMatch;identity_passed=[bool]$live.passed}
        if($live.passed -and $ownersMatch){Add-Check 'live_runtime_identity' 'pass' 'Runtime and Broker match this boot, package, parent, status, and owner.'}
        else{Add-Check 'live_runtime_identity' 'fail' 'Runtime/Broker identity did not fully match.'}
    } catch {Add-Check 'live_runtime_identity' 'unavailable' $_.Exception.Message}
}

if($descriptor -and $root) {
    try {
        $runRead=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
            hDefKey=[uint32]2147483651;sSubKeyName="$sid\Software\Microsoft\Windows\CurrentVersion\Run";sValueName='YimeCoreExperimentalTrial'}
        $uninstall=Read-YimeCoreSystemKey 2147483651 "$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial"
        $expectedRun='"'+$root+'\bin\YimeCoreTrialRuntime.exe" -no-toolbar'
        $runOk=($runRead.ReturnValue -eq 0 -and $runRead.sValue -ceq $expectedRun)
        $uninstallOk=($uninstall.exists -and (Get-RegistryValue $uninstall 'InstallLocation') -ieq $root -and
            (Get-RegistryValue $uninstall 'DisplayVersion') -ceq $descriptor.version)
        $com=[ordered]@{}
        foreach($arch in @('x64','x86')) {
            $key=if($arch -eq 'x64'){"SOFTWARE\Classes\CLSID\$($descriptor.identity.clsid)\InprocServer32"}else{"SOFTWARE\Classes\WOW6432Node\CLSID\$($descriptor.identity.clsid)\InprocServer32"}
            $entry=Read-YimeCoreSystemKey 2147483650 $key
            $expected=Join-Path $root "$arch\YimeTextServiceExperiment.dll"
            $com[$arch]=(@($entry.values|Where-Object {$_.name -eq '' -and $_.value -ieq $expected}).Count -eq 1)
        }
        $record.registry=[ordered]@{provider='StdRegProv/HKEY_USERS and HKEY_LOCAL_MACHINE';run_matches=$runOk;
            uninstall_matches=$uninstallOk;com_x64_matches=$com.x64;com_x86_matches=$com.x86}
        if($runOk -and $uninstallOk -and $com.x64 -and $com.x86){Add-Check 'system_registry_binding' 'pass' 'Run, uninstall, and x64/x86 COM records match.'}
        else{Add-Check 'system_registry_binding' 'fail' 'One or more system-visible registry records differ.'}
    } catch {Add-Check 'system_registry_binding' 'unavailable' $_.Exception.Message}
}

if($record.runtime -and $os) {
    try {
        $log=Get-WinEvent -ListLog 'Microsoft-Windows-Shell-Core/Operational' -ErrorAction Stop
        if(-not $log.IsEnabled){Add-Check 'shell_logon_event_9708' 'unavailable' 'Shell-Core Operational log is disabled.'}
        else {
            $matches=@(Get-WinEvent -FilterHashtable @{LogName=$log.LogName;Id=9708;StartTime=$os.LastBootUpTime} -ErrorAction Stop|ForEach-Object {
                $xml=[xml]$_.ToXml();$fields=@{};foreach($d in $xml.Event.EventData.Data){$fields[[string]$d.Name]=[string]$d.'#text'}
                if($fields.Command -match 'YimeCoreTrialRuntime\.exe' -and [int]$fields.PID -eq [int]$record.runtime.runtime.pid -and
                    [string]$xml.Event.System.Security.UserID -eq $sid){[ordered]@{time=$_.TimeCreated.ToUniversalTime().ToString('o');pid=[int]$fields.PID;image='YimeCoreTrialRuntime.exe'}}
            })
            $record.shell_logon=[ordered]@{log_enabled=$true;matching_event_count=$matches.Count;events=$matches}
            if($matches.Count -ge 1){Add-Check 'shell_logon_event_9708' 'pass' 'A matching Runtime PID and SID event was found.'}
            else{Add-Check 'shell_logon_event_9708' 'fail' 'No matching Runtime PID and SID event was found for this boot.'}
        }
    } catch {Add-Check 'shell_logon_event_9708' 'unavailable' $_.Exception.Message}
}

try {
    $default=Get-WinDefaultInputMethodOverride -ErrorAction Stop
    $record.current_default_input_method=[ordered]@{override_present=[bool]$default;tip=$(if($default){$default.InputMethodTip}else{$null})}
    Add-Check 'current_default_input_method_observed' 'pass' 'Current override presence/value recorded without claiming an unchanged baseline.'
} catch {Add-Check 'current_default_input_method_observed' 'unavailable' $_.Exception.Message}

$required=@('expected_computer','expected_manifest','package_state_binding','payload_integrity','live_runtime_identity','system_registry_binding','shell_logon_event_9708')
$requiredChecks=@($checks|Where-Object {$_.name -in $required})
$record.complete=($requiredChecks.Count -eq $required.Count -and @($requiredChecks|Where-Object {$_.status -eq 'unavailable'}).Count -eq 0)
$record.passed=($record.complete -and @($requiredChecks|Where-Object {$_.status -ne 'pass'}).Count -eq 0)

$json=$record|ConvertTo-Json -Depth 12
if($OutputPath) {
    $target=[IO.Path]::GetFullPath($OutputPath)
    if(Test-Path -LiteralPath $target){throw 'Refusing to overwrite existing evidence.'}
    $parent=Split-Path -Parent $target
    if(-not (Test-Path -LiteralPath $parent -PathType Container)){[void][IO.Directory]::CreateDirectory($parent)}
    [IO.File]::WriteAllText($target,$json+"`r`n",[Text.UTF8Encoding]::new($false))
}
$json
