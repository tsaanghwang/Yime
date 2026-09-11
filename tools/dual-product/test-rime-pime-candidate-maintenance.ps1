[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$parent=Join-Path $repo '.tmp\dual-product'
if(-not $OutputRoot){$OutputRoot=Join-Path $parent ('dp1-candidate-maintenance-test-'+[guid]::NewGuid().ToString('N'))}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if([IO.Path]::GetDirectoryName($OutputRoot) -ine $parent -or [IO.Path]::GetFileName($OutputRoot) -notmatch '^dp1-candidate-maintenance-test-' -or (Test-Path -LiteralPath $OutputRoot)){throw 'Fresh owned maintenance test root required.'}
$null=[IO.Directory]::CreateDirectory($OutputRoot)
$reader=& {Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru -Scope Local}
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){$failure=$null;try{& $Body|Out-Null}catch{$failure=$_.Exception.ToString()};Assert ($failure -and $failure -match $Pattern) ('Expected '+$Pattern+'; observed '+$failure)}
function Check([string]$Name,[scriptblock]$Body){& $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host ('PASS '+$Name)}
function Write-Bytes([string]$Path,[string]$Value){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function New-Fixture {
    $root=Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'));$bundle=Join-Path $root 'bundle'
    $rows=@()
    foreach($name in @('PIMELauncher.exe','x86/PIMETextService.dll','x64/PIMETextService.dll','x86/PIMERegistrationStatus.exe','x64/PIMERegistrationStatus.exe',
        'go-backend/server.exe','maintenance/invoke-rime-pime-candidate.ps1','maintenance/rime-pime-dp1u-candidate-registration.psm1','maintenance/rime-pime-dp1u-candidate-runtime.psm1','maintenance/rime-pime-peer-protection.psm1')){
        $path=Join-Path $bundle $name;Write-Bytes $path ('inert fixture '+$name)
        $rows += [pscustomobject]@{path=$name;bytes=[long](Get-Item $path).Length;sha256=(Hash $path)}
    }
    $manifest=[ordered]@{schema_version='yime-rime-pime-executable-candidate-v2';product='rime-pime';product_version='1.4.0-dev.1';architectures='x86,x64';
        installation_scope='approved-isolated-x64-current-peer-protected';launcher_mode='required-dp1-candidate-state';maintenance_entry='maintenance/invoke-rime-pime-candidate.ps1';
        registration_provider='maintenance/rime-pime-dp1u-candidate-registration.psm1';runtime_provider='maintenance/rime-pime-dp1u-candidate-runtime.psm1';
        files=$rows;source_inventory_sha256=('a'*64);public_release_admitted=$false;installed_acceptance_passed=$false}
    Write-Bytes (Join-Path $bundle 'candidate.json') ($manifest|ConvertTo-Json -Depth 10 -Compress)
    $exe=Join-Path $root 'download\source.exe';Write-Bytes $exe 'inert never executed candidate'
    $approval=Join-Path $root 'approval\approval.json';Write-Bytes $approval '{}'
    $a=[pscustomobject]@{run_id=[guid]::NewGuid().ToString();install_root=(Join-Path $root 'installed');state_root=(Join-Path $root 'state');recovery_root=(Join-Path $root 'recovery');
        initiating_sid='S-1-5-21-1-2-3-1001';target_machine_id=[guid]::NewGuid().ToString();target_name='OWNED-FIXTURE';package_sha256=(Hash $exe)}
    $ctx=[pscustomobject]@{authorization=$a;approval_sha256=('a'*64);authorization_path=$approval;boundary_path=(Join-Path $root 'boundary.json')}
    [pscustomobject]@{root=$root;bundle=$bundle;hash=(Hash (Join-Path $bundle 'candidate.json'));installer=$exe;context=$ctx;
        events=[Collections.Generic.List[string]]::new();registration='absent';fail='';stop_count=0;start_count=0;resume_count=0;remove_count=0;ready_count=0;ticket=$null}
}
Check 'controller loads reader through its retained module without global imports' {
    $f=New-Fixture
    $count=& $module {
        param($r,$h)
        Initialize-CandidateMaintenance
        $candidate=Open-MaintenanceCandidate -PackageRoot $r -ExpectedManifestSha256 $h
        try{$candidate.files.Count}finally{Close-MaintenanceCandidate $candidate}
    } $f.bundle $f.hash
    Assert ($count -eq 10) 'Nested import lost the reader commands.'
}
# Every native product boundary below is replaced only inside this imported
# module instance. The reader, real file leases, journal, and exact removal run.
& $module {
    param($r)
    $script:CandidatePackageModule=$r
    function script:Initialize-CandidateMaintenance {}
    function script:Assert-CandidateTargetHost {}
    function script:Open-MaintenanceAuthorization {param($a,$h,$b) $script:fixture.context}
    function script:Close-MaintenanceAuthorization {param($c)}
    function script:Assert-MaintenanceInitiator {param($c,[switch]$RequireVacant)}
    function script:Open-MaintenanceVerifiedPackage {param($r,$h,$c,$i,$p) Open-MaintenanceCandidate -PackageRoot $r -ExpectedManifestSha256 $h}
    function script:Initialize-MaintenanceProviders {param($r)}
    function script:Start-MaintenancePeerProtection {param($c)
        $p=[pscustomobject]@{fixture=$true};$c|Add-Member -NotePropertyName peer_protection -NotePropertyValue $p -Force;return $p
    }
    function script:Assert-MaintenancePeerProtection {param($p)
        if($null -eq $p){throw 'fixture missing peer baseline'}
        if($script:fixture.fail -ceq 'Peer'){throw 'injected peer changed'}
    }
    function script:Complete-MaintenancePeerProtection {param($p) Assert-MaintenancePeerProtection $p}
    function script:Get-MaintenanceDefaultInput {[pscustomobject][ordered]@{override='fixture';first_language='fixture';first_tip='fixture'}}
    $script:CandidateCoordinatorModule=New-Module {
        function Open-RimePimeCandidateCoordinator {[pscustomobject]@{delegation_token='fixture-only'}}
        function Close-RimePimeCandidateCoordinator {param($Context)}
        function Get-RimePimeCandidateCoordinatorHandle {param($Context) [IntPtr]1}
        Export-ModuleMember -Function Open-RimePimeCandidateCoordinator,Close-RimePimeCandidateCoordinator,Get-RimePimeCandidateCoordinatorHandle
    }
    function script:Invoke-MaintenanceWorker {
        param($Action,$Context,$Ticket,$PackageRoot,$ExpectedManifestSha256,$InstallerPath,$ReceiptPath,$Coordinator)
        $script:fixture.ticket=$Ticket;$script:fixture.events.Add('worker-'+$Action)
        $opened=Read-MaintenancePreparedPlan $Context $Ticket.journal_root $Ticket.prepared_sha256
        try{Assert-MaintenanceWorkerDecision $opened $Action $Context}finally{$opened.store.Dispose()}
        if($script:fixture.fail -ceq $Action){throw ('injected '+$Action)}
        if($Action -eq 'Remove'){$script:fixture.registration='absent';$script:fixture.remove_count++}else{$script:fixture.registration='present'}
    }
    function script:Get-MaintenanceRegistration {param($c,$p,$r,$s)
        $script:fixture.events.Add('observe-'+$s)
        if($s -ceq 'Absent' -and $script:fixture.registration -cne 'absent'){throw 'mock registration remains'}
        [pscustomobject]@{expected=$s}
    }
    function script:Start-MaintenanceRuntime {param($p) $script:fixture.start_count++;$script:fixture.events.Add('runtime-start');[pscustomobject]@{fixture=$true}}
    function script:Resume-MaintenanceRuntime {param($p) $script:fixture.resume_count++;$script:fixture.events.Add('runtime-resume');[pscustomobject]@{fixture=$true}}
    function script:Test-MaintenanceRuntime {param($r) $script:fixture.ready_count++;if($script:fixture.fail -ceq 'Ready'){throw 'injected readiness'};[pscustomobject]@{ready=$true}}
    function script:Stop-MaintenanceRuntime {param($p,$r) $script:fixture.stop_count++;$script:fixture.events.Add('runtime-stop')}
} $reader
function Use-Fixture($Case){& $module {param($f) $script:fixture=$f} $Case}
function Invoke-Case($Case,[string]$Mode='Install',[string]$Prepared=''){
    Use-Fixture $Case
    $parameters=@{Mode=$Mode;PackageRoot=$Case.bundle;ExpectedManifestSha256=$Case.hash;InstallerPath=$Case.installer;
        AuthorizationPath=$Case.context.authorization_path;TrustedApprovalSha256=$Case.context.approval_sha256;
        BoundaryPath=$Case.context.boundary_path;ReceiptPath=(Join-Path $Case.root 'unused-receipt.json');PreparedSha256=$Prepared}
    Invoke-RimePimeCandidateMaintenance @parameters
}
function Open-Ticket($Case){& $module {param($f) Read-MaintenancePreparedPlan $f.context $f.ticket.journal_root $f.ticket.prepared_sha256} $Case}
Check 'fresh fixture stages complete payload and commits only after two ready observations' {
    $f=New-Fixture;$result=Invoke-Case $f
    Assert ($result.disposition -ceq 'install-complete' -and $f.ready_count -eq 2) 'Install not completed in correct sequence.'
    Assert (-not $result.installed_acceptance_passed -and -not $result.dp1_u_acceptance_passed -and -not $result.public_release_admitted) 'Overstated completion.'
    foreach($n in @('Roaming','Local')){Assert (Test-Path (Join-Path $f.context.authorization.state_root $n)) 'Runtime state directory missing.'}
    $ticket=Join-Path (Split-Path $f.context.authorization_path) ('candidate-recovery-'+$f.context.authorization.run_id+'.json')
    Assert ((Get-Content $ticket -Raw|ConvertFrom-Json).prepared_sha256 -ceq $f.ticket.prepared_sha256) 'Original digest not independently exported.'
    Assert (($f.events -join ',') -match 'worker-Register,observe-Partial,runtime-start,worker-PublishMarkers,observe-Present') 'Registration/readiness sequence changed.'
}
Check 'peer drift prevents install completion and preserves recovery evidence' {
    $f=New-Fixture;$f.fail='Peer';Reject {Invoke-Case $f} 'peer changed'
    Assert ($f.start_count -eq 0) 'Peer drift allowed Runtime startup.'
    $opened=Open-Ticket $f
    try{Assert (-not $opened.store.Has('terminal.bin')) 'Peer drift was reported as successful completion.'}finally{$opened.store.Dispose()}
}
Check 'registration failure durably rolls back without starting Runtime' {
    $f=New-Fixture;$f.fail='Register';Reject {Invoke-Case $f} 'rolled back'
    Assert ($f.start_count -eq 0 -and $f.remove_count -eq 1) 'Failed registration started Runtime or missed cleanup.'
    $opened=Open-Ticket $f;try{$d=& $module {param($t) Get-MaintenanceDecision $t.store 'terminal.bin' $t.prepared_sha256 @('rolled-back')} $opened;Assert ($d.disposition -ceq 'rolled-back') 'Rollback terminal missing.'}finally{$opened.store.Dispose()}
}
Check 'native readiness failure removes registration and exact owned files' {
    $f=New-Fixture;$f.fail='Ready';Reject {Invoke-Case $f} 'rolled back'
    Assert ($f.stop_count -eq 1 -and $f.remove_count -eq 1) 'Readiness failure did not quiesce and unregister.'
    Assert (-not (Test-Path (Join-Path $f.context.authorization.install_root 'PIMELauncher.exe'))) 'Owned payload remained.'
}
Check 'committed resume observes existing Runtime without registration replay' {
    $f=New-Fixture;$null=Invoke-Case $f;$before=$f.events.Count
    $r=Invoke-Case $f 'Resume' $f.ticket.prepared_sha256
    Assert ($f.start_count -eq 1 -and $f.resume_count -eq 1 -and $f.remove_count -eq 0) 'Resume replayed start or removal.'
}
Check 'durable removal takes priority over older install commit after interruption' {
    $f=New-Fixture;$null=Invoke-Case $f
    & $module {param($t) Request-MaintenanceRemoval $t} $f.ticket
    $r=Invoke-Case $f 'Resume' $f.ticket.prepared_sha256
    Assert ($r.disposition -ceq 'remove-complete' -and $f.resume_count -eq 0 -and $f.remove_count -eq 1) 'Removal resumed as installation.'
}
Check 'uninstall preserves foreign files state directories and recovery executable' {
    $f=New-Fixture;$null=Invoke-Case $f
    $foreign=Join-Path $f.context.authorization.install_root 'foreign.txt';Write-Bytes $foreign 'keep'
    $learning=Join-Path $f.context.authorization.state_root 'Roaming\owned-fixture-learning.txt';Write-Bytes $learning 'keep-learning'
    $r=Invoke-Case $f 'Remove' $f.ticket.prepared_sha256
    Assert ((Get-Content $foreign -Raw) -ceq 'keep' -and (Get-Content $learning -Raw) -ceq 'keep-learning') 'Foreign or state bytes changed.'
    Assert (Test-Path (Join-Path $f.context.authorization.recovery_root 'maintenance-candidate.exe')) 'Recovery executable removed.'
}
Check 'new approval run reuses same one-way removal history' {
    $f=New-Fixture;$null=Invoke-Case $f;& $module {param($t) Request-MaintenanceRemoval $t} $f.ticket
    $f.context.authorization.run_id=[guid]::NewGuid().ToString();$f.context.approval_sha256='b'*64
    $r=Invoke-Case $f 'Resume' $f.ticket.prepared_sha256
    Assert ($r.disposition -ceq 'remove-complete' -and @(Get-ChildItem $f.context.authorization.recovery_root -Filter 'remove-*' -Directory).Count -eq 1) 'Removal split across approval histories.'
}
Check 'changed installed member is retained and no removal terminal published' {
    $f=New-Fixture;$null=Invoke-Case $f;$file=Join-Path $f.context.authorization.install_root 'PIMELauncher.exe';[IO.File]::AppendAllText($file,'foreign')
    Reject {Invoke-Case $f 'Remove' $f.ticket.prepared_sha256} 'changed; retained'
    Assert ((Get-Content $file -Raw).EndsWith('foreign')) 'Changed member was deleted.'
    $rm=& $module {param($t) Open-MaintenanceRemoval $t} $f.ticket;try{Assert (-not $rm.terminal) 'Premature removal completion.'}finally{$rm.store.Dispose()}
}
Check 'partial exact deletion resumes from observed absence without restarting Runtime' {
    $f=New-Fixture;$null=Invoke-Case $f;& $module {param($t) Request-MaintenanceRemoval $t} $f.ticket
    $f.registration='absent';$row=@($f.ticket.plan.files|Where-Object path -CEQ 'PIMELauncher.exe')[0]
    & $reader {param($r,$f) Remove-CandidateExactFiles $r @($f)} $f.ticket.plan.install_root $row | Out-Null
    $r=Invoke-Case $f 'Resume' $f.ticket.prepared_sha256
    Assert ($r.disposition -ceq 'remove-complete' -and $f.resume_count -eq 0) 'Partial deletion cannot resume.'
    $again=Invoke-Case $f 'Resume' $f.ticket.prepared_sha256
    Assert ($again.disposition -ceq 'remove-complete') 'Completed removal not idempotent.'
}
Check 'wrong external prepared digest refuses all product actions' {
    $f=New-Fixture;$null=Invoke-Case $f;$count=$f.events.Count
    Reject {Invoke-Case $f 'Remove' ('0'*64)} 'external prepared digest'
    Assert ($count -eq $f.events.Count) 'Product action preceded external binding.'
}
Check 'malformed removal journal prevents committed Runtime restart' {
    $f=New-Fixture;$null=Invoke-Case $f;& $module {param($t) Request-MaintenanceRemoval $t} $f.ticket
    $record=Join-Path $f.ticket.plan.recovery_root ('remove-'+$f.ticket.plan.run_id+'\commit.bin');[IO.File]::WriteAllText($record,'invalid')
    Reject {Invoke-Case $f 'Resume' $f.ticket.prepared_sha256} 'frame|record|header|truncated|Invalid|invalid'
    Assert ($f.resume_count -eq 0) 'Malformed history restarted Runtime.'
}
Check 'worker refuses removal without durable intent and registration after commit' {
    $f=New-Fixture;$null=Invoke-Case $f;$opened=Open-Ticket $f
    try{
        Reject {& $module {param($t,$c) Assert-MaintenanceWorkerDecision $t 'Remove' $c} $opened $f.context} 'durable removal decision'
        Reject {& $module {param($t,$c) Assert-MaintenanceWorkerDecision $t 'Register' $c} $opened $f.context} 'cannot replay'
    }finally{$opened.store.Dispose()}
}
$result=[ordered]@{schema_version='yime-rime-pime-candidate-maintenance-test-v1';passed=$true;powershell_version=$PSVersionTable.PSVersion.ToString();checks=@($checks.ToArray());
    real_file_journal_and_exact_removal_used=$true;registration_and_runtime_providers_mocked=$true;installer_executed=$false;product_runtime_started=$false;
    production_registration_modified=$false;installed_local12_touched=$false;dp1_u_acceptance_passed=$false}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'result.json'),($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host ('PASS '+$checks.Count+' candidate maintenance checks: '+$OutputRoot)
