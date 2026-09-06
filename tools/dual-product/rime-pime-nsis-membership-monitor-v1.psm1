# DP1-J-a fixture monitor module. Importing it only defines functions.
. (Join-Path $PSScriptRoot 'rime-pime-nsis-membership-monitor-v1.ps1')

Export-ModuleMember -Function @(
    'Open-RimePimeNsisMembershipMonitorV1',
    'Assert-RimePimeNsisMembershipMonitorArmedV1',
    'Complete-RimePimeNsisMembershipMonitorV1',
    'Close-RimePimeNsisMembershipMonitorV1'
)
