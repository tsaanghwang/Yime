# Definitions-only canonical receipt-v2 closure for one disabled Rime/PIME
# candidate.  This file never starts makensis, 7-Zip, an installer, an
# uninstaller, a signing host, or an installed product process.

$script:RimePimePackageReceiptV2Schema='yime-rime-pime-package-build-receipt-v2'
$script:RimePimePackageReceiptV1Schema='yime-rime-pime-package-build-receipt-v1'

function Get-RimePimeReceiptV2Sha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Read-RimePimeReceiptV2StreamBytes {
    param(
        [Parameter(Mandatory)][IO.FileStream]$Stream,
        [Parameter(Mandatory)][long]$Maximum,
        [Parameter(Mandatory)][string]$Context
    )
    if(-not $Stream.CanRead -or -not $Stream.CanSeek){throw "$Context lease is not readable and seekable."}
    if([long]$Stream.Length -lt 1 -or [long]$Stream.Length -gt $Maximum){throw "$Context exceeds its byte bound."}
    $position=$Stream.Position
    try{
        $Stream.Position=0;$bytes=New-Object byte[] ([int]$Stream.Length);$offset=0
        while($offset -lt $bytes.Length){
            $read=$Stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($read -le 0){throw "$Context ended before its leased byte count."}
            $offset+=$read
        }
        if($Stream.ReadByte() -ne -1){throw "$Context grew while leased."}
        return ,$bytes
    }finally{$Stream.Position=$position}
}

# Validate syntax before either PowerShell JSON parser can discard duplicate
# members or accept comments/trailing commas. Keys are case-insensitive because
# the downstream PSObject reader is case-insensitive. No JSON normalization.
function Assert-RimePimeReceiptJsonSyntax([string]$Text) {
    if (-not ('YimeReceiptJson.Syntax' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
namespace YimeReceiptJson {
 public sealed class Syntax {
  readonly string s; int p;
  Syntax(string text) { s=text; }
  void Fail() { throw new FormatException("Invalid or ambiguous receipt JSON at offset " + p); }
  void Ws() { while(p<s.Length && (s[p]==' ' || s[p]=='\r' || s[p]=='\n' || s[p]=='\t')) p++; }
  bool Take(char c) { Ws(); if(p<s.Length && s[p]==c) { p++; return true; } return false; }
  string Str() {
   if(!Take('"')) Fail(); var b=new StringBuilder();
   while(p<s.Length) {
    char c=s[p++]; if(c=='"') return b.ToString(); if(c<32) Fail();
    if(c=='\\') {
     if(p==s.Length) Fail(); c=s[p++];
     switch(c) {
      case '"': case '\\': case '/': break;
      case 'b': c='\b'; break; case 'f': c='\f'; break;
      case 'n': c='\n'; break; case 'r': c='\r'; break; case 't': c='\t'; break;
      case 'u':
       if(p+4>s.Length || !Regex.IsMatch(s.Substring(p,4),"\\A[0-9a-fA-F]{4}\\z")) Fail();
       c=(char)Convert.ToInt32(s.Substring(p,4),16); p+=4; break;
      default: Fail(); break;
     }
    }
    b.Append(c);
   }
   Fail(); return null;
  }
  void Value(int depth) {
   if(depth>64) Fail(); Ws(); if(p==s.Length) Fail();
   if(Take('{')) {
    var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    if(Take('}')) return;
    do { string key=Str(); if(!keys.Add(key) || !Take(':')) Fail(); Value(depth+1); if(Take('}')) return; } while(Take(','));
    Fail();
   } else if(Take('[')) {
    if(Take(']')) return;
    do { Value(depth+1); if(Take(']')) return; } while(Take(',')); Fail();
   } else if(s[p]=='"') { Str(); }
   else {
    var m=Regex.Match(s.Substring(p),"\\A(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)");
    if(!m.Success) Fail(); p+=m.Length;
   }
  }
  public static void Check(string text) { var v=new Syntax(text); v.Value(0); v.Ws(); if(v.p!=text.Length) v.Fail(); }
 }
}
'@
    }
    [YimeReceiptJson.Syntax]::Check($Text)
}

function Open-RimePimeReceiptV2SealedJsonLease {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Context,
        [switch]$AllowDelete
    )
    $full=[IO.Path]::GetFullPath($Path);$sidecar=$full+'.sha256'
    foreach($candidate in @($full,$sidecar)){
        if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw "$Context sealed input is missing: $candidate"}
        Assert-RimePimeNoReparsePath $candidate
    }
    $share=[IO.FileShare]::Read
    if($AllowDelete){$share=$share -bor [IO.FileShare]::Delete}
    $jsonStream=$null;$sidecarStream=$null
    try{
        $jsonStream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        $sidecarStream=[IO.File]::Open($sidecar,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        Assert-RimePimeNoReparsePath $full;Assert-RimePimeNoReparsePath $sidecar
        $jsonBytes=Read-RimePimeReceiptV2StreamBytes $jsonStream 4194304 $Context
        $sidecarBytes=Read-RimePimeReceiptV2StreamBytes $sidecarStream 256 "$Context sidecar"
        foreach($one in $sidecarBytes){if($one -gt 127){throw "$Context sidecar is not ASCII."}}
        $sidecarText=[Text.Encoding]::ASCII.GetString($sidecarBytes)
        $pattern='\A([0-9a-f]{64})  '+[regex]::Escape([IO.Path]::GetFileName($full))+'(?:\r\n|\n)?\z'
        if($sidecarText -cnotmatch $pattern){throw "$Context sidecar is malformed."}
        $digest=Get-RimePimeReceiptV2Sha256Bytes $jsonBytes
        if($digest -cne [string]$Matches[1]){throw "$Context sidecar does not match its leased JSON bytes."}
        $utf8=New-Object Text.UTF8Encoding($false,$true)
        try{
            Assert-RimePimeReceiptJsonSyntax ($utf8.GetString($jsonBytes))
            # PS7 otherwise coerces receipt timestamps into DateTime objects,
            # losing their JSON representation during retained publication.
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
                $value=$utf8.GetString($jsonBytes)|ConvertFrom-Json -DateKind String
            } else { $value=$utf8.GetString($jsonBytes)|ConvertFrom-Json }
        }
        catch{throw "$Context is not strict UTF-8 JSON: $($_.Exception.Message)"}
        return [pscustomobject]@{
            Path=$full;Sidecar=$sidecar;JsonStream=$jsonStream;SidecarStream=$sidecarStream
            JsonBytes=[byte[]]$jsonBytes;SidecarBytes=[byte[]]$sidecarBytes;Bytes=[long]$jsonBytes.Length
            Digest=$digest;Value=$value
        }
    }catch{
        if($null -ne $sidecarStream){$sidecarStream.Dispose()}
        if($null -ne $jsonStream){$jsonStream.Dispose()}
        throw
    }
}

function Open-RimePimeReceiptV2FileLease {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][long]$ExpectedBytes,
        [Parameter(Mandatory)][string]$Context
    )
    if($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or $ExpectedBytes -lt 1){throw "$Context expected identity is invalid."}
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "$Context is missing: $full"}
    Assert-RimePimeNoReparsePath $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $bytes=Read-RimePimeReceiptV2StreamBytes $stream ([Math]::Max($ExpectedBytes,4194304)) $Context
        $digest=Get-RimePimeReceiptV2Sha256Bytes $bytes
        if([long]$bytes.Length -ne $ExpectedBytes -or $digest -cne $ExpectedSha256){throw "$Context differs from its sealed identity."}
        return [pscustomobject]@{Path=$full;Stream=$stream;Bytes=[long]$bytes.Length;Digest=$digest}
    }catch{$stream.Dispose();throw}
}

function Open-RimePimeReceiptV2RawSidecarLease {
    param(
        [Parameter(Mandatory)][string]$DataPath,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$Context
    )
    $path=[IO.Path]::GetFullPath($DataPath)+'.sha256'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "$Context SHA-256 sidecar is missing: $path"}
    Assert-RimePimeNoReparsePath $path
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $bytes=Read-RimePimeReceiptV2StreamBytes $stream 256 "$Context SHA-256 sidecar"
        foreach($one in $bytes){if($one -gt 127){throw "$Context SHA-256 sidecar is not ASCII."}}
        $text=[Text.Encoding]::ASCII.GetString($bytes)
        $pattern='\A'+[regex]::Escape($ExpectedSha256)+'  '+[regex]::Escape([IO.Path]::GetFileName([IO.Path]::GetFullPath($DataPath)))+'(?:\r\n|\n)?\z'
        if($text -cnotmatch $pattern){throw "$Context SHA-256 sidecar does not bind the data file."}
        return [pscustomobject]@{Path=$path;Stream=$stream;Bytes=[long]$bytes.Length;Digest=(Get-RimePimeReceiptV2Sha256Bytes $bytes)}
    }catch{$stream.Dispose();throw}
}

