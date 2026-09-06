# Definitions-only canonical receipt-v2 closure for one disabled Rime/PIME
# candidate.  This file never starts makensis, 7-Zip, an installer, an
# uninstaller, a signing host, or an installed product process.

$script:RimePimePackageReceiptV2Schema='yime-rime-pime-package-build-receipt-v2'
$script:RimePimePackageReceiptV1Schema='yime-rime-pime-package-build-receipt-v1'
$script:RimePimeLegacyBuildEvidenceSchema='yime-rime-pime-staged-nsis-build-result-v2'
# Deliberately does not end in "result-vN".  Earlier validators admitted every
# future numeric version without understanding its fields; the tagged name
# makes those validators fail closed instead of silently discarding DP1-K.
$script:RimePimeCurrentBuildEvidenceSchema='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
$script:RimePimeCompilerMembershipIntervalSchema='yime-rime-pime-nsis-compiler-membership-interval-v1'
$script:RimePimeCurrentBuildExclusiveProperties=@(
    'nsis_compiler_membership_interval','nsis_compiler_stage_path',
    'nsis_compiler_stage_file_lease_count','nsis_compiler_stage_directory_lease_count'
)
$script:RimePimeCurrentBuildEvidenceProperties=@(
    'schema_version','product','product_version','package_profile','architectures','package_plan_sha256',
    'payload_spec_sha256','content_manifest_sha256','content_tree_sha256','payload_nsh_sha256','copied_file_count',
    'payload_file_count','bootstrap_file_count','main_payload_file_count','package_plan_artifact_count',
    'package_plan_matching_stage_binding_count','staged_pe_unique_artifact_count','staged_pe_path_binding_count',
    'staged_pe_architecture_verified_under_read_leases','executed_build_logic_source_count',
    'executed_build_logic_sources','build_logic_read_lease_count','prebuild_leased_input_count','candidate_leased',
    'lease_share_mode','repository_local_compiler_inputs_leased','repository_local_bare_include_shadowing_closed',
    'makensis_no_current_directory_change','makensis_user_config_disabled','compiler_working_directory',
    'nsis_compiler_membership_interval','nsis_compiler_stage_path','nsis_compiler_stage_file_lease_count',
    'nsis_compiler_stage_directory_lease_count','nsis_toolchain_lock_sha256','nsis_compiler_input_scope',
    'nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
    'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count',
    'nsis_compiler_input_anchor_directory_lease_count','nsis_toolchain_control_read_lease_count',
    'nsis_distribution_tree_exact_at_open_and_test','nsis_known_input_file_replacement_closure',
    'nsis_compiler_input_pre_snapshot_exact','nsis_compiler_input_post_snapshot_exact',
    'nsis_compiler_input_leases_held_during_makensis','active_same_sid_transient_tree_membership_interference_excluded',
    'nsis_non_os_compiler_input_closure','full_nsis_toolchain_input_closure','makensis_path','makensis_sha256',
    'makensis_path_lease_verified','unsigned_disabled_build','signing_hook_processes_executed',
    'signing_host_and_release_signing_pending','path_searched_signing_host_not_executed','candidate_installer_path',
    'candidate_installer_sha256','candidate_installer_bytes','published_installer_path','package_build_receipt_path',
    'package_build_receipt_sha256','publication_status_at_evidence_seal','publication_commit_marker_path',
    'publication_failure_rollback_enabled','publication_cross_process_lock','publication_lock_path',
    'prebuild_stage_verified','postbuild_stage_verified','prebuild_include_verified','postbuild_include_verified',
    'installer_raw_byte_search_found_expected_digests','postbuild_extraction_compared_to_stage',
    'canonical_receipt_binds_stage_evidence','canonical_receipt_v2_finalization_required',
    'canonical_receipt_v2_finalizer_automatically_invoked','canonical_receipt_v2_requires_sealed_postbuild_result',
    'v1_receipt_semantics_preserved_until_explicit_v2_finalization','generated_uninstaller_verified',
    'final_payload_closure','installer_executed','uninstaller_executed','build_tool_processes_executed',
    'makensis_executed','installed_product_processes_touched','product_registry_mutated','default_input_method_changed',
    'production_user_data_read_or_written','installed_yimecore_local12_touched'
)
$script:RimePimeCurrentBuildLogicSources=@(
    'tools/build-rime-pime-installer.ps1',
    'tools/dual-product/rime-pime-package-staging.psm1',
    'tools/dual-product/rime-pime-package-staging.ps1',
    'tools/dual-product/rime-pime-package-plan.ps1',
    'tools/dual-product/rime-pime-payload-closure.ps1',
    'tools/verify-pe-architectures.ps1',
    'tools/dual-product/rime-pime-nsis-stage.psm1',
    'tools/dual-product/rime-pime-nsis-stage.ps1',
    'tools/dual-product/rime-pime-staged-installer-build.psm1',
    'tools/dual-product/rime-pime-staged-installer-build.ps1',
    'tools/dual-product/rime-pime-nsis-toolchain-closure.psm1',
    'tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1',
    'tools/dual-product/rime-pime-nsis-compiler-interval.ps1',
    'tools/dual-product/rime-pime-nsis-toolchain-closure.ps1',
    'tools/dual-product/rime-pime-postbuild-toolchain-lock.json',
    'tools/dual-product/rime-pime-postbuild-toolchain-lock.json.sha256'
) | Sort-Object

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

function Assert-RimePimeReceiptV2LeasedIncludeDocument {
    param(
        [Parameter(Mandatory)]$IncludeLease,
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Context
    )
    $actual=[byte[]](Read-RimePimeReceiptV2StreamBytes $IncludeLease.Stream 4194304 $Context)
    $expected=[Text.Encoding]::ASCII.GetBytes([string]$Document.Text)
    if($actual.Length -ne $expected.Length){throw "$Context differs from the deterministic manifest-derived include."}
    for($i=0;$i -lt $actual.Length;$i++){
        if($actual[$i] -ne $expected[$i]){throw "$Context differs from the deterministic manifest-derived include."}
    }
}

function Assert-RimePimeReceiptV2ToolchainLockLease {
    param([Parameter(Mandatory)]$Lease)
    $strictUtf8=[Text.UTF8Encoding]::new($false,$true)
    try{$raw=$strictUtf8.GetString([byte[]]$Lease.JsonBytes)}
    catch{throw "Current NSIS toolchain lock is not strict UTF-8: $($_.Exception.Message)"}
    $canonical=(ConvertTo-RimePimeStageCanonicalJson $Lease.Value)+"`n"
    if($raw -cne $canonical){throw 'Current NSIS toolchain lock is not canonical single-line JSON.'}
    $null=Test-RimePimeNsisCompilerToolchainLockDocument $Lease.Value
}

