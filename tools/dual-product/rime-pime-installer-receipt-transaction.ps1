# Definitions-only, fixture-gated installer/receipt identity replacement for
# DP1-N.  This file starts no installer, uninstaller, build tool or product
# process.  It is intended to be dot-sourced after the receipt-v2 and retained
# store definitions in one dedicated module.

$script:RimePimeInstallerReceiptTransactionSchema='yime-rime-pime-installer-receipt-transaction-v1'
$script:RimePimeInstallerReceiptOperationSchema='yime-rime-pime-installer-receipt-operation-v1'
$script:RimePimeInstallerReceiptTransactionWorkspaceRoot=
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

function Assert-RimePimeInstallerReceiptTransactionFixtureRoot {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    if(-not(Test-Path -LiteralPath $root -PathType Container)){
        throw 'Installer/receipt transaction fixture repository is missing.'
    }
    $caseRoot=Split-Path -Parent $root
    $casesRoot=Split-Path -Parent $caseRoot
    $runRoot=Split-Path -Parent $casesRoot
    $allowedRoot=Join-Path $script:RimePimeInstallerReceiptTransactionWorkspaceRoot '.tmp\dual-product'
    if((Split-Path -Leaf $root) -cne 'repo' -or
        (Split-Path -Leaf $casesRoot) -cne 'cases' -or
        (Split-Path -Leaf $caseRoot) -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
        (Split-Path -Leaf $runRoot) -cnotmatch '^dp1-package-receipt-v2-test-dp1n-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        (Split-Path -Parent $runRoot) -ine $allowedRoot){
        throw 'Installer/receipt transactions are allowed only in fresh .tmp/dual-product/dp1-package-receipt-v2-test-dp1n-*/cases/*/repo fixtures.'
    }
    foreach($path in @($allowedRoot,$runRoot,$casesRoot,$caseRoot,$root)){
        Assert-RimePimeNoReparsePath $path
    }
    return $root
}

function Resolve-RimePimeInstallerReceiptTransactionFixtureInput {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Context
    )
    $caseRoot=Split-Path -Parent $RepoRoot
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($caseRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
        -not(Test-Path -LiteralPath $full -PathType Leaf)){
        throw "$Context must be an existing leaf inside the DP1-N fixture case."
    }
    Assert-RimePimeNoReparsePath $full
    $null=Get-YimePimePayloadFileRecord $full
    return $full
}

function Get-RimePimeInstallerReceiptTransactionIdentity {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Receipt,
        [Parameter(Mandatory)][string]$Context
    )
    if($Receipt.product_version -isnot [string] -or
        [string]$Receipt.product_version -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$' -or
        $Receipt.installer.path -isnot [string]){
        throw "$Context has an invalid versioned installer identity."
    }
    $expected='installer/YIME-'+[string]$Receipt.product_version+'-setup.exe'
    if([string]$Receipt.installer.path -cne $expected){
        throw "$Context installer must be the versioned direct installer/YIME-*-setup.exe leaf."
    }
    Assert-RimePimeReceiptV2Hash $Receipt.installer.sha256 "$Context installer"
    if(-not(Test-RimePimeStageInteger $Receipt.installer.bytes) -or
        [long]$Receipt.installer.bytes -lt 1){
        throw "$Context installer byte count is invalid."
    }
    $full=Resolve-RimePimePackageFile $RepoRoot $expected
    if((Split-Path -Parent $full) -ine (Join-Path $RepoRoot 'installer')){
        throw "$Context installer is not a direct installer directory leaf."
    }
    return [pscustomobject]@{
        RelativePath=$expected
        Path=$full
        Sha256=[string]$Receipt.installer.sha256
        Bytes=[long]$Receipt.installer.bytes
    }
}

function Get-RimePimeInstallerReceiptTransactionOperationId {
    param(
        [Parameter(Mandatory)][string]$OldReceiptOriginalSha256,
        [Parameter(Mandatory)][string]$OldReceiptRetainedSha256,
        [Parameter(Mandatory)][string]$NewReceiptSha256,
        [Parameter(Mandatory)][string]$OldInstallerPath,
        [Parameter(Mandatory)][string]$OldInstallerSha256,
        [Parameter(Mandatory)][long]$OldInstallerBytes,
        [Parameter(Mandatory)][string]$NewInstallerPath,
        [Parameter(Mandatory)][string]$NewInstallerSha256,
        [Parameter(Mandatory)][long]$NewInstallerBytes
    )
    $identity=[ordered]@{
        schema_version=$script:RimePimeInstallerReceiptOperationSchema
        old_receipt_original_sha256=$OldReceiptOriginalSha256
        old_receipt_retained_sha256=$OldReceiptRetainedSha256
        new_receipt_sha256=$NewReceiptSha256
        old_installer_path=$OldInstallerPath
        old_installer_sha256=$OldInstallerSha256
        old_installer_bytes=$OldInstallerBytes
        new_installer_path=$NewInstallerPath
        new_installer_sha256=$NewInstallerSha256
        new_installer_bytes=$NewInstallerBytes
    }
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $identity)+"`n")
    return Get-RimePimeReceiptV2Sha256Bytes $bytes
}

