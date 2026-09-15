# Build-only speech staging. Definitions only; never installed as a maintenance service.
function Get-LocalProductSpeechPayloadPaths {
    @('speech-capability.json','speech/product.json','speech/admission.json','speech/forward-source.json','speech/admitted-records.json')
    foreach ($mode in @('full','variable','shorthand')) { "speech/indexes/$mode-core.yidx"; "speech/indexes/$mode-stage5c.yidx" }
}

function Assert-LocalProductSpeechBuildInputs($Product,[string]$AdmissionRoot,[string]$SummarySHA256,[string]$SourceInventorySHA256) {
    $declared = $null -ne $Product.PSObject.Properties['speech']
    if (-not $declared) {
        if ($AdmissionRoot -or $SummarySHA256 -or $SourceInventorySHA256) { throw 'Speech inputs require a declared owning product capability.' }
        return $false
    }
    if (-not [IO.Path]::IsPathRooted($AdmissionRoot) -or $SummarySHA256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $SourceInventorySHA256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Declared speech requires explicit admission root and both fixed SHA256 pins.' }
    Assert-LocalProductPlainPath $AdmissionRoot
    if ((Split-Path -Leaf $AdmissionRoot) -cnotmatch '^speech-admission-[a-zA-Z0-9-]+$') { throw 'Expected an explicitly identified speech admission root.' }
    $summaryPath = Resolve-LocalProductChild $AdmissionRoot 'summary.json'
    if ((Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash -ine $SummarySHA256) { throw 'Admission summary pin mismatch.' }
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($summary.schema_version -cne 'yimecore-speech-admission-isolated-v1' -or $summary.passed -ne $true -or
        $summary.stage -cne 'complete' -or $summary.reviewed_records -ne 24 -or $summary.mode_alias_rows -ne 72 -or
        $summary.source_inventory.path -cne 'source-hashes-after.json' -or
        $summary.source_inventory.sha256 -ine $SourceInventorySHA256 -or
        $summary.source_inventory_before.sha256 -ine $SourceInventorySHA256) { throw 'Fresh complete admission with bound source inventory required.' }
    $inventoryPath = Resolve-LocalProductChild $AdmissionRoot 'source-hashes-after.json'
    if ((Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash -ine $SourceInventorySHA256 -or
        (Get-Item -LiteralPath $inventoryPath).Length -ne $summary.source_inventory.bytes) { throw 'Source inventory bytes do not match the summary.' }
    # The Go exporter independently checks exact JSON, sources, receipts, tools,
    # lifecycle results, all six indexes and the normal core/layout bindings.
    return $true
}

function Add-LocalProductSpeechPayload {
    param([string]$RepoRoot,[string]$PackageRoot,[string]$BuildRoot,[string]$Exporter,
        [string]$AdmissionRoot,[string]$SummarySHA256,[string]$SourceInventorySHA256)
    $exportRoot = Join-Path $BuildRoot ('speech-product-export-'+[guid]::NewGuid().ToString('N'))
    $mappingPath = Join-Path $BuildRoot 'speech-product-export-mapping.json'
    Assert-LocalProductPlainPath $exportRoot
    Assert-LocalProductPlainPath $mappingPath
    if ((Test-Path -LiteralPath $exportRoot) -or (Test-Path -LiteralPath $mappingPath)) { throw 'Preserve prior speech staging evidence.' }
    & $Exporter -action export-product -repo $RepoRoot -root $AdmissionRoot -summary-sha256 $SummarySHA256.ToLowerInvariant() `
        -source-inventory-sha256 $SourceInventorySHA256.ToLowerInvariant() -normal-index-root (Join-Path $PackageRoot 'indexes') `
        -normal-data-root (Join-Path $PackageRoot 'data') -output-root $exportRoot -export-receipt $mappingPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Independent speech product export failed; preserve the new build root.' }
    $expected = @(Get-LocalProductSpeechPayloadPaths | Sort-Object)
    $records = @(Get-LocalProductPayloadRecords $exportRoot)
    Assert-LocalProductSourceSet $expected @($records | ForEach-Object { $_.path } | Sort-Object)
    if ($records.Count -ne 11) { throw 'Speech exporter must produce exactly eleven payload files.' }
    foreach ($relative in $expected) {
        if (Test-Path -LiteralPath (Resolve-LocalProductChild $PackageRoot $relative)) { throw 'Speech staging must not overwrite any package file.' }
    }
    foreach ($record in $records) {
        $source = Resolve-LocalProductChild $exportRoot $record.path
        $destination = Resolve-LocalProductChild $PackageRoot $record.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        [IO.File]::Copy($source,$destination,$false)
        $actual = Get-LocalProductFileRecord $PackageRoot $record.path
        if ($actual.sha256 -cne $record.sha256 -or $actual.bytes -ne $record.bytes) { throw 'Speech staging copy differs from verified export.' }
    }
    Assert-LocalProductSourceUnchanged $exportRoot $records
    return [ordered]@{
        schema_version='yimecore-speech-build-binding-v1';admission_summary_sha256=$SummarySHA256.ToLowerInvariant()
        source_inventory_sha256=$SourceInventorySHA256.ToLowerInvariant()
        export_receipt_sha256=(Get-FileHash -LiteralPath $mappingPath -Algorithm SHA256).Hash.ToLowerInvariant()
        capability_sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'speech-capability.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        product_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'speech/product.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
