$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'local-product-readiness.psm1'
Import-Module $module -Force
$root = Join-Path ([IO.Path]::GetTempPath()) ('yimecore-readiness-' + [guid]::NewGuid().ToString('N'))
try {
    $package = Join-Path $root 'package'
    New-Item -ItemType Directory -Path $package | Out-Null
    $members = @('Install-YimeCore-Local.cmd','Maintain-YimeCore-Local.cmd','LOCAL-PRODUCT.md','local-product.json','help/README.html','help/settings-and-data.html','help/diagnostics.html','maintenance/Manage-YimeCoreTrial.ps1','maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1','x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll','bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','build/source-manifest.json')
    $entries = @()
    foreach ($member in $members) {
        $path = Join-Path $package $member
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $member -NoNewline
        $item = Get-Item $path
        $entries += [ordered]@{path=$member;bytes=$item.Length;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
    }
    $manifest = [ordered]@{product_version='0.1.0-local.12';source_manifest_sha256='fixture-source';files=$entries}
    $manifestPath = Join-Path $package 'package-manifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content $manifestPath
    $manifestHash = (Get-FileHash $manifestPath).Hash.ToLowerInvariant()
    function Write-Fixture($Name,$Value) { $path=Join-Path $root $Name; $Value|ConvertTo-Json -Depth 10|Set-Content $path; $path }
    $daily=Write-Fixture 'daily.json' ([ordered]@{schema_version='yimecore-local12-l5-final-daily-use-v1';user_report=@{accepted_for_daily_use=$true};mechanical_post_use=@{passed=$true};gates=@{L5_final_user_confirmation=$true}})
    $registered=Write-Fixture 'registered.json' ([ordered]@{schema_version='yimecore-l5-local12-registered-acceptance-v1';gates=@{passed=$true;registered_host_acceptance=$true}})
    $reboot=Write-Fixture 'reboot.json' ([ordered]@{schema_version='yimecore-l5-local12-reboot-outcomes-v1';local12_reboot_autostart_gate_passed=$true})
    $x86=Join-Path $root 'x86.md'; Set-Content $x86 'fixture accepted'
    $manual=Write-Fixture 'manual.json' ([ordered]@{schema_version='yimecore-l5-local12-manual-pre-reboot-v1';current_installed=@{package_version='0.1.0-local.12';manifest_sha256=$manifestHash};regression_status=@{'D2-F-01'='manual_retest_passed_fixture'};host_modules=@{hosts=@(@{name='notepad++.exe';yime_modules=@(@{sha256=($entries|Where-Object path -eq 'x86/YimeTextServiceExperiment.dll').sha256})})}})
    $backup=Write-Fixture 'backup.json' ([ordered]@{schema_version='yimecore-l5-local12-native-backup-evidence-v1';native_backup_manifest_passed=$true;archived_public_package_verification=@{all_listed_public_package_sizes_and_hashes_matched=$true}})
    $without=Get-YimeCoreLocalProductReadiness $package $daily $registered $reboot $x86 $manual $backup -ExpectedManifestSha256 $manifestHash
    if ($without.local_product_ready -or $without.checks.current_candidate_actual_restore_and_failed_upgrade_rollback -or $without.public_release_ready) { throw 'Missing current recovery evidence did not fail closed.' }
    $recovery=Write-Fixture 'recovery.json' ([ordered]@{schema_version='yimecore-local-product-current-candidate-recovery-v1';passed=$true;package_version='0.1.0-local.12';manifest_sha256=$manifestHash;actual_restore_passed=$true;actual_failed_upgrade_rollback_passed=$true;system_registry_rollback_verified=$true})
    $with=Get-YimeCoreLocalProductReadiness $package $daily $registered $reboot $x86 $manual $backup $recovery -ExpectedManifestSha256 $manifestHash
    if (-not $with.local_product_ready -or $with.public_release_ready -or $with.pending.Count -ne 0) { throw 'Complete fixture did not become locally ready with public release still false.' }
    $manualValue = Get-Content $manual -Raw | ConvertFrom-Json
    $manualValue.host_modules.hosts[0].yime_modules[0].sha256 = '00'
    $manualValue | ConvertTo-Json -Depth 10 | Set-Content $manual
    $wrongX86=Get-YimeCoreLocalProductReadiness $package $daily $registered $reboot $x86 $manual $backup $recovery -ExpectedManifestSha256 $manifestHash
    if ($wrongX86.local_product_ready -or $wrongX86.checks.x86_live_host_evidence_chain) { throw 'Mismatched local.12 x86 host DLL evidence did not fail closed.' }
    Add-Content (Join-Path $package 'bin\YimeBroker.exe') 'tamper'
    $tampered=Get-YimeCoreLocalProductReadiness $package $daily $registered $reboot $x86 $manual $backup $recovery -ExpectedManifestSha256 $manifestHash
    if ($tampered.local_product_ready -or $tampered.package.passed) { throw 'Tampered package did not fail closed.' }
    Write-Host 'PASS: local product readiness fail-closed and complete-fixture contracts.'
} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
