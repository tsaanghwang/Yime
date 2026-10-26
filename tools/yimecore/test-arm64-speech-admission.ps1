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
# Package preflight must bind the pinned admission to the native ARM lane before
# creating a build output. These envelopes are synthetic; the Go exporter still
# independently checks tools, semantics and all exported payloads.
& {
    . (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
    . (Join-Path $PSScriptRoot 'local-product-speech-build.ps1')
    $admission = Join-Path $repo ('.tmp/arm64-speech-package-'+[guid]::NewGuid().ToString('N')+'/speech-admission-synthetic')
    Assert-LocalProductPlainPath $admission
    $null = [IO.Directory]::CreateDirectory($admission)
    $inventory = Join-Path $admission 'source-hashes-after.json'
    Write-LocalProductJson @([ordered]@{path='synthetic-source';bytes=1;sha256=('a'*64)}) $inventory
    $inventorySHA = (Get-FileHash -LiteralPath $inventory -Algorithm SHA256).Hash.ToLowerInvariant()
    $product = [pscustomobject]@{speech=[pscustomobject]@{capability_path='speech-capability.json';default_enabled=$false}}
    function New-PackageAdmissionSummary {
        [ordered]@{schema_version='yimecore-speech-admission-isolated-v1';passed=$true;stage='complete';reviewed_records=24;mode_alias_rows=72
            source_inventory=[ordered]@{path='source-hashes-after.json';sha256=$inventorySHA;bytes=(Get-Item -LiteralPath $inventory).Length}
            source_inventory_before=[ordered]@{path='source-hashes-before.json';sha256=$inventorySHA;bytes=(Get-Item -LiteralPath $inventory).Length}}
    }
    function Invoke-PinnedPackagePreflight($Summary,[switch]$Arm64,[string]$Target='arm64') {
        $path = Join-Path $admission 'summary.json'
        Write-LocalProductJson $Summary $path
        $summarySHA = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Arm64) { Assert-LocalProductSpeechBuildInputs $product $admission $summarySHA $inventorySHA -ExpectedTarget $Target }
        else { Assert-LocalProductSpeechBuildInputs $product $admission $summarySHA $inventorySHA }
    }
    $x64 = New-PackageAdmissionSummary
    $x64.development_scope = [ordered]@{id='yimecore-current-development-scope-v1';computer_name='MYCOMPUTER';active_architectures=@('x64','x86')}
    $x64.go_version = 'go version go1.25.14 windows/amd64'
    Assert-AdmissionCheck (Invoke-PinnedPackagePreflight $x64) 'default legacy x64 admission remains accepted with correct pins'
    Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $x64 -Arm64 } 'native ARM64 admission' 'ARM package rejects correctly pinned x64 admission'
    $missing = New-PackageAdmissionSummary
    Assert-AdmissionCheck (Invoke-PinnedPackagePreflight $missing) 'default historical admission without scope remains accepted'
    Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $missing -Arm64 } 'native ARM64 admission' 'ARM package rejects missing admission scope'
    $native = New-PackageAdmissionSummary
    $native.development_scope = [ordered]@{id='yimecore-arm64-native-source-build-v1';target='arm64';computer_name='HUASHUONOTEBOOK'
        native_architecture='ARM64';target_architecture='arm64';active_architectures=@('arm64');build_lane='arm64_native_source_build'
        machine_observation=[ordered]@{source='IsWow64Process2';native_machine='0xaa64';native_architecture='ARM64';process_machine='0x0000'}}
    $native.go_version = 'go version go1.25.14 windows/arm64'
    Assert-AdmissionCheck (Invoke-PinnedPackagePreflight $native -Arm64) 'ARM package accepts correctly pinned native ARM admission'
    foreach ($targetCase in @('ARM64','Arm64')) {
        Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $x64 -Arm64 -Target $targetCase } 'native ARM64 admission' ("ARM target argument $targetCase still rejects x64 admission")
        Assert-AdmissionCheck (Invoke-PinnedPackagePreflight $native -Arm64 -Target $targetCase) ("ARM target argument $targetCase accepts native admission")
    }
    foreach ($field in @('id','target','computer_name','native_architecture','target_architecture','build_lane','active_architectures','machine_observation')) {
        $changed = $native | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $changed.development_scope.$field = $null
        Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $changed -Arm64 } 'native ARM64 admission' ("ARM package rejects incomplete admission $field")
    }
    foreach ($field in @('source','native_machine','native_architecture')) {
        $changed = $native | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $changed.development_scope.machine_observation.$field = 'unverified'
        Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $changed -Arm64 } 'native ARM64 admission' ("ARM package rejects unverified admission $field")
    }
    $changed = $native | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $changed.go_version = 'go version go1.25.14 windows/amd64'
    Assert-AdmissionRejected { Invoke-PinnedPackagePreflight $changed -Arm64 } 'native ARM64 admission' 'ARM package rejects x64 admission Go identity'
    $builder = Join-Path $PSScriptRoot 'build-arm64-product.ps1'
    $tokens = $null; $errors = $null
    $builderAst = [Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
    Assert-AdmissionCheck (@($errors).Count -eq 0) 'ARM builder parses'
    $commands = @($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
    $preflight = @($commands | Where-Object {$_.GetCommandName() -ceq 'Assert-LocalProductSpeechBuildInputs'})
    Assert-AdmissionCheck ($preflight.Count -eq 1) 'ARM builder has one admission preflight'
    Assert-AdmissionCheck ($preflight[0].Extent.Text -match '-ExpectedTarget\s+arm64\b') 'ARM builder explicitly requires ARM admission'
    $effects = @($commands | Where-Object {$_.GetCommandName() -cin @('New-LocalProductBuildRoot','cmake')})
    Assert-AdmissionCheck ($effects.Count -gt 0 -and @($effects | Where-Object {$_.Extent.StartOffset -lt $preflight[0].Extent.EndOffset}).Count -eq 0) 'ARM admission preflight precedes output creation and compilation'
}
Write-Output "PASS: $script:checks ARM64 speech admission host/toolchain/package contracts; no admission, installation or target process execution."
