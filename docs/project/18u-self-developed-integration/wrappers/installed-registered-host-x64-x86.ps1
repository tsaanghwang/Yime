[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$Pipe,
    [ValidateRange(15,300)][int]$TimeoutSeconds = 120
)
# Installed x64/x86 registered-host regression on the pinned development host (PS5).
# The child activates the registered TIP and commits synthetic text to the installed
# Broker (learning data may be written). Per-child frontend settings/logs are isolated.
# No installer, registration or default-input-method operation is performed.
# Invoke through tools/powershell/run_checked.py --edition ps5 --params-file <json>.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$utf8 = [Text.UTF8Encoding]::new($false)
$currentClsid = '{E40FA752-BB96-461D-A51D-F40EB437EC65}'

function Write-EvidenceJson($Value,[string]$Path) { [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 20),$utf8) }
function Get-FileRecord([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    return [ordered]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();last_write_utc=$item.LastWriteTimeUtc.ToString('o')}
}
function Read-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path); $reader = [IO.BinaryReader]::new($stream)
    try { $stream.Position = 0x3c; $offset = $reader.ReadUInt32(); $stream.Position = $offset + 4; return [int]$reader.ReadUInt16() } finally { $reader.Dispose() }
}
function Get-InstalledPayload {
    $records = [ordered]@{}
    foreach ($relative in @('x64\YimeTextServiceExperiment.dll','x64\YimeRegisteredHostTests.exe','x86\YimeTextServiceExperiment.dll','x86\YimeRegisteredHostTests.exe','bin\YimeBroker.exe','bin\YimeCoreTrialRuntime.exe')) {
        $records[$relative] = Get-FileRecord (Join-Path $InstallRoot $relative)
    }
    return $records
}
function Get-RegistrationObservation {
    $result = [ordered]@{}
    foreach ($pair in @(@{view='Registry64';dir='x64'},@{view='Registry32';dir='x86'})) {
        $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]$pair.view)
        try {
            $key = $hive.OpenSubKey('SOFTWARE\Classes\CLSID\' + $currentClsid + '\InprocServer32')
            if ($null -eq $key) { throw ('Current product COM registration is absent in ' + $pair.view) }
            try { $value = [string]$key.GetValue('') } finally { $key.Dispose() }
            $expected = Join-Path $InstallRoot ($pair.dir + '\YimeTextServiceExperiment.dll')
            if ($value -ine $expected) { throw ('COM path does not match installed product in ' + $pair.view + ': ' + $value) }
            $result[$pair.view] = $value
        } finally { $hive.Dispose() }
    }
    return $result
}
function Get-RuntimeObservation {
    $statusPath = Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial\runtime-status.json'
    $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($status.state -cne 'running' -or $status.install_root -ine $InstallRoot -or $status.pipe_name -cne $Pipe) { throw 'Runtime status does not identify the installed runtime and requested pipe.' }
    $processes = @(foreach ($member in @(@{id=[int]$status.runtime_pid;relative='bin\YimeCoreTrialRuntime.exe'},@{id=[int]$status.broker_pid;relative='bin\YimeBroker.exe'})) {
        $process = Get-Process -Id $member.id -ErrorAction Stop
        if ($process.Path -ine (Join-Path $InstallRoot $member.relative)) { throw ('Runtime status PID does not belong to the installed image: ' + $member.id) }
        [ordered]@{pid=$process.Id;image=$process.Path;started_utc=$process.StartTime.ToUniversalTime().ToString('o')}
    })
    return [ordered]@{status_updated_at=[string]$status.updated_at;processes=$processes}
}

