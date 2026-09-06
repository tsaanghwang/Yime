# Rime/PIME exact payload-closure helpers. Definitions only; no action on import.
# The caller must supply a trusted manifest that is independent of InstallRoot.
$script:YimePimePayloadSchema = 'yime-rime-pime-install-payload-v1'

function ConvertTo-YimePimeCanonicalPayloadPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or
        [IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or
        $Path.StartsWith('/') -or $Path.EndsWith('/') -or $Path.Contains('//') -or
        $Path -match '[\x00-\x1f<>:"|?*]' -or
        -not $Path.IsNormalized([Text.NormalizationForm]::FormC)) {
        throw "Non-canonical payload path rejected: $Path"
    }
    foreach ($segment in $Path.Split('/')) {
        if (-not $segment -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Ambiguous payload path segment rejected: $Path"
        }
    }
    return $Path
}

function Assert-YimePimePayloadProperties {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Context)
    if ($null -eq $Value -or $Value -is [string] -or $null -eq $Value.PSObject) {
        throw "$Context must be a JSON object."
    }
    $actual=@($Value.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $Expected.Count) {
        throw "$Context has an open or incomplete schema."
    }
    foreach ($name in $Expected) {
        if ($actual -cnotcontains $name) { throw "$Context is missing exact property $name." }
    }
}

function Assert-YimePimePayloadAbsolutePath {
    param([Parameter(Mandatory)][string]$Path,[switch]$AllowVolumeRoot)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or
        $Path -match '[/<>|"?*]|(^|\\)\.\.?($|\\)|[. ]($|\\)' -or
        $Path.Substring(2).Contains(':')) {
        throw 'Payload closure requires a canonical local absolute path.'
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $AllowVolumeRoot -and $full.Length -le 3) { throw 'A volume root is not a payload root.' }
    foreach ($segment in $full.Substring(3).Split('\')) {
        if ($segment -and $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'Device-name path rejected.'
        }
    }
    for ($cursor=$full; $cursor; $cursor=Split-Path -Parent $cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse path rejected: $cursor"
            }
        }
        if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
    }
    return $full
}

