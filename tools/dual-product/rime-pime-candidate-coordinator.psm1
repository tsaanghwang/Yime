Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:CoordinatorType=$null
$script:Coordinators=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
function Initialize-CandidateCoordinator {
    if($null -eq $script:CoordinatorType){
        $ns='Yime.Coordinator_'+[guid]::NewGuid().ToString('N')
        $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'rime-pime-candidate-coordinator.cs'))
        $types=Add-Type -TypeDefinition $source.Replace('namespace Yime.CandidateCoordinator {',('namespace '+$ns+' {')) -PassThru
        $script:CoordinatorType=@($types|Where-Object FullName -CEQ ($ns+'.LifetimeGate'))[0]
    }
}
function Add-CoordinatorContext($Native){
    $id=[guid]::NewGuid().ToString('N')
    $value=[pscustomobject]@{context_id=$id;parent_pid=$Native.ParentPid;parent_creation_file_time=$Native.ParentCreationFileTime;target_user_sid=$Native.TargetUserSid;delegation_token=$Native.DelegationToken;worker=$Native.IsWorker}
    $script:Coordinators.Add($id,[pscustomobject]@{public=$value;native=$Native})
    return $value
}
function Open-RimePimeCandidateCoordinator {
    Initialize-CandidateCoordinator
    Add-CoordinatorContext ($script:CoordinatorType::OpenParent('product'))
}
function Join-RimePimeCandidateCoordinator {
    [CmdletBinding()]param([Parameter(Mandatory)][int]$ParentPid,[Parameter(Mandatory)][long]$ParentCreationFileTime,
        [Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$DelegationToken)
    Initialize-CandidateCoordinator
    Add-CoordinatorContext ($script:CoordinatorType::JoinWorker('product',$ParentPid,$ParentCreationFileTime,$TargetUserSid,$DelegationToken))
}
function Close-RimePimeCandidateCoordinator {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    if($Context -isnot [pscustomobject] -or $Context.context_id -isnot [string] -or -not $script:Coordinators.ContainsKey($Context.context_id)){throw 'Unknown coordinator lease.'}
    $entry=$script:Coordinators[$Context.context_id]
    if(-not [object]::ReferenceEquals($entry.public,$Context)){throw 'Only the original coordinator context can close the lease.'}
    $entry.native.Dispose();$null=$script:Coordinators.Remove($Context.context_id)
}
function Get-RimePimeCandidateCoordinatorHandle {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    if($Context -isnot [pscustomobject] -or $Context.context_id -isnot [string] -or -not $script:Coordinators.ContainsKey($Context.context_id)){throw 'Unknown coordinator lease.'}
    $entry=$script:Coordinators[$Context.context_id]
    if(-not [object]::ReferenceEquals($entry.public,$Context)){throw 'Only the original coordinator can lend its handle.'}
    return $entry.native.BorrowGateHandle()
}
Export-ModuleMember -Function Open-RimePimeCandidateCoordinator,Join-RimePimeCandidateCoordinator,Close-RimePimeCandidateCoordinator,Get-RimePimeCandidateCoordinatorHandle
