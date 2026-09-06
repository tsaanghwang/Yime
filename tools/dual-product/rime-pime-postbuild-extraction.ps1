# Static post-build extraction verification for the staged Rime/PIME package.
# Definitions only.  The only process this module may start is an explicitly
# pinned 7-Zip extractor; it never starts the installer or generated uninstaller.
$script:RimePimePostbuildSchema = 'yime-rime-pime-postbuild-extraction-v1'
$script:RimePimePostbuildToolchainLockFile = 'rime-pime-postbuild-toolchain-lock.json'
$script:RimePimePostbuildToolchainLockSha256 = '01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45'
$script:RimePimePostbuildToolchainLockSchema = 'yime-rime-pime-postbuild-toolchain-lock-v2'
$script:RimePimePostbuildDirectoryLeaseTypeInitialized = $false
$script:RimePimePostbuildTopSupport = @(
    [pscustomobject][ordered]@{archive_path='$PLUGINSDIR/modern-wizard.bmp';origin_path='Contrib/Graphics/Wizard/win.bmp'},
    [pscustomobject][ordered]@{archive_path='$PLUGINSDIR/LangDLL.dll';origin_path='Plugins/x86-unicode/LangDLL.dll'},
    [pscustomobject][ordered]@{archive_path='$PLUGINSDIR/nsDialogs.dll';origin_path='Plugins/x86-unicode/nsDialogs.dll'},
    [pscustomobject][ordered]@{archive_path='$PLUGINSDIR/nsExec.dll';origin_path='Plugins/x86-unicode/nsExec.dll'},
    [pscustomobject][ordered]@{archive_path='$PLUGINSDIR/System.dll';origin_path='Plugins/x86-unicode/System.dll'}
)
$script:RimePimePostbuildUninstallerSupportNames = @('nsExec.dll','System.dll')

function ConvertTo-RimePimePostbuildArchivePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or
        [IO.Path]::IsPathRooted($Path) -or $Path.Contains('/') -or
        $Path.StartsWith('\\') -or $Path.EndsWith('\') -or $Path.Contains('\\') -or
        $Path -match '[\x00-\x1f<>:"|?*]' -or
        -not $Path.IsNormalized([Text.NormalizationForm]::FormC)) {
        throw "Non-canonical archive path rejected: $Path"
    }
    $segments=$Path.Split('\')
    if ($segments.Count -gt 16) { throw "Archive path is too deep: $Path" }
    foreach ($segment in $segments) {
        if (-not $segment -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Ambiguous archive path rejected: $Path"
        }
    }
    return $Path.Replace('\','/')
}

function Get-RimePimePostbuildSha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-RimePimePostbuildLockedAbsolutePath {
    param([Parameter(Mandatory)][string]$Path)
    if($Path -notmatch '^[A-Za-z]:/' -or $Path.Contains('\') -or $Path.Contains('//') -or
        $Path.EndsWith('/') -or -not $Path.IsNormalized([Text.NormalizationForm]::FormC)){
        throw 'Post-build toolchain lock contains a non-canonical absolute path.'
    }
    return Assert-YimePimePayloadAbsolutePath $Path.Replace('/','\')
}

function Test-RimePimePostbuildToolchainLockDocument {
    param([Parameter(Mandatory)]$Value)
    $canonical=(ConvertTo-RimePimeStageCanonicalJson $Value)+"`n"
    if((Get-RimePimePostbuildSha256Text $canonical) -cne $script:RimePimePostbuildToolchainLockSha256){
        throw 'Post-build toolchain lock document is not the code-pinned identity.'
    }
    Assert-YimePimePayloadProperties $Value @(
        'schema_version','toolchain_id','package_profile','seven_zip','nsis') 'post-build toolchain lock'
    Assert-YimePimePayloadProperties $Value.seven_zip @(
        'path','bytes','sha256','file_version','product_version','company_name','library') 'post-build 7-Zip lock'
    Assert-YimePimePayloadProperties $Value.seven_zip.library @(
        'path','bytes','sha256','file_version','product_version','company_name') 'post-build 7-Zip library lock'
    Assert-YimePimePayloadProperties $Value.nsis @('root','makensis','compiler_input_closure','support') 'post-build NSIS lock'
    Assert-YimePimePayloadProperties $Value.nsis.makensis @(
        'relative_path','bytes','sha256') 'post-build makensis lock'
    if([string]$Value.schema_version -cne $script:RimePimePostbuildToolchainLockSchema -or
        [string]$Value.toolchain_id -cne 'mycomputer-rime-pime-nsis-static-x86-x64-v2' -or
        [string]$Value.package_profile -cne 'x86-x64-v1'){
        throw 'Post-build toolchain lock identity or package profile is invalid.'
    }
    $null=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$Value.seven_zip.path)
    $null=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$Value.seven_zip.library.path)
    $null=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$Value.nsis.root)
    foreach($record in @($Value.seven_zip,$Value.seven_zip.library,$Value.nsis.makensis)){
        if(-not(Test-RimePimeStageInteger $record.bytes) -or [long]$record.bytes -lt 1 -or
            [string]$record.sha256 -cnotmatch '^[0-9a-f]{64}$'){
            throw 'Post-build toolchain lock contains an invalid file record.'
        }
    }
    foreach($record in @($Value.seven_zip,$Value.seven_zip.library)){
        if([string]$record.file_version -notmatch '^[0-9]+(?:\.[0-9]+)+$' -or
            [string]$record.product_version -cne [string]$record.file_version -or
            [string]::IsNullOrWhiteSpace([string]$record.company_name)){
            throw 'Post-build 7-Zip VERSIONINFO lock is invalid.'
        }
    }
    $null=Test-RimePimeNsisCompilerToolchainLockDocument $Value
    $makensisRelative=ConvertTo-YimePimeCanonicalPayloadPath ([string]$Value.nsis.makensis.relative_path)
    if($makensisRelative -cne 'Bin/makensis.exe'){
        throw 'Post-build NSIS compiler relative path is invalid.'
    }
    $support=@($Value.nsis.support)
    if($support.Count -ne $script:RimePimePostbuildTopSupport.Count){
        throw 'Post-build NSIS support lock does not contain the fixed exact set.'
    }
    for($i=0;$i -lt $support.Count;$i++){
        Assert-YimePimePayloadProperties $support[$i] @(
            'archive_path','relative_path','bytes','sha256') 'post-build NSIS support lock row'
        $relative=ConvertTo-YimePimeCanonicalPayloadPath ([string]$support[$i].relative_path)
        if([string]$support[$i].archive_path -cne [string]$script:RimePimePostbuildTopSupport[$i].archive_path -or
            $relative -cne [string]$script:RimePimePostbuildTopSupport[$i].origin_path -or
            -not(Test-RimePimeStageInteger $support[$i].bytes) -or [long]$support[$i].bytes -lt 1 -or
            [string]$support[$i].sha256 -cnotmatch '^[0-9a-f]{64}$'){
            throw 'Post-build NSIS support lock row is invalid or reordered.'
        }
    }
    return $true
}

function Assert-RimePimePostbuildLockedFileRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)]$LockRecord,
        [Parameter(Mandatory)][string]$Context
    )
    if([long]$Record.bytes -ne [long]$LockRecord.bytes -or
        [string]$Record.sha256 -cne [string]$LockRecord.sha256){
        throw "$Context differs from its sealed expected file record."
    }
}

function Read-RimePimePostbuildToolchainLockDocument {
    $path=Join-Path $PSScriptRoot $script:RimePimePostbuildToolchainLockFile
    $sealed=Read-RimePimeSealedJson $path 'post-build toolchain lock'
    if([string]$sealed.Digest -cne $script:RimePimePostbuildToolchainLockSha256){
        throw 'Post-build toolchain lock differs from the digest pinned in code.'
    }
    $strictUtf8=[Text.UTF8Encoding]::new($false,$true)
    try{$raw=$strictUtf8.GetString([IO.File]::ReadAllBytes($sealed.Path))}
    catch{throw "Post-build toolchain lock is not strict UTF-8: $($_.Exception.Message)"}
    if($raw -cne ((ConvertTo-RimePimeStageCanonicalJson $sealed.Value)+"`n")){
        throw 'Post-build toolchain lock is not canonical single-line JSON with one LF terminator.'
    }
    $null=Test-RimePimePostbuildToolchainLockDocument $sealed.Value
    return [pscustomobject][ordered]@{
        Path=$sealed.Path;Sidecar=$sealed.Sidecar;Digest=$sealed.Digest;Document=$sealed.Value
    }
}

