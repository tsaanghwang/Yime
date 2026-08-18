$ErrorActionPreference = 'Stop'

$checker = Join-Path $PSScriptRoot 'check-rime-cache-freshness.ps1'
$root = Split-Path -Parent $PSScriptRoot
$temporaryRoot = Join-Path $root '.tmp'
$fixture = Join-Path $temporaryRoot ('test-rime-cache-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'build') -Force | Out-Null
    $schemaID = 'yime_full'
    $dictionaryID = 'yime_sentence_full'
    $importedID = 'yime_particle_a_stage6d_full'
    $padding = (1..300 | ForEach-Object { "# parser padding line $_" }) -join "`n"
    @"
custom_phrase:
  dictionary: ""
$padding
schema:
  schema_id: $schemaID
translator:
  dictionary: $dictionaryID
"@ | Set-Content -LiteralPath (Join-Path $fixture "$schemaID.schema.yaml") -Encoding UTF8
    @"
---
name: $dictionaryID
$padding
import_tables:
  - $importedID
...
"@ | Set-Content -LiteralPath (Join-Path $fixture "$dictionaryID.dict.yaml") -Encoding UTF8
    "---`nname: $importedID`n..." | Set-Content -LiteralPath (Join-Path $fixture "$importedID.dict.yaml") -Encoding UTF8
    foreach ($suffix in @('table.bin', 'reverse.bin', 'prism.bin')) {
        'compiled' | Set-Content -LiteralPath (Join-Path $fixture "build\$dictionaryID.$suffix") -Encoding ASCII
    }
    'compiled schema' | Set-Content -LiteralPath (Join-Path $fixture "build\$schemaID.schema.yaml") -Encoding UTF8

    $old = [DateTime]::UtcNow.AddHours(-3)
    $compiled = [DateTime]::UtcNow.AddHours(-2)
    $new = [DateTime]::UtcNow.AddHours(-1)
    (Get-Item -LiteralPath (Join-Path $fixture "$schemaID.schema.yaml")).LastWriteTimeUtc = $old
    (Get-Item -LiteralPath (Join-Path $fixture "$dictionaryID.dict.yaml")).LastWriteTimeUtc = $old
    foreach ($suffix in @('table.bin', 'reverse.bin', 'prism.bin')) {
        (Get-Item -LiteralPath (Join-Path $fixture "build\$dictionaryID.$suffix")).LastWriteTimeUtc = $compiled
    }
    (Get-Item -LiteralPath (Join-Path $fixture "build\$schemaID.schema.yaml")).LastWriteTimeUtc = $compiled
    (Get-Item -LiteralPath (Join-Path $fixture "$importedID.dict.yaml")).LastWriteTimeUtc = $new

    $record = @(& $checker -RimeUserDir $fixture -SchemaIDs $schemaID)[0]
    if ($record.status -ne 'stale' -or $record.staleSources -notcontains (Join-Path $fixture "$importedID.dict.yaml")) {
        throw "Imported dictionary staleness was not detected: $($record | ConvertTo-Json -Depth 4)"
    }

    foreach ($suffix in @('table.bin', 'reverse.bin', 'prism.bin')) {
        (Get-Item -LiteralPath (Join-Path $fixture "build\$dictionaryID.$suffix")).LastWriteTimeUtc = [DateTime]::UtcNow
    }
    $record = @(& $checker -RimeUserDir $fixture -SchemaIDs $schemaID)[0]
    if ($record.status -ne 'match' -or $record.sourceCount -ne 2) {
        throw "Fresh recursive dictionary closure was not accepted: $($record | ConvertTo-Json -Depth 4)"
    }

    foreach ($staleSuffix in @('reverse.bin', 'prism.bin')) {
        $stalePath = Join-Path $fixture "build\$dictionaryID.$staleSuffix"
        (Get-Item -LiteralPath $stalePath).LastWriteTimeUtc = $old
        $record = @(& $checker -RimeUserDir $fixture -SchemaIDs $schemaID)[0]
        if ($record.status -ne 'stale' -or $record.staleArtifacts -notcontains $stalePath) {
            throw "Stale $staleSuffix was not detected: $($record | ConvertTo-Json -Depth 5)"
        }
        (Get-Item -LiteralPath $stalePath).LastWriteTimeUtc = [DateTime]::UtcNow
    }

    "---`nname: $dictionaryID`nimport_tables:`n  - ../outside`n..." |
        Set-Content -LiteralPath (Join-Path $fixture "$dictionaryID.dict.yaml") -Encoding UTF8
    $record = @(& $checker -RimeUserDir $fixture -SchemaIDs $schemaID)[0]
    if ($record.status -ne 'error' -or $record.detail -notmatch 'unsafe') {
        throw "Unsafe import ID was not rejected: $($record | ConvertTo-Json -Depth 4)"
    }

    Write-Host 'Rime compiled-cache freshness tests passed.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
