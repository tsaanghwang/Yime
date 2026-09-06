[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$StageRoot,
    [Parameter(Mandatory)][string]$ContentManifestPath,
    [Parameter(Mandatory)][string]$ExpectedContentManifestDigest,
    [Parameter(Mandatory)][string]$PayloadNshReceiptPath,
    [Parameter(Mandatory)][string]$ExpectedPayloadNshReceiptDigest,
    [string]$InstallerPath,
    [string]$PackagePlanPath
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$StageRoot=[IO.Path]::GetFullPath($StageRoot)
$ContentManifestPath=[IO.Path]::GetFullPath($ContentManifestPath)
$PayloadNshReceiptPath=[IO.Path]::GetFullPath($PayloadNshReceiptPath)
if([string]::IsNullOrWhiteSpace($PackagePlanPath)){$PackagePlanPath=Join-Path $repo 'installer\package-plan.json'}
$PackagePlanPath=[IO.Path]::GetFullPath($PackagePlanPath)
$stagingModule=Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1'
$postbuildModule=Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.psm1'
$logicPaths=@(
    $PSCommandPath,$postbuildModule,(Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.ps1'),
    $stagingModule,(Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-package-plan.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-payload-closure.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1'),
    (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1'),
    (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.ps1'),
    (Join-Path $PSScriptRoot 'rime-pime-postbuild-toolchain-lock.json'),
    (Join-Path $PSScriptRoot 'rime-pime-postbuild-toolchain-lock.json.sha256'),
    (Join-Path $repo 'tools\verify-pe-architectures.ps1')
)
$logicLeases=[Collections.Generic.List[object]]::new()
$seenLogic=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$result=$null
try{
    if($null -ne ('YimePime.Payload.NativeInspection' -as [type]) -or
        $null -ne ('YimePime.Postbuild.DirectoryLeasesV1' -as [type])){
        throw 'Post-build runner requires a fresh process with no preloaded native inspection or directory lease type.'
    }
    # Open every definitions/control file before importing any module. These
    # handles deny writes/deletes while allowing the importer's read access.
    foreach($path in $logicPaths){
        $full=[IO.Path]::GetFullPath($path)
        if(-not $seenLogic.Add($full)){throw "Duplicate post-build execution-logic path: $full"}
        if(-not $full.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or
            -not(Test-Path -LiteralPath $full -PathType Leaf)){
            throw "Post-build execution logic is missing or outside the repository: $full"
        }
        for($cursor=$full;$cursor;$cursor=Split-Path -Parent $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
                throw "Post-build execution logic traverses a reparse point before import: $cursor"
            }
            if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
        }
        $item=Get-Item -LiteralPath $full -Force
        if([string]$item.LinkType -ceq 'HardLink'){
            throw "Hard-linked post-build execution logic rejected before import: $full"
        }
        $streams=@(Get-Item -LiteralPath $full -Stream * -Force)
        if($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA'){
            throw "Alternate data stream on post-build execution logic rejected before import: $full"
        }
        $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try{
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
            finally{$sha.Dispose()}
            $stream.Position=0
            $logicLeases.Add([pscustomobject][ordered]@{
                Path=$full;Stream=$stream;Context='post-build execution logic';PreImportBytes=[long]$stream.Length
                PreImportSha256=$digest;Record=$null
            })
        }catch{$stream.Dispose();throw}
    }
    Import-Module -Name $postbuildModule -Force
    Import-Module -Name $stagingModule -Force
    foreach($lease in @($logicLeases)){
        $streamRecord=Get-RimePimePostbuildLeaseStreamRecord $lease.Stream
        $pathRecord=Get-YimePimePayloadFileRecord $lease.Path
        if([long]$streamRecord.bytes -ne [long]$lease.PreImportBytes -or
            [string]$streamRecord.sha256 -cne [string]$lease.PreImportSha256 -or
            [long]$pathRecord.bytes -ne [long]$lease.PreImportBytes -or
            [string]$pathRecord.sha256 -cne [string]$lease.PreImportSha256){
            throw "Post-build execution logic changed while importing: $($lease.Path)"
        }
        $lease.Record=[pscustomobject][ordered]@{
            bytes=[long]$pathRecord.bytes;sha256=[string]$pathRecord.sha256;file_id=[string]$pathRecord.file_id
        }
    }
    $null=Test-RimePimePostbuildExecutionLogicLeases @($logicLeases)
    $package=Read-RimePimePackagePlan -RepoRoot $repo -PlanPath $PackagePlanPath -VerifyArtifacts
    $content=Read-RimePimeCopiedContentManifest $ContentManifestPath $ExpectedContentManifestDigest
    # This explicit real-Package check is intentionally in the runner and occurs
    # before Invoke-RimePimePostbuildExtraction can start its first 7-Zip process.
    $null=Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest
    if([string]::IsNullOrWhiteSpace($InstallerPath)){
        $version=[IO.File]::ReadAllText((Join-Path $repo 'version.txt')).Trim()
        $InstallerPath=Join-Path $repo ("installer\YIME-$version-setup.exe")
    }
    $InstallerPath=[IO.Path]::GetFullPath($InstallerPath)
    $result=Invoke-RimePimePostbuildExtraction -InstallerPath $InstallerPath -StageRoot $StageRoot `
        -ContentManifestPath $ContentManifestPath -ExpectedContentManifestDigest $ExpectedContentManifestDigest `
        -Package $package -PayloadNshReceiptPath $PayloadNshReceiptPath `
        -ExpectedPayloadNshReceiptDigest $ExpectedPayloadNshReceiptDigest `
        -ExecutionLogicLeases @($logicLeases) -OutputRoot $OutputRoot `
        -AllowedOutputParent (Join-Path $repo '.tmp\dual-product')
    foreach($lease in @($result.PassFileLeases)){$null=Assert-RimePimePostbuildReadLease $lease}
    foreach($lease in @($result.PassDirectoryLeases)){$null=Assert-RimePimePostbuildDirectoryLease $lease}
    Write-Host "PASS: locked NSIS archives passed exact listing, per-entry raw-stdout hashing, and stable leased snapshot comparison; installer and uninstaller were not executed, trust remains false, and final closure remains false. Evidence: $($result.ResultPath) ($($result.ResultDigest))"
}finally{
    if($null -ne $result){
        foreach($lease in @($result.PassFileLeases)){if($null -ne $lease){$lease.Stream.Dispose()}}
        foreach($lease in @($result.PassDirectoryLeases)){if($null -ne $lease){$lease.Native.Dispose()}}
    }
    foreach($lease in @($logicLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
}
