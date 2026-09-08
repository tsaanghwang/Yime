Set-StrictMode -Version Latest

function Get-YimeCoreFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-YimeCoreJsonEvidence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Schema
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Evidence file is missing: $Path" }
    $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($value.schema_version -ne $Schema) { throw "Unexpected evidence schema at ${Path}: $($value.schema_version)" }
    $value
}

function Test-YimeCoreSealedPackage {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [Parameter(Mandatory)][string]$ExpectedManifestSha256
    )
    $root = [IO.Path]::GetFullPath($PackageRoot)
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Sealed package manifest is missing.' }
    $manifestHash = Get-YimeCoreFileSha256 $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $mismatches = @()
    foreach ($entry in @($manifest.files)) {
        $path = [IO.Path]::GetFullPath((Join-Path $root ([string]$entry.path)))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package manifest path escapes the sealed root.' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $mismatches += [string]$entry.path; continue }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [long]$entry.bytes -or (Get-YimeCoreFileSha256 $path) -ne ([string]$entry.sha256).ToLowerInvariant()) {
            $mismatches += [string]$entry.path
        }
    }
    $required = @(
        'Install-YimeCore-Local.cmd', 'Maintain-YimeCore-Local.cmd', 'LOCAL-PRODUCT.md', 'local-product.json',
        'help/README.html', 'help/settings-and-data.html', 'help/diagnostics.html',
        'maintenance/Manage-YimeCoreTrial.ps1', 'maintenance/backup-local-trial-state.ps1',
        'maintenance/restore-local-trial-state.ps1', 'x64/YimeTextServiceExperiment.dll',
        'x86/YimeTextServiceExperiment.dll', 'bin/YimeCoreTrialRuntime.exe', 'bin/YimeBroker.exe',
        'build/source-manifest.json'
    )
    $listed = @($manifest.files | ForEach-Object { ([string]$_.path).Replace('\', '/') })
    $missingRequired = @($required | Where-Object { $_ -notin $listed })
    [ordered]@{
        passed = ($manifestHash -eq $ExpectedManifestSha256 -and $manifest.product_version -eq $ExpectedVersion -and
            $mismatches.Count -eq 0 -and $missingRequired.Count -eq 0)
        root = $root
        version = $manifest.product_version
        manifest_sha256 = $manifestHash
        file_count = @($manifest.files).Count
        mismatches = $mismatches
        missing_required_members = $missingRequired
        source_manifest_sha256 = $manifest.source_manifest_sha256
    }
}

function Get-YimeCoreLocalProductReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$DailyUseEvidence,
        [Parameter(Mandatory)][string]$RegisteredHostEvidence,
        [Parameter(Mandatory)][string]$RebootEvidence,
        [Parameter(Mandatory)][string]$X86AcceptanceRecord,
        [Parameter(Mandatory)][string]$Local12ManualEvidence,
        [Parameter(Mandatory)][string]$PreviousPackageBackupEvidence,
        [string]$CurrentCandidateRecoveryEvidence,
        [string]$RepositoryRoot,
        [string]$ExpectedVersion = '0.1.0-local.12',
        [string]$ExpectedManifestSha256 = '9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e'
    )
    $daily = Read-YimeCoreJsonEvidence $DailyUseEvidence 'yimecore-local12-l5-final-daily-use-v1'
    $registered = Read-YimeCoreJsonEvidence $RegisteredHostEvidence 'yimecore-l5-local12-registered-acceptance-v1'
    $reboot = Read-YimeCoreJsonEvidence $RebootEvidence 'yimecore-l5-local12-reboot-outcomes-v1'
    $manual = Read-YimeCoreJsonEvidence $Local12ManualEvidence 'yimecore-l5-local12-manual-pre-reboot-v1'
    $backup = Read-YimeCoreJsonEvidence $PreviousPackageBackupEvidence 'yimecore-l5-local12-native-backup-evidence-v1'
    if (-not (Test-Path -LiteralPath $X86AcceptanceRecord -PathType Leaf)) { throw 'x86 acceptance record is missing.' }
    $package = Test-YimeCoreSealedPackage $PackageRoot $ExpectedVersion $ExpectedManifestSha256
    $packageManifest = Get-Content -LiteralPath (Join-Path $PackageRoot 'package-manifest.json') -Raw | ConvertFrom-Json
    $packageX86Hash = [string](@($packageManifest.files | Where-Object { $_.path -eq 'x86/YimeTextServiceExperiment.dll' })[0].sha256)
    $manualNotepadppModules = @($manual.host_modules.hosts | Where-Object { $_.name -eq 'notepad++.exe' } | ForEach-Object { $_.yime_modules })
    $local12X86AffectedPathPassed = $manual.current_installed.package_version -eq $ExpectedVersion -and
        $manual.current_installed.manifest_sha256 -eq $ExpectedManifestSha256 -and
        $manual.regression_status.'D2-F-01' -like 'manual_retest_passed*' -and
        @($manualNotepadppModules | Where-Object { $_.sha256 -eq $packageX86Hash }).Count -eq 1
    $outsideRepository = $true
    if ($RepositoryRoot) {
        $repositoryPrefix = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $outsideRepository = -not ([IO.Path]::GetFullPath($PackageRoot).StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase))
    }

    $recoveryPassed = $false
    $recoveryReference = $null
    if ($CurrentCandidateRecoveryEvidence) {
        $recovery = Read-YimeCoreJsonEvidence $CurrentCandidateRecoveryEvidence 'yimecore-local-product-current-candidate-recovery-v1'
        $recoveryPassed = [bool]$recovery.passed -and $recovery.package_version -eq $ExpectedVersion -and
            $recovery.manifest_sha256 -eq $ExpectedManifestSha256 -and [bool]$recovery.actual_restore_passed -and
            [bool]$recovery.actual_failed_upgrade_rollback_passed -and [bool]$recovery.system_registry_rollback_verified
        $recoveryReference = [ordered]@{path=[IO.Path]::GetFullPath($CurrentCandidateRecoveryEvidence);sha256=Get-YimeCoreFileSha256 $CurrentCandidateRecoveryEvidence}
    }

    $checks = [ordered]@{
        sealed_package_integrity = [bool]$package.passed
        sealed_package_outside_repository = $outsideRepository
        l5_final_user_confirmation = [bool]$daily.gates.L5_final_user_confirmation -and [bool]$daily.user_report.accepted_for_daily_use
        l5_post_use_identity_and_protection = [bool]$daily.mechanical_post_use.passed
        installed_x64_x86_registered_hosts = [bool]$registered.gates.passed -and [bool]$registered.gates.registered_host_acceptance
        local12_reboot_and_logon_autostart = [bool]$reboot.local12_reboot_autostart_gate_passed
        x86_live_host_evidence_chain = (Test-Path -LiteralPath $X86AcceptanceRecord -PathType Leaf) -and $local12X86AffectedPathPassed
        previous_working_package_backup_preserved = [bool]$backup.native_backup_manifest_passed -and
            [bool]$backup.archived_public_package_verification.all_listed_public_package_sizes_and_hashes_matched
        current_candidate_actual_restore_and_failed_upgrade_rollback = $recoveryPassed
    }
    $pending = @()
    foreach ($entry in $checks.GetEnumerator()) { if (-not $entry.Value) { $pending += $entry.Key } }
    $localReady = $pending.Count -eq 0
    [ordered]@{
        schema_version = 'yimecore-local-product-readiness-v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        affected_product = 'YimeCore'
        scope = 'MYCOMPUTER x64 runtime plus WOW64 x86 TSF; installed local.12'
        package = $package
        checks = $checks
        local_product_ready = $localReady
        public_release_ready = $false
        pending = $pending
        deferred = @('trusted signing', 'ARM64 native installed and live-host acceptance', 'other physical PC acceptance')
        evidence = [ordered]@{
            daily_use = [ordered]@{path=[IO.Path]::GetFullPath($DailyUseEvidence);sha256=Get-YimeCoreFileSha256 $DailyUseEvidence}
            registered_hosts = [ordered]@{path=[IO.Path]::GetFullPath($RegisteredHostEvidence);sha256=Get-YimeCoreFileSha256 $RegisteredHostEvidence}
            reboot = [ordered]@{path=[IO.Path]::GetFullPath($RebootEvidence);sha256=Get-YimeCoreFileSha256 $RebootEvidence}
            x86_live_hosts = [ordered]@{path=[IO.Path]::GetFullPath($X86AcceptanceRecord);sha256=Get-YimeCoreFileSha256 $X86AcceptanceRecord}
            local12_affected_x86_manual = [ordered]@{path=[IO.Path]::GetFullPath($Local12ManualEvidence);sha256=Get-YimeCoreFileSha256 $Local12ManualEvidence}
            previous_package_backup = [ordered]@{path=[IO.Path]::GetFullPath($PreviousPackageBackupEvidence);sha256=Get-YimeCoreFileSha256 $PreviousPackageBackupEvidence}
            current_candidate_recovery = $recoveryReference
        }
        privacy = [ordered]@{
            installer_executed = $false; product_or_registry_mutated = $false; default_input_method_changed = $false
            user_text_read = $false; user_settings_or_learning_files_read = $false; raw_logs_or_events_read = $false
        }
        limitations = @(
            'A prior-version recovery rehearsal is not promoted to current-candidate recovery evidence after the packaged maintenance controller changed.',
            'The general x86 physical-host checks remain bound to local.11. local.12 changed the x86 TSF binary, so the evidence chain also requires its affected Notepad++ focus-switch path and exact loaded DLL hash; it does not claim a full physical-host rerun.',
            'public_release_ready remains false independently of local readiness.'
        )
    }
}

Export-ModuleMember -Function Get-YimeCoreLocalProductReadiness
