$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('yime-binding-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$pkg=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru -Force
function Hash([byte[]]$b){& $pkg {param($v) Get-CandidateBytesHash $v} $b}
function Bytes($o){,[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $o -Depth 8 -Compress))}
$a=[ordered]@{install_root=(Join-Path $root 'install');state_root=(Join-Path $root 'state');recovery_root=(Join-Path $root 'recovery');initiating_sid='fixture';target_machine_id='fixture';target_name='fixture';package_sha256=''}
foreach($p in @($a.install_root,$a.state_root,$a.recovery_root)){$null=[IO.Directory]::CreateDirectory($p)}
$exe=Join-Path $a.recovery_root 'maintenance-candidate.exe'
[IO.File]::WriteAllBytes($exe,[byte[]]@(1,2,3))
$obs=& $pkg {param($p) Initialize-CandidateNative;$script:CandidateNative::Inspect($p)} $exe
$a.package_sha256=$obs.Sha256
$plan=[ordered]@{}
foreach($k in $a.Keys){$plan[$k]=$a[$k]}
foreach($f in @('install','state')){
    $plan[$f+'_directory_id']=& $pkg {
        param([string]$p)
        $h=$script:CandidateNative.GetMethod('OpenDirectory',[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,[object[]]@($p))
        try{$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,[object[]]@($h,$p,$true))}finally{$h.Dispose()}
    } $a[$f+'_root']
}
$plan.recovery_executable=@{file_id=$obs.FileId;bytes=$obs.Bytes;sha256=$obs.Sha256}
$prepared=Join-Path $root 'prepared.bin';$auth=Join-Path $root 'authorization.json'
function SavePlan {
    $b=Bytes $plan;$sha=[Security.Cryptography.SHA256]::Create()
    try{$digest=$sha.ComputeHash($b)}finally{$sha.Dispose()}
    [IO.File]::WriteAllBytes($prepared,([Text.Encoding]::ASCII.GetBytes('YDP1UTX1')+[BitConverter]::GetBytes([int]$b.Length)+$digest+$b))
    return Hash $b
}
$expected=SavePlan
[IO.File]::WriteAllBytes($auth,(Bytes $a))
$authHash=Hash ([IO.File]::ReadAllBytes($auth))
function Probe {
    $text=& (Join-Path $PSScriptRoot 'inspect-resume-bindings.ps1') -ArchivedPreparedPath $prepared -ExpectedPreparedSha256 $expected -AuthorizationPath $auth -ExpectedAuthorizationSha256 $authHash
    $text|ConvertFrom-Json
}
$r=Probe
if(-not $r.all_checks_passed -or $r.checks.Count -ne 10){throw 'Positive fixture failed.'}
$plan.install_directory_id='00000000:0000000000000000';$expected=SavePlan
$r=Probe
if(@($r.checks|Where-Object {-not $_.passed}).Count -ne 1 -or ($r.checks|Where-Object check -EQ 'install-directory-identity').passed){throw 'Directory mismatch not isolated.'}
$a.target_name='changed';[IO.File]::WriteAllBytes($auth,(Bytes $a));$authHash=Hash ([IO.File]::ReadAllBytes($auth))
$r=Probe
if(($r.checks|Where-Object check -EQ 'approval-target_name').passed){throw 'Approval mismatch accepted.'}
[IO.File]::WriteAllBytes($exe,[byte[]]@(4,5,6))
$r=Probe
if(($r.checks|Where-Object check -EQ 'recovery-executable-identity').passed){throw 'Recovery hash mismatch accepted.'}
$snapshot=Hash ([IO.File]::ReadAllBytes($prepared));$null=Probe
if($snapshot -cne (Hash ([IO.File]::ReadAllBytes($prepared))) -or [IO.File]::Exists((Join-Path $root 'transaction.lock'))){throw 'Probe changed archived evidence.'}
$expected='0'*64;$rejected=$false
try{$null=Probe}catch{$rejected=$true}
if(-not $rejected){throw 'Wrong ticket digest accepted.'}
Write-Output 'PASS: ten positive checks, directory/approval/recovery mismatch rejection, archive preservation, ticket digest rejection. Isolated fixtures retained in temporary directory.'
