Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ReaderNativeFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:ReaderNativeType=$null
$script:ReaderJsonType=$null
function Initialize-RehearsalReaderTypes {
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))
    Assert-RehearsalPlainFile $source
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -lt 1 -or $stream.Length -gt 1048576){throw 'Invalid native helper source size'}
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$read=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($read -le 0){throw 'Truncated native helper source'};$offset+=$read}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($hash -cne $script:ReaderNativeFactsHash){throw 'Reviewed native helper source hash changed'}
        if($null -eq $script:ReaderNativeType){
            $sourceText=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes)
            $namespace='Yime.RehearsalReaderNative.N'+[guid]::NewGuid().ToString('N')
            $types=Add-Type -TypeDefinition ($sourceText.Replace('namespace Yime.Dp1UNative {','namespace '+$namespace+' {')) -PassThru
            $script:ReaderNativeType=@($types | Where-Object {$_.FullName -ceq ($namespace+'.Facts')})[0]
        }
        [void]$script:ReaderNativeType::VerifyFileHandle($stream,$source)
        Assert-RehearsalPlainFile $source
    } finally {$stream.Dispose()}
    if($null -ne $script:ReaderJsonType){return}
    # Deliberately narrow JSON: this schema has only integer numbers. Preserve
    # literal types and reject duplicate (including case-folded) property names.
    $parserSource=@'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
