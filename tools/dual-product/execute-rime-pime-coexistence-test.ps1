[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install','Remove','Resume')][string]$Mode,
    [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$ExpectedInstallerSha256,
    [Parameter(Mandatory)][string]$AuthorizationPath,[Parameter(Mandatory)][string]$TrustedApprovalSha256,
    [Parameter(Mandatory)][string]$BoundaryPath,[Parameter(Mandatory)][string]$ReceiptPath,[string]$PreparedSha256)
$ErrorActionPreference='Stop'
if([Environment]::MachineName -cne (-join @([char]0x8ba1,[char]0x7b97,[char]0x673a))){throw 'Identified test PC only.'}
if((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedInstallerSha256){throw 'Candidate hash changed.'}
$argsList=@(('/Mode='+$Mode),('/AuthorizationPath="'+$AuthorizationPath+'"'),('/TrustedApprovalSha256='+$TrustedApprovalSha256),
    ('/BoundaryPath="'+$BoundaryPath+'"'),('/ReceiptPath="'+$ReceiptPath+'"'))
if($PreparedSha256){$argsList+=('/PreparedSha256='+$PreparedSha256)}
foreach($path in @($InstallerPath,$AuthorizationPath,$BoundaryPath,$ReceiptPath)){
    if($path -match '["\r\n\t]' -or $path.EndsWith('\')){throw 'Ambiguous candidate argument.'}
}
$process=Start-Process -FilePath $InstallerPath -ArgumentList $argsList -PassThru -Wait -WindowStyle Hidden
try{if($process.ExitCode -ne 0){throw ('Candidate failed with exit code '+$process.ExitCode+'; retain all evidence and recovery tickets.')}}finally{$process.Dispose()}
Write-Host 'Candidate operation returned success. Native coexistence and live-host acceptance still require the handoff checklist.'
