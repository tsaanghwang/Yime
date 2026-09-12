[CmdletBinding()]
param([Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][string]$ExpectedPolicySha256)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Fixed test PC only.'}
if((Get-FileHash -LiteralPath $PolicyPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPolicySha256){throw 'Recovery policy hash mismatch.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$base=Join-Path $env:USERPROFILE 'Yime Rime-PIME Test Archives'
$oldRoot=Join-Path $base 'approval-9fe7f28d-0889-4828-85b5-1f481431b43a'
$ticket=Join-Path $oldRoot 'candidate-recovery-9fe7f28d-0889-4828-85b5-1f481431b43a.json'
if((Get-FileHash -LiteralPath $ticket -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'dd6a2b8d98250b921f59a08d47a89d8ee640d8ca9d8489d29d7f7ec832f388f2'){throw 'Wrong original recovery ticket.'}
$delivery=Join-Path $repo 'test-delivery\rime-pime-coexistence-20260911-defaultstring'
$before=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'approval-*'|ForEach-Object FullName)
# Existing preparation establishes native Explorer/SID/MachineGuid and creates
# a new, expiring removal authorization without replaying installation.
& (Join-Path $PSScriptRoot 'prepare-rime-pime-coexistence-test.ps1') -DeliveryRoot $delivery -ExpectedIndexSha256 '15d4819860f462f071fbac004859eb72392229030cd42f7a93aac9f776e9af9d' -Mode Resume -RecoveryTicketPath $ticket
$new=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'approval-*'|Where-Object {$_.FullName -notin $before})
if($new.Count -ne 1){throw 'Preparation did not create exactly one new authorization; preserve output.'}
$root=$new[0].FullName
$old=Get-Content -LiteralPath (Join-Path $oldRoot 'authorization.json') -Raw -Encoding UTF8|ConvertFrom-Json
$bundle=Join-Path $root 'original-bundle'
& python (Join-Path $PSScriptRoot 'stage-defaultstring-recovery.py') $old.install_root (Join-Path $delivery 'candidate.json') $bundle
if($LASTEXITCODE -ne 0){throw 'Original bundle staging failed; preserve evidence.'}
$parameters=[ordered]@{PolicyPath=[IO.Path]::GetFullPath($PolicyPath);ExpectedPolicySha256=$ExpectedPolicySha256;ExecutionParametersPath=(Join-Path $root 'execute-parameters.json');PackageRoot=$bundle}
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $root 'recovery-validate.json'),($parameters|ConvertTo-Json),$utf8)
$parameters.Apply=$true
[IO.File]::WriteAllText((Join-Path $root 'recovery-apply.json'),($parameters|ConvertTo-Json),$utf8)
Write-Host ('Recovery parameters: '+$root)
Write-Host 'Run recovery-validate.json first. Do not execute execute-parameters.json or the old installer.'
