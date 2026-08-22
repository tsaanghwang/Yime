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
    [string]$RepositoryImportApproval = "",
    [string]$PimeRoot = "",
    [string]$RimeUserDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $PimeRoot) {
    $PimeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}
if (-not $RimeUserDir) {
    $RimeUserDir = Join-Path $env:APPDATA "PIME\Rime"
}

$sharedDir = Join-Path $PimeRoot "go-backend\input_methods\yime\data"
$importer = Join-Path $PSScriptRoot "import-yime-core-lexicon.ps1"

# The curated fixed-length core is the only imported runtime candidate set.
# Its evidence manifest proves ranking provenance before all modes are derived.
& $importer -InputPath $InputPath -EvidenceManifest $EvidenceManifest `
    -SourceRevision $SourceRevision `
    -PronunciationEntries $PronunciationEntries `
    -RepositoryImportApproval $RepositoryImportApproval `
    -OutputDir $sharedDir
if ($LASTEXITCODE -ne 0) {
    throw "Yime lexicon import failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Path $RimeUserDir -Force | Out-Null
foreach ($mode in @("full", "variable", "shorthand")) {
    foreach ($suffix in @("dict.yaml", "schema.yaml")) {
        $name = "yime_${mode}.${suffix}"
        Copy-Item -LiteralPath (Join-Path $sharedDir $name) -Destination (Join-Path $RimeUserDir $name) -Force
    }
    $overlayName = "yime_erhua_mixed_${mode}.dict.yaml"
    Copy-Item -LiteralPath (Join-Path $sharedDir $overlayName) `
        -Destination (Join-Path $RimeUserDir $overlayName) -Force
    $overlaySchemaName = "yime_erhua_mixed_${mode}.schema.yaml"
    Copy-Item -LiteralPath (Join-Path $sharedDir $overlaySchemaName) `
        -Destination (Join-Path $RimeUserDir $overlaySchemaName) -Force
	$erhuaSentenceName = "yime_erhua_mixed_sentence_${mode}.dict.yaml"
	Copy-Item -LiteralPath (Join-Path $sharedDir $erhuaSentenceName) `
		-Destination (Join-Path $RimeUserDir $erhuaSentenceName) -Force
	$sentenceName = "yime_sentence_${mode}.dict.yaml"
	Copy-Item -LiteralPath (Join-Path $sharedDir $sentenceName) `
		-Destination (Join-Path $RimeUserDir $sentenceName) -Force
	$thirdToneName = "yime_third_tone_stage5c_${mode}.dict.yaml"
	Copy-Item -LiteralPath (Join-Path $sharedDir $thirdToneName) `
		-Destination (Join-Path $RimeUserDir $thirdToneName) -Force
	$particleAName = "yime_particle_a_stage6d_${mode}.dict.yaml"
	Copy-Item -LiteralPath (Join-Path $sharedDir $particleAName) `
		-Destination (Join-Path $RimeUserDir $particleAName) -Force
    $pscOverlayName = "yime_psc_peripheral_${mode}.dict.yaml"
    Copy-Item -LiteralPath (Join-Path $sharedDir $pscOverlayName) `
        -Destination (Join-Path $RimeUserDir $pscOverlayName) -Force
    $pscOverlaySchemaName = "yime_psc_peripheral_${mode}.schema.yaml"
    Copy-Item -LiteralPath (Join-Path $sharedDir $pscOverlaySchemaName) `
        -Destination (Join-Path $RimeUserDir $pscOverlaySchemaName) -Force
	$pscSentenceName = "yime_psc_peripheral_sentence_${mode}.dict.yaml"
	Copy-Item -LiteralPath (Join-Path $sharedDir $pscSentenceName) `
		-Destination (Join-Path $RimeUserDir $pscSentenceName) -Force
}
# Do not copy the generation manifest here. On the next YIME startup, the
# stale or absent user manifest makes RefreshRimeData atomically refresh the
# dictionaries, re-encode custom_phrase_*.txt, and write the manifest last.

Write-Host "Yime single-source data generated and deployed."
Write-Host "  imported source: $((Resolve-Path -LiteralPath $InputPath).Path)"
Write-Host "  generated data:  $sharedDir"
Write-Host "  PIME user dir:   $RimeUserDir"
Write-Host "Redeploy Rime or restart the installed YIME runtime before verification."
