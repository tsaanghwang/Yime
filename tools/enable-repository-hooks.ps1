param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$hooks = Join-Path $repoRoot '.githooks'
foreach ($name in @('pre-commit', 'commit-msg', 'pre-push')) {
    $path = Join-Path $hooks $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing repository hook: $path"
    }
}

& git -C $repoRoot config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to set core.hooksPath.'
}
Write-Host "Enabled Yime repository gates: $hooks"
