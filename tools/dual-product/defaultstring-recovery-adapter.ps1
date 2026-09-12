# Reviewed recovery providers operate on the immutable original payload.
function Initialize-MaintenanceProviders([string]$PackageRoot){
    $script:CandidateRegistrationModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration.psm1') -PassThru -Scope Local
    $script:CandidateRuntimeModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1') -PassThru -Scope Local
}
function Invoke-MaintenanceWorker([string]$Action,$Context,$Ticket,[string]$PackageRoot,[string]$ExpectedManifestSha256,
    [string]$InstallerPath,[string]$ReceiptPath,$Coordinator){
    if($Action -cne 'Remove' -or $Ticket.plan.run_id -cne '9fe7f28d-0889-4828-85b5-1f481431b43a'){throw 'Recovery worker is removal-only for the fixed transaction.'}
    $self=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID)
    try{
        $request=[ordered]@{Action='Remove';PackageRoot=$PackageRoot;ExpectedManifestSha256=$ExpectedManifestSha256;
            InstallerPath=$InstallerPath;AuthorizationPath=$Context.authorization_path;TrustedApprovalSha256=$Context.approval_sha256;
            BoundaryPath=$Context.boundary_path;ReceiptPath=$ReceiptPath;JournalRoot=$Ticket.journal_root;
            PreparedSha256=$Ticket.prepared_sha256;ParentPid=$PID;ParentCreationFileTime=$self.CreationFileTime;DelegationToken=$Coordinator.delegation_token}
        $root=[IO.Path]::GetDirectoryName($Context.authorization_path)
        $worker=Join-Path $root ('recovery-worker-'+[guid]::NewGuid().ToString('N')+'.json')
        Write-MaintenancePeerEvidence $worker $request
        $entry=Join-Path $root ('recovery-entry-'+[guid]::NewGuid().ToString('N')+'.json')
        Write-MaintenancePeerEvidence $entry @{PolicyPath=$script:RecoveryPolicyPath;ExpectedPolicySha256=$script:RecoveryPolicyHash;WorkerParametersPath=$worker}
        $checked=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\powershell\run_checked.py'))
        $runner=Join-Path $PSScriptRoot 'recover-defaultstring-transaction.ps1'
        $python=(Get-Command python -CommandType Application -ErrorAction Stop).Source
        $process=Start-Process -FilePath $python -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @(('"'+$checked+'"'),'--script',('"'+$runner+'"'),'--edition','ps5','--params-file',('"'+$entry+'"'))
        try{$process.WaitForExit();if($process.ExitCode -ne 0){throw ('Recovery worker failed: '+$process.ExitCode)}}finally{$process.Dispose()}
    }finally{$self.Dispose()}
}
