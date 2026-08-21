function Get-YimeRecorderProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-YimeRecorderInteger {
    param($Value, [Parameter(Mandatory)][string]$Field, [int]$LineNumber)

    [int64]$parsed = 0
    if ($null -eq $Value -or
        -not [int64]::TryParse([string]$Value, [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        throw "Recorder record line $LineNumber has an invalid integer in $Field."
    }
    return $parsed
}

function Assert-YimeRecorderForegroundIdentity {
    param(
        [Parameter(Mandatory)]$Foreground,
        [Parameter(Mandatory)][string]$HostId,
        [int]$LineNumber
    )

    $processId = ConvertTo-YimeRecorderInteger (Get-YimeRecorderProperty $Foreground 'process_id') 'foreground.process_id' $LineNumber
    $processName = [string](Get-YimeRecorderProperty $Foreground 'process_name')
    $executable = [string](Get-YimeRecorderProperty $Foreground 'executable')
    $architecture = [string](Get-YimeRecorderProperty $Foreground 'architecture')
    $windowTitle = [string](Get-YimeRecorderProperty $Foreground 'window_title')
    $windowHandle = [string](Get-YimeRecorderProperty $Foreground 'window_handle')
    $rejectionReason = [string](Get-YimeRecorderProperty $Foreground 'rejection_reason')

    if ($processId -le 0 -or [string]::IsNullOrWhiteSpace($processName) -or
        $windowHandle -notmatch '^0x[0-9A-Fa-f]+$') {
        throw "Recorder record line $LineNumber has incomplete foreground identity data for $HostId."
    }
    if (-not [string]::IsNullOrWhiteSpace($rejectionReason)) {
        throw "Recorder record line $LineNumber accepted a foreground identity that has a rejection reason for $HostId."
    }

    $identityMatches = switch ($HostId) {
        'notepad' {
            $processName -ieq 'notepad' -and $architecture -eq 'x64'
            break
        }
        'codex' {
            ($processName -match '(?i)^(codex|chatgpt)$' -or $windowTitle -match '(?i)Codex') -and
                $architecture -eq 'x64'
            break
        }
        'charmap' {
            $processName -ieq 'charmap' -and $architecture -eq 'x86' -and
                $executable -match '(?i)\\SysWOW64\\charmap\.exe$'
            break
        }
        default { $false }
    }
    if (-not $identityMatches) {
        throw "Recorder record line $LineNumber foreground identity does not match host $HostId."
    }

    return [pscustomobject][ordered]@{
        ProcessId = [int]$processId
        ProcessName = $processName
        Executable = if ([string]::IsNullOrWhiteSpace($executable)) { $null } else { $executable }
        Architecture = $architecture
        WindowTitle = $windowTitle
        WindowHandle = $windowHandle
    }
}

function Assert-YimeRecorderHostCounts {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)]$ExpectedCounts,
        [int]$LineNumber
    )

    $hostCounts = Get-YimeRecorderProperty $Record 'host_counts'
    if ($null -eq $hostCounts) {
        throw "Recorder record line $LineNumber is incomplete: host_counts is missing."
    }
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $actualHost = Get-YimeRecorderProperty $hostCounts $hostId
        if ($null -eq $actualHost) {
            throw "Recorder record line $LineNumber is incomplete: host_counts.$hostId is missing."
        }
        foreach ($field in @('first', 'middle', 'final', 'failures')) {
            $actual = ConvertTo-YimeRecorderInteger (Get-YimeRecorderProperty $actualHost $field) "host_counts.$hostId.$field" $LineNumber
            if ($actual -lt 0 -or $actual -ne [int64]$ExpectedCounts[$hostId][$field]) {
                throw "Recorder record line $LineNumber host count mismatch for $hostId.$field."
            }
        }
        $completed = ConvertTo-YimeRecorderInteger (Get-YimeRecorderProperty $actualHost 'completed_cycles') "host_counts.$hostId.completed_cycles" $LineNumber
        $expectedCompleted = [math]::Min($ExpectedCounts[$hostId].first,
            [math]::Min($ExpectedCounts[$hostId].middle, $ExpectedCounts[$hostId].final))
        if ($completed -ne $expectedCompleted) {
            throw "Recorder record line $LineNumber completed cycle count does not match the replayed events for $hostId."
        }
    }
}