function New-RimePimeInstallerReceiptTransactionIntent {
    param(
        [Parameter(Mandatory)][string]$OldReceiptOriginalSha256,
        [Parameter(Mandatory)][string]$OldReceiptRetainedSha256,
        [Parameter(Mandatory)][string]$NewReceiptSha256,
        [Parameter(Mandatory)]$OldInstaller,
        [Parameter(Mandatory)]$NewInstaller
    )
    $operationId=Get-RimePimeInstallerReceiptTransactionOperationId `
        $OldReceiptOriginalSha256 $OldReceiptRetainedSha256 $NewReceiptSha256 `
        $OldInstaller.RelativePath $OldInstaller.Sha256 $OldInstaller.Bytes `
        $NewInstaller.RelativePath $NewInstaller.Sha256 $NewInstaller.Bytes
    return [pscustomobject][ordered]@{
        schema_version=$script:RimePimeInstallerReceiptTransactionSchema
        operation_id=$operationId
        old_receipt_original_sha256=$OldReceiptOriginalSha256
        old_receipt_retained_sha256=$OldReceiptRetainedSha256
        new_receipt_sha256=$NewReceiptSha256
        old_installer_path=[string]$OldInstaller.RelativePath
        old_installer_sha256=[string]$OldInstaller.Sha256
        old_installer_bytes=[long]$OldInstaller.Bytes
        new_installer_path=[string]$NewInstaller.RelativePath
        new_installer_sha256=[string]$NewInstaller.Sha256
        new_installer_bytes=[long]$NewInstaller.Bytes
    }
}

function Assert-RimePimeInstallerReceiptTransactionIntent {
    param([Parameter(Mandatory)]$Intent)
    $properties=@(
        'schema_version','operation_id','old_receipt_original_sha256','old_receipt_retained_sha256',
        'new_receipt_sha256','old_installer_path','old_installer_sha256','old_installer_bytes',
        'new_installer_path','new_installer_sha256','new_installer_bytes'
    )
    Assert-RimePimeExactProperties $Intent $properties 'installer/receipt transaction intent'
    foreach($name in @('schema_version','operation_id','old_receipt_original_sha256',
        'old_receipt_retained_sha256','new_receipt_sha256','old_installer_path',
        'old_installer_sha256','new_installer_path','new_installer_sha256')){
        if($Intent.$name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Intent.$name)){
            throw 'Installer/receipt transaction intent contains a non-string identity field.'
        }
    }
    if([string]$Intent.schema_version -cne $script:RimePimeInstallerReceiptTransactionSchema){
        throw 'Installer/receipt transaction intent schema is invalid.'
    }
    foreach($name in @('operation_id','old_receipt_original_sha256','old_receipt_retained_sha256',
        'new_receipt_sha256','old_installer_sha256','new_installer_sha256')){
        Assert-RimePimeReceiptV2Hash $Intent.$name "installer/receipt transaction $name"
    }
    foreach($name in @('old_installer_bytes','new_installer_bytes')){
        if(-not(Test-RimePimeStageInteger $Intent.$name) -or [long]$Intent.$name -lt 1){
            throw 'Installer/receipt transaction intent contains an invalid byte count.'
        }
    }
    $expected=Get-RimePimeInstallerReceiptTransactionOperationId `
        $Intent.old_receipt_original_sha256 $Intent.old_receipt_retained_sha256 $Intent.new_receipt_sha256 `
        $Intent.old_installer_path $Intent.old_installer_sha256 ([long]$Intent.old_installer_bytes) `
        $Intent.new_installer_path $Intent.new_installer_sha256 ([long]$Intent.new_installer_bytes)
    if([string]$Intent.operation_id -cne $expected){
        throw 'Installer/receipt transaction operation id does not bind the exact intent.'
    }
    return $Intent
}

# Private checkpoint overridden only by DP1-N fixture tests, including tests
# that terminate their worker process at a durable transition boundary.
function Invoke-RimePimeInstallerReceiptTransactionCheckpoint([string]$Phase) {}