function Read-RimePimePostbuildToolchainLock {
    $locked=Read-RimePimePostbuildToolchainLockDocument
    $sevenZipPath=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$locked.Document.seven_zip.path)
    $sevenZipLibraryPath=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$locked.Document.seven_zip.library.path)
    $nsisRoot=ConvertTo-RimePimePostbuildLockedAbsolutePath ([string]$locked.Document.nsis.root)
    $makensisPath=Get-RimePimeStageFullPath $nsisRoot ([string]$locked.Document.nsis.makensis.relative_path)
    foreach($candidate in @($sevenZipPath,$sevenZipLibraryPath,$nsisRoot,$makensisPath)){
        Assert-RimePimeNoReparsePath $candidate
    }
    $sevenZipRecord=Get-YimePimePayloadFileRecord $sevenZipPath
    Assert-RimePimePostbuildLockedFileRecord $sevenZipRecord $locked.Document.seven_zip '7-Zip extractor'
    $sevenVersion=(Get-Item -LiteralPath $sevenZipPath).VersionInfo
    if([string]$sevenVersion.FileVersion -cne [string]$locked.Document.seven_zip.file_version -or
        [string]$sevenVersion.ProductVersion -cne [string]$locked.Document.seven_zip.product_version -or
        [string]$sevenVersion.CompanyName -cne [string]$locked.Document.seven_zip.company_name){
        throw '7-Zip VERSIONINFO differs from the repository-pinned toolchain lock.'
    }
    $sevenZipLibraryRecord=Get-YimePimePayloadFileRecord $sevenZipLibraryPath
    Assert-RimePimePostbuildLockedFileRecord $sevenZipLibraryRecord $locked.Document.seven_zip.library '7-Zip parser library'
    $sevenZipLibraryVersion=(Get-Item -LiteralPath $sevenZipLibraryPath).VersionInfo
    if([string]$sevenZipLibraryVersion.FileVersion -cne [string]$locked.Document.seven_zip.library.file_version -or
        [string]$sevenZipLibraryVersion.ProductVersion -cne [string]$locked.Document.seven_zip.library.product_version -or
        [string]$sevenZipLibraryVersion.CompanyName -cne [string]$locked.Document.seven_zip.library.company_name){
        throw '7-Zip parser library VERSIONINFO differs from the repository-pinned toolchain lock.'
    }
    $makensisRecord=Get-YimePimePayloadFileRecord $makensisPath
    Assert-RimePimePostbuildLockedFileRecord $makensisRecord $locked.Document.nsis.makensis 'NSIS compiler'
    $supportRecords=[Collections.Generic.List[object]]::new()
    foreach($support in @($locked.Document.nsis.support)){
        $supportPath=Get-RimePimeStageFullPath $nsisRoot ([string]$support.relative_path)
        $record=Get-YimePimePayloadFileRecord $supportPath
        Assert-RimePimePostbuildLockedFileRecord $record $support "NSIS support input $($support.archive_path)"
        $supportRecords.Add([pscustomobject][ordered]@{
            archive_path=[string]$support.archive_path;origin_path=[string]$support.relative_path
            path=$supportPath;bytes=[long]$record.bytes;sha256=[string]$record.sha256
            file_id=[string]$record.file_id
        })
    }
    return [pscustomobject][ordered]@{
        Path=$locked.Path;Sidecar=$locked.Sidecar;Digest=$locked.Digest;Document=$locked.Document
        SevenZip=[pscustomobject][ordered]@{path=$sevenZipPath;bytes=[long]$sevenZipRecord.bytes;sha256=[string]$sevenZipRecord.sha256;file_id=[string]$sevenZipRecord.file_id}
        SevenZipLibrary=[pscustomobject][ordered]@{path=$sevenZipLibraryPath;bytes=[long]$sevenZipLibraryRecord.bytes;sha256=[string]$sevenZipLibraryRecord.sha256;file_id=[string]$sevenZipLibraryRecord.file_id}
        NsisRoot=$nsisRoot
        Makensis=[pscustomobject][ordered]@{path=$makensisPath;bytes=[long]$makensisRecord.bytes;sha256=[string]$makensisRecord.sha256;file_id=[string]$makensisRecord.file_id}
        Support=@($supportRecords)
    }
}

function Get-RimePimePostbuildLeaseStreamRecord {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek){throw 'Post-build read lease is closed or not seekable.'}
    $position=$Stream.Position
    try{
        $Stream.Position=0
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$digest=([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
        finally{$sha.Dispose()}
        return [pscustomobject][ordered]@{bytes=[long]$Stream.Length;sha256=$digest}
    }finally{$Stream.Position=$position}
}

function Open-RimePimePostbuildReadLease {
    param(
        [Parameter(Mandatory)][string]$Path,
        $ExpectedRecord,
        [Parameter(Mandatory)][string]$Context
    )
    $full=Assert-YimePimePayloadAbsolutePath $Path
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $streamRecord=Get-RimePimePostbuildLeaseStreamRecord $stream
        $pathRecord=Get-YimePimePayloadFileRecord $full
        if([long]$streamRecord.bytes -ne [long]$pathRecord.bytes -or
            [string]$streamRecord.sha256 -cne [string]$pathRecord.sha256){
            throw "$Context path and leased handle differ."
        }
        if($null -ne $ExpectedRecord){
            Assert-RimePimePostbuildLockedFileRecord $pathRecord $ExpectedRecord $Context
        }
        return [pscustomobject][ordered]@{
            Path=$full;Stream=$stream;Context=$Context
            Record=[pscustomobject][ordered]@{bytes=[long]$pathRecord.bytes;sha256=[string]$pathRecord.sha256;file_id=[string]$pathRecord.file_id}
        }
    }catch{$stream.Dispose();throw}
}

function Assert-RimePimePostbuildReadLease {
    param([Parameter(Mandatory)]$Lease)
    if($null -eq $Lease -or $Lease.Stream -isnot [IO.FileStream]){throw 'Post-build read lease object is invalid.'}
    $streamRecord=Get-RimePimePostbuildLeaseStreamRecord $Lease.Stream
    $pathRecord=Get-YimePimePayloadFileRecord ([string]$Lease.Path)
    foreach($name in @('bytes','sha256')){
        if([string]$streamRecord.$name -cne [string]$Lease.Record.$name -or
            [string]$pathRecord.$name -cne [string]$Lease.Record.$name){
            throw "$($Lease.Context) changed while its read lease was held: $name"
        }
    }
    if([string]$pathRecord.file_id -cne [string]$Lease.Record.file_id){
        throw "$($Lease.Context) path identity changed while its read lease was held."
    }
    return $pathRecord
}

function Read-RimePimePostbuildLeaseBytes {
    param([Parameter(Mandatory)]$Lease)
    $null=Assert-RimePimePostbuildReadLease $Lease
    $length=[long]$Lease.Stream.Length
    if($length -lt 1 -or $length -gt 536870912){throw 'Post-build leased file size is outside the 512 MiB bound.'}
    $bytes=New-Object byte[] ([int]$length)
    $Lease.Stream.Position=0;$offset=0
    while($offset -lt $bytes.Length){
        $read=$Lease.Stream.Read($bytes,$offset,$bytes.Length-$offset)
        if($read -le 0){throw 'Post-build leased file ended before its sealed length.'}
        $offset+=$read
    }
    $Lease.Stream.Position=0
    return $bytes
}

function Initialize-RimePimePostbuildDirectoryLeaseType {
    $existing='YimePime.Postbuild.DirectoryLeasesV1' -as [type]
    if($script:RimePimePostbuildDirectoryLeaseTypeInitialized){
        $identityProperty=$existing.GetProperty('ImplementationId',
            [Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)
        if($null -eq $identityProperty -or
            [string]$identityProperty.GetValue($null,$null) -cne 'yime-rime-pime-postbuild-directory-leases-v1'){
            throw 'Loaded post-build directory lease type has an untrusted implementation identity.'
        }
        return
    }
    if($null -ne $existing){
        throw 'A post-build directory lease type was preloaded outside this verified module instance.'
    }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace YimePime.Postbuild {
    [StructLayout(LayoutKind.Sequential)]
    internal struct BY_HANDLE_FILE_INFORMATION {
        internal uint FileAttributes;
        internal uint CreationTimeLow;
        internal uint CreationTimeHigh;
        internal uint LastAccessTimeLow;
        internal uint LastAccessTimeHigh;
        internal uint LastWriteTimeLow;
        internal uint LastWriteTimeHigh;
        internal uint VolumeSerialNumber;
        internal uint FileSizeHigh;
        internal uint FileSizeLow;
        internal uint NumberOfLinks;
        internal uint FileIndexHigh;
        internal uint FileIndexLow;
    }
    public sealed class DirectoryLease : IDisposable {
        public SafeFileHandle Handle { get; private set; }
        public string FileId { get; private set; }
        internal DirectoryLease(SafeFileHandle handle, string fileId) { Handle=handle; FileId=fileId; }
        public void Dispose() { if(Handle != null) Handle.Dispose(); }
    }
    public static class DirectoryLeasesV1 {
        public static string ImplementationId { get { return "yime-rime-pime-postbuild-directory-leases-v1"; } }
        private const uint FILE_LIST_DIRECTORY=1;
        private const uint FILE_SHARE_READ=1;
        private const uint FILE_SHARE_WRITE=2;
        private const uint OPEN_EXISTING=3;
        private const uint FILE_FLAG_BACKUP_SEMANTICS=0x02000000;
        private const uint FILE_ATTRIBUTE_DIRECTORY=0x10;
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
            IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle,
            out BY_HANDLE_FILE_INFORMATION info);
        private static string InspectHandle(SafeFileHandle handle) {
            BY_HANDLE_FILE_INFORMATION info;
            if(!GetFileInformationByHandle(handle,out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)==0) throw new InvalidOperationException("Path is not a directory.");
            return String.Format("{0:x8}:{1:x8}{2:x8}",info.VolumeSerialNumber,info.FileIndexHigh,info.FileIndexLow);
        }
        public static DirectoryLease Open(string path) {
            SafeFileHandle handle=CreateFileW(path,FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,IntPtr.Zero,
                OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,IntPtr.Zero);
            if(handle.IsInvalid) { int error=Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error); }
            try { return new DirectoryLease(handle,InspectHandle(handle)); }
            catch { handle.Dispose(); throw; }
        }
        public static string Inspect(string path) {
            using(DirectoryLease lease=Open(path)) return lease.FileId;
        }
    }
}
'@
    $script:RimePimePostbuildDirectoryLeaseTypeInitialized=$true
}

function Open-RimePimePostbuildDirectoryLease {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    if(-not(Test-Path -LiteralPath $full -PathType Container)){throw "$Context directory is missing."}
    Initialize-RimePimePostbuildDirectoryLeaseType
    $native=[YimePime.Postbuild.DirectoryLeasesV1]::Open($full)
    try{
        Assert-RimePimeNoReparsePath $full
        $item=Get-Item -LiteralPath $full -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$Context directory is a reparse point."}
        $pathId=[YimePime.Postbuild.DirectoryLeasesV1]::Inspect($full)
        if([string]$native.FileId -cne [string]$pathId){throw "$Context directory identity changed while acquiring its lease."}
        return [pscustomobject][ordered]@{Path=$full;Context=$Context;FileId=[string]$native.FileId;Native=$native}
    }catch{$native.Dispose();throw}
}

function Assert-RimePimePostbuildDirectoryLease {
    param([Parameter(Mandatory)]$Lease)
    if($null -eq $Lease -or $null -eq $Lease.Native -or $Lease.Native.Handle.IsClosed){
        throw 'Post-build directory lease object is invalid or closed.'
    }
    $full=Assert-YimePimePayloadAbsolutePath ([string]$Lease.Path)
    if(-not(Test-Path -LiteralPath $full -PathType Container)){throw "$($Lease.Context) directory disappeared while leased."}
    Assert-RimePimeNoReparsePath $full
    $item=Get-Item -LiteralPath $full -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$($Lease.Context) directory became a reparse point."}
    $pathId=[YimePime.Postbuild.DirectoryLeasesV1]::Inspect($full)
    if([string]$pathId -cne [string]$Lease.FileId){throw "$($Lease.Context) directory identity changed while leased."}
    return $true
}

