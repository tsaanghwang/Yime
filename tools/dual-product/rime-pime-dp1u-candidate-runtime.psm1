# Candidate-only native runtime adapter. Import performs no product operation.
# The candidate controller must retain admission and full payload leases. This
# adapter additionally pins its two executable images and installed state config.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:LiveContexts=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
if(-not ('Yime.CandidateRuntime.Facts' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.cs') }
. (Join-Path $PSScriptRoot 'rime-pime-directed-stop-contract.ps1')

function Assert-CandidateRuntimeLexicalPath([string]$Path) {
    if($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '(^|\\)\.\.?($|\\)' -or $Path.Substring(2).Contains(':') -or $Path -cne [IO.Path]::GetFullPath($Path).TrimEnd('\')) { throw 'Expected canonical absolute local path.' }
}

function Assert-CandidateRuntimePath([string]$Path,[bool]$Directory=$true) {
    Assert-CandidateRuntimeLexicalPath $Path
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Indirect runtime path rejected.' }
    $parent=if($Directory){[IO.DirectoryInfo]$item}else{$item.Directory}
    while($null -ne $parent) { if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect runtime ancestor rejected.'};$parent=$parent.Parent }
    return $Path
}

function Assert-CandidateRuntimeCaller([string]$TargetUserSid) {
    if([Environment]::MachineName -ieq 'MYCOMPUTER'){throw 'Candidate runtime execution is forbidden on the development host.'}
    $facts=[Yime.CandidateRuntime.Facts]::OpenProcessFacts($PID)
    try {
        if($TargetUserSid -cne $facts.Sid -or $facts.Elevated -or $facts.PackageQuery -ne 15700){throw 'Runtime requires the approved SID in a non-elevated unpackaged process.'}
    } finally {$facts.Dispose()}
}

function Open-CandidateRuntimeImage([string]$Path,[string]$Hash) {
    if($Hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid runtime source hash.'}
    $null=Assert-CandidateRuntimePath $Path $false
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $null=[Yime.CandidateRuntime.Facts]::VerifyFileHandle($stream,$Path)
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
        if($actual -cne $Hash){throw 'Runtime image/configuration hash mismatch.'}
        $stream.Position=0;return $stream
    } catch {$stream.Dispose();throw}
}

function Assert-CandidateRuntimeConfiguration([object]$Config,[string]$InstallRoot,[string]$StateRoot,[string]$TargetUserSid) {
    $fields=@('schema_version','install_root','state_root','target_user_sid')
    $actual=@($Config.PSObject.Properties.Name)
    if($actual.Count -ne 4 -or @(Compare-Object $fields $actual).Count){throw 'Invalid candidate state configuration fields.'}
    foreach($field in $fields){if($Config.$field -isnot [string]){throw 'Candidate state configuration requires literal strings.'}}
    if($Config.schema_version -cne 'yime-rime-pime-candidate-state-v1' -or $Config.install_root -cne $InstallRoot -or $Config.state_root -cne $StateRoot -or $Config.target_user_sid -cne $TargetUserSid){throw 'Candidate state configuration binding mismatch.'}
    if($InstallRoot -ieq $StateRoot -or $InstallRoot.StartsWith($StateRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $StateRoot.StartsWith($InstallRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime payload and state roots overlap.'}
}

function Open-CandidateRuntimeBoundary {
    param([string]$InstallRoot,[string]$StateRoot,[string]$TargetUserSid,[string]$LauncherSha256,[string]$BackendSha256,[string]$ConfigurationSha256)
    Assert-CandidateRuntimeCaller $TargetUserSid
    $null=Assert-CandidateRuntimePath $InstallRoot
    $null=Assert-CandidateRuntimePath $StateRoot
    $null=Assert-CandidateRuntimePath (Join-Path $StateRoot 'Roaming')
    $null=Assert-CandidateRuntimePath (Join-Path $StateRoot 'Local')
    $leases=[Collections.Generic.List[object]]::new()
    try {
        $launcher=Join-Path $InstallRoot 'PIMELauncher.exe';$backend=Join-Path $InstallRoot 'go-backend\server.exe'
        $leases.Add((Open-CandidateRuntimeImage $launcher $LauncherSha256))
        $leases.Add((Open-CandidateRuntimeImage $backend $BackendSha256))
        $configPath=Join-Path $InstallRoot 'rime-pime-candidate-state.json'
        $configLease=Open-CandidateRuntimeImage $configPath $ConfigurationSha256;$leases.Add($configLease)
        if($configLease.Length -gt 16384){throw 'Oversized candidate state configuration.'}
        $reader=[IO.StreamReader]::new($configLease,[Text.UTF8Encoding]::new($false,$true),$false,1024,$true)
        try {$config=$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}
        Assert-CandidateRuntimeConfiguration $config $InstallRoot $StateRoot $TargetUserSid
        return [pscustomobject]@{install_root=$InstallRoot;state_root=$StateRoot;target_user_sid=$TargetUserSid;launcher=$launcher;backend=$backend;leases=$leases;launcher_sha256=$LauncherSha256;backend_sha256=$BackendSha256;configuration_sha256=$ConfigurationSha256}
    } catch {foreach($lease in $leases){$lease.Dispose()};throw}
}

function Get-CandidateRuntimeProcesses([object]$Boundary) {
    $result=[Collections.Generic.List[object]]::new()
    try {
        foreach($record in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            if([string]::IsNullOrWhiteSpace([string]$record.ExecutablePath) -and [string]$record.Name -in @('PIMELauncher.exe','server.exe')){throw 'Relevant runtime image path is unreadable; quiescence cannot be proved.'}
            if([string]$record.ExecutablePath -ine $Boundary.launcher -and [string]$record.ExecutablePath -ine $Boundary.backend){continue}
            $facts=[Yime.CandidateRuntime.Facts]::OpenProcessFacts([int]$record.ProcessId)
            $process=$null
            try {
                $process=[Diagnostics.Process]::GetProcessById($facts.Pid);$null=$process.Handle
                if($facts.Sid -cne $Boundary.target_user_sid -or $facts.Elevated -or $facts.PackageQuery -ne 15700 -or $facts.Image -ine $record.ExecutablePath -or $process.StartTime.ToUniversalTime().ToFileTimeUtc() -ne $facts.CreationFileTime -or [Math]::Abs($record.CreationDate.ToUniversalTime().ToFileTimeUtc()-$facts.CreationFileTime) -gt 10){throw 'Runtime process identity changed or is foreign/elevated.'}
                $result.Add([pscustomobject]@{path=$facts.Image;pid=$facts.Pid;start_utc=$process.StartTime.ToUniversalTime().ToString('o');start_filetime_utc=$facts.CreationFileTime.ToString();owner_sid=$facts.Sid;parent_pid=[int]$record.ParentProcessId;command_line=[string]$record.CommandLine;process=$process;facts=$facts})
                $facts=$null;$process=$null
            } finally {if($facts){$facts.Dispose()};if($process){$process.Dispose()}}
        }
        return $result.ToArray()
    } catch {foreach($item in $result){$item.facts.Dispose();$item.process.Dispose()};throw}
}

function Assert-CandidateRuntimeReadyResponse([object]$Response,[int]$ExpectedSequence) {
    $fields=@('seqNum','success','schema_version','native_rime_ready','schema_id','backend_pid')
    $actual=@($Response.PSObject.Properties.Name)
    if($actual.Count -ne $fields.Count -or @(Compare-Object $fields $actual).Count){throw 'Incomplete or unknown native runtime readiness shape.'}
    if(($Response.seqNum -isnot [int] -and $Response.seqNum -isnot [long]) -or $Response.seqNum -ne $ExpectedSequence -or $Response.success -isnot [bool] -or -not $Response.success -or $Response.native_rime_ready -isnot [bool] -or -not $Response.native_rime_ready -or $Response.schema_version -isnot [string] -or $Response.schema_version -cne 'yime-rime-pime-native-ready-v1' -or $Response.schema_id -isnot [string] -or $Response.schema_id -notmatch '^yime(?:_[a-z0-9_]+)?$' -or ($Response.backend_pid -isnot [int] -and $Response.backend_pid -isnot [long]) -or $Response.backend_pid -le 0 -or $Response.backend_pid -gt [int]::MaxValue){throw 'Native Rime readiness was not proved.'}
    return $Response
}

function Get-CandidateRuntimeContext([object]$Context) {
    if($null -eq $Context -or $Context.PSObject.Properties.Name -notcontains 'context_id' -or -not $script:LiveContexts.ContainsKey([string]$Context.context_id) -or -not [object]::ReferenceEquals($script:LiveContexts[[string]$Context.context_id].public,$Context)){throw 'Original live runtime context required.'}
    return $script:LiveContexts[$Context.context_id]
}

function Start-RimePimeCandidateRuntime {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$LauncherSha256,[Parameter(Mandatory)][string]$BackendSha256,[Parameter(Mandatory)][string]$ConfigurationSha256)
    $boundary=Open-CandidateRuntimeBoundary @PSBoundParameters
    try {
        $old=@(Get-CandidateRuntimeProcesses $boundary)
        try {if($old.Count){throw 'Owned runtime already present; observe/stop it before starting another instance.'}} finally {foreach($p in $old){$p.facts.Dispose();$p.process.Dispose()}}
        $start=[Diagnostics.ProcessStartInfo]::new($boundary.launcher)
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$InstallRoot
        $start.EnvironmentVariables['APPDATA']=Join-Path $StateRoot 'Roaming'
        $start.EnvironmentVariables['LOCALAPPDATA']=Join-Path $StateRoot 'Local'
        $process=[Diagnostics.Process]::Start($start);$null=$process.Handle
        $public=[pscustomobject]@{context_id=[Guid]::NewGuid().ToString('N');launcher_pid=$process.Id;runtime_ready=$false;dp1_u_acceptance_passed=$false}
        $entry=[pscustomobject]@{public=$public;boundary=$boundary;process=$process;start_filetime=$process.StartTime.ToUniversalTime().ToFileTimeUtc()}
        $script:LiveContexts.Add($public.context_id,$entry)
        return $public
    } catch {foreach($lease in $boundary.leases){$lease.Dispose()};throw}
}

function Get-RimePimeCandidateRuntimeContext {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$LauncherSha256,[Parameter(Mandatory)][string]$BackendSha256,[Parameter(Mandatory)][string]$ConfigurationSha256)
    $boundary=Open-CandidateRuntimeBoundary @PSBoundParameters
    $bound=@();$retained=$false;$process=$null
    try {
        $bound=@(Get-CandidateRuntimeProcesses $boundary)
        if($bound.Count -eq 0){return $null}
        # Reuse the exact root/SID/parent/start topology contract before adopting
        # a process after the initiating controller has exited. No stop is sent.
        $request=New-YimePimeDirectedStopRequest -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid -BoundProcesses $bound
        $process=[Diagnostics.Process]::GetProcessById($request.launcher_pid);$null=$process.Handle
        $start=$process.StartTime.ToUniversalTime().ToFileTimeUtc()
        if($process.HasExited -or $start.ToString() -cne $request.launcher_start_filetime_utc){throw 'Owned watchdog changed during recovery adoption.'}
        $public=[pscustomobject]@{context_id=[Guid]::NewGuid().ToString('N');launcher_pid=$process.Id;runtime_ready=$false;adopted_existing=$true;dp1_u_acceptance_passed=$false}
        $script:LiveContexts.Add($public.context_id,[pscustomobject]@{public=$public;boundary=$boundary;process=$process;start_filetime=$start})
        $retained=$true;return $public
    } finally {
        foreach($p in $bound){$p.facts.Dispose();$p.process.Dispose()}
        if(-not $retained){if($process){$process.Dispose()};foreach($lease in $boundary.leases){$lease.Dispose()}}
    }
}

function Test-RimePimeCandidateRuntimeReady {
    [CmdletBinding()]param([Parameter(Mandatory)][object]$Context,[ValidateRange(1000,180000)][int]$TimeoutMs=120000)
    $entry=Get-CandidateRuntimeContext $Context;$boundary=$entry.boundary
    Assert-CandidateRuntimeCaller $boundary.target_user_sid
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',($env:USERNAME+'\PIME\Launcher'),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    $bound=@()
    try {
        $pipe.Connect(5000);$workerPid=[Yime.CandidateRuntime.PipeFacts]::ServerPid($pipe)
        $bound=@(Get-CandidateRuntimeProcesses $boundary)
        $watchdog=@($bound | Where-Object {$_.pid -eq $entry.process.Id -and $_.start_filetime_utc -ceq $entry.start_filetime.ToString() -and $_.path -ieq $boundary.launcher})
        $worker=@($bound | Where-Object {$_.pid -eq $workerPid -and $_.parent_pid -eq $entry.process.Id -and $_.path -ieq $boundary.launcher})
        if($entry.process.HasExited -or $watchdog.Count -ne 1 -or $worker.Count -ne 1){throw 'Launcher pipe does not belong to the started worker/watchdog.'}
        [Yime.CandidateRuntime.PipeFacts]::WriteLine($pipe,'{"method":"init","seqNum":1,"id":"{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}","isWindows8Above":true,"isUiLess":true}')
        $init=[Yime.CandidateRuntime.PipeFacts]::ReadLine($pipe,$TimeoutMs) | ConvertFrom-Json
        if($init.success -isnot [bool] -or -not $init.success -or $init.seqNum -ne 1){throw 'Dedicated readiness client init failed.'}
        [Yime.CandidateRuntime.PipeFacts]::WriteLine($pipe,'{"method":"maintenanceReady","seqNum":2}')
        $ready=Assert-CandidateRuntimeReadyResponse ([Yime.CandidateRuntime.PipeFacts]::ReadLine($pipe,$TimeoutMs) | ConvertFrom-Json) 2
        $current=@(Get-CandidateRuntimeProcesses $boundary)
        try {
            $backend=@($current | Where-Object {$_.pid -eq $ready.backend_pid -and $_.parent_pid -eq $workerPid -and $_.path -ieq $boundary.backend})
            if($backend.Count -ne 1){throw 'Readiness backend is not the exact owned child image.'}
            $observations=@($current | ForEach-Object {[pscustomobject]@{pid=$_.pid;image=$_.path;sid=$_.owner_sid;start_filetime_utc=$_.start_filetime_utc;elevated=$false;parent_pid=$_.parent_pid}})
        } finally {foreach($p in $current){$p.facts.Dispose();$p.process.Dispose()}}
        [Yime.CandidateRuntime.PipeFacts]::WriteLine($pipe,'{"method":"close","seqNum":3}')
        $closed=[Yime.CandidateRuntime.PipeFacts]::ReadLine($pipe,10000) | ConvertFrom-Json
        if($closed.success -isnot [bool] -or -not $closed.success -or $closed.seqNum -ne 3){throw 'Dedicated readiness session did not close successfully.'}
        $Context.runtime_ready=$true
        return [pscustomobject]@{ready=$true;runtime_ready=$true;actual_runtime_non_elevated=$true;actual_runtime_target_sid_verified=$true;actual_runtime_current_images_verified=$true;actual_runtime_launcher_ready=$true;actual_runtime_backend_ready=$true;schema_id=$ready.schema_id;observed_processes=$observations;dp1_u_acceptance_passed=$false;live_host_acceptance_passed=$false}
    } finally {$pipe.Dispose();foreach($p in $bound){$p.facts.Dispose();$p.process.Dispose()}}
}

function Stop-CandidateRuntimeBoundary([object]$Boundary) {
    $bound=@(Get-CandidateRuntimeProcesses $Boundary);$pipe=$null
    try {
        if($bound.Count -eq 0){return [pscustomobject]@{status='already-quiescent';stopped_count=0}}
        $request=New-YimePimeDirectedStopRequest -InstallRoot $Boundary.install_root -TargetUserSid $Boundary.target_user_sid -BoundProcesses $bound
        $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',('PIME\Maintenance\'+$request.worker_pid),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect(3000)
        if([Yime.CandidateRuntime.PipeFacts]::ServerPid($pipe) -ne $request.worker_pid){throw 'Directed stop pipe server is foreign.'}
        [Yime.CandidateRuntime.PipeFacts]::WriteLine($pipe,($request | ConvertTo-Json -Depth 8 -Compress))
        $ack=[Yime.CandidateRuntime.PipeFacts]::ReadLine($pipe,5000) | ConvertFrom-Json
        $null=Assert-YimePimeDirectedStopAck $request $ack
        foreach($p in $bound){if(-not $p.process.WaitForExit(15000)){throw 'Owned runtime has not become quiescent; preserve installed payload.'}}
        $remaining=@(Get-CandidateRuntimeProcesses $Boundary)
        try {if($remaining.Count){throw 'Owned runtime restarted; preserve installed payload.'}} finally {foreach($p in $remaining){$p.facts.Dispose();$p.process.Dispose()}}
        return [pscustomobject]@{status='acknowledged-and-quiescent';stopped_count=$bound.Count;request_id=$request.request_id}
    } finally {if($pipe){$pipe.Dispose()};foreach($p in $bound){$p.facts.Dispose();$p.process.Dispose()}}
}

function Stop-RimePimeCandidateRuntime {
    [CmdletBinding()]param([Parameter(Mandatory)][object]$Context)
    $entry=Get-CandidateRuntimeContext $Context;Assert-CandidateRuntimeCaller $entry.boundary.target_user_sid
    $result=Stop-CandidateRuntimeBoundary $entry.boundary
    $null=$script:LiveContexts.Remove($Context.context_id);$entry.process.Dispose();foreach($lease in $entry.boundary.leases){$lease.Dispose()}
    return $result
}

function Stop-RimePimeCandidateOwnedRuntime {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$LauncherSha256,[Parameter(Mandatory)][string]$BackendSha256,[Parameter(Mandatory)][string]$ConfigurationSha256)
    # After committed removal, some executable/config files may already be
    # absent. Absence is a native process observation, never a successful stop
    # attributed to this invocation. A present process still requires all pins.
    Assert-CandidateRuntimeCaller $TargetUserSid
    Assert-CandidateRuntimeLexicalPath $InstallRoot
    Assert-CandidateRuntimeLexicalPath $StateRoot
    $observationBoundary=[pscustomobject]@{launcher=(Join-Path $InstallRoot 'PIMELauncher.exe');backend=(Join-Path $InstallRoot 'go-backend\server.exe');target_user_sid=$TargetUserSid}
    $observed=@(Get-CandidateRuntimeProcesses $observationBoundary)
    try {if($observed.Count -eq 0){return [pscustomobject]@{status='already-quiescent';stopped_count=0;desired_runtime_absence_observed=$true;stopped_this_invocation=$false}}}
    finally {foreach($p in $observed){$p.facts.Dispose();$p.process.Dispose()}}
    $boundary=Open-CandidateRuntimeBoundary @PSBoundParameters
    try {return Stop-CandidateRuntimeBoundary $boundary} finally {foreach($lease in $boundary.leases){$lease.Dispose()}}
}
Export-ModuleMember -Function Start-RimePimeCandidateRuntime,Get-RimePimeCandidateRuntimeContext,Test-RimePimeCandidateRuntimeReady,Stop-RimePimeCandidateRuntime,Stop-RimePimeCandidateOwnedRuntime
