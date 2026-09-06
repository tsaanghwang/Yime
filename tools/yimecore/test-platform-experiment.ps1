[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$entry=Join-Path $PSScriptRoot 'run-platform-experiment.ps1'
$count=0
function Check([bool]$condition,[string]$label){if(-not $condition){throw "FAIL: $label"};$script:count++}
foreach($target in @('mainstream_x64','arm64')){
    $plan=(& $entry -Target $target)|ConvertFrom-Json
    Check ($plan.target -eq $target -and $plan.status -eq 'active') "$target active"
    Check ($null -eq $plan.physical_host_passed -and -not $plan.installed) "$target no false acceptance"
    Check (-not $plan.cloud_provisioning_authorized -and -not $plan.hardware_purchase_authorized) "$target no provisioning"
}
foreach($target in @('unlisted','x86','forward_looking')){
    $rejected=$false;try{& $entry -Target $target | Out-Null}catch{$rejected=$true}
    Check $rejected 'unlisted target rejected'
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'entry parses'
$text=Get-Content -LiteralPath $entry -Raw
Check ($text -match 'Assert-LocalProductSourceUnchanged' -and $text -match 'Assert-LocalProductPlainPath') 'source and output guard'
Check ($text -match 'Get-LocalProductProtectionEvidence' -and $text -match 'protected_registration_unchanged') 'registration comparison'
Check ($text -notmatch 'Start-Process|Stop-Process|register-com|regsvr32|ctest') 'build entry cannot execute target or maintenance'
Check ($text -match '0xaa64' -and $text -match '0x8664') 'both PE machines verified'
$cmake=Get-Content (Join-Path $PSScriptRoot '../../YimeTextServiceExperiment/CMakeLists.txt') -Raw
Check ($cmake -match 'CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64"' -and $cmake -match 'YIME_LOCAL_PRODUCT') 'ARM64 current-identity CMake lane'
Write-Output "PASS: $count platform experiment contracts; no target binaries executed."
