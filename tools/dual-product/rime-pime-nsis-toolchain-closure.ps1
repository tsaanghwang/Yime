# Repository-pinned NSIS compiler-distribution input closure. Definitions only.
#
# This contract deliberately excludes Windows loader DLLs, process environment,
# time, scheduling and kernel/filesystem implementation. It proves every known
# file in the pinned distribution is held under a read/no-delete lease and that
# the directory tree is exact whenever tested. Windows directory handles do not
# freeze child membership, so a same-SID process could transiently add and then
# remove a plug-in between tests. This helper therefore cannot by itself prove
# complete non-OS compiler input closure.
$script:RimePimeNsisClosureLockFile='rime-pime-postbuild-toolchain-lock.json'
$script:RimePimeNsisClosureLockSha256='01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45'
$script:RimePimeNsisClosureLockSchema='yime-rime-pime-postbuild-toolchain-lock-v2'
$script:RimePimeNsisClosureToolchainId='mycomputer-rime-pime-nsis-static-x86-x64-v2'
$script:RimePimeNsisClosureScope='repository-pinned-nsis-distribution-non-os-v1'
$script:RimePimeNsisClosureTreeAlgorithm='sha256-directory-then-file-tab-records-utf8-lf-v1'
$script:RimePimeNsisClosureDirectoryLeaseTypeInitialized=$false

function Get-RimePimeNsisClosureSha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function ConvertTo-RimePimeNsisClosureRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or
        [IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or $Path.Contains('//') -or
        $Path.StartsWith('/') -or $Path.EndsWith('/') -or
        -not $Path.IsNormalized([Text.NormalizationForm]::FormC)){
        throw "Non-canonical NSIS closure path rejected: $Path"
    }
    foreach($segment in $Path.Split('/')){
        if(-not $segment -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){
            throw "Ambiguous NSIS closure path rejected: $Path"
        }
    }
    return $Path
}

