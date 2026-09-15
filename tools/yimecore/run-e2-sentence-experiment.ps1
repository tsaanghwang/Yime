[CmdletBinding()]
param(
    [int]$Iterations = 100,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run-e1-index-experiment.ps1'
$arguments = @{
    Iterations = $Iterations
    Stage = 'e2'
}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $arguments.OutputRoot = $OutputRoot
}
& $runner @arguments
