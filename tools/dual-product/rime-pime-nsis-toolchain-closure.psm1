# Definitions-only entry point for the repository-pinned NSIS distribution
# input closure. Importing this module does not execute makensis or any product
# binary and performs no installation or registration action.
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force
. (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.ps1')
Export-ModuleMember -Function Open-RimePimeNsisCompilerInputClosure,Test-RimePimeNsisCompilerInputClosure,Close-RimePimeNsisCompilerInputClosure,Read-RimePimeNsisCompilerToolchainLockDocument,Test-RimePimeNsisCompilerToolchainLockDocument

. (Join-Path $PSScriptRoot 'rime-pime-nsis-membership-monitor-v1.ps1')
. (Join-Path $PSScriptRoot 'rime-pime-nsis-compiler-interval.ps1')
Export-ModuleMember -Function Open-RimePimeMonitoredNsisStage,Complete-RimePimeMonitoredNsisStage,Close-RimePimeMonitoredNsisStage
