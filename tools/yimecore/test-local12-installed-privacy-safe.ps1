[CmdletBinding()]
param([switch]$PreflightOnly, [switch]$ConfirmHostsClosedAndInputIdle)
# Native, current-candidate registered-host acceptance only. Never invoke Maintain Verify,
# read live settings/learning/config, or connect a test to the daily-use Broker.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
Assert-YimeCoreUnpackagedDataMaintenance
$expectedSid = 'S-1-5-21-2783006668-770716121-2150155084-1001'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($identity.User.Value -ne $expectedSid -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess -or $env:COMPUTERNAME -ine 'MYCOMPUTER' -or
    [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName -ine (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')) {
    throw 'Use ordinary same-user x64 Windows PowerShell 5.1 launched from Explorer on MYCOMPUTER.'
}
if (-not $PreflightOnly -and -not $ConfirmHostsClosedAndInputIdle) {
    throw 'Save/close Word, Notepad++, and Yime tools; confirm that keyboard/mouse will remain idle during the tests.'
}
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1') # Definitions only; no state/file inspection on import.
$installRoot = 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-62af8b507c91-9b3366b3'
$manifestHash = '9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e'
$clsid = '{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$productProfile = '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$legacyClsid = $null # Assigned below only from the hash-pinned public descriptor.
$environmentNames = @('TEMP','TMP','APPDATA','LOCALAPPDATA','YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE',
    'YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST','YIME_TEXTSERVICE_EXPERIMENT_PIPE')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }

function Get-RecordDigest($Record) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $Record -Depth 60 -Compress))))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}
function Assert-HostsClosed {
    $candidates = @(Get-CimInstance Win32_Process -Filter "Name='WINWORD.exe' OR Name='notepad++.exe' OR Name='notepad.exe' OR Name LIKE 'Yime%'" -Property Name,ProcessId,ExecutablePath)
    foreach ($candidate in $candidates) {
        if ($candidate.Name -in @('WINWORD.exe','notepad++.exe','notepad.exe') -or
            ([string]$candidate.ExecutablePath).StartsWith($installRoot+'\',[StringComparison]::OrdinalIgnoreCase) -and
            $candidate.Name -notin @('YimeCoreTrialRuntime.exe','YimeBroker.exe')) {
            throw 'A daily-use host or installed Yime tool is still open.'
        }
    }
}
function Assert-PinnedPackage {
    Assert-YimeCorePlainPath $installRoot
    $manifestPath = Join-Path $installRoot 'package-manifest.json'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ine $manifestHash) { throw 'Pinned installed manifest mismatch.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.product_version -ne '0.1.0-local.12' -or @($manifest.files).Count -ne 74) { throw 'Unexpected candidate inventory/version.' }
    $seen = @{}
    foreach ($file in $manifest.files) {
        $relative = [string]$file.path
        if (-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])\.\.?([/\\]|$)|:' -or
            $seen.ContainsKey($relative) -or [string]$file.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid installed manifest record.' }
        $seen[$relative] = $true
        $path = [IO.Path]::GetFullPath((Join-Path $installRoot $relative))
        if (-not $path.StartsWith($installRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Installed record escapes package.' }
        Assert-YimeCorePlainPath $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$file.bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$file.sha256) { throw 'Installed payload integrity mismatch.' }
    }
    $descriptor = Get-Content -LiteralPath (Join-Path $installRoot 'local-product.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($descriptor.version -ne '0.1.0-local.12' -or $descriptor.identity.clsid -ne $clsid -or $descriptor.identity.profile -ne $productProfile) {
        throw 'Installed public product identity mismatch.'
    }
    return $descriptor
}
function Get-SystemBaseline {
    $protected = [ordered]@{}
    foreach ($id in @('{35F67E9D-A54D-4177-9697-8B0AB71A9E04}', $legacyClsid, $clsid)) {
        foreach ($key in @("SOFTWARE\Classes\CLSID\$id", "SOFTWARE\Classes\WOW6432Node\CLSID\$id",
            "SOFTWARE\Microsoft\CTF\TIP\$id", "SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$id")) {
            $protected["machine/$key"] = Get-RecordDigest (Read-YimeCoreSystemKey 2147483650 $key)
        }
        $key = "Software\Microsoft\CTF\TIP\$id"
        $protected["user/$key"] = Get-RecordDigest (Read-YimeCoreSystemKey 2147483651 "$expectedSid\$key")
    }
    foreach ($key in @('Control Panel\International\User Profile','Keyboard Layout\Preload','Keyboard Layout\Substitutes',
        'Software\Microsoft\CTF\SortOrder')) {
        $protected["user/$key"] = Get-RecordDigest (Read-YimeCoreSystemKey 2147483651 "$expectedSid\$key")
    }
    # Enumerate Run names/types only, then fetch this product's single value; never fetch other Run commands.
    $runKey = "$expectedSid\Software\Microsoft\Windows\CurrentVersion\Run"
    $runNames = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments @{hDefKey=[uint32]2147483651;sSubKeyName=$runKey}
    if ($null -eq $runNames.ReturnValue -or $runNames.ReturnValue -notin @(0,2)) { throw 'Independent product Run metadata read failed.' }
    $runKinds = @(for ($i=0;$null -ne $runNames.sNames -and $i -lt @($runNames.sNames).Count;$i++) {
        if ($runNames.sNames[$i] -eq 'YimeCoreExperimentalTrial') { [int]$runNames.Types[$i] }
    })
    $runRecord = [ordered]@{name='YimeCoreExperimentalTrial';kinds=$runKinds;value=$null}
    if ($runKinds.Count -eq 1 -and $runKinds[0] -eq 1) {
        $run = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
            hDefKey=[uint32]2147483651;sSubKeyName=$runKey;sValueName='YimeCoreExperimentalTrial'}
        if ($null -eq $run.ReturnValue -or $run.ReturnValue -ne 0) { throw 'Independent product Run read failed.' }
        $runRecord.value = $run.sValue
    }
    $runMatches = $runKinds.Count -eq 1 -and $runKinds[0] -eq 1 -and $runRecord.value -ceq ('"'+(Join-Path $installRoot 'bin\YimeCoreTrialRuntime.exe')+'" -no-toolbar')
    $protected['user/product-Run-only'] = Get-RecordDigest $runRecord
    $uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial'
    $protected['user/product-uninstall'] = Get-RecordDigest (Read-YimeCoreSystemKey 2147483651 "$expectedSid\$uninstall")
    foreach ($key in @($uninstall,'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial')) {
        $protected["machine/$key"] = Get-RecordDigest (Read-YimeCoreSystemKey 2147483650 $key)
    }
    $tip = Read-YimeCoreSystemKey 2147483651 "$expectedSid\Software\Microsoft\CTF\TIP\$clsid\LanguageProfile\0x00000804\$productProfile"
    $enabled = @($tip.values | Where-Object { $_.name -eq 'Enable' -and $_.kind -eq 4 -and $_.value -eq 1 }).Count -eq 1
    $dlls = [ordered]@{}
    foreach ($arch in @('x64','x86')) {
        $key = if ($arch -eq 'x64') { "SOFTWARE\Classes\CLSID\$clsid\InprocServer32" } else { "SOFTWARE\Classes\WOW6432Node\CLSID\$clsid\InprocServer32" }
        $record = Read-YimeCoreSystemKey 2147483650 $key
        $value = @($record.values | Where-Object { $_.name -eq '' -and $_.kind -eq 1 })
        $dlls[$arch] = $value.Count -eq 1 -and $value[0].value -ieq (Join-Path $installRoot "$arch\YimeTextServiceExperiment.dll")
    }
    return [ordered]@{provider='out-of-process StdRegProv; no process-view fallback';sha256=$protected;
        current_tip_already_enabled=$enabled;registered_dll_matches=$dlls;product_run_matches=$runMatches}
}
function Get-RunningProductMetadata {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='YimeCoreTrialRuntime.exe' OR Name='YimeBroker.exe'" -Property Name,ProcessId,ParentProcessId,ExecutablePath,CreationDate)
    if ($rows.Count -ne 2) { throw 'Expected exactly the installed Runtime and its Broker before/after fixture execution.' }
    $runtime = @($rows | Where-Object { $_.Name -eq 'YimeCoreTrialRuntime.exe' })
    $broker = @($rows | Where-Object { $_.Name -eq 'YimeBroker.exe' })
    if ($runtime.Count -ne 1 -or $broker.Count -ne 1 -or $broker[0].ParentProcessId -ne $runtime[0].ProcessId) { throw 'Runtime/Broker ownership mismatch.' }
    $result = @(foreach ($row in $rows | Sort-Object Name) {
        $owner = Invoke-CimMethod -InputObject $row -MethodName GetOwnerSid
        if ($row.ExecutablePath -ine (Join-Path $installRoot "bin\$($row.Name)") -or $row.CreationDate -lt $boot -or
            $owner.ReturnValue -ne 0 -or $owner.Sid -ne $expectedSid) { throw 'Runtime/Broker metadata identity mismatch.' }
        [ordered]@{name=$row.Name;pid=[int]$row.ProcessId;parent_pid=[int]$row.ParentProcessId;image=$row.ExecutablePath;
            started_utc=$row.CreationDate.ToUniversalTime().ToString('o');owner_sid=$owner.Sid}
    })
    return [ordered]@{boot_utc=$boot.ToUniversalTime().ToString('o');processes=$result}
}
function Set-FixtureEnvironment([string]$Root) {
    Assert-YimeCorePlainPath $Root
    if ($Root.Length -gt 110 -or -not $Root.StartsWith($out+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Root)) {
        throw 'Expected a fresh short fixture child inside this run.'
    }
    $null = New-Item -ItemType Directory -Path $Root
    foreach ($leaf in @('tmp','local','roaming')) { $null = New-Item -ItemType Directory -Path (Join-Path $Root $leaf) }
    $env:TEMP = Join-Path $Root 'tmp'; $env:TMP = $env:TEMP
    $env:LOCALAPPDATA = Join-Path $Root 'local'; $env:APPDATA = Join-Path $Root 'roaming'
    foreach ($name in @('YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE','YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST','YIME_TEXTSERVICE_EXPERIMENT_PIPE')) {
        [Environment]::SetEnvironmentVariable($name,$null,'Process')
    }
}
function Start-OwnedTestChild([string]$Image,[string]$Arguments,[string]$Directory) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Image; $info.Arguments = $Arguments; $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Could not start owned fixture child.' }
        $null = $process.Handle # Retain the exact process handle; never kill by a discovered/global PID.
        return @{process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync();image=$Image}
    } catch {
        # Even startup/capture failure cleans only the process object just created here.
        if ($started) {
            try {
                if (-not $process.HasExited) { $process.Kill() }
                if (-not $process.WaitForExit(5000)) { $summary.children_stopped=$false }
            } catch { $summary.children_stopped=$false }
        }
        $process.Dispose(); throw 'Could not start owned fixture child.'
    }
}
function Stop-OwnedTestChild($Child) {
    if (-not $Child) { return }
    try {
        if (-not $Child.process.HasExited) { $Child.process.Kill() }
        if (-not $Child.process.WaitForExit(5000)) { throw 'Owned child did not stop within cleanup bound.' }
    } finally { $Child.process.Dispose() }
}
$required = @('candidate_popup_ownership_guard_verified','registered_key_sink_verified','registered_text_extent_anchor',
    'registered_candidate_commit','registered_default_candidate_keys_verified','registered_invalid_code_backspace_recovery_verified',
    'registered_direction_and_page_keys_verified','registered_english_shift_passthrough_verified','physical_mouse_candidate_selection_verified',
    'delayed_async_edit_completion_verified','failed_async_edit_recovery_verified','punctuation_text_extent_anchor_verified',
    'retained_language_bar_after_deactivation_verified','registered_focus_callbacks_verified',
    'registered_focus_cancellation_preserves_committed_text_verified','registered_delayed_focus_cancellation_verified',
    'registered_failed_focus_cancellation_text_preservation_verified')
