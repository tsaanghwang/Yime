[CmdletBinding()]
param()
# Read-only product inspection for the identified test host and failed transaction.
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$target=-join @([char]0x8ba1,[char]0x7b97,[char]0x673a)
if([Environment]::MachineName -cne $target){throw 'This collector is restricted to the identified test PC.'}
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Run in native Windows PowerShell 5 through run_checked.py.'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$base=Join-Path $env:USERPROFILE 'Yime Rime-PIME Test Archives'
$approvalPath=Join-Path $base 'approval-9fe7f28d-0889-4828-85b5-1f481431b43a\authorization.json'
$approval=Get-Content -LiteralPath $approvalPath -Raw -Encoding UTF8|ConvertFrom-Json
if($approval.initiating_sid -cne $sid){throw 'Current user differs from the retained transaction initiator.'}
$probe=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -PassThru
& $probe {Initialize-Dp1UNativeFacts}
$maintenance=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
$context=[pscustomobject]@{authorization=$approval;probe=$probe}
& $maintenance {param($c) Assert-MaintenanceInitiator $c} $context
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
$rime='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$peer='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$records=[Collections.Generic.List[object]]::new()
function Read-ScopedRegistry($Hive,$View,$Key,$Method,$Values=@{}) {
    $c=Convert-YimePimeSystemRegistryCoordinate $Hive $View $Key
    try{
        $result=Invoke-YimePimeSystemRegistryMethod -Method $Method -Hive $c.hive -Key $c.key -ProviderArchitecture $c.provider_architecture -Values $Values
        $records.Add([pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');hive=$Hive;view=$View;key=$Key;method=$Method;arguments=$Values;result=$result;error=$null})
        return $result
    }catch{
        $records.Add([pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');hive=$Hive;view=$View;key=$Key;method=$Method;arguments=$Values;result=$null;error=$_.Exception.Message})
        return $null
    }
}
$root="$sid\Control Panel\International\User Profile"
$children=Read-ScopedRegistry Users Shared $root EnumKey
$paths=@($root)
if($null -ne $children -and $children.ReturnValue -eq 0){$paths+=@($children.sNames|ForEach-Object{$root+'\'+$_})}
foreach($path in $paths){
    # Names/types are needed to identify the exact rejected name. Do not collect unrelated values.
    $values=Read-ScopedRegistry Users Shared $path EnumValues
    if($null -eq $values -or $values.ReturnValue -ne 0){continue}
    for($i=0;$i -lt @($values.sNames).Count;$i++){
        $name=[string]$values.sNames[$i]
        if($name.IndexOf($rime,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        $method=switch([int]$values.Types[$i]){1{'GetStringValue'}2{'GetExpandedStringValue'}7{'GetMultiStringValue'}default{$null}}
        if($method){$null=Read-ScopedRegistry Users Shared $path $method @{sValueName=$name}}
    }
}
foreach($view in @('Registry32','Registry64')){
    foreach($spec in @(
        @{hive='LocalMachine';key="SOFTWARE\Classes\CLSID\$peer"},
        @{hive='LocalMachine';key="SOFTWARE\Classes\CLSID\$peer\InprocServer32"},
        @{hive='LocalMachine';key="SOFTWARE\Microsoft\CTF\TIP\$peer"},
        @{hive='LocalMachine';key="SOFTWARE\Microsoft\CTF\TIP\$peer\LanguageProfile\0x00000804\$profile"},
        @{hive='Users';key="$sid\SOFTWARE\Microsoft\CTF\TIP\$peer"},
        @{hive='Users';key="$sid\SOFTWARE\Microsoft\CTF\TIP\$peer\LanguageProfile\0x00000804\$profile"}
    )){
        $null=Read-ScopedRegistry $spec.hive $view $spec.key EnumKey
        $null=Read-ScopedRegistry $spec.hive $view $spec.key EnumValues
        if($spec.hive -eq 'Users' -and $spec.key.EndsWith($profile)){
            $null=Read-ScopedRegistry Users $view $spec.key GetDWORDValue @{sValueName='Enable'}
        }
    }
}
$result=[ordered]@{schema_version='yime-peer-current-readonly-v1';transaction_id='9fe7f28d-0889-4828-85b5-1f481431b43a';assembled_utc=[DateTime]::UtcNow.ToString('o');computer=[Environment]::MachineName;initiating_sid=$sid;product_mutation_executed=$false;physical_input='not tested';observations=@($records.ToArray())}
$output=Join-Path $base ('current-peer-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $output -ErrorAction Stop
$utf8=[Text.UTF8Encoding]::new($false)
$json=ConvertTo-Json -InputObject $result -Depth 30
$raw=Join-Path $output 'current-private.json'
$redacted=Join-Path $output 'current-redacted.json'
[IO.File]::WriteAllText($raw,$json,$utf8)
[IO.File]::WriteAllText($redacted,$json.Replace($sid,'<initiating-SID>'),$utf8)
$files=@(foreach($file in @($raw,$redacted)){[pscustomobject]@{path=[IO.Path]::GetFileName($file);bytes=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}})
[IO.File]::WriteAllText((Join-Path $output 'index.json'),(ConvertTo-Json -InputObject $files -Depth 5),$utf8)
Write-Output "Evidence: $output"
Write-Output 'Collection finished. Inspect provider errors; this is not recovery or product acceptance.'
