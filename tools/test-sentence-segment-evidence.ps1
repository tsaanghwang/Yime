$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$captureScript = Join-Path $PSScriptRoot 'capture-sentence-segment-evidence.ps1'
$verifyScript = Join-Path $PSScriptRoot 'verify-installed-runtime.ps1'
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path $root '.tmp'))
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $temporaryRoot ('test-sentence-segment-evidence-' + [guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($temporaryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use fixture path outside the repository temporary directory: $fixtureRoot"
}
$repoRoot = Join-Path $fixtureRoot 'repo'
$installRoot = Join-Path $fixtureRoot 'install'
$logPath = Join-Path $fixtureRoot 'go_backend.log'
$outputDirectory = Join-Path $fixtureRoot 'reports'

function Write-RecorderFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Cycles = 2,
        [switch]$AddFailure,
        [switch]$BadForegroundIdentity,
        [switch]$TamperFinalCounts,
        [switch]$OmitTerminalEvent
    )

    $sessionId = 'fixture-session-' + [guid]::NewGuid().ToString('N')
    $startedAt = [DateTimeOffset]'2026-07-24T16:00:00+08:00'
    $fixtureState = [pscustomobject]@{ EventNumber = 0 }
    $counts = [ordered]@{
        notepad = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
        codex = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
        charmap = [ordered]@{ first = 0; middle = 0; final = 0; failures = 0 }
    }
    $records = [Collections.Generic.List[object]]::new()
    $addRecord = {
        param([string]$Event, [string]$HostId = '', [string]$Position = '', $Foreground = $null)
        $fixtureState.EventNumber++
        $hostCounts = [ordered]@{}
        foreach ($id in @('notepad', 'codex', 'charmap')) {
            $completed = [math]::Min($counts[$id].first, [math]::Min($counts[$id].middle, $counts[$id].final))
            $hostCounts[$id] = [ordered]@{
                first = $counts[$id].first; middle = $counts[$id].middle; final = $counts[$id].final
                completed_cycles = $completed; failures = $counts[$id].failures
            }
        }
        $record = [ordered]@{
            schema_version = 2
            event = $Event
            session_id = $sessionId
            timestamp = $startedAt.AddSeconds($fixtureState.EventNumber).ToString('o')
            minimum_cycles_per_host = $Cycles
            host_counts = $hostCounts
        }
        if ($HostId) {
            $record.segment_event_id = "segment-$($fixtureState.EventNumber)"
            $record.host_id = $HostId
            $record.position = $Position
        }
        if ($null -ne $Foreground) { $record.foreground = $Foreground }
        $records.Add($record)
    }

    & $addRecord 'session_started'
    foreach ($hostId in @('notepad', 'codex', 'charmap')) {
        $foreground = switch ($hostId) {
            'notepad' { [ordered]@{ process_id = 101; process_name = 'notepad'; executable = 'C:\Windows\notepad.exe'; architecture = 'x64'; window_title = 'Untitled - Notepad'; window_handle = '0x101'; rejection_reason = $null } }
            'codex' {
                if ($BadForegroundIdentity) {
                    [ordered]@{ process_id = 202; process_name = 'powershell'; executable = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'; architecture = 'x64'; window_title = 'PowerShell'; window_handle = '0x202'; rejection_reason = $null }
                } else {
                    [ordered]@{ process_id = 202; process_name = 'ChatGPT'; executable = 'C:\Program Files\WindowsApps\ChatGPT\ChatGPT.exe'; architecture = 'x64'; window_title = 'Codex'; window_handle = '0x202'; rejection_reason = $null }
                }
            }
            'charmap' { [ordered]@{ process_id = 303; process_name = 'charmap'; executable = 'C:\Windows\SysWOW64\charmap.exe'; architecture = 'x86'; window_title = 'Character Map'; window_handle = '0x303'; rejection_reason = $null } }
        }
        for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
            foreach ($position in @('first', 'middle', 'final')) {
                $counts[$hostId][$position]++
                & $addRecord 'segment_result' $hostId $position $foreground
            }
        }
    }
    if ($AddFailure) {
        $counts.codex.failures++
        $foreground = [ordered]@{ process_id = 202; process_name = 'ChatGPT'; executable = 'C:\Program Files\WindowsApps\ChatGPT\ChatGPT.exe'; architecture = 'x64'; window_title = 'Codex'; window_handle = '0x202'; rejection_reason = $null }
        & $addRecord 'segment_result' 'codex' 'failure' $foreground
    }
    if (-not $OmitTerminalEvent) { & $addRecord 'evidence_snapshot' }
    if ($TamperFinalCounts) { $records[$records.Count - 1].host_counts.notepad.first++ }

    $jsonLines = @($records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 7 })
    [IO.File]::WriteAllLines($Path, $jsonLines, (New-Object Text.UTF8Encoding($false)))
}

