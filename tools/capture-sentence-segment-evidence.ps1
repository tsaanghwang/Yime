param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'PIME\Logs\go_backend.log'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) '.tmp\sentence-segment-evidence'),
    [int]$LogTailLines = 50000,
    [int]$MaxRpcTransactions = 500,
    [ValidateRange(1, 1000)]
    [int]$MinimumCyclesPerHost = 20,
    [ValidateRange(1, 100000)]
    [int]$MinimumCorrelatedRpcTransactions = 1,
    [string[]]$ProcessNames = @('PIMELauncher', 'server'),
    [ValidateSet('pass', 'fail', 'blocked', 'not-run', 'not-recorded')]
    [string]$NotepadOutcome = 'not-recorded',
    [string]$NotepadNotes = '',
    [ValidateRange(0, 100000)][int]$NotepadFirstSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$NotepadMiddleSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$NotepadFinalSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$NotepadSessionMinutes = 0,
    [ValidateSet('pass', 'fail', 'blocked', 'not-run', 'not-recorded')]
    [string]$CodexIdeOutcome = 'not-recorded',
    [string]$CodexIdeNotes = '',
    [ValidateRange(0, 100000)][int]$CodexIdeFirstSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$CodexIdeMiddleSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$CodexIdeFinalSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$CodexIdeSessionMinutes = 0,
    [ValidateSet('pass', 'fail', 'blocked', 'not-run', 'not-recorded')]
    [string]$SysWow64CharmapOutcome = 'not-recorded',
    [string]$SysWow64CharmapNotes = '',
    [ValidateRange(0, 100000)][int]$SysWow64CharmapFirstSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$SysWow64CharmapMiddleSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$SysWow64CharmapFinalSegmentSwitches = 0,
    [ValidateRange(0, 100000)][int]$SysWow64CharmapSessionMinutes = 0,
    [string]$BuildManifestPath,
    [switch]$RequireLongSession,
    [switch]$RequireComplete
)

$ErrorActionPreference = 'Stop'

function Get-EvidenceFileRecord {
    param(
        [string]$Name,
        [string]$InstalledPath,
        [string]$ReferencePath
    )

    $record = [ordered]@{
        Name = $Name
        InstalledPath = [IO.Path]::GetFullPath($InstalledPath)
        InstalledExists = $false
        InstalledSha256 = $null
        InstalledSize = $null
        InstalledModifiedUtc = $null
        ReferencePath = [IO.Path]::GetFullPath($ReferencePath)
        ReferenceExists = $false
        ReferenceSha256 = $null
        Status = 'unknown'
    }

    if (-not (Test-Path -LiteralPath $record.InstalledPath -PathType Leaf)) {
        $record.Status = 'installed-missing'
        return [pscustomobject]$record
    }

    $installed = Get-Item -LiteralPath $record.InstalledPath
    $record.InstalledExists = $true
    $record.InstalledSha256 = (Get-FileHash -LiteralPath $record.InstalledPath -Algorithm SHA256).Hash
    $record.InstalledSize = $installed.Length
    $record.InstalledModifiedUtc = $installed.LastWriteTimeUtc.ToString('o')

    if (-not (Test-Path -LiteralPath $record.ReferencePath -PathType Leaf)) {
        $record.Status = 'reference-missing'
        return [pscustomobject]$record
    }

    $record.ReferenceExists = $true
    $record.ReferenceSha256 = (Get-FileHash -LiteralPath $record.ReferencePath -Algorithm SHA256).Hash
    $record.Status = if ($record.InstalledSha256 -eq $record.ReferenceSha256) { 'match' } else { 'mismatch' }
    return [pscustomobject]$record
}

