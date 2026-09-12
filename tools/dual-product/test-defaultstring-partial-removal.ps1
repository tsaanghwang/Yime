$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$root=Join-Path $repo ('.tmp\dual-product\dp1-partial-removal-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $root 'payload';$evidence=Join-Path $root 'evidence'
$null=[IO.Directory]::CreateDirectory($payload);$null=[IO.Directory]::CreateDirectory($evidence)
foreach($name in @('a.bin','b.bin','c.bin','foreign.bin')){[IO.File]::WriteAllText((Join-Path $payload $name),'fixture')}
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-maintenance.psm1') -PassThru
& $module {
    param($payload,$evidence)
    Initialize-CandidateMaintenance
    & $script:CandidatePackageModule {Initialize-CandidateNative}
    . (Join-Path $PSScriptRoot 'defaultstring-recovery-adapter.ps1')
    $files=@(foreach($name in @('a.bin','b.bin','c.bin')){
        $r=& $script:CandidatePackageModule {param($p) $script:CandidateNative::Inspect($p)} (Join-Path $payload $name)
        [pscustomobject]@{path=$name;bytes=$r.Bytes;sha256=$r.Sha256;file_id=$r.FileId}
    })
    $plan=[pscustomobject]@{install_root=$payload;recovery_root=$evidence;files=$files}
    $ticket=[pscustomobject]@{plan=$plan}
    $registrationsAbsent=$false
    function Get-MaintenanceRegistration($Context,$Plan,$Bundle,$State){
        if($State -cne 'Absent'){throw 'Partial-removal gate did not require absence.'}
        if(-not $registrationsAbsent){throw 'Fixture registration still present.'}
        return [pscustomobject]@{absent=$true}
    }
    # A real delete-sharing reader allows marking, but delays disappearance.
    # Its held handle reproduces a partial operation without force deletion.
    $held=[IO.File]::Open((Join-Path $payload 'b.bin'),'Open','Read',([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    try{
        $failed=$false
        try{Remove-MaintenanceInstalledFiles $plan}catch{
            if($_.Exception.Message -notlike 'Exact removal is pending or incomplete*'){throw}
            $failed=$true
        }
        if(-not $failed){throw 'Pending removal was accepted.'}
        $paths=@(Get-ChildItem -LiteralPath $evidence -Filter 'exact-removal-*.json')
        if($paths.Count -ne 1){throw 'Native outcomes were not persisted before failure.'}
        $result=Get-Content -LiteralPath $paths[0].FullName -Raw|ConvertFrom-Json
        if(-not $result.outcomes_available -or $result.outcomes.Count -ne 3 -or
            -not $result.outcomes[0].removed -or $result.outcomes[1].removed -or
            -not $result.outcomes[1].marked_for_deletion -or $result.outcomes[1].native_error -eq 0 -or
            $result.outcomes[2].status -cne 'not-attempted'){throw 'Partial native outcomes lost their meaning.'}
    }finally{$held.Dispose()}
    $rejected=$false
    try{$null=Assert-RecoveryRemainingPayload $null $ticket 'fixture-bundle'}catch{$rejected=$true}
    if(-not $rejected){throw 'Partial payload admitted while registration remains.'}
    $registrationsAbsent=$true
    if((Assert-RecoveryRemainingPayload $null $ticket 'fixture-bundle') -ne 1){throw 'Wrong remaining file count.'}
    [IO.File]::WriteAllText((Join-Path $payload 'c.bin'),'changed')
    $rejected=$false
    try{$null=Assert-RecoveryRemainingPayload $null $ticket 'fixture-bundle'}catch{$rejected=$true}
    if(-not $rejected){throw 'Changed survivor admitted.'}
    [IO.File]::WriteAllText((Join-Path $payload 'c.bin'),'fixture')
    Remove-MaintenanceInstalledFiles $plan
    if((Assert-RecoveryRemainingPayload $null $ticket 'fixture-bundle') -ne 0){throw 'Replay did not reach exact absence.'}
    $records=@(Get-ChildItem -LiteralPath $evidence -Filter 'exact-removal-*.json'|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json})
    if(@($records|Where-Object initially_absent_count -eq 2).Count -ne 1){throw 'Replay lost already-absent count.'}
    if([IO.File]::ReadAllText((Join-Path $payload 'foreign.bin')) -cne 'fixture'){throw 'Unlisted file changed.'}
} $payload $evidence
Write-Output ('PASS: real partial deletion outcomes, registration-absence gate, changed survivor rejection and exact replay; evidence '+$root)
