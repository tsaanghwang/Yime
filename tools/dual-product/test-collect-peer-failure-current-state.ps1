$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
# Execute the collector's acquisition block with a synthetic provider only.
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'collect-peer-failure-current-state.ps1') -Raw
$start=$source.IndexOf('$rime=');$end=$source.IndexOf('$output=Join-Path $base')
if($start -lt 0 -or $end -le $start){throw 'Collector acquisition block not found.'}
$sid='S-1-5-21-1-2-3-1001'
$script:reads=[Collections.Generic.List[string]]::new()
function Convert-YimePimeSystemRegistryCoordinate($Hive,$View,$Key){@{hive=$Hive;key=$Key;provider_architecture=64}}
function Invoke-YimePimeSystemRegistryMethod($Method,$Hive,$Key,$ProviderArchitecture,$Values){
    $script:reads.Add($Method+'|'+$Key)
    if($Key -like '*Control Panel*'){
        if($Method -eq 'EnumKey'){return [pscustomobject]@{ReturnValue=0;sNames=@()}}
        if($Method -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=0;sNames=@('0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}','unrelated');Types=@(1,1)}}
        if($Values.sValueName -eq 'unrelated'){throw 'Unrelated content must never be read.'}
        return [pscustomobject]@{ReturnValue=0;sValue='fixture'}
    }
    if($Hive -eq 'Users'){return [pscustomobject]@{ReturnValue=2}}
    throw 'Fixture provider denied access (5)'
}
# The block has its own scope, so capture its result explicitly for verification.
$result=& ([scriptblock]::Create($source.Substring($start,$end-$start)+'; $result'))
$observations=@($result.observations)
if(@($observations|Where-Object {$null -ne $_.error}).Count -ne 16){throw 'Provider errors were not retained distinctly.'}
if(@($observations|Where-Object {$null -ne $_.result -and $_.result.ReturnValue -eq 2}).Count -ne 10){throw 'Missing keys were not retained distinctly.'}
$names=@($observations|Where-Object {$_.key -like '*Control Panel*' -and $_.method -eq 'EnumValues'})[0].result.sNames
if($names[0] -cne '0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'){throw 'Exact reference name changed.'}
if($result.product_mutation_executed -ne $false){throw 'Invalid collection metadata.'}
Write-Output 'PASS: exact reference retained, unrelated content excluded, provider error distinguished from missing key.'
