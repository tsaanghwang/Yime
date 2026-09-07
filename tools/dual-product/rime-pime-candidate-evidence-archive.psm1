# Definitions-only entry point for the fixture-gated DP1-Q candidate evidence
# archive protocol. Importing this module performs no build, installation,
# registry, process, user-data, actual-checkout, or external-archive action.
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')
. (Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.ps1')
Export-ModuleMember -Function @(
    'Publish-RimePimeCandidateEvidenceArchive',
    'Resume-RimePimeCandidateEvidenceArchive',
    'Read-RimePimeCandidateEvidenceArchive'
)
