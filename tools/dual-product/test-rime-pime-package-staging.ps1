[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-package-staging-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a new immediate .tmp/dual-product/dp1-package-staging-* fixture root.'
}
if(-not (Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null

$helperPath=Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1'
$helperHash=(Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant()
$beforeFunctions=@(Get-Command -CommandType Function|ForEach-Object Name)
function Get-YimePimePayloadFileRecord { throw 'ambient-function-spoof-must-not-run' }
$errorActionBeforeImport=$ErrorActionPreference
Import-Module -Name $helperPath -Force

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action,[string]$Like='*'){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notlike $Like){throw "Unexpected rejection: $($_.Exception.Message)"};return}
    throw 'Unsafe staging case was accepted.'
}
function Write-FixtureFile([string]$Path,[string]$Text){
    $parent=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent|Out-Null}
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Write-FixtureInventory([string]$Source,[string[]]$Files){
    $inventoryPath=Join-Path $Source 'controls\go-payload-inventory.json'
    $inventory=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-go-payload-inventory-v1'
        source_root='go-backend/build/go-backend'
        destination_root='go-backend'
        selection_policy='exact-versioned-path-list-v1'
        files=@($Files)
    }
    $digest=Write-RimePimeStageSealedJson $inventory $inventoryPath
    return [pscustomobject]@{Path='controls/go-payload-inventory.json';Digest=$digest}
}

function New-StagingCase([string]$Name){
    $root=Join-Path $output $Name
    $source=Join-Path $root 'source'
    $evidence=Join-Path $root 'evidence'
    New-Item -ItemType Directory -Path $source,$evidence|Out-Null
    Write-FixtureFile (Join-Path $source 'go-backend\build\go-backend\app.bin') 'fixture executable bytes'
    Write-FixtureFile (Join-Path $source 'go-backend\build\go-backend\data\config.json') '{"fixture":true}'
    Write-FixtureFile (Join-Path $source 'root.txt') 'fixture root metadata'
    Write-FixtureFile (Join-Path $source 'helper.ps1') '# fixture helper'
    $bindings=@(
        [pscustomobject][ordered]@{source_path='go-backend/build/go-backend/app.bin';destination_path='go-backend/app.bin';stage_scope='payload';owner_class='backend';architecture='x64';install_scope='installed'},
        [pscustomobject][ordered]@{source_path='go-backend/build/go-backend/data/config.json';destination_path='go-backend/data/config.json';stage_scope='payload';owner_class='backend';architecture='neutral';install_scope='installed'},
        [pscustomobject][ordered]@{source_path='root.txt';destination_path='root.txt';stage_scope='payload';owner_class='metadata';architecture='neutral';install_scope='installed'},
        [pscustomobject][ordered]@{source_path='helper.ps1';destination_path='helper.ps1';stage_scope='bootstrap';owner_class='maintenance';architecture='neutral';install_scope='transient'}
    )
    $inventory=Write-FixtureInventory $source @('app.bin','data/config.json')
    $trees=@([pscustomobject][ordered]@{
        source_root='go-backend/build/go-backend';destination_root='go-backend';stage_scope='payload'
        inventory_path=$inventory.Path;inventory_sha256=$inventory.Digest
    })
    $generated=@([pscustomobject][ordered]@{
        destination_path='Uninstall.exe';stage_scope='payload';generator_id='nsis-uninstaller-prebuild-v1'
        identity_policy_id='authenticode-rime-pime-uninstaller-v1';owner_class='runtime';architecture='x86';install_scope='installed'
    })
    $specPath=Join-Path $evidence 'payload-spec.json'
    $spec=Write-RimePimePackageStageSpec -SourceRoot $source -SpecPath $specPath -ProductVersion '1.4.0-test' `
        -PackagePlanDigest ('1'*64) -CopyBindings $bindings -ClosedSourceTrees $trees -GeneratedOutputs $generated
    return [pscustomobject]@{
        Root=$root;Source=$source;Evidence=$evidence;SpecPath=$specPath;SpecDigest=$spec.Digest
        InventoryPath=(Join-Path $source $inventory.Path.Replace('/','\'));InventoryDigest=$inventory.Digest
    }
}

function New-CaseStage($Case,[string]$Name='stage'){
    $content=Join-Path $Case.Evidence ($Name+'-content.json')
    $observation=Join-Path $Case.Evidence ($Name+'-observation.json')
    return New-RimePimePackageCopyStage -SourceRoot $Case.Source -StageRoot (Join-Path $Case.Root $Name) `
        -AllowedStageParent $Case.Root -SpecPath $Case.SpecPath -ExpectedSpecDigest $Case.SpecDigest `
        -ContentManifestPath $content -ObservationPath $observation
}

Check 'definitions-only-helper-loads-without-product-action' {
    Assert-True ((Get-Command New-RimePimePackageCopyStage -CommandType Function -ErrorAction Stop) -ne $null) 'Stage function is missing.'
    Assert-True ((Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $helperHash) 'Helper changed while loading.'
    Assert-True ((@($beforeFunctions|Where-Object{$_ -like 'New-RimePimePackageCopyStage'})).Count -eq 0) 'Fixture shell was already contaminated.'
    Assert-True ($ErrorActionPreference -ceq $errorActionBeforeImport) 'Module import changed the caller error-action preference.'
}

Check 'canonical-stage-json-is-byte-stable' {
    $value=[pscustomobject][ordered]@{z='引号"与反斜线\';a=@(1,$true,$false,$null,"line`nend")}
    $expected='{"z":"引号\"与反斜线\\","a":[1,true,false,null,"line\nend"]}'
    Assert-True ((ConvertTo-RimePimeStageCanonicalJson $value) -ceq $expected) 'Canonical JSON bytes changed.'
}

