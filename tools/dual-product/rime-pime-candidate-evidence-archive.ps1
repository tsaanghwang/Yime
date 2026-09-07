# Definitions-only DP1-Q protocol for exporting one sealed, versioned Rime/PIME
# candidate evidence set into one immutable, single-generation archive capsule.
#
# The public surface is deliberately fixture-gated.  Every path it can mutate
# is derived below a fresh repository-local
# .tmp/dual-product/dp1-candidate-evidence-archive-test-*/cases/* directory.
# The sibling "archive" directory models crossing the source outer-tmp
# boundary; it is not evidence that a real archive outside this repository was
# written.  No build, installer, uninstaller, registry, process, user-data, or
# actual canonical publication action exists in this file.

$script:RimePimeCandidateArchiveWorkspaceRoot =
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$script:RimePimeCandidateArchiveRootSchema = 'yime-rime-pime-candidate-evidence-archive-root-v1'
$script:RimePimeCandidateArchiveManifestSchema = 'yime-rime-pime-candidate-evidence-archive-manifest-v1'
$script:RimePimeCandidateArchiveHeadSchema = 'yime-rime-pime-candidate-evidence-archive-head-v1'
$script:RimePimeCandidateArchiveIntentSchema = 'yime-rime-pime-candidate-evidence-archive-intent-v1'
$script:RimePimeCandidateArchiveCompletionSchema = 'yime-rime-pime-candidate-evidence-archive-completion-v1'
$script:RimePimeCandidateArchiveRunnerSchema = 'yime-rime-pime-isolated-candidate-result-v1'
$script:RimePimeCandidateArchiveReceiptSchema = 'yime-rime-pime-package-build-receipt-v2'
$script:RimePimeCandidateArchiveBuildSchema = 'yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
$script:RimePimeCandidateArchiveLockBytes = [Text.Encoding]::ASCII.GetBytes("fixture-candidate-evidence-archive-lock-v1`n")

function Get-RimePimeCandidateArchiveSha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-RimePimeCandidateArchiveDigest($Value) {
    return $Value -is [string] -and [string]$Value -cmatch '^[0-9a-f]{64}$'
}

function Test-RimePimeCandidateArchiveInteger($Value) {
    return $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64]
}

function ConvertTo-RimePimeCandidateArchiveBytes($Value) {
    $text = (ConvertTo-RimePimeStageCanonicalJson $Value) + "`n"
    return ,[Text.UTF8Encoding]::new($false,$true).GetBytes($text)
}

function Test-RimePimeCandidateArchiveBytesEqual([byte[]]$Left,[byte[]]$Right) {
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i=0;$i -lt $Left.Length;$i++) { if ($Left[$i] -ne $Right[$i]) { return $false } }
    return $true
}

function ConvertFrom-RimePimeCandidateArchiveJsonBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][string]$Context,[switch]$RequireCanonical)
    if ($Bytes.Length -lt 3 -or $Bytes.Length -gt 16777216) { throw "$Context exceeds its JSON byte bound." }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    try { $text = $utf8.GetString($Bytes) } catch { throw "$Context is not strict UTF-8." }
    if (-not $text.EndsWith("`n",[StringComparison]::Ordinal) -or $text.Contains("`r")) {
        throw "$Context is not LF-terminated JSON."
    }
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
            $value = ConvertFrom-Json -InputObject $text -DateKind String
        } else { $value = ConvertFrom-Json -InputObject $text }
    } catch { throw "$Context is not JSON: $($_.Exception.Message)" }
    if ($RequireCanonical) {
        $canonical = ConvertTo-RimePimeCandidateArchiveBytes $value
        if (-not(Test-RimePimeCandidateArchiveBytesEqual $Bytes $canonical)) {
            throw "$Context is not in the canonical representation."
        }
    }
    return $value
}

function Assert-RimePimeCandidateArchiveFalseFlags {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Names,[Parameter(Mandatory)][string]$Context)
    foreach ($name in $Names) {
        $property = $Value.PSObject.Properties[$name]
        if ($null -eq $property -or $property.Value -isnot [bool] -or [bool]$property.Value) {
            throw "$Context must keep $name as Boolean false."
        }
    }
}

function Assert-RimePimeCandidateArchiveCaseRoot {
    param([Parameter(Mandatory)][string]$CaseRoot)
    $case = [IO.Path]::GetFullPath($CaseRoot).TrimEnd('\')
    if (-not(Test-Path -LiteralPath $case -PathType Container)) { throw 'Candidate archive fixture case is missing.' }
    $cases = Split-Path -Parent $case
    $run = Split-Path -Parent $cases
    $allowed = Join-Path $script:RimePimeCandidateArchiveWorkspaceRoot '.tmp\dual-product'
    if ((Split-Path -Leaf $cases) -cne 'cases' -or
        (Split-Path -Leaf $case) -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or
        (Split-Path -Leaf $run) -cnotmatch '^dp1-candidate-evidence-archive-test-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        (Split-Path -Parent $run) -ine $allowed) {
        throw 'Candidate evidence archives are allowed only in fresh .tmp/dual-product/dp1-candidate-evidence-archive-test-*/cases/* fixtures.'
    }
    foreach ($path in @($allowed,$run,$cases,$case)) { Assert-RimePimeNoReparsePath $path }
    return [pscustomobject][ordered]@{
        case_root = $case
        source_root = Join-Path $case 'outer-tmp'
        archive_root = Join-Path $case 'archive'
        lock_path = Join-Path $case '.rime-pime-candidate-evidence-archive.lock'
    }
}

function Assert-RimePimeCandidateArchiveDirectory {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context)
    if (-not(Test-Path -LiteralPath $Path -PathType Container)) { throw "$Context directory is missing." }
    Assert-RimePimeNoReparsePath $Path
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Context is a reparse directory." }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Read-RimePimeCandidateArchiveFileBytes {
    param([Parameter(Mandatory)][string]$Path,[long]$Maximum=536870912,[Parameter(Mandatory)][string]$Context)
    Assert-RimePimeNoReparsePath $Path
    $before = Get-YimePimePayloadFileRecord $Path
    if ([long]$before.bytes -lt 1 -or [long]$before.bytes -gt $Maximum) { throw "$Context exceeds its byte bound." }
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw "$Context ended before its leased byte count." }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw "$Context grew while read." }
        $digest = Get-RimePimeCandidateArchiveSha256Bytes $bytes
        $after = Get-YimePimePayloadFileRecord $Path
        if ([string]$before.file_id -cne [string]$after.file_id -or
            [long]$before.bytes -ne [long]$after.bytes -or
            [string]$before.sha256 -cne $digest -or [string]$after.sha256 -cne $digest) {
            throw "$Context identity changed while read."
        }
        return [pscustomobject]@{ Path=[IO.Path]::GetFullPath($Path);Bytes=[byte[]]$bytes;Sha256=$digest;Length=[long]$bytes.Length;FileId=[string]$after.file_id }
    } finally { $stream.Dispose() }
}

function Read-RimePimeCandidateArchiveSealedSource {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context)
    $data = Read-RimePimeCandidateArchiveFileBytes $Path 16777216 "$Context data"
    $sidecarPath = $data.Path + '.sha256'
    $marker = Read-RimePimeCandidateArchiveFileBytes $sidecarPath 256 "$Context sidecar"
    foreach ($one in $marker.Bytes) { if ($one -gt 127) { throw "$Context sidecar is not ASCII." } }
    $expected = $data.Sha256 + '  ' + [IO.Path]::GetFileName($data.Path) + "`n"
    if ([Text.Encoding]::ASCII.GetString($marker.Bytes) -cne $expected) { throw "$Context sidecar does not bind its exact data bytes." }
    return [pscustomobject]@{ Data=$data;Sidecar=$marker;Value=(ConvertFrom-RimePimeCandidateArchiveJsonBytes $data.Bytes $Context) }
}

function Assert-RimePimeCandidateArchiveRelativePathText {
    param([Parameter(Mandatory)]$RelativePath,[Parameter(Mandatory)][string]$Context)
    if ($RelativePath -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$RelativePath) -or
        [IO.Path]::IsPathRooted([string]$RelativePath) -or
        [string]$RelativePath -cne ([string]$RelativePath).Normalize([Text.NormalizationForm]::FormC) -or
        ([string]$RelativePath).Contains('\') -or ([string]$RelativePath).StartsWith('/') -or
        ([string]$RelativePath).EndsWith('/') -or ([string]$RelativePath).Contains('//') -or
        [string]$RelativePath -match '[\x00-\x1f<>:"|?*]') {
        throw "$Context is not a canonical relative Windows archive path: $RelativePath"
    }
    foreach ($segment in ([string]$RelativePath).Split('/')) {
        if (-not $segment -or $segment -in @('.','..') -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            throw "$Context is ambiguous: $RelativePath"
        }
        if ($segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') {
            throw "$Context contains a reserved Windows device segment: $RelativePath"
        }
    }
    return [string]$RelativePath
}

