[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'invoke-local6-failed-upgrade-rollback.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text.Contains("`$installedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'installed local.6 identity is pinned'
Check ($text.Contains("`$failureManifest='bbde69c4453a07c7cf915d641cd648f88ac8376fda0027881d857454344e1b07'")) 'failure package identity is pinned'
Check ($text.Contains("`$failureRuntime='c109d17a918d26f19146ec6ae93e97515cb2e55f8771a52f0bb9f227df0c24ac'")) 'failure runtime is pinned'
Check ($text.Contains("`$backupManifestHash='7d474b4ac32b47d68ee714e1613a2fbf756423acc8d1d67298b015cc4e435b12'")) 'independent recovery archive is pinned'
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains('Assert-LocalProductPackage $failurePackage') -and $text.Contains('rehearsal_only')) 'strict package audit and failure-only marker are required'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance') -and $text.Contains('not Run as administrator')) 'ordinary unpackaged initiator is required'
Check ($text.Contains('Assert-YimeCoreUnchangedData $backupManifest.data_files')) 'data must still match the fresh recovery archive before mutation'
Check ($text.Contains('Failure target root is occupied')) 'occupied failure target is rejected'
Check ($text.Contains("-Action Upgrade")) 'normal local-product upgrade path is exercised'
Check ($text.Contains("`$maintenanceErrorItem.LastWriteTimeUtc -ge `$attemptStartedUtc") -and $text.Contains("`$maintenanceErrorText -match 'trial runtime did not become ready'") -and $text.Contains('[regex]::Escape($failurePackage)')) 'authoritative maintenance error is time and package correlated'
Check ($text.Contains('Same $beforeRegistry $afterRegistry')) 'complete system registry rollback is compared'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData')) 'user data rollback is compared'
Check ($text.Contains('Assert-LocalProductLiveRuntime $afterContext')) 'ordinary restored runtime is verified'
Check ($text.Contains("-Action Verify")) 'restored three-mode behavior is verified'
Check ($text.Contains('independent_recovery_archive_preserved=$passed')) 'independent recovery media preservation is recorded'
Check ($text.Contains('maintenance_error_correlated=$failureTriggered')) 'summary records authoritative failure correlation'
Check ($text.Contains('default_input_method_changed=$false') -and $text.Contains('production_components_changed=$false')) 'production and default input remain outside mutation scope'
Check ($text.Contains('reboot_requested=$false') -and $text.Contains('local_product_ready=$false')) 'acceptance does not reboot or overclaim readiness'
$completePath=Join-Path $PSScriptRoot 'complete-local6-failed-upgrade.ps1'
$complete=Get-Content -LiteralPath $completePath -Raw -Encoding UTF8
$completeTokens=$null;$completeErrors=$null
[Management.Automation.Language.Parser]::ParseFile($completePath,[ref]$completeTokens,[ref]$completeErrors)|Out-Null
Check ($completeErrors.Count -eq 0) 'corrected postacceptance script parses'
Check ($complete -notmatch '[^\u0000-\u007f]') 'corrected postacceptance is ASCII-safe for Windows PowerShell 5.1'
Check ($complete.Contains("`$evidence='C:\Users\tsaan\YimeCore Recovery Archives\local6-failed-upgrade-rollback-20260903-110721-19d95018'")) 'false-negative evidence is pinned'
Check ($complete.Contains('original_summary_preserved') -and $complete.Contains('failure_not_repeated=$true')) 'original failure is preserved and not repeated'
Check ($complete.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData') -and $complete.Contains('Same $beforeRegistry $afterRegistry')) 'correction independently compares data and registry'
Check ($complete.Contains("`$beforeData=Get-Content -LiteralPath (Join-Path `$evidence 'data-before.json') -Raw -Encoding UTF8|ConvertFrom-Json") -and
    $complete.Contains('`$beforeData=@(`$beforeData)'.Replace('`$','$'))) 'Windows PowerShell 5.1 evidence array is expanded in two steps'
Check ($complete.Contains('Assert-LocalProductLiveRuntime $context') -and $complete.Contains('YimeCoreIndependenceAudit.exe')) 'correction verifies live runtime and installed package'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-failed-upgrade-rollback-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_failed_upgrade_executed=$false}|ConvertTo-Json -Depth 6|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.6 failed-upgrade rollback contracts. Evidence: $out"