function Close-RimePimePackageReceiptV2Preparation {
    param($Prepared)
    if($null -eq $Prepared){return}
    foreach($lease in @($Prepared.FileLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
    foreach($lease in @($Prepared.JsonLeases)){
        if($null -ne $lease.SidecarStream){$lease.SidecarStream.Dispose()}
        if($null -ne $lease.JsonStream){$lease.JsonStream.Dispose()}
    }
}

function Test-RimePimeReceiptV2OrderedArchitectures {
    param($Value)
    $items=@($Value)
    return $items.Count -eq 2 -and [string]$items[0] -ceq 'x86' -and [string]$items[1] -ceq 'x64'
}

function Assert-RimePimeReceiptV2Hash {
    param($Value,[string]$Context)
    if([string]$Value -cnotmatch '^[0-9a-f]{64}$'){throw "$Context is not a lowercase SHA-256 digest."}
}

function Assert-RimePimeReceiptV2RequiredProperties {
    param($Value,[string[]]$Required,[string]$Context)
    if($null -eq $Value -or $Value -is [string] -or $null -eq $Value.PSObject){throw "$Context must be an object."}
    $actual=@($Value.PSObject.Properties|ForEach-Object Name)
    foreach($name in $Required){if($actual -cnotcontains $name){throw "$Context is missing required property $name."}}
}

function Test-RimePimeReceiptV2Boolean {
    param($Value,[bool]$Expected)
    return $Value -is [bool] -and [bool]$Value -eq $Expected
}

function ConvertTo-RimePimeReceiptV2RelativePath {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\');$full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Receipt-v2 evidence path is outside the repository: $full"}
    Assert-RimePimeNoReparsePath $full
    return ConvertTo-RimePimePackagePath $full.Substring($root.Length+1).Replace('\','/')
}

function Assert-RimePimeReceiptV2Predecessor {
    param($Receipt,[string]$RepoRoot)
    Assert-RimePimeExactProperties $Receipt @(
        'schema_version','product','closure_scope','architectures','package_plan_path','package_plan_sha256','nsis_profile',
        'installer_source_path','installer_source_sha256','installer_path','installer_size','installer_sha256','sealed_at_utc') 'receipt-v2 predecessor v1'
    if([string]$Receipt.schema_version -cne $script:RimePimePackageReceiptV1Schema -or
        [string]$Receipt.product -cne 'rime-pime' -or
        [string]$Receipt.closure_scope -cne 'declared-packaged-product-pe-inputs-only-not-installed-payload' -or
        -not(Test-RimePimeReceiptV2OrderedArchitectures $Receipt.architectures) -or
        [string]$Receipt.nsis_profile -cne 'x86-x64-v1' -or
        -not(Test-RimePimeStageInteger $Receipt.installer_size) -or [long]$Receipt.installer_size -lt 65536 -or
        -not(Test-RimePimeUtcTimestamp $Receipt.sealed_at_utc)){
        throw 'Receipt-v2 predecessor is not an admitted historical v1 build receipt.'
    }
    foreach($hash in @('package_plan_sha256','installer_source_sha256','installer_sha256')){
        Assert-RimePimeReceiptV2Hash $Receipt.$hash "receipt-v2 predecessor $hash"
    }
    foreach($path in @('package_plan_path','installer_source_path','installer_path')){$null=ConvertTo-RimePimePackagePath ([string]$Receipt.$path)}
}

function Assert-RimePimeReceiptV2BuildEvidence {
    param($Build,$V1,$Manifest,$PayloadReceipt,$Postbuild)
    Assert-RimePimeReceiptV2RequiredProperties $Build @(
        'schema_version','product','product_version','package_profile','architectures','package_plan_sha256','payload_spec_sha256',
        'content_manifest_sha256','content_tree_sha256','payload_nsh_sha256','copied_file_count','payload_file_count','bootstrap_file_count',
        'candidate_installer_sha256','candidate_installer_bytes','package_build_receipt_sha256','candidate_leased','prebuild_stage_verified',
        'postbuild_stage_verified','prebuild_include_verified','postbuild_include_verified','installer_raw_byte_search_found_expected_digests',
        'executed_build_logic_source_count','executed_build_logic_sources','build_logic_read_lease_count',
        'repository_local_compiler_inputs_leased','makensis_path_lease_verified','build_tool_processes_executed','makensis_executed',
        'makensis_sha256','nsis_toolchain_lock_sha256','nsis_compiler_input_scope','nsis_compiler_input_tree_sha256',
        'nsis_compiler_input_file_count','nsis_compiler_input_directory_count','nsis_compiler_input_read_lease_count',
        'nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
        'nsis_toolchain_control_read_lease_count','nsis_known_input_file_replacement_closure',
        'nsis_compiler_input_pre_snapshot_exact','nsis_compiler_input_post_snapshot_exact',
        'nsis_compiler_input_leases_held_during_makensis',
        'active_same_sid_transient_tree_membership_interference_excluded',
        'nsis_non_os_compiler_input_closure','full_nsis_toolchain_input_closure',
        'unsigned_disabled_build','signing_hook_processes_executed','installer_executed','uninstaller_executed',
        'installed_product_processes_touched','product_registry_mutated','default_input_method_changed','production_user_data_read_or_written',
        'installed_yimecore_local12_touched') 'receipt-v2 build result'
    if([string]$Build.schema_version -cnotmatch '^yime-rime-pime-staged-nsis-build-result-v[1-9][0-9]*$' -or
        [string]$Build.product -cne 'rime-pime' -or [string]$Build.product_version -cne [string]$Manifest.product_version -or
        [string]$Build.package_profile -cne 'x86-x64-v1' -or -not(Test-RimePimeReceiptV2OrderedArchitectures $Build.architectures) -or
        [string]$Build.package_plan_sha256 -cne [string]$Manifest.package_plan_sha256 -or
        [string]$Build.payload_spec_sha256 -cne [string]$Manifest.payload_spec_sha256 -or
        [string]$Build.content_manifest_sha256 -cne [string]$Postbuild.content_manifest_sha256 -or
        [string]$Build.content_tree_sha256 -cne [string]$Manifest.content_tree_sha256 -or
        [string]$Build.payload_nsh_sha256 -cne [string]$PayloadReceipt.include_sha256 -or
        [string]$Build.candidate_installer_sha256 -cne [string]$V1.installer_sha256 -or
        [long]$Build.candidate_installer_bytes -ne [long]$V1.installer_size -or
        [string]$Build.package_build_receipt_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        -not(Test-RimePimeStageInteger $Build.executed_build_logic_source_count) -or
        [int]$Build.executed_build_logic_source_count -lt 1 -or
        @($Build.executed_build_logic_sources).Count -ne [int]$Build.executed_build_logic_source_count -or
        -not(Test-RimePimeStageInteger $Build.build_logic_read_lease_count) -or
        [int]$Build.build_logic_read_lease_count -ne [int]$Build.executed_build_logic_source_count -or
        -not(Test-RimePimeReceiptV2Boolean $Build.repository_local_compiler_inputs_leased $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.makensis_path_lease_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.build_tool_processes_executed $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.makensis_executed $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.candidate_leased $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.prebuild_stage_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.postbuild_stage_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.prebuild_include_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.postbuild_include_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.installer_raw_byte_search_found_expected_digests $true) -or
        [string]$Build.nsis_compiler_input_scope -cne 'repository-pinned-nsis-distribution-non-os-v1' -or
        -not(Test-RimePimeReceiptV2Boolean $Build.nsis_known_input_file_replacement_closure $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.nsis_compiler_input_pre_snapshot_exact $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.nsis_compiler_input_post_snapshot_exact $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.nsis_compiler_input_leases_held_during_makensis $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.active_same_sid_transient_tree_membership_interference_excluded $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.nsis_non_os_compiler_input_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.full_nsis_toolchain_input_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.unsigned_disabled_build $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.signing_hook_processes_executed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.installer_executed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.uninstaller_executed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.installed_product_processes_touched $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.product_registry_mutated $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.default_input_method_changed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.production_user_data_read_or_written $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Build.installed_yimecore_local12_touched $false)){
        throw 'Build result does not describe the same sealed, disabled and non-mutating candidate.'
    }
    foreach($pair in @(
        @($Build.makensis_sha256,'build-result makensis_sha256'),
        @($Build.nsis_toolchain_lock_sha256,'build-result nsis_toolchain_lock_sha256'),
        @($Build.nsis_compiler_input_tree_sha256,'build-result nsis_compiler_input_tree_sha256'))){
        Assert-RimePimeReceiptV2Hash $pair[0] $pair[1]
    }
    foreach($name in @('nsis_compiler_input_file_count','nsis_compiler_input_directory_count','nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count','nsis_toolchain_control_read_lease_count')){
        if(-not(Test-RimePimeStageInteger $Build.$name) -or [int]$Build.$name -lt 1){throw "Build result has an invalid $name."}
    }
    if([int]$Build.nsis_compiler_input_file_count -ne 303 -or
        [int]$Build.nsis_compiler_input_directory_count -ne 17 -or
        [int]$Build.nsis_compiler_input_read_lease_count -ne 303 -or
        [int]$Build.nsis_compiler_input_directory_lease_count -ne 19 -or
        [int]$Build.nsis_compiler_input_anchor_directory_lease_count -ne 2 -or
        [int]$Build.nsis_toolchain_control_read_lease_count -ne 2){
        throw 'Build result NSIS compiler-input lease counts do not close its exact sets.'
    }
}

function Assert-RimePimeReceiptV2PostbuildEvidence {
    param($Postbuild,$Build,$Manifest,$PayloadReceipt)
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild @(
        'schema_version','product','product_version','package_profile','architectures','package_plan_sha256','content_manifest_sha256',
        'content_tree_sha256','payload_nsh_receipt_sha256','payload_nsh_sha256','installer','generated_uninstaller','toolchain_lock',
        'seven_zip','seven_zip_parser_library','makensis','installer_archive','uninstaller_archive','installer_archive_listing_exact',
        'nested_uninstaller_archive_listing_exact','stable_extracted_snapshot_matches_expected_sources',
        'stable_extracted_stage_owned_files_match_sealed_manifest','installer_archive_per_entry_raw_stdout_verified',
        'nested_uninstaller_archive_per_entry_raw_stdout_verified','archive_content_origin_proven','package_plan_stage_bindings_verified',
        'archive_content_provenance_closed_against_active_same_sid_replacement',
        'active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance',
        'parent_created_per_entry_raw_stdout_snapshot','seven_zip_never_received_snapshot_output_paths',
        'payload_nsh_raw_byte_binding_verified','installer_read_lease_held_for_all_reads','uninstaller_read_lease_held_for_all_reads',
        'seven_zip_read_lease_held_for_all_calls','seven_zip_parser_library_read_lease_held_for_all_calls',
        'execution_logic_read_leases_held_through_seal','extraction_root_and_expected_directory_identity_leases_held_through_seal',
        'extracted_file_read_leases_held_through_seal','raw_generated_uninstaller_capture_read_lease_held_through_seal',
        'result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass',
        'text_logs_create_new_memory_digest_bound_and_leased_through_result_seal','verification_passes',
        'seven_zip_call_count','seven_zip_text_call_count','seven_zip_per_entry_raw_stdout_call_count',
        'nsis_toolchain_lock_sha256','nsis_compiler_input_scope','nsis_compiler_input_tree_sha256',
        'nsis_compiler_input_file_count','nsis_compiler_input_directory_count','nsis_compiler_input_read_lease_count',
        'nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
        'nsis_toolchain_control_read_lease_count','nsis_distribution_inputs_exact_and_read_leased_during_postbuild',
        'nsis_known_input_file_replacement_closure','active_same_sid_transient_tree_membership_interference_excluded',
        'nsis_compiler_input_leases_held_during_makensis','nsis_non_os_compiler_input_closure','full_nsis_toolchain_input_closure',
        'generated_uninstaller_present','generated_uninstaller_static_archive_member_verified','generated_uninstaller_verified',
        'generated_uninstaller_trusted','final_payload_closure','delivery_admitted','extractor_process_executed',
        'actual_installer_or_uninstaller_executed','product_process_started_or_stopped','registry_touched','default_input_method_changed',
        'production_user_data_read_or_written','installed_yimecore_local12_touched') 'receipt-v2 postbuild result'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.installer @(
        'sha256','bytes','signature_status','package_plan_raw_byte_binding','content_manifest_raw_byte_binding',
        'content_tree_raw_byte_binding','payload_nsh_raw_byte_binding','trusted') 'receipt-v2 postbuild installer'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.generated_uninstaller @(
        'sha256','bytes','signature_status','package_plan_raw_byte_binding','content_manifest_raw_byte_binding',
        'content_tree_raw_byte_binding','payload_nsh_raw_byte_binding','trusted') 'receipt-v2 postbuild generated uninstaller'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.toolchain_lock @('sha256','toolchain_id') 'receipt-v2 postbuild toolchain lock'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.seven_zip @('sha256','bytes') 'receipt-v2 postbuild 7-Zip'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.seven_zip_parser_library @('sha256','bytes','version','loaded_library_binding_verified') 'receipt-v2 postbuild parser library'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.makensis @('sha256','bytes') 'receipt-v2 postbuild makensis'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.installer_archive @('entry_count','raw_stdout_entry_count') 'receipt-v2 installer archive'
    Assert-RimePimeReceiptV2RequiredProperties $Postbuild.uninstaller_archive @('entry_count','raw_stdout_entry_count') 'receipt-v2 uninstaller archive'
    foreach($name in @(
        'nsis_compiler_input_file_count','nsis_compiler_input_directory_count','nsis_compiler_input_read_lease_count',
        'nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
        'nsis_toolchain_control_read_lease_count')){
        if(-not(Test-RimePimeStageInteger $Postbuild.$name) -or [int]$Postbuild.$name -lt 1){
            throw "Postbuild result has an invalid $name."
        }
    }
    if([string]$Postbuild.schema_version -cnotmatch '^yime-rime-pime-postbuild-extraction-v[1-9][0-9]*$' -or
        [string]$Postbuild.product -cne 'rime-pime' -or [string]$Postbuild.product_version -cne [string]$Build.product_version -or
        [string]$Postbuild.package_profile -cne 'x86-x64-v1' -or -not(Test-RimePimeReceiptV2OrderedArchitectures $Postbuild.architectures) -or
        [string]$Postbuild.package_plan_sha256 -cne [string]$Build.package_plan_sha256 -or
        [string]$Postbuild.content_manifest_sha256 -cne [string]$Build.content_manifest_sha256 -or
        [string]$Postbuild.content_tree_sha256 -cne [string]$Build.content_tree_sha256 -or
        [string]$Postbuild.payload_nsh_receipt_sha256 -cne [string]$PayloadReceipt.__sealed_digest -or
        [string]$Postbuild.payload_nsh_sha256 -cne [string]$Build.payload_nsh_sha256 -or
        [string]$Postbuild.installer.sha256 -cne [string]$Build.candidate_installer_sha256 -or
        [long]$Postbuild.installer.bytes -ne [long]$Build.candidate_installer_bytes -or
        [string]$Postbuild.installer.signature_status -cne 'NotSigned' -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer.package_plan_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer.content_manifest_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer.content_tree_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer.payload_nsh_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer.trusted $false) -or
        [string]$Postbuild.generated_uninstaller.signature_status -cne 'NotSigned' -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller.package_plan_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller.content_manifest_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller.content_tree_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller.payload_nsh_raw_byte_binding $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller.trusted $false) -or
        [string]$Postbuild.makensis.sha256 -cne [string]$Build.makensis_sha256 -or
        [string]$Postbuild.toolchain_lock.sha256 -cne [string]$Build.nsis_toolchain_lock_sha256 -or
        [string]$Postbuild.nsis_toolchain_lock_sha256 -cne [string]$Build.nsis_toolchain_lock_sha256 -or
        [string]$Postbuild.nsis_compiler_input_scope -cne [string]$Build.nsis_compiler_input_scope -or
        [string]$Postbuild.nsis_compiler_input_tree_sha256 -cne [string]$Build.nsis_compiler_input_tree_sha256 -or
        [int]$Postbuild.nsis_compiler_input_file_count -ne [int]$Build.nsis_compiler_input_file_count -or
        [int]$Postbuild.nsis_compiler_input_directory_count -ne [int]$Build.nsis_compiler_input_directory_count -or
        [int]$Postbuild.nsis_compiler_input_read_lease_count -ne [int]$Build.nsis_compiler_input_read_lease_count -or
        [int]$Postbuild.nsis_compiler_input_directory_lease_count -ne [int]$Build.nsis_compiler_input_directory_lease_count -or
        [int]$Postbuild.nsis_compiler_input_anchor_directory_lease_count -ne [int]$Build.nsis_compiler_input_anchor_directory_lease_count -or
        [int]$Postbuild.nsis_toolchain_control_read_lease_count -ne [int]$Build.nsis_toolchain_control_read_lease_count -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nsis_distribution_inputs_exact_and_read_leased_during_postbuild $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nsis_known_input_file_replacement_closure $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.active_same_sid_transient_tree_membership_interference_excluded $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nsis_compiler_input_leases_held_during_makensis $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nsis_non_os_compiler_input_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.full_nsis_toolchain_input_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer_archive_listing_exact $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nested_uninstaller_archive_listing_exact $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.stable_extracted_snapshot_matches_expected_sources $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.stable_extracted_stage_owned_files_match_sealed_manifest $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer_archive_per_entry_raw_stdout_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.nested_uninstaller_archive_per_entry_raw_stdout_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.archive_content_origin_proven $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.archive_content_provenance_closed_against_active_same_sid_replacement $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.parent_created_per_entry_raw_stdout_snapshot $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.seven_zip_never_received_snapshot_output_paths $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.package_plan_stage_bindings_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.payload_nsh_raw_byte_binding_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installer_read_lease_held_for_all_reads $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.uninstaller_read_lease_held_for_all_reads $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.seven_zip_read_lease_held_for_all_calls $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.seven_zip_parser_library_read_lease_held_for_all_calls $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.execution_logic_read_leases_held_through_seal $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.extraction_root_and_expected_directory_identity_leases_held_through_seal $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.extracted_file_read_leases_held_through_seal $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.raw_generated_uninstaller_capture_read_lease_held_through_seal $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.text_logs_create_new_memory_digest_bound_and_leased_through_result_seal $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.seven_zip_parser_library.loaded_library_binding_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller_present $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller_static_archive_member_verified $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller_verified $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.generated_uninstaller_trusted $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.final_payload_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.delivery_admitted $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.extractor_process_executed $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.actual_installer_or_uninstaller_executed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.product_process_started_or_stopped $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.registry_touched $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.default_input_method_changed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.production_user_data_read_or_written $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Postbuild.installed_yimecore_local12_touched $false)){
        throw 'Postbuild result does not close the same disabled candidate under the required static-only boundaries.'
    }
    foreach($pair in @(
        @($Postbuild.toolchain_lock.sha256,'postbuild toolchain lock'),
        @($Postbuild.seven_zip.sha256,'postbuild seven_zip'),
        @($Postbuild.seven_zip_parser_library.sha256,'postbuild seven_zip parser library'),
        @($Postbuild.makensis.sha256,'postbuild makensis'),
        @($Postbuild.generated_uninstaller.sha256,'postbuild generated uninstaller'))){
        Assert-RimePimeReceiptV2Hash $pair[0] $pair[1]
    }
    if([string]::IsNullOrWhiteSpace([string]$Postbuild.toolchain_lock.toolchain_id) -or
        [string]$Postbuild.toolchain_lock.toolchain_id -cnotmatch '^[A-Za-z0-9._+-]{1,128}$' -or
        [string]::IsNullOrWhiteSpace([string]$Postbuild.seven_zip_parser_library.version) -or
        -not(Test-RimePimeStageInteger $Postbuild.installer_archive.entry_count) -or
        [int]$Postbuild.installer_archive.entry_count -lt 1 -or
        [int]$Postbuild.installer_archive.raw_stdout_entry_count -ne [int]$Postbuild.installer_archive.entry_count -or
        -not(Test-RimePimeStageInteger $Postbuild.uninstaller_archive.entry_count) -or
        [int]$Postbuild.uninstaller_archive.entry_count -lt 1 -or
        [int]$Postbuild.uninstaller_archive.raw_stdout_entry_count -ne [int]$Postbuild.uninstaller_archive.entry_count -or
        -not(Test-RimePimeStageInteger $Postbuild.verification_passes) -or [int]$Postbuild.verification_passes -lt 2 -or
        -not(Test-RimePimeStageInteger $Postbuild.seven_zip_call_count) -or
        -not(Test-RimePimeStageInteger $Postbuild.seven_zip_text_call_count) -or
        -not(Test-RimePimeStageInteger $Postbuild.seven_zip_per_entry_raw_stdout_call_count) -or
        [int]$Postbuild.seven_zip_per_entry_raw_stdout_call_count -ne
            ([int]$Postbuild.installer_archive.entry_count+[int]$Postbuild.uninstaller_archive.entry_count) -or
        [int]$Postbuild.seven_zip_call_count -ne
            ([int]$Postbuild.seven_zip_text_call_count+[int]$Postbuild.seven_zip_per_entry_raw_stdout_call_count) -or
        -not(Test-RimePimeStageInteger $Postbuild.generated_uninstaller.bytes) -or [long]$Postbuild.generated_uninstaller.bytes -lt 65536){
        throw 'Postbuild toolchain or archive identity is incomplete.'
    }
}

