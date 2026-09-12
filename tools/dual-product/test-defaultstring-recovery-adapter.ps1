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

# Exercise the actual launch helper. Keep FilePath untyped in the mock so a
# caller-side array cannot be silently coerced by the test itself.
& {
    . (Join-Path $PSScriptRoot 'defaultstring-recovery-adapter.ps1')
    $fixturePaths=@()
    $launches=[Collections.Generic.List[object]]::new()
    function Get-Command {param($Name,$CommandType,[switch]$All,$ErrorAction) foreach($path in $fixturePaths){[pscustomobject]@{Source=$path}}}
    function Test-Path {param($LiteralPath,$PathType) return ($LiteralPath -notlike '*missing*')}
    function Start-Process {param($FilePath,$Verb,$WindowStyle,[switch]$PassThru,$ArgumentList)
        if($FilePath -isnot [string]){throw 'Launch received an array.'}
        if($Verb -cne 'RunAs' -or $WindowStyle -cne 'Hidden' -or -not $PassThru){throw 'Launch options changed.'}
        $expected=@('"C:\repo space\run_checked.py"','--script','"C:\repo space\worker.ps1"','--edition','ps5','--params-file','"C:\archive space\entry.json"')
        if(($ArgumentList -join '|') -cne ($expected -join '|')){throw 'Checked invocation arguments changed.'}
        $launches.Add($FilePath)
        return [pscustomobject]@{fixture_process=$true}
    }
    $alias='C:\Users\fixture\AppData\Local\Microsoft\WindowsApps\python.exe'
    foreach($case in @(
        @('C:\Program Files\Python314\python.exe',$alias),
        @($alias,'C:\Program Files\Python314\python.exe'),
        @('C:\Program Files\Python314\python.exe','C:\Python313\python.exe'),
        @('C:\missing\python.exe','C:\Program Files\Python314\python.exe')
    )){
        $fixturePaths=$case
        $result=Start-RecoveryCheckedWorker 'C:\repo space\run_checked.py' 'C:\repo space\worker.ps1' 'C:\archive space\entry.json'
        if(-not $result.fixture_process -or $launches[$launches.Count-1] -cne 'C:\Program Files\Python314\python.exe'){throw 'Wrong Python selected.'}
    }
    foreach($case in @(@($alias),@())){
        $fixturePaths=$case;$rejected=$false
        try{$null=Start-RecoveryCheckedWorker 'unused' 'unused' 'unused'}catch{$rejected=$true}
        if(-not $rejected -or $launches.Count -ne 4){throw 'Unavailable native Python reached launch.'}
    }
}
Write-Output 'PASS: multiple Python matches produce one native launch path; alias/missing cases and spaced checked arguments covered without UAC.'
