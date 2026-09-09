[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$parent=Join-Path $repo '.tmp\dual-product';$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if([IO.Path]::GetDirectoryName($output) -cne $parent -or [IO.Path]::GetFileName($output) -cnotmatch '^dp1-u-app-hive-test-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $output)){throw 'Use a fresh repository .tmp/dual-product/dp1-u-app-hive-test-* root.'}
for($cursor=$parent;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test ancestor is indirect.'}
}
[void][IO.Directory]::CreateDirectory($output)
$modulePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-application-hive.psm1'
$module=Import-Module $modulePath -PassThru
$checks=[Collections.Generic.List[object]]::new();$fixtures=[Collections.Generic.List[string]]::new()
$names=@('machine-com-server-x86','machine-com-server-native','machine-profile-icon-index','machine-product-root','target-profile-enabled','target-profile-metadata')
$shell=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Core'){'pwsh.exe'}else{'powershell.exe'})
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true});Write-Host "PASS: $Name"}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message});Write-Host "FAIL: $Name - $($_.Exception.Message)"}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern='*'){$caught=$null;try{& $Body|Out-Null}catch{$caught=$_};if($null -eq $caught){throw 'Expected rejection.'};if($caught.Exception.Message -notlike $Pattern){throw "Unexpected rejection: $($caught.Exception.Message)"}}
function New-Case {
    $root=Join-Path $parent ('dp1-u-app-hive-own-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root);$fixtures.Add($root)
    return [pscustomobject]@{root=$root;path=(Join-Path $root 'private.hiv')}
}
function New-Values {
    return @(
        [pscustomobject]@{value_id=$names[0];kind='String';raw_bytes=[Text.Encoding]::Unicode.GetBytes("fixture-x86`0")},
        [pscustomobject]@{value_id=$names[1];kind='String';raw_bytes=[Text.Encoding]::Unicode.GetBytes("fixture-native`0")},
        [pscustomobject]@{value_id=$names[2];kind='DWord';raw_bytes=[byte[]]@(255,255,255,255)},
        [pscustomobject]@{value_id=$names[3];kind='ExpandString';raw_bytes=[Text.Encoding]::Unicode.GetBytes("%PATH%\fixture`0")},
        [pscustomobject]@{value_id=$names[4];kind='DWord';raw_bytes=[byte[]]@(1,0,0,0)},
        [pscustomobject]@{value_id=$names[5];kind='MultiString';raw_bytes=[Text.Encoding]::Unicode.GetBytes("one`0`0three`0`0")}
    )
}
function Hash-Bytes([byte[]]$Bytes){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Same-Snapshot($Left,$Right){return (($Left.values|ConvertTo-Json -Depth 5 -Compress) -ceq ($Right.values|ConvertTo-Json -Depth 5 -Compress))}
function Release($Context){if($null -ne $Context){Close-RimePimeDp1UApplicationHive $Context|Out-Null}}
function Native-Value($Context,[string]$Name,[uint32]$Type,[byte[]]$Data){
    & $module {param($c,$name,$type,$data)
        $b=Get-AppHiveBundle $c
        $h=$b.native.GetType().GetField('hive',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($b.native)
        $method=$script:HiveNativeType.GetMethod('RegSetValueExW',[Reflection.BindingFlags]'Static,NonPublic')
        $rc=$method.Invoke($null,[object[]]@($h,$name,[uint32]0,[uint32]$type,$data,[uint32]$data.Length))
        if($rc -ne 0){throw "Fixture native write failed: $rc"}
    } $Context $Name $Type $Data
}
function Native-Read($Context,[string]$Name){
    return & $module {param($c,$name)
        $b=Get-AppHiveBundle $c;$h=$b.native.GetType().GetField('hive',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($b.native)
        $method=$script:HiveNativeType.GetMethod('RegQueryValueExW',[Reflection.BindingFlags]'Static,NonPublic')
        $args=[object[]]@($h,$name,[IntPtr]::Zero,[uint32]0,[byte[]]::new(65536),[uint32]65536)
        $rc=$method.Invoke($null,$args);if($rc -ne 0){throw "Fixture native read failed: $rc"}
        $raw=[byte[]]::new([int]$args[5]);[Array]::Copy($args[4],$raw,$raw.Length)
        [pscustomobject]@{type=$args[3];raw=$raw}
    } $Context $Name
}
function Child([string]$Name,[string]$Code,[string[]]$Arguments=@()){
    $scriptPath=Join-Path $output ($Name+'.ps1');[IO.File]::WriteAllText($scriptPath,$Code,[Text.UTF8Encoding]::new($false))
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'))+$Arguments
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$shell;$p.StartInfo.Arguments=($args -join ' ')
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $started=$false;$stdout=$null;$stderr=$null;$timedOut=$false
    try{
        $started=$p.Start();if(-not $started){throw 'Own fixture child did not start.'}
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(20000)){$timedOut=$true;$p.Kill();$p.WaitForExit()}
        [IO.File]::WriteAllText((Join-Path $output ($Name+'.stdout.log')),$stdout.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $output ($Name+'.stderr.log')),$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        if($timedOut){throw 'Own fixture child timed out.'}
        Require ($p.ExitCode -eq 0) "Own fixture child failed: $Name (see retained stdout/stderr)."
    }finally{
        if($started -and -not $p.HasExited){$p.Kill();$p.WaitForExit()}
        if($null -ne $stdout){$null=$stdout.GetAwaiter().GetResult()};if($null -ne $stderr){$null=$stderr.GetAwaiter().GetResult()};$p.Dispose()
    }
}
try {
Check 'missing-file-creates-private-empty-hive-and-unloads' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{$snapshot=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require ($snapshot.values.Count -eq 6 -and @($snapshot.values|Where-Object{$_.kind -cne 'Absent'}).Count -eq 0) 'New hive was not empty.'}
    finally{$identity=Close-RimePimeDp1UApplicationHive $ctx}
    Require ($identity.bytes -gt 0 -and $identity.sha256 -cmatch '^[0-9a-f]{64}$' -and [IO.File]::Exists($c.path)) 'No closed hive artifact.'
    $writer=[IO.File]::Open($c.path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$writer.Dispose()
}
Check 'four-types-roundtrip-exact-bytes-without-expansion-or-normalization' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{
        $before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;$values=New-Values
        $result=Set-RimePimeDp1UApplicationHiveValues $ctx $before $values;Require $result.passed 'Apply failed.'
        $after=Get-RimePimeDp1UApplicationHiveSnapshot $ctx
        for($i=0;$i -lt 6;$i++){Require ($after.values[$i].kind -ceq $values[$i].kind -and $after.values[$i].bytes -eq $values[$i].raw_bytes.Length -and $after.values[$i].sha256 -ceq (Hash-Bytes $values[$i].raw_bytes)) "Typed bytes differ: $i"}
        $json=$after|ConvertTo-Json -Depth 6;Require ($json -notmatch 'fixture-x86|fixture-native|%PATH%|raw_bytes') 'Snapshot exported value content.'
        foreach($claim in @('production_registry_accessed','native_com_profile_registration_verified','target_user_sid_verified','independent_system_registry_visibility_verified','atomic_multi_value_transaction_verified','hostile_same_sid_creation_prevention_verified','continuous_membership_protection','physical_crash_durability_verified','in_memory_caller_authenticated','installer_executed','installed_yimecore_local12_touched','production_user_data_accessed','full_transaction_acceptance_passed','dp1_u_acceptance_passed')){Require ($result.$claim -is [bool] -and -not $result.$claim) "Unsupported claim: $claim"}
        Require (-not $after.atomic_snapshot_verified -and -not $after.quiescence_verified) 'Snapshot certainty overstated.'
    }finally{Release $ctx}
}
Check 'rollback-restores-absent-values-and-preserves-foreign-value' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{
        Native-Value $ctx 'foreign-value' 3 ([byte[]]@(1,3,5,7));$before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx
        Require (Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)).passed 'Apply failed.'
        $after=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require (Restore-RimePimeDp1UApplicationHive $ctx $before $after).passed 'Rollback failed.'
        Require (Same-Snapshot $before (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Absent values not restored.'
        $foreign=Native-Read $ctx 'foreign-value';Require ($foreign.type -eq 3 -and [BitConverter]::ToString($foreign.raw) -ceq '01-03-05-07') 'Foreign value changed.'
    }finally{Release $ctx}
}
Check 'rollback-restores-original-types-order-empty-elements-and-raw-terminators' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{
        $empty=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;$original=New-Values;Require (Set-RimePimeDp1UApplicationHiveValues $ctx $empty $original).passed 'Setup failed.'
        $before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;$changed=New-Values
        $changed[0].raw_bytes=[byte[]]::new(0);$changed[5].raw_bytes=[byte[]]::new(0);$changed[3].kind='Absent';$changed[3].raw_bytes=[byte[]]::new(0)
        Require (Set-RimePimeDp1UApplicationHiveValues $ctx $before $changed).passed 'Second apply failed.'
        $after=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require ($after.values[0].kind -ceq 'String' -and $after.values[0].bytes -eq 0 -and $after.values[3].kind -ceq 'Absent' -and $after.values[5].bytes -eq 0) 'Empty/absent distinctions lost.'
        Require (Restore-RimePimeDp1UApplicationHive $ctx $before $after).passed 'Rollback failed.'
        Require (Same-Snapshot $before (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Original typed bytes not restored.'
    }finally{Release $ctx}
}
Check 'expected-before-conflict-rejects-without-new-write' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{$before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Native-Value $ctx $names[0] 1 ([Text.Encoding]::Unicode.GetBytes('external'));$changed=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Reject {Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)} '*conflict*';Require (Same-Snapshot $changed (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Conflict overwrote values.'}finally{Release $ctx}
}
Check 'mid-apply-native-step-error-is-recorded-and-original-snapshot-rolls-back' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    $old=& $module {(Get-Item Function:Write-AppHiveValue).ScriptBlock}
    try{
        $before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx
        & $module {Set-Item Function:script:Write-AppHiveValue {param($Native,$Wanted,[int]$Index)if($Index -eq 2){throw 'Owned fixture native step failure.'};$Native.WriteIndex($Wanted,$Index)}}
        $result=Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)
        Require (-not $result.passed -and $result.partial_change_possible -and $result.completed_value_writes -eq 2 -and $result.error -like '*fixture native step failure*') 'Partial failure was hidden.'
        & $module {param($body)Set-Item Function:script:Write-AppHiveValue $body} $old
        $partial=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require (-not(Same-Snapshot $before $partial)) 'Fault did not follow real native writes.'
        Require (Restore-RimePimeDp1UApplicationHive $ctx $before $partial).passed 'Partial rollback failed.'
        Require (Same-Snapshot $before (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Partial rollback changed original state.'
    }finally{& $module {param($body)Set-Item Function:script:Write-AppHiveValue $body} $old;Release $ctx}
}
Check 'rollback-conflict-does-not-overwrite-newer-values' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{$before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require (Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)).passed 'Apply failed.';$after=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Native-Value $ctx $names[0] 1 ([Text.Encoding]::Unicode.GetBytes('newer'));$newer=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Reject {Restore-RimePimeDp1UApplicationHive $ctx $before $after} '*conflict*';Require (Same-Snapshot $newer (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Conflict rollback overwrote newer data.'}finally{Release $ctx}
}
Check 'same-bytes-different-native-kind-conflicts' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{Native-Value $ctx $names[0] 1 ([byte[]]@(1,0,0,0));$before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Native-Value $ctx $names[0] 2 ([byte[]]@(1,0,0,0));$after=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require ($before.values[0].sha256 -ceq $after.values[0].sha256 -and -not(Same-Snapshot $before $after)) 'Kind not part of snapshot.';Reject {Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)} '*conflict*';Require (Restore-RimePimeDp1UApplicationHive $ctx $before $after).passed 'Raw observed kind restore failed.'}finally{Release $ctx}
}
$invalidCases=@('missing-row','extra-row','duplicate','wrong-case','unknown-name','wrong-kind','kind-array','name-array','raw-untyped','raw-null','odd-string','short-dword','absent-nonempty','oversize','extra-field','case-field','unterminated-string','unterminated-expand-string','unterminated-multi-string')
foreach($bad in $invalidCases){
Check ('full-preflight-rejects-'+$bad+'-without-partial-write') {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{
        $before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;$rows=New-Values
        switch($bad){
            'missing-row'{$rows=@($rows[0..4])};'extra-row'{$rows=@($rows)+@($rows[0])};'duplicate'{$rows[5].value_id=$rows[0].value_id};'wrong-case'{$rows[5].value_id=$rows[5].value_id.ToUpperInvariant()};'unknown-name'{$rows[5].value_id='foreign-value'}
            'wrong-kind'{$rows[5].kind='String'};'kind-array'{$rows[5].kind=@('MultiString')};'name-array'{$rows[5].value_id=@($rows[5].value_id)};'raw-untyped'{$rows[5].raw_bytes=@(0,0)};'raw-null'{$rows[5].raw_bytes=$null}
            'odd-string'{$rows[1].raw_bytes=[byte[]]@(1)};'short-dword'{$rows[4].raw_bytes=[byte[]]@(1,0)};'absent-nonempty'{$rows[5].kind='Absent'};'oversize'{$rows[5].raw_bytes=[byte[]]::new(65538)}
            'extra-field'{$rows[5]|Add-Member extra $true};'case-field'{$rows[5]=[pscustomobject]@{Value_id=$names[5];kind='MultiString';raw_bytes=[byte[]]@(0,0)}}
            'unterminated-string'{$rows[0].raw_bytes=[byte[]]@(1,0)};'unterminated-expand-string'{$rows[3].raw_bytes=[byte[]]@(1,0)};'unterminated-multi-string'{$rows[5].raw_bytes=[byte[]]@(1,0,0,0)}
        }
        Reject {Set-RimePimeDp1UApplicationHiveValues $ctx $before $rows}
        Require (Same-Snapshot $before (Get-RimePimeDp1UApplicationHiveSnapshot $ctx)) 'Validation produced partial mutation.'
    }finally{Release $ctx}
}}
Check 'opaque-context-snapshot-copy-json-and-cross-context-are-rejected' {
    $a=New-Case;$b=New-Case;$ca=Open-RimePimeDp1UApplicationHive $a.path;$cb=Open-RimePimeDp1UApplicationHive $b.path
    try{
        $sa=Get-RimePimeDp1UApplicationHiveSnapshot $ca;$sb=Get-RimePimeDp1UApplicationHiveSnapshot $cb
        Reject {Get-RimePimeDp1UApplicationHiveSnapshot ($ca|ConvertTo-Json|ConvertFrom-Json)} '*Original*'
        Reject {Set-RimePimeDp1UApplicationHiveValues $ca ($sa|ConvertTo-Json -Depth 6|ConvertFrom-Json) (New-Values)} '*Original*'
        Reject {Restore-RimePimeDp1UApplicationHive $ca $sb $sa} '*Original*'
        $sa.id='tampered';$sa.values=@();$ca.id='tampered';$ca.hive_path='C:\untrusted'
        Require (Set-RimePimeDp1UApplicationHiveValues $ca $sa (New-Values)).passed 'Public metadata mutated private state.'
    }finally{Release $ca;Release $cb}
    Reject {Get-RimePimeDp1UApplicationHiveSnapshot $ca} '*closed*';Reject {Close-RimePimeDp1UApplicationHive $ca} '*closed*'
}
Check 'new-open-rejects-existing-valid-file-and-zero-byte-placeholder' {
    $a=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $a.path;Release $ctx;$hash=(Get-FileHash $a.path).Hash
    Reject {Open-RimePimeDp1UApplicationHive $a.path} '*exists*';Require ((Get-FileHash $a.path).Hash -ceq $hash) 'Existing hive changed.'
    $b=New-Case;[IO.File]::WriteAllBytes($b.path,[byte[]]::new(0));Reject {Open-RimePimeDp1UApplicationHive $b.path} '*exists*';Require ((Get-Item $b.path).Length -eq 0) 'Placeholder changed.'
}
Check 'directory-lease-rejects-rename-and-close-releases-it' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{Reject {[IO.Directory]::Move($c.root,$c.root+'-moved')}}finally{Release $ctx}
    [IO.Directory]::Move($c.root,$c.root+'-moved');[IO.Directory]::Move($c.root+'-moved',$c.root)
}
Check 'reopen-requires-exact-identity-size-hash-and-literal-fields' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path;$identity=Close-RimePimeDp1UApplicationHive $ctx
    foreach($field in @('file_id','bytes','sha256')){
        $bad=[pscustomobject]@{file_id=$identity.file_id;bytes=$identity.bytes;sha256=$identity.sha256}
        switch($field){'file_id'{$bad.file_id='00000000:0000000000000000'};'bytes'{$bad.bytes++};'sha256'{$bad.sha256='0'*64}}
        Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $bad} '*mismatch*'
    }
    $bad=[pscustomobject]@{file_id=$identity.file_id;bytes=[string]$identity.bytes;sha256=$identity.sha256};Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $bad} '*literal*'
    $bad=[pscustomobject]@{file_id=$identity.file_id;bytes=$identity.bytes;sha256=@($identity.sha256)};Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $bad} '*literal*'
    Release (Open-RimePimeDp1UExistingApplicationHive $c.path $identity)
}
Check 'same-byte-replacement-file-id-is-rejected-before-load' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path;$identity=Close-RimePimeDp1UApplicationHive $ctx
    [IO.File]::Move($c.path,$c.path+'.original');[IO.File]::Copy($c.path+'.original',$c.path)
    Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $identity} '*mismatch*'
}
Check 'reopen-invalid-hive-bytes-fails-and-releases-ancestors' {
    $c=New-Case;[IO.File]::WriteAllText($c.path,'not a registry hive')
    $identity=& $module {param($p)$s=Open-AppHiveSource;try{$o=$script:HiveNativeType::Inspect($p);[pscustomobject]@{file_id=$o.FileId;bytes=$o.Bytes;sha256=$o.Sha256}}finally{$s.Dispose()}} $c.path
    Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $identity} '*RegLoadAppKeyW*'
    [IO.Directory]::Move($c.root,$c.root+'-moved');[IO.Directory]::Move($c.root+'-moved',$c.root)
}
foreach($bad in @('readonly','hardlink','ads','directory')){
Check ('reopen-rejects-'+$bad) {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path;$identity=Close-RimePimeDp1UApplicationHive $ctx
    try{
        switch($bad){'readonly'{[IO.File]::SetAttributes($c.path,[IO.FileAttributes]::ReadOnly)};'hardlink'{New-Item -ItemType HardLink -Path ($c.path+'.link') -Target $c.path|Out-Null};'ads'{Set-Content -LiteralPath $c.path -Stream 'foreign' -Value 'fixture'};'directory'{[IO.File]::Move($c.path,$c.path+'.original');[void][IO.Directory]::CreateDirectory($c.path)}}
        Reject {Open-RimePimeDp1UExistingApplicationHive $c.path $identity}
    }finally{if($bad -eq 'readonly'){[IO.File]::SetAttributes($c.path,[IO.FileAttributes]::Normal)}}
}}
Check 'reparse-parent-and-directory-stream-are-rejected' {
    $c=New-Case;$other=New-Case;[IO.Directory]::Move($c.root,$c.root+'-plain')
    New-Item -ItemType Junction -Path $c.root -Target $other.root|Out-Null
    Reject {Open-RimePimeDp1UApplicationHive $c.path} '*Indirect*'
    Require (-not[IO.File]::Exists($other.path)) 'Indirect destination was written.'
    $d=New-Case;Set-Content -LiteralPath $d.root -Stream 'foreign' -Value 'fixture';Reject {Open-RimePimeDp1UApplicationHive $d.path} '*stream*'
}
Check 'public-path-scope-canonical-aliases-and-no-provider-overrides' {
    $c=New-Case
    foreach($path in @((Join-Path $c.root 'other.hiv'),($c.path+':stream'),($c.path -replace 'private.hiv','..\private.hiv'),($c.path -replace 'private.hiv','private.hiv.'),($c.path -replace 'dp1-u-app-hive-own','unapproved-own'),('\\?\'+$c.path))){Reject {Open-RimePimeDp1UApplicationHive $path}}
    Reject {Open-RimePimeDp1UApplicationHive @($c.path)} '*literal*'
    $params=(Get-Command Open-RimePimeDp1UApplicationHive).Parameters.Keys
    Require ($params -notcontains 'Provider' -and $params -notcontains 'RootKey' -and $params -notcontains 'Callback' -and $params -notcontains 'SourceHash') 'Production override exposed.'
}
Check 'loaded-hive-cannot-be-loaded-by-another-process' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    try{
        Child 'exclusive' @'
param([string]$HivePath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;public static class OwnHiveProbe{[DllImport("advapi32.dll",CharSet=CharSet.Unicode)]public static extern int RegLoadAppKeyW(string p,out SafeRegistryHandle k,uint a,uint o,uint r);}'
$h=$null;$rc=[OwnHiveProbe]::RegLoadAppKeyW($HivePath,[ref]$h,0x2001f,1,0)
try{if($rc -eq 0){throw 'REG_PROCESS_APPKEY unexpectedly admitted another process.'};if($rc -ne 5 -and $rc -ne 32){throw "Unexpected native refusal: $rc"};[pscustomobject]@{native_error=$rc;second_process_load_refused=$true}|ConvertTo-Json}finally{if($null -ne $h){$h.Dispose()}}
'@ @(('"'+$c.path+'"'))
    }finally{Release $ctx}
}
Check 'closed-hive-reopens-in-fresh-process-with-original-typed-bytes' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    $before=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;Require (Set-RimePimeDp1UApplicationHiveValues $ctx $before (New-Values)).passed 'Setup failed.'
    $snapshot=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;$identity=Close-RimePimeDp1UApplicationHive $ctx
    $binding=Join-Path $output 'reopen-binding.json';[IO.File]::WriteAllText($binding,([pscustomobject]@{path=$c.path;expected=$identity;values=$snapshot.values}|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
    Child 'reopen' @'
param([string]$ModulePath,[string]$BindingPath)
$ErrorActionPreference='Stop';$m=Import-Module $ModulePath -PassThru;$b=Get-Content -LiteralPath $BindingPath -Raw|ConvertFrom-Json
$ctx=Open-RimePimeDp1UExistingApplicationHive $b.path $b.expected
try{$s=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;if(($s.values|ConvertTo-Json -Compress) -cne ($b.values|ConvertTo-Json -Compress)){throw 'Fresh process typed snapshot mismatch.'};[pscustomobject]@{fresh_process_reopen_passed=$true;value_count=$s.values.Count;production_registry_accessed=$false}|ConvertTo-Json}finally{Close-RimePimeDp1UApplicationHive $ctx|Out-Null;Remove-Module $m}
'@ @(('"'+$modulePath+'"'),('"'+$binding+'"'))
}
Check 'private-source-type-does-not-adopt-preloaded-global-fake' {
    $c=New-Case
    Child 'spoof' @'
param([string]$ModulePath,[string]$HivePath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'namespace Yime.Dp1UApplicationHive{public class HiveContext{public static object Open(string p){throw new System.Exception("fake adopted");}}public class Native{public static void Canonical(string p){throw new System.Exception("fake adopted");}}}'
$m=Import-Module $ModulePath -PassThru;$ctx=Open-RimePimeDp1UApplicationHive $HivePath
try{$s=Get-RimePimeDp1UApplicationHiveSnapshot $ctx;if($s.values.Count -ne 6){throw 'Native snapshot missing.'};$private=& $m {$script:HiveType.FullName};if($private -notlike 'Yime.Dp1UApplicationHive_*.HiveContext'){throw 'Nonprivate type.'};[pscustomobject]@{private_type_used=$true}|ConvertTo-Json}finally{Close-RimePimeDp1UApplicationHive $ctx|Out-Null;Remove-Module $m}
'@ @(('"'+$modulePath+'"'),('"'+$c.path+'"'))
}
Check 'source-read-lease-and-module-removal-release-all-contexts' {
    $c=New-Case;$ctx=Open-RimePimeDp1UApplicationHive $c.path
    Reject {[IO.File]::Open((Join-Path $PSScriptRoot 'rime-pime-dp1u-application-hive.cs'),[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)}
    Remove-Module $module;$module=$null
    $stream=[IO.File]::Open($c.path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$stream.Dispose()
    [IO.Directory]::Move($c.root,$c.root+'-moved');[IO.Directory]::Move($c.root+'-moved',$c.root)
}
} finally {if($null -ne $module){Remove-Module $module}}
$sources=@('rime-pime-dp1u-application-hive.cs','rime-pime-dp1u-application-hive.psm1','test-rime-pime-dp1u-application-hive.ps1'|ForEach-Object{$p=Join-Path $PSScriptRoot $_;[ordered]@{path=$p;sha256=(Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item $p).Length}})
$result=[ordered]@{schema_version='yime-rime-pime-dp1u-app-hive-tests-v1';passed=(@($checks|Where-Object{-not $_.passed}).Count -eq 0);check_count=$checks.Count;shell_version=$PSVersionTable.PSVersion.ToString();process_is_64_bit=[Environment]::Is64BitProcess;checks=@($checks.ToArray());source_files=$sources;fixture_roots=@($fixtures.ToArray());native_application_hive_exercised=$true;real_hkcu_hklm_accessed=$false;product_registration_modified=$false;installer_executed=$false;installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;hostile_same_sid_creation_prevention_verified=$false;physical_crash_durability_verified=$false;dp1_u_acceptance_passed=$false}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),($result|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw 'Application hive regressions failed; see retained result.json.'}
$global:LASTEXITCODE=0
Write-Host ("Application hive: {0}/{0} passed." -f $checks.Count)
