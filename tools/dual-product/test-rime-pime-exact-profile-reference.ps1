$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
$clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$profile='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'
$exact='0804:'+$clsid+$profile
$peer='0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
foreach($name in @($exact,$exact.ToLowerInvariant(),('0x'+$exact))){
    if(-not (Test-YimePimeProfileRegistryReference -Name $name -Value $null)){throw 'Exact current/legacy profile reference not recognized.'}
}
if(Test-YimePimeProfileRegistryReference -Name $peer -Value $null){throw 'Peer reference misidentified as Rime/PIME.'}
foreach($name in @(($exact+';'+$peer),(' '+$exact),($exact+' '),('0409:'+$clsid+$profile),('0804:'+$clsid+'{00000000-0000-0000-0000-000000000000}'))){
    $rejected=$false
    try{$null=Test-YimePimeProfileRegistryReference -Name $name -Value $null}catch{$rejected=$true}
    if(-not $rejected){throw "Ambiguous reference accepted: $name"}
}
# Exercise the same EnumValues name path as the real rollback stack, with DWORD
# metadata and a separate peer entry. No registry or product mutations occur.
function Invoke-YimePimeSystemRegistryMethod($Method,$Hive,$Key,$ProviderArchitecture,$Values){
    switch($Method){
        'EnumKey' {return [pscustomobject]@{ReturnValue=0;sNames=@('zh-Hans-CN')}}
        'EnumValues' {
            if($Key.EndsWith('zh-Hans-CN')){return [pscustomobject]@{ReturnValue=0;sNames=@($peer,$exact);Types=@(4,4)}}
            return [pscustomobject]@{ReturnValue=0;sNames=@();Types=@()}
        }
        default {throw "Unexpected provider method: $Method"}
    }
}
$currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if(-not (Test-YimePimeTargetUserControlPanelReference -TargetUserSid $currentSid)){throw 'Exact DWORD-name reference was not detected.'}
Write-Output 'PASS: exact observed reference, legacy compatibility, peer separation and mixed-reference rejection.'