function Assert-RimePimeReceiptV2InstallerRawBindings {
    param(
        [Parameter(Mandatory)]$InstallerLease,
        [Parameter(Mandatory)]$PackagePlanDigest,
        [Parameter(Mandatory)]$ContentManifestDigest,
        [Parameter(Mandatory)]$ContentTreeDigest,
        [Parameter(Mandatory)]$PayloadIncludeDigest
    )
    $bytes=[byte[]](Read-RimePimeReceiptV2StreamBytes $InstallerLease.Stream 536870912 'disabled installer raw bindings')
    $latin1=[Text.Encoding]::GetEncoding(28591);$haystack=$latin1.GetString($bytes)
    foreach($pair in @(
        @('package plan',$PackagePlanDigest),@('content manifest',$ContentManifestDigest),
        @('content tree',$ContentTreeDigest),@('payload include',$PayloadIncludeDigest))){
        Assert-RimePimeReceiptV2Hash $pair[1] "disabled installer $($pair[0]) binding"
        $needle=$latin1.GetString([Text.Encoding]::Unicode.GetBytes([string]$pair[1]))
        if($haystack.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){
            throw "Disabled installer lacks its sealed $($pair[0]) raw-byte binding."
        }
    }
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
    return $Value -is [Array] -and $items.Count -eq 2 -and
        $items[0] -is [string] -and $items[1] -is [string] -and
        [string]$items[0] -ceq 'x86' -and [string]$items[1] -ceq 'x64'
}

function Assert-RimePimeReceiptV2Hash {
    param($Value,[string]$Context)
    if($Value -isnot [string] -or [string]$Value -cnotmatch '^[0-9a-f]{64}$'){
        throw "$Context is not a lowercase SHA-256 digest."
    }
}

function Assert-RimePimeReceiptV2StringFields {
    param($Value,[string[]]$Names,[string]$Context)
    foreach($name in $Names){
        if($Value.$name -isnot [string]){throw "$Context $name must be a JSON string."}
    }
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

function Test-RimePimeReceiptV2BuildEvidenceSchema {
    param($Value)
    return $Value -is [string] -and
        ($Value -ceq $script:RimePimeLegacyBuildEvidenceSchema -or
         $Value -ceq $script:RimePimeCurrentBuildEvidenceSchema)
}

function Assert-RimePimeReceiptV2CompilerMembershipInterval {
    param($Interval)
    Assert-RimePimeExactProperties $Interval @(
        'schema_version','armed_before_baseline','completion_barrier_after_compiler_exit',
        'unexpected_membership_event_count','notification_batch_count','physical_membership_prevention_claimed',
        'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
        'full_nsis_toolchain_input_closure'
    ) 'receipt-v2 compiler membership interval'
    if($Interval.schema_version -isnot [string] -or
        [string]$Interval.schema_version -cne $script:RimePimeCompilerMembershipIntervalSchema -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.armed_before_baseline $true) -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.completion_barrier_after_compiler_exit $true) -or
        -not(Test-RimePimeStageInteger $Interval.unexpected_membership_event_count) -or
        [long]$Interval.unexpected_membership_event_count -ne 0 -or
        -not(Test-RimePimeStageInteger $Interval.notification_batch_count) -or
        [long]$Interval.notification_batch_count -lt 1 -or
        [long]$Interval.notification_batch_count -gt [int]::MaxValue -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.physical_membership_prevention_claimed $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.active_same_sid_transient_tree_membership_interference_excluded $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.nsis_non_os_compiler_input_closure $false) -or
        -not(Test-RimePimeReceiptV2Boolean $Interval.full_nsis_toolchain_input_closure $false)){
        throw 'Current membership-interval build evidence has an invalid compiler interval.'
    }
}

