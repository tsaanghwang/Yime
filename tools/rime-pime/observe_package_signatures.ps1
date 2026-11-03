[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PackageRoot)
$paths=@((Join-Path $root 'YimeMaintenance.exe'),(Join-Path $root 'maintenance/powershell/pwsh.exe'))
$paths+=@(Get-ChildItem -LiteralPath (Join-Path $root 'payload') -Recurse -File | Where-Object {$_.Extension -in @('.exe','.dll')} | ForEach-Object {$_.FullName})
$rows=@(foreach($path in $paths){
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    [ordered]@{path=$path.Substring($root.Length+1).Replace('\','/');status=$signature.Status.ToString();
        sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();
        subject=$(if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{''});
        thumbprint=$(if($signature.SignerCertificate){$signature.SignerCertificate.Thumbprint}else{''})}
})
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),([ordered]@{schema=1;observedUtc=[DateTime]::UtcNow.ToString('o');files=$rows}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ('Recorded signatures of '+$rows.Count+' package binaries; observation is not publisher authentication for unsigned development binaries')
