param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot 'check-libime2-change-boundary.ps1'
$zero = '0' * 40
$checked = 0

foreach ($line in @($input)) {
    $parts = @(([string]$line).Trim() -split '\s+')
    if ($parts.Count -lt 4) {
        continue
    }
    $localSha = $parts[1]
    $remoteSha = $parts[3]
    if (-not $localSha -or $localSha -eq $zero) {
        continue
    }
    $arguments = @{
        RepoRoot = $RepoRoot
        HeadRef = $localSha
    }
    if ($remoteSha -and $remoteSha -ne $zero) {
        $arguments.BaseRef = $remoteSha
    }
    & $checker @arguments
    $checked++
}

if ($checked -eq 0) {
    Write-Host 'libIME2 pre-push: no new commits to check.'
}
