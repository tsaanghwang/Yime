[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'invoke-local6-uninstall-reinstall.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text -notmatch '[^\u0000-\u007f]') 'acceptance source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains("`$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'local.6 package identity is pinned'
Check ($text.Contains('Assert-YimeCoreUnpackagedDataMaintenance') -and $text.Contains('not Run as administrator')) 'ordinary Explorer-launched initiator is required'
Check ($text.Contains("Get-Process WINWORD") -and $text.Contains('Close Word')) 'Word must be closed before the maintenance window'
Check ($text.Contains("-Action Backup -BackupRoot `$backup")) 'a fresh native backup precedes uninstall'
Check ($text.IndexOf("-Action Backup -BackupRoot `$backup") -lt $text.IndexOf("-Action Uninstall")) 'backup is ordered before uninstall'
Check ($text.Contains('Assert-YimeCoreArchiveRecords') -and $text.Contains('Assert-YimeCoreUnchangedData $backupManifest.data_files')) 'fresh recovery archive and data are verified before mutation'
Check ($text.Contains("`$archivedPackage=Join-Path `$backup 'previous-package'") -and
    $text.Contains("`$reinstallPackage=Join-Path `$backup 'reinstall-package'") -and
    $text.Contains('Fresh recovery package audit failed.')) 'reinstall source is a fresh manifest-only package outside the repository'
Check ($text.Contains('New-InstallablePackageCopy $archivedPackage $reinstallPackage $package.manifest') -and
    $text.Contains('leaving the exact archive intact')) 'root-bound install metadata is excluded without changing exact recovery material'
Check ($text.Contains('Capturing native') -and $text.Contains('open indefinitely') -and
    $text -notmatch '(backup|uninstall|install|verify)Output\s*=\s*@\(') 'runtime-starting maintenance commands are not captured through inheritable pipes'
Check ($text.Contains("Write-CommandResult 'Backup' `$backupExit") -and
    $text.Contains("Write-CommandResult 'Install' `$installExit")) 'maintenance exit codes are preserved as evidence without output pipes'
Check ($text.Contains("Join-Path `$reinstallPackage 'Maintain-YimeCore-Local.cmd'") -and
    $text.Contains('deleted by a successful uninstall')) 'uninstall is launched from preserved media rather than its self-deleting installed CMD'
Check ($text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.native_tip') -and
    $text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.mirrored_tip')) 'semantic registration absence accepts only empty native and mirrored TIP skeletons'
Check ($text.Contains("-Action Uninstall") -and $text.Contains("Install-YimeCore-Local.cmd")) 'package uninstall and first-install paths are both exercised'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData $midData')) 'uninstalled state preserves all user data records'
Check ($text.Contains('Same $beforeRegistry.protected $midRegistry.protected')) 'uninstall preserves production frozen default and unrelated registry state'
Check ($text.Contains('$midRegistry.native_com.exists') -and
    $text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.native_tip') -and
    $text.Contains('Test-TipSnapshotSemanticallyAbsent $midRegistry.mirrored_tip')) 'active COM and semantic TIP absence is verified between operations'
Check ($text.Contains("@(`$midRegistry.trial_run).Count -ne 0") -and $text.Contains('$midRegistry.uninstall.exists')) 'autostart and uninstall entry absence is verified'
Check ($text.Contains("runtime-config.json") -and $text.Contains("runtime-status.json")) 'active runtime state removal is verified'
Check ($text.Contains('Uninstall left runtime process alive')) 'old runtime and broker termination is verified'
Check ($text.Contains("live-before-uninstall.json") -and $text.IndexOf("live-before-uninstall.json") -gt $text.IndexOf("-Action Backup -BackupRoot `$backup")) 'post-backup runtime PIDs are captured for uninstall verification'
Check ($text.Contains('Assert-LocalProductInstalledContext $newRoot $state') -and $text.Contains('Assert-LocalProductLiveRuntime $newContext')) 'reinstalled package and ordinary runtime are verified'
Check ($text.Contains("-Action Verify")) 'reinstalled three-mode verification is required'
Check ($text.Contains('Normalize-RootInSnapshot $beforeRegistry $oldRoot') -and $text.Contains('Normalize-RootInSnapshot $afterRegistry $newRoot')) 'complete registry comparison allows only install-root relocation'
Check ($text.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData')) 'data remains byte-identical after reinstall'
Check ($text.Contains('Fresh recovery media changed during uninstall.')) 'recovery manifest identities are rechecked before reinstall'
Check ($text.Contains('installed-audit-after.json')) 'reinstalled package receives an independence audit'
Check ($text.Contains('production_components_changed=$false') -and $text.Contains('default_input_method_changed=$false')) 'production and default input remain outside mutation scope'
Check ($text.Contains('frozen_targets_executed=$false') -and $text.Contains('reboot_requested=$false')) 'frozen targets are not run and reboot is not requested'
Check ($text.Contains('local_product_ready=$false') -and $text.Contains('public_release_ready=$false')) 'acceptance does not overclaim readiness'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
foreach($functionName in @('Same','Normalize-RootInSnapshot','New-InstallablePackageCopy','Write-CommandResult',
    'Get-ChildNames','Get-ChildNode','Test-TipSnapshotSemanticallyAbsent')){
    $definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
    if(-not $definition){throw "FAIL: missing function $functionName"}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$oldFixture=[ordered]@{path='C:\Program Files\Old Root\bin\runtime.exe';nested=[ordered]@{value='unchanged'}}
$newFixture=[ordered]@{path='C:\Program Files\New Root\bin\runtime.exe';nested=[ordered]@{value='unchanged'}}
$badFixture=[ordered]@{path='C:\Program Files\New Root\bin\runtime.exe';nested=[ordered]@{value='changed'}}
Check (Same (Normalize-RootInSnapshot $oldFixture 'C:\Program Files\Old Root') (Normalize-RootInSnapshot $newFixture 'C:\Program Files\New Root')) 'registry normalization accepts only equivalent root relocation'
Check (-not (Same (Normalize-RootInSnapshot $oldFixture 'C:\Program Files\Old Root') (Normalize-RootInSnapshot $badFixture 'C:\Program Files\New Root'))) 'registry normalization still rejects unrelated changes'
$copyFixture=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-installable-copy-fixture-'+[guid]::NewGuid().ToString('N'))
$copySource=Join-Path $copyFixture 'previous-package';$copyDestination=Join-Path $copyFixture 'reinstall-package'
New-Item -ItemType Directory -Path (Join-Path $copySource 'bin') -Force|Out-Null
'payload'|Set-Content -LiteralPath (Join-Path $copySource 'bin\payload.exe') -Encoding ASCII
'manifest'|Set-Content -LiteralPath (Join-Path $copySource 'package-manifest.json') -Encoding ASCII
'root-bound'|Set-Content -LiteralPath (Join-Path $copySource 'install-metadata.json') -Encoding ASCII
$null=New-InstallablePackageCopy $copySource $copyDestination ([pscustomobject]@{files=@([pscustomobject]@{path='bin/payload.exe'})})
Check ((Test-Path -LiteralPath (Join-Path $copyDestination 'bin\payload.exe')) -and
    (Test-Path -LiteralPath (Join-Path $copyDestination 'package-manifest.json')) -and
    -not (Test-Path -LiteralPath (Join-Path $copyDestination 'install-metadata.json'))) 'installable copy omits root-bound install metadata'
$emptyTip=[pscustomobject]@{exists=$true;children=[pscustomobject]@{
    LanguageProfile=[pscustomobject]@{children=[pscustomobject]@{'0x00000804'=[pscustomobject]@{children=[pscustomobject]@{}}}}
    Category=[pscustomobject]@{children=[pscustomobject]@{
        Category=[pscustomobject]@{children=[pscustomobject]@{'category'=[pscustomobject]@{children=[pscustomobject]@{}}}}
        Item=[pscustomobject]@{children=[pscustomobject]@{'{TRIAL}'=[pscustomobject]@{children=[pscustomobject]@{}}}}
    }}
}}
Check (Test-TipSnapshotSemanticallyAbsent $emptyTip '{TRIAL}') 'empty Windows TIP container is accepted as unregistered'
$emptyTip.children.LanguageProfile.children.'0x00000804'.children|Add-Member -NotePropertyName '{PROFILE}' -NotePropertyValue ([pscustomobject]@{})
Check (-not (Test-TipSnapshotSemanticallyAbsent $emptyTip '{TRIAL}')) 'remaining language profile is rejected as registered'
$liveEmptyTip=[ordered]@{exists=$true;children=[ordered]@{
    LanguageProfile=[ordered]@{children=[ordered]@{'0x00000804'=[ordered]@{children=[ordered]@{}}}}
    Category=[ordered]@{children=[ordered]@{
        Category=[ordered]@{children=[ordered]@{'{CATEGORY}'=[ordered]@{children=[ordered]@{}}}}
        Item=[ordered]@{children=[ordered]@{'{TRIAL}'=[ordered]@{children=[ordered]@{}}}}
    }}
}}
Check (Test-TipSnapshotSemanticallyAbsent $liveEmptyTip '{TRIAL}') 'live ordered-dictionary TIP skeleton ignores dictionary adapter properties'
$cmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Test-YimeCore-Local6-Uninstall-Reinstall.cmd') -Raw -Encoding UTF8
Check ($cmd.Contains('WindowsPowerShell\v1.0\powershell.exe') -and $cmd.Contains('-Execute')) 'root entry uses native Windows PowerShell and explicit execution'
Check ($cmd.Contains('Keep the PASS or BLOCKED line and evidence directory')) 'root entry preserves actionable result text'
$completionPath=Join-Path $PSScriptRoot 'complete-local6-uninstall-reinstall.ps1'
$completionText=Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8
$completionTokens=$null;$completionErrors=$null
[Management.Automation.Language.Parser]::ParseFile($completionPath,[ref]$completionTokens,[ref]$completionErrors)|Out-Null
Check ($completionErrors.Count -eq 0) 'partial-uninstall completion source parses under Windows PowerShell'
Check ($completionText.Contains('local6-uninstall-reinstall-20260903-121508-ef668e62') -and
    $completionText.Contains("`$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'completion is pinned to the reviewed failure and package'
Check ($completionText.Contains("`$beforeData=Get-Content -LiteralPath (Join-Path `$evidence 'data-before.json') -Raw -Encoding UTF8|ConvertFrom-Json") -and
    -not $completionText.Contains("`$beforeData=@(Get-Content -LiteralPath (Join-Path `$evidence 'data-before.json')")) 'PowerShell 5.1 data-before JSON array is not wrapped as a nested array'
Check ($completionText.Contains("Start-Transcript -LiteralPath (Join-Path `$evidence 'completion-transcript.txt') -Append")) 'completion retry preserves the prior transcript'
Check ($completionText.IndexOf('Restore-RegistryTreeFromSystemSnapshot') -lt $completionText.IndexOf("`$stage='reinstall-same-package'")) 'frozen user TIP is restored before reinstall'
Check ($completionText.Contains('registration-absence-before-completion.txt') -and
    $completionText.Contains('Test-TipSnapshotSemanticallyAbsent') -and $completionText.Contains('system-uninstalled.json')) 'completion records the semantic uninstall gap'
Check ($completionText.Contains('Assert-YimeCoreUnchangedData $beforeData $afterData') -and
    $completionText.Contains('Assert-LocalProductLiveRuntime $newContext') -and $completionText.Contains('installed-audit-after.json')) 'completion requires data live-runtime and installed-audit evidence'
$completionCmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Complete-YimeCore-Local6-Uninstall-Reinstall.cmd') -Raw -Encoding UTF8
Check ($completionCmd.Contains('WindowsPowerShell\v1.0\powershell.exe') -and $completionCmd.Contains('-Execute') -and
    $completionCmd.Contains('not as administrator')) 'completion root entry uses ordinary native Windows PowerShell'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-uninstall-reinstall-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_uninstall_executed=$false;actual_reinstall_executed=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.6 uninstall/reinstall contracts. Evidence: $out"
