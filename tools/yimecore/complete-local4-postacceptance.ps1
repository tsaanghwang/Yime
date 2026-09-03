[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$archive='C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-085024-6b3929c6'
$root='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-324e46fc'
$manifestHash='324e46fc5c930d79de713b1fe8d4a0c7cefa884c88b25721dec50cb3c2ed4431'
$sid='S-1-5-21-2783006668-770716121-2150155084-1001'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$output=Join-Path $archive 'corrected-postacceptance.json'
if(Test-Path -LiteralPath $output){throw 'Corrected post-acceptance evidence already exists.'}
if((Get-FileHash -LiteralPath (Join-Path $root 'package-manifest.json')).Hash -ine $manifestHash){throw 'Installed local.4 manifest changed.'}
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){. (Join-Path $root "maintenance\$name")}
$null=Get-YimeCoreDevelopmentScope
Assert-YimeCoreUnpackagedDataMaintenance
$package=Assert-LocalProductPackage $root
$context=Assert-LocalProductInstalledContext $root $state
$live=Assert-LocalProductLiveRuntime $context
& (Join-Path $root 'Maintain-YimeCore-Local.cmd') -Action Verify
if($LASTEXITCODE -ne 0){throw 'Installed three-mode verification failed.'}
$before=Get-Content -LiteralPath (Join-Path $archive 'system-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$capturedAfter=Get-Content -LiteralPath (Join-Path $archive 'system-after.json') -Raw -Encoding UTF8|ConvertFrom-Json
$acceptance=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($acceptance,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue','Assert-CutoverRegistry')){$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);if(-not $fn){throw "Missing validator: $name"};. ([scriptblock]::Create($fn.Extent.Text))}
$current=Get-CutoverRegistrySnapshot
Assert-CutoverRegistry $before $current $root ([string]$package.descriptor.display_name) $sid $state
if(($capturedAfter|ConvertTo-Json -Depth 40 -Compress) -cne ($current|ConvertTo-Json -Depth 40 -Compress)){throw 'Registry changed after the original post-check.'}
$saved=Get-Content -LiteralPath (Join-Path $archive 'preinstall-backup\backup-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-YimeCoreUnchangedData $saved.data_files @(Get-YimeCoreDataRecords $state)
$plan=Get-Content -LiteralPath (Join-Path $archive 'preflight.json') -Raw -Encoding UTF8|ConvertFrom-Json
$frozenRoots=@($plan.plan.frozen_registration_references|ForEach-Object{[IO.Path]::GetFullPath([string]$_.install_root)}|Sort-Object -Unique)
foreach($frozenRoot in $frozenRoots){
    $manifestPath=Join-Path $frozenRoot 'package-manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $manifest.files){throw "Frozen payload manifest is incomplete: $frozenRoot"}
    foreach($record in $manifest.files){
        $payload=[IO.Path]::GetFullPath((Join-Path $frozenRoot $record.path))
        if(-not $payload.StartsWith($frozenRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $payload -PathType Leaf) -or (Get-Item -LiteralPath $payload).Length -ne $record.bytes -or
            (Get-FileHash -LiteralPath $payload).Hash -ine $record.sha256){throw "Frozen payload mismatch: $($record.path)"}
    }
    $expectedFiles=@($manifest.files.path)+@('package-manifest.json','install-metadata.json')
    $actualFiles=@(Get-ChildItem -LiteralPath $frozenRoot -Recurse -File|ForEach-Object{$_.FullName.Substring($frozenRoot.Length+1).Replace('\','/')})
    if(Compare-Object $expectedFiles $actualFiles){throw "Frozen payload contains an unexpected or missing file: $frozenRoot"}
}
[ordered]@{schema_version='yimecore-local4-corrected-postacceptance-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');passed=$true;
    installed_manifest_sha256=$manifestHash;install_root=$root;installed_version=[string]$package.manifest.product_version;
    live_standard_user_runtime=$live;three_mode_verification_passed=$true;user_data_unchanged=$true;
    protected_system_registry_unchanged=$true;frozen_payload_roots_verified=$frozenRoots;
    immediate_previous_unreferenced_root_removed=(-not (Test-Path 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-75485fda5d79-6964099f'));
    original_summary_preserved=$true;original_false_negative='acceptance asserted that the immediately previous active root was the frozen root';
    native_install_accepted=$true;live_host_acceptance=$false;actual_backup_restore_tested=$false;actual_failed_upgrade_rollback_tested=$false;
    reboot_requested=$false;public_release_ready=$false}|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $output -Encoding UTF8
$null=Assert-YimeCoreNativeFile $output
Write-Host "PASS: local.4 corrected native post-acceptance. Evidence: $output"