function Convert-AllowedHostOutput([string]$Text,[string]$Architecture) {
    # Neither arbitrary stdout/stderr nor candidates/input/error payloads reach disk or the caller.
    if ($Text.Length -gt 65536) { throw 'Host output exceeded the outcome-only bound.' }
    $lines = @($Text -split '\r?\n')
    $outcomes = [ordered]@{}
    foreach ($name in $required) { $outcomes[$name] = @($lines | Where-Object { $_ -ceq "$name=true" }).Count -eq 1 }
    $outcomes['registered_language_bar_accepted'] = @($lines | Where-Object { $_ -ceq 'registered_language_bar_accepted=true' }).Count -eq 1
    $outcomes['registered_focus_outcome'] = if (@($lines | Where-Object { $_ -ceq 'registered_focus_outcome=unconfirmed_input_cancelled' }).Count -eq 1) { 'unconfirmed_input_cancelled' } else { 'missing' }
    $bits = if ($Architecture -eq 'x64') {64} else {32}
    $outcomes['architecture_verified'] = @($lines | Where-Object { $_ -ceq "architecture_bits=$bits" }).Count -eq 1
    return $outcomes
}

# Everything above this point defines/read-checks metadata only. Preflight never creates a file or child.
Assert-HostsClosed
$descriptor = Assert-PinnedPackage
$legacyClsid = [string]$descriptor.identity.legacy_clsid
if ($legacyClsid -notmatch '^\{[A-Fa-f0-9-]{36}\}$' -or $legacyClsid -eq $clsid) { throw 'Invalid historical protection identity.' }
$before = Get-SystemBaseline
if (-not $before.current_tip_already_enabled -or -not $before.registered_dll_matches.x64 -or -not $before.registered_dll_matches.x86 -or -not $before.product_run_matches) {
    throw 'Current local.12 TIP must already be enabled and both registered DLL paths must match; no automatic repair.'
}
$runtimeBefore = Get-RunningProductMetadata
if ($PreflightOnly) {
    [ordered]@{schema_version='yimecore-local12-private-host-preflight-v1';passed=$true;package_files_verified=74;
        install_root=$installRoot;manifest_sha256=$manifestHash;registry=$before;runtime=$runtimeBefore;
        token_integrity_checked=$false;note='Read-only preflight; full run inspects tokens after creating private compiler TEMP.';
        tests_executed=$false;files_written=$false;live_user_data_read=$false} | ConvertTo-Json -Depth 12
    return
}
$experimentParent = 'C:\dev\Yime\.tmp\yimecore-experiment'
Assert-YimeCorePlainPath $experimentParent
$out = Join-Path $experimentParent ('local12-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
if (Test-Path -LiteralPath $out) { throw 'Fixture root must be new.' }
$null = New-Item -ItemType Directory -Path $out
$summary = [ordered]@{schema_version='yimecore-local12-private-host-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    output_root=$out;install_root=$installRoot;manifest_sha256=$manifestHash;package_files_verified=74;initiating_sid=$expectedSid;
    baseline_before=$before;runtime_before=$runtimeBefore;results=@();passed=$false;failure_stage=$null;
    profile_activation='Harness calls EnableLanguageProfile(TRUE) for the already-enabled local product and activates its process; this is not registry-write-free.';
    default_input_method_setter_called=$false;protected_registry_unchanged=$false;runtime_unchanged=$false;
    environment_restored=$false;children_stopped=$true;live_user_data_read=$false;raw_output_recorded=$false;
    registered_host_acceptance=$false;manual_daily_use_acceptance=$false;reboot_gate_cleared=$false}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
$stage = 'initialize-private-token-inspection'
try {
    Set-FixtureEnvironment (Join-Path $out 'bootstrap')
    if ('YimeCore.LocalMaintenance.StandardUserLauncher' -as [type]) { throw 'Use a fresh native PowerShell process for pinned token-helper loading.' }
    Add-Type -Path (Join-Path $installRoot 'maintenance\local-runtime-launcher.cs')
    $tokens = @()
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    foreach ($processId in @($PID)+@($runtimeBefore.processes | ForEach-Object { $_.pid })) {
        $token = [YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess([int]$processId)
        if (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($token,$expectedSid,$sessionId)) { throw 'Expected same-user medium-integrity non-elevated process token.' }
        $tokens += [ordered]@{pid=$processId;sid=$token.Sid;elevated=$token.Elevated;integrity=$token.Integrity;session=$token.Session;app_container=$token.AppContainer;token_type=$token.TokenType}
    }
    $summary['standard_user_tokens'] = $tokens
    foreach ($arch in @('x64','x86')) {
        foreach ($mode in @('full','variable','shorthand')) {
            $stage = "$arch/$mode"
            Assert-HostsClosed
            $fixture = Join-Path $out "$arch\$mode"
            Set-FixtureEnvironment $fixture
            $pipe = '\\.\pipe\YimeBroker-local12-private-'+[guid]::NewGuid().ToString('N')
            $brokerChild = $null; $hostChild = $null
            $result = [ordered]@{architecture=$arch;mode=$mode;fixture_root=$fixture;passed=$false;exit_code=$null;timed_out=$false;outcomes=$null}
            $summary.results += $result
            try {
                $brokerChild = Start-OwnedTestChild (Join-Path $installRoot 'bin\YimeBroker.exe') (
                    '-index "{0}" -mode {1} -named-pipe "{2}"' -f (Join-Path $installRoot "indexes\$mode.yidx"),$mode,$pipe) $fixture
                Start-Sleep -Milliseconds 400
                if ($brokerChild.process.HasExited) { throw 'Fixture Broker exited before the host test.' }
                $hostChild = Start-OwnedTestChild (Join-Path $installRoot "$arch\YimeRegisteredHostTests.exe") ('"'+$pipe+'"') $fixture
                if (-not $hostChild.process.WaitForExit(45000)) { $result.timed_out=$true; throw 'Registered fixture host timed out.' }
                $result.exit_code = $hostChild.process.ExitCode
                if (-not $hostChild.stdout.Wait(5000)) { throw 'Host outcome capture timed out.' }
                $result.outcomes = Convert-AllowedHostOutput $hostChild.stdout.Result $arch
                $missing = @($required | Where-Object { -not $result.outcomes[$_] })
                if ($result.exit_code -ne 0 -or $missing.Count -or -not $result.outcomes.architecture_verified -or
                    $result.outcomes.registered_focus_outcome -ne 'unconfirmed_input_cancelled') { throw 'Registered host exit/outcome gate failed.' }
                $result.passed = $true
            } finally {
                foreach ($child in @($hostChild,$brokerChild)) {
                    try { Stop-OwnedTestChild $child } catch { $summary.children_stopped=$false }
                }
                # This result contains only allowlisted flags/counts; never write captured child streams.
                $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixture 'outcome.json') -Encoding UTF8
            }
            if (-not $summary.children_stopped) { throw 'Owned fixture child cleanup failed.' }
            Write-Host "Completed registered fixture: $arch/$mode"
        }
    }
    $summary.registered_host_acceptance = @($summary.results | Where-Object { $_.passed }).Count -eq 6
} catch {
    $summary.failure_stage = $stage # Deliberately do not echo/store exception or arbitrary child output.
} finally {
    $restoreFailures = @()
    foreach ($name in $environmentNames) {
        try { [Environment]::SetEnvironmentVariable($name,$originalEnvironment[$name],'Process') }
        catch { $restoreFailures += $name }
    }
    foreach ($name in $environmentNames) {
        try {
            if ([Environment]::GetEnvironmentVariable($name,'Process') -cne $originalEnvironment[$name]) { $restoreFailures += $name }
        } catch { $restoreFailures += $name }
    }
    $summary.environment_restored = $restoreFailures.Count -eq 0
    $summary['environment_restore_failures'] = @($restoreFailures | Select-Object -Unique)
    try {
        $summary['baseline_after'] = Get-SystemBaseline
        $summary.protected_registry_unchanged = (Get-RecordDigest $before) -ceq (Get-RecordDigest $summary.baseline_after)
    } catch { $summary['post_registry_check_failed'] = $true }
    try {
        $summary['runtime_after'] = Get-RunningProductMetadata
        $summary.runtime_unchanged = (Get-RecordDigest $runtimeBefore) -ceq (Get-RecordDigest $summary.runtime_after)
    } catch { $summary['post_runtime_check_failed'] = $true }
    try { $null = Assert-PinnedPackage; $summary['package_recheck_passed']=$true } catch { $summary['package_recheck_passed']=$false }
    $summary.passed = $summary.registered_host_acceptance -and $summary.children_stopped -and $summary.environment_restored -and
        $summary.protected_registry_unchanged -and $summary.runtime_unchanged -and $summary.package_recheck_passed -and -not $summary.failure_stage
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
}
Write-Host "Outcome-only evidence: $out"
if (-not $summary.passed) { throw 'Registered acceptance did not pass all gates. Stop here; provide only the evidence directory and failure stage from summary.json.' }
Write-Host 'PASS: installed local.12 x64/x86 registered fixtures; no manual daily-use or reboot gate is inferred.'
