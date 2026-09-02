[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
function Read-Key($base,[string]$path) {
    $key=$base.OpenSubKey($path)
    if(-not $key){return [ordered]@{exists=$false}}
    try {
        $values=@($key.GetValueNames()|Sort-Object|ForEach-Object{
            [ordered]@{name=$_;kind=[string]$key.GetValueKind($_);value=$key.GetValue($_,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
        })
        $children=[ordered]@{}
        foreach($child in @($key.GetSubKeyNames()|Sort-Object)){$children[$child]=Read-Key $base ($path+'\'+$child)}
        return [ordered]@{exists=$true;values=$values;children=$children}
    }finally{$key.Dispose()}
}
$trial='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$production='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$registration=[ordered]@{}
foreach($view in @('Registry64','Registry32')) {
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::$view)
    try {
        $registration[$view]=[ordered]@{
            production_com=Read-Key $base "SOFTWARE\Classes\CLSID\$production"
            production_tip=Read-Key $base "SOFTWARE\Microsoft\CTF\TIP\$production"
            trial_com=Read-Key $base "SOFTWARE\Classes\CLSID\$trial"
            trial_tip=Read-Key $base "SOFTWARE\Microsoft\CTF\TIP\$trial"
            legacy_trial_uninstall=Read-Key $base 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial'
        }
    }finally{$base.Dispose()}
}
$current=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
try {
    $user=[ordered]@{
        trial_uninstall=Read-Key $current 'Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial'
        trial_tip=Read-Key $current "Software\Microsoft\CTF\TIP\$trial"
        language_profile=Read-Key $current 'Control Panel\International\User Profile'
        keyboard_preload=Read-Key $current 'Keyboard Layout\Preload'
    }
    $run=$current.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
    try{$user['trial_run']=[ordered]@{value=$run.GetValue('YimeCoreExperimentalTrial',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);kind=[string]$run.GetValueKind('YimeCoreExperimentalTrial')}}finally{$run.Dispose()}
}finally{$current.Dispose()}
$stateRoot=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$configPath=Join-Path $stateRoot 'runtime-config.json'
$config=Get-Content -Encoding UTF8 -LiteralPath $configPath -Raw | ConvertFrom-Json
$result=[ordered]@{schema_version='yimecore-local-maintenance-state-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');
    development_scope=$scope;sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;
    registration=$registration;user=$user;runtime_config=$config;
    runtime_config_sha256=(Get-FileHash -LiteralPath $configPath).Hash;
    runtime_status=(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $stateRoot 'runtime-status.json') -Raw|ConvertFrom-Json);
    manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $config.install_root 'package-manifest.json')).Hash}
# Keep old process-view fields for historical comparisons, but never present
# them as proof of Explorer's HKCU view. Record independent system values too.
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$systemQueries=[ordered]@{
    trial_run=@{hDefKey=[uint32]2147483651;sSubKeyName="$sid\Software\Microsoft\Windows\CurrentVersion\Run";sValueName='YimeCoreExperimentalTrial'}
    trial_uninstall_location=@{hDefKey=[uint32]2147483651;sSubKeyName="$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial";sValueName='InstallLocation'}
    trial_uninstall_command=@{hDefKey=[uint32]2147483651;sSubKeyName="$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial";sValueName='UninstallString'}
    trial_user_enable=@{hDefKey=[uint32]2147483651;sSubKeyName="$sid\Software\Microsoft\CTF\TIP\$trial\LanguageProfile\0x00000804\{607895A8-9504-4A2E-9BB1-2C159E3A1757}";sValueName='Enable'}
    trial_com_x64=@{hDefKey=[uint32]2147483650;sSubKeyName="SOFTWARE\Classes\CLSID\$trial\InprocServer32";sValueName=''}
    production_com_x64=@{hDefKey=[uint32]2147483650;sSubKeyName="SOFTWARE\Classes\CLSID\$production\InprocServer32";sValueName=''}
    production_com_x86=@{hDefKey=[uint32]2147483650;sSubKeyName="SOFTWARE\Classes\WOW6432Node\CLSID\$production\InprocServer32";sValueName=''}
}
$systemValues=[ordered]@{}
foreach($name in $systemQueries.Keys) {
    $method=if($name -eq 'trial_user_enable'){'GetDWORDValue'}else{'GetStringValue'}
    $read=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $method -Arguments $systemQueries[$name]
    if($null -eq $read.ReturnValue -or $read.ReturnValue -notin @(0,2)){throw "System registry capture failed: $name/$($read.ReturnValue)"}
    $systemValues[$name]=@{query=$systemQueries[$name];return_code=$read.ReturnValue;value=$(if($method -eq 'GetDWORDValue'){$read.uValue}else{$read.sValue})}
}
$result['system_registry_reader']='StdRegProv/HKEY_USERS+HKLM'
$result['system_registry_values']=$systemValues
$result['legacy_registry_fields_are_process_view']=$true
$systemTrees=[ordered]@{}
foreach($entry in @(
    @('trial_uninstall',"$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial"),
    @('trial_tip',"$sid\Software\Microsoft\CTF\TIP\$trial"),
    @('language_profile',"$sid\Control Panel\International\User Profile"),
    @('keyboard_preload',"$sid\Keyboard Layout\Preload")
)){$systemTrees[$entry[0]]=Read-YimeCoreSystemKey 2147483651 $entry[1]}
$runTree=Read-YimeCoreSystemKey 2147483651 "$sid\Software\Microsoft\Windows\CurrentVersion\Run"
$systemTrees['trial_run']=@($runTree.values|Where-Object name -eq 'YimeCoreExperimentalTrial')
foreach($entry in @(@('trial',$trial),@('production',$production))) {
    foreach($view in @(@('x64','SOFTWARE'),@('x86','SOFTWARE\WOW6432Node'))) {
        # Passive registry reads only; frozen host binaries are never invoked.
        $systemTrees[($entry[0]+'_'+$view[0]+'_com')]=Read-YimeCoreSystemKey 2147483650 ($view[1]+'\Classes\CLSID\'+$entry[1])
        $systemTrees[($entry[0]+'_'+$view[0]+'_tip')]=Read-YimeCoreSystemKey 2147483650 ($view[1]+'\Microsoft\CTF\TIP\'+$entry[1])
    }
}
$result['system_registry_trees']=$systemTrees
$result['live_runtime']=Get-YimeCoreLiveRuntimeEvidence $stateRoot
$result['data_files']=@(Get-YimeCoreDataRecords $stateRoot)
New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Force | Out-Null
$result|ConvertTo-Json -Depth 35|Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Maintenance state captured: $OutputPath"
