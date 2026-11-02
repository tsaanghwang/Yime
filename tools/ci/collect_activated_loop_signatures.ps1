param(
    [Parameter(Mandatory=$true)][string]$BinaryDirectory,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$SourceCommit
)
$ErrorActionPreference = 'Stop'
if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw 'Exact source commit required' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Output already exists' }
$names = @('YimeActivatedLoopController.exe', 'YimeActivatedLoopOnce.exe', 'YimeTextService18u.dll', 'YimeBroker18u.exe', 'YimeMyComputerActivationStage1.exe')
$files = @()
foreach ($name in $names) {
    $path = Join-Path $BinaryDirectory $name
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Regular binary required' }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    $after = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($after.Length -ne $item.Length -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) { throw 'Binary changed during signature query' }
    $thumbprint = $null
    if ($null -ne $signature.SignerCertificate) { $thumbprint = $signature.SignerCertificate.Thumbprint }
    $files += [ordered]@{ path = "bin/$name"; sha256 = $hash; bytes = $item.Length; status = [string]$signature.Status; signerThumbprint = $thumbprint }
}
$result = [ordered]@{ schema = 'activated-loop-signatures-v1'; sourceCommit = $SourceCommit; files = $files }
$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($OutputPath, $json + "`n", (New-Object Text.UTF8Encoding($false)))
