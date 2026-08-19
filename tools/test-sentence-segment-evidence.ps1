$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$captureScript = Join-Path $PSScriptRoot 'capture-sentence-segment-evidence.ps1'
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path $root '.tmp'))
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $temporaryRoot ('test-sentence-segment-evidence-' + [guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($temporaryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use fixture path outside the repository temporary directory: $fixtureRoot"
}
$repoRoot = Join-Path $fixtureRoot 'repo'
$installRoot = Join-Path $fixtureRoot 'install'
$logPath = Join-Path $fixtureRoot 'go_backend.log'
$outputDirectory = Join-Path $fixtureRoot 'reports'

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
    @'
func (b *nativeBackend) UsesBackendCandidatePaging() bool {
    return true
}
'@ | Set-Content -LiteralPath (Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo.go') -Encoding UTF8
    'func TestNativeBackendKeepsRimeOwnedCandidatePaging() {}' |
        Set-Content -LiteralPath (Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo_test.go') -Encoding UTF8

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