function Get-RimePimePostbuildExpectedDirectoryPaths {
    param([Parameter(Mandatory)][object[]]$ExpectedRows)
    $directories=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($ExpectedRows)){
        $path=[string]$row.path;$slash=$path.LastIndexOf('/')
        while($slash -gt 0){
            $parent=$path.Substring(0,$slash)
            if(-not $directories.Add($parent)){
                $existing=@($directories|Where-Object{$_ -ieq $parent})[0]
                if([string]$existing -cne $parent){throw "Case-folded expected extraction directory collision: $parent"}
            }
            $slash=$parent.LastIndexOf('/')
        }
    }
    return @($directories|Sort-Object @{Expression={@($_.Split('/')).Count}},@{Expression={$_}} -CaseSensitive)
}

function Open-RimePimePostbuildExpectedDirectoryLeases {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object[]]$ExpectedRows,
        [Parameter(Mandatory)][string]$Context
    )
    $rootFull=(Assert-YimePimePayloadAbsolutePath $Root).TrimEnd([char]92)
    $leases=[Collections.Generic.List[object]]::new()
    try{
        foreach($relative in @(Get-RimePimePostbuildExpectedDirectoryPaths $ExpectedRows)){
            $canonical=ConvertTo-RimePimePostbuildArchivePath ([string]$relative).Replace('/','\')
            $full=[IO.Path]::GetFullPath((Join-Path $rootFull $canonical.Replace('/','\')))
            if(-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)){
                throw 'Expected extraction directory escapes its root.'
            }
            if(Test-Path -LiteralPath $full -PathType Leaf){throw "Expected extraction directory is occupied by a file: $relative"}
            if(-not(Test-Path -LiteralPath $full -PathType Container)){New-Item -ItemType Directory -Path $full|Out-Null}
            $leases.Add((Open-RimePimePostbuildDirectoryLease $full "$Context/$relative"))
        }
        return @($leases)
    }catch{
        foreach($lease in @($leases)){$lease.Native.Dispose()}
        throw
    }
}

function Test-RimePimePostbuildDirectoryLeases {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Leases)
    foreach($lease in @($Leases)){$null=Assert-RimePimePostbuildDirectoryLease $lease}
    return $true
}

function Open-RimePimePostbuildExtractedFileLeases {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object[]]$ExpectedRows,
        [Parameter(Mandatory)][string]$Context
    )
    $rootFull=(Assert-YimePimePayloadAbsolutePath $Root).TrimEnd([char]92)
    $leases=[Collections.Generic.List[object]]::new()
    try{
        foreach($row in @($ExpectedRows|Sort-Object path -CaseSensitive)){
            $archivePath=ConvertTo-RimePimePostbuildArchivePath ([string]$row.path).Replace('/','\')
            $full=[IO.Path]::GetFullPath((Join-Path $rootFull $archivePath.Replace('/','\')))
            if(-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)){
                throw 'Expected extracted file escapes its root.'
            }
            $expectedRecord=$null
            if($null -ne $row.bytes -and $null -ne $row.sha256){
                $expectedRecord=[pscustomobject]@{bytes=[long]$row.bytes;sha256=[string]$row.sha256}
            }
            $lease=Open-RimePimePostbuildReadLease $full $expectedRecord "$Context/$archivePath"
            $lease|Add-Member -NotePropertyName ArchivePath -NotePropertyValue $archivePath
            $lease|Add-Member -NotePropertyName Category -NotePropertyValue ([string]$row.category)
            $leases.Add($lease)
        }
        if($leases.Count -ne $ExpectedRows.Count){throw 'Extracted file lease set is incomplete.'}
        return @($leases)
    }catch{
        foreach($lease in @($leases)){$lease.Stream.Dispose()}
        throw
    }
}

function Get-RimePimePostbuildExtractedFilePath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ArchivePath)
    $rootFull=(Assert-YimePimePayloadAbsolutePath $Root).TrimEnd([char]92)
    $canonical=ConvertTo-RimePimePostbuildArchivePath $ArchivePath.Replace('/','\')
    $full=[IO.Path]::GetFullPath((Join-Path $rootFull $canonical.Replace('/','\')))
    if(-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'Expected extracted file escapes its root.'
    }
    return $full
}

function Test-RimePimePostbuildExtractedFileLeases {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Leases,
        [Parameter(Mandatory)][int]$ExpectedCount
    )
    if($Leases.Count -ne $ExpectedCount){throw "Extracted file lease count mismatch: expected $ExpectedCount, found $($Leases.Count)."}
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($lease in @($Leases)){
        if(-not $paths.Add([string]$lease.ArchivePath)){throw "Duplicate extracted file lease: $($lease.ArchivePath)"}
        $null=Assert-RimePimePostbuildReadLease $lease
    }
    return $true
}

function Test-RimePimePostbuildExecutionLogicLeases {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Leases)
    $expected=@(
        'tools/dual-product/run-rime-pime-postbuild-extraction.ps1',
        'tools/dual-product/rime-pime-postbuild-extraction.psm1',
        'tools/dual-product/rime-pime-postbuild-extraction.ps1',
        'tools/dual-product/rime-pime-package-staging.psm1',
        'tools/dual-product/rime-pime-package-staging.ps1',
        'tools/dual-product/rime-pime-package-plan.ps1',
        'tools/dual-product/rime-pime-payload-closure.ps1',
        'tools/dual-product/rime-pime-nsis-stage.psm1',
        'tools/dual-product/rime-pime-nsis-stage.ps1',
        'tools/dual-product/rime-pime-nsis-toolchain-closure.psm1',
        'tools/dual-product/rime-pime-nsis-toolchain-closure.ps1',
        'tools/dual-product/rime-pime-postbuild-toolchain-lock.json',
        'tools/dual-product/rime-pime-postbuild-toolchain-lock.json.sha256',
        'tools/verify-pe-architectures.ps1'
    )
    if($Leases.Count -ne $expected.Count){throw 'Post-build execution-logic lease set is incomplete.'}
    $byPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($lease in @($Leases)){
        $null=Assert-RimePimePostbuildReadLease $lease
        if($byPath.ContainsKey([string]$lease.Path)){throw 'Post-build execution-logic lease set contains a duplicate path.'}
        $byPath.Add([string]$lease.Path,$lease)
    }
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
    foreach($name in $expected){
        $path=[IO.Path]::GetFullPath((Join-Path $repo $name.Replace('/','\')))
        if(-not $byPath.ContainsKey($path)){throw "Post-build execution-logic lease is missing: $name"}
    }
    return @($Leases|ForEach-Object{[pscustomobject][ordered]@{
        path=[string]$_.Path;bytes=[long]$_.Record.bytes;sha256=[string]$_.Record.sha256
    }}|Sort-Object path -CaseSensitive)
}

function Write-RimePimePostbuildTextFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
    $full=[IO.Path]::GetFullPath($Path)
    Assert-RimePimeNoReparsePath $full
    $normalized=$Text.Replace("`r`n","`n").Replace("`r","`n")
    if (-not $normalized.EndsWith("`n",[StringComparison]::Ordinal)) { $normalized += "`n" }
    $bytes=[Text.Encoding]::UTF8.GetBytes($normalized)
    $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    $record=[pscustomobject][ordered]@{
        path=$full;bytes=[long]$bytes.Length;sha256=Get-RimePimePostbuildSha256Bytes $bytes
    }
    $lease=Open-RimePimePostbuildReadLease $full $record 'post-build text evidence'
    return [pscustomobject][ordered]@{Record=$record;Lease=$lease}
}

function Get-RimePimePostbuildSha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Write-RimePimePostbuildSealedJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path);$sidecar=$full+'.sha256'
    $parent=Split-Path -Parent $full
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Post-build evidence parent is missing.'}
    Assert-RimePimeNoReparsePath $parent
    $jsonBytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-RimePimeStageCanonicalJson $Value)+"`n")
    if($jsonBytes.Length -gt 1048576){throw 'Canonical post-build JSON exceeds the 1 MiB bound.'}
    $digest=Get-RimePimePostbuildSha256Bytes $jsonBytes
    $sidecarBytes=[Text.Encoding]::ASCII.GetBytes("$digest  $([IO.Path]::GetFileName($full))`n")
    $leases=[Collections.Generic.List[object]]::new()
    try{
        foreach($item in @(
            [pscustomobject]@{path=$full;bytes=$jsonBytes;context='post-build result JSON'},
            [pscustomobject]@{path=$sidecar;bytes=$sidecarBytes;context='post-build result sidecar'}
        )){
            $stream=$null
            try{
                $stream=[IO.File]::Open([string]$item.path,[IO.FileMode]::CreateNew,
                    [IO.FileAccess]::Write,[IO.FileShare]::None)
                $stream.Write([byte[]]$item.bytes,0,([byte[]]$item.bytes).Length)
                $stream.Flush($true)
            }finally{if($null -ne $stream){$stream.Dispose()}}
            $expected=[pscustomobject]@{
                bytes=[long]([byte[]]$item.bytes).Length
                sha256=Get-RimePimePostbuildSha256Bytes ([byte[]]$item.bytes)
            }
            $leases.Add((Open-RimePimePostbuildReadLease ([string]$item.path) $expected ([string]$item.context)))
        }
        return [pscustomobject][ordered]@{
            Path=$full;Sidecar=$sidecar;Digest=$digest
            JsonLease=$leases[0];SidecarLease=$leases[1]
        }
    }catch{
        foreach($lease in @($leases)){if($null -ne $lease){$lease.Stream.Dispose()}}
        throw
    }
}

