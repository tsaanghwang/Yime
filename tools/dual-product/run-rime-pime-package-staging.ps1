[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$PackagePlanPath
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
if([string]::IsNullOrWhiteSpace($PackagePlanPath)){
    $PackagePlanPath=Join-Path $repo 'installer\package-plan.json'
}
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-package-stage-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a new immediate .tmp/dual-product/dp1-package-stage-* evidence root.'
}
if(-not (Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null
$evidence=Join-Path $output 'evidence'
New-Item -ItemType Directory -Path $evidence|Out-Null

$helper=Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1'
Import-Module -Name $helper -Force
$package=Read-RimePimePackagePlan -RepoRoot $repo -PlanPath $PackagePlanPath -VerifyArtifacts
$version=[IO.File]::ReadAllText((Join-Path $repo 'version.txt')).Trim()
$declaration=Get-RimePimeCurrentPackageStageDeclaration $package
$specPath=Join-Path $evidence 'payload-spec.json'
$spec=Write-RimePimePackageStageSpec -SourceRoot $repo -SpecPath $specPath -ProductVersion $version `
    -PackagePlanDigest $package.Digest -CopyBindings $declaration.CopyBindings `
    -ClosedSourceTrees $declaration.ClosedSourceTrees -GeneratedOutputs $declaration.GeneratedOutputs

$stageResult=New-RimePimePackageCopyStage -SourceRoot $repo -StageRoot (Join-Path $output 'stage') `
    -AllowedStageParent $output -SpecPath $specPath -ExpectedSpecDigest $spec.Digest `
    -ContentManifestPath (Join-Path $evidence 'package-stage-content.json') `
    -ObservationPath (Join-Path $evidence 'package-stage-observation.json')
$content=Read-RimePimeCopiedContentManifest $stageResult.ContentManifestPath $stageResult.ContentManifestDigest
$planBindings=Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest
$stagedVersion=Assert-RimePimeStagedProductVersion -StageRoot $stageResult.StageRoot -ContentManifest $content.Manifest
if($stagedVersion -cne $version){throw 'Staged version differs from the requested product version.'}
$payloadFiles=@($content.Manifest.files|Where-Object{$_.stage_scope -ceq 'payload'})
$bootstrapFiles=@($content.Manifest.files|Where-Object{$_.stage_scope -ceq 'bootstrap'})
$goTree=@($spec.Spec.source_trees|Where-Object{$_.source_root -ceq 'go-backend/build/go-backend'})

$summary=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-current-package-copy-stage-result-v1'
    generated_at_utc=[DateTime]::UtcNow.ToString('o')
    product='rime-pime'
    product_version=$version
    package_profile='x86-x64-v1'
    architectures=@('x86','x64')
    evidence_level='source-verified-isolated-copy-stage-before-generated-uninstaller-not-nsis-or-installed'
    package_plan_path=$package.Path
    package_plan_sha256=$package.Digest
    payload_spec_path=$spec.Path
    payload_spec_sha256=$spec.Digest
    stage_root=$stageResult.StageRoot
    content_manifest_path=$stageResult.ContentManifestPath
    content_manifest_sha256=$stageResult.ContentManifestDigest
    observation_path=$stageResult.ObservationPath
    observation_sha256=$stageResult.ObservationDigest
    copied_file_count=$stageResult.Verification.file_count
    installed_namespace_file_count=$payloadFiles.Count
    bootstrap_namespace_file_count=$bootstrapFiles.Count
    closed_go_source_tree_file_count=$(if($goTree.Count -eq 1){[int]$goTree[0].file_count}else{-1})
    package_plan_artifact_count=[int]$planBindings.package_plan_artifact_count
    package_plan_matching_stage_binding_count=[int]$planBindings.matching_stage_binding_count
    directory_count=$stageResult.Verification.directory_count
    total_bytes=$stageResult.Verification.total_bytes
    content_tree_sha256=$stageResult.Verification.content_tree_sha256
    local_observation_sha256=$stageResult.Verification.local_observation_sha256
    verification_passes=2
    source_tree_wildcard_used_for_copy=$false
    source_set_selected_by_recursive_enumeration=$false
    source_set_selected_by_versioned_inventory=$true
    generated_uninstaller_present=$false
    generated_uninstaller_verified=$false
    final_payload_closure=$false
    nsis_consumes_stage=$false
    postbuild_extraction_compared_to_stage=$false
    package_or_installed_state_changed=$false
    actual_installer_or_uninstaller_executed=$false
    registry_or_process_touched=$false
    default_input_method_changed=$false
    production_user_data_read_or_written=$false
    installed_yimecore_local12_touched=$false
    hard_blocks_remain=$true
    helper_module_sha256=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant()
    helper_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    runner_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$summaryPath=Join-Path $evidence 'result.json'
$summaryDigest=Write-RimePimeStageSealedJson $summary $summaryPath
Write-Host "PASS: staged $($summary.copied_file_count) explicit Rime/PIME copy inputs ($($summary.installed_namespace_file_count) installed, $($summary.bootstrap_namespace_file_count) bootstrap); final closure remains blocked. Evidence: $summaryPath ($summaryDigest)"
