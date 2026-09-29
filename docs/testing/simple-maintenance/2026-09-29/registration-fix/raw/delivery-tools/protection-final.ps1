$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$delivery='C:\dev\Yime-deliveries\registration-fix-20260929'
. (Join-Path $repo 'tools/yimecore/build-system-observation.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-build-common.ps1')
$before=Get-Content -LiteralPath (Join-Path $repo '.tmp/yimecore-local-product/r/protection-before.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$after=Get-LocalProductProtectionEvidence -HashesOnly
Write-LocalProductJson $after (Join-Path $delivery 'protection-final.json')
$same=($before|ConvertTo-Json -Depth 30 -Compress) -ceq ($after|ConvertTo-Json -Depth 30 -Compress)
Write-LocalProductJson ([ordered]@{passed=$same;scope='Out-of-process machine/user TSF/COM registrations, language/default/startup values; read-only comparison after package validation';live_installation_executed=$false}) (Join-Path $delivery 'registration-preservation.json')
if(-not $same){throw 'Registration/default hash observation differs; preserve evidence.'}
Write-Output 'PASS: system-view registration/default/startup hashes preserved after package validation.'
