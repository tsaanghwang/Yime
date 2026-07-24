param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'PIME\Logs\go_backend.log'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) '.tmp\sentence-segment-evidence'),
    [int]$LogTailLines = 5000,
    [int]$MaxRpcTransactions = 50,
    [string[]]$ProcessNames = @('PIMELauncher', 'server'),
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
                ResponseLine = $null
            }
        }
        $transactionsByKey[$key].RequestLines.Add($line)
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
        [pscustomobject][ordered]@{
            Client = $_.Client
            SeqNum = $_.SeqNum
            RequestLines = @($_.RequestLines)
            ResponseLine = $_.ResponseLine
            ResponseFound = [bool]$_.ResponseLine
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

$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$installRootPath = [IO.Path]::GetFullPath($InstallRoot)
$outputDirectoryPath = [IO.Path]::GetFullPath($OutputDirectory)
$capturedAt = [DateTimeOffset]::Now
$stamp = $capturedAt.ToString('yyyyMMdd-HHmmss-fff')
$reportPath = Join-Path $outputDirectoryPath "sentence-segment-evidence-$stamp.md"

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
$processes = @(Get-EvidenceProcessSnapshot -Names $ProcessNames)
$rpc = Get-CompositionSegmentRpcEvidence -Path $LogPath -TailLines $LogTailLines -MaxTransactions $MaxRpcTransactions

$failedFiles = @($files | Where-Object { $_.Status -in @('installed-missing', 'mismatch') })
$unverifiedFiles = @($files | Where-Object { $_.Status -eq 'reference-missing' })
$overall = if ($failedFiles.Count -gt 0) {
    'failed'
} elseif ($unverifiedFiles.Count -gt 0) {
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

New-Item -ItemType Directory -Path $outputDirectoryPath -Force | Out-Null
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($reportPath, $markdown, $utf8WithoutBom)

$summary = [pscustomobject][ordered]@{
    Status = $overall
    ReportPath = $reportPath
    FileRecords = $files
    ProcessRecords = $processes
    RpcTransactionCount = $rpc.Transactions.Count
}
Write-Host "Sentence segment evidence report: $reportPath"
Write-Host "Installed runtime evidence status: $overall"

if ($RequireComplete -and $overall -ne 'complete') {
    throw "Installed runtime evidence is $overall; report was saved to $reportPath"
}
$summary