$evidence = [IO.Path]::GetFullPath($EvidenceRoot)
if (Test-Path -LiteralPath $evidence) { throw 'EvidenceRoot must be new.' }
$null = [IO.Directory]::CreateDirectory($evidence)
$cases = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    schema_version='yimecore-installed-registered-host-x64-x86-v1';started_at=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME
    completed=$false;passed=$false;attempted_cases=0;passed_cases=0;expected_cases=6;install_root=$InstallRoot;pipe=$Pipe
    scope='Installed x64/x86 COM/TIP with installed Broker on the pinned development host; synthetic host text and input injection, not physical application acceptance. Installed baseline build, not the PR source build.'
    installed_broker_learning_may_be_written=$true;profile_activation_performed_by_test=$true;installer_or_registration_command_run=$false
    foreground_hosts_before=@(Get-Process -Name WINWORD,EXCEL,POWERPNT -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    payload_before=$null;payload_after=$null;registration_before=$null;registration_after=$null;runtime_before=$null;runtime_after=$null;cases=$cases;error=$null
}
$summaryPath = Join-Path $evidence 'summary.json'
Write-EvidenceJson $summary $summaryPath
try {
    if ($summary.foreground_hosts_before.Count -gt 0) { throw 'Close Office hosts before running the registered-host tests.' }
    $summary.payload_before = Get-InstalledPayload
    $summary.registration_before = Get-RegistrationObservation
    $summary.runtime_before = Get-RuntimeObservation
    Write-EvidenceJson $summary $summaryPath
    foreach ($architecture in @('x64','x86')) {
        foreach ($mode in @('full','variable','shorthand')) {
            $caseName = $architecture + '-' + $mode
            $caseRoot = Join-Path $evidence $caseName
            $null = [IO.Directory]::CreateDirectory($caseRoot)
            $fixture = Join-Path $caseRoot 't'
            $childEnvironment = [ordered]@{LOCALAPPDATA=(Join-Path $fixture 'l');APPDATA=(Join-Path $fixture 'r');TEMP=(Join-Path $fixture 'tmp');TMP=(Join-Path $fixture 'tmp')}
            $settingsPath = Join-Path $childEnvironment.LOCALAPPDATA 'YimeCore Experimental Trial\yimecore_experimental_toolbar_state.json'
            $seed = [ordered]@{version=1;revision=1;experiment_mode=$mode;ascii_mode=$false;full_shape=$false;ascii_punctuation=$true;traditionalization=$false;candidate_page_size=5;candidate_layout='vertical';candidate_font_preset='medium';candidate_font_family='Microsoft YaHei UI';candidate_annotation='key_sequence'}
            $testImage = Join-Path $InstallRoot ($architecture + '\YimeRegisteredHostTests.exe')
            $expectedMachine = if ($architecture -ceq 'x64') {0x8664} else {0x14c}
            $stdoutPath = Join-Path $caseRoot 'stdout.txt'; $stderrPath = Join-Path $caseRoot 'stderr.txt'
            $record = [ordered]@{
                architecture=$architecture;mode=$mode;started_at=[DateTime]::UtcNow.ToString('o');completed=$false
                image=$testImage;image_record=$null;pe_machine=('0x{0:x4}' -f $expectedMachine);pid=$null
                child_environment=$childEnvironment;settings_before=$seed;settings_after=$null
                timeout_seconds=$TimeoutSeconds;timed_out=$false;owned_process_stopped=$false;exit_code=$null
                flags=[ordered]@{};false_or_missing=@();functional_passed=$false;passed=$false;error=$null
            }
            $ownedProcess = $null; $stdoutFile = $null; $stderrFile = $null
            try {
                foreach ($path in @($childEnvironment.Values | Select-Object -Unique)) { $null = [IO.Directory]::CreateDirectory($path) }
                $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($settingsPath))
                Write-EvidenceJson $seed $settingsPath
                $record.image_record = Get-FileRecord $testImage
                if ((Read-PeMachine $testImage) -ne $expectedMachine) { throw 'Test executable PE architecture mismatch.' }
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $testImage; $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
                $startInfo.WorkingDirectory = $caseRoot; $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
                $startInfo.Arguments = $Pipe # PS5/.NET Framework: no ArgumentList; the pipe name has no spaces.
                foreach ($key in $childEnvironment.Keys) { $startInfo.Environment[$key] = $childEnvironment[$key] }
                foreach ($name in @('YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE','YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST','YIME_TEXTSERVICE_EXPERIMENT_PIPE')) { $null = $startInfo.Environment.Remove($name) }
                $stdoutFile = [IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $stderrFile = [IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $ownedProcess = [Diagnostics.Process]::new(); $ownedProcess.StartInfo = $startInfo
                if (-not $ownedProcess.Start()) { throw 'Could not start the test process.' }
                $record.pid = $ownedProcess.Id
                $stdoutCopy = $ownedProcess.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
                $stderrCopy = $ownedProcess.StandardError.BaseStream.CopyToAsync($stderrFile)
                if (-not $ownedProcess.WaitForExit($TimeoutSeconds * 1000)) {
                    $record.timed_out = $true
                    $ownedProcess.Kill() # Only the process this run created; never a tree, user application or Broker.
                    $record.owned_process_stopped = $ownedProcess.WaitForExit(5000)
                }
                $record.exit_code = $ownedProcess.ExitCode
                [Threading.Tasks.Task]::WaitAll(@($stdoutCopy,$stderrCopy),10000) | Out-Null
            } catch { $record.error = $_.Exception.ToString() }
            finally {
                if ($null -ne $stdoutFile) { $stdoutFile.Dispose() }
                if ($null -ne $stderrFile) { $stderrFile.Dispose() }
                if ($null -ne $ownedProcess) { $ownedProcess.Dispose() }
            }
            if (Test-Path -LiteralPath $stdoutPath) {
                $textOutput = [IO.File]::ReadAllText($stdoutPath,$utf8)
                $falseOrMissing = [Collections.Generic.List[string]]::new()
                foreach ($match in [regex]::Matches($textOutput,'(?m)^([a-z0-9_]+)=([^\r\n]*)\r?$')) {
                    $record.flags[$match.Groups[1].Value] = $match.Groups[2].Value
                    if ($match.Groups[2].Value -ceq 'false') { $falseOrMissing.Add($match.Groups[1].Value) }
                }
                $bits = if ($architecture -ceq 'x86') {'32'} else {'64'}
                if (-not $record.flags.Contains('architecture_bits') -or $record.flags['architecture_bits'] -cne $bits) { $falseOrMissing.Add('architecture_bits') }
                if (-not $record.flags.Contains('registered_candidate_commit')) { $falseOrMissing.Add('registered_candidate_commit') }
                $record.false_or_missing = @($falseOrMissing.ToArray())
            } else { $record.false_or_missing = @('stdout-missing') }
            if (Test-Path -LiteralPath $settingsPath) {
                $record.settings_after = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($record.settings_after.experiment_mode -cne $mode) { $record.error = [string]$record.error + "`nThe test mode changed during execution." }
            } else { $record.error = [string]$record.error + "`nSettings file is missing." }
            $record.functional_passed = [bool]($record.pid -and $record.exit_code -eq 0 -and -not $record.timed_out -and $record.false_or_missing.Count -eq 0 -and -not $record.error)
            $record.passed = $record.functional_passed
            $record.completed = $true; $record['finished_at'] = [DateTime]::UtcNow.ToString('o')
            Write-EvidenceJson $record (Join-Path $caseRoot 'result.json')
            $cases.Add($record)
            $summary.attempted_cases = $cases.Count
            $summary.passed_cases = @($cases.ToArray() | Where-Object {$_.passed}).Count
            Write-EvidenceJson $summary $summaryPath
            Write-Host ($caseName + ': passed=' + $record.passed + '; exit=' + $record.exit_code + '; flags=' + $record.flags.Count + '; false/missing=' + ($record.false_or_missing -join ','))
        }
    }
    $summary.payload_after = Get-InstalledPayload
    $summary.registration_after = Get-RegistrationObservation
    $summary.runtime_after = Get-RuntimeObservation
    $summary['payload_unchanged'] = (ConvertTo-Json -InputObject $summary.payload_before -Compress -Depth 5) -ceq (ConvertTo-Json -InputObject $summary.payload_after -Compress -Depth 5)
    $summary['runtime_processes_unchanged'] = (ConvertTo-Json -InputObject $summary.runtime_before.processes -Compress -Depth 5) -ceq (ConvertTo-Json -InputObject $summary.runtime_after.processes -Compress -Depth 5)
    $summary.completed = $true
    $summary.passed = $cases.Count -eq 6 -and $summary.passed_cases -eq 6 -and $summary.runtime_processes_unchanged -and $summary.payload_unchanged
} catch { $summary.error = $_.Exception.ToString() }
finally { $summary['finished_at'] = [DateTime]::UtcNow.ToString('o'); Write-EvidenceJson $summary $summaryPath }
if (-not $summary.passed) { throw ('Installed registered-host regression did not pass; preserve ' + $summaryPath) }
Write-Host ('PASS: six installed x64/x86 registered-host cases. Summary: ' + $summaryPath)
