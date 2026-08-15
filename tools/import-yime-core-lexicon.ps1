param(
    [Parameter(Mandatory = $true)]
    [Alias("Input")]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceManifest,
    [Parameter(Mandatory = $true)]
    [string]$SourceRevision,
    [Parameter(Mandatory = $true)]
    [string]$PronunciationEntries,
    [string]$OutputDir = "",
    [switch]$DeployToUserDir
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$goBackend = Join-Path $root "go-backend"
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedEvidencePath = (Resolve-Path -LiteralPath $EvidenceManifest).Path
$resolvedPronunciationEntries = (Resolve-Path -LiteralPath $PronunciationEntries).Path
$evidence = Get-Content -LiteralPath $resolvedEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if (-not $evidence.ranking_evidence.policy_id) {
    throw "Core evidence manifest has no ranking policy."
}
if (-not $evidence.ranking_evidence.distinct_texts_by_source) {
    throw "Core evidence manifest has no source-separated ranking counts."
}
$characterRanking = $evidence.single_character_ranking
if (-not $characterRanking) {
    throw "Core evidence manifest has no single-character ranking evidence."
}
$singleCharacters = [int64]$evidence.distinct_texts_by_length.'1'
$singleMappings = [int64]$evidence.reading_entries_by_length.'1'
$coreCharacters = [int64]$characterRanking.core_distinct_characters
$peripheralCharacters = [int64]$characterRanking.peripheral_distinct_characters
if ($singleCharacters -ne ($coreCharacters + $peripheralCharacters)) {
    throw "Core and peripheral character counts do not cover the runtime single-character inventory."
}
if (-not [bool]$characterRanking.core_above_peripheral) {
    throw "Core and peripheral single-character weight ranges overlap."
}
$sourceHash = (Get-FileHash -LiteralPath $resolvedInputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$pronunciationEntriesHash = (Get-FileHash -LiteralPath $resolvedPronunciationEntries -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne [string]$evidence.output_sha256) {
    throw "Core dictionary hash does not match the evidence manifest."
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $goBackend "input_methods\yime\data"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path
$reverseCodeMapPath = Join-Path $outputPath "yime_pinyin_codes.tsv"
if (-not (Test-Path -LiteralPath $reverseCodeMapPath)) {
    $reverseCodeMapPath = Join-Path $goBackend "input_methods\yime\data\yime_pinyin_codes.tsv"
}
$reverseCodeMapHash = (Get-FileHash -LiteralPath $reverseCodeMapPath -Algorithm SHA256).Hash.ToLowerInvariant()

Push-Location $goBackend
try {
    go run ./cmd/yime-lexicon-derive `
        -input $resolvedInputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime core derivation failed with exit code $LASTEXITCODE"
    }
    go run ./cmd/yime-reverse-pinyin-derive `
        -codes $reverseCodeMapPath `
        -dictionary (Join-Path $outputPath "yime_full.dict.yaml") `
        -pronunciations $resolvedPronunciationEntries `
        -output (Join-Path $outputPath "yime_pinyin_reverse_source.tsv")
    if ($LASTEXITCODE -ne 0) {
        throw "Yime reverse-Pinyin source derivation failed with exit code $LASTEXITCODE"
    }
    go run ./cmd/yime-erhua-mixed-derive `
        -repo-root $root `
        -data-dir $outputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime explicit-erhua mixed overlay derivation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$generatedManifestPath = Join-Path $outputPath "yime_lexicon_manifest.json"
$generated = Get-Content -LiteralPath $generatedManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([int64]$generated.entry_count -ne [int64]$evidence.total_reading_entries) {
    throw "Derived entry count does not match the curated core evidence."
}

$counts = $evidence.ranking_evidence.distinct_texts_by_source
$reverseSourcePath = Join-Path $outputPath "yime_pinyin_reverse_source.tsv"
$reverseSourceHash = (Get-FileHash -LiteralPath $reverseSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
$reverseSourceRows = [Math]::Max(0, (Get-Content -LiteralPath $reverseSourcePath -Encoding UTF8).Count - 1)
$sourceRecord = [ordered]@{
    schema_version = 1
    source_project = "Yime-python-prototype"
    source_revision = $SourceRevision
    source_dictionary = [IO.Path]::GetFileName($resolvedInputPath)
    source_dictionary_sha256 = $sourceHash
    source_selection_sha256 = [string]$evidence.selection_tsv_sha256
    pronunciation_entries = [IO.Path]::GetFileName($resolvedPronunciationEntries)
    pronunciation_entries_sha256 = $pronunciationEntriesHash
    reverse_pinyin_source = "yime_pinyin_reverse_source.tsv"
    reverse_pinyin_source_sha256 = $reverseSourceHash
    reverse_pinyin_source_rows = $reverseSourceRows
    reverse_pinyin_code_map_sha256 = $reverseCodeMapHash
    entry_count = [int64]$evidence.total_reading_entries
    distinct_texts = [int64]$evidence.total_distinct_texts
    ranking_evidence = [ordered]@{
        policy_id = [string]$evidence.ranking_evidence.policy_id
        policy_sha256 = [string]$evidence.ranking_evidence.policy_sha256
        direct_bcc = [int64]$counts.direct_bcc
        provisional_rime_lmdg = [int64]$counts.provisional_rime_lmdg
        provisional_structural_floor = [int64]$counts.provisional_structural_floor
        missing_selected_source_texts = [int64]$evidence.ranking_evidence.missing_selected_source_texts
        raw_bcc_and_lmdg_values_added = [bool]$evidence.ranking_evidence.raw_bcc_and_lmdg_values_added
        source_priority_separation_passed = $true
    }
    character_coverage = [ordered]@{
        distinct_characters = $singleCharacters
        runtime_mapping_entries = $singleMappings
        core_distinct_characters = $coreCharacters
        core_reading_entries = [int64]$characterRanking.core_reading_entries
        peripheral_distinct_characters = $peripheralCharacters
        peripheral_reading_entries = [int64]$characterRanking.peripheral_reading_entries
        minimum_core_weight = [int64]$characterRanking.minimum_core_weight
        maximum_peripheral_weight = [int64]$characterRanking.maximum_peripheral_weight
        core_above_peripheral = [bool]$characterRanking.core_above_peripheral
    }
    runtime_scope = "curated_phrases_with_all_encoded_character_periphery"
    prototype_scope = @("candidate_pool", "source_evidence", "regression_cases")
}
$sourceManifestPath = Join-Path $outputPath "yime_core_source_manifest.json"
$sourceJson = ($sourceRecord | ConvertTo-Json -Depth 8) + [Environment]::NewLine
[IO.File]::WriteAllText(
    $sourceManifestPath,
    $sourceJson,
    [Text.UTF8Encoding]::new($false)
)

Write-Host "Generated core-backed full, variable, and shorthand dictionaries."
Write-Host "Generation manifest: $generatedManifestPath"
Write-Host "Source evidence: $sourceManifestPath"

if ($DeployToUserDir) {
    $userDir = Join-Path $env:APPDATA "PIME\Rime"
    New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    foreach ($name in @(
        "yime_full.dict.yaml",
        "yime_variable.dict.yaml",
        "yime_shorthand.dict.yaml",
        "yime_erhua_mixed_full.dict.yaml",
        "yime_erhua_mixed_variable.dict.yaml",
        "yime_erhua_mixed_shorthand.dict.yaml",
        "yime_erhua_mixed_manifest.json",
        "yime_erhua_reverse_source.tsv",
        "yime_pinyin_reverse_source.tsv",
        "yime_lexicon_manifest.json",
        "yime_core_source_manifest.json"
    )) {
        Copy-Item -LiteralPath (Join-Path $outputPath $name) `
            -Destination (Join-Path $userDir $name) -Force
    }
    Write-Host "Core runtime dictionaries copied to $userDir"
}
