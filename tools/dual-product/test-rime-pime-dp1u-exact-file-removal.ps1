[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$parent=Join-Path $repo '.tmp\dual-product'
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if([IO.Path]::GetDirectoryName($output) -cne $parent -or [IO.Path]::GetFileName($output) -cnotmatch '^dp1-u-exact-removal-test-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $output)){throw 'Use a fresh repository .tmp/dual-product/dp1-u-exact-removal-test-* root.'}
for($cursor=$parent;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test root ancestor is indirect.'}
}
[void][IO.Directory]::CreateDirectory($output)
$modulePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.psm1'
$module=Import-Module $modulePath -PassThru
$checks=[Collections.Generic.List[object]]::new()
$fixtures=[Collections.Generic.List[string]]::new()
$interference=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true});Write-Host "PASS: $Name"}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message});Write-Host "FAIL: $Name - $($_.Exception.Message)"}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern='*'){
    $caught=$null;try{& $Body|Out-Null}catch{$caught=$_}
    if($null -eq $caught){throw 'Expected rejection.'}
    if($caught.Exception.Message -notlike $Pattern){throw "Unexpected rejection: $($caught.Exception.Message)"}
}
function New-Case {
    $root=Join-Path $parent ('dp1-u-exact-removal-own-'+[guid]::NewGuid().ToString('N'))
    $payload=Join-Path $root 'payload';[void][IO.Directory]::CreateDirectory($payload)
    $fixtures.Add($root)
    [pscustomobject]@{root=$root;payload=$payload}
}
function Write-File($Case,[string]$Relative,[string]$Text='fixture'){
    $path=Join-Path $Case.payload $Relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
    return $path
}
function Expected($Case,[string]$Relative){
    $record=& $module {param($p)
        $source=Open-ExactRemovalSource
        try{$script:RemovalNativeType::Inspect($p)}finally{$source.Dispose()}
    } (Join-Path $Case.payload $Relative)
    return [pscustomobject][ordered]@{path=$Relative;bytes=[long]$record.Bytes;sha256=$record.Sha256;file_id=$record.FileId}
}
function Release($Context){if($null -ne $Context){Close-RimePimeDp1UExactFileRemoval $Context}}
try {
Check 'approved-file-deleted-foreign-and-directories-preserved' {
    $c=New-Case;$a=Write-File $c 'sub\approved.bin';$foreign=Write-File $c 'sub\foreign.bin' 'foreign'
    [void][IO.Directory]::CreateDirectory((Join-Path $c.payload 'empty'))
    $ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'sub\approved.bin')
    $result=Invoke-RimePimeDp1UExactFileRemoval $ctx
    Require ($result.all_approved_files_removed -and $result.files[0].status -ceq 'removed') 'Native removal not confirmed.'
    Require (-not[IO.File]::Exists($a) -and [IO.File]::ReadAllText($foreign) -ceq 'foreign') 'Foreign leaf changed.'
    Require ([IO.Directory]::Exists((Join-Path $c.payload 'sub')) -and [IO.Directory]::Exists((Join-Path $c.payload 'empty'))) 'Directory was removed.'
    foreach($name in @('directory_or_root_removal_performed','path_delete_fallback_used','reboot_deletion_queued','continuous_membership_protection','hostile_same_sid_prevention_verified','independent_system_visibility_verified','in_memory_caller_authenticated','installer_executed','uninstaller_executed','product_registration_modified','installed_yimecore_local12_touched','production_user_data_accessed','full_removal_acceptance_passed','dp1_u_acceptance_passed')){
        Require ($result.$name -is [bool] -and -not $result.$name) "Unsupported claim: $name"
    }
    Reject {Invoke-RimePimeDp1UExactFileRemoval $ctx} '*closed*'
}
Check 'zero-length-file-is-supported' {
    $c=New-Case;$path=Write-File $c 'empty.bin' ''
    $ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'empty.bin')
    Require (Invoke-RimePimeDp1UExactFileRemoval $ctx).all_approved_files_removed 'Zero-byte leaf failed.'
}
Check 'late-invalid-member-releases-all-without-partial-removal' {
    $c=New-Case;$a=Write-File $c 'a.bin';$b=Write-File $c 'b.bin'
    $rows=@((Expected $c 'a.bin'),(Expected $c 'b.bin'));$rows[1].sha256='0'*64
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload $rows} '*mismatch*'
    [IO.File]::WriteAllText($a,'released');[IO.File]::WriteAllText($b,'released')
    Require ([IO.File]::Exists($a) -and [IO.File]::Exists($b)) 'Preflight partially removed files.'
    $moved=$c.payload+'-moved';[IO.Directory]::Move($c.payload,$moved);[IO.Directory]::Move($moved,$c.payload)
}
Check 'same-content-preopen-replacement-file-id-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    [IO.File]::Move($path,(Join-Path $c.payload 'original.bin'));$null=Write-File $c 'a.bin'
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*mismatch*'
    Require ([IO.File]::ReadAllText($path) -ceq 'fixture') 'Replacement changed.'
}
Check 'leased-leaf-write-rename-and-parent-move-rejected' {
    $c=New-Case;$path=Write-File $c 'sub\a.bin';$ctx=$null
    try{
        $ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'sub\a.bin')
        Reject {[IO.File]::WriteAllText($path,'changed')}
        Reject {[IO.File]::Move($path,$path+'.moved')}
        Reject {[IO.Directory]::Move((Join-Path $c.payload 'sub'),(Join-Path $c.payload 'other'))}
        Reject {[IO.Directory]::Move($c.payload,$c.payload+'-moved')}
        Reject {[IO.Directory]::Move($c.root,$c.root+'-moved')}
    }finally{Release $ctx}
    [IO.File]::WriteAllText($path,'released');Require ([IO.File]::ReadAllText($path) -ceq 'released') 'Close retained a lock.'
}
Check 'preexisting-writer-is-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    $writer=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]7)
    try{Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)}}finally{$writer.Dispose()}
    Require ([IO.File]::Exists($path)) 'Writer conflict removed file.'
}
Check 'preexisting-reader-without-delete-sharing-is-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    $reader=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)}}finally{$reader.Dispose()}
}
Check 'delete-sharing-reader-keeps-pending-and-stops-later-removal' {
    $c=New-Case;$path=Write-File $c 'a.bin';$later=Write-File $c 'b.bin';$rows=@((Expected $c 'a.bin'),(Expected $c 'b.bin'))
    $reader=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]7)
    try{
        $ctx=Open-RimePimeDp1UExactFileRemoval $c.payload $rows
        $result=Invoke-RimePimeDp1UExactFileRemoval $ctx
        Require (-not$result.all_approved_files_removed -and $result.files[0].marked_for_deletion -and -not$result.files[0].removed) 'Pending reader was claimed removed.'
        Require ($result.files[0].status -ceq 'pending-or-inaccessible' -and $result.files[1].status -ceq 'not-attempted') 'Pending result or stop boundary wrong.'
        Require ([IO.File]::Exists($later) -and $reader.ReadByte() -ge 0) 'Pending reader or later member was changed.'
    }finally{$reader.Dispose()}
    Require (-not[IO.File]::Exists($path)) 'Approved pending object not deleted after final reader close.'
}
Check 'hardlinked-leaf-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    $null=New-Item -ItemType HardLink -Path (Join-Path $c.payload 'other.bin') -Target $path
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*Hardlinked*'
}
Check 'named-file-stream-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    Set-Content -LiteralPath $path -Stream extra -Value 'foreign' -Encoding ASCII
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*stream*'
    Require ((Get-Content -LiteralPath $path -Stream extra -Raw).Trim() -ceq 'foreign') 'Named stream changed.'
}
Check 'named-directory-stream-rejected' {
    $c=New-Case;$path=Write-File $c 'sub\a.bin';$row=Expected $c 'sub\a.bin'
    Set-Content -LiteralPath (Join-Path $c.payload 'sub') -Stream extra -Value 'foreign' -Encoding ASCII
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*stream*'
}
Check 'readonly-leaf-rejected-before-deleting-other-members' {
    $c=New-Case;$a=Write-File $c 'a.bin';$b=Write-File $c 'b.bin';$rows=@((Expected $c 'a.bin'),(Expected $c 'b.bin'))
    [IO.File]::SetAttributes($b,[IO.FileAttributes]::ReadOnly)
    try{Reject {Open-RimePimeDp1UExactFileRemoval $c.payload $rows} '*read-only*';Require ([IO.File]::Exists($a)) 'Earlier leaf removed.'}
    finally{[IO.File]::SetAttributes($b,[IO.FileAttributes]::Normal)}
}
Check 'junction-parent-rejected' {
    $c=New-Case;$path=Write-File $c 'original\a.bin';$row=Expected $c 'original\a.bin';$row.path='alias\a.bin'
    $null=New-Item -ItemType Junction -Path (Join-Path $c.payload 'alias') -Target (Join-Path $c.payload 'original')
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*Indirect*'
}
Check 'payload-root-junction-rejected' {
    $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    [IO.Directory]::Move($c.payload,(Join-Path $c.root 'original'))
    $null=New-Item -ItemType Junction -Path $c.payload -Target (Join-Path $c.root 'original')
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)} '*Indirect*'
}
Check 'serialized-or-copied-context-rejected-and-original-remains-closable' {
    $c=New-Case;$path=Write-File $c 'a.bin';$ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'a.bin')
    try{
        $copy=$ctx|ConvertTo-Json|ConvertFrom-Json
        Reject {Invoke-RimePimeDp1UExactFileRemoval $copy} '*Original*'
        Reject {Close-RimePimeDp1UExactFileRemoval $copy} '*Original*'
    }finally{Release $ctx}
    Reject {Invoke-RimePimeDp1UExactFileRemoval $ctx} '*closed*'
    [IO.File]::WriteAllText($path,'still-owned')
}
Check 'modified-public-id-and-metadata-cannot-orphan-native-leases' {
    $c=New-Case;$path=Write-File $c 'a.bin';$ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'a.bin')
    $ctx.id='caller-overwrite';$ctx.payload_root='C:\must-not-touch';$ctx.approved_file_count=999
    Close-RimePimeDp1UExactFileRemoval $ctx
    [IO.File]::WriteAllText($path,'released')
    Require ([IO.File]::ReadAllText($path) -ceq 'released') 'Mutable metadata orphaned retained handle.'
    Reject {Invoke-RimePimeDp1UExactFileRemoval $ctx} '*closed*'
}
foreach($kind in @('stream','hardlink')){
    $kindCopy=$kind
    Check ('new-'+$kindCopy+'-while-leased-is-blocked-or-detected-before-deletion') {
        $c=New-Case;$path=Write-File $c 'a.bin';$ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'a.bin')
        $created=$false;$errorText=$null
        try {
            try {
                if($kindCopy -ceq 'stream'){Set-Content -LiteralPath $path -Stream late -Value 'foreign' -Encoding ASCII}
                else{$null=New-Item -ItemType HardLink -Path (Join-Path $c.payload 'late-link.bin') -Target $path}
                $created=$true
            } catch {$errorText=$_.Exception.Message}
            if($created){
                Reject {Invoke-RimePimeDp1UExactFileRemoval $ctx}
                $ctx=$null
                Require ([IO.File]::Exists($path)) 'Concurrent indirect member not preserved.'
            }else{
                $result=Invoke-RimePimeDp1UExactFileRemoval $ctx;$ctx=$null
                Require $result.all_approved_files_removed 'Denied interference prevented valid removal.'
            }
            $interference.Add([ordered]@{kind=$kindCopy;creation_succeeded=$created;creation_error=$errorText;blocked_or_detected=$true;continuous_membership_protection=$false})
        }finally{Release $ctx}
    }
}
Check 'missing-late-member-is-rejected-before-any-deletion' {
    $c=New-Case;$a=Write-File $c 'a.bin';$b=Write-File $c 'b.bin';$rows=@((Expected $c 'a.bin'),(Expected $c 'b.bin'))
    [IO.File]::Move($b,(Join-Path $c.payload 'b-withheld.bin'))
    Reject {Open-RimePimeDp1UExactFileRemoval $c.payload $rows}
    [IO.File]::WriteAllText($a,'released');Require ([IO.File]::Exists($a)) 'Missing leaf caused partial deletion.'
}
foreach($fault in @('duplicate-case','wrong-size','wrong-hash','wrong-id','string-size','bool-size','array-hash','extra-field','missing-field','empty-array','non-array')){
    $faultCopy=$fault
    Check ('strict-expected-set-'+$faultCopy) {
        $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin';$rows=@($row)
        switch($faultCopy){
            'duplicate-case' {$second=Expected $c 'a.bin';$second.path='A.bin';$rows=@($row,$second)}
            'wrong-size' {$row.bytes++}
            'wrong-hash' {$row.sha256='0'*64}
            'wrong-id' {$row.file_id='00000000:0000000000000000'}
            'string-size' {$row.bytes=[string]$row.bytes}
            'bool-size' {$row.bytes=$true}
            'array-hash' {$row.sha256=@($row.sha256)}
            'extra-field' {$row|Add-Member x 'extra'}
            'missing-field' {$row.PSObject.Properties.Remove('file_id')}
            'empty-array' {$rows=@()}
            'non-array' {$rows=$row}
        }
        Reject {Open-RimePimeDp1UExactFileRemoval $c.payload $rows}
        [IO.File]::WriteAllText($path,'released');Require ([IO.File]::ReadAllText($path) -ceq 'released') 'Rejected set retained locks.'
    }
}
foreach($bad in @('..\outside','sub\..\a.bin','a.bin:stream','a.bin.','a.bin ','a/b','A~1.bin','NUL','\a.bin','a\\b',('a'+[char]1+'.bin'))){
    $badCopy=$bad
    Check ('reject-relative-path-'+$checks.Count) {
        $c=New-Case;$path=Write-File $c 'a.bin';$row=Expected $c 'a.bin';$row.path=$badCopy
        Reject {Open-RimePimeDp1UExactFileRemoval $c.payload @($row)}
        Require ([IO.File]::Exists($path)) 'Invalid path changed valid leaf.'
    }
}
Check 'root-scope-prohibits-repository-production-and-arbitrary-fixture-paths' {
    $c=New-Case;$null=Write-File $c 'a.bin';$row=Expected $c 'a.bin'
    foreach($bad in @($repo,(Join-Path $repo 'installer'),(Join-Path $output 'payload'),($c.payload+'\'),$c.payload.Replace('\','/'))){
        Reject {Open-RimePimeDp1UExactFileRemoval $bad @($row)}
    }
    Reject {Open-RimePimeDp1UExactFileRemoval @($c.payload) @($row)}
}
Check 'source-read-lease-held-until-close' {
    $c=New-Case;$null=Write-File $c 'a.bin';$ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'a.bin')
    try{Reject {$s=[IO.File]::Open((Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.cs'),[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$s.Dispose()}}
    finally{Release $ctx}
}
Check 'private-native-types-do-not-adopt-a-preloaded-global-impostor' {
    $shell=(Get-Process -Id $PID).Path
    $child=Join-Path $output 'private-types.ps1'
    $escaped=$modulePath.Replace("'","''")
    $script=@'
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'namespace Yime.Dp1UExactRemoval { public static class Native { public static string Marker(){return "fake";} } public class RemovalContext {} }'
$m=Import-Module '__MODULE__' -PassThru
try {
    & $m {
        $s=Open-ExactRemovalSource
        try {
            if($script:RemovalNativeType.FullName -ceq 'Yime.Dp1UExactRemoval.Native' -or $script:RemovalType.FullName -ceq 'Yime.Dp1UExactRemoval.RemovalContext'){throw 'Global type adopted'}
        }finally{$s.Dispose()}
    }
}finally{Remove-Module $m}
'@
    [IO.File]::WriteAllText($child,$script.Replace('__MODULE__',$escaped),[Text.UTF8Encoding]::new($false))
    & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child
    Require ($LASTEXITCODE -eq 0) 'Private native helper initialization failed.'
}
Check 'module-removal-releases-all-live-contexts-without-deletion' {
    $c=New-Case;$path=Write-File $c 'a.bin';$ctx=Open-RimePimeDp1UExactFileRemoval $c.payload @(Expected $c 'a.bin')
    Remove-Module $module
    $script:module=$null
    [IO.File]::WriteAllText($path,'released')
    Require ([IO.File]::ReadAllText($path) -ceq 'released') 'Module cleanup retained handle or removed leaf.'
}
}finally{if($null -ne $module){Remove-Module $module}}
$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1u-exact-file-removal-test-v1';powershell_version=$PSVersionTable.PSVersion.ToString()
    passed=($failed.Count -eq 0);check_count=$checks.Count;failed_count=$failed.Count;checks=@($checks);fixture_roots=@($fixtures);interference_attempts=@($interference)
    native_primitive_executed=$true;only_owned_fixture_payloads=$true;directory_or_root_removal_performed=$false
    installer_executed=$false;uninstaller_executed=$false;product_registration_modified=$false;production_user_data_accessed=$false
    installed_yimecore_local12_touched=$false;full_removal_acceptance_passed=$false;dp1_u_acceptance_passed=$false
    source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.cs')).Hash.ToLowerInvariant()
    module_sha256=(Get-FileHash -LiteralPath $modulePath).Hash.ToLowerInvariant();test_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if($failed.Count){throw "$($failed.Count) exact-file-removal checks failed."}
Write-Host "PASS: $($checks.Count) exact-file-removal checks. Evidence: $output"
$global:LASTEXITCODE=0
