[CmdletBinding()]
param([Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][string]$ExpectedPolicySha256,
    [string]$ExecutionParametersPath,[string]$PackageRoot,[switch]$Apply,[string]$WorkerParametersPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Fixed test PC only.'}
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Native PS5 required.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$leases=[Collections.Generic.List[object]]::new()
function Read-LockedJson([string]$Path,[string]$Hash){
    for($cursor=[IO.Path]::GetFullPath($Path);$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
        if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect recovery input path.'}
    }
    $stream=[IO.File]::Open($Path,'Open','Read','Read');$leases.Add($stream)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    if($actual -cne $Hash){throw ('Recovery input hash mismatch: '+$Path)}
    $stream.Position=0;$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
    try{return $reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
}
try{
    $policy=Read-LockedJson $PolicyPath $ExpectedPolicySha256
    if($policy.transaction_id -cne '9fe7f28d-0889-4828-85b5-1f481431b43a'){throw 'Wrong recovery policy.'}
    foreach($file in $policy.code){
        if($file.path -match '(^/|\\|:|(^|/)\.\.(/|$))'){throw 'Unsafe code path.'}
        $path=Join-Path $repo $file.path
        # Retain all code leases across UAC and mutations.
        $stream=[IO.File]::Open($path,'Open','Read','Read');$leases.Add($stream)
        $memory=[IO.MemoryStream]::new()
        try{$stream.CopyTo($memory);$code=[Text.Encoding]::UTF8.GetString($memory.ToArray()).Replace("`r`n","`n")}finally{$memory.Dispose()}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($code)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($hash -cne $file.sha256){throw ('Recovery code changed: '+$file.path)}
    }
    $base=Join-Path $env:USERPROFILE 'Yime Rime-PIME Test Archives'
    $oldRoot=Join-Path $base 'approval-9fe7f28d-0889-4828-85b5-1f481431b43a'
    $old=Read-LockedJson (Join-Path $oldRoot 'authorization.json') '67c1654c42975a4d169fe94ef272b5c84f765f2aa38bba3eca490298106e9fe2'
    $original=Read-LockedJson (Join-Path $oldRoot 'candidate-recovery-9fe7f28d-0889-4828-85b5-1f481431b43a.json') 'dd6a2b8d98250b921f59a08d47a89d8ee640d8ca9d8489d29d7f7ec832f388f2'
    $baseline=Read-LockedJson (Join-Path $oldRoot 'peer-preflight.json') '9fbcf26fc7b557f6393b4a8ae890048e0231a708591ad66fa044cf7e5f12b447'
    if($old.initiating_sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Wrong initiating SID.'}
    $module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
    & $module {
        param($pPath,$bundle,$apply,$workerPath,$policyPath,$policyHash,$old,$original,$baseline)
        . (Join-Path $PSScriptRoot 'defaultstring-recovery-adapter.ps1')
        . (Join-Path $PSScriptRoot 'defaultstring-peer-repair.ps1')
        $script:RecoveryPolicyPath=$policyPath;$script:RecoveryPolicyHash=$policyHash
        Initialize-CandidateMaintenance
        $manifest='256a9ab5d213093248001d2bb32f918bcb0c4431628ec40ea5295e8b14a76ddf'
        if($workerPath){
            $w=Get-Content -LiteralPath $workerPath -Raw -Encoding UTF8|ConvertFrom-Json
            if($w.Action -cne 'Remove' -or $w.PreparedSha256 -cne $original.prepared_sha256 -or $w.ExpectedManifestSha256 -cne $manifest -or $w.JournalRoot -cne (Join-Path $old.recovery_root 'install-9fe7f28d-0889-4828-85b5-1f481431b43a')){throw 'Worker escaped fixed recovery scope.'}
            $args=@{};foreach($property in $w.PSObject.Properties){$args[$property.Name]=$property.Value}
            try{Invoke-RimePimeCandidateWorker @args}catch{Save-RimePimeMaintenanceFailure -Failure $_ -Phase 'defaultstring-recovery-worker';throw}
            return
        }
        $p=Get-Content -LiteralPath $pPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($p.Mode -cne 'Resume' -or $p.PreparedSha256 -cne $original.prepared_sha256 -or $p.ExpectedInstallerSha256 -cne $old.package_sha256){throw 'Fixed original Resume binding required.'}
        $context=$null;$package=$null;$ticket=$null;$coordinator=$null
        try{
            $context=Open-MaintenanceAuthorization $p.AuthorizationPath $p.TrustedApprovalSha256 $p.BoundaryPath
            Assert-MaintenanceInitiator $context
            foreach($field in @('install_root','state_root','recovery_root','initiating_sid','target_machine_id','package_sha256','canonical_receipt_sha256','product_boundary_sha256')){if($context.authorization.$field -cne $old.$field){throw ('Recovery changed original '+$field)}}
            $coordinator=& $script:CandidateCoordinatorModule {Open-RimePimeCandidateCoordinator}
            $context|Add-Member -NotePropertyName coordinator_handle -NotePropertyValue (& $script:CandidateCoordinatorModule {param($c) Get-RimePimeCandidateCoordinatorHandle -Context $c} $coordinator)
            $package=Open-MaintenanceVerifiedPackage $bundle $manifest $context $p.InstallerPath $p.ReceiptPath
            Initialize-MaintenanceProviders $bundle
            $ticket=Read-MaintenancePreparedPlan $context (Join-Path $old.recovery_root 'install-9fe7f28d-0889-4828-85b5-1f481431b43a') $original.prepared_sha256
            if($ticket.plan.run_id -cne '9fe7f28d-0889-4828-85b5-1f481431b43a' -or $ticket.plan.manifest_sha256 -cne $manifest){throw 'Plan identity mismatch.'}
            if(Get-MaintenanceDecision $ticket.store 'commit.bin' $ticket.prepared_sha256 @('installed')){throw 'Recovery cannot remove a committed installation.'}
            $removal=Open-MaintenanceRemoval $ticket
            try{if(-not $removal -or -not $removal.commit){throw 'Existing removal intent required.'}}finally{if($removal){$removal.store.Dispose()}}
            $protection=Start-MaintenancePeerProtection $context
            Assert-DefaultstringPeerDifference $baseline $protection.before $old.initiating_sid
            foreach($tree in @($baseline.registry|Where-Object {$_.hive -ceq 'Users' -and $_.key.EndsWith('CTF\TIP\{E40FA752-BB96-461D-A51D-F40EB437EC65}')})){Assert-DefaultstringTipShape $tree $old.initiating_sid}
            Assert-MaintenanceDefaultInput $ticket.plan.default_input
            $peerReference=Get-DefaultstringPeerControlPanel $old.initiating_sid
            $null=Get-MaintenanceRegistration $context $ticket.plan $bundle 'Partial'
            if(-not $apply){
                $null=Test-MaintenanceInstalledFiles $ticket.plan
                Write-Host 'VALIDATED: fixed recovery inputs; no product mutation. Apply must repeat every check.'
                return
            }
            $arguments=@{Context=$context;Ticket=$ticket;PackageRoot=$bundle;ExpectedManifestSha256=$manifest;InstallerPath=$p.InstallerPath;ReceiptPath=$p.ReceiptPath;Coordinator=$coordinator}
            Complete-MaintenanceRemoval $context $ticket $arguments $null
            $null=Get-MaintenanceRegistration $context $ticket.plan $bundle 'Absent'
            $peerReferenceAfter=Get-DefaultstringPeerControlPanel $old.initiating_sid
            if(($peerReference|ConvertTo-Json -Compress) -cne ($peerReferenceAfter|ConvertTo-Json -Compress)){throw 'Peer Control Panel reference changed; stop before repair.'}
            $evidence=Join-Path ([IO.Path]::GetDirectoryName($p.AuthorizationPath)) ('peer-repair-'+[guid]::NewGuid().ToString('N'))
            $null=[IO.Directory]::CreateDirectory($evidence)
            Restore-DefaultstringPeerTip $context $baseline $evidence
            Assert-MaintenanceDefaultInput $ticket.plan.default_input
            Write-MaintenancePeerEvidence (Join-Path $evidence 'result.json') @{transaction_id=$ticket.plan.run_id;rime_rollback_complete=$true;peer_snapshot_restored=$true;physical_input_verified=$false;reboot_verified=$false}
            Write-Host ('RECOVERED: rollback and original peer snapshot verified. Evidence: '+$evidence)
        }catch{Save-RimePimeMaintenanceFailure -Failure $_ -Phase 'defaultstring-recovery';throw}
        finally{
            if($ticket){$ticket.store.Dispose()};if($package){Close-MaintenanceCandidate $package};if($context){Close-MaintenanceAuthorization $context}
            if($coordinator){& $script:CandidateCoordinatorModule {param($c) Close-RimePimeCandidateCoordinator -Context $c} $coordinator}
        }
    } $ExecutionParametersPath $PackageRoot ([bool]$Apply) $WorkerParametersPath $PolicyPath $ExpectedPolicySha256 $old $original $baseline
}finally{foreach($stream in $leases){$stream.Dispose()}}
