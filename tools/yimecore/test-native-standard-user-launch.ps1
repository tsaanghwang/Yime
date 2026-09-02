[CmdletBinding()]
param(
    [string]$StandardUserInitiator,
    [string]$EvidenceRoot,
    [string]$ExpectedSourcesHash
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-token-diagnostics.ps1')
$null=Get-YimeCoreDevelopmentScope
Assert-YimeCoreUnpackagedDataMaintenance
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -ne 'S-1-5-21-2783006668-770716121-2150155084-1001'){throw 'Use the initiating Windows account; do not switch administrator accounts.'}
$administrator=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$files=@('test-native-standard-user-launch.ps1','local-runtime-launcher.cs','development-scope.ps1','local-maintenance-safety.ps1','local-token-diagnostics.ps1')
$sources=@($files|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_)).Hash.ToLowerInvariant()}})
$digest=[Security.Cryptography.SHA256]::Create()
try {$sourceHash=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sources|ConvertTo-Json -Compress))))).Replace('-','').ToLowerInvariant()}
finally {$digest.Dispose()}
$archiveBase=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'
trap {
    $bootstrapError=$_
    # A hidden UAC worker must not lose preflight errors. Context protection has
    # already passed; only write inside an existing, exact native-probe archive.
    try {
        if($StandardUserInitiator -and $EvidenceRoot) {
            $failureRoot=[IO.Path]::GetFullPath($EvidenceRoot)
            Assert-YimeCorePlainPath $failureRoot
            if((Split-Path -Parent $failureRoot) -ieq $archiveBase -and
                (Split-Path -Leaf $failureRoot) -match '^native-launch-fix-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$' -and
                (Test-Path -LiteralPath (Join-Path $failureRoot 'initiator.json'))) {
                [ordered]@{stage='worker-bootstrap';exception_chain=@(Get-YimeCoreExceptionEvidence $bootstrapError.Exception)}|
                    ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $failureRoot 'worker-bootstrap-failure.json') -Encoding UTF8
            }
        }
    } catch {}
    Write-Error $bootstrapError -ErrorAction Continue
    exit 1
}
$package='C:\dev\Yime\.tmp\yimecore-local-product\20260903-000638-13644db3\package'
$manifestHash='6bb1c10d24228c436ce6e77b4063c36bcc786fd5cabaa38a8efd690941e10e9d'
function Write-ProbeJson($Value,[string]$Name){$Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceRoot $Name) -Encoding UTF8}
function Get-VerifiedProbeAudit {
    if((Get-FileHash -LiteralPath (Join-Path $package 'package-manifest.json')).Hash -ine $manifestHash){throw 'Frozen audit package manifest changed.'}
    $manifest=Get-Content -LiteralPath (Join-Path $package 'package-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $audit=Join-Path $package 'bin\YimeCoreIndependenceAudit.exe'
    $record=@($manifest.files|Where-Object{$_.path -ceq 'bin/YimeCoreIndependenceAudit.exe'})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $audit).Hash -ine $record[0].sha256){throw 'Audit executable does not match the frozen manifest.'}
    return $audit
}

