[CmdletBinding()]
param([Parameter(Mandatory)][string]$CorePackage,[Parameter(Mandatory)][string]$RimePackage)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$work=Join-Path $repo ('.tmp\simple-install-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Work){$rejected=$false;try{& $Work|Out-Null}catch{$rejected=$true};Require $rejected 'Expected rejection'}
$core=Read-Package $CorePackage;$rime=Read-Package $RimePackage
# Use actual packaged resources, without running any product or registration binary.
$target=Join-Path $work 'core';$peer=Join-Path $work 'rime'
Copy-ProductPayload $core $target;Copy-ProductPayload $rime $peer
$peerHash=Get-ContentHash (Join-Path $peer 'go-backend\server.exe')
Reject {Remove-ProductDirectory $peer 'yimecore'}
$foreign=Join-Path $work 'foreign';$null=[IO.Directory]::CreateDirectory($foreign)
[IO.File]::WriteAllText((Join-Path $foreign 'keep.txt'),'unrelated')
Reject {Remove-ProductDirectory $foreign 'yimecore'}
Require (Test-Path -LiteralPath (Join-Path $foreign 'keep.txt')) 'Unowned files removed'
$font=Join-Path $target 'data\fonts\YinYuan-Regular.ttf'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SimpleFontTest {
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string path,uint flags,IntPtr reserved);
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string path,uint flags,IntPtr reserved);
}
'@
Require ([SimpleFontTest]::AddFontResourceEx($font,16,[IntPtr]::Zero) -gt 0) 'Private font fixture load failed'
try{Reject {Wait-ProductFiles $target -Silent};Require (Test-Path -LiteralPath $font) 'Occupancy check removed font'}
finally{$null=[SimpleFontTest]::RemoveFontResourceEx($font,16,[IntPtr]::Zero)}
Wait-ProductFiles $target -Silent
# Damaged/missing installed data must not require restoring an old snapshot.
[IO.File]::WriteAllText((Join-Path $target 'indexes\full.yidx'),'broken test data')
[IO.File]::Delete((Join-Path $target 'bin\YimeBroker.exe'))
Remove-ProductDirectory $target 'yimecore'
Copy-ProductPayload $core $target
Require ((Get-ContentHash (Join-Path $target 'indexes\full.yidx')) -ceq (Get-ContentHash (Join-Path $CorePackage 'payload\indexes\full.yidx'))) 'Reinstall did not restore built-in data'
Require ((Get-ContentHash (Join-Path $peer 'go-backend\server.exe')) -ceq $peerHash) 'Peer changed during core reinstall'
Remove-ProductDirectory $target 'yimecore';Remove-ProductDirectory $peer 'rime-pime'
Require (-not (Test-Path -LiteralPath $target)) 'Core uninstall left payload'
Require (-not (Test-Path -LiteralPath $peer)) 'Rime uninstall left payload'
# A copy error leaves an ownership marker, so rerunning uninstall is possible.
$partial=Join-Path $work 'partial'
$bad=[pscustomobject]@{root=$CorePackage;product=$core.product;manifest=[pscustomobject]@{version='test';files=@([pscustomobject]@{path='missing-fixture'})}}
Reject {Copy-ProductPayload $bad $partial}
Assert-OwnedDirectory $partial 'yimecore';Remove-ProductDirectory $partial 'yimecore'
Write-Output ('PASS: both product payloads; unowned/peer rejection; actual private-font occupancy; damaged install replacement; interrupted copy cleanup. No registry or installed products changed. '+$work)
