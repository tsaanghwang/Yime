[CmdletBinding()]
param(
    [string]$RuntimeDir,
    [string]$LockFile
)

$ErrorActionPreference = 'Stop'

if (-not $RuntimeDir) {
    $RuntimeDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'go-backend\input_methods\yime'
}
$runtimeDir = (Resolve-Path -LiteralPath $RuntimeDir).Path
if (-not $LockFile) {
    $LockFile = Join-Path $runtimeDir 'rime_runtime.lock.json'
}
$lockPath = (Resolve-Path -LiteralPath $LockFile).Path
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json

if ($lock.schema_version -ne 1) {
    throw "Unsupported Rime runtime lock schema: $($lock.schema_version)"
}
foreach ($field in 'source', 'librime_version', 'librime_commit', 'platform') {
    if ([string]::IsNullOrWhiteSpace([string]$lock.$field)) {
        throw "Rime runtime lock is missing $field"
    }
}

$requiredFiles = @('rime.dll', 'rime_deployer.exe', 'rime_dict_manager.exe')
$declaredFiles = @($lock.files.PSObject.Properties.Name)
if (@(Compare-Object ($requiredFiles | Sort-Object) ($declaredFiles | Sort-Object)).Count -ne 0) {
    throw "Rime runtime lock must declare exactly: $($requiredFiles -join ', ')"
}

foreach ($name in $requiredFiles) {
    $path = Join-Path $runtimeDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pinned Rime runtime file is missing: $path"
    }
    $expected = [string]$lock.files.$name
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Rime runtime hash mismatch for ${name}: expected $expected, got $actual"
    }
}

$dllPath = Join-Path $runtimeDir 'rime.dll'
$dllText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dllPath))
if (-not $dllText.Contains([string]$lock.librime_version)) {
    throw "rime.dll does not identify the locked librime version $($lock.librime_version)"
}

Write-Host "Verified librime $($lock.librime_version) ($($lock.librime_commit)) for $($lock.platform)."
Write-Host "Runtime source: $($lock.source)"
