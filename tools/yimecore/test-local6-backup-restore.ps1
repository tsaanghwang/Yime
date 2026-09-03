[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'invoke-local6-backup-restore.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text.Contains("`$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'installed local.6 manifest is pinned'
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance')) 'unpackaged native context is mandatory'
Check ($text.Contains('not Run as administrator')) 'ordinary user entry is mandatory'
Check ($text.Contains("Get-Process WINWORD,Notepad")) 'interactive hosts must be closed'
Check ($text.Contains('Assert-LocalProductLiveRuntime $context')) 'live runtime is required before maintenance'
Check ($text.Contains("-Action Backup -BackupRoot `$archive")) 'installed package backup entry is used'
Check ($text.IndexOf("`$stage='fresh-backup'") -lt $text.IndexOf("`$stage='live-restore'")) 'fresh backup precedes restore'
Check ($text.Contains("-Action Restore -BackupRoot `$archive")) 'installed package restore entry is used'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData')) 'data records must be byte-identical after restore'
Check ($text.Contains('Same $beforeRegistry $afterRegistry')) 'data-only restore must preserve the full registry snapshot'
Check ($text.Contains('Assert-LocalProductLiveRuntime $afterContext')) 'ordinary runtime is reverified after restore'
Check ($text.Contains("-Action Verify")) 'three-mode verification follows restore'
Check ($text.Contains('original_model_preserved=$passed')) 'summary records original model preservation'
Check ($text.Contains('production_components_changed=$false') -and $text.Contains('default_input_method_changed=$false')) 'production and default input are outside mutation scope'
Check ($text.Contains('reboot_requested=$false') -and $text.Contains('local_product_ready=$false')) 'acceptance does not reboot or overclaim readiness'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-backup-restore-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_backup_or_restore_executed=$false}|ConvertTo-Json -Depth 6|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.6 backup/restore contracts. Evidence: $out"
