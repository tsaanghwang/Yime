[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'repair-local6-active-user-tip.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
Check ($text -notmatch '[^\u0000-\u007f]') 'repair source is ASCII-safe for Windows PowerShell 5.1'
Check ($text.Contains("`$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'")) 'installed local.6 manifest is pinned'
Check ($text.Contains("`$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'")) 'initiating user SID is pinned'
Check ($text.Contains("`$clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'") -and
    $text.Contains("`$profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'")) 'active identity is pinned'
Check ($text.Contains('beforeEnable.kind -ne 4') -and $text.Contains('beforeEnable.value -ne 0')) 'repair accepts only the observed DWORD Enable=0 failure'
Check ($text.Contains("SetValue('Enable',[uint32]1,[Microsoft.Win32.RegistryValueKind]::DWord)")) 'repair writes only DWORD Enable=1'
Check ($text.Contains('Active user TIP changed beyond Enable 0 to 1.')) 'full active user TIP snapshot permits only the enable transition'
Check ($text.Contains('Get-CutoverRegistrySnapshot') -and $text.Contains('Same $beforeSystem $afterSystem')) 'complete protected system snapshot must remain unchanged'
Check ($text.Contains('Get-WinDefaultInputMethodOverride') -and $text.Contains('Default input method changed during repair.')) 'default input method is independently protected'
Check ($text.Contains('Assert-LocalProductLiveRuntime') -and $text.Contains('live-after.json')) 'ordinary installed runtime is verified after repair'
Check ($text -notmatch 'Set-WinUserLanguageList|register\s|unregister\s|Stop-Process|Remove-Item') 'repair does not normalize languages reregister stop processes or delete data'
Check ($text.Contains('taskbar_visibility_user_confirmation_required=$true') -and
    $text.Contains('local_product_ready=$false')) 'registry repair does not overclaim taskbar or product readiness'
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-EnableRecord'},$true)
if(-not $fn){throw 'FAIL: missing Get-EnableRecord'}
. ([scriptblock]::Create($fn.Extent.Text))
$profile='{PROFILE}'
$fixture=[pscustomobject]@{exists=$true;children=[pscustomobject]@{LanguageProfile=[pscustomobject]@{children=[pscustomobject]@{
    '0x00000804'=[pscustomobject]@{children=[pscustomobject]@{$profile=[pscustomobject]@{exists=$true;values=@([pscustomobject]@{name='Enable';kind=4;value=0})}}}
}}}}
$record=Get-EnableRecord $fixture $profile
Check ($record.kind -eq 4 -and $record.value -eq 0) 'fixture finds exact nested enable record'
$fixture.children.LanguageProfile.children.'0x00000804'.children.$profile.values+=([pscustomobject]@{name='Enable';kind=4;value=1})
Check ($null -eq (Get-EnableRecord $fixture $profile)) 'ambiguous duplicate enable records are rejected'
$cmd=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Repair-YimeCore-Local6-Taskbar.cmd') -Raw -Encoding UTF8
Check ($cmd.Contains('WindowsPowerShell\v1.0\powershell.exe') -and $cmd.Contains('-Execute') -and
    $cmd.Contains('not as administrator')) 'root entry uses ordinary native Windows PowerShell'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local6-active-user-tip-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);actual_registry_repair_executed=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.6 active user TIP repair contracts. Evidence: $out"
