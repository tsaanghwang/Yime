# Isolated module entry point for deterministic NSIS stage include generation.
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.ps1')
Export-ModuleMember -Function '*-RimePimeNsis*'
