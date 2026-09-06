# Definitions-only entry point for the isolated receipt-v2 supersession fixture.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-supersession.ps1')
Export-ModuleMember -Function @(
    'New-RimePimeReceiptV2SupersessionFixture',
    'Open-RimePimeReceiptV2SupersessionFixture',
    'Invoke-RimePimeReceiptV2Supersession',
    'Resume-RimePimeReceiptV2Supersession',
    'Get-RimePimeReceiptV2SupersessionHead',
    'Get-RimePimeReceiptV2SupersessionJournal'
)
