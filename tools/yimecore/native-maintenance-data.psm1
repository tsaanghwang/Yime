Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:DataSchema='yimecore-native-maintenance-data-v1'
$script:DataFiles=@('learning.json','professional-lexicons.json','speech.json','yime_blocklist.txt','yime_user_phrases.txt','yimecore_experimental_toolbar_state.json')
$script:DataFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:DataNativeNamespace='Yime.MaintenanceData_'+[guid]::NewGuid().ToString('N')
$script:DataFactsType=$null
$script:DataPathsType=$null

function Assert-YcDataRoot($Path) {
    # A caller must name the exact root; no user-profile/default/install lookup.
    if($Path -isnot [string] -or $Path -cnotmatch '^[A-Z]:\\[^\\]' -or $Path -match '[/\x00-\x1f"<>|?*]' -or $Path.Substring(2).Contains(':') -or
        $Path.EndsWith('\') -or $Path -match '\\\\|\\(\.|\.\.)(\\|$)|[. ](\\|$)' -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'Explicit canonical StateRoot required'}
}
function Assert-YcDataRelative($Path) {
    if($Path -isnot [string] -or [string]::IsNullOrEmpty($Path) -or $Path -match '[\\:\x00-\x1f"<>|?*]|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)' -or
        $Path -match '(?i)(^|/)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|/|$)'){throw 'Invalid data member path'}
}
function Assert-YcDataPlain([string]$Path) {
    $cursor=$Path
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect data path rejected'}
        $parent=Split-Path -Parent $cursor;if(-not $parent -or $parent -ceq $cursor){break};$cursor=$parent
    }
}
function Get-YcDataStreamHash([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$Stream.Position=0;$sha.Dispose()}
}
function Get-YcDataDigest($Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 30 -Compress))))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Initialize-YcDataNative {
    # Compile source-owned facts only. No package scripts or executables loaded.
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))
    Assert-YcDataPlain $source
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if((Get-YcDataStreamHash $stream) -cne $script:DataFactsHash){throw 'Reviewed native data facts source changed'}
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    # Never adopt a caller-preloaded global type as native evidence. Retain the
    # actual Type compiled from reviewed bytes in this module's random namespace.
    if($null -eq $script:DataFactsType){
        $types=@(Add-Type -TypeDefinition ($text.Replace('namespace Yime.Dp1UNative {',('namespace '+$script:DataNativeNamespace+' {'))) -PassThru)
        $script:DataFactsType=@($types|Where-Object {$_.FullName -ceq ($script:DataNativeNamespace+'.Facts')})[0]
    }
    if($null -eq $script:DataPathsType){$pathSource=@'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Yime {
    public static class MaintenanceDataPaths {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,out AttributeTag info,uint size);
        [StructLayout(LayoutKind.Sequential)] private struct AttributeTag {public uint Attributes,Tag;}
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct StreamData {
            public long Size;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)] public string Name;
        }
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr FindFirstStreamW(string path,int level,out StreamData data,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool FindNextStreamW(IntPtr handle,out StreamData data);
        [DllImport("kernel32.dll")] private static extern bool FindClose(IntPtr handle);
        public static SafeFileHandle OpenDirectory(string path) {
            // LIST_DIRECTORY is required for sharing checks to deny rename.
            // READ_ATTRIBUTES alone (0x80) does not hold a rename barrier.
            var handle=CreateFile(path,0x81,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
            if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
            try{VerifyDirectory(handle,path);return handle;}catch{handle.Dispose();throw;}
        }
        public static void VerifyDirectory(SafeFileHandle handle,string path) {
            AttributeTag info;
            if(!GetFileInformationByHandleEx(handle,9,out info,8))throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.Attributes&0x10)==0 || (info.Attributes&0x400)!=0)throw new InvalidOperationException("Indirect or non-directory data path.");
            var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(handle,final,(uint)final.Capacity,0);
            if(n==0 || n>=final.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());
            if(!String.Equals(final.ToString(),@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Data directory final path mismatch.");
        }
        public static void RejectNamedStreams(string path) {
            StreamData data;IntPtr handle=FindFirstStreamW(path,0,out data,0);
            if(handle==new IntPtr(-1)) {
                int error=Marshal.GetLastWin32Error();
                if(error==38)return; // ERROR_HANDLE_EOF: directory has no streams.
                throw new Win32Exception(error); // Unsupported/denied enumeration is not success.
            }
            try {
                do{if(!String.Equals(data.Name,"::$DATA",StringComparison.Ordinal))throw new InvalidOperationException("Named data stream rejected.");}
                while(FindNextStreamW(handle,out data));
                int error=Marshal.GetLastWin32Error();if(error!=38)throw new Win32Exception(error);
            } finally {FindClose(handle);}
        }
    }
}
'@
        $types=@(Add-Type -TypeDefinition ($pathSource.Replace('namespace Yime {',('namespace '+$script:DataNativeNamespace+' {'))) -PassThru)
        $script:DataPathsType=@($types|Where-Object {$_.FullName -ceq ($script:DataNativeNamespace+'.MaintenanceDataPaths')})[0]
    }
}
function Get-YcDataInventory([string]$Root,$Directories) {
    # Match Get-YimeCoreDataRecords' explicit categories, adding directory
    # metadata and a separate runtime-config fingerprint. Other state is ignored.
    $rows=[Collections.Generic.List[object]]::new();$seen=@{}
    $queue=[Collections.Generic.Queue[string]]::new()
    $script:DataPathsType::VerifyDirectory($Directories[''],$Root)
    foreach($item in Get-ChildItem -LiteralPath $Root -Force){
        if($item.Name -ieq 'user-model' -or $script:DataFiles -icontains $item.Name -or $item.Name -ieq 'runtime-config.json'){
            if($item.Name -cne 'user-model' -and $script:DataFiles -cnotcontains $item.Name -and $item.Name -cne 'runtime-config.json'){throw 'Noncanonical data category case'}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect data member rejected'}
            if($seen.ContainsKey($item.Name)){throw 'Duplicate data member case'};$seen[$item.Name]=$true
            if($item.Name -ceq 'user-model'){
                if(-not $item.PSIsContainer){throw 'user-model must be a directory'}
                if(-not $Directories.ContainsKey('user-model')){$Directories['user-model']=$script:DataPathsType::OpenDirectory($item.FullName)}
                $rows.Add([pscustomobject][ordered]@{path='user-model';kind='directory'});$queue.Enqueue($item.FullName)
            }else{
                if($item.PSIsContainer){throw 'Data file category is a directory'}
                $rows.Add([pscustomobject][ordered]@{path=$item.Name;kind='file'})
            }
        }
    }
    while($queue.Count){$dir=$queue.Dequeue()
        $dirRelative=$dir.Substring($Root.Length+1).Replace('\','/')
        # Acquire and verify each directory before descending. Checking a path
        # only after a recursive enumeration could already follow a raced link.
        $script:DataPathsType::VerifyDirectory($Directories[$dirRelative],$dir)
        $script:DataPathsType::RejectNamedStreams($dir)
        foreach($item in Get-ChildItem -LiteralPath $dir -Force){
            $relative=$item.FullName.Substring($Root.Length+1).Replace('\','/');Assert-YcDataRelative $relative
            if(-not $item.FullName.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Data member outside root'}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect data member rejected'}
            if($seen.ContainsKey($relative)){throw 'Duplicate data member case'};$seen[$relative]=$true
            $kind=if($item.PSIsContainer){'directory'}else{'file'}
            $rows.Add([pscustomobject][ordered]@{path=$relative;kind=$kind})
            if($item.PSIsContainer){
                if(-not $Directories.ContainsKey($relative)){$Directories[$relative]=$script:DataPathsType::OpenDirectory($item.FullName)}
                $queue.Enqueue($item.FullName)
            }
        }
    }
    # Ordinal ordering is stable across cultures and shells.
    $keys=[string[]]@($rows | ForEach-Object path);[Array]::Sort($keys,[StringComparer]::Ordinal)
    $map=@{};foreach($row in $rows){$map[$row.path]=$row};foreach($key in $keys){$map[$key]}
}
function Get-YcDataFileRecord([IO.FileStream]$Stream,[string]$Path,[string]$Relative) {
    $identity=$script:DataFactsType::VerifyFileHandle($Stream,$Path)
    $script:DataPathsType::RejectNamedStreams($Path)
    $length=$Stream.Length;$hash=Get-YcDataStreamHash $Stream
    if($Stream.Length -ne $length){throw 'Data length changed during observation'}
    [pscustomobject][ordered]@{path=$Relative;kind='file';bytes=$length;sha256=$hash;file_identity=$identity}
}
function Get-YcDataSnapshotBody($Snapshot) {
    [ordered]@{schema_version=$Snapshot.schema_version;state_root=$Snapshot.state_root;categories=$Snapshot.categories;records=$Snapshot.records;runtime_config=$Snapshot.runtime_config;
        observation=$Snapshot.observation;sharing_mode=$Snapshot.sharing_mode;ordinary_file_writers_excluded_during_observation=$Snapshot.ordinary_file_writers_excluded_during_observation;
        native_handle_paths_verified=$Snapshot.native_handle_paths_verified;single_link_files_verified=$Snapshot.single_link_files_verified;
        two_pass_equal=$Snapshot.two_pass_equal;atomic=$Snapshot.atomic;quiescent=$Snapshot.quiescent;continuous_membership_protection=$Snapshot.continuous_membership_protection;
        authenticated=$Snapshot.authenticated;execution_authorized=$Snapshot.execution_authorized}
}
function Get-YimeCoreNativeMaintenanceDataSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$StateRoot,[Parameter(Mandatory)]$BaselineSchemaVersion,[switch]$SharedObservation)
    Assert-YcDataRoot $StateRoot
    if($BaselineSchemaVersion -isnot [string] -or $BaselineSchemaVersion -cne $script:DataSchema){throw 'Unsupported data baseline schema'}
    Assert-YcDataPlain $StateRoot;Initialize-YcDataNative
    $dirs=@{};$files=@{}
    try{
        $dirs['']=$script:DataPathsType::OpenDirectory($StateRoot)
        $script:DataPathsType::RejectNamedStreams($StateRoot)
        $inventory=@(Get-YcDataInventory $StateRoot $dirs)
        $records=[Collections.Generic.List[object]]::new();$runtime=[pscustomobject][ordered]@{path='runtime-config.json';kind='absent'}
        foreach($row in $inventory){
            $path=Join-Path $StateRoot $row.path;Assert-YcDataPlain $path
            if($row.kind -ceq 'directory'){
                $script:DataPathsType::VerifyDirectory($dirs[$row.path],$path)
                $script:DataPathsType::RejectNamedStreams($path)
                $records.Add([pscustomobject][ordered]@{path=$row.path;kind='directory'})
            }else{
                $sharing=if($SharedObservation){[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete}else{[IO.FileShare]::Read}
                $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$sharing);$files[$row.path]=$stream
                $record=Get-YcDataFileRecord $stream $path $row.path
                if($row.path -ceq 'runtime-config.json'){$runtime=$record}else{$records.Add($record)}
            }
        }
        if((Get-YcDataDigest $inventory) -cne (Get-YcDataDigest @(Get-YcDataInventory $StateRoot $dirs))){throw 'Data membership changed during observation'}
        foreach($relative in $dirs.Keys){$path=if($relative){Join-Path $StateRoot $relative}else{$StateRoot}
            $script:DataPathsType::VerifyDirectory($dirs[$relative],$path);$script:DataPathsType::RejectNamedStreams($path)
        }
        foreach($record in @($records.ToArray())+@($runtime)){
            if($record.kind -ceq 'file'){
                $again=Get-YcDataFileRecord $files[$record.path] (Join-Path $StateRoot $record.path) $record.path
                if((Get-YcDataDigest $record) -cne (Get-YcDataDigest $again)){throw 'Data bytes or identity changed during observation'}
            }
        }
        if((Get-YcDataDigest $inventory) -cne (Get-YcDataDigest @(Get-YcDataInventory $StateRoot $dirs))){throw 'Data membership changed during final verification'}
        Assert-YcDataPlain $StateRoot
        $snapshot=[pscustomobject][ordered]@{schema_version=$script:DataSchema;state_root=$StateRoot;categories=@('user-model/')+$script:DataFiles;records=@($records.ToArray());runtime_config=$runtime;
            observation='process-local-native-file-handles';sharing_mode=$(if($SharedObservation){'read-write-delete'}else{'read'});ordinary_file_writers_excluded_during_observation=(-not [bool]$SharedObservation);
            native_handle_paths_verified=$true;single_link_files_verified=$true;two_pass_equal=$true;
            atomic=$false;quiescent=$false;continuous_membership_protection=$false;authenticated=$false;execution_authorized=$false}
        $snapshot|Add-Member -NotePropertyName snapshot_sha256 -NotePropertyValue (Get-YcDataDigest (Get-YcDataSnapshotBody $snapshot))
        return $snapshot
    }finally{
        foreach($stream in $files.Values){$stream.Dispose()}
        foreach($handle in $dirs.Values){$handle.Dispose()}
    }
}
function Assert-YcDataFields($Value,[string[]]$Names) {
    if($null -eq $Value -or ($Value -isnot [pscustomobject] -and $Value -isnot [Collections.IDictionary])){throw 'Data evidence object required'}
    $actual=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    if($actual.Count -ne $Names.Count){throw 'Unexpected data evidence fields'}
    foreach($name in $Names){if($actual -cnotcontains $name){throw 'Missing data evidence field'}}
}
function Assert-YcDataRecord($Row,[bool]$Runtime) {
    if($Row.kind -isnot [string]){throw 'Literal data record kind required'}
    $fields=if($Row.kind -ceq 'file'){@('path','kind','bytes','sha256','file_identity')}else{@('path','kind')}
    Assert-YcDataFields $Row $fields;Assert-YcDataRelative $Row.path
    if($Runtime){if($Row.path -cne 'runtime-config.json' -or $Row.kind -cnotin @('file','absent')){throw 'Invalid runtime-config fingerprint'}}
    elseif($Row.kind -cnotin @('file','directory') -or ($Row.path -cne 'user-model' -and -not $Row.path.StartsWith('user-model/',[StringComparison]::Ordinal) -and $script:DataFiles -cnotcontains $Row.path)){throw 'Out-of-category data record'}
    elseif(($Row.path -ceq 'user-model' -and $Row.kind -cne 'directory') -or ($script:DataFiles -ccontains $Row.path -and $Row.kind -cne 'file')){throw 'Invalid data category kind'}
    if($Row.kind -ceq 'file'){
        if(($Row.bytes -isnot [int] -and $Row.bytes -isnot [long]) -or $Row.bytes -lt 0 -or $Row.sha256 -isnot [string] -or $Row.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Row.file_identity -isnot [string] -or $Row.file_identity -cnotmatch '^[a-f0-9]{8}:[a-f0-9]{16}$'){throw 'Invalid data file metadata'}
    }
}
function Assert-YcDataSnapshot($Snapshot) {
    Assert-YcDataFields $Snapshot @('schema_version','state_root','categories','records','runtime_config','observation','sharing_mode','ordinary_file_writers_excluded_during_observation','native_handle_paths_verified','single_link_files_verified','two_pass_equal','atomic','quiescent','continuous_membership_protection','authenticated','execution_authorized','snapshot_sha256')
    if($Snapshot.schema_version -isnot [string] -or $Snapshot.schema_version -cne $script:DataSchema -or $Snapshot.observation -isnot [string] -or $Snapshot.observation -cne 'process-local-native-file-handles'){throw 'Wrong data evidence schema or observation'}
    Assert-YcDataRoot $Snapshot.state_root
    if($Snapshot.sharing_mode -isnot [string] -or $Snapshot.sharing_mode -cnotin @('read','read-write-delete') -or $Snapshot.ordinary_file_writers_excluded_during_observation -isnot [bool] -or
        $Snapshot.ordinary_file_writers_excluded_during_observation -ne ($Snapshot.sharing_mode -ceq 'read')){throw 'Invalid data sharing claim'}
    foreach($name in @('native_handle_paths_verified','single_link_files_verified','two_pass_equal')){if($Snapshot.$name -isnot [bool] -or -not $Snapshot.$name){throw 'Invalid data evidence claim'}}
    foreach($name in @('atomic','quiescent','continuous_membership_protection','authenticated','execution_authorized')){if($Snapshot.$name -isnot [bool] -or $Snapshot.$name){throw 'Unsupported data evidence claim'}}
    $expected=@('user-model/')+$script:DataFiles
    if($Snapshot.categories -isnot [array] -or $Snapshot.categories.Count -ne $expected.Count){throw 'Invalid data categories'}
    for($i=0;$i -lt $expected.Count;$i++){if($Snapshot.categories[$i] -isnot [string] -or $Snapshot.categories[$i] -cne $expected[$i]){throw 'Invalid data category'}}
    if($Snapshot.records -isnot [array]){throw 'Data records must be an array'}
    $map=@{};$last=$null
    foreach($row in $Snapshot.records){
        Assert-YcDataRecord $row $false
        if($map.ContainsKey($row.path) -or ($null -ne $last -and [StringComparer]::Ordinal.Compare($last,$row.path) -ge 0)){throw 'Duplicate or unsorted data records'}
        if($row.path.StartsWith('user-model/',[StringComparison]::Ordinal)){
            $parent=$row.path.Substring(0,$row.path.LastIndexOf('/'))
            if(-not $map.ContainsKey($parent) -or $map[$parent].kind -cne 'directory'){throw 'Data directory closure missing'}
        }
        $map[$row.path]=$row;$last=$row.path
    }
    Assert-YcDataRecord $Snapshot.runtime_config $true
    if($Snapshot.snapshot_sha256 -isnot [string] -or $Snapshot.snapshot_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Snapshot.snapshot_sha256 -cne (Get-YcDataDigest (Get-YcDataSnapshotBody $Snapshot))){throw 'Data snapshot digest mismatch'}
}
function Test-YcDataContentEqual($Before,$After) {
    if($Before.kind -cne $After.kind){return $false}
    if($Before.kind -ceq 'file'){return ($Before.bytes -eq $After.bytes -and $Before.sha256 -ceq $After.sha256)}
    return $true
}
function Compare-YimeCoreNativeMaintenanceDataSnapshots {
    [CmdletBinding()]param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After,[switch]$AllowDifferentRoots)
    Assert-YcDataSnapshot $Before;Assert-YcDataSnapshot $After
    $sameRoot=[string]::Equals($Before.state_root,$After.state_root,[StringComparison]::OrdinalIgnoreCase)
    if(-not $sameRoot -and -not $AllowDifferentRoots){throw 'Different data roots require explicit mapping approval'}
    $left=@{};$right=@{};foreach($row in $Before.records){$left[$row.path]=$row};foreach($row in $After.records){$right[$row.path]=$row}
    $added=@($After.records|Where-Object {-not $left.ContainsKey($_.path)}|ForEach-Object path)
    $deleted=@($Before.records|Where-Object {-not $right.ContainsKey($_.path)}|ForEach-Object path)
    $changed=@();$identities=@()
    foreach($row in $Before.records){if($right.ContainsKey($row.path)){
        $other=$right[$row.path]
        if($row.path -cne $other.path -or -not (Test-YcDataContentEqual $row $other)){$changed+=,$row.path}
        if($sameRoot -and $row.kind -ceq 'file' -and $other.kind -ceq 'file' -and $row.file_identity -cne $other.file_identity){$identities+=,$row.path}
    }}
    $runtimeSame=Test-YcDataContentEqual $Before.runtime_config $After.runtime_config
    $dataSame=($added.Count -eq 0 -and $deleted.Count -eq 0 -and $changed.Count -eq 0)
    [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-data-comparison-v1';before_snapshot_sha256=$Before.snapshot_sha256;after_snapshot_sha256=$After.snapshot_sha256;
        before_state_root=$Before.state_root;after_state_root=$After.state_root;before_sharing_mode=$Before.sharing_mode;after_sharing_mode=$After.sharing_mode;
        different_roots_explicitly_allowed=[bool]$AllowDifferentRoots;data_unchanged=$dataSame;runtime_config_unchanged=$runtimeSame;
        unchanged=($dataSame -and $runtimeSame);added_paths=$added;deleted_paths=$deleted;changed_paths=$changed;file_identity_changed_paths=$identities;
        runtime_config_identity_changed=($sameRoot -and $Before.runtime_config.kind -ceq 'file' -and $After.runtime_config.kind -ceq 'file' -and $Before.runtime_config.file_identity -cne $After.runtime_config.file_identity);
        serialized_evidence_only=$true;authenticated=$false;quiescent=$false;continuous_membership_protection=$false;execution_authorized=$false}
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceDataSnapshot,Compare-YimeCoreNativeMaintenanceDataSnapshots
