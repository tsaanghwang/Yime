$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'capture-installed-readonly-evidence.ps1'
$source=Get-Content -LiteralPath $script -Raw
foreach($forbidden in @('Start-Process','Stop-Process','Set-ItemProperty','New-ItemProperty','Remove-ItemProperty')) {
    if($source -match [regex]::Escape($forbidden)){throw "Read-only collector contains forbidden operation: $forbidden"}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('yime-readonly-evidence-'+[guid]::NewGuid().ToString('N'))
$output=Join-Path $root 'evidence.json'
try {
    $missing=Join-Path $root 'missing-state'
    $json=& $script -StateRoot $missing -ExpectedComputerName '__not_this_host__' -ExpectedManifestSha256 ('0'*64) -OutputPath $output
    $record=$json|ConvertFrom-Json
    if($record.schema_version -ne 'yimecore-installed-readonly-evidence-v1' -or -not (Test-Path -LiteralPath $output)) {throw 'Collector did not emit its evidence contract.'}
    if(@($record.checks|Where-Object {$_.name -eq 'installed_package_discovery' -and $_.status -eq 'unavailable'}).Count -ne 1){throw 'Missing install must be reported as unavailable.'}
    if($record.complete -or $record.passed -or $record.side_effects.product_state_written){throw 'Unavailable fixture was incorrectly accepted or marked mutating.'}
    Write-Output 'PASS: conditional read-only evidence collector contract'
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
