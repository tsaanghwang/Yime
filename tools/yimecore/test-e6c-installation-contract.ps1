[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PackageRoot,
    [Parameter(Mandatory)] [string]$OutputPath,
    [string]$ManagerPath
)

$ErrorActionPreference = 'Stop'
$packageRootPath = [IO.Path]::GetFullPath($PackageRoot)
$outputPathValue = [IO.Path]::GetFullPath($OutputPath)
$manager = if ([string]::IsNullOrWhiteSpace($ManagerPath)) {
    Join-Path $packageRootPath 'maintenance\Manage-YimeCoreTrial.ps1'
} else {
    [IO.Path]::GetFullPath($ManagerPath)
}
if (-not (Test-Path -LiteralPath $manager -PathType Leaf)) {
    throw "packaged installation manager is missing: $manager"
}

$stateRoot = Join-Path (Split-Path -Parent $outputPathValue) 'installer-contract-state'
$sentinel = Join-Path $stateRoot 'user-model\learning-sentinel.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $sentinel) -Force | Out-Null
$sentinelValue = '{"generation":17,"mode":"variable"}'
[IO.File]::WriteAllText($sentinel, $sentinelValue, (New-Object Text.UTF8Encoding($false)))

$planText = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action Plan `
    -PackageRoot $packageRootPath -StateRoot $stateRoot 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "installation plan contract failed: $planText" }
$plan = $planText | ConvertFrom-Json

$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$invalidText = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action Plan `
    -PackageRoot $packageRootPath -InstallRoot 'C:\Program Files\PIME' -StateRoot $stateRoot 2>&1) -join "`n"
$invalidExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$invalidRootRejected = $invalidExitCode -ne 0
if (-not $invalidRootRejected) { throw 'installation manager accepted a non-trial install root' }

$sentinelPreserved = (Test-Path -LiteralPath $sentinel -PathType Leaf) -and
    ((Get-Content -LiteralPath $sentinel -Raw) -eq $sentinelValue)
$managerText = Get-Content -LiteralPath $manager -Raw
$currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$profileIcon = Join-Path $packageRootPath 'profile-icon.ico'
$inputToolbar = Join-Path $packageRootPath 'bin\YimeCoreInputToolbar.exe'
function Get-PeSubsystem([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 24 + 68
        return $reader.ReadUInt16()
    } finally {
        $stream.Dispose()
    }
}
function Get-PeMachine([string]$path) {
	$stream = [IO.File]::OpenRead($path)
	try {
		$reader = [IO.BinaryReader]::new($stream)
		$stream.Position = 0x3c
		$peOffset = $reader.ReadInt32()
		$stream.Position = $peOffset + 4
		return $reader.ReadUInt16()
	} finally {
		$stream.Dispose()
	}
}
$inputToolbarSubsystem = if (Test-Path -LiteralPath $inputToolbar -PathType Leaf) {
    Get-PeSubsystem $inputToolbar
} else { 0 }
$autoStartTemplate = [regex]::Match($managerText,
    '(?m)^\s*\$runValue\s*=\s*''\{0\} -no-toolbar'' -f \(Quote-Argument \(\[string\]\$runtimeConfig\.runtime_path\)\)\s*$')
$longestInstallRoot = Join-Path $env:ProgramFiles `
    ('YimeCore Experimental Trial\yimecore-e6c-' + ('f' * 64))
$longestAutoStartValue = ('"{0}" -no-toolbar' -f `
    (Join-Path $longestInstallRoot 'bin\YimeCoreTrialRuntime.exe'))
$stagedValidationIndex = $managerText.IndexOf('Assert-PrivilegedPackageCopy $stagingRoot $package')
$preinstallIndex = $managerText.IndexOf('$preinstall = Invoke-UninstallCore')
$installedValidationIndex = $managerText.IndexOf('Assert-PrivilegedPackageCopy $targetRoot $package')
$registrationAfterValidationIndex = if ($installedValidationIndex -ge 0) {
	$managerText.IndexOf('$registrationStarted = $true', $installedValidationIndex)
} else { -1 }
$removeInputMethodTipText = [regex]::Match(
	$managerText, '(?s)function Remove-InputMethodTip\s*\{.*?\r?\n\}').Value
