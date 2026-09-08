Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:VisibilityFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:VisibilityNamespace='Yime.Visibility_'+[guid]::NewGuid().ToString('N')
$script:VisibilityFactsType=$null;$script:VisibilityPathsType=$null
$script:VisibilityLeaves=@('package-manifest.json','install-metadata.json','backup-manifest.json','archive-manifest.json','archive-summary.json','preparation.json','plan.json')

function Assert-VisibilityPath($Path,[switch]$Provider) {
    if($Path -isnot [string] -or $Path -notmatch '^[A-Za-z]:\\[^\\]' -or (-not $Provider -and $Path -cnotmatch '^[A-Z]:') -or
        $Path -match '[/\x00-\x1f"<>|?*%~]' -or $Path.Contains("'") -or $Path.Substring(2).Contains(':') -or
        $Path.EndsWith('\') -or $Path -match '\\\\|\\(\.|\.\.)(\\|$)|[. ](\\|$)|(?i)\\(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|\\|$)' -or
        [IO.Path]::GetFullPath($Path) -cne $Path){throw 'Explicit canonical local metadata path required'}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Path)
}
function Assert-VisibilityPlain([string]$Path) {
    $cursor=$Path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect visibility input path'};$cursor=Split-Path -Parent $cursor}
}
function Assert-VisibilityFields($Value,[string[]]$Names) {
    if($Value -isnot [pscustomobject] -and $Value -isnot [Collections.IDictionary]){throw 'Literal metadata object required'}
    $keys=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    if($keys.Count -ne $Names.Count){throw 'Unexpected metadata fields'}
    foreach($name in $Names){if($keys -cnotcontains $name){throw 'Noncanonical metadata field name'}}
}
function Get-VisibilityStreamHash([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$Stream.Position=0}
}
function Initialize-VisibilityNative {
    $path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'));Assert-VisibilityPlain $path
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if((Get-VisibilityStreamHash $stream) -cne $script:VisibilityFactsHash){throw 'Reviewed visibility facts source changed'}
        $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try{$source=$reader.ReadToEnd()}finally{$reader.Dispose()}
        if($null -eq $script:VisibilityFactsType){
            $types=@(Add-Type -TypeDefinition ($source.Replace('namespace Yime.Dp1UNative {',('namespace '+$script:VisibilityNamespace+' {'))) -PassThru)
            $script:VisibilityFactsType=@($types|Where-Object {$_.FullName -ceq ($script:VisibilityNamespace+'.Facts')})[0]
        }
        [void]$script:VisibilityFactsType::VerifyFileHandle($stream,$path)
    }finally{$stream.Dispose()}
    if($null -ne $script:VisibilityPathsType){return}
    $source=@'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Yime.VisibilityPaths {
 public static class Paths {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,out Tag info,uint size);
  [StructLayout(LayoutKind.Sequential)] struct Tag {public uint Attributes,ReparseTag;}
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct StreamData {public long Size;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)]public string Name;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr FindFirstStreamW(string path,int level,out StreamData data,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool FindNextStreamW(IntPtr handle,out StreamData data);
  [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr handle);
  public static SafeFileHandle OpenDirectory(string path){
   var handle=CreateFile(path,0x81,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
   if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
   try{VerifyDirectory(handle,path);return handle;}catch{handle.Dispose();throw;}
  }
  public static void VerifyDirectory(SafeFileHandle handle,string path){Tag tag;
   if(!GetFileInformationByHandleEx(handle,9,out tag,8))throw new Win32Exception(Marshal.GetLastWin32Error());
   if((tag.Attributes&0x10)==0||(tag.Attributes&0x400)!=0)throw new InvalidOperationException("Indirect or non-directory visibility root");
   var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(handle,final,(uint)final.Capacity,0);
   if(n==0||n>=final.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());
   if(!String.Equals(final.ToString(),@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Visibility directory final path mismatch");
  }
  public static void RejectNamedStreams(string path){StreamData data;IntPtr handle=FindFirstStreamW(path,0,out data,0);
   if(handle==new IntPtr(-1)){int error=Marshal.GetLastWin32Error();if(error==38)return;throw new Win32Exception(error);}
   try{do{if(!String.Equals(data.Name,"::$DATA",StringComparison.Ordinal))throw new InvalidOperationException("Named visibility stream rejected");}while(FindNextStreamW(handle,out data));int error=Marshal.GetLastWin32Error();if(error!=38)throw new Win32Exception(error);}finally{FindClose(handle);}
  }
 }
}
'@
    $types=@(Add-Type -TypeDefinition ($source.Replace('namespace Yime.VisibilityPaths {',('namespace '+$script:VisibilityNamespace+' {'))) -PassThru)
    $script:VisibilityPathsType=@($types|Where-Object {$_.FullName -ceq ($script:VisibilityNamespace+'.Paths')})[0]
}
function Release-VisibilityCom($Object) {
    if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object)}
}
function Open-VisibilityProvider {
    $session=@{locator=$null;services=$null}
    try{
        $session.locator=New-Object -ComObject WbemScripting.SWbemLocator
        $session.services=$session.locator.ConnectServer('.','root\cimv2')
        $session.services.Security_.ImpersonationLevel=3
        if($null -eq $session.services){throw 'Missing independent CIM provider'}
        return $session
    }catch{Close-VisibilityProvider $session;throw}
}
function Close-VisibilityProvider($Session) {
    if($null -ne $Session){foreach($name in @('services','locator')){Release-VisibilityCom $Session[$name]}}
}
function Copy-VisibilityProperty($Property) {
    # Retain native CIM declarations. Automation represents CIM_UINT64 as a
    # decimal string on some hosts; arbitrary JSON strings are not a fallback.
    [pscustomobject][ordered]@{name=$Property.Name;cim_type=$Property.CIMType;is_array=$Property.IsArray;value=$Property.Value}
}
function Invoke-VisibilityQuery($Session,[string]$Path) {
    $escaped=$Path.Replace('\','\\').Replace("'","\'")
    $query="SELECT Name, FileSize FROM CIM_DataFile WHERE Name='$escaped'"
    $set=$null;$objects=[Collections.Generic.List[object]]::new();$rows=[Collections.Generic.List[object]]::new()
    try{
        # ReturnImmediately | EnsureLocatable. Count requires a bidirectional
        # set; PowerShell need not enumerate SWbemObjectSet through foreach.
        # https://learn.microsoft.com/en-us/windows/win32/wmisdk/swbemobjectset-count
        $set=$Session.services.ExecQuery($query,'WQL',272)
        if($null -eq $set){throw 'Null CIM file query result'}
        $count=$set.Count
        if($count -isnot [int] -or $count -ne 1){throw 'Exactly one native CIM file result required'}
        for($index=0;$index -lt $count;$index++){
            $item=$set.ItemIndex($index)
            if($null -eq $item){throw 'Null native CIM file instance'}
            $objects.Add($item)
            $properties=@{};$objectPath=$null
            try{
                # ItemIndex gives the instance; foreach can yield the set itself.
                # Read the instance's documented Path_ interface and retain its
                # actual scalar types, not invented CIM declarations.
                $objectPath=$item.Path_
                foreach($name in @('Name','FileSize')){$properties[$name]=$item.Properties_.Item($name)}
                $rows.Add([pscustomobject][ordered]@{object_path=[pscustomobject][ordered]@{class=$objectPath.Class;is_class=$objectPath.IsClass;
                        server=$objectPath.Server;namespace=$objectPath.Namespace};
                    name=(Copy-VisibilityProperty $properties['Name']);file_size=(Copy-VisibilityProperty $properties['FileSize'])})
            }finally{foreach($property in $properties.Values){Release-VisibilityCom $property};Release-VisibilityCom $objectPath}
        }
        return ,($rows.ToArray())
    }finally{foreach($item in $objects){Release-VisibilityCom $item};Release-VisibilityCom $set}
}
function Assert-VisibilityProperty($Property,[string]$Name,[int]$Type) {
    Assert-VisibilityFields $Property @('name','cim_type','is_array','value')
    if($Property.name -isnot [string] -or $Property.name -cne $Name -or
        ($Property.cim_type -isnot [int] -and $Property.cim_type -isnot [uint32]) -or $Property.cim_type -ne $Type -or
        $Property.is_array -isnot [bool] -or $Property.is_array){throw 'CIM property metadata mismatch'}
}
function Assert-VisibilityReply($Rows,[string]$Path,[long]$Bytes) {
    if($Rows -isnot [array] -or $Rows.Count -ne 1){throw 'Exactly one CIM file instance required'}
    $row=$Rows[0];Assert-VisibilityFields $row @('object_path','name','file_size')
    Assert-VisibilityFields $row.object_path @('class','is_class','server','namespace');$identity=$row.object_path
    foreach($spec in @(@('name','Name',8),@('file_size','FileSize',21))){Assert-VisibilityProperty $row.($spec[0]) $spec[1] $spec[2]}
    if($identity.class -isnot [string] -or $identity.class -cne 'CIM_DataFile' -or $identity.is_class -isnot [bool] -or $identity.is_class -or
        $identity.server -isnot [string] -or -not [string]::Equals($identity.server,[Environment]::MachineName,[StringComparison]::OrdinalIgnoreCase) -or
        $identity.namespace -isnot [string] -or $identity.namespace -cne 'root\cimv2'){throw 'Wrong CIM class, instance, host or namespace'}
    Assert-VisibilityPath $row.name.value -Provider
    if(-not [string]::Equals($row.name.value,$Path,[StringComparison]::OrdinalIgnoreCase)){throw 'CIM returned a different file path'}
    $value=$row.file_size.value;$size=[uint64]0
    if($value -is [string]){
        if($value -cnotmatch '^(0|[1-9][0-9]*)$' -or -not [uint64]::TryParse($value,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$size)){throw 'Noncanonical CIM_UINT64 size'}
    }elseif($value -is [uint64]){$size=$value}
    else{throw 'Unexpected Automation representation for CIM_UINT64 size'}
    if($size -ne [uint64]$Bytes){throw 'Independent system file size differs'}
    [pscustomobject][ordered]@{path=$row.name.value;kind='file';class='CIM_DataFile';namespace='root\cimv2';server=$identity.server;bytes=[long]$size}
}
function Get-YimeCoreNativeMaintenanceFileVisibility {
    [CmdletBinding()]param([Parameter(Mandatory)]$ApprovedRoot,[Parameter(Mandatory)]$ExpectedFiles)
    Assert-VisibilityPath $ApprovedRoot
    if($ExpectedFiles -isnot [array] -or $ExpectedFiles.Count -lt 1 -or $ExpectedFiles.Count -gt 128){throw 'Bounded explicit metadata file array required'}
    $expected=@{};foreach($row in $ExpectedFiles){
        Assert-VisibilityFields $row @('path','bytes','sha256');Assert-VisibilityPath $row.path
        if(-not $row.path.StartsWith($ApprovedRoot+'\',[StringComparison]::Ordinal) -or $script:VisibilityLeaves -cnotcontains [IO.Path]::GetFileName($row.path) -or
            $expected.ContainsKey($row.path) -or ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 0 -or $row.bytes -gt 16777216 -or
            $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Unapproved, duplicate or malformed metadata input'}
        $expected[$row.path]=$row
    }
    Assert-VisibilityPlain $ApprovedRoot;Initialize-VisibilityNative
    $files=@{};$directories=@{};$session=$null;$records=[Collections.Generic.List[object]]::new()
    $paths=[string[]]@($expected.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal)
    try{
        $directories[$ApprovedRoot]=$script:VisibilityPathsType::OpenDirectory($ApprovedRoot)
        foreach($path in $paths){
            $parent=Split-Path -Parent $path;$chain=[Collections.Generic.List[string]]::new()
            while($parent -cne $ApprovedRoot){
                if(-not $parent.StartsWith($ApprovedRoot+'\',[StringComparison]::Ordinal)){throw 'Metadata parent left root'}
                $chain.Add($parent);$parent=Split-Path -Parent $parent
            }
            for($i=$chain.Count-1;$i -ge 0;$i--){$dir=$chain[$i];if(-not $directories.ContainsKey($dir)){$directories[$dir]=$script:VisibilityPathsType::OpenDirectory($dir)}}
            Assert-VisibilityPlain $path
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$files[$path]=@{stream=$stream;identity=$null}
            $files[$path].identity=$script:VisibilityFactsType::VerifyFileHandle($stream,$path)
            $script:VisibilityPathsType::RejectNamedStreams($path)
            if($stream.Length -ne $expected[$path].bytes -or (Get-VisibilityStreamHash $stream) -cne $expected[$path].sha256){throw 'Local held metadata differs from expected manifest binding'}
        }
        foreach($dir in $directories.Keys){$script:VisibilityPathsType::RejectNamedStreams($dir)}
        $session=Open-VisibilityProvider
        if($null -eq $session){throw 'Independent CIM session unavailable'}
        foreach($path in $paths){
            $reply=Invoke-VisibilityQuery $session $path
            $system=Assert-VisibilityReply $reply $path $expected[$path].bytes
            $records.Add([pscustomobject][ordered]@{path=$path;bytes=$expected[$path].bytes;local_sha256=$expected[$path].sha256;local_file_identity=$files[$path].identity;
                system_metadata=$system;system_metadata_visible=$true;bound_metadata=$true;independent_content_hash_verified=$false})
        }
        foreach($path in $paths){$file=$files[$path];$stream=$file.stream
            Assert-VisibilityPlain $path;$script:VisibilityPathsType::RejectNamedStreams($path)
            if($script:VisibilityFactsType::VerifyFileHandle($stream,$path) -cne $file.identity -or $stream.Length -ne $expected[$path].bytes -or
                (Get-VisibilityStreamHash $stream) -cne $expected[$path].sha256){throw 'Local metadata changed during independent observation'}
        }
        foreach($dir in $directories.Keys){$script:VisibilityPathsType::VerifyDirectory($directories[$dir],$dir);$script:VisibilityPathsType::RejectNamedStreams($dir)}
        [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-visibility-v1';approved_root=$ApprovedRoot;records=$records.ToArray();file_count=$records.Count;
            provider='out-of-process WMI CIM_DataFile metadata via root/cimv2';system_metadata_visible=$true;bound_metadata=$true;local_held_hashes_verified=$true;
            independent_content_hash_verified=$false;independent_file_identity_verified=$false;expected_manifest_origin_authenticated=$false;loaded_provider_identity_authenticated=$false;
            continuous_membership_protection=$false;atomic=$false;leases_released_on_return=$true;execution_authorized=$false;ready_to_execute=$false;
            full_acceptance=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
    }finally{
        try{Close-VisibilityProvider $session}finally{foreach($file in $files.Values){$file.stream.Dispose()};foreach($handle in $directories.Values){$handle.Dispose()}}
    }
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceFileVisibility
