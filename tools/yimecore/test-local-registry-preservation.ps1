[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$manager=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($manager,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Initialize-RegistryKeyPreservingValues','Restore-RegistryValueSnapshot','Get-RegistryKeySnapshot',
    'Restore-RegistryKeySnapshotInPlace','Get-FrozenTipSnapshot','Restore-FrozenTipSnapshot',
    'Get-FrozenUserTipSnapshot','Restore-FrozenUserTipSnapshot','Invoke-Registration',
    'Get-CurrentIdentityArchitecturesForRoot','Find-CurrentRegistrationTool','Remove-TrialRegistration')) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing function: $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Name}
# Only a disposable fixture is mutated. Never use an actual Run/TIP key here.
$fixture='Registry::HKEY_CURRENT_USER\Software\YimeCoreTests\RunPreservation-'+[guid]::NewGuid().ToString('N')
try {
    $fixtureHandle=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture.Substring('Registry::HKEY_CURRENT_USER\'.Length))
    $fixtureHandle.Dispose()
    New-ItemProperty -LiteralPath $fixture -Name OtherApp -Value 'sentinel' -PropertyType String|Out-Null
    New-Item -Path $fixture -Force|Out-Null
    Check ((Get-RegistryKeySnapshot $fixture).values.Count -eq 0) 'real disposable registry repro: New-Item -Force erases existing values'
    New-ItemProperty -LiteralPath $fixture -Name OtherApp -Value 'sentinel' -PropertyType String|Out-Null
    New-ItemProperty -LiteralPath $fixture -Name Expand -Value '%USERPROFILE%\literal' -PropertyType ExpandString|Out-Null
    New-ItemProperty -LiteralPath $fixture -Name Multi -Value @('first','second') -PropertyType MultiString|Out-Null
    New-ItemProperty -LiteralPath $fixture -Name Count -Value 7 -PropertyType DWord|Out-Null
    $before=Get-RegistryKeySnapshot $fixture
    Initialize-RegistryKeyPreservingValues $fixture
    Check (($before|ConvertTo-Json -Depth 8 -Compress) -ceq ((Get-RegistryKeySnapshot $fixture)|ConvertTo-Json -Depth 8 -Compress)) 'ensure-existing preserves all other values and kinds'
    Restore-RegistryValueSnapshot $fixture YimeCoreExperimentalTrial @{exists=$true;kind=1;value='new runtime'}
    $after=Get-RegistryKeySnapshot $fixture
    $others=@($after.values|Where-Object{$_.name -ne 'YimeCoreExperimentalTrial'})
    Check (($before.values|ConvertTo-Json -Depth 8 -Compress) -ceq ($others|ConvertTo-Json -Depth 8 -Compress)) 'value rollback does not erase unrelated Run siblings'
    Restore-RegistryValueSnapshot $fixture YimeCoreExperimentalTrial @{exists=$false}
    Check (($before|ConvertTo-Json -Depth 8 -Compress) -ceq ((Get-RegistryKeySnapshot $fixture)|ConvertTo-Json -Depth 8 -Compress)) 'absent owned value rollback preserves all siblings'
    New-ItemProperty -LiteralPath $fixture -Name Unexpected -Value 'remove me' -PropertyType String|Out-Null
    Set-ItemProperty -LiteralPath $fixture -Name OtherApp -Value 'changed'
    $unexpectedChild=$fixture+'\unexpected-child'
    New-Item -Path $unexpectedChild|Out-Null
    Restore-RegistryKeySnapshotInPlace $fixture $before
    Check (($before|ConvertTo-Json -Depth 8 -Compress) -ceq ((Get-RegistryKeySnapshot $fixture)|ConvertTo-Json -Depth 8 -Compress)) 'in-place tree restore converges without replacing expected keys'
    $child=$fixture+'\new-key'
    Initialize-RegistryKeyPreservingValues $child
    Check (Test-Path -LiteralPath $child) 'missing parent is created without force'
} finally {
    if($fixture -notmatch '^Registry::HKEY_CURRENT_USER\\Software\\YimeCoreTests\\RunPreservation-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup target.'}
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
# Frozen registration is simulated, never executed or written on this PC.
$NativeX64Only=$true
$NativeLocalProduct=$true
$legacyClsid='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$legacyUserTipKey="Registry::HKEY_USERS\S-1-5-21-fixture\Software\Microsoft\CTF\TIP\$legacyClsid"
$script:frozenMachine=@{exists=$true;values=@(@{name='Description';kind=1;value='old'},@{name='Enable';kind=4;value=1});children=@{}}
$script:frozenUser=@{exists=$true;values=@(@{name='Enable';kind=4;value=1});children=@{}}
$script:breakRestore=$false
$originalMachine=$script:frozenMachine|ConvertTo-Json -Depth 8 -Compress
$originalUser=$script:frozenUser|ConvertTo-Json -Depth 8 -Compress
function Get-RegistryKeySnapshot {param($path)
    if($path -ceq "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$legacyClsid"){$value=$script:frozenMachine}
    elseif($path -ceq $legacyUserTipKey){$value=$script:frozenUser}
    else{throw "Unexpected frozen snapshot target: $path"}
    return ($value|ConvertTo-Json -Depth 8|ConvertFrom-Json)
}
function Restore-RegistryKeySnapshotInPlace {param($path,$snapshot)
    $null=Get-RegistryKeySnapshot $path
    if(-not $script:breakRestore){
        if($path -ceq $legacyUserTipKey){$script:frozenUser=$snapshot}
        else{$script:frozenMachine=$snapshot}
    }
}
function Test-RegistrationTool {param($command,$dll)
    $script:frozenMachine=[ordered]@{exists=$true;values=@(@{name='Description';kind=1;value='new'});children=[ordered]@{}}
    $script:frozenUser=[ordered]@{exists=$true;values=@(@{name='Enable';kind=4;value=0});children=[ordered]@{}}
    $global:LASTEXITCODE=$script:toolExit
}
$script:toolExit=0
Invoke-Registration Test-RegistrationTool register fixture 'fixture registration'
Check (($script:frozenMachine|ConvertTo-Json -Depth 8 -Compress) -ceq $originalMachine) 'successful x64 registration preserves frozen machine profile snapshot'
Check (($script:frozenUser|ConvertTo-Json -Depth 8 -Compress) -ceq $originalUser) 'successful x64 registration preserves frozen per-user profile snapshot'
$script:toolExit=7
Reject {Invoke-Registration Test-RegistrationTool register fixture 'fixture registration'} 'registration failure remains failure'
Check (($script:frozenMachine|ConvertTo-Json -Depth 8 -Compress) -ceq $originalMachine) 'failed registration also restores frozen machine profile'
Check (($script:frozenUser|ConvertTo-Json -Depth 8 -Compress) -ceq $originalUser) 'failed registration also restores frozen per-user profile'
$script:breakRestore=$true;$script:toolExit=0
Reject {Invoke-Registration Test-RegistrationTool register fixture 'fixture registration'} 'failed frozen readback cannot claim registration success'
$script:breakRestore=$false
Reject {Restore-FrozenTipSnapshot $null} 'missing frozen snapshot is not accepted'
$script:frozenMachine=[ordered]@{exists=$false;values=@();children=[ordered]@{}}
$script:frozenUser=[ordered]@{exists=$false;values=@();children=[ordered]@{}}
Invoke-Registration Test-RegistrationTool register fixture 'fixture registration'
Check (-not $script:frozenMachine.exists -and -not $script:frozenUser.exists) 'original frozen profile absence is preserved in both scopes'
function Get-RegistrationArchitectures {return @(@{name='x64'})}
Reject {Remove-TrialRegistration @()} 'missing x64 unregister tool remains failure'
Check (-not $script:frozenMachine.exists -and -not $script:frozenUser.exists) 'unregister failure retains frozen state'
$NativeX64Only=$false
$NativeLocalProduct=$false
Check ($null -eq (Get-FrozenTipSnapshot)) 'historical modes do not acquire native-only snapshot'
Check ($null -eq (Get-FrozenUserTipSnapshot)) 'historical modes do not acquire per-user frozen snapshot'
$text=Get-Content -LiteralPath $manager -Raw -Encoding UTF8
Check ($text -notmatch 'New-Item -Path \$runKey -Force') 'no destructive shared Run-key creation remains'
Check ($text.Contains('Initialize-RegistryKeyPreservingValues $runKey')) 'installation uses non-destructive parent creation'
Check ($text.Contains('Restore-RegistryKeySnapshotInPlace $path $snapshot')) 'frozen profile uses in-place restoration instead of root replacement'
Check ($text.Contains('finally { Restore-FrozenUserTipSnapshot $frozenUserTip }')) 'registration and unregister boundaries restore both frozen scopes even on errors'
Check ($text.Contains('Restore-FrozenUserTipSnapshot $migrationLegacyUserTipSnapshot')) 'final migration boundary restores legacy user TIP after language-list normalization'
$uninstallNode=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-UninstallCore'},$true)
$uninstallText=$uninstallNode.Extent.Text
Check ($uninstallText.IndexOf('$frozenUserTipBeforeLanguageList = Get-FrozenUserTipSnapshot') -lt $uninstallText.IndexOf('Remove-InputMethodTip') -and
    $uninstallText.IndexOf('Restore-FrozenUserTipSnapshot $frozenUserTipBeforeLanguageList') -gt $uninstallText.IndexOf('Remove-InputMethodTip')) 'uninstall snapshots frozen user TIP before Set-WinUserLanguageList can delete it'
Check ($text.Contains("return 'repoint'") -and $text.Contains('Resolve-RegistrationAction')) 'preserved shared profile uses x64 COM repoint instead of conflicting full registration'
$repair=Join-Path $PSScriptRoot 'repair-local5-identity-migration.ps1'
$repairText=Get-Content -LiteralPath $repair -Raw -Encoding UTF8
$workerBody=$repairText.Substring($repairText.IndexOf('$users='))
Check ($repairText.Contains("Write-Json `$preflightLive 'live-runtime-before.json'") -and $repairText.Contains("Write-Json `$live 'live-runtime-after.json'")) 'repair live-runtime validation stays in standard-user parent before and after UAC'
Check (-not $workerBody.Contains('Assert-LocalProductLiveRuntime')) 'elevated repair worker does not perform standard-user launch-token validation'
Check ($repairText.Contains("'worker-summary.json'") -and $repairText.Contains("'summary.json'")) 'repair separates elevated mutation evidence from parent acceptance summary'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('registry-preservation-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();
    real_registry_fixture_only=$true;actual_Run_or_TIP_written=$false;frozen_binaries_executed=$false}|
    ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) registry preservation regressions. Evidence: $out"
