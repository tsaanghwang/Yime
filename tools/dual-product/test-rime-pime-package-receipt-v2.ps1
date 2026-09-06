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
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1') -Force

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
function ConvertFrom-TestJson([string]$Text){
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){return ConvertFrom-Json -InputObject $Text -DateKind String}
    return ConvertFrom-Json -InputObject $Text
}
$currentBuildSchema='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
$legacyBuildSchema='yime-rime-pime-staged-nsis-build-result-v2'
$membershipIntervalSchema='yime-rime-pime-nsis-compiler-membership-interval-v1'
$membershipBuildFields=@(
    'nsis_compiler_membership_interval','nsis_compiler_stage_path',
    'nsis_compiler_stage_file_lease_count','nsis_compiler_stage_directory_lease_count'
)
$requiredBuildLogicSources=@(
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
function New-Case([string]$Name){
    $caseRoot=Join-Path $output ('cases\'+$Name);$root=Join-Path $caseRoot 'repo'
    $installerDir=Join-Path $root 'installer'
    $work=Join-Path $root '.tmp\dual-product\dp1-package-build-stage-fixture'
    $evidence=Join-Path $work 'evidence'
    New-Item -ItemType Directory -Path $installerDir,$evidence,(Join-Path $root '.tmp\dual-product') -Force|Out-Null
    $source=Join-Path $installerDir 'installer.nsi';[IO.File]::WriteAllText($source,'disabled fixture source',[Text.UTF8Encoding]::new($false))
    $installer=Join-Path $installerDir 'YIME-1.0-test-setup.exe';[IO.File]::WriteAllBytes($installer,(New-Object byte[] 65536))
    $installerHash=Hash $installer;$sourceHash=Hash $source
    $planPath=Join-Path $installerDir 'package-plan.json'
    $artifactSpecs=@(Get-RimePimePackageArtifactSpecs -ArchitectureSet @('x86','x64'))
    $planArtifacts=[Collections.Generic.List[object]]::new()
    $artifactByPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    for($artifactIndex=0;$artifactIndex -lt $artifactSpecs.Count;$artifactIndex++){
        $spec=$artifactSpecs[$artifactIndex]
        $artifact=[pscustomobject][ordered]@{
            path=[string]$spec.path;architecture=[string]$spec.architecture
            size=[long](1001+$artifactIndex);sha256=('{0:x64}' -f (1001+$artifactIndex))
        }
        $planArtifacts.Add($artifact);$artifactByPath.Add([string]$artifact.path,$artifact)
    }
    $plan=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-plan-v1';product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'
        architectures=@('x86','x64');hash_algorithm='sha256';sealed_at_utc='2030-01-01T00:00:00.0000000Z'
        artifacts=@($planArtifacts)
    }
    $planDigest=Seal $plan $planPath
    $manifestFiles=[Collections.Generic.List[object]]::new()
    $addManifestRow={
        param([string]$SourcePath,[string]$DestinationPath,[string]$StageScope,[string]$OwnerClass,
            [string]$Architecture,[string]$InstallScope,$Artifact)
        if($null -eq $Artifact){
            $identity=[long](9000+$manifestFiles.Count)
            $bytes=$identity;$sha256=('{0:x64}' -f $identity)
        }else{$bytes=[long]$Artifact.size;$sha256=[string]$Artifact.sha256}
        $manifestFiles.Add([pscustomobject][ordered]@{
            stage_scope=$StageScope;path=$DestinationPath;bytes=$bytes;sha256=$sha256
            owner_class=$OwnerClass;architecture=$Architecture;install_scope=$InstallScope
            origin_class='copied';source_path=$SourcePath
        })
    }
    & $addManifestRow 'version.txt' 'version.txt' 'payload' 'metadata' 'neutral' 'installed' $null
    & $addManifestRow 'backends.json' 'backends.json' 'payload' 'metadata' 'neutral' 'installed' $null
    foreach($mapping in @(
        @('APACHE-2.0.txt','APACHE-2.0.txt'),@('AUTHORS.txt','AUTHORS.txt'),@('LGPL-2.0.txt','LGPL-2.0.txt'),
        @('LICENSE.txt','LICENSE.txt'),@('json/LICENSE.MIT','NLOHMANN-JSON-MIT.txt'),@('NOTICE.md','NOTICE.md'),
        @('LICENSES/PIME-UPSTREAM-LICENSE.txt','PIME-UPSTREAM-LICENSE.txt'),
        @('LICENSES/RIME-BSD-3-Clause.txt','RIME-BSD-3-Clause.txt'),
        @('LICENSES/RIME-FROST-GPL-3.0.txt','RIME-FROST-GPL-3.0.txt'),
        @('LICENSES/RUST-DEPENDENCIES.md','RUST-DEPENDENCIES.md'),@('LICENSES/SIL-OFL-1.1.txt','SIL-OFL-1.1.txt'),
        @('THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'),@('LICENSES/UNICODE-3.0.txt','UNICODE-3.0.txt'))){
        & $addManifestRow ([string]$mapping[0]) ('licenses/'+[string]$mapping[1]) 'payload' 'license' 'neutral' 'installed' $null
    }
    $launcher=$artifactByPath['build/PIMELauncher/PIMELauncher.exe']
    & $addManifestRow $launcher.path 'PIMELauncher.exe' 'payload' 'runtime' 'x86' 'installed' $launcher
    foreach($architecture in @('x86','x64')){
        $prefix=if($architecture -ceq 'x86'){'build'}else{'build64'}
        $service=$artifactByPath[$prefix+'/PIMETextService/Release/PIMETextService.dll']
        $registration=$artifactByPath[$prefix+'/PIMETextService/Release/PIMERegistrationStatus.exe']
        & $addManifestRow $service.path ($architecture+'/PIMETextService.dll') 'payload' 'text-service' $architecture 'installed' $service
        & $addManifestRow $service.path ('PIMETextService_'+$architecture+'.dll') 'bootstrap' 'text-service' $architecture 'transient' $service
        & $addManifestRow $registration.path ('PIMERegistrationStatus_'+$architecture+'.exe') 'bootstrap' 'maintenance' $architecture 'transient' $registration
    }
    foreach($artifact in @($planArtifacts|Where-Object{$_.path.StartsWith('go-backend/build/go-backend/',[StringComparison]::Ordinal)})){
        $suffix=[string]$artifact.path.Substring('go-backend/build/go-backend/'.Length)
        & $addManifestRow $artifact.path ('go-backend/'+$suffix) 'payload' 'backend' 'x64' 'installed' $artifact
    }
    foreach($helper in @(
        'invoke-rime-pime-maintenance.ps1','invoke-rime-pime-target-user.ps1','rime-pime-directed-stop-contract.ps1',
        'rime-pime-ownership.ps1','rime-pime-target-user.ps1')){
        & $addManifestRow ('tools/dual-product/'+$helper) $helper 'bootstrap' 'maintenance' 'neutral' 'transient' $null
    }
    $manifestOrder=Get-RimePimeOrdinalKeys -Values @($manifestFiles) -Selector {
        param($row);return ([string]$row.stage_scope)+"`0"+([string]$row.path)
    }
    $orderedManifestFiles=@($manifestOrder.Keys|ForEach-Object{$manifestOrder.Map[$_]})
    $derivedInputs=@($orderedManifestFiles|ForEach-Object{[pscustomobject][ordered]@{
        destination_path=[string]$_.path;stage_scope=[string]$_.stage_scope
        owner_class=[string]$_.owner_class;install_scope=[string]$_.install_scope
    }})
    $manifestDirectories=@(Get-RimePimeDerivedStageDirectories -CopyFiles $derivedInputs)
    $contentTreeDigest=Get-RimePimeStageContentDigest -Directories $manifestDirectories -Files $orderedManifestFiles
    $generatedOutput=[pscustomobject][ordered]@{
        destination_path='Uninstall.exe';stage_scope='payload';generator_id='nsis-uninstaller-prebuild-v1'
        identity_policy_id='authenticode-rime-pime-uninstaller-v1';owner_class='runtime';architecture='x86';install_scope='installed'
    }
    $specCopyFiles=@($orderedManifestFiles|ForEach-Object{[pscustomobject][ordered]@{
        source_path=[string]$_.source_path;destination_path=[string]$_.path;stage_scope=[string]$_.stage_scope
        owner_class=[string]$_.owner_class;architecture=[string]$_.architecture;install_scope=[string]$_.install_scope
        source_bytes=[long]$_.bytes;source_sha256=[string]$_.sha256
    }})
    $goRelativeFiles=[string[]]@($specCopyFiles|Where-Object{
        $_.source_path -clike 'go-backend/build/go-backend/*'
    }|ForEach-Object{$_.source_path.Substring('go-backend/build/go-backend/'.Length)})
    $goInventoryPath=Join-Path $root 'tools\dual-product\rime-pime-go-payload-inventory.json'
    $goInventory=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-go-payload-inventory-v1';source_root='go-backend/build/go-backend'
        destination_root='go-backend';selection_policy='exact-versioned-path-list-v1';files=@($goRelativeFiles)
    }
    $goInventoryDigest=Seal $goInventory $goInventoryPath
    $payloadSpecPath=Join-Path $evidence 'payload-spec.json'
    $payloadSpec=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-payload-spec-v1';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');phase='declared-copy-inputs-before-generated-output'
        hash_algorithm='sha256';directory_policy='derived-nonempty-only-v1';limits=[pscustomobject][ordered]@{
            max_files=512;max_directories=256;max_total_bytes=536870912;max_file_bytes=134217728;max_path_chars=512;max_path_depth=16
        }
        package_plan_sha256=$planDigest;source_trees=@([pscustomobject][ordered]@{
            source_root='go-backend/build/go-backend';destination_root='go-backend';stage_scope='payload'
            file_count=$goRelativeFiles.Count
            inventory_path='tools/dual-product/rime-pime-go-payload-inventory.json';inventory_sha256=$goInventoryDigest
        });directories=@($manifestDirectories);copy_files=@($specCopyFiles);generated_outputs=@($generatedOutput)
    }
    $payloadSpecDigest=Seal $payloadSpec $payloadSpecPath
    $manifestPath=Join-Path $evidence 'package-stage-content.json'
    $manifest=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-copied-content-v1';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');phase='copied-inputs-awaiting-generated-output'
        hash_algorithm='sha256';directory_policy='derived-nonempty-only-v1';package_plan_sha256=$planDigest
        payload_spec_sha256=$payloadSpecDigest;content_tree_sha256=$contentTreeDigest;directories=@($manifestDirectories)
        files=@($orderedManifestFiles);pending_generated_outputs=@($generatedOutput)
        final_payload_closure=$false
    }
    $manifestDigest=Seal $manifest $manifestPath
    $includeDocument=Get-RimePimeNsisStageIncludeDocument -Manifest $manifest -ContentManifestDigest $manifestDigest `
        -ExpectedPackagePlanDigest $planDigest
    $includePath=Join-Path $evidence 'payload-files.nsh';[IO.File]::WriteAllText($includePath,$includeDocument.Text,[Text.Encoding]::ASCII)
    $includeHash=Hash $includePath;Write-AsciiSidecar $includePath $includeHash
    $installerBytes=New-Object byte[] 65536
    $installerBytes[0]=0x4d;$installerBytes[1]=0x5a
    $bindingOffset=512
    foreach($digest in @($planDigest,$manifestDigest,$contentTreeDigest,$includeHash)){
        $bindingBytes=[Text.Encoding]::Unicode.GetBytes([string]$digest)
        [Array]::Copy($bindingBytes,0,$installerBytes,$bindingOffset,$bindingBytes.Length)
        $bindingOffset+=$bindingBytes.Length+16
    }
    [IO.File]::WriteAllBytes($installer,$installerBytes);$installerHash=Hash $installer
    $payloadReceiptPath=Join-Path $evidence 'payload-files-receipt.json'
    $payloadReceipt=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-nsis-stage-include-v1';product='rime-pime';package_profile='x86-x64-v1'
        architectures=@('x86','x64');phase='copied-inputs-awaiting-generated-output'
        package_plan_sha256=$planDigest;payload_spec_sha256=$payloadSpecDigest
        content_manifest_sha256=$manifestDigest;content_tree_sha256=$contentTreeDigest;include_file='payload-files.nsh'
        include_sha256=$includeHash;include_bytes=[long](Get-Item $includePath).Length;encoding='us-ascii';line_ending='lf'
        macros=@($includeDocument.MacroCounts);unique_stage_file_count=[int]$includeDocument.UniqueStageFileCount
        payload_file_count=[int]$includeDocument.PayloadCount;bootstrap_file_count=[int]$includeDocument.BootstrapCount
        main_payload_file_count=[int]$includeDocument.MainPayloadCount;macro_file_reference_count=[int]$includeDocument.FileReferenceCount
        final_payload_closure=$false
    }
    $payloadReceiptDigest=Seal $payloadReceipt $payloadReceiptPath
    $v1Path=Join-Path $installerDir 'package-build-receipt.json'
    $v1=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload';architectures=@('x86','x64')
        package_plan_path='installer/package-plan.json';package_plan_sha256=$planDigest;nsis_profile='x86-x64-v1'
        installer_source_path='installer/installer.nsi';installer_source_sha256=$sourceHash
        installer_path='installer/YIME-1.0-test-setup.exe';installer_size=65536;installer_sha256=$installerHash
        sealed_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $v1Digest=Seal $v1 $v1Path
    $buildPath=Join-Path $evidence 'build-result.json'
    $compilerStagePath=Join-Path $work 'NSIS'
    New-Item -ItemType Directory -Path (Join-Path $compilerStagePath 'Bin'),(Join-Path $compilerStagePath 'Include') -Force|Out-Null
    $lockRelative='tools/dual-product/rime-pime-postbuild-toolchain-lock.json'
    foreach($relative in $requiredBuildLogicSources){
        if($relative -in @($lockRelative,($lockRelative+'.sha256'))){continue}
        $logicPath=Join-Path $root $relative.Replace('/','\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $logicPath) -Force|Out-Null
        [IO.File]::WriteAllText($logicPath,("fixture build logic: $relative`n"),[Text.UTF8Encoding]::new($false))
    }
    $toolchainLockPath=Join-Path $root $lockRelative.Replace('/','\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $toolchainLockPath) -Force|Out-Null
    [IO.File]::WriteAllBytes($toolchainLockPath,[IO.File]::ReadAllBytes((Join-Path $repo $lockRelative.Replace('/','\'))))
    $toolchainLockDigest=Hash $toolchainLockPath;Write-AsciiSidecar $toolchainLockPath $toolchainLockDigest
    $toolchainLock=ConvertFrom-TestJson ([IO.File]::ReadAllText($toolchainLockPath))
    $makensisDigest=[string]$toolchainLock.nsis.makensis.sha256
    $compilerTreeDigest=[string]$toolchainLock.nsis.compiler_input_closure.tree_sha256
    $buildLogicSources=@()
    for($sourceIndex=0;$sourceIndex -lt $requiredBuildLogicSources.Count;$sourceIndex++){
        $buildLogicSources+=[pscustomobject][ordered]@{
            path=$requiredBuildLogicSources[$sourceIndex]
            sha256=(Hash (Join-Path $root $requiredBuildLogicSources[$sourceIndex].Replace('/','\')))
        }
    }
    $membershipInterval=[pscustomobject][ordered]@{
        schema_version=$membershipIntervalSchema
        armed_before_baseline=$true
        completion_barrier_after_compiler_exit=$true
        unexpected_membership_event_count=0
        notification_batch_count=1
        physical_membership_prevention_claimed=$false
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false
        full_nsis_toolchain_input_closure=$false
    }
    $build=[pscustomobject][ordered]@{
        schema_version=$currentBuildSchema;product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$planDigest
        payload_spec_sha256=$payloadSpecDigest;content_manifest_sha256=$manifestDigest;content_tree_sha256=$contentTreeDigest;payload_nsh_sha256=$includeHash
        copied_file_count=[int]$includeDocument.UniqueStageFileCount;payload_file_count=[int]$includeDocument.PayloadCount
        bootstrap_file_count=[int]$includeDocument.BootstrapCount
        main_payload_file_count=[int]$includeDocument.MainPayloadCount;package_plan_artifact_count=20;package_plan_matching_stage_binding_count=22
        staged_pe_unique_artifact_count=20;staged_pe_path_binding_count=22;staged_pe_architecture_verified_under_read_leases=$true
        executed_build_logic_source_count=16;executed_build_logic_sources=$buildLogicSources
        build_logic_read_lease_count=16;prebuild_leased_input_count=([int]$includeDocument.UniqueStageFileCount+336);candidate_leased=$true
        lease_share_mode='read-only-with-file-share-read';repository_local_compiler_inputs_leased=$true
        repository_local_bare_include_shadowing_closed=$true;makensis_no_current_directory_change=$true
        makensis_user_config_disabled=$true;compiler_working_directory=(Join-Path $compilerStagePath 'Include')
        nsis_compiler_membership_interval=$membershipInterval;nsis_compiler_stage_path=$compilerStagePath
        nsis_compiler_stage_file_lease_count=303;nsis_compiler_stage_directory_lease_count=19
        nsis_toolchain_lock_sha256=$toolchainLockDigest
        nsis_compiler_input_scope='repository-pinned-nsis-distribution-non-os-v1';nsis_compiler_input_tree_sha256=$compilerTreeDigest
        nsis_compiler_input_file_count=303;nsis_compiler_input_directory_count=17
        nsis_compiler_input_read_lease_count=303;nsis_compiler_input_directory_lease_count=19
        nsis_compiler_input_anchor_directory_lease_count=2;nsis_toolchain_control_read_lease_count=2
        nsis_distribution_tree_exact_at_open_and_test=$true;nsis_known_input_file_replacement_closure=$true
        nsis_compiler_input_pre_snapshot_exact=$true
        nsis_compiler_input_post_snapshot_exact=$true;nsis_compiler_input_leases_held_during_makensis=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
        makensis_path=(Join-Path $compilerStagePath 'Bin\makensis.exe');makensis_sha256=$makensisDigest;makensis_path_lease_verified=$true
        unsigned_disabled_build=$true;signing_hook_processes_executed=$false
        signing_host_and_release_signing_pending=$true;path_searched_signing_host_not_executed=$true
        candidate_installer_path=(Join-Path $work 'candidate\YIME-1.0-test-setup.exe')
        candidate_installer_sha256=$installerHash;candidate_installer_bytes=65536;published_installer_path=$installer
        package_build_receipt_path=$v1Path;package_build_receipt_sha256=$v1Digest
        publication_status_at_evidence_seal='prepared-awaiting-receipt-sidecar-commit-marker'
        publication_commit_marker_path=$v1Path+'.sha256';publication_failure_rollback_enabled=$true
        publication_cross_process_lock=$true;publication_lock_path=(Join-Path $installerDir '.rime-pime-publication.lock')
        prebuild_stage_verified=$true;postbuild_stage_verified=$true;prebuild_include_verified=$true;postbuild_include_verified=$true
        installer_raw_byte_search_found_expected_digests=$true;postbuild_extraction_compared_to_stage=$false
        canonical_receipt_binds_stage_evidence=$false;canonical_receipt_v2_finalization_required=$true
        canonical_receipt_v2_finalizer_automatically_invoked=$false;canonical_receipt_v2_requires_sealed_postbuild_result=$true
        v1_receipt_semantics_preserved_until_explicit_v2_finalization=$true
        generated_uninstaller_verified=$false;final_payload_closure=$false;installer_executed=$false;uninstaller_executed=$false
        build_tool_processes_executed=$true;makensis_executed=$true
        installed_product_processes_touched=$false;product_registry_mutated=$false;default_input_method_changed=$false
        production_user_data_read_or_written=$false;installed_yimecore_local12_touched=$false
    }
    $null=Seal $build $buildPath
    $postPath=Join-Path $evidence 'postbuild-result.json'
    $post=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-postbuild-extraction-v2';product='rime-pime';product_version='1.0-test'
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$planDigest
        content_manifest_sha256=$manifestDigest;content_tree_sha256=$contentTreeDigest;payload_nsh_receipt_sha256=$payloadReceiptDigest
        payload_nsh_sha256=$includeHash;installer=[pscustomobject]@{
            sha256=$installerHash;bytes=65536;signature_status='NotSigned';package_plan_raw_byte_binding=$true
            content_manifest_raw_byte_binding=$true;content_tree_raw_byte_binding=$true;payload_nsh_raw_byte_binding=$true;trusted=$false
        }
        generated_uninstaller=[pscustomobject]@{
            sha256=('6'*64);bytes=65536;signature_status='NotSigned';package_plan_raw_byte_binding=$true
            content_manifest_raw_byte_binding=$true;content_tree_raw_byte_binding=$true;payload_nsh_raw_byte_binding=$true;trusted=$false
        }
        toolchain_lock=[pscustomobject]@{sha256=$toolchainLockDigest;toolchain_id=[string]$toolchainLock.toolchain_id}
        seven_zip=[pscustomobject]@{sha256=[string]$toolchainLock.seven_zip.sha256;bytes=[long]$toolchainLock.seven_zip.bytes}
        seven_zip_parser_library=[pscustomobject]@{
            sha256=[string]$toolchainLock.seven_zip.library.sha256;bytes=[long]$toolchainLock.seven_zip.library.bytes
            version='1.0';loaded_library_binding_verified=$true
        }
        makensis=[pscustomobject]@{sha256=$makensisDigest;bytes=[long]$toolchainLock.nsis.makensis.bytes}
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
        nsis_toolchain_lock_sha256=$toolchainLockDigest;nsis_compiler_input_scope='repository-pinned-nsis-distribution-non-os-v1'
        nsis_compiler_input_tree_sha256=$compilerTreeDigest;nsis_compiler_input_file_count=303;nsis_compiler_input_directory_count=17
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
        Root=$root;Work=$work;V1Path=$v1Path;BuildPath=$buildPath;PayloadSpecPath=$payloadSpecPath;ManifestPath=$manifestPath;IncludePath=$includePath
        PayloadReceiptPath=$payloadReceiptPath;PostPath=$postPath;Build=$build;Post=$post;Installer=$installer
        V2Output=Join-Path $root ('.tmp\dual-product\dp1-package-receipt-v2-'+$Name)
    }
}
function Convert-BuildObjectToHistoricalV2($Build,[string]$KeepMembershipField){
    $legacy=ConvertFrom-TestJson ($Build|ConvertTo-Json -Depth 20)
    $legacy.schema_version=$legacyBuildSchema
    foreach($field in $membershipBuildFields){if($field -cne $KeepMembershipField){$legacy.PSObject.Properties.Remove($field)}}
    return $legacy
}
function Convert-CaseBuildToHistoricalV2($Case,[string]$KeepMembershipField){
    $Case.Build=Convert-BuildObjectToHistoricalV2 $Case.Build $KeepMembershipField
    return Seal $Case.Build $Case.BuildPath
}
function Convert-ReceiptFileToHistoricalV2($Case,[string]$ReceiptPath,[string]$BuildLeaf='historical-build-result-v2.json',[string]$KeepMembershipField){
    $legacyBuild=Convert-BuildObjectToHistoricalV2 $Case.Build $KeepMembershipField
    $legacyBuildPath=Join-Path (Split-Path -Parent $Case.BuildPath) $BuildLeaf
    $legacyBuildDigest=Seal $legacyBuild $legacyBuildPath
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($ReceiptPath))
    $receipt.disabled_build.result_path=$legacyBuildPath.Substring($Case.Root.Length+1).Replace('\','/')
    $receipt.disabled_build.result_sha256=$legacyBuildDigest
    $receipt.disabled_build.schema_version=$legacyBuildSchema
    if($null -ne $receipt.sealed_stage.PSObject.Properties['payload_spec_path']){$receipt.sealed_stage.PSObject.Properties.Remove('payload_spec_path')}
    foreach($field in @('go_payload_inventory_path','go_payload_inventory_sha256')){
        if($null -ne $receipt.sealed_stage.PSObject.Properties[$field]){$receipt.sealed_stage.PSObject.Properties.Remove($field)}
    }
    if($null -ne $receipt.disabled_build.PSObject.Properties['nsis_toolchain_lock_path']){$receipt.disabled_build.PSObject.Properties.Remove('nsis_toolchain_lock_path')}
    foreach($field in $membershipBuildFields){$receipt.disabled_build.PSObject.Properties.Remove($field)}
    $null=Seal $receipt $ReceiptPath
    return $receipt
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
        Assert-True ([string]$r.Receipt.disabled_build.schema_version -ceq $currentBuildSchema) 'Receipt did not retain the exact membership-interval build schema.'
        Assert-True (@($case.Build.PSObject.Properties).Count -eq 91) 'Current build fixture no longer mirrors the frozen 91-property result.'
        Assert-True (@($case.Build.nsis_compiler_membership_interval.PSObject.Properties).Count -eq 9) 'Compiler interval fixture is not the exact nine-property object.'
        Assert-True (@($case.Build.executed_build_logic_sources).Count -eq 16) 'Current build fixture does not bind all 16 build-logic sources.'
        Assert-True ([int]$case.Build.package_plan_artifact_count -eq 20 -and
            [int]$case.Build.package_plan_matching_stage_binding_count -eq 22 -and
            [int]$case.Build.staged_pe_unique_artifact_count -eq 20 -and
            [int]$case.Build.staged_pe_path_binding_count -eq 22) 'Fixture no longer exercises distinct artifact and path-binding cardinalities.'
        Assert-True ([int]$case.Build.copied_file_count -eq 42 -and
            [int]$case.Build.prebuild_leased_input_count -eq 378) 'Fixture no longer exercises the current manifest and prebuild lease cardinalities.'
    }finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'package-plan-must-have-the-exact-seven-property-schema' {
    $case=New-Case 'plan-shape';$plan=ConvertFrom-TestJson ([IO.File]::ReadAllText((Join-Path $case.Root 'installer\package-plan.json')))
    $plan.PSObject.Properties.Remove('closure_scope');$null=Seal $plan (Join-Path $case.Root 'installer\package-plan.json')
    Assert-Rejected {Prepare $case} '*package plan*open or incomplete schema*'
}
Check 'package-plan-must-use-the-fixed-twenty-artifact-order' {
    $case=New-Case 'plan-order';$planPath=Join-Path $case.Root 'installer\package-plan.json'
    $plan=ConvertFrom-TestJson ([IO.File]::ReadAllText($planPath));$plan.artifacts[0].path='build/forged.exe'
    $null=Seal $plan $planPath;Assert-Rejected {Prepare $case} '*artifact order, path, or architecture drifted*'
}
Check 'copied-content-manifest-must-have-the-full-sealed-shape' {
    $case=New-Case 'manifest-shape';$manifest=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.ManifestPath))
    $manifest.PSObject.Properties.Remove('phase');$null=Seal $manifest $case.ManifestPath
    Assert-Rejected {Prepare $case} '*copied-content manifest*open or incomplete schema*'
}
Check 'payload-include-receipt-must-have-the-full-deterministic-shape' {
    $case=New-Case 'include-shape';$payload=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.PayloadReceiptPath))
    $payload.PSObject.Properties.Remove('encoding');$null=Seal $payload $case.PayloadReceiptPath
    Assert-Rejected {Prepare $case} '*NSIS stage include receipt*open or incomplete schema*'
}
Check 'payload-spec-must-bind-the-sealed-go-inventory' {
    $case=New-Case 'spec-inventory';$inventoryPath=Join-Path $case.Root 'tools\dual-product\rime-pime-go-payload-inventory.json'
    $inventory=ConvertFrom-TestJson ([IO.File]::ReadAllText($inventoryPath));$inventory.files[0]='forged.exe'
    $null=Seal $inventory $inventoryPath
    Assert-Rejected {Prepare $case} '*Go payload inventory*'
}
Check 'payload-spec-source-to-destination-map-is-not-swappable' {
    $case=New-Case 'spec-map';$spec=(Read-RimePimeSealedJson $case.PayloadSpecPath 'fixture spec').Value
    $manifest=(Read-RimePimeSealedJson $case.ManifestPath 'fixture manifest').Value
    $plan=(Read-RimePimeSealedJson (Join-Path $case.Root 'installer\package-plan.json') 'fixture plan').Value
    $inventorySeal=Read-RimePimeSealedJson (Join-Path $case.Root 'tools\dual-product\rime-pime-go-payload-inventory.json') 'fixture inventory'
    $launcher=$spec.copy_files|Where-Object{$_.destination_path -ceq 'PIMELauncher.exe'}
    $service=$spec.copy_files|Where-Object{$_.destination_path -ceq 'x86/PIMETextService.dll'}
    $swap=[pscustomobject]@{source_path=$launcher.source_path;source_bytes=$launcher.source_bytes;source_sha256=$launcher.source_sha256}
    $launcher.source_path=$service.source_path;$launcher.source_bytes=$service.source_bytes;$launcher.source_sha256=$service.source_sha256
    $service.source_path=$swap.source_path;$service.source_bytes=$swap.source_bytes;$service.source_sha256=$swap.source_sha256
    $manifestLauncher=$manifest.files|Where-Object{$_.path -ceq 'PIMELauncher.exe'}
    $manifestService=$manifest.files|Where-Object{$_.path -ceq 'x86/PIMETextService.dll'}
    $manifestSwap=[pscustomobject]@{source_path=$manifestLauncher.source_path;bytes=$manifestLauncher.bytes;sha256=$manifestLauncher.sha256}
    $manifestLauncher.source_path=$manifestService.source_path;$manifestLauncher.bytes=$manifestService.bytes;$manifestLauncher.sha256=$manifestService.sha256
    $manifestService.source_path=$manifestSwap.source_path;$manifestService.bytes=$manifestSwap.bytes;$manifestService.sha256=$manifestSwap.sha256
    $manifest.content_tree_sha256=Get-RimePimeStageContentDigest @($manifest.directories) @($manifest.files)
    Assert-Rejected {Assert-RimePimeStageSpecManifestBinding $spec $manifest $plan $inventorySeal.Value $inventorySeal.Digest} '*current declaration*'
}
Check 'current-build-hash-arrays-cannot-spoof-scalars' {
    $case=New-Case 'hash-array';$case.Build.candidate_installer_sha256=@([string]$case.Build.candidate_installer_sha256)
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*not a lowercase SHA-256 digest*'
}
Check 'current-build-architectures-must-be-a-flat-string-array' {
    $case=New-Case 'architecture-array';$case.Build.architectures=@(@('x86'),@('x64'))
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*same sealed, disabled*'
}
Check 'current-build-product-and-scope-must-be-string-scalars' {
    $case=New-Case 'scalar-identity';$case.Build.product=@('rime-pime');$case.Build.nsis_compiler_input_scope=@('repository-pinned-nsis-distribution-non-os-v1')
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*product identity*'
}
Check 'predecessor-identity-fields-must-be-string-scalars' {
    $case=New-Case 'predecessor-scalar';$v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path))
    $v1.sealed_at_utc=@([string]$v1.sealed_at_utc);$null=Seal $v1 $case.V1Path
    Assert-Rejected {Prepare $case} '*must be a JSON string*'
}
Check 'current-preparation-requires-the-canonical-installer-source' {
    $case=New-Case 'source-path-preparation';$alternate=Join-Path $case.Root 'installer\alternate.nsi'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes((Join-Path $case.Root 'installer\installer.nsi')))
    $v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path));$v1.installer_source_path='installer/alternate.nsi'
    $v1Digest=Seal $v1 $case.V1Path;$case.Build.package_build_receipt_sha256=$v1Digest;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*non-canonical installer source path*'
}
Check 'disabled-installer-must-contain-the-four-sealed-raw-bindings' {
    $case=New-Case 'installer-bindings';$bytes=[IO.File]::ReadAllBytes($case.Installer);$bytes[512]=0xff
    [IO.File]::WriteAllBytes($case.Installer,$bytes);$installerHash=Hash $case.Installer
    $v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path));$v1.installer_sha256=$installerHash
    $v1Digest=Seal $v1 $case.V1Path;$case.Build.candidate_installer_sha256=$installerHash
    $case.Build.package_build_receipt_sha256=$v1Digest;$case.Post.installer.sha256=$installerHash
    $null=Seal $case.Build $case.BuildPath;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*lacks its sealed package plan raw-byte binding*'
}
foreach($bareVersion in @('v3','v4')){
    Check ('bare-numeric-build-schema-'+$bareVersion+'-is-rejected') {
        $case=New-Case ('sch-'+$bareVersion);$case.Build.schema_version='yime-rime-pime-staged-nsis-build-result-'+$bareVersion
        $null=Seal $case.Build $case.BuildPath
        Assert-Rejected {Prepare $case} '*membership-interval*'
    }
}
Check 'legacy-v2-cannot-enter-new-preparation' {
    $case=New-Case 'legacy-prep';$null=Convert-CaseBuildToHistoricalV2 $case
    Assert-Rejected {Prepare $case} '*current membership-interval build evidence*'
}
foreach($exclusiveField in $membershipBuildFields){
    Check ('legacy-v2-with-'+$exclusiveField+'-is-rejected') {
        $case=New-Case ('legacy-field-'+$membershipBuildFields.IndexOf($exclusiveField));$p=Prepare $case
        Close-RimePimePackageReceiptV2Preparation $p
        $null=Convert-ReceiptFileToHistoricalV2 $case $p.ReceiptPath ('legacy-field-'+$membershipBuildFields.IndexOf($exclusiveField)+'.json') $exclusiveField
        Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*membership-interval*'
    }
}
Check 'strict-reader-retains-read-only-historical-v2-compatibility' {
    $case=New-Case 'legacy-read';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $null=Convert-ReceiptFileToHistoricalV2 $case $p.ReceiptPath
    $read=Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath
    Assert-True ([string]$read.Receipt.disabled_build.schema_version -ceq $legacyBuildSchema) 'Historical v2 was not read under its exact legacy schema.'
}
Check 'strict-reader-rejects-resealed-build-missing-interval' {
    $case=New-Case 'reader-no-int';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $build=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.BuildPath))
    $build.PSObject.Properties.Remove('nsis_compiler_membership_interval')
    $p.Receipt.disabled_build.result_sha256=Seal $build $case.BuildPath
    $null=Seal $p.Receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*membership-interval*'
}
Check 'current-interval-missing-property-is-rejected' {
    $case=New-Case 'int-missing';$case.Build.nsis_compiler_membership_interval.PSObject.Properties.Remove('notification_batch_count')
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case}
}
Check 'current-interval-extra-property-is-rejected' {
    $case=New-Case 'int-extra';$case.Build.nsis_compiler_membership_interval|Add-Member -NotePropertyName unreviewed -NotePropertyValue $true
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case}
}
Check 'current-build-extra-property-is-rejected' {
    $case=New-Case 'build-extra';$case.Build|Add-Member -NotePropertyName unreviewed -NotePropertyValue $true
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case} '*open or incomplete schema*'
}
foreach($intervalFault in @('batch-string','batch-zero','event-nonzero','armed-string','physical-claim')){
    Check ('current-interval-'+$intervalFault+'-is-rejected') {
        $case=New-Case ('int-'+$intervalFault)
        switch($intervalFault){
            'batch-string' {$case.Build.nsis_compiler_membership_interval.notification_batch_count='1'}
            'batch-zero' {$case.Build.nsis_compiler_membership_interval.notification_batch_count=0}
            'event-nonzero' {$case.Build.nsis_compiler_membership_interval.unexpected_membership_event_count=1}
            'armed-string' {$case.Build.nsis_compiler_membership_interval.armed_before_baseline='true'}
            'physical-claim' {$case.Build.nsis_compiler_membership_interval.physical_membership_prevention_claimed=$true}
        }
        $null=Seal $case.Build $case.BuildPath
        Assert-Rejected {Prepare $case} '*membership-interval build evidence*'
    }
}
foreach($stageFault in @('file-value','file-string','directory-value','directory-string')){
    Check ('current-stage-lease-'+$stageFault+'-is-rejected') {
        $case=New-Case ('stage-'+$stageFault)
        switch($stageFault){
            'file-value' {$case.Build.nsis_compiler_stage_file_lease_count=302}
            'file-string' {$case.Build.nsis_compiler_stage_file_lease_count='303'}
            'directory-value' {$case.Build.nsis_compiler_stage_directory_lease_count=18}
            'directory-string' {$case.Build.nsis_compiler_stage_directory_lease_count='19'}
        }
        $null=Seal $case.Build $case.BuildPath
        Assert-Rejected {Prepare $case} '*membership-interval build evidence*'
    }
}
Check 'current-build-logic-critical-source-missing-is-rejected' {
    $case=New-Case 'logic-missing'
    $case.Build.executed_build_logic_sources=@($case.Build.executed_build_logic_sources|Where-Object{$_.path -cne 'tools/dual-product/rime-pime-nsis-compiler-interval.ps1'})
    $case.Build.executed_build_logic_source_count=15;$case.Build.build_logic_read_lease_count=15
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*membership-interval build evidence*'
}
Check 'current-build-logic-duplicate-source-is-rejected' {
    $case=New-Case 'logic-duplicate';$sources=@($case.Build.executed_build_logic_sources)
    $sources[-1]=[pscustomobject][ordered]@{path=[string]$sources[0].path;sha256=[string]$sources[0].sha256}
    $case.Build.executed_build_logic_sources=$sources;$null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*membership-interval build evidence*'
}
Check 'current-staged-pe-artifact-cross-mismatch-is-rejected' {
    $case=New-Case 'pe-artifact-mismatch';$case.Build.staged_pe_unique_artifact_count=22
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*artifact and path-binding sets*'
}
Check 'current-staged-pe-path-binding-cross-mismatch-is-rejected' {
    $case=New-Case 'pe-path-mismatch';$case.Build.staged_pe_path_binding_count=20
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*artifact and path-binding sets*'
}
foreach($stagePathFault in @('outside-root','wrong-parent')){
    Check ('current-compiler-stage-'+$stagePathFault+'-is-rejected') {
        $case=New-Case ('stage-path-'+$stagePathFault)
        if($stagePathFault -ceq 'outside-root'){
            $forged=[IO.Path]::GetFullPath((Join-Path $case.Root '..\dp1-package-build-stage-forged\NSIS'))
        }else{
            $forged=Join-Path $case.Root '.tmp\other\dp1-package-build-stage-forged\NSIS'
        }
        $case.Build.nsis_compiler_stage_path=$forged
        $case.Build.makensis_path=Join-Path $forged 'Bin\makensis.exe'
        $case.Build.compiler_working_directory=Join-Path $forged 'Include'
        $null=Seal $case.Build $case.BuildPath
        Assert-Rejected {Prepare $case} '*inconsistent compiler stage paths*'
    }
}
foreach($pathField in @(
    'candidate_installer_path','published_installer_path','package_build_receipt_path',
    'publication_commit_marker_path','publication_lock_path')){
    Check ('current-'+$pathField+'-identity-is-enforced') {
        $case=New-Case ('path-'+@(
            'candidate_installer_path','published_installer_path','package_build_receipt_path',
            'publication_commit_marker_path','publication_lock_path').IndexOf($pathField))
        $case.Build.$pathField=Join-Path $case.Work ('forged-'+$pathField)
        $null=Seal $case.Build $case.BuildPath
        Assert-Rejected {Prepare $case} '*candidate or publication paths*'
    }
}
Check 'current-build-result-must-come-from-declared-work-root' {
    $case=New-Case 'build-result-path';$forged=Join-Path $case.Work 'other\build-result.json'
    $null=Seal $case.Build $forged;$case.BuildPath=$forged
    Assert-Rejected {Prepare $case} '*declared build root*'
}
Check 'current-build-receipt-path-must-match-actual-predecessor' {
    $case=New-Case 'predecessor-path';$v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path))
    $alternate=Join-Path $case.Work 'evidence\alternate-v1.json';$v1Digest=Seal $v1 $alternate
    $case.V1Path=$alternate;$case.Build.package_build_receipt_sha256=$v1Digest
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*actual predecessor identity*'
}
Check 'current-published-installer-path-must-match-predecessor-installer' {
    $case=New-Case 'predecessor-installer';$alternate=Join-Path $case.Root 'installer\YIME-alternate-setup.exe'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes($case.Installer))
    $v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path));$v1.installer_path='installer/YIME-alternate-setup.exe'
    $v1Digest=Seal $v1 $case.V1Path;$case.Build.package_build_receipt_sha256=$v1Digest
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*actual predecessor identity*'
}
Check 'current-prebuild-lease-formula-is-enforced' {
    $case=New-Case 'prebuild-count';$case.Build.prebuild_leased_input_count=357
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case} '*prebuild leased-input count*'
}
Check 'current-payload-count-tuple-is-bound' {
    $case=New-Case 'payload-count';$case.Build.payload_file_count=1
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case} '*manifest or payload include counts*'
}
Check 'current-manifest-file-count-is-bound' {
    $case=New-Case 'manifest-count';$case.Build.copied_file_count=21;$case.Build.prebuild_leased_input_count=357
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*manifest or payload include counts*'
}
Check 'current-package-binding-cardinalities-are-not-self-reported' {
    $case=New-Case 'package-count'
    $case.Build.package_plan_artifact_count=1;$case.Build.staged_pe_unique_artifact_count=1
    $case.Build.package_plan_matching_stage_binding_count=1;$case.Build.staged_pe_path_binding_count=1
    $null=Seal $case.Build $case.BuildPath;Assert-Rejected {Prepare $case} '*artifact and path-binding sets*'
}
Check 'current-content-manifest-digest-is-bound-to-sealed-payload-receipt' {
    $case=New-Case 'manifest-digest';$case.Build.content_manifest_sha256=('9'*64);$case.Post.content_manifest_sha256=('9'*64)
    $null=Seal $case.Build $case.BuildPath;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*manifest or payload include counts*'
}
Check 'stage-final-payload-boundaries-require-real-booleans' {
    $case=New-Case 'stage-bool';$manifest=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.ManifestPath))
    $manifest.final_payload_closure=0;$manifestDigest=Seal $manifest $case.ManifestPath
    $payload=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.PayloadReceiptPath))
    $payload.final_payload_closure=0;$payload.content_manifest_sha256=$manifestDigest
    $null=Seal $payload $case.PayloadReceiptPath
    $case.Build.content_manifest_sha256=$manifestDigest;$case.Post.content_manifest_sha256=$manifestDigest
    $null=Seal $case.Build $case.BuildPath;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*boundary*'
}
Check 'current-product-identity-is-typed-and-cross-bound' {
    $case=New-Case 'product-identity';$case.Build.product_version=@('1.0-test')
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*product identity*'
}
Check 'current-build-digests-require-exact-sha256' {
    $case=New-Case 'build-hash';$case.Build.content_tree_sha256='not-a-digest'
    $manifest=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.ManifestPath));$manifest.content_tree_sha256='not-a-digest'
    $manifestDigest=Seal $manifest $case.ManifestPath
    $payload=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.PayloadReceiptPath))
    $payload.content_manifest_sha256=$manifestDigest;$payload.content_tree_sha256='not-a-digest'
    $case.Build.content_manifest_sha256=$manifestDigest;$case.Post.content_manifest_sha256=$manifestDigest
    $case.Post.content_tree_sha256='not-a-digest'
    $null=Seal $payload $case.PayloadReceiptPath
    $null=Seal $case.Build $case.BuildPath;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*boundary*'
}
Check 'current-candidate-size-upper-bound-is-enforced' {
    $case=New-Case 'candidate-size';$v1=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path))
    $v1.installer_size=536870913;$v1Digest=Seal $v1 $case.V1Path
    $case.Build.candidate_installer_bytes=536870913;$case.Build.package_build_receipt_sha256=$v1Digest
    $null=Seal $case.Build $case.BuildPath
    Assert-Rejected {Prepare $case} '*candidate size*'
}
Check 'current-build-logic-source-bytes-are-leased-and-verified-at-preparation' {
    $case=New-Case 'logic-bytes'
    [IO.File]::AppendAllText((Join-Path $case.Root 'tools\build-rime-pime-installer.ps1'),'tampered',[Text.UTF8Encoding]::new($false))
    Assert-Rejected {Prepare $case} '*build-logic source differs*'
}
Check 'current-toolchain-lock-content-is-cross-bound-at-preparation' {
    $case=New-Case 'toolchain-lock';$lockPath=Join-Path $case.Root 'tools\dual-product\rime-pime-postbuild-toolchain-lock.json'
    $lock=ConvertFrom-TestJson ([IO.File]::ReadAllText($lockPath));$lock.nsis.compiler_input_closure.tree_sha256=('9'*64)
    $lockDigest=Seal $lock $lockPath
    foreach($relative in @('tools/dual-product/rime-pime-postbuild-toolchain-lock.json','tools/dual-product/rime-pime-postbuild-toolchain-lock.json.sha256')){
        ($case.Build.executed_build_logic_sources|Where-Object{$_.path -ceq $relative}).sha256=(Hash (Join-Path $case.Root $relative.Replace('/','\')))
    }
    $case.Build.nsis_toolchain_lock_sha256=$lockDigest;$case.Post.toolchain_lock.sha256=$lockDigest
    $case.Post.nsis_toolchain_lock_sha256=$lockDigest
    $null=Seal $case.Build $case.BuildPath;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*code-pinned identity*'
}
Check 'strict-reader-cross-binds-current-installer-path-to-build-evidence' {
    $case=New-Case 'reader-installer-path';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $alternate=Join-Path $case.Root 'installer\YIME-alternate-setup.exe'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes($case.Installer))
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath));$receipt.installer.path='installer/YIME-alternate-setup.exe'
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*publication paths contradict*'
}
Check 'strict-reader-rejects-array-wrapped-outer-identity' {
    $case=New-Case 'reader-outer-scalar';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath));$receipt.product=@([string]$receipt.product)
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*must be a JSON string*'
}
Check 'strict-reader-rejects-array-wrapped-summary-identity' {
    $case=New-Case 'reader-summary-scalar';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath));$receipt.predecessor_v1.schema_version=@([string]$receipt.predecessor_v1.schema_version)
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*must be a JSON string*'
}
Check 'strict-reader-requires-the-canonical-installer-source' {
    $case=New-Case 'reader-source-path';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $alternate=Join-Path $case.Root 'installer\alternate.nsi'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes((Join-Path $case.Root 'installer\installer.nsi')))
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath));$receipt.installer.source_path='installer/alternate.nsi'
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*declared build evidence root*'
}
Check 'strict-reader-requires-payload-spec-at-the-build-evidence-root' {
    $case=New-Case 'reader-spec-path';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $alternate=Join-Path (Split-Path -Parent $case.PayloadSpecPath) 'payload-spec-alternate.json'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes($case.PayloadSpecPath));Write-AsciiSidecar $alternate (Hash $alternate)
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath))
    $receipt.sealed_stage.payload_spec_path=$alternate.Substring($case.Root.Length+1).Replace('\','/')
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*declared build evidence root*'
}
Check 'strict-reader-requires-the-fixed-go-inventory-path' {
    $case=New-Case 'reader-inventory-path';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $source=Join-Path $case.Root 'tools\dual-product\rime-pime-go-payload-inventory.json'
    $alternate=Join-Path $case.Root 'tools\dual-product\rime-pime-go-payload-inventory-alternate.json'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes($source));Write-AsciiSidecar $alternate (Hash $alternate)
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath))
    $receipt.sealed_stage.go_payload_inventory_path='tools/dual-product/rime-pime-go-payload-inventory-alternate.json'
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*declared build evidence root*'
}
Check 'strict-reader-requires-the-fixed-toolchain-lock-path' {
    $case=New-Case 'reader-lock-path';$p=Prepare $case;Close-RimePimePackageReceiptV2Preparation $p
    $source=Join-Path $case.Root 'tools\dual-product\rime-pime-postbuild-toolchain-lock.json'
    $alternate=Join-Path $case.Root 'tools\dual-product\rime-pime-postbuild-toolchain-lock-alternate.json'
    [IO.File]::WriteAllBytes($alternate,[IO.File]::ReadAllBytes($source));Write-AsciiSidecar $alternate (Hash $alternate)
    $receipt=ConvertFrom-TestJson ([IO.File]::ReadAllText($p.ReceiptPath))
    $receipt.disabled_build.nsis_toolchain_lock_path='tools/dual-product/rime-pime-postbuild-toolchain-lock-alternate.json'
    $null=Seal $receipt $p.ReceiptPath
    Assert-Rejected {Read-RimePimePackageBuildReceiptV2 $case.Root $p.ReceiptPath} '*declared build evidence root*'
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
Check 'postbuild-bound-digest-array-cannot-spoof-a-string' {
    $case=New-Case 'postbuild-hash-array';$case.Post.package_plan_sha256=@([string]$case.Post.package_plan_sha256);$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*must be a JSON string*'
}
Check 'postbuild-installer-byte-string-cannot-spoof-an-integer' {
    $case=New-Case 'postbuild-installer-bytes';$case.Post.installer.bytes=[string]$case.Post.installer.bytes;$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*invalid bound byte or archive count*'
}
Check 'postbuild-raw-entry-count-string-cannot-spoof-an-integer' {
    $case=New-Case 'postbuild-raw-count';$case.Post.installer_archive.raw_stdout_entry_count='3';$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*invalid bound byte or archive count*'
}
Check 'string-false-cannot-spoof-boolean-boundary' {
    $case=New-Case 'string-false';$case.Post.delivery_admitted='false';$null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*static-only boundaries*'
}
Check 'tampered-sealed-result-sidecar-is-rejected' {
    $case=New-Case 'sidecar';[IO.File]::WriteAllText($case.PostPath+'.sha256',(('0'*64)+'  postbuild-result.json'+"`n"),[Text.Encoding]::ASCII)
    Assert-Rejected {Prepare $case} '*sidecar does not match*'
}
Check 'evolved-postbuild-schema-is-accepted-with-code-pinned-toolchain' {
    $case=New-Case 'schema-evolution';$case.Post|Add-Member -NotePropertyName future_static_field -NotePropertyValue 'ignored-but-result-digest-bound'
    $null=Seal $case.Post $case.PostPath;$p=$null
    try{$p=Prepare $case;Assert-True ($p.Receipt.static_postbuild.toolchain.toolchain_id -ceq $case.Post.toolchain_lock.toolchain_id) 'Code-pinned toolchain identity was not retained.'}
    finally{Close-RimePimePackageReceiptV2Preparation $p}
}
Check 'postbuild-toolchain-id-must-match-code-pinned-lock' {
    $case=New-Case 'toolchain-id';$case.Post.toolchain_lock.toolchain_id='other-pinned-toolchain.3'
    $null=Seal $case.Post $case.PostPath
    Assert-Rejected {Prepare $case} '*code-pinned NSIS toolchain lock*'
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
