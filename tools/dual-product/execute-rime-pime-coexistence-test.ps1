[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install','Remove','Resume')][string]$Mode,
    [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$ExpectedInstallerSha256,
    [Parameter(Mandatory)][string]$AuthorizationPath,[Parameter(Mandatory)][string]$TrustedApprovalSha256,
    [Parameter(Mandatory)][string]$BoundaryPath,[Parameter(Mandatory)][string]$ReceiptPath,[string]$PreparedSha256)
$ErrorActionPreference='Stop'
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Identified test PC only.'}
if((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedInstallerSha256){throw 'Candidate hash changed.'}
$legacyTransport=$Mode -ceq 'Resume' -and $ExpectedInstallerSha256 -ceq '0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617'
if($legacyTransport){
    Import-Module (Join-Path $PSScriptRoot 'legacy-resume-transport.psm1')
    $length=Get-LegacyResumeCommandBound ([pscustomobject]$PSBoundParameters) ([IO.Path]::GetTempPath()) $env:SystemRoot
    if($length -gt 1000){throw 'Legacy NSIS command would risk truncation. Prepare byte-identical short-path transport first.'}
    $stageRoot=[IO.Path]::GetDirectoryName($InstallerPath)
    if([IO.Path]::GetDirectoryName($stageRoot) -ine $env:USERPROFILE -or [IO.Path]::GetFileName($stageRoot) -cnotmatch '^YRP-[a-f0-9]{12}$' -or
        [IO.Path]::GetFileName($InstallerPath) -cne 'p.exe' -or $ReceiptPath -cne (Join-Path $stageRoot 'r.json')){throw 'Prepared short transport required for original Resume.'}
}
$argsList=@(('/Mode='+$Mode),('/AuthorizationPath="'+$AuthorizationPath+'"'),('/TrustedApprovalSha256='+$TrustedApprovalSha256),
    ('/BoundaryPath="'+$BoundaryPath+'"'),('/ReceiptPath="'+$ReceiptPath+'"'))
if($PreparedSha256){$argsList+=('/PreparedSha256='+$PreparedSha256)}
foreach($path in @($InstallerPath,$AuthorizationPath,$BoundaryPath,$ReceiptPath)){
    if($path -match '["\r\n\t]' -or $path.EndsWith('\')){throw 'Ambiguous candidate argument.'}
}
if($legacyTransport){
    $marker=[IO.File]::Open((Join-Path $stageRoot 'resume-started'),'CreateNew','Write','None')
    try{$marker.WriteByte(1);$marker.Flush($true)}finally{$marker.Dispose()}
}
$process=Start-Process -FilePath $InstallerPath -ArgumentList $argsList -PassThru -Wait -WindowStyle Hidden
try{if($process.ExitCode -ne 0){throw ('Candidate failed with exit code '+$process.ExitCode+'; retain all evidence and recovery tickets.')}}finally{$process.Dispose()}
Write-Host 'Candidate operation returned success. Native coexistence and live-host acceptance still require the handoff checklist.'
