[CmdletBinding()]
param(
    [string]$Python = "",
    [string]$OutputDir = "",
    [string]$PackageRoot = "",
    [Parameter(Mandatory = $true)]
    [string]$ExternalRestoreEvidence
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $toolRoot "..\..")).Path
$runner = Join-Path $toolRoot "invoke-python.ps1"
$resolvedRestoreEvidence = (Resolve-Path -LiteralPath $ExternalRestoreEvidence).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot ".generated\release_acceptance"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

# This is intentionally first. A blocked source identity must stop the release
# before dictionaries, package payloads or installers are regenerated.
& $runner -Python $Python `
    (Join-Path $toolRoot "verify_release_readiness.py") `
    --require-release `
    --external-restore-evidence $resolvedRestoreEvidence
if ($LASTEXITCODE -ne 0) {
    throw "Release acceptance stopped at source reproducibility or external restore evidence; no package action is allowed."
}

& (Join-Path $toolRoot "test.ps1") -Python $Python
if ($LASTEXITCODE -ne 0) { throw "Offline lexicon tests failed." }

& (Join-Path $toolRoot "replay-approved-handoff.ps1") `
    -Python $Python `
    -OutputDir (Join-Path $resolvedOutput "handoff_replay")
if ($LASTEXITCODE -ne 0) { throw "Approved handoff replay failed." }

& (Join-Path $repoRoot "tools\evaluation\run.ps1") `
    -Python $Python `
    -OutputDir (Join-Path $resolvedOutput "evaluation")
if ($LASTEXITCODE -ne 0) { throw "Target-locked evaluation failed." }

if ($PackageRoot) {
    & $runner -Python $Python `
        (Join-Path $toolRoot "verify_package_handoff.py") `
        --package-root $PackageRoot `
        --output (Join-Path $resolvedOutput "package_handoff.json")
    if ($LASTEXITCODE -ne 0) { throw "Packaged handoff verification failed." }
}

Write-Host "Yime lexicon release acceptance passed: $resolvedOutput"
