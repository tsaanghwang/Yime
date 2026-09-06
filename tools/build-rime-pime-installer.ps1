[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$PackagePlanPath,
    [string]$ReceiptPath,
    [string]$MakensisPath = 'C:\Program Files (x86)\NSIS\Bin\makensis.exe',
    [string]$BuildEvidenceRoot,
    [switch]$RefreshReceiptOnly
)

$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=Split-Path -Parent $PSScriptRoot}
foreach ($name in @(
    'YIME_SIGN_CERT_SHA1',
    'YIME_RELEASE_SIGNING_REQUIRED',
    'YIME_SIGNTOOL_EXE',
    'YIME_TIMESTAMP_URL'
)) {
    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "build-rime-pime-installer.ps1 only builds an unsigned disabled package; clear process signing variable $name and use the protected release workflow for signing."
    }
}
$root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if (-not $PackagePlanPath) { $PackagePlanPath=Join-Path $root 'installer\package-plan.json' }
if (-not $ReceiptPath) { $ReceiptPath=Join-Path $root 'installer\package-build-receipt.json' }
$ReceiptPath=[IO.Path]::GetFullPath($ReceiptPath)
$canonicalReceipt=Join-Path $root 'installer\package-build-receipt.json'
if($ReceiptPath -ine $canonicalReceipt){throw 'The staged builder only publishes the canonical installer/package-build-receipt.json bundle.'}
if($RefreshReceiptOnly){
    throw 'RefreshReceiptOnly is not admitted after staged NSIS consumption; rebuild and reverify one fresh candidate instead.'
}
$stagingModule=Join-Path $root 'tools\dual-product\rime-pime-package-staging.psm1'
$nsisStageModule=Join-Path $root 'tools\dual-product\rime-pime-nsis-stage.psm1'
$stagedBuildModule=Join-Path $root 'tools\dual-product\rime-pime-staged-installer-build.psm1'
$nsisToolchainModule=Join-Path $root 'tools\dual-product\rime-pime-nsis-toolchain-closure.psm1'
$buildLogicPaths=@(
    $PSCommandPath,
    $stagingModule,
    (Join-Path $root 'tools\dual-product\rime-pime-package-staging.ps1'),
    (Join-Path $root 'tools\dual-product\rime-pime-package-plan.ps1'),
    (Join-Path $root 'tools\dual-product\rime-pime-payload-closure.ps1'),
    (Join-Path $root 'tools\verify-pe-architectures.ps1'),
    $nsisStageModule,
    (Join-Path $root 'tools\dual-product\rime-pime-nsis-stage.ps1'),
    $stagedBuildModule,
    (Join-Path $root 'tools\dual-product\rime-pime-staged-installer-build.ps1'),
    $nsisToolchainModule,
    (Join-Path $root 'tools\dual-product\rime-pime-nsis-membership-monitor-v1.ps1'),
    (Join-Path $root 'tools\dual-product\rime-pime-nsis-compiler-interval.ps1'),
    (Join-Path $root 'tools\dual-product\rime-pime-nsis-toolchain-closure.ps1'),
    (Join-Path $root 'tools\dual-product\rime-pime-postbuild-toolchain-lock.json'),
    (Join-Path $root 'tools\dual-product\rime-pime-postbuild-toolchain-lock.json.sha256')
)
function Get-RimePimeBootstrapStreamDigest([IO.FileStream]$Stream){
    $Stream.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$Stream.Position=0}
}
function Assert-RimePimeBootstrapPlainPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "Build-logic source is missing: $full"}
    for($cursor=$full;$cursor;$cursor=Split-Path -Parent $cursor){
        if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
            throw "Build-logic source traverses a reparse point before import: $cursor"
        }
        if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
    }
    $item=Get-Item -LiteralPath $full -Force
    if([string]$item.LinkType -ceq 'HardLink'){
        throw "Hard-linked build-logic source rejected before import: $full"
    }
    $streams=@(Get-Item -LiteralPath $full -Stream * -Force)
    if($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA'){
        throw "Alternate data stream on build-logic source rejected before import: $full"
    }
}
$buildLogicLeases=[Collections.Generic.List[object]]::new()
try{
foreach($path in $buildLogicPaths){
    $full=[IO.Path]::GetFullPath($path)
    if(@($buildLogicLeases|Where-Object{$_.Path -ieq $full}).Count -ne 0){throw "Duplicate build-logic source: $full"}
    Assert-RimePimeBootstrapPlainPath $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        Assert-RimePimeBootstrapPlainPath $full
        $buildLogicLeases.Add([pscustomobject]@{
            Path=$full;Stream=$stream;Sha256=(Get-RimePimeBootstrapStreamDigest $stream)
            Bytes=[long]$stream.Length;FileId=''
        })
        $stream=$null
    }finally{if($null -ne $stream){$stream.Dispose()}}
}
Import-Module -Name $nsisToolchainModule -Force
Import-Module -Name $stagingModule -Force
Import-Module -Name $nsisStageModule -Force
Import-Module -Name $stagedBuildModule -Force
$canonicalReceiptExists=Test-Path -LiteralPath $canonicalReceipt -PathType Leaf
$canonicalMarkerExists=Test-Path -LiteralPath ($canonicalReceipt+'.sha256') -PathType Leaf
if($canonicalReceiptExists -ne $canonicalMarkerExists){
    throw 'Canonical package receipt and its sidecar are not a complete pair; refusing build publication.'
}
if($canonicalReceiptExists){
    $existingCanonical=Read-RimePimeSealedJson $canonicalReceipt 'existing canonical package build receipt'
    $existingSchema=[string]$existingCanonical.Value.schema_version
    if($existingSchema -ceq 'yime-rime-pime-package-build-receipt-v2'){
        throw 'Canonical package receipt is already v2; the staged builder refuses to silently downgrade it to an interim v1 receipt.'
    }
    if($existingSchema -cne 'yime-rime-pime-package-build-receipt-v1'){
        throw "Unknown canonical package receipt schema blocks staged build publication: $existingSchema"
    }
}
$buildLogicDigests=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($lease in $buildLogicLeases){
    $record=Get-YimePimePayloadFileRecord $lease.Path
    if([long]$record.bytes -ne [long]$lease.Bytes -or [string]$record.sha256 -cne [string]$lease.Sha256){
        throw "Build-logic path differs from its pre-import read lease: $($lease.Path)"
    }
    $lease.FileId=[string]$record.file_id
    $buildLogicDigests.Add([string]$lease.Path,[string]$lease.Sha256)
}
$package=Read-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath -VerifyArtifacts

