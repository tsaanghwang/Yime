# Definitions-only entry point for static post-build NSIS archive verification.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1') -Force
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1') -Force
. (Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.ps1')
Export-ModuleMember -Function '*-RimePimePostbuild*'
