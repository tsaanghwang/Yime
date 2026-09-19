$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'retire-legacy-entry.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Retirement script parse failed.'}
$remove=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remove-ExactLegacyTip'},$true)
if(-not $remove){throw 'Exact list mutation helper missing.'}
. ([scriptblock]::Create($remove.Extent.Text))

$legacy='0804:{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$current='0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$production='0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA038EC515D7}'
$checks=0
foreach($tips in @(@($production,$legacy,$current),@($legacy,$production,$legacy,$current),@($production,$current))){
    $list=[Collections.Generic.List[string]]::new()
    foreach($tip in $tips){$list.Add($tip)}
    $language=[pscustomobject]@{LanguageTag='zh-Hans-CN';InputMethodTips=$list;Spellchecking=$true;Handwriting=$true}
    $removed=Remove-ExactLegacyTip @($language) $legacy
    $expected=@($tips|Where-Object {$_ -ne $legacy})
    if($removed -ne (@($tips|Where-Object {$_ -eq $legacy}).Count) -or ($list -join '|') -cne ($expected -join '|')){throw 'Exact removal changed another entry or order.'}
    if((Remove-ExactLegacyTip @($language) $legacy) -ne 0){throw 'Repeated retirement is not idempotent.'}
    $checks++
}

$text=Get-Content -LiteralPath $path -Raw
foreach($required in @('Assert-YimeCoreUnpackagedDataMaintenance','Set-WinUserLanguageList -LanguageList $desired -Force','Restore-RegistrySnapshots $exports -ProtectedOnly','Assert-Preserved $before (Get-ProtectedState)','historical_payloads_required=$false')){
    if(-not $text.Contains($required)){throw "Required guard missing: $required"};$checks++
}
foreach($forbidden in @('Remove-Item','Stop-Process','Start-Process','regsvr32','Set-WinDefaultInputMethodOverride','package-manifest.json')){
    if($text.Contains($forbidden)){throw "Unauthorized or obsolete surface present: $forbidden"};$checks++
}
$parameter=$ast.ParamBlock.Parameters[0]
if($parameter.DefaultValue.SafeGetValue() -cne 'Plan'){throw 'Default action must remain Plan.'};$checks++
$planReturn=$text.IndexOf("if(`$Action -eq 'Plan')")
$contextGuard=$text.IndexOf('Assert-YimeCoreUnpackagedDataMaintenance')
$languageWrite=$text.IndexOf('Set-WinUserLanguageList -LanguageList $desired -Force')
if($planReturn -lt 0 -or $contextGuard -lt $planReturn -or $languageWrite -lt $contextGuard){throw 'Plan/Apply boundary moved.'};$checks++
$launcher=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Retire-Legacy-YimeCore-Entry.cmd') -Raw
if(-not $launcher.Contains('-Action Apply') -or -not $launcher.Contains('WindowsPowerShell\v1.0\powershell.exe')){throw 'Launcher action or edition changed.'};$checks++

$guardPath=Join-Path $PSScriptRoot 'development-scope.ps1'
$guardAst=[Management.Automation.Language.Parser]::ParseFile($guardPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Development guard parse failed.'}
$guard=$guardAst.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-YimeCoreUnpackagedDataMaintenance'},$true)
if(-not $guard){throw 'Maintenance ancestry guard missing.'}
. ([scriptblock]::Create($guard.Extent.Text))
function Get-CimInstance {
    param($ClassName,$Filter)
    if($ClassName -cne 'Win32_Process' -or $Filter -notmatch '^ProcessId=([0-9]+)$'){throw 'Unexpected guard query.'}
    $script:processFixture[[int]$Matches[1]]
}
$shell=[pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';ParentProcessId=102}
$explorer=[pscustomobject]@{Name='explorer.exe';ExecutablePath='C:\Windows\explorer.exe';ParentProcessId=0}
$packaged=[pscustomobject]@{Name='Codex.exe';ExecutablePath=(Join-Path $env:ProgramFiles 'WindowsApps\fixture\Codex.exe');ParentProcessId=103}
foreach($case in @(
    @{processes=@{101=$shell;102=$explorer};allowed=$true},
    @{processes=@{101=$shell;102=$packaged;103=$explorer};allowed=$false},
    @{processes=@{};allowed=$false},
    @{processes=@{101=$shell;102=$shell};allowed=$false}
)){
    $script:processFixture=$case.processes
    $allowed=$true
    try{Assert-YimeCoreUnpackagedDataMaintenance -RootProcessId 101}catch{$allowed=$false}
    if($allowed -ne $case.allowed){throw 'Maintenance ancestry guard accepted or rejected the wrong context.'}
    $checks++
}

Write-Host "PASS: $checks retirement checks; synthetic language lists only, no system mutation."