function Get-EvidenceProcessSnapshot {
    param([string[]]$Names)

    $records = [Collections.Generic.List[object]]::new()
    foreach ($name in $Names) {
        $processName = [IO.Path]::GetFileNameWithoutExtension($name)
        $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        if ($processes.Count -eq 0) {
            $records.Add([pscustomobject][ordered]@{
                Name = $processName
                State = 'not-running'
                ProcessId = $null
                ExecutablePath = $null
                StartTimeUtc = $null
            })
            continue
        }

        foreach ($process in $processes) {
            $path = $null
            $startTimeUtc = $null
            try { $path = $process.Path } catch {}
            try { $startTimeUtc = $process.StartTime.ToUniversalTime().ToString('o') } catch {}
            $records.Add([pscustomobject][ordered]@{
                Name = $processName
                State = 'running'
                ProcessId = $process.Id
                ExecutablePath = $path
                StartTimeUtc = $startTimeUtc
            })
        }
    }
    return @($records)
}

function Get-BuildIdentity {
    param(
        [string]$Root,
        [string]$ManifestPath,
        [object[]]$FileRecords
    )

    $versionPath = Join-Path $Root 'version.txt'
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    } else { $null }
    $commit = $null
    $ref = $null
    $dirty = $null
    try {
        $commit = (& git -C $Root rev-parse HEAD 2>$null).Trim()
        $ref = (& git -C $Root branch --show-current 2>$null).Trim()
        $dirty = [bool](@(& git -C $Root status --porcelain 2>$null).Count -gt 0)
    } catch {}

    $manifest = [ordered]@{
        Path = if ($ManifestPath) { [IO.Path]::GetFullPath($ManifestPath) } else { $null }
        Exists = $false
        Sha256 = $null
        Version = $null
        Commit = $null
        Status = 'not-present'
        FileMatches = @()
    }
    if ($ManifestPath -and (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $manifest.Exists = $true
        $manifest.Sha256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
        try {
            $parsed = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $manifest.Version = [string]$parsed.version
            $manifest.Commit = [string]$parsed.commit
            $manifestMatches = [Collections.Generic.List[object]]::new()
            $manifestPathByEvidenceName = @{
                'server.exe' = 'go-backend/build/go-backend/server.exe'
                'x86/PIMETextService.dll' = 'build/PIMETextService/Release/PIMETextService.dll'
                'x64/PIMETextService.dll' = 'build64/PIMETextService/Release/PIMETextService.dll'
            }
            foreach ($file in $FileRecords) {
                $path = $manifestPathByEvidenceName[$file.Name]
                $entry = @($parsed.files | Where-Object { [string]$_.path -eq $path }) | Select-Object -First 1
                $manifestMatches.Add([pscustomobject][ordered]@{
                    Name = $file.Name
                    ManifestPath = $path
                    ManifestSha256 = if ($entry) { [string]$entry.sha256 } else { $null }
                    InstalledSha256 = $file.InstalledSha256
                    Status = if (-not $entry) { 'entry-missing' } elseif ([string]$entry.sha256 -eq $file.InstalledSha256) { 'match' } else { 'mismatch' }
                })
            }
            $manifest.FileMatches = @($manifestMatches)
            $identityMatches = $manifest.Version -eq $version -and
                $commit -and $manifest.Commit -eq $commit
            $manifest.Status = if ($identityMatches -and @($manifestMatches | Where-Object Status -ne 'match').Count -eq 0) {
                'match'
            } else { 'mismatch' }
        } catch {
            $manifest.Status = 'invalid'
        }
    }

    return [pscustomobject][ordered]@{
        Version = $version
        Commit = $commit
        Ref = $ref
        WorkingTreeDirty = $dirty
        Manifest = [pscustomobject]$manifest
    }
}

