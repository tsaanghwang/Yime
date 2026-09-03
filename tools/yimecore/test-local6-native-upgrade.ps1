[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path $PSScriptRoot 'invoke-local6-native-upgrade.ps1'
$text=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text.Contains("`$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'candidate manifest is pinned'
Check ($text.Contains("`$expectedPreviousManifest='2631aeb3634f6bc103771e12e3a8d6748bd87123f890afb2ae874b1d06706c7a'")) 'repaired local.5 baseline is pinned'
Check ($text.Contains("`$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'")) 'read-only registry validator is pinned'
Check ($text.Contains('Restore-FrozenUserTipSnapshot $migrationLegacyUserTipSnapshot')) 'package must contain final frozen user TIP restoration'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance')) 'native unpackaged context is mandatory'
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance script is ASCII-safe when Windows PowerShell reads a no-BOM file'
Check ($text.Contains("if(`$principal.IsInRole") -and $text.Contains('not Run as administrator')) 'ordinary Explorer initiator is mandatory'
Check ($text.Contains("-Action Plan") -and $text.IndexOf("if(-not `$Execute)") -gt $text.IndexOf("-Action Plan")) 'read-only plan precedes execute gate'
Check ($text.Contains("if(Test-Path -LiteralPath ([string]`$plan.install_root))")) 'occupied target is rejected'
Check ($text.Contains("previous-package-audit.json") -and $text.Contains("candidate-package-audit.json")) 'both packages are independently audited'
Check ($text.IndexOf("`$stage='fresh-backup'") -lt $text.IndexOf("`$stage='upgrade'")) 'fresh backup precedes upgrade'
Check ($text.Contains("-Action Upgrade")) 'package upgrade entry is used'
Check ($text.Contains('Assert-LocalProductLiveRuntime $context')) 'ordinary installed runtime is verified'
Check ($text.Contains("-Action Verify")) 'installed three-mode verification is required'
Check ($text.Contains('Same $before.protected $after.protected')) 'protected registry is byte-shape compared'
Check ($text.Contains('Same $before.language_profile $after.language_profile')) 'language profile is unchanged on same-identity upgrade'
Check ($text.Contains('Assert-YimeCoreUnchangedData $saved.data_files')) 'user data continuity is enforced'
Check ($text.Contains('Assert-FrozenPayloads $plan')) 'frozen payload roots are manifest verified'
Check ($text.Contains('function Get-AcceptanceExceptionEvidence') -and $text.Contains('Get-AcceptanceExceptionEvidence $_.Exception')) 'failure evidence has a self-contained exception serializer'
Check ($text.Contains('reboot_requested=$false') -and $text.Contains('local_product_ready=$false')) 'upgrade does not overclaim readiness or request reboot'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-native-upgrade-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_upgrade_executed=$false}|ConvertTo-Json -Depth 6|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.6 native upgrade contracts. Evidence: $out"
