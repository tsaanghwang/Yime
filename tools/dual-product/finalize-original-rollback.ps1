[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionParametersPath,
      [Parameter(Mandatory=$true)][string]$RecoveryTicketPath,
      [Parameter(Mandatory=$true)][string]$OriginalBundleRoot,[switch]$Apply)
$ErrorActionPreference='Stop'
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Original test PC only.'}
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
$definitions=Join-Path $PSScriptRoot 'original-rollback-finalizer.ps1'
& $module {
    param($parametersPath,$ticketPath,$bundle,$definitions,$apply)
    Initialize-CandidateMaintenance
    $p=Get-Content -LiteralPath $parametersPath -Raw -Encoding UTF8|ConvertFrom-Json
    & $script:CandidatePackageModule {param($v) Assert-CandidateObject $v @('Mode','InstallerPath','ExpectedInstallerSha256','AuthorizationPath','TrustedApprovalSha256','BoundaryPath','ReceiptPath','PreparedSha256')} $p
    $raw=[IO.File]::ReadAllBytes($ticketPath)
    $hash=& $script:CandidatePackageModule {param($b) Get-CandidateBytesHash $b} $raw
    if($hash -cne '05352e3da345967e3e71fb5b6551f1db5739473f46a36ce3b311c46313d2b039'){throw 'Original recovery ticket hash mismatch.'}
    $original=& $script:CandidatePackageModule {param($b) ConvertFrom-CandidateJson $b} $raw
    if($p.Mode -cne 'Resume' -or $p.PreparedSha256 -cne $original.prepared_sha256 -or $p.ExpectedInstallerSha256 -cne '0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617'){throw 'Finalizer requires the fixed original package and ticket.'}
    $context=$null;$coordinator=$null;$package=$null;$ticket=$null;$protection=$null
    try{
        # This is a raw file digest, not the canonical approval object digest
        # stored in the authenticated recovery ticket and prepared plan.
        $originalAuthorizationPath=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ticketPath))) 'authorization.json'
        if((Get-MaintenanceHash $originalAuthorizationPath) -cne '89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab'){throw 'Original authorization file hash mismatch.'}
        $context=Open-MaintenanceAuthorization $p.AuthorizationPath $p.TrustedApprovalSha256 $p.BoundaryPath
        Assert-MaintenanceInitiator $context
        if($context.authorization.package_sha256 -cne $p.ExpectedInstallerSha256 -or $context.authorization.canonical_receipt_sha256 -cne 'c4badd8cc2c3b06389ed044f08bcfb0383eb963affe5ca93a3e1c5e870eea4a1'){throw 'New authorization must retain the original package and receipt.'}
        $coordinator=& $script:CandidateCoordinatorModule {Open-RimePimeCandidateCoordinator}
        $context|Add-Member -NotePropertyName coordinator_handle -NotePropertyValue (& $script:CandidateCoordinatorModule {param($c) Get-RimePimeCandidateCoordinatorHandle -Context $c} $coordinator)
        foreach($root in @($context.authorization.install_root,$context.authorization.state_root,$context.authorization.recovery_root)){Assert-MaintenanceRootDisjoint ([IO.Path]::GetFullPath($bundle)) $root}
        $manifest='3f676b80b86f4c752e96c5ed06655bddb3b5b4aedd762ca8369483e7ae14b01d'
        $package=Open-MaintenanceVerifiedPackage $bundle $manifest $context $p.InstallerPath $p.ReceiptPath
        # Current reviewed observers; old bundle remains byte-identical data and
        # original native query executables. Never import its buggy worker.
        $script:CandidateRegistrationModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration.psm1') -PassThru -Scope Local
        $script:CandidateRuntimeModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1') -PassThru -Scope Local
        $protection=Start-MaintenancePeerProtection $context
        $journal=Join-Path $context.authorization.recovery_root 'install-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0'
        $ticket=Read-MaintenancePreparedPlan $context $journal $p.PreparedSha256
        . $definitions
        Assert-FinalizerPlanBinding $ticket.plan $original $manifest
        $result=Invoke-AbsentRollbackFinalization $context $ticket $bundle -Apply:$apply
        $resultPath=Join-Path ([IO.Path]::GetDirectoryName($context.authorization_path)) ('original-finalizer-'+[guid]::NewGuid().ToString('N')+'.json')
        Write-MaintenancePeerEvidence $resultPath $result
        Write-Host ('Finalizer evidence: '+$resultPath)
        $result|ConvertTo-Json
    }catch{Save-RimePimeMaintenanceFailure -Failure $_ -Phase 'original-rollback-finalizer';throw}
    finally{
        try{if($protection){Complete-MaintenancePeerProtection $protection}}
        finally{
            if($ticket){$ticket.store.Dispose()};if($package){Close-MaintenanceCandidate $package};if($context){Close-MaintenanceAuthorization $context}
            if($coordinator){& $script:CandidateCoordinatorModule {param($c) Close-RimePimeCandidateCoordinator -Context $c} $coordinator}
        }
    }
} $ExecutionParametersPath $RecoveryTicketPath $OriginalBundleRoot $definitions ([bool]$Apply)
