[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourceFont,[switch]$UiSmoke)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$root=Join-Path $repo ('.tmp\dual-product\application-use-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$font=Join-Path $root 'font.ttf';$peer=Join-Path $root 'peer.ttf'
[IO.File]::Copy($SourceFont,$font);[IO.File]::Copy($SourceFont,$peer)
$hash=(Get-FileHash -LiteralPath $font).Hash
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MaintenanceFontFixture {
[DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string p,uint f,IntPtr r);
[DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string p,uint f,IntPtr r);
}
'@
$module=Import-Module (Join-Path $PSScriptRoot 'maintenance-application-use.psm1') -PassThru
$loaded=$false;$peerLoaded=$false
try{
    $data=Join-Path $root 'held.bin';[IO.File]::WriteAllText($data,'unmodified')
    $held=[IO.File]::Open($data,'Open','Read','Read')
    try{
        $ordinary=Get-MaintenanceApplicationUse $root @('held.bin')
        if($ordinary.clear -or @($ordinary.applications|Where-Object Pid -eq $PID).Count -ne 1){throw 'Real application name/PID not identified for an ordinary held file'}
    }finally{$held.Dispose()}
    [IO.File]::SetAttributes($data,[IO.FileAttributes]::ReadOnly)
    try{
        $denied=Get-MaintenanceApplicationUse $root @('held.bin')
        if($denied.clear -or $denied.resources[0].native_error -ne 5){throw 'Access denial was admitted'}
    }finally{[IO.File]::SetAttributes($data,[IO.FileAttributes]::Normal)}
    if([MaintenanceFontFixture]::AddFontResourceEx($font,16,[IntPtr]::Zero) -le 0){throw 'Font load failed'}
    $loaded=$true
    if([MaintenanceFontFixture]::AddFontResourceEx($peer,16,[IntPtr]::Zero) -le 0){throw 'Peer font load failed'}
    $peerLoaded=$true
    $during=Get-MaintenanceApplicationUse $root @('font.ttf')
    if($during.clear -or $during.resources.Count -ne 1 -or $during.resources[0].native_error -ne 32){throw 'Private font was not blocked by the read-only probe'}
    $cancelled=& $module {
        param($root)
        function Show-MaintenanceApplicationPrompt {param($Snapshot) return $false}
        try{Wait-MaintenanceApplicationRelease -Check {Get-MaintenanceApplicationUse $root @('font.ttf')} -Interactive -EvidenceRoot $root;return $false}
        catch [OperationCanceledException]{return $true}
    } $root
    if(-not $cancelled -or (Get-FileHash -LiteralPath $font).Hash -cne $hash){throw 'Cancel did not preserve the font'}
    $silentRejected=$false
    try{Wait-MaintenanceApplicationRelease -Check {Get-MaintenanceApplicationUse $root @('font.ttf')} -EvidenceRoot $root}catch{
        if($_.Exception.Message -notlike 'Maintenance resources are unavailable*'){throw};$silentRejected=$true
    }
    if(-not $silentRejected){throw 'Silent invocation admitted occupied resources'}
    & $module {
        param($root,$font)
        $script:promptCount=0
        function Show-MaintenanceApplicationPrompt {
            param($Snapshot)
            $script:promptCount++
            if($script:promptCount -eq 2){
                if(-not [MaintenanceFontFixture]::RemoveFontResourceEx($font,16,[IntPtr]::Zero)){throw 'Fixture release failed'}
            }
            if($script:promptCount -gt 2){throw 'Loop did not observe release'}
            return $true
        }
        Wait-MaintenanceApplicationRelease -Check {Get-MaintenanceApplicationUse $root @('font.ttf')} -Interactive -EvidenceRoot $root
        if($script:promptCount -ne 2){throw 'Persistent occupation did not require another user decision'}
    } $root $font
    $loaded=$false
    $after=Get-MaintenanceApplicationUse $root @('font.ttf')
    if(-not $after.clear){throw 'Released font not admitted'}
    if((Get-MaintenanceApplicationUse $root @('peer.ttf')).clear -or (Get-FileHash -LiteralPath $peer).Hash -cne $hash){throw 'Peer font was released or changed'}
    $package=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru
    $outcomes=@(& $package {
        param($root,$font)
        Initialize-CandidateNative
        $r=$script:CandidateNative::Inspect($font)
        Remove-CandidateExactFiles $root @([pscustomobject]@{path='font.ttf';bytes=$r.Bytes;sha256=$r.Sha256;file_id=$r.FileId})
    } $root $font)
    if($outcomes.Count -ne 1 -or -not $outcomes[0].Removed){throw 'Actual exact removal did not succeed after release'}
    $rejected=$false
    try{Get-MaintenanceApplicationUse $root @('..\foreign.ttf')|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Escaped member admitted'}
    $checkFailed=$false
    try{Wait-MaintenanceApplicationRelease -Check {throw 'Changed identity fixture'} -Interactive -EvidenceRoot $root}catch{
        if($_.Exception.Message -cne 'Changed identity fixture'){throw};$checkFailed=$true
    }
    if(-not $checkFailed){throw 'Admission error was hidden by prompt'}
    if($UiSmoke){
        # Exercise the real dialog and its Cancel button, with no human input.
        & $module {
            Add-Type -AssemblyName System.Windows.Forms
            $timer=New-Object Windows.Forms.Timer;$timer.Interval=250
            $timer.Add_Tick({
                foreach($form in @([Windows.Forms.Application]::OpenForms)){
                    if($form.CancelButton){$form.CancelButton.PerformClick()}
                }
            })
            try{
                $timer.Start()
                if(Show-MaintenanceApplicationPrompt ([pscustomobject]@{applications=@();resources=@()})){throw 'Real Cancel returned retry'}
            }finally{$timer.Stop();$timer.Dispose()}
        }
    }
    [IO.File]::WriteAllText((Join-Path $root 'result.json'),([ordered]@{passed=$true;private_font_blocked=$true;cancel_preserved=$true;silent_rejected=$true;retry_observed_release=$true;exact_removal=$true;peer_font_preserved=$true;ui_smoke=[bool]$UiSmoke;during=$during;after=$after}|ConvertTo-Json -Depth 8))
    Write-Output ('PASS: application release, cancel, silent mode, exact deletion and independent peer font; evidence '+$root)
}finally{
    if($loaded){$null=[MaintenanceFontFixture]::RemoveFontResourceEx($font,16,[IntPtr]::Zero)}
    if($peerLoaded){$null=[MaintenanceFontFixture]::RemoveFontResourceEx($peer,16,[IntPtr]::Zero)}
}
