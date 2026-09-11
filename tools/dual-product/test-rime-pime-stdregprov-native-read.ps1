[CmdletBinding()]
param()
# Read-only native regression: no registration, writes, private identity or learning reads.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
foreach ($view in @('Registry32','Registry64')) {
    if (-not (Test-YimePimeSystemRegistryKeyExists -Hive LocalMachine -View $view -Key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion')) {
        throw "Known Windows registry key absent in $view"
    }
    $architecture = if ($view -eq 'Registry32') {32} else {64}
    $reply = @(Invoke-YimePimeSystemRegistryMethod -Method GetStringValue -Hive ([uint32]2147483650) -Key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ProviderArchitecture $architecture -Values @{sValueName='ProductName'})
    if ($reply.Count -ne 1 -or $reply[0].ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace($reply[0].sValue)) {
        throw "Expected one valid registry result in $view"
    }
    Write-Output "PASS: $view native key existence and string read; one result; no writes."
}
