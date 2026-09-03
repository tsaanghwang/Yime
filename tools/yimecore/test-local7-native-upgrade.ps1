[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path $PSScriptRoot 'invoke-local7-native-upgrade.ps1'
$text=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text.Contains("`$package='C:\dev\Yime\.tmp\yimecore-local-product\local7-build-20260903-1645\package'")) 'candidate path is pinned'
Check ($text.Contains("`$expectedManifest='0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb'")) 'candidate manifest is pinned'
Check ($text.Contains("`$expectedPreviousManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'repaired local.6 baseline is pinned'
Check ($text.Contains("`$expectedManager='4680a94aada563e2fc988529dca27050c5ce43dd7e447577093e2a4a93d721c5'")) 'fixed maintenance manager is pinned'
Check ($text.Contains('Enable-TargetUserTip $userTipKey $profile')) 'package must enable a newly created active user TIP'
Check ($text.Contains('Restore-FrozenUserTipSnapshot $migrationLegacyUserTipSnapshot')) 'package must preserve frozen user TIP state'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance')) 'native unpackaged context is mandatory'
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance script is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains('Read-ActiveUserTip') -and $text.Contains("Require-CutoverValue `$profile.values 'Enable' 4 '1'")) 'system-view active TIP Enable DWORD is required'
Check ($text.Contains('Same $activeUserTipBefore $activeUserTipAfter')) 'active user TIP is byte-shape preserved during upgrade'
Check ($text.Contains("if(`$principal.IsInRole") -and $text.Contains('not Run as administrator')) 'ordinary Explorer initiator is mandatory'
Check ($text.Contains('-Action Plan') -and $text.IndexOf('if(-not $Execute)') -gt $text.IndexOf('-Action Plan')) 'read-only plan precedes execute gate'
Check ($text.Contains("if(Test-Path -LiteralPath ([string]`$plan.install_root))")) 'occupied target is rejected'
Check ($text.Contains('previous-package-audit.json') -and $text.Contains('candidate-package-audit.json')) 'both packages are independently audited'
Check ($text.IndexOf("`$stage='fresh-backup'") -lt $text.IndexOf("`$stage='upgrade'")) 'fresh backup precedes upgrade'
Check ($text.Contains('-Action Upgrade')) 'package upgrade entry is used'
Check ($text.Contains('Assert-LocalProductLiveRuntime $context')) 'ordinary installed runtime is verified'
Check ($text.Contains('-Action Verify')) 'installed three-mode verification is required'
Check ($text.Contains('Same $before.protected $after.protected')) 'protected registry is byte-shape compared'
Check ($text.Contains('Same $before.language_profile $after.language_profile')) 'language profile is unchanged on same-identity upgrade'
Check ($text.Contains('Assert-YimeCoreUnchangedData $saved.data_files')) 'user data continuity is enforced'
Check ($text.Contains('Assert-FrozenPayloads $plan')) 'frozen payload roots are manifest verified'
Check ($text.Contains('active_user_tip_enabled_and_preserved=$passed')) 'acceptance reports the taskbar-enabling state without overclaiming'
Check ($text.Contains('reboot_requested=$false') -and $text.Contains('local_product_ready=$false')) 'upgrade does not overclaim readiness or request reboot'
$entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Upgrade-YimeCore-Local7.cmd') -Raw -Encoding UTF8
Check ($entry.Contains('invoke-local7-native-upgrade.ps1') -and $entry.Contains('-Execute')) 'Explorer entry invokes the pinned acceptance'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local7-native-upgrade-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_upgrade_executed=$false}|ConvertTo-Json -Depth 6|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.7 native upgrade contracts. Evidence: $out"
