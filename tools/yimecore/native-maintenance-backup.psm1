Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:BackupFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:BackupNativeType=$null
$script:BackupJsonType=$null
$script:BackupDirectoryType=$null

function Assert-BackupString($Value) {
    if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)){throw 'Literal nonempty backup string required'}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Value)
}
function Assert-BackupEqual($Value,[string]$Expected) {
    Assert-BackupString $Value;if($Value -cne $Expected){throw 'Backup identity binding mismatch'}
}
function Assert-BackupInteger($Value,[long]$Minimum,[long]$Maximum) {
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Literal backup integer out of range'}
}
function Assert-BackupTrue($Value) {if($Value -isnot [bool] -or -not $Value){throw 'Literal backup true required'}}
function Assert-BackupHash($Value) {Assert-BackupString $Value;if($Value -cnotmatch '^[a-f0-9]{64}$'){throw 'Canonical backup SHA256 required'}}
function Assert-BackupRoot($Path) {
    Assert-BackupString $Path
    if($Path -cnotmatch '^[A-Z]:\\[^\\]' -or $Path -match '[/\x00-\x1f"<>|?*%]' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'Canonical local backup path required'}
    foreach($part in $Path.Substring(3).Split('\')){if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Ambiguous backup path'}}
}
function Assert-BackupRelative($Path) {
    Assert-BackupString $Path
    if($Path -match '[\\:\x00-\x1f"<>|?*%]|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)|~' -or
        $Path -match '(?i)(^|/)(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9]|\.git)(\.|/|$)' -or [IO.Path]::IsPathRooted($Path)){throw 'Unsafe backup member path'}
}
function Assert-BackupPlain([string]$Path) {
    $cursor=$Path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect backup path'};$cursor=Split-Path -Parent $cursor}
}
function Get-BackupStreamHash([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$Stream.Position=0}
}
function Assert-BackupObject($Value,[string[]]$Required,[switch]$Exact) {
    if($Value -isnot [Collections.Generic.Dictionary[string,object]]){throw 'Literal backup object required'}
    foreach($key in $Required){if(-not $Value.ContainsKey($key)){throw 'Missing backup object field'}}
    if($Exact -and $Value.Count -ne $Required.Count){throw 'Unexpected backup object field'}
}

