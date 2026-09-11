[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionParametersPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Identified test PC only.'}
$p=Get-Content -LiteralPath $ExecutionParametersPath -Raw -Encoding UTF8|ConvertFrom-Json
$pkg=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru
& $pkg {param($v) Assert-CandidateObject $v @('Mode','InstallerPath','ExpectedInstallerSha256','AuthorizationPath','TrustedApprovalSha256','BoundaryPath','ReceiptPath','PreparedSha256');Assert-CandidateHash $v.PreparedSha256;Assert-CandidateHash $v.TrustedApprovalSha256} $p
$installerHash='0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617'
$receiptHash='c4badd8cc2c3b06389ed044f08bcfb0383eb963affe5ca93a3e1c5e870eea4a1'
$manifestHash='3f676b80b86f4c752e96c5ed06655bddb3b5b4aedd762ca8369483e7ae14b01d'
if($p.Mode -cne 'Resume' -or $p.ExpectedInstallerSha256 -cne $installerHash){throw 'Only original fixed-package Resume transport supported.'}
Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-receipt.psm1')
Import-Module (Join-Path $PSScriptRoot 'legacy-resume-transport.psm1')
$null=Read-RimePimeExecutableReceipt -ReceiptPath $p.ReceiptPath -ExpectedReceiptSha256 $receiptHash -InstallerPath $p.InstallerPath -ExpectedInstallerSha256 $installerHash -ExpectedManifestSha256 $manifestHash
$root=Join-Path $env:USERPROFILE ('YRP-'+[guid]::NewGuid().ToString('N').Substring(0,12))
for($dir=$root;$dir;$dir=[IO.Path]::GetDirectoryName($dir)){
    if($dir -match '(?i)\\AppData(?:\\|$)' -or (Test-Path -LiteralPath (Join-Path $dir '.git'))){throw 'Staging must be outside AppData and Git.'}
    if((Test-Path -LiteralPath $dir) -and ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect staging path.'}
}
if(Test-Path -LiteralPath $root){throw 'Fresh staging root required.'}
$originalInstaller=$p.InstallerPath;$originalReceipt=$p.ReceiptPath
$p.InstallerPath=Join-Path $root 'p.exe';$p.ReceiptPath=Join-Path $root 'r.json'
$bound=Get-LegacyResumeCommandBound $p ([IO.Path]::GetTempPath()) $env:SystemRoot
if($bound -gt 1000){throw 'Short transport still exceeds conservative legacy command budget.'}
$null=[IO.Directory]::CreateDirectory($root)
# Copy bytes only; do not rewrite/sign/patch the original installer or receipt.
[IO.File]::Copy($originalInstaller,$p.InstallerPath,$false)
[IO.File]::Copy($originalReceipt,$p.ReceiptPath,$false)
$null=Read-RimePimeExecutableReceipt -ReceiptPath $p.ReceiptPath -ExpectedReceiptSha256 $receiptHash -InstallerPath $p.InstallerPath -ExpectedInstallerSha256 $installerHash -ExpectedManifestSha256 $manifestHash
function Save([string]$Name,$Value){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Value -Depth 8))
    $s=[IO.File]::Open((Join-Path $root $Name),'CreateNew','Write','None')
    try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
}
Save 'execute.json' $p
Save 'transport.json' ([ordered]@{schema_version='yime-original-resume-transport-v1';installer_sha256=$installerHash;receipt_sha256=$receiptHash;command_length_upper_bound=$bound;original_parameters_sha256=(Get-FileHash -LiteralPath $ExecutionParametersPath).Hash.ToLowerInvariant();maintenance_executed=$false})
Write-Output ('Prepared byte-identical transport only: '+(Join-Path $root 'execute.json'))
