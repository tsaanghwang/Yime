[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [string]$RimeUserDir = $(if ($env:APPDATA) { Join-Path $env:APPDATA 'PIME\Rime' }),
    [ValidateRange(1, 1000000)]
    [int]$ExpectedEntries = 5618,
    [string]$CacheCheckerPath = (Join-Path $PSScriptRoot 'check-rime-cache-freshness.ps1')
)

$ErrorActionPreference = 'Stop'

function Get-Stage6DDictionarySummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Stage 6D dictionary is missing: $Path"
    }
    $entryCount = 0
    $invalidRows = [Collections.Generic.List[string]]::new()
    $inBody = $false
    $reader = [IO.StreamReader]::new($Path, [Text.Encoding]::UTF8, $true)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            if (-not $inBody) {
                if ($line.Trim() -eq '...') { $inBody = $true }
                continue
            }
            if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
            $fields = $line.Split("`t")
            if ($fields.Count -ne 3 -or $fields[2] -ne '1' -or -not $fields[0].Contains('啊')) {
                $invalidRows.Add($line)
                continue
            }
            $entryCount++
        }
    } finally {
        $reader.Dispose()
    }
    if (-not $inBody) { throw "Stage 6D dictionary has no YAML body marker: $Path" }
    [pscustomobject]@{
        entryCount = $entryCount
        invalidRows = @($invalidRows)
    }
}

function Test-DictionaryImport {
    param([string]$Path, [string]$ExpectedImport)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $inImports = $false
    $found = $false
    $reader = [IO.StreamReader]::new($Path, [Text.Encoding]::UTF8, $true)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            $trimmed = $line.Trim()
            if ($trimmed -eq '...') { break }
            if ($trimmed -eq 'import_tables:') {
                $inImports = $true
                continue
            }
            if ($inImports -and $trimmed.StartsWith('-')) {
                $value = $trimmed.Substring(1).Trim().Trim('"', "'")
                if ($value -eq $ExpectedImport) {
                    $found = $true
                    break
                }
            } elseif ($inImports -and $trimmed -and -not $trimmed.StartsWith('#')) {
                $inImports = $false
            }
        }
    } finally {
        $reader.Dispose()
    }
    return $found
}

