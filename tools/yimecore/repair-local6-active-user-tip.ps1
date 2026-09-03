[CmdletBinding()]
param([switch]$Execute)
$ErrorActionPreference='Stop'
$installed='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-42e28f7d'
$expectedManifest='42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087'
$expectedValidator='8f560a009bfead4a3bd8ca736d8b4008e0e0da32a350aeaf0a7fa0f1ad0addb4'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$tip="0804:$clsid$profile"
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$manifestPath=Join-Path $installed 'package-manifest.json'
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $manifestPath).Hash -ine $expectedManifest){throw 'Installed local.6 identity changed; refuse targeted repair.'}
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){
    $path=Join-Path $installed "maintenance\$name"
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Installed helper is missing: $name"}
    . $path
}
$null=Assert-LocalProductPackage $installed
$null=Get-YimeCoreDevelopmentScope
$validator=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
if((Get-FileHash -LiteralPath $validator).Hash -ine $expectedValidator){throw 'Pinned system-registry validator changed.'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($validator,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CutoverRegistrySnapshot'},$true)
if(-not $fn){throw 'Missing independent system-registry snapshot helper.'}
. ([scriptblock]::Create($fn.Extent.Text))
function Same($Left,$Right){return (($Left|ConvertTo-Json -Depth 40 -Compress) -ceq ($Right|ConvertTo-Json -Depth 40 -Compress))}
function Write-Evidence($Value,[string]$Path){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Path -Encoding UTF8}
function Get-EnableRecord($Snapshot,[string]$ProfileGuid){
    if($null -eq $Snapshot -or -not $Snapshot.exists){return $null}
    $leaf=$Snapshot.children.LanguageProfile.children.'0x00000804'.children.$ProfileGuid
    if($null -eq $leaf -or -not $leaf.exists){return $null}
    $values=@($leaf.values|Where-Object{$_.name -ceq 'Enable'})
    if($values.Count -ne 1){return $null}
    return $values[0]
}
function Read-ActiveUserTip {
    Read-YimeCoreSystemKey ([uint32]2147483651) "$expectedSid\Software\Microsoft\CTF\TIP\$clsid"
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -cne $expectedSid){throw 'Use the Windows account that owns local.6.'}
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use normal File Explorer double-click, not Run as administrator.'}
$language=Get-WinUserLanguageList|Where-Object{$_.LanguageTag -eq 'zh-Hans-CN'}|Select-Object -First 1
if($null -eq $language -or @($language.InputMethodTips) -notcontains $tip){throw 'The active local.6 TIP is not present in the zh-Hans-CN language list.'}
$beforeTip=Read-ActiveUserTip
$beforeEnable=Get-EnableRecord $beforeTip $profile
if($null -eq $beforeEnable -or [int]$beforeEnable.kind -ne 4 -or [int]$beforeEnable.value -ne 0){throw 'Current active user TIP is not the reviewed DWORD Enable=0 failure.'}
$beforeSystem=Get-CutoverRegistrySnapshot
$beforeDefault=Get-WinDefaultInputMethodOverride
$beforeLive=Assert-LocalProductLiveRuntime (Assert-LocalProductInstalledContext $installed $state)
$plan=[ordered]@{action='repair-local6-active-user-tip';installed_root=$installed;manifest_sha256=$expectedManifest;
    sid=$expectedSid;tip=$tip;before_enable=0;after_enable=1;language_list_changed=$false;
    default_input_method_changed=$false;production_components_changed=$false;reinstall=$false;reboot=$false}
if(-not $Execute){$plan|ConvertTo-Json -Depth 8;exit 0}
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
$evidence=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local6-active-user-tip-repair-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
if(Test-Path -LiteralPath $evidence){throw 'Repair evidence directory must be new.'}
New-Item -ItemType Directory -Path $evidence|Out-Null
Write-Evidence $plan (Join-Path $evidence 'plan.json')
Write-Evidence $beforeTip (Join-Path $evidence 'active-user-tip-before.json')
Write-Evidence $beforeSystem (Join-Path $evidence 'system-before.json')
Write-Evidence $beforeLive (Join-Path $evidence 'live-before.json')
$passed=$false;$failure=$null
try{
    $users=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users,[Microsoft.Win32.RegistryView]::Registry64)
    try{
        $relative="$expectedSid\Software\Microsoft\CTF\TIP\$clsid\LanguageProfile\0x00000804\$profile"
        $key=$users.OpenSubKey($relative,$true)
        if($null -eq $key){throw 'Active per-user TIP profile key disappeared before repair.'}
        try{$key.SetValue('Enable',[uint32]1,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Dispose()}
    }finally{$users.Dispose()}
    $afterTip=Read-ActiveUserTip
    $afterEnable=Get-EnableRecord $afterTip $profile
    if($null -eq $afterEnable -or [int]$afterEnable.kind -ne 4 -or [int]$afterEnable.value -ne 1){throw 'Independent system view did not confirm DWORD Enable=1.'}
    $projected=$afterTip|ConvertTo-Json -Depth 40|ConvertFrom-Json
    (Get-EnableRecord $projected $profile).value=0
    if(-not (Same $beforeTip $projected)){throw 'Active user TIP changed beyond Enable 0 to 1.'}
    $afterSystem=Get-CutoverRegistrySnapshot
    if(-not (Same $beforeSystem $afterSystem)){throw 'Protected system registry changed during active user TIP repair.'}
    $afterDefault=Get-WinDefaultInputMethodOverride
    $beforeDefaultTip=if($beforeDefault){[string]$beforeDefault.InputMethodTip}else{''}
    $afterDefaultTip=if($afterDefault){[string]$afterDefault.InputMethodTip}else{''}
    if($beforeDefaultTip -cne $afterDefaultTip){throw 'Default input method changed during repair.'}
    $afterLive=Assert-LocalProductLiveRuntime (Assert-LocalProductInstalledContext $installed $state)
    Write-Evidence $afterTip (Join-Path $evidence 'active-user-tip-after.json')
    Write-Evidence $afterSystem (Join-Path $evidence 'system-after.json')
    Write-Evidence $afterLive (Join-Path $evidence 'live-after.json')
    $passed=$true
}catch{$failure=$_.Exception.Message}
$summary=[ordered]@{schema_version='yimecore-local6-active-user-tip-repair-v1';passed=$passed;failure=$failure;
    installed_manifest_sha256=$expectedManifest;tip=$tip;enable_before=0;enable_after=if($passed){1}else{$null};
    language_list_changed=$false;default_input_method_changed=$false;production_components_changed=$false;
    reinstall_performed=$false;reboot_requested=$false;taskbar_visibility_user_confirmation_required=$true;
    local_product_ready=$false;public_release_ready=$false}
Write-Evidence $summary (Join-Path $evidence 'summary.json')
if(-not $passed){Write-Host "BLOCKED: local.6 active user TIP repair failed: $failure Evidence: $evidence";exit 1}
Write-Host "PASS: local.6 active user TIP changed from DWORD Enable=0 to Enable=1. Reopen the host and confirm taskbar visibility. Evidence: $evidence"