$source=Join-Path $root 'installer\installer.nsi'
$requestedVersion=(Get-Content -LiteralPath (Join-Path $root 'version.txt') -Raw).Trim()
if (-not (Test-Path -LiteralPath $MakensisPath -PathType Leaf)) { throw "makensis.exe is missing: $MakensisPath" }
$MakensisPath=[IO.Path]::GetFullPath($MakensisPath)
if([IO.Path]::GetFileName($MakensisPath) -cne 'makensis.exe' -or
    (Split-Path -Leaf (Split-Path -Parent $MakensisPath)) -cne 'Bin' -or
    (Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $MakensisPath))) -cne 'NSIS'){
    throw 'MakensisPath must identify an NSIS/Bin/makensis.exe toolchain entry.'
}
$makensisRecord=Get-YimePimePayloadFileRecord ([IO.Path]::GetFullPath($MakensisPath))
$nsisRoot=Split-Path -Parent (Split-Path -Parent $MakensisPath)
$nsisIncludeRoot=Join-Path $nsisRoot 'Include'
$null=Assert-RimePimeNoReparsePath $nsisIncludeRoot
if(-not(Test-Path -LiteralPath $nsisIncludeRoot -PathType Container)){throw 'The fixed NSIS include root is missing.'}
$workParent=Join-Path $root '.tmp\dual-product'
if(-not $BuildEvidenceRoot){
    $BuildEvidenceRoot=Join-Path $workParent ('dp1-package-build-stage-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
}
$work=[IO.Path]::GetFullPath($BuildEvidenceRoot).TrimEnd('\')
if((Split-Path -Parent $work) -ine $workParent -or
    (Split-Path -Leaf $work) -cnotmatch '^dp1-package-build-stage-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $work)){
    throw 'BuildEvidenceRoot must be a new immediate .tmp/dual-product/dp1-package-build-stage-* directory.'
}
if(-not (Test-Path -LiteralPath $workParent)){New-Item -ItemType Directory -Path $workParent -Force|Out-Null}
New-Item -ItemType Directory -Path $work|Out-Null
$evidence=Join-Path $work 'evidence';$candidateDirectory=Join-Path $work 'candidate'
New-Item -ItemType Directory -Path $evidence,$candidateDirectory|Out-Null

$declaration=Get-RimePimeCurrentPackageStageDeclaration $package
$specPath=Join-Path $evidence 'payload-spec.json'
$spec=Write-RimePimePackageStageSpec -SourceRoot $root -SpecPath $specPath -ProductVersion $requestedVersion `
    -PackagePlanDigest $package.Digest -CopyBindings $declaration.CopyBindings `
    -ClosedSourceTrees $declaration.ClosedSourceTrees -GeneratedOutputs $declaration.GeneratedOutputs
$stageResult=New-RimePimePackageCopyStage -SourceRoot $root -StageRoot (Join-Path $work 'stage') `
    -AllowedStageParent $work -SpecPath $specPath -ExpectedSpecDigest $spec.Digest `
    -ContentManifestPath (Join-Path $evidence 'package-stage-content.json') `
    -ObservationPath (Join-Path $evidence 'package-stage-observation.json')
$include=Write-RimePimeNsisStageInclude -StageRoot $stageResult.StageRoot `
    -ContentManifestPath $stageResult.ContentManifestPath `
    -ExpectedContentManifestDigest $stageResult.ContentManifestDigest -ExpectedPackagePlanDigest $package.Digest `
    -IncludePath (Join-Path $evidence 'payload-files.nsh') -ReceiptPath (Join-Path $evidence 'payload-files-receipt.json')
$content=Read-RimePimeCopiedContentManifest $stageResult.ContentManifestPath $stageResult.ContentManifestDigest
$planStageBindings=Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest
$version=Assert-RimePimeStagedProductVersion -StageRoot $stageResult.StageRoot -ContentManifest $content.Manifest
if($version -cne $requestedVersion){throw 'Staged product version differs from the pre-stage source identity.'}
$installer=Join-Path $root "installer\YIME-$version-setup.exe"
$candidate=Join-Path $candidateDirectory "YIME-$version-setup.exe"
$null=Assert-RimePimeNsisDefinePath $candidate
$localeRoot=Join-Path $root 'installer\locale'
$null=Assert-RimePimeNsisDefinePath $localeRoot
$null=Assert-RimePimeNsisDefinePath $source

$expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-RimePimeExpectedBuildInput([string]$Path,[string]$Digest){
    $full=[IO.Path]::GetFullPath($Path)
    if($Digest -cnotmatch '^[0-9a-f]{64}$' -or $expected.ContainsKey($full)){throw "Invalid or duplicate expected build input: $full"}
    $expected.Add($full,$Digest)
}
foreach($row in @($content.Manifest.files)){
    Add-RimePimeExpectedBuildInput (Join-Path (Join-Path $stageResult.StageRoot ([string]$row.stage_scope)) ([string]$row.path).Replace('/','\')) ([string]$row.sha256)
}
foreach($control in @(
    [pscustomobject]@{Path=$stageResult.ContentManifestPath;Digest=$stageResult.ContentManifestDigest},
    [pscustomobject]@{Path=$stageResult.ContentManifestPath+'.sha256';Digest=(Get-FileHash -LiteralPath ($stageResult.ContentManifestPath+'.sha256') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$spec.Path;Digest=$spec.Digest},
    [pscustomobject]@{Path=$spec.Sidecar;Digest=(Get-FileHash -LiteralPath $spec.Sidecar -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$include.IncludePath;Digest=$include.IncludeDigest},
    [pscustomobject]@{Path=$include.IncludePath+'.sha256';Digest=(Get-FileHash -LiteralPath ($include.IncludePath+'.sha256') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$include.ReceiptPath;Digest=$include.ReceiptDigest},
    [pscustomobject]@{Path=$include.ReceiptPath+'.sha256';Digest=(Get-FileHash -LiteralPath ($include.ReceiptPath+'.sha256') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$package.Path;Digest=$package.Digest},
    [pscustomobject]@{Path=$package.Sidecar;Digest=(Get-FileHash -LiteralPath $package.Sidecar -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$source;Digest=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=(Join-Path $root 'installer\locale\English.nsh');Digest=(Get-FileHash -LiteralPath (Join-Path $root 'installer\locale\English.nsh') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=(Join-Path $root 'installer\locale\SimpChinese.nsh');Digest=(Get-FileHash -LiteralPath (Join-Path $root 'installer\locale\SimpChinese.nsh') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=(Join-Path $root 'installer\locale\TradChinese.nsh');Digest=(Get-FileHash -LiteralPath (Join-Path $root 'installer\locale\TradChinese.nsh') -Algorithm SHA256).Hash.ToLowerInvariant()},
    [pscustomobject]@{Path=$MakensisPath;Digest=[string]$makensisRecord.sha256}
)){
    Add-RimePimeExpectedBuildInput ([string]$control.Path) ([string]$control.Digest)
}
$leases=$null
$candidateLeases=$null
$nsisCompilerInputClosure=$null
$nsisClosureBefore=$null
$nsisClosureAfter=$null
$compilerStage=$null
try{
    $nsisCompilerInputClosure=Open-RimePimeNsisCompilerInputClosure
    $pinnedMakensis=Join-Path ([string]$nsisCompilerInputClosure.NsisRoot) 'Bin\makensis.exe'
    if($MakensisPath -ine $pinnedMakensis){
        throw 'MakensisPath differs from the repository-pinned NSIS compiler distribution.'
    }
    $nsisClosureBefore=Test-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure
    if(-not [bool]$nsisClosureBefore.nsis_distribution_tree_exact_at_open_and_test -or
        -not [bool]$nsisClosureBefore.nsis_known_input_file_replacement_closure -or
        [bool]$nsisClosureBefore.active_same_sid_transient_tree_membership_interference_excluded -or
        [bool]$nsisClosureBefore.nsis_non_os_compiler_input_closure -or
        [bool]$nsisClosureBefore.full_nsis_toolchain_input_closure){
        throw 'Pinned NSIS compiler input evidence does not preserve the reviewed incomplete-closure boundary.'
    }
    $compilerStage=Open-RimePimeMonitoredNsisStage (Join-Path $work 'NSIS')
    $MakensisPath=Join-Path $compilerStage.Root 'Bin\makensis.exe'
    $nsisIncludeRoot=Join-Path $compilerStage.Root 'Include'
    $leases=Open-RimePimeBuildInputLeases $expected
    Test-RimePimeBuildInputLeases @($buildLogicLeases)
    Test-RimePimeBuildInputLeases @($leases)
    $preStage=Test-RimePimePackageCopyStage $stageResult.StageRoot $stageResult.ContentManifestPath $stageResult.ContentManifestDigest
    $preInclude=Test-RimePimeNsisStageInclude -StageRoot $stageResult.StageRoot `
        -ContentManifestPath $stageResult.ContentManifestPath -ExpectedContentManifestDigest $stageResult.ContentManifestDigest `
        -ExpectedPackagePlanDigest $package.Digest -ReceiptPath $include.ReceiptPath -ExpectedReceiptDigest $include.ReceiptDigest
    $stagePayloadRoot=Join-Path $stageResult.StageRoot 'payload'
    $stageBootstrapRoot=Join-Path $stageResult.StageRoot 'bootstrap'
    $stagePeVerifier=Join-Path $root 'tools\verify-pe-architectures.ps1'
    & $stagePeVerifier -RepoRoot $stageResult.StageRoot `
        -X86TextService (Join-Path $stagePayloadRoot 'x86\PIMETextService.dll') `
        -X64TextService (Join-Path $stagePayloadRoot 'x64\PIMETextService.dll') `
        -X86Launcher (Join-Path $stagePayloadRoot 'PIMELauncher.exe') `
        -X86RegistrationStatus (Join-Path $stageBootstrapRoot 'PIMERegistrationStatus_x86.exe') `
        -X64RegistrationStatus (Join-Path $stageBootstrapRoot 'PIMERegistrationStatus_x64.exe') `
        -RimeDll (Join-Path $stagePayloadRoot 'go-backend\input_methods\yime\rime.dll') `
        -RimeDeployer (Join-Path $stagePayloadRoot 'go-backend\input_methods\yime\rime_deployer.exe') `
        -RimeDictManager (Join-Path $stagePayloadRoot 'go-backend\input_methods\yime\rime_dict_manager.exe') `
        -GoBackendRoot (Join-Path $stagePayloadRoot 'go-backend') 6>$null | Out-Null
    Test-RimePimeBuildInputLeases @($leases)
    $savedNsisDir=[Environment]::GetEnvironmentVariable('NSISDIR','Process')
    $env:NSISDIR=$compilerStage.Root
    Push-Location $nsisIncludeRoot
    try{
        $arguments=@(
            '/NOCD','/NOCONFIG',
            "/DPACKAGE_PLAN_SHA256=$($package.Digest)",'/DPACKAGE_PLAN_X86_X64=1',
            "/DPACKAGE_STAGE_ROOT=$($stageResult.StageRoot)",
            "/DPACKAGE_STAGE_MANIFEST_SHA256=$($stageResult.ContentManifestDigest)",
            "/DPACKAGE_STAGE_CONTENT_SHA256=$($content.Manifest.content_tree_sha256)",
            "/DPACKAGE_PAYLOAD_NSH_PATH=$($include.IncludePath)",
            "/DPACKAGE_PAYLOAD_NSH_SHA256=$($include.IncludeDigest)",
            "/DPACKAGE_OUTPUT_PATH=$candidate",
            "/DPACKAGE_LOCALE_ROOT=$localeRoot",
            '/DPACKAGE_UNSIGNED_DISABLED_BUILD=1',$source
        )
        & $MakensisPath @arguments
        if ($LASTEXITCODE -ne 0) { throw "makensis failed with exit code $LASTEXITCODE" }
    }finally{Pop-Location;[Environment]::SetEnvironmentVariable('NSISDIR',$savedNsisDir,'Process')}
    $membershipInterval=Complete-RimePimeMonitoredNsisStage $compilerStage
    if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'makensis returned success without the fresh candidate installer.'}
    $candidateRecord=Get-YimePimePayloadFileRecord $candidate
    if([long]$candidateRecord.bytes -lt 65536 -or [long]$candidateRecord.bytes -gt 536870912){
        throw 'Makensis candidate size is outside the admitted disabled-installer range.'
    }
    $candidateExpected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidateExpected.Add([IO.Path]::GetFullPath($candidate),[string]$candidateRecord.sha256)
    $candidateLeases=Open-RimePimeBuildInputLeases $candidateExpected
    Test-RimePimeBuildInputLeases @($candidateLeases)
    $candidateDigest=[string]$candidateLeases[0].Sha256
    Test-RimePimeBuildInputLeases @($buildLogicLeases)
    Test-RimePimeBuildInputLeases @($leases)
    $postStage=Test-RimePimePackageCopyStage $stageResult.StageRoot $stageResult.ContentManifestPath $stageResult.ContentManifestDigest
    $postInclude=Test-RimePimeNsisStageInclude -StageRoot $stageResult.StageRoot `
        -ContentManifestPath $stageResult.ContentManifestPath -ExpectedContentManifestDigest $stageResult.ContentManifestDigest `
        -ExpectedPackagePlanDigest $package.Digest -ReceiptPath $include.ReceiptPath -ExpectedReceiptDigest $include.ReceiptDigest
    foreach($digest in @($package.Digest,$stageResult.ContentManifestDigest,[string]$content.Manifest.content_tree_sha256,$include.IncludeDigest)){
        if(-not (Test-RimePimeInstallerPlanDigest $candidate $digest)){throw "Candidate installer does not embed sealed build digest: $digest"}
    }
    Test-RimePimeBuildInputLeases @($candidateLeases)
    $packageAfter=Read-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath -VerifyArtifacts
    if([string]$packageAfter.Digest -cne [string]$package.Digest){throw 'Package plan changed while NSIS was running.'}
    $postPlanBindings=Assert-RimePimePackagePlanStageBindings -Package $packageAfter -ContentManifest $content.Manifest
    if([int]$postPlanBindings.package_plan_artifact_count -ne [int]$planStageBindings.package_plan_artifact_count -or
        [int]$postPlanBindings.matching_stage_binding_count -ne [int]$planStageBindings.matching_stage_binding_count){
        throw 'Package-plan to copied-stage binding changed while NSIS was running.'
    }
    $nsisClosureAfter=Test-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure
    if([string]$nsisClosureAfter.nsis_toolchain_lock_sha256 -cne [string]$nsisClosureBefore.nsis_toolchain_lock_sha256 -or
        [string]$nsisClosureAfter.nsis_compiler_input_tree_sha256 -cne [string]$nsisClosureBefore.nsis_compiler_input_tree_sha256 -or
        [int]$nsisClosureAfter.nsis_compiler_input_file_count -ne [int]$nsisClosureBefore.nsis_compiler_input_file_count -or
        [int]$nsisClosureAfter.nsis_compiler_input_directory_count -ne [int]$nsisClosureBefore.nsis_compiler_input_directory_count){
        throw 'Pinned NSIS compiler input evidence changed while makensis was running.'
    }
    $prepared=New-RimePimePreparedPublication -Package $package -CandidateStream $candidateLeases[0].Stream `
        -CandidateDigest $candidateDigest -InstallerSourcePath $source -InstallerPath $installer -ReceiptPath $ReceiptPath `
        -PublicationRoot (Join-Path $work 'prepared-publication')
    Test-RimePimeBuildInputLeases @($candidateLeases)
    $buildResult=[pscustomobject][ordered]@{
        # Tagged so pre-DP1-M validators with an open result-vN regex reject it
        # instead of accepting a membership interval they do not validate.
        schema_version='yime-rime-pime-staged-nsis-build-result-membership-interval-v1';product='rime-pime';product_version=$version
        package_profile='x86-x64-v1';architectures=@('x86','x64');package_plan_sha256=$package.Digest
        payload_spec_sha256=$spec.Digest;content_manifest_sha256=$stageResult.ContentManifestDigest
        content_tree_sha256=[string]$content.Manifest.content_tree_sha256;payload_nsh_sha256=$include.IncludeDigest
        copied_file_count=[int]$preStage.file_count;payload_file_count=[int]$preInclude.payload_file_count
        bootstrap_file_count=[int]$preInclude.bootstrap_file_count;main_payload_file_count=[int]$preInclude.main_payload_file_count
        package_plan_artifact_count=[int]$planStageBindings.package_plan_artifact_count
        package_plan_matching_stage_binding_count=[int]$planStageBindings.matching_stage_binding_count
        staged_pe_unique_artifact_count=[int]$planStageBindings.package_plan_artifact_count
        staged_pe_path_binding_count=[int]$planStageBindings.matching_stage_binding_count
        staged_pe_architecture_verified_under_read_leases=$true
        executed_build_logic_source_count=[int]$buildLogicDigests.Count
        executed_build_logic_sources=@($buildLogicDigests.Keys|Sort-Object|ForEach-Object{[pscustomobject][ordered]@{
            path=$_.Substring($root.Length+1).Replace('\','/');sha256=[string]$buildLogicDigests[$_]
        }})
        build_logic_read_lease_count=[int]$buildLogicLeases.Count
        prebuild_leased_input_count=[int]($leases.Count+$buildLogicLeases.Count+
            [int]$nsisClosureAfter.nsis_compiler_input_read_lease_count+
            [int]$nsisClosureAfter.nsis_toolchain_control_read_lease_count);candidate_leased=$true
        lease_share_mode='read-only-with-file-share-read'
        repository_local_compiler_inputs_leased=$true;repository_local_bare_include_shadowing_closed=$true
        makensis_no_current_directory_change=$true;makensis_user_config_disabled=$true
        compiler_working_directory=$nsisIncludeRoot
        nsis_compiler_membership_interval=$membershipInterval
        nsis_compiler_stage_path=$compilerStage.Root
        nsis_compiler_stage_file_lease_count=[int]$compilerStage.Closure.FileLeases.Count
        nsis_compiler_stage_directory_lease_count=[int]$compilerStage.Closure.DirectoryLeases.Count
        nsis_toolchain_lock_sha256=[string]$nsisClosureAfter.nsis_toolchain_lock_sha256
        nsis_compiler_input_scope=[string]$nsisClosureAfter.nsis_compiler_input_scope
        nsis_compiler_input_tree_sha256=[string]$nsisClosureAfter.nsis_compiler_input_tree_sha256
        nsis_compiler_input_file_count=[int]$nsisClosureAfter.nsis_compiler_input_file_count
        nsis_compiler_input_directory_count=[int]$nsisClosureAfter.nsis_compiler_input_directory_count
        nsis_compiler_input_read_lease_count=[int]$nsisClosureAfter.nsis_compiler_input_read_lease_count
        nsis_compiler_input_directory_lease_count=[int]$nsisClosureAfter.nsis_compiler_input_directory_lease_count
        nsis_compiler_input_anchor_directory_lease_count=[int]$nsisClosureAfter.nsis_compiler_input_anchor_directory_lease_count
        nsis_toolchain_control_read_lease_count=[int]$nsisClosureAfter.nsis_toolchain_control_read_lease_count
        nsis_distribution_tree_exact_at_open_and_test=$true
        nsis_known_input_file_replacement_closure=$true
        nsis_compiler_input_pre_snapshot_exact=$true
        nsis_compiler_input_post_snapshot_exact=$true
        nsis_compiler_input_leases_held_during_makensis=$true
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false
        full_nsis_toolchain_input_closure=$false
        makensis_path=[IO.Path]::GetFullPath($MakensisPath);makensis_sha256=[string]$makensisRecord.sha256
        makensis_path_lease_verified=$true
        unsigned_disabled_build=$true;signing_hook_processes_executed=$false
        signing_host_and_release_signing_pending=$true;path_searched_signing_host_not_executed=$true
        candidate_installer_path=$candidate;candidate_installer_sha256=$candidateDigest
        candidate_installer_bytes=[long]$candidateRecord.bytes;published_installer_path=$installer
        package_build_receipt_path=$ReceiptPath;package_build_receipt_sha256=[string]$prepared.ReceiptDigest
        publication_status_at_evidence_seal='prepared-awaiting-receipt-sidecar-commit-marker'
        publication_commit_marker_path=$ReceiptPath+'.sha256';publication_failure_rollback_enabled=$true
        publication_cross_process_lock=$true
        publication_lock_path=(Join-Path (Split-Path -Parent $ReceiptPath) '.rime-pime-publication.lock')
        prebuild_stage_verified=$true;postbuild_stage_verified=$true;prebuild_include_verified=$true;postbuild_include_verified=$true
        installer_raw_byte_search_found_expected_digests=$true;postbuild_extraction_compared_to_stage=$false
        canonical_receipt_binds_stage_evidence=$false
        canonical_receipt_v2_finalization_required=$true
        canonical_receipt_v2_finalizer_automatically_invoked=$false
        canonical_receipt_v2_requires_sealed_postbuild_result=$true
        v1_receipt_semantics_preserved_until_explicit_v2_finalization=$true
        generated_uninstaller_verified=$false;final_payload_closure=$false;installer_executed=$false;uninstaller_executed=$false
        build_tool_processes_executed=$true;makensis_executed=$true
        installed_product_processes_touched=$false;product_registry_mutated=$false
        default_input_method_changed=$false;production_user_data_read_or_written=$false
        installed_yimecore_local12_touched=$false
    }
    $buildResultPath=Join-Path $evidence 'build-result.json'
    $buildResultDigest=Write-RimePimeStageSealedJson $buildResult $buildResultPath
    $canonicalReceiptExists=Test-Path -LiteralPath $ReceiptPath -PathType Leaf
    $canonicalMarkerExists=Test-Path -LiteralPath ($ReceiptPath+'.sha256') -PathType Leaf
    if($canonicalReceiptExists -ne $canonicalMarkerExists){
        throw 'Canonical package receipt pair changed during the build; refusing publication.'
    }
    if($canonicalReceiptExists){
        $canonicalBeforeCommit=Read-RimePimeSealedJson $ReceiptPath 'canonical package build receipt before interim-v1 publication'
        if([string]$canonicalBeforeCommit.Value.schema_version -ceq 'yime-rime-pime-package-build-receipt-v2'){
            throw 'Canonical package receipt became v2 during the build; refusing to replace it with interim v1.'
        }
        if([string]$canonicalBeforeCommit.Value.schema_version -cne 'yime-rime-pime-package-build-receipt-v1'){
            throw 'Canonical package receipt schema changed during the build; refusing publication.'
        }
    }
    $receipt=Invoke-RimePimePublicationCommit -Package $package -Prepared $prepared -InstallerPath $installer `
        -ReceiptPath $ReceiptPath -RecoveryRoot (Join-Path $work 'publication-recovery')
}finally{
    if($null -ne $compilerStage){Close-RimePimeMonitoredNsisStage $compilerStage}
    if($null -ne $candidateLeases){for($i=$candidateLeases.Count-1;$i -ge 0;$i--){try{$candidateLeases[$i].Stream.Dispose()}catch{Write-Warning "Could not release candidate lease: $($_.Exception.Message)"}}}
    if($null -ne $leases){for($i=$leases.Count-1;$i -ge 0;$i--){try{$leases[$i].Stream.Dispose()}catch{Write-Warning "Could not release build-input lease: $($_.Exception.Message)"}}}
    if($null -ne $nsisCompilerInputClosure){try{Close-RimePimeNsisCompilerInputClosure $nsisCompilerInputClosure}catch{Write-Warning "Could not release NSIS compiler-input closure: $($_.Exception.Message)"}}
}
Write-Host "PASS: makensis compiled explicit sealed-stage references; candidate leases, pre/post checks and receipt-sidecar publication commit passed. Static archive comparison remains pending. Evidence: $buildResultPath ($buildResultDigest); receipt $($receipt.Path) ($($receipt.Digest))"
}finally{
    for($i=$buildLogicLeases.Count-1;$i -ge 0;$i--){try{$buildLogicLeases[$i].Stream.Dispose()}catch{Write-Warning "Could not release build-logic lease: $($_.Exception.Message)"}}
}
