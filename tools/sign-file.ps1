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

$timestamp = $env:YIME_TIMESTAMP_URL
if ([string]::IsNullOrWhiteSpace($timestamp)) {
    $timestamp = 'http://timestamp.digicert.com'
}

& $signTool sign /sha1 $thumbprint /fd SHA256 /tr $timestamp /td SHA256 $resolved
if ($LASTEXITCODE -ne 0) {
    throw "signtool.exe failed for $resolved with exit code $LASTEXITCODE"
}
