param()

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:YIME_SIGN_CERT_BASE64)) {
    throw 'Tagged releases require YIME_SIGN_CERT_BASE64.'
}
if ([string]::IsNullOrWhiteSpace($env:YIME_SIGN_CERT_PASSWORD)) {
    throw 'Tagged releases require YIME_SIGN_CERT_PASSWORD.'
}
if ([string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    throw 'GITHUB_ENV is required when importing the release certificate.'
}

$pfxPath = Join-Path $env:RUNNER_TEMP 'yime-release.pfx'
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:YIME_SIGN_CERT_BASE64))
try {
    $password = ConvertTo-SecureString $env:YIME_SIGN_CERT_PASSWORD -AsPlainText -Force
    $certificate = @(Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\CurrentUser\My -Password $password) |
        Where-Object HasPrivateKey | Select-Object -First 1
} finally {
    Remove-Item -LiteralPath $pfxPath -Force -ErrorAction SilentlyContinue
}
if (-not $certificate) {
    throw 'The release certificate could not be imported.'
}

$signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signTool) {
    throw 'signtool.exe was not found in the Windows SDK.'
}

"YIME_SIGN_CERT_SHA1=$($certificate.Thumbprint)" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
"YIME_SIGNTOOL_EXE=$($signTool.FullName)" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
'YIME_RELEASE_SIGNING_REQUIRED=1' | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
