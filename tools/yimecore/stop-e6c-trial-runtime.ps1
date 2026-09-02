[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$DisableAutoStart,
    [switch]$RemoveInputMethod
)

$ErrorActionPreference = 'Stop'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$configPath = Join-Path $stateRootPath 'runtime-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
	throw "cannot verify E6-C trial runtime state because configuration is missing: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($property in @('runtime_path', 'broker_path', 'install_root', 'state_root')) {
	if ([string]::IsNullOrWhiteSpace([string]$config.$property)) {
		throw "invalid E6-C trial runtime configuration: missing $property"
	}
}
if (-not ([IO.Path]::GetFullPath([string]$config.state_root)).Equals(
		$stateRootPath, [StringComparison]::OrdinalIgnoreCase)) {
	throw 'configured E6-C state root does not match the requested state root'
}
if (-not (Test-Path -LiteralPath ([string]$config.runtime_path) -PathType Leaf)) {
	throw "configured E6-C runtime is unavailable: $($config.runtime_path)"
}
$manifestPath=Join-Path ([string]$config.install_root) 'package-manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.PSObject.Properties['package_contract'] -and $manifest.package_contract -eq 'yimecore-local-product-package-v1') {
    . (Join-Path $PSScriptRoot 'development-scope.ps1')
    . (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
    . (Join-Path $PSScriptRoot 'local-package-contract.ps1')
    $null=Get-YimeCoreDevelopmentScope
    Assert-YimeCoreUnpackagedDataMaintenance
    if ($DisableAutoStart -or $RemoveInputMethod) { throw 'Use local product uninstall for registration/autostart changes.' }
    $null=Assert-LocalProductInstalledContext (Split-Path -Parent $PSScriptRoot) $stateRootPath
}
$argumentLine = '-stop -install-root "{0}" -broker "{1}" -state-root "{2}"' -f
	([string]$config.install_root), ([string]$config.broker_path), ([string]$config.state_root)
$stopper = Start-Process -FilePath ([string]$config.runtime_path) -ArgumentList $argumentLine -WindowStyle Hidden -Wait -PassThru
if ($stopper.ExitCode -ne 0) {
	throw "E6-C trial runtime stop request failed with exit $($stopper.ExitCode)"
}
if ($DisableAutoStart) {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Remove-ItemProperty -LiteralPath $runKey -Name 'YimeCoreExperimentalTrial' -ErrorAction SilentlyContinue
}
if ($RemoveInputMethod) {
    $tip = '0804:{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
    $languageList = Get-WinUserLanguageList
    $changed = $false
    foreach ($language in @($languageList)) {
        while (@($language.InputMethodTips) -contains $tip) {
            if (-not $language.InputMethodTips.Remove($tip)) {
                throw "failed to remove the YimeCore trial TIP from $($language.LanguageTag)"
            }
            $changed = $true
        }
    }
    if ($changed) {
        Set-WinUserLanguageList -LanguageList $languageList -Force
        $remaining = @(Get-WinUserLanguageList | Where-Object {
            @($_.InputMethodTips) -contains $tip
        })
        if ($remaining.Count -ne 0) {
            throw ('YimeCore trial TIP remained in language entries: ' +
                (($remaining | ForEach-Object LanguageTag) -join ', '))
        }
    }
}
