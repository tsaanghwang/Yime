[CmdletBinding()]
param(
    [string]$OutputDir = "",
    [string]$SourceRevision = "",
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $toolRoot "..\..")).Path
$runner = Join-Path $toolRoot "invoke-python.ps1"
$lock = Join-Path $toolRoot "data\yime_core_target.lock.json"
$handoff = Join-Path $toolRoot "handoff\yime_core_fixed.dict.yaml"
$evidence = Join-Path $toolRoot "handoff\yime_core_fixed.evidence.json"
$dataDir = Join-Path $repoRoot "go-backend\input_methods\yime\data"
$reverseSource = Join-Path $dataDir "yime_pinyin_reverse_source.tsv"
$previousSource = Join-Path $dataDir "yime_core_source_manifest.json"
$importer = Join-Path $repoRoot "tools\import-yime-core-lexicon.ps1"
$verifier = Join-Path $toolRoot "verify_replayed_handoff.py"

if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot ".generated\approved_core_handoff_replay"
}
if (Test-Path -LiteralPath $OutputDir) {
    $existing = @(Get-ChildItem -LiteralPath $OutputDir -Force -ErrorAction Stop)
    if ($existing.Count -gt 0) {
        throw "Replay output directory must be new or empty: $OutputDir"
    }
}
else {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

if (-not $SourceRevision) {
    $SourceRevision = (& git -C $repoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $SourceRevision) {
        throw "Cannot resolve the Yime source revision."
    }
}

& $runner -Python $Python (Join-Path $toolRoot "verify_target_lock.py")
if ($LASTEXITCODE -ne 0) {
    throw "Approved target lock verification failed."
}

& $importer `
    -InputPath $handoff `
    -EvidenceManifest $evidence `
    -SourceRevision $SourceRevision `
    -PrebuiltReverseSource $reverseSource `
    -PreviousCoreSourceManifest $previousSource `
    -ApprovedTargetLock $lock `
    -OutputDir $resolvedOutput
if ($LASTEXITCODE -ne 0) {
    throw "Approved core handoff replay failed with exit code $LASTEXITCODE."
}

& $runner -Python $Python $verifier --output-dir $resolvedOutput
if ($LASTEXITCODE -ne 0) {
    throw "Replayed handoff verification failed."
}

Write-Host "Approved Yime-local handoff replay passed: $resolvedOutput"
