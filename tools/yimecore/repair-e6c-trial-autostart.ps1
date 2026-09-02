[CmdletBinding()]
param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$ValidateOnly,
    [string]$OutputPath
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
function Get-TrialProcessViewSnapshot {
    if (-not (Test-Path -LiteralPath $runKey)) {
        return [ordered]@{ exists = $false; kind = ''; value = $null }
    }
    $key = Get-Item -LiteralPath $runKey
    try {
        if ($key.GetValueNames() -notcontains $productKeyName) {
            return [ordered]@{ exists = $false; kind = ''; value = $null }
        }
        return [ordered]@{
            exists = $true
            kind = [string]$key.GetValueKind($productKeyName)
            value = $key.GetValue($productKeyName, $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    }
    finally { $key.Close() }
}
$targetSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$systemRunKey = "$targetSid\Software\Microsoft\Windows\CurrentVersion\Run"
function Invoke-TrialSystemRegistry([string]$Method, [hashtable]$Values) {
    $arguments = @{ hDefKey = [uint32]2147483651; sSubKeyName = $systemRunKey }
    foreach ($entry in $Values.GetEnumerator()) { $arguments[$entry.Key] = $entry.Value }
    $result = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv `
        -MethodName $Method -Arguments $arguments
    if ($null -eq $result.ReturnValue -or [int]$result.ReturnValue -notin @(0,2)) {
        throw "system registry $Method failed: $($result.ReturnValue); refusing process-view fallback"
    }
    return $result
}
function Get-TrialAutostartSnapshot {
    # StdRegProv runs outside the caller's MSIX registry overlay. HKCU in that
    # provider would select the provider account, so always address HKU/<our SID>.
    $values = Invoke-TrialSystemRegistry 'EnumValues' @{}
    if ($values.ReturnValue -eq 2) { return [ordered]@{exists=$false;kind='';value=$null} }
    $names = @($values.sNames)
    $index = [Array]::IndexOf($names, $productKeyName)
    if ($index -lt 0) { return [ordered]@{exists=$false;kind='';value=$null} }
    $kind = [string]([Microsoft.Win32.RegistryValueKind]([int]$values.Types[$index]))
    if ($kind -ne 'String') { return [ordered]@{exists=$true;kind=$kind;value=$null} }
    $read = Invoke-TrialSystemRegistry 'GetStringValue' @{sValueName=$productKeyName}
    return [ordered]@{exists=($read.ReturnValue -eq 0);kind=$kind;value=$read.sValue}
}
$processBefore = Get-TrialProcessViewSnapshot
$before = Get-TrialAutostartSnapshot
if (-not $ValidateOnly) {
    foreach ($operation in @('CreateKey', 'SetStringValue')) {
        $values = if ($operation -eq 'CreateKey') { @{} } else { @{sValueName=$productKeyName;sValue=$runValue} }
        $write = Invoke-TrialSystemRegistry $operation $values
        if ($write.ReturnValue -ne 0) { throw "system registry $operation failed: $($write.ReturnValue)" }
    }
}
$after = Get-TrialAutostartSnapshot
$processAfter = Get-TrialProcessViewSnapshot
$passed = $after.exists -and $after.kind -eq 'String' -and
    ([string]$after.value).Equals($runValue, [StringComparison]::Ordinal)
$evidence = [ordered]@{
    schema_version = 'yimecore-e6c-autostart-repair-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    validated_only = [bool]$ValidateOnly
    target_user_sid = $targetSid
    registry_key = "HKEY_USERS\$systemRunKey"
    registry_reader = 'StdRegProv/HKEY_USERS'
    system_registry_verified = [bool]$passed
    value_name = $productKeyName
    value = $runValue
    expected_value = $runValue
    before = $before
    after = $after
    process_view_before = $processBefore
    process_view_after = $processAfter
    process_view_matches_system = (($processAfter | ConvertTo-Json -Compress) -ceq ($after | ConvertTo-Json -Compress))
    registry_mutation_requested = -not [bool]$ValidateOnly
    install_root = $installRoot
    runtime_sha256 = $runtimeHash
    package_manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    passed = [bool]$passed
}
$json = $evidence | ConvertTo-Json -Depth 4
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $evidencePath = [IO.Path]::GetFullPath($OutputPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $evidencePath) | Out-Null
    $json | Set-Content -LiteralPath $evidencePath -Encoding utf8
}
if (-not $passed) {
    throw ('E6-C current-user autostart did not converge to the active runtime; ' +
        "expected REG_SZ [$runValue]; actual exists=$($after.exists), " +
        "kind=[$($after.kind)], value=[$($after.value)]")
}
$json