if(-not $StandardUserInitiator) {
    if($EvidenceRoot -or $ExpectedSourcesHash){throw 'Internal worker arguments require an explicit retained initiator.'}
    if($administrator){throw 'Start this probe from ordinary Windows PowerShell, NOT administrator. It will request UAC itself and retain the original standard-user process. No input method was stopped or installed.'}
    Add-Type -Path (Join-Path $PSScriptRoot 'local-runtime-launcher.cs')
    $reference=[YimeCore.LocalMaintenance.StandardUserLauncher]::CaptureInitiatorReference($sid)
    $EvidenceRoot=Join-Path $archiveBase ('native-launch-fix-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    Assert-YimeCorePlainPath $EvidenceRoot
    if(Test-Path -LiteralPath $EvidenceRoot){throw 'Probe evidence directory must be new.'}
    New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
    Write-ProbeJson ([ordered]@{initiator=$reference;sid=$sid;sources=$sources;source_set_sha256=$sourceHash}) 'initiator.json'
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -StandardUserInitiator "'+$reference+'" -EvidenceRoot "'+$EvidenceRoot+'" -ExpectedSourcesHash "'+$sourceHash+'"'
    $worker=$null
    $parentStage='ordinary-audit-baseline'
    try {
        # Prove native ordinary execution of the SAME pinned image and directory
        # before UAC; a failure here is not a cross-token launch failure.
        $audit=Get-VerifiedProbeAudit
        $ordinaryOutput=Join-Path $EvidenceRoot 'ordinary-audit.json'
        $ordinary=$null
        try {
            $ordinary=[YimeCore.LocalMaintenance.StandardUserLauncher]::Start($audit,('-package "'+$package+'" -output "'+$ordinaryOutput+'"'),$package,$sid)
            if(-not $ordinary.WaitForExit(20000) -or $ordinary.ExitCode -ne 0){throw 'Native ordinary audit baseline failed or timed out.'}
            $baseline=Get-Content -LiteralPath $ordinaryOutput -Raw -Encoding UTF8|ConvertFrom-Json
            if(-not $baseline.passed -or $baseline.manifest_sha256 -ine $manifestHash){throw 'Ordinary audit baseline did not verify the pinned package.'}
            $null=Assert-YimeCoreNativeFile $ordinaryOutput
            Write-ProbeJson ([ordered]@{passed=$true;launch_attempt=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt}) 'ordinary-baseline.json'
        } finally {
            if($ordinary){try{if(-not $ordinary.HasExited){$ordinary.Kill()}}finally{$ordinary.Dispose()}}
        }
        $parentStage='uac-worker'
        # Native user-started context only. Keep this exact ordinary process
        # alive while UAC/worker uses its primary token; do not use Explorer's.
        $worker=Start-Process -FilePath $ps -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $worker.WaitForExit()
        $summaryPath=Join-Path $EvidenceRoot 'summary.json'
        if(Test-Path -LiteralPath $summaryPath) {
            $summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json
            if($worker.ExitCode -eq 0 -and $summary.passed -and $summary.source_set_sha256 -eq $sourceHash) {
                $null=Assert-YimeCoreNativeFile $summaryPath
                Write-Host "PASS: native same-user standard-primary launch; no stop, backup, install or reboot. Evidence: $EvidenceRoot"
                exit 0
            }
            Write-Host "BLOCKED: $($summary.stage); $($summary.failure|ConvertTo-Json -Depth 8 -Compress). Evidence: $EvidenceRoot"
        } else {
            $bootstrapFailure=Join-Path $EvidenceRoot 'worker-bootstrap-failure.json'
            if(Test-Path -LiteralPath $bootstrapFailure){Write-Host (Get-Content -LiteralPath $bootstrapFailure -Raw -Encoding UTF8)}
            Write-Host "BLOCKED: elevated probe exited $($worker.ExitCode) without a summary. Preserve: $EvidenceRoot"
        }
        exit 1
    } catch {
        Write-ProbeJson ([ordered]@{stage=$parentStage;exception_chain=@(Get-YimeCoreExceptionEvidence $_.Exception);
            launch_attempt=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt}) 'parent-failure.json'
        throw
    } finally {if($worker){$worker.Dispose()}}
}

# Elevated half, never an installer. The same account, source snapshot, native
# ancestry and exact retained process must be verified before launching anything.
if(-not $administrator){throw 'Worker requires the same-account UAC elevation.'}
if(-not $ExpectedSourcesHash -or $ExpectedSourcesHash -cne $sourceHash){throw 'Probe sources changed across UAC; restart from ordinary PowerShell.'}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot)
if((Split-Path -Parent $EvidenceRoot) -ine $archiveBase -or (Split-Path -Leaf $EvidenceRoot) -notmatch '^native-launch-fix-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'Unexpected probe evidence path.'}
Assert-YimeCorePlainPath $EvidenceRoot
if(-not (Test-Path -LiteralPath (Join-Path $EvidenceRoot 'initiator.json'))){throw 'Missing initiating process record.'}
if(Test-Path -LiteralPath (Join-Path $EvidenceRoot 'summary.json')){throw 'Do not reuse a completed probe directory.'}
$origin=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'initiator.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($origin.initiator -cne $StandardUserInitiator -or $origin.sid -cne $sid -or $origin.source_set_sha256 -cne $sourceHash){throw 'Initiator record does not match this worker.'}
$env:YIMECORE_MAINTENANCE_INITIATOR=$StandardUserInitiator
$stage='validate-native-initiator';$passed=$false;$failure=$null;$probe=$null;$token=$null;$childToken=$null
try {
    Assert-YimeCoreMaintenanceInitiator
    Add-Type -Path (Join-Path $PSScriptRoot 'local-runtime-launcher.cs')
    $token=[YimeCore.LocalMaintenance.StandardUserLauncher]::ValidateLaunchToken($sid)
    Write-ProbeJson ([ordered]@{initiator_reference=$StandardUserInitiator;standard_primary_token=$token;worker_tokens=(Get-YimeCoreLaunchTokenDiagnostics);sources=$sources}) 'token-evidence.json'
    $stage='verify-audit-payload'
    $audit=Get-VerifiedProbeAudit
    $stage='standard-primary-launch'
    $probeOutput=Join-Path $EvidenceRoot 'audit.json'
    $probe=[YimeCore.LocalMaintenance.StandardUserLauncher]::Start($audit,('-package "'+$package+'" -output "'+$probeOutput+'"'),$package,$sid)
    # Captured on the retained child handle while suspended inside Start; do not
    # reopen a PID that a short-lived audit could already have exited/reused.
    $childToken=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt.ChildToken
    if(-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardPrimaryToken($childToken,$sid,(Get-Process -Id $PID).SessionId)){throw 'Actual audit process was not the expected standard primary user.'}
    if(-not $probe.WaitForExit(20000) -or $probe.ExitCode -ne 0){throw 'Read-only audit probe failed or timed out.'}
    $result=Get-Content -LiteralPath $probeOutput -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $result.passed -or $result.manifest_sha256 -ine $manifestHash){throw 'Audit probe did not validate the pinned package.'}
    $null=Assert-YimeCoreNativeFile $probeOutput
    $stage='native-standard-primary-launch-passed';$passed=$true
} catch {
    $failure=@(Get-YimeCoreExceptionEvidence $_.Exception)
} finally {
    if($probe){try{if(-not $probe.HasExited){$probe.Kill()}}finally{$probe.Dispose()}}
    Write-ProbeJson ([ordered]@{schema_version='yimecore-native-launch-fix-probe-v1';passed=$passed;stage=$stage;failure=$failure;
        source_set_sha256=$sourceHash;candidate_manifest_sha256=$manifestHash;initiator_reference=$StandardUserInitiator;
        source_token=$token;actual_child_token=$childToken;actual_install_executed=$false;old_runtime_stopped=$false;
        launch_attempt=[YimeCore.LocalMaintenance.StandardUserLauncher]::LastLaunchAttempt;
        backup_restore_executed=$false;reboot_requested=$false;local_product_ready=$false}) 'summary.json'
}
if(-not $passed){exit 1}
