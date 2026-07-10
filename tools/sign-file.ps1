param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Path).Path
$thumbprint = $env:YIME_SIGN_CERT_SHA1
if ([string]::IsNullOrWhiteSpace($thumbprint)) {
    if ($env:YIME_RELEASE_SIGNING_REQUIRED -eq '1') {
        throw "Release signing is required, but YIME_SIGN_CERT_SHA1 is not set."
    }
    Write-Host "[WARN] Signing skipped for $resolved"
    exit 0
}

$signTool = $env:YIME_SIGNTOOL_EXE
if ([string]::IsNullOrWhiteSpace($signTool)) {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        $signTool = $command.Source
    }
}
if ([string]::IsNullOrWhiteSpace($signTool) -or -not (Test-Path -LiteralPath $signTool)) {
    throw 'signtool.exe was not found. Set YIME_SIGNTOOL_EXE.'
}

$certificate = @(
    Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $thumbprint }
) | Select-Object -First 1
if (-not $certificate) {
    throw "The signing certificate $thumbprint was not found."
}
if (-not $certificate.HasPrivateKey) {
    throw 'The signing certificate does not have an accessible private key.'
}
if ($certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) {
    throw 'The signing certificate is outside its validity period.'
}
if ($certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') {
    throw 'Yime release signing requires an RSA certificate.'
}
$codeSigningOid = '1.3.6.1.5.5.7.3.3'
if ($certificate.EnhancedKeyUsageList.ObjectId.Value -notcontains $codeSigningOid) {
    throw 'The signing certificate is not valid for code signing.'
}

$timestamp = $env:YIME_TIMESTAMP_URL
if ([string]::IsNullOrWhiteSpace($timestamp)) {
    $timestamp = 'http://timestamp.digicert.com'
}

& $signTool sign /sha1 $thumbprint /fd SHA256 /tr $timestamp /td SHA256 $resolved
if ($LASTEXITCODE -ne 0) {
    throw "signtool.exe failed for $resolved with exit code $LASTEXITCODE"
}
