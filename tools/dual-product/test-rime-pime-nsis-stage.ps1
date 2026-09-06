[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-nsis-stage-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a new immediate .tmp/dual-product/dp1-nsis-stage-* fixture root.'
}
if(-not (Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null

$modulePath=Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1'
$moduleHash=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force
Import-Module -Name $modulePath -Force
$planDigest='1'*64
$referenceIncludeDigest=$null

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action,[string]$Like='*'){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notlike $Like){throw "Unexpected rejection: $($_.Exception.Message)"};return}
    throw 'Unsafe NSIS-stage case was accepted.'
}
function Write-FixtureFile([string]$Path,[string]$Text){
    $parent=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function New-NsisStageCase {
    param(
        [string]$Name,[string]$OmitBootstrap,[string]$ExtraBootstrap,[string]$InjectedGoPath,
        [string]$OmitLicense,[switch]$DivergentBootstrapTextService
    )
    $root=Join-Path $output $Name
    $source=Join-Path $root 'source';$evidence=Join-Path $root 'evidence'
    New-Item -ItemType Directory -Path $source,$evidence|Out-Null
    $goFiles=[Collections.Generic.List[string]]::new();$goFiles.Add('app.bin');$goFiles.Add('data/config.json')
    if($InjectedGoPath){$goFiles.Add($InjectedGoPath)}
    $goArray=[string[]]@($goFiles);[Array]::Sort($goArray,[StringComparer]::Ordinal)
    foreach($relative in $goArray){Write-FixtureFile (Join-Path $source ('go-backend\build\go-backend\'+$relative.Replace('/','\'))) ("go:$relative")}
    $inventoryPath=Join-Path $source 'controls\go-payload-inventory.json'
    $inventory=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-go-payload-inventory-v1';source_root='go-backend/build/go-backend'
        destination_root='go-backend';selection_policy='exact-versioned-path-list-v1';files=@($goArray)
    }
    $inventoryDigest=Write-RimePimeStageSealedJson $inventory $inventoryPath
    $bindings=[Collections.Generic.List[object]]::new()
    function Add-Binding([string]$SourcePath,[string]$DestinationPath,[string]$StageScope,
        [string]$Owner,[string]$Architecture,[string]$InstallScope){
        Write-FixtureFile (Join-Path $source $SourcePath.Replace('/','\')) ("fixture:$SourcePath")
        $bindings.Add([pscustomobject][ordered]@{
            source_path=$SourcePath;destination_path=$DestinationPath;stage_scope=$StageScope
            owner_class=$Owner;architecture=$Architecture;install_scope=$InstallScope
        })
    }
    Add-Binding 'source/version.txt' 'version.txt' 'payload' 'metadata' 'neutral' 'installed'
    Add-Binding 'source/backends.json' 'backends.json' 'payload' 'metadata' 'neutral' 'installed'
    foreach($license in @(
        'APACHE-2.0.txt','AUTHORS.txt','LGPL-2.0.txt','LICENSE.txt','NLOHMANN-JSON-MIT.txt','NOTICE.md',
        'PIME-UPSTREAM-LICENSE.txt','RIME-BSD-3-Clause.txt','RIME-FROST-GPL-3.0.txt','RUST-DEPENDENCIES.md',
        'SIL-OFL-1.1.txt','THIRD_PARTY_NOTICES.md','UNICODE-3.0.txt'
    )){
        if($OmitLicense -and $license -ceq $OmitLicense){continue}
        Add-Binding ('source/licenses/'+$license) ('licenses/'+$license) 'payload' 'license' 'neutral' 'installed'
    }
    Add-Binding 'source/PIMELauncher.exe' 'PIMELauncher.exe' 'payload' 'runtime' 'x86' 'installed'
    Add-Binding 'source/PIMETextService-x86.dll' 'x86/PIMETextService.dll' 'payload' 'text-service' 'x86' 'installed'
    Add-Binding 'source/PIMETextService-x64.dll' 'x64/PIMETextService.dll' 'payload' 'text-service' 'x64' 'installed'
    foreach($relative in $goArray){
        $bindings.Add([pscustomobject][ordered]@{
            source_path='go-backend/build/go-backend/'+$relative;destination_path='go-backend/'+$relative
            stage_scope='payload';owner_class='backend';architecture='neutral';install_scope='installed'
        })
    }
    $bootstrap=@(
        @{name='invoke-rime-pime-maintenance.ps1';owner='maintenance';arch='neutral'},
        @{name='invoke-rime-pime-target-user.ps1';owner='maintenance';arch='neutral'},
        @{name='PIMERegistrationStatus_x64.exe';owner='maintenance';arch='x64'},
        @{name='PIMERegistrationStatus_x86.exe';owner='maintenance';arch='x86'},
        @{name='PIMETextService_x64.dll';owner='text-service';arch='x64'},
        @{name='PIMETextService_x86.dll';owner='text-service';arch='x86'},
        @{name='rime-pime-directed-stop-contract.ps1';owner='maintenance';arch='neutral'},
        @{name='rime-pime-ownership.ps1';owner='maintenance';arch='neutral'},
        @{name='rime-pime-target-user.ps1';owner='maintenance';arch='neutral'}
    )
    foreach($entry in $bootstrap){
        if($OmitBootstrap -and $entry.name -ceq $OmitBootstrap){continue}
        if($entry.name -clike 'PIMETextService_*.dll' -and -not $DivergentBootstrapTextService){
            $architecture=if($entry.name -clike '*_x86.dll'){'x86'}else{'x64'}
            $bindings.Add([pscustomobject][ordered]@{
                source_path='source/PIMETextService-'+$architecture+'.dll';destination_path=$entry.name
                stage_scope='bootstrap';owner_class=$entry.owner;architecture=$entry.arch;install_scope='transient'
            })
        }else{
            Add-Binding ('bootstrap-source/'+$entry.name) $entry.name 'bootstrap' $entry.owner $entry.arch 'transient'
        }
    }
    if($ExtraBootstrap){Add-Binding ('bootstrap-source/'+$ExtraBootstrap) $ExtraBootstrap 'bootstrap' 'maintenance' 'neutral' 'transient'}
    $trees=@([pscustomobject][ordered]@{
        source_root='go-backend/build/go-backend';destination_root='go-backend';stage_scope='payload'
        inventory_path='controls/go-payload-inventory.json';inventory_sha256=$inventoryDigest
    })
    $generated=@([pscustomobject][ordered]@{
        destination_path='Uninstall.exe';stage_scope='payload';generator_id='nsis-uninstaller-prebuild-v1'
        identity_policy_id='authenticode-rime-pime-uninstaller-v1';owner_class='runtime';architecture='x86';install_scope='installed'
    })
    $specPath=Join-Path $evidence 'payload-spec.json'
    $spec=Write-RimePimePackageStageSpec -SourceRoot $source -SpecPath $specPath -ProductVersion '1.4.0-test' `
        -PackagePlanDigest $planDigest -CopyBindings @($bindings) -ClosedSourceTrees $trees -GeneratedOutputs $generated
    $stage=New-RimePimePackageCopyStage -SourceRoot $source -StageRoot (Join-Path $root 'stage') `
        -AllowedStageParent $root -SpecPath $specPath -ExpectedSpecDigest $spec.Digest `
        -ContentManifestPath (Join-Path $evidence 'content.json') -ObservationPath (Join-Path $evidence 'observation.json')
    return [pscustomobject]@{Root=$root;Source=$source;Evidence=$evidence;Stage=$stage}
}

function New-Include($Case,[string]$BaseName='payload-files'){
    return Write-RimePimeNsisStageInclude -StageRoot $Case.Stage.StageRoot `
        -ContentManifestPath $Case.Stage.ContentManifestPath `
        -ExpectedContentManifestDigest $Case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
        -IncludePath (Join-Path $Case.Evidence ($BaseName+'.nsh')) `
        -ReceiptPath (Join-Path $Case.Evidence ($BaseName+'-receipt.json'))
}

function Rewrite-ContentManifest($Case,[scriptblock]$Mutation){
    $sealed=Read-RimePimeSealedJson $Case.Stage.ContentManifestPath 'fixture content manifest'
    & $Mutation $sealed.Value
    $sealed.Value.content_tree_sha256=Get-RimePimeStageContentDigest @($sealed.Value.directories) @($sealed.Value.files)
    $digest=Write-RimePimeStageSealedJson $sealed.Value $Case.Stage.ContentManifestPath
    $Case.Stage.ContentManifestDigest=$digest
    return $digest
}

Check 'definitions-only-module-generates-six-stage-only-macros' {
    $case=New-NsisStageCase 'positive'
    $result=New-Include $case
    $script:referenceIncludeDigest=$result.IncludeDigest
    $text=[IO.File]::ReadAllText($result.IncludePath)
    $bytes=[IO.File]::ReadAllBytes($result.IncludePath)
    Assert-True ($result.Verification.passed -and $result.Verification.unique_stage_file_count -eq 29 -and
        $result.Verification.payload_file_count -eq 20 -and $result.Verification.bootstrap_file_count -eq 9 -and
        $result.Verification.main_payload_file_count -eq 18 -and $result.Verification.macro_file_reference_count -eq 30) `
        'NSIS stage macro partition counts are wrong.'
    Assert-True ([regex]::Matches($text,'(?m)^!macro YimePimeStage').Count -eq 6) 'Expected six generated macros.'
    Assert-True ([regex]::Matches($text,'(?m)^\s*File ').Count -eq 30) 'Generated File reference count drifted.'
    Assert-True ($bytes.Length -gt 0 -and $bytes[0] -ne 0xEF -and $text.IndexOf("`r",[StringComparison]::Ordinal) -lt 0 -and
        $text.EndsWith("`n",[StringComparison]::Ordinal) -and -not $text.EndsWith("`n`n",[StringComparison]::Ordinal)) `
        'Generated include is not ASCII without BOM using one final LF.'
    Assert-True ($text -notmatch '(?im)File\s+/r\b|\.\.\\|/nonfatal|[?*]' -and
        [regex]::Matches($text,'(?m)^\s*File [^\r\n]*"\$\{PACKAGE_STAGE_ROOT\}\\(?:payload|bootstrap)\\').Count -eq 30) `
        'Generated include escaped the stage-only explicit-File contract.'
}

Check 'include-bytes-are-stable-across-distinct-stage-roots' {
    $a=New-NsisStageCase 'stable-a';$b=New-NsisStageCase 'stable-b'
    $first=New-Include $a;$second=New-Include $b
    Assert-True ($first.IncludeDigest -ceq $second.IncludeDigest -and
        [IO.File]::ReadAllText($first.IncludePath) -ceq [IO.File]::ReadAllText($second.IncludePath)) `
        'Generated include bytes depend on local absolute paths or file identities.'
}

Check 'wrong-content-manifest-digest-is-rejected' {
    $case=New-NsisStageCase 'wrong-manifest-digest'
    Assert-Rejected {
        Write-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest ('2'*64) -ExpectedPackagePlanDigest $planDigest `
            -IncludePath (Join-Path $case.Evidence 'wrong.nsh') -ReceiptPath (Join-Path $case.Evidence 'wrong-receipt.json')
    } '*external digest*'
}

Check 'wrong-package-plan-digest-is-rejected' {
    $case=New-NsisStageCase 'wrong-plan-digest'
    Assert-Rejected {
        Write-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest ('2'*64) `
            -IncludePath (Join-Path $case.Evidence 'wrong.nsh') -ReceiptPath (Join-Path $case.Evidence 'wrong-receipt.json')
    } '*different package plan*'
}

Check 'missing-fixed-bootstrap-input-is-rejected' {
    $case=New-NsisStageCase 'missing-bootstrap' -OmitBootstrap 'rime-pime-ownership.ps1'
    Assert-Rejected {New-Include $case} '*exact fixed helper/tool set*'
}

Check 'extra-bootstrap-input-is-rejected' {
    $case=New-NsisStageCase 'extra-bootstrap' -ExtraBootstrap 'foreign-helper.ps1'
    Assert-Rejected {New-Include $case} '*exact fixed helper/tool set*'
}

Check 'missing-required-license-input-is-rejected' {
    $case=New-NsisStageCase 'missing-license' -OmitLicense 'NOTICE.md'
    Assert-Rejected {New-Include $case} '*Required NSIS main payload input is missing*'
}

Check 'divergent-bootstrap-text-service-is-rejected' {
    $case=New-NsisStageCase 'divergent-text-service' -DivergentBootstrapTextService
    Assert-Rejected {New-Include $case} '*bootstrap and installed text-service bytes differ*'
}

Check 'nsis-literal-injection-path-is-rejected' {
    $case=New-NsisStageCase 'literal-injection' -InjectedGoPath 'evil$define.dat'
    Assert-Rejected {New-Include $case} '*ASCII literal subset*'
}

Check 'wrong-owner-and-architecture-semantics-are-rejected' {
    $mutations=@(
        @{name='helper-owner';path='rime-pime-target-user.ps1';scope='bootstrap';property='owner_class';value='runtime'},
        @{name='registration-architecture';path='PIMERegistrationStatus_x64.exe';scope='bootstrap';property='architecture';value='neutral'},
        @{name='metadata-owner';path='backends.json';scope='payload';property='owner_class';value='backend'},
        @{name='launcher-architecture';path='PIMELauncher.exe';scope='payload';property='architecture';value='x64'}
    )
    foreach($mutation in $mutations){
        $case=New-NsisStageCase ('semantics-'+$mutation.name)
        $null=Rewrite-ContentManifest $case {
            param($manifest)
            $row=@($manifest.files|Where-Object{[string]$_.stage_scope -ceq $mutation.scope -and [string]$_.path -ceq $mutation.path})[0]
            $row.($mutation.property)=$mutation.value
        }.GetNewClosure()
        Assert-Rejected {New-Include $case} '*wrong owner or architecture semantics*'
    }
}

Check 'unsafe-command-line-define-paths-are-rejected-and-spaces-are-allowed' {
    Assert-True ((Assert-RimePimeNsisDefinePath 'C:\safe path\stage') -ceq 'C:\safe path\stage') 'A normal space was rejected.'
    foreach($unsafe in @('C:\unsafe!root','C:\unsafe$root','C:\unsafe;root')){
        Assert-Rejected {Assert-RimePimeNsisDefinePath $unsafe} '*literal subset*'
    }
}

Check 'changed-generated-include-is-rejected' {
    $case=New-NsisStageCase 'changed-include';$result=New-Include $case
    [IO.File]::AppendAllText($result.IncludePath,'; changed')
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $result.ReceiptDigest
    } '*include*invalid*'
}


Check 'changed-stage-after-include-generation-is-rejected' {
    $case=New-NsisStageCase 'changed-stage';$result=New-Include $case
    [IO.File]::AppendAllText((Join-Path $case.Stage.StageRoot 'payload\backends.json'),'changed')
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $result.ReceiptDigest
    } '*content mismatch*'
}

Check 'missing-generated-include-sidecar-is-rejected' {
    $case=New-NsisStageCase 'missing-include-sidecar';$result=New-Include $case
    Remove-Item -LiteralPath ($result.IncludePath+'.sha256')
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $result.ReceiptDigest
    } '*sidecar is missing*'
}

Check 'hard-linked-generated-include-is-rejected' {
    $case=New-NsisStageCase 'hardlink-include';$result=New-Include $case
    New-Item -ItemType HardLink -Path (Join-Path $case.Root 'include-link.nsh') -Target $result.IncludePath|Out-Null
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $result.ReceiptDigest
    } '*Hard-linked*'
}

Check 'alternate-data-stream-on-generated-include-is-rejected' {
    $case=New-NsisStageCase 'ads-include';$result=New-Include $case
    Set-Content -LiteralPath ($result.IncludePath+':private') -Value 'hidden' -Encoding UTF8
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $result.ReceiptDigest
    } '*Alternate data stream*'
}

Check 'tampered-macro-receipt-count-is-rejected' {
    $case=New-NsisStageCase 'receipt-count';$result=New-Include $case
    $sealed=Read-RimePimeSealedJson $result.ReceiptPath 'fixture NSIS receipt'
    $sealed.Value.macros[0].file_reference_count=[int]$sealed.Value.macros[0].file_reference_count+1
    $digest=Write-RimePimeStageSealedJson $sealed.Value $result.ReceiptPath
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $digest
    } '*macro inventory differs*'
}

Check 'numeric-false-include-receipt-is-rejected' {
    $case=New-NsisStageCase 'receipt-numeric-false';$result=New-Include $case
    $sealed=Read-RimePimeSealedJson $result.ReceiptPath 'fixture NSIS receipt'
    $sealed.Value.final_payload_closure=0
    $digest=Write-RimePimeStageSealedJson $sealed.Value $result.ReceiptPath
    Assert-Rejected {
        Test-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -ReceiptPath $result.ReceiptPath -ExpectedReceiptDigest $digest
    } '*identity or boundary is invalid*'
}

Check 'include-output-cannot-be-overwritten' {
    $case=New-NsisStageCase 'no-overwrite';$null=New-Include $case
    Assert-Rejected {New-Include $case} '*already exists*'
}

Check 'include-and-receipt-must-share-evidence-directory' {
    $case=New-NsisStageCase 'one-evidence-directory'
    $other=Join-Path $case.Root 'other';New-Item -ItemType Directory -Path $other|Out-Null
    Assert-Rejected {
        Write-RimePimeNsisStageInclude -StageRoot $case.Stage.StageRoot -ContentManifestPath $case.Stage.ContentManifestPath `
            -ExpectedContentManifestDigest $case.Stage.ContentManifestDigest -ExpectedPackagePlanDigest $planDigest `
            -IncludePath (Join-Path $case.Evidence 'files.nsh') -ReceiptPath (Join-Path $other 'receipt.json')
    } '*share one evidence directory*'
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-nsis-stage-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    test_level='isolated-filesystem-nsis-include-generation-only';checks_count=$checks.Count;passed=$failed.Count -eq 0
    generated_macro_count=6;generated_file_reference_count_current_fixture=30
    reference_include_sha256=$referenceIncludeDigest
    actual_makensis_executed=$false;actual_installer_or_uninstaller_executed=$false
    registry_or_process_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
    final_payload_closure=$false;module_sha256=$moduleHash
    helper_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();checks=@($checks)
}
$resultPath=Join-Path $output 'result.json'
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
if($failed.Count){foreach($failure in $failed){Write-Host "FAIL: $($failure.name): $($failure.error)"};throw "$($failed.Count) of $($checks.Count) NSIS-stage checks failed."}
Write-Host "PASS: $($checks.Count) isolated NSIS-stage checks passed. Evidence: $resultPath"