function Initialize-BackupTypes {
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))
    Assert-BackupPlain $source
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -lt 1 -or $stream.Length -gt 1048576){throw 'Invalid backup helper source size'}
        if((Get-BackupStreamHash $stream) -cne $script:BackupFactsHash){throw 'Reviewed backup helper source changed'}
        $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
        try{$sourceText=$reader.ReadToEnd()}finally{$reader.Dispose()}
        if($null -eq $script:BackupNativeType){
            $namespace='Yime.BackupFacts.N'+[guid]::NewGuid().ToString('N')
            $types=Add-Type -TypeDefinition ($sourceText.Replace('namespace Yime.Dp1UNative {','namespace '+$namespace+' {')) -PassThru
            $script:BackupNativeType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Facts')})[0]
        }
        [void]$script:BackupNativeType::VerifyFileHandle($stream,$source)
        Assert-BackupPlain $source
    }finally{$stream.Dispose()}
    if($null -eq $script:BackupDirectoryType){
        $directorySource=@'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Yime.BackupDirectories {
 public sealed class Pin : IDisposable {
  SafeFileHandle handle;
  [StructLayout(LayoutKind.Sequential)] struct Info {public uint Attributes,CreationLow,CreationHigh,AccessLow,AccessHigh,WriteLow,WriteHigh,Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle,out Info info);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct StreamData {public long Size;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)] public string Name;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr FindFirstStreamW(string path,int level,out StreamData data,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool FindNextStreamW(IntPtr handle,out StreamData data);
  [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr handle);
  public static void RejectNamedStreams(string path){StreamData data;IntPtr h=FindFirstStreamW(path,0,out data,0);
   if(h==new IntPtr(-1)){int error=Marshal.GetLastWin32Error();if(error==38)return;throw new Win32Exception(error);}
   try{do{if(!String.Equals(data.Name,"::$DATA",StringComparison.Ordinal))throw new InvalidOperationException("Named backup stream rejected");}while(FindNextStreamW(h,out data));int error=Marshal.GetLastWin32Error();if(error!=38)throw new Win32Exception(error);}finally{FindClose(h);}
  }
  public static Pin Open(string path){
   var p=new Pin();p.handle=CreateFile(path,0x81,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
   try{if(p.handle.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());Info i;
    if(!GetFileInformationByHandle(p.handle,out i))throw new Win32Exception(Marshal.GetLastWin32Error());
    if((i.Attributes&0x400)!=0||(i.Attributes&0x10)==0)throw new InvalidOperationException("Indirect or non-directory backup path");
    var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(p.handle,b,(uint)b.Capacity,0);
    if(n==0||n>=b.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());string actual=b.ToString();
    if(actual.StartsWith(@"\\?\",StringComparison.Ordinal))actual=actual.Substring(4);
    if(!String.Equals(actual.TrimEnd('\\'),path.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Backup directory final path mismatch");
    return p;
   }catch{p.Dispose();throw;}
  }
  public void Dispose(){if(handle!=null){handle.Dispose();handle=null;}}
 }
}
'@
        $namespace='Yime.BackupDirectories.N'+[guid]::NewGuid().ToString('N')
        $types=Add-Type -TypeDefinition ($directorySource.Replace('namespace Yime.BackupDirectories {','namespace '+$namespace+' {')) -PassThru
        $script:BackupDirectoryType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Pin')})[0]
    }
    if($null -ne $script:BackupJsonType){return}
    # Independent parser: no ConvertFrom-Json coercion/duplicate-key loss. The
    # backup producer may include non-integer diagnostic numbers in live facts;
    # every identity/count below still requires an actual integer token.
    $parser=@'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
namespace Yime.BackupParser {
 public sealed class Json {
  readonly string text; int p;
  Json(string value){text=value;}
  Exception Bad(){return new FormatException("Strict backup JSON rejected");}
  char Take(){if(p>=text.Length)throw Bad();return text[p++];}
  void Expect(char c){if(Take()!=c)throw Bad();}
  void Space(){while(p<text.Length && (text[p]==' '||text[p]=='\t'||text[p]=='\r'||text[p]=='\n'))p++;}
  string Str(){Expect('"');var s=new StringBuilder();bool end=false;
   while(p<text.Length){char c=Take();if(c=='"'){end=true;break;}if(c<' ')throw Bad();
    if(c!='\\'){s.Append(c);continue;}c=Take();switch(c){
     case '"':case '\\':case '/':s.Append(c);break;case 'b':s.Append('\b');break;case 'f':s.Append('\f');break;
     case 'n':s.Append('\n');break;case 'r':s.Append('\r');break;case 't':s.Append('\t');break;
     case 'u':ushort v;if(p+4>text.Length||!UInt16.TryParse(text.Substring(p,4),NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out v))throw Bad();p+=4;s.Append((char)v);break;
     default:throw Bad();}}
   if(!end)throw Bad();string value=s.ToString();new UnicodeEncoding(false,false,true).GetBytes(value);return value;}
  object Value(int depth){if(depth>32)throw Bad();Space();if(p>=text.Length)throw Bad();char c=text[p];
   if(c=='"')return Str();
   if(c=='{'){p++;Space();var d=new Dictionary<string,object>(StringComparer.Ordinal);var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    if(p<text.Length&&text[p]=='}'){p++;return d;}while(true){Space();string k=Str();if(!keys.Add(k)||keys.Count>65536)throw Bad();Space();Expect(':');d.Add(k,Value(depth+1));Space();char n=Take();if(n=='}')return d;if(n!=',')throw Bad();}}
   if(c=='['){p++;Space();var a=new List<object>();if(p<text.Length&&text[p]==']'){p++;return a.ToArray();}
    while(true){a.Add(Value(depth+1));if(a.Count>65536)throw Bad();Space();char n=Take();if(n==']')return a.ToArray();if(n!=',')throw Bad();}}
   foreach(string t in new[]{"true","false","null"}){if(p+t.Length<=text.Length&&String.CompareOrdinal(text,p,t,0,t.Length)==0){p+=t.Length;if(t=="null")return null;return t=="true";}}
   int start=p;if(c=='-')p++;if(p>=text.Length||text[p]<'0'||text[p]>'9')throw Bad();
   if(text[p]=='0')p++;else while(p<text.Length&&text[p]>='0'&&text[p]<='9')p++;
   bool integer=true;if(p<text.Length&&text[p]=='.'){integer=false;p++;int b=p;while(p<text.Length&&text[p]>='0'&&text[p]<='9')p++;if(p==b)throw Bad();}
   if(p<text.Length&&(text[p]=='e'||text[p]=='E')){integer=false;p++;if(p<text.Length&&(text[p]=='+'||text[p]=='-'))p++;int b=p;while(p<text.Length&&text[p]>='0'&&text[p]<='9')p++;if(p==b)throw Bad();}
   string number=text.Substring(start,p-start);if(integer){long v;if(!Int64.TryParse(number,NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out v))throw Bad();return v;}
   double f;if(!Double.TryParse(number,NumberStyles.Float,CultureInfo.InvariantCulture,out f)||Double.IsInfinity(f)||Double.IsNaN(f))throw Bad();return f;
  }
  public static object Parse(string text){var r=new Json(text);object v=r.Value(0);r.Space();if(r.p!=text.Length)throw r.Bad();return v;}
 }
}
'@
    $namespace='Yime.BackupParser.N'+[guid]::NewGuid().ToString('N')
    $types=Add-Type -TypeDefinition ($parser.Replace('namespace Yime.BackupParser {','namespace '+$namespace+' {')) -PassThru
    $script:BackupJsonType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Json')})[0]
}
function Open-BackupFile($Session,[string]$Path,$ExpectedHash=$null,$ExpectedBytes=$null) {
    Assert-BackupPlain $Path
    foreach($alternate in Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop){if($alternate.Stream -cne ':$DATA'){throw 'Alternate backup file stream rejected'}}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $Session.Add($stream)
    $identity=$script:BackupNativeType::VerifyFileHandle($stream,$Path)
    if($null -ne $ExpectedBytes -and $stream.Length -ne $ExpectedBytes){throw 'Backup file size changed'}
    $hash=Get-BackupStreamHash $stream
    if($null -ne $ExpectedHash -and $hash -cne $ExpectedHash){throw 'Backup file hash changed'}
    [pscustomobject]@{path=$Path;stream=$stream;sha256=$hash;bytes=$stream.Length;identity=$identity}
}
function Read-BackupJson($File) {
    if($File.bytes -lt 1 -or $File.bytes -gt 16777216){throw 'Backup JSON exceeds bounded read'}
    $reader=[IO.StreamReader]::new($File.stream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$File.stream.Position=0}
    # PS5 Set-Content -Encoding UTF8 writes exactly one optional UTF8 BOM.
    if($text.Length -gt 0 -and $text[0] -eq [char]0xfeff){$text=$text.Substring(1)}
    $script:BackupJsonType::Parse($text)
}
function Get-BackupRecords($Rows,[switch]$AllowEmpty) {
    if($Rows -isnot [object[]] -or (-not $AllowEmpty -and $Rows.Count -lt 1) -or $Rows.Count -gt 65536){throw 'Literal backup records array required'}
    $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $Rows){
        Assert-BackupObject $row @('path','bytes','sha256') -Exact
        Assert-BackupRelative $row.path;Assert-BackupHash $row.sha256;Assert-BackupInteger $row.bytes 0 ([long]::MaxValue)
        if($map.ContainsKey($row.path)){throw 'Duplicate or case-colliding backup member'};$map.Add($row.path,$row)
    }
    return ,$map
}
function Get-BackupTree([string]$Root,$DirectoryLeases) {
    Assert-BackupPlain $Root
    # Open each directory without following reparse points before descending.
    # Retaining these handles prevents a queued child from being replaced by a
    # junction between enumeration and descent; new members remain possible.
    if(-not $DirectoryLeases.ContainsKey($Root)){$DirectoryLeases[$Root]=$script:BackupDirectoryType::Open($Root)}
    $files=New-Object 'Collections.Generic.List[string]';$directories=New-Object 'Collections.Generic.List[string]'
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($Root)
    while($queue.Count){$directory=$queue.Dequeue();$script:BackupDirectoryType::RejectNamedStreams($directory);foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect backup tree member'}
        $relative=$item.FullName.Substring($Root.Length+1).Replace('\','/');Assert-BackupRelative $relative
        if($relative.Split('/').Count -gt 32 -or $files.Count+$directories.Count -ge 65536){throw 'Backup tree exceeds bound'}
        if($item.PSIsContainer){if(-not $DirectoryLeases.ContainsKey($item.FullName)){$DirectoryLeases[$item.FullName]=$script:BackupDirectoryType::Open($item.FullName)};$directories.Add($relative);$queue.Enqueue($item.FullName)}else{$files.Add($relative)}
    }}
    [pscustomobject]@{files=@($files.ToArray()|Sort-Object);directories=@($directories.ToArray()|Sort-Object)}
}
function Assert-BackupTreeRecords($Tree,$Records,[switch]$ExactDirectories) {
    if($Tree.files.Count -ne $Records.Count){throw 'Backup file inventory is incomplete or has unlisted members'}
    foreach($path in $Tree.files){if(-not $Records.ContainsKey($path) -or $Records[$path].path -cne $path){throw 'Unlisted or differently cased backup file'}}
    if($ExactDirectories){$dirs=@{};foreach($path in $Tree.files){$parts=$path.Split('/');for($i=1;$i -lt $parts.Count;$i++){$dirs[($parts[0..($i-1)] -join '/')]=1}}
        if($dirs.Count -ne $Tree.directories.Count){throw 'Unexpected package directory'};foreach($dir in $Tree.directories){if(-not $dirs.ContainsKey($dir)){throw 'Unlisted package directory'}}}
}

function Read-YimeCoreNativeMaintenanceBackup {
    [CmdletBinding()]param([Parameter(Mandatory)]$BackupRoot,[Parameter(Mandatory)]$ExpectedStateRoot,
        [Parameter(Mandatory)]$ExpectedInstallRoot,[Parameter(Mandatory)]$ExpectedPreviousManifestSha256,
        [Parameter(Mandatory)]$ActualBackupExitCode)
    # This is supplied context, not authenticated OS exit evidence.
    Assert-BackupInteger $ActualBackupExitCode 0 0
    foreach($path in @($BackupRoot,$ExpectedStateRoot,$ExpectedInstallRoot)){Assert-BackupRoot $path}
    foreach($root in @($ExpectedStateRoot,$ExpectedInstallRoot)){
        if($BackupRoot -ieq $root -or $BackupRoot.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($BackupRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Backup overlaps a live source root'}}
    Assert-BackupHash $ExpectedPreviousManifestSha256
    Initialize-BackupTypes
    $session=New-Object 'Collections.Generic.List[IO.FileStream]';$opened=New-Object 'Collections.Generic.List[object]';$directoryLeases=@{}
    try {
        $top=Get-BackupTree $BackupRoot $directoryLeases
        $manifestFile=Open-BackupFile $session (Join-Path $BackupRoot 'backup-manifest.json');$opened.Add($manifestFile)
        $manifest=Read-BackupJson $manifestFile
        Assert-BackupObject $manifest @('schema_version','generated_at','development_scope','source_state_root','source_install_root','runtime_pid_before','broker_pid_before','writers_stopped','source_stable_during_copy','state_files','package_files','native_context_verified','live_runtime_before','data_files','backup_root','passed') -Exact
        Assert-BackupEqual $manifest.schema_version 'yimecore-quiesced-backup-v1'
        foreach($name in @('passed','writers_stopped','native_context_verified','source_stable_during_copy')){Assert-BackupTrue $manifest[$name]}
        Assert-BackupEqual $manifest.backup_root $BackupRoot;Assert-BackupEqual $manifest.source_state_root $ExpectedStateRoot;Assert-BackupEqual $manifest.source_install_root $ExpectedInstallRoot
        Assert-BackupString $manifest.generated_at;[void][DateTimeOffset]::Parse($manifest.generated_at,[Globalization.CultureInfo]::InvariantCulture)
        Assert-BackupInteger $manifest.runtime_pid_before 1 ([int]::MaxValue);Assert-BackupInteger $manifest.broker_pid_before 1 ([int]::MaxValue)
        if($manifest.runtime_pid_before -eq $manifest.broker_pid_before){throw 'Backup process IDs overlap'}
        Assert-BackupObject $manifest.live_runtime_before @('passed');Assert-BackupTrue $manifest.live_runtime_before.passed
        $scope=$manifest.development_scope
        Assert-BackupObject $scope @('id','computer_name','native_architecture','active_architectures','performance_profile','frozen_targets','experiment_targets','policy_sha256') -Exact
        Assert-BackupEqual $scope.id 'mainstream-x64-arm64-resumed-2026-09-04';Assert-BackupEqual $scope.computer_name 'MYCOMPUTER';Assert-BackupEqual $scope.native_architecture 'AMD64';Assert-BackupEqual $scope.performance_profile 'development_host_x64';Assert-BackupHash $scope.policy_sha256
        if($scope.active_architectures -isnot [object[]] -or $scope.active_architectures.Count -ne 2){throw 'Backup architecture array required'}
        Assert-BackupEqual $scope.active_architectures[0] 'x64';Assert-BackupEqual $scope.active_architectures[1] 'x86'
        $stateRecords=Get-BackupRecords $manifest.state_files;$packageRecords=Get-BackupRecords $manifest.package_files;$dataRecords=Get-BackupRecords $manifest.data_files -AllowEmpty
        $stateRoot=Join-Path $BackupRoot 'state';$packageRoot=Join-Path $BackupRoot 'previous-package'
        $stateTree=Get-BackupTree $stateRoot $directoryLeases;$packageTree=Get-BackupTree $packageRoot $directoryLeases
        Assert-BackupTreeRecords $stateTree $stateRecords;Assert-BackupTreeRecords $packageTree $packageRecords -ExactDirectories
        $allowedData=@{};foreach($row in $stateRecords.Values){if($row.path.StartsWith('user-model/',[StringComparison]::Ordinal) -or $row.path -cin @('learning.json','professional-lexicons.json','speech.json','yime_blocklist.txt','yime_user_phrases.txt','yimecore_experimental_toolbar_state.json')){$allowedData[$row.path]=$row}}
        if($allowedData.Count -ne $dataRecords.Count){throw 'Backup data subset missing or includes non-data files'}
        foreach($row in $dataRecords.Values){$expected=$allowedData[$row.path];if(-not $expected -or $expected.path -cne $row.path -or $expected.sha256 -cne $row.sha256 -or $expected.bytes -ne $row.bytes){throw 'Backup data records disagree with complete state records'}}
        $packageManifest=Open-BackupFile $session (Join-Path $packageRoot 'package-manifest.json') $ExpectedPreviousManifestSha256;$opened.Add($packageManifest)
        $previous=Read-BackupJson $packageManifest
        Assert-BackupObject $previous @('package_contract','tool_version','product_version','package_id','files')
        Assert-BackupEqual $previous.package_contract 'yimecore-local-product-package-v1';Assert-BackupEqual $previous.tool_version 'yimecore-local-builder-v1';Assert-BackupEqual $previous.product_version '0.1.0-local.12';Assert-BackupString $previous.package_id
        $listed=Get-BackupRecords $previous.files
        if($listed.Count -ne 74 -or $packageRecords.Count -ne 76){throw 'Previous local.12 backup requires 74 payloads plus manifest and installed marker'}
        foreach($reserved in @('package-manifest.json','install-metadata.json')){if($listed.ContainsKey($reserved) -or -not $packageRecords.ContainsKey($reserved)){throw 'Invalid package metadata membership'}}
        foreach($row in $listed.Values){$actual=$packageRecords[$row.path];if($actual.path -cne $row.path -or $actual.bytes -ne $row.bytes -or $actual.sha256 -cne $row.sha256){throw 'Previous package records differ from pinned manifest'}}
        foreach($spec in @(@{root=$stateRoot;records=$stateRecords},@{root=$packageRoot;records=$packageRecords})){
            foreach($row in $spec.records.Values){$file=Open-BackupFile $session (Join-Path $spec.root $row.path) $row.sha256 $row.bytes;$opened.Add($file)}
        }
        $markerFile=@($opened|Where-Object {$_.path -ceq (Join-Path $packageRoot 'install-metadata.json')})[0]
        $marker=Read-BackupJson $markerFile
        Assert-BackupObject $marker @('schema_version','product_key','install_root','package_manifest_sha256')
        Assert-BackupEqual $marker.schema_version 'yimecore-trial-install-v1';Assert-BackupEqual $marker.product_key 'YimeCoreExperimentalTrial';Assert-BackupEqual $marker.install_root $ExpectedInstallRoot;Assert-BackupEqual $marker.package_manifest_sha256 $ExpectedPreviousManifestSha256
        if($marker.ContainsKey('staging') -and ($marker.staging -isnot [bool] -or $marker.staging)){throw 'Staged package is not the previous installed package'}
        $expectedTop=@('backup-manifest.json')+@($stateTree.files|ForEach-Object {'state/'+$_})+@($packageTree.files|ForEach-Object {'previous-package/'+$_})
        if(($top.files -join '|') -cne (($expectedTop|Sort-Object) -join '|') -or @($top.directories|Where-Object {$_ -cne 'state' -and $_ -cne 'previous-package' -and -not $_.StartsWith('state/',[StringComparison]::Ordinal) -and -not $_.StartsWith('previous-package/',[StringComparison]::Ordinal)}).Count){throw 'Backup is not a fresh complete two-tree archive'}
        foreach($file in $opened){Assert-BackupPlain $file.path;foreach($alternate in Get-Item -LiteralPath $file.path -Stream * -ErrorAction Stop){if($alternate.Stream -cne ':$DATA'){throw 'Alternate backup stream appeared'}};if($script:BackupNativeType::VerifyFileHandle($file.stream,$file.path) -cne $file.identity -or $file.stream.Length -ne $file.bytes -or (Get-BackupStreamHash $file.stream) -cne $file.sha256){throw 'Held backup file changed'}}
        $after=Get-BackupTree $BackupRoot $directoryLeases
        if(($top.files -join '|') -cne ($after.files -join '|') -or ($top.directories -join '|') -cne ($after.directories -join '|')){throw 'Backup membership changed during verification'}
        # The real producer embeds runtime-status diagnostics in live_runtime_before.
        # Keep original bytes/hash as evidence, but never forward that arbitrary
        # body (or unvalidated package extras) in a caller-visible receipt.
        $manifestMetadata=[pscustomobject][ordered]@{schema_version=$manifest.schema_version;generated_at=$manifest.generated_at;
            source_state_root=$manifest.source_state_root;source_install_root=$manifest.source_install_root;backup_root=$manifest.backup_root;
            runtime_pid_before=$manifest.runtime_pid_before;broker_pid_before=$manifest.broker_pid_before;
            writers_stopped=$manifest.writers_stopped;source_stable_during_copy=$manifest.source_stable_during_copy;
            native_context_verified=$manifest.native_context_verified;passed=$manifest.passed;
            state_files=$manifest.state_files;package_files=$manifest.package_files;data_files=$manifest.data_files}
        $previousMetadata=[pscustomobject][ordered]@{package_contract=$previous.package_contract;tool_version=$previous.tool_version;
            product_version=$previous.product_version;package_id=$previous.package_id;files=$previous.files}
        [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-backup-read-v1';static_backup_verified=$true;
            backup_manifest=[pscustomobject]@{path=$manifestFile.path;sha256=$manifestFile.sha256;bytes=$manifestFile.bytes};
            previous_manifest=[pscustomobject]@{path=$packageManifest.path;sha256=$packageManifest.sha256;bytes=$packageManifest.bytes;product_version=$previous.product_version;package_id=$previous.package_id};
            state_reference=[pscustomobject]@{root=$stateRoot;records=$manifest.state_files;directories=@($stateTree.directories)};data_reference=[pscustomobject]@{root=$stateRoot;records=$manifest.data_files};manifest=$manifestMetadata;previous_package_manifest=$previousMetadata;
            package_file_count=$packageRecords.Count;state_file_count=$stateRecords.Count;supplied_backup_exit_code=$ActualBackupExitCode;
            all_files_held_through_verification=$true;leases_released_on_return=$true;continuous_membership_protection=$false;
            actual_backup_exit_os_authenticated=$false;runtime_restart_verified=$false;native_context_authenticated=$false;independent_system_visibility_verified=$false;loaded_helper_identity_authenticated=$false;
            execution_authorized=$false;ready_to_execute=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
    }finally{foreach($stream in $session){$stream.Dispose()};foreach($directory in $directoryLeases.Values){$directory.Dispose()}}
}
Export-ModuleMember -Function Read-YimeCoreNativeMaintenanceBackup
