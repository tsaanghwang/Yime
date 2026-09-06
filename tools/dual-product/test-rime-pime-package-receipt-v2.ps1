[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot,[switch]$DefinitionsOnly)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\');$allowed=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $allowed -or (Split-Path -Leaf $output) -cnotmatch '^dp1-package-receipt-v2-test-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-package-receipt-v2-test-* output root.'
}
New-Item -ItemType Directory -Path $output|Out-Null
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.psm1') -Force
# Receipt-v2 deliberately does not re-export the imported staging module.
# This fixture consumes the staging JSON writer as a separate test dependency.
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true;detail='ok'})}
    catch{$checks.Add([pscustomobject]@{name=$Name;passed=$false;detail=$_.Exception.Message})}
}
function Assert-True($Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Rejected([scriptblock]$Body,[string]$Pattern='*'){
    try{& $Body;throw 'Expected rejection did not occur.'}catch{if($_.Exception.Message -eq 'Expected rejection did not occur.'){throw};if($_.Exception.Message -notlike $Pattern){throw "Unexpected rejection: $($_.Exception.Message)"}}
}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-AsciiSidecar([string]$Path,[string]$Digest){
    [IO.File]::WriteAllText($Path+'.sha256',"$Digest  $([IO.Path]::GetFileName($Path))`n",[Text.Encoding]::ASCII)
}
function Seal($Value,[string]$Path){return Write-RimePimeStageSealedJson $Value $Path}
function New-Case([string]$Name){
    $caseRoot=Join-Path $output ('cases\'+$Name);$root=Join-Path $caseRoot 'repo'
    $installerDir=Join-Path $root 'installer';$evidence=Join-Path $root '.tmp\evidence'
    New-Item -ItemType Directory -Path $installerDir,$evidence,(Join-Path $root '.tmp\dual-product') -Force|Out-Null
    $source=Join-Path $installerDir 'installer.nsi';[IO.File]::WriteAllText($source,'disabled fixture source',[Text.UTF8Encoding]::new($false))
    $installer=Join-Path $installerDir 'YIME-test-setup.exe';[IO.File]::WriteAllBytes($installer,(New-Object byte[] 65536))
    $installerHash=Hash $installer;$sourceHash=Hash $source
    $planPath=Join-Path $installerDir 'package-plan.json'
    $plan=[pscustomobject][ordered]@{schema_version='yime-rime-pime-package-plan-v1';product='rime-pime';architectures=@('x86','x64')}
    $planDigest=Seal $plan $planPath
    $manifestPath=Join-Path $evidence 'package-stage-content.json'
    $manifest=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-copied-content-v1';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$planDigest
        payload_spec_sha256=('1'*64);content_tree_sha256=('2'*64);final_payload_closure=$false
    }
    $manifestDigest=Seal $manifest $manifestPath
    $includePath=Join-Path $evidence 'payload-files.nsh';[IO.File]::WriteAllText($includePath,'File /nonfatal fixture',[Text.Encoding]::ASCII)
    $includeHash=Hash $includePath;Write-AsciiSidecar $includePath $includeHash
    $payloadReceiptPath=Join-Path $evidence 'payload-files-receipt.json'
    $payloadReceipt=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-nsis-stage-include-v1';product='rime-pime';package_profile='x86-x64-v1'
        architectures=@('x86','x64');package_plan_sha256=$planDigest;payload_spec_sha256=('1'*64)
        content_manifest_sha256=$manifestDigest;content_tree_sha256=('2'*64);include_file='payload-files.nsh'
        include_sha256=$includeHash;include_bytes=[long](Get-Item $includePath).Length;final_payload_closure=$false
    }
    $payloadReceiptDigest=Seal $payloadReceipt $payloadReceiptPath
    $v1Path=Join-Path $installerDir 'package-build-receipt.json'
    $v1=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload';architectures=@('x86','x64')
        package_plan_path='installer/package-plan.json';package_plan_sha256=$planDigest;nsis_profile='x86-x64-v1'
        installer_source_path='installer/installer.nsi';installer_source_sha256=$sourceHash
        installer_path='installer/YIME-test-setup.exe';installer_size=65536;installer_sha256=$installerHash
        sealed_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $v1Digest=Seal $v1 $v1Path
    $buildPath=Join-Path $evidence 'build-result.json'
    $build=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-staged-nsis-build-result-v2';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$planDigest
        payload_spec_sha256=('1'*64);content_manifest_sha256=$manifestDigest;content_tree_sha256=('2'*64);payload_nsh_sha256=$includeHash
        copied_file_count=3;payload_file_count=2;bootstrap_file_count=1
        candidate_installer_sha256=$installerHash;candidate_installer_bytes=65536;package_build_receipt_sha256=$v1Digest
        executed_build_logic_source_count=1;executed_build_logic_sources=@([pscustomobject]@{path='tools/build.ps1';sha256=('a'*64)})
        build_logic_read_lease_count=1;repository_local_compiler_inputs_leased=$true;makensis_path_lease_verified=$true
        build_tool_processes_executed=$true;makensis_executed=$true
        candidate_leased=$true;prebuild_stage_verified=$true;postbuild_stage_verified=$true
        prebuild_include_verified=$true;postbuild_include_verified=$true;installer_raw_byte_search_found_expected_digests=$true
        makensis_sha256=('3'*64);nsis_toolchain_lock_sha256=('4'*64)
        nsis_compiler_input_scope='repository-pinned-nsis-distribution-non-os-v1';nsis_compiler_input_tree_sha256=('5'*64)
        nsis_compiler_input_file_count=303;nsis_compiler_input_directory_count=17
        nsis_compiler_input_read_lease_count=303;nsis_compiler_input_directory_lease_count=19
        nsis_compiler_input_anchor_directory_lease_count=2
        nsis_toolchain_control_read_lease_count=2;nsis_compiler_input_pre_snapshot_exact=$true
        nsis_compiler_input_post_snapshot_exact=$true;nsis_compiler_input_leases_held_during_makensis=$true
        nsis_known_input_file_replacement_closure=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
        unsigned_disabled_build=$true;signing_hook_processes_executed=$false;installer_executed=$false;uninstaller_executed=$false
        installed_product_processes_touched=$false;product_registry_mutated=$false;default_input_method_changed=$false
        production_user_data_read_or_written=$false;installed_yimecore_local12_touched=$false
    }
    $null=Seal $build $buildPath
    $postPath=Join-Path $evidence 'postbuild-result.json'
    $post=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-postbuild-extraction-v2';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$planDigest
        content_manifest_sha256=$manifestDigest;content_tree_sha256=('2'*64);payload_nsh_receipt_sha256=$payloadReceiptDigest
        payload_nsh_sha256=$includeHash;installer=[pscustomobject]@{
            sha256=$installerHash;bytes=65536;signature_status='NotSigned';package_plan_raw_byte_binding=$true
            content_manifest_raw_byte_binding=$true;content_tree_raw_byte_binding=$true;payload_nsh_raw_byte_binding=$true;trusted=$false
        }
        generated_uninstaller=[pscustomobject]@{
            sha256=('6'*64);bytes=65536;signature_status='NotSigned';package_plan_raw_byte_binding=$true
            content_manifest_raw_byte_binding=$true;content_tree_raw_byte_binding=$true;payload_nsh_raw_byte_binding=$true;trusted=$false
        }
        toolchain_lock=[pscustomobject]@{sha256=('4'*64);toolchain_id='fixture-nsis-toolchain-v2'}
        seven_zip=[pscustomobject]@{sha256=('7'*64);bytes=1}
        seven_zip_parser_library=[pscustomobject]@{sha256=('8'*64);bytes=1;version='1.0';loaded_library_binding_verified=$true}
        makensis=[pscustomobject]@{sha256=('3'*64);bytes=1}
        installer_archive=[pscustomobject]@{entry_count=3;raw_stdout_entry_count=3}
        uninstaller_archive=[pscustomobject]@{entry_count=2;raw_stdout_entry_count=2}
        installer_archive_listing_exact=$true;nested_uninstaller_archive_listing_exact=$true
        stable_extracted_snapshot_matches_expected_sources=$true;stable_extracted_stage_owned_files_match_sealed_manifest=$true
        installer_archive_per_entry_raw_stdout_verified=$true;nested_uninstaller_archive_per_entry_raw_stdout_verified=$true
        archive_content_origin_proven=$true;archive_content_provenance_closed_against_active_same_sid_replacement=$true
        active_same_sid_extracted_path_interference_excluded_from_archive_byte_provenance=$true
        parent_created_per_entry_raw_stdout_snapshot=$true;seven_zip_never_received_snapshot_output_paths=$true
        package_plan_stage_bindings_verified=$true;payload_nsh_raw_byte_binding_verified=$true
        installer_read_lease_held_for_all_reads=$true;uninstaller_read_lease_held_for_all_reads=$true
        seven_zip_read_lease_held_for_all_calls=$true;seven_zip_parser_library_read_lease_held_for_all_calls=$true
        execution_logic_read_leases_held_through_seal=$true
        extraction_root_and_expected_directory_identity_leases_held_through_seal=$true
        extracted_file_read_leases_held_through_seal=$true;raw_generated_uninstaller_capture_read_lease_held_through_seal=$true
        result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass=$true
        text_logs_create_new_memory_digest_bound_and_leased_through_result_seal=$true
        verification_passes=2;seven_zip_call_count=7;seven_zip_text_call_count=2;seven_zip_per_entry_raw_stdout_call_count=5
        nsis_toolchain_lock_sha256=('4'*64);nsis_compiler_input_scope='repository-pinned-nsis-distribution-non-os-v1'
        nsis_compiler_input_tree_sha256=('5'*64);nsis_compiler_input_file_count=303;nsis_compiler_input_directory_count=17
        nsis_compiler_input_read_lease_count=303;nsis_compiler_input_directory_lease_count=19
        nsis_compiler_input_anchor_directory_lease_count=2;nsis_toolchain_control_read_lease_count=2
        nsis_distribution_inputs_exact_and_read_leased_during_postbuild=$true;nsis_known_input_file_replacement_closure=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_compiler_input_leases_held_during_makensis=$false;nsis_non_os_compiler_input_closure=$false
        full_nsis_toolchain_input_closure=$false
        generated_uninstaller_present=$true;generated_uninstaller_static_archive_member_verified=$true
        generated_uninstaller_verified=$false;generated_uninstaller_trusted=$false;final_payload_closure=$false;delivery_admitted=$false
        extractor_process_executed=$true;actual_installer_or_uninstaller_executed=$false;product_process_started_or_stopped=$false
        registry_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
        installed_yimecore_local12_touched=$false
    }
    $null=Seal $post $postPath
    return [pscustomobject]@{
        Root=$root;V1Path=$v1Path;BuildPath=$buildPath;ManifestPath=$manifestPath;IncludePath=$includePath
        PayloadReceiptPath=$payloadReceiptPath;PostPath=$postPath;Build=$build;Post=$post;Installer=$installer
        V2Output=Join-Path $root ('.tmp\dual-product\dp1-package-receipt-v2-'+$Name)
    }
}
function Prepare($Case){
    return New-RimePimePackageReceiptV2Preparation -RepoRoot $Case.Root -BuildReceiptV1Path $Case.V1Path `
        -BuildResultPath $Case.BuildPath -ContentManifestPath $Case.ManifestPath -PayloadNshPath $Case.IncludePath `
        -PayloadNshReceiptPath $Case.PayloadReceiptPath -PostbuildResultPath $Case.PostPath -OutputRoot $Case.V2Output
}

