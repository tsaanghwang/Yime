param(
	[switch]$IncludeInstaller,
	[switch]$RequireComplete,
	[string]$Root = (Split-Path -Parent $PSScriptRoot),
	[string]$PackagePlanPath,
	[string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Root).Path
$packageModule=Join-Path $PSScriptRoot 'dual-product\rime-pime-package-plan.ps1'
. $packageModule
if (-not $PackagePlanPath) { $PackagePlanPath=Join-Path $root 'installer\package-plan.json' }
$canonicalReceiptPath=Join-Path $root 'installer\package-build-receipt.json'
$receiptEnvelope=Read-RimePimePackageBuildReceiptEnvelope -RepoRoot $root -ReceiptPath $canonicalReceiptPath
if ([string]$receiptEnvelope.State -ceq 'present' -and
    [string]$receiptEnvelope.SchemaVersion -cne 'yime-rime-pime-package-build-receipt-v1') {
    throw "Release signing refuses canonical package receipt schema $($receiptEnvelope.SchemaVersion); disabled v2 evidence cannot be signed or rewritten as v1."
}
if (-not $ReceiptPath) { $ReceiptPath=$canonicalReceiptPath }
if ([IO.Path]::GetFullPath($ReceiptPath) -ine [IO.Path]::GetFullPath($canonicalReceiptPath)) {
    throw 'Release signing accepts only the canonical package build receipt path.'
}
if ($IncludeInstaller -and [string]$receiptEnvelope.State -ne 'present') {
    throw 'Installer signing requires one complete canonical v1 receipt pair.'
}
if (-not $IncludeInstaller -and [string]$receiptEnvelope.State -eq 'present') {
    throw 'Payload-only signing requires an absent canonical installer receipt so it cannot invalidate an existing v1 bundle.'
}
$package=Read-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath -VerifyArtifacts
$files=@()
if ($IncludeInstaller) {
    $receipt=Read-RimePimePackageBuildReceipt -Package $package -ReceiptPath $ReceiptPath
    $files=@($receipt.InstallerPath)
} else {
    $files=@($package.Plan.artifacts | ForEach-Object { $_.path.Replace('/','\') })
}

foreach ($file in $files) {
    $path = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $root $file }
    if (-not (Test-Path -LiteralPath $path)) {
        if ($RequireComplete) {
            throw "Required release file is missing: $path"
        }
        Write-Warning "Release file is missing: $path"
        continue
    }
    & (Join-Path $PSScriptRoot 'sign-file.ps1') -Path $path
}

if ($IncludeInstaller) {
    Write-RimePimePackageBuildReceipt -Package $package -InstallerPath $receipt.InstallerPath `
        -InstallerSourcePath $receipt.InstallerSourcePath -ReceiptPath $ReceiptPath | Out-Null
} else {
    Write-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath `
        -ArchitectureSet @($package.Plan.architectures) | Out-Null
}
