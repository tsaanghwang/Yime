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
function Test-Exact([string]$Actual, [string]$Expected) {
    return [string]::Equals($Actual, $Expected, [StringComparison]::Ordinal)
}
function Assert-UniqueWord([object[]]$Processes, [long]$OwnerId = 0, [long]$ExpectedId = 0) {
    if ($Processes.Count -ne 1) { throw 'Cannot uniquely locate Word: exactly one WINWORD process is required.' }
    $identity = [long]$Processes[0].Id
    if ($identity -le 0 -or ($OwnerId -ne 0 -and $OwnerId -ne $identity) -or
        ($ExpectedId -ne 0 -and $ExpectedId -ne $identity)) { throw 'Word process identity changed or HWND does not match.' }
    return $identity
}
function Get-WordProcesses {
    # Enumerate all processes; enumeration failure must stop the capture.
    return @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -ieq 'WINWORD' })
}
function Assert-WordBinding($Application, [long]$ExpectedId) {
    $handle = [long]$Application.Hwnd
    if ($handle -eq 0) { throw 'Word HWND unavailable.' }
    [uint32]$ownerId = 0
    if ([WordCaptureNative]::GetWindowThreadProcessId([IntPtr]$handle, [ref]$ownerId) -eq 0 -or $ownerId -eq 0) { throw 'Cannot resolve Word HWND owner.' }
    [void](Assert-UniqueWord @(Get-WordProcesses) $ownerId $ExpectedId)
    return $handle
}
function Read-VerifiedWordText($Application, $Document, [long]$ProcessId, [long]$Hwnd) {
    $content = $null
    try {
        if ((Assert-WordBinding $Application $ProcessId) -ne $Hwnd) { throw 'Word HWND changed.' }
        $content = $Document.Content
        $text = [string]$content.Text
        if ((Assert-WordBinding $Application $ProcessId) -ne $Hwnd) { throw 'Word HWND changed during read.' }
        return $text
    } finally {
        if ($null -ne $content -and [Runtime.InteropServices.Marshal]::IsComObject($content)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($content) }
    }
}
if ($SelfTest) {
    foreach ($id in @('W01','W02')) {
        $expected = Get-Expected $id
        if (!(Test-Exact (Read-Body ($expected + [char]13)) $expected)) { throw 'Body mismatch' }
        foreach ($position in @(0,1,$expected.Length)) {
            foreach ($invisible in @(0x00AD,0x200B,0xFEFF)) {
                $changed = $expected.Insert($position, [string][char]$invisible)
                if (Test-Exact (Read-Body ($changed + [char]13)) $expected) { throw 'Invisible character hidden' }
            }
        }
        foreach ($extra in @(' ', [string][char]13, [string][char]0x2026)) {
            if (Test-Exact (Read-Body ($expected + $extra + [char]13)) $expected) { throw 'Extra character hidden' }
        }
    }
    if ((Get-Scalars ([char]0x2026 + [string][char]0x22EF)) -join ' ' -ne 'U+2026 U+22EF') { throw 'Ellipsis confusion' }
    if ((Get-Scalars ([char]::ConvertFromUtf32(0x1F600))) -join ' ' -ne 'U+1F600') { throw 'Surrogate failure' }
    if ((Assert-UniqueWord @([pscustomobject]@{Id=101}) 101 101) -ne 101) { throw 'Unique process failure' }
    foreach ($scenario in @(
        @{ Processes=@(); Owner=0; Expected=0 },
        @{ Processes=@([pscustomobject]@{Id=101},[pscustomobject]@{Id=202}); Owner=101; Expected=101 },
        @{ Processes=@([pscustomobject]@{Id=101}); Owner=202; Expected=101 },
        @{ Processes=@([pscustomobject]@{Id=202}); Owner=202; Expected=101 }
    )) {
        $rejected = $false
        try { [void](Assert-UniqueWord $scenario.Processes $scenario.Owner $scenario.Expected) } catch { $rejected = $true }
        if (!$rejected) { throw 'Ambiguous/mismatched Word was accepted' }
    }
    Write-Output 'Ordinal W01/W02: correct text accepted; U+00AD/U+200B/U+FEFF at start/middle/end rejected (18 negatives). Word identity: unique accepted; zero/multiple/mismatched/changed rejected (synthetic).'
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
    $wordProcessId = Assert-UniqueWord @(Get-WordProcesses)
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WordCaptureNative {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
    $word = [Runtime.InteropServices.Marshal]::GetActiveObject('Word.Application')
    $wordHwnd = Assert-WordBinding $word $wordProcessId
    $docs = $word.Documents
    $doc = $docs.Item($DocumentName)
    if (!(Test-Exact ([string]$doc.Name) $DocumentName) -or $doc.Path -ne '') { throw 'Use the exact name of an unsaved disposable test document.' }
    $raw = Read-VerifiedWordText $word $doc $wordProcessId $wordHwnd
    $body = Read-Body $raw
    $expected = Get-Expected $CaseId
    $record = [ordered]@{
        schemaVersion=1; capturedAt=[DateTimeOffset]::Now.ToString('o'); machine=$env:COMPUTERNAME
        wordProcessId=$wordProcessId; wordHwnd=$wordHwnd; identityPolicy='Unique WINWORD plus COM HWND/PID checked before and after read';
        host='Word'; hostVersion=[string]$word.Version; documentName=$DocumentName
        caseId=$CaseId; method='mouse'; readMethod='Word COM Document.Content.Text (read only)'
        sourceCommit='f01326e6c1976a4e67c9ff59693effc0e1110b1a'; keyboardExeSHA256=$hash
        packageBinding='File hash checked; operator must confirm this executable produced the text'
        rawText=$raw; rawCodepoints=(Get-Scalars $raw); removedFinalParagraphMark=$true
        actualText=$body; actualCodepoints=(Get-Scalars $body); scalarCount=(Get-Scalars $body).Count
        expectedText=$expected; expectedCodepoints=(Get-Scalars $expected)
        exactMatch=(Test-Exact $body $expected); acceptanceStatus='pending-operator-review'
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