function Resolve-RimePimeCandidateArchiveSourcePath {
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$RelativePath)
    $RelativePath = Assert-RimePimeCandidateArchiveRelativePathText $RelativePath 'Candidate archive source path'
    $root = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $full = [IO.Path]::GetFullPath((Join-Path $root $RelativePath.Replace('/','\')))
    if (-not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Candidate archive source path escapes outer-tmp.' }
    Assert-RimePimeNoReparsePath $full
    return $full
}

# Private checkpoint. Fixture tests override it inside module scope, including
# with Environment.Exit to model independent-process hard interruption.
function Invoke-RimePimeCandidateEvidenceArchiveCheckpoint([string]$Phase) {}

function Initialize-RimePimeCandidateArchiveNativeMove {
    if ($null -ne ('YimeCandidateEvidenceArchive.Native' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YimeCandidateEvidenceArchive {
 public static class Native {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool MoveFileEx(string source, string destination, uint flags);
 }
}
'@
}

function Move-RimePimeCandidateArchiveNoReplace {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    Initialize-RimePimeCandidateArchiveNativeMove
    if ((Split-Path -Qualifier $Source) -ine (Split-Path -Qualifier $Destination)) {
        throw 'Candidate archive ownership move must remain on one volume.'
    }
    # MOVEFILE_WRITE_THROUGH only.  REPLACE_EXISTING is intentionally absent.
    $nativeSource = [IO.Path]::GetFullPath($Source)
    $nativeDestination = [IO.Path]::GetFullPath($Destination)
    if ($nativeSource.StartsWith('\\',[StringComparison]::Ordinal)) {
        $nativeSource = '\\?\UNC\'+$nativeSource.Substring(2)
    } else { $nativeSource = '\\?\'+$nativeSource }
    if ($nativeDestination.StartsWith('\\',[StringComparison]::Ordinal)) {
        $nativeDestination = '\\?\UNC\'+$nativeDestination.Substring(2)
    } else { $nativeDestination = '\\?\'+$nativeDestination }
    if (-not[YimeCandidateEvidenceArchive.Native]::MoveFileEx($nativeSource,$nativeDestination,8)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}

function Ensure-RimePimeCandidateArchiveDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $null = Assert-RimePimeCandidateArchiveDirectory $Path 'Candidate archive'
    } else {
        New-Item -ItemType Directory -Path $Path | Out-Null
        $null = Assert-RimePimeCandidateArchiveDirectory $Path 'Candidate archive'
    }
}

function Ensure-RimePimeCandidateArchiveFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Phase
    )
    $expected = Get-RimePimeCandidateArchiveSha256Bytes $Bytes
    if (Test-Path -LiteralPath $Path) {
        $existing = Read-RimePimeCandidateArchiveFileBytes $Path ([Math]::Max([long]$Bytes.Length,1048576)) "candidate archive $Phase"
        if ($existing.Sha256 -cne $expected -or $existing.Length -ne $Bytes.Length -or
            -not(Test-RimePimeCandidateArchiveBytesEqual $existing.Bytes $Bytes)) {
            throw "Candidate archive $Phase target is foreign; replacement is forbidden."
        }
        return $existing
    }
    Assert-RimePimeNoReparsePath $Path
    $parent = Split-Path -Parent $Path
    $null = Assert-RimePimeCandidateArchiveDirectory $parent "candidate archive $Phase parent"
    $temp = Join-Path $parent ('.writing-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $stream = [IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try {
        $first = [Math]::Min($Bytes.Length,128)
        $stream.Write($Bytes,0,$first)
        $stream.Flush($true)
        Invoke-RimePimeCandidateEvidenceArchiveCheckpoint ($Phase+'-copy')
        if ($first -lt $Bytes.Length) { $stream.Write($Bytes,$first,$Bytes.Length-$first) }
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    $staged = Read-RimePimeCandidateArchiveFileBytes $temp ([Math]::Max([long]$Bytes.Length,1048576)) "candidate archive staged $Phase"
    if ($staged.Sha256 -cne $expected -or $staged.Length -ne $Bytes.Length) { throw "Candidate archive staged $Phase differs." }
    try { Move-RimePimeCandidateArchiveNoReplace $temp $Path }
    catch {
        $moveError = $_
        if (Test-Path -LiteralPath $Path) {
            $raced = Read-RimePimeCandidateArchiveFileBytes $Path ([Math]::Max([long]$Bytes.Length,1048576)) "candidate archive raced $Phase"
            if ($raced.Sha256 -cne $expected -or $raced.Length -ne $Bytes.Length) { throw $moveError }
        }
        throw $moveError
    }
    Invoke-RimePimeCandidateEvidenceArchiveCheckpoint ($Phase+'-data')
    return Read-RimePimeCandidateArchiveFileBytes $Path ([Math]::Max([long]$Bytes.Length,1048576)) "candidate archive published $Phase"
}

function Ensure-RimePimeCandidateArchiveSealedBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Phase
    )
    $digest = Get-RimePimeCandidateArchiveSha256Bytes $Bytes
    $null = Ensure-RimePimeCandidateArchiveFile $Path $Bytes $Phase
    $markerBytes = [Text.Encoding]::ASCII.GetBytes($digest+'  '+[IO.Path]::GetFileName($Path)+"`n")
    $null = Ensure-RimePimeCandidateArchiveFile ($Path+'.sha256') $markerBytes ($Phase+'-sidecar')
    Invoke-RimePimeCandidateEvidenceArchiveCheckpoint ($Phase+'-sidecar')
    return [pscustomobject]@{ Path=$Path;Sha256=$digest;Bytes=[long]$Bytes.Length }
}

function Read-RimePimeCandidateArchiveSealedArchiveFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context,[long]$Maximum=16777216,[switch]$Json)
    $data = Read-RimePimeCandidateArchiveFileBytes $Path $Maximum "$Context data"
    $marker = Read-RimePimeCandidateArchiveFileBytes ($Path+'.sha256') 256 "$Context sidecar"
    foreach ($one in $marker.Bytes) { if ($one -gt 127) { throw "$Context sidecar is not ASCII." } }
    $expected = $data.Sha256+'  '+[IO.Path]::GetFileName($Path)+"`n"
    if ([Text.Encoding]::ASCII.GetString($marker.Bytes) -cne $expected) { throw "$Context sidecar is invalid." }
    $value = $null
    if ($Json) { $value = ConvertFrom-RimePimeCandidateArchiveJsonBytes $data.Bytes $Context -RequireCanonical }
    return [pscustomobject]@{ Data=$data;Sidecar=$marker;Value=$value }
}

function Open-RimePimeCandidateArchiveLock {
    param([Parameter(Mandatory)]$Context,[switch]$RequireExisting)
    $path = [string]$Context.lock_path
    if (-not(Test-Path -LiteralPath $path)) {
        if ($RequireExisting) { throw 'Candidate archive lock anchor is missing.' }
        $created = $null
        try {
            $created = [IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
            $created.Write($script:RimePimeCandidateArchiveLockBytes,0,$script:RimePimeCandidateArchiveLockBytes.Length)
            $created.Flush($true)
            Invoke-RimePimeCandidateEvidenceArchiveCheckpoint 'lock-created'
            return $created
        } catch {
            if ($null -ne $created) { $created.Dispose() }
            if (-not(Test-Path -LiteralPath $path)) { throw }
        }
    }
    $record = Get-YimePimePayloadFileRecord $path
    $stream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $bytes = New-Object byte[] ([int]$stream.Length)
        $null = $stream.Read($bytes,0,$bytes.Length)
        if (-not(Test-RimePimeCandidateArchiveBytesEqual $bytes $script:RimePimeCandidateArchiveLockBytes) -or
            [string]$record.sha256 -cne (Get-RimePimeCandidateArchiveSha256Bytes $bytes)) {
            throw 'Candidate archive lock anchor is foreign.'
        }
        return $stream
    } catch { $stream.Dispose();throw }
}

function Add-RimePimeCandidateArchiveArtifact {
    param(
        [Parameter(Mandatory)]$Artifacts,
        [Parameter(Mandatory)]$Seen,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Kind,
        [string]$ExpectedSha256,
        [long]$ExpectedBytes=0
    )
    $full = Resolve-RimePimeCandidateArchiveSourcePath $SourceRoot $RelativePath
    $record = Read-RimePimeCandidateArchiveFileBytes $full 536870912 "candidate archive source $RelativePath"
    if ($ExpectedSha256 -and $record.Sha256 -cne $ExpectedSha256) { throw "Candidate archive source digest differs: $RelativePath" }
    if ($ExpectedBytes -gt 0 -and $record.Length -ne $ExpectedBytes) { throw "Candidate archive source byte count differs: $RelativePath" }
    if ($Seen.ContainsKey($RelativePath)) {
        $existing = $Seen[$RelativePath]
        if ($existing.Sha256 -cne $record.Sha256 -or $existing.Length -ne $record.Length) {
            throw "Candidate archive source path was bound to two identities: $RelativePath"
        }
        return $existing
    }
    $artifact = [pscustomobject]@{
        RelativePath=$RelativePath;Kind=$Kind;Sha256=$record.Sha256;Length=$record.Length;Bytes=[byte[]]$record.Bytes
    }
    $Seen.Add($RelativePath,$artifact)
    $Artifacts.Add($artifact)
    return $artifact
}

function Add-RimePimeCandidateArchiveSealedArtifact {
    param(
        [Parameter(Mandatory)]$Artifacts,
        [Parameter(Mandatory)]$Seen,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Kind,
        [string]$ExpectedSha256,
        [long]$ExpectedBytes=0
    )
    $data = Add-RimePimeCandidateArchiveArtifact $Artifacts $Seen $SourceRoot $RelativePath $Kind $ExpectedSha256 $ExpectedBytes
    $sidecarRelative = $RelativePath + '.sha256'
    $sidecar = Add-RimePimeCandidateArchiveArtifact $Artifacts $Seen $SourceRoot $sidecarRelative ($Kind+'-sidecar')
    foreach ($one in $sidecar.Bytes) { if ($one -gt 127) { throw "Candidate archive source sidecar is not ASCII: $sidecarRelative" } }
    $expected = $data.Sha256+'  '+[IO.Path]::GetFileName($RelativePath)+"`n"
    if ([Text.Encoding]::ASCII.GetString($sidecar.Bytes) -cne $expected) {
        throw "Candidate archive source sidecar is not exact: $sidecarRelative"
    }
    return $data
}

function Assert-RimePimeCandidateArchiveRunnerResult {
    param([Parameter(Mandatory)]$Result)
    Assert-RimePimeExactProperties $Result @(
        'schema_version','generated_at_utc','status','source','commands','evidence','failure','boundaries'
    ) 'candidate archive runner result'
    if ($Result.schema_version -isnot [string] -or $Result.generated_at_utc -isnot [string] -or
        [string]$Result.generated_at_utc -cnotmatch '^\d{4}-\d{2}-\d{2}T.*Z$' -or
        [string]$Result.schema_version -cne $script:RimePimeCandidateArchiveRunnerSchema -or
        $Result.status -isnot [string] -or [string]$Result.status -cne 'pass' -or $null -ne $Result.failure) {
        throw 'Candidate archive requires one passing isolated-candidate runner result.'
    }
    Assert-RimePimeExactProperties $Result.source @(
        'repo_root','exact_head','exact_tree','runner_relative_path','runner_head_blob','runner_worktree_blob',
        'runner_matches_exact_head','clone_core_autocrlf','clone_detached_exact_head','actual_protected_snapshot_unchanged',
        'before_snapshot_sha256','after_snapshot_sha256'
    ) 'candidate archive runner source'
    if ($Result.source.repo_root -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Result.source.repo_root) -or
        $Result.source.runner_relative_path -isnot [string] -or
        [string]$Result.source.runner_relative_path -cne 'tools/dual-product/run-rime-pime-isolated-candidate.ps1' -or
        $Result.source.clone_core_autocrlf -isnot [string] -or [string]$Result.source.clone_core_autocrlf -cne 'false' -or
        $Result.source.before_snapshot_sha256 -isnot [string] -or
        $Result.source.after_snapshot_sha256 -isnot [string] -or
        -not(Test-RimePimeCandidateArchiveDigest $Result.source.before_snapshot_sha256) -or
        -not(Test-RimePimeCandidateArchiveDigest $Result.source.after_snapshot_sha256) -or
        [string]$Result.source.before_snapshot_sha256 -cne [string]$Result.source.after_snapshot_sha256) {
        throw 'Candidate archive runner source metadata or protected snapshot binding is invalid.'
    }
    foreach ($name in @('exact_head','exact_tree','runner_head_blob','runner_worktree_blob')) {
        if ($Result.source.$name -isnot [string] -or [string]$Result.source.$name -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$') {
            throw "Candidate archive runner source $name is invalid."
        }
    }
    if ($Result.source.runner_matches_exact_head -isnot [bool] -or -not[bool]$Result.source.runner_matches_exact_head -or
        $Result.source.clone_detached_exact_head -isnot [bool] -or -not[bool]$Result.source.clone_detached_exact_head -or
        $Result.source.actual_protected_snapshot_unchanged -isnot [bool] -or -not[bool]$Result.source.actual_protected_snapshot_unchanged -or
        [string]$Result.source.runner_head_blob -cne [string]$Result.source.runner_worktree_blob) {
        throw 'Candidate archive runner source identity is not exact and protected.'
    }
    if ($Result.commands -isnot [Array]) { throw 'Candidate archive runner commands must be a JSON array.' }
    $commands = @($Result.commands)
    if ($commands.Count -lt 1) { throw 'Candidate archive runner command record is empty.' }
    foreach ($command in $commands) {
        if ($null -eq $command.PSObject.Properties['exit_code'] -or
            -not(Test-RimePimeCandidateArchiveInteger $command.exit_code) -or [int]$command.exit_code -ne 0) {
            throw 'Candidate archive runner contains a failed or malformed command.'
        }
    }
    $evidence = $Result.evidence
    foreach ($name in @('clone_path','source_head','source_tree','clone_current_version',
        'distinct_versioned_installer_leaf_for_dp1n','dp1n_version_identity_admission','package_plan','build_result',
        'build_manifest','postbuild_result','installer','historical_v1_receipt','durable_v2_receipt')) {
        if ($null -eq $evidence.PSObject.Properties[$name]) { throw "Candidate archive runner evidence is missing $name." }
    }
    if ($evidence.clone_path -isnot [string] -or $evidence.source_head -isnot [string] -or
        $evidence.source_tree -isnot [string] -or
        [string]$evidence.clone_path -cne 'repo' -or
        [string]$evidence.source_head -cne [string]$Result.source.exact_head -or
        [string]$evidence.source_tree -cne [string]$Result.source.exact_tree -or
        $evidence.distinct_versioned_installer_leaf_for_dp1n -isnot [bool] -or
        -not[bool]$evidence.distinct_versioned_installer_leaf_for_dp1n) {
        throw 'Candidate archive runner does not describe the admitted versioned successor clone.'
    }
    $admission = $evidence.dp1n_version_identity_admission
    foreach ($name in @('identity_transition_admitted','actual_canonical_migration_admitted','actual_canonical_migrated')) {
        if ($null -eq $admission.PSObject.Properties[$name] -or $admission.$name -isnot [bool]) {
            throw 'Candidate archive version-identity admission is malformed.'
        }
    }
    if (-not[bool]$admission.identity_transition_admitted -or [bool]$admission.actual_canonical_migration_admitted -or
        [bool]$admission.actual_canonical_migrated) {
        throw 'Candidate archive requires identity admission without actual migration admission.'
    }
    if (-not(Test-RimePimeCandidateArchiveInteger $evidence.build_manifest.bytes) -or
        [long]$evidence.build_manifest.bytes -lt 1) {
        throw 'Candidate archive runner build-manifest byte type is invalid.'
    }
    if ($evidence.installer.unsigned_disabled -isnot [bool] -or -not[bool]$evidence.installer.unsigned_disabled -or
        $evidence.build_manifest.static_only_passed -isnot [bool] -or -not[bool]$evidence.build_manifest.static_only_passed -or
        $evidence.build_result.schema_version -isnot [string] -or
        [string]$evidence.build_result.schema_version -cne $script:RimePimeCandidateArchiveBuildSchema -or
        $evidence.durable_v2_receipt.schema_version -isnot [string] -or
        [string]$evidence.durable_v2_receipt.schema_version -cne $script:RimePimeCandidateArchiveReceiptSchema -or
        $evidence.durable_v2_receipt.evidence_artifacts_durable -isnot [bool] -or
        -not[bool]$evidence.durable_v2_receipt.evidence_artifacts_durable -or
        $evidence.durable_v2_receipt.durability_scope -isnot [string] -or
        [string]$evidence.durable_v2_receipt.durability_scope -cne 'isolated-clone-content-addressed-process-interruption-protocol') {
        throw 'Candidate archive runner evidence is not a disabled static candidate with retained receipt evidence.'
    }
    $boundaryNames = @(
        'installer_executed','uninstaller_executed','signing_process_executed','installed_product_processes_touched',
        'product_registry_mutated','default_input_method_changed','production_user_data_read_or_written',
        'installed_yimecore_local12_touched','actual_canonical_migrated','actual_canonical_migration_admitted',
        'actual_installer_published','real_installer_transaction_adapter_wired','release_signing_complete','delivery_admitted',
        'hardware_power_loss_durability_verified','directory_metadata_durability_verified','outer_tmp_retention_guaranteed',
        'evidence_archived_outside_tmp','active_same_sid_physical_replacement_prevented','full_nsis_toolchain_input_closure'
    )
    Assert-RimePimeExactProperties $Result.boundaries $boundaryNames 'candidate archive runner boundaries'
    Assert-RimePimeCandidateArchiveFalseFlags $Result.boundaries $boundaryNames 'candidate archive runner boundaries'
    return $Result
}

