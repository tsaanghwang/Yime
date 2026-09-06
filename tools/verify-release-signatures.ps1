param(
	[switch]$IncludeInstaller,
	[string]$Root = (Split-Path -Parent $PSScriptRoot),
	[string]$PackagePlanPath,
	[string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Root).Path
$packageModule=Join-Path $PSScriptRoot 'dual-product\rime-pime-package-plan.ps1'
. $packageModule
if (-not $PackagePlanPath) { $PackagePlanPath=Join-Path $root 'installer\package-plan.json' }
$package=Read-RimePimePackagePlan -RepoRoot $root -PlanPath $PackagePlanPath -VerifyArtifacts
$files=@($package.Plan.artifacts | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $root $_.path.Replace('/','\')) -ErrorAction Stop
})
if ($IncludeInstaller) {
    if (-not $ReceiptPath) { $ReceiptPath=Join-Path $root 'installer\package-build-receipt.json' }
    $receipt=Read-RimePimePackageBuildReceipt -Package $package -ReceiptPath $ReceiptPath
    $files+=@(Get-Item -LiteralPath $receipt.InstallerPath -ErrorAction Stop)
}
$invalid = foreach ($file in $files | Sort-Object FullName -Unique) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    Write-Host "$($signature.Status)`t$($file.FullName)"
    $wrongSigner = (-not [string]::IsNullOrWhiteSpace($env:YIME_SIGN_CERT_SHA1)) -and ($signature.SignerCertificate.Thumbprint -ne $env:YIME_SIGN_CERT_SHA1)
    $missingTimestamp = $null -eq $signature.TimeStamperCertificate
    if ($signature.Status -ne 'Valid' -or $wrongSigner -or $missingTimestamp) {
        if ($wrongSigner) { Write-Warning "Unexpected signer for $($file.FullName)" }
        if ($missingTimestamp) { Write-Warning "Missing timestamp for $($file.FullName)" }
        $file.FullName
    }
}
if ($invalid) {
    throw "Unsigned or invalid release files:`n$($invalid -join "`n")"
}
