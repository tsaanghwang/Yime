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

    @(
        '2026/07/24 15:00:00 request client=client-a method=selectCompositionSegment seq=42 cursor=0 data=',
        '2026/07/24 15:00:00 forward client=client-a seq=42 method=selectCompositionSegment guid=test',
        '2026/07/24 15:00:00 response client=other payload={"seqNum":42,"success":false}',
        '2026/07/24 15:00:00 response client=client-a payload={"seqNum":42,"success":true}',
        '2026/07/24 15:00:01 request client=client-b method=onKeyDown seq=43 cursor=0 data='
    ) | Set-Content -LiteralPath $logPath -Encoding UTF8

    $result = & $captureScript `
        -RepoRoot $repoRoot `
        -InstallRoot $installRoot `
        -LogPath $logPath `
        -OutputDirectory $outputDirectory `
        -ProcessNames '__yime_evidence_fixture_process__' `
        -RequireComplete

    if ($result.Status -ne 'complete') { throw "Expected complete evidence, got $($result.Status)." }
    if ($result.RpcTransactionCount -ne 1) { throw "Expected one RPC transaction, got $($result.RpcTransactionCount)." }
    if (-not (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) { throw 'Evidence report was not created.' }
    $report = Get-Content -LiteralPath $result.ReportPath -Raw -Encoding UTF8
    foreach ($fragment in @(
        'Status: **complete**',
        'server.exe | match',
        'x86/PIMETextService.dll | match',
        'x64/PIMETextService.dll | match',
        'client=client-a, seq=42',
        'response client=client-a payload={"seqNum":42,"success":true}'
    )) {
        if (-not $report.Contains($fragment)) { throw "Evidence report is missing: $fragment" }
    }
    if ($report.Contains('response client=other')) { throw 'RPC correlation included a response from the wrong client.' }

    Set-Content -LiteralPath (Join-Path $installRoot 'x86\PIMETextService.dll') -Value 'mismatch fixture' -Encoding UTF8
    $beforeFailureReports = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.md').Count
    try {
        & $captureScript `
            -RepoRoot $repoRoot `
            -InstallRoot $installRoot `
            -LogPath $logPath `
            -OutputDirectory $outputDirectory `
            -ProcessNames '__yime_evidence_fixture_process__' `
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
