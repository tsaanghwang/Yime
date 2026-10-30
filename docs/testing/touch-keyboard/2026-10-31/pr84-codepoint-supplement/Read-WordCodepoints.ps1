[CmdletBinding()]
param(
    [ValidateSet('W01','W02')][string]$CaseId,
    [string]$DocumentName,
    [string]$KeyboardExe,
    [string]$OutputPath,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
function Get-Scalars([string]$Text) {
    $codes = @()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $n = [char]::ConvertToUtf32($Text, $i)
        $codes += ('U+{0:X4}' -f $n)
        if ($n -gt 0xFFFF) { $i++ }
    }
    return ,$codes
}
function Get-Expected([string]$Id) {
    if ($Id -eq 'W01') { return ('12' + [char]0x2026) }
    return ('12' + [char]0x22EF + [char]0x22EF)
}
function Read-Body([string]$Raw) {
    # Remove only Word's mandatory final paragraph mark, never whitespace/extra text.
    if (!$Raw.EndsWith([string][char]13)) { throw 'Missing final Word paragraph mark.' }
    return $Raw.Substring(0, $Raw.Length - 1)
}
if ($SelfTest) {
    foreach ($id in @('W01','W02')) {
        $expected = Get-Expected $id
        if ((Read-Body ($expected + [char]13)) -cne $expected) { throw 'Body mismatch' }
        foreach ($extra in @(' ', [string][char]13, [string][char]0x2026)) {
            if ((Read-Body ($expected + $extra + [char]13)) -ceq $expected) { throw 'Extra character hidden' }
        }
    }
    if ((Get-Scalars ([char]0x2026 + [string][char]0x22EF)) -join ' ' -ne 'U+2026 U+22EF') { throw 'Ellipsis confusion' }
    if ((Get-Scalars ([char]::ConvertFromUtf32(0x1F600))) -join ' ' -ne 'U+1F600') { throw 'Surrogate failure' }
    Write-Output 'Synthetic self-test passed; no Word or host acceptance executed.'
    return
}
if (!$CaseId -or !$DocumentName -or !$KeyboardExe -or !$OutputPath) { throw 'CaseId, DocumentName, KeyboardExe and OutputPath are required.' }
$output = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $output) { throw 'Output already exists; use a new attempt filename.' }
$exe = (Resolve-Path -LiteralPath $KeyboardExe).Path
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne '0e24a31e2088c5b19e39bae8ac78adcc28a9cb258d2f0034b2addac1ec8cbc07') { throw 'Not the PR83 fixed amd64 executable.' }
$word = $null; $doc = $null; $range = $null; $docs = $null
try {
    # Windows PowerShell 5.1: attach only, never create Word or open/save a document.
    $word = [Runtime.InteropServices.Marshal]::GetActiveObject('Word.Application')
    $docs = $word.Documents
    $doc = $docs.Item($DocumentName)
    if ($doc.Name -cne $DocumentName -or $doc.Path -ne '') { throw 'Use the exact name of an unsaved disposable test document.' }
    $range = $doc.Content
    $raw = [string]$range.Text
    $body = Read-Body $raw
    $expected = Get-Expected $CaseId
    $record = [ordered]@{
        schemaVersion=1; capturedAt=[DateTimeOffset]::Now.ToString('o'); machine=$env:COMPUTERNAME
        host='Word'; hostVersion=[string]$word.Version; documentName=$DocumentName
        caseId=$CaseId; method='mouse'; readMethod='Word COM Document.Content.Text (read only)'
        sourceCommit='f01326e6c1976a4e67c9ff59693effc0e1110b1a'; keyboardExeSHA256=$hash
        packageBinding='File hash checked; operator must confirm this executable produced the text'
        rawText=$raw; rawCodepoints=(Get-Scalars $raw); removedFinalParagraphMark=$true
        actualText=$body; actualCodepoints=(Get-Scalars $body); scalarCount=(Get-Scalars $body).Count
        expectedText=$expected; expectedCodepoints=(Get-Scalars $expected)
        exactMatch=($body -ceq $expected); acceptanceStatus='pending-operator-review'
        limitation='Final text detects extra/duplicate characters, not identical replacement events or future delayed commits'
    }
    $json = $record | ConvertTo-Json -Depth 8
    $stream = [IO.File]::Open($output, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n"); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    Write-Output $json
} finally {
    foreach ($obj in @($range,$doc,$docs,$word)) {
        if ($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj) }
    }
}
