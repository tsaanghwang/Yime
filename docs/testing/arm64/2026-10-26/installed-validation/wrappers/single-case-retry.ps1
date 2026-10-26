[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$Pipe,
    [ValidateRange(15,300)][int]$TimeoutSeconds = 90,
    [ValidateSet('x86')][string]$TargetArchitecture = 'x86',
    [ValidateSet('shorthand')][string]$TargetMode = 'shorthand',
    [switch]$EnableSelectionDiagnostics
)
# Installation must already have completed from the CI-passed, delivered R2 package.
# This is an installed integration test: the child activates the registered TIP and
# commits synthetic text to the installed Broker, which may update its learning data.
# Only per-child frontend settings/logs are isolated. No registration or installer
# operation is performed here. A timeout kills only the process created by this run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$deliveryRoot = 'C:\dev\Yime-deliveries\arm64-proart-20261026-r2'
$referenceManifestPath = Join-Path $deliveryRoot 'YimeCore-ARM64\payload\package-manifest.json'
$referenceManifestHash = 'a54c8c323460b8a2644feb24dd7da1d8ad7f87cca87da30089049bf8bc4dd89c'
$x64Tool = Join-Path $deliveryRoot 'acceptance-tools\YimeRegisteredHostTests-x64.exe'
$x64ToolHash = '3399d886545d0b809cb48461e961939a8866ccbf30ecac884871d8fd7f59ae72'
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-PlainLocalPath([string]$Value) {
    $full = [IO.Path]::GetFullPath($Value).TrimEnd('\')
    if ($full -notmatch '^[A-Za-z]:\\' -or $full.Substring(2).Contains(':')) { throw 'A local absolute path is required.' }
    for ($cursor = $full; $cursor; $cursor = [IO.Path]::GetDirectoryName($cursor)) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ('Linked paths are not permitted: ' + $cursor)
        }
    }
    return $full
}
function Write-EvidenceJson($Value,[string]$Path) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 20), $utf8)
}
function Read-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw 'Invalid DOS header.' }
        $stream.Position = 0x3c; $offset = $reader.ReadUInt32()
        if ($offset -lt 64 -or [uint64]$offset + 6 -gt [uint64]$stream.Length) { throw 'Invalid PE offset.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid PE signature.' }
        return [int]$reader.ReadUInt16()
    } finally { $reader.Dispose() }
}
function Get-FileRecord([string]$Path) {
    $pathValue = Assert-PlainLocalPath $Path
    $item = Get-Item -LiteralPath $pathValue -Force
    if ($item.PSIsContainer) { throw ('Expected a file: ' + $pathValue) }
    return [ordered]@{path=$pathValue;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $pathValue -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Assert-Record([string]$Path,$Expected) {
    $actual = Get-FileRecord $Path
    if ($actual.bytes -ne $Expected.bytes -or $actual.sha256 -cne $Expected.sha256) { throw ('R2 file identity mismatch: ' + $Path) }
    return $actual
}
function Assert-InstalledPayload {
    $manifestActual = Get-FileRecord (Join-Path $installedRoot 'package-manifest.json')
    if ($manifestActual.sha256 -cne $referenceManifestHash) { throw 'Installed manifest differs from the pinned R2 manifest.' }
    $checked = @(foreach ($entry in $manifest.files) {
        $relative = [string]$entry.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) { throw 'Invalid manifest relative path.' }
        $file = Assert-PlainLocalPath (Join-Path $installedRoot $relative)
        if (-not $file.StartsWith($installedRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes install root.' }
        Assert-Record $file $entry
    })
    return [ordered]@{passed=$true;manifest_sha256=$manifestActual.sha256;files=$checked}
}
function Get-RegistrationObservation {
    $result = [ordered]@{}
    foreach ($viewName in @('Registry64','Registry32')) {
        $view = [Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$viewName))
        $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
        try {
            $key = $hive.OpenSubKey('SOFTWARE\Classes\CLSID\{E40FA752-BB96-461D-A51D-F40EB437EC65}\InprocServer32')
            if ($null -eq $key) { throw ('Current product COM registration is absent in ' + $viewName) }
            try { $value = [string]$key.GetValue('') } finally { $key.Dispose() }
            $directory = if ($viewName -ceq 'Registry64') {'arm64'} else {'x86'}
            $expected = Join-Path $installedRoot ($directory + '\YimeTextServiceExperiment.dll')
            if ($value -ine $expected) { throw ('COM path does not match installed R2 in ' + $viewName + ': ' + $value) }
            $result[$viewName] = $value
        } finally { $hive.Dispose() }
    }
    return $result
}
function Get-LimitedProcessObservation([uint32]$ObservedProcessId) {
    # Win32_Process.ExecutablePath can be null for the elevated installer-owned
    # runtime. Query the actual process with the narrow supported access right;
    # neither a missing provider field nor runtime-status alone proves identity.
    $handle = [YimeArm64Acceptance.Native]::OpenProcess(0x1000,$false,$ObservedProcessId)
    try {
        if ($handle -eq [IntPtr]::Zero) {
            throw ('OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION) could not observe PID ' + $ObservedProcessId + '; Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $imageBuffer = [Text.StringBuilder]::new(32768)
        [uint32]$imageCapacity = 32768
        if (-not [YimeArm64Acceptance.Native]::QueryFullProcessImageNameW($handle,0,$imageBuffer,[ref]$imageCapacity)) {
            throw ('QueryFullProcessImageNameW failed for PID ' + $ObservedProcessId + '; Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        [long]$creationTime = 0; [long]$exitTime = 0; [long]$kernelTime = 0; [long]$userTime = 0
        if (-not [YimeArm64Acceptance.Native]::GetProcessTimes($handle,[ref]$creationTime,[ref]$exitTime,[ref]$kernelTime,[ref]$userTime)) {
            throw ('GetProcessTimes failed for PID ' + $ObservedProcessId + '; Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        [uint32]$processExitCode = 0
        if (-not [YimeArm64Acceptance.Native]::GetExitCodeProcess($handle,[ref]$processExitCode)) {
            throw ('GetExitCodeProcess failed for PID ' + $ObservedProcessId + '; Win32=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if ($processExitCode -ne 259 -or $exitTime -ne 0 -or $creationTime -le 0) {
            throw ('Runtime status PID is not an observed live process: ' + $ObservedProcessId)
        }
        return [ordered]@{
            pid=$ObservedProcessId;image=$imageBuffer.ToString();created_at=[DateTime]::FromFileTimeUtc($creationTime).ToString('o')
            creation_filetime=$creationTime;exit_code=$processExitCode;query_access='0x1000'
            provider='QueryFullProcessImageNameW + GetProcessTimes + GetExitCodeProcess'
        }
    } finally { if ($handle -ne [IntPtr]::Zero) { $null = [YimeArm64Acceptance.Native]::CloseHandle($handle) } }
}
function Convert-RuntimeTimestampToUtc($Value) {
    # PS 7.6 ConvertFrom-Json produces a DateTime for an ISO timestamp. Passing
    # that value to Parse(string) strips Kind and fractional seconds through the
    # PowerShell string conversion, then wrongly assumes the local timezone.
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        throw 'Runtime timestamp has unspecified timezone; identity cannot be established.'
    }
    if ($Value -isnot [string] -or $Value -notmatch 'T.*(?:Z|[+-][0-9]{2}:[0-9]{2})$') {
        throw 'Runtime timestamp must carry an explicit ISO timezone.'
    }
    return [DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
}
function Assert-ProcessCreationNotAfterStatus([long]$CreationFileTime,[DateTime]$StatusUpdatedUtc) {
    if ($StatusUpdatedUtc.Kind -ne [DateTimeKind]::Utc -or $CreationFileTime -le 0) { throw 'Process/status timestamps are not verified UTC values.' }
    if ($CreationFileTime -gt $StatusUpdatedUtc.ToFileTimeUtc()) {
        throw 'Runtime status predates its current process; PID reuse or stale status is possible.'
    }
}
function Get-InstalledRuntimeObservation {
    $status = Get-Content -LiteralPath $runtimeStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $statusUpdatedUtc = Convert-RuntimeTimestampToUtc $status.updated_at
    if ($status.schema_version -cne 'yimecore-trial-runtime-v1' -or $status.state -cne 'running' -or
        $status.install_root -ine $installedRoot -or $status.pipe_name -cne $Pipe -or
        $status.broker_path -ine (Join-Path $installedRoot 'bin\YimeBroker.exe')) {
        throw 'Runtime status does not identify the installed R2 runtime and requested pipe.'
    }
    $processes = @(foreach ($member in @(
        @{id=[int]$status.runtime_pid;relative='bin\YimeCoreTrialRuntime.exe'},
        @{id=[int]$status.broker_pid;relative='bin\YimeBroker.exe'})) {
        if ($member.id -le 0) { throw 'Invalid runtime/Broker PID.' }
        $live = Get-LimitedProcessObservation ([uint32]$member.id)
        if ($live.image -ine (Join-Path $installedRoot $member.relative)) {
            throw ('Runtime status PID does not belong to the installed image: PID ' + $member.id + ', observed image ' + $live.image)
        }
        Assert-ProcessCreationNotAfterStatus $live.creation_filetime $statusUpdatedUtc
        $live
    })
    $connection = [IO.Pipes.NamedPipeClientStream]::new('.', $Pipe.Substring(9), [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::Asynchronous, [Security.Principal.TokenImpersonationLevel]::Identification)
    try {
        $connection.Connect(2000)
        [uint32]$serverProcessId = 0
        if (-not [YimeArm64Acceptance.Native]::GetNamedPipeServerProcessId($connection.SafePipeHandle.DangerousGetHandle(),[ref]$serverProcessId)) {
            throw ('Cannot identify pipe server PID: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if ($serverProcessId -ne [uint32]$status.broker_pid) { throw 'The requested pipe is not served by the observed installed Broker.' }
    } finally { $connection.Dispose() }
    return [ordered]@{status_updated_at=$statusUpdatedUtc.ToString('o');pipe=$Pipe;pipe_server_pid=$serverProcessId;processes=$processes;restarts=$status.restarts}
}

$installedRoot = Assert-PlainLocalPath $InstallRoot
$outputRoot = Assert-PlainLocalPath $EvidenceRoot
$allowedOutput = Join-Path $repoRoot '.tmp'
if (-not $outputRoot.StartsWith($allowedOutput + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceRoot must be a new directory below this repository .tmp.' }
if (Test-Path -LiteralPath $outputRoot) { throw 'Preserve previous evidence; choose a fresh EvidenceRoot.' }
if ($outputRoot.StartsWith($installedRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be outside the installation.' }
if ($Pipe -cne '\\.\pipe\YimeBroker.YimeCoreTrial.v1') { throw 'This R2 acceptance wrapper requires the installed product stable pipe.' }
$reference = Get-FileRecord $referenceManifestPath
if ($reference.sha256 -cne $referenceManifestHash) { throw 'The reference R2 manifest changed.' }
$manifest = Get-Content -LiteralPath $referenceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestRecords = @{}
foreach ($entry in $manifest.files) {
    if ($manifestRecords.ContainsKey([string]$entry.path)) { throw 'Duplicate manifest path.' }
    $manifestRecords[[string]$entry.path] = $entry
}
$null = Assert-Record $x64Tool ([pscustomobject]@{bytes=458752;sha256=$x64ToolHash})
$runtimeStatusPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'YimeCore Experimental Trial\runtime-status.json'
$null = Assert-PlainLocalPath $runtimeStatusPath
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace YimeArm64Acceptance {
  public static class Native {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder image, ref uint size);
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out uint serverProcessId);
  }
}
'@
$observer = [Diagnostics.Process]::GetCurrentProcess()
[uint16]$observerProcessMachine = 0; [uint16]$observerNativeMachine = 0
if (-not [YimeArm64Acceptance.Native]::IsWow64Process2($observer.Handle,[ref]$observerProcessMachine,[ref]$observerNativeMachine) -or
    $observerNativeMachine -ne 0xaa64 -or (Read-PeMachine $observer.MainModule.FileName) -ne 0xaa64) {
    throw 'Run this wrapper with the verified native ARM64 PowerShell observer.'
}
$expectedFlags = @(
    'candidate_popup_ownership_guard_verified', 'registered_english_shift_passthrough_verified',
    'physical_mouse_candidate_selection_verified', 'delayed_async_edit_completion_verified',
    'punctuation_text_extent_anchor_verified', 'registered_key_sink_verified',
    'registered_language_bar_accepted', 'registered_text_extent_anchor', 'registered_focus_callbacks_verified',
    'registered_focus_cancellation_preserves_committed_text_verified', 'registered_candidate_commit',
    'registered_default_candidate_keys_verified', 'registered_invalid_initial_code_rejection_verified',
    'registered_invalid_code_rejection_verified', 'registered_invalid_code_backspace_recovery_verified',
    'registered_direction_and_page_keys_verified', 'registered_delayed_focus_cancellation_verified',
    'failed_async_edit_recovery_verified', 'registered_failed_focus_cancellation_text_preservation_verified',
    'retained_language_bar_after_deactivation_verified'
)
$cases = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema_version='yimecore-arm64-r2-installed-registered-host-retry-v1';started_at=[DateTime]::UtcNow.ToString('o')
    retry_of='C:\dev\Yime\.tmp\arm64-reg-r2-20261026-acc00c7b\x86-shorthand\result.json'
    original_matrix_preserved=$true;target_architecture=$TargetArchitecture;target_mode=$TargetMode
    completed=$false;passed=$false;attempted_cases=0;passed_cases=0;install_root=$installedRoot;reference_manifest_sha256=$referenceManifestHash
    wrapper=(Get-FileRecord $PSCommandPath);pipe=$Pipe;expected_cases=1;expected_flags=$expectedFlags;cases=$cases
    observer=[ordered]@{image=$observer.MainModule.FileName;pe_machine='0xaa64';native_machine=('0x{0:x4}' -f $observerNativeMachine);process_machine=('0x{0:x4}' -f $observerProcessMachine)}
    scope='Installed COM/TIP with installed Broker; synthetic host text and input injection, not physical application acceptance.'
    child_frontend_settings_isolated=$true;parent_environment_changed=$false
    installed_broker_learning_may_be_written=$true;profile_activation_performed_by_test=$true
    installer_or_registration_command_run=$false;tool_menu_smoke_enabled=$false
    selection_key_diagnostics_enabled=[bool]$EnableSelectionDiagnostics
    payload_before=$null;payload_after=$null;registration_before=$null;registration_after=$null
    runtime_before=$null;runtime_after=$null;error=$null
}
$null = [IO.Directory]::CreateDirectory($outputRoot)
$summaryPath = Join-Path $outputRoot 'summary.json'
Write-EvidenceJson $summary $summaryPath
try {
    $summary.payload_before = Assert-InstalledPayload
    $summary.registration_before = Get-RegistrationObservation
    $summary.runtime_before = Get-InstalledRuntimeObservation
    Write-EvidenceJson $summary $summaryPath
    foreach ($architecture in @($TargetArchitecture)) {
        foreach ($mode in @($TargetMode)) {
            $caseName = $architecture + '-' + $mode
            $caseRoot = Join-Path $outputRoot $caseName
            $null = [IO.Directory]::CreateDirectory($caseRoot)
            $fixture = Join-Path $caseRoot 't'
            $childEnvironment = [ordered]@{
                LOCALAPPDATA=(Join-Path $fixture 'l');APPDATA=(Join-Path $fixture 'r')
                TEMP=(Join-Path $fixture 'tmp');TMP=(Join-Path $fixture 'tmp')
            }
            $settingsPath = Join-Path $childEnvironment.LOCALAPPDATA 'YimeCore Experimental Trial\yimecore_experimental_toolbar_state.json'
            $seed = [ordered]@{version=1;revision=1;experiment_mode=$mode;ascii_mode=$false;full_shape=$false;ascii_punctuation=$true;traditionalization=$false;candidate_page_size=5;candidate_layout='vertical';candidate_font_preset='medium';candidate_font_family='Microsoft YaHei UI';candidate_annotation='key_sequence'}
            $testImage = if ($architecture -ceq 'x64') {$x64Tool} else {Join-Path $installedRoot ($architecture + '\YimeRegisteredHostTests.exe')}
            $expectedMachine = if ($architecture -ceq 'arm64') {0xaa64} elseif ($architecture -ceq 'x64') {0x8664} else {0x14c}
            $dllDirectory = if ($architecture -ceq 'x86') {'x86'} else {'arm64'}
            $expectedDll = Join-Path $installedRoot ($dllDirectory + '\YimeTextServiceExperiment.dll')
            $expectedDllHash = $manifestRecords[$dllDirectory + '/YimeTextServiceExperiment.dll'].sha256
            $stdoutPath = Join-Path $caseRoot 'stdout.txt'; $stderrPath = Join-Path $caseRoot 'stderr.txt'
            $record = [ordered]@{
                architecture=$architecture;mode=$mode;started_at=[DateTime]::UtcNow.ToString('o');completed=$false
                image=$testImage;image_record=$null;pe_machine=('0x{0:x4}' -f $expectedMachine);pid=$null;pid_created_at=$null
                observed_process_machine=$null;observed_native_machine=$null
                expected_dll=$expectedDll;expected_dll_sha256=$expectedDllHash;module_observation_status='not_started'
                module_observations=@();module_observation_errors=@();module_observation_attempts=0;module_verified=$false
                foreground_samples=@();selection_key_diagnostics_enabled=[bool]$EnableSelectionDiagnostics
                child_environment=$childEnvironment;settings_before=$seed;settings_after=$null
                timeout_seconds=$TimeoutSeconds;timed_out=$false;owned_process_stopped=$false;exit_code=$null
                stdout=$stdoutPath;stderr=$stderrPath;log_capture_complete=$false
                missing_or_false_flags=@();functional_passed=$false;passed=$false;error=$null
            }
            $ownedProcess = $null; $stdoutFile = $null; $stderrFile = $null; $stdoutCopy = $null; $stderrCopy = $null
            $seenModules = @{}; $moduleErrors = [Collections.Generic.List[string]]::new()
            $foregroundSamples = [Collections.Generic.List[object]]::new()
            try {
                if ($settingsPath.Length -gt 240 -or $childEnvironment.TEMP.Length -gt 120) { throw 'EvidenceRoot is too long for the native state-file APIs.' }
                foreach ($path in @($childEnvironment.Values | Select-Object -Unique)) { $null = [IO.Directory]::CreateDirectory($path) }
                $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($settingsPath))
                Write-EvidenceJson $seed $settingsPath
                Write-EvidenceJson $seed (Join-Path $caseRoot 'settings-before.json')
                $expectedTool = if ($architecture -ceq 'x64') {[pscustomobject]@{bytes=458752;sha256=$x64ToolHash}} else {$manifestRecords[$architecture + '/YimeRegisteredHostTests.exe']}
                $record.image_record = Assert-Record $testImage $expectedTool
                if ((Read-PeMachine $testImage) -ne $expectedMachine) { throw 'Test executable PE architecture mismatch.' }
                $null = Assert-Record $expectedDll $manifestRecords[$dllDirectory + '/YimeTextServiceExperiment.dll']
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $testImage; $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
                $startInfo.WorkingDirectory = $caseRoot; $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
                $startInfo.ArgumentList.Add($Pipe)
                foreach ($key in $childEnvironment.Keys) { $startInfo.Environment[$key] = $childEnvironment[$key] }
                $null = $startInfo.Environment.Remove('YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE')
                $null = $startInfo.Environment.Remove('YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST')
                $null = $startInfo.Environment.Remove('YIME_TEXTSERVICE_EXPERIMENT_PIPE')
                $null = $startInfo.Environment.Remove('YIME_TEXTSERVICE_EXPERIMENT_KEY_DIAGNOSTICS')
                if ($EnableSelectionDiagnostics) { $startInfo.Environment['YIME_TEXTSERVICE_EXPERIMENT_KEY_DIAGNOSTICS'] = '1' }
                $stdoutFile = [IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $stderrFile = [IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $ownedProcess = [Diagnostics.Process]::new(); $ownedProcess.StartInfo = $startInfo
                if (-not $ownedProcess.Start()) { throw 'Could not start the test process.' }
                $ownedHandle = $ownedProcess.Handle # Hold this exact process handle throughout cleanup; never rediscover a PID for killing.
                $record.pid = $ownedProcess.Id; $record.pid_created_at = $ownedProcess.StartTime.ToUniversalTime().ToString('o')
                $stdoutCopy = $ownedProcess.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
                $stderrCopy = $ownedProcess.StandardError.BaseStream.CopyToAsync($stderrFile)
                [uint16]$childProcessMachine = 0; [uint16]$childNativeMachine = 0
                if ([YimeArm64Acceptance.Native]::IsWow64Process2($ownedHandle,[ref]$childProcessMachine,[ref]$childNativeMachine)) {
                    $record.observed_process_machine = '0x{0:x4}' -f $childProcessMachine
                    $record.observed_native_machine = '0x{0:x4}' -f $childNativeMachine
                }
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $record.module_observation_status = 'not_observed'
                while (-not $ownedProcess.HasExited) {
                    $foregroundWindow = [YimeArm64Acceptance.Native]::GetForegroundWindow()
                    [uint32]$foregroundProcessId = 0
                    if ($foregroundWindow -ne [IntPtr]::Zero) {
                        $null = [YimeArm64Acceptance.Native]::GetWindowThreadProcessId($foregroundWindow,[ref]$foregroundProcessId)
                    }
                    $foregroundSamples.Add([ordered]@{
                        observed_at=[DateTime]::UtcNow.ToString('o');window=('0x{0:x}' -f $foregroundWindow.ToInt64())
                        process_id=$foregroundProcessId;belongs_to_test=($foregroundProcessId -eq [uint32]$record.pid)
                        note='OS foreground PID only; no window title/text read. This does not directly prove TSF key focus.'
                    })
                    if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                        $record.timed_out = $true
                        $ownedProcess.Kill() # Kill only our process, never a tree, user application or Broker.
                        $record.owned_process_stopped = $true
                        if (-not $ownedProcess.WaitForExit(5000)) { throw 'Timed-out owned process did not exit.' }
                        break
                    }
                    if (-not $record.module_verified) {
                        $record.module_observation_attempts++
                        try {
                            $ownedProcess.Refresh()
                            foreach ($module in @($ownedProcess.Modules | Where-Object ModuleName -eq 'YimeTextServiceExperiment.dll')) {
                                if (-not $seenModules.ContainsKey($module.FileName)) {
                                    $moduleFile = Get-FileRecord $module.FileName
                                    $matches = $module.FileName -ieq $expectedDll -and $moduleFile.sha256 -ceq $expectedDllHash
                                    $seenModules[$module.FileName] = [ordered]@{observed_at=[DateTime]::UtcNow.ToString('o');path=$module.FileName;sha256=$moduleFile.sha256;bytes=$moduleFile.bytes;matches_expected=$matches}
                                }
                            }
                            $observations = @($seenModules.Values)
                            $record.module_verified = $observations.Count -eq 1 -and @($observations | Where-Object {$_.matches_expected}).Count -eq 1
                            if ($record.module_verified) { $record.module_observation_status = 'verified' }
                            elseif ($observations.Count) { $record.module_observation_status = 'unexpected_module' }
                        } catch {
                            $message = $_.Exception.Message
                            if (-not $moduleErrors.Contains($message)) { $moduleErrors.Add($message) }
                        }
                    }
                    Start-Sleep -Milliseconds 100
                }
                if (-not $ownedProcess.WaitForExit(5000)) { throw 'Owned process exit could not be observed.' }
                $record.exit_code = $ownedProcess.ExitCode
            } catch { $record.error = $_.Exception.ToString() }
            finally {
                if ($null -ne $ownedProcess) {
                    try {
                        if ($record.pid -and -not $ownedProcess.HasExited) {
                            $ownedProcess.Kill(); $record.owned_process_stopped = $true
                            if (-not $ownedProcess.WaitForExit(5000)) { throw 'Owned-process cleanup timed out.' }
                        }
                        if ($record.pid -and $ownedProcess.HasExited) { $record.exit_code = $ownedProcess.ExitCode }
                        if ($null -ne $stdoutCopy -and $null -ne $stderrCopy) {
                            if (-not $stdoutCopy.Wait(5000) -or -not $stderrCopy.Wait(5000)) { throw 'Log stream capture did not finish.' }
                            $record.log_capture_complete = $true
                        }
                    } catch { $record.error = [string]$record.error + "`nCleanup: " + $_.Exception.ToString() }
                }
                if ($null -ne $stdoutFile) { $stdoutFile.Dispose() }
                if ($null -ne $stderrFile) { $stderrFile.Dispose() }
                if ($null -ne $ownedProcess) { $ownedProcess.Dispose() }
                $record.module_observations = @($seenModules.Values)
                $record.module_observation_errors = @($moduleErrors.ToArray())
                $record.foreground_samples = @($foregroundSamples.ToArray())
                if (-not $record.module_verified -and $moduleErrors.Count -gt 0 -and $seenModules.Count -eq 0) { $record.module_observation_status = 'observation_failed' }
            }
            if (Test-Path -LiteralPath $stdoutPath) {
                $textOutput = [IO.File]::ReadAllText($stdoutPath,$utf8)
                $missing = [Collections.Generic.List[string]]::new()
                foreach ($flag in $expectedFlags) {
                    $values = @([regex]::Matches($textOutput, '(?m)^' + [regex]::Escape($flag) + '=([^\r\n]*)\r?$') | ForEach-Object {$_.Groups[1].Value})
                    if ($values.Count -ne 1 -or $values[0] -cne 'true') { $missing.Add($flag) }
                }
                if ($textOutput -notmatch '(?m)^registered_focus_outcome=unconfirmed_input_cancelled\r?$') { $missing.Add('registered_focus_outcome') }
                $bits = if ($architecture -ceq 'x86') {32} else {64}
                if ($textOutput -notmatch ('(?m)^architecture_bits=' + $bits + '\r?$')) { $missing.Add('architecture_bits') }
                $record.missing_or_false_flags = @($missing.ToArray())
                $record['stdout_record'] = Get-FileRecord $stdoutPath
                if (Test-Path -LiteralPath $stderrPath) { $record['stderr_record'] = Get-FileRecord $stderrPath }
                else { $record.error = [string]$record.error + "`nStderr file is missing." }
            } else { $record.missing_or_false_flags = $expectedFlags }
            if (Test-Path -LiteralPath $settingsPath) {
                try {
                    $record.settings_after = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    Write-EvidenceJson $record.settings_after (Join-Path $caseRoot 'settings-after.json')
                    if ($record.settings_after.experiment_mode -cne $mode) { throw 'The test mode changed during execution.' }
                } catch { $record.error = [string]$record.error + "`nSettings: " + $_.Exception.ToString() }
            } else { $record.error = [string]$record.error + "`nSettings file is missing." }
            $record.functional_passed = $record.pid -and $record.exit_code -eq 0 -and -not $record.timed_out -and
                $record.log_capture_complete -and $record.missing_or_false_flags.Count -eq 0 -and -not $record.error
            $record.passed = [bool]($record.functional_passed -and $record.module_verified)
            $diagnosticPath = Join-Path $childEnvironment.LOCALAPPDATA 'YimeCore Experimental Trial\evidence\tsf-key-host.log'
            if (Test-Path -LiteralPath $diagnosticPath) { $record['selection_key_diagnostic_record'] = Get-FileRecord $diagnosticPath }
            $record.completed = $true; $record['finished_at'] = [DateTime]::UtcNow.ToString('o')
            Write-EvidenceJson $record (Join-Path $caseRoot 'result.json')
            $cases.Add($record)
            $summary.attempted_cases = $cases.Count
            $summary.passed_cases = @($cases.ToArray() | Where-Object {$_.passed}).Count
            Write-EvidenceJson $summary $summaryPath
            Write-Host ($caseName + ': functional=' + $record.functional_passed + '; module=' + $record.module_observation_status + '; exit=' + $record.exit_code)
        }
    }
    $summary.payload_after = Assert-InstalledPayload
    $summary.registration_after = Get-RegistrationObservation
    $summary.runtime_after = Get-InstalledRuntimeObservation
    $runtimeUnchanged = (ConvertTo-Json -InputObject $summary.runtime_before.processes -Compress) -ceq (ConvertTo-Json -InputObject $summary.runtime_after.processes -Compress)
    $summary['runtime_processes_unchanged'] = $runtimeUnchanged
    $summary['passed_cases'] = @($cases.ToArray() | Where-Object {$_.passed}).Count
    $summary.completed = $true
    $summary.passed = $cases.Count -eq 1 -and $summary.passed_cases -eq 1 -and $runtimeUnchanged
} catch { $summary.error = $_.Exception.ToString() }
finally {
    $summary['finished_at'] = [DateTime]::UtcNow.ToString('o')
    Write-EvidenceJson $summary $summaryPath
}
if (-not $summary.passed) { throw ('Installed registered-host acceptance did not pass; preserve ' + $summaryPath) }
Write-Host ('PASS: x86 shorthand retry with matching loaded DLL evidence. Preserve the original eight passes and failed attempt. Summary: ' + $summaryPath)