$installRoot = [IO.Path]::GetFullPath($InstallRoot)
if (-not $RimeUserDir) { throw 'Rime user directory was not supplied and APPDATA is unavailable.' }
$rimeUserDir = [IO.Path]::GetFullPath($RimeUserDir)
$installedDataDir = Join-Path $installRoot 'go-backend\input_methods\yime\data'
$manifestPath = Join-Path $installedDataDir 'yime_particle_a_stage6d_manifest.json'
$deployedManifestPath = Join-Path $rimeUserDir 'yime_particle_a_stage6d_manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Installed Stage 6D manifest is missing: $manifestPath"
}
if (-not (Test-Path -LiteralPath $CacheCheckerPath -PathType Leaf)) {
    throw "Rime cache checker is missing: $CacheCheckerPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = [Collections.Generic.List[string]]::new()
$installedManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$deployedManifestHash = $null
if (Test-Path -LiteralPath $deployedManifestPath -PathType Leaf) {
    $deployedManifestHash = (Get-FileHash -LiteralPath $deployedManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
if (-not $deployedManifestHash -or $deployedManifestHash -ne $installedManifestHash) {
    $issues.Add('deployed Stage 6D manifest does not match the installed manifest')
}
if (-not [bool]$manifest.summary.passed) { $issues.Add('installed manifest summary did not pass') }
if ([int64]$manifest.summary.materialized_candidate_count -ne $ExpectedEntries) {
    $issues.Add("installed manifest materialized_candidate_count=$($manifest.summary.materialized_candidate_count), want $ExpectedEntries")
}
if ([int64]$manifest.summary.three_mode_row_count -ne (3 * $ExpectedEntries)) {
    $issues.Add("installed manifest three_mode_row_count=$($manifest.summary.three_mode_row_count), want $(3 * $ExpectedEntries)")
}

$cacheBySchema = @{}
foreach ($cacheRecord in @(& $CacheCheckerPath -RimeUserDir $rimeUserDir)) {
    $cacheBySchema[[string]$cacheRecord.schemaID] = $cacheRecord
}

$modeRecords = [Collections.Generic.List[object]]::new()
foreach ($mode in @('full', 'variable', 'shorthand')) {
    $schemaID = "yime_$mode"
    $dictionaryID = "yime_particle_a_stage6d_$mode"
    $name = "$dictionaryID.dict.yaml"
    $installedPath = Join-Path $installedDataDir $name
    $deployedPath = Join-Path $rimeUserDir $name
    $sentencePath = Join-Path $rimeUserDir "yime_sentence_$mode.dict.yaml"
    $installedHash = $null
    $deployedHash = $null
    $installedEntries = $null
    $deployedEntries = $null
    try {
        $installedSummary = Get-Stage6DDictionarySummary $installedPath
        $installedEntries = $installedSummary.entryCount
        if ($installedSummary.invalidRows.Count -gt 0) {
            $issues.Add("$name has $($installedSummary.invalidRows.Count) invalid installed row(s)")
        }
        $deployedSummary = Get-Stage6DDictionarySummary $deployedPath
        $deployedEntries = $deployedSummary.entryCount
        if ($deployedSummary.invalidRows.Count -gt 0) {
            $issues.Add("$name has $($deployedSummary.invalidRows.Count) invalid deployed row(s)")
        }
        $installedHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $deployedHash = (Get-FileHash -LiteralPath $deployedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch {
        $issues.Add($_.Exception.Message)
    }
    $manifestHash = [string]$manifest.output_sha256.$name
    $manifestRows = [int64]$manifest.summary.mode_row_counts.$mode
    $importsStage6D = Test-DictionaryImport $sentencePath $dictionaryID
    $cacheRecord = $cacheBySchema[$schemaID]
    $cacheStatus = if ($cacheRecord) { [string]$cacheRecord.status } else { 'missing' }

    if ($manifestRows -ne $ExpectedEntries) { $issues.Add("$name manifest rows=$manifestRows, want $ExpectedEntries") }
    if ($installedEntries -ne $ExpectedEntries) { $issues.Add("$name installed rows=$installedEntries, want $ExpectedEntries") }
    if ($deployedEntries -ne $ExpectedEntries) { $issues.Add("$name deployed rows=$deployedEntries, want $ExpectedEntries") }
    if (-not $manifestHash -or $installedHash -ne $manifestHash.ToLowerInvariant()) {
        $issues.Add("$name installed hash does not match the installed manifest")
    }
    if (-not $installedHash -or $deployedHash -ne $installedHash) {
        $issues.Add("$name deployed hash does not match the installed dictionary")
    }
    if (-not $importsStage6D) { $issues.Add("yime_sentence_$mode.dict.yaml does not import $dictionaryID") }
    if ($cacheStatus -ne 'match') { $issues.Add("$schemaID compiled cache status=$cacheStatus, want match") }

    $modeRecords.Add([pscustomobject]@{
        mode = $mode
        schemaID = $schemaID
        installedDictionary = $installedPath
        deployedDictionary = $deployedPath
        installedHash = $installedHash
        deployedHash = $deployedHash
        manifestHash = $manifestHash
        installedEntries = $installedEntries
        deployedEntries = $deployedEntries
        importsStage6D = $importsStage6D
        cacheStatus = $cacheStatus
    })
}

$report = [pscustomobject]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    installRoot = $installRoot
    rimeUserDir = $rimeUserDir
    installedManifest = $manifestPath
    deployedManifest = $deployedManifestPath
    installedManifestHash = $installedManifestHash
    deployedManifestHash = $deployedManifestHash
    expectedEntriesPerMode = $ExpectedEntries
    expectedThreeModeRows = 3 * $ExpectedEntries
    status = if ($issues.Count -eq 0) { 'match' } else { 'failed' }
    issues = @($issues)
    modes = @($modeRecords)
}

$report
if ($issues.Count -gt 0) {
    throw "Installed particle-a Stage 6D verification failed: $($issues -join '; ')"
}
