[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot ('e6b4c\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$prefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-B4c evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force $outputDir | Out-Null
$payload = Join-Path $outputDir 'focus-payload'
& (Join-Path $PSScriptRoot 'run-e6b4b-focus-experiment.ps1') -OutputRoot $payload
if ($LASTEXITCODE) { throw 'E6-B4c focus payload failed' }

$payloadSummaryPath = Join-Path $payload 'summary.json'
$payloadSummary = Get-Content $payloadSummaryPath -Raw | ConvertFrom-Json
$expectedIds = [ordered]@{
    clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
    profile_guid = '{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
    language_bar_guid = '{E7ED229C-24F4-47A4-B547-684C17014D25}'
}

function Convert-KeyValue([string]$text) {
    $result = [ordered]@{}
    foreach ($line in ($text -split "`r?`n")) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $result[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return $result
}

$architectures = @()
foreach ($architecture in @([ordered]@{ name = 'x64'; bits = 64 }, [ordered]@{ name = 'x86'; bits = 32 })) {
    $buildRoot = Join-Path $payload ("language-bar-payload\candidate-ui-payload\tsf-payload\build-$($architecture.name)\Release")
    $tool = Join-Path $buildRoot 'YimeTextServiceRegistration.exe'
    $dll = Join-Path $buildRoot 'YimeTextServiceExperiment.dll'
    if (-not (Test-Path -LiteralPath $tool) -or -not (Test-Path -LiteralPath $dll)) {
        throw "missing $($architecture.name) registration artifact"
    }
    $architectureDir = Join-Path $outputDir $architecture.name
    New-Item -ItemType Directory -Force $architectureDir | Out-Null
    $statusText = (& $tool status 2>&1) -join "`n"
    $statusExit = $LASTEXITCODE
    $statusText | Set-Content (Join-Path $architectureDir 'status-before.txt') -Encoding utf8
    if ($statusExit -ne 0) { throw "$($architecture.name) status failed with $statusExit" }
    $status = Convert-KeyValue $statusText
    if ([int]$status.architecture_bits -ne $architecture.bits -or
        $status.clsid -ne $expectedIds.clsid -or
        $status.profile_guid -ne $expectedIds.profile_guid -or
        $status.language_bar_guid -ne $expectedIds.language_bar_guid -or
        $status.com_registered_current_view -ne 'false' -or
        $status.profile_registered -ne 'false' -or
        [int]$status.categories_registered_count -ne 0 -or
        $status.mutation_performed -ne 'false') {
        throw "$($architecture.name) registration identity or initial state mismatch"
    }

    $elevated = $status.elevated -eq 'true'
    $liveCycle = $false
    $blocked = $null
    if ($elevated) {
        $registerText = (& $tool register $dll 2>&1) -join "`n"
        $registerExit = $LASTEXITCODE
        $registerText | Set-Content (Join-Path $architectureDir 'register.txt') -Encoding utf8
        try {
            if ($registerExit -ne 0) { throw "$($architecture.name) registration failed with $registerExit" }
            $registeredText = (& $tool status 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "$($architecture.name) registered status failed" }
            $registeredText | Set-Content (Join-Path $architectureDir 'status-registered.txt') -Encoding utf8
            $registered = Convert-KeyValue $registeredText
            if ($registered.com_registered_current_view -ne 'true' -or $registered.profile_registered -ne 'true' -or
                [int]$registered.categories_registered_count -ne 3) {
                throw "$($architecture.name) registration was not observable"
            }
            $liveCycle = $true
        } finally {
            $unregisterText = (& $tool unregister 2>&1) -join "`n"
            $unregisterExit = $LASTEXITCODE
            $unregisterText | Set-Content (Join-Path $architectureDir 'unregister.txt') -Encoding utf8
            if ($unregisterExit -ne 0) { throw "$($architecture.name) rollback failed with $unregisterExit" }
        }
    } else {
        $registerText = (& $tool register $dll 2>&1) -join "`n"
        $registerExit = $LASTEXITCODE
        $registerText | Set-Content (Join-Path $architectureDir 'register-preflight.txt') -Encoding utf8
        $register = Convert-KeyValue $registerText
        if ($registerExit -ne 3 -or $register.blocked -ne 'requires_elevated_token' -or
            $register.mutation_performed -ne 'false') {
            throw "$($architecture.name) non-elevated registration did not fail closed"
        }
        $blocked = 'requires_elevated_token'
    }

    $absentText = (& $tool verify-absent 2>&1) -join "`n"
    $absentExit = $LASTEXITCODE
    $absentText | Set-Content (Join-Path $architectureDir 'status-after.txt') -Encoding utf8
    if ($absentExit -ne 0) { throw "$($architecture.name) registration residue detected"
    }
    $architectures += [ordered]@{
        architecture = $architecture.name
        bits = $architecture.bits
        elevated = $elevated
        registration_tool_sha256 = (Get-FileHash $tool -Algorithm SHA256).Hash.ToLowerInvariant()
        dll_sha256 = (Get-FileHash $dll -Algorithm SHA256).Hash.ToLowerInvariant()
        live_register_unregister_cycle = $liveCycle
        blocked_reason = $blocked
        no_residue_after_test = $true
    }
}

$sourceFiles = @(
    'docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md',
    'YimeTextServiceExperiment\CMakeLists.txt',
    'YimeTextServiceExperiment\RegistrationTool.cpp',
    'YimeTextServiceExperiment\YimeTextServiceIds.h',
    'tools\yimecore\run-e6b4c-registration-readiness.ps1'
)
$hashes = foreach ($relative in $sourceFiles) {
    $hash = Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256
    [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash.Hash.ToLowerInvariant() }
}
$sourceHashes = Join-Path $outputDir 'source-hashes.json'
$hashes | ConvertTo-Json -Depth 3 | Set-Content $sourceHashes -Encoding utf8
$summary = [ordered]@{
    tool_version = 'yime-text-service-e6b4c-registration-readiness-v1'
    stage = 'e6b4c-readiness'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    output_boundary = $outputDir
    payload_summary_path = $payloadSummaryPath
    payload_summary_sha256 = (Get-FileHash $payloadSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payload_clean = -not [bool]$payloadSummary.git_dirty
    registration_identity = $expectedIds
    architectures = $architectures
    x86_x64_tools_verified = $architectures.Count -eq 2
    fail_closed_before_mutation = -not ($architectures.elevated -contains $true)
    all_no_residue = -not ($architectures.no_residue_after_test -contains $false)
    live_registration_verified = -not ($architectures.live_register_unregister_cycle -contains $false)
    production_registration_changed = $false
    source_hashes_sha256 = (Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant()
    blockers = @($architectures | Where-Object { $_.blocked_reason } | ForEach-Object {
        "$($_.architecture):$($_.blocked_reason)"
    })
    limitations = @(
        'the helper implements machine COM, TSF profile and category registration with exact-identity rollback',
        'automatic host callback delivery and language bar manager acceptance require a live elevated registration cycle'
    )
}
$summaryPath = Join-Path $outputDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B4c readiness evidence: $outputDir"
if (-not $summary.x86_x64_tools_verified -or -not $summary.all_no_residue -or $summary.production_registration_changed) {
    throw "E6-B4c readiness gate failed; see $summaryPath"
}
