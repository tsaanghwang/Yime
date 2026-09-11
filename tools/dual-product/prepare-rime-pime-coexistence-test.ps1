[CmdletBinding()]
param([Parameter(Mandatory)][string]$DeliveryRoot,
    [Parameter(Mandatory)][string]$ExpectedIndexSha256,
    [ValidateSet('Install','Remove','Resume')][string]$Mode='Install',
    [string]$RecoveryTicketPath)
# Materialize the user's 2026-09-11 test instruction for the identified test PC.
# Preparation is read-only for both products; execution is a separate command.
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$target=-join @([char]0x8ba1,[char]0x7b97,[char]0x673a)
if([Environment]::MachineName -cne $target){throw 'This handoff is bound to the identified test PC only.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
& python (Join-Path $PSScriptRoot 'verify_delivery.py') $DeliveryRoot --expected-index-sha256 $ExpectedIndexSha256
if($LASTEXITCODE -ne 0){throw 'Delivery integrity verification failed.'}
$index=Get-Content -LiteralPath (Join-Path $DeliveryRoot 'delivery-index.json') -Raw -Encoding UTF8|ConvertFrom-Json
$manifest=Get-Content -LiteralPath (Join-Path $DeliveryRoot $index.artifacts.manifest.path) -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.schema_version -cne 'yime-rime-pime-executable-candidate-v2' -or $manifest.installation_scope -cne 'approved-isolated-x64-current-peer-protected'){throw 'Use the new peer-protected candidate, not the historical clean-only package.'}
$probe=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -PassThru
& $probe {Initialize-Dp1UNativeFacts}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$machine=& $probe {Invoke-Dp1UNativeRegistryRead GetStringValue 2147483650 'SOFTWARE\Microsoft\Cryptography' 'MachineGuid' 64}
if($machine.ReturnValue -ne 0){throw 'System-visible machine identity unavailable.'}
# Establish native context before opening peer settings. Remove/Resume use the
# same ancestry gate without requiring the already installed target to be absent.
$maintenance=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
$context=[pscustomobject]@{authorization=[pscustomobject]@{initiating_sid=$sid;target_machine_id=$machine.sValue};probe=$probe}
& $maintenance {param($c,$vacant) Assert-MaintenanceInitiator $c -RequireVacant:$vacant} $context ($Mode -ceq 'Install')
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$run=[guid]::NewGuid().ToString();$base=Join-Path $env:USERPROFILE 'Yime Rime-PIME Test Archives'
$output=Join-Path $base ('approval-'+$run)
& $maintenance {param($r) Assert-MaintenanceRecoveryRoot $r} $output
$installRoot=Join-Path $base ('product-'+$run);$stateRoot=Join-Path $base ('state-'+$run);$recoveryRoot=Join-Path $base ('recovery-'+$run)
$prepared=''
if($Mode -cne 'Install'){
    if(-not $RecoveryTicketPath){throw 'Remove/Resume needs the original independently retained recovery ticket.'}
    $ticket=Get-Content -LiteralPath $RecoveryTicketPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($ticket.schema_version -cne 'yime-rime-pime-candidate-recovery-ticket-v1' -or $ticket.package_sha256 -cne $index.artifacts.installer.sha256){throw 'Recovery ticket is for another candidate.'}
    # Original approval is beside the ticket; never infer a prepared digest from
    # a mutable journal. The controller independently authenticates that journal.
    $old=Get-Content -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($RecoveryTicketPath)) 'authorization.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $installRoot=$old.install_root;$stateRoot=$old.state_root;$recoveryRoot=$old.recovery_root;$prepared=$ticket.prepared_sha256
}
$b=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1u-product-boundary-v1';install_root=$installRoot;state_root=$stateRoot;recovery_root=$recoveryRoot;
    peer_install_root=[string]$config.install_root;peer_state_root=$state;peer_recovery_root=(Join-Path $env:USERPROFILE 'YimeCore Recovery Archives');
    production_install_root=(Join-Path ${env:ProgramFiles(x86)} 'YIME');production_state_root=(Join-Path $env:APPDATA 'PIME');
    clsid='{35f67e9d-a54d-4177-9697-8b0ab71a9e04}';profile_guid='{3f6b5a12-8d44-4e71-9a2e-6b4f9c1d2a30}';
    peer_clsid='{e40fa752-bb96-461d-a51d-f40eb437ec65}';peer_profile_guid='{126f54c6-e9b1-4e22-8652-03224cbd49f9}';
    runtime_endpoint='PIME';peer_runtime_endpoint='YimeBroker.YimeCoreTrial.v1';run_value_name='PIMELauncher';peer_run_value_name='YimeCoreExperimentalTrial';
    uninstall_key_name='YIME';peer_uninstall_key_name='YimeCoreExperimentalTrial'
}
$schema=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.schema.json') -Raw -Encoding UTF8|ConvertFrom-Json
$boundaryHash=& $probe {param($v,$s) Get-Dp1UNativeObjectDigest $v $s 'dp1u-product-boundary-v1'} $b $schema.properties.product_boundary
$now=[DateTime]::UtcNow
$a=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1u-isolated-authorization-v1';approval_reference='user-thread-2026-09-11-current-peer-coexistence-installation-test';approved_by=$sid;
    approved_at_utc=$now.ToString('yyyy-MM-ddTHH:mm:ssZ');expires_at_utc=$now.AddHours(24).ToString('yyyy-MM-ddTHH:mm:ssZ');run_id=$run;
    target_name=$target;target_machine_id=$machine.sValue.ToLowerInvariant();initiating_sid=$sid;state_root=$stateRoot;install_root=$installRoot;recovery_root=$recoveryRoot;
    package_sha256=$index.artifacts.installer.sha256;canonical_receipt_sha256=$index.artifacts.receipt.sha256;product_boundary_sha256=$boundaryHash;
    affected_product='rime-pime';target_class='isolated-mainstream-windows-x64';package_architectures='x86,x64';operations='registration,rollback,removal,runtime';
    production_rime_pime_allowed=$false;yimecore_local12_allowed=$false;default_input_method_mutation_allowed=$false;production_user_data_allowed=$false;
    cross_product_mutation_allowed=$false;historical_payload_execution_allowed=$false;shared_runtime_or_state_allowed=$false
}
$approvalHash=& $probe {param($v,$s) Get-Dp1UNativeObjectDigest $v $s 'dp1u-authorization-v1'} $a $schema.properties.authorization
& $probe {param($a,$b,$h) Assert-Dp1UNativeRequest $a $b $h ([Environment]::MachineName) ([DateTime]::UtcNow)} $a $b $approvalHash
Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1')
$peer=Get-RimePimePeerProtectionSnapshot $b $sid
if(-not $peer.peer_present){throw 'This acceptance row requires the existing YimeCore peer.'}
if((Test-Path -LiteralPath $b.production_install_root) -or (Test-Path -LiteralPath $b.production_state_root)){throw 'Existing production Rime/PIME files are outside this initial-install test.'}
$null=[IO.Directory]::CreateDirectory($output)
function Save([string]$Name,$Value){& $maintenance {param($p,$v) Write-MaintenancePeerEvidence $p $v} (Join-Path $output $Name) $Value}
Save 'authorization.json' $a;Save 'boundary.json' $b;Save 'peer-preflight.json' $peer
$parameters=[ordered]@{Mode=$Mode;InstallerPath=([IO.Path]::GetFullPath((Join-Path $DeliveryRoot $index.artifacts.installer.path)));
    ExpectedInstallerSha256=$a.package_sha256;AuthorizationPath=(Join-Path $output 'authorization.json');TrustedApprovalSha256=$approvalHash;
    BoundaryPath=(Join-Path $output 'boundary.json');ReceiptPath=([IO.Path]::GetFullPath((Join-Path $DeliveryRoot $index.artifacts.receipt.path)));PreparedSha256=$prepared}
Save 'execute-parameters.json' $parameters
Write-Host ('Prepared only. Execution parameters: '+(Join-Path $output 'execute-parameters.json'))
Write-Host 'Retain this directory outside Git. Product mutation has not been performed.'
