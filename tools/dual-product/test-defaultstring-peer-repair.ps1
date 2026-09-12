$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'defaultstring-peer-repair.ps1')
$sid='S-1-5-21-1-2-3-1001'
$root=$sid+'\SOFTWARE\Microsoft\CTF\TIP\{E40FA752-BB96-461D-A51D-F40EB437EC65}'
function Clone-Fixture($v){$v|ConvertTo-Json -Depth 90 -Compress|ConvertFrom-Json}
function Reject([scriptblock]$Body){$bad=$false;try{& $Body}catch{$bad=$true};if(-not $bad){throw 'Expected rejection.'}}
$trees=@(foreach($view in @('Registry32','Registry64')){
    $leaf=[pscustomobject][ordered]@{hive='Users';view=$view;key=($root+'\LanguageProfile\0x00000804\{126F54C6-E9B1-4E22-8652-03224CBD49F9}');exists=$true;values=@([pscustomobject]@{name='Enable';value_kind='DWord';value=1;exists=$true});children=@()}
    foreach($suffix in @('\LanguageProfile\0x00000804','\LanguageProfile','')){
        $leaf=[pscustomobject][ordered]@{hive='Users';view=$view;key=($root+$suffix);exists=$true;values=@();children=@($leaf)}
    }
    $leaf
})
$baseline=[pscustomobject][ordered]@{registry=$trees;payload='same';processes=@('same')}
$missing=Clone-Fixture $baseline
foreach($tree in $missing.registry){$tree.exists=$false;$tree.values=@();$tree.children=@()}
Assert-DefaultstringPeerDifference $baseline $missing $sid
Assert-DefaultstringPeerDifference $baseline (Clone-Fixture $baseline) $sid
foreach($tree in $trees){Assert-DefaultstringTipShape $tree $sid}
$bad=Clone-Fixture $missing;$bad.payload='changed';Reject {Assert-DefaultstringPeerDifference $baseline $bad $sid}
$bad=Clone-Fixture $baseline;$bad.registry[0].children[0].children[0].children[0].values[0].value=0
Reject {Assert-DefaultstringPeerDifference $baseline $bad $sid}
Reject {Assert-DefaultstringTipShape $bad.registry[0] $sid}
$bad=Clone-Fixture $trees[0];$bad.children+=Clone-Fixture $bad.children[0];Reject {Assert-DefaultstringTipShape $bad $sid}
Reject {Assert-DefaultstringPeerDifference $baseline $missing 'S-1-5-21-1-2-3-1002'}
Write-Output 'PASS: missing and exact-restored peer admitted; foreign changes, conflicting values, extra children and wrong SID rejected.'
