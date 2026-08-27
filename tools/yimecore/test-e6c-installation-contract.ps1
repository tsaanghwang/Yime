[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PackageRoot,
    [Parameter(Mandatory)] [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$packageRootPath = [IO.Path]::GetFullPath($PackageRoot)
$outputPathValue = [IO.Path]::GetFullPath($OutputPath)
$manager = Join-Path $packageRootPath 'maintenance\Manage-YimeCoreTrial.ps1'
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
$profileIcon = Join-Path $packageRootPath 'profile-icon.ico'
$desktopTools = Join-Path $packageRootPath 'bin\YimeCoreDesktopTools.exe'
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
$desktopToolsSubsystem = if (Test-Path -LiteralPath $desktopTools -PathType Leaf) {
    Get-PeSubsystem $desktopTools
} else { 0 }
$autoStartTemplate = [regex]::Match($managerText,
    '(?m)^\s*\$runValue\s*=\s*''\{0\} -no-toolbar'' -f \(Quote-Argument \(\[string\]\$runtimeConfig\.runtime_path\)\)\s*$')
$longestInstallRoot = Join-Path $env:ProgramFiles `
    ('YimeCore Experimental Trial\yimecore-e6c-' + ('f' * 64))
$longestAutoStartValue = ('"{0}" -no-toolbar' -f `
    (Join-Path $longestInstallRoot 'bin\YimeCoreTrialRuntime.exe'))
$result = [ordered]@{
    tool_version = 'yimecore-e6c-installation-contract-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    manager_sha256 = (Get-FileHash -LiteralPath $manager -Algorithm SHA256).Hash.ToLowerInvariant()
    installed_apps_entry_planned = [bool]([string]$plan.installed_apps_registry_key -like '*\Uninstall\YimeCoreExperimentalTrial')
    force_cleanup_before_install = [bool]$plan.forced_preinstall_cleanup
    x64_x86_tsf_registration_planned = [bool]$plan.x64_x86_tsf_registration
    learning_sentinel_preserved = [bool]$sentinelPreserved
    invalid_non_trial_root_rejected = [bool]$invalidRootRejected
    exact_trial_clsid_scoped = [bool]($managerText.Contains('{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'))
    secondary_architecture_com_only = [bool]($managerText -match 'Invoke-Registration \$x86Tool ''register-com''')
    profile_keyboard_icon_packaged = [bool](Test-Path -LiteralPath $profileIcon -PathType Leaf)
    trial_tools_packaged = [bool]((@(
        'YimeCoreDesktopTools.exe', 'YimeCoreReverseLookup.exe',
        'YimeCoreLexiconManager.exe', 'YimeCoreTrainer.exe', 'YimeCoreToolCenter.exe',
        'YimeCoreSettingsTool.exe',
        'YimeCoreExplain.exe', 'YimeCoreSentenceRegression.exe'
    ) | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('bin\' + $_)) -PathType Leaf)
    }).Count -eq 0)
    trainer_data_packaged = [bool]((@(
        'yime_yinyuan_layout.json', 'yime_syllable_decomposition.tsv', 'yime_full.dict.yaml',
        'trainer\foundation.json', 'trainer\curriculum.json',
        'trainer\yinyuan_catalog.json', 'trainer\yinyuan_groups.json'
    ) | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $packageRootPath ('data\' + $_)) -PathType Leaf)
    }).Count -eq 0)
    legacy_trial_toolbar_absent = [bool](-not (Test-Path -LiteralPath `
        (Join-Path $packageRootPath 'bin\YimeCoreToolbar.exe') -PathType Leaf))
    native_desktop_tools_windows_gui = [bool]($desktopToolsSubsystem -eq 2)
    desktop_tools_powershell_ui_absent = [bool](@(Get-ChildItem -LiteralPath $packageRootPath `
        -Recurse -File -Filter '*DesktopTools*.ps1').Count -eq 0)
    registration_state_convergence_wait = [bool]($managerText.Contains('function Wait-RegistrationState'))
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
    $result.force_cleanup_before_install -ne $true -or
    $result.x64_x86_tsf_registration_planned -ne $true -or
    $result.learning_sentinel_preserved -ne $true -or
    $result.invalid_non_trial_root_rejected -ne $true -or
    $result.exact_trial_clsid_scoped -ne $true -or
    $result.secondary_architecture_com_only -ne $true -or
    $result.profile_keyboard_icon_packaged -ne $true -or
    $result.trial_tools_packaged -ne $true -or
    $result.trainer_data_packaged -ne $true -or
    $result.legacy_trial_toolbar_absent -ne $true -or
    $result.native_desktop_tools_windows_gui -ne $true -or
    $result.desktop_tools_powershell_ui_absent -ne $true -or
    $result.registration_state_convergence_wait -ne $true -or
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
