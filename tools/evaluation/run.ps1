[CmdletBinding()]
param(
    [string]$Python = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $evaluationRoot "..\..")).Path
$runner = Join-Path $repoRoot "tools\lexicon\invoke-python.ps1"
if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot ".generated\evaluation\approved_target"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

& $runner -Python $Python `
    (Join-Path $evaluationRoot "evaluate_modes.py") `
    --output (Join-Path $resolvedOutput "mode_efficiency.json")
if ($LASTEXITCODE -ne 0) {
    throw "Three-mode efficiency evaluation failed."
}

& $runner -Python $Python `
    (Join-Path $evaluationRoot "compare_layout.py") `
    --candidate-layout (Join-Path $repoRoot "internal_data\manual_key_layout.json") `
    --output-dir (Join-Path $resolvedOutput "canonical_layout_baseline")
if ($LASTEXITCODE -ne 0) {
    throw "Canonical layout baseline evaluation failed."
}

Write-Host "Target-locked evaluation passed: $resolvedOutput"
