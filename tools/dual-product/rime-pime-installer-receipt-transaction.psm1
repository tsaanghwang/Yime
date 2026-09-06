# Definitions-only isolated DP1-N entry point. Importing this module performs
# no build, installer, uninstaller, registry, process, or user-data action.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')
. (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')
. (Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.ps1')
Export-ModuleMember -Function @(
    'Publish-RimePimeInstallerReceiptTransaction',
    'Resume-RimePimeInstallerReceiptTransaction'
)
