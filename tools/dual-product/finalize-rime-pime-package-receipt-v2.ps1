[CmdletBinding()]
param(
    [string]$RepoRoot,
    [Parameter(Mandatory)][string]$BuildReceiptV1Path,
    [Parameter(Mandatory)][string]$BuildResultPath,
    [Parameter(Mandatory)][string]$ContentManifestPath,
    [Parameter(Mandatory)][string]$PayloadNshPath,
    [Parameter(Mandatory)][string]$PayloadNshReceiptPath,
    [Parameter(Mandatory)][string]$PostbuildResultPath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [switch]$PublishCanonical
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
if(-not $PublishCanonical){throw 'Explicit -PublishCanonical is required; preparation alone is not recorded as canonical closure.'}
$module=Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.psm1'
$logicPaths=@(
    $PSCommandPath,$module,(Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.psm1'),
    (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1'),
    (Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-package-plan.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-payload-closure.ps1')
)
function Get-RimePimeReceiptV2RunnerDigest([IO.FileStream]$Stream){
    $Stream.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$Stream.Position=0}
}
$logicLeases=[Collections.Generic.List[object]]::new();$prepared=$null
try{
    foreach($path in $logicPaths){
        $full=[IO.Path]::GetFullPath($path)
        if(@($logicLeases|Where-Object{$_.Path -ieq $full}).Count){throw "Duplicate receipt-v2 execution logic: $full"}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "Receipt-v2 execution logic is missing: $full"}
        for($cursor=$full;$cursor;$cursor=Split-Path -Parent $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Receipt-v2 execution logic traverses a reparse point: $cursor"}
            if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
        }
        $item=Get-Item -LiteralPath $full -Force
        if([string]$item.LinkType -ceq 'HardLink'){throw "Hard-linked receipt-v2 execution logic rejected: $full"}
        $streams=@(Get-Item -LiteralPath $full -Stream * -Force)
        if($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA'){throw "Alternate data stream on receipt-v2 execution logic rejected: $full"}
        $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $logicLeases.Add([pscustomobject]@{Path=$full;Stream=$stream;Digest=(Get-RimePimeReceiptV2RunnerDigest $stream)})
    }
    Import-Module -Name $module -Force
    # The receipt module intentionally exports only its own receipt surface.
    # Re-import staging after it so the runner can independently re-read every
    # leased execution-logic file without relying on nested-module re-exports.
    Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force
    foreach($lease in $logicLeases){
        $record=Get-YimePimePayloadFileRecord $lease.Path
        if((Get-RimePimeReceiptV2RunnerDigest $lease.Stream) -cne [string]$lease.Digest -or [string]$record.sha256 -cne [string]$lease.Digest){
            throw "Receipt-v2 execution logic changed during import: $($lease.Path)"
        }
    }
    $prepared=New-RimePimePackageReceiptV2Preparation -RepoRoot $RepoRoot -BuildReceiptV1Path $BuildReceiptV1Path `
        -BuildResultPath $BuildResultPath -ContentManifestPath $ContentManifestPath -PayloadNshPath $PayloadNshPath `
        -PayloadNshReceiptPath $PayloadNshReceiptPath -PostbuildResultPath $PostbuildResultPath -OutputRoot $OutputRoot
    $published=Publish-RimePimePackageReceiptV2 -Prepared $prepared `
        -CanonicalReceiptPath (Join-Path ([IO.Path]::GetFullPath($RepoRoot)) 'installer\package-build-receipt.json')
    Write-Host "PASS: canonical receipt v2 binds one disabled candidate to sealed stage, include, build and static postbuild toolchain evidence. No installer, uninstaller or signing process ran. Receipt: $($published.Path) ($($published.Digest))"
}finally{
    Close-RimePimePackageReceiptV2Preparation $prepared
    foreach($lease in $logicLeases){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
}