function Open-RimePimePostbuildCreateNewCaptureStream {
    param([Parameter(Mandatory)][string]$Path)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    $parent=Split-Path -Parent $full
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Raw-entry capture parent is missing.'}
    Assert-RimePimeNoReparsePath $parent
    return [IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}

function Read-RimePimePostbuildSevenZipListing {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][ValidateSet('installer','uninstaller')][string]$Kind
    )
    $normalized=$Text.Replace("`r`n","`n").Replace("`r","`n")
    $lines=@($normalized.Split("`n"))
    $separator=-1
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i] -ceq '----------'){$separator=$i;break}
    }
    if($separator -lt 0){throw '7-Zip listing has no archive/entry separator.'}
    $header=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($line in @($lines[0..($separator-1)])){
        $at=$line.IndexOf(' = ',[StringComparison]::Ordinal)
        if($at -lt 1){continue}
        $name=$line.Substring(0,$at);$value=$line.Substring($at+3)
        if($header.ContainsKey($name)){throw "Duplicate 7-Zip archive property: $name"}
        $header.Add($name,$value)
    }
    $wantedSubtype=if($Kind -ceq 'installer'){'NSIS-3 Unicode'}else{'NSIS-3 Unicode (Uninstall)'}
    if(-not $header.ContainsKey('Type') -or $header['Type'] -cne 'Nsis' -or
        -not $header.ContainsKey('SubType') -or $header['SubType'] -cne $wantedSubtype){
        throw "Unexpected 7-Zip archive type or subtype for $Kind."
    }
    if(-not $header.ContainsKey('Physical Size') -or $header['Physical Size'] -cnotmatch '^[0-9]+$'){
        throw '7-Zip listing has no valid physical size.'
    }
    $records=[Collections.Generic.List[object]]::new()
    $properties=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    function Add-PostbuildListingRecord {
        if($properties.Count -eq 0){return}
        if(-not $properties.ContainsKey('Path') -or -not $properties.ContainsKey('Size')){
            throw '7-Zip entry record is incomplete.'
        }
        $canonical=ConvertTo-RimePimePostbuildArchivePath $properties['Path']
        $size=$null
        if(-not [string]::IsNullOrEmpty($properties['Size'])){
            [long]$parsed=0
            if(-not [long]::TryParse($properties['Size'],[Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,[ref]$parsed) -or $parsed -lt 0){
                throw "Invalid 7-Zip entry size: $canonical"
            }
            $size=$parsed
        }
        $records.Add([pscustomobject][ordered]@{path=$canonical;bytes=$size})
        $properties.Clear()
    }
    for($i=$separator+1;$i -lt $lines.Count;$i++){
        $line=$lines[$i]
        if([string]::IsNullOrEmpty($line)){Add-PostbuildListingRecord;continue}
        $at=$line.IndexOf(' = ',[StringComparison]::Ordinal)
        if($at -lt 1){throw "Malformed 7-Zip entry property: $line"}
        $name=$line.Substring(0,$at);$value=$line.Substring($at+3)
        if($properties.ContainsKey($name)){throw "Duplicate 7-Zip entry property: $name"}
        $properties.Add($name,$value)
    }
    Add-PostbuildListingRecord
    if($records.Count -lt 1 -or $records.Count -gt 512){throw '7-Zip listing entry count is outside the sealed bound.'}
    return [pscustomobject][ordered]@{
        kind=$Kind;type=$header['Type'];subtype=$header['SubType'];physical_size=[long]$header['Physical Size']
        entries=@($records)
    }
}

function Get-RimePimePostbuildNsisSupportRecords {
    param([Parameter(Mandatory)]$Toolchain)
    $records=[Collections.Generic.List[object]]::new()
    foreach($locked in @($Toolchain.Support)){
        $record=Get-YimePimePayloadFileRecord ([string]$locked.path)
        Assert-RimePimePostbuildLockedFileRecord $record $locked "NSIS support input $($locked.archive_path)"
        if([string]$record.file_id -cne [string]$locked.file_id){
            throw "NSIS support input path identity changed: $($locked.archive_path)"
        }
        $records.Add([pscustomobject][ordered]@{
            archive_path=[string]$locked.archive_path;origin_path=[string]$locked.origin_path
            bytes=[long]$record.bytes;sha256=[string]$record.sha256;file_id=[string]$record.file_id
        })
    }
    return @($records)
}

function Get-RimePimePostbuildExpectedArchiveRows {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][object[]]$SupportRecords,
        [Parameter(Mandatory)][ValidateSet('installer','uninstaller')][string]$Kind
    )
    $rows=[Collections.Generic.List[object]]::new()
    foreach($row in @($Manifest.files)){
        $scope=[string]$row.stage_scope
        if($Kind -ceq 'uninstaller' -and $scope -cne 'bootstrap'){continue}
        $path=[string]$row.path
        $archive=if($scope -ceq 'bootstrap'){'$PLUGINSDIR/'+$path}else{$path}
        $rows.Add([pscustomobject][ordered]@{
            path=$archive;bytes=[long]$row.bytes;sha256=[string]$row.sha256
            category=if($scope -ceq 'bootstrap'){'product-bootstrap'}else{'installed-payload'}
        })
    }
    foreach($support in @($SupportRecords)){
        $name=[IO.Path]::GetFileName(([string]$support.archive_path).Replace('/','\'))
        if($Kind -ceq 'uninstaller' -and $script:RimePimePostbuildUninstallerSupportNames -cnotcontains $name){continue}
        $rows.Add([pscustomobject][ordered]@{
            path=[string]$support.archive_path;bytes=[long]$support.bytes;sha256=[string]$support.sha256
            category='nsis-support'
        })
    }
    if($Kind -ceq 'installer'){
        $rows.Add([pscustomobject][ordered]@{path='Uninstall.exe';bytes=$null;sha256=$null;category='generated-uninstaller'})
    }
    $index=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($rows)){
        $windowsPath=([string]$row.path).Replace('/','\')
        $canonical=ConvertTo-RimePimePostbuildArchivePath $windowsPath
        if($index.ContainsKey($canonical)){throw "Case-folded expected archive collision: $canonical"}
        $index.Add($canonical,$row)
    }
    return @($rows)
}

function Test-RimePimePostbuildArchiveListing {
    param(
        [Parameter(Mandatory)]$Listing,
        [Parameter(Mandatory)][object[]]$ExpectedRows
    )
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($ExpectedRows)){
        $path=[string]$row.path
        if($expected.ContainsKey($path)){throw "Case-folded expected archive collision: $path"}
        $expected.Add($path,$row)
    }
    $actual=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $blankSizes=0
    $entries=@($Listing.entries)
    for($i=0;$i -lt $entries.Count;$i++){
        $row=$entries[$i];$path=[string]$row.path
        if($actual.ContainsKey($path)){throw "Duplicate or case-folded archive entry: $path"}
        $actual.Add($path,$row)
        if($null -eq $row.bytes){
            $blankSizes++
            if($i -ne $entries.Count-1){throw "Only the final NSIS solid member may have a blank size: $path"}
        }
    }
    if($blankSizes -ne 1){throw 'NSIS listing must contain exactly one final blank-size member.'}
    if($actual.Count -ne $expected.Count){throw "Archive exact-set count mismatch: expected $($expected.Count), found $($actual.Count)."}
    foreach($path in $expected.Keys){
        if(-not $actual.ContainsKey($path) -or [string]$actual[$path].path -cne [string]$expected[$path].path){
            throw "Archive entry is missing or case-mismatched: $path"
        }
        if($null -ne $actual[$path].bytes -and $null -ne $expected[$path].bytes -and
            [long]$actual[$path].bytes -ne [long]$expected[$path].bytes){
            throw "Archive listing size mismatch: $path"
        }
    }
    $counts=[ordered]@{}
    foreach($category in @('installed-payload','product-bootstrap','nsis-support','generated-uninstaller')){
        $counts[$category]=@($ExpectedRows|Where-Object{[string]$_.category -ceq $category}).Count
    }
    return [pscustomobject][ordered]@{
        passed=$true;entry_count=$actual.Count;blank_size_count=$blankSizes;category_counts=[pscustomobject]$counts
    }
}

function Get-RimePimePostbuildExtractedSnapshot {
    param(
        [Parameter(Mandatory)][string]$ExtractionRoot,
        [Parameter(Mandatory)][object[]]$ExpectedRows
    )
    $root=(Assert-YimePimePayloadAbsolutePath $ExtractionRoot).TrimEnd([char]92)
    if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'Post-build extraction root is missing.'}
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $expectedDirs=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($ExpectedRows)){
        $path=[string]$row.path
        if($expected.ContainsKey($path)){throw "Duplicate expected extracted path: $path"}
        $expected.Add($path,$row)
        $slash=$path.LastIndexOf('/')
        while($slash -gt 0){
            $parent=$path.Substring(0,$slash)
            if(-not $expectedDirs.ContainsKey($parent)){$expectedDirs.Add($parent,$parent)}
            $slash=$parent.LastIndexOf('/')
        }
    }
    $actualDirs=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $actualFiles=[Collections.Generic.List[object]]::new()
    $fileIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
    while($pending.Count){
        $directory=$pending.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $directory -Force)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Indirect extracted entry rejected: $($item.FullName)"}
            $relative=$item.FullName.Substring($root.Length+1).Replace('\','/')
            $canonical=ConvertTo-RimePimePostbuildArchivePath $relative.Replace('/','\')
            if($item.PSIsContainer){
                if(-not $expectedDirs.ContainsKey($canonical) -or [string]$expectedDirs[$canonical] -cne $canonical){
                    throw "Unlisted or case-mismatched extracted directory: $canonical"
                }
                $actualDirs.Add($canonical,$canonical);$pending.Push($item.FullName);continue
            }
            if(-not $expected.ContainsKey($canonical) -or [string]$expected[$canonical].path -cne $canonical){
                throw "Unlisted or case-mismatched extracted file: $canonical"
            }
            $record=Get-YimePimePayloadFileRecord $item.FullName
            $wanted=$expected[$canonical]
            if($null -ne $wanted.bytes -and ([long]$wanted.bytes -ne [long]$record.bytes -or
                [string]$wanted.sha256 -cne [string]$record.sha256)){
                throw "Extracted content mismatch: $canonical"
            }
            if(-not $fileIds.Add([string]$record.file_id)){throw "Duplicate extracted file identity: $canonical"}
            $actualFiles.Add([pscustomobject][ordered]@{
                path=$canonical;bytes=[long]$record.bytes;sha256=[string]$record.sha256
                file_id=[string]$record.file_id;category=[string]$wanted.category
            })
        }
    }
    if($actualFiles.Count -ne $expected.Count){throw 'Extracted tree has missing files.'}
    if($actualDirs.Count -ne $expectedDirs.Count){throw 'Extracted tree has missing directories.'}
    return [pscustomobject][ordered]@{
        files=@($actualFiles|Sort-Object path -CaseSensitive);directories=@($actualDirs.Values|Sort-Object -CaseSensitive)
        file_count=$actualFiles.Count;directory_count=$actualDirs.Count
    }
}

