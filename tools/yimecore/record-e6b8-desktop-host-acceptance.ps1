[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$StageRoot,
    [Parameter(Mandatory)] [string]$InstallRoot,
    [Parameter(Mandatory)] [int]$HostProcessId,
    [Parameter(Mandatory)] [int]$BrokerProcessId,
    [string]$OutputRoot,
    [string]$HostName = 'Microsoft Word 16 x64',
    [string]$CommittedText = '其',
    [switch]$InitialCandidateObserved,
    [switch]$HostTerminationObserved,
    [switch]$ReconnectCandidateObserved,
    [switch]$ShiftOrdinalCommitObserved
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment\e6b8'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$outputPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputDir.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B8 evidence must stay under $allowedRoot"
}
if (Test-Path -LiteralPath $outputDir) {
    if (@(Get-ChildItem -LiteralPath $outputDir -Force).Count -ne 0) {
        throw "E6-B8 evidence directory must be new or empty: $outputDir"
    }
} else {
    New-Item -ItemType Directory -Force $outputDir | Out-Null
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
if ($dirty) { throw 'E6-B8 formal evidence requires a clean commit' }

$resolvedStageRoot = [IO.Path]::GetFullPath($StageRoot)
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if (-not (Test-Path -LiteralPath $resolvedStageRoot -PathType Container)) {
    throw "missing staged package root: $resolvedStageRoot"
}
if (-not (Test-Path -LiteralPath $resolvedInstallRoot -PathType Container)) {
    throw "missing installed package root: $resolvedInstallRoot"
}

function Get-PackageRecords([string]$root) {
    $normalizedRoot = [IO.Path]::GetFullPath($root)
    @(Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object path)
}

$stagedRecords = @(Get-PackageRecords $resolvedStageRoot)
$installedRecords = @(Get-PackageRecords $resolvedInstallRoot)
if ($stagedRecords.Count -ne $installedRecords.Count) {
    throw 'staged and installed package file counts differ'
}
[long]$packageBytes = 0
for ($index = 0; $index -lt $stagedRecords.Count; $index++) {
    $staged = $stagedRecords[$index]
    $installed = $installedRecords[$index]
    if ($staged.path -ne $installed.path -or $staged.bytes -ne $installed.bytes -or
        $staged.sha256 -ne $installed.sha256) {
        throw "package handoff mismatch for $($staged.path)"
    }
    $packageBytes += [long]$staged.bytes
}
$handoffPath = Join-Path $outputDir 'package-handoff.json'
[ordered]@{
    staged_root = $resolvedStageRoot
    installed_root = $resolvedInstallRoot
    file_count = $stagedRecords.Count
    total_bytes = $packageBytes
    all_hashes_verified = $true
    files = $stagedRecords
} | ConvertTo-Json -Depth 6 | Set-Content $handoffPath -Encoding utf8

$clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$x64Registry = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
$x86Registry = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid\InprocServer32"
$x64Path = (Get-ItemProperty -LiteralPath $x64Registry).'(default)'
$x86Path = (Get-ItemProperty -LiteralPath $x86Registry).'(default)'
$expectedX64 = Join-Path $resolvedInstallRoot 'x64\YimeTextServiceExperiment.dll'
$expectedX86 = Join-Path $resolvedInstallRoot 'x86\YimeTextServiceExperiment.dll'
if (-not $x64Path.Equals($expectedX64, [StringComparison]::OrdinalIgnoreCase) -or
    -not $x86Path.Equals($expectedX86, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'installed COM paths do not match the E6-B8 package root'
}
$registrationPath = Join-Path $outputDir 'registration.json'
[ordered]@{
    clsid = $clsid
    x64_path = $x64Path
    x64_sha256 = (Get-FileHash -LiteralPath $x64Path -Algorithm SHA256).Hash.ToLowerInvariant()
    x86_path = $x86Path
    x86_sha256 = (Get-FileHash -LiteralPath $x86Path -Algorithm SHA256).Hash.ToLowerInvariant()
    both_registry_views_match_install_root = $true
} | ConvertTo-Json -Depth 4 | Set-Content $registrationPath -Encoding utf8

$hostProcess = Get-Process -Id $HostProcessId
$loadedModule = @($hostProcess.Modules | Where-Object {
    $_.ModuleName -eq 'YimeTextServiceExperiment.dll'
})
if ($hostProcess.ProcessName -ne 'WINWORD' -or $loadedModule.Count -ne 1 -or
    -not $loadedModule[0].FileName.Equals($expectedX64, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'the observed desktop host is not using the installed x64 experiment DLL'
}
$brokerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $BrokerProcessId"
$expectedBroker = Join-Path $resolvedInstallRoot 'bin\YimeBroker.exe'
$defaultPipe = '\\.\pipe\YimeBroker.YimeCoreTrial.v1'
if (-not $brokerProcess -or
    -not $brokerProcess.ExecutablePath.Equals($expectedBroker, [StringComparison]::OrdinalIgnoreCase) -or
    $brokerProcess.CommandLine.IndexOf($defaultPipe, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw 'the observed desktop host is not using the installed Broker at the default endpoint'
}

$observationsPassed = $InitialCandidateObserved -and $HostTerminationObserved -and
    $ReconnectCandidateObserved -and $ShiftOrdinalCommitObserved
$observationPath = Join-Path $outputDir 'desktop-observation.json'
[ordered]@{
    host = $HostName
    host_process_id = $HostProcessId
    host_executable = $hostProcess.Path
    loaded_text_service = $loadedModule[0].FileName
    loaded_text_service_sha256 = (Get-FileHash -LiteralPath $loadedModule[0].FileName -Algorithm SHA256).Hash.ToLowerInvariant()
    broker_process_id = $BrokerProcessId
    broker_executable = $brokerProcess.ExecutablePath
    broker_command_line = $brokerProcess.CommandLine
    input_trace = '2 -> Word File backstage -> return to document -> 2 -> Shift+1'
    initial_candidate_observed = [bool]$InitialCandidateObserved
    host_termination_observed = [bool]$HostTerminationObserved
    reconnect_candidate_observed = [bool]$ReconnectCandidateObserved
    shift_ordinal_commit_observed = [bool]$ShiftOrdinalCommitObserved
    committed_text = $CommittedText
    all_desktop_observations_passed = [bool]$observationsPassed
} | ConvertTo-Json -Depth 5 | Set-Content $observationPath -Encoding utf8

$sourceFiles = @(
    'YimeTextServiceExperiment\BrokerClient.h',
    'YimeTextServiceExperiment\BrokerClient.cpp',
    'YimeTextServiceExperiment\BrokerEndpoint.cpp',
    'YimeTextServiceExperiment\BrokerEndpoint.h',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\CandidateListUIElement.cpp',
    'YimeTextServiceExperiment\CandidateListUIElement.h',
    'YimeTextServiceExperiment\KeyContract.cpp',
    'YimeTextServiceExperiment\KeyContract.h',
    'YimeTextServiceExperiment\RegistrationTool.cpp',
    'YimeTextServiceExperiment\SurfaceSession.cpp',
    'YimeTextServiceExperiment\SurfaceSession.h',
    'YimeTextServiceExperiment\TextService.cpp',
    'YimeTextServiceExperiment\TextService.h',
    'YimeTextServiceExperiment\tests\BrokerBridgeTests.cpp',
    'YimeTextServiceExperiment\tests\ContractTests.cpp',
    'YimeTextServiceExperiment\tests\RegisteredHostTests.cpp',
    'YimeTextServiceExperiment\tests\TsfCompositionTests.cpp',
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'tools\yimecore\record-e6b8-desktop-host-acceptance.ps1'
)
$sourceHashesPath = Join-Path $outputDir 'source-hashes.json'
@($sourceFiles | ForEach-Object {
    $sourcePath = Join-Path $repoRoot $_
    [ordered]@{
        path = $_.Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}) | ConvertTo-Json -Depth 4 | Set-Content $sourceHashesPath -Encoding utf8

$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b8-desktop-host-v1'
    stage = 'e6b8'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $commit
    git_dirty = $false
    output_boundary = $outputDir
    package_handoff_path = $handoffPath
    package_handoff_sha256 = (Get-FileHash -LiteralPath $handoffPath -Algorithm SHA256).Hash.ToLowerInvariant()
    registration_path = $registrationPath
    registration_sha256 = (Get-FileHash -LiteralPath $registrationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    desktop_observation_path = $observationPath
    desktop_observation_sha256 = (Get-FileHash -LiteralPath $observationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    source_hashes_path = $sourceHashesPath
    source_hashes_sha256 = (Get-FileHash -LiteralPath $sourceHashesPath -Algorithm SHA256).Hash.ToLowerInvariant()
    installed_package_hash_handoff_verified = $true
    both_registry_views_match_install_root = $true
    installed_host_module_verified = $true
    installed_default_endpoint_broker_verified = $true
    all_desktop_observations_passed = [bool]$observationsPassed
    production_registration_changed = $false
    production_installation_changed = $false
    large_lexicon_added_to_git = $false
    blockers = @()
    limitations = @(
        'the desktop interaction observation covers Microsoft Word x64; x86 is covered by the registered in-memory host gate',
        'the package remains an unsigned experimental staging tree rather than a signed public installer',
        'the observation switches are operator-attested while process paths, loaded modules and hashes are verified mechanically'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 7 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B8 evidence: $outputDir"
if (-not $observationsPassed) { throw "E6-B8 desktop observation gate failed; see $summaryPath" }
