[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'recover-local8-from-local7-uninstall.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text -notmatch '[^\u0000-\u007f]') 'recovery source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains("`$candidate='C:\dev\Yime\.tmp\yimecore-local-product\local8-build-20260903-1705\package'")) 'local.8 candidate path is pinned'
Check ($text.Contains("`$expectedManifest='0354fd33fcae9171004ecd7c9a33f2e56bcf27c2cc99e58fbf857bc67e8e1fc2'")) 'local.8 candidate manifest is pinned'
Check ($text.Contains("`$expectedManager='70d6c04c85d35d018c69510b7158198f13d08efb1d12dffb707972d3e762d4df'")) 'fixed local.8 manager is pinned'
Check ($text.Contains('local7-uninstall-reinstall-20260903-165714-7550706e')) 'failed local.7 evidence is pinned'
Check ($text.Contains("`$failedManifest='0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb'")) 'failed local.7 package identity is pinned'
Check ($text.Contains('Remove-TargetUserTipState') -and $text.Contains('Test-RestorablePreviousUserTipSnapshot $previousRoot $previousUserTipSnapshot')) 'candidate must contain both reviewed TIP fixes'
Check ($text.Contains('failedSummary.passed') -and $text.Contains('failedSummary.uninstalled') -and $text.Contains('failedSummary.reinstalled')) 'recovery requires the exact interrupted stage'
Check ($text.Contains('Pinned local.7 recovery media changed.')) 'both retained local.7 recovery packages are hash pinned'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance') -and $text.Contains('not Run as administrator')) 'ordinary unpackaged Explorer initiator is mandatory'
Check ($text.Contains('Get-Process WINWORD') -and $text.Contains('Close Word')) 'Word must be closed before recovery'
Check ($text.IndexOf("`$stage='verify-failed-uninstall'") -lt $text.IndexOf("`$stage='install-local8'")) 'failed-uninstall validation precedes installation'
Check ($text.Contains('Assert-Enable $currentTip 0') -and $text.Contains('Same $currentTip $expectedStaleTip')) 'current stale DWORD Enable=0 state is exact'
Check ($text.Contains('Test-TipSnapshotSemanticallyAbsent $currentSystem.native_tip') -and $text.Contains('Test-TipSnapshotSemanticallyAbsent $currentSystem.mirrored_tip')) 'machine registration remains semantically absent before recovery'
Check ($text.Contains('runtime-config.json') -and $text.Contains('runtime-status.json')) 'active runtime state must remain absent before recovery'
Check ($text.Contains('unexpectedRuntime') -and $text.Contains('Close leftover YimeCore runtime processes before recovery')) 'uninstalled state rejects any leftover project runtime image'
Check ($text.Contains('Get-WinUserLanguageList') -and $text.Contains('Failed uninstall language list is not clean.')) 'TIP language-list absence is verified before recovery'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData')) 'user data is checked before and after recovery'
Check ($text.Contains('Assert-YimeCoreArchiveRecords') -and $text.Contains('backupManifestHash')) 'independent recovery media stays intact'
Check ($text.Contains('candidate-audit-before.json') -and $text.Contains('installed-audit-after.json')) 'candidate and installed package both receive independence audits'
Check ($text.Contains("Join-Path `$candidate 'Install-YimeCore-Local.cmd'")) 'normal package first-install entry performs recovery'
Check ($text.Contains('Assert-LocalProductInstalledContext $newRoot $state') -and $text.Contains('Assert-LocalProductLiveRuntime $context')) 'installed context and ordinary runtime are verified'
Check ($text.Contains('-Action Verify')) 'installed three-mode verification is required'
Check ($text.Contains('Assert-Enable $afterTip 1')) 'fresh install must produce DWORD Enable=1'
Check ($text.Contains('Same $afterTip $expectedEnabledTip')) 'fresh install restores the exact enabled pre-uninstall TIP state'
Check ($text.Contains('Same $afterSystem.protected $originalSystem.protected')) 'protected registry is exactly preserved'
Check ($text.Contains('Same $afterSystem.language_profile $originalSystem.language_profile')) 'Windows language profile returns exactly to its pre-uninstall state'
Check ($text.Contains('Assert-ProductRegistry $afterSystem')) 'new local.8 registration paths are independently verified'
Check ($text.Contains('Assert-FrozenPayloads $plan')) 'frozen payload bytes and inventory are checked'
Check ($text.Contains('taskbar_visibility_user_confirmation_required=$passed')) 'physical taskbar confirmation remains required'
Check ($text.Contains('reboot_requested=$false') -and $text.Contains('local_product_ready=$false') -and $text.Contains('public_release_ready=$false')) 'recovery does not reboot or overclaim readiness'
$cmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Recover-YimeCore-Local8.cmd') -Raw -Encoding UTF8
Check ($cmd.Contains('WindowsPowerShell\v1.0\powershell.exe') -and $cmd.Contains('-Execute')) 'root entry uses native Windows PowerShell and explicit execution'
Check ($cmd.Contains('Keep the PASS or BLOCKED line and evidence directory')) 'root entry preserves actionable result text'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local8-recovery-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_install_executed=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.8 recovery contracts. Evidence: $out"
