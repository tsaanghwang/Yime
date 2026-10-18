[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
$expectedCommit = '0ab8631266736775bf1386f456d4a1d53e8e2eb3'
$commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve source commit for $RepoRoot"
}
if ($commit -cne $expectedCommit) {
    throw "Unexpected source $commit; expected $expectedCommit"
}
Write-Host "Verified exact source commit $commit"
