$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify-installed-particle-a-stage6d.ps1'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path (Join-Path $root '.tmp') ('test-installed-particle-a-' + [guid]::NewGuid().ToString('N'))
$installData = Join-Path $fixture 'install\go-backend\input_methods\yime\data'
$rimeUserDir = Join-Path $fixture 'user-rime'
$buildDir = Join-Path $rimeUserDir 'build'

function Set-FileUtc {
    param([string]$Path, [DateTime]$Value)
    (Get-Item -LiteralPath $Path).LastWriteTimeUtc = $Value
}

function Assert-VerifierFails {
    param([string]$ExpectedMessage)
    try {
        & $verifier -InstallRoot (Join-Path $fixture 'install') -RimeUserDir $rimeUserDir -ExpectedEntries 2 | Out-Null
        throw 'Verifier unexpectedly accepted an invalid installed deployment fixture.'
    } catch {
        if ($_.Exception.Message -notmatch $ExpectedMessage) { throw }
    }
}

try {
    New-Item -ItemType Directory -Path $installData, $buildDir -Force | Out-Null
    $outputHashes = [ordered]@{}
    $old = [DateTime]::UtcNow.AddHours(-2)
    $fresh = [DateTime]::UtcNow.AddHours(-1)

    foreach ($mode in @('full', 'variable', 'shorthand')) {
        $dictionaryID = "yime_particle_a_stage6d_$mode"
        $name = "$dictionaryID.dict.yaml"
        $payload = "---`nname: $dictionaryID`nversion: `"fixture`"`n...`n样子啊`tcode-$mode-1`t1`n走啊走`tcode-$mode-2`t1`n"
        $installedPath = Join-Path $installData $name
        $deployedPath = Join-Path $rimeUserDir $name
        $payload | Set-Content -LiteralPath $installedPath -Encoding UTF8 -NoNewline
        Copy-Item -LiteralPath $installedPath -Destination $deployedPath
        $outputHashes[$name] = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $schemaID = "yime_$mode"
        $sentenceID = "yime_sentence_$mode"
        "---`nname: $sentenceID`nimport_tables:`n  - $dictionaryID`n...`n" |
            Set-Content -LiteralPath (Join-Path $rimeUserDir "$sentenceID.dict.yaml") -Encoding UTF8 -NoNewline
        "schema:`n  schema_id: $schemaID`ntranslator:`n  dictionary: $sentenceID`n" |
            Set-Content -LiteralPath (Join-Path $rimeUserDir "$schemaID.schema.yaml") -Encoding UTF8 -NoNewline
        "schema:`n  schema_id: $schemaID`ntranslator:`n  dictionary: $sentenceID`n" |
            Set-Content -LiteralPath (Join-Path $buildDir "$schemaID.schema.yaml") -Encoding UTF8 -NoNewline
        foreach ($suffix in @('table.bin', 'reverse.bin', 'prism.bin')) {
            'compiled' | Set-Content -LiteralPath (Join-Path $buildDir "$sentenceID.$suffix") -Encoding ASCII
        }
        foreach ($path in @(
            $deployedPath,
            (Join-Path $rimeUserDir "$sentenceID.dict.yaml"),
            (Join-Path $rimeUserDir "$schemaID.schema.yaml")
        )) { Set-FileUtc $path $old }
        foreach ($path in @(
            (Join-Path $buildDir "$schemaID.schema.yaml"),
            (Join-Path $buildDir "$sentenceID.table.bin"),
            (Join-Path $buildDir "$sentenceID.reverse.bin"),
            (Join-Path $buildDir "$sentenceID.prism.bin")
        )) { Set-FileUtc $path $fresh }
    }

    $manifest = [ordered]@{
        output_sha256 = $outputHashes
        summary = [ordered]@{
            materialized_candidate_count = 2
            mode_row_counts = [ordered]@{ full = 2; variable = 2; shorthand = 2 }
            three_mode_row_count = 6
            passed = $true
        }
    }
    $installedManifest = Join-Path $installData 'yime_particle_a_stage6d_manifest.json'
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $installedManifest -Encoding UTF8
    Copy-Item -LiteralPath $installedManifest -Destination (Join-Path $rimeUserDir 'yime_particle_a_stage6d_manifest.json')

    $report = & $verifier -InstallRoot (Join-Path $fixture 'install') -RimeUserDir $rimeUserDir -ExpectedEntries 2
    if ($report.status -ne 'match' -or $report.modes.Count -ne 3) {
        throw "Valid installed deployment fixture was rejected: $($report | ConvertTo-Json -Depth 5)"
    }

    $fullDeployed = Join-Path $rimeUserDir 'yime_particle_a_stage6d_full.dict.yaml'
    (Get-Content -LiteralPath $fullDeployed -Raw -Encoding UTF8).Replace("走啊走`tcode-full-2`t1`n", '') |
        Set-Content -LiteralPath $fullDeployed -Encoding UTF8 -NoNewline
    Set-FileUtc $fullDeployed $old
    Assert-VerifierFails 'deployed rows=1, want 2'
    Copy-Item -LiteralPath (Join-Path $installData 'yime_particle_a_stage6d_full.dict.yaml') -Destination $fullDeployed -Force
    Set-FileUtc $fullDeployed $old

    $staleTable = Join-Path $buildDir 'yime_sentence_full.table.bin'
    Set-FileUtc $staleTable ([DateTime]::UtcNow.AddHours(-3))
    Assert-VerifierFails 'compiled cache status=stale'

    Write-Host 'Installed particle-a Stage 6D verifier regression tests passed.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
