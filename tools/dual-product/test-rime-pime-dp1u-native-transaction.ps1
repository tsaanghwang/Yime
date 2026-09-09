[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$parent=Join-Path $repo '.tmp\dual-product';$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if([IO.Path]::GetDirectoryName($output) -cne $parent -or [IO.Path]::GetFileName($output) -cnotmatch '^dp1-u-native-transaction-test-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $output)){throw 'Use a fresh repository .tmp/dual-product/dp1-u-native-transaction-test-* output root.'}
if(-not [Environment]::Is64BitProcess){throw 'The owned native transaction fixtures require a 64-bit test host.'}
for($cursor=$parent;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test root ancestor is indirect.'}
}
[void][IO.Directory]::CreateDirectory($output)
$modulePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-native-transaction.psm1'
$hivePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-application-hive.psm1'
$removalPath=Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.psm1'
$module=Import-Module $modulePath -PassThru;$hiveModule=Import-Module $hivePath -PassThru;$removalModule=Import-Module $removalPath -PassThru
$checks=[Collections.Generic.List[object]]::new();$fixtures=[Collections.Generic.List[object]]::new();$children=[Collections.Generic.List[object]]::new()
$names=@('machine-com-server-x86','machine-com-server-native','machine-profile-icon-index','machine-product-root','target-profile-enabled','target-profile-metadata')
$shell=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Core'){'pwsh.exe'}else{'powershell.exe'})
$sourceNames=@('rime-pime-dp1u-native-transaction.cs','rime-pime-dp1u-native-transaction.psm1','rime-pime-dp1u-application-hive.cs','rime-pime-dp1u-application-hive.psm1','rime-pime-dp1u-exact-file-removal.cs','rime-pime-dp1u-exact-file-removal.psm1','test-rime-pime-dp1u-native-transaction.ps1')
function Source-Records {return @($sourceNames|ForEach-Object{$p=Join-Path $PSScriptRoot $_;[pscustomobject]@{path=$p;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $p).Length}})}
$initialSources=Source-Records
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true});Write-Host "PASS: $Name"}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message;position=$_.InvocationInfo.PositionMessage;exception=$_.Exception.ToString()});Write-Host "FAIL: $Name - $($_.Exception.Message)"}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern='*'){$caught=$null;try{& $Body|Out-Null}catch{$caught=$_};if($null -eq $caught){throw 'Expected rejection.'};if($caught.Exception.Message -notlike $Pattern){throw "Unexpected rejection: $($caught.Exception.Message)"}}
function Hash-Bytes([byte[]]$Bytes){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function File-Reference([string]$Path){[pscustomobject]@{path=$Path;bytes=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}}
function New-Values([string]$Tag){
    $number=if($Tag -ceq 'old'){1}else{2}
    $enabledKind='Absent';$enabledBytes=[byte[]]::new(0)
    if($Tag -cne 'old'){$enabledKind='DWord';$enabledBytes=[BitConverter]::GetBytes([int]$number)}
    return @(
        [pscustomobject]@{value_id=$names[0];kind='String';raw_bytes=[Text.Encoding]::Unicode.GetBytes("$Tag-x86`0")},
        [pscustomobject]@{value_id=$names[1];kind='String';raw_bytes=[Text.Encoding]::Unicode.GetBytes("$Tag-native`0")},
        [pscustomobject]@{value_id=$names[2];kind='DWord';raw_bytes=[BitConverter]::GetBytes([int]$number)},
        [pscustomobject]@{value_id=$names[3];kind='ExpandString';raw_bytes=[Text.Encoding]::Unicode.GetBytes("%PATH%\$Tag`0")},
        [pscustomobject]@{value_id=$names[4];kind=$enabledKind;raw_bytes=$enabledBytes},
        [pscustomobject]@{value_id=$names[5];kind='MultiString';raw_bytes=[Text.Encoding]::Unicode.GetBytes("$Tag`0`0tail`0`0")}
    )
}
function Inspect-File([string]$Path){
    $r=& $removalModule {param($p)$s=Open-ExactRemovalSource;try{$script:RemovalNativeType::Inspect($p)}finally{$s.Dispose()}} $Path
    return [pscustomobject]@{file_id=$r.FileId;bytes=[long]$r.Bytes;sha256=$r.Sha256}
}
function Read-Hive($Case){
    $id=Inspect-File $Case.hive;$ctx=Open-RimePimeDp1UExistingApplicationHive $Case.hive $id
    try{Assert-ForeignHive $ctx;return ,(Export-RimePimeDp1UApplicationHiveValues $ctx (Get-RimePimeDp1UApplicationHiveSnapshot $ctx))}finally{Close-RimePimeDp1UApplicationHive $ctx|Out-Null}
}
function Write-ForeignHive($Context){
    & $hiveModule {param($c)
        $b=Get-AppHiveBundle $c;$h=$b.native.GetType().GetField('hive',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($b.native)
        $method=$script:HiveNativeType.GetMethod('RegSetValueExW',[Reflection.BindingFlags]'Static,NonPublic')
        $rc=$method.Invoke($null,[object[]]@($h,'foreign-owned-fixture',[uint32]0,[uint32]3,[byte[]]@(222,173,190,239),[uint32]4))
        if($rc -ne 0){throw 'Own foreign binary value setup failed.'}
    } $Context
}
function Assert-ForeignHive($Context){
    & $hiveModule {param($c)
        $b=Get-AppHiveBundle $c;$h=$b.native.GetType().GetField('hive',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($b.native)
        $method=$script:HiveNativeType.GetMethod('RegQueryValueExW',[Reflection.BindingFlags]'Static,NonPublic')
        $queryArgs=[object[]]@($h,'foreign-owned-fixture',[IntPtr]::Zero,[uint32]0,[byte[]]::new(16),[uint32]16)
        $rc=$method.Invoke($null,$queryArgs)
        if($rc -ne 0 -or $queryArgs[3] -ne 3 -or $queryArgs[5] -ne 4 -or [BitConverter]::ToString($queryArgs[4],0,4) -cne 'DE-AD-BE-EF'){throw 'Foreign private-hive type/bytes changed.'}
    } $Context
}
function Write-Hive($Case,$Values){
    $id=Inspect-File $Case.hive;$ctx=Open-RimePimeDp1UExistingApplicationHive $Case.hive $id
    try{Require (Set-RimePimeDp1UApplicationHiveValues $ctx (Get-RimePimeDp1UApplicationHiveSnapshot $ctx) $Values).passed 'Owned hive setup failed.'}finally{Close-RimePimeDp1UApplicationHive $ctx|Out-Null}
}
function Values-Equal($Left,$Right){
    if($Left.Count -ne 6 -or $Right.Count -ne 6){return $false}
    for($i=0;$i -lt 6;$i++){if($Left[$i].value_id -cne $Right[$i].value_id -or $Left[$i].kind -cne $Right[$i].kind -or (Hash-Bytes $Left[$i].raw_bytes) -cne (Hash-Bytes $Right[$i].raw_bytes)){return $false}}
    return $true
}
function New-Case {
    $id=[guid]::NewGuid().ToString('N');$root=Join-Path $parent ('dp1-u-native-transaction-'+$id)
    $hive=Join-Path $parent ('dp1-u-app-hive-'+$id+'\private.hiv');$payload=Join-Path $parent ('dp1-u-exact-removal-'+$id+'\payload')
    foreach($p in @($root,[IO.Path]::GetDirectoryName($hive),$payload)){Require (-not (Test-Path -LiteralPath $p)) 'Own GUID fixture path already exists.';[void][IO.Directory]::CreateDirectory($p)}
    $old=New-Values 'old';$new=New-Values 'new';$ctx=Open-RimePimeDp1UApplicationHive $hive
    try{Require (Set-RimePimeDp1UApplicationHiveValues $ctx (Get-RimePimeDp1UApplicationHiveSnapshot $ctx) $old).passed 'Owned initial hive write failed.';Write-ForeignHive $ctx}finally{$identity=Close-RimePimeDp1UApplicationHive $ctx}
    $files=@(foreach($leaf in @('first.bin','second.bin')){
        $p=Join-Path $payload $leaf;[IO.File]::WriteAllText($p,('owned-'+$id+'-'+$leaf),[Text.UTF8Encoding]::new($false));$f=Inspect-File $p
        [pscustomobject]@{path=$leaf;file_id=$f.file_id;bytes=$f.bytes;sha256=$f.sha256}
    })
    [IO.File]::WriteAllText((Join-Path $payload 'foreign.txt'),'foreign fixture preserved',[Text.UTF8Encoding]::new($false))
    $c=[pscustomobject]@{id=$id;root=$root;hive=$hive;payload=$payload;old=$old;desired=$new;files=$files;expected_hive=$identity;ticket=$null}
    $fixtures.Add([pscustomobject]@{transaction_root=$root;hive=$hive;payload=$payload});return $c
}
function Prepare($Case){
    $Case.ticket=New-RimePimeDp1UNativeTransaction -TransactionRoot $Case.root -ExpectedHiveFile $Case.expected_hive -DesiredValues $Case.desired -ExpectedFiles $Case.files
    Require ($Case.ticket.prepared_sha256 -is [string] -and $Case.ticket.prepared_sha256 -cmatch '^[0-9a-f]{64}$' -and $Case.ticket.fixture_only -is [bool] -and $Case.ticket.fixture_only -and $Case.ticket.execution_authorized -is [bool] -and -not $Case.ticket.execution_authorized) 'Prepared ticket claims/types incorrect.'
    Require (Values-Equal (Read-Hive $Case) $Case.old) 'Prepare mutated the hive.';Assert-Payload $Case 'present'
}
function Assert-Payload($Case,[string]$State){
    foreach($f in $Case.files){$p=Join-Path $Case.payload $f.path;if($State -ceq 'absent'){Require (-not [IO.File]::Exists($p)) 'Payload remains after commit.'}else{$actual=Inspect-File $p;Require ($actual.file_id -ceq $f.file_id -and $actual.bytes -eq $f.bytes -and $actual.sha256 -ceq $f.sha256) 'Uncommitted payload identity/content changed.'}}
    Require ([IO.File]::ReadAllText((Join-Path $Case.payload 'foreign.txt')) -ceq 'foreign fixture preserved') 'Foreign file changed.'
    Require ([IO.Directory]::Exists($Case.payload) -and [IO.Directory]::Exists($Case.root)) 'A fixture root was removed.'
}
function Assert-Result($Result,[string]$Disposition){
    Require ($Result.schema_version -ceq 'yime-rime-pime-dp1u-native-transaction-result-v1' -and $Result.disposition -ceq $Disposition -and $Result.desired_state_verified -is [bool] -and $Result.desired_state_verified) 'Wrong transaction outcome.'
    Require ($Result.fixture_only -is [bool] -and $Result.fixture_only) 'Native transaction fixture scope missing.'
    foreach($flag in @('production_registration_modified','installer_executed','uninstaller_executed','runtime_started','installed_yimecore_local12_touched','production_user_data_accessed','directory_or_root_removal_performed','hardware_power_loss_verified','directory_metadata_durability_verified','hostile_same_sid_prevention_verified','missing_members_attributed_to_this_process','in_memory_caller_authenticated','full_native_product_transaction_complete','dp1_u_acceptance_passed')){Require ($Result.$flag -is [bool] -and -not $Result.$flag) "Unsupported transaction claim: $flag"}
}
function Invoke-Own($Case){Invoke-RimePimeDp1UNativeTransaction -TransactionRoot $Case.root -PreparedSha256 $Case.ticket.prepared_sha256}
function Resume-Own($Case){Resume-RimePimeDp1UNativeTransaction -TransactionRoot $Case.root -PreparedSha256 $Case.ticket.prepared_sha256}
function Write-Frame([string]$Path,[string]$Json){
    $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($Json);$sha=[Security.Cryptography.SHA256]::Create();try{$digest=$sha.ComputeHash($bytes)}finally{$sha.Dispose()}
    $stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
    try{$writer.Write([Text.Encoding]::ASCII.GetBytes('YDP1UTX1'));$writer.Write([int]$bytes.Length);$writer.Write([byte[]]$digest);$writer.Write([byte[]]$bytes);$writer.Flush();[IO.File]::WriteAllBytes($Path,$stream.ToArray())}finally{$writer.Dispose();$stream.Dispose()}
    return Hash-Bytes $bytes
}
function Read-Plan($Case){$bytes=[IO.File]::ReadAllBytes((Join-Path $Case.root 'prepared.bin'));return ([Text.UTF8Encoding]::new($false,$true).GetString($bytes,44,$bytes.Length-44)|ConvertFrom-Json)}
function Decision($Case,[string]$Disposition){return [pscustomobject]@{schema_version='yime-rime-pime-dp1u-native-decision-v1';transaction_id=$Case.id;prepared_sha256=$Case.ticket.prepared_sha256;disposition=$Disposition}}
$childSource=@'
param([string]$ModulePath,[string]$BindingPath,[string]$Mode,[string]$Checkpoint,[string]$ResultPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$b=[IO.File]::ReadAllText($BindingPath)|ConvertFrom-Json;$m=Import-Module $ModulePath -PassThru
try{
    if($Checkpoint -ceq 'partial-hive-write'){
        & $m {param($r)$t=Open-Tx $r $false;Close-Tx $t} $b.transaction_root
        $h=& $m {$script:TxHiveModule}
        & $h {function script:Write-AppHiveValue($Native,$Wanted,[int]$Index){$Native.WriteIndex($Wanted,$Index);$Native.Flush();if($Index -eq 2){[Console]::WriteLine('fixture-checkpoint:partial-hive-write');[Environment]::Exit(73)}}}
    }elseif($Checkpoint){
        & $m {param($name)$script:OwnedStopPoint=$name;function script:Invoke-TxCheckpoint([string]$Name){if($Name -ceq $script:OwnedStopPoint){[Console]::WriteLine('fixture-checkpoint:'+$Name);[Environment]::Exit(73)}}} $Checkpoint
    }
    if($Mode -ceq 'Invoke'){$r=Invoke-RimePimeDp1UNativeTransaction -TransactionRoot $b.transaction_root -PreparedSha256 $b.prepared_sha256}
    elseif($Mode -ceq 'Resume'){$r=Resume-RimePimeDp1UNativeTransaction -TransactionRoot $b.transaction_root -PreparedSha256 $b.prepared_sha256}
    else{throw 'Unknown own fixture child mode.'}
    [IO.File]::WriteAllText($ResultPath,($r|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}finally{Remove-Module $m}
'@
$childPath=Join-Path $output 'owned-transaction-child.ps1';[IO.File]::WriteAllText($childPath,$childSource,[Text.UTF8Encoding]::new($false))
function Child($Case,[string]$Mode,[string]$Checkpoint='',[int]$ExpectedExit=0){
    $id=[guid]::NewGuid().ToString('N');$binding=Join-Path $output ($id+'-binding.json');$resultPath=Join-Path $output ($id+'-result.json')
    $stdoutPath=Join-Path $output ($id+'-stdout.log');$stderrPath=Join-Path $output ($id+'-stderr.log')
    [IO.File]::WriteAllText($binding,([pscustomobject]@{transaction_root=$Case.root;prepared_sha256=$Case.ticket.prepared_sha256}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$shell
    $p.StartInfo.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$childPath+'" -ModulePath "'+$modulePath+'" -BindingPath "'+$binding+'" -Mode '+$Mode+' -Checkpoint "'+$Checkpoint+'" -ResultPath "'+$resultPath+'"'
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $started=$false;$stdout=$null;$stderr=$null;$forced=$false
    try{
        $started=$p.Start();Require $started 'Own transaction child failed to start.';$p.StandardInput.Close()
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(30000)){$forced=$true;$p.Kill();$p.WaitForExit()}
        $outText=$stdout.GetAwaiter().GetResult();$errText=$stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($stdoutPath,$outText,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($stderrPath,$errText,[Text.UTF8Encoding]::new($false))
        $children.Add([pscustomobject]@{transaction_root=$Case.root;mode=$Mode;checkpoint=$Checkpoint;actual_exit_code=$p.ExitCode;expected_exit_code=$ExpectedExit;forced_cleanup=$forced;stdin_closed=$true;binding=(File-Reference $binding);stdout=(File-Reference $stdoutPath);stderr=(File-Reference $stderrPath);result_path=$resultPath})
        Require (-not $forced) 'Own transaction child timed out.'
        Require ($p.ExitCode -eq $ExpectedExit) "Own transaction child exit $($p.ExitCode), wanted $ExpectedExit. See $stderrPath"
        if($ExpectedExit -eq 73){Require ($outText.Contains('fixture-checkpoint:'+$Checkpoint) -and -not [IO.File]::Exists($resultPath)) 'Child did not reach the exact interruption boundary.';return}
        Require ([IO.File]::Exists($resultPath)) 'Fresh child did not publish a result.'
        return ([IO.File]::ReadAllText($resultPath)|ConvertFrom-Json)
    }finally{
        if($started -and -not $p.HasExited){$p.Kill();$p.WaitForExit()}
        if($null -ne $stdout){$null=$stdout.GetAwaiter().GetResult()};if($null -ne $stderr){$null=$stderr.GetAwaiter().GetResult()};$p.Dispose()
    }
}
try {
Check 'native-commit-removes-only-approved-files-and-repeated-resume-revalidates' {
    $c=New-Case;Prepare $c;$r=Invoke-Own $c;Assert-Result $r 'commit-complete';Require (-not $r.replayed) 'First apply was labelled replay.'
    Require (Values-Equal (Read-Hive $c) $c.desired) 'Committed hive differs.';Assert-Payload $c 'absent'
    $again=Resume-Own $c;Assert-Result $again 'commit-complete';Require $again.replayed 'Resume missing replay label.'
    foreach($row in $again.payload_observations){Require (-not $row.removed_this_invocation) 'Replay claimed prior removals.'}
    Reject {Invoke-Own $c} '*use Resume*';Assert-Payload $c 'absent'
}
Check 'prepared-resume-rolls-back-without-payload-removal-and-repeated-resume-is-safe' {
    $c=New-Case;Prepare $c;$r=Resume-Own $c;Assert-Result $r 'rolled-back';Require (Values-Equal (Read-Hive $c) $c.old) 'Prepared recovery changed old hive.';Assert-Payload $c 'present'
    Assert-Result (Resume-Own $c) 'rolled-back';Assert-Payload $c 'present'
}
Check 'inadmissible-old-field-kind-is-rejected-before-any-prepared-publication' {
    $c=New-Case;$ctx=Open-RimePimeDp1UExistingApplicationHive $c.hive $c.expected_hive
    try{
        & $hiveModule {param($context)
            $b=Get-AppHiveBundle $context;$h=$b.native.GetType().GetField('hive',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($b.native)
            $method=$script:HiveNativeType.GetMethod('RegSetValueExW',[Reflection.BindingFlags]'Static,NonPublic')
            $bytes=[Text.Encoding]::Unicode.GetBytes("%PATH%\inadmissible-old`0")
            $rc=$method.Invoke($null,[object[]]@($h,'machine-com-server-x86',[uint32]0,[uint32]2,$bytes,[uint32]$bytes.Length))
            if($rc -ne 0){throw 'Own old-kind fixture write failed.'}
        } $ctx
    }finally{$c.expected_hive=Close-RimePimeDp1UApplicationHive $ctx}
    $before=Read-Hive $c;Require ($before[0].kind -ceq 'ExpandString') 'Old-kind negative fixture missing.'
    Reject {New-RimePimeDp1UNativeTransaction $c.root $c.expected_hive $c.desired $c.files} '*allowlist*'
    Require (Values-Equal (Read-Hive $c) $before) 'Invalid old-value admission mutated the hive.';Assert-Payload $c 'present'
    $recordNames=@(Get-ChildItem -LiteralPath $c.root -Force|ForEach-Object{$_.Name})
    Require ($recordNames.Count -eq 1 -and $recordNames[0] -ceq 'transaction.lock') 'An unrecoverable plan or pending record was published.'
}
foreach($point in @('before-hive-write','after-hive-write','after-commit','after-removal-1','after-terminal')){
Check ('fresh-process-interruption-at-'+$point+'-recovers-by-decision') {
    $c=New-Case;Prepare $c;Child $c 'Invoke' $point 73
    $committed=$point -cin @('after-commit','after-removal-1','after-terminal')
    if($point -ceq 'before-hive-write'){Require (Values-Equal (Read-Hive $c) $c.old) 'Before-write checkpoint already changed hive.'}
    else{Require (Values-Equal (Read-Hive $c) $c.desired) 'Checkpoint did not follow real native writes.'}
    if($point -ceq 'after-removal-1'){Require (-not [IO.File]::Exists((Join-Path $c.payload 'first.bin')) -and [IO.File]::Exists((Join-Path $c.payload 'second.bin'))) 'Removal checkpoint did not retain partial progress.'}
    $r=Child $c 'Resume';Assert-Result $r $(if($committed){'commit-complete'}else{'rolled-back'})
    Require (Values-Equal (Read-Hive $c) $(if($committed){$c.desired}else{$c.old})) 'Fresh recovery hive state incorrect.'
    Assert-Payload $c $(if($committed){'absent'}else{'present'})
}
}
Check 'half-written-real-hive-restores-old-values-in-fresh-process' {
    $c=New-Case;Prepare $c;Child $c 'Invoke' 'partial-hive-write' 73
    $mixed=Read-Hive $c
    for($i=0;$i -lt 6;$i++){$expected=if($i -le 2){$c.desired[$i]}else{$c.old[$i]};Require ((Hash-Bytes $mixed[$i].raw_bytes) -ceq (Hash-Bytes $expected.raw_bytes) -and $mixed[$i].kind -ceq $expected.kind) 'Real partial native state missing.'}
    Assert-Result (Child $c 'Resume') 'rolled-back';Require (Values-Equal (Read-Hive $c) $c.old) 'Partial state did not restore.';Assert-Payload $c 'present'
}
Check 'interrupted-rollback-is-reentered-before-terminal-publication' {
    $c=New-Case;Prepare $c;Child $c 'Invoke' 'after-hive-write' 73;Child $c 'Resume' 'after-rollback' 73
    Require (Values-Equal (Read-Hive $c) $c.old) 'Rollback checkpoint preceded actual restore.'
    Require (-not [IO.File]::Exists((Join-Path $c.root 'terminal.bin'))) 'Interrupted rollback claimed terminal publication.'
    Assert-Result (Child $c 'Resume') 'rolled-back';Assert-Payload $c 'present'
}
Check 'unapproved-third-current-value-is-preserved-with-all-files' {
    $c=New-Case;Prepare $c;$other=New-Values 'old';$other[0].raw_bytes=[Text.Encoding]::Unicode.GetBytes("external-third`0");Write-Hive $c $other
    Reject {Resume-Own $c} '*Unapproved*';Reject {Invoke-Own $c} '*Unapproved*'
    Require (Values-Equal (Read-Hive $c) $other) 'Third party value overwritten.';Assert-Payload $c 'present'
    Require (-not [IO.File]::Exists((Join-Path $c.root 'commit.bin')) -and -not [IO.File]::Exists((Join-Path $c.root 'terminal.bin'))) 'Rejected third value created a decision.'
}
foreach($change in @('same-bytes-new-file-id','changed-bytes-same-file-id')){
Check ('payload-'+$change+'-is-preserved-before-commit') {
    $c=New-Case;Prepare $c;$path=Join-Path $c.payload 'first.bin'
    if($change -ceq 'same-bytes-new-file-id'){[IO.File]::Move($path,$path+'.original');[IO.File]::Copy($path+'.original',$path)}else{[IO.File]::WriteAllText($path,'changed owned fixture')}
    $changed=Inspect-File $path;Reject {Invoke-Own $c} '*identity/bytes changed*';Reject {Resume-Own $c} '*identity/bytes changed*'
    $after=Inspect-File $path;Require ($after.file_id -ceq $changed.file_id -and $after.sha256 -ceq $changed.sha256) 'Changed payload overwritten/deleted.'
    Require ([IO.File]::Exists((Join-Path $c.payload 'second.bin')) -and (Values-Equal (Read-Hive $c) $c.old)) 'Payload rejection changed later state.'
}
}
Check 'wrong-external-prepared-sha-rejects-without-mutation' {
    $c=New-Case;Prepare $c;Reject {Invoke-RimePimeDp1UNativeTransaction $c.root ('0'*64)} '*external SHA256*';Require (Values-Equal (Read-Hive $c) $c.old) 'Wrong SHA changed hive.';Assert-Payload $c 'present'
}
Check 'copied-prepared-record-rejects-different-transaction-root' {
    $a=New-Case;Prepare $a;$b=New-Case;Prepare $b
    [IO.File]::WriteAllBytes((Join-Path $b.root 'prepared.bin'),[IO.File]::ReadAllBytes((Join-Path $a.root 'prepared.bin')))
    Reject {Resume-RimePimeDp1UNativeTransaction $b.root $a.ticket.prepared_sha256} '*root/identity*';Assert-Payload $a 'present';Assert-Payload $b 'present';Require (Values-Equal (Read-Hive $b) $b.old) 'Copied record changed target hive.'
}
Check 'persisted-source-binding-drift-is-rejected' {
    $c=New-Case;Prepare $c;$plan=Read-Plan $c;$plan.source_hashes.'rime-pime-dp1u-application-hive.psm1'='0'*64
    $digest=Write-Frame (Join-Path $c.root 'prepared.bin') ($plan|ConvertTo-Json -Depth 20 -Compress)
    Reject {Resume-RimePimeDp1UNativeTransaction $c.root $digest} '*source changed*';Assert-Payload $c 'present';Require (Values-Equal (Read-Hive $c) $c.old) 'Source drift changed hive.'
}
foreach($record in @('commit.bin','terminal.bin')){
foreach($bad in @('torn-frame','wrong-digest','duplicate-json-key','wrong-transaction','wrong-prepared-sha','wrong-role','array-schema','array-id','array-sha','array-sha-empty','array-disposition')){
Check ($record+'-'+$bad+'-is-fatal-and-not-overwritten') {
    $c=New-Case;Prepare $c;$path=Join-Path $c.root $record;$decision=Decision $c $(if($record -ceq 'commit.bin'){'commit'}else{'rolled-back'})
    switch($bad){
        'wrong-transaction'{$decision.transaction_id='0'*32};'wrong-prepared-sha'{$decision.prepared_sha256='0'*64}
        'wrong-role'{$decision.disposition=if($record -ceq 'commit.bin'){'rolled-back'}else{'commit'}}
        'array-schema'{$decision.schema_version=@($decision.schema_version)};'array-id'{$decision.transaction_id=@($decision.transaction_id)};'array-sha'{$decision.prepared_sha256=@($decision.prepared_sha256)};'array-sha-empty'{$decision.prepared_sha256=@()};'array-disposition'{$decision.disposition=@($decision.disposition)}
    }
    $json=$decision|ConvertTo-Json -Depth 8 -Compress
    if($bad -ceq 'duplicate-json-key'){$json=$json.Substring(0,$json.Length-1)+',"Disposition":"commit"}'}
    $null=Write-Frame $path $json
    if($bad -ceq 'torn-frame'){$bytes=[IO.File]::ReadAllBytes($path);[IO.File]::WriteAllBytes($path,[byte[]]$bytes[0..20])}
    if($bad -ceq 'wrong-digest'){$bytes=[IO.File]::ReadAllBytes($path);$bytes[12]=$bytes[12] -bxor 1;[IO.File]::WriteAllBytes($path,$bytes)}
    $before=File-Reference $path;Reject {Resume-Own $c};$after=File-Reference $path
    Require ($after.sha256 -ceq $before.sha256 -and $after.bytes -eq $before.bytes) 'Malformed final decision was overwritten.'
    Assert-Payload $c 'present';Require (Values-Equal (Read-Hive $c) $c.old) 'Malformed final decision caused a write.'
}
}
}
Check 'orphan-pending-decision-is-never-a-commit' {
    $c=New-Case;Prepare $c;$pending=Join-Path $c.root ('commit.bin.pending-'+[guid]::NewGuid().ToString('N'))
    $null=Write-Frame $pending ((Decision $c 'commit')|ConvertTo-Json -Compress);$hash=(File-Reference $pending).sha256
    Assert-Result (Resume-Own $c) 'rolled-back';Assert-Payload $c 'present';Require ((File-Reference $pending).sha256 -ceq $hash -and -not [IO.File]::Exists((Join-Path $c.root 'commit.bin'))) 'Orphan pending was adopted or erased.'
}
Check 'cooperative-lock-refuses-a-second-transaction-operation' {
    $c=New-Case;Prepare $c;$held=& $module {param($r)Open-Tx $r $false} $c.root
    try{Reject {Resume-Own $c};Reject {[IO.Directory]::Move($c.root,$c.root+'-moved')};Assert-Payload $c 'present'}finally{& $module {param($t)Close-Tx $t} $held}
    Assert-Result (Resume-Own $c) 'rolled-back'
}
Check 'delete-sharing-reader-pending-prevents-terminal-success-and-resume-completes' {
    $c=New-Case;Prepare $c;$reader=[IO.File]::Open((Join-Path $c.payload 'first.bin'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]7)
    try{
        Reject {Invoke-Own $c} '*removal pending*'
        Require ([IO.File]::Exists((Join-Path $c.root 'commit.bin')) -and -not [IO.File]::Exists((Join-Path $c.root 'terminal.bin'))) 'Pending deletion was marked terminal.'
        Require ($reader.ReadByte() -ge 0 -and [IO.File]::Exists((Join-Path $c.payload 'second.bin'))) 'Pending deletion continued past boundary.'
        Reject {Resume-Own $c} '*pending or inaccessible*'
    }finally{$reader.Dispose()}
    $r=Resume-Own $c;Assert-Result $r 'commit-complete';Assert-Payload $c 'absent'
    Require (-not $r.payload_observations[0].removed_this_invocation) 'Resume attributed prior pending removal to itself.'
}
Check 'terminal-commit-later-hive-change-is-rejected' {
    $c=New-Case;Prepare $c;Assert-Result (Invoke-Own $c) 'commit-complete';Write-Hive $c $c.old
    Reject {Resume-Own $c} '*Unapproved*';Require (Values-Equal (Read-Hive $c) $c.old) 'Terminal replay overwrote changed hive.';Assert-Payload $c 'absent'
}
Check 'terminal-rollback-later-payload-replacement-is-rejected' {
    $c=New-Case;Prepare $c;Assert-Result (Resume-Own $c) 'rolled-back';$p=Join-Path $c.payload 'first.bin';[IO.File]::Move($p,$p+'.original');[IO.File]::Copy($p+'.original',$p);$changed=Inspect-File $p
    Reject {Resume-Own $c} '*identity/bytes changed*';Require ((Inspect-File $p).file_id -ceq $changed.file_id) 'Terminal rollback erased replacement.'
}
Check 'public-path-escape-and-literal-array-sha-are-rejected' {
    $c=New-Case;Prepare $c
    foreach($path in @(($c.root+'\..\'+[IO.Path]::GetFileName($c.root)),($c.root+'\'),($c.root+':named'),($c.root -replace 'dp1-u-native-transaction','unapproved'),('\\?\'+$c.root))){Reject {Resume-RimePimeDp1UNativeTransaction $path $c.ticket.prepared_sha256}}
    Reject {Resume-RimePimeDp1UNativeTransaction @($c.root) $c.ticket.prepared_sha256};Reject {Resume-RimePimeDp1UNativeTransaction $c.root @($c.ticket.prepared_sha256)}
    Assert-Payload $c 'present';Require (Values-Equal (Read-Hive $c) $c.old) 'Path rejection changed hive.'
    $parameters=(Get-Command Invoke-RimePimeDp1UNativeTransaction).Parameters.Keys
    foreach($forbidden in @('RootKey','Provider','Checkpoint','Callback','SourceHash')){Require ($parameters -notcontains $forbidden) 'A production provider/fault override was exposed.'}
}
Check 'source-bytes-remain-fixed-across-the-regression' {
    Require (($initialSources|ConvertTo-Json -Compress) -ceq ((Source-Records)|ConvertTo-Json -Compress)) 'Source changed while fixtures ran; rerun against frozen sources.'
}
}finally{Remove-Module $module;Remove-Module $hiveModule;Remove-Module $removalModule}
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-native-transaction-tests-v1';passed=(@($checks|Where-Object{-not $_.passed}).Count -eq 0);check_count=$checks.Count
    shell_version=$PSVersionTable.PSVersion.ToString();process_is_64_bit=[Environment]::Is64BitProcess;checks=@($checks.ToArray());source_files=$initialSources
    fixture_roots=@($fixtures.ToArray());children=@($children.ToArray());child_script=(File-Reference $childPath)
    native_private_hive_and_exact_removal_exercised=(@($checks|Where-Object{$_.name -ceq 'native-commit-removes-only-approved-files-and-repeated-resume-revalidates' -and $_.passed}).Count -eq 1)
    owned_process_exit_73_exercised=(@($children|Where-Object{$_.actual_exit_code -eq 73 -and $_.expected_exit_code -eq 73 -and -not $_.forced_cleanup}).Count -gt 0)
    fresh_process_resume_exercised=(@($children|Where-Object{$_.mode -ceq 'Resume' -and $_.actual_exit_code -eq 0 -and -not $_.forced_cleanup}).Count -gt 0)
    installer_executed=$false;uninstaller_executed=$false;runtime_started=$false;production_registration_modified=$false;production_user_data_accessed=$false;installed_yimecore_local12_touched=$false
    hardware_power_loss_verified=$false;hostile_same_sid_prevention_verified=$false;directory_metadata_durability_verified=$false;full_native_product_transaction_complete=$false;dp1_u_acceptance_passed=$false
    limitations=@('Own repository fixture paths and fixed six native registry values only.','Environment.Exit(73) demonstrates process interruption, not hardware power loss.','Prepared SHA is externally supplied binding; no hostile same-SID or in-memory caller authentication is claimed.','Fixtures, orphan records and child logs are retained; no recursive cleanup or production provider runs.')
}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),($result|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw 'Native transaction regressions failed; see retained result.json.'}
$global:LASTEXITCODE=0
Write-Host ("Native transaction: {0}/{0} passed." -f $checks.Count)
