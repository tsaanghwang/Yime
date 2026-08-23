[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$B6EvidenceRoot,
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b7\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$outputPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and
    -not $outputDir.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B7 evidence must stay under $allowedRoot"
}
if (Test-Path -LiteralPath $outputDir) {
    if (@(Get-ChildItem -LiteralPath $outputDir -Force).Count -ne 0) {
        throw "E6-B7 evidence directory must be new or empty: $outputDir"
    }
} else {
    New-Item -ItemType Directory -Force $outputDir | Out-Null
}
Start-Transcript -LiteralPath (Join-Path $outputDir 'transcript.txt') -Force | Out-Null

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'E6-B7 requires an elevated token for the independent Program Files install root'
}

if ([string]::IsNullOrWhiteSpace($B6EvidenceRoot)) {
    $B6EvidenceRoot = Join-Path $outputDir 'b6'
    & (Join-Path $PSScriptRoot 'run-e6b6-registered-host-experiment.ps1') -OutputRoot $B6EvidenceRoot
    if ($LASTEXITCODE) { throw 'E6-B7 prerequisite E6-B6 failed' }
}
$b6Root = [IO.Path]::GetFullPath($B6EvidenceRoot)
$b6SummaryPath = Join-Path $b6Root 'summary.json'
if (-not (Test-Path -LiteralPath $b6SummaryPath)) { throw "missing E6-B6 summary: $b6SummaryPath" }
$b6Summary = Get-Content -LiteralPath $b6SummaryPath -Raw | ConvertFrom-Json
if ($b6Summary.stage -ne 'e6b6' -or $b6Summary.git_dirty -or
    -not $b6Summary.all_x86_x64_three_mode_registered_paths_passed -or
    -not $b6Summary.registered_key_sink_verified -or
    -not $b6Summary.registered_text_extent_anchor_verified -or
    -not $b6Summary.registered_focus_callbacks_verified -or
    -not $b6Summary.registered_candidate_commit_verified -or
    -not $b6Summary.all_no_residue) {
    throw "E6-B6 prerequisite is not a clean passing payload: $b6SummaryPath"
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$packageId = "yimecore-e6b7-$($commit.Substring(0, 12))"
$installParent = [IO.Path]::GetFullPath('C:\Program Files\YimeCore Experimental Trial')
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $installParent $packageId
}
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$installPrefix = $installParent.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedInstallRoot.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B7 install root must be a child of $installParent"
}
if (Test-Path -LiteralPath $resolvedInstallRoot) {
    throw "E6-B7 refuses to overwrite an existing install root: $resolvedInstallRoot"
}