Check 'sealed-spec-builds-and-verifies-exact-copy-stage' {
    $case=New-StagingCase 'positive'
    $stage=New-CaseStage $case
    Assert-True ($stage.Verification.passed -and $stage.Verification.file_count -eq 4 -and
        $stage.Verification.directory_count -eq 2) 'Positive stage counts are wrong.'
    Assert-True (-not $stage.Verification.final_payload_closure -and
        $stage.Verification.pending_generated_output_count -eq 1) 'Pre-generated-output boundary was lost.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stage.StageRoot 'payload\Uninstall.exe'))) 'Uninstaller placeholder was materialized.'
}

Check 'copied-architecture-inputs-remain-bound-to-the-sealed-package-plan' {
    $case=New-StagingCase 'plan-binding-positive'
    $stage=New-CaseStage $case
    $content=Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $stage.ContentManifestDigest
    $row=@($content.Manifest.files|Where-Object{[string]$_.source_path -ceq 'go-backend/build/go-backend/app.bin'})[0]
    $package=[pscustomobject]@{
        Digest=('1'*64)
        Plan=[pscustomobject]@{artifacts=@([pscustomobject]@{
            path=[string]$row.source_path;architecture='x64';size=[long]$row.bytes;sha256=[string]$row.sha256
        })}
    }
    $verified=Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest
    Assert-True ($verified.passed -and $verified.package_plan_artifact_count -eq 1 -and
        $verified.matching_stage_binding_count -eq 1) 'Package-plan to stage binding counts are wrong.'
    $package.Plan.artifacts[0].sha256=('2'*64)
    Assert-Rejected {
        Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest
    } '*differs from its sealed package-plan artifact*'
}

Check 'isolated-module-ignores-ambient-function-spoof' {
    $case=New-StagingCase 'ambient-spoof'
    $stage=New-CaseStage $case
    Assert-True ($stage.Verification.passed) 'An ambient same-name function replaced the module dependency.'
}

