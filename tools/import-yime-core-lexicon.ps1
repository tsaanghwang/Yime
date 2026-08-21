param(
    [Parameter(Mandatory = $true)]
    [Alias("Input")]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceManifest,
    [Parameter(Mandatory = $true)]
    [string]$SourceRevision,
    [string]$PronunciationEntries = "",
    [string]$PrebuiltReverseSource = "",
    [string]$PreviousCoreSourceManifest = "",
    [string]$ApprovedTargetLock = "",
    [string]$OutputDir = "",
    [switch]$DeployToUserDir
)

$ErrorActionPreference = "Stop"

function Replace-ExactlyOnce {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Replacement,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $matches = [regex]::Matches($Content, $Pattern)
    if ($matches.Count -ne 1) {
        throw "$Label must match exactly once; found $($matches.Count)."
    }
    return [regex]::Replace($Content, $Pattern, $Replacement, 1)
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$goBackend = Join-Path $root "go-backend"
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedEvidencePath = (Resolve-Path -LiteralPath $EvidenceManifest).Path
$evidence = Get-Content -LiteralPath $resolvedEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$sourceHash = (Get-FileHash -LiteralPath $resolvedInputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$usingPrebuiltReverseSource = -not [string]::IsNullOrWhiteSpace($PrebuiltReverseSource)
$usingApprovedTarget = -not [string]::IsNullOrWhiteSpace($ApprovedTargetLock)
if ($usingApprovedTarget -and -not $usingPrebuiltReverseSource) {
    throw "-ApprovedTargetLock requires -PrebuiltReverseSource."
}
$resolvedPronunciationEntries = ""
$resolvedPrebuiltReverseSource = ""
$previousCoreSource = $null
if ($usingPrebuiltReverseSource) {
    if ([string]::IsNullOrWhiteSpace($PreviousCoreSourceManifest)) {
        throw "-PreviousCoreSourceManifest is required with -PrebuiltReverseSource."
    }
    $resolvedPrebuiltReverseSource = (Resolve-Path -LiteralPath $PrebuiltReverseSource).Path
    $resolvedPreviousCoreSourceManifest = (Resolve-Path -LiteralPath $PreviousCoreSourceManifest).Path
    $previousCoreSource = Get-Content -LiteralPath $resolvedPreviousCoreSourceManifest -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if (-not $previousCoreSource.pronunciation_entries -or
        -not $previousCoreSource.pronunciation_entries_sha256) {
        throw "Previous core source manifest has no pronunciation-source evidence."
    }
    $prebuiltReverseHash = (Get-FileHash -LiteralPath $resolvedPrebuiltReverseSource -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($usingApprovedTarget) {
        $resolvedTargetLock = (Resolve-Path -LiteralPath $ApprovedTargetLock).Path
        $targetLock = Get-Content -LiteralPath $resolvedTargetLock -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ([string]$targetLock.status -ne "approved_windows_handoff_target") {
            throw "Approved target lock does not identify an approved Windows handoff."
        }
        if ($sourceHash -ne [string]$targetLock.target.source_dictionary_sha256 -or
            $sourceHash -ne [string]$evidence.output_sha256) {
            throw "Approved replay source dictionary does not match the target lock and evidence."
        }
        if ([string]$evidence.selection_tsv_sha256 -ne [string]$targetLock.target.source_selection_sha256) {
            throw "Approved replay selection identity does not match the target lock."
        }
        if ([int64]$evidence.total_reading_entries -ne [int64]$targetLock.target.entry_count -or
            [int64]$evidence.total_distinct_texts -ne [int64]$targetLock.target.distinct_texts) {
            throw "Approved replay counts do not match the target lock."
        }
        $reverseArtifact = @($targetLock.artifacts | Where-Object role -eq "reverse_pinyin_source") |
            Select-Object -First 1
        if (-not $reverseArtifact -or
            $prebuiltReverseHash -ne [string]$reverseArtifact.sha256 -or
            $prebuiltReverseHash -ne [string]$previousCoreSource.reverse_pinyin_source_sha256) {
            throw "Approved replay reverse-Pinyin source does not match the locked target."
        }
    }
    else {
        if (-not $evidence.layout_reprojection -or
            [bool]$evidence.layout_reprojection.candidate_selection_changed -or
            [bool]$evidence.layout_reprojection.weights_changed) {
            throw "Prebuilt reverse source requires layout-only evidence with unchanged selection and weights."
        }
        if ($prebuiltReverseHash -ne [string]$evidence.layout_reprojection.reverse_source_sha256) {
            throw "Prebuilt reverse source hash does not match layout-reprojection evidence."
        }
    }
    $pronunciationEntriesName = [string]$previousCoreSource.pronunciation_entries
    $pronunciationEntriesHash = [string]$previousCoreSource.pronunciation_entries_sha256
}
else {
    if ([string]::IsNullOrWhiteSpace($PronunciationEntries)) {
        throw "-PronunciationEntries is required unless -PrebuiltReverseSource is used."
    }
    $resolvedPronunciationEntries = (Resolve-Path -LiteralPath $PronunciationEntries).Path
    $pronunciationEntriesName = [IO.Path]::GetFileName($resolvedPronunciationEntries)
    $pronunciationEntriesHash = (Get-FileHash -LiteralPath $resolvedPronunciationEntries -Algorithm SHA256).Hash.ToLowerInvariant()
}

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
    $canonicalReverseCodeMapPath = Join-Path $goBackend "input_methods\yime\data\yime_pinyin_codes.tsv"
    Copy-Item -LiteralPath $canonicalReverseCodeMapPath -Destination $reverseCodeMapPath -Force
}
foreach ($sidecarName in @("yime_syllable_decomposition.tsv", "yime_yinyuan_layout.json")) {
    $sidecarPath = Join-Path $outputPath $sidecarName
    if (-not (Test-Path -LiteralPath $sidecarPath)) {
        Copy-Item -LiteralPath (Join-Path $goBackend "input_methods\yime\data\$sidecarName") `
            -Destination $sidecarPath -Force
    }
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
    if ($usingPrebuiltReverseSource) {
        Copy-Item -LiteralPath $resolvedPrebuiltReverseSource `
            -Destination (Join-Path $outputPath "yime_pinyin_reverse_source.tsv") -Force
    }
    else {
        go run ./cmd/yime-reverse-pinyin-derive `
            -codes $reverseCodeMapPath `
            -dictionary (Join-Path $outputPath "yime_full.dict.yaml") `
            -pronunciations $resolvedPronunciationEntries `
            -output (Join-Path $outputPath "yime_pinyin_reverse_source.tsv")
        if ($LASTEXITCODE -ne 0) {
            throw "Yime reverse-Pinyin source derivation failed with exit code $LASTEXITCODE"
        }
    }
    go run ./cmd/yime-psc-peripheral-derive `
        -repo-root $root `
        -codes $reverseCodeMapPath `
        -data-dir $outputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime PSC pronunciation peripheral derivation failed with exit code $LASTEXITCODE"
    }
    go run ./cmd/yime-third-tone-stage5c-derive `
        -repo-root $root `
        -data-dir $outputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime reviewed third-tone Stage 5C derivation failed with exit code $LASTEXITCODE"
    }
    go run ./cmd/yime-particle-a-stage6d-derive `
        -repo-root $root `
        -data-dir $outputPath `
        -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime reviewed particle-a Stage 6D derivation failed with exit code $LASTEXITCODE"
    }
    # The explicit-erhua generator may inherit the reviewed low-frequency
    # weight from an exact PSC suffix-compatible entry, so the PSC overlay is
    # a declared upstream artifact and must be generated first.
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
$runtimeEntryCount = [int64]$evidence.total_reading_entries
$runtimeDistinctTexts = [int64]$evidence.total_distinct_texts
foreach ($mode in @("full", "variable", "shorthand")) {
    $schemaPath = Join-Path $outputPath "yime_$mode.schema.yaml"
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        continue
    }
    $schemaText = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
    $schemaText = Replace-ExactlyOnce `
        -Content $schemaText `
        -Pattern 'core-[0-9]+' `
        -Replacement "core-$runtimeEntryCount" `
        -Label "yime_$mode schema version core namespace"
    $schemaText = Replace-ExactlyOnce `
        -Content $schemaText `
        -Pattern 'core_[0-9]+' `
        -Replacement "core_$runtimeEntryCount" `
        -Label "yime_$mode user dictionary core namespace"
    [IO.File]::WriteAllText(
        $schemaPath,
        $schemaText,
        [Text.UTF8Encoding]::new($false)
    )
}

$runtimeProfilePath = Join-Path $outputPath "yime_runtime_profile.json"
if (Test-Path -LiteralPath $runtimeProfilePath) {
    $runtimeProfileText = Get-Content -LiteralPath $runtimeProfilePath -Raw -Encoding UTF8
    foreach ($replacement in @(
        @('(?m)("entry_count_per_mode"\s*:\s*)[0-9]+', ('${1}' + $runtimeEntryCount), 'runtime profile entry count'),
        @('(?m)("distinct_core_texts"\s*:\s*)[0-9]+', ('${1}' + $runtimeDistinctTexts), 'runtime profile distinct text count'),
        @('(?m)("direct_bcc"\s*:\s*)[0-9]+', ('${1}' + [int64]$counts.direct_bcc), 'runtime profile direct BCC count'),
        @('(?m)("provisional_rime_lmdg"\s*:\s*)[0-9]+', ('${1}' + [int64]$counts.provisional_rime_lmdg), 'runtime profile Rime LMDG count'),
        @('(?m)("provisional_structural_floor"\s*:\s*)[0-9]+', ('${1}' + [int64]$counts.provisional_structural_floor), 'runtime profile structural floor count')
    )) {
        $runtimeProfileText = Replace-ExactlyOnce `
            -Content $runtimeProfileText `
            -Pattern $replacement[0] `
            -Replacement $replacement[1] `
            -Label $replacement[2]
    }
    [IO.File]::WriteAllText(
        $runtimeProfilePath,
        $runtimeProfileText,
        [Text.UTF8Encoding]::new($false)
    )
}

$reverseSourcePath = Join-Path $outputPath "yime_pinyin_reverse_source.tsv"
$reverseSourceHash = (Get-FileHash -LiteralPath $reverseSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
$reverseSourceRows = [Math]::Max(0, (Get-Content -LiteralPath $reverseSourcePath -Encoding UTF8).Count - 1)
$sourceRecord = [ordered]@{
    schema_version = 1
    source_project = "Yime"
    source_revision = $SourceRevision
    source_dictionary = [IO.Path]::GetFileName($resolvedInputPath)
    source_dictionary_sha256 = $sourceHash
    source_selection_sha256 = [string]$evidence.selection_tsv_sha256
    pronunciation_entries = $pronunciationEntriesName
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
    offline_tooling_scope = @("candidate_pool", "source_evidence", "regression_cases")
}
if ($usingApprovedTarget) {
    $sourceRecord["approved_target_lock"] = [IO.Path]::GetFileName($resolvedTargetLock)
    $sourceRecord["historical_source_project"] = [string]$previousCoreSource.source_project
    $sourceRecord["historical_source_revision"] = [string]$previousCoreSource.source_revision
}
elseif ($usingPrebuiltReverseSource) {
    $sourceRecord["layout_reprojection"] = [ordered]@{
        layout_digest = [string]$evidence.layout_reprojection.layout_digest
        previous_reverse_pinyin_source_sha256 = [string]$previousCoreSource.reverse_pinyin_source_sha256
        old_pinyin_codes_sha256 = [string]$evidence.layout_reprojection.old_pinyin_codes_sha256
        new_pinyin_codes_sha256 = [string]$evidence.layout_reprojection.new_pinyin_codes_sha256
        changed_dictionary_records = [int64]$evidence.layout_reprojection.changed_dictionary_records
        changed_reverse_source_rows = [int64]$evidence.layout_reprojection.changed_reverse_source_rows
        candidate_selection_changed = $false
        weights_changed = $false
    }
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
		"yime_erhua_mixed_sentence_full.dict.yaml",
		"yime_erhua_mixed_sentence_variable.dict.yaml",
		"yime_erhua_mixed_sentence_shorthand.dict.yaml",
		"yime_sentence_full.dict.yaml",
		"yime_sentence_variable.dict.yaml",
		"yime_sentence_shorthand.dict.yaml",
		"yime_third_tone_stage5c_full.dict.yaml",
		"yime_third_tone_stage5c_variable.dict.yaml",
		"yime_third_tone_stage5c_shorthand.dict.yaml",
		"yime_third_tone_stage5c_manifest.json",
		"yime_particle_a_stage6d_full.dict.yaml",
		"yime_particle_a_stage6d_variable.dict.yaml",
		"yime_particle_a_stage6d_shorthand.dict.yaml",
		"yime_particle_a_stage6d_manifest.json",
        "yime_erhua_mixed_manifest.json",
        "yime_erhua_reverse_source.tsv",
        "yime_psc_peripheral_full.dict.yaml",
        "yime_psc_peripheral_variable.dict.yaml",
        "yime_psc_peripheral_shorthand.dict.yaml",
		"yime_psc_peripheral_sentence_full.dict.yaml",
		"yime_psc_peripheral_sentence_variable.dict.yaml",
		"yime_psc_peripheral_sentence_shorthand.dict.yaml",
        "yime_psc_peripheral_manifest.json",
        "yime_pinyin_reverse_source.tsv",
        "yime_lexicon_manifest.json",
        "yime_core_source_manifest.json"
    )) {
        Copy-Item -LiteralPath (Join-Path $outputPath $name) `
            -Destination (Join-Path $userDir $name) -Force
    }
    Write-Host "Core runtime dictionaries copied to $userDir"
}
