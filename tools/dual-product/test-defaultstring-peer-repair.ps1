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
$baseline=[pscustomobject][ordered]@{registry=$trees;payload='same';processes=@('same');state=[pscustomobject]@{files=@(
    [pscustomobject]@{path='evidence/language-bar-host.log';bytes=13119;sha256='798c6f380dfbcb340a7dd2c08296a5d6a6ab5641eed8b7af2e0b8130616d37ac'},
    [pscustomobject]@{path='settings.json';bytes=10;sha256='settings'},
    [pscustomobject]@{path='learning.bin';bytes=20;sha256='learning'},
    [pscustomobject]@{path='evidence/other.log';bytes=30;sha256='other'}
)}}
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
$rawBefore=$baseline|ConvertTo-Json -Depth 90 -Compress
$changed=Clone-Fixture $missing
$changed.state.files[0].bytes=13252
$changed.state.files[0].sha256='2d1f97dd3570b95b526ecdd4a5544576a5ac325205ed1d632700682f6ab2d694'
$rawChanged=$changed|ConvertTo-Json -Depth 90 -Compress
Assert-DefaultstringPeerDifference $baseline $changed $sid
if(($baseline|ConvertTo-Json -Depth 90 -Compress) -cne $rawBefore -or ($changed|ConvertTo-Json -Depth 90 -Compress) -cne $rawChanged){throw 'Raw evidence was modified.'}
foreach($index in @(1,2,3)){
    $bad=Clone-Fixture $changed;$bad.state.files[$index].sha256='changed'
    Reject {Assert-DefaultstringPeerDifference $baseline $bad $sid}
}
$bad=Clone-Fixture $changed;$bad.state.files=@($bad.state.files|Where-Object path -ne 'evidence/language-bar-host.log')
Reject {Assert-DefaultstringPeerDifference $baseline $bad $sid}
$bad=Clone-Fixture $changed;$bad.state.files[0].path='evidence/language-bar-host.log.bak'
Reject {Assert-DefaultstringPeerDifference $baseline $bad $sid}
$peer=Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -PassThru
$restored=Clone-Fixture $baseline;$restored.state=$changed.state
& $peer {param($a,$b) Assert-RimePimePeerProtectionUnchanged $a $b} $baseline $restored
Write-Output 'PASS: missing and exact-restored peer admitted; foreign changes, conflicting values, extra children and wrong SID rejected.'
Write-Output 'PASS: exact diagnostic metadata changes admitted before/after repair; raw evidence, settings, learning, other logs and file presence protected.'
