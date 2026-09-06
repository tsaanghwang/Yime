# Isolated definitions-only entry point for staged installer build leases and
# fail-closed canonical publication.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.ps1')
Export-ModuleMember -Function '*-RimePime*'
