[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$script:arm64Checks = 0
function Assert-Arm64Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "ARM64 build-scope regression: $Name" }
    $script:arm64Checks++
}
function Assert-Arm64Rejected([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Arm64Check $rejected $Name
}
$target = Get-YimeCoreExperimentTarget 'arm64'
$native = [ordered]@{ source='IsWow64Process2'; native_machine='0xaa64'; native_architecture='ARM64'; process_machine='0x0000' }
Assert-YimeCoreArm64BuildHost $target 'HUASHUONOTEBOOK' $native $true
Assert-Arm64Check $true 'identified ARM64 host accepted for source build'
Assert-Arm64Rejected { Assert-YimeCoreArm64BuildHost $target 'OTHER-PC' $native $true } 'unlisted ARM64 host rejected'
Assert-Arm64Rejected { Assert-YimeCoreArm64BuildHost $target 'HUASHUONOTEBOOK' $native $false } '32-bit orchestration rejected'
foreach ($field in @('source','native_machine','native_architecture')) {
    $changed = [ordered]@{}; foreach ($key in $native.Keys) { $changed[$key] = $native[$key] }
    $changed[$field] = 'unverified'
    Assert-Arm64Rejected { Assert-YimeCoreArm64BuildHost $target 'HUASHUONOTEBOOK' $changed $true } ("unverified $field rejected")
}
$wrongTarget = $target | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$wrongTarget.physical_host.computer_name = 'OTHER-PC'
Assert-Arm64Rejected { Assert-YimeCoreArm64BuildHost $wrongTarget 'OTHER-PC' $native $true } 'policy cannot silently admit another native host'
$wrongTarget = $target | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$wrongTarget.physical_host.approved_uses = @('host_inventory')
Assert-Arm64Rejected { Assert-YimeCoreArm64BuildHost $wrongTarget 'HUASHUONOTEBOOK' $native $true } 'inventory-only authorization cannot build'

# Query the real native-machine API under misleading environment labels. The
# helper is read-only and must not depend on those process observations.
$observed = Get-YimeCoreNativeMachine
$savedArchitecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE','Process')
$savedWow64 = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432','Process')
try {
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
    $misleading = Get-YimeCoreNativeMachine
    Assert-Arm64Check ($misleading.source -ceq 'IsWow64Process2' -and
        $misleading.native_machine -ceq $observed.native_machine -and
        $misleading.native_architecture -ceq $observed.native_architecture) 'native API overrides misleading environment labels'
} finally {
    [Environment]::SetEnvironmentVariable('PROCESSOR_ARCHITECTURE',$savedArchitecture,'Process')
    [Environment]::SetEnvironmentVariable('PROCESSOR_ARCHITEW6432',$savedWow64,'Process')
}

# Preserve the original cross-build route; do not run its host-specific build.
& {
    function Get-YimeCoreNativeMachine { [ordered]@{ source='IsWow64Process2'; native_machine='0x8664'; native_architecture='AMD64'; process_machine='0x0000' } }
    function Get-YimeCoreDevelopmentScope { [ordered]@{ id='original-pinned-scope'; computer_name='MYCOMPUTER'; active_architectures=@('x64','x86') } }
    $cross = Get-YimeCoreExperimentBuildScope 'arm64'
    Assert-Arm64Check ($cross.id -ceq 'original-pinned-scope' -and $cross.computer_name -ceq 'MYCOMPUTER' -and
        $cross.build_lane -ceq 'arm64_cross_build' -and ($cross.active_architectures -join '|') -ceq 'x64|x86') 'AMD64 ARM target still invokes pinned development scope'
}
& {
    function Get-YimeCoreNativeMachine { throw 'simulated native API unavailable' }
    function Get-YimeCoreDevelopmentScope { throw 'incorrect environment fallback' }
    try {
        Get-YimeCoreExperimentBuildScope 'arm64' | Out-Null
        throw 'native API failure was ignored'
    } catch {
        Assert-Arm64Check ($_.Exception.Message -ceq 'simulated native API unavailable') 'API failure cannot enter an environment fallback'
    }
}
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'development-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-YimeCoreDevelopmentHost $policy 'MYCOMPUTER' 'AMD64' $true
Assert-Arm64Check $true 'original pinned x64/x86 host remains accepted'
Assert-Arm64Rejected { Assert-YimeCoreDevelopmentHost $policy 'HUASHUONOTEBOOK' 'ARM64' $true } 'new host cannot enter local x64 product lane'

$nativeScope = [ordered]@{ build_lane='arm64_native_source_build' }
foreach ($generator in @('Visual Studio 17 2022','Visual Studio 18 2026')) {
    Assert-Arm64Check ((Resolve-YimeCorePlatformGenerator 'arm64' $nativeScope $generator) -ceq $generator) ("native explicit generator: $generator")
}
Assert-Arm64Rejected { Resolve-YimeCorePlatformGenerator 'arm64' $nativeScope '' } 'native generator cannot be guessed'
Assert-Arm64Rejected { Resolve-YimeCorePlatformGenerator 'arm64' $nativeScope 'Ninja' } 'unreviewed native generator rejected'
$crossScope = [ordered]@{ build_lane='arm64_cross_build' }
Assert-Arm64Check ((Resolve-YimeCorePlatformGenerator 'arm64' $crossScope '') -ceq 'Visual Studio 17 2022') 'cross-build keeps VS2022'
Assert-Arm64Rejected { Resolve-YimeCorePlatformGenerator 'arm64' $crossScope 'Visual Studio 18 2026' } 'cross-build generator cannot silently change'
Assert-Arm64Check ((Resolve-YimeCorePlatformGenerator 'mainstream_x64' @{} '') -ceq 'Visual Studio 18 2026') 'mainstream keeps VS2026'
Assert-Arm64Rejected { Resolve-YimeCorePlatformGenerator 'mainstream_x64' @{} 'Visual Studio 17 2022' } 'mainstream generator cannot silently change'
Write-Output "PASS: $script:arm64Checks ARM64 source-build scope contracts; no build, target execution or installation."