function Write-RimePimeReceiptV2CreateNewSealedJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path);$sidecar=$full+'.sha256';$parent=Split-Path -Parent $full
    foreach($candidate in @($parent,$full,$sidecar)){Assert-RimePimeNoReparsePath $candidate}
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Receipt-v2 prepared parent must already exist.'}
    $text=(ConvertTo-RimePimeStageCanonicalJson $Value)+"`n";$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
    if($bytes.Length -gt 1048576){throw 'Receipt-v2 exceeds its 1 MiB bound.'}
    $digest=Get-RimePimeReceiptV2Sha256Bytes $bytes
    $json=$null;$marker=$null
    try{
        $json=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $json.Write($bytes,0,$bytes.Length);$json.Flush($true);$json.Dispose();$json=$null
        $markerBytes=[Text.Encoding]::ASCII.GetBytes("$digest  $([IO.Path]::GetFileName($full))`n")
        $marker=[IO.File]::Open($sidecar,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $marker.Write($markerBytes,0,$markerBytes.Length);$marker.Flush($true);$marker.Dispose();$marker=$null
        return Open-RimePimeReceiptV2SealedJsonLease $full 'prepared package receipt v2' -AllowDelete
    }catch{
        if($null -ne $marker){$marker.Dispose()};if($null -ne $json){$json.Dispose()};throw
    }
}