$result = [ordered]@{
    tool_version = 'yimecore-e6c-installation-contract-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    manager_sha256 = (Get-FileHash -LiteralPath $manager -Algorithm SHA256).Hash.ToLowerInvariant()
	installed_apps_entry_planned = [bool]([string]$plan.installed_apps_registry_key -eq
		"Registry::HKEY_USERS\$currentUserSid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial")
    autostart_targets_calling_user = [bool](
        [string]$plan.target_user_sid -eq $currentUserSid -and
        [string]$plan.autostart_registry_key -eq
            "Registry::HKEY_USERS\$currentUserSid\Software\Microsoft\Windows\CurrentVersion\Run")
    elevation_preserves_target_user_sid = [bool](
        $managerText -match "'-TargetUserSid', \(Quote-Argument \`$TargetUserSid\)" -and
        $managerText -match 'Registry::HKEY_USERS\\\$TargetUserSid\\Software' -and
        $managerText -match '\$effectiveUserSid\.Equals\(\$TargetUserSid' -and
        $managerText -match "-Action Uninstall -StateRoot \{2\} -TargetUserSid \{3\}" -and
		$managerText -notmatch "-Action Uninstall -Force -StateRoot")
    force_cleanup_before_install = [bool]$plan.forced_preinstall_cleanup
    failed_upgrade_restores_previous_install = [bool](
        $plan.upgrade_rollback_supported -and
        $plan.package_staged_before_preinstall_cleanup -and
        $managerText.Contains('function Restore-PreviousInstallation') -and
		$managerText.Contains('-PreserveInstallRoots @($previousRoots + $targetRoot)'))
	preinstall_failure_restores_previous_install = [bool](
		$managerText.Contains('$preinstallStarted = $false') -and
		$managerText.Contains('$preinstallStarted = $true') -and
		$managerText.Contains('if ($preinstallStarted)') -and
		$managerText.IndexOf('$preinstallStarted = $true') -lt $preinstallIndex)
    x64_x86_tsf_registration_planned = [bool]$plan.x64_x86_tsf_registration
    learning_sentinel_preserved = [bool]$sentinelPreserved
    invalid_non_trial_root_rejected = [bool]$invalidRootRejected
    exact_trial_clsid_scoped = [bool]($managerText.Contains('{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'))
	secondary_architecture_com_only = [bool](
		$managerText -match "name = 'x86'; action = 'register-com'" -and
		$managerText -match "name = 'x64'; action = 'register-com'")
	arm64_tsf_packaged = [bool]((@(
		'YimeTextServiceExperiment.dll', 'YimeTextServiceRegistration.exe', 'YimeRegisteredHostTests.exe'
	) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('arm64\' + $_)) -PathType Leaf) }).Count -eq 0)
	arm64_dll_machine_verified = [bool]((Test-Path -LiteralPath (Join-Path $packageRootPath 'arm64\YimeTextServiceExperiment.dll')) -and
		(Get-PeMachine (Join-Path $packageRootPath 'arm64\YimeTextServiceExperiment.dll')) -eq 0xAA64)
	arm64_fail_fast_and_registration_planned = [bool](
		$plan.arm64_tsf_artifacts_required -and
		$managerText.Contains("'arm64\YimeTextServiceExperiment.dll'") -and
		$managerText.Contains("if (`$nativeArchitecture -eq 'ARM64')"))
    profile_keyboard_icon_packaged = [bool](Test-Path -LiteralPath $profileIcon -PathType Leaf)
    yinyuan_private_font_packaged = [bool](Test-Path -LiteralPath `
        (Join-Path $packageRootPath 'data\fonts\YinYuan-Regular.ttf') -PathType Leaf)
    trial_tools_packaged = [bool]((@(
        'YimeCoreInputToolbar.exe', 'YimeCoreReverseLookup.exe',
        'YimeCoreLexiconManager.exe', 'YimeCoreTrainer.exe', 'YimeCoreToolCenter.exe',
        'YimeCoreLexiconCenter.exe', 'YimeCoreBlocklistManager.exe',
        'YimeCoreSystemLexiconAudit.exe', 'YimeCoreLearningManager.exe',
        'YimeCorePromotionScan.exe',
		'YimeCoreProfessionalLexicon.exe',
		'YimeCoreSettingsTool.exe', 'YimeCoreLayoutDesigner.exe', 'YimeCoreDiagnostics.exe',
        'YimeCoreExplain.exe', 'YimeCoreSentenceRegression.exe'
    ) | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('bin\' + $_)) -PathType Leaf)
    }).Count -eq 0)
    professional_catalog_packaged = [bool](Test-Path -LiteralPath `
        (Join-Path $packageRootPath 'professional-lexicons\catalog.json') -PathType Leaf)
    help_files_packaged = [bool]((@(
        'README.html', 'trial-feedback.html', 'diagnostics.html'
    ) | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('help\' + $_)) -PathType Leaf)
    }).Count -eq 0)
    trainer_data_packaged = [bool]((@(
        'yime_yinyuan_layout.json', 'yime_syllable_decomposition.tsv', 'yime_full.dict.yaml',
        'trainer\foundation.json', 'trainer\curriculum.json',
        'trainer\yinyuan_catalog.json', 'trainer\yinyuan_groups.json',
        'dynamic_sentence_cases.json'
    ) | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('data\' + $_)) -PathType Leaf)
    }).Count -eq 0)
    legacy_trial_toolbar_absent = [bool](-not (Test-Path -LiteralPath `
        (Join-Path $packageRootPath 'bin\YimeCoreToolbar.exe') -PathType Leaf) -and
        -not (Test-Path -LiteralPath `
        (Join-Path $packageRootPath 'bin\YimeCoreDesktopTools.exe') -PathType Leaf))
    native_input_toolbar_windows_gui = [bool]($inputToolbarSubsystem -eq 2)
    input_toolbar_powershell_ui_absent = [bool](@(Get-ChildItem -LiteralPath $packageRootPath `
        -Recurse -File -Filter '*.ps1' | Where-Object {
            $_.Name -like '*DesktopTools*' -or $_.Name -like '*InputToolbar*'
        }).Count -eq 0)
    registration_state_convergence_wait = [bool]($managerText.Contains('function Wait-RegistrationState'))
	privileged_copy_revalidated_before_cleanup = [bool](
		$managerText.Contains('function Assert-PrivilegedPackageCopy') -and
		$stagedValidationIndex -ge 0 -and $stagedValidationIndex -lt $preinstallIndex -and
		$installedValidationIndex -ge 0 -and $installedValidationIndex -lt $registrationAfterValidationIndex)
	uninstall_requires_verified_registration_absence = [bool](
		$managerText.Contains('& $tool verify-absent') -and
		$managerText.Contains('installation files were preserved') -and
		$managerText -notmatch '\$LASTEXITCODE -ne 0 -and -not \$Force')
	input_method_tip_cleanup_is_global_and_fail_loud = [bool](
		$removeInputMethodTipText -match 'foreach \(\$language in @\(\$languageList\)\)' -and
		$removeInputMethodTipText -match 'Get-WinUserLanguageList \| Where-Object' -and
		$removeInputMethodTipText -notmatch 'zh-Hans-CN' -and
		$removeInputMethodTipText -notmatch 'catch')
	pre_registration_validation_failure_avoids_untrusted_cleanup_tool = [bool](
		$managerText.Contains('$registrationStarted = $false') -and
		$managerText.Contains('$registrationStarted = $true') -and
		$managerText.Contains('if ($registrationStarted)') -and
		$managerText.IndexOf('$registrationStarted = $true') -gt $installedValidationIndex)
    taskbar_language_bar_categories = [bool]$plan.taskbar_language_bar_categories
    windows_native_language_bar_only = [bool]($managerText.Contains('-no-toolbar'))
    autostart_uses_runtime_defaults = [bool]$autoStartTemplate.Success
    autostart_value_within_run_limit = [bool]($longestAutoStartValue.Length -le 260)
    production_rime_pime_changed = $false
    bare_digit_selection_rules_changed = $false
    plan = $plan
    invalid_root_error = $invalidText
}
if ($result.installed_apps_entry_planned -ne $true -or
    $result.autostart_targets_calling_user -ne $true -or
    $result.elevation_preserves_target_user_sid -ne $true -or
    $result.force_cleanup_before_install -ne $true -or
    $result.failed_upgrade_restores_previous_install -ne $true -or
	$result.preinstall_failure_restores_previous_install -ne $true -or
    $result.x64_x86_tsf_registration_planned -ne $true -or
    $result.learning_sentinel_preserved -ne $true -or
    $result.invalid_non_trial_root_rejected -ne $true -or
    $result.exact_trial_clsid_scoped -ne $true -or
    $result.secondary_architecture_com_only -ne $true -or
	$result.arm64_tsf_packaged -ne $true -or
	$result.arm64_dll_machine_verified -ne $true -or
	$result.arm64_fail_fast_and_registration_planned -ne $true -or
    $result.profile_keyboard_icon_packaged -ne $true -or
    $result.yinyuan_private_font_packaged -ne $true -or
    $result.trial_tools_packaged -ne $true -or
	$result.help_files_packaged -ne $true -or
    $result.trainer_data_packaged -ne $true -or
    $result.legacy_trial_toolbar_absent -ne $true -or
    $result.native_input_toolbar_windows_gui -ne $true -or
    $result.input_toolbar_powershell_ui_absent -ne $true -or
    $result.registration_state_convergence_wait -ne $true -or
	$result.privileged_copy_revalidated_before_cleanup -ne $true -or
	$result.uninstall_requires_verified_registration_absence -ne $true -or
	$result.input_method_tip_cleanup_is_global_and_fail_loud -ne $true -or
	$result.pre_registration_validation_failure_avoids_untrusted_cleanup_tool -ne $true -or
    $result.taskbar_language_bar_categories -ne $true -or
    $result.windows_native_language_bar_only -ne $true -or
    $result.autostart_uses_runtime_defaults -ne $true -or
    $result.autostart_value_within_run_limit -ne $true -or
    $result.production_rime_pime_changed -or $result.bare_digit_selection_rules_changed) {
    throw ('E6-C installation contract failed: ' + ($result | ConvertTo-Json -Depth 7 -Compress))
}
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPathValue) -Force | Out-Null
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $outputPathValue -Encoding utf8
Write-Host "E6-C installation contract: $outputPathValue"
exit 0
