Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:RuntimeModuleSource=$PSCommandPath
$script:RuntimeProcessModule=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-processes.psm1') -Scope Local -PassThru
$script:RuntimeFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:RuntimeFactsType=$null
$script:RuntimeJsonType=$null

function Assert-MaintenanceRuntimePath($Value) {
    if($Value -isnot [string] -or $Value -cnotmatch '^[A-Z]:\\[^\\]+' -or $Value -match '[\x00-\x1f/"<>|?*%]' -or
        $Value.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Value) -cne $Value){throw 'Explicit canonical local root required'}
    foreach($part in $Value.Substring(3).Split('\')){if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Ambiguous runtime observation root'}}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Value)
}
function Assert-MaintenanceRuntimePlainPath([string]$Path) {
    $cursor=$Path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect runtime observation path rejected'};$cursor=Split-Path -Parent $cursor}
}
function Get-MaintenanceRuntimeHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Read-MaintenanceRuntimeBytes([IO.FileStream]$Stream,[int]$Limit) {
    if($Stream.Length -le 0 -or $Stream.Length -gt $Limit){throw 'Runtime metadata exceeds bounded read'}
    $bytes=New-Object byte[] ([int]$Stream.Length);$offset=0;$Stream.Position=0
    while($offset -lt $bytes.Length){$count=$Stream.Read($bytes,$offset,$bytes.Length-$offset);if($count -le 0){throw 'Incomplete runtime metadata read'};$offset+=$count}
    return ,$bytes
}
function Initialize-MaintenanceRuntimeTypes {
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))
    Assert-MaintenanceRuntimePlainPath $source
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $bytes=Read-MaintenanceRuntimeBytes $stream 131072
        if((Get-MaintenanceRuntimeHash $bytes) -cne $script:RuntimeFactsHash){throw 'Reviewed native runtime facts source changed'}
        if($null -eq $script:RuntimeFactsType){
            $text=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes)
            $namespace='Yime.MaintenanceRuntimeFacts.N'+[guid]::NewGuid().ToString('N')
            $types=@(Add-Type -TypeDefinition ($text.Replace('namespace Yime.Dp1UNative {','namespace '+$namespace+' {')) -PassThru)
            $script:RuntimeFactsType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Facts')})[0]
        }
        [void]$script:RuntimeFactsType::VerifyFileHandle($stream,$source)
    } finally {$stream.Dispose()}
    if($null -ne $script:RuntimeJsonType){return}
    # The actual config producer emits a flat string-only object. Reject other
    # JSON types and duplicate/case-colliding keys before PowerShell conversion.
    $parser=@'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