function Assert-RimePimeReceiptV2CurrentBuildLogicSources {
    param($Build)
    $sources=@($Build.executed_build_logic_sources)
    if($Build.executed_build_logic_sources -isnot [Array] -or
        $sources.Count -ne $script:RimePimeCurrentBuildLogicSources.Count -or
        [int]$Build.executed_build_logic_source_count -ne $script:RimePimeCurrentBuildLogicSources.Count -or
        [int]$Build.build_logic_read_lease_count -ne $script:RimePimeCurrentBuildLogicSources.Count){
        throw 'Current membership-interval build evidence has an incomplete build-logic source closure.'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for($i=0;$i -lt $sources.Count;$i++){
        $row=$sources[$i]
        Assert-RimePimeExactProperties $row @('path','sha256') 'receipt-v2 current build-logic source'
        if($row.path -isnot [string] -or -not $seen.Add([string]$row.path)){
            throw 'Current membership-interval build evidence has a duplicate or non-string build-logic source.'
        }
        $path=ConvertTo-RimePimePackagePath ([string]$row.path)
        if($path -cne [string]$script:RimePimeCurrentBuildLogicSources[$i]){
            throw 'Current membership-interval build evidence has an unexpected or unordered build-logic source.'
        }
        Assert-RimePimeReceiptV2Hash $row.sha256 'receipt-v2 current build-logic source sha256'
    }
}

function Assert-RimePimeReceiptV2CurrentBuildEvidence {
    param($Build,[Parameter(Mandatory)][string]$RepoRoot,$Manifest,$PayloadReceipt,$PlanBindings)
    Assert-RimePimeExactProperties $Build $script:RimePimeCurrentBuildEvidenceProperties 'receipt-v2 current membership-interval build evidence'
    Assert-RimePimeReceiptV2CompilerMembershipInterval $Build.nsis_compiler_membership_interval
    Assert-RimePimeReceiptV2CurrentBuildLogicSources $Build

    if($Build.product -isnot [string] -or $Build.product_version -isnot [string] -or
        $Build.package_profile -isnot [string] -or $Build.nsis_compiler_input_scope -isnot [string] -or
        [string]$Build.product -cne 'rime-pime' -or [string]$Build.package_profile -cne 'x86-x64-v1' -or
        [string]$Build.nsis_compiler_input_scope -cne 'repository-pinned-nsis-distribution-non-os-v1' -or
        $Manifest.product_version -isnot [string] -or
        [string]$Build.product_version -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$' -or
        $Manifest.product -isnot [string] -or $PayloadReceipt.product -isnot [string] -or
        [string]$Manifest.product -cne 'rime-pime' -or [string]$PayloadReceipt.product -cne 'rime-pime' -or
        $Manifest.package_profile -isnot [string] -or $PayloadReceipt.package_profile -isnot [string] -or
        [string]$Manifest.package_profile -cne 'x86-x64-v1' -or
        [string]$PayloadReceipt.package_profile -cne 'x86-x64-v1' -or
        -not(Test-RimePimeReceiptV2OrderedArchitectures $Manifest.architectures) -or
        -not(Test-RimePimeReceiptV2OrderedArchitectures $PayloadReceipt.architectures)){
        throw 'Current membership-interval build evidence has an invalid or contradictory product identity.'
    }
    foreach($name in @(
        'package_plan_sha256','payload_spec_sha256','content_manifest_sha256','content_tree_sha256','payload_nsh_sha256',
        'nsis_toolchain_lock_sha256','nsis_compiler_input_tree_sha256','makensis_sha256','candidate_installer_sha256',
        'package_build_receipt_sha256')){
        Assert-RimePimeReceiptV2Hash $Build.$name "receipt-v2 current build $name"
    }

    foreach($name in @(
        'copied_file_count','payload_file_count','bootstrap_file_count','main_payload_file_count',
        'package_plan_artifact_count','package_plan_matching_stage_binding_count','staged_pe_unique_artifact_count',
        'staged_pe_path_binding_count','prebuild_leased_input_count','candidate_installer_bytes')){
        if(-not(Test-RimePimeStageInteger $Build.$name) -or [long]$Build.$name -lt 1){
            throw "Current membership-interval build evidence has an invalid $name."
        }
    }
    if($null -eq $PlanBindings -or -not(Test-RimePimeReceiptV2Boolean $PlanBindings.passed $true) -or
        -not(Test-RimePimeStageInteger $PlanBindings.package_plan_artifact_count) -or
        -not(Test-RimePimeStageInteger $PlanBindings.matching_stage_binding_count) -or
        [int]$Build.package_plan_artifact_count -ne [int]$PlanBindings.package_plan_artifact_count -or
        [int]$Build.package_plan_matching_stage_binding_count -ne [int]$PlanBindings.matching_stage_binding_count -or
        [int]$Build.package_plan_artifact_count -ne [int]$Build.staged_pe_unique_artifact_count -or
        [int]$Build.package_plan_matching_stage_binding_count -ne [int]$Build.staged_pe_path_binding_count -or
        [int]$PlanBindings.package_plan_artifact_count -lt 1 -or
        [int]$PlanBindings.matching_stage_binding_count -lt [int]$PlanBindings.package_plan_artifact_count){
        throw 'Current membership-interval build evidence does not close its staged PE artifact and path-binding sets.'
    }
    Assert-RimePimeReceiptV2RequiredProperties $PayloadReceipt @(
        'content_manifest_sha256','unique_stage_file_count','payload_file_count','bootstrap_file_count','main_payload_file_count'
    ) 'receipt-v2 current payload include receipt'
    foreach($name in @('unique_stage_file_count','payload_file_count','bootstrap_file_count','main_payload_file_count')){
        if(-not(Test-RimePimeStageInteger $PayloadReceipt.$name) -or [long]$PayloadReceipt.$name -lt 1){
            throw "Current membership-interval payload include receipt has an invalid $name."
        }
    }
    if([string]$Build.content_manifest_sha256 -cne [string]$PayloadReceipt.content_manifest_sha256 -or
        [long]$Build.copied_file_count -ne [long]$PayloadReceipt.unique_stage_file_count -or
        [long]$Build.copied_file_count -ne @($Manifest.files).Count -or
        [long]$Build.payload_file_count -ne [long]$PayloadReceipt.payload_file_count -or
        [long]$Build.bootstrap_file_count -ne [long]$PayloadReceipt.bootstrap_file_count -or
        [long]$Build.main_payload_file_count -ne [long]$PayloadReceipt.main_payload_file_count -or
        [long]$Build.copied_file_count -ne ([long]$Build.payload_file_count+[long]$Build.bootstrap_file_count) -or
        [long]$Build.main_payload_file_count -gt [long]$Build.payload_file_count){
        throw 'Current membership-interval build evidence contradicts its sealed manifest or payload include counts.'
    }
    $expectedPrebuildLeaseCount=[long]$Build.copied_file_count+15L+
        [long]$Build.build_logic_read_lease_count+[long]$Build.nsis_compiler_input_read_lease_count+
        [long]$Build.nsis_toolchain_control_read_lease_count
    if([long]$Build.prebuild_leased_input_count -ne $expectedPrebuildLeaseCount){
        throw 'Current membership-interval build evidence has an invalid prebuild leased-input count.'
    }
    if([long]$Build.candidate_installer_bytes -lt 65536 -or [long]$Build.candidate_installer_bytes -gt 536870912){
        throw 'Current membership-interval build evidence candidate size is outside the admitted disabled-installer range.'
    }
    foreach($name in @(
        'candidate_leased','repository_local_compiler_inputs_leased','repository_local_bare_include_shadowing_closed',
        'makensis_no_current_directory_change','makensis_user_config_disabled','staged_pe_architecture_verified_under_read_leases',
        'nsis_distribution_tree_exact_at_open_and_test','nsis_known_input_file_replacement_closure',
        'nsis_compiler_input_pre_snapshot_exact','nsis_compiler_input_post_snapshot_exact',
        'nsis_compiler_input_leases_held_during_makensis','makensis_path_lease_verified','unsigned_disabled_build',
        'signing_host_and_release_signing_pending','path_searched_signing_host_not_executed',
        'publication_failure_rollback_enabled','publication_cross_process_lock','prebuild_stage_verified',
        'postbuild_stage_verified','prebuild_include_verified','postbuild_include_verified',
        'installer_raw_byte_search_found_expected_digests','canonical_receipt_v2_finalization_required',
        'canonical_receipt_v2_requires_sealed_postbuild_result','v1_receipt_semantics_preserved_until_explicit_v2_finalization',
        'build_tool_processes_executed','makensis_executed')){
        if(-not(Test-RimePimeReceiptV2Boolean $Build.$name $true)){
            throw "Current membership-interval build evidence has an invalid true boundary $name."
        }
    }
    foreach($name in @(
        'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
        'full_nsis_toolchain_input_closure','signing_hook_processes_executed','postbuild_extraction_compared_to_stage',
        'canonical_receipt_binds_stage_evidence','canonical_receipt_v2_finalizer_automatically_invoked',
        'generated_uninstaller_verified','final_payload_closure','installer_executed','uninstaller_executed',
        'installed_product_processes_touched','product_registry_mutated','default_input_method_changed',
        'production_user_data_read_or_written','installed_yimecore_local12_touched')){
        if(-not(Test-RimePimeReceiptV2Boolean $Build.$name $false)){
            throw "Current membership-interval build evidence has an invalid false boundary $name."
        }
    }
    if($Build.lease_share_mode -isnot [string] -or [string]$Build.lease_share_mode -cne 'read-only-with-file-share-read' -or
        $Build.publication_status_at_evidence_seal -isnot [string] -or
        [string]$Build.publication_status_at_evidence_seal -cne 'prepared-awaiting-receipt-sidecar-commit-marker'){
        throw 'Current membership-interval build evidence has an invalid lease or publication state.'
    }

    foreach($name in @('nsis_compiler_stage_file_lease_count','nsis_compiler_stage_directory_lease_count')){
        if(-not(Test-RimePimeStageInteger $Build.$name)){
            throw "Current membership-interval build evidence has an invalid $name."
        }
    }
    if([int]$Build.nsis_compiler_stage_file_lease_count -ne 303 -or
        [int]$Build.nsis_compiler_stage_file_lease_count -ne [int]$Build.nsis_compiler_input_read_lease_count -or
        [int]$Build.nsis_compiler_stage_directory_lease_count -ne 19 -or
        [int]$Build.nsis_compiler_stage_directory_lease_count -ne [int]$Build.nsis_compiler_input_directory_lease_count){
        throw 'Current membership-interval build evidence stage lease counts are not closed.'
    }
    if($Build.nsis_compiler_membership_interval.active_same_sid_transient_tree_membership_interference_excluded -ne
            $Build.active_same_sid_transient_tree_membership_interference_excluded -or
        $Build.nsis_compiler_membership_interval.nsis_non_os_compiler_input_closure -ne $Build.nsis_non_os_compiler_input_closure -or
        $Build.nsis_compiler_membership_interval.full_nsis_toolchain_input_closure -ne $Build.full_nsis_toolchain_input_closure){
        throw 'Current membership-interval build evidence contradicts its closure boundaries.'
    }

    $repo=[IO.Path]::GetFullPath($RepoRoot).TrimEnd([char]92)
    $allowedStageParent=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd([char]92)
    $stageText=[string]$Build.nsis_compiler_stage_path
    try{$stage=[IO.Path]::GetFullPath($stageText).TrimEnd([char]92)}catch{throw 'Current membership-interval build evidence has an invalid compiler stage path.'}
    $buildStage=Split-Path -Parent $stage
    if($Build.nsis_compiler_stage_path -isnot [string] -or -not[IO.Path]::IsPathRooted($stageText) -or
        $stageText -cne $stage -or (Split-Path -Leaf $stage) -cne 'NSIS' -or
        (Split-Path -Leaf $buildStage) -cnotmatch '^dp1-package-build-stage-[A-Za-z0-9-]+$' -or
        (Split-Path -Parent $buildStage) -ine $allowedStageParent -or
        $Build.makensis_path -isnot [string] -or
        [string]$Build.makensis_path -ine (Join-Path $stage 'Bin\makensis.exe') -or
        $Build.compiler_working_directory -isnot [string] -or
        [string]$Build.compiler_working_directory -ine (Join-Path $stage 'Include')){
        throw 'Current membership-interval build evidence has inconsistent compiler stage paths.'
    }
    $pathFields=@(
        'candidate_installer_path','published_installer_path','package_build_receipt_path',
        'publication_commit_marker_path','publication_lock_path'
    )
    $normalizedPaths=@{}
    foreach($name in $pathFields){
        if($Build.$name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Build.$name)){
            throw "Current membership-interval build evidence has an invalid $name."
        }
        try{$normalized=[IO.Path]::GetFullPath([string]$Build.$name)}catch{throw "Current membership-interval build evidence has an invalid $name."}
        if(-not[IO.Path]::IsPathRooted([string]$Build.$name) -or [string]$Build.$name -ine $normalized){
            throw "Current membership-interval build evidence has a non-canonical $name."
        }
        $normalizedPaths[$name]=$normalized
    }
    $expectedInstallerLeaf=('YIME-'+[string]$Build.product_version+'-setup'+'.exe')
    $expectedReceipt=Join-Path $repo 'installer\package-build-receipt.json'
    if([string]$normalizedPaths.candidate_installer_path -ine (Join-Path $buildStage ('candidate\'+$expectedInstallerLeaf)) -or
        [string]$normalizedPaths.published_installer_path -ine (Join-Path $repo ('installer\'+$expectedInstallerLeaf)) -or
        [string]$normalizedPaths.package_build_receipt_path -ine $expectedReceipt -or
        [string]$normalizedPaths.publication_commit_marker_path -ine ($expectedReceipt+'.sha256') -or
        [string]$normalizedPaths.publication_lock_path -ine (Join-Path $repo 'installer\.rime-pime-publication.lock')){
        throw 'Current membership-interval build evidence has inconsistent candidate or publication paths.'
    }
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
    Assert-RimePimeReceiptV2StringFields $Receipt @(
        'schema_version','product','closure_scope','nsis_profile','package_plan_path','installer_source_path','installer_path','sealed_at_utc'
    ) 'receipt-v2 predecessor'
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
    param($Build,$V1,$Manifest,$PayloadReceipt,$Postbuild,[Parameter(Mandatory)][string]$RepoRoot,$PlanBindings)
    if($null -eq $Build -or -not(Test-RimePimeReceiptV2BuildEvidenceSchema $Build.schema_version)){
        throw 'Build result schema is not an admitted legacy or current membership-interval format.'
    }
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
    if([string]$Build.product -cne 'rime-pime' -or [string]$Build.product_version -cne [string]$Manifest.product_version -or
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
    if([string]$Build.schema_version -ceq $script:RimePimeLegacyBuildEvidenceSchema){
        $actual=@($Build.PSObject.Properties|ForEach-Object Name)
        foreach($name in $script:RimePimeCurrentBuildExclusiveProperties){
            if($actual -ccontains $name){
                throw 'Legacy build evidence cannot carry membership-interval fields under the old schema.'
            }
        }
    }else{
        if($null -ne $V1.PSObject.Properties['installer_source_path'] -and
            [string]$V1.installer_source_path -cne 'installer/installer.nsi'){
            throw 'Current membership-interval build evidence has a non-canonical installer source path.'
        }
        Assert-RimePimeReceiptV2CurrentBuildEvidence $Build $RepoRoot $Manifest $PayloadReceipt $PlanBindings
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
    Assert-RimePimeReceiptV2StringFields $Postbuild @(
        'schema_version','product','product_version','package_profile','package_plan_sha256','content_manifest_sha256',
        'content_tree_sha256','payload_nsh_receipt_sha256','payload_nsh_sha256','nsis_toolchain_lock_sha256',
        'nsis_compiler_input_scope','nsis_compiler_input_tree_sha256'
    ) 'receipt-v2 postbuild result'
    Assert-RimePimeReceiptV2StringFields $Postbuild.installer @('sha256','signature_status') 'receipt-v2 postbuild installer'
    Assert-RimePimeReceiptV2StringFields $Postbuild.generated_uninstaller @('sha256','signature_status') 'receipt-v2 postbuild generated uninstaller'
    Assert-RimePimeReceiptV2StringFields $Postbuild.toolchain_lock @('sha256','toolchain_id') 'receipt-v2 postbuild toolchain lock'
    Assert-RimePimeReceiptV2StringFields $Postbuild.seven_zip @('sha256') 'receipt-v2 postbuild 7-Zip'
    Assert-RimePimeReceiptV2StringFields $Postbuild.seven_zip_parser_library @('sha256','version') 'receipt-v2 postbuild parser library'
    Assert-RimePimeReceiptV2StringFields $Postbuild.makensis @('sha256') 'receipt-v2 postbuild makensis'
    foreach($value in @(
        $Postbuild.installer.bytes,$Postbuild.generated_uninstaller.bytes,$Postbuild.seven_zip.bytes,
        $Postbuild.seven_zip_parser_library.bytes,$Postbuild.makensis.bytes,
        $Postbuild.installer_archive.entry_count,$Postbuild.installer_archive.raw_stdout_entry_count,
        $Postbuild.uninstaller_archive.entry_count,$Postbuild.uninstaller_archive.raw_stdout_entry_count)){
        if(-not(Test-RimePimeStageInteger $value) -or [long]$value -lt 1){
            throw 'Postbuild result has an invalid bound byte or archive count value.'
        }
    }
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
        @($Postbuild.package_plan_sha256,'postbuild package plan'),
        @($Postbuild.content_manifest_sha256,'postbuild content manifest'),
        @($Postbuild.content_tree_sha256,'postbuild content tree'),
        @($Postbuild.payload_nsh_receipt_sha256,'postbuild payload receipt'),
        @($Postbuild.payload_nsh_sha256,'postbuild payload include'),
        @($Postbuild.nsis_toolchain_lock_sha256,'postbuild top-level toolchain lock'),
        @($Postbuild.nsis_compiler_input_tree_sha256,'postbuild compiler input tree'),
        @($Postbuild.installer.sha256,'postbuild installer'),
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
        $null=Assert-RimePimePackagePlanValue $plan.Value
        $manifest.Value=Assert-RimePimeCopiedContentManifestValue $manifest.Value
        if($plan.Digest -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$plan.Value.schema_version -cne 'yime-rime-pime-package-plan-v1' -or
            [string]$plan.Value.product -cne 'rime-pime' -or
            -not(Test-RimePimeReceiptV2OrderedArchitectures $plan.Value.architectures)){
            throw 'Package plan does not match the historical v1 receipt identity.'
        }
        $payloadValidation=Assert-RimePimeNsisStageIncludeReceiptValue $payloadReceipt.Value $manifest.Value `
            $manifest.Digest $plan.Digest
        if([string]$manifest.Value.schema_version -cne 'yime-rime-pime-copied-content-v1' -or
            [string]$payloadReceipt.Value.schema_version -cne 'yime-rime-pime-nsis-stage-include-v1' -or
            [string]$manifest.Value.package_plan_sha256 -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$payloadReceipt.Value.package_plan_sha256 -cne [string]$v1.Value.package_plan_sha256 -or
            [string]$payloadReceipt.Value.payload_spec_sha256 -cne [string]$manifest.Value.payload_spec_sha256 -or
            [string]$payloadReceipt.Value.content_manifest_sha256 -cne $manifest.Digest -or
            [string]$payloadReceipt.Value.content_tree_sha256 -cne [string]$manifest.Value.content_tree_sha256 -or
            -not(Test-RimePimeReceiptV2Boolean $manifest.Value.final_payload_closure $false) -or
            -not(Test-RimePimeReceiptV2Boolean $payloadReceipt.Value.final_payload_closure $false)){
            throw 'Stage manifest and payload include receipt do not share one copied-input identity.'
        }
        $payloadReceipt.Value|Add-Member -NotePropertyName __sealed_digest -NotePropertyValue $payloadReceipt.Digest
        $planBindings=$null
        if([string]$build.Value.schema_version -ceq $script:RimePimeCurrentBuildEvidenceSchema){
            $planBindings=Assert-RimePimePackagePlanStageBindings `
                -Package ([pscustomobject]@{Digest=$plan.Digest;Plan=$plan.Value}) -ContentManifest $manifest.Value
        }
        Assert-RimePimeReceiptV2BuildEvidence $build.Value $v1.Value $manifest.Value $payloadReceipt.Value $postbuild.Value $root $planBindings
        if([string]$build.Value.schema_version -cne $script:RimePimeCurrentBuildEvidenceSchema){
            throw 'New receipt preparation requires current membership-interval build evidence; legacy evidence is read-only.'
        }
        $predecessorInstallerPath=Resolve-RimePimePackageFile $root ([string]$v1.Value.installer_path)
        if([string]$build.Value.package_build_receipt_path -ine [string]$v1.Path -or
            [string]$build.Value.published_installer_path -ine $predecessorInstallerPath){
            throw 'Current build publication paths contradict the actual predecessor identity.'
        }
        $expectedBuildResultPath=Join-Path (Split-Path -Parent ([string]$build.Value.nsis_compiler_stage_path)) 'evidence\build-result.json'
        if([string]$build.Path -ine [IO.Path]::GetFullPath($expectedBuildResultPath)){
            throw 'Current build evidence must be the sealed build-result.json from its declared build root.'
        }
        $expectedEvidenceRoot=Split-Path -Parent $expectedBuildResultPath
        if([string]$manifest.Path -ine (Join-Path $expectedEvidenceRoot 'package-stage-content.json') -or
            [string]$payloadReceipt.Path -ine (Join-Path $expectedEvidenceRoot 'payload-files-receipt.json') -or
            [IO.Path]::GetFullPath($PayloadNshPath) -ine (Join-Path $expectedEvidenceRoot 'payload-files.nsh')){
            throw 'Current build evidence inputs do not share its declared evidence root.'
        }
        $payloadSpecPath=Join-Path $expectedEvidenceRoot 'payload-spec.json'
        $payloadSpec=Open-RimePimeReceiptV2SealedJsonLease $payloadSpecPath 'sealed payload stage spec';$jsonLeases.Add($payloadSpec)
        $goInventoryPath=Join-Path $root 'tools\dual-product\rime-pime-go-payload-inventory.json'
        $goInventory=Open-RimePimeReceiptV2SealedJsonLease $goInventoryPath 'sealed Go payload inventory';$jsonLeases.Add($goInventory)
        if($payloadSpec.Digest -cne [string]$manifest.Value.payload_spec_sha256){
            throw 'Payload stage spec does not match the copied-content manifest identity.'
        }
        $null=Assert-RimePimeStageSpecManifestBinding $payloadSpec.Value $manifest.Value $plan.Value `
            $goInventory.Value $goInventory.Digest
        foreach($row in @($build.Value.executed_build_logic_sources)){
            $logicPath=Resolve-RimePimePackageFile $root ([string]$row.path)
            $logicRecord=Get-YimePimePayloadFileRecord $logicPath
            $logicLease=Open-RimePimeReceiptV2FileLease $logicPath ([string]$row.sha256) ([long]$logicRecord.bytes) 'current build-logic source'
            $fileLeases.Add($logicLease)
        }
        $toolchainLockPath=Join-Path $root 'tools\dual-product\rime-pime-postbuild-toolchain-lock.json'
        $toolchainLock=Open-RimePimeReceiptV2SealedJsonLease $toolchainLockPath 'current NSIS toolchain lock';$jsonLeases.Add($toolchainLock)
        Assert-RimePimeReceiptV2ToolchainLockLease $toolchainLock
        $toolchainClosure=$toolchainLock.Value.nsis.compiler_input_closure
        if($toolchainLock.Digest -cne [string]$build.Value.nsis_toolchain_lock_sha256 -or
            [string]$toolchainLock.Value.schema_version -cne 'yime-rime-pime-postbuild-toolchain-lock-v2' -or
            [string]$toolchainLock.Value.package_profile -cne [string]$build.Value.package_profile -or
            [string]$toolchainLock.Value.nsis.makensis.sha256 -cne [string]$build.Value.makensis_sha256 -or
            [string]$toolchainClosure.scope -cne [string]$build.Value.nsis_compiler_input_scope -or
            [string]$toolchainClosure.tree_sha256 -cne [string]$build.Value.nsis_compiler_input_tree_sha256 -or
            -not(Test-RimePimeStageInteger $toolchainClosure.file_count) -or
            [int]$toolchainClosure.file_count -ne [int]$build.Value.nsis_compiler_input_file_count -or
            -not(Test-RimePimeStageInteger $toolchainClosure.directory_count) -or
            [int]$toolchainClosure.directory_count -ne [int]$build.Value.nsis_compiler_input_directory_count){
            throw 'Current build evidence contradicts the leased repository NSIS toolchain lock.'
        }
        if([string]$build.Value.package_build_receipt_sha256 -cne $v1.Digest){throw 'Build result does not bind the supplied historical v1 receipt bytes.'}
        Assert-RimePimeReceiptV2PostbuildEvidence $postbuild.Value $build.Value $manifest.Value $payloadReceipt.Value
        if([string]$postbuild.Value.toolchain_lock.toolchain_id -cne [string]$toolchainLock.Value.toolchain_id -or
            [string]$postbuild.Value.seven_zip.sha256 -cne [string]$toolchainLock.Value.seven_zip.sha256 -or
            [long]$postbuild.Value.seven_zip.bytes -ne [long]$toolchainLock.Value.seven_zip.bytes -or
            [string]$postbuild.Value.seven_zip_parser_library.sha256 -cne [string]$toolchainLock.Value.seven_zip.library.sha256 -or
            [long]$postbuild.Value.seven_zip_parser_library.bytes -ne [long]$toolchainLock.Value.seven_zip.library.bytes -or
            [string]$postbuild.Value.makensis.sha256 -cne [string]$toolchainLock.Value.nsis.makensis.sha256 -or
            [long]$postbuild.Value.makensis.bytes -ne [long]$toolchainLock.Value.nsis.makensis.bytes){
            throw 'Postbuild tool identities contradict the code-pinned NSIS toolchain lock.'
        }
        $includePath=[IO.Path]::GetFullPath($PayloadNshPath)
        if((Split-Path -Parent $includePath) -ine (Split-Path -Parent $payloadReceipt.Path) -or
            [IO.Path]::GetFileName($includePath) -cne [string]$payloadReceipt.Value.include_file){throw 'Payload include path differs from its sealed receipt.'}
        $include=Open-RimePimeReceiptV2FileLease $includePath ([string]$payloadReceipt.Value.include_sha256) ([long]$payloadReceipt.Value.include_bytes) 'payload include';$fileLeases.Add($include)
        $includeSidecar=Open-RimePimeReceiptV2RawSidecarLease $includePath $include.Digest 'payload include';$fileLeases.Add($includeSidecar)
        Assert-RimePimeReceiptV2LeasedIncludeDocument $include $payloadValidation.Document 'payload include'
        $sourcePath=Resolve-RimePimePackageFile $root ([string]$v1.Value.installer_source_path)
        $sourceBytes=[long](Get-Item -LiteralPath $sourcePath).Length
        $source=Open-RimePimeReceiptV2FileLease $sourcePath ([string]$v1.Value.installer_source_sha256) $sourceBytes 'installer source';$fileLeases.Add($source)
        $installerPath=Resolve-RimePimePackageFile $root ([string]$v1.Value.installer_path)
        $installer=Open-RimePimeReceiptV2FileLease $installerPath ([string]$v1.Value.installer_sha256) ([long]$v1.Value.installer_size) 'canonical disabled installer';$fileLeases.Add($installer)
        Assert-RimePimeReceiptV2InstallerRawBindings $installer $plan.Digest $manifest.Digest `
            ([string]$manifest.Value.content_tree_sha256) $include.Digest
        foreach($path in @($build.Path,$manifest.Path,$payloadReceipt.Path,$postbuild.Path,$include.Path)){$null=ConvertTo-RimePimeReceiptV2RelativePath $root $path}
        $receipt=[pscustomobject][ordered]@{
            schema_version=$script:RimePimePackageReceiptV2Schema;product='rime-pime'
            closure_scope='sealed-stage-disabled-nsis-build-and-static-archive-evidence-not-release'
            receipt_state='canonical-static-closure-disabled';product_version=[string]$build.Value.product_version
            architectures=@('x86','x64');package_profile='x86-x64-v1'
            package_plan=[pscustomobject][ordered]@{path=[string]$v1.Value.package_plan_path;sha256=[string]$v1.Value.package_plan_sha256}
            sealed_stage=[pscustomobject][ordered]@{
                content_manifest_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $manifest.Path)
                content_manifest_sha256=$manifest.Digest
                payload_spec_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $payloadSpec.Path)
                payload_spec_sha256=[string]$manifest.Value.payload_spec_sha256
                go_payload_inventory_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $goInventory.Path)
                go_payload_inventory_sha256=$goInventory.Digest
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
                nsis_toolchain_lock_path=(ConvertTo-RimePimeReceiptV2RelativePath $root $toolchainLock.Path)
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
        $currentReceiptEvidence=[string]$r.disabled_build.schema_version -ceq $script:RimePimeCurrentBuildEvidenceSchema
        $stageProperties=@('content_manifest_path','content_manifest_sha256','payload_spec_sha256','content_tree_sha256','copied_file_count','payload_file_count','bootstrap_file_count')
        if($currentReceiptEvidence){$stageProperties=@(
            'content_manifest_path','content_manifest_sha256','payload_spec_path','payload_spec_sha256',
            'go_payload_inventory_path','go_payload_inventory_sha256','content_tree_sha256',
            'copied_file_count','payload_file_count','bootstrap_file_count')}
        Assert-RimePimeExactProperties $r.sealed_stage $stageProperties 'receipt-v2 stage'
        Assert-RimePimeExactProperties $r.payload_include @('path','sha256','bytes','receipt_path','receipt_sha256') 'receipt-v2 payload include'
        Assert-RimePimeExactProperties $r.predecessor_v1 @('schema_version','source_path_at_finalization','sha256','bytes','installer_sha256','installer_size','package_plan_sha256') 'receipt-v2 predecessor identity'
        $disabledBuildProperties=@(
            'result_path','result_sha256','schema_version','makensis_sha256','nsis_toolchain_lock_sha256','nsis_compiler_input_scope',
            'nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
            'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
            'nsis_toolchain_control_read_lease_count','nsis_known_input_file_replacement_closure',
            'nsis_compiler_input_pre_snapshot_exact','nsis_compiler_input_post_snapshot_exact',
            'nsis_compiler_input_leases_held_during_makensis',
            'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
            'full_nsis_toolchain_input_closure','unsigned_disabled_build','signing_hook_processes_executed')
        if($currentReceiptEvidence){$disabledBuildProperties=@('result_path','result_sha256','schema_version','makensis_sha256','nsis_toolchain_lock_path','nsis_toolchain_lock_sha256','nsis_compiler_input_scope',
            'nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
            'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
            'nsis_toolchain_control_read_lease_count','nsis_known_input_file_replacement_closure','nsis_compiler_input_pre_snapshot_exact',
            'nsis_compiler_input_post_snapshot_exact','nsis_compiler_input_leases_held_during_makensis',
            'active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure',
            'full_nsis_toolchain_input_closure','unsigned_disabled_build','signing_hook_processes_executed')}
        Assert-RimePimeExactProperties $r.disabled_build $disabledBuildProperties 'receipt-v2 disabled build'
        Assert-RimePimeExactProperties $r.static_postbuild @('result_path','result_sha256','schema_version','toolchain','installer_archive_entry_count','nested_uninstaller_archive_entry_count','generated_uninstaller_sha256','generated_uninstaller_bytes','archive_content_origin_proven','actual_installer_or_uninstaller_executed') 'receipt-v2 static postbuild'
        Assert-RimePimeExactProperties $r.static_postbuild.toolchain @(
            'toolchain_id','lock_sha256','makensis_sha256','seven_zip_sha256','seven_zip_parser_library_sha256','seven_zip_parser_library_version',
            'nsis_compiler_input_scope','nsis_compiler_input_tree_sha256','nsis_compiler_input_file_count','nsis_compiler_input_directory_count',
            'nsis_compiler_input_read_lease_count','nsis_compiler_input_directory_lease_count','nsis_compiler_input_anchor_directory_lease_count',
            'nsis_toolchain_control_read_lease_count','inputs_exact_and_read_leased_during_postbuild','known_input_file_replacement_closure',
            'active_same_sid_transient_tree_membership_interference_excluded','compiler_input_leases_held_during_makensis',
            'non_os_compiler_input_closure','full_toolchain_input_closure') 'receipt-v2 toolchain'
        Assert-RimePimeExactProperties $r.installer @('path','sha256','bytes','source_path','source_sha256') 'receipt-v2 installer'
        Assert-RimePimeReceiptV2StringFields $r @(
            'schema_version','product','closure_scope','receipt_state','product_version','package_profile','sealed_at_utc'
        ) 'receipt-v2'
        Assert-RimePimeReceiptV2StringFields $r.disabled_build @('schema_version','nsis_compiler_input_scope') 'receipt-v2 disabled build'
        Assert-RimePimeReceiptV2StringFields $r.predecessor_v1 @('schema_version') 'receipt-v2 predecessor identity'
        Assert-RimePimeReceiptV2StringFields $r.static_postbuild @('schema_version') 'receipt-v2 static postbuild'
        Assert-RimePimeReceiptV2StringFields $r.static_postbuild.toolchain @(
            'toolchain_id','seven_zip_parser_library_version','nsis_compiler_input_scope'
        ) 'receipt-v2 static postbuild toolchain'
        foreach($pathValue in @(
            $r.package_plan.path,$r.sealed_stage.content_manifest_path,$r.payload_include.path,$r.payload_include.receipt_path,
            $r.predecessor_v1.source_path_at_finalization,$r.disabled_build.result_path,$r.static_postbuild.result_path,
            $r.installer.path,$r.installer.source_path)){
            if($pathValue -isnot [string]){throw 'Receipt-v2 bound paths must be JSON strings.'}
        }
        if($currentReceiptEvidence){
            foreach($pathValue in @($r.sealed_stage.payload_spec_path,$r.sealed_stage.go_payload_inventory_path,$r.disabled_build.nsis_toolchain_lock_path)){
                if($pathValue -isnot [string]){throw 'Current receipt-v2 bound paths must be JSON strings.'}
            }
        }
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
            -not(Test-RimePimeReceiptV2BuildEvidenceSchema $r.disabled_build.schema_version) -or
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
        $boundDigests=@(
            $r.package_plan.sha256,$r.sealed_stage.content_manifest_sha256,$r.sealed_stage.payload_spec_sha256,$r.sealed_stage.content_tree_sha256,
            $r.payload_include.sha256,$r.payload_include.receipt_sha256,$r.predecessor_v1.sha256,
            $r.predecessor_v1.installer_sha256,$r.predecessor_v1.package_plan_sha256,$r.disabled_build.result_sha256,
            $r.disabled_build.makensis_sha256,$r.disabled_build.nsis_toolchain_lock_sha256,$r.disabled_build.nsis_compiler_input_tree_sha256,
            $r.static_postbuild.result_sha256,$r.static_postbuild.toolchain.lock_sha256,
            $r.static_postbuild.toolchain.makensis_sha256,$r.static_postbuild.toolchain.nsis_compiler_input_tree_sha256,
            $r.static_postbuild.toolchain.seven_zip_sha256,$r.static_postbuild.toolchain.seven_zip_parser_library_sha256,
            $r.static_postbuild.generated_uninstaller_sha256,$r.installer.sha256,$r.installer.source_sha256)
        if($currentReceiptEvidence){$boundDigests+=@($r.sealed_stage.go_payload_inventory_sha256)}
        foreach($value in $boundDigests){
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
        if($currentReceiptEvidence){
            $evidencePairs+=@([pscustomobject]@{Path=$r.sealed_stage.payload_spec_path;Digest=$r.sealed_stage.payload_spec_sha256;Context='receipt-v2 payload stage spec'})
            $evidencePairs+=@([pscustomobject]@{Path=$r.sealed_stage.go_payload_inventory_path;Digest=$r.sealed_stage.go_payload_inventory_sha256;Context='receipt-v2 Go payload inventory'})
            $evidencePairs+=@([pscustomobject]@{Path=$r.disabled_build.nsis_toolchain_lock_path;Digest=$r.disabled_build.nsis_toolchain_lock_sha256;Context='receipt-v2 NSIS toolchain lock'})
        }
        $evidence=@{}
        foreach($item in $evidencePairs){
            $path=Resolve-RimePimeReceiptEvidence $root $r ([string]$item.Path) ([string]$item.Digest)
            $bound=Open-RimePimeReceiptV2SealedJsonLease $path ([string]$item.Context)
            try{
                if($bound.Digest -cne [string]$item.Digest){throw "$($item.Context) differs from the canonical receipt."}
                if([string]$item.Context -ceq 'receipt-v2 NSIS toolchain lock'){
                    Assert-RimePimeReceiptV2ToolchainLockLease $bound
                }
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
        $null=Assert-RimePimePackagePlanValue $plan
        $manifest=Assert-RimePimeCopiedContentManifestValue $manifest
        $payloadValidation=Assert-RimePimeNsisStageIncludeReceiptValue $payload $manifest `
            ([string]$r.sealed_stage.content_manifest_sha256) ([string]$r.package_plan.sha256)
        if($currentReceiptEvidence){
            $null=Assert-RimePimeStageSpecManifestBinding $evidence['receipt-v2 payload stage spec'] $manifest $plan `
                $evidence['receipt-v2 Go payload inventory'] ([string]$r.sealed_stage.go_payload_inventory_sha256)
            $lock=$evidence['receipt-v2 NSIS toolchain lock']
            if([string]$post.toolchain_lock.toolchain_id -cne [string]$lock.toolchain_id -or
                [string]$post.seven_zip.sha256 -cne [string]$lock.seven_zip.sha256 -or
                [long]$post.seven_zip.bytes -ne [long]$lock.seven_zip.bytes -or
                [string]$post.seven_zip_parser_library.sha256 -cne [string]$lock.seven_zip.library.sha256 -or
                [long]$post.seven_zip_parser_library.bytes -ne [long]$lock.seven_zip.library.bytes -or
                [string]$post.makensis.sha256 -cne [string]$lock.nsis.makensis.sha256 -or
                [long]$post.makensis.bytes -ne [long]$lock.nsis.makensis.bytes){
                throw 'Bound postbuild tools contradict the retained code-pinned NSIS toolchain lock.'
            }
        }
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
        $planBindings=$null
        if([string]$build.schema_version -ceq $script:RimePimeCurrentBuildEvidenceSchema){
            $planBindings=Assert-RimePimePackagePlanStageBindings `
                -Package ([pscustomobject]@{Digest=[string]$r.package_plan.sha256;Plan=$plan}) -ContentManifest $manifest
        }
        Assert-RimePimeReceiptV2BuildEvidence $build $v1Identity $manifest $payload $post $root $planBindings
        Assert-RimePimeReceiptV2PostbuildEvidence $post $build $manifest $payload
        if([string]$build.schema_version -ceq $script:RimePimeCurrentBuildEvidenceSchema){
            $expectedEvidenceRoot=Join-Path (Split-Path -Parent ([string]$build.nsis_compiler_stage_path)) 'evidence'
            if([string]$r.disabled_build.result_path -cne (ConvertTo-RimePimeReceiptV2RelativePath $root (Join-Path $expectedEvidenceRoot 'build-result.json')) -or
                [string]$r.sealed_stage.content_manifest_path -cne (ConvertTo-RimePimeReceiptV2RelativePath $root (Join-Path $expectedEvidenceRoot 'package-stage-content.json')) -or
                [string]$r.sealed_stage.payload_spec_path -cne (ConvertTo-RimePimeReceiptV2RelativePath $root (Join-Path $expectedEvidenceRoot 'payload-spec.json')) -or
                [string]$r.sealed_stage.go_payload_inventory_path -cne 'tools/dual-product/rime-pime-go-payload-inventory.json' -or
                [string]$r.payload_include.path -cne (ConvertTo-RimePimeReceiptV2RelativePath $root (Join-Path $expectedEvidenceRoot 'payload-files.nsh')) -or
                [string]$r.payload_include.receipt_path -cne (ConvertTo-RimePimeReceiptV2RelativePath $root (Join-Path $expectedEvidenceRoot 'payload-files-receipt.json')) -or
                [string]$r.disabled_build.nsis_toolchain_lock_path -cne 'tools/dual-product/rime-pime-postbuild-toolchain-lock.json' -or
                [string]$r.installer.source_path -cne 'installer/installer.nsi'){
                throw 'Current receipt evidence paths do not match the declared build evidence root.'
            }
            if([string]$build.package_build_receipt_path -ine (Resolve-RimePimePackageFile $root ([string]$r.predecessor_v1.source_path_at_finalization)) -or
                [string]$build.published_installer_path -ine (Resolve-RimePimePackageFile $root ([string]$r.installer.path))){
                throw 'Current receipt publication paths contradict its predecessor or installer identity.'
            }
        }
        foreach ($property in $r.disabled_build.PSObject.Properties) {
            if ($property.Name -in @('result_path','result_sha256','nsis_toolchain_lock_path')) { continue }
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
            try{Assert-RimePimeReceiptV2LeasedIncludeDocument $include $payloadValidation.Document 'receipt-v2 payload include'}
            finally{$marker.Stream.Dispose()}
        }finally{$include.Stream.Dispose()}
        $sourcePath=Resolve-RimePimeReceiptEvidence $root $r ([string]$r.installer.source_path) ([string]$r.installer.source_sha256)
        $sourceBytes=[long](Get-Item -LiteralPath $sourcePath).Length
        $source=Open-RimePimeReceiptV2FileLease $sourcePath ([string]$r.installer.source_sha256) $sourceBytes 'receipt-v2 installer source'
        $source.Stream.Dispose()
        $installerPath=Resolve-RimePimeReceiptEvidence $root $r ([string]$r.installer.path) ([string]$r.installer.sha256)
        $candidate=Open-RimePimeReceiptV2FileLease $installerPath ([string]$r.installer.sha256) ([long]$r.installer.bytes) 'receipt-v2 canonical installer'
        try{
            Assert-RimePimeReceiptV2InstallerRawBindings $candidate $r.package_plan.sha256 `
                $r.sealed_stage.content_manifest_sha256 $r.sealed_stage.content_tree_sha256 $r.payload_include.sha256
            return [pscustomobject]@{Receipt=$r;Digest=$lease.Digest;Path=$lease.Path;Sidecar=$lease.Sidecar;InstallerPath=$installerPath}
        }
        finally{$candidate.Stream.Dispose()}
    }finally{$lease.SidecarStream.Dispose();$lease.JsonStream.Dispose()}
}