function Get-RimePagingGuard {
    param([string]$Root)

    $implementationPath = Join-Path $Root 'go-backend\input_methods\yime\native_cgo.go'
    $testPath = Join-Path $Root 'go-backend\input_methods\yime\native_cgo_test.go'
    $implementationText = if (Test-Path -LiteralPath $implementationPath) { Get-Content -LiteralPath $implementationPath -Raw } else { '' }
    $testText = if (Test-Path -LiteralPath $testPath) { Get-Content -LiteralPath $testPath -Raw } else { '' }
    $implementationPresent = $implementationText -match '(?s)func \(b \*nativeBackend\) UsesBackendCandidatePaging\(\) bool\s*\{.*?return true\s*\}'
    $testPresent = $testText.Contains('TestNativeBackendKeepsRimeOwnedCandidatePaging')
    return [pscustomobject][ordered]@{
        Owner = 'rime-native-backend'
        Status = if ($implementationPresent -and $testPresent) { 'guarded' } else { 'missing' }
        ImplementationPath = $implementationPath
        ImplementationSha256 = if (Test-Path -LiteralPath $implementationPath) { (Get-FileHash -LiteralPath $implementationPath -Algorithm SHA256).Hash } else { $null }
        RegressionTest = 'TestNativeBackendKeepsRimeOwnedCandidatePaging'
        TestPath = $testPath
        TestSha256 = if (Test-Path -LiteralPath $testPath) { (Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash } else { $null }
    }
}

function Get-CompositionSegmentRpcEvidence {
    param(
        [string]$Path,
        [int]$TailLines,
        [int]$MaxTransactions
    )

    $result = [ordered]@{
        LogPath = [IO.Path]::GetFullPath($Path)
        LogExists = $false
        LogSize = $null
        LogModifiedUtc = $null
        LinesScanned = 0
        Transactions = @()
    }
    if (-not (Test-Path -LiteralPath $result.LogPath -PathType Leaf)) {
        return [pscustomobject]$result
    }

    $log = Get-Item -LiteralPath $result.LogPath
    $result.LogExists = $true
    $result.LogSize = $log.Length
    $result.LogModifiedUtc = $log.LastWriteTimeUtc.ToString('o')

    $allLines = @(Get-Content -LiteralPath $result.LogPath -Encoding UTF8)
    if ($allLines.Count -gt $TailLines) {
        $lines = @($allLines[($allLines.Count - $TailLines)..($allLines.Count - 1)])
    } else {
        $lines = $allLines
    }
    $result.LinesScanned = $lines.Count

    $transactionsByKey = [ordered]@{}
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -notmatch 'method=selectCompositionSegment') { continue }
        $clientMatch = [regex]::Match($line, 'client=(\S+)')
        $seqMatch = [regex]::Match($line, 'seq=(\d+)')
        if (-not $clientMatch.Success -or -not $seqMatch.Success) { continue }
        $key = $clientMatch.Groups[1].Value + ':' + $seqMatch.Groups[1].Value
        if (-not $transactionsByKey.Contains($key)) {
            $transactionsByKey[$key] = [ordered]@{
                Client = $clientMatch.Groups[1].Value
                SeqNum = [int64]$seqMatch.Groups[1].Value
                FirstLineIndex = $index
                RequestLines = [Collections.Generic.List[string]]::new()
                RequestCursor = $null
                RequestSelEnd = $null
                ResponseLine = $null
            }
        }
        $transactionsByKey[$key].RequestLines.Add($line)
        $cursorMatch = [regex]::Match($line, 'cursor=(-?\d+)')
        $selEndMatch = [regex]::Match($line, 'selEnd=(-?\d+)')
        if ($cursorMatch.Success) { $transactionsByKey[$key].RequestCursor = [int]$cursorMatch.Groups[1].Value }
        if ($selEndMatch.Success) { $transactionsByKey[$key].RequestSelEnd = [int]$selEndMatch.Groups[1].Value }
    }

    foreach ($transaction in $transactionsByKey.Values) {
        $escapedClient = [regex]::Escape($transaction.Client)
        $escapedSeq = [regex]::Escape([string]$transaction.SeqNum)
        $responsePattern = 'client=' + $escapedClient + '\s+payload='
        $seqPattern = '"seqNum"\s*:\s*' + $escapedSeq + '(?:\D|$)'
        for ($index = $transaction.FirstLineIndex + 1; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line -match $responsePattern -and
                $line -match $seqPattern) {
                $transaction.ResponseLine = $line
                break
            }
        }
    }

    $transactions = @($transactionsByKey.Values | ForEach-Object {
        $responseSuccess = $false
        $responseHandled = $false
        $segmentPosition = $null
        if ($_.ResponseLine -and $_.ResponseLine -match 'payload=(\{.*\})\s*$') {
            try {
                $payload = $Matches[1] | ConvertFrom-Json
                $responseSuccess = [bool]$payload.success
                $responseHandled = [bool]$payload.return
                $segments = @($payload.compositionSegments)
                $activeIndexes = @()
                if ($responseSuccess -and $responseHandled -and $segments.Count -ge 3) {
                    for ($segmentIndex = 0; $segmentIndex -lt $segments.Count; $segmentIndex++) {
                        if ([bool]$segments[$segmentIndex].active) { $activeIndexes += $segmentIndex }
                    }
                    if ($activeIndexes.Count -eq 1) {
                        $activeIndex = $activeIndexes[0]
                        $segmentPosition = if ($activeIndex -eq 0) { 'first' } elseif ($activeIndex -eq $segments.Count - 1) { 'final' } else { 'middle' }
                    }
                }
            } catch {}
        }
        [pscustomobject][ordered]@{
            Client = $_.Client
            SeqNum = $_.SeqNum
            RequestLines = @($_.RequestLines)
            RequestCursor = $_.RequestCursor
            RequestSelEnd = $_.RequestSelEnd
            ResponseLine = $_.ResponseLine
            ResponseFound = [bool]$_.ResponseLine
            ResponseSuccess = $responseSuccess
            ResponseHandled = $responseHandled
            SegmentPosition = $segmentPosition
        }
    })
    if ($transactions.Count -gt $MaxTransactions) {
        $transactions = @($transactions[($transactions.Count - $MaxTransactions)..($transactions.Count - 1)])
    }
    $result.Transactions = $transactions
    return [pscustomobject]$result
}

