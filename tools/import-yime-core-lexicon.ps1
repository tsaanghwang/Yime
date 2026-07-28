param(
    [Parameter(Mandatory = $true)]
    [Alias("Input")]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceManifest,
    [Parameter(Mandatory = $true)]
    [string]$SourceRevision,
    [string]$OutputDir = "",
    [switch]$DeployToUserDir
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$goBackend = Join-Path $root "go-backend"
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedEvidencePath = (Resolve-Path -LiteralPath $EvidenceManifest).Path
$evidence = Get-Content -LiteralPath $resolvedEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if (-not $evidence.ranking_evidence.policy_id) {
    throw "Core evidence manifest has no ranking policy."
}
if (-not $evidence.ranking_evidence.distinct_texts_by_source) {
    throw "Core evidence manifest has no source-separated ranking counts."
}
$sourceHash = (Get-FileHash -LiteralPath $resolvedInputPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne [string]$evidence.output_sha256) {
    throw "Core dictionary hash does not match the evidence manifest."
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $goBackend "input_methods\yime\data"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path

Push-Location $goBackend
try {
    go run ./cmd/yime-lexicon-derive `
        -input $resolvedInputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime core derivation failed with exit code $LASTEXITCODE"
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
$sourceRecord = [ordered]@{
    schema_version = 1
    source_project = "Yime-python-prototype"
    source_revision = $SourceRevision
    source_dictionary = [IO.Path]::GetFileName($resolvedInputPath)
    source_dictionary_sha256 = $sourceHash
    source_selection_sha256 = [string]$evidence.selection_tsv_sha256
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
    runtime_scope = "curated_core_only"
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
        "yime_lexicon_manifest.json",
        "yime_core_source_manifest.json"
    )) {
        Copy-Item -LiteralPath (Join-Path $outputPath $name) `
            -Destination (Join-Path $userDir $name) -Force
    }
    Write-Host "Core runtime dictionaries copied to $userDir"
}
