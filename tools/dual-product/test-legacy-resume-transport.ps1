$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'legacy-resume-transport.psm1') -Force
$base='C:\Users\Golde\Yime Rime-PIME Test Archives\approval-fa4e23d2-e352-4e44-ad7c-b96162f91e67'
$delivery='C:\dev\Yime-localtest\test-delivery\rime-pime-coexistence-20260911-empty'
$p=[pscustomobject]@{InstallerPath=($delivery+'\YIME-RimePime-1.4.0-dev.1-candidate.exe');ReceiptPath=($delivery+'\executable-build-receipt.json');AuthorizationPath=($base+'\authorization.json');BoundaryPath=($base+'\boundary.json');TrustedApprovalSha256=('a'*64);PreparedSha256=('b'*64)}
$long=Get-LegacyResumeCommandBound $p 'C:\Users\Golde\AppData\Local\Temp' 'C:\Windows'
if($long -le 1023){throw 'Known failing path was not rejected.'}
$p.InstallerPath='C:\Users\Golde\YRP-0123456789ab\p.exe';$p.ReceiptPath='C:\Users\Golde\YRP-0123456789ab\r.json'
$short=Get-LegacyResumeCommandBound $p 'C:\Users\Golde\AppData\Local\Temp' 'C:\Windows'
if($short -gt 1000){throw 'Short transport does not fit.'}
$tooLong=Get-LegacyResumeCommandBound $p ('C:\'+('x'*200)) 'C:\Windows'
if($tooLong -le 1000){throw 'Long temp root escaped budget check.'}
# Confirm original receipt accepts byte-identical copies, retaining all digest checks.
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$original=Join-Path $repo 'test-delivery\rime-pime-coexistence-20260911-empty'
$out=Join-Path $repo ('.tmp\legacy-transport-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($out)
[IO.File]::Copy((Join-Path $original 'YIME-RimePime-1.4.0-dev.1-candidate.exe'),(Join-Path $out 'p.exe'),$false)
[IO.File]::Copy((Join-Path $original 'executable-build-receipt.json'),(Join-Path $out 'r.json'),$false)
Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-receipt.psm1') -Force
$receiptParameters=@{ReceiptPath=(Join-Path $out 'r.json');ExpectedReceiptSha256='c4badd8cc2c3b06389ed044f08bcfb0383eb963affe5ca93a3e1c5e870eea4a1';InstallerPath=(Join-Path $out 'p.exe');ExpectedInstallerSha256='0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617';ExpectedManifestSha256='3f676b80b86f4c752e96c5ed06655bddb3b5b4aedd762ca8369483e7ae14b01d'}
$null=Read-RimePimeExecutableReceipt @receiptParameters
$receiptParameters.ExpectedInstallerSha256='a'*64
$rejected=$false
try{$null=Read-RimePimeExecutableReceipt @receiptParameters}catch{$rejected=$true}
if(-not $rejected){throw 'Changed package digest accepted.'}
Write-Output ('PASS: legacy bounds '+$long+' -> '+$short+'; long temp rejected; original receipt validates relocated bytes and rejects wrong hash. No EXE executed.')