function Initialize-RimePimeInstallerReceiptTransactionNativeMove {
    if(-not('YimeReceiptStorage.Native' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YimeReceiptStorage {
 public static class Native {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool MoveFileEx(string source, string destination, uint flags);
 }
}
'@
    }
}

function Move-RimePimeInstallerReceiptNoReplace {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    Initialize-RimePimeInstallerReceiptTransactionNativeMove
    # MOVEFILE_WRITE_THROUGH only.  Deliberately omit REPLACE_EXISTING.
    if(-not[YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,8)){
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}

function Get-RimePimeInstallerReceiptStagePath {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$OperationId
    )
    Assert-RimePimeReceiptV2Hash $OperationId 'installer/receipt transaction operation id'
    $parent=Split-Path -Parent $TargetPath
    $stage=Join-Path $parent ('.rime-pime-installer-'+$OperationId+'.staged')
    if((Split-Path -Parent $stage) -ine $parent -or
        (Split-Path -Qualifier $stage) -ine (Split-Path -Qualifier $TargetPath)){
        throw 'New installer staging leaf is not on the target volume.'
    }
    if($stage.Length -ge 260){
        throw 'New installer staging path exceeds the Windows PowerShell 5.1 path budget.'
    }
    return $stage
}

function Get-RimePimeInstallerReceiptCompletedPath {
    param(
        [Parameter(Mandatory)][string]$Pending,
        [Parameter(Mandatory)][string]$OperationId
    )
    Assert-RimePimeReceiptV2Hash $OperationId 'installer/receipt transaction operation id'
    $completed=Join-Path (Split-Path -Parent $Pending) ('completed-'+$OperationId+'.json')
    if($completed.Length -ge 260){
        throw 'Completed transaction path exceeds the Windows PowerShell 5.1 path budget.'
    }
    return $completed
}

function Assert-RimePimeInstallerReceiptCompletionTargetAbsent {
    param(
        [Parameter(Mandatory)][string]$Pending,
        [Parameter(Mandatory)][string]$OperationId
    )
    $completed=Get-RimePimeInstallerReceiptCompletedPath $Pending $OperationId
    Assert-RimePimeNoReparsePath $completed
    if(Test-Path -LiteralPath $completed){
        throw 'Completed installer/receipt transaction leaf already exists while pending intent is active.'
    }
    return $completed
}

function Open-RimePimeInstallerReceiptPhysicalLeaf {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$Bytes,
        [Parameter(Mandatory)][string]$Context
    )
    Assert-RimePimeNoReparsePath $Path
    $record=Get-YimePimePayloadFileRecord $Path
    if([string]$record.sha256 -cne $Sha256 -or [long]$record.bytes -ne $Bytes){
        throw "$Context differs from its transaction identity."
    }
    $lease=Open-RimePimeReceiptV2FileLease $Path $Sha256 $Bytes $Context
    return [pscustomobject]@{Lease=$lease;Record=$record}
}

function Test-RimePimeInstallerReceiptPhysicalLeafExact {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$Bytes,
        [Parameter(Mandatory)][string]$Context
    )
    if(-not(Test-Path -LiteralPath $Path)) { return $false }
    $opened=Open-RimePimeInstallerReceiptPhysicalLeaf $Path $Sha256 $Bytes $Context
    $opened.Lease.Stream.Dispose()
    return $true
}

function Write-RimePimeInstallerReceiptIntentNoReplace {
    param(
        [Parameter(Mandatory)][string]$Pending,
        [Parameter(Mandatory)]$Intent
    )
    if(Test-Path -LiteralPath $Pending){
        throw 'Pending installer/receipt transaction requires explicit recovery.'
    }
    $null=Assert-RimePimeInstallerReceiptTransactionIntent $Intent
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $Intent)+"`n")
    $digest=Get-RimePimeReceiptV2Sha256Bytes $bytes
    $parent=Split-Path -Parent $Pending
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){
        throw 'Retained receipt evidence directory is missing before transaction intent.'
    }
    Assert-RimePimeNoReparsePath $parent
    # A unique attempt leaf keeps an arbitrary process exit during Write/Flush
    # from poisoning the deterministic pending path. Completed unique orphans
    # are inert and are never adopted by a later attempt.
    $temp=Join-Path $parent ('.rime-pime-intent-'+[guid]::NewGuid().ToString('N')+'.tmp')
    if($temp.Length -ge 260){
        throw 'Transaction intent staging path exceeds the Windows PowerShell 5.1 path budget.'
    }
    $stream=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try{
        $prefix=[Math]::Min(128,$bytes.Length)
        $stream.Write($bytes,0,$prefix)
        $stream.Flush($true)
        Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-copy'
        if($prefix -lt $bytes.Length){$stream.Write($bytes,$prefix,$bytes.Length-$prefix)}
        $stream.Flush($true)
    }finally{$stream.Dispose()}
    $check=Get-YimePimePayloadFileRecord $temp
    if([string]$check.sha256 -cne $digest -or [long]$check.bytes -ne [long]$bytes.Length){
        throw 'Transaction intent staging leaf differs from the exact intent.'
    }
    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-temp'
    Move-RimePimeInstallerReceiptNoReplace $temp $Pending
    $pendingRecord=Get-YimePimePayloadFileRecord $Pending
    if([string]$pendingRecord.sha256 -cne $digest -or [long]$pendingRecord.bytes -ne [long]$bytes.Length){
        throw 'Durable transaction intent differs after publication.'
    }
    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent'
}