function ConvertTo-MarkdownCell {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '-' }
    $text = [string]$Value
    $text = $text.Replace([string][char]124, ([string][char]92 + [char]124))
    $text = $text.Replace([string][char]13, '').Replace([string][char]10, ' ')
    return $text
}

if ($LogTailLines -lt 1) { throw 'LogTailLines must be at least 1.' }
if ($MaxRpcTransactions -lt 1) { throw 'MaxRpcTransactions must be at least 1.' }
if ($MinimumCorrelatedRpcTransactions -gt $MaxRpcTransactions) {
    throw 'MinimumCorrelatedRpcTransactions cannot exceed MaxRpcTransactions.'
}

$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$installRootPath = [IO.Path]::GetFullPath($InstallRoot)
$outputDirectoryPath = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $BuildManifestPath) { $BuildManifestPath = Join-Path $repoRootPath 'installer\build-manifest.json' }
$capturedAt = [DateTimeOffset]::Now
$stamp = $capturedAt.ToString('yyyyMMdd-HHmmss-fff')
$reportPath = Join-Path $outputDirectoryPath "sentence-segment-evidence-$stamp.md"
$jsonReportPath = Join-Path $outputDirectoryPath "sentence-segment-acceptance-$stamp.json"

$files = @(
    Get-EvidenceFileRecord `
        -Name 'server.exe' `
        -InstalledPath (Join-Path $installRootPath 'go-backend\server.exe') `
        -ReferencePath (Join-Path $repoRootPath 'go-backend\build\go-backend\server.exe')
    Get-EvidenceFileRecord `
        -Name 'x86/PIMETextService.dll' `
        -InstalledPath (Join-Path $installRootPath 'x86\PIMETextService.dll') `
        -ReferencePath (Join-Path $repoRootPath 'build\PIMETextService\Release\PIMETextService.dll')
    Get-EvidenceFileRecord `
        -Name 'x64/PIMETextService.dll' `
        -InstalledPath (Join-Path $installRootPath 'x64\PIMETextService.dll') `
        -ReferencePath (Join-Path $repoRootPath 'build64\PIMETextService\Release\PIMETextService.dll')
)
$build = Get-BuildIdentity -Root $repoRootPath -ManifestPath $BuildManifestPath -FileRecords $files
$paging = Get-RimePagingGuard -Root $repoRootPath
$processes = @(Get-EvidenceProcessSnapshot -Names $ProcessNames)
$rpc = Get-CompositionSegmentRpcEvidence -Path $LogPath -TailLines $LogTailLines -MaxTransactions $MaxRpcTransactions
$hostOutcomes = @(
    [pscustomobject][ordered]@{
        Host = 'x64 Notepad'
        Architecture = 'x64'
        Executable = 'Notepad'
        Outcome = $NotepadOutcome
        Notes = $NotepadNotes
        FirstSegmentSwitches = $NotepadFirstSegmentSwitches
        MiddleSegmentSwitches = $NotepadMiddleSegmentSwitches
        FinalSegmentSwitches = $NotepadFinalSegmentSwitches
        CompletedCycles = [Math]::Min($NotepadFirstSegmentSwitches, [Math]::Min($NotepadMiddleSegmentSwitches, $NotepadFinalSegmentSwitches))
        SessionMinutes = $NotepadSessionMinutes
    }
    [pscustomobject][ordered]@{
        Host = 'Codex IDE'
        Architecture = 'x64'
        Executable = 'Codex IDE'
        Outcome = $CodexIdeOutcome
        Notes = $CodexIdeNotes
        FirstSegmentSwitches = $CodexIdeFirstSegmentSwitches
        MiddleSegmentSwitches = $CodexIdeMiddleSegmentSwitches
        FinalSegmentSwitches = $CodexIdeFinalSegmentSwitches
        CompletedCycles = [Math]::Min($CodexIdeFirstSegmentSwitches, [Math]::Min($CodexIdeMiddleSegmentSwitches, $CodexIdeFinalSegmentSwitches))
        SessionMinutes = $CodexIdeSessionMinutes
    }
    [pscustomobject][ordered]@{
        Host = 'x86 SysWOW64 charmap'
        Architecture = 'x86'
        Executable = 'C:\Windows\SysWOW64\charmap.exe'
        Outcome = $SysWow64CharmapOutcome
        Notes = $SysWow64CharmapNotes
        FirstSegmentSwitches = $SysWow64CharmapFirstSegmentSwitches
        MiddleSegmentSwitches = $SysWow64CharmapMiddleSegmentSwitches
        FinalSegmentSwitches = $SysWow64CharmapFinalSegmentSwitches
        CompletedCycles = [Math]::Min($SysWow64CharmapFirstSegmentSwitches, [Math]::Min($SysWow64CharmapMiddleSegmentSwitches, $SysWow64CharmapFinalSegmentSwitches))
        SessionMinutes = $SysWow64CharmapSessionMinutes
    }
)

foreach ($hostOutcome in $hostOutcomes) {
    $hostOutcome | Add-Member -NotePropertyName LongSessionStatus -NotePropertyValue $(
        if ($hostOutcome.Outcome -eq 'fail') { 'failed' }
        elseif ($hostOutcome.Outcome -eq 'pass' -and $hostOutcome.CompletedCycles -ge $MinimumCyclesPerHost) { 'pass' }
        else { 'incomplete' }
    )
}

$failedFiles = @($files | Where-Object { $_.Status -in @('installed-missing', 'mismatch') })
$unverifiedFiles = @($files | Where-Object { $_.Status -eq 'reference-missing' })
$failedHosts = @($hostOutcomes | Where-Object { $_.Outcome -eq 'fail' })
$incompleteHosts = @($hostOutcomes | Where-Object { $_.Outcome -ne 'pass' })
$completeRpcTransactions = @($rpc.Transactions | Where-Object { $_.ResponseFound })
$successfulRpcTransactions = @($rpc.Transactions | Where-Object { $_.ResponseFound -and $_.ResponseSuccess -and $_.ResponseHandled })
$classifiedRpcTransactions = @($successfulRpcTransactions | Where-Object { $_.SegmentPosition -in @('first', 'middle', 'final') })
$rpcPositionCounts = [ordered]@{
    first = @($classifiedRpcTransactions | Where-Object SegmentPosition -eq 'first').Count
    middle = @($classifiedRpcTransactions | Where-Object SegmentPosition -eq 'middle').Count
    final = @($classifiedRpcTransactions | Where-Object SegmentPosition -eq 'final').Count
}
$requiredPositionTransactions = $MinimumCyclesPerHost * $hostOutcomes.Count
$longSessionHostIssues = @($hostOutcomes | Where-Object LongSessionStatus -ne 'pass')
$longSessionRpcComplete = $successfulRpcTransactions.Count -ge $MinimumCorrelatedRpcTransactions -and
    $rpcPositionCounts.first -ge $requiredPositionTransactions -and
    $rpcPositionCounts.middle -ge $requiredPositionTransactions -and
    $rpcPositionCounts.final -ge $requiredPositionTransactions
$longSessionComplete = $longSessionHostIssues.Count -eq 0 -and $longSessionRpcComplete
$overall = if ($failedFiles.Count -gt 0 -or $failedHosts.Count -gt 0) {
    'failed'
} elseif ($unverifiedFiles.Count -gt 0 -or
    $incompleteHosts.Count -gt 0 -or
    $completeRpcTransactions.Count -eq 0 -or
    $paging.Status -ne 'guarded' -or
    ($build.Manifest.Exists -and $build.Manifest.Status -ne 'match') -or
    ($RequireLongSession -and -not $longSessionComplete)) {
    'partial'
} else {
    'complete'
}

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Sentence Segment Correction Installed-Runtime Evidence')
$markdown.Add('')
$markdown.Add("- Captured: $($capturedAt.ToString('o'))")
$markdown.Add("- Status: **$overall**")
$markdown.Add('- Install root: ' + [char]96 + (ConvertTo-MarkdownCell $installRootPath) + [char]96)
$markdown.Add('- Repository root: ' + [char]96 + (ConvertTo-MarkdownCell $repoRootPath) + [char]96)
$markdown.Add('')
$markdown.Add('## Build identity')
$markdown.Add('')
$markdown.Add("- Version: $([char]96)$(ConvertTo-MarkdownCell $build.Version)$([char]96)")
$markdown.Add("- Git commit: $([char]96)$(ConvertTo-MarkdownCell $build.Commit)$([char]96)")
$markdown.Add("- Git ref: $([char]96)$(ConvertTo-MarkdownCell $build.Ref)$([char]96)")
$markdown.Add("- Working tree dirty: $($build.WorkingTreeDirty)")
$markdown.Add("- Build manifest status: $([char]96)$(ConvertTo-MarkdownCell $build.Manifest.Status)$([char]96)")
$markdown.Add("- Build manifest SHA-256: $([char]96)$(ConvertTo-MarkdownCell $build.Manifest.Sha256)$([char]96)")
$markdown.Add('')
$markdown.Add('## Installed runtime hashes')
$markdown.Add('')
$markdown.Add('| File | Status | Installed SHA-256 | Reference SHA-256 | Size | Installed modified (UTC) |')
$markdown.Add('| --- | --- | --- | --- | ---: | --- |')
foreach ($file in $files) {
    $markdown.Add("| $(ConvertTo-MarkdownCell $file.Name) | $(ConvertTo-MarkdownCell $file.Status) | $(ConvertTo-MarkdownCell $file.InstalledSha256) | $(ConvertTo-MarkdownCell $file.ReferenceSha256) | $(ConvertTo-MarkdownCell $file.InstalledSize) | $(ConvertTo-MarkdownCell $file.InstalledModifiedUtc) |")
}
$markdown.Add('')
$markdown.Add('`match` means the installed file SHA-256 equals the corresponding repository build artifact. `reference-missing` preserves the installed hash but cannot prove that comparison.')
$markdown.Add('')
$markdown.Add('### Compared paths')
$markdown.Add('')
foreach ($file in $files) {
    $markdown.Add("- $($file.Name) installed: $([char]96)$(ConvertTo-MarkdownCell $file.InstalledPath)$([char]96)")
    $markdown.Add("- $($file.Name) reference: $([char]96)$(ConvertTo-MarkdownCell $file.ReferencePath)$([char]96)")
}
$markdown.Add('')
$markdown.Add('## Host outcomes')
$markdown.Add('')
$markdown.Add('| Host | Architecture | Executable | Outcome | First | Middle | Final | Cycles | Minutes | Long-session | Notes |')
$markdown.Add('| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |')
foreach ($hostOutcome in $hostOutcomes) {
    $markdown.Add("| $(ConvertTo-MarkdownCell $hostOutcome.Host) | $(ConvertTo-MarkdownCell $hostOutcome.Architecture) | $(ConvertTo-MarkdownCell $hostOutcome.Executable) | $(ConvertTo-MarkdownCell $hostOutcome.Outcome) | $($hostOutcome.FirstSegmentSwitches) | $($hostOutcome.MiddleSegmentSwitches) | $($hostOutcome.FinalSegmentSwitches) | $($hostOutcome.CompletedCycles) | $($hostOutcome.SessionMinutes) | $($hostOutcome.LongSessionStatus) | $(ConvertTo-MarkdownCell $hostOutcome.Notes) |")
}
$markdown.Add('')
$markdown.Add('A complete report requires an explicit `pass` for every host. `fail` makes the report failed; `blocked`, `not-run`, and `not-recorded` keep it partial.')
$markdown.Add("When long-session verification is required, every host must complete at least $MinimumCyclesPerHost first/middle/final cycles and the log must contain the corresponding classified RPC evidence.")
$markdown.Add('')
$markdown.Add('## Process snapshot')
$markdown.Add('')
$markdown.Add('| Process | State | PID | Executable path | Started (UTC) |')
$markdown.Add('| --- | --- | ---: | --- | --- |')
foreach ($process in $processes) {
    $markdown.Add("| $(ConvertTo-MarkdownCell $process.Name) | $(ConvertTo-MarkdownCell $process.State) | $(ConvertTo-MarkdownCell $process.ProcessId) | $(ConvertTo-MarkdownCell $process.ExecutablePath) | $(ConvertTo-MarkdownCell $process.StartTimeUtc) |")
}
$markdown.Add('')
$markdown.Add('## selectCompositionSegment RPC evidence')
$markdown.Add('')
$markdown.Add('- Log: ' + [char]96 + (ConvertTo-MarkdownCell $rpc.LogPath) + [char]96)
$markdown.Add("- Log exists: $($rpc.LogExists)")
$markdown.Add("- Log modified (UTC): $(ConvertTo-MarkdownCell $rpc.LogModifiedUtc)")
$markdown.Add("- Tail lines scanned: $($rpc.LinesScanned)")
$markdown.Add("- Transactions found: $($rpc.Transactions.Count)")
$markdown.Add("- Transactions with correlated responses: $($completeRpcTransactions.Count)")
$markdown.Add("- Successful correlated responses: $($successfulRpcTransactions.Count)")
$markdown.Add("- Classified first/middle/final transactions: $($rpcPositionCounts.first)/$($rpcPositionCounts.middle)/$($rpcPositionCounts.final)")
$markdown.Add("- Required classified transactions per position: $requiredPositionTransactions")
$markdown.Add('')
if ($rpc.Transactions.Count -eq 0) {
    $markdown.Add('_No selectCompositionSegment transactions were found in the scanned log tail._')
} else {
    foreach ($transaction in $rpc.Transactions) {
        $markdown.Add("### client=$(ConvertTo-MarkdownCell $transaction.Client), seq=$($transaction.SeqNum)")
        $markdown.Add('')
        $markdown.Add('```text')
        foreach ($line in $transaction.RequestLines) { $markdown.Add($line) }
        if ($transaction.ResponseFound) {
            $markdown.Add($transaction.ResponseLine)
        } else {
            $markdown.Add('<matching response not found in scanned log tail>')
        }
        $markdown.Add('```')
        $markdown.Add('')
    }
}