try {
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'go-backend\build\go-backend') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'go-backend\input_methods\yime') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'build\PIMETextService\Release') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'build64\PIMETextService\Release') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installRoot 'go-backend') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installRoot 'x86') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installRoot 'x64') -Force | Out-Null

    $fixtures = @(
        @('go-backend\build\go-backend\server.exe', 'go-backend\server.exe', 'server fixture'),
        @('build\PIMETextService\Release\PIMETextService.dll', 'x86\PIMETextService.dll', 'x86 fixture'),
        @('build64\PIMETextService\Release\PIMETextService.dll', 'x64\PIMETextService.dll', 'x64 fixture')
    )
    foreach ($fixture in $fixtures) {
        Set-Content -LiteralPath (Join-Path $repoRoot $fixture[0]) -Value $fixture[2] -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $installRoot $fixture[1]) -Value $fixture[2] -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $repoRoot 'version.txt') -Value '1.4.0-test' -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $installRoot 'version.txt') -Value '1.4.0-test' -Encoding UTF8 -NoNewline
    @'
func (b *nativeBackend) UsesBackendCandidatePaging() bool {
    return true
}
'@ | Set-Content -LiteralPath (Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo.go') -Encoding UTF8
    'func TestNativeBackendKeepsRimeOwnedCandidatePaging() {}' |
        Set-Content -LiteralPath (Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo_test.go') -Encoding UTF8
    & git -C $repoRoot init --quiet
    & git -C $repoRoot config user.email 'fixture@yime.invalid'
    & git -C $repoRoot config user.name 'Yime Fixture'
    & git -C $repoRoot add .
    & git -C $repoRoot commit --quiet -m 'fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the evidence fixture Git identity.' }

    @(
        '2026/07/24 15:00:00 request client=client-a method=selectCompositionSegment seq=42 cursor=0 selStart=0 selEnd=1 data=',
        '2026/07/24 15:00:00 forward client=client-a seq=42 method=selectCompositionSegment guid=test',
        '2026/07/24 15:00:00 response client=other payload={"seqNum":42,"success":false}',
        '2026/07/24 15:00:00 response client=client-a payload={"seqNum":42,"success":true,"return":true,"compositionSegments":[{"start":0,"end":1,"active":true},{"start":1,"end":2},{"start":2,"end":3}]}',
        '2026/07/24 15:00:01 request client=client-b method=onKeyDown seq=43 cursor=0 data='
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8

    $readOnlyInputPaths = @(
        (Join-Path $installRoot 'go-backend\server.exe'),
        (Join-Path $installRoot 'x86\PIMETextService.dll'),
        (Join-Path $installRoot 'x64\PIMETextService.dll'),
        $logPath
    )
    $readOnlyInputBefore = @($readOnlyInputPaths | ForEach-Object {
        $item = Get-Item -LiteralPath $_
        [pscustomobject]@{
            Path = $item.FullName
            Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            ModifiedUtc = $item.LastWriteTimeUtc
        }
    })

    $result = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $logPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -NotepadOutcome pass `
        -NotepadNotes 'first, middle, and final segments passed' `
        -CodexIdeOutcome pass `
        -CodexIdeNotes 'composition remained active' `
        -SysWow64CharmapOutcome pass `
        -SysWow64CharmapNotes 'x86 installed DLL exercised' `
        -RequireComplete

    if ($result.Status -ne 'complete') { throw "Expected complete evidence, got $($result.Status)." }
    if ($result.RpcTransactionCount -ne 1) { throw "Expected one RPC transaction, got $($result.RpcTransactionCount)." }
    if ($result.RpcCompleteTransactionCount -ne 1) { throw "Expected one correlated RPC transaction, got $($result.RpcCompleteTransactionCount)." }
    if ($result.HostOutcomeRecords.Count -ne 3) { throw "Expected three host outcomes, got $($result.HostOutcomeRecords.Count)." }
    if (-not (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) { throw 'Evidence report was not created.' }
    $report = Get-Content -LiteralPath $result.ReportPath -Raw -Encoding UTF8
    foreach ($fragment in @(
        'Status: **complete**',
        'server.exe | match',
        'x86/PIMETextService.dll | match',
        'x64/PIMETextService.dll | match',
        'x64 Notepad | x64 | Notepad | pass | 0 | 0 | 0 | 0 | 0 | incomplete | first, middle, and final segments passed',
        'Codex IDE | x64 | Codex IDE | pass | 0 | 0 | 0 | 0 | 0 | incomplete | composition remained active',
        'x86 SysWOW64 charmap | x86 | C:\Windows\SysWOW64\charmap.exe | pass | 0 | 0 | 0 | 0 | 0 | incomplete | x86 installed DLL exercised',
        'Transactions with correlated responses: 1',
        'Classified first/middle/final transactions: 1/0/0',
        'Status: `guarded`',
        'client=client-a, seq=42',
        'response client=client-a payload={"seqNum":42,"success":true,"return":true,'
    )) {
        if (-not $report.Contains($fragment)) { throw "Evidence report is missing: $fragment" }
    }
    if ($report.Contains('response client=other')) { throw 'RPC correlation included a response from the wrong client.' }
    if (-not (Test-Path -LiteralPath $result.AcceptancePath -PathType Leaf)) { throw 'JSON acceptance record was not created.' }
    $acceptance = Get-Content -LiteralPath $result.AcceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$acceptance.SchemaVersion -ne 2 -or [string]$acceptance.Build.Version -ne '1.4.0-test') {
        throw 'Acceptance record did not preserve its schema and build version.'
    }
    if ([string]$acceptance.PagingOwnership.Owner -ne 'rime-native-backend' -or
        [string]$acceptance.PagingOwnership.Status -ne 'guarded') {
        throw 'Acceptance record did not preserve the Rime-owned paging guard.'
    }
    foreach ($before in $readOnlyInputBefore) {
        $after = Get-Item -LiteralPath $before.Path
        $afterHash = (Get-FileHash -LiteralPath $after.FullName -Algorithm SHA256).Hash
        if ($afterHash -ne $before.Sha256 -or $after.LastWriteTimeUtc -ne $before.ModifiedUtc) {
            throw "Capture modified a read-only PIME evidence input: $($before.Path)"
        }
    }

    $longSessionLogPath = Join-Path $fixtureRoot 'go_backend_long_session.log'
    $longSessionLines = [Collections.Generic.List[string]]::new()
    $sequence = 100
    foreach ($client in @('notepad-x64', 'codex-x64', 'charmap-x86')) {
        for ($cycle = 1; $cycle -le 2; $cycle++) {
            foreach ($target in @(
                @{ Position = 'first'; Cursor = 0; End = 1; Active = 0 },
                @{ Position = 'middle'; Cursor = 1; End = 2; Active = 1 },
                @{ Position = 'final'; Cursor = 2; End = 3; Active = 2 }
            )) {
                $sequence++
                $longSessionLines.Add("2026/07/24 16:00:00 request client=$client method=selectCompositionSegment seq=$sequence cursor=$($target.Cursor) selStart=$($target.Cursor) selEnd=$($target.End) data=")
                $segments = @(
                    @{ start = 0; end = 1; active = $target.Active -eq 0 },
                    @{ start = 1; end = 2; active = $target.Active -eq 1 },
                    @{ start = 2; end = 3; active = $target.Active -eq 2 }
                )
                $payload = @{ seqNum = $sequence; success = $true; 'return' = $true; compositionString = 'abc'; compositionSegments = $segments } | ConvertTo-Json -Compress
                $longSessionLines.Add("2026/07/24 16:00:00 response client=$client payload=$payload")
            }
        }
    }
    $longSessionLines | Set-Content -LiteralPath $longSessionLogPath -Encoding UTF8
    $longSessionResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $longSessionLogPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -MinimumCyclesPerHost 2 `
        -MinimumCorrelatedRpcTransactions 18 `
        -NotepadOutcome pass `
        -NotepadFirstSegmentSwitches 2 `
        -NotepadMiddleSegmentSwitches 2 `
        -NotepadFinalSegmentSwitches 2 `
        -CodexIdeOutcome pass `
        -CodexIdeFirstSegmentSwitches 2 `
        -CodexIdeMiddleSegmentSwitches 2 `
        -CodexIdeFinalSegmentSwitches 2 `
        -SysWow64CharmapOutcome pass `
        -SysWow64CharmapFirstSegmentSwitches 2 `
        -SysWow64CharmapMiddleSegmentSwitches 2 `
        -SysWow64CharmapFinalSegmentSwitches 2 `
        -RequireLongSession `
        -RequireComplete
    if (-not $longSessionResult.LongSessionComplete -or $longSessionResult.Status -ne 'complete') {
        throw 'Focused long-session fixture did not satisfy the acceptance gate.'
    }
    if ($longSessionResult.RpcSuccessfulTransactionCount -ne 18 -or
        $longSessionResult.RpcClassifiedPositionCounts.first -ne 6 -or
        $longSessionResult.RpcClassifiedPositionCounts.middle -ne 6 -or
        $longSessionResult.RpcClassifiedPositionCounts.final -ne 6) {
        throw "Long-session RPC classification was incomplete: $($longSessionResult.RpcClassifiedPositionCounts | ConvertTo-Json -Compress)"
    }
    $longSessionAcceptance = Get-Content -LiteralPath $longSessionResult.AcceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$longSessionAcceptance.RequireLongSession -or
        [int]$longSessionAcceptance.RequiredClassifiedTransactionsPerPosition -ne 6) {
        throw 'Long-session acceptance record omitted its repeatability threshold.'
    }

    $recorderPath = Join-Path $fixtureRoot 'three-host-schema2.jsonl'
    Write-RecorderFixture -Path $recorderPath
    $recorderResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $longSessionLogPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -RecorderRecordPath $recorderPath `
        -RequireComplete
    if ($recorderResult.Status -ne 'complete' -or -not $recorderResult.LongSessionComplete -or
        -not $recorderResult.RecorderRecord.Provided -or $recorderResult.RecorderRecord.Status -ne 'match') {
        throw 'Schema 2 recorder record did not produce complete long-session evidence.'
    }
    foreach ($hostOutcome in @($recorderResult.HostOutcomeRecords)) {
        if ($hostOutcome.FirstSegmentSwitches -ne 2 -or $hostOutcome.MiddleSegmentSwitches -ne 2 -or
            $hostOutcome.FinalSegmentSwitches -ne 2 -or $hostOutcome.FailureCount -ne 0 -or
            $hostOutcome.ForegroundEventCount -ne 6 -or -not $hostOutcome.RecorderHostId) {
            throw "Recorder host data was not imported: $($hostOutcome | ConvertTo-Json -Compress)"
        }
    }
    $recorderAcceptance = Get-Content -LiteralPath $recorderResult.AcceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$recorderAcceptance.RequireLongSession -or
        [int]$recorderAcceptance.MinimumCorrelatedRpcTransactions -ne 18 -or
        [string]$recorderAcceptance.RecorderRecord.Sha256 -ne (Get-FileHash -LiteralPath $recorderPath -Algorithm SHA256).Hash -or
        @($recorderAcceptance.RecorderRecord.ForegroundIdentityRecords).Count -ne 18) {
        throw 'Recorder-backed acceptance record is not suitable for installed-runtime verification.'
    }

    $rimeFixtureDirectory = Join-Path $fixtureRoot 'rime-user'
    New-Item -ItemType Directory -Path $rimeFixtureDirectory -Force | Out-Null
    $verificationJsonPath = Join-Path $fixtureRoot 'installed-runtime-verification.json'
    try {
        & $verifyScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -RimeUserDir $rimeFixtureDirectory `
            -LongSessionAcceptancePath $recorderResult.AcceptancePath `
            -JsonPath $verificationJsonPath | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Installed runtime verification failed') { throw }
    }
    $verification = Get-Content -LiteralPath $verificationJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$verification.longSessionAcceptance.status -ne 'match') {
        throw "Installed-runtime verifier rejected the recorder-backed acceptance: $($verification.longSessionAcceptance.issues -join '; ')"
    }

    [IO.File]::AppendAllText($recorderPath, "`r`n", (New-Object Text.UTF8Encoding($false)))
    $changedVerificationJsonPath = Join-Path $fixtureRoot 'installed-runtime-verification-changed-record.json'
    try {
        & $verifyScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -RimeUserDir $rimeFixtureDirectory `
            -LongSessionAcceptancePath $recorderResult.AcceptancePath `
            -JsonPath $changedVerificationJsonPath | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Installed runtime verification failed') { throw }
    }
    $changedVerification = Get-Content -LiteralPath $changedVerificationJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$changedVerification.longSessionAcceptance.status -ne 'mismatch' -or
        (@($changedVerification.longSessionAcceptance.issues) -join '; ') -notmatch 'recorder record changed after acceptance') {
        throw 'Installed-runtime verifier accepted a recorder JSONL that changed after acceptance.'
    }

    try {
        & $captureScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -LogPath $longSessionLogPath `
            -OutputDirectory $outputDirectory `
            -ProcessNames '__yime_evidence_fixture_process__' `
            -RecorderRecordPath $recorderPath `
            -NotepadFirstSegmentSwitches 3 | Out-Null
        throw 'Recorder record accepted mismatched explicit manual counts.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not match explicitly supplied') { throw }
    }

    $incompleteRecorderPath = Join-Path $fixtureRoot 'three-host-incomplete.jsonl'
    Write-RecorderFixture -Path $incompleteRecorderPath -OmitTerminalEvent
    try {
        & $captureScript -RepoRoot $repoRoot -InstallRoot $installRoot -LogPath $longSessionLogPath `
            -OutputDirectory $outputDirectory -RecorderRecordPath $incompleteRecorderPath | Out-Null
        throw 'Capture accepted an unterminated recorder record.'
    } catch {
        if ($_.Exception.Message -notmatch 'Recorder record is incomplete') { throw }
    }

    $tamperedRecorderPath = Join-Path $fixtureRoot 'three-host-tampered.jsonl'
    Write-RecorderFixture -Path $tamperedRecorderPath -TamperFinalCounts
    try {
        & $captureScript -RepoRoot $repoRoot -InstallRoot $installRoot -LogPath $longSessionLogPath `
            -OutputDirectory $outputDirectory -RecorderRecordPath $tamperedRecorderPath | Out-Null
        throw 'Capture accepted recorder counts that did not match event replay.'
    } catch {
        if ($_.Exception.Message -notmatch 'host count mismatch') { throw }
    }

    $identityMismatchPath = Join-Path $fixtureRoot 'three-host-identity-mismatch.jsonl'
    Write-RecorderFixture -Path $identityMismatchPath -BadForegroundIdentity
    try {
        & $captureScript -RepoRoot $repoRoot -InstallRoot $installRoot -LogPath $longSessionLogPath `
            -OutputDirectory $outputDirectory -RecorderRecordPath $identityMismatchPath | Out-Null
        throw 'Capture accepted a mismatched foreground host identity.'
    } catch {
        if ($_.Exception.Message -notmatch 'foreground identity does not match host codex') { throw }
    }

    $failureRecorderPath = Join-Path $fixtureRoot 'three-host-failure.jsonl'
    Write-RecorderFixture -Path $failureRecorderPath -AddFailure
    $failureRecorderResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $longSessionLogPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -RecorderRecordPath $failureRecorderPath
    $codexFailure = @($failureRecorderResult.HostOutcomeRecords | Where-Object RecorderHostId -eq 'codex')[0]
    if ($failureRecorderResult.Status -ne 'failed' -or $codexFailure.Outcome -ne 'fail' -or
        $codexFailure.FailureCount -ne 1 -or $codexFailure.ForegroundEventCount -ne 7) {
        throw 'Recorder failure events were not imported into the failed acceptance outcome.'
    }

    $underCountResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $longSessionLogPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -MinimumCyclesPerHost 2 `
        -NotepadOutcome pass `
        -CodexIdeOutcome pass `
        -SysWow64CharmapOutcome pass `
        -RequireLongSession
    if ($underCountResult.Status -ne 'partial' -or $underCountResult.LongSessionComplete) {
        throw 'Long-session gate accepted hosts without explicit repeated segment counts.'
    }

    $partialResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $logPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__'
    if ($partialResult.Status -ne 'partial') {
        throw "Missing host outcomes should produce partial evidence, got $($partialResult.Status)."
    }
    $partialReport = Get-Content -LiteralPath $partialResult.ReportPath -Raw -Encoding UTF8
    foreach ($hostLabel in @('x64 Notepad', 'Codex IDE', 'x86 SysWOW64 charmap')) {
        if (-not $partialReport.Contains("$hostLabel |")) {
            throw "Partial report omitted the host label: $hostLabel"
        }
    }
    if (([regex]::Matches($partialReport, [regex]::Escape('| not-recorded |'))).Count -ne 3) {
        throw 'Partial report did not explicitly record all three missing host outcomes.'
    }
    try {
        & $captureScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -LogPath $logPath `
            -OutputDirectory $outputDirectory `
            -ProcessNames '__yime_evidence_fixture_process__' `
            -RequireComplete | Out-Null
        throw 'RequireComplete accepted missing host outcomes.'
    } catch {
        if ($_.Exception.Message -notmatch 'evidence is partial') { throw }
    }

    $noRpcLogPath = Join-Path $fixtureRoot 'go_backend_without_segment_rpc.log'
    '2026/07/24 15:00:01 request client=client-b method=onKeyDown seq=43 cursor=0 data=' |
        Set-Content -LiteralPath $noRpcLogPath -Encoding UTF8
    $noRpcResult = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $noRpcLogPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -NotepadOutcome pass `
        -CodexIdeOutcome pass `
        -SysWow64CharmapOutcome pass
    if ($noRpcResult.Status -ne 'partial') {
        throw "Missing correlated RPC evidence should produce partial evidence, got $($noRpcResult.Status)."
    }
    $noRpcReport = Get-Content -LiteralPath $noRpcResult.ReportPath -Raw -Encoding UTF8
    if (-not $noRpcReport.Contains('Transactions with correlated responses: 0')) {
        throw 'Partial report did not record the missing correlated RPC evidence.'
    }

    Set-Content -LiteralPath (Join-Path $installRoot 'x86\PIMETextService.dll') -Value 'mismatch fixture' -Encoding UTF8
    $beforeFailureReports = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.md').Count
    try {
        & $captureScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -LogPath $logPath `
            -OutputDirectory $outputDirectory `
            -ProcessNames '__yime_evidence_fixture_process__' `
            -NotepadOutcome pass `
            -CodexIdeOutcome pass `
            -SysWow64CharmapOutcome pass `
            -RequireComplete | Out-Null
        throw 'RequireComplete accepted a mismatched installed DLL.'
    } catch {
        if ($_.Exception.Message -notmatch 'evidence is failed') { throw }
    }
    $failureReports = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.md' | Sort-Object LastWriteTime)
    if ($failureReports.Count -le $beforeFailureReports) { throw 'Failure evidence report was not preserved.' }
    $failureReport = Get-Content -LiteralPath $failureReports[-1].FullName -Raw -Encoding UTF8
    if (-not $failureReport.Contains('x86/PIMETextService.dll | mismatch')) {
        throw 'Failure report did not identify the mismatched x86 DLL.'
    }

    Write-Host 'Sentence segment installed-runtime evidence tests passed.'
} finally {
    if ($fixtureRoot.StartsWith($temporaryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $fixtureRoot)) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
