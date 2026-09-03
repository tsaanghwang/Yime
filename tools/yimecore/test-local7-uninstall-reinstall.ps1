[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'invoke-local7-uninstall-reinstall.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains("`$candidate='C:\dev\Yime\.tmp\yimecore-local-product\local7-build-20260903-1645\package'")) 'candidate path is pinned'
Check ($text.Contains("`$expectedManifest='0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb'")) 'local.7 package identity is pinned'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance') -and $text.Contains('not Run as administrator')) 'ordinary Explorer-launched initiator is required'
Check ($text.Contains('Get-Process WINWORD') -and $text.Contains('Close Word')) 'Word must be closed before maintenance'
Check ($text.IndexOf('-Action Backup -BackupRoot $backup') -lt $text.IndexOf('-Action Uninstall')) 'fresh backup precedes uninstall'
Check ($text.Contains('Assert-YimeCoreArchiveRecords') -and $text.Contains('Assert-YimeCoreUnchangedData $backupManifest.data_files')) 'fresh recovery archive and data are verified before mutation'
Check ($text.Contains('New-InstallablePackageCopy $archivedPackage $reinstallPackage $package.manifest')) 'reinstall uses a manifest-only copy of fresh external recovery media'
Check ($text.Contains("Write-CommandResult 'Backup' `$backupExit") -and $text.Contains("Write-CommandResult 'Install' `$installExit")) 'native maintenance exit codes are preserved without output pipes'
Check ($text.Contains("Join-Path `$reinstallPackage 'Maintain-YimeCore-Local.cmd'")) 'uninstall runs from preserved external media'
Check ($text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.native_tip') -and $text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.mirrored_tip')) 'machine TIP registration is absent between operations'
Check ($text.Contains('Read-ActiveUserTip') -and $text.Contains('Assert-ActiveUserTipEnabled')) 'active user TIP is independently captured and validated'
Check ($text.Contains("active-user-tip-before.json") -and $text.Contains("active-user-tip-uninstalled.json") -and $text.Contains("active-user-tip-after.json")) 'active user TIP has before gap and after evidence'
Check ($text.Contains('Test-TipSnapshotSemanticallyAbsent $midActiveUserTip $trialClsid')) 'uninstall gap removes active user TIP'
Check ($text.Contains('Same $beforeActiveUserTip $afterActiveUserTip')) 'reinstall restores the exact enabled active user TIP state'
Check ($text.Contains("[int]`$enable.kind -ne 4") -and $text.Contains("[int]`$enable.value -ne 1")) 'taskbar gate requires DWORD Enable=1'
Check ($text.Contains('-Action Uninstall') -and $text.Contains('Install-YimeCore-Local.cmd')) 'uninstall and first-install paths are both exercised'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData $midData') -and $text.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData')) 'user data remains byte-identical across both stages'
Check ($text.Contains('Same $beforeRegistry.protected $midRegistry.protected')) 'uninstall preserves production frozen default and unrelated registry state'
Check ($text.Contains('Normalize-RootInSnapshot $beforeRegistry $oldRoot') -and $text.Contains('Normalize-RootInSnapshot $afterRegistry $newRoot')) 'complete registry comparison permits only install-root relocation'
Check ($text.Contains('Uninstall left runtime process alive')) 'old runtime and broker termination is verified'
Check ($text.Contains('Assert-LocalProductInstalledContext $newRoot $state') -and $text.Contains('Assert-LocalProductLiveRuntime $newContext')) 'reinstalled package and ordinary runtime are verified'
Check ($text.Contains('-Action Verify')) 'reinstalled three-mode verification is required'
Check ($text.Contains('Fresh recovery media changed during uninstall.')) 'recovery identities are rechecked before reinstall'
Check ($text.Contains('installed-audit-after.json')) 'reinstalled package receives an independence audit'
Check ($text.Contains('active_user_tip_enable_after=if($passed){1}else{$null}')) 'summary records the taskbar-enabling value only after full success'
Check ($text.Contains('taskbar_visibility_user_confirmation_required=$passed')) 'summary requires a final physical taskbar confirmation'
Check ($text.Contains('production_components_changed=$false') -and $text.Contains('default_input_method_changed=$false')) 'production and default input remain outside mutation scope'
Check ($text.Contains('frozen_targets_executed=$false') -and $text.Contains('reboot_requested=$false')) 'frozen targets are not run and reboot is not requested'
Check ($text.Contains('local_product_ready=$false') -and $text.Contains('public_release_ready=$false')) 'acceptance does not overclaim readiness'
foreach($functionName in @('Same','Normalize-RootInSnapshot','New-InstallablePackageCopy','Write-CommandResult','Get-ChildNames','Get-ChildNode','Get-EnableRecord','Assert-ActiveUserTipEnabled','Test-TipSnapshotSemanticallyAbsent')){
    $definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
    Check ($null -ne $definition) "required helper exists: $functionName"
}
$cmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Test-YimeCore-Local7-Uninstall-Reinstall.cmd') -Raw -Encoding UTF8
Check ($cmd.Contains('WindowsPowerShell\v1.0\powershell.exe') -and $cmd.Contains('-Execute')) 'root entry uses native Windows PowerShell and explicit execution'
Check ($cmd.Contains('Keep the PASS or BLOCKED line and evidence directory')) 'root entry preserves actionable result text'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local7-uninstall-reinstall-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_uninstall_executed=$false;actual_reinstall_executed=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.7 uninstall/reinstall contracts. Evidence: $out"
