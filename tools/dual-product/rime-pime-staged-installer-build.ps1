# Definitions-only helpers for holding build inputs and publishing a disabled
# Rime/PIME candidate as a fail-closed installer/receipt/sidecar bundle.

function Get-RimePimeLeaseStreamDigest {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    $Stream.Position=0
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$digest=([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$Stream.Position=0}
    return $digest
}

function Open-RimePimeBuildInputLeases {
    param([Parameter(Mandatory)][Collections.Generic.Dictionary[string,string]]$Expected)
    $leases=[Collections.Generic.List[object]]::new()
    $keys=[string[]]@($Expected.Keys);[Array]::Sort($keys,[StringComparer]::OrdinalIgnoreCase)
    try{
        foreach($path in $keys){
            $before=Get-YimePimePayloadFileRecord $path
            if([string]$before.sha256 -cne [string]$Expected[$path]){throw "Build input differs before lease: $path"}
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try{
                $handleDigest=Get-RimePimeLeaseStreamDigest $stream
                $after=Get-YimePimePayloadFileRecord $path
                if($handleDigest -cne [string]$Expected[$path] -or [string]$before.file_id -cne [string]$after.file_id -or
                    [string]$before.sha256 -cne [string]$after.sha256){throw "Build input identity changed while acquiring lease: $path"}
                $leases.Add([pscustomobject]@{Path=$path;Stream=$stream;Sha256=$handleDigest;FileId=[string]$after.file_id})
                $stream=$null
            }finally{if($null -ne $stream){$stream.Dispose()}}
        }
    }catch{
        for($i=$leases.Count-1;$i -ge 0;$i--){try{$leases[$i].Stream.Dispose()}catch{}}
        throw
    }
    return $leases
}

function Test-RimePimeBuildInputLeases {
    param([Parameter(Mandatory)][object[]]$Leases)
    foreach($lease in $Leases){
        $handleDigest=Get-RimePimeLeaseStreamDigest $lease.Stream
        $pathRecord=Get-YimePimePayloadFileRecord $lease.Path
        if($handleDigest -cne [string]$lease.Sha256 -or [string]$pathRecord.sha256 -cne [string]$lease.Sha256 -or
            [string]$pathRecord.file_id -cne [string]$lease.FileId){throw "Leased build input changed: $($lease.Path)"}
    }
}

function Open-RimePimePublicationLock {
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ReceiptPath
    )
    $installer=[IO.Path]::GetFullPath($InstallerPath)
    $receipt=[IO.Path]::GetFullPath($ReceiptPath)
    $directory=Split-Path -Parent $installer
    if((Split-Path -Parent $receipt) -ine $directory -or
        [IO.Path]::GetFileName($receipt) -cne 'package-build-receipt.json' -or
        [IO.Path]::GetFileName($installer) -cnotmatch '^YIME-[A-Za-z0-9.+_-]+-setup\.exe$'){
        throw 'Publication lock accepts only the canonical installer/receipt directory and names.'
    }
    $null=Assert-RimePimeNoReparsePath $directory
    $lockPath=Join-Path $directory '.rime-pime-publication.lock'
    $before=$null
    $existed=Test-Path -LiteralPath $lockPath -PathType Leaf
    if($existed){$before=Get-YimePimePayloadFileRecord $lockPath}
    $stream=$null
    try{
        $mode=if($existed){[IO.FileMode]::Open}else{[IO.FileMode]::CreateNew}
        $stream=[IO.File]::Open($lockPath,$mode,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if($null -ne $before -and
            ([long]$stream.Length -ne [long]$before.bytes -or
             (Get-RimePimeLeaseStreamDigest $stream) -cne [string]$before.sha256)){
            throw 'Publication lock content changed while acquiring it.'
        }
        return [pscustomobject]@{Path=$lockPath;Stream=$stream;Existed=[bool]$existed}
    }catch{
        if($null -ne $stream){$stream.Dispose()}
        throw
    }
}

function Assert-RimePimeV1PublicationTargetState {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ReceiptPath
    )
    $installer=[IO.Path]::GetFullPath($InstallerPath)
    $receipt=[IO.Path]::GetFullPath($ReceiptPath)
    $members=@($installer,$receipt,($receipt+'.sha256'))
    $occupied=@($members|Where-Object{Test-Path -LiteralPath $_})
    if($occupied.Count -eq 0){return [pscustomobject]@{State='absent';Receipt=$null}}
    if($occupied.Count -ne $members.Count -or
        @($members|Where-Object{-not(Test-Path -LiteralPath $_ -PathType Leaf)}).Count -ne 0){
        throw 'Canonical installer/receipt/sidecar publication target is partial or not made of files.'
    }
    $envelope=Read-RimePimePackageBuildReceiptEnvelope -RepoRoot $Package.RepoRoot -ReceiptPath $receipt
    if([string]$envelope.SchemaVersion -cne 'yime-rime-pime-package-build-receipt-v1'){
        throw "Legacy v1 publication cannot replace canonical receipt schema $($envelope.SchemaVersion)."
    }
    $existing=Read-RimePimePackageBuildReceipt -Package $Package -ReceiptPath $receipt
    if($existing.InstallerPath -ine $installer){
        throw 'Existing v1 receipt does not own the canonical installer publication target.'
    }
    return [pscustomobject]@{State='validated-v1';Receipt=$existing}
}

