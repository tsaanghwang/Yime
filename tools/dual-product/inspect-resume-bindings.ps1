[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ArchivedPreparedPath,
    [Parameter(Mandatory=$true)][string]$ExpectedPreparedSha256,
    [Parameter(Mandatory=$true)][string]$AuthorizationPath,
    [Parameter(Mandatory=$true)][string]$ExpectedAuthorizationSha256,
    [switch]$IncludeJournalReadChecks
)
# Diagnostic only. Never opens a transaction store or invokes maintenance.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$pkg=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru -Force
& $pkg {param($a,$b) Assert-CandidateHash $a; Assert-CandidateHash $b} $ExpectedPreparedSha256 $ExpectedAuthorizationSha256
function ReadBounded([string]$Path,[int]$Maximum){
    $s=[IO.File]::Open($Path,'Open','Read','Read')
    try{
        if($s.Length -lt 1 -or $s.Length -gt $Maximum){throw 'Diagnostic input size invalid.'}
        $m=[IO.MemoryStream]::new()
        try{$s.CopyTo($m);return ,$m.ToArray()}finally{$m.Dispose()}
    }finally{$s.Dispose()}
}
$raw=ReadBounded $ArchivedPreparedPath 1048620
if($raw.Length -lt 45 -or [Text.Encoding]::ASCII.GetString($raw,0,8) -cne 'YDP1UTX1' -or [BitConverter]::ToInt32($raw,8) -ne $raw.Length-44){throw 'Invalid archived journal envelope.'}
$payload=[byte[]]::new($raw.Length-44);[Array]::Copy($raw,44,$payload,0,$payload.Length)
$embedded=([BitConverter]::ToString($raw,12,32)).Replace('-','').ToLowerInvariant()
$digest=& $pkg {param($b) Get-CandidateBytesHash $b} $payload
if($digest -cne $embedded -or $digest -cne $ExpectedPreparedSha256){throw 'Archived payload differs from ticket digest.'}
$authBytes=ReadBounded $AuthorizationPath 1048576
if((& $pkg {param($b) Get-CandidateBytesHash $b} $authBytes) -cne $ExpectedAuthorizationSha256){throw 'Authorization digest mismatch.'}
$plan=& $pkg {param($b) ConvertFrom-CandidateJson $b} $payload
$authorization=& $pkg {param($b) ConvertFrom-CandidateJson $b} $authBytes
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body; $checks.Add([ordered]@{check=$Name;passed=$true;error_type=$null})}
    catch{
        $row=[ordered]@{check=$Name;passed=$false;error_type=$_.Exception.GetType().FullName}
        $row.base_error_type=$_.Exception.GetBaseException().GetType().FullName
        $row.hresult=$_.Exception.GetBaseException().HResult
        # The copied schema validator uses fixed messages, without identity values.
        if($Name -ceq 'complete-plan-schema'){$row.error_message=$_.Exception.Message}
        $checks.Add($row)
    }
}
Import-Module (Join-Path $PSScriptRoot 'resume-plan-diagnostic.psm1') -Force
Check 'complete-plan-schema' { Assert-ArchivedResumePlan -Plan $plan -PackageModule $pkg }
foreach($field in @('install_root','state_root','recovery_root','initiating_sid','target_machine_id','target_name','package_sha256')){
    Check ('approval-'+$field) {
        if($plan.$field -isnot [string] -or $plan.$field -cne $authorization.$field){throw 'Binding mismatch.'}
    }
}
foreach($field in @('install','state')){
    Check ($field+'-directory-identity') {
        $path=$plan.($field+'_root');$expected=$plan.($field+'_directory_id')
        $observed=& $pkg {
            param([string]$path)
            Initialize-CandidateNative
            $script:CandidateNative::CanonicalPath($path)
            $open=$script:CandidateNative.GetMethod('OpenDirectory',[Reflection.BindingFlags]'NonPublic,Static')
            $verify=$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static')
            $ads=$script:CandidateNative.GetMethod('RejectNamedStreams',[Reflection.BindingFlags]'NonPublic,Static')
            $handles=[Collections.Generic.List[object]]::new()
            try{
                $pending=[Collections.Generic.Stack[string]]::new()
                for($p=$path;$null -ne $p;$p=[IO.Path]::GetDirectoryName($p)){$pending.Push($p)}
                while($pending.Count){
                    $p=$pending.Pop();$h=$open.Invoke($null,[object[]]@($p));$handles.Add($h)
                    $id=$verify.Invoke($null,[object[]]@($h,$p,$true));$null=$ads.Invoke($null,[object[]]@($p))
                }
                return $id
            }finally{foreach($h in $handles){$h.Dispose()}}
        } $path
        if($expected -isnot [string] -or $observed -cne $expected){throw 'Directory identity mismatch.'}
    }
}
Check 'recovery-executable-identity' {
    $observation=& $pkg {param($p) $script:CandidateNative::Inspect($p)} (Join-Path $plan.recovery_root 'maintenance-candidate.exe')
    if($observation.FileId -cne $plan.recovery_executable.file_id -or $observation.Bytes -ne $plan.recovery_executable.bytes -or $observation.Sha256 -cne $plan.package_sha256 -or $observation.Sha256 -cne $plan.recovery_executable.sha256){throw 'Recovery identity mismatch.'}
}
if($IncludeJournalReadChecks){
    # These are read observations, not TransactionStore.Open or a maintenance lease.
    # Read-only exclusive sharing does NOT prove that ReadWrite access is permitted.
    Check 'single-install-journal' {
        $roots=@(Get-ChildItem -LiteralPath $plan.recovery_root -Directory -Filter 'install-*' -ErrorAction Stop)
        if($roots.Count -ne 1 -or $roots[0].FullName -cne (Join-Path $plan.recovery_root ('install-'+$plan.run_id))){throw 'Unexpected retained install journal set.'}
    }
    foreach($kind in @('install','remove')){
        $journal=Join-Path $plan.recovery_root ($kind+'-'+$plan.run_id)
        Check ($kind+'-journal-inventory') {
            $count=0
            foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($journal)){
                $count++
                $name=[IO.Path]::GetFileName($entry)
                if($count -gt 128 -or [IO.Directory]::Exists($entry) -or
                    ($name -cnotin @('transaction.lock','prepared.bin','commit.bin','terminal.bin') -and
                     $name -cnotmatch '^(prepared|commit|terminal)\.bin\.pending-[a-f0-9]{32}$')){throw 'Unexpected journal member.'}
            }
        }
        Check ($kind+'-lock-exclusive-read') {
            $lockPath=Join-Path $journal 'transaction.lock'
            & $pkg {
                param([string]$p)
                $script:CandidateNative::CanonicalPath($p)
                $s=[IO.File]::Open($p,'Open','Read','None')
                try{
                    $verify=$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static')
                    $ads=$script:CandidateNative.GetMethod('RejectNamedStreams',[Reflection.BindingFlags]'NonPublic,Static')
                    $null=$verify.Invoke($null,[object[]]@($s.SafeFileHandle,$p,$false))
                    $null=$ads.Invoke($null,[object[]]@($p))
                    if($s.Length -ne 0){throw 'Nonempty transaction lock.'}
                }finally{$s.Dispose()}
            } $lockPath
        }
    }
}
[ordered]@{
    schema_version='yime-resume-binding-diagnostic-v1';checks=@($checks.ToArray());
    all_checks_passed=(@($checks|Where-Object {-not $_.passed}).Count -eq 0);
    opened_transaction_store=$false;maintenance_executed=$false;installed_acceptance_passed=$false;
    journal_read_checks_requested=[bool]$IncludeJournalReadChecks;write_access_tested=$false
}|ConvertTo-Json -Depth 6
