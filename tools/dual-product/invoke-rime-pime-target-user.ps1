[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('CaptureInitiator','CreateEnvelope','ValidateWorker')]
    [string]$Action,
    [string]$TargetUserSid,
    [string]$InitiatingSid,
    [string]$EnvelopePath,
    [string]$CorrelationId
)

$ErrorActionPreference='Stop'
$contract=Join-Path $PSScriptRoot 'rime-pime-target-user.ps1'
if(-not (Test-Path -LiteralPath $contract -PathType Leaf)){throw 'Rime/PIME target-user contract is unavailable.'}
. $contract
$current=Get-YimePimeCurrentTokenObservation

switch($Action){
    'CaptureInitiator' {
        Assert-YimePimeUnpackagedExplorerInitiator | Out-Null
        if($current.elevated){throw 'Capture the initiating SID before requesting elevation.'}
        [Console]::Out.Write([string]$current.sid)
    }
    'CreateEnvelope' {
        Assert-YimePimeUnpackagedExplorerInitiator | Out-Null
        if($current.elevated){throw 'Create the elevation envelope before requesting elevation.'}
        if([string]::IsNullOrWhiteSpace($TargetUserSid) -or [string]::IsNullOrWhiteSpace($InitiatingSid) -or
            [string]::IsNullOrWhiteSpace($EnvelopePath)){throw 'Creating an elevation envelope requires its path and explicit SIDs.'}
        if($current.sid -cne $InitiatingSid){throw 'Current token differs from the declared initiating SID.'}
        $record=New-YimePimeElevationEnvelopeFile $EnvelopePath $InitiatingSid $TargetUserSid
        [Console]::Out.Write([string]$record.correlation_id)
    }
    'ValidateWorker' {
        if([string]::IsNullOrWhiteSpace($TargetUserSid) -or [string]::IsNullOrWhiteSpace($InitiatingSid) -or
            [string]::IsNullOrWhiteSpace($EnvelopePath) -or [string]::IsNullOrWhiteSpace($CorrelationId)){
            throw 'The elevated worker requires explicit initiating/target SIDs and one-time correlation identity.'
        }
        $envelope=Confirm-YimePimeElevationEnvelopeFile -Path $EnvelopePath -CorrelationId $CorrelationId `
            -WorkerSid $current.sid -WorkerTokenElevated:$current.elevated -Consume
        if($envelope.initiating_sid -cne $InitiatingSid -or $envelope.target_user_sid -cne $TargetUserSid){
            throw 'The one-time elevation envelope differs from worker command parameters.'
        }
        [Console]::Out.Write([string]$envelope.target_user_sid)
    }
}