$markdown.Add('## Paging ownership guard')
$markdown.Add('')
$markdown.Add("- Owner: $([char]96)$($paging.Owner)$([char]96)")
$markdown.Add("- Status: $([char]96)$($paging.Status)$([char]96)")
$markdown.Add("- Implementation SHA-256: $([char]96)$(ConvertTo-MarkdownCell $paging.ImplementationSha256)$([char]96)")
$markdown.Add("- Regression: $([char]96)$($paging.RegressionTest)$([char]96)")
$markdown.Add("- Regression source SHA-256: $([char]96)$(ConvertTo-MarkdownCell $paging.TestSha256)$([char]96)")
$markdown.Add('')

New-Item -ItemType Directory -Path $outputDirectoryPath -Force | Out-Null
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($reportPath, $markdown, $utf8WithoutBom)

$acceptance = [pscustomobject][ordered]@{
    SchemaVersion = 2
    CapturedAt = $capturedAt.ToString('o')
    Status = $overall
    RequireLongSession = [bool]$RequireLongSession
    MinimumCyclesPerHost = $MinimumCyclesPerHost
    MinimumCorrelatedRpcTransactions = $MinimumCorrelatedRpcTransactions
    RequiredClassifiedTransactionsPerPosition = $requiredPositionTransactions
    RepoRoot = $repoRootPath
    InstallRoot = $installRootPath
    Build = $build
    FileRecords = $files
    HostOutcomeRecords = $hostOutcomes
    Rpc = [pscustomobject][ordered]@{
        LogPath = $rpc.LogPath
        LogSha256 = if ($rpc.LogExists) { (Get-FileHash -LiteralPath $rpc.LogPath -Algorithm SHA256).Hash } else { $null }
        Transactions = $rpc.Transactions
        CorrelatedTransactionCount = $completeRpcTransactions.Count
        SuccessfulTransactionCount = $successfulRpcTransactions.Count
        ClassifiedPositionCounts = [pscustomobject]$rpcPositionCounts
    }
    PagingOwnership = $paging
    MarkdownReportPath = $reportPath
}
[IO.File]::WriteAllText($jsonReportPath, ($acceptance | ConvertTo-Json -Depth 6), $utf8WithoutBom)

$summary = [pscustomobject][ordered]@{
    Status = $overall
    ReportPath = $reportPath
    AcceptancePath = $jsonReportPath
    FileRecords = $files
    Build = $build
    PagingOwnership = $paging
    ProcessRecords = $processes
    HostOutcomeRecords = $hostOutcomes
    RpcTransactionCount = $rpc.Transactions.Count
    RpcCompleteTransactionCount = $completeRpcTransactions.Count
    RpcSuccessfulTransactionCount = $successfulRpcTransactions.Count
    RpcClassifiedPositionCounts = [pscustomobject]$rpcPositionCounts
    LongSessionComplete = $longSessionComplete
}
Write-Host "Sentence segment evidence report: $reportPath"
Write-Host "Sentence segment acceptance record: $jsonReportPath"
Write-Host "Installed runtime evidence status: $overall"

if ($RequireComplete -and $overall -ne 'complete') {
    throw "Installed runtime evidence is $overall; report was saved to $reportPath"
}
$summary