function Resolve-RimePimeNsisClosurePath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath)
    $rootFull=(Assert-YimePimePayloadAbsolutePath $Root).TrimEnd([char]92)
    $relative=ConvertTo-RimePimeNsisClosureRelativePath $RelativePath
    $full=[IO.Path]::GetFullPath((Join-Path $rootFull $relative.Replace('/','\')))
    if(-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw "NSIS closure path escapes its root: $relative"
    }
    return $full
}

function Initialize-RimePimeNsisClosureDirectoryLeaseType {
    $existing='YimePime.NsisToolchain.DirectoryLeasesV1' -as [type]
    if($script:RimePimeNsisClosureDirectoryLeaseTypeInitialized){
        $identity=$existing.GetProperty('ImplementationId',[Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)
        if($null -eq $identity -or [string]$identity.GetValue($null,$null) -cne 'yime-rime-pime-nsis-toolchain-directory-leases-v1'){
            throw 'Loaded NSIS toolchain directory lease type has an untrusted identity.'
        }
        return
    }
    if($null -ne $existing){throw 'An NSIS toolchain directory lease type was preloaded outside this verified module instance.'}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace YimePime.NsisToolchain {
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
        internal DirectoryLease(SafeFileHandle handle,string fileId) { Handle=handle; FileId=fileId; }
        public void Dispose() { if(Handle != null) Handle.Dispose(); }
    }
    public static class DirectoryLeasesV1 {
        public static string ImplementationId { get { return "yime-rime-pime-nsis-toolchain-directory-leases-v1"; } }
        private const uint FILE_LIST_DIRECTORY=1;
        private const uint FILE_SHARE_READ=1;
        private const uint FILE_SHARE_WRITE=2;
        private const uint OPEN_EXISTING=3;
        private const uint FILE_FLAG_BACKUP_SEMANTICS=0x02000000;
        private const uint FILE_ATTRIBUTE_DIRECTORY=0x10;
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        private static extern SafeFileHandle CreateFileW(string path,uint access,uint share,
            IntPtr security,uint creation,uint flags,IntPtr template);
        [DllImport("kernel32.dll",SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle,
            out BY_HANDLE_FILE_INFORMATION info);
        private static string InspectHandle(SafeFileHandle handle) {
            BY_HANDLE_FILE_INFORMATION info;
            if(!GetFileInformationByHandle(handle,out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)==0) throw new InvalidOperationException("Path is not a directory.");
            return String.Format("{0:x8}:{1:x8}{2:x8}",info.VolumeSerialNumber,info.FileIndexHigh,info.FileIndexLow);
        }
        public static DirectoryLease Open(string path) {
            SafeFileHandle handle=CreateFileW(path,FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,
                IntPtr.Zero,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,IntPtr.Zero);
            if(handle.IsInvalid) { int error=Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error); }
            try { return new DirectoryLease(handle,InspectHandle(handle)); }
            catch { handle.Dispose(); throw; }
        }
        public static string Inspect(string path) { using(DirectoryLease lease=Open(path)) return lease.FileId; }
    }
}
'@
    $script:RimePimeNsisClosureDirectoryLeaseTypeInitialized=$true
}

function Open-RimePimeNsisClosureDirectoryLease {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    if(-not(Test-Path -LiteralPath $full -PathType Container)){throw "$Context directory is missing."}
    Assert-RimePimeNoReparsePath $full
    Initialize-RimePimeNsisClosureDirectoryLeaseType
    $native=[YimePime.NsisToolchain.DirectoryLeasesV1]::Open($full)
    try{
        $item=Get-Item -LiteralPath $full -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$Context directory is a reparse point."}
        $pathId=[YimePime.NsisToolchain.DirectoryLeasesV1]::Inspect($full)
        if([string]$native.FileId -cne [string]$pathId){throw "$Context directory identity changed while acquiring its lease."}
        return [pscustomobject][ordered]@{Path=$full;Context=$Context;FileId=[string]$native.FileId;Native=$native}
    }catch{$native.Dispose();throw}
}

function Assert-RimePimeNsisClosureDirectoryLease {
    param([Parameter(Mandatory)]$Lease)
    if($null -eq $Lease -or $null -eq $Lease.Native -or $Lease.Native.Handle.IsClosed){throw 'NSIS directory lease is invalid or closed.'}
    $full=Assert-YimePimePayloadAbsolutePath ([string]$Lease.Path)
    Assert-RimePimeNoReparsePath $full
    if(-not(Test-Path -LiteralPath $full -PathType Container)){throw "$($Lease.Context) directory disappeared while leased."}
    $item=Get-Item -LiteralPath $full -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$($Lease.Context) directory became a reparse point."}
    $pathId=[YimePime.NsisToolchain.DirectoryLeasesV1]::Inspect($full)
    if([string]$pathId -cne [string]$Lease.FileId){throw "$($Lease.Context) directory identity changed while leased."}
    return $true
}

function Get-RimePimeNsisClosureStreamRecord {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    if(-not $Stream.CanRead -or -not $Stream.CanSeek){throw 'NSIS file lease is closed or not seekable.'}
    $position=$Stream.Position
    try{
        $Stream.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
        try{$digest=([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
        finally{$sha.Dispose()}
        return [pscustomobject][ordered]@{bytes=[long]$Stream.Length;sha256=$digest}
    }finally{$Stream.Position=$position}
}

function Open-RimePimeNsisClosureFileLease {
    param([Parameter(Mandatory)][string]$Path,$ExpectedRecord,[Parameter(Mandatory)][string]$Context)
    $full=Assert-YimePimePayloadAbsolutePath $Path
    Assert-RimePimeNoReparsePath $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $streamRecord=Get-RimePimeNsisClosureStreamRecord $stream
        $pathRecord=Get-YimePimePayloadFileRecord $full
        if([long]$streamRecord.bytes -ne [long]$pathRecord.bytes -or
            [string]$streamRecord.sha256 -cne [string]$pathRecord.sha256){throw "$Context path and leased handle differ."}
        if($null -ne $ExpectedRecord -and
            ([long]$streamRecord.bytes -ne [long]$ExpectedRecord.bytes -or
             [string]$streamRecord.sha256 -cne [string]$ExpectedRecord.sha256)){
            throw "$Context differs from the repository-pinned record."
        }
        return [pscustomobject][ordered]@{
            Path=$full;Context=$Context;Stream=$stream
            Record=[pscustomobject][ordered]@{bytes=[long]$streamRecord.bytes;sha256=[string]$streamRecord.sha256;file_id=[string]$pathRecord.file_id}
        }
    }catch{$stream.Dispose();throw}
}

function Assert-RimePimeNsisClosureFileLease {
    param([Parameter(Mandatory)]$Lease)
    if($null -eq $Lease -or $null -eq $Lease.Stream -or -not $Lease.Stream.CanRead){throw 'NSIS file lease is invalid or closed.'}
    $streamRecord=Get-RimePimeNsisClosureStreamRecord $Lease.Stream
    $pathRecord=Get-YimePimePayloadFileRecord ([string]$Lease.Path)
    if([long]$streamRecord.bytes -ne [long]$Lease.Record.bytes -or
        [string]$streamRecord.sha256 -cne [string]$Lease.Record.sha256 -or
        [long]$pathRecord.bytes -ne [long]$Lease.Record.bytes -or
        [string]$pathRecord.sha256 -cne [string]$Lease.Record.sha256 -or
        [string]$pathRecord.file_id -cne [string]$Lease.Record.file_id){
        throw "$($Lease.Context) changed while its NSIS input lease was held."
    }
    return $true
}

function Get-RimePimeNsisCompilerInputTreeSnapshot {
    param([Parameter(Mandatory)][string]$NsisRoot,[Parameter(Mandatory)]$ClosureRecord)
    $root=(Assert-YimePimePayloadAbsolutePath $NsisRoot).TrimEnd([char]92)
    Assert-RimePimeNoReparsePath $root
    if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'Pinned NSIS root is missing.'}
    $directoryMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $fileMap=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $roots=@($ClosureRecord.roots)
    if($roots.Count -lt 1 -or $roots.Count -gt 16){throw 'NSIS compiler closure root count is invalid.'}
    $previousRoot=$null
    foreach($rootRecord in $roots){
        Assert-YimePimePayloadProperties $rootRecord @('path','directory_count','file_count') 'NSIS compiler closure root'
        $relative=ConvertTo-RimePimeNsisClosureRelativePath ([string]$rootRecord.path)
        if($null -ne $previousRoot -and [StringComparer]::Ordinal.Compare($previousRoot,$relative) -ge 0){throw 'NSIS closure roots are not in canonical ordinal order.'}
        $previousRoot=$relative
        $full=Resolve-RimePimeNsisClosurePath $root $relative
        if(-not(Test-Path -LiteralPath $full -PathType Container)){throw "NSIS closure root is missing: $relative"}
        Assert-RimePimeNoReparsePath $full
        foreach($directory in @((Get-Item -LiteralPath $full -Force)) + @(Get-ChildItem -LiteralPath $full -Recurse -Force -Directory)){
            if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse directory rejected from NSIS closure: $($directory.FullName)"}
            $path=$directory.FullName.Substring($root.Length+1).Replace('\','/')
            $path=ConvertTo-RimePimeNsisClosureRelativePath $path
            if($directoryMap.ContainsKey($path)){throw "Overlapping or case-folded NSIS closure directory rejected: $path"}
            $directoryMap.Add($path,$directory.FullName)
        }
        foreach($file in Get-ChildItem -LiteralPath $full -Recurse -Force -File){
            $path=ConvertTo-RimePimeNsisClosureRelativePath $file.FullName.Substring($root.Length+1).Replace('\','/')
            if($fileMap.ContainsKey($path)){throw "Overlapping or case-folded NSIS closure file rejected: $path"}
            $record=Get-YimePimePayloadFileRecord $file.FullName
            $fileMap.Add($path,[pscustomobject][ordered]@{
                path=$path;full_path=$file.FullName;bytes=[long]$record.bytes;sha256=[string]$record.sha256;file_id=[string]$record.file_id
            })
        }
        $prefix=$relative+'/'
        $rootDirectoryCount=@($directoryMap.Keys|Where-Object{$_ -ceq $relative -or $_.StartsWith($prefix,[StringComparison]::Ordinal)}).Count
        $rootFileCount=@($fileMap.Keys|Where-Object{$_.StartsWith($prefix,[StringComparison]::Ordinal)}).Count
        if(-not(Test-RimePimeStageInteger $rootRecord.directory_count) -or -not(Test-RimePimeStageInteger $rootRecord.file_count) -or
            [int]$rootRecord.directory_count -ne $rootDirectoryCount -or [int]$rootRecord.file_count -ne $rootFileCount){
            throw "NSIS closure root exact-set count differs: $relative"
        }
    }
    $directoryPaths=[string[]]@($directoryMap.Keys);[Array]::Sort($directoryPaths,[StringComparer]::Ordinal)
    $filePaths=[string[]]@($fileMap.Keys);[Array]::Sort($filePaths,[StringComparer]::Ordinal)
    $builder=[Text.StringBuilder]::new()
    foreach($path in $directoryPaths){$null=$builder.Append("D`t$path`n")}
    $files=[Collections.Generic.List[object]]::new()
    foreach($path in $filePaths){
        $row=$fileMap[$path];$null=$builder.Append("F`t$path`t$($row.bytes)`t$($row.sha256)`n");$files.Add($row)
    }
    $canonicalBytes=[Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
    $digest=Get-RimePimeNsisClosureSha256Bytes $canonicalBytes
    if(-not(Test-RimePimeStageInteger $ClosureRecord.directory_count) -or
        -not(Test-RimePimeStageInteger $ClosureRecord.file_count) -or
        -not(Test-RimePimeStageInteger $ClosureRecord.canonical_tree_bytes) -or
        [int]$ClosureRecord.directory_count -ne $directoryPaths.Count -or
        [int]$ClosureRecord.file_count -ne $filePaths.Count -or
        [int]$ClosureRecord.canonical_tree_bytes -ne $canonicalBytes.Length -or
        [string]$ClosureRecord.tree_sha256 -cne $digest){
        throw 'NSIS compiler input tree differs from the repository-pinned exact set.'
    }
    $previousRequired=$null
    foreach($required in @($ClosureRecord.required_inputs)){
        Assert-YimePimePayloadProperties $required @('class','path') 'NSIS compiler required input'
        if([string]$required.class -notin @('compiler','compiler-runtime','include','locale','plugin-scan','resource','stub')){throw 'NSIS compiler required input class is invalid.'}
        $path=ConvertTo-RimePimeNsisClosureRelativePath ([string]$required.path)
        if($null -ne $previousRequired -and [StringComparer]::Ordinal.Compare($previousRequired,$path) -ge 0){throw 'NSIS required inputs are not in canonical ordinal order.'}
        $previousRequired=$path
        if(-not $fileMap.ContainsKey($path)){throw "Required NSIS compiler input is outside the exact tree: $path"}
    }
    return [pscustomobject][ordered]@{
        root=$root;scope=[string]$ClosureRecord.scope;tree_sha256=$digest
        canonical_tree_bytes=[int]$canonicalBytes.Length;directory_count=[int]$directoryPaths.Count;file_count=[int]$filePaths.Count
        directory_paths=@($directoryPaths);files=@($files)
    }
}

function Test-RimePimeNsisCompilerToolchainLockDocument {
    param([Parameter(Mandatory)]$Value)
    $canonical=(ConvertTo-RimePimeStageCanonicalJson $Value)+"`n"
    $digest=Get-RimePimeNsisClosureSha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($canonical))
    if($digest -cne $script:RimePimeNsisClosureLockSha256){throw 'NSIS toolchain lock is not the code-pinned identity.'}
    Assert-YimePimePayloadProperties $Value @('schema_version','toolchain_id','package_profile','seven_zip','nsis') 'NSIS toolchain lock'
    Assert-YimePimePayloadProperties $Value.nsis @('root','makensis','compiler_input_closure','support') 'NSIS toolchain record'
    Assert-YimePimePayloadProperties $Value.nsis.compiler_input_closure @(
        'scope','canonical_tree_algorithm','roots','directory_count','file_count','canonical_tree_bytes','tree_sha256','required_inputs') 'NSIS compiler input closure'
    if([string]$Value.schema_version -cne $script:RimePimeNsisClosureLockSchema -or
        [string]$Value.toolchain_id -cne $script:RimePimeNsisClosureToolchainId -or
        [string]$Value.package_profile -cne 'x86-x64-v1' -or
        [string]$Value.nsis.compiler_input_closure.scope -cne $script:RimePimeNsisClosureScope -or
        [string]$Value.nsis.compiler_input_closure.canonical_tree_algorithm -cne $script:RimePimeNsisClosureTreeAlgorithm -or
        [string]$Value.nsis.compiler_input_closure.tree_sha256 -cnotmatch '^[0-9a-f]{64}$'){
        throw 'NSIS compiler input closure identity is invalid.'
    }
    $root=[string]$Value.nsis.root
    if($root -cne 'C:/Program Files (x86)/NSIS'){throw 'NSIS compiler root is not the repository-pinned installation.'}
    if([string]$Value.nsis.makensis.relative_path -cne 'Bin/makensis.exe'){throw 'NSIS compiler executable path is invalid.'}
    return $true
}

function Read-RimePimeNsisCompilerToolchainLockDocument {
    $path=Join-Path $PSScriptRoot $script:RimePimeNsisClosureLockFile
    $sealed=Read-RimePimeSealedJson $path 'NSIS compiler toolchain lock'
    if([string]$sealed.Digest -cne $script:RimePimeNsisClosureLockSha256){throw 'NSIS compiler toolchain lock differs from the digest pinned in code.'}
    $strictUtf8=[Text.UTF8Encoding]::new($false,$true)
    try{$raw=$strictUtf8.GetString([IO.File]::ReadAllBytes($sealed.Path))}catch{throw "NSIS compiler toolchain lock is not strict UTF-8: $($_.Exception.Message)"}
    if($raw -cne ((ConvertTo-RimePimeStageCanonicalJson $sealed.Value)+"`n")){throw 'NSIS compiler toolchain lock is not canonical single-line JSON.'}
    $null=Test-RimePimeNsisCompilerToolchainLockDocument $sealed.Value
    return [pscustomobject][ordered]@{Path=$sealed.Path;Sidecar=$sealed.Sidecar;Digest=$sealed.Digest;Document=$sealed.Value}
}

function Open-RimePimeNsisCompilerInputClosureCore {
    param([Parameter(Mandatory)][string]$NsisRoot,[Parameter(Mandatory)]$ClosureRecord)
    $snapshot=Get-RimePimeNsisCompilerInputTreeSnapshot $NsisRoot $ClosureRecord
    $directoryLeases=[Collections.Generic.List[object]]::new();$fileLeases=[Collections.Generic.List[object]]::new()
    try{
        $directoryPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $null=$directoryPaths.Add($snapshot.root)
        foreach($relative in @($snapshot.directory_paths)){
            $full=Resolve-RimePimeNsisClosurePath $snapshot.root ([string]$relative)
            $null=$directoryPaths.Add($full)
            for($cursor=Split-Path -Parent $full;$cursor -and $cursor.StartsWith($snapshot.root+'\',[StringComparison]::OrdinalIgnoreCase);$cursor=Split-Path -Parent $cursor){$null=$directoryPaths.Add($cursor)}
        }
        $orderedDirectories=[string[]]@($directoryPaths);[Array]::Sort($orderedDirectories,[StringComparer]::Ordinal)
        foreach($path in $orderedDirectories){$directoryLeases.Add((Open-RimePimeNsisClosureDirectoryLease $path 'NSIS compiler distribution'))}
        foreach($row in @($snapshot.files)){
            $fileLeases.Add((Open-RimePimeNsisClosureFileLease ([string]$row.full_path) $row "NSIS compiler input $($row.path)"))
        }
        $after=Get-RimePimeNsisCompilerInputTreeSnapshot $snapshot.root $ClosureRecord
        if([string]$after.tree_sha256 -cne [string]$snapshot.tree_sha256 -or
            [int]$after.file_count -ne [int]$snapshot.file_count -or [int]$after.directory_count -ne [int]$snapshot.directory_count){throw 'NSIS compiler input tree changed while leases were acquired.'}
        foreach($lease in @($fileLeases)){$null=Assert-RimePimeNsisClosureFileLease $lease}
        foreach($lease in @($directoryLeases)){$null=Assert-RimePimeNsisClosureDirectoryLease $lease}
        return [pscustomobject][ordered]@{
            NsisRoot=$snapshot.root;Scope=[string]$ClosureRecord.scope;TreeSha256=[string]$snapshot.tree_sha256
            CanonicalTreeBytes=[int]$snapshot.canonical_tree_bytes;FileCount=[int]$snapshot.file_count
            DirectoryCount=[int]$snapshot.directory_count;FileLeases=@($fileLeases);DirectoryLeases=@($directoryLeases)
            ControlLeases=@();ToolchainLockPath=$null;ToolchainLockDigest=$null;Closed=$false
        }
    }catch{
        foreach($lease in @($fileLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
        foreach($lease in @($directoryLeases)){if($null -ne $lease.Native){$lease.Native.Dispose()}}
        throw
    }
}

function Open-RimePimeNsisCompilerInputClosure {
    $lock=Read-RimePimeNsisCompilerToolchainLockDocument
    $root=([string]$lock.Document.nsis.root).Replace('/','\')
    $closure=$null;$controls=[Collections.Generic.List[object]]::new()
    try{
        $lockRecord=Get-YimePimePayloadFileRecord $lock.Path
        $sidecarRecord=Get-YimePimePayloadFileRecord $lock.Sidecar
        $controls.Add((Open-RimePimeNsisClosureFileLease $lock.Path $lockRecord 'NSIS toolchain lock'))
        $controls.Add((Open-RimePimeNsisClosureFileLease $lock.Sidecar $sidecarRecord 'NSIS toolchain lock sidecar'))
        $closure=Open-RimePimeNsisCompilerInputClosureCore $root $lock.Document.nsis.compiler_input_closure
        $closure.ControlLeases=@($controls);$closure.ToolchainLockPath=$lock.Path;$closure.ToolchainLockDigest=$lock.Digest
        $null=Test-RimePimeNsisCompilerInputClosure $closure
        return $closure
    }catch{
        if($null -ne $closure){Close-RimePimeNsisCompilerInputClosure $closure}
        else{foreach($lease in @($controls)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}}
        throw
    }
}

function Test-RimePimeNsisCompilerInputClosure {
    param([Parameter(Mandatory)]$Closure)
    if($null -eq $Closure -or $Closure.Closed -or [string]$Closure.Scope -cne $script:RimePimeNsisClosureScope -or
        [string]$Closure.TreeSha256 -cnotmatch '^[0-9a-f]{64}$' -or @($Closure.FileLeases).Count -ne [int]$Closure.FileCount -or
        @($Closure.ControlLeases).Count -ne 2){throw 'NSIS compiler input closure object is invalid or closed.'}
    foreach($lease in @($Closure.ControlLeases)){$null=Assert-RimePimeNsisClosureFileLease $lease}
    foreach($lease in @($Closure.FileLeases)){$null=Assert-RimePimeNsisClosureFileLease $lease}
    foreach($lease in @($Closure.DirectoryLeases)){$null=Assert-RimePimeNsisClosureDirectoryLease $lease}
    $lock=Read-RimePimeNsisCompilerToolchainLockDocument
    if([string]$lock.Digest -cne [string]$Closure.ToolchainLockDigest){throw 'NSIS compiler toolchain lock changed while the closure was active.'}
    $snapshot=Get-RimePimeNsisCompilerInputTreeSnapshot $Closure.NsisRoot $lock.Document.nsis.compiler_input_closure
    if([string]$snapshot.tree_sha256 -cne [string]$Closure.TreeSha256 -or [int]$snapshot.file_count -ne [int]$Closure.FileCount -or
        [int]$snapshot.directory_count -ne [int]$Closure.DirectoryCount){throw 'NSIS compiler distribution changed while the closure was active.'}
    return [pscustomobject][ordered]@{
        nsis_toolchain_lock_sha256=[string]$Closure.ToolchainLockDigest
        nsis_compiler_input_scope=[string]$Closure.Scope;nsis_compiler_input_tree_sha256=[string]$Closure.TreeSha256
        nsis_compiler_input_file_count=[int]$Closure.FileCount;nsis_compiler_input_directory_count=[int]$Closure.DirectoryCount
        nsis_compiler_input_read_lease_count=[int]@($Closure.FileLeases).Count
        nsis_compiler_input_directory_lease_count=[int]@($Closure.DirectoryLeases).Count
        nsis_compiler_input_anchor_directory_lease_count=[int](@($Closure.DirectoryLeases).Count-[int]$Closure.DirectoryCount)
        nsis_toolchain_control_read_lease_count=[int]@($Closure.ControlLeases).Count
        nsis_distribution_tree_exact_at_open_and_test=$true
        nsis_known_input_file_replacement_closure=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
    }
}

function Close-RimePimeNsisCompilerInputClosure {
    param([Parameter(Mandatory)]$Closure)
    if($null -eq $Closure -or $Closure.Closed){return}
    foreach($lease in @($Closure.ControlLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
    foreach($lease in @($Closure.FileLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
    foreach($lease in @($Closure.DirectoryLeases)){if($null -ne $lease.Native){$lease.Native.Dispose()}}
    $Closure.Closed=$true
}
