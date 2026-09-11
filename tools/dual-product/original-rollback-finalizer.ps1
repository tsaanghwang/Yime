# Definitions only. Dot-source inside the reviewed maintenance module scope.
# This separate recovery policy never invokes registration/removal workers.
function Assert-FinalizerPlanBinding($Plan,$Original,[string]$Manifest){
    # The caller authenticates the original ticket bytes before parsing them.
    # Both fields below are canonical approval object digests, not JSON file hashes.
    if($Original.approval_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Plan.original_approval_sha256 -cne $Original.approval_sha256 -or
        $Plan.manifest_sha256 -cne $Manifest -or $Plan.files.Count -ne 191){
        throw 'Finalizer plan differs from authenticated original ticket or manifest.'
    }
}
function Assert-FinalizerRuntimeAbsent($Plan){
    $parameters=Get-MaintenanceRuntimeParameters $Plan
    & $script:CandidateRuntimeModule {
        param($p)
        $boundary=Open-CandidateRuntimeBoundary @p;$bound=@()
        try{
            $bound=@(Get-CandidateRuntimeProcesses $boundary)
            if($bound.Count){throw 'Finalizer requires no candidate Runtime processes.'}
        }finally{
            foreach($process in $bound){$process.facts.Dispose();$process.process.Dispose()}
            foreach($lease in $boundary.leases){$lease.Dispose()}
        }
    } $parameters
}
function Invoke-AbsentRollbackFinalization($Context,$Ticket,[string]$PackageRoot,[switch]$Apply){
    if($Ticket.store.Has('commit.bin') -or $Ticket.store.Has('terminal.bin')){throw 'Finalizer requires an undecided install; retain decisions.'}
    $removal=Open-MaintenanceRemoval $Ticket
    if($null -eq $removal){throw 'Finalizer requires original durable removal intent.'}
    try{if(-not $removal.commit -or $removal.terminal){throw 'Finalizer requires pending committed removal.'}}
    finally{$removal.store.Dispose()}
    $present=Test-MaintenanceInstalledFiles $Ticket.plan
    if($present.Count -ne $Ticket.plan.files.Count){throw 'Finalizer requires every original payload still present.'}
    Assert-FinalizerRuntimeAbsent $Ticket.plan
    $null=Get-MaintenanceRegistration $Context $Ticket.plan $PackageRoot 'Absent'
    Assert-MaintenancePeerProtection $Context.peer_protection
    Assert-MaintenanceDefaultInput $Ticket.plan.default_input
    if(-not $Apply){return [pscustomobject]@{eligible=$true;applied=$false;payload_count=$present.Count;installed_acceptance_passed=$false}}
    # Only one attempt per fresh authorization, after all observations pass.
    $marker=[IO.File]::Open((Join-Path ([IO.Path]::GetDirectoryName($Context.authorization_path)) 'original-finalizer-started'),'CreateNew','Write','None')
    try{$marker.WriteByte(1);$marker.Flush($true)}finally{$marker.Dispose()}
    Remove-MaintenanceInstalledFiles $Ticket.plan
    Assert-MaintenancePeerProtection $Context.peer_protection
    Assert-MaintenanceDefaultInput $Ticket.plan.default_input
    $removal=Open-MaintenanceRemoval $Ticket
    try{Publish-MaintenanceDecision $removal.store 'terminal.bin' $removal.hash 'remove-complete'}
    finally{$removal.store.Dispose()}
    Publish-MaintenanceDecision $Ticket.store 'terminal.bin' $Ticket.prepared_sha256 'rolled-back'
    [pscustomobject]@{eligible=$true;applied=$true;disposition='rolled-back';installed_acceptance_passed=$false}
}