function New-RimePimePackageReceiptV2Preparation {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$BuildReceiptV1Path,
        [Parameter(Mandatory)][string]$BuildResultPath,
        [Parameter(Mandatory)][string]$ContentManifestPath,
        [Parameter(Mandatory)][string]$PayloadNshPath,
        [Parameter(Mandatory)][string]$PayloadNshReceiptPath,
        [Parameter(Mandatory)][string]$PostbuildResultPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\');$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
    $allowed=Join-Path $root '.tmp\dual-product'
    if((Split-Path -Parent $output) -ine $allowed -or (Split-Path -Leaf $output) -cnotmatch '^dp1-package-receipt-v2-[A-Za-z0-9-]+$' -or
        (Test-Path -LiteralPath $output)){
        throw 'Receipt-v2 OutputRoot must be a fresh immediate .tmp/dual-product/dp1-package-receipt-v2-* directory.'
    }
    Assert-RimePimeNoReparsePath $root;Assert-RimePimeNoReparsePath $allowed
    $jsonLeases=[Collections.Generic.List[object]]::new();$fileLeases=[Collections.Generic.List[object]]::new();$prepared=$null
    try{
        $v1=Open-RimePimeReceiptV2SealedJsonLease $BuildReceiptV1Path 'historical v1 build receipt' -AllowDelete;$jsonLeases.Add($v1)
        Assert-RimePimeReceiptV2Predecessor $v1.Value $root
        $planPath=Resolve-RimePimePackageFile $root ([string]$v1.Value.package_plan_path)
        $plan=Open-RimePimeReceiptV2SealedJsonLease $planPath 'sealed package plan';$jsonLeases.Add($plan)
        $build=Open-RimePimeReceiptV2SealedJsonLease $BuildResultPath 'sealed build result';$jsonLeases.Add($build)
        $manifest=Open-RimePimeReceiptV2SealedJsonLease $ContentManifestPath 'sealed copied-content manifest';$jsonLeases.Add($manifest)
        $payloadReceipt=Open-RimePimeReceiptV2SealedJsonLease $PayloadNshReceiptPath 'sealed payload include receipt';$jsonLeases.Add($payloadReceipt)
        $postbuild=Open-RimePimeReceiptV2SealedJsonLease $PostbuildResultPath 'sealed postbuild result';$jsonLeases.Add($postbuild)
        if($plan.Digest -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$plan.Value.schema_version -cne 'yime-rime-pime-package-plan-v1' -or
            [string]$plan.Value.product -cne 'rime-pime' -or
            -not(Test-RimePimeReceiptV2OrderedArchitectures $plan.Value.architectures)){
            throw 'Package plan does not match the historical v1 receipt identity.'
        }
        $payloadReceipt.Value|Add-Member -NotePropertyName __sealed_digest -NotePropertyValue $payloadReceipt.Digest
        if([string]$manifest.Value.schema_version -cne 'yime-rime-pime-copied-content-v1' -or
            [string]$payloadReceipt.Value.schema_version -cne 'yime-rime-pime-nsis-stage-include-v1' -or
            [string]$manifest.Value.package_plan_sha256 -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$payloadReceipt.Value.package_plan_sha256 -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$payloadReceipt.Value.payload_spec_sha256 -cne [string]$manifest.Value.payload_spec_sha256 -or
            [string]$payloadReceipt.Value.content_manifest_sha256 -cne $manifest.Digest -or
            [string]$payloadReceipt.Value.content_tree_sha256 -cne [string]$manifest.Value.content_tree_sha256 -or
            [bool]$manifest.Value.final_payload_closure -or [bool]$payloadReceipt.Value.final_payload_closure){
            throw 'Stage manifest and payload include receipt do not share one copied-input identity.'
        }
        Assert-RimePimeReceiptV2BuildEvidence $build.Value $v1.Value $manifest.Value $payloadReceipt.Value $postbuild.Value
        if([string]$build.Value.package_build_receipt_sha256 -cne $v1.Digest){throw 'Build result does not bind the supplied historical v1 receipt bytes.'}
        Assert-RimePimeReceiptV2PostbuildEvidence $postbuild.Value $build.Value $manifest.Value $payloadReceipt.Value
        $includePath=[IO.Path]::GetFullPath($PayloadNshPath)
        if((Split-Path -Parent $includePath) -ine (Split-Path -Parent $payloadReceipt.Path) -or
            [IO.Path]::GetFileName($includePath) -cne [string]$payloadReceipt.Value.include_file){throw 'Payload include path differs from its sealed receipt.'}
        $include=Open-RimePimeReceiptV2FileLease $includePath ([string]$payloadReceipt.Value.include_sha256) ([long]$payloadReceipt.Value.include_bytes) 'payload include';$fileLeases.Add($include)
        $includeSidecar=Open-RimePimeReceiptV2RawSidecarLease $includePath $include.Digest 'payload include';$fileLeases.Add($includeSidecar)
        $sourcePath=Resolve-RimePimePackageFile $root ([string]$v1.Value.installer_source_path)
        $sourceBytes=[long](Get-Item -LiteralPath $sourcePath).Length
        $source=Open-RimePimeReceiptV2FileLease $sourcePath ([string]$v1.Value.installer_source_sha256) $sourceBytes 'installer source';$fileLeases.Add($source)
        $installerPath=Resolve-RimePimePackageFile $root ([string]$v1.Value.installer_path)
        $installer=Open-RimePimeReceiptV2FileLease $installerPath ([string]$v1.Value.installer_sha256) ([long]$v1.Value.installer_size) 'canonical disabled installer';$fileLeases.Add($installer)
        foreach($path in @($build.Path,$manifest.Path,$payloadReceipt.Path,$postbuild.Path,$include.Path)){$null=ConvertTo-RimePimeReceiptV2RelativePath $root $path}
        $receipt=[pscustomobject][ordered]@{
            schema_version=$script:RimePimePackageReceiptV2Schema;product='rime-pime'
            closure_scope='sealed-stage-disabled-nsis-build-and-static-archive-evidence-not-release'
            receipt_state='canonical-static-closure-disabled';product_version=[string]$build.Value.product_version
            architectures=@('x86','x64');package_profile='x86-x64-v1'
            package_plan=[pscustomobject][ordered]@{path=[string]$v1.Value.package_plan_path;sha256=[string]$v1.Value.package_plan_sha256}
            sealed_stage=[pscustomobject][ordered]@{
                content_manifest_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $manifest.Path)
                content_manifest_sha256=$manifest.Digest;payload_spec_sha256=[string]$manifest.Value.payload_spec_sha256
                content_tree_sha256=[string]$manifest.Value.content_tree_sha256
                copied_file_count=[int]$build.Value.copied_file_count;payload_file_count=[int]$build.Value.payload_file_count
                bootstrap_file_count=[int]$build.Value.bootstrap_file_count
            }
            payload_include=[pscustomobject][ordered]@{
                path=(ConvertTo-RimePimeReceiptV2RelativePath $root $include.Path);sha256=$include.Digest;bytes=[long]$include.Bytes
                receipt_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $payloadReceipt.Path);receipt_sha256=$payloadReceipt.Digest
            }
            predecessor_v1=[pscustomobject][ordered]@{
                schema_version=$script:RimePimePackageReceiptV1Schema;source_path_at_finalization=(ConvertTo-RimePimeReceiptV2RelativePath $root $v1.Path)
                sha256=$v1.Digest;bytes=[long]$v1.Bytes;installer_sha256=[string]$v1.Value.installer_sha256
                installer_size=[long]$v1.Value.installer_size;package_plan_sha256=[string]$v1.Value.package_plan_sha256
            }
            disabled_build=[pscustomobject][ordered]@{
                result_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $build.Path);result_sha256=$build.Digest
                schema_version=[string]$build.Value.schema_version;makensis_sha256=[string]$build.Value.makensis_sha256
                nsis_toolchain_lock_sha256=[string]$build.Value.nsis_toolchain_lock_sha256
                nsis_compiler_input_scope=[string]$build.Value.nsis_compiler_input_scope
                nsis_compiler_input_tree_sha256=[string]$build.Value.nsis_compiler_input_tree_sha256
                nsis_compiler_input_file_count=[int]$build.Value.nsis_compiler_input_file_count
                nsis_compiler_input_directory_count=[int]$build.Value.nsis_compiler_input_directory_count
                nsis_compiler_input_read_lease_count=[int]$build.Value.nsis_compiler_input_read_lease_count
                nsis_compiler_input_directory_lease_count=[int]$build.Value.nsis_compiler_input_directory_lease_count
                nsis_compiler_input_anchor_directory_lease_count=[int]$build.Value.nsis_compiler_input_anchor_directory_lease_count
                nsis_toolchain_control_read_lease_count=[int]$build.Value.nsis_toolchain_control_read_lease_count
                nsis_compiler_input_pre_snapshot_exact=$true;nsis_compiler_input_post_snapshot_exact=$true
                nsis_compiler_input_leases_held_during_makensis=$true
                nsis_known_input_file_replacement_closure=$true
                active_same_sid_transient_tree_membership_interference_excluded=$false
                nsis_non_os_compiler_input_closure=$false
                full_nsis_toolchain_input_closure=[bool]$build.Value.full_nsis_toolchain_input_closure
                unsigned_disabled_build=$true;signing_hook_processes_executed=$false
            }
            static_postbuild=[pscustomobject][ordered]@{
                result_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $postbuild.Path);result_sha256=$postbuild.Digest
                schema_version=[string]$postbuild.Value.schema_version
                toolchain=[pscustomobject][ordered]@{
                    toolchain_id=[string]$postbuild.Value.toolchain_lock.toolchain_id
                    lock_sha256=[string]$postbuild.Value.toolchain_lock.sha256
                    makensis_sha256=[string]$postbuild.Value.makensis.sha256
                    seven_zip_sha256=[string]$postbuild.Value.seven_zip.sha256
                    seven_zip_parser_library_sha256=[string]$postbuild.Value.seven_zip_parser_library.sha256
                    seven_zip_parser_library_version=[string]$postbuild.Value.seven_zip_parser_library.version
                    nsis_compiler_input_scope=[string]$postbuild.Value.nsis_compiler_input_scope
                    nsis_compiler_input_tree_sha256=[string]$postbuild.Value.nsis_compiler_input_tree_sha256
                    nsis_compiler_input_file_count=[int]$postbuild.Value.nsis_compiler_input_file_count
                    nsis_compiler_input_directory_count=[int]$postbuild.Value.nsis_compiler_input_directory_count
                    nsis_compiler_input_read_lease_count=[int]$postbuild.Value.nsis_compiler_input_read_lease_count
                    nsis_compiler_input_directory_lease_count=[int]$postbuild.Value.nsis_compiler_input_directory_lease_count
                    nsis_compiler_input_anchor_directory_lease_count=[int]$postbuild.Value.nsis_compiler_input_anchor_directory_lease_count
                    nsis_toolchain_control_read_lease_count=[int]$postbuild.Value.nsis_toolchain_control_read_lease_count
                    inputs_exact_and_read_leased_during_postbuild=$true
                    known_input_file_replacement_closure=$true
                    active_same_sid_transient_tree_membership_interference_excluded=$false
                    compiler_input_leases_held_during_makensis=$false
                    non_os_compiler_input_closure=$false;full_toolchain_input_closure=$false
                }
                installer_archive_entry_count=[int]$postbuild.Value.installer_archive.entry_count
                nested_uninstaller_archive_entry_count=[int]$postbuild.Value.uninstaller_archive.entry_count
                generated_uninstaller_sha256=[string]$postbuild.Value.generated_uninstaller.sha256
                generated_uninstaller_bytes=[long]$postbuild.Value.generated_uninstaller.bytes
                archive_content_origin_proven=$true;actual_installer_or_uninstaller_executed=$false
            }
            installer=[pscustomobject][ordered]@{
                path=[string]$v1.Value.installer_path;sha256=$installer.Digest;bytes=[long]$installer.Bytes
                source_path=[string]$v1.Value.installer_source_path;source_sha256=$source.Digest
            }
            evidence_artifacts_embedded=$false;evidence_artifacts_durable=$false
            unsigned_disabled_build=$true;signing_complete=$false;generated_uninstaller_verified=$false
            generated_uninstaller_trusted=$false;final_payload_closure=$false;delivery_admitted=$false
            installer_executed=$false;uninstaller_executed=$false;installed_product_processes_touched=$false
            product_registry_mutated=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
            installed_yimecore_local12_touched=$false;sealed_at_utc=[DateTime]::UtcNow.ToString('o')
        }
        New-Item -ItemType Directory -Path $output|Out-Null
        $preparedRoot=Join-Path $output 'prepared';New-Item -ItemType Directory -Path $preparedRoot|Out-Null
        $preparedLease=Write-RimePimeReceiptV2CreateNewSealedJson $receipt (Join-Path $preparedRoot 'package-build-receipt.json')
        $jsonLeases.Add($preparedLease)
        $prepared=[pscustomobject]@{
            RepoRoot=$root;OutputRoot=$output;Receipt=$receipt;ReceiptPath=$preparedLease.Path;ReceiptSidecar=$preparedLease.Sidecar
            ReceiptDigest=$preparedLease.Digest;InstallerPath=$installer.Path;Predecessor=$v1;PreparedLease=$preparedLease
            InstallerLease=$installer;JsonLeases=$jsonLeases;FileLeases=$fileLeases
        }
        return $prepared
    }catch{
        if($null -eq $prepared){
            foreach($lease in @($fileLeases)){if($null -ne $lease.Stream){$lease.Stream.Dispose()}}
            foreach($lease in @($jsonLeases)){
                if($null -ne $lease.SidecarStream){$lease.SidecarStream.Dispose()}
                if($null -ne $lease.JsonStream){$lease.JsonStream.Dispose()}
            }
        }
        throw
    }
}

