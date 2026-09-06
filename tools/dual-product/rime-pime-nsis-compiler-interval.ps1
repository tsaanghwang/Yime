# DP1-NSIS-MEMBERSHIP-05: private copied compiler tree; notification failure rejects publication.
# Uses the DP1-J native primitive without widening its fixture-only public API.
function Open-RimePimeMonitoredNsisStage {
    param([Parameter(Mandatory)][string]$StageRoot)
    $parent=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) '.tmp\dual-product'
    $full=[IO.Path]::GetFullPath($StageRoot).TrimEnd([char]92)
    $work=Split-Path -Parent $full
    if((Split-Path -Parent $work) -ine $parent -or
        (Split-Path -Leaf $work) -cnotmatch '^dp1-(package-build-stage|nsis-interval-test)-[A-Za-z0-9-]+$' -or
        (Split-Path -Leaf $full) -cne 'NSIS' -or (Test-Path -LiteralPath $full)){
        throw 'Monitored compiler stage requires a fresh NSIS child of a DP1 build/test workspace.'
    }
    Assert-RimePimeNoReparsePath $work
    $source=$null;$closure=$null;$monitor=$null
    try{
        $source=Open-RimePimeNsisCompilerInputClosure
        $lock=Read-RimePimeNsisCompilerToolchainLockDocument
        New-Item -ItemType Directory -Path $full -ErrorAction Stop|Out-Null
        foreach($lease in $source.FileLeases){
            $relative=$lease.Path.Substring($source.NsisRoot.Length+1)
            $target=Join-Path $full $relative
            $null=[IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            Assert-RimePimeNoReparsePath (Split-Path -Parent $target)
            $destination=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$lease.Stream.Position=0;$lease.Stream.CopyTo($destination);$destination.Flush($true)}
            finally{$destination.Dispose();$lease.Stream.Position=0}
        }
        Initialize-RimePimeNsisMembershipMonitorTypeV1
        $monitor=[YimePime.NsisMembership.MonitorHostV1]::new($full,65536)
        # Arm BEFORE the exact baseline and leases. Pre-arm additions must fail baseline;
        # every subsequent membership notification (including transient additions) fails seal.
        $closure=Open-RimePimeNsisCompilerInputClosureCore $full $lock.Document.nsis.compiler_input_closure
        $closure.ControlLeases=$source.ControlLeases
        $source.ControlLeases=@()
        $closure.ToolchainLockPath=$lock.Path;$closure.ToolchainLockDigest=$lock.Digest
        $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($lease in @($closure.FileLeases)+@($closure.DirectoryLeases)){$null=$allowed.Add($lease.Path)}
        foreach($item in Get-ChildItem -LiteralPath $full -Recurse -Force){
            if(-not $allowed.Contains($item.FullName)){throw 'Unlisted member outside scoped NSIS roots.'}
        }
        $null=Test-RimePimeNsisCompilerInputClosure $closure
        return [pscustomobject]@{Root=$full;Closure=$closure;Monitor=$monitor;Completed=$false}
    }catch{
        if($null -ne $monitor){$monitor.Dispose()}
        if($null -ne $closure){Close-RimePimeNsisCompilerInputClosure $closure}
        throw
    }finally{if($null -ne $source){Close-RimePimeNsisCompilerInputClosure $source}}
}

function Complete-RimePimeMonitoredNsisStage {
    param([Parameter(Mandatory)]$Stage)
    if($Stage.Completed -or -not $Stage.Monitor.IsArmed){throw 'Compiler membership interval is not armed.'}
    # Caller must have synchronously waited for makensis exit. No candidate publication
    # is admitted before this barrier; overflow, cancellation and cleanup fail closed.
    $result=$Stage.Monitor.Seal(10000)
    $null=Test-RimePimeNsisCompilerInputClosure $Stage.Closure
    if(-not $result.ArmedBeforeInterval -or -not $result.BarrierObserved -or $result.UnexpectedEventCount -ne 0){
        throw 'Compiler membership interval did not complete cleanly.'
    }
    $Stage.Completed=$true
    return [pscustomobject]@{
        schema_version='yime-rime-pime-nsis-compiler-membership-interval-v1'
        armed_before_baseline=$true;completion_barrier_after_compiler_exit=$true
        unexpected_membership_event_count=$result.UnexpectedEventCount
        notification_batch_count=$result.NotificationBatchCount
        physical_membership_prevention_claimed=$false
        active_same_sid_transient_tree_membership_interference_excluded=$false
        nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false
    }
}
function Close-RimePimeMonitoredNsisStage {
    param([Parameter(Mandatory)]$Stage)
    try{$Stage.Monitor.Dispose()}finally{Close-RimePimeNsisCompilerInputClosure $Stage.Closure}
}
