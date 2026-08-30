[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$productKeyName = 'YimeCoreExperimentalTrial'
$expectedClsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$configPath = Join-Path $stateRootPath 'runtime-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "missing E6-C runtime configuration: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$installRoot = [IO.Path]::GetFullPath([string]$config.install_root)
$runtimePath = [IO.Path]::GetFullPath([string]$config.runtime_path)
$configuredStateRoot = [IO.Path]::GetFullPath([string]$config.state_root)
$productRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'YimeCore Experimental Trial'))
$productPrefix = $productRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
    [IO.Path]::DirectorySeparatorChar
$expectedRuntimePath = [IO.Path]::GetFullPath((Join-Path $installRoot 'bin\YimeCoreTrialRuntime.exe'))
if (-not $installRoot.StartsWith($productPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $runtimePath.Equals($expectedRuntimePath, [StringComparison]::OrdinalIgnoreCase) -or
    -not $configuredStateRoot.Equals($stateRootPath, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([string]$config.experimental_clsid).Equals($expectedClsid, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'refusing to create autostart from an invalid E6-C runtime configuration'
}
$manifestPath = Join-Path $installRoot 'package-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw 'configured E6-C installation is incomplete'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeRecord = @($manifest.files | Where-Object { $_.path -eq 'bin/YimeCoreTrialRuntime.exe' })
$runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($runtimeRecord.Count -ne 1 -or
    $runtimeHash -ne ([string]$runtimeRecord[0].sha256).ToLowerInvariant()) {
    throw 'configured E6-C runtime does not match its package manifest'
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue = '"{0}" -no-toolbar' -f $runtimePath
if (-not $ValidateOnly) {
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -LiteralPath $runKey -Name $productKeyName -Value $runValue `
        -PropertyType String -Force | Out-Null
}
$actualValue = if ($ValidateOnly) { $runValue } else {
    [string](Get-ItemPropertyValue -LiteralPath $runKey -Name $productKeyName)
}
if (-not $actualValue.Equals($runValue, [StringComparison]::Ordinal)) {
    throw 'E6-C current-user autostart did not converge to the active runtime'
}
[ordered]@{
    schema_version = 'yimecore-e6c-autostart-repair-v1'
    validated_only = [bool]$ValidateOnly
    target_user_sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    registry_key = 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
    value_name = $productKeyName
    value = $runValue
    install_root = $installRoot
    runtime_sha256 = $runtimeHash
    package_manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    passed = $true
} | ConvertTo-Json -Depth 4
