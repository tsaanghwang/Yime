[CmdletBinding()]
param([Parameter(Mandatory)][string]$CorePackage,[Parameter(Mandatory)][string]$EvidenceRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidence=Assert-PlainPath $EvidenceRoot
$allowed=Join-Path $repo '.tmp/yimecore-platform-experiments'
if(-not $evidence.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $evidence -PathType Container)){throw 'Use this build’s existing isolated evidence directory.'}
$report=Join-Path $evidence 'arm64-payload-maintenance.json'
if(Test-Path -LiteralPath $report){throw 'Preserve the earlier maintenance report.'}
$work=Join-Path $evidence ('maintenance-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$null=[IO.Directory]::CreateDirectory($work)
$checks=[Collections.Generic.List[string]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$script:checks.Add($Message)}
function Reject([scriptblock]$Code,[string]$Message){$rejected=$false;try{& $Code|Out-Null}catch{$rejected=$true};Require $rejected $Message}
function Child([string]$Name){
    $path=Assert-PlainPath (Join-Path $work $Name)
    if(-not $path.StartsWith($work+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture escaped this test workspace.'}
    return $path
}
$core=Read-Package $CorePackage
if($core.contract.target -cne 'windows-arm64'){throw 'This regression requires the actual ARM64 package.'}
$target=Child 'core';$peer=Child 'peer';$foreign=Child 'foreign';$partial=Child 'partial'
$passed=$false;$failure=$null
try {
    Copy-ProductPayload $core $target
    $null=[IO.Directory]::CreateDirectory($peer)
    [IO.File]::WriteAllText((Join-Path $peer '.yime-product.json'),' {"format":"yime-simple-install-1","product":"rime-pime","version":"synthetic"}')
    [IO.File]::WriteAllText((Join-Path $peer 'keep.txt'),'synthetic independent-product fixture; never an installed Rime product')
    $peerHash=Get-ContentHash (Join-Path $peer 'keep.txt')
    Reject {Remove-ProductDirectory $peer 'yimecore'} 'Other product ownership is preserved'
    $null=[IO.Directory]::CreateDirectory($foreign)
    [IO.File]::WriteAllText((Join-Path $foreign 'keep.txt'),'unowned fixture')
    Reject {Remove-ProductDirectory $foreign 'yimecore'} 'Unowned directory is preserved'
    $font=Join-Path $target 'data/fonts/YinYuan-Regular.ttf'
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Arm64PayloadFontFixture {
 [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string path,uint flags,IntPtr reserved);
 [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string path,uint flags,IntPtr reserved);
}
'@
    Require ([Arm64PayloadFontFixture]::AddFontResourceEx($font,16,[IntPtr]::Zero) -gt 0) 'Packaged private font loads in this test process'
    try {Reject {Wait-ProductFiles $target -Silent} 'Private-font occupancy stops replacement'}
    finally {$null=[Arm64PayloadFontFixture]::RemoveFontResourceEx($font,16,[IntPtr]::Zero)}
    Wait-ProductFiles $target -Silent
    [IO.File]::WriteAllText((Join-Path $target 'indexes/full.yidx'),'damaged fixture')
    [IO.File]::Delete((Join-Path $target 'bin/YimeBroker.exe'))
    Remove-ProductDirectory $target 'yimecore'
    Require (-not (Test-Path -LiteralPath $target)) 'Owned fixture uninstall removes its payload'
    Copy-ProductPayload $core $target
    foreach($row in $core.manifest.files){
        if((Get-ContentHash (Join-Path $target $row.path)) -cne $row.sha256){throw ('Reinstall mismatch: '+$row.path)}
    }
    $checks.Add('Reinstall restores every declared payload file and hash')
    Require ((Get-ContentHash (Join-Path $peer 'keep.txt')) -ceq $peerHash) 'Peer fixture bytes are unchanged'
    Require (Test-Path -LiteralPath (Join-Path $foreign 'keep.txt')) 'Unowned fixture bytes remain'
    $bad=[pscustomobject]@{root=$core.root;product=$core.product;contract=$core.contract;manifest=[pscustomobject]@{version='test';files=@([pscustomobject]@{path='missing-fixture'})}}
    Reject {Copy-ProductPayload $bad $partial} 'Interrupted copy fails'
    Require (Test-Path -LiteralPath (Join-Path $partial '.yime-product.json')) 'Interrupted copy retains ownership for repair'
    Remove-ProductDirectory $partial 'yimecore'
    Remove-ProductDirectory $target 'yimecore'
    Require (-not (Test-Path -LiteralPath $partial)) 'Interrupted fixture can be uninstalled'
    Require (-not (Test-Path -LiteralPath $target)) 'Reinstalled fixture can be uninstalled'
    $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally {
    [ordered]@{schema_version='yime-arm64-payload-maintenance-v1';passed=$passed;failure=$failure;package_manifest_sha256=(Get-ContentHash (Join-Path $core.root 'product-package.json'));fixture_root=$work;checks=@($checks);installed=$false;registration_executed=$false;peer_is_synthetic=$true;private_font_process_only=$true}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $report -Encoding UTF8
}
Write-Output ('PASS: '+$checks.Count+' actual ARM64 payload maintenance checks in owned fixtures; no installed products changed. '+$report)
