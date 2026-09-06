# Retained receipt evidence and receipt-only v2 supersession. No product execution.
# Objects are never garbage-collected here. WriteThrough + Flush(true) and
# same-volume write-through rename cover process interruption; hardware power
# loss and hostile same-SID path/member or ancestor replacement are not claimed.
function Get-RimePimeReceiptObjectPath($RepoRoot,[string]$Digest) {
    Assert-RimePimeReceiptV2Hash $Digest 'retained object'
    return Join-Path $RepoRoot ("installer\receipt-evidence\sha256\"+$Digest.Substring(0,2)+'\'+$Digest+'.blob')
}

function Resolve-RimePimeReceiptEvidence($Root,$Receipt,$Path,$Digest) {
    if ($Receipt.evidence_artifacts_durable -is [bool] -and $Receipt.evidence_artifacts_durable) {
        $full=Get-RimePimeReceiptObjectPath $Root $Digest
        $null=Get-YimePimePayloadFileRecord $full
        $marker=Open-RimePimeReceiptV2RawSidecarLease $full $Digest 'retained receipt evidence object'
        $marker.Stream.Dispose()
        return $full
    }
    return Resolve-RimePimePackageFile $Root $Path
}

function Move-RimePimeReceiptDurableFile([string]$Source,[string]$Destination) {
    if (-not ('YimeReceiptStorage.Native' -as [type])) {
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
    if (-not [YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,9)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}

function Write-RimePimeReceiptAtomicBytes([string]$Path,[byte[]]$Bytes) {
    Assert-RimePimeNoReparsePath $Path
    if (Test-Path -LiteralPath $Path) { $null=Get-YimePimePayloadFileRecord $Path }
    $parent=Split-Path -Parent $Path
    if (-not(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Assert-RimePimeNoReparsePath $parent
    # Do not append a GUID to the 64-character object digest: this can exceed
    # the PS5/.NET Framework path limit even when the destination is valid.
    $temp=Join-Path $parent ('.writing-'+[guid]::NewGuid().ToString('N'))
    $stream=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try { $stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    if ($Path.EndsWith('.blob')) { Invoke-RimePimeReceiptPublicationCheckpoint 'object-temp' }
    if ($Path.EndsWith('\pending.json')) { Invoke-RimePimeReceiptPublicationCheckpoint 'intent-temp' }
    Move-RimePimeReceiptDurableFile $temp $Path
}

function Save-RimePimeReceiptObject($RepoRoot,[byte[]]$Bytes) {
    $digest=Get-RimePimeReceiptV2Sha256Bytes $Bytes
    $path=Get-RimePimeReceiptObjectPath $RepoRoot $digest
    if (Test-Path -LiteralPath $path) {
        $record=Get-YimePimePayloadFileRecord $path
        if ($record.sha256 -cne $digest -or $record.bytes -ne $Bytes.Length) { throw 'Retained object corruption; refusing replacement.' }
    } else { Write-RimePimeReceiptAtomicBytes $path $Bytes }
    Invoke-RimePimeReceiptPublicationCheckpoint 'object-data'
    $marker=[Text.Encoding]::ASCII.GetBytes("$digest  $([IO.Path]::GetFileName($path))`n")
    if (Test-Path -LiteralPath ($path+'.sha256')) {
        $check=Open-RimePimeReceiptV2RawSidecarLease $path $digest 'retained object'
        $check.Stream.Dispose()
    } else { Write-RimePimeReceiptAtomicBytes ($path+'.sha256') $marker }
    return $path
}

function Get-RimePimeReceiptEvidenceSet($Receipt) {
    $r=$Receipt
    $set=[Collections.Generic.List[object]]::new()
    foreach($pair in @(
        @($r.package_plan.path,$r.package_plan.sha256),
        @($r.sealed_stage.content_manifest_path,$r.sealed_stage.content_manifest_sha256),
        @($r.payload_include.path,$r.payload_include.sha256),
        @($r.payload_include.receipt_path,$r.payload_include.receipt_sha256),
        @($r.disabled_build.result_path,$r.disabled_build.result_sha256),
        @($r.static_postbuild.result_path,$r.static_postbuild.result_sha256),
        @($r.installer.source_path,$r.installer.source_sha256),
        @($r.installer.path,$r.installer.sha256),
        @($r.predecessor_v1.source_path_at_finalization,$r.predecessor_v1.sha256)
    )){$set.Add($pair)}
    if($null -ne $r.sealed_stage.PSObject.Properties['payload_spec_path']){
        $set.Add(@($r.sealed_stage.payload_spec_path,$r.sealed_stage.payload_spec_sha256))
    }
    if($null -ne $r.sealed_stage.PSObject.Properties['go_payload_inventory_path']){
        $set.Add(@($r.sealed_stage.go_payload_inventory_path,$r.sealed_stage.go_payload_inventory_sha256))
    }
    if($null -ne $r.disabled_build.PSObject.Properties['nsis_toolchain_lock_path']){
        $set.Add(@($r.disabled_build.nsis_toolchain_lock_path,$r.disabled_build.nsis_toolchain_lock_sha256))
    }
    return @($set)
}

# Called only under the canonical publication lock. Original receipts are kept
# byte-for-byte; the new v2 receipt changes only its explicit retention flag.
function Save-RimePimeReceiptEvidence($RepoRoot,$ReceiptPath,$HistoricalV1Path) {
    $read=Read-RimePimePackageBuildReceiptV2 $RepoRoot $ReceiptPath
    $r=$read.Receipt
    foreach ($pair in (Get-RimePimeReceiptEvidenceSet $r)) {
        $stored=Get-RimePimeReceiptObjectPath $RepoRoot $pair[1]
        if (Test-Path -LiteralPath $stored) { $source=$stored }
        elseif ($pair[1] -ceq $r.predecessor_v1.sha256 -and $HistoricalV1Path) { $source=$HistoricalV1Path }
        else { $source=Resolve-RimePimeReceiptEvidence $RepoRoot $r $pair[0] $pair[1] }
        $record=Get-YimePimePayloadFileRecord $source
        $lease=Open-RimePimeReceiptV2FileLease $source $pair[1] $record.bytes 'retained evidence source'
        try { $null=Save-RimePimeReceiptObject $RepoRoot (Read-RimePimeReceiptV2StreamBytes $lease.Stream 536870912 'retained evidence') }
        finally { $lease.Stream.Dispose() }
    }
    $lease=Open-RimePimeReceiptV2SealedJsonLease $ReceiptPath 'receipt to retain'
    try {
        if ($lease.Digest -cne $read.Digest) { throw 'Receipt changed while retaining evidence.' }
        $original=Save-RimePimeReceiptObject $RepoRoot $lease.JsonBytes
    }
    finally { $lease.SidecarStream.Dispose();$lease.JsonStream.Dispose() }
    $r.evidence_artifacts_durable=$true
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $r)+"`n")
    $path=Save-RimePimeReceiptObject $RepoRoot $bytes
    $retained=Read-RimePimePackageBuildReceiptV2 $RepoRoot $path
    return [pscustomobject]@{Original=$original;Retained=$retained}
}

# Private checkpoint overridden only by isolated tests (including process exit).
function Invoke-RimePimeReceiptPublicationCheckpoint([string]$Phase) {}

function Open-RimePimeReceiptPublicationIntentLease([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if (-not(Test-Path -LiteralPath $full -PathType Leaf)) { throw "Receipt publication intent is missing: $full" }
    Assert-RimePimeNoReparsePath $full
    $before=Get-YimePimePayloadFileRecord $full
    $share=[IO.FileShare]::Read -bor [IO.FileShare]::Delete
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
    try {
        Assert-RimePimeNoReparsePath $full
        $bytes=Read-RimePimeReceiptV2StreamBytes $stream 65536 'receipt publication intent'
        $digest=Get-RimePimeReceiptV2Sha256Bytes $bytes
        $current=Get-YimePimePayloadFileRecord $full
        if ([long]$bytes.Length -ne [long]$before.bytes -or $digest -cne [string]$before.sha256 -or
            [string]$current.sha256 -cne $digest -or [long]$current.bytes -ne [long]$bytes.Length -or
            [string]$current.file_id -cne [string]$before.file_id) {
            throw 'Receipt publication intent changed while acquiring its read lease.'
        }
        $utf8=[Text.UTF8Encoding]::new($false,$true)
        try {
            $text=$utf8.GetString($bytes)
            Assert-RimePimeReceiptJsonSyntax $text
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
                $value=$text|ConvertFrom-Json -DateKind String
            } else { $value=$text|ConvertFrom-Json }
        } catch { throw "Receipt publication intent is not strict UTF-8 JSON: $($_.Exception.Message)" }
        return [pscustomobject]@{
            Path=$full;Stream=$stream;Bytes=[long]$bytes.Length;Digest=$digest
            FileId=[string]$before.file_id;Value=$value
        }
    } catch { $stream.Dispose();throw }
}

function Open-RimePimeReceiptPublicationSidecarLease([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if (-not(Test-Path -LiteralPath $full -PathType Leaf)) { throw "Canonical receipt sidecar is missing: $full" }
    Assert-RimePimeNoReparsePath $full
    $before=Get-YimePimePayloadFileRecord $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $bytes=Read-RimePimeReceiptV2StreamBytes $stream 256 'canonical receipt sidecar'
        $digest=Get-RimePimeReceiptV2Sha256Bytes $bytes
        $current=Get-YimePimePayloadFileRecord $full
        if ([long]$bytes.Length -ne [long]$before.bytes -or $digest -cne [string]$before.sha256 -or
            [string]$current.sha256 -cne $digest -or [long]$current.bytes -ne [long]$bytes.Length -or
            [string]$current.file_id -cne [string]$before.file_id) {
            throw 'Canonical receipt sidecar changed while acquiring its read lease.'
        }
        foreach ($one in $bytes) { if ($one -gt 127) { throw 'Canonical receipt sidecar is not ASCII.' } }
        $text=[Text.Encoding]::ASCII.GetString($bytes)
        if ($text -cnotmatch '\A([0-9a-f]{64})  package-build-receipt\.json(?:\r\n|\n)?\z') { throw 'Canonical receipt sidecar is malformed.' }
        return [pscustomobject]@{
            Path=$full;Stream=$stream;Bytes=[long]$bytes.Length;Digest=$digest
            FileId=[string]$before.file_id;BoundDigest=[string]$Matches[1]
        }
    } catch { $stream.Dispose();throw }
}

function Complete-RimePimeReceiptPublication($RepoRoot,$Canonical,$Pending) {
    $intentLease=Open-RimePimeReceiptPublicationIntentLease $Pending
    try {
    $record=[pscustomobject]@{sha256=$intentLease.Digest;bytes=$intentLease.Bytes;file_id=$intentLease.FileId}
    $intent=$intentLease.Value
    Assert-RimePimeExactProperties $intent @('schema_version','previous','previous_retained','next','installer_path') 'receipt publication intent'
    foreach ($name in @('schema_version','previous','previous_retained','next','installer_path')) {
        if ($intent.$name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$intent.$name)) { throw 'Invalid receipt publication intent.' }
    }
    if ($intent.schema_version -cne 'yime-rime-pime-retained-publication-v1') { throw 'Invalid receipt publication intent.' }
    foreach ($digest in @($intent.previous,$intent.previous_retained,$intent.next)) { Assert-RimePimeReceiptV2Hash $digest 'publication intent' }
    $oldPath=Get-RimePimeReceiptObjectPath $RepoRoot $intent.previous
    $old=Open-RimePimeReceiptV2SealedJsonLease $oldPath 'retained previous receipt'
    try {
        if ($old.Digest -cne $intent.previous -or $old.Value.schema_version -cne $script:RimePimePackageReceiptV2Schema) { throw 'Previous publication is not v2.' }
    } finally { $old.SidecarStream.Dispose();$old.JsonStream.Dispose() }
    $previous=Read-RimePimePackageBuildReceiptV2 $RepoRoot (Get-RimePimeReceiptObjectPath $RepoRoot $intent.previous_retained)
    $next=Read-RimePimePackageBuildReceiptV2 $RepoRoot (Get-RimePimeReceiptObjectPath $RepoRoot $intent.next)
    if($intent.next -cne $intent.previous_retained -and
        [string]$next.Receipt.disabled_build.schema_version -cne $script:RimePimeCurrentBuildEvidenceSchema){
        throw 'Changed receipt recovery requires current membership-interval build evidence.'
    }
    $old.Value.evidence_artifacts_durable=$true
    $expectedRetained=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $old.Value)+"`n")
    if ((Get-RimePimeReceiptV2Sha256Bytes $expectedRetained) -cne $intent.previous_retained) { throw 'Retained previous receipt is not the exact retention conversion.' }
    if (-not $previous.Receipt.evidence_artifacts_durable -or -not $next.Receipt.evidence_artifacts_durable -or
        $next.Digest -cne $intent.next -or $previous.Digest -cne $intent.previous_retained -or
        $next.Receipt.installer.path -cne $intent.installer_path -or
        $previous.Receipt.installer.sha256 -cne $next.Receipt.installer.sha256 -or
        $previous.Receipt.installer.path -cne $next.Receipt.installer.path) { throw 'Receipt-only supersession cannot replace the installer identity.' }
    $installer=Resolve-RimePimePackageFile $RepoRoot $intent.installer_path
    $objectLeases=[Collections.Generic.List[object]]::new()
    try {
    # Deny write/delete to all retained bytes through the canonical switch.
    $digests=@($intent.previous,$intent.previous_retained,$intent.next)
    foreach ($receipt in @($previous.Receipt,$next.Receipt)) {
        foreach ($pair in (Get-RimePimeReceiptEvidenceSet $receipt)) { $digests+= $pair[1] }
    }
    foreach ($digest in ($digests|Select-Object -Unique)) {
        $path=Get-RimePimeReceiptObjectPath $RepoRoot $digest
        Assert-RimePimeNoReparsePath $path
        $object=Get-YimePimePayloadFileRecord $path
        $objectLeases.Add((Open-RimePimeReceiptV2FileLease $path $digest $object.bytes 'publication retained object'))
        $null=Get-YimePimePayloadFileRecord ($path+'.sha256')
        $objectLeases.Add((Open-RimePimeReceiptV2RawSidecarLease $path $digest 'publication retained object'))
    }
    $lease=Open-RimePimeReceiptV2FileLease $installer $next.Receipt.installer.sha256 $next.Receipt.installer.bytes 'publication installer'
    try {
        # Both leaves must be a known old/new pair. Never repair unrelated bytes.
        $current=Get-YimePimePayloadFileRecord $Canonical
        $currentLease=Open-RimePimeReceiptV2FileLease $Canonical $current.sha256 $current.bytes 'canonical receipt during recovery'
        $markerPath=$Canonical+'.sha256'
        $oldMarker="$($intent.previous)  package-build-receipt.json"
        $newMarker="$($intent.next)  package-build-receipt.json"
        $markerLease=$null
        try {
            $markerLease=Open-RimePimeReceiptPublicationSidecarLease $markerPath
            if ($currentLease.Digest -cne $intent.previous -and $currentLease.Digest -cne $intent.next) { throw 'Canonical receipt conflicts with pending publication.' }
            if ($markerLease.BoundDigest -cne $intent.previous -and $markerLease.BoundDigest -cne $intent.next) { throw 'Canonical sidecar conflicts with pending publication.' }
            if ($intent.previous -cne $intent.next -and $currentLease.Digest -ceq $intent.previous -and $markerLease.BoundDigest -ceq $intent.next) { throw 'Impossible publication ordering.' }
        } finally {
            if ($null -ne $markerLease) { $markerLease.Stream.Dispose() }
            $currentLease.Stream.Dispose()
        }
        $currentFinal=Get-YimePimePayloadFileRecord $Canonical
        $markerFinal=Get-YimePimePayloadFileRecord $markerPath
        if ($currentFinal.sha256 -cne $current.sha256 -or $currentFinal.bytes -ne $current.bytes -or $currentFinal.file_id -cne $current.file_id -or
            $markerFinal.sha256 -cne $markerLease.Digest -or $markerFinal.bytes -ne $markerLease.Bytes -or $markerFinal.file_id -cne $markerLease.FileId) {
            throw 'Canonical receipt pair changed before recovery commit.'
        }
        Write-RimePimeReceiptAtomicBytes $Canonical ([IO.File]::ReadAllBytes($next.Path))
        Invoke-RimePimeReceiptPublicationCheckpoint 'receipt'
        Write-RimePimeReceiptAtomicBytes $markerPath ([Text.Encoding]::ASCII.GetBytes($newMarker+"`n"))
        Invoke-RimePimeReceiptPublicationCheckpoint 'sidecar'
        $result=Read-RimePimePackageBuildReceiptV2 $RepoRoot $Canonical
        $completed=Join-Path (Split-Path -Parent $Pending) ('completed-'+$record.sha256+'.json')
        Assert-RimePimeNoReparsePath $completed
        if (Test-Path -LiteralPath $completed) {
            $existing=Get-YimePimePayloadFileRecord $completed
            if ($existing.sha256 -cne $record.sha256) { throw 'Completed publication record is corrupt; refusing replacement.' }
        }
        $pendingCurrent=Get-YimePimePayloadFileRecord $Pending
        if ($pendingCurrent.sha256 -cne $record.sha256 -or $pendingCurrent.bytes -ne $record.bytes -or
            $pendingCurrent.file_id -cne $record.file_id) { throw 'Receipt publication intent changed before completion.' }
        Move-RimePimeReceiptDurableFile $Pending $completed
        Invoke-RimePimeReceiptPublicationCheckpoint 'complete'
        return $result
    } finally { $lease.Stream.Dispose() }
    } finally { foreach ($objectLease in $objectLeases) { $objectLease.Stream.Dispose() } }
    } finally { $intentLease.Stream.Dispose() }
}

function Publish-RimePimePackageReceiptV2Supersession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$ExpectedPreviousDigest,
        [string]$HistoricalV1Path)
    $RepoRoot=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    Assert-RimePimeReceiptV2Hash $ExpectedPreviousDigest 'expected previous receipt'
    $canonical=Join-Path $RepoRoot 'installer\package-build-receipt.json'
    # Lock is directory-wide, shared with v1 and v1->v2 publication.
    $lock=Open-RimePimePublicationLock (Join-Path $RepoRoot 'installer\YIME-receipt-setup.exe') $canonical
    try {
        $pending=Join-Path $RepoRoot 'installer\receipt-evidence\pending.json'
        if (Test-Path -LiteralPath $pending) { throw 'Pending receipt publication requires explicit recovery.' }
        $current=Read-RimePimePackageBuildReceiptV2 $RepoRoot $canonical
        if ($current.Digest -cne $ExpectedPreviousDigest) { throw 'Stale expected previous receipt digest.' }
        $next=Read-RimePimePackageBuildReceiptV2 $RepoRoot $ReceiptPath
        if($next.Digest -cne $current.Digest -and
            [string]$next.Receipt.disabled_build.schema_version -cne $script:RimePimeCurrentBuildEvidenceSchema){
            throw 'Changed receipt publication requires current membership-interval build evidence.'
        }
        if ($next.Receipt.installer.sha256 -cne $current.Receipt.installer.sha256 -or $next.Receipt.installer.path -cne $current.Receipt.installer.path) {
            throw 'Receipt-only supersession cannot replace the installer identity.'
        }
        $old=Save-RimePimeReceiptEvidence $RepoRoot $canonical $HistoricalV1Path
        $new=Save-RimePimeReceiptEvidence $RepoRoot $ReceiptPath $HistoricalV1Path
        Invoke-RimePimeReceiptPublicationCheckpoint 'objects'
        $intent=[ordered]@{schema_version='yime-rime-pime-retained-publication-v1';previous=$current.Digest;
            previous_retained=$old.Retained.Digest;next=$new.Retained.Digest;installer_path=$next.Receipt.installer.path}
        Write-RimePimeReceiptAtomicBytes $pending ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $intent)+"`n"))
        Invoke-RimePimeReceiptPublicationCheckpoint 'intent'
        return Complete-RimePimeReceiptPublication $RepoRoot $canonical $pending
    } finally { $lock.Stream.Dispose() }
}

function Resume-RimePimePackageReceiptV2Publication {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)
    $RepoRoot=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $canonical=Join-Path $RepoRoot 'installer\package-build-receipt.json'
    $lock=Open-RimePimePublicationLock (Join-Path $RepoRoot 'installer\YIME-receipt-setup.exe') $canonical
    try {
        $pending=Join-Path $RepoRoot 'installer\receipt-evidence\pending.json'
        if (-not(Test-Path -LiteralPath $pending)) { return Read-RimePimePackageBuildReceiptV2 $RepoRoot $canonical }
        return Complete-RimePimeReceiptPublication $RepoRoot $canonical $pending
    } finally { $lock.Stream.Dispose() }
}
