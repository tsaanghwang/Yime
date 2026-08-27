[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$NoAutoStart
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$x64Registry = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
$x86Registry = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid\InprocServer32"
$x64DLL = [string](Get-ItemProperty -LiteralPath $x64Registry).'(default)'
$x86DLL = [string](Get-ItemProperty -LiteralPath $x86Registry).'(default)'
$experimentalTip = '0804:{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Split-Path -Parent (Split-Path -Parent $x64DLL)
}
$installRootPath = [IO.Path]::GetFullPath($InstallRoot)
$expectedX64 = Join-Path $installRootPath 'x64\YimeTextServiceExperiment.dll'
$expectedX86 = Join-Path $installRootPath 'x86\YimeTextServiceExperiment.dll'
if (-not $x64DLL.Equals($expectedX64, [StringComparison]::OrdinalIgnoreCase) -or
    -not $x86DLL.Equals($expectedX86, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'the independent experimental CLSID does not point to the requested package in both COM views'
}
$requiredPackageFiles = @(
    $expectedX64,
    $expectedX86,
    (Join-Path $installRootPath 'bin\YimeCoreDesktopTools.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreReverseLookup.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreLexiconManager.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreTrainer.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreToolCenter.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreSettingsTool.exe'),
	(Join-Path $installRootPath 'bin\YimeCoreLayoutDesigner.exe'),
	(Join-Path $installRootPath 'bin\YimeCoreDiagnostics.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreExplain.exe'),
    (Join-Path $installRootPath 'bin\YimeCoreSentenceRegression.exe'),
    (Join-Path $installRootPath 'indexes\full.yidx'),
    (Join-Path $installRootPath 'indexes\variable.yidx'),
    (Join-Path $installRootPath 'indexes\shorthand.yidx'),
    (Join-Path $installRootPath 'data\yime_pinyin_codes.tsv'),
    (Join-Path $installRootPath 'data\yime_yinyuan_layout.json'),
    (Join-Path $installRootPath 'data\yime_syllable_decomposition.tsv'),
    (Join-Path $installRootPath 'data\yime_full.dict.yaml'),
    (Join-Path $installRootPath 'data\trainer\foundation.json'),
    (Join-Path $installRootPath 'data\trainer\curriculum.json'),
    (Join-Path $installRootPath 'data\trainer\yinyuan_catalog.json'),
    (Join-Path $installRootPath 'data\trainer\yinyuan_groups.json'),
    (Join-Path $installRootPath 'help\README.html'),
    (Join-Path $installRootPath 'help\trial-feedback.html'),
    (Join-Path $installRootPath 'help\diagnostics.html')
)
foreach ($required in $requiredPackageFiles) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "incomplete E6-C experimental package: $required"
    }
}

$languageList = Get-WinUserLanguageList
$chinese = $languageList | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
if (-not $chinese) {
    throw 'the current user has no zh-Hans-CN language entry for the experimental TIP'
}
$inputMethodsBefore = @($chinese.InputMethodTips)
if ($inputMethodsBefore -notcontains $experimentalTip) {
    $null = $chinese.InputMethodTips.Add($experimentalTip)
    Set-WinUserLanguageList -LanguageList $languageList -Force
}
$verifiedLanguageList = Get-WinUserLanguageList
$verifiedChinese = $verifiedLanguageList | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
$inputMethodsAfter = @($verifiedChinese.InputMethodTips)
if ($inputMethodsAfter -notcontains $experimentalTip -or
    @($inputMethodsBefore | Where-Object { $inputMethodsAfter -contains $_ }).Count -ne $inputMethodsBefore.Count) {
    throw 'failed to add the experimental TIP without preserving existing Chinese input methods'
}

$configPath = Join-Path $stateRootPath 'runtime-config.json'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    & (Join-Path $PSScriptRoot 'stop-e6c-trial-runtime.ps1') -StateRoot $stateRootPath
}
$brokerPath = Join-Path $installRootPath 'bin\YimeBroker.exe'
$runtimePath = Join-Path $installRootPath 'bin\YimeCoreTrialRuntime.exe'

$config = [ordered]@{
    schema_version = 'yimecore-trial-runtime-config-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    install_root = $installRootPath
    runtime_path = $runtimePath
    runtime_sha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    broker_path = $brokerPath
    broker_sha256 = (Get-FileHash -LiteralPath $brokerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    state_root = $stateRootPath
    pipe_name = '\\.\pipe\YimeBroker.YimeCoreTrial.v1'
    experimental_clsid = $clsid
    experimental_input_method_tip = $experimentalTip
}
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($configPath, (($config | ConvertTo-Json -Depth 4) + "`n"), $utf8NoBom)

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue = ('"{0}"' -f $runtimePath)
if ($NoAutoStart) {
    Remove-ItemProperty -LiteralPath $runKey -Name 'YimeCoreExperimentalTrial' -ErrorAction SilentlyContinue
} else {
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -LiteralPath $runKey -Name 'YimeCoreExperimentalTrial' -Value $runValue -PropertyType String -Force | Out-Null
}

$status = & (Join-Path $PSScriptRoot 'start-e6c-trial-runtime.ps1') -StateRoot $stateRootPath
$evidenceRoot = Join-Path $stateRootPath 'evidence'
New-Item -ItemType Directory -Force $evidenceRoot | Out-Null
$evidencePath = Join-Path $evidenceRoot 'runtime-deployment.json'
[ordered]@{
    schema_version = 'yimecore-e6c-runtime-deployment-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    install_root = $installRootPath
    x64_registered_dll = $x64DLL
    x86_registered_dll = $x86DLL
    runtime = $status
    auto_start_enabled = -not $NoAutoStart
    auto_start_value = $(if ($NoAutoStart) { $null } else { $runValue })
    input_methods_before = $inputMethodsBefore
    input_methods_after = $inputMethodsAfter
    existing_input_methods_preserved = $true
    experimental_input_method_enabled = $true
    production_rime_pime_changed = $false
    bare_digit_selection_changed = $false
} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $evidencePath -Encoding utf8
Write-Host "E6-C trial runtime is ready: $evidencePath"