Check 'preexisting-source-extra-is-rejected-by-versioned-inventory' {
    $case=New-StagingCase 'inventory-preexisting-extra'
    Write-FixtureFile (Join-Path $case.Source 'go-backend\build\go-backend\already-there.log') 'unlisted before a new spec'
    Assert-Rejected {
        Read-RimePimeGoPayloadInventory -SourceRoot $case.Source `
            -InventoryPath 'controls/go-payload-inventory.json' -ExpectedDigest $case.InventoryDigest -VerifySourceTree
    } '*exact versioned inventory*'
}

Check 'stale-versioned-inventory-sidecar-is-rejected' {
    $case=New-StagingCase 'inventory-stale-sidecar'
    [IO.File]::AppendAllText($case.InventoryPath," `n",(New-Object Text.UTF8Encoding($false)))
    Assert-Rejected {
        Read-RimePimeGoPayloadInventory -SourceRoot $case.Source `
            -InventoryPath 'controls/go-payload-inventory.json' -ExpectedDigest $case.InventoryDigest
    } '*does not match its JSON bytes*'
}

Check 'unordered-versioned-inventory-is-rejected' {
    $case=New-StagingCase 'inventory-order'
    $sealed=Read-RimePimeSealedJson $case.InventoryPath 'fixture inventory'
    $sealed.Value.files=@('data/config.json','app.bin')
    $digest=Write-RimePimeStageSealedJson $sealed.Value $case.InventoryPath
    Assert-Rejected {
        Read-RimePimeGoPayloadInventory -SourceRoot $case.Source `
            -InventoryPath 'controls/go-payload-inventory.json' -ExpectedDigest $digest
    } '*canonical ordinal order*'
}

Check 'portable-content-digest-does-not-contain-local-file-identity' {
    $case=New-StagingCase 'portable-digest'
    $first=New-CaseStage $case 'stage-a'
    $second=New-CaseStage $case 'stage-b'
    Assert-True ($first.Verification.content_tree_sha256 -ceq $second.Verification.content_tree_sha256) 'Portable content digest changed across copies.'
    Assert-True ($first.Verification.local_observation_sha256 -cne $second.Verification.local_observation_sha256) 'Local file-identity observation did not change across copies.'
}

Check 'new-file-in-closed-source-tree-is-rejected-after-spec-seal' {
    $case=New-StagingCase 'source-extra'
    Write-FixtureFile (Join-Path $case.Source 'go-backend\build\go-backend\backup.log') 'unlisted'
    Assert-Rejected {New-CaseStage $case} '*exact versioned inventory*'
}

Check 'changed-source-file-is-rejected-after-spec-seal' {
    $case=New-StagingCase 'source-changed'
    Write-FixtureFile (Join-Path $case.Source 'root.txt') 'changed after sealing'
    Assert-Rejected {New-CaseStage $case} '*does not match the sealed stage spec*'
}

Check 'missing-source-file-is-rejected-after-spec-seal' {
    $case=New-StagingCase 'source-missing'
    Remove-Item -LiteralPath (Join-Path $case.Source 'go-backend\build\go-backend\app.bin')
    Assert-Rejected {New-CaseStage $case} '*missing*'
}

Check 'alternate-data-stream-on-source-is-rejected-before-spec-seal' {
    $caseRoot=Join-Path $output 'source-ads'
    $source=Join-Path $caseRoot 'source';$evidence=Join-Path $caseRoot 'evidence'
    New-Item -ItemType Directory -Path $source,$evidence|Out-Null
    Write-FixtureFile (Join-Path $source 'go-backend\build\go-backend\app.bin') 'fixture'
    Set-Content -LiteralPath ((Join-Path $source 'go-backend\build\go-backend\app.bin')+':Zone.Identifier') -Value 'metadata' -Encoding UTF8
    $bindings=@([pscustomobject][ordered]@{source_path='go-backend/build/go-backend/app.bin';destination_path='go-backend/app.bin';stage_scope='payload';owner_class='backend';architecture='x64';install_scope='installed'})
    $inventory=Write-FixtureInventory $source @('app.bin')
    $trees=@([pscustomobject][ordered]@{
        source_root='go-backend/build/go-backend';destination_root='go-backend';stage_scope='payload'
        inventory_path=$inventory.Path;inventory_sha256=$inventory.Digest
    })
    $generated=@([pscustomobject][ordered]@{destination_path='Uninstall.exe';stage_scope='payload';generator_id='nsis-uninstaller-prebuild-v1';identity_policy_id='authenticode-rime-pime-uninstaller-v1';owner_class='runtime';architecture='x86';install_scope='installed'})
    Assert-Rejected {
        Write-RimePimePackageStageSpec -SourceRoot $source -SpecPath (Join-Path $evidence 'spec.json') `
            -ProductVersion '1.4.0-test' -PackagePlanDigest ('1'*64) -CopyBindings $bindings `
            -ClosedSourceTrees $trees -GeneratedOutputs $generated
    } '*Alternate data stream*'
}

Check 'wrong-external-spec-digest-is-rejected' {
    $case=New-StagingCase 'wrong-spec-digest'
    Assert-Rejected {
        New-RimePimePackageCopyStage -SourceRoot $case.Source -StageRoot (Join-Path $case.Root 'stage') `
            -AllowedStageParent $case.Root -SpecPath $case.SpecPath -ExpectedSpecDigest ('2'*64) `
            -ContentManifestPath (Join-Path $case.Evidence 'content.json') -ObservationPath (Join-Path $case.Evidence 'observation.json')
    } '*externally supplied digest*'
}

Check 'case-folded-destination-duplicate-is-rejected' {
    $case=New-StagingCase 'case-duplicate'
    $sealed=Read-RimePimeSealedJson $case.SpecPath 'fixture spec'
    $first=$sealed.Value.copy_files[0]
    $duplicate=[pscustomobject][ordered]@{
        source_path=$first.source_path;destination_path=([string]$first.destination_path).ToUpperInvariant()
        stage_scope=$first.stage_scope;owner_class=$first.owner_class;architecture=$first.architecture
        install_scope=$first.install_scope;source_bytes=$first.source_bytes;source_sha256=$first.source_sha256
    }
    $sealed.Value.copy_files=@($first,$duplicate)+@($sealed.Value.copy_files|Select-Object -Skip 1)
    $digest=Write-RimePimeStageSealedJson $sealed.Value $case.SpecPath
    Assert-Rejected {Read-RimePimePackageStageSpec $case.Source $case.SpecPath $digest -VerifySources} '*duplicate*'
}

Check 'extra-copied-file-is-rejected' {
    $case=New-StagingCase 'stage-extra'
    $stage=New-CaseStage $case
    Write-FixtureFile (Join-Path $stage.StageRoot 'payload\go-backend\unknown.dat') 'unknown'
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*Unlisted staged file*'
}

Check 'extra-empty-stage-directory-is-rejected' {
    $case=New-StagingCase 'stage-empty-dir'
    $stage=New-CaseStage $case
    New-Item -ItemType Directory -Path (Join-Path $stage.StageRoot 'payload\empty')|Out-Null
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*empty staged directory*'
}

Check 'modified-copied-file-is-rejected' {
    $case=New-StagingCase 'stage-changed'
    $stage=New-CaseStage $case
    Write-FixtureFile (Join-Path $stage.StageRoot 'payload\root.txt') 'stage changed'
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*content mismatch*'
}

Check 'missing-copied-file-is-rejected' {
    $case=New-StagingCase 'stage-missing'
    $stage=New-CaseStage $case
    Remove-Item -LiteralPath (Join-Path $stage.StageRoot 'payload\root.txt')
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*missing files*'
}

Check 'generated-uninstaller-placeholder-in-copy-stage-is-rejected' {
    $case=New-StagingCase 'uninstaller-placeholder'
    $stage=New-CaseStage $case
    Write-FixtureFile (Join-Path $stage.StageRoot 'payload\Uninstall.exe') 'placeholder'
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*Unlisted staged file*'
}

Check 'missing-content-manifest-sidecar-is-rejected' {
    $case=New-StagingCase 'manifest-sidecar-missing'
    $stage=New-CaseStage $case
    Remove-Item -LiteralPath ($stage.ContentManifestPath+'.sha256')
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*sidecar is missing*'
}

Check 'stale-content-manifest-sidecar-is-rejected' {
    $case=New-StagingCase 'manifest-sidecar-stale'
    $stage=New-CaseStage $case
    [IO.File]::AppendAllText($stage.ContentManifestPath," `n",(New-Object Text.UTF8Encoding($false)))
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*does not match its JSON bytes*'
}

Check 'numeric-false-final-closure-is-rejected' {
    $case=New-StagingCase 'manifest-numeric-false'
    $stage=New-CaseStage $case
    $sealed=Read-RimePimeSealedJson $stage.ContentManifestPath 'fixture content manifest'
    $sealed.Value.final_payload_closure=0
    $digest=Write-RimePimeStageSealedJson $sealed.Value $stage.ContentManifestPath
    Assert-Rejected {Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $digest} '*identity or evidence boundary*'
}

Check 'invalid-content-file-semantics-are-rejected' {
    $case=New-StagingCase 'manifest-file-semantics'
    $stage=New-CaseStage $case
    $sealed=Read-RimePimeSealedJson $stage.ContentManifestPath 'fixture content manifest'
    $sealed.Value.files[0].owner_class='foreign'
    $digest=Write-RimePimeStageSealedJson $sealed.Value $stage.ContentManifestPath
    Assert-Rejected {Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $digest} '*file record is invalid*'
}

Check 'invalid-content-directory-semantics-are-rejected' {
    $case=New-StagingCase 'manifest-directory-semantics'
    $stage=New-CaseStage $case
    $sealed=Read-RimePimeSealedJson $stage.ContentManifestPath 'fixture content manifest'
    $sealed.Value.directories[0].removal_policy='foreign-delete'
    $digest=Write-RimePimeStageSealedJson $sealed.Value $stage.ContentManifestPath
    Assert-Rejected {Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $digest} '*directory record is invalid*'
}

Check 'invalid-pending-uninstaller-semantics-are-rejected' {
    $case=New-StagingCase 'manifest-uninstaller-semantics'
    $stage=New-CaseStage $case
    $sealed=Read-RimePimeSealedJson $stage.ContentManifestPath 'fixture content manifest'
    $sealed.Value.pending_generated_outputs[0].generator_id='untrusted-generator'
    $digest=Write-RimePimeStageSealedJson $sealed.Value $stage.ContentManifestPath
    Assert-Rejected {Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $digest} '*uninstaller contract is invalid*'
}

Check 'invalid-content-product-version-is-rejected' {
    $case=New-StagingCase 'manifest-product-version'
    $stage=New-CaseStage $case
    $sealed=Read-RimePimeSealedJson $stage.ContentManifestPath 'fixture content manifest'
    $sealed.Value.product_version='bad version with spaces'
    $digest=Write-RimePimeStageSealedJson $sealed.Value $stage.ContentManifestPath
    Assert-Rejected {Read-RimePimeCopiedContentManifest $stage.ContentManifestPath $digest} '*identity or evidence boundary*'
}

Check 'hard-linked-copied-file-is-rejected' {
    $case=New-StagingCase 'stage-hardlink'
    $stage=New-CaseStage $case
    New-Item -ItemType HardLink -Path (Join-Path $case.Root 'outside-hardlink.bin') `
        -Target (Join-Path $stage.StageRoot 'payload\root.txt')|Out-Null
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*Hard-linked*'
}

Check 'alternate-data-stream-on-copied-file-is-rejected' {
    $case=New-StagingCase 'stage-ads'
    $stage=New-CaseStage $case
    Set-Content -LiteralPath ((Join-Path $stage.StageRoot 'payload\root.txt')+':private') -Value 'hidden' -Encoding UTF8
    Assert-Rejected {Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest} '*Alternate data stream*'
}

Check 'second-pass-insertion-is-rejected' {
    $case=New-StagingCase 'stage-race'
    $stage=New-CaseStage $case
    Assert-Rejected {
        Test-RimePimePackageCopyStage $stage.StageRoot $stage.ContentManifestPath $stage.ContentManifestDigest -BetweenPassHook {
            param($root)
            Write-FixtureFile (Join-Path $root 'payload\raced.bin') 'race'
        }
    } '*Unlisted staged file*'
}

Check 'stage-root-must-be-fresh-and-immediate' {
    $case=New-StagingCase 'stage-location'
    $existing=Join-Path $case.Root 'stage';New-Item -ItemType Directory -Path $existing|Out-Null
    Assert-Rejected {
        New-RimePimePackageCopyStage -SourceRoot $case.Source -StageRoot $existing -AllowedStageParent $case.Root `
            -SpecPath $case.SpecPath -ExpectedSpecDigest $case.SpecDigest `
            -ContentManifestPath (Join-Path $case.Evidence 'content.json') -ObservationPath (Join-Path $case.Evidence 'observation.json')
    } '*new immediate child*'
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-package-staging-test-v1';generated_at=[DateTime]::UtcNow.ToString('o')
    test_level='isolated-filesystem-copy-stage-only';checks_count=$checks.Count;passed=$failed.Count -eq 0
    portable_content_and_local_observation_digests_separated=$true
    source_set_selected_by_recursive_enumeration=$false;source_set_selected_by_versioned_inventory=$true
    dependencies_loaded_in_isolated_module_scope=$true
    generated_uninstaller_verified=$false;nsis_consumes_stage=$false;postbuild_extraction_verified=$false
    final_payload_closure=$false;actual_installer_or_uninstaller_executed=$false
    registry_or_process_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
    helper_module_sha256=$helperHash
    helper_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks=@($checks)
}
$resultPath=Join-Path $output 'result.json'
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
if($failed.Count){foreach($failure in $failed){Write-Host "FAIL: $($failure.name): $($failure.error)"};throw "$($failed.Count) of $($checks.Count) staging checks failed."}
Write-Host "PASS: $($checks.Count) isolated package-staging checks passed. Evidence: $resultPath"
