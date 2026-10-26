[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$script:checks = 0
function Assert-AdmissionCheck([bool]$Passed, [string]$Name) {
    if (-not $Passed) { throw "ARM64 speech admission regression: $Name" }
    $script:checks++
}
function Assert-AdmissionRejected([scriptblock]$Action, [string]$Message, [string]$Name) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-AdmissionCheck ($null -ne $caught -and $caught -match $Message) $Name
}
$runner = Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
Assert-AdmissionCheck (@($errors).Count -eq 0) 'runner parses'
$functions = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false) |
    Where-Object Name -CEQ 'Get-SpeechAdmissionGoArchitecture')
Assert-AdmissionCheck ($functions.Count -eq 1) 'architecture function is unambiguous'
. ([scriptblock]::Create($functions[0].Extent.Text))
$scope = [ordered]@{ target='arm64'; build_lane='arm64_native_source_build'; native_architecture='ARM64'; computer_name='HUASHUONOTEBOOK';
    machine_observation=[ordered]@{source='IsWow64Process2';native_machine='0xaa64';process_machine='0x0000'} }
Assert-AdmissionCheck ((Get-SpeechAdmissionGoArchitecture arm64 $scope) -ceq 'arm64') 'registered native scope chooses arm64'
foreach ($field in @('target','build_lane','native_architecture','computer_name')) {
    $changed = $scope | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $changed.$field = 'unapproved'
    Assert-AdmissionRejected { Get-SpeechAdmissionGoArchitecture arm64 $changed } 'identified native ARM64' ("reject changed $field")
}
foreach ($field in @('source','native_machine')) {
    $changed = $scope | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $changed.machine_observation.$field = 'unverified'
    Assert-AdmissionRejected { Get-SpeechAdmissionGoArchitecture arm64 $changed } 'identified native ARM64' ("reject unverified $field")
}
Assert-AdmissionCheck ((Get-SpeechAdmissionGoArchitecture '' @{}) -ceq 'amd64') 'default stays amd64'
Assert-AdmissionCheck ((Get-SpeechAdmissionGoArchitecture mainstream_x64 @{}) -ceq 'amd64') 'mainstream stays amd64'
Assert-AdmissionRejected { Get-SpeechAdmissionGoArchitecture unlisted @{} } 'Unapproved' 'unknown target rejected'

foreach ($response in @(@('windows','amd64'),@('windows','arm64'),@('windows','386'),@('linux','amd64'))) {
    & {
        function go { $global:LASTEXITCODE=0; $response }
        $rejected=$false
        try { Assert-YimeCoreNativeGo } catch { $rejected=$true }
        Assert-AdmissionCheck ($rejected -eq (($response -join '|') -cne 'windows|amd64')) ("legacy Go target $($response -join '/')")
    }
}
& {
    function Get-YimeCoreExperimentBuildScope { throw 'host guard rejected' }
    function go { throw 'Go must not run before the host guard' }
    Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget mainstream_x64 } '^host guard rejected$' 'mainstream host guard retained'
    Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget arm64 } '^host guard rejected$' 'ARM host guard runs first'
}
& {
    function Get-YimeCoreExperimentBuildScope { [ordered]@{build_lane='arm64_cross_build'} }
    Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget arm64 } 'not the cross-build lane' 'cross-build Go cannot execute as native admission'
}
& {
    function Get-YimeCoreExperimentBuildScope { [ordered]@{build_lane='arm64_native_source_build'} }
    Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget arm64 } 'explicit absolute executable path' 'ARM Go cannot resolve from ambient PATH'
}

# Static PE fixtures are never launched. Rejection must occur before invocation.
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureParent = [IO.Path]::GetFullPath((Join-Path $repo '.tmp'))
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $fixtureParent ('arm64-speech-gate-'+[guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($fixtureParent+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped workspace' }
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
try {
    $fixture = Join-Path $fixtureRoot 'go.exe'
    [IO.File]::WriteAllBytes($fixture,[byte[]]@(0,1,2,3))
    & {
        function Get-YimeCoreExperimentBuildScope { [ordered]@{build_lane='arm64_native_source_build'} }
        Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget arm64 -GoExecutable $fixture } 'DOS header' 'invalid executable rejected before launch'
    }
    $bytes = [byte[]]::new(256)
    [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes,0)
    [BitConverter]::GetBytes([uint32]128).CopyTo($bytes,0x3c)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes,128)
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes,132)
    [IO.File]::WriteAllBytes($fixture,$bytes)
    & {
        function Get-YimeCoreExperimentBuildScope { [ordered]@{build_lane='arm64_native_source_build'} }
        Assert-AdmissionRejected { Assert-YimeCoreNativeGo -ExperimentTarget arm64 -GoExecutable $fixture } 'PE machine 0xAA64' 'x64 Go rejected before launch on ARM scope'
    }
} finally {
    if ([IO.File]::Exists($fixture)) { [IO.File]::Delete($fixture) }
    [IO.Directory]::Delete($fixtureRoot,$false)
}
Write-Output "PASS: $script:checks ARM64 speech admission host/toolchain contracts; no admission, installation or target process execution."
