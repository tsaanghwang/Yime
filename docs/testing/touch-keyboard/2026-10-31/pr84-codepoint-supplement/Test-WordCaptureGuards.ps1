# Synthetic integration tests: no COM attachment, Word launch or document changes.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Read-WordCodepoints.ps1" -SelfTest
Add-Type -TypeDefinition @'
using System;
public static class WordCaptureNative {
    public static uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId) {
        processId = hwnd.ToInt64() == 1001 ? 101u : 202u;
        return hwnd == IntPtr.Zero ? 0u : 1u;
    }
}
'@
function Get-WordProcesses {
    if ($script:enumerationFails) { throw 'Synthetic enumeration failure' }
    $script:checks++
    if ($script:checks -gt 1 -and $script:changeAfterRead) { return @([pscustomobject]@{Id=202}) }
    return $script:processes
}
$doc = New-Object PSObject
$doc | Add-Member ScriptProperty Content {
    $script:reads++
    return [pscustomobject]@{Text=('12' + [char]0x2026 + [char]13)}
}
$cases = @(
    @{Name='unique'; Ids=@(101); Hwnd=1001; ExpectedReads=1; Reject=$false},
    @{Name='no process'; Ids=@(); Hwnd=1001; ExpectedReads=0; Reject=$true},
    @{Name='two same-name unsaved documents in different processes'; Ids=@(101,202); Hwnd=1001; ExpectedReads=0; Reject=$true},
    @{Name='HWND owner mismatch'; Ids=@(101); Hwnd=2002; ExpectedReads=0; Reject=$true},
    @{Name='missing HWND'; Ids=@(101); Hwnd=0; ExpectedReads=0; Reject=$true},
    @{Name='enumeration failure'; Ids=@(101); Hwnd=1001; ExpectedReads=0; Reject=$true; Fail=$true},
    @{Name='process changes during read'; Ids=@(101); Hwnd=1001; ExpectedReads=1; Reject=$true; Change=$true}
)
foreach ($case in $cases) {
    $script:reads=0; $script:checks=0
    $script:enumerationFails=$case.Fail; $script:changeAfterRead=$case.Change
    $script:processes=@($case.Ids | ForEach-Object { [pscustomobject]@{Id=$_} })
    $rejected=$false; $returned=$false
    try {
        $text = Read-VerifiedWordText ([pscustomobject]@{Hwnd=$case.Hwnd}) $doc 101 1001
        $returned=$true
    } catch { $rejected=$true }
    if ($rejected -ne $case.Reject -or $script:reads -ne $case.ExpectedReads -or ($case.Reject -and $returned)) { throw ('Gate failed: ' + $case.Name) }
    if (!$rejected -and !(Test-Exact (Read-Body $text) (Get-Expected 'W01'))) { throw 'Valid read changed' }
    Write-Output ('PASS synthetic gate: ' + $case.Name + '; content reads=' + $script:reads + '; rejected=' + $rejected)
}
Write-Output 'Seven synthetic integration scenarios passed; no actual Word COM acceptance was performed.'