function Assert-RimePimeCandidateArchiveReceipt {
    param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$RunnerEvidence)
    foreach ($name in @('schema_version','product','product_version','package_plan','sealed_stage','payload_include',
        'predecessor_v1','disabled_build','static_postbuild','installer','evidence_artifacts_durable','delivery_admitted')) {
        if ($null -eq $Receipt.PSObject.Properties[$name]) { throw "Candidate archive retained receipt is missing $name." }
    }
    if ($Receipt.schema_version -isnot [string] -or $Receipt.product -isnot [string] -or
        $Receipt.product_version -isnot [string] -or
        [string]$Receipt.schema_version -cne $script:RimePimeCandidateArchiveReceiptSchema -or
        [string]$Receipt.product -cne 'rime-pime' -or
        [string]$Receipt.product_version -cne [string]$RunnerEvidence.clone_current_version -or
        $Receipt.evidence_artifacts_durable -isnot [bool] -or -not[bool]$Receipt.evidence_artifacts_durable -or
        $Receipt.delivery_admitted -isnot [bool] -or [bool]$Receipt.delivery_admitted -or
        $Receipt.disabled_build.schema_version -isnot [string] -or
        [string]$Receipt.disabled_build.schema_version -cne $script:RimePimeCandidateArchiveBuildSchema) {
        throw 'Candidate archive retained receipt identity or safety boundary is invalid.'
    }
    foreach ($name in @('path','sha256','bytes')) {
        if ($null -eq $Receipt.installer.PSObject.Properties[$name]) { throw 'Candidate archive receipt installer identity is incomplete.' }
    }
    if ($Receipt.installer.path -isnot [string] -or $Receipt.installer.sha256 -isnot [string] -or
        [string]$Receipt.installer.path -cne ('installer/YIME-'+[string]$Receipt.product_version+'-setup.exe') -or
        -not(Test-RimePimeCandidateArchiveDigest $Receipt.installer.sha256) -or
        -not(Test-RimePimeCandidateArchiveInteger $Receipt.installer.bytes) -or [long]$Receipt.installer.bytes -lt 1 -or
        [string]$Receipt.installer.sha256 -cne [string]$RunnerEvidence.installer.sha256 -or
        [long]$Receipt.installer.bytes -ne [long]$RunnerEvidence.installer.bytes) {
        throw 'Candidate archive receipt and runner installer identities differ.'
    }
    return $Receipt
}

function Get-RimePimeCandidateArchiveReceiptDigests {
    param([Parameter(Mandatory)]$Receipt)
    $digests = [Collections.Generic.List[string]]::new()
    foreach ($value in @(
        $Receipt.package_plan.sha256,
        $Receipt.sealed_stage.content_manifest_sha256,
        $Receipt.payload_include.sha256,
        $Receipt.payload_include.receipt_sha256,
        $Receipt.predecessor_v1.sha256,
        $Receipt.disabled_build.result_sha256,
        $Receipt.static_postbuild.result_sha256,
        $Receipt.installer.source_sha256,
        $Receipt.installer.sha256
    )) {
        if (-not(Test-RimePimeCandidateArchiveDigest $value)) { throw 'Candidate archive receipt contains an invalid evidence digest.' }
        $digests.Add([string]$value)
    }
    foreach ($pair in @(
        @('payload_spec_sha256',$Receipt.sealed_stage),
        @('go_payload_inventory_sha256',$Receipt.sealed_stage),
        @('nsis_toolchain_lock_sha256',$Receipt.disabled_build)
    )) {
        $property = $pair[1].PSObject.Properties[$pair[0]]
        if ($null -ne $property) {
            if (-not(Test-RimePimeCandidateArchiveDigest $property.Value)) { throw 'Candidate archive receipt contains an invalid optional evidence digest.' }
            $digests.Add([string]$property.Value)
        }
    }
    return @($digests | Select-Object -Unique)
}

