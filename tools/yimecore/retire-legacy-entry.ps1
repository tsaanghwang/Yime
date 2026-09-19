[CmdletBinding()]
param([ValidateSet('Plan','Apply')][string]$Action='Plan')

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'build-system-observation.ps1')
$scope=Get-YimeCoreDevelopmentScope

$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -cne $expectedSid){throw 'This retirement is authorized only for the initiating MYCOMPUTER user.'}

$legacy='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$legacyTip='0804:'+ $legacy +'{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$current='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$currentTip='0804:'+ $current +'{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$production='{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}'
$productionTip='0804:'+ $production +'{FA550B04-5AD7-411F-A5AC-CA038EC515D7}'
$simpleRime='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$simpleRimeTip='0804:'+ $simpleRime +'{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'

function Get-RecordHash($Record){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $json=ConvertTo-Json -InputObject $Record -Depth 40 -Compress
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}

function Get-LanguageListRecord($List){
    @(foreach($language in $List){
        [ordered]@{
            tag=[string]$language.LanguageTag
            tips=@($language.InputMethodTips)
            spellchecking=[bool]$language.Spellchecking
            handwriting=[bool]$language.Handwriting
        }
    })
}

function Remove-ExactLegacyTip($List,[string]$ExactTip){
    $removed=0
    foreach($language in $List){
        while(@($language.InputMethodTips) -contains $ExactTip){
            if(-not $language.InputMethodTips.Remove($ExactTip)){throw 'Exact legacy TIP removal failed.'}
            $removed++
        }
    }
    return $removed
}

function Get-ProtectedState {
    $records=[ordered]@{}
    foreach($id in @($legacy,$current,$production,$simpleRime)){
        foreach($key in @("SOFTWARE\Classes\CLSID\$id","SOFTWARE\Classes\WOW6432Node\CLSID\$id","SOFTWARE\Microsoft\CTF\TIP\$id","SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$id")){
            $records["machine/$key"]=Get-RecordHash (Read-YimeCoreSystemKey 2147483650 $key)
        }
    }
    foreach($key in @("Software\Microsoft\CTF\TIP\$current","Software\Microsoft\CTF\TIP\$production","Software\Microsoft\CTF\TIP\$simpleRime",'Keyboard Layout\Preload','Keyboard Layout\Substitutes')){
        $records["user/$key"]=Get-RecordHash (Read-YimeCoreSystemKey 2147483651 "$sid\$key")
    }
    $profile=Read-YimeCoreSystemKey 2147483651 "$sid\Control Panel\International\User Profile"
    $records.default=Get-RecordHash @($profile.values|Where-Object {$_.name -eq 'InputMethodOverride'})
    foreach($key in @('Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeSimple-yimecore','Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeSimple-rime-pime')){
        $records["machine/$key"]=Get-RecordHash (Read-YimeCoreSystemKey 2147483650 $key)
    }
    $run=Read-YimeCoreSystemKey 2147483651 "$sid\Software\Microsoft\Windows\CurrentVersion\Run"
    $records.run=Get-RecordHash @($run.values|Where-Object {$_.name -in @('YimeSimple-yimecore','YimeSimple-rime-pime')})
    return $records
}

function Assert-Preserved($Before,$After){
    foreach($key in $Before.Keys){
        if(-not $After.Contains($key) -or $Before[$key] -cne $After[$key]){throw "Protected state changed: $key"}
    }
}

function Export-RegistrySnapshots([string]$Archive){
    $exports=@()
    foreach($key in @('Control Panel\International\User Profile',"Software\Microsoft\CTF\TIP\$legacy","Software\Microsoft\CTF\TIP\$current","Software\Microsoft\CTF\TIP\$production","Software\Microsoft\CTF\TIP\$simpleRime",'Keyboard Layout\Preload','Keyboard Layout\Substitutes')){
        $system=Read-YimeCoreSystemKey 2147483651 "$sid\$key"
        if(-not $system.exists){continue}
        $path=Join-Path $Archive ('registry-'+$exports.Count+'.reg')
        & reg.exe export "HKU\$sid\$key" $path /y|Out-Null
        if($LASTEXITCODE -ne 0){throw 'Registry backup failed before mutation.'}
        $identity=Assert-YimeCoreNativeFile $path
        $exports+=@([ordered]@{key=$key;path=$path;sha256=$identity.sha256})
    }
    return $exports
}

function Restore-RegistrySnapshots($Exports,[switch]$ProtectedOnly){
    foreach($entry in $Exports){
        if($ProtectedOnly -and $entry.key -cnotin @("Software\Microsoft\CTF\TIP\$current","Software\Microsoft\CTF\TIP\$production","Software\Microsoft\CTF\TIP\$simpleRime")){continue}
        if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ine $entry.sha256){throw 'Recovery export hash mismatch.'}
        & reg.exe import $entry.path|Out-Null
        if($LASTEXITCODE -ne 0){throw 'Registry recovery import failed.'}
    }
}

$profile=Read-YimeCoreSystemKey 2147483651 "$sid\Control Panel\International\User Profile"
$default=@($profile.values|Where-Object {$_.name -eq 'InputMethodOverride'})
if($default.Count -ne 1 -or $default[0].value -eq $legacyTip){throw 'Cannot retire a default legacy profile or an ambiguous default.'}

# Both Plan and Apply require Explorer ancestry. Packaged application processes
# can observe a virtualized/stale language list that differs from StdRegProv and
# from the standalone process which would perform the actual write.
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use standalone Windows PowerShell 5.1.'}
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use ordinary same-user PowerShell, not an administrator window.'}

$original=Get-WinUserLanguageList
$originalRecord=Get-LanguageListRecord $original
$desired=Get-WinUserLanguageList
$removed=Remove-ExactLegacyTip $desired $legacyTip
$desiredRecord=Get-LanguageListRecord $desired
$currentCount=@($desiredRecord|ForEach-Object {$_.tips}|Where-Object {$_ -eq $currentTip}).Count
$productionCount=@($desiredRecord|ForEach-Object {$_.tips}|Where-Object {$_ -eq $productionTip}).Count
$simpleRimeCount=@($desiredRecord|ForEach-Object {$_.tips}|Where-Object {$_ -eq $simpleRimeTip}).Count
if($currentCount -ne 1 -or $productionCount -ne 1){throw 'Current YimeCore and Rime/PIME entries must each remain exactly once.'}
if($simpleRimeCount -gt 1){throw 'Simple-installer Rime/PIME entry is ambiguous.'}
$before=Get-ProtectedState

$plan=[ordered]@{
    schema_version='legacy-entry-retirement-v3'
    action=$Action
    target=$legacyTip
    legacy_entry_count=$removed
    current_entry_count=$currentCount
    rime_pime_entry_count=$productionCount
    simple_rime_pime_entry_count=$simpleRimeCount
    default_unchanged=$true
    historical_payloads_required=$false
    file_or_machine_registration_mutation_authorized=$false
    scope_id=$scope.id
    observation_context='unpackaged-explorer-powershell-5.1'
    mutation_performed=$false
}
if($Action -eq 'Plan'){$plan|ConvertTo-Json -Depth 5;return}
if($removed -eq 0){$plan.action='Apply';$plan.already_absent=$true;$plan|ConvertTo-Json -Depth 5;return}

$archive=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\legacy-entry-retirement-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-YimeCorePlainPath $archive
[void][IO.Directory]::CreateDirectory($archive)
$original|Export-Clixml (Join-Path $archive 'language-list.xml')
$before|ConvertTo-Json -Depth 10|Set-Content (Join-Path $archive 'protected-before.json') -Encoding UTF8
$exports=Export-RegistrySnapshots $archive
$exports|ConvertTo-Json -Depth 5|Set-Content (Join-Path $archive 'registry-exports.json') -Encoding UTF8

$result=[ordered]@{
    schema_version='legacy-entry-retirement-v3'
    generated_at=[DateTime]::UtcNow.ToString('o')
    target=$legacyTip
    archive=$archive
    passed=$false
    removed_count=$removed
    machine_registration_removed=$false
    files_removed=$false
    mutation_requested=$true
}
try{
    Set-WinUserLanguageList -LanguageList $desired -Force
    Restore-RegistrySnapshots $exports -ProtectedOnly
    $remaining=Get-WinUserLanguageList
    $remainingRecord=Get-LanguageListRecord $remaining
    if((Get-RecordHash $remainingRecord) -cne (Get-RecordHash $desiredRecord)){throw 'Windows changed language preferences or an unrelated input entry.'}
    if(@($remainingRecord|ForEach-Object {$_.tips}|Where-Object {$_ -eq $legacyTip}).Count){throw 'Legacy entry remains in Windows language list.'}
    Assert-Preserved $before (Get-ProtectedState)
    $result.passed=$true
}catch{
    $result.error=$_.Exception.Message
    try{
        Set-WinUserLanguageList -LanguageList $original -Force
        Restore-RegistrySnapshots $exports
        if((Get-RecordHash (Get-LanguageListRecord (Get-WinUserLanguageList))) -cne (Get-RecordHash $originalRecord)){throw 'Rollback language list does not match the original.'}
        Assert-Preserved $before (Get-ProtectedState)
        $result.rollback_protected_state_verified=$true
    }catch{$result.rollback_error=$_.Exception.Message}
}finally{
    $result|ConvertTo-Json -Depth 10|Set-Content (Join-Path $archive 'result.json') -Encoding UTF8
}
Write-Host "Evidence: $archive\result.json"
if(-not $result.passed){throw "Retirement did not pass; see recovery evidence: $archive"}
Write-Host 'PASS: exact legacy user-language-list entry retired; registrations and files preserved.'