function Stage-RimePimeInstallerReceiptPhysicalLeaf {
    param(
        [Parameter(Mandatory)][IO.FileStream]$SourceStream,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$Bytes,
        [Parameter(Mandatory)][string]$OperationId
    )
    if(Test-Path -LiteralPath $TargetPath){
        throw 'New physical installer must remain absent while its durable stage is prepared.'
    }
    Assert-RimePimeNoReparsePath $TargetPath
    $parent=Split-Path -Parent $TargetPath
    $stage=Get-RimePimeInstallerReceiptStagePath $TargetPath $OperationId
    if(Test-Path -LiteralPath $stage){
        $stageLease=Open-RimePimeInstallerReceiptPhysicalLeaf $stage $Sha256 $Bytes 'staged new installer'
        $stageLease.Lease.Stream.Dispose()
    }else{
        Assert-RimePimeNoReparsePath $stage
        # Copy into a unique attempt leaf. A process exit during this copy may
        # leave an inert orphan, but can never leave a partial deterministic
        # stage that would make a durable intent unrecoverable.
        $copy=Join-Path $parent ('.rime-pime-copy-'+[guid]::NewGuid().ToString('N')+'.tmp')
        if($copy.Length -ge 260){
            throw 'New installer copy path exceeds the Windows PowerShell 5.1 path budget.'
        }
        $position=$SourceStream.Position
        $destination=$null
        try{
            $SourceStream.Position=0
            $destination=[IO.FileStream]::new($copy,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
                [IO.FileShare]::None,16384,[IO.FileOptions]::WriteThrough)
            $buffer=New-Object byte[] 16384
            $first=$true
            while(($read=$SourceStream.Read($buffer,0,$buffer.Length)) -gt 0){
                $destination.Write($buffer,0,$read)
                if($first){
                    $destination.Flush($true)
                    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-copy'
                    $first=$false
                }
            }
            $destination.Flush($true)
        }finally{
            if($null -ne $destination){$destination.Dispose()}
            $SourceStream.Position=$position
        }
        $copyLease=Open-RimePimeInstallerReceiptPhysicalLeaf $copy $Sha256 $Bytes 'copied new installer'
        $copyLease.Lease.Stream.Dispose()
        Move-RimePimeInstallerReceiptNoReplace $copy $stage
        $stageLease=Open-RimePimeInstallerReceiptPhysicalLeaf $stage $Sha256 $Bytes 'staged new installer'
        $stageLease.Lease.Stream.Dispose()
    }
    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-temp'
    return $stage
}

function Publish-RimePimeInstallerReceiptPhysicalLeaf {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$Bytes,
        [Parameter(Mandatory)][string]$OperationId
    )
    $stage=Get-RimePimeInstallerReceiptStagePath $TargetPath $OperationId
    if(Test-Path -LiteralPath $TargetPath){
        $null=Test-RimePimeInstallerReceiptPhysicalLeafExact $TargetPath $Sha256 $Bytes 'new physical installer'
        if(Test-Path -LiteralPath $stage){
            throw 'Exact new installer and deterministic stage coexist; provenance is ambiguous.'
        }
        return
    }
    Assert-RimePimeNoReparsePath $TargetPath
    $stageLease=Open-RimePimeInstallerReceiptPhysicalLeaf $stage $Sha256 $Bytes 'staged new installer'
    $stageLease.Lease.Stream.Dispose()
    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-before-move'
    try{
        Move-RimePimeInstallerReceiptNoReplace $stage $TargetPath
    }catch{
        $moveFailure=$_
        if(Test-Path -LiteralPath $TargetPath){
            $null=Test-RimePimeInstallerReceiptPhysicalLeafExact $TargetPath $Sha256 $Bytes 'new physical installer'
        }
        throw $moveFailure
    }
    $targetLease=Open-RimePimeInstallerReceiptPhysicalLeaf $TargetPath $Sha256 $Bytes 'new physical installer'
    try{
        if([string]$targetLease.Lease.Path -ine [IO.Path]::GetFullPath($TargetPath)){
            throw 'New physical installer resolved to an unexpected leaf.'
        }
    }finally{$targetLease.Lease.Stream.Dispose()}
    if(Test-Path -LiteralPath $stage){
        throw 'Deterministic installer stage remained after no-replace publication.'
    }
    Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer'
}

function Get-RimePimeInstallerReceiptCanonicalState {
    param(
        [Parameter(Mandatory)][string]$Canonical,
        [Parameter(Mandatory)][string]$OldDigest,
        [Parameter(Mandatory)][string]$NewDigest
    )
    $record=Get-YimePimePayloadFileRecord $Canonical
    $receipt=Open-RimePimeReceiptV2FileLease $Canonical $record.sha256 $record.bytes 'transaction canonical receipt'
    $sidecar=$null
    try{
        $sidecar=Open-RimePimeReceiptPublicationSidecarLease ($Canonical+'.sha256')
        $receiptDigest=[string]$receipt.Digest
        $markerDigest=[string]$sidecar.BoundDigest
        $state=if($receiptDigest -ceq $OldDigest -and $markerDigest -ceq $OldDigest){'old'}
            elseif($receiptDigest -ceq $NewDigest -and $markerDigest -ceq $OldDigest){'receipt'}
            elseif($receiptDigest -ceq $NewDigest -and $markerDigest -ceq $NewDigest){'new'}
            else{$null}
        if($null -eq $state){
            throw 'Canonical receipt pair is outside the allowed old/new transaction states.'
        }
        return [pscustomobject]@{
            State=$state
            ReceiptDigest=$receiptDigest
            ReceiptRecord=$record
            SidecarDigest=[string]$sidecar.Digest
            SidecarBoundDigest=$markerDigest
            SidecarBytes=[long]$sidecar.Bytes
            SidecarFileId=[string]$sidecar.FileId
        }
    }finally{
        if($null -ne $sidecar){$sidecar.Stream.Dispose()}
        $receipt.Stream.Dispose()
    }
}

