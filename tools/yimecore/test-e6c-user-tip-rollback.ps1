[CmdletBinding()]
param([string]$ManagerPath)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ManagerPath)){$ManagerPath=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'}
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($ManagerPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-RegistryKeySnapshot','Restore-RegistryKeySnapshot')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
$testRoot='HKCU:\Software\YimeCoreRollbackTests\'+[guid]::NewGuid().ToString('N')
if(Test-Path -LiteralPath $testRoot){throw 'Test key exists.'}
try {
    $leaf=$testRoot+'\LanguageProfile\0x00000804\{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
    New-Item -Path $leaf -Force|Out-Null
    New-ItemProperty -LiteralPath $leaf -Name Enable -PropertyType DWord -Value 1|Out-Null
    New-ItemProperty -LiteralPath $leaf -Name Expand -PropertyType ExpandString -Value '%LOCALAPPDATA%\trial'|Out-Null
    New-ItemProperty -LiteralPath $leaf -Name Ordered -PropertyType MultiString -Value @('second','first')|Out-Null
    $before=Get-RegistryKeySnapshot $testRoot
    Remove-Item -LiteralPath $testRoot -Recurse -Force
    Restore-RegistryKeySnapshot $testRoot $before
    if(-not (Test-Path -LiteralPath $leaf)){throw 'Regression: nested user TIP profile lost during rollback.'}
    $after=Get-RegistryKeySnapshot $testRoot
    if(($before|ConvertTo-Json -Depth 20 -Compress) -cne ($after|ConvertTo-Json -Depth 20 -Compress)){throw 'Registry types or values changed.'}
    if((Get-ItemPropertyValue -LiteralPath $leaf -Name Enable) -ne 1){throw 'User TIP Enable was not restored.'}
    $text=$ast.Extent.Text
    if(-not $text.Contains('$previousUserTipSnapshot = Get-RegistryKeySnapshot $userTipKey') -or
       -not $text.Contains('Restore-RegistryKeySnapshot $userTipKey $userTipSnapshot') -or
       -not $text.Contains('$previousRuntimeWasRunning $previousUserTipSnapshot')) {throw 'User TIP snapshot not wired into installer rollback.'}
    if(-not $text.Contains('Restore-RegistryKeySnapshot $userTipKey $previousUserTipSnapshot')) {throw 'Successful upgrade also loses existing per-user TIP settings.'}
    Write-Host 'User TIP nested Enable/value-kind rollback regression passed.'
}finally{
    if($testRoot -notmatch '^HKCU:\\Software\\YimeCoreRollbackTests\\[0-9a-f]{32}$'){throw 'Unsafe test cleanup.'}
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
