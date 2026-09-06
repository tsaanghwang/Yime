# Definitions-only entry point. Importing it performs no build, extraction,
# signing, installation, registry, process, or user-data action.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')
Export-ModuleMember -Function '*-RimePime*'
