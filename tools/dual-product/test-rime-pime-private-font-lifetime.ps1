[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceFont)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source=[IO.Path]::GetFullPath($SourceFont)
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'd0d881aca381b7fd220ba34cc84c4ec8d2f3e6a2f72d64390507d6569bf00d0d'){throw 'Original font hash differs'}
$root=Join-Path $repo ('.tmp\dual-product\font-map-probe-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$path=Join-Path $root 'YinYuan-Regular.ttf'
[IO.File]::Copy($source,$path,$false)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PrivateFontProbe {
 [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string name,uint flags,IntPtr reserved);
 [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string name,uint flags,IntPtr reserved);
}
'@
$module=Import-Module (Join-Path $repo 'tools\dual-product\rime-pime-executable-candidate.psm1') -PassThru
$file=& $module {param($p)
 Initialize-CandidateNative
 $r=$script:CandidateNative::Inspect($p)
 [pscustomobject]@{path='YinYuan-Regular.ttf';bytes=$r.Bytes;sha256=$r.Sha256;file_id=$r.FileId}
} $path
$loaded=$false
try{
    $count=[PrivateFontProbe]::AddFontResourceEx($path,16,[IntPtr]::Zero)
    if($count -le 0){throw 'Private font load failed'}
    $loaded=$true
    $during=@(& $module {param($r,$f) Remove-CandidateExactFiles $r @($f)} $root $file)
    if(-not [PrivateFontProbe]::RemoveFontResourceEx($path,16,[IntPtr]::Zero)){throw 'Private font unload failed'}
    $loaded=$false
    $after=@(& $module {param($r,$f) Remove-CandidateExactFiles $r @($f)} $root $file)
    if($during.Count -ne 1 -or $during[0].Status -ne 'preserved-error' -or $during[0].ErrorCode -ne 5 -or $during[0].MarkedForDeletion -or $during[0].Removed){throw 'Expected private font mapping to prevent deletion with error 5'}
    if($after.Count -ne 1 -or $after[0].Status -ne 'removed' -or -not $after[0].Removed -or (Test-Path -LiteralPath $path)){throw 'Expected deletion after private font release'}
    $result=[ordered]@{private_font_count=$count;during_private_load=$during;after_private_unload=$after;system_font_installation_changed=$false;registered_product_changed=$false}
    $result|ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $root 'result.json'),($result|ConvertTo-Json -Depth 6))
    Write-Output "Evidence: $root"
}finally{if($loaded){$null=[PrivateFontProbe]::RemoveFontResourceEx($path,16,[IntPtr]::Zero)}}
