[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$NativeRoot,
    [Parameter(Mandatory)][string]$GoRoot,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
if ($SourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Full source base SHA required' }
if (Test-Path -LiteralPath $ReportPath) { throw 'Choose a fresh signature report' }
$members = @(
    @{ Path='payload/arm64/YimeTextService18u.dll'; Source=(Join-Path $NativeRoot 'YimeTextService18u.dll') },
    @{ Path='payload/arm64/Yime18uProductRegistration.exe'; Source=(Join-Path $NativeRoot 'Yime18uProductRegistration.exe') },
    @{ Path='payload/arm64/YimeTouchRegisteredFormalHostTests.exe'; Source=(Join-Path $NativeRoot 'YimeTouchRegisteredFormalHostTests.exe') },
    @{ Path='payload/bin/YimeBroker18u.exe'; Source=(Join-Path $GoRoot 'YimeBroker18u.exe') },
    @{ Path='payload/bin/Yime18uInstalledRuntime.exe'; Source=(Join-Path $GoRoot 'Yime18uInstalledRuntime.exe') },
    @{ Path='payload/bin/YimeTouchKeyboard.exe'; Source=(Join-Path $GoRoot 'YimeTouchKeyboard.exe') }
)
$rows = foreach ($member in $members) {
    $file = Get-Item -LiteralPath $member.Source
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    $thumbprint = $null
    if ($null -ne $signature.SignerCertificate) { $thumbprint = $signature.SignerCertificate.Thumbprint }
    [ordered]@{ path=$member.Path; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); status=[string]$signature.Status; signerThumbprint=$thumbprint }
}
[ordered]@{ schema='installed-18u-signatures-v1'; sourceCommit=$SourceCommit; files=@($rows) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
Write-Output ('Observed six PE signatures: ' + $ReportPath)
