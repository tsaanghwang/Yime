[CmdletBinding()]
param([switch]$Execute,[switch]$Worker,[string]$InitiatorReference,[string]$EvidenceRoot)
$ErrorActionPreference='Stop'
$expectedManifest='324e46fc5c930d79de713b1fe8d4a0c7cefa884c88b25721dec50cb3c2ed4431'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$root=[IO.Path]::GetFullPath([string]$config.install_root)
if((Get-FileHash -LiteralPath (Join-Path $root 'package-manifest.json')).Hash -ine $expectedManifest){throw 'Current installation is not the reviewed local.4 package.'}
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1','local-product-runtime.ps1')){. (Join-Path $root "maintenance\$name")}
$null=Get-YimeCoreDevelopmentScope
$context=Assert-LocalProductInstalledContext $root $state
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Wrong initiating user.'}
$admin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $Execute){[ordered]@{action='detached-start-plan';writes_requested=$false;install_root=$root;manifest=$expectedManifest}|ConvertTo-Json;exit 0}
Assert-YimeCoreUnpackagedDataMaintenance
if(-not $Worker){
    Initialize-LocalProductLauncher $context
    $reference=[YimeCore.LocalMaintenance.StandardUserLauncher]::CaptureInitiatorReference($expectedSid)
    $EvidenceRoot=Join-Path $env:USERPROFILE ('YimeCore Recovery Archives\local4-detached-start-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Execute -Worker -InitiatorReference "'+$reference+'" -EvidenceRoot "'+$EvidenceRoot+'"'
    $p=Start-Process -FilePath $ps -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru;$p.WaitForExit();$code=$p.ExitCode;$p.Dispose()
    if($code -ne 0){throw "Detached start failed (exit $code): $EvidenceRoot"}
    $live=Assert-LocalProductLiveRuntime $context
    [ordered]@{passed=$true;manifest=$expectedManifest;live=$live}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceRoot 'parent-summary.json') -Encoding UTF8
    Write-Host "PASS: installed local.4 runtime is detached and live. Evidence: $EvidenceRoot";exit 0
}
if(-not $admin -or -not $InitiatorReference -or -not $EvidenceRoot){throw 'Incomplete detached-start worker.'}
$env:YIMECORE_MAINTENANCE_INITIATOR=$InitiatorReference
Assert-YimeCoreMaintenanceInitiator
$existing=Get-YimeCoreLiveRuntimeEvidence $state
$live=if($existing.passed){Assert-LocalProductLiveRuntime $context}else{
    if(Get-Process YimeCoreTrialRuntime,YimeBroker -ErrorAction SilentlyContinue){throw 'Unverified runtime process exists.'}
    Start-LocalProductRuntime $context
}
[ordered]@{passed=$true;manifest=$expectedManifest;live=$live}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceRoot 'worker-summary.json') -Encoding UTF8