function Open-RimePimeInstallerReceiptTransactionObjectLeases {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Intent,
        [Parameter(Mandatory)]$Previous,
        [Parameter(Mandatory)]$Next
    )
    $digests=@($Intent.old_receipt_original_sha256,$Intent.old_receipt_retained_sha256,$Intent.new_receipt_sha256)
    foreach($receipt in @($Previous.Receipt,$Next.Receipt)){
        foreach($pair in (Get-RimePimeReceiptEvidenceSet $receipt)){$digests+=[string]$pair[1]}
    }
    $leases=[Collections.Generic.List[object]]::new()
    try{
        foreach($digest in @($digests|Sort-Object -Unique)){
            Assert-RimePimeReceiptV2Hash $digest 'transaction retained object'
            $path=Get-RimePimeReceiptObjectPath $RepoRoot $digest
            $record=Get-YimePimePayloadFileRecord $path
            $leases.Add((Open-RimePimeReceiptV2FileLease $path $digest $record.bytes 'transaction retained object'))
            $leases.Add((Open-RimePimeReceiptV2RawSidecarLease $path $digest 'transaction retained object'))
        }
        return $leases
    }catch{
        foreach($lease in $leases){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
        throw
    }
}

function Read-RimePimeInstallerReceiptTransactionBindings {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Intent
    )
    $oldOriginalPath=Get-RimePimeReceiptObjectPath $RepoRoot $Intent.old_receipt_original_sha256
    $oldOriginal=Open-RimePimeReceiptV2SealedJsonLease $oldOriginalPath 'transaction old original receipt'
    $newSealed=$null
    try{
        if($oldOriginal.Digest -cne $Intent.old_receipt_original_sha256 -or
            [string]$oldOriginal.Value.schema_version -cne $script:RimePimePackageReceiptV2Schema){
            throw 'Transaction old original receipt identity is invalid.'
        }
        $oldOriginal.Value.evidence_artifacts_durable=$true
        $retainedBytes=[Text.UTF8Encoding]::new($false).GetBytes(
            (ConvertTo-RimePimeStageCanonicalJson $oldOriginal.Value)+"`n")
        if((Get-RimePimeReceiptV2Sha256Bytes $retainedBytes) -cne $Intent.old_receipt_retained_sha256){
            throw 'Transaction old retained receipt is not the exact retention conversion.'
        }
        $previous=Read-RimePimePackageBuildReceiptV2 $RepoRoot `
            (Get-RimePimeReceiptObjectPath $RepoRoot $Intent.old_receipt_retained_sha256)
        $newPath=Get-RimePimeReceiptObjectPath $RepoRoot $Intent.new_receipt_sha256
        $newSealed=Open-RimePimeReceiptV2SealedJsonLease $newPath 'transaction new receipt'
        $next=Read-RimePimePackageBuildReceiptV2 $RepoRoot $newPath
        if($previous.Digest -cne $Intent.old_receipt_retained_sha256 -or
            -not(Test-RimePimeReceiptV2Boolean $previous.Receipt.evidence_artifacts_durable $true) -or
            $newSealed.Digest -cne $Intent.new_receipt_sha256 -or
            $next.Digest -cne $Intent.new_receipt_sha256 -or
            -not(Test-RimePimeReceiptV2Boolean $next.Receipt.evidence_artifacts_durable $true) -or
            [string]$next.Receipt.disabled_build.schema_version -cne $script:RimePimeCurrentBuildEvidenceSchema){
            throw 'Transaction successor must be a durable strict current membership-interval receipt.'
        }
        $oldInstaller=Get-RimePimeInstallerReceiptTransactionIdentity $RepoRoot $previous.Receipt 'old retained receipt'
        $newInstaller=Get-RimePimeInstallerReceiptTransactionIdentity $RepoRoot $next.Receipt 'new receipt'
        if($oldInstaller.Path -ieq $newInstaller.Path -or
            $oldInstaller.Sha256 -ceq $newInstaller.Sha256){
            throw 'Installer identity replacement requires distinct old/new versioned paths and SHA-256 identities.'
        }
        foreach($pair in @(
            @($Intent.old_installer_path,$oldInstaller.RelativePath),
            @($Intent.old_installer_sha256,$oldInstaller.Sha256),
            @([string]$Intent.old_installer_bytes,[string]$oldInstaller.Bytes),
            @($Intent.new_installer_path,$newInstaller.RelativePath),
            @($Intent.new_installer_sha256,$newInstaller.Sha256),
            @([string]$Intent.new_installer_bytes,[string]$newInstaller.Bytes))){
            if([string]$pair[0] -cne [string]$pair[1]){
                throw 'Transaction intent contradicts its strict receipt installer identities.'
            }
        }
        return [pscustomobject]@{
            Previous=$previous;Next=$next;OldInstaller=$oldInstaller;NewInstaller=$newInstaller
            NewReceiptBytes=[byte[]]$newSealed.JsonBytes
        }
    }finally{
        if($null -ne $newSealed){$newSealed.SidecarStream.Dispose();$newSealed.JsonStream.Dispose()}
        $oldOriginal.SidecarStream.Dispose();$oldOriginal.JsonStream.Dispose()
    }
}

function Complete-RimePimeInstallerReceiptTransaction {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Canonical,
        [Parameter(Mandatory)][string]$Pending
    )
    $root=Assert-RimePimeInstallerReceiptTransactionFixtureRoot $RepoRoot
    if($Canonical -ine (Join-Path $root 'installer\package-build-receipt.json') -or
        $Pending -ine (Join-Path $root 'installer\receipt-evidence\pending.json')){
        throw 'Installer/receipt transaction paths are not canonical fixture paths.'
    }
    $intentLease=Open-RimePimeReceiptPublicationIntentLease $Pending
    try{
        $intent=Assert-RimePimeInstallerReceiptTransactionIntent $intentLease.Value
        $completed=Assert-RimePimeInstallerReceiptCompletionTargetAbsent $Pending $intent.operation_id
        $bindings=Read-RimePimeInstallerReceiptTransactionBindings $root $intent
        $objectLeases=@()
        $oldPhysical=$null
        $newObject=$null
        $newPhysical=$null
        try{
            $objectLeases=@(Open-RimePimeInstallerReceiptTransactionObjectLeases $root $intent $bindings.Previous $bindings.Next)
            $oldPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.OldInstaller.Path `
                $bindings.OldInstaller.Sha256 $bindings.OldInstaller.Bytes 'old physical installer'
            $newObjectPath=Get-RimePimeReceiptObjectPath $root $intent.new_installer_sha256
            $newObject=Open-RimePimeInstallerReceiptPhysicalLeaf $newObjectPath `
                $bindings.NewInstaller.Sha256 $bindings.NewInstaller.Bytes 'retained new installer object'

            $state=Get-RimePimeInstallerReceiptCanonicalState $Canonical `
                $intent.old_receipt_original_sha256 $intent.new_receipt_sha256
            $newExists=Test-Path -LiteralPath $bindings.NewInstaller.Path
            if($newExists){
                $null=Test-RimePimeInstallerReceiptPhysicalLeafExact $bindings.NewInstaller.Path `
                    $bindings.NewInstaller.Sha256 $bindings.NewInstaller.Bytes 'new physical installer'
                $stage=Get-RimePimeInstallerReceiptStagePath $bindings.NewInstaller.Path $intent.operation_id
                if(Test-Path -LiteralPath $stage){
                    throw 'Exact new installer and deterministic stage coexist; provenance is ambiguous.'
                }
            }
            if(-not $newExists -and $state.State -cne 'old'){
                throw 'Canonical receipt advanced without the exact physical new installer; recovery refuses to reconstruct that invalid state.'
            }
            if(-not $newExists){
                Publish-RimePimeInstallerReceiptPhysicalLeaf $bindings.NewInstaller.Path `
                    $bindings.NewInstaller.Sha256 $bindings.NewInstaller.Bytes $intent.operation_id
            }
            $newPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.NewInstaller.Path `
                $bindings.NewInstaller.Sha256 $bindings.NewInstaller.Bytes 'new physical installer'

            $state=Get-RimePimeInstallerReceiptCanonicalState $Canonical `
                $intent.old_receipt_original_sha256 $intent.new_receipt_sha256
            if($state.State -ceq 'old'){
                Write-RimePimeReceiptAtomicBytes $Canonical $bindings.NewReceiptBytes
                Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'receipt'
            }
            $state=Get-RimePimeInstallerReceiptCanonicalState $Canonical `
                $intent.old_receipt_original_sha256 $intent.new_receipt_sha256
            if($state.State -ceq 'receipt'){
                $marker=[Text.Encoding]::ASCII.GetBytes(
                    $intent.new_receipt_sha256+'  package-build-receipt.json'+"`n")
                Write-RimePimeReceiptAtomicBytes ($Canonical+'.sha256') $marker
                Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'sidecar'
            }
            $state=Get-RimePimeInstallerReceiptCanonicalState $Canonical `
                $intent.old_receipt_original_sha256 $intent.new_receipt_sha256
            if($state.State -cne 'new'){
                throw 'Installer/receipt transaction did not reach its canonical new state.'
            }
            $result=Read-RimePimePackageBuildReceiptV2 $root $Canonical
            if($result.Digest -cne $intent.new_receipt_sha256){
                throw 'Committed canonical receipt differs from the transaction successor.'
            }
            foreach($identity in @(
                @($bindings.OldInstaller.Path,$bindings.OldInstaller.Sha256,$bindings.OldInstaller.Bytes,'old physical installer'),
                @($bindings.NewInstaller.Path,$bindings.NewInstaller.Sha256,$bindings.NewInstaller.Bytes,'new physical installer'))){
                $terminal=Open-RimePimeInstallerReceiptPhysicalLeaf $identity[0] $identity[1] ([long]$identity[2]) $identity[3]
                $terminal.Lease.Stream.Dispose()
            }
            $oldFinal=Get-YimePimePayloadFileRecord $bindings.OldInstaller.Path
            if([string]$oldFinal.file_id -cne [string]$oldPhysical.Record.file_id -or
                [string]$oldFinal.sha256 -cne [string]$bindings.OldInstaller.Sha256 -or
                [long]$oldFinal.bytes -ne [long]$bindings.OldInstaller.Bytes){
                throw 'Old physical installer changed; it must be preserved byte-for-byte.'
            }
            $newFinal=Get-YimePimePayloadFileRecord $bindings.NewInstaller.Path
            if([string]$newFinal.file_id -cne [string]$newPhysical.Record.file_id -or
                [string]$newFinal.sha256 -cne [string]$bindings.NewInstaller.Sha256 -or
                [long]$newFinal.bytes -ne [long]$bindings.NewInstaller.Bytes){
                throw 'New physical installer changed before receipt transaction completion.'
            }

            $pendingRecord=Get-YimePimePayloadFileRecord $Pending
            if([string]$pendingRecord.sha256 -cne [string]$intentLease.Digest -or
                [long]$pendingRecord.bytes -ne [long]$intentLease.Bytes -or
                [string]$pendingRecord.file_id -cne [string]$intentLease.FileId){
                throw 'Installer/receipt transaction intent changed before completion.'
            }
            Move-RimePimeInstallerReceiptNoReplace $Pending $completed
            $completedRecord=Get-YimePimePayloadFileRecord $completed
            if([string]$completedRecord.sha256 -cne [string]$intentLease.Digest -or
                [long]$completedRecord.bytes -ne [long]$intentLease.Bytes -or
                [string]$completedRecord.file_id -cne [string]$intentLease.FileId){
                throw 'Completed installer/receipt transaction record changed during rename.'
            }
            $oldTerminal=Get-YimePimePayloadFileRecord $bindings.OldInstaller.Path
            if([string]$oldTerminal.file_id -cne [string]$oldPhysical.Record.file_id -or
                [string]$oldTerminal.sha256 -cne [string]$bindings.OldInstaller.Sha256){
                throw 'Old physical installer was not preserved through transaction completion.'
            }
            Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'complete'
            return $result
        }finally{
            if($null -ne $newPhysical){$newPhysical.Lease.Stream.Dispose()}
            if($null -ne $newObject){$newObject.Lease.Stream.Dispose()}
            if($null -ne $oldPhysical){$oldPhysical.Lease.Stream.Dispose()}
            foreach($lease in @($objectLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
        }
    }finally{$intentLease.Stream.Dispose()}
}

function Publish-RimePimeInstallerReceiptTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$NextReceiptDigest,
        [Parameter(Mandatory)][string]$ExpectedPreviousDigest,
        [string]$HistoricalV1Path
    )
    $root=Assert-RimePimeInstallerReceiptTransactionFixtureRoot $RepoRoot
    Assert-RimePimeReceiptV2Hash $NextReceiptDigest 'next receipt digest'
    Assert-RimePimeReceiptV2Hash $ExpectedPreviousDigest 'expected previous receipt digest'
    if($HistoricalV1Path){
        $HistoricalV1Path=Resolve-RimePimeInstallerReceiptTransactionFixtureInput `
            $root $HistoricalV1Path 'HistoricalV1Path'
    }
    $canonical=Join-Path $root 'installer\package-build-receipt.json'
    $pending=Join-Path $root 'installer\receipt-evidence\pending.json'
    $lock=Open-RimePimePublicationLock (Join-Path $root 'installer\YIME-transaction-setup.exe') $canonical
    $oldGuard=$null
    try{
        if(Test-Path -LiteralPath $pending){
            throw 'Pending installer/receipt transaction requires explicit recovery.'
        }
        $current=Read-RimePimePackageBuildReceiptV2 $root $canonical
        if($current.Digest -cne $ExpectedPreviousDigest){
            throw 'Stale expected previous receipt digest.'
        }
        $oldInstaller=Get-RimePimeInstallerReceiptTransactionIdentity $root $current.Receipt 'current receipt'
        $oldGuard=Open-RimePimeInstallerReceiptPhysicalLeaf $oldInstaller.Path `
            $oldInstaller.Sha256 $oldInstaller.Bytes 'old physical installer'
        $nextPath=Get-RimePimeReceiptObjectPath $root $NextReceiptDigest
        $next=Read-RimePimePackageBuildReceiptV2 $root $nextPath
        if($next.Digest -cne $NextReceiptDigest -or
            -not(Test-RimePimeReceiptV2Boolean $next.Receipt.evidence_artifacts_durable $true) -or
            [string]$next.Receipt.disabled_build.schema_version -cne $script:RimePimeCurrentBuildEvidenceSchema){
            throw 'Successor must be the requested durable strict current membership-interval receipt object.'
        }
        $newInstaller=Get-RimePimeInstallerReceiptTransactionIdentity $root $next.Receipt 'successor receipt'
        if($oldInstaller.Path -ieq $newInstaller.Path -or
            $oldInstaller.Sha256 -ceq $newInstaller.Sha256){
            throw 'Installer identity replacement requires distinct old/new versioned paths and SHA-256 identities.'
        }
        # A new transaction never adopts a pre-existing target, even if its
        # bytes happen to be exact.  Only pending-intent recovery may do so.
        if(Test-Path -LiteralPath $newInstaller.Path){
            throw 'Fresh installer/receipt transaction rejected because the new installer leaf already exists.'
        }
        $old=Save-RimePimeReceiptEvidence $root $canonical $HistoricalV1Path
        if($old.Original -ine (Get-RimePimeReceiptObjectPath $root $current.Digest) -or
            $old.Retained.Digest -ceq $NextReceiptDigest){
            throw 'Old receipt retention produced an invalid transaction identity.'
        }
        Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'objects'
        $currentAgain=Read-RimePimePackageBuildReceiptV2 $root $canonical
        if($currentAgain.Digest -cne $ExpectedPreviousDigest){
            throw 'Canonical receipt changed after expected-current CAS.'
        }
        $oldAgain=Open-RimePimeInstallerReceiptPhysicalLeaf $oldInstaller.Path `
            $oldInstaller.Sha256 $oldInstaller.Bytes 'old physical installer'
        $oldAgain.Lease.Stream.Dispose()
        if(Test-Path -LiteralPath $newInstaller.Path){
            throw 'New installer leaf already exists before durable transaction intent.'
        }
        $intent=New-RimePimeInstallerReceiptTransactionIntent $current.Digest `
            $old.Retained.Digest $next.Digest $oldInstaller $newInstaller
        $null=Assert-RimePimeInstallerReceiptCompletionTargetAbsent $pending $intent.operation_id
        $newObjectPath=Get-RimePimeReceiptObjectPath $root $newInstaller.Sha256
        $newObject=Open-RimePimeInstallerReceiptPhysicalLeaf $newObjectPath `
            $newInstaller.Sha256 $newInstaller.Bytes 'retained new installer object'
        try{
            $null=Stage-RimePimeInstallerReceiptPhysicalLeaf $newObject.Lease.Stream `
                $newInstaller.Path $newInstaller.Sha256 $newInstaller.Bytes $intent.operation_id
        }finally{$newObject.Lease.Stream.Dispose()}
        $currentBeforeIntent=Read-RimePimePackageBuildReceiptV2 $root $canonical
        if($currentBeforeIntent.Digest -cne $ExpectedPreviousDigest -or
            (Test-Path -LiteralPath $newInstaller.Path)){
            throw 'Canonical or new-installer state changed while preparing the durable installer stage.'
        }
        Write-RimePimeInstallerReceiptIntentNoReplace $pending $intent
        return Complete-RimePimeInstallerReceiptTransaction $root $canonical $pending
    }finally{
        if($null -ne $oldGuard){$oldGuard.Lease.Stream.Dispose()}
        $lock.Stream.Dispose()
    }
}

function Resume-RimePimeInstallerReceiptTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)
    $root=Assert-RimePimeInstallerReceiptTransactionFixtureRoot $RepoRoot
    $canonical=Join-Path $root 'installer\package-build-receipt.json'
    $pending=Join-Path $root 'installer\receipt-evidence\pending.json'
    $lock=Open-RimePimePublicationLock (Join-Path $root 'installer\YIME-transaction-setup.exe') $canonical
    try{
        if(-not(Test-Path -LiteralPath $pending)){
            $current=Read-RimePimePackageBuildReceiptV2 $root $canonical
            $installer=Get-RimePimeInstallerReceiptTransactionIdentity $root $current.Receipt 'canonical receipt'
            $physical=Open-RimePimeInstallerReceiptPhysicalLeaf $installer.Path `
                $installer.Sha256 $installer.Bytes 'canonical physical installer'
            $physical.Lease.Stream.Dispose()
            return $current
        }
        if(-not(Test-Path -LiteralPath $pending -PathType Leaf)){
            throw 'Pending installer/receipt transaction is not a file.'
        }
        return Complete-RimePimeInstallerReceiptTransaction $root $canonical $pending
    }finally{$lock.Stream.Dispose()}
}