function Get-RimePimeCandidateArchiveSourceMaterial {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$ExpectedRunnerResultSha256)
    if (-not(Test-RimePimeCandidateArchiveDigest $ExpectedRunnerResultSha256)) { throw 'Expected runner result digest is invalid.' }
    $source = Assert-RimePimeCandidateArchiveDirectory $Context.source_root 'candidate archive outer-tmp source'
    $artifacts = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)

    $resultArtifact = Add-RimePimeCandidateArchiveSealedArtifact $artifacts $seen $source 'result.json' 'runner-result' $ExpectedRunnerResultSha256
    $result = ConvertFrom-RimePimeCandidateArchiveJsonBytes $resultArtifact.Bytes 'candidate archive runner result'
    $null = Assert-RimePimeCandidateArchiveRunnerResult $result
    $e = $result.evidence

    foreach ($name in @('package_plan','build_result','build_manifest','postbuild_result','historical_v1_receipt','durable_v2_receipt')) {
        $record = $e.$name
        if ($record.path -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$record.path) -or
            $record.sha256 -isnot [string]) {
            throw "Candidate archive runner $name path/digest types are invalid."
        }
    }
    if ($e.installer.path -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$e.installer.path) -or
        $e.installer.sha256 -isnot [string] -or $e.clone_current_version -isnot [string] -or
        [string]$e.clone_current_version -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$') {
        throw 'Candidate archive runner installer/version field types are invalid.'
    }
    if (-not(Test-RimePimeCandidateArchiveInteger $e.build_manifest.bytes) -or [long]$e.build_manifest.bytes -lt 1) {
        throw 'Candidate archive runner build-manifest byte type is invalid.'
    }

    $primary = @(
        @([string]$e.package_plan.path,'package-plan',[string]$e.package_plan.sha256,0L),
        @([string]$e.build_result.path,'build-result',[string]$e.build_result.sha256,0L),
        @([string]$e.build_manifest.path,'build-manifest',[string]$e.build_manifest.sha256,[long]$e.build_manifest.bytes),
        @([string]$e.postbuild_result.path,'postbuild-result',[string]$e.postbuild_result.sha256,0L),
        @([string]$e.historical_v1_receipt.path,'historical-v1-receipt',[string]$e.historical_v1_receipt.sha256,0L),
        @([string]$e.durable_v2_receipt.path,'retained-v2-receipt',[string]$e.durable_v2_receipt.sha256,0L)
    )
    $primaryByKind = @{}
    foreach ($item in $primary) {
        if (-not(Test-RimePimeCandidateArchiveDigest $item[2])) { throw "Candidate archive runner $($item[1]) digest is invalid." }
        $primaryByKind[$item[1]] = Add-RimePimeCandidateArchiveSealedArtifact $artifacts $seen $source $item[0] $item[1] $item[2] ([long]$item[3])
    }
    if (-not(Test-RimePimeCandidateArchiveDigest $e.installer.sha256) -or
        -not(Test-RimePimeCandidateArchiveInteger $e.installer.bytes) -or [long]$e.installer.bytes -lt 1) {
        throw 'Candidate archive runner installer identity is invalid.'
    }
    $installerArtifact = Add-RimePimeCandidateArchiveArtifact $artifacts $seen $source ([string]$e.installer.path) `
        'candidate-installer' ([string]$e.installer.sha256) ([long]$e.installer.bytes)

    $receiptArtifact = $primaryByKind['retained-v2-receipt']
    $receipt = ConvertFrom-RimePimeCandidateArchiveJsonBytes $receiptArtifact.Bytes 'candidate archive retained receipt'
    $null = Assert-RimePimeCandidateArchiveReceipt $receipt $e
    if ([string]$receipt.installer.sha256 -cne $installerArtifact.Sha256 -or
        [long]$receipt.installer.bytes -ne $installerArtifact.Length) {
        throw 'Candidate archive physical installer differs from its retained receipt.'
    }

    $storeRoot = Join-Path $source 'repo\installer\receipt-evidence\sha256'
    $null = Assert-RimePimeCandidateArchiveDirectory $storeRoot 'candidate archive retained object store'
    $storedDigests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @(Get-ChildItem -LiteralPath $storeRoot -Force)) {
        if (-not $entry.PSIsContainer -or $entry.Name -cnotmatch '^[0-9a-f]{2}$') {
            throw 'Candidate archive retained object store has an unexpected top-level entry.'
        }
        $null = Assert-RimePimeCandidateArchiveDirectory $entry.FullName 'candidate archive retained object prefix'
        foreach ($leaf in @(Get-ChildItem -LiteralPath $entry.FullName -Force)) {
            if ($leaf.PSIsContainer) { throw 'Candidate archive retained object prefix contains a directory.' }
            if ($leaf.Name -cmatch '^\.writing-[0-9a-f]{32}(?:\.tmp)?$') { continue }
            if ($leaf.Name -cnotmatch '^([0-9a-f]{64})\.blob$') {
                if ($leaf.Name -cmatch '^[0-9a-f]{64}\.blob\.sha256$') { continue }
                throw 'Candidate archive retained object store has an unexpected leaf.'
            }
            $digest = [string]$Matches[1]
            if ($digest.Substring(0,2) -cne $entry.Name) { throw 'Candidate archive retained object is under the wrong prefix.' }
            $relative = $leaf.FullName.Substring($source.Length+1).Replace('\','/')
            $object = Add-RimePimeCandidateArchiveArtifact $artifacts $seen $source $relative 'retained-object' $digest
            $sidecarRelative = $relative+'.sha256'
            $sidecar = Add-RimePimeCandidateArchiveArtifact $artifacts $seen $source $sidecarRelative 'retained-object-sidecar'
            foreach ($one in $sidecar.Bytes) { if ($one -gt 127) { throw 'Retained object sidecar is not ASCII.' } }
            $marker = $digest+'  '+$leaf.Name+"`n"
            if ([Text.Encoding]::ASCII.GetString($sidecar.Bytes) -cne $marker) { throw 'Retained object sidecar is malformed.' }
            $null = $storedDigests.Add($object.Sha256)
        }
    }
    $requiredDigests = @(Get-RimePimeCandidateArchiveReceiptDigests $receipt)
    $requiredDigests += $receiptArtifact.Sha256
    foreach ($digest in @($requiredDigests | Select-Object -Unique)) {
        if (-not $storedDigests.Contains([string]$digest)) { throw "Candidate archive retained object is missing: $digest" }
    }

    $paths = [string[]]@($artifacts | ForEach-Object { [string]$_.RelativePath })
    [Array]::Sort($paths,[StringComparer]::Ordinal)
    $ordered = [Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($path in $paths) {
        $artifact = $seen[$path]
        $ordered.Add([pscustomobject][ordered]@{
            ordinal=$ordinal;source_relative_path=[string]$artifact.RelativePath;kind=[string]$artifact.Kind
            sha256=[string]$artifact.Sha256;bytes=[long]$artifact.Length
        })
        $ordinal++
    }
    $archiveIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-identity-v1'
        product='rime-pime';runner_result_sha256=$resultArtifact.Sha256;receipt_sha256=$receiptArtifact.Sha256
        installer_sha256=$installerArtifact.Sha256;installer_bytes=[long]$installerArtifact.Length
    }
    $archiveId = Get-RimePimeCandidateArchiveSha256Bytes (ConvertTo-RimePimeCandidateArchiveBytes $archiveIdentity)
    $manifest = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveManifestSchema
        product='rime-pime';archive_id=$archiveId;archive_format='immutable-single-generation-content-addressed-capsule-v1'
        source_runner_result_path='result.json';source_runner_result_sha256=$resultArtifact.Sha256
        source_runner_result_bytes=[long]$resultArtifact.Length
        source_head=[string]$result.source.exact_head;source_tree=[string]$result.source.exact_tree
        runner_head_blob=[string]$result.source.runner_head_blob;runner_worktree_blob=[string]$result.source.runner_worktree_blob
        product_version=[string]$receipt.product_version
        installer_path=[string]$receipt.installer.path;installer_source_relative_path=[string]$e.installer.path
        installer_sha256=[string]$receipt.installer.sha256
        installer_bytes=[long]$receipt.installer.bytes
        retained_receipt_path=[string]$e.durable_v2_receipt.path
        retained_receipt_sha256=$receiptArtifact.Sha256;retained_receipt_bytes=[long]$receiptArtifact.Length
        build_evidence_schema=[string]$receipt.disabled_build.schema_version
        artifact_count=[int]$ordered.Count;artifacts=@($ordered | ForEach-Object { $_ })
        source_outer_tmp_required_after_commit=$false
        actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
    $manifestBytes = ConvertTo-RimePimeCandidateArchiveBytes $manifest
    $manifestDigest = Get-RimePimeCandidateArchiveSha256Bytes $manifestBytes
    $operationIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-operation-v1'
        archive_id=$archiveId;manifest_sha256=$manifestDigest;runner_result_sha256=$resultArtifact.Sha256
        retained_receipt_sha256=$receiptArtifact.Sha256
    }
    $operationId = Get-RimePimeCandidateArchiveSha256Bytes (ConvertTo-RimePimeCandidateArchiveBytes $operationIdentity)
    $head = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveHeadSchema;product='rime-pime';archive_id=$archiveId
        operation_id=$operationId;generation_ordinal=1;manifest_sha256=$manifestDigest
        runner_result_sha256=$resultArtifact.Sha256;retained_receipt_sha256=$receiptArtifact.Sha256
        fixture_protocol_only=$true;actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
    $headBytes = ConvertTo-RimePimeCandidateArchiveBytes $head
    $headDigest = Get-RimePimeCandidateArchiveSha256Bytes $headBytes
    $rootMarker = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveRootSchema;product='rime-pime'
        owner_scope='fixture-candidate-evidence-only';archive_id=$archiveId;operation_id=$operationId
        manifest_sha256=$manifestDigest;head_sha256=$headDigest;runner_result_sha256=$resultArtifact.Sha256
        retained_receipt_sha256=$receiptArtifact.Sha256;fixture_protocol_only=$true
        actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
    $intent = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveIntentSchema;archive_id=$archiveId;operation_id=$operationId
        manifest_sha256=$manifestDigest;head_sha256=$headDigest;runner_result_sha256=$resultArtifact.Sha256
        retained_receipt_sha256=$receiptArtifact.Sha256;post_intent_roll_forward_only=$true
        actual_archive_root_published=$false;actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
    $completion = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveCompletionSchema;archive_id=$archiveId;operation_id=$operationId
        manifest_sha256=$manifestDigest;head_sha256=$headDigest;runner_result_sha256=$resultArtifact.Sha256
        retained_receipt_sha256=$receiptArtifact.Sha256;capsule_complete=$true
        actual_archive_root_published=$false;actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
    return [pscustomobject]@{
        Result=$result;Receipt=$receipt;Artifacts=@($artifacts);Manifest=$manifest;ManifestBytes=$manifestBytes
        ManifestDigest=$manifestDigest;ArchiveId=$archiveId;OperationId=$operationId
        Head=$head;HeadBytes=$headBytes;HeadDigest=$headDigest;RootMarker=$rootMarker;Intent=$intent;Completion=$completion
    }
}

function Get-RimePimeCandidateArchiveObjectPath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Digest)
    if (-not(Test-RimePimeCandidateArchiveDigest $Digest)) { throw 'Candidate archive object digest is invalid.' }
    return Join-Path $Root ('objects\sha256\'+$Digest.Substring(0,2)+'\'+$Digest+'.blob')
}

function Ensure-RimePimeCandidateArchiveObject {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][byte[]]$Bytes,[string]$Phase='object')
    $digest = Get-RimePimeCandidateArchiveSha256Bytes $Bytes
    $path = Get-RimePimeCandidateArchiveObjectPath $Root $digest
    Ensure-RimePimeCandidateArchiveDirectory (Split-Path -Parent $path)
    $sealed = Ensure-RimePimeCandidateArchiveSealedBytes $path $Bytes $Phase
    if ($sealed.Sha256 -cne $digest) { throw 'Candidate archive object publication changed its digest.' }
    return $sealed
}