function Invoke-RimePimePostbuildSevenZip {
    param(
        [Parameter(Mandatory)]$SevenZipLease,
        [Parameter(Mandatory)]$SevenZipLibraryLease,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [switch]$RequireEverythingOk
    )
    $null=Assert-RimePimePostbuildReadLease $SevenZipLease
    $null=Assert-RimePimePostbuildReadLease $SevenZipLibraryLease
    $lines=@(& ([string]$SevenZipLease.Path) @Arguments 2>&1 | ForEach-Object{$_.ToString()})
    $exitCode=$LASTEXITCODE
    $null=Assert-RimePimePostbuildReadLease $SevenZipLibraryLease
    $null=Assert-RimePimePostbuildReadLease $SevenZipLease
    $text=[string]::Join("`n",$lines)
    if($exitCode -ne 0){throw "7-Zip $Operation failed with exit code $exitCode."}
    if($RequireEverythingOk -and $text -cnotmatch '(?m)^Everything is Ok\s*$'){
        throw "7-Zip $Operation did not report exact success."
    }
    return [pscustomobject][ordered]@{exit_code=[int]$exitCode;text=$text}
}

function Test-RimePimePostbuildSevenZipLibraryBinding {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$ExpectedLibraryPath,
        [Parameter(Mandatory)][string]$ExpectedVersion
    )
    $expected=Assert-YimePimePayloadAbsolutePath $ExpectedLibraryPath
    if($ExpectedVersion -cnotmatch '^[0-9]+(?:\.[0-9]+)+$'){throw 'Expected 7-Zip library version is invalid.'}
    $lines=@($Text.Replace("`r`n","`n").Replace("`r","`n").Split("`n"))
    $libs=@();$formats=@()
    for($index=0;$index -lt $lines.Count;$index++){
        if($lines[$index] -ceq 'Libs:'){$libs+=,$index}
        if($lines[$index] -ceq 'Formats:'){$formats+=,$index}
    }
    if($libs.Count -ne 1 -or $formats.Count -ne 1 -or $formats[0] -le $libs[0]+1){
        throw '7-Zip information output has no unique Libs/Formats boundary.'
    }
    $libraryLines=@($lines[($libs[0]+1)..($formats[0]-1)]|Where-Object{-not [string]::IsNullOrWhiteSpace($_)})
    if($libraryLines.Count -ne 1 -or $libraryLines[0] -cnotmatch '^ 0 : ([0-9]+(?:\.[0-9]+)+) : (.+)$'){
        throw '7-Zip information output has no unique external parser library binding.'
    }
    $reportedVersion=[string]$Matches[1]
    $reportedPath=Assert-YimePimePayloadAbsolutePath ([string]$Matches[2])
    if($reportedVersion -cne $ExpectedVersion -or $reportedPath -cne $expected){
        throw '7-Zip loaded parser library differs from the repository-pinned binding.'
    }
    return [pscustomobject][ordered]@{path=$reportedPath;version=$reportedVersion;binding_verified=$true}
}

function ConvertTo-RimePimePostbuildWindowsCommandLineArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Argument)
    if($Argument -match '[\x00\r\n]'){throw '7-Zip command-line argument contains a control character.'}
    $builder=[Text.StringBuilder]::new()
    $null=$builder.Append('"')
    $slashes=0
    foreach($character in $Argument.ToCharArray()){
        if($character -eq [char]92){$slashes++;continue}
        if($character -eq [char]34){
            if($slashes){$null=$builder.Append([char]92,($slashes*2))}
            $null=$builder.Append([char]92);$null=$builder.Append([char]34);$slashes=0;continue
        }
        if($slashes){$null=$builder.Append([char]92,$slashes);$slashes=0}
        $null=$builder.Append($character)
    }
    if($slashes){$null=$builder.Append([char]92,($slashes*2))}
    $null=$builder.Append('"')
    return $builder.ToString()
}

