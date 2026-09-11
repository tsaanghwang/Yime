[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $OutputRoot){$OutputRoot=Join-Path $repo ('.tmp\dual-product\dp1-peer-test-'+[guid]::NewGuid().ToString('N'))}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if([IO.Path]::GetDirectoryName($OutputRoot) -ine (Join-Path $repo '.tmp\dual-product') -or
    [IO.Path]::GetFileName($OutputRoot) -cnotmatch '^dp1-peer-test-' -or (Test-Path -LiteralPath $OutputRoot)){throw 'Fresh isolated peer test root required.'}
$null=[IO.Directory]::CreateDirectory($OutputRoot)
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Assert($Ok,[string]$Message){if(-not $Ok){throw $Message}}
function Check([string]$Name,[scriptblock]$Body){& $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host ('PASS '+$Name)}
function Reject([scriptblock]$Body,[string]$Pattern){$errorText='';try{& $Body|Out-Null}catch{$errorText=$_.Exception.Message};Assert ($errorText -match $Pattern) ('Expected '+$Pattern+'; got '+$errorText)}
function Text([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text)}
function Tree([string]$Path,[bool]$State=$false){& $module {param($p,$s) Get-PeerFileTree $p -State:$s} $Path $State}
Check 'handoff entries reject other hosts before opening supplied paths' {
    if([Environment]::MachineName -ceq (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'This synthetic guard test must not run on the native acceptance target.'}
    Reject {& (Join-Path $PSScriptRoot 'prepare-rime-pime-coexistence-test.ps1') -DeliveryRoot 'C:\NeverReadPeerFixture' -ExpectedIndexSha256 ('a'*64)} 'identified test PC'
    Reject {& (Join-Path $PSScriptRoot 'execute-rime-pime-coexistence-test.ps1') -Mode Install -InstallerPath 'C:\NeverRun.exe' -ExpectedInstallerSha256 ('a'*64) -AuthorizationPath 'C:\NeverRead.json' -TrustedApprovalSha256 ('b'*64) -BoundaryPath 'C:\NeverRead.json' -ReceiptPath 'C:\NeverRead.json'} 'Identified test PC'
}
Check 'present peer learning and unknown settings are hash-only protected' {
    $root=Join-Path $OutputRoot 'state';Text (Join-Path $root 'user-model\learning.json') 'private-fixture';Text (Join-Path $root 'future-setting.txt') 'private-setting'
    $before=Tree $root $true
    Assert ($before.files.Count -eq 2 -and ($before|ConvertTo-Json -Depth 10) -notmatch 'private-fixture|private-setting') 'State missing or content leaked.'
    Text (Join-Path $root 'future-setting.txt') 'changed'
    Reject {Assert-RimePimePeerProtectionUnchanged $before (Tree $root $true)} 'peer changed'
}
Check 'only top-level operational status and logs are excluded' {
    $root=Join-Path $OutputRoot 'operational';Text (Join-Path $root 'logs\log.txt') 'log';Text (Join-Path $root 'runtime-status.json') 'status';Text (Join-Path $root 'user-model\runtime-status.json') 'learning'
    $before=Tree $root $true;Assert ($before.files.Count -eq 1) 'Exclusion scope drift.'
    Text (Join-Path $root 'runtime-status.json') 'new-status'
    Assert-RimePimePeerProtectionUnchanged $before (Tree $root $true)
}
Check 'added and removed peer files and empty directories are detected' {
    $root=Join-Path $OutputRoot 'membership';$before=Tree $root
    Text (Join-Path $root 'payload.dll') 'inert'
    Reject {Assert-RimePimePeerProtectionUnchanged $before (Tree $root)} 'peer changed'
    $before=Tree $root;$null=[IO.Directory]::CreateDirectory((Join-Path $root 'empty'))
    Reject {Assert-RimePimePeerProtectionUnchanged $before (Tree $root)} 'peer changed'
}
Check 'registry value kinds and process identity participate in equality' {
    foreach($field in @('value_kind','pid','image','sid','creation_utc')){
        $before=[pscustomobject]@{value_kind='DWord';pid=10;image='inert';sid='fixture';creation_utc='start'}
        $after=$before|ConvertTo-Json|ConvertFrom-Json;$after.$field='changed'
        Reject {Assert-RimePimePeerProtectionUnchanged $before $after} 'peer changed'
    }
}
# Full admission runs with exclusively synthetic native observations. No current
# machine registry, installed payload, user state or process is read.
& $module {
    $script:present=$true;$script:legacy=$false;$script:wrongCom=$false
    function script:Test-YimePimeSystemRegistryKeyExists {param($h,$v,$k) $script:legacy}
    function script:Get-PeerRegistryTree {param($h,$v,$k) [pscustomobject]@{exists=$script:present;key=$k}}
    function script:Get-YimePimeSystemRegistryValueRecord {param($e)
        $com=$e.id -ceq 'peer-com';$exists=$script:present -and $e.hive -ceq 'LocalMachine'
        $value=if($com){if($script:wrongCom){'C:\Wrong\x.dll'}elseif($e.view -ceq 'Registry32'){'C:\FixturePeer\x86\YimeTextServiceExperiment.dll'}else{'C:\FixturePeer\x64\YimeTextServiceExperiment.dll'}}else{'inert-run'}
        [pscustomobject]@{exists=$exists;value_kind='String';value=$value}
    }
    function script:Get-PeerFileTree {param($r,[switch]$State) [pscustomobject]@{exists=$script:present;root=$r;files=@()}}
    function script:Get-PeerProcesses {param($r,$s) return ,@()}
    function script:Test-Path {param($LiteralPath) $false}
    function script:Assert-YimePimePlainPath {param($p)}
    function script:Get-Content {param($LiteralPath,[switch]$Raw,$Encoding,$ErrorAction) '{"install_root":"C:\\FixturePeer","state_root":"C:\\FixtureState"}'}
}
$boundary=[pscustomobject]@{peer_install_root='C:\FixturePeer';peer_state_root='C:\FixtureState';peer_recovery_root='C:\FixtureRecovery'}
Check 'current installed peer admitted with exact COM and configuration roots' {
    $v=Get-RimePimePeerProtectionSnapshot $boundary 'S-1-5-21-1-2-3-1001';Assert $v.peer_present 'Current peer not admitted.'
}
Check 'absent peer remains an independent single-product choice' {
    & $module {$script:present=$false}
    $v=Get-RimePimePeerProtectionSnapshot $boundary 'S-1-5-21-1-2-3-1001';Assert (-not $v.peer_present) 'Peer became a prerequisite.'
    & $module {$script:present=$true}
}
Check 'historical profile cannot be admitted as current peer' {
    & $module {$script:legacy=$true}
    Reject {Get-RimePimePeerProtectionSnapshot $boundary 'S-1-5-21-1-2-3-1001'} 'Historical'
    & $module {$script:legacy=$false}
}
Check 'invented peer COM root is rejected' {
    & $module {$script:wrongCom=$true}
    Reject {Get-RimePimePeerProtectionSnapshot $boundary 'S-1-5-21-1-2-3-1001'} 'COM does not match'
}
$result=[ordered]@{schema_version='yime-peer-protection-test-v1';checks=$checks.ToArray();passed=$true;native_installed_acceptance_passed=$false}
$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'result.json') -Encoding UTF8
Write-Host ('Evidence: '+(Join-Path $OutputRoot 'result.json'))