function Copy-RimePimeReceiptV2HistoricalPredecessor {
    param([Parameter(Mandatory)]$Prepared)
    $history=Join-Path $Prepared.OutputRoot 'historical';New-Item -ItemType Directory -Path $history|Out-Null
    $path=Join-Path $history 'package-build-receipt-v1.json';$sidecar=$path+'.sha256'
    $json=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[byte[]]$Prepared.Predecessor.JsonBytes;$json.Write($bytes,0,$bytes.Length);$json.Flush($true)}finally{$json.Dispose()}
    $marker=[Text.Encoding]::ASCII.GetBytes("$($Prepared.Predecessor.Digest)  $([IO.Path]::GetFileName($path))`n")
    $out=[IO.File]::Open($sidecar,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$out.Write($marker,0,$marker.Length);$out.Flush($true)}finally{$out.Dispose()}
    $check=Open-RimePimeReceiptV2SealedJsonLease $path 'historical v1 receipt copy'
    try{if($check.Digest -cne $Prepared.Predecessor.Digest){throw 'Historical v1 receipt copy differs.'}}
    finally{$check.SidecarStream.Dispose();$check.JsonStream.Dispose()}
    return $path
}

function Publish-RimePimePackageReceiptV2 {
    param(
        [Parameter(Mandatory)]$Prepared,
        [Parameter(Mandatory)][string]$CanonicalReceiptPath
    )
    $canonical=[IO.Path]::GetFullPath($CanonicalReceiptPath)
    $expected=Join-Path $Prepared.RepoRoot 'installer\package-build-receipt.json'
    if($canonical -ine $expected -or $Prepared.Predecessor.Path -ine $canonical){
        throw 'Receipt-v2 publication requires the current canonical v1 receipt as its predecessor.'
    }
    $null=Copy-RimePimeReceiptV2HistoricalPredecessor $Prepared
    $lock=Open-RimePimePublicationLock -InstallerPath $Prepared.InstallerPath -ReceiptPath $canonical
    $currentTarget=$null
    $recovery=Join-Path $Prepared.OutputRoot 'publication-recovery';$previous=Join-Path $recovery 'previous';$failed=Join-Path $recovery 'failed-new'
    New-Item -ItemType Directory -Path $previous,$failed|Out-Null
    $oldJson=Join-Path $previous 'package-build-receipt.json';$oldSidecar=$oldJson+'.sha256'
    $movedOldJson=$false;$movedOldSidecar=$false;$movedNewJson=$false;$movedNewSidecar=$false
    try{
        $currentTarget=Open-RimePimeReceiptV2SealedJsonLease $canonical 'current canonical v1 publication target' -AllowDelete
        if([string]$currentTarget.Value.schema_version -cne $script:RimePimePackageReceiptV1Schema -or
            [string]$currentTarget.Digest -cne [string]$Prepared.Predecessor.Digest){
            throw 'Canonical receipt no longer matches the sealed v1 predecessor; refusing receipt-v2 publication.'
        }
        if((Get-RimePimeReceiptV2Sha256Bytes (Read-RimePimeReceiptV2StreamBytes $Prepared.InstallerLease.Stream 536870912 'canonical installer')) -cne [string]$Prepared.Receipt.installer.sha256){
            throw 'Canonical installer changed before receipt-v2 publication.'
        }
        [IO.File]::Move($canonical+'.sha256',$oldSidecar);$movedOldSidecar=$true
        [IO.File]::Move($canonical,$oldJson);$movedOldJson=$true
        [IO.File]::Move($Prepared.ReceiptPath,$canonical);$movedNewJson=$true
        [IO.File]::Move($Prepared.ReceiptSidecar,$canonical+'.sha256');$movedNewSidecar=$true
        $read=Read-RimePimePackageBuildReceiptV2 -RepoRoot $Prepared.RepoRoot -ReceiptPath $canonical
        if([string]$read.Digest -cne [string]$Prepared.ReceiptDigest){throw 'Published receipt-v2 differs from its prepared identity.'}
        return $read
    }catch{
        $original=$_;$errors=[Collections.Generic.List[string]]::new()
        try{if($movedNewSidecar -and (Test-Path -LiteralPath ($canonical+'.sha256'))){[IO.File]::Move($canonical+'.sha256',(Join-Path $failed 'package-build-receipt.json.sha256'))}}catch{$errors.Add($_.Exception.Message)}
        try{if($movedNewJson -and (Test-Path -LiteralPath $canonical)){[IO.File]::Move($canonical,(Join-Path $failed 'package-build-receipt.json'))}}catch{$errors.Add($_.Exception.Message)}
        try{if($movedOldJson -and (Test-Path -LiteralPath $oldJson)){[IO.File]::Move($oldJson,$canonical)}}catch{$errors.Add($_.Exception.Message)}
        try{if($movedOldSidecar -and (Test-Path -LiteralPath $oldSidecar)){[IO.File]::Move($oldSidecar,$canonical+'.sha256')}}catch{$errors.Add($_.Exception.Message)}
        if($errors.Count){throw "Receipt-v2 publication failed and rollback was incomplete: $($errors -join '; '). Original: $($original.Exception.Message)"}
        throw $original
    }finally{
        if($null -ne $currentTarget){$currentTarget.SidecarStream.Dispose();$currentTarget.JsonStream.Dispose()}
        $lock.Stream.Dispose()
    }
}