function Invoke-RimePimePostbuildSevenZipRawEntry {
    param(
        [Parameter(Mandatory)]$SevenZipLease,
        [Parameter(Mandatory)]$SevenZipLibraryLease,
        [Parameter(Mandatory)]$ArchiveLease,
        [Parameter(Mandatory)][string]$ArchivePath,
        $ExpectedRecord,
        [string]$CapturePath,
        [Parameter(Mandatory)][string]$Operation
    )
    $canonical=ConvertTo-RimePimePostbuildArchivePath $ArchivePath.Replace('/','\')
    if($null -eq $ExpectedRecord -and [string]::IsNullOrWhiteSpace($CapturePath)){
        throw 'An entry without a sealed expected record must be captured for subsequent verification.'
    }
    $maximumBytes=[long]67108864
    if($null -ne $ExpectedRecord){
        if(-not(Test-RimePimeStageInteger $ExpectedRecord.bytes) -or [long]$ExpectedRecord.bytes -lt 0 -or
            [string]$ExpectedRecord.sha256 -cnotmatch '^[0-9a-f]{64}$'){
            throw 'Raw-entry verification received an invalid expected record.'
        }
        $maximumBytes=[long]$ExpectedRecord.bytes
    }
    $capture=$null;$process=$null;$sha=$null;$stderrTask=$null
    try{
        if(-not [string]::IsNullOrWhiteSpace($CapturePath)){
            $captureFull=Assert-YimePimePayloadAbsolutePath $CapturePath
            $capture=Open-RimePimePostbuildCreateNewCaptureStream $captureFull
        }
        $null=Assert-RimePimePostbuildReadLease $SevenZipLease
        $null=Assert-RimePimePostbuildReadLease $SevenZipLibraryLease
        $null=Assert-RimePimePostbuildReadLease $ArchiveLease
        $arguments=@(
            'e','-so','-spd','-y','-bso0','-bsp0','-bse2','-sccUTF-8','--',
            [string]$ArchiveLease.Path,$canonical.Replace('/','\')
        )
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=[string]$SevenZipLease.Path
        $start.Arguments=[string]::Join(' ',@($arguments|ForEach-Object{
            ConvertTo-RimePimePostbuildWindowsCommandLineArgument ([string]$_)
        }))
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new();$process.StartInfo=$start
        if(-not $process.Start()){throw "7-Zip $Operation could not start."}
        $stderrTask=$process.StandardError.ReadToEndAsync()
        $sha=[Security.Cryptography.SHA256]::Create()
        $buffer=New-Object byte[] 65536;$total=[long]0
        while(($read=$process.StandardOutput.BaseStream.Read($buffer,0,$buffer.Length)) -gt 0){
            $total+=[long]$read
            if($total -gt $maximumBytes){
                try{$process.Kill()}catch{}
                $process.WaitForExit()
                throw "7-Zip $Operation exceeded its sealed byte bound."
            }
            $null=$sha.TransformBlock($buffer,0,$read,$buffer,0)
            if($null -ne $capture){$capture.Write($buffer,0,$read)}
        }
        $null=$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
        $process.WaitForExit()
        $stderr=[string]$stderrTask.Result
        if($process.ExitCode -ne 0){throw "7-Zip $Operation failed with exit code $($process.ExitCode)."}
        if(-not [string]::IsNullOrWhiteSpace($stderr)){throw "7-Zip $Operation emitted unexpected diagnostic output."}
        if($null -ne $capture){$capture.Flush($true)}
        $digest=([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
        if($null -ne $ExpectedRecord -and
            ($total -ne [long]$ExpectedRecord.bytes -or $digest -cne [string]$ExpectedRecord.sha256)){
            throw "7-Zip raw stdout differs from the sealed expected entry: $canonical"
        }
        $null=Assert-RimePimePostbuildReadLease $ArchiveLease
        $null=Assert-RimePimePostbuildReadLease $SevenZipLibraryLease
        $null=Assert-RimePimePostbuildReadLease $SevenZipLease
        return [pscustomobject][ordered]@{
            archive_path=$canonical;bytes=$total;sha256=$digest
            capture_path=if($null -ne $capture){$captureFull}else{$null};exit_code=0
        }
    }finally{
        if($null -ne $sha){$sha.Dispose()}
        if($null -ne $capture){$capture.Dispose()}
        if($null -ne $process){$process.Dispose()}
    }
}

function Test-RimePimePostbuildRawByteBindings {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$PackagePlanDigest,
        [Parameter(Mandatory)][string]$ContentManifestDigest,
        [Parameter(Mandatory)][string]$ContentTreeDigest,
        [Parameter(Mandatory)][string]$PayloadNshDigest
    )
    $latin1=[Text.Encoding]::GetEncoding(28591)
    $haystack=$latin1.GetString($Bytes)
    $bindings=[ordered]@{
        package_plan=$PackagePlanDigest;content_manifest=$ContentManifestDigest
        content_tree=$ContentTreeDigest;payload_nsh=$PayloadNshDigest
    }
    foreach($name in @($bindings.Keys)){
        $binding=[string]$bindings[$name]
        if($binding -cnotmatch '^[0-9a-f]{64}$'){
            throw "Generated NSIS image $name raw-byte binding digest is invalid."
        }
        $needle=$latin1.GetString([Text.Encoding]::Unicode.GetBytes($binding))
        if($haystack.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){
            throw "Generated NSIS image lacks required $name raw-byte binding."
        }
    }
    return [pscustomobject][ordered]@{
        package_plan_raw_byte_binding=$true;content_manifest_raw_byte_binding=$true
        content_tree_raw_byte_binding=$true;payload_nsh_raw_byte_binding=$true
    }
}

function Test-RimePimePostbuildPeIdentity {
    param(
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)][string]$ProductVersion,
        [Parameter(Mandatory)][string]$PackagePlanDigest,
        [Parameter(Mandatory)][string]$ContentManifestDigest,
        [Parameter(Mandatory)][string]$ContentTreeDigest,
        [Parameter(Mandatory)][string]$PayloadNshDigest
    )
    $record=Assert-RimePimePostbuildReadLease $Lease
    if($record.bytes -lt 65536){throw 'Generated NSIS PE is unexpectedly small.'}
    $bytes=Read-RimePimePostbuildLeaseBytes $Lease
    if([BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d){throw 'Generated NSIS image has no MZ header.'}
    $peOffset=[uint32][BitConverter]::ToUInt32($bytes,0x3c)
    if([uint64]$peOffset+24 -gt [uint64]$bytes.Length){throw 'Generated NSIS image has an invalid PE offset.'}
    if([BitConverter]::ToUInt32($bytes,[int]$peOffset) -ne 0x00004550 -or
        [BitConverter]::ToUInt16($bytes,[int]$peOffset+4) -ne 0x014c){
        throw 'Generated NSIS image is not an x86 PE.'
    }
    $full=[string]$Lease.Path
    $version=(Get-Item -LiteralPath $full).VersionInfo
    if([string]$version.FileVersion -cne $ProductVersion -or [string]$version.ProductVersion -cne $ProductVersion -or
        [string]$version.CompanyName -cne 'YIME Project' -or [string]::IsNullOrWhiteSpace([string]$version.ProductName)){
        throw 'Generated NSIS image VERSIONINFO is missing or mismatched.'
    }
    $rawBindings=Test-RimePimePostbuildRawByteBindings $bytes $PackagePlanDigest `
        $ContentManifestDigest $ContentTreeDigest $PayloadNshDigest
    $signature=Get-AuthenticodeSignature -LiteralPath $full
    if([string]$signature.Status -cne 'NotSigned'){throw 'Disabled post-build verification requires an unsigned NSIS image.'}
    $null=Assert-RimePimePostbuildReadLease $Lease
    return [pscustomobject][ordered]@{
        path=$full;bytes=[long]$record.bytes;sha256=[string]$record.sha256;machine='x86'
        file_version=[string]$version.FileVersion;product_version=[string]$version.ProductVersion
        company_name=[string]$version.CompanyName;signature_status=[string]$signature.Status
        package_plan_raw_byte_binding=$rawBindings.package_plan_raw_byte_binding
        content_manifest_raw_byte_binding=$rawBindings.content_manifest_raw_byte_binding
        content_tree_raw_byte_binding=$rawBindings.content_tree_raw_byte_binding
        payload_nsh_raw_byte_binding=$rawBindings.payload_nsh_raw_byte_binding;trusted=$false
    }
}

function Test-RimePimePostbuildSuccessText {
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][ValidateSet('installer','uninstaller')][string]$Kind)
    $subtype=if($Kind -ceq 'installer'){'NSIS-3 Unicode'}else{'NSIS-3 Unicode \(Uninstall\)'}
    if($Text -cnotmatch '(?m)^Everything is Ok\s*$' -or $Text -cnotmatch '(?m)^Type = Nsis\s*$' -or
        $Text -cnotmatch ("(?m)^SubType = "+$subtype+'\s*$')){
        throw "7-Zip test output does not identify a valid $Kind NSIS archive."
    }
}

function Invoke-RimePimePostbuildExtraction {
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$ContentManifestPath,
        [Parameter(Mandatory)][string]$ExpectedContentManifestDigest,
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$PayloadNshReceiptPath,
        [Parameter(Mandatory)][string]$ExpectedPayloadNshReceiptDigest,
        [Parameter(Mandatory)][object[]]$ExecutionLogicLeases,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$AllowedOutputParent
    )
    $installer=Assert-YimePimePayloadAbsolutePath $InstallerPath
    $stage=(Assert-YimePimePayloadAbsolutePath $StageRoot).TrimEnd([char]92)
    $payloadNshReceipt=Assert-YimePimePayloadAbsolutePath $PayloadNshReceiptPath
    $parent=(Assert-YimePimePayloadAbsolutePath $AllowedOutputParent).TrimEnd([char]92)
    $output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd([char]92)
    if((Split-Path -Parent $output) -ine $parent -or
        (Split-Path -Leaf $output) -cnotmatch '^dp1-postbuild-extraction-[A-Za-z0-9-]+$' -or
        (Test-Path -LiteralPath $output)){
        throw 'Use a fresh immediate dp1-postbuild-extraction-* output root.'
    }
    foreach($candidate in @($output,$installer,$stage,$ContentManifestPath,$payloadNshReceipt)){
        Assert-RimePimeNoReparsePath ([IO.Path]::GetFullPath($candidate))
    }
    if($ExpectedContentManifestDigest -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedPayloadNshReceiptDigest -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Package.Digest -cnotmatch '^[0-9a-f]{64}$'){
        throw 'Post-build extraction requires lowercase SHA-256 input digests.'
    }
    $executionLogicEvidence=@(Test-RimePimePostbuildExecutionLogicLeases $ExecutionLogicLeases)
    $manifest=Read-RimePimeCopiedContentManifest $ContentManifestPath $ExpectedContentManifestDigest
    # This binding is deliberately evaluated against the Package object, not
    # merely a caller-supplied digest. It must complete before any 7-Zip call.
    $planStageBindings=Assert-RimePimePackagePlanStageBindings -Package $Package -ContentManifest $manifest.Manifest
    $payloadNsh=Test-RimePimeNsisStageInclude -StageRoot $stage -ContentManifestPath $manifest.Path `
        -ExpectedContentManifestDigest $manifest.Digest -ExpectedPackagePlanDigest ([string]$Package.Digest) `
        -ReceiptPath $payloadNshReceipt -ExpectedReceiptDigest $ExpectedPayloadNshReceiptDigest
    $payload=@($manifest.Manifest.files|Where-Object{[string]$_.stage_scope -ceq 'payload'})
    $bootstrap=@($manifest.Manifest.files|Where-Object{[string]$_.stage_scope -ceq 'bootstrap'})
    if($payload.Count -ne 166 -or $bootstrap.Count -ne 9){throw 'Current x86/x64 post-build profile requires exactly 166 payload and 9 bootstrap files.'}
    $stageBefore=Test-RimePimePackageCopyStage $stage $manifest.Path $manifest.Digest
    $toolchain=Read-RimePimePostbuildToolchainLock
    $supportBefore=@();$topExpected=@();$uninstallerExpected=@();$nsisClosureEvidence=$null
    $sevenZipLease=$null;$sevenZipLibraryLease=$null;$installerLease=$null;$uninstallerLease=$null
    $nsisCompilerInputClosure=$null
    $outputDirectoryLease=$null;$topDirectoryLease=$null;$unDirectoryLease=$null;$evidenceDirectoryLease=$null
    $topExpectedDirectoryLeases=@();$unExpectedDirectoryLeases=@()
    $topExtractedFileLeases=[Collections.Generic.List[object]]::new()
    $unExtractedFileLeases=[Collections.Generic.List[object]]::new()
    $logFileLeases=[Collections.Generic.List[object]]::new()
    $topRawEntryRecords=@();$unRawEntryRecords=@()
    $resultSeal=$null
    try{
        # This post-build pass establishes a current, read-leased exact NSIS
        # distribution tree. It does not retroactively prove that these leases
        # surrounded the earlier makensis invocation. Even around makensis it
        # closes known-file replacement, not transient child insertion.
        $nsisCompilerInputClosure=Open-RimePimeNsisCompilerInputClosure
        $nsisClosureEvidence=Test-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure
        if([string]$nsisClosureEvidence.nsis_toolchain_lock_sha256 -cne [string]$toolchain.Digest){
            throw 'Post-build NSIS compiler closure and archive toolchain lock differ.'
        }
        $supportBefore=@(Get-RimePimePostbuildNsisSupportRecords $toolchain)
        $topExpected=@(Get-RimePimePostbuildExpectedArchiveRows $manifest.Manifest $supportBefore installer)
        $uninstallerExpected=@(Get-RimePimePostbuildExpectedArchiveRows $manifest.Manifest $supportBefore uninstaller)
        if($topExpected.Count -ne 181 -or $uninstallerExpected.Count -ne 11){throw 'Post-build exact-set partition counts drifted.'}
        # Each lease is acquired before identity/record/archive operations for
        # that image and remains open until all reads of that image finish.
        $sevenZipLease=Open-RimePimePostbuildReadLease $toolchain.SevenZip.path $toolchain.Document.seven_zip '7-Zip extractor'
        $sevenZipLibraryLease=Open-RimePimePostbuildReadLease $toolchain.SevenZipLibrary.path $toolchain.Document.seven_zip.library '7-Zip parser library'
        $installerLease=Open-RimePimePostbuildReadLease $installer $null 'disabled installer candidate'
        $installerBefore=$installerLease.Record
        $installerIdentity=Test-RimePimePostbuildPeIdentity $installerLease `
            ([string]$manifest.Manifest.product_version) ([string]$Package.Digest) $manifest.Digest `
            ([string]$manifest.Manifest.content_tree_sha256) ([string]$payloadNsh.include_sha256)
        # The executable is only a front end: bind the external parser DLL it
        # actually loaded before asking it to inspect either NSIS archive.
        $sevenZipInfo=Invoke-RimePimePostbuildSevenZip $sevenZipLease $sevenZipLibraryLease `
            @('i','-sccUTF-8') '7-Zip parser library binding'
        $sevenZipLibraryBinding=Test-RimePimePostbuildSevenZipLibraryBinding $sevenZipInfo.text `
            ([string]$toolchain.SevenZipLibrary.path) ([string]$toolchain.Document.seven_zip.library.file_version)
        # Ordering is security-significant: test and exact listing validation
        # complete before the first extraction directory is created.
        $topTest=Invoke-RimePimePostbuildSevenZip $sevenZipLease $sevenZipLibraryLease @('t','-sccUTF-8',$installer) 'installer test' -RequireEverythingOk
        Test-RimePimePostbuildSuccessText $topTest.text installer
        $topList=Invoke-RimePimePostbuildSevenZip $sevenZipLease $sevenZipLibraryLease @('l','-slt','-sccUTF-8',$installer) 'installer listing'
        $topListing=Read-RimePimePostbuildSevenZipListing $topList.text installer
        $topListingResult=Test-RimePimePostbuildArchiveListing $topListing $topExpected
        if([long]$topListing.physical_size -ne [long]$installerBefore.bytes){throw '7-Zip listing physical size differs from the locked installer.'}
        New-Item -ItemType Directory -Path $output|Out-Null
        $outputDirectoryLease=Open-RimePimePostbuildDirectoryLease $output 'post-build output root'
        $topRoot=Join-Path $output 'installer-extract';New-Item -ItemType Directory -Path $topRoot|Out-Null
        $topDirectoryLease=Open-RimePimePostbuildDirectoryLease $topRoot 'installer extraction root'
        $topExpectedDirectoryLeases=@(Open-RimePimePostbuildExpectedDirectoryLeases $topRoot $topExpected 'installer extraction path')
        # 7-Zip never receives an output path. The parent process writes each
        # exact stdout member through CreateNew, hashes those same bytes, then
        # immediately opens a digest-bound no-write/no-delete lease.
        $topRaw=[Collections.Generic.List[object]]::new()
        foreach($row in @($topExpected|Sort-Object path -CaseSensitive)){
            $expectedRecord=$null
            if($null -ne $row.bytes -and $null -ne $row.sha256){
                $expectedRecord=[pscustomobject]@{bytes=[long]$row.bytes;sha256=[string]$row.sha256}
            }elseif([string]$row.category -cne 'generated-uninstaller'){
                throw "Archive member has neither a sealed record nor the generated-uninstaller role: $($row.path)"
            }
            $capturePath=Get-RimePimePostbuildExtractedFilePath $topRoot ([string]$row.path)
            $raw=Invoke-RimePimePostbuildSevenZipRawEntry $sevenZipLease $sevenZipLibraryLease $installerLease `
                ([string]$row.path) $expectedRecord $capturePath "installer raw entry $($row.path)"
            if([string]$row.category -ceq 'generated-uninstaller'){
                $row.bytes=[long]$raw.bytes;$row.sha256=[string]$raw.sha256
            }
            $fileLease=Open-RimePimePostbuildReadLease $capturePath $raw "installer captured member $($row.path)"
            $fileLease|Add-Member -NotePropertyName ArchivePath -NotePropertyValue ([string]$raw.archive_path)
            $fileLease|Add-Member -NotePropertyName Category -NotePropertyValue ([string]$row.category)
            $topExtractedFileLeases.Add($fileLease)
            $topRaw.Add([pscustomobject][ordered]@{
                path=[string]$raw.archive_path;bytes=[long]$raw.bytes;sha256=[string]$raw.sha256
                category=[string]$row.category
            })
        }
        $topRawEntryRecords=@($topRaw)
        if($topRawEntryRecords.Count -ne 181){throw 'Installer raw stdout entry verification count drifted.'}
        $rawUninstaller=@($topRawEntryRecords|Where-Object{[string]$_.category -ceq 'generated-uninstaller'})
        $generatedRows=@($topExpected|Where-Object{[string]$_.category -ceq 'generated-uninstaller'})
        if($rawUninstaller.Count -ne 1 -or $generatedRows.Count -ne 1){throw 'Installer has no unique raw generated-uninstaller record.'}
        $uninstallerMatches=@($topExtractedFileLeases|Where-Object{[string]$_.Category -ceq 'generated-uninstaller'})
        if($uninstallerMatches.Count -ne 1){throw 'Installer snapshot has no unique generated-uninstaller lease.'}
        $uninstallerLease=$uninstallerMatches[0]
        $uninstaller=[string]$uninstallerLease.Path
        $uninstallerBefore=$uninstallerLease.Record
        $uninstallerIdentity=Test-RimePimePostbuildPeIdentity $uninstallerLease `
            ([string]$manifest.Manifest.product_version) ([string]$Package.Digest) $manifest.Digest `
            ([string]$manifest.Manifest.content_tree_sha256) ([string]$payloadNsh.include_sha256)
        $null=Assert-RimePimePostbuildDirectoryLease $outputDirectoryLease
        $null=Assert-RimePimePostbuildDirectoryLease $topDirectoryLease
        $null=Test-RimePimePostbuildDirectoryLeases $topExpectedDirectoryLeases
        $null=Test-RimePimePostbuildExtractedFileLeases @($topExtractedFileLeases) 181
        $topSnapshot=Get-RimePimePostbuildExtractedSnapshot $topRoot $topExpected
        $unTest=Invoke-RimePimePostbuildSevenZip $sevenZipLease $sevenZipLibraryLease @('t','-sccUTF-8',$uninstaller) 'uninstaller test' -RequireEverythingOk
        Test-RimePimePostbuildSuccessText $unTest.text uninstaller
        $unList=Invoke-RimePimePostbuildSevenZip $sevenZipLease $sevenZipLibraryLease @('l','-slt','-sccUTF-8',$uninstaller) 'uninstaller listing'
        $unListing=Read-RimePimePostbuildSevenZipListing $unList.text uninstaller
        $unListingResult=Test-RimePimePostbuildArchiveListing $unListing $uninstallerExpected
        if([long]$unListing.physical_size -ne [long]$uninstallerBefore.bytes){throw '7-Zip listing physical size differs from the locked uninstaller.'}
        $unRoot=Join-Path $output 'uninstaller-extract';New-Item -ItemType Directory -Path $unRoot|Out-Null
        $unDirectoryLease=Open-RimePimePostbuildDirectoryLease $unRoot 'uninstaller extraction root'
        $unExpectedDirectoryLeases=@(Open-RimePimePostbuildExpectedDirectoryLeases $unRoot $uninstallerExpected 'uninstaller extraction path')
        $unRaw=[Collections.Generic.List[object]]::new()
        foreach($row in @($uninstallerExpected|Sort-Object path -CaseSensitive)){
            $expectedRecord=[pscustomobject]@{bytes=[long]$row.bytes;sha256=[string]$row.sha256}
            $capturePath=Get-RimePimePostbuildExtractedFilePath $unRoot ([string]$row.path)
            $raw=Invoke-RimePimePostbuildSevenZipRawEntry $sevenZipLease $sevenZipLibraryLease $uninstallerLease `
                ([string]$row.path) $expectedRecord $capturePath "uninstaller raw entry $($row.path)"
            $fileLease=Open-RimePimePostbuildReadLease $capturePath $raw "uninstaller captured member $($row.path)"
            $fileLease|Add-Member -NotePropertyName ArchivePath -NotePropertyValue ([string]$raw.archive_path)
            $fileLease|Add-Member -NotePropertyName Category -NotePropertyValue ([string]$row.category)
            $unExtractedFileLeases.Add($fileLease)
            $unRaw.Add([pscustomobject][ordered]@{
                path=[string]$raw.archive_path;bytes=[long]$raw.bytes;sha256=[string]$raw.sha256
                category=[string]$row.category
            })
        }
        $unRawEntryRecords=@($unRaw)
        if($unRawEntryRecords.Count -ne 11){throw 'Uninstaller raw stdout entry verification count drifted.'}
        $null=Assert-RimePimePostbuildDirectoryLease $unDirectoryLease
        $null=Test-RimePimePostbuildDirectoryLeases $unExpectedDirectoryLeases
        $null=Test-RimePimePostbuildExtractedFileLeases @($unExtractedFileLeases) 11
        $unSnapshot=Get-RimePimePostbuildExtractedSnapshot $unRoot $uninstallerExpected
        $topSnapshotAfter=Get-RimePimePostbuildExtractedSnapshot $topRoot $topExpected
        $unSnapshotAfter=Get-RimePimePostbuildExtractedSnapshot $unRoot $uninstallerExpected
        if((ConvertTo-Json $topSnapshot -Depth 8 -Compress) -cne (ConvertTo-Json $topSnapshotAfter -Depth 8 -Compress) -or
            (ConvertTo-Json $unSnapshot -Depth 8 -Compress) -cne (ConvertTo-Json $unSnapshotAfter -Depth 8 -Compress)){
            throw 'Extracted NSIS trees changed between verification passes.'
        }
        $null=Assert-RimePimePostbuildReadLease $uninstallerLease
        $null=Test-RimePimePostbuildExtractedFileLeases @($topExtractedFileLeases) 181
        $null=Test-RimePimePostbuildExtractedFileLeases @($unExtractedFileLeases) 11
        $stageAfter=Test-RimePimePackageCopyStage $stage $manifest.Path $manifest.Digest
        foreach($name in @('file_count','directory_count','total_bytes','content_tree_sha256','local_observation_sha256')){
            if([string]$stageBefore.$name -cne [string]$stageAfter.$name){throw "Copied stage changed during post-build extraction: $name"}
        }
        $null=Assert-RimePimePostbuildReadLease $installerLease
        $supportAfter=@(Get-RimePimePostbuildNsisSupportRecords $toolchain)
        for($i=0;$i -lt $supportBefore.Count;$i++){
            foreach($name in @('archive_path','origin_path','bytes','sha256','file_id')){
                if([string]$supportBefore[$i].$name -cne [string]$supportAfter[$i].$name){throw "NSIS support input changed during static extraction: $name"}
            }
        }
        $null=Assert-RimePimePostbuildReadLease $sevenZipLibraryLease
        $null=Assert-RimePimePostbuildReadLease $sevenZipLease
        $null=Assert-RimePimePostbuildDirectoryLease $outputDirectoryLease
        $null=Assert-RimePimePostbuildDirectoryLease $topDirectoryLease
        $null=Assert-RimePimePostbuildDirectoryLease $unDirectoryLease
        $null=Test-RimePimePostbuildDirectoryLeases $topExpectedDirectoryLeases
        $null=Test-RimePimePostbuildDirectoryLeases $unExpectedDirectoryLeases
        $executionLogicEvidence=@(Test-RimePimePostbuildExecutionLogicLeases $ExecutionLogicLeases)
        $nsisClosureEvidence=Test-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure
    $evidence=Join-Path $output 'evidence';New-Item -ItemType Directory -Path $evidence|Out-Null
    $evidenceDirectoryLease=Open-RimePimePostbuildDirectoryLease $evidence 'post-build evidence root'
    $logs=[ordered]@{}
    foreach($entry in @(
        @('seven_zip_info',$sevenZipInfo.text),
        @('installer_test',$topTest.text),@('installer_list',$topList.text),
        @('uninstaller_test',$unTest.text),@('uninstaller_list',$unList.text))){
        $written=Write-RimePimePostbuildTextFile (Join-Path $evidence ($entry[0]+'.txt')) ([string]$entry[1])
        $logs[$entry[0]]=$written.Record;$logFileLeases.Add($written.Lease)
    }
    $supportEvidence=@($supportBefore|ForEach-Object{[pscustomobject][ordered]@{
        archive_path=$_.archive_path;origin_path=$_.origin_path;bytes=$_.bytes;sha256=$_.sha256
    }})
    $result=[pscustomobject][ordered]@{
        schema_version=$script:RimePimePostbuildSchema;generated_at_utc=[DateTime]::UtcNow.ToString('o')
        product='rime-pime';product_version=[string]$manifest.Manifest.product_version
        package_profile='x86-x64-v1';architectures=@('x86','x64')
        evidence_level='locked-archive-fixed-seven-zip-per-entry-raw-stdout-plus-stable-leased-extracted-snapshots'
        package_plan_path=[string]$Package.Path;package_plan_sha256=[string]$Package.Digest
        package_plan_artifact_count=[int]$planStageBindings.package_plan_artifact_count
        package_plan_matching_stage_binding_count=[int]$planStageBindings.matching_stage_binding_count
        content_manifest_path=$manifest.Path;content_manifest_sha256=$manifest.Digest
        content_tree_sha256=[string]$manifest.Manifest.content_tree_sha256
        payload_nsh_receipt_path=$payloadNshReceipt;payload_nsh_receipt_sha256=$ExpectedPayloadNshReceiptDigest
        payload_nsh_sha256=[string]$payloadNsh.include_sha256
        execution_logic_read_leases=$executionLogicEvidence
        stage_root=$stage;installer=$installerIdentity;generated_uninstaller=$uninstallerIdentity
        toolchain_lock=[pscustomobject][ordered]@{path=$toolchain.Path;sha256=$toolchain.Digest;toolchain_id=[string]$toolchain.Document.toolchain_id}
        seven_zip=[pscustomobject][ordered]@{path=$toolchain.SevenZip.path;bytes=$toolchain.SevenZip.bytes;sha256=$toolchain.SevenZip.sha256}
        seven_zip_parser_library=[pscustomobject][ordered]@{
            path=$toolchain.SevenZipLibrary.path;bytes=$toolchain.SevenZipLibrary.bytes;sha256=$toolchain.SevenZipLibrary.sha256
            version=[string]$sevenZipLibraryBinding.version;loaded_library_binding_verified=$true
        }
        makensis=[pscustomobject][ordered]@{path=$toolchain.Makensis.path;bytes=$toolchain.Makensis.bytes;sha256=$toolchain.Makensis.sha256}
        nsis_toolchain_lock_sha256=[string]$nsisClosureEvidence.nsis_toolchain_lock_sha256
        nsis_compiler_input_scope=[string]$nsisClosureEvidence.nsis_compiler_input_scope
        nsis_compiler_input_tree_sha256=[string]$nsisClosureEvidence.nsis_compiler_input_tree_sha256
        nsis_compiler_input_file_count=[int]$nsisClosureEvidence.nsis_compiler_input_file_count
        nsis_compiler_input_directory_count=[int]$nsisClosureEvidence.nsis_compiler_input_directory_count
        nsis_compiler_input_read_lease_count=[int]$nsisClosureEvidence.nsis_compiler_input_read_lease_count
        nsis_compiler_input_directory_lease_count=[int]$nsisClosureEvidence.nsis_compiler_input_directory_lease_count
        nsis_compiler_input_anchor_directory_lease_count=[int]$nsisClosureEvidence.nsis_compiler_input_anchor_directory_lease_count
        nsis_toolchain_control_read_lease_count=[int]$nsisClosureEvidence.nsis_toolchain_control_read_lease_count
        nsis_distribution_inputs_exact_and_read_leased_during_postbuild=$true
        nsis_known_input_file_replacement_closure=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_compiler_input_leases_held_during_makensis=$false
        nsis_non_os_compiler_input_closure=$false
        full_nsis_toolchain_input_closure=$false
        nsis_support=$supportEvidence;installer_archive=[pscustomobject][ordered]@{
            entry_count=$topListingResult.entry_count;extracted_file_count=$topSnapshot.file_count
            extracted_directory_count=$topSnapshot.directory_count;installed_payload_count=166
            product_bootstrap_count=9;nsis_support_count=5;generated_uninstaller_count=1
            raw_stdout_entry_count=[int]$topRawEntryRecords.Count;raw_stdout_entries=$topRawEntryRecords
        }
        uninstaller_archive=[pscustomobject][ordered]@{
            entry_count=$unListingResult.entry_count;extracted_file_count=$unSnapshot.file_count
            extracted_directory_count=$unSnapshot.directory_count;product_bootstrap_count=9;nsis_support_count=2
            raw_stdout_entry_count=[int]$unRawEntryRecords.Count;raw_stdout_entries=$unRawEntryRecords
        }
        logs=[pscustomobject]$logs;verification_passes=2;installer_archive_listing_exact=$true
        nested_uninstaller_archive_listing_exact=$true;stable_extracted_snapshot_matches_expected_sources=$true
        stable_extracted_stage_owned_files_match_sealed_manifest=$true
        parent_created_per_entry_raw_stdout_snapshot=$true
        seven_zip_never_received_snapshot_output_paths=$true
        installer_archive_per_entry_raw_stdout_verified=$true
        nested_uninstaller_archive_per_entry_raw_stdout_verified=$true
        archive_content_origin_proven=$true
        archive_content_provenance_closed_against_active_same_sid_replacement=$true
        active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance=$true
        package_plan_stage_bindings_verified=$true;payload_nsh_raw_byte_binding_verified=$true
        execution_logic_read_leases_held_through_seal=$true
        extraction_root_and_expected_directory_identity_leases_held_through_seal=$true
        installer_expected_directory_lease_count=[int]$topExpectedDirectoryLeases.Count
        uninstaller_expected_directory_lease_count=[int]$unExpectedDirectoryLeases.Count
        installer_extracted_file_read_lease_count=[int]$topExtractedFileLeases.Count
        uninstaller_extracted_file_read_lease_count=[int]$unExtractedFileLeases.Count
        extracted_file_read_leases_held_through_seal=$true
        raw_generated_uninstaller_capture_read_lease_held_through_seal=$true
        result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass=$true
        text_logs_create_new_memory_digest_bound_and_leased_through_result_seal=$true
        installer_read_lease_held_for_all_reads=$true;uninstaller_read_lease_held_for_all_reads=$true
        seven_zip_read_lease_held_for_all_calls=$true;seven_zip_parser_library_read_lease_held_for_all_calls=$true
        seven_zip_call_count=197;seven_zip_text_call_count=5;seven_zip_per_entry_raw_stdout_call_count=192
        generated_uninstaller_present=$true;generated_uninstaller_verified=$false
        generated_uninstaller_static_archive_member_verified=$true
        generated_uninstaller_trusted=$false;uninstaller_trust_state='unsigned-disabled-static-observation-only'
        final_payload_closure=$false;delivery_admitted=$false;extractor_process_executed=$true
        actual_installer_or_uninstaller_executed=$false;product_process_started_or_stopped=$false
        registry_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
        installed_yimecore_local12_touched=$false
        helper_source_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $resultPath=Join-Path $evidence 'result.json'
    $null=Assert-RimePimePostbuildDirectoryLease $outputDirectoryLease
    $null=Assert-RimePimePostbuildDirectoryLease $topDirectoryLease
    $null=Assert-RimePimePostbuildDirectoryLease $unDirectoryLease
    $null=Assert-RimePimePostbuildDirectoryLease $evidenceDirectoryLease
    $null=Test-RimePimePostbuildDirectoryLeases $topExpectedDirectoryLeases
    $null=Test-RimePimePostbuildDirectoryLeases $unExpectedDirectoryLeases
    $null=Test-RimePimePostbuildExtractedFileLeases @($topExtractedFileLeases) 181
    $null=Test-RimePimePostbuildExtractedFileLeases @($unExtractedFileLeases) 11
    $null=Assert-RimePimePostbuildReadLease $installerLease
    $null=Assert-RimePimePostbuildReadLease $uninstallerLease
    $null=Assert-RimePimePostbuildReadLease $sevenZipLibraryLease
    $null=Assert-RimePimePostbuildReadLease $sevenZipLease
    foreach($lease in @($logFileLeases)){$null=Assert-RimePimePostbuildReadLease $lease}
    $executionLogicEvidence=@(Test-RimePimePostbuildExecutionLogicLeases $ExecutionLogicLeases)
    $nsisClosureEvidence=Test-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure
    $resultSeal=Write-RimePimePostbuildSealedJson $result $resultPath
    $null=Assert-RimePimePostbuildReadLease $resultSeal.JsonLease
    $null=Assert-RimePimePostbuildReadLease $resultSeal.SidecarLease
    $null=Assert-RimePimePostbuildDirectoryLease $outputDirectoryLease
    $null=Assert-RimePimePostbuildDirectoryLease $evidenceDirectoryLease
    $passFiles=@($resultSeal.JsonLease,$resultSeal.SidecarLease)+@($nsisCompilerInputClosure.ControlLeases)+@($nsisCompilerInputClosure.FileLeases)
    $passDirectories=@($outputDirectoryLease,$evidenceDirectoryLease)+@($nsisCompilerInputClosure.DirectoryLeases)
    $returnValue=[pscustomobject]@{
        Result=$result;ResultPath=$resultSeal.Path;ResultDigest=$resultSeal.Digest
        PassFileLeases=@($passFiles)
        PassDirectoryLeases=@($passDirectories)
    }
    $resultSeal=$null;$outputDirectoryLease=$null;$evidenceDirectoryLease=$null;$nsisCompilerInputClosure=$null
    return $returnValue
    }finally{
        if($null -ne $resultSeal){
            if($null -ne $resultSeal.SidecarLease){$resultSeal.SidecarLease.Stream.Dispose()}
            if($null -ne $resultSeal.JsonLease){$resultSeal.JsonLease.Stream.Dispose()}
        }
        if($null -ne $evidenceDirectoryLease){$evidenceDirectoryLease.Native.Dispose()}
        foreach($lease in @($logFileLeases)){if($null -ne $lease){$lease.Stream.Dispose()}}
        foreach($lease in @($unExtractedFileLeases)){if($null -ne $lease){$lease.Stream.Dispose()}}
        foreach($lease in @($topExtractedFileLeases)){if($null -ne $lease){$lease.Stream.Dispose()}}
        foreach($lease in @($unExpectedDirectoryLeases)){if($null -ne $lease){$lease.Native.Dispose()}}
        foreach($lease in @($topExpectedDirectoryLeases)){if($null -ne $lease){$lease.Native.Dispose()}}
        if($null -ne $unDirectoryLease){$unDirectoryLease.Native.Dispose()}
        if($null -ne $topDirectoryLease){$topDirectoryLease.Native.Dispose()}
        if($null -ne $outputDirectoryLease){$outputDirectoryLease.Native.Dispose()}
        if($null -ne $installerLease){$installerLease.Stream.Dispose()}
        if($null -ne $sevenZipLibraryLease){$sevenZipLibraryLease.Stream.Dispose()}
        if($null -ne $sevenZipLease){$sevenZipLease.Stream.Dispose()}
        if($null -ne $nsisCompilerInputClosure){Close-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure}
    }
}
