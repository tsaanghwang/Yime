# Rime/PIME directed maintenance-stop contract. Definitions only; no action on import.
# The client transport below talks only to the worker-PID-specific pipe. The
# corresponding validator and restart-suppression path live in PIMELauncher.

function ConvertTo-YimePimeUtcStartIdentity([object]$Value) {
    if($Value -is [datetime]){$time=[datetime]$Value}
    else {
        try {$time=[Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)}
        catch {$time=[datetime]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
    }
    return $time.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-YimePimeFileTimeStartIdentity([datetime]$Value) {
    return $Value.ToUniversalTime().ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Get-YimePimeDirectedStopHash([object]$Value) {
    $json=$Value | ConvertTo-Json -Depth 8 -Compress
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally {$sha.Dispose()}
}

function Get-YimePimeDirectedStopBoundProcesses {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid)
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $imageNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in Get-YimePimeExecutablePaths $InstallRoot){$null=$paths.Add($path);$null=$imageNames.Add([IO.Path]::GetFileName($path))}
    $bound=[Collections.Generic.List[object]]::new()
    try {
        foreach($record in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            if(-not $record.ExecutablePath) {
                if($imageNames.Contains([string]$record.Name)){throw 'A relevant executable image path is unreadable; directed maintenance identity cannot be proved.'}
                continue
            }
            if(-not $paths.Contains([string]$record.ExecutablePath)){continue}
            $process=Get-Process -Id ([int]$record.ProcessId) -ErrorAction Stop
            $null=$process.Handle
            $recordStart=ConvertTo-YimePimeUtcStartIdentity $record.CreationDate
            $processStart=ConvertTo-YimePimeUtcStartIdentity $process.StartTime
            $recordTime=[datetime]::Parse($recordStart,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
            $processTime=[datetime]::Parse($processStart,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
            if($process.Path -ine [string]$record.ExecutablePath -or
                [Math]::Abs(($recordTime-$processTime).TotalMilliseconds) -gt 1) {
                throw 'Process path/PID/start identity changed while binding directed maintenance target.'
            }
            $owner=Invoke-CimMethod -InputObject $record -MethodName GetOwnerSid -ErrorAction Stop
            if($owner.ReturnValue -ne 0 -or [string]$owner.Sid -cne $TargetUserSid) {
                throw 'A directed maintenance target belongs to another or unknown SID.'
            }
            $bound.Add([pscustomobject][ordered]@{
                path=[string]$record.ExecutablePath;pid=[int]$record.ProcessId;start_utc=$recordStart
                start_filetime_utc=(ConvertTo-YimePimeFileTimeStartIdentity $process.StartTime)
                owner_sid=[string]$owner.Sid;parent_pid=[int]$record.ParentProcessId
                command_line=[string]$record.CommandLine;process=$process
            })
        }
        return @($bound | Sort-Object -Property @{Expression='pid';Ascending=$true},@{Expression='path';Ascending=$true})
    } catch {
        foreach($item in $bound){if($item.process -is [IDisposable]){$item.process.Dispose()}}
        throw
    }
}

function New-YimePimeDirectedStopRequest {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][object[]]$BoundProcesses)
    $launchers=@($BoundProcesses | Where-Object {$_.path -ieq (Join-Path $InstallRoot 'PIMELauncher.exe')})
    $workers=@($launchers | Where-Object {$_.command_line -match '(?i)(?:^|\s)/worker(?:\s|$)'})
    $watchdogs=@($launchers | Where-Object {$_.command_line -notmatch '(?i)(?:^|\s)/worker(?:\s|$)'})
    if($workers.Count -ne 1 -or $watchdogs.Count -ne 1 -or [int]$workers[0].parent_pid -ne [int]$watchdogs[0].pid) {
        throw 'Directed stop requires one identity-bound watchdog and its one /worker child for the selected product root.'
    }
    $other=@($BoundProcesses | Where-Object {$_.path -ine (Join-Path $InstallRoot 'PIMELauncher.exe')})
    $backendPath=Join-Path $InstallRoot 'go-backend\server.exe'
    if($other.Count -gt 1 -or @($other | Where-Object {$_.path -ine $backendPath -or [int]$_.parent_pid -ne [int]$workers[0].pid}).Count -ne 0) {
        throw 'A standalone Rime/PIME tool or unbound backend is running; close it before directed maintenance.'
    }
    $observed=@($BoundProcesses | ForEach-Object {
        $role='backend'
        if([int]$_.pid -eq [int]$watchdogs[0].pid){$role='watchdog'}
        elseif([int]$_.pid -eq [int]$workers[0].pid){$role='worker'}
        [ordered]@{path=[string]$_.path;pid=[int]$_.pid;start_utc=[string]$_.start_utc
            start_filetime_utc=[string]$_.start_filetime_utc;owner_sid=[string]$_.owner_sid
            parent_pid=[int]$_.parent_pid;role=$role}
    })
    $observationHash=Get-YimePimeDirectedStopHash $observed
    return [pscustomobject][ordered]@{
        schema_version='yime-rime-directed-stop-request-v1'
        request_id=[Guid]::NewGuid().ToString('N')
        install_root=$InstallRoot
        target_user_sid=$TargetUserSid
        launcher_pid=[int]$watchdogs[0].pid
        launcher_start_utc=[string]$watchdogs[0].start_utc
        launcher_start_filetime_utc=[string]$watchdogs[0].start_filetime_utc
        worker_pid=[int]$workers[0].pid
        worker_start_utc=[string]$workers[0].start_utc
        worker_start_filetime_utc=[string]$workers[0].start_filetime_utc
        observation_sha256=$observationHash
        observed_processes=$observed
    }
}

function Assert-YimePimeDirectedStopAck {
    param([Parameter(Mandatory)][object]$Request,[Parameter(Mandatory)][object]$Ack)
    if($null -eq $Ack){throw 'Directed stop transport returned no acknowledgement.'}
    $expected=@('schema_version','request_id','accepted','install_root','target_user_sid','launcher_pid','launcher_start_utc','launcher_start_filetime_utc',
        'worker_pid','worker_start_utc','worker_start_filetime_utc','observation_sha256','watchdog_restart_suppressed')
    $actual=@($Ack.PSObject.Properties.Name)
    if($actual.Count -ne $expected.Count -or @(Compare-Object $expected $actual).Count -ne 0){throw 'Directed stop acknowledgement has an incomplete or unknown shape.'}
    if([string]$Ack.schema_version -cne 'yime-rime-directed-stop-ack-v1' -or
        $Ack.accepted -isnot [bool] -or $Ack.accepted -ne $true -or
        [string]$Ack.request_id -cne [string]$Request.request_id -or
        [string]$Ack.install_root -cne [string]$Request.install_root -or
        [string]$Ack.target_user_sid -cne [string]$Request.target_user_sid -or
        [int]$Ack.launcher_pid -ne [int]$Request.launcher_pid -or
        [string]$Ack.launcher_start_utc -cne [string]$Request.launcher_start_utc -or
        [string]$Ack.launcher_start_filetime_utc -cne [string]$Request.launcher_start_filetime_utc -or
        [int]$Ack.worker_pid -ne [int]$Request.worker_pid -or
        [string]$Ack.worker_start_utc -cne [string]$Request.worker_start_utc -or
        [string]$Ack.worker_start_filetime_utc -cne [string]$Request.worker_start_filetime_utc -or
        [string]$Ack.observation_sha256 -cne [string]$Request.observation_sha256 -or
        $Ack.watchdog_restart_suppressed -isnot [bool] -or $Ack.watchdog_restart_suppressed -ne $true) {
        throw 'Directed stop acknowledgement did not echo the exact request identity or suppress watchdog restart.'
    }
    return $Ack
}

function Invoke-YimePimeDirectedStopTransport {
    param([Parameter(Mandatory)][object]$Request)
    $pipeName='PIME\Maintenance\'+[string]$Request.worker_pid
    $client=$null;$writer=$null;$reader=$null
    try {
        $client=[IO.Pipes.NamedPipeClientStream]::new('.',$pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
        $client.Connect(3000)
        $writer=[IO.StreamWriter]::new($client,[Text.UTF8Encoding]::new($false),4096,$true)
        $reader=[IO.StreamReader]::new($client,[Text.UTF8Encoding]::new($false),$false,4096,$true)
        $writer.WriteLine(($Request | ConvertTo-Json -Depth 8 -Compress));$writer.Flush()
        $readTask=$reader.ReadLineAsync()
        if(-not $readTask.Wait(5000)){throw 'Directed stop acknowledgement timed out.'}
        $line=$readTask.Result
        if([string]::IsNullOrWhiteSpace($line) -or $line.Length -gt 32768){throw 'Directed stop acknowledgement is empty or oversized.'}
        return $line | ConvertFrom-Json
    } finally {
        if($reader){$reader.Dispose()};if($writer){$writer.Dispose()};if($client){$client.Dispose()}
    }
}

function Invoke-YimePimeDirectedStop {
    param([Parameter(Mandatory)][string]$InstallRoot,[string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid
    $root=(Assert-YimePimeOwnedRoot -Root $InstallRoot).path
    $bound=@()
    try {
        $bound=@(Get-YimePimeDirectedStopBoundProcesses -InstallRoot $root -TargetUserSid $sid)
        if($bound.Count -eq 0){return [pscustomobject]@{status='already-quiescent';stopped_count=0}}
        $request=New-YimePimeDirectedStopRequest -InstallRoot $root -TargetUserSid $sid -BoundProcesses $bound
        $ack=Invoke-YimePimeDirectedStopTransport -Request $request
        $null=Assert-YimePimeDirectedStopAck -Request $request -Ack $ack
        Wait-Process -InputObject @($bound | ForEach-Object {$_.process}) -Timeout 15 -ErrorAction Stop
        $remaining=@(Get-YimePimeDirectedStopBoundProcesses -InstallRoot $root -TargetUserSid $sid)
        try {
            if($remaining.Count -ne 0){throw 'Acknowledged directed stop did not leave the selected product quiescent.'}
        } finally {
            foreach($item in $remaining){if($item.process -is [IDisposable]){$item.process.Dispose()}}
        }
        return [pscustomobject]@{status='acknowledged-and-quiescent';stopped_count=$bound.Count;request_id=$request.request_id}
    } finally {
        foreach($item in $bound){if($item.process -is [IDisposable]){$item.process.Dispose()}}
    }
}
