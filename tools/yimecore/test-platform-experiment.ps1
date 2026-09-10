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
$mainstream=(& $entry -Target mainstream_x64)|ConvertFrom-Json
Check ($mainstream.physical_host.computer_name -ceq '计算机' -and $mainstream.physical_host.owner -ceq 'developer') 'identified mainstream physical host'
foreach($target in @('unlisted','x86','forward_looking')){
    $rejected=$false;try{& $entry -Target $target | Out-Null}catch{$rejected=$true}
    Check $rejected 'unlisted target rejected'
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'entry parses'
$text=Get-Content -LiteralPath $entry -Raw
Check ($text -match 'Assert-LocalProductSourceUnchanged' -and $text -match 'Assert-LocalProductPlainPath') 'source and output guard'
Check ($text -match "ValidateSet\('Plan','Build','Package'\)" -and $text -match "build-local-product\.ps1.*ExperimentTarget") 'target-scoped package entry'
Check ($text -match 'Get-YimeCoreExperimentBuildScope' -and $text -notmatch 'Get-YimeCoreDevelopmentScope') 'experiment build does not enter MYCOMPUTER lane'
Check ($text -match 'Package requires an explicit completed speech admission root and both SHA256 pins' -and $text -match 'ExpectedSpeechSourceInventorySha256') 'package refuses an unpinned speech admission'
Check ($text -match "mainstream_x64'\)\{'Visual Studio 18 2026'\}" -and $text -match "else\{'Visual Studio 17 2022'\}") 'target host uses its installed Visual Studio generation'
Check ($text -match "mx64-package-" -and $text -match "Output name must identify") 'mainstream package path remains attributable and short enough for native fixtures'
Check ($text -match 'Get-LocalProductProtectionEvidence' -and $text -match 'protected_registration_unchanged') 'registration comparison'
Check ($text -notmatch 'Start-Process|Stop-Process|register-com|regsvr32|ctest') 'build entry cannot execute target or maintenance'
Check ($text -match '0xaa64' -and $text -match '0x8664') 'both PE machines verified'
$managerText=Get-Content (Join-Path $PSScriptRoot 'manage-local-product.ps1') -Raw
Check ($managerText -match 'Get-YimeCoreExperimentBuildScope \$experimentTarget' -and
    $managerText.IndexOf("if (`$Action -ne 'Plan') { Assert-YimeCoreUnpackagedDataMaintenance }") -lt
        $managerText.IndexOf('$package=Assert-LocalProductPackage')) `
    'experiment package uses its physical-host scope after the unpackaged mutation guard'
$trialManagerText=Get-Content (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') -Raw
Check ($trialManagerText -match '\$scopePackage=Assert-Package \$PackageRoot' -and
    $trialManagerText -match 'Get-YimeCoreExperimentBuildScope \$experimentTarget' -and
    $trialManagerText.IndexOf('$scopePackage=Assert-Package $PackageRoot') -lt
        $trialManagerText.IndexOf("if (`$Action -ne 'Plan' -and -not (Test-Administrator))")) `
    'shared transaction manager validates the package and exact experiment host before elevation'
$isolationText=Get-Content (Join-Path $PSScriptRoot 'local-product-test-isolation.ps1') -Raw
Check ($isolationText -match '\$fixture = Join-Path \$build \(''t\\''' -and
    $isolationText -match '\$fixtureTemp\.Length -gt 120') `
    'runtime evidence can remain descriptive while native TEMP stays below its path limit'
$cmake=Get-Content (Join-Path $PSScriptRoot '../../YimeTextServiceExperiment/CMakeLists.txt') -Raw
Check ($cmake -match 'CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64"' -and $cmake -match 'YIME_LOCAL_PRODUCT') 'ARM64 current-identity CMake lane'
Write-Output "PASS: $count platform experiment contracts; no target binaries executed."