namespace Yime.MaintenanceRuntimeJson {
 public sealed class ConfigJson {
  readonly string text; int position;
  ConfigJson(string text){this.text=text;}
  void Space(){while(position<text.Length && (text[position]==' '||text[position]=='\t'||text[position]=='\r'||text[position]=='\n'))position++;}
  Exception Bad(){return new FormatException("Strict runtime configuration JSON rejected.");}
  char Take(){if(position>=text.Length)throw Bad();return text[position++];}
  void Expect(char value){if(Take()!=value)throw Bad();}
  string String(){
   Expect('"');var result=new StringBuilder();bool closed=false;
   while(position<text.Length){char c=Take();if(c=='"'){closed=true;break;}if(c<' ')throw Bad();
    if(c=='\\'){c=Take();switch(c){case '"':case '\\':case '/':result.Append(c);break;
     case 'b':result.Append('\b');break;case 'f':result.Append('\f');break;case 'n':result.Append('\n');break;
     case 'r':result.Append('\r');break;case 't':result.Append('\t');break;
     case 'u':if(position+4>text.Length)throw Bad();ushort code;
      if(!UInt16.TryParse(text.Substring(position,4),NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out code))throw Bad();
      position+=4;result.Append((char)code);break;default:throw Bad();}
    }else result.Append(c);
   }
   if(!closed)throw Bad();string value=result.ToString();new UnicodeEncoding(false,false,true).GetBytes(value);return value;
  }
  public static Dictionary<string,string> Parse(string text){
   var reader=new ConfigJson(text);reader.Space();reader.Expect('{');reader.Space();
   var result=new Dictionary<string,string>(StringComparer.Ordinal);var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   while(true){reader.Space();string key=reader.String();if(!keys.Add(key)||keys.Count>11)throw reader.Bad();
    reader.Space();reader.Expect(':');reader.Space();result.Add(key,reader.String());reader.Space();char next=reader.Take();
    if(next=='}')break;if(next!=',')throw reader.Bad();
   }
   reader.Space();if(reader.position!=text.Length)throw reader.Bad();return result;
  }
 }
}
'@
    $namespace='Yime.MaintenanceRuntimeJson.N'+[guid]::NewGuid().ToString('N')
    $types=@(Add-Type -TypeDefinition ($parser.Replace('namespace Yime.MaintenanceRuntimeJson {','namespace '+$namespace+' {')) -PassThru)
    $script:RuntimeJsonType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.ConfigJson')})[0]
}
function Read-MaintenanceRuntimeProcesses($Observation) {
    # Original lease only. The dependency re-reads held OS handles and rejects
    # a serialized/tampered public evidence object instead of trusting its JSON.
    & $script:RuntimeProcessModule {param($value) Assert-YimeCoreNativeMaintenanceProcessesCurrent -Observation $value} $Observation
}
function Assert-MaintenanceRuntimeProcessShape($Value) {
    if($null -eq $Value -or $Value.schema_version -isnot [string] -or $Value.schema_version -cne 'yimecore-native-maintenance-processes-v1' -or
        $Value.native_handle_identity_observed -isnot [bool] -or -not $Value.native_handle_identity_observed -or
        $Value.native_parent_relation_observed -isnot [bool] -or -not $Value.native_parent_relation_observed -or
        $Value.public_image_hash_verified -isnot [bool] -or -not $Value.public_image_hash_verified -or
        $Value.target_user_sid -isnot [string] -or $Value.target_user_sid -cnotmatch '^S-1-5-21-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*$' -or
        $Value.processes -isnot [array] -or $Value.processes.Count -ne 2){throw 'Retained native process evidence is incomplete'}
    Assert-MaintenanceRuntimePath $Value.expected_install_root
    $index=0
    foreach($role in @('runtime','broker')){
        $row=$Value.processes[$index];$name=if($role -ceq 'runtime'){'YimeCoreTrialRuntime.exe'}else{'YimeBroker.exe'}
        if($row.role -isnot [string] -or $row.role -cne $role -or $row.pid -isnot [int] -or $row.pid -le 0 -or
            $row.parent_pid -isnot [int] -or $row.parent_pid -le 0 -or $row.creation_filetime -isnot [long] -or $row.creation_filetime -le 0 -or
            $row.image -isnot [string] -or $row.image -ine (Join-Path $Value.expected_install_root ('bin\'+$name)) -or
            $row.sid -isnot [string] -or $row.sid -cne $Value.target_user_sid -or $row.elevated -isnot [bool] -or $row.elevated -or
            $row.image_sha256 -isnot [string] -or $row.image_sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Retained native process identity is invalid'}
        $index++
    }
    if($Value.processes[0].pid -eq $Value.processes[1].pid -or $Value.processes[1].parent_pid -ne $Value.processes[0].pid -or
        $Value.processes[1].creation_filetime -lt $Value.processes[0].creation_filetime){throw 'Retained Runtime/Broker relation differs'}
}
function Assert-MaintenanceRuntimeConfig($Config,$Processes,[string]$StateRoot) {
    $names=@('schema_version','generated_at','install_root','runtime_path','broker_path','state_root','pipe_name','experimental_clsid','experimental_input_method_tip')
    if($Config -isnot [Collections.Generic.Dictionary[string,string]] -or $Config.Count -notin @(9,11)){throw 'Exact runtime config fields required'}
    foreach($name in $names){if(-not $Config.ContainsKey($name)){throw 'Required runtime config metadata is missing'}}
    if($Config.Count -eq 11 -and (-not $Config.ContainsKey('runtime_sha256') -or -not $Config.ContainsKey('broker_sha256'))){throw 'Only the paired deployed image hashes are optional'}
    foreach($pair in @(
        @('schema_version','yimecore-trial-runtime-config-v1'),@('install_root',$Processes.expected_install_root),@('state_root',$StateRoot),
        @('runtime_path',(Join-Path $Processes.expected_install_root 'bin\YimeCoreTrialRuntime.exe')),
        @('broker_path',(Join-Path $Processes.expected_install_root 'bin\YimeBroker.exe')),@('pipe_name','\\.\pipe\YimeBroker.YimeCoreTrial.v1'),
        @('experimental_clsid','{E40FA752-BB96-461D-A51D-F40EB437EC65}'),
        @('experimental_input_method_tip','0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}'))){
        if($Config[$pair[0]] -cne $pair[1]){throw 'Runtime config does not match its fixed product/process/state identity'}
    }
    $generated=[DateTime]::MinValue
    if(-not [DateTime]::TryParseExact($Config.generated_at,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$generated) -or
        $generated.Kind -ne [DateTimeKind]::Utc -or $generated.ToString('o') -cne $Config.generated_at -or $generated -gt [DateTime]::UtcNow.AddSeconds(5)){throw 'Canonical nonfuture config generation time required'}
    # A saved generation time is configuration metadata, never restart/logon evidence.
    if($Config.Count -eq 11){
        if($Config.runtime_sha256 -cne $Processes.processes[0].image_sha256 -or $Config.broker_sha256 -cne $Processes.processes[1].image_sha256){throw 'Optional deployed hashes disagree with retained process images'}
    }
}
function Get-YimeCoreNativeMaintenanceRuntime {
    [CmdletBinding()]param([Parameter(Mandatory)]$ProcessObservation,[Parameter(Mandatory)]$StateRoot,[Parameter(Mandatory)]$ExpectedRuntimeConfigSha256)
    Assert-MaintenanceRuntimePath $StateRoot
    if($ExpectedRuntimeConfigSha256 -isnot [string] -or $ExpectedRuntimeConfigSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Literal verified backup runtime config SHA256 required'}
    # Validate original process lease before opening the explicitly named config.
    $before=Read-MaintenanceRuntimeProcesses $ProcessObservation;Assert-MaintenanceRuntimeProcessShape $before
    if($StateRoot -ieq $before.expected_install_root -or $StateRoot.StartsWith($before.expected_install_root+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $before.expected_install_root.StartsWith($StateRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime state and installed payload roots must be independent'}
    Initialize-MaintenanceRuntimeTypes
    $path=Join-Path $StateRoot 'runtime-config.json';Assert-MaintenanceRuntimePlainPath $path
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $identity=$script:RuntimeFactsType::VerifyFileHandle($stream,$path)
        $bytes=Read-MaintenanceRuntimeBytes $stream 16384;$hash=Get-MaintenanceRuntimeHash $bytes
        if($hash -cne $ExpectedRuntimeConfigSha256){throw 'Runtime configuration differs from verified backup baseline'}
        $config=$script:RuntimeJsonType::Parse(([Text.UTF8Encoding]::new($false,$true)).GetString($bytes))
        Assert-MaintenanceRuntimeConfig $config $before $StateRoot
        $after=Read-MaintenanceRuntimeProcesses $ProcessObservation;Assert-MaintenanceRuntimeProcessShape $after
        if((ConvertTo-Json -InputObject $before -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $after -Depth 20 -Compress)){throw 'Retained process facts changed during config validation'}
        Assert-MaintenanceRuntimePlainPath $path
        if($script:RuntimeFactsType::VerifyFileHandle($stream,$path) -cne $identity -or $stream.Length -ne $bytes.Length){throw 'Runtime configuration identity changed'}
        $projection=[ordered]@{};foreach($name in @('schema_version','generated_at','install_root','runtime_path','broker_path','state_root','pipe_name','experimental_clsid','experimental_input_method_tip')){$projection[$name]=$config[$name]}
        if($config.Count -eq 11){$projection.runtime_sha256=$config.runtime_sha256;$projection.broker_sha256=$config.broker_sha256}
        [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-runtime-v1';context_consistent=$true;processes=$after;
            runtime_config=[pscustomobject][ordered]@{path=$path;bytes=$bytes.Length;sha256=$hash;file_identity=$identity;metadata=$projection};
            config_bound_to_expected_sha256=$true;config_semantics_verified=$true;retained_process_lease_checked_twice=$true;
            source_sha256=(Get-FileHash -LiteralPath $script:RuntimeModuleSource -Algorithm SHA256).Hash.ToLowerInvariant();helper_source_sha256=$script:RuntimeFactsHash;
            loaded_helper_identity_authenticated=$false;in_memory_code_identity_verified=$false;process_command_line_verified=$false;
            runtime_consumed_config_verified=$false;readonly_health_protocol_available=$false;health_endpoint_contacted=$false;session_created=$false;
            runtime_status_read=$false;settings_or_learning_read=$false;rollback_restart_verified=$false;reboot_logon_startup_verified=$false;
            startup_verified=$false;runtime_ready_verified=$false;continuous_monitoring=$false;E7_verified=$false;L6_sealed=$false;
            execution_authorized=$false;ready_to_execute=$false;local_product_ready=$false;public_release_ready=$false;
            pending_reason='This observer validates process/config consistency without requesting health. The rollback collector still pins legacy local.12; this observation does not determine other candidates health capability, engine readiness, a rollback-caused restart, or reboot/logon startup.'}
    } finally {$stream.Dispose()}
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceRuntime
