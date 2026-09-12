# Reviewed recovery providers operate on the immutable original payload.
function Assert-RecoveryRemainingPayload($Context,$Ticket,[string]$Bundle){
    $remaining=Test-MaintenanceInstalledFiles $Ticket.plan -AllowAbsent
    if($remaining.Count -lt @($Ticket.plan.files).Count){
        # Partial deletion is admitted only after fresh, independent full
        # registration absence. A registrar cannot depend on missing DLLs.
        $null=Get-MaintenanceRegistration $Context $Ticket.plan $Bundle 'Absent'
    }
    return $remaining.Count
}
function Release-RecoveryJournalForWorker($Ticket){
    # The controller retains the product coordinator, authenticated inputs and
    # plan. The worker must independently acquire and verify the install journal.
    # Do not carry its exclusive transaction.lock lease across that process hop.
    if($null -eq $Ticket.store){throw 'Expected an owned journal lease before handoff.'}
    $Ticket.store.Dispose()
    $Ticket.store=$null
}
function Get-RecoveryPythonPath {
    foreach($command in @(Get-Command python -CommandType Application -All -ErrorAction Stop)){
        $path=$command.Source
        # WindowsApps may expose an app-execution alias, not the native Python
        # required by this worker. Keep PATH precedence among real executables.
        if($path -isnot [string] -or -not [IO.Path]::IsPathRooted($path) -or
            $path -match '(?i)\\WindowsApps\\' -or -not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
        return $path
    }
    throw 'No native Python executable found for recovery; do not launch an app-execution alias.'
}
function Start-RecoveryCheckedWorker([string]$Checked,[string]$Runner,[string]$Entry){
    $python=Get-RecoveryPythonPath
    if($python -isnot [string]){throw 'Recovery Python path must be one string.'}
    Start-Process -FilePath $python -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @(('"'+$Checked+'"'),'--script',('"'+$Runner+'"'),'--edition','ps5','--params-file',('"'+$Entry+'"'))
}
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
        $process=Start-RecoveryCheckedWorker $checked $runner $entry
        try{$process.WaitForExit();if($process.ExitCode -ne 0){throw ('Recovery worker failed: '+$process.ExitCode)}}finally{$process.Dispose()}
    }finally{$self.Dispose()}
}
