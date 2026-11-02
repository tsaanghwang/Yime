# Read only the two PE payloads; never load or execute them.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DllPath,
    [Parameter(Mandatory=$true)][string]$ToolPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rows = @()
$inputs = @(
    @{ Path = $DllPath; Name = 'YimeTextService18u.dll' },
    @{ Path = $ToolPath; Name = 'YimeMyComputerActivationStage1.exe' }
)
foreach ($inputFile in $inputs) {
    $file = Get-Item -LiteralPath $inputFile.Path
    if ($file.PSIsContainer -or $file.Name -cne $inputFile.Name) { throw 'Unexpected signature input' }
    $before = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    $after = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($before -cne $after) { throw 'Signature input changed while queried' }
    $signer = $null
    $timestamp = $null
    if ($null -ne $signature.SignerCertificate) { $signer = $signature.SignerCertificate.Thumbprint }
    if ($null -ne $signature.TimeStamperCertificate) { $timestamp = $signature.TimeStamperCertificate.Thumbprint }
    $rows += [ordered]@{
        name = $inputFile.Name
        sha256 = $before
        status = $signature.Status.ToString()
        signerCertificateThumbprint = $signer
        timestampCertificateThumbprint = $timestamp
    }
}
$record = [ordered]@{ schema = 'mycomputer-authenticode-v1'; files = @($rows) }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Depth 8))
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
