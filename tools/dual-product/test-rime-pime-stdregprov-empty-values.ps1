[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
function Invoke-YimePimeStdRegProvMethod {
    param($Method,$Arguments,$ProviderArchitecture)
    if($Method -eq 'GetStringValue'){return [pscustomobject]@{ReturnValue=0;sValue='fixture'}}
    if($Method -eq 'EnumKey'){return [pscustomobject]@{ReturnValue=0;sNames=$script:children}}
    return [pscustomobject]@{ReturnValue=$script:code;sNames=$script:names;Types=$script:types}
}
$expected=[pscustomobject]@{id='fixture';hive='LocalMachine';view='Registry64';key='SOFTWARE\YimeFixture';name=''}
$script:code=0
foreach($empty in @($null,[DBNull]::Value)) {
    $script:names=$empty;$script:types=$empty;$script:children=$empty
    $shape=Get-YimePimeSystemRegistryKeyShape LocalMachine Registry64 $expected.key
    if(-not $shape.exists -or @($shape.value_names).Count -ne 0 -or @($shape.subkey_names).Count -ne 0){throw 'Empty key produced phantom names.'}
    if((Get-YimePimeSystemRegistryValueRecord $expected).exists){throw 'Empty key produced default value.'}
    if(Test-YimePimeSystemRegistryValueExists LocalMachine Registry64 $expected.key ''){throw 'Empty key reports default value exists.'}
}
$script:names=@('');$script:types=@(1);$script:children=@()
$value=Get-YimePimeSystemRegistryValueRecord $expected
if(-not $value.exists -or $value.value -ne 'fixture'){throw 'Real default value was lost.'}
foreach($case in @(
    @{names=@('named');types=[DBNull]::Value},
    @{names=[DBNull]::Value;types=@(1)},
    @{names=@('');types=@([DBNull]::Value)},
    @{names=@('');types=@($null)},
    @{names=@([DBNull]::Value);types=@(1)}
)) {
    $script:names=$case.names;$script:types=$case.types
    $rejected=$false
    try {$null=Get-YimePimeSystemRegistryKeyShape LocalMachine Registry64 $expected.key} catch {$rejected=$true}
    if(-not $rejected){throw 'Malformed enumeration accepted.'}
}
$script:code=5;$rejected=$false
try {$null=Get-YimePimeSystemRegistryValueRecord $expected} catch {$rejected=$true}
if(-not $rejected){throw 'Provider denial accepted.'}
Write-Output 'PASS: empty/null/DBNull collections, real default value, malformed pairs and provider failure.'
