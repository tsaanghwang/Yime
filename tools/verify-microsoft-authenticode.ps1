param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Path).Path
$item = Get-Item -LiteralPath $resolved
if (-not $item.PSIsContainer -and $item.Extension -ieq '.exe') {
    $signature = Get-AuthenticodeSignature -LiteralPath $resolved
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw "Authenticode verification failed for ${resolved}: $($signature.Status)"
    }
    if ($signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Unexpected Authenticode signer for ${resolved}: $($signature.SignerCertificate.Subject)"
    }
    $codeSigningOid = '1.3.6.1.5.5.7.3.3'
    $ekuOids = @($signature.SignerCertificate.EnhancedKeyUsageList | ForEach-Object {
        if ($_.ObjectId -is [string]) { $_.ObjectId } else { $_.ObjectId.Value }
    })
    if ($ekuOids -notcontains $codeSigningOid) {
        throw "Signer certificate is not valid for code signing: $resolved"
    }
    exit 0
}
throw "Expected a regular executable file: $resolved"
