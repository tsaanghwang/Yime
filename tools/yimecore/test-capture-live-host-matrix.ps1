$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'capture-live-host-matrix.ps1'
$source=Get-Content -LiteralPath $script -Raw
foreach($forbidden in @('Start-Process','Stop-Process','Set-ItemProperty','New-ItemProperty','Remove-ItemProperty')) {
    if($source -match [regex]::Escape($forbidden)){throw "Read-only collector contains forbidden operation: $forbidden"}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('yime-live-host-matrix-'+[guid]::NewGuid().ToString('N'))
$output=Join-Path $root 'evidence.json'
try {
    [void][IO.Directory]::CreateDirectory($root)
    $missingState=Join-Path $root 'missing-state'
    $missingPid=2147483000
    $json=& $script -HostProcessId $missingPid -StateRoot $missingState -OutputPath $output
    $record=$json|ConvertFrom-Json
    if($record.schema_version -ne 'yimecore-real-live-host-metadata-v1'){throw 'Wrong evidence schema.'}
    if(-not (Test-Path -LiteralPath $output)){throw 'Evidence file was not created.'}
    if($record.package.status -ne 'unavailable' -or $record.hosts[0].status -ne 'unavailable'){throw 'Unavailable probes were not retained.'}
    if($record.complete -or $record.passed){throw 'Unavailable fixture was incorrectly accepted.'}
    if($record.privacy.user_text_read -or $record.privacy.window_titles_read -or $record.side_effects.product_state_changed){throw 'Privacy or side-effect contract is wrong.'}
    Write-Output 'PASS: real live-host metadata collector contract'
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