function Read-RimePimePackageBuildReceiptV2 {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ReceiptPath
    )
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $lease=Open-RimePimeReceiptV2SealedJsonLease $ReceiptPath 'package build receipt v2'
    try{
        $r=$lease.Value
        Assert-RimePimeExactProperties $r @(
            'schema_version','product','closure_scope','receipt_state','product_version','architectures','package_profile','package_plan',
            'sealed_stage','payload_include','predecessor_v1','disabled_build','static_postbuild','installer',
            'evidence_artifacts_embedded','evidence_artifacts_durable','unsigned_disabled_build','signing_complete',
            'generated_uninstaller_verified','generated_uninstaller_trusted','final_payload_closure','delivery_admitted',
            'installer_executed','uninstaller_executed','installed_product_processes_touched','product_registry_mutated',
            'default_input_method_changed','production_user_data_read_or_written','installed_yimecore_local12_touched','sealed_at_utc') 'package build receipt v2'
        Assert-RimePimeExactProperties $r.package_plan @('path','sha256') 'receipt-v2 package plan'
        Assert-RimePimeExactProperties $r.sealed_stage @('content_manifest_path','content_manifest_sha256','payload_spec_sha256','content_tree_sha256','copied_file_count','payload_file_count','bootstrap_file_count') 'receipt-v2 stage'
        Assert-RimePimeExactProperties $r.payload_include @('path','sha256','bytes','receipt_path','receipt_sha256') 'receipt-v2 payload include'
        Assert-RimePimeExactProperties $r.predecessor_v1 @('schema_version','source_path_at_finalization','sha256','bytes','installer_sha256','installer_size','package_plan_sha256') 'receipt-v2 predecessor identity'
        Assert-RimePimeExactProperties $r.disabled_build @(
            'result_path','result_sha256','schema_version','makensis_sha256','nsis_toolchain_lock_sha256','nsis_compiler_input_scope',
            'nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
            'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
            'nsis_toolchain_control_read_lease_count','nsis_known_input_file_replacement_closure',
            'nsis_compiler_input_pre_snapshot_exact','nsis_compiler_input_post_snapshot_exact',
            'nsis_compiler_input_leases_held_during_makensis',
            'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
            'full_nsis_toolchain_input_closure','unsigned_disabled_build','signing_hook_processes_executed') 'receipt-v2 disabled build'
        Assert-RimePimeExactProperties $r.static_postbuild @('result_path','result_sha256','schema_version','toolchain','installer_archive_entry_count','nested_uninstaller_archive_entry_count','generated_uninstaller_sha256','generated_uninstaller_bytes','archive_content_origin_proven','actual_installer_or_uninstaller_executed') 'receipt-v2 static postbuild'
        Assert-RimePimeExactProperties $r.static_postbuild.toolchain @(
            'toolchain_id','lock_sha256','makensis_sha256','seven_zip_sha256','seven_zip_parser_library_sha256','seven_zip_parser_library_version',
            'nsis_compiler_input_scope','nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
            'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
            'nsis_toolchain_control_read_lease_count','inputs_exact_and_read_leased_during_postbuild','known_input_file_replacement_closure',
            'active_same_sid_transient_tree_membership_interference_excluded','compiler_input_leases_held_during_makensis',
            'non_os_compiler_input_closure','full_toolchain_input_closure') 'receipt-v2 toolchain'
        Assert-RimePimeExactProperties $r.installer @('path','sha256','bytes','source_path','source_sha256') 'receipt-v2 installer'
        if([string]$r.schema_version -cne $script:RimePimePackageReceiptV2Schema -or [string]$r.product -cne 'rime-pime' -or
            [string]$r.closure_scope -cne 'sealed-stage-disabled-nsis-build-and-static-archive-evidence-not-release' -or
            [string]$r.receipt_state -cne 'canonical-static-closure-disabled' -or
            [string]::IsNullOrWhiteSpace([string]$r.product_version) -or
            [string]$r.product_version -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$' -or
            -not(Test-RimePimeReceiptV2OrderedArchitectures $r.architectures) -or [string]$r.package_profile -cne 'x86-x64-v1' -or
            [string]$r.predecessor_v1.schema_version -cne $script:RimePimePackageReceiptV1Schema -or
            [string]$r.predecessor_v1.installer_sha256 -cne [string]$r.installer.sha256 -or
            [long]$r.predecessor_v1.installer_size -ne [long]$r.installer.bytes -or
            [string]$r.predecessor_v1.package_plan_sha256 -cne [string]$r.package_plan.sha256 -or
            [string]$r.disabled_build.makensis_sha256 -cne [string]$r.static_postbuild.toolchain.makensis_sha256 -or
            [string]$r.disabled_build.nsis_toolchain_lock_sha256 -cne [string]$r.static_postbuild.toolchain.lock_sha256 -or
            [string]$r.disabled_build.nsis_compiler_input_scope -cne [string]$r.static_postbuild.toolchain.nsis_compiler_input_scope -or
            [string]$r.disabled_build.nsis_compiler_input_tree_sha256 -cne [string]$r.static_postbuild.toolchain.nsis_compiler_input_tree_sha256 -or
            [string]$r.disabled_build.schema_version -cnotmatch '^yime-rime-pime-staged-nsis-build-result-v[1-9][0-9]*$' -or
            [string]$r.static_postbuild.schema_version -cnotmatch '^yime-rime-pime-postbuild-extraction-v[1-9][0-9]*$' -or
            [string]::IsNullOrWhiteSpace([string]$r.static_postbuild.toolchain.toolchain_id) -or
            [string]$r.static_postbuild.toolchain.toolchain_id -cnotmatch '^[A-Za-z0-9._+-]{1,128}$' -or
            [string]$r.disabled_build.nsis_compiler_input_scope -cne 'repository-pinned-nsis-distribution-non-os-v1' -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.nsis_known_input_file_replacement_closure $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.nsis_compiler_input_pre_snapshot_exact $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.nsis_compiler_input_post_snapshot_exact $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.nsis_compiler_input_leases_held_during_makensis $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.active_same_sid_transient_tree_membership_interference_excluded $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.nsis_non_os_compiler_input_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.full_nsis_toolchain_input_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.inputs_exact_and_read_leased_during_postbuild $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.known_input_file_replacement_closure $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.active_same_sid_transient_tree_membership_interference_excluded $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.compiler_input_leases_held_during_makensis $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.non_os_compiler_input_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.toolchain.full_toolchain_input_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.unsigned_disabled_build $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.disabled_build.signing_hook_processes_executed $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.evidence_artifacts_embedded $false) -or
            $r.evidence_artifacts_durable -isnot [bool] -or
            -not(Test-RimePimeReceiptV2Boolean $r.unsigned_disabled_build $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.signing_complete $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.generated_uninstaller_verified $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.generated_uninstaller_trusted $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.final_payload_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.delivery_admitted $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.installer_executed $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.uninstaller_executed $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.installed_product_processes_touched $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.product_registry_mutated $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.default_input_method_changed $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.production_user_data_read_or_written $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.installed_yimecore_local12_touched $false) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.archive_content_origin_proven $true) -or
            -not(Test-RimePimeReceiptV2Boolean $r.static_postbuild.actual_installer_or_uninstaller_executed $false) -or
            -not(Test-RimePimeUtcTimestamp $r.sealed_at_utc)){
            throw 'Package receipt-v2 identity or fail-closed boundary is invalid.'
        }
        foreach($value in @(
            $r.package_plan.sha256,$r.sealed_stage.content_manifest_sha256,$r.sealed_stage.payload_spec_sha256,$r.sealed_stage.content_tree_sha256,
            $r.payload_include.sha256,$r.payload_include.receipt_sha256,$r.predecessor_v1.sha256,$r.disabled_build.result_sha256,
            $r.disabled_build.makensis_sha256,$r.disabled_build.nsis_toolchain_lock_sha256,$r.disabled_build.nsis_compiler_input_tree_sha256,
            $r.static_postbuild.result_sha256,$r.static_postbuild.toolchain.lock_sha256,
            $r.static_postbuild.toolchain.nsis_compiler_input_tree_sha256,
            $r.static_postbuild.toolchain.seven_zip_sha256,$r.static_postbuild.toolchain.seven_zip_parser_library_sha256,
            $r.static_postbuild.generated_uninstaller_sha256,$r.installer.sha256,$r.installer.source_sha256)){
            Assert-RimePimeReceiptV2Hash $value 'receipt-v2 bound digest'
        }
        foreach($path in @($r.package_plan.path,$r.sealed_stage.content_manifest_path,$r.payload_include.path,$r.payload_include.receipt_path,
            $r.predecessor_v1.source_path_at_finalization,$r.disabled_build.result_path,$r.static_postbuild.result_path,$r.installer.path,$r.installer.source_path)){
            $null=ConvertTo-RimePimePackagePath ([string]$path)
        }
        foreach($count in @(
            $r.sealed_stage.copied_file_count,$r.sealed_stage.payload_file_count,$r.sealed_stage.bootstrap_file_count,
            $r.payload_include.bytes,$r.predecessor_v1.bytes,$r.predecessor_v1.installer_size,
            $r.disabled_build.nsis_compiler_input_file_count,$r.disabled_build.nsis_compiler_input_directory_count,
             $r.disabled_build.nsis_compiler_input_read_lease_count,$r.disabled_build.nsis_compiler_input_directory_lease_count,
             $r.disabled_build.nsis_compiler_input_anchor_directory_lease_count,$r.disabled_build.nsis_toolchain_control_read_lease_count,
             $r.static_postbuild.toolchain.nsis_compiler_input_file_count,$r.static_postbuild.toolchain.nsis_compiler_input_directory_count,
             $r.static_postbuild.toolchain.nsis_compiler_input_read_lease_count,$r.static_postbuild.toolchain.nsis_compiler_input_directory_lease_count,
             $r.static_postbuild.toolchain.nsis_compiler_input_anchor_directory_lease_count,$r.static_postbuild.toolchain.nsis_toolchain_control_read_lease_count,
             $r.static_postbuild.installer_archive_entry_count,$r.static_postbuild.nested_uninstaller_archive_entry_count,
            $r.static_postbuild.generated_uninstaller_bytes,$r.installer.bytes)){
            if(-not(Test-RimePimeStageInteger $count) -or [long]$count -lt 1){throw 'Receipt-v2 contains an invalid bound byte or count value.'}
        }
        if([int]$r.disabled_build.nsis_compiler_input_file_count -ne 303 -or
            [int]$r.disabled_build.nsis_compiler_input_directory_count -ne 17 -or
            [int]$r.disabled_build.nsis_compiler_input_read_lease_count -ne 303 -or
            [int]$r.disabled_build.nsis_compiler_input_directory_lease_count -ne 19 -or
            [int]$r.disabled_build.nsis_compiler_input_anchor_directory_lease_count -ne 2 -or
            [int]$r.disabled_build.nsis_toolchain_control_read_lease_count -ne 2){
            throw 'Receipt-v2 NSIS compiler-input lease counts are not closed.'
        }
        if([int]$r.static_postbuild.toolchain.nsis_compiler_input_file_count -ne 303 -or
            [int]$r.static_postbuild.toolchain.nsis_compiler_input_directory_count -ne 17 -or
            [int]$r.static_postbuild.toolchain.nsis_compiler_input_read_lease_count -ne 303 -or
            [int]$r.static_postbuild.toolchain.nsis_compiler_input_directory_lease_count -ne 19 -or
            [int]$r.static_postbuild.toolchain.nsis_compiler_input_anchor_directory_lease_count -ne 2 -or
            [int]$r.static_postbuild.toolchain.nsis_toolchain_control_read_lease_count -ne 2){
            throw 'Receipt-v2 postbuild NSIS input counts are not the sealed exact set.'
        }
        $evidencePairs=@(
            [pscustomobject]@{Path=$r.package_plan.path;Digest=$r.package_plan.sha256;Context='receipt-v2 package plan'},
            [pscustomobject]@{Path=$r.sealed_stage.content_manifest_path;Digest=$r.sealed_stage.content_manifest_sha256;Context='receipt-v2 stage manifest'},
            [pscustomobject]@{Path=$r.payload_include.receipt_path;Digest=$r.payload_include.receipt_sha256;Context='receipt-v2 payload receipt'},
            [pscustomobject]@{Path=$r.disabled_build.result_path;Digest=$r.disabled_build.result_sha256;Context='receipt-v2 build result'},
            [pscustomobject]@{Path=$r.static_postbuild.result_path;Digest=$r.static_postbuild.result_sha256;Context='receipt-v2 postbuild result'}
        )
        $evidence=@{}
        foreach($item in $evidencePairs){
            $path=Resolve-RimePimeReceiptEvidence $root $r ([string]$item.Path) ([string]$item.Digest)
            $bound=Open-RimePimeReceiptV2SealedJsonLease $path ([string]$item.Context)
            try{
                if($bound.Digest -cne [string]$item.Digest){throw "$($item.Context) differs from the canonical receipt."}
                $evidence[$item.Context]=$bound.Value
            }
            finally{$bound.SidecarStream.Dispose();$bound.JsonStream.Dispose()}
        }
        if ($r.evidence_artifacts_durable) {
            $predecessorPath=Get-RimePimeReceiptObjectPath $root $r.predecessor_v1.sha256
            $null=Get-YimePimePayloadFileRecord $predecessorPath
            $predecessor=Open-RimePimeReceiptV2SealedJsonLease $predecessorPath 'retained v1 predecessor'
            try {
                if ($predecessor.Digest -cne $r.predecessor_v1.sha256 -or $predecessor.Bytes -ne $r.predecessor_v1.bytes -or
                    $predecessor.Value.schema_version -cne $script:RimePimePackageReceiptV1Schema) { throw 'Retained predecessor identity differs.' }
                Assert-RimePimeReceiptV2Predecessor $predecessor.Value $root
                foreach ($pair in @(@('installer_sha256',$r.installer.sha256),@('installer_size',$r.installer.bytes),
                    @('installer_source_sha256',$r.installer.source_sha256),@('package_plan_sha256',$r.package_plan.sha256),
                    @('installer_path',$r.installer.path),@('installer_source_path',$r.installer.source_path),@('package_plan_path',$r.package_plan.path))) {
                    if ([string]$predecessor.Value.($pair[0]) -cne [string]$pair[1]) { throw 'Retained predecessor contradicts receipt identity.' }
                }
            } finally { $predecessor.SidecarStream.Dispose();$predecessor.JsonStream.Dispose() }
        }
        # Digest binding alone does not validate what the bound evidence says.
        $plan=$evidence['receipt-v2 package plan'];$manifest=$evidence['receipt-v2 stage manifest']
        $payload=$evidence['receipt-v2 payload receipt'];$build=$evidence['receipt-v2 build result'];$post=$evidence['receipt-v2 postbuild result']
        if ($plan.schema_version -cne 'yime-rime-pime-package-plan-v1' -or $plan.product -cne 'rime-pime' -or
            -not(Test-RimePimeReceiptV2OrderedArchitectures $plan.architectures) -or
            $manifest.schema_version -cne 'yime-rime-pime-copied-content-v1' -or
            $payload.schema_version -cne 'yime-rime-pime-nsis-stage-include-v1' -or
            $manifest.package_plan_sha256 -cne $r.package_plan.sha256 -or $payload.package_plan_sha256 -cne $r.package_plan.sha256 -or
            $manifest.payload_spec_sha256 -cne $r.sealed_stage.payload_spec_sha256 -or $payload.payload_spec_sha256 -cne $manifest.payload_spec_sha256 -or
            $manifest.content_tree_sha256 -cne $r.sealed_stage.content_tree_sha256 -or $payload.content_tree_sha256 -cne $manifest.content_tree_sha256 -or
            $payload.content_manifest_sha256 -cne $r.sealed_stage.content_manifest_sha256 -or
            $payload.include_sha256 -cne $r.payload_include.sha256 -or $payload.include_bytes -ne $r.payload_include.bytes -or
            -not(Test-RimePimeReceiptV2Boolean $manifest.final_payload_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $payload.final_payload_closure $false) -or
            $build.product_version -cne $r.product_version -or $build.package_build_receipt_sha256 -cne $r.predecessor_v1.sha256 -or
            $build.content_manifest_sha256 -cne $r.sealed_stage.content_manifest_sha256) { throw 'Receipt evidence contradicts its sealed identity.' }
        $payload|Add-Member -NotePropertyName __sealed_digest -NotePropertyValue $r.payload_include.receipt_sha256
        $v1Identity=[pscustomobject]@{installer_sha256=$r.installer.sha256;installer_size=$r.installer.bytes}
        Assert-RimePimeReceiptV2BuildEvidence $build $v1Identity $manifest $payload $post
        Assert-RimePimeReceiptV2PostbuildEvidence $post $build $manifest $payload
        foreach ($property in $r.disabled_build.PSObject.Properties) {
            if ($property.Name -in @('result_path','result_sha256')) { continue }
            if ([string]$property.Value -cne [string]$build.($property.Name)) { throw 'Receipt build summary contradicts bound evidence.' }
        }
        foreach ($name in @('copied_file_count','payload_file_count','bootstrap_file_count')) {
            if ($r.sealed_stage.$name -ne $build.$name) { throw 'Receipt stage counts contradict bound evidence.' }
        }
        foreach ($pair in @(@($r.static_postbuild.schema_version,$post.schema_version),
            @($r.static_postbuild.generated_uninstaller_sha256,$post.generated_uninstaller.sha256),
            @($r.static_postbuild.generated_uninstaller_bytes,$post.generated_uninstaller.bytes),
            @($r.static_postbuild.installer_archive_entry_count,$post.installer_archive.entry_count),
            @($r.static_postbuild.nested_uninstaller_archive_entry_count,$post.uninstaller_archive.entry_count),
            @($r.static_postbuild.toolchain.toolchain_id,$post.toolchain_lock.toolchain_id),
            @($r.static_postbuild.toolchain.seven_zip_sha256,$post.seven_zip.sha256),
            @($r.static_postbuild.toolchain.seven_zip_parser_library_sha256,$post.seven_zip_parser_library.sha256),
            @($r.static_postbuild.toolchain.seven_zip_parser_library_version,$post.seven_zip_parser_library.version))) {
            if ([string]$pair[0] -cne [string]$pair[1]) { throw 'Receipt postbuild summary contradicts bound evidence.' }
        }
        $includePath=Resolve-RimePimeReceiptEvidence $root $r ([string]$r.payload_include.path) ([string]$r.payload_include.sha256)
        $include=Open-RimePimeReceiptV2FileLease $includePath ([string]$r.payload_include.sha256) ([long]$r.payload_include.bytes) 'receipt-v2 payload include'
        try{
            $marker=Open-RimePimeReceiptV2RawSidecarLease $includePath ([string]$r.payload_include.sha256) 'receipt-v2 payload include'
            try{}finally{$marker.Stream.Dispose()}
        }finally{$include.Stream.Dispose()}
        $sourcePath=Resolve-RimePimeReceiptEvidence $root $r ([string]$r.installer.source_path) ([string]$r.installer.source_sha256)
        $sourceBytes=[long](Get-Item -LiteralPath $sourcePath).Length
        $source=Open-RimePimeReceiptV2FileLease $sourcePath ([string]$r.installer.source_sha256) $sourceBytes 'receipt-v2 installer source'
        $source.Stream.Dispose()
        $installerPath=Resolve-RimePimeReceiptEvidence $root $r ([string]$r.installer.path) ([string]$r.installer.sha256)
        $candidate=Open-RimePimeReceiptV2FileLease $installerPath ([string]$r.installer.sha256) ([long]$r.installer.bytes) 'receipt-v2 canonical installer'
        try{return [pscustomobject]@{Receipt=$r;Digest=$lease.Digest;Path=$lease.Path;Sidecar=$lease.Sidecar;InstallerPath=$installerPath}}
        finally{$candidate.Stream.Dispose()}
    }finally{$lease.SidecarStream.Dispose();$lease.JsonStream.Dispose()}
}
