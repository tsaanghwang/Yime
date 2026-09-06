# Isolated DP1-I fixture transaction-journal module. Importing this module
# defines helpers only and performs no filesystem, registry, process, installer,
# or uninstaller action.
. (Join-Path $PSScriptRoot 'rime-pime-fixture-transaction-journal.ps1')
Export-ModuleMember -Function @(
    'New-RimePimeFixtureTransactionContext',
    'Assert-RimePimeFixtureTransactionContext',
    'Open-RimePimeFixtureJournalLock',
    'Close-RimePimeFixtureJournalLock',
    'Get-RimePimeFixtureRegistryCoordinateCatalog',
    'New-RimePimeFixtureRegistryRecord',
    'New-RimePimeFixtureRegistryState',
    'Assert-RimePimeFixtureRegistryState',
    'Write-RimePimeFixtureRegistryState',
    'Read-RimePimeFixtureRegistryState',
    'Write-RimePimeFixtureInstallFile',
    'New-RimePimeFixtureRemovalManifest',
    'Assert-RimePimeFixtureRemovalManifest',
    'Write-RimePimeFixtureRemovalManifest',
    'Read-RimePimeFixtureRemovalManifest',
    'Get-RimePimeFixtureRemovalPlan',
    'Test-RimePimeFixtureRemovalClosure',
    'Invoke-RimePimeFixtureExactRemoval',
    'New-RimePimeFixturePreparedRecord',
    'Start-RimePimeFixtureTransaction',
    'Get-RimePimeFixtureOperationId',
    'Add-RimePimeFixtureStep',
    'Complete-RimePimeFixtureCommit',
    'Complete-RimePimeFixtureTerminal',
    'Read-RimePimeFixtureJournal',
    'Resume-RimePimeFixtureTransaction'
)