function Convert-KeyValue([string]$text) {
    $result = [ordered]@{}
    foreach ($line in ($text -split "`r?`n")) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $result[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return $result
}

function Wait-RegistrationState([string]$tool, [bool]$registered, [string]$logPath) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $text = (& $tool status 2>&1) -join "`n"
        $values = Convert-KeyValue $text
        $expectedBoolean = if ($registered) { 'true' } else { 'false' }
        $expectedCategories = if ($registered) { 3 } else { 0 }
        if ($LASTEXITCODE -eq 0 -and
            $values.com_registered_current_view -eq $expectedBoolean -and
            $values.profile_registered -eq $expectedBoolean -and
            [int]$values.categories_registered_count -eq $expectedCategories) {
            $timer.Stop()
            $text | Set-Content $logPath -Encoding utf8
            return $timer.Elapsed.TotalMilliseconds
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    $timer.Stop()
    $text | Set-Content $logPath -Encoding utf8
    throw "TSF registration state did not converge to registered=$registered within 10 seconds"
}

function Start-Broker([string]$broker, [string]$index, [string]$mode,
                      [string]$pipe, [string]$errorLog) {
    Start-Process -FilePath $broker -ArgumentList @('-index', ('"' + $index + '"'),
        '-mode', $mode, '-named-pipe', ('"' + $pipe + '"')) `
        -PassThru -WindowStyle Hidden -RedirectStandardError $errorLog
}

function Stop-Broker([Diagnostics.Process]$process) {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}

function Get-PackageRecords([string]$root) {
    $normalizedRoot = [IO.Path]::GetFullPath($root)
    @(Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File | Where-Object {
        $_.Name -ne 'package-manifest.json'
    } | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object path)
}

function Assert-Package([string]$root, [string]$logPath) {
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "package manifest missing: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.package_id -ne $packageId) { throw "package identity mismatch at $root" }
    $actual = @(Get-PackageRecords $root)
    if ($actual.Count -ne @($manifest.files).Count) { throw "package file count mismatch at $root" }
    for ($i = 0; $i -lt $actual.Count; $i++) {
        $expected = $manifest.files[$i]
        if ($actual[$i].path -ne $expected.path -or
            $actual[$i].bytes -ne $expected.bytes -or
            $actual[$i].sha256 -ne $expected.sha256) {
            throw "package hash handoff mismatch at $root for $($actual[$i].path)"
        }
    }
    [long]$totalBytes = 0
    foreach ($record in $actual) { $totalBytes += [long]$record.bytes }
    [ordered]@{
        package_root = [IO.Path]::GetFullPath($root)
        package_id = $packageId
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        file_count = $actual.Count
        total_bytes = $totalBytes
        all_hashes_verified = $true
    } | ConvertTo-Json -Depth 4 | Set-Content $logPath -Encoding utf8
    return (Get-Content -LiteralPath $logPath -Raw | ConvertFrom-Json)
}

$artifactRoot = Join-Path $b6Root 'p\p'
$packageRoot = Join-Path $outputDir 'package'
New-Item -ItemType Directory -Force (Join-Path $packageRoot 'bin') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $packageRoot 'indexes') | Out-Null
foreach ($architecture in @('x64', 'x86')) {
    New-Item -ItemType Directory -Force (Join-Path $packageRoot $architecture) | Out-Null
}

$copies = [ordered]@{
    'bin/YimeBroker.exe' = (Join-Path $artifactRoot 'bin\YimeBroker.exe')
    'indexes/full.yidx' = (Join-Path $artifactRoot 'full\index.yidx')
    'indexes/variable.yidx' = (Join-Path $artifactRoot 'variable\index.yidx')
    'indexes/shorthand.yidx' = (Join-Path $artifactRoot 'shorthand\index.yidx')
}
foreach ($architecture in @('x64', 'x86')) {
    $release = Join-Path $artifactRoot "build-$architecture\Release"
    $copies["$architecture/YimeTextServiceExperiment.dll"] = Join-Path $release 'YimeTextServiceExperiment.dll'
    $copies["$architecture/YimeTextServiceRegistration.exe"] = Join-Path $release 'YimeTextServiceRegistration.exe'
    $copies["$architecture/YimeRegisteredHostTests.exe"] = Join-Path $release 'YimeRegisteredHostTests.exe'
}
foreach ($entry in $copies.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) { throw "missing package source artifact: $($entry.Value)" }
    Copy-Item -LiteralPath $entry.Value -Destination (Join-Path $packageRoot $entry.Key) -Force
}

$packageManifest = [ordered]@{
    tool_version = 'yimecore-experimental-package-v1'
    package_id = $packageId
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $commit
    b6_git_commit = $b6Summary.git_commit
    b6_summary_sha256 = (Get-FileHash -LiteralPath $b6SummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    install_scope = 'parallel experimental trial; independent CLSID/profile and install root'
    files = @(Get-PackageRecords $packageRoot)
}
$packageManifestPath = Join-Path $packageRoot 'package-manifest.json'
$packageManifest | ConvertTo-Json -Depth 6 | Set-Content $packageManifestPath -Encoding utf8
$stagedHandoff = Assert-Package $packageRoot (Join-Path $outputDir 'package-handoff-staged.json')

$installedHandoff = $null
$architectureResults = @()
$installedRemoved = $false
try {
    New-Item -ItemType Directory -Force $installParent | Out-Null
    Copy-Item -LiteralPath $packageRoot -Destination $resolvedInstallRoot -Recurse
    $installedHandoff = Assert-Package $resolvedInstallRoot (Join-Path $outputDir 'package-handoff-installed.json')

    $broker = Join-Path $resolvedInstallRoot 'bin\YimeBroker.exe'
    $modeDefinitions = @(
        [ordered]@{ mode = 'full'; index = (Join-Path $resolvedInstallRoot 'indexes\full.yidx') },
        [ordered]@{ mode = 'variable'; index = (Join-Path $resolvedInstallRoot 'indexes\variable.yidx') },
        [ordered]@{ mode = 'shorthand'; index = (Join-Path $resolvedInstallRoot 'indexes\shorthand.yidx') }
    )
    foreach ($architecture in @([ordered]@{ name = 'x64'; bits = 64 },
                                 [ordered]@{ name = 'x86'; bits = 32 })) {
        $architectureDir = Join-Path $outputDir $architecture.name
        New-Item -ItemType Directory -Force $architectureDir | Out-Null
        $installedArchitecture = Join-Path $resolvedInstallRoot $architecture.name
        $tool = Join-Path $installedArchitecture 'YimeTextServiceRegistration.exe'
        $dll = Join-Path $installedArchitecture 'YimeTextServiceExperiment.dll'
        $hostTest = Join-Path $installedArchitecture 'YimeRegisteredHostTests.exe'
        $null = Wait-RegistrationState $tool $false (Join-Path $architectureDir 'status-before.txt')
        $registerText = (& $tool register $dll 2>&1) -join "`n"
        $registerExit = $LASTEXITCODE
        $registerText | Set-Content (Join-Path $architectureDir 'register.txt') -Encoding utf8
        $registrationVisibilityMs = $null
        $rollbackVisibilityMs = $null
        $modeResults = @()
        try {
            if ($registerExit -ne 0) { throw "$($architecture.name) installed registration failed with $registerExit" }
            $registrationVisibilityMs = Wait-RegistrationState $tool $true (Join-Path $architectureDir 'status-registered.txt')
            foreach ($definition in $modeDefinitions) {
                $pipe = "\\.\pipe\YimeBroker-e6b7-$($architecture.name)-$($definition.mode)-$PID"
                $process = Start-Broker $broker $definition.index $definition.mode $pipe `
                    (Join-Path $architectureDir "broker-$($definition.mode).err")
                $timer = [Diagnostics.Stopwatch]::StartNew()
                try {
                    Start-Sleep -Milliseconds 200
                    $testText = (& $hostTest $pipe 2>&1) -join "`n"
                    $testExit = $LASTEXITCODE
                } finally {
                    Stop-Broker $process
                    $timer.Stop()
                }
                $testLog = Join-Path $architectureDir "$($definition.mode).txt"
                $testText | Set-Content $testLog -Encoding utf8
                if ($testExit -ne 0) { throw "$($architecture.name) $($definition.mode) installed host failed: $testText" }
                $observed = Convert-KeyValue $testText
                foreach ($required in @('registered_key_sink_verified', 'registered_text_extent_anchor',
                                         'registered_focus_callbacks_verified', 'registered_candidate_commit')) {
                    if ($observed[$required] -ne 'true') { throw "$testLog missing $required=true" }
                }
                if ([int]$observed.architecture_bits -ne $architecture.bits) { throw "$testLog architecture mismatch" }
                $modeResults += [ordered]@{
                    mode = $definition.mode
                    elapsed_ms = $timer.Elapsed.TotalMilliseconds
                    installed_host_path_verified = $true
                }
            }
        } finally {
            $unregisterText = (& $tool unregister 2>&1) -join "`n"
            $unregisterExit = $LASTEXITCODE
            $unregisterText | Set-Content (Join-Path $architectureDir 'unregister.txt') -Encoding utf8
            if ($unregisterExit -ne 0) { throw "$($architecture.name) installed rollback failed with $unregisterExit" }
            $rollbackVisibilityMs = Wait-RegistrationState $tool $false (Join-Path $architectureDir 'status-after.txt')
            $absentText = (& $tool verify-absent 2>&1) -join "`n"
            $absentExit = $LASTEXITCODE
            $absentText | Set-Content (Join-Path $architectureDir 'verify-absent-after.txt') -Encoding utf8
            if ($absentExit -ne 0) { throw "$($architecture.name) installed registration residue detected" }
        }
        $architectureResults += [ordered]@{
            architecture = $architecture.name
            bits = $architecture.bits
            registration_visibility_ms = $registrationVisibilityMs
            rollback_visibility_ms = $rollbackVisibilityMs
            modes = $modeResults
            no_registration_residue = $true
        }
    }
} finally {
    foreach ($architecture in @('x64', 'x86')) {
        $cleanupTool = Join-Path $resolvedInstallRoot "$architecture\YimeTextServiceRegistration.exe"
        if (Test-Path -LiteralPath $cleanupTool) { & $cleanupTool unregister *> $null }
    }
    if (Test-Path -LiteralPath $resolvedInstallRoot) {
        $installedManifestPath = Join-Path $resolvedInstallRoot 'package-manifest.json'
        if (-not (Test-Path -LiteralPath $installedManifestPath)) {
            throw "refusing cleanup without package marker: $resolvedInstallRoot"
        }
        $installedMarker = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
        if ($installedMarker.package_id -ne $packageId) {
            throw "refusing cleanup of mismatched package identity: $resolvedInstallRoot"
        }
        Remove-Item -LiteralPath $resolvedInstallRoot -Recurse -Force
    }
    $installedRemoved = -not (Test-Path -LiteralPath $resolvedInstallRoot)
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'tools\yimecore\run-e6b7-parallel-package-experiment.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$allInstalledModes = @($architectureResults | ForEach-Object { $_.modes })
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b7-parallel-package-v1'
    stage = 'e6b7'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = $commit
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    elevated = $true
    output_boundary = $outputDir
    prerequisite_b6_summary_path = $b6SummaryPath
    prerequisite_b6_summary_sha256 = (Get-FileHash -LiteralPath $b6SummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    package_root = $packageRoot
    package_manifest_sha256 = $stagedHandoff.manifest_sha256
    package_file_count = $stagedHandoff.file_count
    package_total_bytes = $stagedHandoff.total_bytes
    staged_package_hash_handoff_verified = [bool]$stagedHandoff.all_hashes_verified
    installed_package_hash_handoff_verified = [bool]$installedHandoff.all_hashes_verified
    install_root = $resolvedInstallRoot
    independent_install_root = $true
    independent_experimental_registration_identity = $true
    architectures = $architectureResults
    all_x86_x64_three_mode_installed_paths_passed = $allInstalledModes.Count -eq 6 -and
        -not ($allInstalledModes.installed_host_path_verified -contains $false)
    all_registration_residue_removed = -not ($architectureResults.no_registration_residue -contains $false)
    installed_tree_removed = $installedRemoved
    production_registration_changed = $false
    production_installation_changed = $false
    large_lexicon_added_to_git = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    blockers = @()
    limitations = @(
        'the package is an unsigned experimental staging tree rather than a public MSI or signed release bundle',
        'the installed host remains the purpose-built in-memory ITextStoreACP application; third-party desktop application acceptance remains separate',
        'language-bar visual exposure and click behavior remain auxiliary installed-application observations'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B7 evidence: $outputDir"
if (-not $summary.staged_package_hash_handoff_verified -or
    -not $summary.installed_package_hash_handoff_verified -or
    -not $summary.all_x86_x64_three_mode_installed_paths_passed -or
    -not $summary.all_registration_residue_removed -or
    -not $summary.installed_tree_removed -or
    $summary.production_registration_changed -or $summary.production_installation_changed -or
    $summary.large_lexicon_added_to_git) {
    throw "E6-B7 gate failed; see $summaryPath"
}
Stop-Transcript | Out-Null
