param([switch]$IncludeInstaller)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patterns = @(
    'build\PIMELauncher\PIMELauncher.exe',
    'build\PIMETextService\Release\PIMETextService.dll',
    'build64\PIMETextService\Release\PIMETextService.dll',
    'go-backend\build\go-backend\*.exe',
    'go-backend\build\go-backend\input_methods\yime\rime_deployer.exe',
    'go-backend\build\go-backend\input_methods\yime\rime.dll'
)
if (Test-Path -LiteralPath (Join-Path $root 'build_arm64\PIMETextService\Release\PIMETextService.dll')) {
    $patterns += 'build_arm64\PIMETextService\Release\PIMETextService.dll'
}
if ($IncludeInstaller) {
    $patterns += 'installer\YIME-*-setup.exe'
}

$files = foreach ($pattern in $patterns) {
    Get-ChildItem -Path (Join-Path $root $pattern) -File -ErrorAction SilentlyContinue
}
if (-not $files) {
    throw 'No release files were found for signature verification.'
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