namespace Yime.RehearsalReader {
 public sealed class Json {
  readonly string text; int position;
  Json(string value){text=value;}
  void Space(){while(position<text.Length && (text[position]==' '||text[position]=='\t'||text[position]=='\r'||text[position]=='\n'))position++;}
  Exception Invalid(){return new FormatException("Strict outcome JSON rejected at offset "+position);}
  char Take(){if(position>=text.Length)throw Invalid();return text[position++];}
  void Expect(char value){if(Take()!=value)throw Invalid();}
  string ReadString(){
   Expect('"');var result=new StringBuilder();bool closed=false;
   while(position<text.Length){char c=Take();if(c=='"'){closed=true;break;}if(c<' ')throw Invalid();
    if(c=='\\'){c=Take();switch(c){case '"':case '\\':case '/':result.Append(c);break;
     case 'b':result.Append('\b');break;case 'f':result.Append('\f');break;case 'n':result.Append('\n');break;
     case 'r':result.Append('\r');break;case 't':result.Append('\t');break;
     case 'u':if(position+4>text.Length)throw Invalid();ushort code;
      if(!UInt16.TryParse(text.Substring(position,4),NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out code))throw Invalid();
      position+=4;result.Append((char)code);break;default:throw Invalid();}
    }else result.Append(c);
   }
   if(!closed)throw Invalid();string value=result.ToString();new UnicodeEncoding(false,false,true).GetBytes(value);return value;
  }
  object Value(int depth){
   if(depth>12)throw Invalid();Space();if(position>=text.Length)throw Invalid();char c=text[position];
   if(c=='"')return ReadString();
   if(c=='{'){
    position++;Space();var values=new Dictionary<string,object>(StringComparer.Ordinal);
    var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    if(position<text.Length && text[position]=='}'){position++;return values;}
    while(true){Space();string key=ReadString();if(!keys.Add(key))throw Invalid();Space();Expect(':');values.Add(key,Value(depth+1));Space();char next=Take();if(next=='}')return values;if(next!=',')throw Invalid();}
   }
   if(c=='['){
    position++;Space();var values=new List<object>();if(position<text.Length && text[position]==']'){position++;return values.ToArray();}
    while(true){values.Add(Value(depth+1));if(values.Count>128)throw Invalid();Space();char next=Take();if(next==']')return values.ToArray();if(next!=',')throw Invalid();}
   }
   foreach(string token in new[]{"true","false","null"}){
    if(position+token.Length<=text.Length && String.CompareOrdinal(text,position,token,0,token.Length)==0){position+=token.Length;if(token=="null")return null;return token=="true";}
   }
   int start=position;if(c=='-')position++;if(position>=text.Length||text[position]<'0'||text[position]>'9')throw Invalid();
   if(text[position]=='0')position++;else while(position<text.Length && text[position]>='0' && text[position]<='9')position++;
   long number;if(!Int64.TryParse(text.Substring(start,position-start),NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out number))throw Invalid();return number;
  }
  public static object Parse(string text){var reader=new Json(text);object value=reader.Value(0);reader.Space();if(reader.position!=text.Length)throw reader.Invalid();return value;}
 }
}
'@
    $namespace='Yime.RehearsalReaderParser.N'+[guid]::NewGuid().ToString('N')
    $types=Add-Type -TypeDefinition ($parserSource.Replace('namespace Yime.RehearsalReader {','namespace '+$namespace+' {')) -PassThru
    $script:ReaderJsonType=@($types | Where-Object {$_.FullName -ceq ($namespace+'.Json')})[0]
}
function Assert-RehearsalLiteralString($Value,[string]$Name) {
    if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)){throw "Literal nonempty string required: $Name"}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Value)
}
function Assert-RehearsalInteger($Value,[long]$Minimum,[long]$Maximum,[string]$Name) {
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw "Literal integer out of range: $Name"}
}
function Assert-RehearsalPath($Value,[string]$Name) {
    Assert-RehearsalLiteralString $Value $Name
    if($Value -cnotmatch '^[A-Z]:\\[^\\]+' -or $Value -match '[\x00-\x1f/"<>|?*%]' -or $Value.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Value) -cne $Value){throw "Canonical local absolute path required: $Name"}
    foreach($part in $Value.Substring(3).Split('\')){if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw "Ambiguous path: $Name"}}
}
function Assert-RehearsalPlainFile([string]$Path) {
    $cursor=$Path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect outcome path rejected'};$cursor=Split-Path -Parent $cursor}
}
function Assert-RehearsalFields($Value,[string[]]$Names,[string]$Name) {
    if($Value -isnot [Collections.Generic.Dictionary[string,object]] -or $Value.Count -ne $Names.Count){throw "Exact object fields required: $Name"}
    foreach($field in $Names){if(-not $Value.ContainsKey($field)){throw "Missing literal field $Name.$field"}}
}
function Assert-RehearsalEqual($Value,$Expected,[string]$Name) {
    if($Value -isnot [string] -or $Value -cne $Expected){throw "Expected binding mismatch: $Name"}
}
function Read-YimeCoreNativeRehearsalOutcome {
    [CmdletBinding()]param(
        [Parameter(Mandatory)]$OutcomePath,[Parameter(Mandatory)]$ActualControllerExitCode,
        [Parameter(Mandatory)]$ExpectedAttemptId,[Parameter(Mandatory)]$ExpectedTargetUserSid,
        [Parameter(Mandatory)]$ExpectedControllerSha256,
        # Producer source_manifest_sha256 is the DERIVATION NORMAL PACKAGE
        # manifest hash, never build/source-manifest.json or a source inventory.
        [Parameter(Mandatory)][Alias('ExpectedNormalPackageManifestSha256')]$ExpectedSourceManifestSha256,
        [Parameter(Mandatory)]$ExpectedFailureManifestSha256,[Parameter(Mandatory)]$ExpectedProducerPid,
        [Parameter(Mandatory)]$ExpectedProducerCreationFileTime,[Parameter(Mandatory)]$ExpectedOutcomeDirectory,
        [Parameter(Mandatory)]$ExpectedStateRoot,[Parameter(Mandatory)]$ExpectedPreviousInstallRoot,
        [Parameter(Mandatory)]$ExpectedTargetInstallRoot
    )
    Assert-RehearsalInteger $ActualControllerExitCode 1 26 'actual controller exit'
    if($ActualControllerExitCode -notin @(20,21,22,23,24,25)){throw 'No complete outcome can be accepted with actual controller exit 1 or 26, or an unknown exit'}
    Assert-RehearsalLiteralString $ExpectedAttemptId 'attempt'
    if($ExpectedAttemptId -cnotmatch '^[a-f0-9]{32}$'){throw 'Canonical attempt ID required'}
    Assert-RehearsalLiteralString $ExpectedTargetUserSid 'SID'
    if(([Security.Principal.SecurityIdentifier]::new($ExpectedTargetUserSid)).Value -cne $ExpectedTargetUserSid){throw 'Canonical target SID required'}
    foreach($hash in @($ExpectedControllerSha256,$ExpectedSourceManifestSha256,$ExpectedFailureManifestSha256)){
        Assert-RehearsalLiteralString $hash 'SHA256';if($hash -cnotmatch '^[a-f0-9]{64}$'){throw 'Canonical SHA256 required'}
    }
    Assert-RehearsalInteger $ExpectedProducerPid 1 ([int]::MaxValue) 'expected producer PID'
    Assert-RehearsalInteger $ExpectedProducerCreationFileTime 1 ([DateTime]::MaxValue.ToFileTimeUtc()) 'expected producer creation'
    foreach($path in @($OutcomePath,$ExpectedOutcomeDirectory,$ExpectedStateRoot,$ExpectedPreviousInstallRoot,$ExpectedTargetInstallRoot)){Assert-RehearsalPath $path 'expected path'}
    if($ExpectedPreviousInstallRoot -ieq $ExpectedTargetInstallRoot){throw 'Previous and target installation roots must differ'}
    if((Split-Path -Parent $OutcomePath) -cne $ExpectedOutcomeDirectory -or (Split-Path -Leaf $OutcomePath) -cne ('native-desktop-rehearsal-'+$ExpectedAttemptId+'.json')){throw 'Outcome destination is not bound to the expected directory and attempt'}
    Initialize-RehearsalReaderTypes
    Assert-RehearsalPlainFile $OutcomePath
    $stream=[IO.File]::Open($OutcomePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $identity=$script:ReaderNativeType::VerifyFileHandle($stream,$OutcomePath)
        if($stream.Length -le 0 -or $stream.Length -gt 262144){throw 'Outcome file exceeds bounded read'}
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$count=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($count -le 0){throw 'Incomplete outcome read'};$offset+=$count}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        $text=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes)
        $record=$script:ReaderJsonType::Parse($text)
        Assert-RehearsalFields $record @('schema_version','attempt_id','producer_pid','producer_creation_filetime','target_user_sid','controller_sha256','failure_manifest_sha256','source_manifest_sha256','state_root','previous_install_root','target_install_root','phase','events','registered_architectures','fault_runtime','rollback_attempted','rollback_procedure_completed','frozen_tip_finalizer_completed','unexpected_runtime_success','outcome','independent_registry_restore_verified','data_restore_verified','deferred_delete_absence_verified','loaded_code_identity_verified','execution_authorized','L6_sealed','local_product_ready','public_release_ready','outcome_complete','required_controller_exit_code') 'outcome'
        foreach($binding in @(
            @('schema_version','yimecore-native-desktop-rehearsal-outcome-v1'),@('attempt_id',$ExpectedAttemptId),
            @('target_user_sid',$ExpectedTargetUserSid),@('controller_sha256',$ExpectedControllerSha256),@('state_root',$ExpectedStateRoot))){Assert-RehearsalEqual $record[$binding[0]] $binding[1] $binding[0]}
        Assert-RehearsalInteger $record.producer_pid 1 ([int]::MaxValue) 'producer PID'
        Assert-RehearsalInteger $record.producer_creation_filetime 1 ([DateTime]::MaxValue.ToFileTimeUtc()) 'producer creation'
        if($record.producer_pid -ne $ExpectedProducerPid -or $record.producer_creation_filetime -ne $ExpectedProducerCreationFileTime){throw 'Producer PID/creation binding mismatch'}
        foreach($name in @('rollback_attempted','rollback_procedure_completed','frozen_tip_finalizer_completed','unexpected_runtime_success','outcome_complete','independent_registry_restore_verified','data_restore_verified','deferred_delete_absence_verified','loaded_code_identity_verified','execution_authorized','L6_sealed','local_product_ready','public_release_ready')){if($record[$name] -isnot [bool]){throw "Literal boolean required: $name"}}
        if(-not $record.outcome_complete){throw 'Outcome is incomplete'}
        foreach($name in @('independent_registry_restore_verified','data_restore_verified','deferred_delete_absence_verified','loaded_code_identity_verified','execution_authorized','L6_sealed','local_product_ready','public_release_ready')){if($record[$name]){throw "Producer cannot attest $name"}}
        if($record.events -isnot [object[]] -or $record.events.Count -lt 1 -or $record.events.Count -gt 14 -or $record.registered_architectures -isnot [object[]]){throw 'Literal bounded event and architecture arrays required'}
        $main=@('preflight','package_verified','baseline_verified','staged','preinstall_started','registered_x64','registered_x86','registered','fault_runtime_launched')
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$phases=New-Object 'Collections.Generic.List[string]'
        $index=0;$tail=$false;$lastTime=[DateTime]::FromFileTimeUtc($record.producer_creation_filetime)
        foreach($event in $record.events){
            Assert-RehearsalFields $event @('sequence','phase','observed_utc') 'event'
            Assert-RehearsalInteger $event.sequence 1 14 'event sequence'
            Assert-RehearsalLiteralString $event.phase 'event phase';Assert-RehearsalLiteralString $event.observed_utc 'event time'
            if($event.sequence -ne ($phases.Count+1) -or -not $seen.Add($event.phase)){throw 'Duplicate or unordered event sequence'}
            if($event.observed_utc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$'){throw 'Canonical UTC event time required'}
            $when=[DateTime]::ParseExact($event.observed_utc,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
            if($when -lt $lastTime){throw 'Event time reversed or predates producer'};$lastTime=$when
            if($main -ccontains $event.phase){if($tail -or $index -ge $main.Count -or $event.phase -cne $main[$index]){throw 'Missing or reversed main phase'};$index++}
            else {
                $tail=$true
                switch -CaseSensitive ($event.phase){
                    'fault_runtime_exited' {if($index -ne 9 -or $phases[$phases.Count-1] -cne 'fault_runtime_launched'){throw 'Exit phase without launch'}}
                    'unexpected_runtime_success' {if($index -ne 9 -or $phases[$phases.Count-1] -cne 'fault_runtime_launched'){throw 'Unexpected success phase without launch'}}
                    'rollback_started' {if($index -lt 5 -or $seen.Contains('previous_installation_restored') -or $seen.Contains('frozen_tip_finalizer_completed')){throw 'Rollback phase before mutation or after finalizer'}}
                    'previous_installation_restored' {if($phases[$phases.Count-1] -cne 'rollback_started'){throw 'Restore phase outside rollback'}}
                    'frozen_tip_finalizer_completed' {if($index -lt 3 -or ($index -ge 5 -and -not $seen.Contains('rollback_started'))){throw 'Finalizer before transaction/rollback'}}
                    default {throw 'Unknown outcome phase'}
                }
            }
            if($phases.Count -gt 0 -and $phases[$phases.Count-1] -ceq 'frozen_tip_finalizer_completed'){throw 'Event after finalizer'}
            $phases.Add($event.phase)
        }
        Assert-RehearsalEqual $record.phase $phases[$phases.Count-1] 'terminal phase'
        if($index -lt 1){throw 'Missing preflight event'}
        if($index -ge 2){Assert-RehearsalEqual $record.source_manifest_sha256 $ExpectedSourceManifestSha256 'source manifest';Assert-RehearsalEqual $record.failure_manifest_sha256 $ExpectedFailureManifestSha256 'failure manifest'}
        elseif($null -ne $record.source_manifest_sha256 -or $null -ne $record.failure_manifest_sha256){throw 'Manifest binding before verification phase'}
        if($index -ge 3){Assert-RehearsalEqual $record.previous_install_root $ExpectedPreviousInstallRoot 'previous root'}elseif($null -ne $record.previous_install_root){throw 'Previous root before verified baseline'}
        if($null -ne $record.target_install_root){if($index -lt 3){throw 'Target root before baseline'};Assert-RehearsalEqual $record.target_install_root $ExpectedTargetInstallRoot 'target root'}
        elseif($index -ge 4 -or $record.frozen_tip_finalizer_completed){throw 'Missing target root for transaction'}
        $architectures=@();if($index -ge 6){$architectures+='x64'};if($index -ge 7){$architectures+='x86'}
        if($record.registered_architectures.Count -ne $architectures.Count){throw 'Architecture count does not match phases'}
        for($a=0;$a -lt $architectures.Count;$a++){Assert-RehearsalEqual $record.registered_architectures[$a] $architectures[$a] 'architecture'}
        if($record.rollback_attempted -ne $seen.Contains('rollback_started') -or ($index -ge 5 -and -not $record.rollback_attempted) -or
            ($record.rollback_procedure_completed -and -not $seen.Contains('previous_installation_restored')) -or
            $record.frozen_tip_finalizer_completed -ne $seen.Contains('frozen_tip_finalizer_completed') -or
            $record.unexpected_runtime_success -ne $seen.Contains('unexpected_runtime_success')){throw 'Phase/boolean relationship mismatch'}
        if($index -eq 9){
            $runtime=$record.fault_runtime
            Assert-RehearsalFields $runtime @('pid','creation_filetime','launch_path','natural_exit_observed','exit_code','controller_termination_requested') 'fault runtime'
            Assert-RehearsalInteger $runtime.pid 1 ([int]::MaxValue) 'runtime PID'
            Assert-RehearsalInteger $runtime.creation_filetime $record.producer_creation_filetime ([DateTime]::MaxValue.ToFileTimeUtc()) 'runtime creation'
            if($runtime.pid -eq $record.producer_pid){throw 'Runtime and producer PID overlap'}
            Assert-RehearsalEqual $runtime.launch_path ($ExpectedTargetInstallRoot+'\bin\YimeCoreTrialRuntime.exe') 'fault runtime path'
            if($runtime.natural_exit_observed -isnot [bool] -or $runtime.controller_termination_requested -isnot [bool]){throw 'Literal runtime boolean required'}
            if($runtime.natural_exit_observed -ne $seen.Contains('fault_runtime_exited') -or ($runtime.natural_exit_observed -and $runtime.controller_termination_requested)){throw 'Natural exit and controller termination conflict'}
            if($runtime.natural_exit_observed){Assert-RehearsalInteger $runtime.exit_code ([int]::MinValue) ([int]::MaxValue) 'runtime exit'}elseif($null -ne $runtime.exit_code){throw 'Exit code without natural exit'}
            if($record.unexpected_runtime_success -and ($runtime.natural_exit_observed -or $runtime.controller_termination_requested)){throw 'Unexpected success conflicts with runtime termination'}
            $launched=@($record.events | Where-Object {$_.phase -ceq 'fault_runtime_launched'})[0]
            if([DateTime]::FromFileTimeUtc($runtime.creation_filetime) -gt [DateTime]::ParseExact($launched.observed_utc,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)){throw 'Runtime creation follows launch observation'}
        } elseif($null -ne $record.fault_runtime){throw 'Runtime facts before launch phase'}
        $expectedOutcome=if($record.rollback_attempted -and -not $record.rollback_procedure_completed){'rollback_failed'}
            elseif($record.rollback_attempted -and -not $record.frozen_tip_finalizer_completed){'protection_finalizer_failed'}
            elseif(-not $record.rollback_attempted){'preflight_or_staging_rejected'}
            elseif($record.unexpected_runtime_success){'unexpected_runtime_success_rollback_completed'}
            elseif($null -ne $record.fault_runtime -and $record.fault_runtime.natural_exit_observed -and $record.fault_runtime.exit_code -eq 86 -and $architectures.Count -eq 2){'expected_fault_rollback_completed'}
            else{'unexpected_failure_rollback_completed'}
        Assert-RehearsalEqual $record.outcome $expectedOutcome 'outcome classification'
        $required=@{expected_fault_rollback_completed=20;unexpected_runtime_success_rollback_completed=21;rollback_failed=22;protection_finalizer_failed=23;unexpected_failure_rollback_completed=24;preflight_or_staging_rejected=25}[$expectedOutcome]
        Assert-RehearsalInteger $record.required_controller_exit_code 20 25 'required exit'
        if($record.required_controller_exit_code -ne $required -or $ActualControllerExitCode -ne $required){throw 'Actual controller exit and typed outcome disagree'}
        Assert-RehearsalPlainFile $OutcomePath
        if($script:ReaderNativeType::VerifyFileHandle($stream,$OutcomePath) -cne $identity -or $stream.Length -ne $bytes.Length){throw 'Outcome file identity changed'}
        [pscustomobject][ordered]@{schema_version='yimecore-native-rehearsal-outcome-read-v1';record_consistent=$true;
            expected_fault_procedure_observed=($required -eq 20);outcome=$expectedOutcome;actual_controller_exit_code=$ActualControllerExitCode;
            outcome_path=$OutcomePath;outcome_sha256=$hash;outcome_bytes=$bytes.Length;file_identity=$identity;record=$record;
            helper_source_sha256=$script:ReaderNativeFactsHash;helper_type=$script:ReaderNativeType.FullName;
            loaded_helper_identity_authenticated=$false;actual_exit_os_authenticated=$false;producer_process_authenticated=$false;native_execution_authenticated=$false;
            independent_restore_verified=$false;startup_verified=$false;runtime_ready_verified=$false;source_readiness=$false;
            execution_authorized=$false;ready_to_execute=$false;local_product_ready=$false;public_release_ready=$false;L6_sealed=$false}
    } finally {$stream.Dispose()}
}
Export-ModuleMember -Function Read-YimeCoreNativeRehearsalOutcome