function Read-RimePimeCandidateArchiveRootMarker {
    param([Parameter(Mandatory)][string]$Root)
    $sealed = Read-RimePimeCandidateArchiveSealedArchiveFile (Join-Path $Root 'archive-root.json') 'candidate archive root marker' 1048576 -Json
    $value = $sealed.Value
    Assert-RimePimeExactProperties $value @(
        'schema_version','product','owner_scope','archive_id','operation_id','manifest_sha256','head_sha256',
        'runner_result_sha256','retained_receipt_sha256','fixture_protocol_only','actual_archive_root_published',
        'actual_evidence_archived_outside_repository_tmp','actual_canonical_migration_admitted','actual_canonical_migrated',
        'hardware_power_loss_verified','directory_metadata_durability_verified','active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive root marker'
    if ($value.schema_version -isnot [string] -or $value.product -isnot [string] -or $value.owner_scope -isnot [string] -or
        [string]$value.schema_version -cne $script:RimePimeCandidateArchiveRootSchema -or
        [string]$value.product -cne 'rime-pime' -or [string]$value.owner_scope -cne 'fixture-candidate-evidence-only' -or
        $value.fixture_protocol_only -isnot [bool] -or -not[bool]$value.fixture_protocol_only) {
        throw 'Candidate archive root ownership marker is invalid.'
    }
    foreach ($name in @('archive_id','operation_id','manifest_sha256','head_sha256','runner_result_sha256','retained_receipt_sha256')) {
        if (-not(Test-RimePimeCandidateArchiveDigest $value.$name)) { throw "Candidate archive root $name is invalid." }
    }
    Assert-RimePimeCandidateArchiveFalseFlags $value @(
        'actual_archive_root_published','actual_evidence_archived_outside_repository_tmp','actual_canonical_migration_admitted',
        'actual_canonical_migrated','hardware_power_loss_verified','directory_metadata_durability_verified',
        'active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive root marker'
    return $value
}

function Assert-RimePimeCandidateArchiveManifest {
    param([Parameter(Mandatory)]$Manifest)
    Assert-RimePimeExactProperties $Manifest @(
        'schema_version','product','archive_id','archive_format','source_runner_result_path','source_runner_result_sha256',
        'source_runner_result_bytes','source_head','source_tree','runner_head_blob','runner_worktree_blob','product_version',
        'installer_path','installer_source_relative_path','installer_sha256','installer_bytes','retained_receipt_path',
        'retained_receipt_sha256','retained_receipt_bytes','build_evidence_schema','artifact_count','artifacts',
        'source_outer_tmp_required_after_commit','actual_evidence_archived_outside_repository_tmp',
        'actual_canonical_migration_admitted','actual_canonical_migrated','hardware_power_loss_verified',
        'directory_metadata_durability_verified','active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive manifest'
    if ($Manifest.schema_version -isnot [string] -or $Manifest.product -isnot [string] -or
        $Manifest.archive_format -isnot [string] -or $Manifest.build_evidence_schema -isnot [string] -or
        [string]$Manifest.schema_version -cne $script:RimePimeCandidateArchiveManifestSchema -or
        [string]$Manifest.product -cne 'rime-pime' -or
        [string]$Manifest.archive_format -cne 'immutable-single-generation-content-addressed-capsule-v1' -or
        [string]$Manifest.build_evidence_schema -cne $script:RimePimeCandidateArchiveBuildSchema -or
        $Manifest.product_version -isnot [string] -or
        [string]$Manifest.product_version -cnotmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$' -or
        $Manifest.source_runner_result_path -isnot [string] -or [string]$Manifest.source_runner_result_path -cne 'result.json' -or
        $Manifest.retained_receipt_path -isnot [string] -or $Manifest.installer_source_relative_path -isnot [string] -or
        $Manifest.installer_path -isnot [string] -or
        [string]$Manifest.retained_receipt_path -cne 'repo/installer/package-build-receipt.json' -or
        [string]$Manifest.installer_path -cne ('installer/YIME-'+[string]$Manifest.product_version+'-setup.exe') -or
        [string]$Manifest.installer_source_relative_path -cne ('repo/'+[string]$Manifest.installer_path) -or
        $Manifest.source_head -isnot [string] -or [string]$Manifest.source_head -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or
        $Manifest.source_tree -isnot [string] -or [string]$Manifest.source_tree -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or
        $Manifest.runner_head_blob -isnot [string] -or [string]$Manifest.runner_head_blob -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or
        $Manifest.runner_worktree_blob -isnot [string] -or [string]$Manifest.runner_worktree_blob -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or
        [string]$Manifest.runner_head_blob -cne [string]$Manifest.runner_worktree_blob -or
        -not(Test-RimePimeCandidateArchiveDigest $Manifest.archive_id) -or
        -not(Test-RimePimeCandidateArchiveDigest $Manifest.source_runner_result_sha256) -or
        -not(Test-RimePimeCandidateArchiveDigest $Manifest.retained_receipt_sha256) -or
        -not(Test-RimePimeCandidateArchiveDigest $Manifest.installer_sha256) -or
        -not(Test-RimePimeCandidateArchiveInteger $Manifest.artifact_count) -or
        -not(Test-RimePimeCandidateArchiveInteger $Manifest.installer_bytes) -or
        -not(Test-RimePimeCandidateArchiveInteger $Manifest.retained_receipt_bytes) -or
        -not(Test-RimePimeCandidateArchiveInteger $Manifest.source_runner_result_bytes)) {
        throw 'Candidate archive manifest identity is invalid.'
    }
    Assert-RimePimeCandidateArchiveFalseFlags $Manifest @(
        'source_outer_tmp_required_after_commit','actual_evidence_archived_outside_repository_tmp',
        'actual_canonical_migration_admitted','actual_canonical_migrated','hardware_power_loss_verified',
        'directory_metadata_durability_verified','active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive manifest'
    $rows = @($Manifest.artifacts)
    if ($rows.Count -lt 10 -or $rows.Count -ne [int]$Manifest.artifact_count) { throw 'Candidate archive manifest artifact count is invalid.' }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($i=0;$i -lt $rows.Count;$i++) {
        $row = $rows[$i]
        Assert-RimePimeExactProperties $row @('ordinal','source_relative_path','kind','sha256','bytes') 'candidate archive artifact'
        $null = Assert-RimePimeCandidateArchiveRelativePathText $row.source_relative_path 'Candidate archive artifact source path'
        if (-not(Test-RimePimeCandidateArchiveInteger $row.ordinal) -or [int]$row.ordinal -ne $i -or
            -not $paths.Add([string]$row.source_relative_path) -or $row.kind -isnot [string] -or
            [string]$row.kind -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or -not(Test-RimePimeCandidateArchiveDigest $row.sha256) -or
            -not(Test-RimePimeCandidateArchiveInteger $row.bytes) -or [long]$row.bytes -lt 1) {
            throw 'Candidate archive artifact identity is invalid.'
        }
    }
    foreach ($binding in @(
        @('runner-result',[string]$Manifest.source_runner_result_path,[string]$Manifest.source_runner_result_sha256,[long]$Manifest.source_runner_result_bytes,$true),
        @('retained-v2-receipt',[string]$Manifest.retained_receipt_path,[string]$Manifest.retained_receipt_sha256,[long]$Manifest.retained_receipt_bytes,$true),
        @('candidate-installer',[string]$Manifest.installer_source_relative_path,[string]$Manifest.installer_sha256,[long]$Manifest.installer_bytes,$false)
    )) {
        $kind = [string]$binding[0]
        $matches = @($rows | Where-Object { [string]$_.kind -ceq $kind })
        if ($matches.Count -ne 1 -or [string]$matches[0].source_relative_path -cne [string]$binding[1] -or
            [string]$matches[0].sha256 -cne [string]$binding[2] -or [long]$matches[0].bytes -ne [long]$binding[3]) {
            throw "Candidate archive manifest must uniquely bind its $kind path, digest, and byte count."
        }
        if ([bool]$binding[4]) {
            $sidecarKind = $kind+'-sidecar'
            $sidecarMatches = @($rows | Where-Object { [string]$_.kind -ceq $sidecarKind })
            if ($sidecarMatches.Count -ne 1 -or
                [string]$sidecarMatches[0].source_relative_path -cne ([string]$binding[1]+'.sha256')) {
                throw "Candidate archive manifest must uniquely bind its $sidecarKind source path."
            }
        }
    }
    return $Manifest
}

function New-RimePimeCandidateArchiveHeadFromRoot {
    param([Parameter(Mandatory)]$RootMarker)
    return [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveHeadSchema;product='rime-pime';archive_id=[string]$RootMarker.archive_id
        operation_id=[string]$RootMarker.operation_id;generation_ordinal=1;manifest_sha256=[string]$RootMarker.manifest_sha256
        runner_result_sha256=[string]$RootMarker.runner_result_sha256
        retained_receipt_sha256=[string]$RootMarker.retained_receipt_sha256
        fixture_protocol_only=$true;actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
}

function New-RimePimeCandidateArchiveCompletionFromRoot {
    param([Parameter(Mandatory)]$RootMarker)
    return [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveCompletionSchema;archive_id=[string]$RootMarker.archive_id
        operation_id=[string]$RootMarker.operation_id;manifest_sha256=[string]$RootMarker.manifest_sha256
        head_sha256=[string]$RootMarker.head_sha256;runner_result_sha256=[string]$RootMarker.runner_result_sha256
        retained_receipt_sha256=[string]$RootMarker.retained_receipt_sha256;capsule_complete=$true
        actual_archive_root_published=$false;actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
}

function Read-RimePimeCandidateArchiveAtRoot {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Root,[switch]$AllowStage)
    $root = Assert-RimePimeCandidateArchiveDirectory $Root 'candidate archive capsule'
    if (-not $AllowStage -and $root -ine [string]$Context.archive_root) { throw 'Candidate archive reader accepts only the final fixture archive root.' }
    if ($AllowStage -and $root -ine [string]$Context.archive_root -and
        ((Split-Path -Parent $root) -ine [string]$Context.case_root -or
         (Split-Path -Leaf $root) -cnotmatch '^\.rpa-[0-9a-f]{16}\.staged$')) {
        throw 'Candidate archive stage is outside its fixture case.'
    }
    $owner = Read-RimePimeCandidateArchiveRootMarker $root
    $manifestSeal = Read-RimePimeCandidateArchiveSealedArchiveFile (Join-Path $root 'manifest.json') 'candidate archive manifest' 16777216 -Json
    $manifest = Assert-RimePimeCandidateArchiveManifest $manifestSeal.Value
    if ($manifestSeal.Data.Sha256 -cne [string]$owner.manifest_sha256 -or
        [string]$manifest.archive_id -cne [string]$owner.archive_id -or
        [string]$manifest.source_runner_result_sha256 -cne [string]$owner.runner_result_sha256 -or
        [string]$manifest.retained_receipt_sha256 -cne [string]$owner.retained_receipt_sha256) {
        throw 'Candidate archive root, manifest, and source identities differ.'
    }
    $archiveIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-identity-v1'
        product='rime-pime';runner_result_sha256=[string]$manifest.source_runner_result_sha256
        receipt_sha256=[string]$manifest.retained_receipt_sha256
        installer_sha256=[string]$manifest.installer_sha256;installer_bytes=[long]$manifest.installer_bytes
    }
    $expectedArchiveId = Get-RimePimeCandidateArchiveSha256Bytes (ConvertTo-RimePimeCandidateArchiveBytes $archiveIdentity)
    if ($expectedArchiveId -cne [string]$owner.archive_id) {
        throw 'Candidate archive ID is not the deterministic identity of its manifest evidence.'
    }
    $operationIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-operation-v1'
        archive_id=$expectedArchiveId;manifest_sha256=$manifestSeal.Data.Sha256
        runner_result_sha256=[string]$manifest.source_runner_result_sha256
        retained_receipt_sha256=[string]$manifest.retained_receipt_sha256
    }
    $expectedOperationId = Get-RimePimeCandidateArchiveSha256Bytes (ConvertTo-RimePimeCandidateArchiveBytes $operationIdentity)
    if ($expectedOperationId -cne [string]$owner.operation_id) {
        throw 'Candidate archive operation ID is not the deterministic identity of its manifest publication.'
    }
    $manifestObject = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root $manifestSeal.Data.Sha256) 'candidate archive manifest object' 16777216
    if ($manifestObject.Data.Sha256 -cne $manifestSeal.Data.Sha256 -or
        -not(Test-RimePimeCandidateArchiveBytesEqual $manifestObject.Data.Bytes $manifestSeal.Data.Bytes)) {
        throw 'Candidate archive named manifest differs from its content-addressed object.'
    }
    $expectedDigests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $expectedDigests.Add($manifestSeal.Data.Sha256)
    foreach ($row in @($manifest.artifacts)) {
        $object = Read-RimePimeCandidateArchiveSealedArchiveFile `
            (Get-RimePimeCandidateArchiveObjectPath $root ([string]$row.sha256)) "candidate archive object $($row.ordinal)" 536870912
        if ($object.Data.Sha256 -cne [string]$row.sha256 -or $object.Data.Length -ne [long]$row.bytes) {
            throw 'Candidate archive object digest or byte count differs from the manifest.'
        }
        $null = $expectedDigests.Add([string]$row.sha256)
    }
    $runnerRow = @($manifest.artifacts | Where-Object { [string]$_.kind -ceq 'runner-result' })[0]
    $runnerSidecarRow = @($manifest.artifacts | Where-Object { [string]$_.kind -ceq 'runner-result-sidecar' })[0]
    $receiptRow = @($manifest.artifacts | Where-Object { [string]$_.kind -ceq 'retained-v2-receipt' })[0]
    $receiptSidecarRow = @($manifest.artifacts | Where-Object { [string]$_.kind -ceq 'retained-v2-receipt-sidecar' })[0]
    $runnerObject = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root ([string]$runnerRow.sha256)) 'candidate archive semantic runner object' 16777216
    $runnerResult = ConvertFrom-RimePimeCandidateArchiveJsonBytes $runnerObject.Data.Bytes 'candidate archive semantic runner result'
    $null = Assert-RimePimeCandidateArchiveRunnerResult $runnerResult
    $runnerSourceSidecar = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root ([string]$runnerSidecarRow.sha256)) `
        'candidate archive semantic runner source-sidecar object' 256
    $expectedRunnerMarker = [string]$runnerRow.sha256+'  '+[IO.Path]::GetFileName([string]$runnerRow.source_relative_path)+"`n"
    if ([Text.Encoding]::ASCII.GetString($runnerSourceSidecar.Data.Bytes) -cne $expectedRunnerMarker) {
        throw 'Candidate archive runner source-sidecar object does not bind the runner object.'
    }
    $receiptObject = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root ([string]$receiptRow.sha256)) 'candidate archive semantic receipt object' 16777216
    $receipt = ConvertFrom-RimePimeCandidateArchiveJsonBytes $receiptObject.Data.Bytes 'candidate archive semantic retained receipt'
    $null = Assert-RimePimeCandidateArchiveReceipt $receipt $runnerResult.evidence
    $receiptSourceSidecar = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root ([string]$receiptSidecarRow.sha256)) `
        'candidate archive semantic receipt source-sidecar object' 256
    $expectedReceiptMarker = [string]$receiptRow.sha256+'  '+[IO.Path]::GetFileName(([string]$receiptRow.source_relative_path).Replace('/','\'))+"`n"
    if ([Text.Encoding]::ASCII.GetString($receiptSourceSidecar.Data.Bytes) -cne $expectedReceiptMarker) {
        throw 'Candidate archive receipt source-sidecar object does not bind the receipt object.'
    }
    if ([string]$runnerResult.source.exact_head -cne [string]$manifest.source_head -or
        [string]$runnerResult.source.exact_tree -cne [string]$manifest.source_tree -or
        [string]$runnerResult.source.runner_head_blob -cne [string]$manifest.runner_head_blob -or
        [string]$runnerResult.source.runner_worktree_blob -cne [string]$manifest.runner_worktree_blob -or
        [string]$runnerResult.evidence.clone_current_version -cne [string]$manifest.product_version -or
        [string]$runnerResult.evidence.installer.path -cne [string]$manifest.installer_source_relative_path -or
        [string]$runnerResult.evidence.installer.sha256 -cne [string]$manifest.installer_sha256 -or
        [long]$runnerResult.evidence.installer.bytes -ne [long]$manifest.installer_bytes -or
        [string]$runnerResult.evidence.durable_v2_receipt.path -cne [string]$manifest.retained_receipt_path -or
        [string]$runnerResult.evidence.durable_v2_receipt.sha256 -cne [string]$manifest.retained_receipt_sha256 -or
        [string]$runnerResult.evidence.build_result.schema_version -cne [string]$manifest.build_evidence_schema -or
        [string]$receipt.product_version -cne [string]$manifest.product_version -or
        [string]$receipt.installer.path -cne [string]$manifest.installer_path -or
        [string]$receipt.installer.sha256 -cne [string]$manifest.installer_sha256 -or
        [long]$receipt.installer.bytes -ne [long]$manifest.installer_bytes -or
        [string]$receipt.disabled_build.schema_version -cne [string]$manifest.build_evidence_schema) {
        throw 'Candidate archive semantic runner, receipt, and manifest bindings differ.'
    }
    $headSeal = Read-RimePimeCandidateArchiveSealedArchiveFile (Join-Path $root 'head.json') 'candidate archive head' 1048576 -Json
    $expectedHead = New-RimePimeCandidateArchiveHeadFromRoot $owner
    $expectedHeadBytes = ConvertTo-RimePimeCandidateArchiveBytes $expectedHead
    if ($headSeal.Data.Sha256 -cne [string]$owner.head_sha256 -or
        -not(Test-RimePimeCandidateArchiveBytesEqual $headSeal.Data.Bytes $expectedHeadBytes)) {
        throw 'Candidate archive head differs from its root-bound deterministic value.'
    }
    $headObject = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $root $headSeal.Data.Sha256) 'candidate archive head object' 1048576
    if ($headObject.Data.Sha256 -cne $headSeal.Data.Sha256 -or
        -not(Test-RimePimeCandidateArchiveBytesEqual $headObject.Data.Bytes $headSeal.Data.Bytes)) {
        throw 'Candidate archive named head differs from its content-addressed object.'
    }
    $null = $expectedDigests.Add($headSeal.Data.Sha256)

    $intentSeal = Read-RimePimeCandidateArchiveSealedArchiveFile (Join-Path $root 'transactions\intent.json') 'candidate archive intent' 1048576 -Json
    $intent = $intentSeal.Value
    Assert-RimePimeExactProperties $intent @(
        'schema_version','archive_id','operation_id','manifest_sha256','head_sha256','runner_result_sha256',
        'retained_receipt_sha256','post_intent_roll_forward_only','actual_archive_root_published',
        'actual_canonical_migration_admitted','actual_canonical_migrated','hardware_power_loss_verified',
        'directory_metadata_durability_verified','active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive intent'
    if ($intent.schema_version -isnot [string] -or
        [string]$intent.schema_version -cne $script:RimePimeCandidateArchiveIntentSchema -or
        $intent.post_intent_roll_forward_only -isnot [bool] -or -not[bool]$intent.post_intent_roll_forward_only) {
        throw 'Candidate archive intent is invalid.'
    }
    foreach ($name in @('archive_id','operation_id','manifest_sha256','head_sha256','runner_result_sha256','retained_receipt_sha256')) {
        if (-not(Test-RimePimeCandidateArchiveDigest $intent.$name)) { throw 'Candidate archive intent identity type is invalid.' }
        if ([string]$intent.$name -cne [string]$owner.$name) { throw 'Candidate archive intent differs from root ownership.' }
    }
    Assert-RimePimeCandidateArchiveFalseFlags $intent @(
        'actual_archive_root_published','actual_canonical_migration_admitted','actual_canonical_migrated',
        'hardware_power_loss_verified','directory_metadata_durability_verified','active_hostile_same_sid_physical_replacement_prevented'
    ) 'candidate archive intent'

    $completionSeal = Read-RimePimeCandidateArchiveSealedArchiveFile (Join-Path $root 'transactions\completed.json') 'candidate archive completion' 1048576 -Json
    $completion = $completionSeal.Value
    $expectedCompletion = New-RimePimeCandidateArchiveCompletionFromRoot $owner
    if (-not(Test-RimePimeCandidateArchiveBytesEqual $completionSeal.Data.Bytes (ConvertTo-RimePimeCandidateArchiveBytes $expectedCompletion))) {
        throw 'Candidate archive completion differs from its deterministic root binding.'
    }

    $rootExpected = @('archive-root.json','archive-root.json.sha256','head.json','head.json.sha256',
        'manifest.json','manifest.json.sha256','objects','transactions')
    $rootActual = @(Get-ChildItem -LiteralPath $root -Force | ForEach-Object { [string]$_.Name } | Sort-Object)
    $rootExpected = @($rootExpected | Sort-Object)
    if (($rootActual -join "`n") -cne ($rootExpected -join "`n")) {
        throw 'Candidate archive root physical member set is not exact.'
    }
    $transactionRoot = Assert-RimePimeCandidateArchiveDirectory (Join-Path $root 'transactions') 'candidate archive transaction records'
    $transactionExpected = @('completed.json','completed.json.sha256','intent.json','intent.json.sha256') | Sort-Object
    $transactionActual = @(Get-ChildItem -LiteralPath $transactionRoot -Force | ForEach-Object { [string]$_.Name } | Sort-Object)
    if (($transactionActual -join "`n") -cne ($transactionExpected -join "`n")) {
        throw 'Candidate archive transaction physical member set is not exact.'
    }
    $objectsContainer = Assert-RimePimeCandidateArchiveDirectory (Join-Path $root 'objects') 'candidate archive objects container'
    $objectContainerMembers = @(Get-ChildItem -LiteralPath $objectsContainer -Force)
    if ($objectContainerMembers.Count -ne 1 -or -not $objectContainerMembers[0].PSIsContainer -or
        [string]$objectContainerMembers[0].Name -cne 'sha256') {
        throw 'Candidate archive objects container physical member set is not exact.'
    }
    $objectsRoot = Assert-RimePimeCandidateArchiveDirectory (Join-Path $root 'objects\sha256') 'candidate archive object store'
    $expectedObjectLeaves = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expectedObjectPrefixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($digest in $expectedDigests) {
        $null = $expectedObjectPrefixes.Add($digest.Substring(0,2))
        $null = $expectedObjectLeaves.Add($digest.Substring(0,2)+'\'+$digest+'.blob')
        $null = $expectedObjectLeaves.Add($digest.Substring(0,2)+'\'+$digest+'.blob.sha256')
    }
    $actualObjectLeaves = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @(Get-ChildItem -LiteralPath $objectsRoot -Force)) {
        if (-not $entry.PSIsContainer -or $entry.Name -cnotmatch '^[0-9a-f]{2}$') { throw 'Candidate archive object store contains an unexpected prefix.' }
        if (-not $expectedObjectPrefixes.Contains([string]$entry.Name)) { throw 'Candidate archive object store contains an unneeded prefix.' }
        foreach ($leaf in @(Get-ChildItem -LiteralPath $entry.FullName -Force)) {
            if ($leaf.PSIsContainer) { throw 'Candidate archive object prefix contains a directory.' }
            if ($leaf.Name -cmatch '^([0-9a-f]{64})\.blob$') {
                if (-not $expectedDigests.Contains([string]$Matches[1])) { throw 'Candidate archive object store contains an unmanifested object.' }
            } elseif ($leaf.Name -cmatch '^([0-9a-f]{64})\.blob\.sha256$') {
                if (-not $expectedDigests.Contains([string]$Matches[1])) { throw 'Candidate archive object store contains an unmanifested sidecar.' }
            } else { throw 'Candidate archive object store contains an unexpected leaf.' }
            $null = $actualObjectLeaves.Add($entry.Name+'\'+$leaf.Name)
        }
    }
    $actualObjectPrefixes = @(Get-ChildItem -LiteralPath $objectsRoot -Directory -Force | ForEach-Object { [string]$_.Name })
    if ($actualObjectPrefixes.Count -ne $expectedObjectPrefixes.Count) {
        throw 'Candidate archive object prefix member set is not exact.'
    }
    if ($actualObjectLeaves.Count -ne $expectedObjectLeaves.Count) { throw 'Candidate archive object physical member set is not exact.' }
    foreach ($leaf in $expectedObjectLeaves) {
        if (-not $actualObjectLeaves.Contains($leaf)) { throw 'Candidate archive object physical member set is incomplete.' }
    }
    return [pscustomobject][ordered]@{
        status='fixture-archive-complete';archive_root=$root;archive_id=[string]$owner.archive_id
        operation_id=[string]$owner.operation_id;manifest_sha256=$manifestSeal.Data.Sha256
        head_sha256=$headSeal.Data.Sha256;runner_result_sha256=[string]$owner.runner_result_sha256
        retained_receipt_sha256=[string]$owner.retained_receipt_sha256;artifact_count=[int]$manifest.artifact_count
        fixture_sibling_archive_protocol_passed=$true;source_outer_tmp_required=$false
        actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
}

function Get-RimePimeCandidateArchiveStages {
    param([Parameter(Mandatory)]$Context)
    $stages = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Get-ChildItem -LiteralPath $Context.case_root -Force)) {
        if ($entry.Name -clike '.rpa-*') {
            if (-not $entry.PSIsContainer -or $entry.Name -cnotmatch '^\.rpa-[0-9a-f]{16}\.staged$') {
                throw 'Candidate archive fixture contains a foreign transaction stage.'
            }
            $null = Assert-RimePimeCandidateArchiveDirectory $entry.FullName 'candidate archive transaction stage'
            $stages.Add([IO.Path]::GetFullPath($entry.FullName).TrimEnd('\'))
        }
    }
    return @($stages)
}

function New-RimePimeCandidateArchiveIntentFromRoot {
    param([Parameter(Mandatory)]$RootMarker)
    return [pscustomobject][ordered]@{
        schema_version=$script:RimePimeCandidateArchiveIntentSchema;archive_id=[string]$RootMarker.archive_id
        operation_id=[string]$RootMarker.operation_id;manifest_sha256=[string]$RootMarker.manifest_sha256
        head_sha256=[string]$RootMarker.head_sha256;runner_result_sha256=[string]$RootMarker.runner_result_sha256
        retained_receipt_sha256=[string]$RootMarker.retained_receipt_sha256;post_intent_roll_forward_only=$true
        actual_archive_root_published=$false;actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
    }
}

function Read-RimePimeCandidateArchiveIntentStage {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$StageRoot)
    $stage = Assert-RimePimeCandidateArchiveDirectory $StageRoot 'candidate archive intent stage'
    if ((Split-Path -Parent $stage) -ine [string]$Context.case_root -or
        (Split-Path -Leaf $stage) -cnotmatch '^\.rpa-([0-9a-f]{16})\.staged$') {
        throw 'Candidate archive intent stage is outside its owned fixture case.'
    }
    $stageOperationPrefix = [string]$Matches[1]
    $owner = Read-RimePimeCandidateArchiveRootMarker $stage
    if ([string]$owner.operation_id.Substring(0,16) -cne $stageOperationPrefix) { throw 'Candidate archive stage name and ownership operation differ.' }

    $manifestSeal = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Join-Path $stage 'manifest.json') 'candidate archive intent-stage manifest' 16777216 -Json
    $manifest = Assert-RimePimeCandidateArchiveManifest $manifestSeal.Value
    if ($manifestSeal.Data.Sha256 -cne [string]$owner.manifest_sha256 -or
        [string]$manifest.archive_id -cne [string]$owner.archive_id -or
        [string]$manifest.source_runner_result_sha256 -cne [string]$owner.runner_result_sha256 -or
        [string]$manifest.retained_receipt_sha256 -cne [string]$owner.retained_receipt_sha256) {
        throw 'Candidate archive intent stage has divergent ownership and manifest identities.'
    }
    $manifestObject = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Get-RimePimeCandidateArchiveObjectPath $stage $manifestSeal.Data.Sha256) `
        'candidate archive intent-stage manifest object' 16777216
    if ($manifestObject.Data.Sha256 -cne $manifestSeal.Data.Sha256 -or
        -not(Test-RimePimeCandidateArchiveBytesEqual $manifestObject.Data.Bytes $manifestSeal.Data.Bytes)) {
        throw 'Candidate archive intent-stage manifest object differs.'
    }
    foreach ($row in @($manifest.artifacts)) {
        $object = Read-RimePimeCandidateArchiveSealedArchiveFile `
            (Get-RimePimeCandidateArchiveObjectPath $stage ([string]$row.sha256)) `
            "candidate archive intent-stage object $($row.ordinal)" 536870912
        if ($object.Data.Sha256 -cne [string]$row.sha256 -or $object.Data.Length -ne [long]$row.bytes) {
            throw 'Candidate archive intent-stage object digest or byte count differs.'
        }
    }

    $expectedHead = New-RimePimeCandidateArchiveHeadFromRoot $owner
    if ((Get-RimePimeCandidateArchiveSha256Bytes (ConvertTo-RimePimeCandidateArchiveBytes $expectedHead)) -cne
        [string]$owner.head_sha256) {
        throw 'Candidate archive intent stage root does not bind its deterministic head.'
    }
    $intentSeal = Read-RimePimeCandidateArchiveSealedArchiveFile `
        (Join-Path $stage 'transactions\intent.json') 'candidate archive intent-stage intent' 1048576 -Json
    $expectedIntent = New-RimePimeCandidateArchiveIntentFromRoot $owner
    if (-not(Test-RimePimeCandidateArchiveBytesEqual $intentSeal.Data.Bytes `
        (ConvertTo-RimePimeCandidateArchiveBytes $expectedIntent))) {
        throw 'Candidate archive intent stage intent differs from its deterministic root binding.'
    }
    return [pscustomobject]@{ Root=$stage;Owner=$owner;Manifest=$manifest }
}

function Initialize-RimePimeCandidateArchiveStage {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Material)
    $stage = Join-Path $Context.case_root ('.rpa-'+[string]$Material.OperationId.Substring(0,16)+'.staged')
    $stages = @(Get-RimePimeCandidateArchiveStages $Context)
    foreach ($other in $stages) {
        if ($other -ine $stage) { throw 'Candidate archive fixture already contains a foreign transaction stage.' }
    }
    if (-not(Test-Path -LiteralPath $stage)) { New-Item -ItemType Directory -Path $stage | Out-Null }
    $null = Assert-RimePimeCandidateArchiveDirectory $stage 'candidate archive transaction stage'
    Ensure-RimePimeCandidateArchiveDirectory (Join-Path $stage 'objects')
    Ensure-RimePimeCandidateArchiveDirectory (Join-Path $stage 'objects\sha256')
    Ensure-RimePimeCandidateArchiveDirectory (Join-Path $stage 'transactions')

    $null = Ensure-RimePimeCandidateArchiveSealedBytes (Join-Path $stage 'archive-root.json') `
        (ConvertTo-RimePimeCandidateArchiveBytes $Material.RootMarker) 'root-marker'
    foreach ($artifact in @($Material.Artifacts)) {
        $null = Ensure-RimePimeCandidateArchiveObject $stage ([byte[]]$artifact.Bytes) 'object'
    }
    $manifestObject = Ensure-RimePimeCandidateArchiveObject $stage ([byte[]]$Material.ManifestBytes) 'manifest-object'
    if ($manifestObject.Sha256 -cne [string]$Material.ManifestDigest) { throw 'Candidate archive manifest object identity changed.' }
    $null = Ensure-RimePimeCandidateArchiveSealedBytes (Join-Path $stage 'manifest.json') `
        ([byte[]]$Material.ManifestBytes) 'manifest'
    Invoke-RimePimeCandidateEvidenceArchiveCheckpoint 'objects'
    $null = Ensure-RimePimeCandidateArchiveSealedBytes (Join-Path $stage 'transactions\intent.json') `
        (ConvertTo-RimePimeCandidateArchiveBytes $Material.Intent) 'intent'
    return $stage
}

function Move-RimePimeCandidateArchiveWritingOrphans {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$OperationId
    )
    if (-not(Test-RimePimeCandidateArchiveDigest $OperationId)) { throw 'Candidate archive orphan quarantine operation is invalid.' }
    $stage = Assert-RimePimeCandidateArchiveDirectory $StageRoot 'candidate archive orphan scan stage'
    $orphans = [Collections.Generic.List[object]]::new()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($stage)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $null = Assert-RimePimeCandidateArchiveDirectory $directory 'candidate archive orphan scan directory'
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($entry.PSIsContainer) {
                $pending.Push([string]$entry.FullName)
            } elseif ($entry.Name -cmatch '^\.writing-[0-9a-f]{32}\.tmp$') {
                $record = Get-YimePimePayloadFileRecord $entry.FullName
                $relative = $entry.FullName.Substring($stage.Length+1).Replace('\','/')
                $identity = [Text.UTF8Encoding]::new($false).GetBytes($relative+"`n"+[string]$record.sha256+"`n"+[string]$record.bytes+"`n")
                $orphans.Add([pscustomobject]@{
                    Path=[string]$entry.FullName
                    QuarantineName=(Get-RimePimeCandidateArchiveSha256Bytes $identity)+'.orphan'
                })
            }
        }
    }
    if ($orphans.Count -eq 0) { return }
    $quarantine = Join-Path $Context.case_root ('.candidate-evidence-archive-quarantine\'+$OperationId.Substring(0,16))
    Ensure-RimePimeCandidateArchiveDirectory (Split-Path -Parent $quarantine)
    Ensure-RimePimeCandidateArchiveDirectory $quarantine
    foreach ($orphan in $orphans) {
        $destination = Join-Path $quarantine ([string]$orphan.QuarantineName)
        Move-RimePimeCandidateArchiveNoReplace ([string]$orphan.Path) $destination
    }
}

function Complete-RimePimeCandidateArchiveStage {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$StageRoot)
    if (Test-Path -LiteralPath $Context.archive_root) {
        throw 'Candidate archive final root already exists; staged replacement is forbidden.'
    }
    $state = Read-RimePimeCandidateArchiveIntentStage $Context $StageRoot
    $headBytes = ConvertTo-RimePimeCandidateArchiveBytes (New-RimePimeCandidateArchiveHeadFromRoot $state.Owner)
    $headObject = Ensure-RimePimeCandidateArchiveObject $state.Root $headBytes 'head-object'
    if ($headObject.Sha256 -cne [string]$state.Owner.head_sha256) { throw 'Candidate archive deterministic head object identity changed.' }
    $null = Ensure-RimePimeCandidateArchiveSealedBytes (Join-Path $state.Root 'head.json') $headBytes 'head'
    $completionBytes = ConvertTo-RimePimeCandidateArchiveBytes (New-RimePimeCandidateArchiveCompletionFromRoot $state.Owner)
    $null = Ensure-RimePimeCandidateArchiveSealedBytes `
        (Join-Path $state.Root 'transactions\completed.json') $completionBytes 'complete'
    Move-RimePimeCandidateArchiveWritingOrphans $Context $state.Root ([string]$state.Owner.operation_id)
    $null = Read-RimePimeCandidateArchiveAtRoot $Context $state.Root -AllowStage
    Invoke-RimePimeCandidateEvidenceArchiveCheckpoint 'before-archive-root'
    Move-RimePimeCandidateArchiveNoReplace $state.Root $Context.archive_root
    Invoke-RimePimeCandidateEvidenceArchiveCheckpoint 'archive-root'
    return Read-RimePimeCandidateArchiveAtRoot $Context $Context.archive_root
}

function Assert-RimePimeCandidateArchiveExpectedResult {
    param([Parameter(Mandatory)]$Status,[string]$ExpectedRunnerResultSha256)
    if ($ExpectedRunnerResultSha256) {
        if (-not(Test-RimePimeCandidateArchiveDigest $ExpectedRunnerResultSha256)) {
            throw 'Expected runner result digest is invalid.'
        }
        if ([string]$Status.runner_result_sha256 -cne $ExpectedRunnerResultSha256) {
            throw 'Existing candidate archive belongs to a different runner result.'
        }
    }
    return $Status
}

function Publish-RimePimeCandidateEvidenceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CaseRoot,
        [Parameter(Mandatory)][string]$ExpectedRunnerResultSha256
    )
    $context = Assert-RimePimeCandidateArchiveCaseRoot $CaseRoot
    if (-not(Test-RimePimeCandidateArchiveDigest $ExpectedRunnerResultSha256)) {
        throw 'Expected runner result digest is invalid.'
    }
    $lock = Open-RimePimeCandidateArchiveLock $context
    try {
        if (Test-Path -LiteralPath $context.archive_root) {
            if (@(Get-RimePimeCandidateArchiveStages $context).Count -ne 0) {
                throw 'Candidate archive final root and transaction stage coexist.'
            }
            return Assert-RimePimeCandidateArchiveExpectedResult `
                (Read-RimePimeCandidateArchiveAtRoot $context $context.archive_root) $ExpectedRunnerResultSha256
        }
        $stages = @(Get-RimePimeCandidateArchiveStages $context)
        if ($stages.Count -gt 1) { throw 'Candidate archive fixture contains multiple transaction stages.' }
        $stageIntent = if ($stages.Count -eq 1) { Join-Path $stages[0] 'transactions\intent.json' } else { $null }
        if ($stages.Count -eq 1 -and (Test-Path -LiteralPath $stageIntent -PathType Leaf) -and
            (Test-Path -LiteralPath ($stageIntent+'.sha256') -PathType Leaf)) {
            $state = Read-RimePimeCandidateArchiveIntentStage $context $stages[0]
            if ([string]$state.Owner.runner_result_sha256 -cne $ExpectedRunnerResultSha256) {
                throw 'Candidate archive intent belongs to a different runner result.'
            }
            return Complete-RimePimeCandidateArchiveStage $context $stages[0]
        }
        $material = Get-RimePimeCandidateArchiveSourceMaterial $context $ExpectedRunnerResultSha256
        $stage = Initialize-RimePimeCandidateArchiveStage $context $material
        return Complete-RimePimeCandidateArchiveStage $context $stage
    } finally { $lock.Dispose() }
}

function Resume-RimePimeCandidateEvidenceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CaseRoot,
        [string]$ExpectedRunnerResultSha256
    )
    $context = Assert-RimePimeCandidateArchiveCaseRoot $CaseRoot
    if ($ExpectedRunnerResultSha256 -and -not(Test-RimePimeCandidateArchiveDigest $ExpectedRunnerResultSha256)) {
        throw 'Expected runner result digest is invalid.'
    }
    $lock = Open-RimePimeCandidateArchiveLock $context -RequireExisting
    try {
        if (Test-Path -LiteralPath $context.archive_root) {
            if (@(Get-RimePimeCandidateArchiveStages $context).Count -ne 0) {
                throw 'Candidate archive final root and transaction stage coexist.'
            }
            return Assert-RimePimeCandidateArchiveExpectedResult `
                (Read-RimePimeCandidateArchiveAtRoot $context $context.archive_root) $ExpectedRunnerResultSha256
        }
        $stages = @(Get-RimePimeCandidateArchiveStages $context)
        if ($stages.Count -eq 0) {
            if (-not $ExpectedRunnerResultSha256) {
                throw 'Candidate archive resume without a stage needs the expected runner result digest.'
            }
            $material = Get-RimePimeCandidateArchiveSourceMaterial $context $ExpectedRunnerResultSha256
            $stage = Initialize-RimePimeCandidateArchiveStage $context $material
            return Complete-RimePimeCandidateArchiveStage $context $stage
        }
        if ($stages.Count -ne 1) { throw 'Candidate archive resume requires at most one owned transaction stage.' }
        $stage = $stages[0]
        $stageIntent = Join-Path $stage 'transactions\intent.json'
        if ((Test-Path -LiteralPath $stageIntent -PathType Leaf) -and
            (Test-Path -LiteralPath ($stageIntent+'.sha256') -PathType Leaf)) {
            $state = Read-RimePimeCandidateArchiveIntentStage $context $stage
            if ($ExpectedRunnerResultSha256 -and
                [string]$state.Owner.runner_result_sha256 -cne $ExpectedRunnerResultSha256) {
                throw 'Candidate archive intent belongs to a different runner result.'
            }
            return Complete-RimePimeCandidateArchiveStage $context $stage
        }
        $ownerPath = Join-Path $stage 'archive-root.json'
        if (-not(Test-Path -LiteralPath $ownerPath)) {
            if (-not $ExpectedRunnerResultSha256) {
                throw 'Pre-intent candidate archive stage needs the expected runner result digest.'
            }
            $material = Get-RimePimeCandidateArchiveSourceMaterial $context $ExpectedRunnerResultSha256
        } else {
            $owner = Read-RimePimeCandidateArchiveRootMarker $stage
            if ($ExpectedRunnerResultSha256 -and
                [string]$owner.runner_result_sha256 -cne $ExpectedRunnerResultSha256) {
                throw 'Candidate archive pre-intent stage belongs to a different runner result.'
            }
            $material = Get-RimePimeCandidateArchiveSourceMaterial $context ([string]$owner.runner_result_sha256)
            if ([string]$material.OperationId -cne [string]$owner.operation_id) {
                throw 'Candidate archive source changed before durable intent.'
            }
        }
        $stage = Initialize-RimePimeCandidateArchiveStage $context $material
        return Complete-RimePimeCandidateArchiveStage $context $stage
    } finally { $lock.Dispose() }
}

function Read-RimePimeCandidateEvidenceArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaseRoot)
    $context = Assert-RimePimeCandidateArchiveCaseRoot $CaseRoot
    $lock = Open-RimePimeCandidateArchiveLock $context -RequireExisting
    try {
        if (-not(Test-Path -LiteralPath $context.archive_root -PathType Container)) {
            throw 'Candidate evidence archive is not committed.'
        }
        if (@(Get-RimePimeCandidateArchiveStages $context).Count -ne 0) {
            throw 'Candidate archive final root and transaction stage coexist.'
        }
        return Read-RimePimeCandidateArchiveAtRoot $context $context.archive_root
    } finally { $lock.Dispose() }
}