function New-RimePimePreparedPublication {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][IO.FileStream]$CandidateStream,
        [Parameter(Mandatory)][string]$CandidateDigest,
        [Parameter(Mandatory)][string]$InstallerSourcePath,
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$PublicationRoot
    )
    if(Test-Path -LiteralPath $PublicationRoot){throw 'Publication preparation root already exists.'}
    New-Item -ItemType Directory -Path $PublicationRoot|Out-Null
    $pendingInstaller=Join-Path $PublicationRoot ([IO.Path]::GetFileName($InstallerPath))
    $CandidateStream.Position=0
    $destination=[IO.File]::Open($pendingInstaller,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$CandidateStream.CopyTo($destination);$destination.Flush()}
    finally{$destination.Dispose();$CandidateStream.Position=0}
    $pendingInstallerRecord=Get-YimePimePayloadFileRecord $pendingInstaller
    if([string]$pendingInstallerRecord.sha256 -cne $CandidateDigest){throw 'Prepared publication installer differs from the leased candidate.'}

    $installerFull=[IO.Path]::GetFullPath($InstallerPath)
    $sourceFull=[IO.Path]::GetFullPath($InstallerSourcePath)
    $installerRelative=$installerFull.Substring($Package.RepoRoot.Length+1).Replace('\','/')
    $sourceRelative=$sourceFull.Substring($Package.RepoRoot.Length+1).Replace('\','/')
    $planRelative=$Package.Path.Substring($Package.RepoRoot.Length+1).Replace('\','/')
    $value=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'
        architectures=@($Package.Plan.architectures);package_plan_path=$planRelative
        package_plan_sha256=$Package.Digest;nsis_profile='x86-x64-v1';installer_source_path=$sourceRelative
        installer_source_sha256=(Get-FileHash -LiteralPath $sourceFull -Algorithm SHA256).Hash.ToLowerInvariant()
        installer_path=$installerRelative;installer_size=[long]$pendingInstallerRecord.bytes
        installer_sha256=$CandidateDigest;sealed_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $pendingReceipt=Join-Path $PublicationRoot ([IO.Path]::GetFileName($ReceiptPath))
    Write-RimePimeSealedJson $value $pendingReceipt|Out-Null
    $sealed=Read-RimePimeSealedJson $pendingReceipt 'prepared package build receipt'
    return [pscustomobject]@{
        InstallerPath=$pendingInstaller;InstallerDigest=$CandidateDigest;ReceiptPath=$pendingReceipt
        ReceiptDigest=[string]$sealed.Digest;ReceiptSidecar=$pendingReceipt+'.sha256'
        ReceiptSidecarDigest=(Get-FileHash -LiteralPath ($pendingReceipt+'.sha256') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Invoke-RimePimePublicationCommit {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$Prepared,
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$RecoveryRoot
    )
    $publicationLock=Open-RimePimePublicationLock -InstallerPath $InstallerPath -ReceiptPath $ReceiptPath
    try{
    $null=Assert-RimePimeV1PublicationTargetState -Package $Package -InstallerPath $InstallerPath -ReceiptPath $ReceiptPath
    if(Test-Path -LiteralPath $RecoveryRoot){throw 'Publication recovery root already exists.'}
    $previous=Join-Path $RecoveryRoot 'previous';$failed=Join-Path $RecoveryRoot 'failed-new'
    New-Item -ItemType Directory -Path $previous,$failed|Out-Null
    $items=@(
        [pscustomobject]@{Source=$Prepared.InstallerPath;Target=$InstallerPath;Digest=$Prepared.InstallerDigest;Name='installer'},
        [pscustomobject]@{Source=$Prepared.ReceiptPath;Target=$ReceiptPath;Digest=$Prepared.ReceiptDigest;Name='receipt'},
        [pscustomobject]@{Source=$Prepared.ReceiptSidecar;Target=$ReceiptPath+'.sha256';Digest=$Prepared.ReceiptSidecarDigest;Name='receipt-sidecar-commit-marker'}
    )
    $publicationLeases=[Collections.Generic.List[object]]::new()
    try{
        foreach($item in $items){
            $record=Get-YimePimePayloadFileRecord ([string]$item.Source)
            $share=[IO.FileShare]::Read -bor [IO.FileShare]::Delete
            $stream=[IO.File]::Open([string]$item.Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
            try{
                $handleDigest=Get-RimePimeLeaseStreamDigest $stream
                $after=Get-YimePimePayloadFileRecord ([string]$item.Source)
                if($handleDigest -cne [string]$item.Digest -or [string]$record.file_id -cne [string]$after.file_id -or
                    [string]$after.sha256 -cne [string]$item.Digest){throw "Prepared publication input changed while leasing: $($item.Name)"}
                $publicationLeases.Add([pscustomobject]@{Stream=$stream;FileId=[string]$after.file_id;Digest=$handleDigest;Item=$item})
                $stream=$null
            }finally{if($null -ne $stream){$stream.Dispose()}}
        }
    }catch{
        for($i=$publicationLeases.Count-1;$i -ge 0;$i--){try{$publicationLeases[$i].Stream.Dispose()}catch{}}
        throw
    }
    $committed=[Collections.Generic.List[object]]::new()
    try{
        try{
        for($itemIndex=0;$itemIndex -lt $items.Count;$itemIndex++){
            $item=$items[$itemIndex];$publicationLease=$publicationLeases[$itemIndex]
            if((Get-RimePimeLeaseStreamDigest $publicationLease.Stream) -cne [string]$item.Digest){
                throw "Prepared publication input changed: $($item.Name)"
            }
            $target=[IO.Path]::GetFullPath([string]$item.Target)
            $backup=Join-Path $previous ([IO.Path]::GetFileName($target))
            $hadPrevious=Test-Path -LiteralPath $target -PathType Leaf
            $state=[pscustomobject]@{
                Target=$target;Backup=$backup;HadPrevious=$hadPrevious;OldMoved=$false;NewMoved=$false
                Name=[string]$item.Name;Digest=[string]$item.Digest
            }
            $committed.Add($state)
            if($hadPrevious){
                $null=Get-YimePimePayloadFileRecord $target
                [IO.File]::Move($target,$backup);$state.OldMoved=$true
            }
            [IO.File]::Move([string]$item.Source,$target);$state.NewMoved=$true
            $targetRecord=Get-YimePimePayloadFileRecord $target
            if([string]$targetRecord.file_id -cne [string]$publicationLease.FileId -or
                [string]$targetRecord.sha256 -cne [string]$item.Digest -or
                (Get-RimePimeLeaseStreamDigest $publicationLease.Stream) -cne [string]$item.Digest){
                throw "Published file identity changed: $($item.Name)"
            }
        }
        $receipt=Read-RimePimePackageBuildReceipt -Package $Package -ReceiptPath $ReceiptPath
        if([string]$receipt.Digest -cne [string]$Prepared.ReceiptDigest){throw 'Committed package receipt differs from its prepared identity.'}
        return $receipt
    }catch{
        $original=$_;$rollbackErrors=[Collections.Generic.List[string]]::new()
        for($i=$committed.Count-1;$i -ge 0;$i--){
            $state=$committed[$i]
            try{
                if($state.NewMoved -and (Test-Path -LiteralPath $state.Target -PathType Leaf)){
                    [IO.File]::Move($state.Target,(Join-Path $failed ([IO.Path]::GetFileName($state.Target))))
                }
                if($state.OldMoved -and (Test-Path -LiteralPath $state.Backup -PathType Leaf)){
                    [IO.File]::Move($state.Backup,$state.Target)
                }
            }catch{$rollbackErrors.Add("$($state.Name): $($_.Exception.Message)")}
        }
        if($rollbackErrors.Count -gt 0){
            throw "Publication failed and rollback was incomplete: $($rollbackErrors -join '; '). Original: $($original.Exception.Message)"
        }
        throw $original
        }
    }finally{
        for($i=$publicationLeases.Count-1;$i -ge 0;$i--){try{$publicationLeases[$i].Stream.Dispose()}catch{}}
    }
    }finally{
        $publicationLock.Stream.Dispose()
    }
}