function Get-YimeSentenceSegmentRecorderRecord {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Recorder record is missing: $fullPath"
    }

    $lines = @(Get-Content -LiteralPath $fullPath -Encoding UTF8)
    $nonEmptyLines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nonEmptyLines.Count -eq 0) { throw "Recorder record is incomplete: $fullPath is empty." }

    $counts = [ordered]@{
        notepad = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
        codex = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
        charmap = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
    }
    $activeEvents = [Collections.Generic.List[object]]::new()
    $foregroundEvents = [Collections.Generic.List[object]]::new()
    $eventIds = @{}
    $sessionId = $null
    [int]$minimumCycles = 0
    [DateTimeOffset]$previousTimestamp = [DateTimeOffset]::MinValue
    $firstTimestamp = $null
    $lastTimestamp = $null
    $lastEvent = $null
    $sessionActive = $false

    for ($index = 0; $index -lt $nonEmptyLines.Count; $index++) {
        $lineNumber = $index + 1
        try { $record = $nonEmptyLines[$index] | ConvertFrom-Json }
        catch { throw "Recorder record line $lineNumber is not valid JSON: $($_.Exception.Message)" }

        $schemaVersion = ConvertTo-YimeRecorderInteger (Get-YimeRecorderProperty $record 'schema_version') 'schema_version' $lineNumber
        if ($schemaVersion -ne 2) { throw "Recorder record line $lineNumber is not schema 2." }
        $recordSessionId = [string](Get-YimeRecorderProperty $record 'session_id')
        if ([string]::IsNullOrWhiteSpace($recordSessionId)) { throw "Recorder record line $lineNumber has no session_id." }
        if ($null -eq $sessionId) { $sessionId = $recordSessionId }
        elseif ($sessionId -ne $recordSessionId) { throw "Recorder record line $lineNumber belongs to a different session." }

        $recordMinimum = ConvertTo-YimeRecorderInteger (Get-YimeRecorderProperty $record 'minimum_cycles_per_host') 'minimum_cycles_per_host' $lineNumber
        if ($recordMinimum -lt 1 -or $recordMinimum -gt 1000) { throw "Recorder record line $lineNumber has an invalid cycle threshold." }
        if ($minimumCycles -eq 0) { $minimumCycles = [int]$recordMinimum }
        elseif ($minimumCycles -ne $recordMinimum) { throw "Recorder record line $lineNumber changes minimum_cycles_per_host." }

        [DateTimeOffset]$timestamp = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string](Get-YimeRecorderProperty $record 'timestamp'),
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)) {
            throw "Recorder record line $lineNumber has an invalid timestamp."
        }
        if ($timestamp -lt $previousTimestamp) { throw "Recorder record timestamps are not monotonic at line $lineNumber." }
        if ($null -eq $firstTimestamp) { $firstTimestamp = $timestamp.ToString('o') }
        $lastTimestamp = $timestamp.ToString('o')
        $previousTimestamp = $timestamp

        $event = [string](Get-YimeRecorderProperty $record 'event')
        if ($event -notin @('session_started', 'session_resumed', 'segment_result', 'host_target_reached',
            'hotkey_rejected', 'undo', 'evidence_snapshot', 'session_ended')) {
            throw "Recorder record line $lineNumber has unknown event '$event'."
        }
        if ($lineNumber -eq 1 -and $event -ne 'session_started') {
            throw 'Recorder record is incomplete: the first event is not session_started.'
        }

        switch ($event) {
            'session_started' {
                if ($lineNumber -ne 1 -or $sessionActive) { throw "Recorder record has an unexpected session_started event at line $lineNumber." }
                $sessionActive = $true
            }
            'session_resumed' {
                if ($sessionActive) { throw "Recorder record has an unexpected session_resumed event at line $lineNumber." }
                $sessionActive = $true
            }
            'session_ended' {
                if (-not $sessionActive) { throw "Recorder record has an unexpected session_ended event at line $lineNumber." }
                $sessionActive = $false
            }
            'evidence_snapshot' {
                if (-not $sessionActive) { throw "Recorder record has an inactive evidence_snapshot event at line $lineNumber." }
            }
            'segment_result' {
                if (-not $sessionActive) { throw "Recorder record has a segment result outside an active session at line $lineNumber." }
                $hostId = [string](Get-YimeRecorderProperty $record 'host_id')
                $position = ([string](Get-YimeRecorderProperty $record 'position')).ToLowerInvariant()
                $segmentEventId = [string](Get-YimeRecorderProperty $record 'segment_event_id')
                if ($hostId -notin @('notepad', 'codex', 'charmap') -or
                    $position -notin @('first', 'middle', 'final', 'failure') -or
                    [string]::IsNullOrWhiteSpace($segmentEventId) -or $eventIds.ContainsKey($segmentEventId)) {
                    throw "Recorder record line $lineNumber has invalid segment event identity."
                }
                $foreground = Get-YimeRecorderProperty $record 'foreground'
                if ($null -eq $foreground) { throw "Recorder record line $lineNumber has no foreground identity." }
                $identity = Assert-YimeRecorderForegroundIdentity $foreground $hostId $lineNumber
                $field = if ($position -eq 'failure') { 'failures' } else { $position }
                $counts[$hostId][$field]++
                $activeEvent = [pscustomobject]@{ EventId = $segmentEventId; HostId = $hostId; Position = $position; Field = $field }
                $activeEvents.Add($activeEvent)
                $eventIds[$segmentEventId] = $true
                $foregroundEvents.Add([pscustomobject][ordered]@{
                    SegmentEventId = $segmentEventId
                    Timestamp = $timestamp.ToString('o')
                    HostId = $hostId
                    Position = $position
                    ProcessId = $identity.ProcessId
                    ProcessName = $identity.ProcessName
                    Executable = $identity.Executable
                    Architecture = $identity.Architecture
                    WindowTitle = $identity.WindowTitle
                    WindowHandle = $identity.WindowHandle
                })
            }
            'undo' {
                if (-not $sessionActive -or $activeEvents.Count -eq 0) { throw "Recorder record line $lineNumber cannot undo a segment event." }
                $lastActiveIndex = $activeEvents.Count - 1
                $activeEvent = $activeEvents[$lastActiveIndex]
                if ([string](Get-YimeRecorderProperty $record 'segment_event_id') -ne $activeEvent.EventId -or
                    [string](Get-YimeRecorderProperty $record 'host_id') -ne $activeEvent.HostId -or
                    ([string](Get-YimeRecorderProperty $record 'position')).ToLowerInvariant() -ne $activeEvent.Position) {
                    throw "Recorder record line $lineNumber does not undo the latest active segment event."
                }
                $counts[$activeEvent.HostId][$activeEvent.Field]--
                $activeEvents.RemoveAt($lastActiveIndex)
                for ($foregroundIndex = $foregroundEvents.Count - 1; $foregroundIndex -ge 0; $foregroundIndex--) {
                    if ($foregroundEvents[$foregroundIndex].SegmentEventId -eq $activeEvent.EventId) {
                        $foregroundEvents.RemoveAt($foregroundIndex)
                        break
                    }
                }
            }
            'host_target_reached' {
                if (-not $sessionActive -or $activeEvents.Count -eq 0) { throw "Recorder record line $lineNumber has no segment event for host_target_reached." }
                $activeEvent = $activeEvents[$activeEvents.Count - 1]
                if ([string](Get-YimeRecorderProperty $record 'segment_event_id') -ne $activeEvent.EventId -or
                    [string](Get-YimeRecorderProperty $record 'host_id') -ne $activeEvent.HostId -or
                    ([string](Get-YimeRecorderProperty $record 'position')).ToLowerInvariant() -ne $activeEvent.Position) {
                    throw "Recorder record line $lineNumber host_target_reached does not match the latest segment event."
                }
                $foreground = Get-YimeRecorderProperty $record 'foreground'
                if ($null -eq $foreground) { throw "Recorder record line $lineNumber has no foreground identity." }
                [void](Assert-YimeRecorderForegroundIdentity $foreground $activeEvent.HostId $lineNumber)
            }
            'hotkey_rejected' {
                if (-not $sessionActive -or $null -eq (Get-YimeRecorderProperty $record 'foreground')) {
                    throw "Recorder record line $lineNumber has an incomplete hotkey_rejected event."
                }
            }
        }

        Assert-YimeRecorderHostCounts $record $counts $lineNumber
        $lastEvent = $event
    }

    if ($lastEvent -notin @('evidence_snapshot', 'session_ended')) {
        throw "Recorder record is incomplete: the final event must be evidence_snapshot or session_ended."
    }

    $hostNames = @{ notepad = 'x64 Notepad'; codex = 'Codex IDE'; charmap = 'x86 SysWOW64 charmap' }
    $hostRecords = [Collections.Generic.List[object]]::new()
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $completedCycles = [math]::Min($counts[$hostId].first,
            [math]::Min($counts[$hostId].middle, $counts[$hostId].final))
        if ($completedCycles -lt $minimumCycles) {
            throw "Recorder record is incomplete: $($hostNames[$hostId]) has $completedCycles of $minimumCycles required cycles."
        }
        $hostForegroundEvents = @($foregroundEvents | Where-Object HostId -eq $hostId)
        if ($hostForegroundEvents.Count -eq 0) {
            throw "Recorder record is incomplete: $($hostNames[$hostId]) has no accepted foreground identity."
        }
        $hostRecords.Add([pscustomobject][ordered]@{
            HostId = $hostId
            Host = $hostNames[$hostId]
            First = [int]$counts[$hostId].first
            Middle = [int]$counts[$hostId].middle
            Final = [int]$counts[$hostId].final
            CompletedCycles = [int]$completedCycles
            Failures = [int]$counts[$hostId].failures
            ForegroundEventCount = $hostForegroundEvents.Count
        })
    }

    return [pscustomobject][ordered]@{
        Provided = $true
        Status = 'match'
        SchemaVersion = 2
        Path = $fullPath
        Sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        SessionId = $sessionId
        MinimumCyclesPerHost = $minimumCycles
        EventCount = $nonEmptyLines.Count
        TerminalEvent = $lastEvent
        FirstTimestamp = $firstTimestamp
        LastTimestamp = $lastTimestamp
        HostRecords = @($hostRecords)
        ForegroundIdentityRecords = @($foregroundEvents)
    }
}
