[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot 'local13-maintenance-inputs.psm1'
$module=Import-Module $modulePath -Force -PassThru
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-local13-inputs-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
$leases=New-Object 'Collections.Generic.List[object]'
$junction=''
function Check([bool]$Value,[string]$Name){if(-not $Value){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Code,[string]$Name){$rejected=$false;try{$null=& $Code}catch{$rejected=$true};Check $rejected $Name}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json($Value,[string]$Path){$Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding UTF8}
function Rows([string]$Base,[string[]]$Members){return @(foreach($member in $Members){$file=Join-Path $Base $member;@{path=$member;bytes=(Get-Item -LiteralPath $file).Length;sha256=(Hash $file)}})}
function RefreshPackages($Fixture){foreach($lane in @('normal','fault')){$Fixture[$lane].files=Rows (Join-Path $Fixture.root ($lane+'/package')) $Fixture.members}}
function Seal($Fixture){
    $normalPath=Join-Path $Fixture.root 'normal/package/package-manifest.json';Json $Fixture.normal $normalPath;$normalHash=Hash $normalPath
    $Fixture.fault.source_package_manifest_sha256=$normalHash
    $faultPath=Join-Path $Fixture.root 'fault/package/package-manifest.json';Json $Fixture.fault $faultPath;$faultHash=Hash $faultPath
    $runtimeHash=Hash (Join-Path $Fixture.root 'fault/package/bin/YimeCoreTrialRuntime.exe')
    $probeHash=Hash (Join-Path $Fixture.root 'fault/evidence/rollback-failure-runtime.go')
    $entryHash=Hash (Join-Path $Fixture.root 'fault/evidence/prepare-local13-maintenance.ps1')
    $moduleHash=Hash (Join-Path $Fixture.root 'fault/evidence/local12-maintenance-preparation.psm1')
    $common=@{source_manifest_sha256=$normalHash;source_package_id='fixture-normal';probe_source_sha256=$probeHash;
        execution_authorized=$false;ready_to_execute=$false;probe_exit_observed=$false;installer_executed=$false;product_executed=$false;installed_package_read=$false;user_state_read=$false;product_mutated=$false;same_sid_execution_boundary=$false;unexpected_success_rollback_guard_available=$true}
    $prep=$common.Clone();$prep.schema_version='yimecore-local13-fault-preparation-output-v1';$prep.failure_manifest_sha256=$faultHash;$prep.failure_package_id='fixture-fault'
    $prep.failure_runtime_sha256=$runtimeHash;$prep.file_count=$Fixture.members.Count;$prep.preparation_entry_sha256=$entryHash;$prep.preparation_module_sha256=$moduleHash
    foreach($key in $Fixture.prepOverride.Keys){$prep[$key]=$Fixture.prepOverride[$key]}
    $plan=$common.Clone();$plan.schema_version='yimecore-local13-fault-preparation-plan-v1';$plan.required_maintenance_mode='NativeDesktopRehearsal'
    $plan.manager_sha256=$Fixture.controllerHash;$plan.wrapper_sha256=$Fixture.wrapperHash
    Json $prep (Join-Path $Fixture.root 'fault/evidence/preparation.json');Json $plan (Join-Path $Fixture.root 'fault/evidence/plan.json')
    $paths=@(foreach($lane in @('normal','fault')){foreach($member in $Fixture.members){$lane+'/package/'+$member};$lane+'/package/package-manifest.json'})+
        @('fault/evidence/preparation.json','fault/evidence/plan.json','fault/evidence/rollback-failure-runtime.go','fault/evidence/prepare-local13-maintenance.ps1','fault/evidence/local12-maintenance-preparation.psm1')
    $archive=@{schema_version='yimecore-local13-public-archive-v1';root=$Fixture.root;normal_manifest_sha256=$normalHash;fault_manifest_sha256=$faultHash;
        source_file_count=$paths.Count;files=(Rows $Fixture.root $paths);user_state_read=$false;installed_package_touched=$false;artifact_executed=$false;execution_authorized=$false;ready_to_execute=$false;L6_closed=$false}
    foreach($key in $Fixture.archiveOverride.Keys){$archive[$key]=$Fixture.archiveOverride[$key]}
    Json $archive (Join-Path $Fixture.root 'archive-manifest.json');$archiveHash=Hash (Join-Path $Fixture.root 'archive-manifest.json')
    $summary=@{schema_version='yimecore-local13-public-archive-summary-v1';passed=$true;archive_root=$Fixture.root;archive_manifest_sha256=$archiveHash;archived_public_inputs=$paths.Count;user_state_backup=$false;execution_authorized=$false;ready_to_execute=$false;L6_closed=$false}
    Json $summary (Join-Path $Fixture.root 'archive-summary.json')
    $Fixture.catalog=@{root=$Fixture.root;archive_manifest_sha256=$archiveHash;archive_summary_sha256=(Hash (Join-Path $Fixture.root 'archive-summary.json'));
        normal_manifest_sha256=$normalHash;fault_manifest_sha256=$faultHash;normal_id='fixture-normal';fault_id='fixture-fault';package_members=$Fixture.members.Count;archive_inputs=$paths.Count;
        controller_sha256=$Fixture.controllerHash;wrapper_sha256=$Fixture.wrapperHash;
        preparation_sha256=(Hash (Join-Path $Fixture.root 'fault/evidence/preparation.json'));plan_sha256=(Hash (Join-Path $Fixture.root 'fault/evidence/plan.json'));
        runtime_sha256=$runtimeHash;probe_source_sha256=$probeHash;preparation_entry_sha256=$entryHash;preparation_module_sha256=$moduleHash}
}
function Fixture([string]$Name){
    $base=Join-Path $root $Name
    $members=@('local-product.json','maintenance/Manage-YimeCoreTrial.ps1','maintenance/manage-local-product.ps1',
        'x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll','x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
        'bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','bin/YimeCoreRecoveryProbe.exe')
    $descriptor=@{schema_version='yimecore-local-product-v1';version='0.1.0-local.13';package_contract='yimecore-local-product-package-v1';installable=$true;
        scope=@{computer_name='MYCOMPUTER';active_architectures=@('x64','x86')};identity=@{product_key='YimeCoreExperimentalTrial';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'}}
    foreach($lane in @('normal','fault')){
        $package=Join-Path $base ($lane+'/package')
        foreach($member in $members){$file=Join-Path $package $member;New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force|Out-Null;Set-Content -LiteralPath $file -Value "throw 'Fixture public payload must not execute'" -Encoding UTF8}
        Json $descriptor (Join-Path $package 'local-product.json')
    }
    Set-Content -LiteralPath (Join-Path $base 'fault/package/bin/YimeCoreTrialRuntime.exe') -Value 'nonexecutable synthetic replacement' -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $base 'fault/evidence')|Out-Null
    foreach($name in @('rollback-failure-runtime.go','prepare-local13-maintenance.ps1','local12-maintenance-preparation.psm1')){Set-Content -LiteralPath (Join-Path $base ('fault/evidence/'+$name)) -Value "throw 'Evidence must not execute'" -Encoding UTF8}
    $normal=@{package_contract='yimecore-local-product-package-v1';tool_version='yimecore-local-builder-v1';product_version='0.1.0-local.13';package_id='fixture-normal';files=@()}
    $fault=$normal.Clone();$fault.package_id='fixture-fault';$fault.rehearsal_only=$true;$fault.preparation_only=$true;$fault.source_package_id='fixture-normal';$fault.rehearsal_mode='NativeDesktopRehearsal';$fault.expected_runtime_exit_code=86
    $result=@{root=$base;members=$members;normal=$normal;fault=$fault;descriptor=$descriptor;catalog=@{};prepOverride=@{};archiveOverride=@{};
        controllerHash=(Hash (Join-Path $base 'normal/package/maintenance/Manage-YimeCoreTrial.ps1'));wrapperHash=(Hash (Join-Path $base 'normal/package/maintenance/manage-local-product.ps1'))}
    RefreshPackages $result;Seal $result;return $result
}
function UseFixture($Fixture){& $module {param($value) $script:InputCatalog=$value} $Fixture.catalog}
function RejectFixture($Fixture,[string]$Name){UseFixture $Fixture;Reject {Open-YimeCoreLocal13MaintenanceInputs} $Name
    $sessions=& $module {$script:InputSessions.Count};Check ($sessions -eq 0) ($Name+' releases unsuccessful session')}
try{
    $fixedPlan=Get-YimeCoreLocal13MaintenanceInputPlan
    Check ($fixedPlan.normal.manifest_sha256 -ceq '8f7e44ab9097a99d938891b507d0a07b753ffa66dbbec887cb0576286470f2cc' -and $fixedPlan.fault.manifest_sha256 -ceq 'd8cd1338ea2439620f840ef5f43687f15069200f16e1de16b2b6653c9e217161' -and $fixedPlan.normal.member_count -eq 85) 'default Plan returns fixed reviewed candidate constants'
    Check ($fixedPlan.controller_sha256 -ceq '9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d') 'default provider pins archived controller independently of current workspace manager'
    Check (-not $fixedPlan.verification_performed -and -not $fixedPlan.input_files_opened -and -not $fixedPlan.execution_authorized) 'default Plan does not inspect or authorize inputs'
    $fixedPlan.normal.package_id='caller mutation'
    Check ((Get-YimeCoreLocal13MaintenanceInputPlan).normal.package_id -ceq 'yimecore-local-0.1.0-local.13-7f86b4384fef') 'Plan mutation cannot change provider catalog'
    $exports=@($module.ExportedFunctions.Keys|Sort-Object)
    Check (($exports -join '|') -ceq 'Close-YimeCoreLocal13MaintenanceInputs|Get-YimeCoreLocal13MaintenanceInputPlan|Open-YimeCoreLocal13MaintenanceInputs') 'only three fixed provider APIs exported'
    Check (-not (Get-Command Open-YimeCoreLocal13MaintenanceInputs).Parameters.ContainsKey('PackageRoot') -and -not (Get-Command Open-YimeCoreLocal13MaintenanceInputs).Parameters.ContainsKey('Contract')) 'Open has no public root or hash override'
    $fixture=Fixture 'valid';UseFixture $fixture
    # Preload the former global names only in a disposable child so this test
    # cannot poison a later test or retained input lease in the caller's PS7.
    $oldFacts='Yime.Local13InputFacts.Facts' -as [type]
    $oldDirectories='Yime.Local13InputDirectories' -as [type]
    $spoofScript=Join-Path $root 'spoof-global-types.ps1';$spoofCatalog=Join-Path $root 'spoof-catalog.json';$spoofResult=Join-Path $root 'spoof-result.json'
    Json $fixture.catalog $spoofCatalog
    $spoofSource=@'
param([string]$ModulePath,[string]$CatalogPath,[string]$ResultPath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;
using System.IO;
using Microsoft.Win32.SafeHandles;
namespace Yime.Local13InputFacts {
    public static class Facts {
        public static string VerifyFileHandle(FileStream stream,string path){throw new Exception("Preloaded fake file facts were adopted");}
    }
}
namespace Yime {
    public static class Local13InputDirectories {
        public static SafeFileHandle Open(string path){throw new Exception("Preloaded fake directory pin was adopted");}
        public static void Verify(SafeFileHandle handle,string path){throw new Exception("Preloaded fake directory verification was adopted");}
    }
}
"@
$module=Import-Module $ModulePath -Force -PassThru
$catalog=Get-Content -LiteralPath $CatalogPath -Raw|ConvertFrom-Json
& $module {param($value) $script:InputCatalog=$value} $catalog
$inputs=$null
try{
    $inputs=Open-YimeCoreLocal13MaintenanceInputs
    $private=& $module {($script:InputFactsType.Namespace -cmatch '^Yime\.Local13Inputs_[a-f0-9]{32}$') -and
        ($script:InputDirectoriesType.Namespace -ceq $script:InputFactsType.Namespace)}
    if(-not $private -or -not $inputs.verified -or -not $inputs.final_paths_and_single_file_links_verified){throw 'Private native input helpers were not used'}
    if($inputs.continuous_membership_protection -or $inputs.execution_authorized){throw 'Read leases were promoted to execution protection'}
    [IO.File]::WriteAllText($ResultPath,'{"passed":true}',[Text.UTF8Encoding]::new($false))
}finally{if($null -ne $inputs){Close-YimeCoreLocal13MaintenanceInputs $inputs}}
'@
    [IO.File]::WriteAllText($spoofScript,$spoofSource,[Text.UTF8Encoding]::new($false))
    $shell=Join-Path $PSHOME $(if($PSVersionTable.PSVersion.Major -ge 7){'pwsh.exe'}else{'powershell.exe'})
    & $shell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $spoofScript -ModulePath $modulePath -CatalogPath $spoofCatalog -ResultPath $spoofResult
    Check ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $spoofResult) -and (Get-Content -LiteralPath $spoofResult -Raw|ConvertFrom-Json).passed) 'preloaded global fake helpers cannot replace native input verification'
    Check ([object]::ReferenceEquals($oldFacts,('Yime.Local13InputFacts.Facts' -as [type])) -and
        [object]::ReferenceEquals($oldDirectories,('Yime.Local13InputDirectories' -as [type]))) 'spoof fixture leaves caller global helper types unchanged'
    $before=@(Get-ChildItem -LiteralPath $fixture.root -Recurse -File).Count
    $result=Open-YimeCoreLocal13MaintenanceInputs;$leases.Add($result)
    Check ($result.verified -and $result.file_lease_count -eq $fixture.catalog.archive_inputs+2 -and $result.directory_lease_count -gt 2 -and $result.leases_held) 'Open holds complete file and directory leases'
    Check ($result.normal.package_id -ceq 'fixture-normal' -and $result.fault.package_id -ceq 'fixture-fault' -and $result.controller_sha256 -ceq $fixture.controllerHash) 'normal and independent fault identities bound to private fixture controller pin'
    Check (-not $result.continuous_membership_protection -and -not $result.execution_authorized -and -not $result.ready_to_execute -and -not $result.artifact_executed -and -not $result.user_state_read) 'successful read verification cannot authorize native maintenance'
    $locked=Join-Path $fixture.root 'normal/package/bin/YimeBroker.exe'
    Reject {$s=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$s.Dispose()} 'member write denied while leased'
    Reject {[IO.File]::Delete($locked)} 'member deletion denied while leased'
    Reject {[IO.Directory]::Move($fixture.root,($fixture.root+'-moved'))} 'archive root rename denied while directory lease held'
    $nativeDirectoryType=& $module {$script:InputDirectoriesType}
    Check (($nativeDirectoryType.Namespace -cmatch '^Yime\.Local13Inputs_[a-f0-9]{32}$') -and
        (& $module {$script:InputFactsType.Namespace -ceq $script:InputDirectoriesType.Namespace})) 'both input helpers are retained Types in the private module namespace'
    # An empty directory has no child file lease that might independently deny
    # its rename. Exercise the actual private directory helper in isolation.
    foreach($relative in @('empty-pin-root','empty-pin-parent/empty-child')){
        $emptyPath=Join-Path $root $relative;$movedPath=$emptyPath+'-moved'
        New-Item -ItemType Directory -Path $emptyPath -Force|Out-Null
        $directoryHandle=$nativeDirectoryType::Open($emptyPath);$renamed=$false
        try{
            $nativeDirectoryType::Verify($directoryHandle,$emptyPath)
            try{[IO.Directory]::Move($emptyPath,$movedPath);$renamed=$true}catch{}
        }finally{
            $directoryHandle.Dispose()
            if($renamed){[IO.Directory]::Move($movedPath,$emptyPath)}
        }
        Check (-not $renamed) ('directory LIST lease alone denies real empty directory rename: '+$relative)
        [IO.Directory]::Move($emptyPath,$movedPath);[IO.Directory]::Move($movedPath,$emptyPath)
        Check $true ('empty directory becomes movable after its own lease closes: '+$relative)
    }
    $transient=Join-Path $fixture.root 'normal/package/transient-fixture-only.tmp';$transientCreated=$false
    try{[IO.File]::WriteAllText($transient,'fixture only');$transientCreated=$true} catch{} finally{if(Test-Path -LiteralPath $transient){[IO.File]::Delete($transient)}}
    Check (-not $result.continuous_membership_protection) 'transient member attempts do not turn read leases into a continuous membership claim'
    Check (@(Get-ChildItem -LiteralPath $fixture.root -Recurse -File).Count -eq $before) 'Open never creates archive files'
    Close-YimeCoreLocal13MaintenanceInputs $result;Close-YimeCoreLocal13MaintenanceInputs $result
    Check ($result.closed -and -not $result.leases_held) 'Close releases and is idempotent'
    $s=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$s.Dispose()
    Check $true 'source becomes writable after Close'
    Reject {Close-YimeCoreLocal13MaintenanceInputs ([pscustomobject]@{session_id='unknown'})} 'unknown Close cannot dispose caller supplied objects'
    $bad=Fixture 'tampered';Add-Content -LiteralPath (Join-Path $bad.root 'fault/package/bin/YimeBroker.exe') -Value 'changed'
    RejectFixture $bad 'reject changed package bytes'
    $probeFile=Join-Path $bad.root 'normal/package/bin/YimeBroker.exe';$s=[IO.File]::Open($probeFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$s.Dispose()
    Check $true 'partial acquisition failure releases earlier file handles'
    $bad=Fixture 'unlisted';Set-Content -LiteralPath (Join-Path $bad.root 'unlisted.txt') -Value 'not cataloged';RejectFixture $bad 'reject unlisted archive file'
    $bad=Fixture 'empty-directory';New-Item -ItemType Directory -Path (Join-Path $bad.root 'unlisted')|Out-Null;RejectFixture $bad 'reject unlisted empty directory'
    $bad=Fixture 'array-identity';$bad.normal.package_contract=@('yimecore-local-product-package-v1');Seal $bad;RejectFixture $bad 'reject array identity even when fixture manifest hash is rebound'
    $bad=Fixture 'string-size';$bad.normal.files[0].bytes=[string]$bad.normal.files[0].bytes;Seal $bad;RejectFixture $bad 'reject coerced package member size'
    $bad=Fixture 'array-hash';$bad.normal.files[0].sha256=@($bad.normal.files[0].sha256);Seal $bad;RejectFixture $bad 'reject array package member hash'
    $bad=Fixture 'duplicate-archive';$archive=Get-Content (Join-Path $bad.root 'archive-manifest.json') -Raw|ConvertFrom-Json;$archive.files[1].path=$archive.files[0].path;$bad.archiveOverride.files=$archive.files;Seal $bad;RejectFixture $bad 'reject duplicate archive member'
    $bad=Fixture 'string-marker';$bad.fault.rehearsal_only='true';Seal $bad;RejectFixture $bad 'reject truthy string rehearsal marker'
    $bad=Fixture 'normal-marked';$bad.normal.preparation_only=$true;Seal $bad;RejectFixture $bad 'reject normal package with fault-only marker'
    $bad=Fixture 'same-id';$bad.fault.package_id='fixture-normal';Seal $bad;RejectFixture $bad 'reject fault package reusing normal ID'
    $bad=Fixture 'coerced-claim';$bad.prepOverride.execution_authorized=@($false);Seal $bad;RejectFixture $bad 'reject array false preparation claim'
    $bad=Fixture 'invalid-architecture';$bad.descriptor.scope.active_architectures='x64|x86';foreach($lane in @('normal','fault')){Json $bad.descriptor (Join-Path $bad.root ($lane+'/package/local-product.json'))};RefreshPackages $bad;Seal $bad;RejectFixture $bad 'reject string architecture list'
    $bad=Fixture 'fake-controller';foreach($lane in @('normal','fault')){Set-Content -LiteralPath (Join-Path $bad.root ($lane+'/package/maintenance/Manage-YimeCoreTrial.ps1')) -Value "throw 'No guard'"};RefreshPackages $bad;Seal $bad;RejectFixture $bad 'reject self-attested replacement controller'
    $bad=Fixture 'non-runtime-change';Add-Content -LiteralPath (Join-Path $bad.root 'fault/package/bin/YimeBroker.exe') -Value 'different';RefreshPackages $bad;Seal $bad;RejectFixture $bad 'reject fault changing a non-Runtime member'
    $bad=Fixture 'hardlink';$alias=Join-Path $root 'hardlink-alias.bin';New-Item -ItemType HardLink -Path $alias -Target (Join-Path $bad.root 'normal/package/bin/YimeBroker.exe')|Out-Null;RejectFixture $bad 'reject multiply linked input file'
    $bad=Fixture 'junction-target';$junction=Join-Path $root 'junction';New-Item -ItemType Junction -Path $junction -Target $bad.root|Out-Null;$bad.catalog.root=$junction;RejectFixture $bad 'reject archive root junction'
    $astTokens=$null;$astErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$astTokens,[ref]$astErrors)
    Check ($astErrors.Count -eq 0) 'provider parses in current shell'
    $invocations=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.InvocationOperator -in @([Management.Automation.Language.TokenKind]::Ampersand,[Management.Automation.Language.TokenKind]::Dot)},$true))
    Check ($invocations.Count -eq 0) 'provider never invokes or dot-sources package code'
    $evidence=[ordered]@{schema_version='yimecore-local13-maintenance-input-test-v1';passed=$true;powershell_version=$PSVersionTable.PSVersion.ToString();checks_passed=$checks.Count;checks=@($checks.ToArray());synthetic_fixtures_only=$true;native_handle_checks_used=$true;transient_fixture_created_during_lease=$transientCreated;archive_modified=$false;installed_package_read=$false;user_state_read=$false;artifact_executed=$false;continuous_membership_protection=$false;execution_authorized=$false}
}finally{
    foreach($item in $leases){Close-YimeCoreLocal13MaintenanceInputs $item}
    if($junction -and (Test-Path -LiteralPath $junction)){[IO.Directory]::Delete($junction,$false)}
    $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^yimecore-local13-inputs-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup root'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if($OutputPath){Json $evidence $OutputPath}
Write-Host ('PASS: local.13 maintenance input fixtures '+$checks.Count+'; no execution authorization.')
