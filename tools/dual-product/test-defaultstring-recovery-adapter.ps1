$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
& $module {
    # Simulate a module-defined worker calling the provider initializer after
    # the recovery entry injects its reviewed adapter in the invocation scope.
    function script:Test-AdapterDispatch {Initialize-MaintenanceProviders 'Z:\nonexistent-original-payload'}
    try{
        . (Join-Path $PSScriptRoot 'defaultstring-recovery-adapter.ps1')
        Test-AdapterDispatch
        if($script:CandidateRegistrationModule.Path -ine (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration.psm1')){throw 'Original payload provider was selected.'}
        if($script:CandidateRuntimeModule.Path -ine (Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-runtime.psm1')){throw 'Original runtime provider was selected.'}
        $rejected=$false
        try{Invoke-MaintenanceWorker -Action Register -Ticket ([pscustomobject]@{plan=[pscustomobject]@{run_id='wrong'}})}catch{$rejected=$true}
        if(-not $rejected){throw 'Adapter admitted registration.'}
    }finally{Remove-Item Function:Test-AdapterDispatch}
}
Write-Output 'PASS: module worker selects reviewed providers; registration dispatch rejected before process launch.'
