# Definitions-only entry point. Importing it performs no build, extraction,
# signing, installation, registry, process, or user-data action.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.psm1')
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')
. (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')
Export-ModuleMember -Function @(
    'New-RimePimePackageReceiptV2Preparation',
    'Close-RimePimePackageReceiptV2Preparation',
    'Publish-RimePimePackageReceiptV2',
    'Read-RimePimePackageBuildReceiptV2',
    'Publish-RimePimePackageReceiptV2Supersession',
    'Resume-RimePimePackageReceiptV2Publication'
)