function Initialize-YimePimePayloadNativeInspection {
    if ($null -ne ('YimePime.Payload.NativeInspection' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace YimePime.Payload {
    public sealed class FileIdentity {
        public long Length { get; set; }
        public uint LinkCount { get; set; }
        public string FileId { get; set; }
        public string[] Streams { get; set; }
    }

    public static class NativeInspection {
        private const uint FILE_READ_ATTRIBUTES = 0x0080;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private static readonly IntPtr InvalidHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME {
            public uint Low;
            public uint High;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION {
            public uint FileAttributes;
            public FILETIME CreationTime;
            public FILETIME LastAccessTime;
            public FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        private enum STREAM_INFO_LEVELS {
            FindStreamInfoStandard = 0
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WIN32_FIND_STREAM_DATA {
            public long StreamSize;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)]
            public string StreamName;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess,
            uint shareMode, IntPtr securityAttributes, uint creationDisposition,
            uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file,
            out BY_HANDLE_FILE_INFORMATION information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstStreamW(string fileName, STREAM_INFO_LEVELS level,
            out WIN32_FIND_STREAM_DATA data, uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindNextStreamW(IntPtr find, out WIN32_FIND_STREAM_DATA data);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindClose(IntPtr find);

        public static FileIdentity Inspect(string path) {
            BY_HANDLE_FILE_INFORMATION info;
            using (SafeFileHandle handle = CreateFileW(path, FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
                OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (!GetFileInformationByHandle(handle, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            var streams = new List<string>();
            WIN32_FIND_STREAM_DATA stream;
            IntPtr find = FindFirstStreamW(path, STREAM_INFO_LEVELS.FindStreamInfoStandard,
                out stream, 0);
            if (find == InvalidHandle) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                streams.Add(stream.StreamName);
                while (FindNextStreamW(find, out stream)) streams.Add(stream.StreamName);
                int error = Marshal.GetLastWin32Error();
                if (error != 38) throw new Win32Exception(error); // ERROR_HANDLE_EOF
            } finally {
                FindClose(find);
            }

            long length = ((long)info.FileSizeHigh << 32) | info.FileSizeLow;
            return new FileIdentity {
                Length = length,
                LinkCount = info.NumberOfLinks,
                FileId = String.Format("{0:x8}:{1:x8}{2:x8}", info.VolumeSerialNumber,
                    info.FileIndexHigh, info.FileIndexLow),
                Streams = streams.ToArray()
            };
        }
    }
}
'@
}

function Get-YimePimePayloadFileRecord {
    param([Parameter(Mandatory)][string]$Path)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Payload file is missing: $full" }
    $item=Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse file rejected: $full" }
    Initialize-YimePimePayloadNativeInspection
    $before=[YimePime.Payload.NativeInspection]::Inspect($full)
    if ($before.LinkCount -ne 1) { throw "Hard-linked payload file rejected: $full" }
    if (@($before.Streams).Count -ne 1 -or [string]$before.Streams[0] -cne '::$DATA') {
        throw "Alternate data stream rejected: $full"
    }
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
    $after=[YimePime.Payload.NativeInspection]::Inspect($full)
    if ($after.LinkCount -ne 1 -or @($after.Streams).Count -ne 1 -or
        [string]$after.Streams[0] -cne '::$DATA' -or $before.FileId -cne $after.FileId -or
        $before.Length -ne $after.Length) {
        throw "Payload file identity changed while hashing: $full"
    }
    return [pscustomobject][ordered]@{
        bytes=[long]$after.Length
        sha256=$hash
        file_id=[string]$after.FileId
        link_count=[uint32]$after.LinkCount
        streams=@($after.Streams)
    }
}

function Read-YimePimePayloadManifest {
    param([Parameter(Mandatory)][string]$Path)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'Trusted payload manifest is missing.' }
    if ((Get-Item -LiteralPath $full).Length -gt 16777216) { throw 'Payload manifest is too large.' }
    try { $manifest=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Invalid payload manifest JSON: $($_.Exception.Message)" }
    Assert-YimePimePayloadProperties $manifest @(
        'schema_version','product','product_version','architectures','manifest_path','special_files','files') 'manifest'
    if ([string]$manifest.schema_version -cne $script:YimePimePayloadSchema -or
        [string]$manifest.product -cne 'rime-pime' -or
        [string]$manifest.product_version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$') {
        throw 'Payload manifest identity is invalid.'
    }
    $architectures=@($manifest.architectures)
    if ($architectures.Count -ne 2 -or [string]$architectures[0] -cne 'x86' -or
        [string]$architectures[1] -notin @('x64','arm64x')) {
        throw 'Payload manifest architecture set is not an admitted host pair.'
    }
    $manifestPath=ConvertTo-YimePimeCanonicalPayloadPath ([string]$manifest.manifest_path)
    $specialFiles=@($manifest.special_files)
    if ($specialFiles.Count -ne 1) { throw 'Payload manifest requires exactly one separately verified special uninstaller.' }
    Assert-YimePimePayloadProperties $specialFiles[0] @('path','identity_class') 'manifest special file record'
    $specialPath=ConvertTo-YimePimeCanonicalPayloadPath ([string]$specialFiles[0].path)
    if ($specialPath -cne 'Uninstall.exe' -or
        [string]$specialFiles[0].identity_class -cne 'signed-self-image-v1') {
        throw 'Payload manifest special uninstaller identity is invalid.'
    }
    $files=@($manifest.files)
    if ($files.Count -eq 0) { throw 'Payload manifest cannot be empty.' }
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null=$paths.Add($manifestPath)
    if (-not $paths.Add($specialPath)) { throw 'Special uninstaller collides with the manifest path.' }
    $previous=$null
    foreach ($row in $files) {
        Assert-YimePimePayloadProperties $row @('path','bytes','sha256','owner_class','architecture') 'manifest file record'
        $relative=ConvertTo-YimePimeCanonicalPayloadPath ([string]$row.path)
        if ($relative -ieq 'Uninstall.exe') {
            throw 'Uninstall.exe requires a separately sealed self-identity contract; it cannot be an ordinary manifest row.'
        }
        if (-not $paths.Add($relative)) { throw "Case-folded duplicate payload path rejected: $relative" }
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$relative) -ge 0) {
            throw 'Payload manifest files are not in canonical ordinal order.'
        }
        $previous=$relative
        if (-not ($row.bytes -is [int] -or $row.bytes -is [long]) -or [long]$row.bytes -lt 0 -or
            [string]$row.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Invalid payload size or SHA-256: $relative"
        }
        if ([string]$row.owner_class -notin @('metadata','license','runtime','backend','text-service','font','maintenance') -or
            ([string]$row.architecture -cne 'neutral' -and $architectures -cnotcontains [string]$row.architecture)) {
            throw "Invalid payload ownership or architecture: $relative"
        }
    }
    return $manifest
}

function Get-YimePimePayloadClosedTreeSnapshot {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$TrustedManifestRecord,
        [Parameter(Mandatory)][object[]]$VerifiedSpecialFiles)
    $root=Assert-YimePimePayloadAbsolutePath $InstallRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Payload root is absent.' }
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($Manifest.files)) { $expected.Add([string]$row.path,$row) }
    $manifestRow=[pscustomobject][ordered]@{
        path=[string]$Manifest.manifest_path
        bytes=[long]$TrustedManifestRecord.bytes
        sha256=[string]$TrustedManifestRecord.sha256
        owner_class='metadata'
        architecture='neutral'
    }
    $expected.Add([string]$Manifest.manifest_path,$manifestRow)
    if (@($VerifiedSpecialFiles).Count -ne 1) {
        throw 'Exactly one independently verified special-file record is required.'
    }
    $special=$VerifiedSpecialFiles[0]
    Assert-YimePimePayloadProperties $special @('path','bytes','sha256','trust_class') 'verified special file record'
    if ([string]$special.path -cne [string]$Manifest.special_files[0].path -or
        [string]$special.trust_class -cne 'authenticode-product-self-image-v1' -or
        -not ($special.bytes -is [int] -or $special.bytes -is [long]) -or [long]$special.bytes -lt 0 -or
        [string]$special.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Verified special uninstaller record is invalid.'
    }
    $specialRow=[pscustomobject][ordered]@{
        path=[string]$special.path;bytes=[long]$special.bytes;sha256=[string]$special.sha256
        owner_class='maintenance';architecture='neutral'
    }
    $expected.Add([string]$special.path,$specialRow)

    $expectedDirs=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in @($expected.Keys)) {
        $slash=$relative.LastIndexOf('/')
        while ($slash -gt 0) {
            $parent=$relative.Substring(0,$slash)
            if ($expected.ContainsKey($parent)) { throw "Payload file/directory type conflict: $parent" }
            if ($expectedDirs.ContainsKey($parent)) {
                if ($expectedDirs[$parent] -cne $parent) { throw "Case-folded directory collision: $parent" }
            } else { $expectedDirs.Add($parent,$parent) }
            $slash=$parent.LastIndexOf('/')
        }
    }

    $pending=[Collections.Generic.Stack[string]]::new(); $pending.Push($root)
    $actualFiles=[Collections.Generic.List[object]]::new()
    $actualDirs=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $fileIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($pending.Count) {
        $directory=$pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Indirect payload entry rejected: $($item.FullName)"
            }
            $relative=$item.FullName.Substring($root.Length+1).Replace('\','/')
            $relative=ConvertTo-YimePimeCanonicalPayloadPath $relative
            if ($item.PSIsContainer) {
                if ($expected.ContainsKey($relative)) { throw "Payload file became a directory: $relative" }
                if (-not $expectedDirs.ContainsKey($relative) -or $expectedDirs[$relative] -cne $relative) {
                    throw "Unlisted or case-mismatched payload directory: $relative"
                }
                $actualDirs.Add($relative,$relative)
                $pending.Push($item.FullName)
                continue
            }
            if (-not $expected.ContainsKey($relative)) { throw "Unlisted payload file: $relative" }
            $wanted=$expected[$relative]
            if ([string]$wanted.path -cne $relative) { throw "Payload path case mismatch: $relative" }
            $record=Get-YimePimePayloadFileRecord $item.FullName
            if ([long]$wanted.bytes -ne [long]$record.bytes -or
                [string]$wanted.sha256 -cne [string]$record.sha256) {
                throw "Payload content mismatch: $relative"
            }
            if (-not $fileIds.Add([string]$record.file_id)) { throw "Duplicate payload file identity: $relative" }
            $actualFiles.Add([pscustomobject][ordered]@{
                path=$relative;bytes=[long]$record.bytes;sha256=[string]$record.sha256
                file_id=[string]$record.file_id
            })
        }
    }
    if ($actualFiles.Count -ne $expected.Count) { throw 'Payload tree has missing files.' }
    if ($actualDirs.Count -ne $expectedDirs.Count) { throw 'Payload tree has missing or extra directories.' }
    return [pscustomobject][ordered]@{
        files=@($actualFiles | Sort-Object path -CaseSensitive)
        directories=@($actualDirs.Values | Sort-Object -CaseSensitive)
    }
}

function Test-YimePimePayloadClosure {
    param([Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$TrustedManifestPath,
        [Parameter(Mandatory)][string]$InstalledManifestPath,
        [Parameter(Mandatory)][object[]]$VerifiedSpecialFiles,
        [scriptblock]$BetweenPassHook)
    $root=Assert-YimePimePayloadAbsolutePath $InstallRoot
    $trusted=Assert-YimePimePayloadAbsolutePath $TrustedManifestPath
    if ($trusted.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Trusted manifest must be independent of the installed payload root.'
    }
    $manifest=Read-YimePimePayloadManifest $trusted
    $installed=Assert-YimePimePayloadAbsolutePath $InstalledManifestPath
    $expectedInstalled=[IO.Path]::GetFullPath((Join-Path $root ([string]$manifest.manifest_path).Replace('/','\')))
    if ($installed -ine $expectedInstalled) { throw 'Installed manifest path does not match the trusted contract.' }
    $trustedRecord=Get-YimePimePayloadFileRecord $trusted
    $installedRecord=Get-YimePimePayloadFileRecord $installed
    if ($trustedRecord.bytes -ne $installedRecord.bytes -or
        $trustedRecord.sha256 -cne $installedRecord.sha256) {
        throw 'Installed manifest bytes do not match the trusted manifest.'
    }
    $first=Get-YimePimePayloadClosedTreeSnapshot $root $manifest $trustedRecord $VerifiedSpecialFiles
    if ($null -ne $BetweenPassHook) { & $BetweenPassHook $root }
    $second=Get-YimePimePayloadClosedTreeSnapshot $root $manifest $trustedRecord $VerifiedSpecialFiles
    $firstJson=ConvertTo-Json $first -Depth 8 -Compress
    $secondJson=ConvertTo-Json $second -Depth 8 -Compress
    if ($firstJson -cne $secondJson) { throw 'Payload identity changed between closure passes.' }
    $digestBytes=[Text.Encoding]::UTF8.GetBytes($secondJson)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $digest=([BitConverter]::ToString($sha.ComputeHash($digestBytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject][ordered]@{
        passed=$true
        schema_version=$script:YimePimePayloadSchema
        manifest_sha256=[string]$trustedRecord.sha256
        file_count=@($second.files).Count
        directory_count=@($second.directories).Count
        closed_tree_sha256=$digest
        actual_install_or_removal_executed=$false
    }
}