if ($DefinitionsOnly) { return }

Check 'matching-sealed-evidence-prepares-strict-v2' {
    $case=New-Case 'matching';$p=$null
    try{$p=Prepare $case;$r=Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath
        Assert-True ($r.Digest -ceq $p.ReceiptDigest -and -not $r.Receipt.delivery_admitted) 'Strict v2 readback differs.'
    }finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'candidate-byte-mismatch-is-rejected' {
    $case=New-Case 'candidate-mismatch';$bytes=[IO.File]::ReadAllBytes($case.Installer);$bytes[0]=1;[IO.File]::WriteAllBytes($case.Installer,$bytes)
    Assert-Rejected {Prepare $case} '*canonical disabled installer differs*'
}
Check 'postbuild-stage-mismatch-is-rejected' {
    $case=New-Case 'stage-mismatch';$case.Post.content_tree_sha256=('9'*64);$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*same disabled candidate*'
}
Check 'postbuild-toolchain-lock-mismatch-is-rejected' {
    $case=New-Case 'lock-mismatch';$case.Post.toolchain_lock.sha256=('9'*64);$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*same disabled candidate*'
}
Check 'missing-non-os-closure-field-is-rejected' {
    $case=New-Case 'missing-closure';$case.Build.PSObject.Properties.Remove('nsis_non_os_compiler_input_closure');$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*missing required property nsis_non_os_compiler_input_closure*'
}
Check 'dishonest-non-os-closure-claim-is-rejected' {
    $case=New-Case 'false-closure';$case.Build.nsis_non_os_compiler_input_closure=$true;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*same sealed, disabled*'
}
Check 'dishonest-transient-membership-exclusion-claim-is-rejected' {
    $case=New-Case 'transient-claim';$case.Build.active_same_sid_transient_tree_membership_interference_excluded=$true;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*same sealed, disabled*'
}
Check 'missing-exact-post-snapshot-is-rejected' {
    $case=New-Case 'post-snapshot';$case.Build.nsis_compiler_input_post_snapshot_exact=$false;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*same sealed, disabled*'
}
Check 'full-os-toolchain-closure-claim-is-rejected' {
    $case=New-Case 'false-full-claim';$case.Build.full_nsis_toolchain_input_closure=$true;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*same sealed, disabled*'
}
Check 'postbuild-execution-boundary-violation-is-rejected' {
    $case=New-Case 'executed';$case.Post.actual_installer_or_uninstaller_executed=$true;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*static-only boundaries*'
}
Check 'dishonest-postbuild-toolchain-closure-claim-is-rejected' {
    $case=New-Case 'postbuild-toolchain-claim';$case.Post.nsis_non_os_compiler_input_closure=$true;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*static-only boundaries*'
}
Check 'postbuild-toolchain-count-string-cannot-spoof-integer' {
    $case=New-Case 'postbuild-count-string';$case.Post.nsis_compiler_input_file_count='303';$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*invalid nsis_compiler_input_file_count*'
}
Check 'string-false-cannot-spoof-boolean-boundary' {
    $case=New-Case 'string-false';$case.Post.delivery_admitted='false';$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*static-only boundaries*'
}
Check 'tampered-sealed-result-sidecar-is-rejected' {
    $case=New-Case 'sidecar';[IO.File]::WriteAllText($case.PostPath+'.sha256',(('0'*64)+'  postbuild-result.json'+"`n"),[Text.Encoding]::ASCII)
    Assert-Rejected {Prepare $case} '*sidecar does not match*'
}
Check 'evolved-postbuild-schema-and-generic-toolchain-id-are-accepted' {
    $case=New-Case 'schema-evolution';$case.Post|Add-Member -NotePropertyName future_static_field -NotePropertyValue 'ignored-but-result-digest-bound'
    $case.Post.toolchain_lock.toolchain_id='other-pinned-toolchain.3';$null=Seal $case.Post $case.PostPath;$p=$null
    try{$p=Prepare $case;Assert-True ($p.Receipt.static_postbuild.toolchain.toolchain_id -ceq 'other-pinned-toolchain.3') 'Generic toolchain identity was not retained.'}
    finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'strict-reader-rejects-open-v2-schema' {
    $case=New-Case 'open-v2';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $p.Receipt|Add-Member -NotePropertyName unreviewed -NotePropertyValue $true;$null=Seal $p.Receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*open or incomplete schema*'
}
Check 'strict-reader-rejects-resealed-false-archive-origin' {
    $case=New-Case 'reader-origin';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $p.Receipt.static_postbuild.archive_content_origin_proven=$false;$null=Seal $p.Receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*identity or fail-closed boundary*'
}
Check 'strict-reader-rejects-resealed-executed-installer-claim' {
    $case=New-Case 'reader-executed';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $p.Receipt.static_postbuild.actual_installer_or_uninstaller_executed=$true;$null=Seal $p.Receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*identity or fail-closed boundary*'
}
Check 'strict-reader-rejects-resealed-invalid-evidence-schema' {
    $case=New-Case 'reader-schema';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $p.Receipt.static_postbuild.schema_version='invented';$null=Seal $p.Receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*identity or fail-closed boundary*'
}
Check 'publication-preserves-v1-copy-and-commits-v2-sidecar-last' {
    $case=New-Case 'publish';$v1Digest=Hash $case.V1Path;$p=$null
    try{$p=Prepare $case;$published=Publish-RimePimePackageReceiptV2 $p $case.V1Path
        Assert-True ($published.Receipt.schema_version -ceq 'yime-rime-pime-package-build-receipt-v2') 'Canonical receipt was not v2.'
        $history=Join-Path $case.V2Output 'historical\package-build-receipt-v1.json'
        Assert-True ((Hash $history) -ceq $v1Digest) 'Historical v1 bytes were not retained.'
        Assert-Rejected {Read-RimePimePackageBuildReceipt ([pscustomobject]@{RepoRoot=$case.Root;Digest=$published.Receipt.package_plan.sha256}) $case.V1Path} '*open or incomplete schema*'
    }finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'publication-failure-rolls-back-exact-v1-pair' {
    $case=New-Case 'rollback';$before=Hash $case.V1Path;$beforeMarker=Hash ($case.V1Path+'.sha256');$p=$null;$blocker=$null
    try{$p=Prepare $case;$blocker=[IO.File]::Open($case.V1Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        Assert-Rejected {Publish-RimePimePackageReceiptV2 $p $case.V1Path} '*being used by another process*'
    }finally{if($null -ne $blocker){$blocker.Dispose()};Close-RimePimePackageReceiptV2Preparation $p}
    Assert-True ((Hash $case.V1Path) -ceq $before -and (Hash ($case.V1Path+'.sha256')) -ceq $beforeMarker) 'Rollback did not restore exact v1 pair.'
}
Check 'publication-rejects-canonical-change-after-preparation' {
    $case=New-Case 'stale-predecessor';$p=Prepare $case
    try{
        [IO.File]::Move($case.V1Path,$case.V1Path+'.stale')
        [IO.File]::Move($case.V1Path+'.sha256',$case.V1Path+'.sha256.stale')
        $replacement=[pscustomobject][ordered]@{
            schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
            closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload';architectures=@('x86','x64')
            package_plan_path='installer/package-plan.json';package_plan_sha256=$p.Receipt.package_plan.sha256;nsis_profile='x86-x64-v1'
            installer_source_path='installer/installer.nsi';installer_source_sha256=$p.Receipt.installer.source_sha256
            installer_path='installer/YIME-test-setup.exe';installer_size=$p.Receipt.installer.bytes
            installer_sha256=$p.Receipt.installer.sha256;sealed_at_utc='2030-01-01T00:00:00.0000000Z'
        }
        $replacementDigest=Seal $replacement $case.V1Path
        Assert-Rejected {Publish-RimePimePackageReceiptV2 $p $case.V1Path} '*no longer matches the sealed v1 predecessor*'
        Assert-True ((Hash $case.V1Path) -ceq $replacementDigest) 'Stale publication changed the replacement canonical receipt.'
    }finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'existing-v2-cannot-be-used-as-v1-predecessor' {
    $case=New-Case 'no-downgrade';$p=$null
    try{$p=Prepare $case;$null=Publish-RimePimePackageReceiptV2 $p $case.V1Path}finally{Close-RimePimePackageReceiptV2Preparation $p}
    $case.V2Output=Join-Path $case.Root '.tmp\dual-product\dp1-package-receipt-v2-no-downgrade-second'
    Assert-Rejected {Prepare $case} '*predecessor*'
}
Check 'runner-requires-explicit-canonical-publication' {
    $runner=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'finalize-rime-pime-package-receipt-v2.ps1'))
    $receiptImport=$runner.IndexOf('Import-Module -Name $module -Force',[StringComparison]::Ordinal)
    $stagingReimport=$runner.IndexOf("Import-Module -Name (Join-Path `$PSScriptRoot 'rime-pime-package-staging.psm1') -Force",[StringComparison]::Ordinal)
    Assert-True ($runner.Contains("if(-not `$PublishCanonical){throw") -and $receiptImport -ge 0 -and
        $stagingReimport -gt $receiptImport) 'Runner lacks explicit publication admission or the post-receipt staging re-import required for PS5/PS7 lease verification.'
}
Check 'staged-builder-refuses-canonical-v2-downgrade' {
    $builder=[IO.File]::ReadAllText((Join-Path $repo 'tools\build-rime-pime-installer.ps1'))
    Assert-True ($builder.Contains("if(`$existingSchema -ceq 'yime-rime-pime-package-build-receipt-v2')") -and
        $builder.Contains('refuses to silently downgrade it to an interim v1 receipt') -and
        $builder.Contains("if([string]`$canonicalBeforeCommit.Value.schema_version -ceq 'yime-rime-pime-package-build-receipt-v2')")) `
        'Staged builder lacks preflight and pre-commit v2 downgrade guards.'
}
Check 'receipt-v2-implementation-has-no-process-launch-surface' {
    foreach($name in @('rime-pime-package-receipt-v2.ps1','rime-pime-package-receipt-v2.psm1','finalize-rime-pime-package-receipt-v2.ps1')){
        $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
        Assert-True ($text -notmatch '(?im)^\s*(Start-Process|Invoke-Expression|Invoke-Command|Start-Job)\b' -and $text -notmatch '(?i)\.exe["'']?\s') "$name exposes a process-launch surface."
    }
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-package-receipt-v2-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    total=$checks.Count;passed=$checks.Count-$failed.Count;failed=$failed.Count;checks=@($checks)
    installer_or_uninstaller_executed=$false;extractor_or_compiler_executed=$false;registry_touched=$false
    installed_product_processes_touched=$false;production_user_data_read_or_written=$false
    helper_sha256=Hash (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')
    runner_sha256=Hash (Join-Path $PSScriptRoot 'finalize-rime-pime-package-receipt-v2.ps1')
}
$resultPath=Join-Path $output 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
if($failed.Count){Write-Host "FAIL: $($failed.Count) of $($checks.Count) receipt-v2 synthetic checks failed. Evidence: $resultPath";exit 1}
Write-Host "PASS: $($checks.Count) receipt-v2 synthetic checks passed without native tool or product execution. Evidence: $resultPath"
