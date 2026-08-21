param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [string]$JsonPath,
    [string]$RimeUserDir = $(if ($env:APPDATA) { Join-Path $env:APPDATA 'PIME\Rime' }),
    [string]$LongSessionAcceptancePath,
    [switch]$AllowTextServiceMismatch,
    [switch]$RequireRunningLauncher,
    [switch]$RequireFreshRimeCache,
    [switch]$RequireLongSessionAcceptance
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sentence-segment-recorder-record.ps1')

function Get-FileRecord {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Installed,
        [bool]$Required = $true,
        [bool]$TextService = $false
    )

    $record = [ordered]@{
        name = $Name
        source = $Source
        installed = $Installed
        required = $Required
        textService = $TextService
        sourceHash = $null
        installedHash = $null
        status = 'unknown'
    }
    if (-not (Test-Path -LiteralPath $Source)) {
        $record.status = if ($Required) { 'source-missing' } else { 'not-built' }
        return [pscustomobject]$record
    }
    $record.sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if (-not (Test-Path -LiteralPath $Installed)) {
        $record.status = 'installed-missing'
        return [pscustomobject]$record
    }
    $record.installedHash = (Get-FileHash -LiteralPath $Installed -Algorithm SHA256).Hash
    $record.status = if ($record.sourceHash -eq $record.installedHash) { 'match' } else { 'mismatch' }
    return [pscustomobject]$record
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$installRoot = [IO.Path]::GetFullPath($InstallRoot)
$goSourceRoot = Join-Path $repoRoot 'go-backend\build\go-backend'
$goInstallRoot = Join-Path $installRoot 'go-backend'

$files = [Collections.Generic.List[object]]::new()
$files.Add((Get-FileRecord 'version.txt' (Join-Path $repoRoot 'version.txt') (Join-Path $installRoot 'version.txt')))
$files.Add((Get-FileRecord 'backends.json' (Join-Path $repoRoot 'backends.json') (Join-Path $installRoot 'backends.json')))

$launcherCandidates = @(
    (Join-Path $repoRoot 'build\PIMELauncher\PIMELauncher.exe'),
    (Join-Path $repoRoot 'build\PIMELauncher\Release\PIMELauncher.exe')
)
$launcherSource = $launcherCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $launcherSource) { $launcherSource = $launcherCandidates[0] }
$files.Add((Get-FileRecord 'PIMELauncher.exe' $launcherSource (Join-Path $installRoot 'PIMELauncher.exe')))
$files.Add((Get-FileRecord 'x86/PIMETextService.dll' (Join-Path $repoRoot 'build\PIMETextService\Release\PIMETextService.dll') (Join-Path $installRoot 'x86\PIMETextService.dll') $true $true))
$files.Add((Get-FileRecord 'x64/PIMETextService.dll' (Join-Path $repoRoot 'build64\PIMETextService\Release\PIMETextService.dll') (Join-Path $installRoot 'x64\PIMETextService.dll') $true $true))

foreach ($relativePath in @(
    'server.exe',
    'tool-hub.exe',
    'yime-trainer.exe',
    'input-toolbar.exe',
    'lexicon-manager.exe',
    'system-lexicon-audit.exe',
    'lexicon-promotion-scan.exe',
    'blocklist-manager.exe',
    'reverse-lookup.exe',
    'settings-tool.exe',
    'diagnostics-tool.exe',
    'yime-layout-designer.exe',
    'input_methods\yime\rime.dll'
)) {
    $files.Add((Get-FileRecord "go-backend/$($relativePath.Replace('\', '/'))" (Join-Path $goSourceRoot $relativePath) (Join-Path $goInstallRoot $relativePath)))
}
$files.Add((Get-FileRecord 'go-backend/input_methods/yime/rime_deployer.exe' (Join-Path $goSourceRoot 'input_methods\yime\rime_deployer.exe') (Join-Path $goInstallRoot 'input_methods\yime\rime_deployer.exe') $false))
foreach ($relativePath in @(
    'input_methods\yime\data\yime_full.dict.yaml',
    'input_methods\yime\data\yime_variable.dict.yaml',
    'input_methods\yime\data\yime_shorthand.dict.yaml',
    'input_methods\yime\data\yime_full.schema.yaml',
    'input_methods\yime\data\yime_variable.schema.yaml',
    'input_methods\yime\data\yime_shorthand.schema.yaml',
    'input_methods\yime\data\yime_lexicon_manifest.json',
    'input_methods\yime\data\yime_core_source_manifest.json',
    'input_methods\yime\data\yime_runtime_profile.json',
    'input_methods\yime\data\yime_pinyin_reverse_source.tsv',
    'input_methods\yime\data\yime_pinyin_codes.tsv',
	'input_methods\yime\data\yime_system_candidate_exclusions.tsv',
    'input_methods\yime\data\yime_erhua_mixed_full.dict.yaml',
    'input_methods\yime\data\yime_erhua_mixed_variable.dict.yaml',
    'input_methods\yime\data\yime_erhua_mixed_shorthand.dict.yaml',
	'input_methods\yime\data\yime_erhua_mixed_sentence_full.dict.yaml',
	'input_methods\yime\data\yime_erhua_mixed_sentence_variable.dict.yaml',
	'input_methods\yime\data\yime_erhua_mixed_sentence_shorthand.dict.yaml',
	'input_methods\yime\data\yime_sentence_full.dict.yaml',
	'input_methods\yime\data\yime_sentence_variable.dict.yaml',
	'input_methods\yime\data\yime_sentence_shorthand.dict.yaml',
	'input_methods\yime\data\yime_third_tone_stage5c_full.dict.yaml',
	'input_methods\yime\data\yime_third_tone_stage5c_variable.dict.yaml',
	'input_methods\yime\data\yime_third_tone_stage5c_shorthand.dict.yaml',
	'input_methods\yime\data\yime_third_tone_stage5c_manifest.json',
	'input_methods\yime\data\yime_particle_a_stage6d_full.dict.yaml',
	'input_methods\yime\data\yime_particle_a_stage6d_variable.dict.yaml',
	'input_methods\yime\data\yime_particle_a_stage6d_shorthand.dict.yaml',
	'input_methods\yime\data\yime_particle_a_stage6d_manifest.json',
    'input_methods\yime\data\yime_erhua_mixed_manifest.json',
    'input_methods\yime\data\yime_erhua_reverse_source.tsv',
    'input_methods\yime\data\yime_erhua_mixed_full.schema.yaml',
    'input_methods\yime\data\yime_erhua_mixed_variable.schema.yaml',
    'input_methods\yime\data\yime_erhua_mixed_shorthand.schema.yaml',
    'input_methods\yime\data\yime_psc_peripheral_full.dict.yaml',
    'input_methods\yime\data\yime_psc_peripheral_variable.dict.yaml',
    'input_methods\yime\data\yime_psc_peripheral_shorthand.dict.yaml',
	'input_methods\yime\data\yime_psc_peripheral_sentence_full.dict.yaml',
	'input_methods\yime\data\yime_psc_peripheral_sentence_variable.dict.yaml',
	'input_methods\yime\data\yime_psc_peripheral_sentence_shorthand.dict.yaml',
    'input_methods\yime\data\yime_psc_peripheral_manifest.json',
    'input_methods\yime\data\yime_psc_peripheral_full.schema.yaml',
    'input_methods\yime\data\yime_psc_peripheral_variable.schema.yaml',
    'input_methods\yime\data\yime_psc_peripheral_shorthand.schema.yaml',
    'input_methods\yime\data\trainer\foundation.json',
    'input_methods\yime\data\trainer\yinyuan_catalog.json'
)) {
    $files.Add((Get-FileRecord "go-backend/$($relativePath.Replace('\', '/'))" (Join-Path $goSourceRoot $relativePath) (Join-Path $goInstallRoot $relativePath)))
}

$retiredRuntimeFiles = @(
    'yime_core_trial.dict.yaml',
    'yime_core_trial.schema.yaml',
    'yime_core_trial_manifest.json'
)
$runtimeDataDir = Join-Path $goInstallRoot 'input_methods\yime\data'
$retiredLeakage = @($retiredRuntimeFiles | Where-Object {
    Test-Path -LiteralPath (Join-Path $runtimeDataDir $_)
})

$registryRoot = $null
try {
    $registryRoot = (Get-Item -Path 'HKLM:\SOFTWARE\YIME' -ErrorAction Stop).GetValue('')
} catch {
}
$registryMatches = $registryRoot -and ([IO.Path]::GetFullPath($registryRoot).TrimEnd('\') -eq $installRoot.TrimEnd('\'))

$launcherRunning = $false
$launcherPathUnavailable = $false
foreach ($process in @(Get-Process -Name PIMELauncher -ErrorAction SilentlyContinue)) {
    try {
        if ($process.Path -and $process.Path.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $launcherRunning = $true
            break
        }
        if (-not $process.Path) {
            $launcherPathUnavailable = $true
        }
    } catch {
        $launcherPathUnavailable = $true
    }
}
if (-not $launcherRunning -and $launcherPathUnavailable -and $registryMatches) {
    $launcherFile = $files | Where-Object { $_.name -eq 'PIMELauncher.exe' } | Select-Object -First 1
    if ($launcherFile -and $launcherFile.status -eq 'match') {
        # Some Windows security contexts expose the process but redact Path and
        # ExecutablePath. The matching installed binary plus matching registry
        # root still identifies the expected development installation.
        $launcherRunning = $true
    }
}

$rimeCacheRecords = @(& (Join-Path $PSScriptRoot 'check-rime-cache-freshness.ps1') -RimeUserDir $RimeUserDir)
$rimeCacheIssues = @($rimeCacheRecords | Where-Object {
    $_.status -notin @('match', 'not-deployed')
})

$longSessionAcceptance = [ordered]@{
    path = if ($LongSessionAcceptancePath) { [IO.Path]::GetFullPath($LongSessionAcceptancePath) } else { $null }
    exists = $false
    sha256 = $null
    status = 'not-provided'
    capturedAt = $null
    buildVersion = $null
    buildCommit = $null
    issues = @()
}
if ($LongSessionAcceptancePath) {
    $acceptanceIssues = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $LongSessionAcceptancePath -PathType Leaf)) {
        $longSessionAcceptance.status = 'missing'
        $acceptanceIssues.Add('acceptance record is missing')
    } else {
        $longSessionAcceptance.exists = $true
        $longSessionAcceptance.sha256 = (Get-FileHash -LiteralPath $LongSessionAcceptancePath -Algorithm SHA256).Hash
        try {
            $acceptance = Get-Content -LiteralPath $LongSessionAcceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $longSessionAcceptance.capturedAt = [string]$acceptance.CapturedAt
            $longSessionAcceptance.buildVersion = [string]$acceptance.Build.Version
            $longSessionAcceptance.buildCommit = [string]$acceptance.Build.Commit
            if ([int]$acceptance.SchemaVersion -ne 2) { $acceptanceIssues.Add('schemaVersion must be 2') }
            if ([string]$acceptance.Status -ne 'complete') { $acceptanceIssues.Add("record status is $($acceptance.Status)") }
            if (-not [bool]$acceptance.RequireLongSession) { $acceptanceIssues.Add('record did not require the long-session gate') }
            if ([IO.Path]::GetFullPath([string]$acceptance.InstallRoot).TrimEnd('\') -ne $installRoot.TrimEnd('\')) {
                $acceptanceIssues.Add('install root does not match this verification')
            }
            $installedVersionPath = Join-Path $installRoot 'version.txt'
            $installedVersion = if (Test-Path -LiteralPath $installedVersionPath) { (Get-Content -LiteralPath $installedVersionPath -Raw).Trim() } else { $null }
            if (-not $installedVersion -or [string]$acceptance.Build.Version -ne $installedVersion) {
                $acceptanceIssues.Add('build version does not match the installed runtime')
            }
            $currentCommit = $null
            try { $currentCommit = (& git -C $repoRoot rev-parse HEAD 2>$null).Trim() } catch {}
            if (-not $currentCommit -or [string]$acceptance.Build.Commit -ne $currentCommit) {
                $acceptanceIssues.Add('Git commit does not match the acceptance build')
            }
            if ([bool]$acceptance.Build.Manifest.Exists -and [string]$acceptance.Build.Manifest.Status -ne 'match') {
                $acceptanceIssues.Add('build manifest linkage is not a match')
            }
            foreach ($name in @('server.exe', 'x86/PIMETextService.dll', 'x64/PIMETextService.dll')) {
                $acceptedFile = @($acceptance.FileRecords | Where-Object { [string]$_.Name -eq $name }) | Select-Object -First 1
                $currentFile = @($files | Where-Object { [string]$_.name -eq $(if ($name -eq 'server.exe') { 'go-backend/server.exe' } else { $name }) }) | Select-Object -First 1
                if (-not $acceptedFile) {
                    $acceptanceIssues.Add("missing file record: $name")
                } elseif ([string]$acceptedFile.Status -ne 'match') {
                    $acceptanceIssues.Add("accepted file was not build-hash matched: $name")
                } elseif (-not $currentFile -or [string]$acceptedFile.InstalledSha256 -ne [string]$currentFile.installedHash) {
                    $acceptanceIssues.Add("installed hash changed after acceptance: $name")
                }
            }
            $architectures = @($acceptance.HostOutcomeRecords | Where-Object LongSessionStatus -eq 'pass' | ForEach-Object { [string]$_.Architecture } | Sort-Object -Unique)
            if ($architectures -notcontains 'x86' -or $architectures -notcontains 'x64') {
                $acceptanceIssues.Add('passing long-session hosts must cover x86 and x64')
            }
            $minimumCycles = [int]$acceptance.MinimumCyclesPerHost
            foreach ($hostOutcome in @($acceptance.HostOutcomeRecords)) {
                if ([string]$hostOutcome.Outcome -ne 'pass' -or
                    [string]$hostOutcome.LongSessionStatus -ne 'pass' -or
                    [int]$hostOutcome.FirstSegmentSwitches -lt $minimumCycles -or
                    [int]$hostOutcome.MiddleSegmentSwitches -lt $minimumCycles -or
                    [int]$hostOutcome.FinalSegmentSwitches -lt $minimumCycles -or
                    [int]$hostOutcome.CompletedCycles -lt $minimumCycles) {
                    $acceptanceIssues.Add("host long-session threshold is not met: $($hostOutcome.Host)")
                }
            }
            $recorderRecordProperty = $acceptance.PSObject.Properties['RecorderRecord']
            if ($null -ne $recorderRecordProperty -and [bool]$recorderRecordProperty.Value.Provided) {
                $acceptedRecorderRecord = $recorderRecordProperty.Value
                if ([string]$acceptedRecorderRecord.Status -ne 'match' -or [int]$acceptedRecorderRecord.SchemaVersion -ne 2) {
                    $acceptanceIssues.Add('recorder record linkage is not a schema 2 match')
                } else {
                    try {
                        $currentRecorderRecord = Get-YimeSentenceSegmentRecorderRecord -Path ([string]$acceptedRecorderRecord.Path)
                        if ([string]$currentRecorderRecord.Sha256 -ne [string]$acceptedRecorderRecord.Sha256) {
                            $acceptanceIssues.Add('recorder record changed after acceptance')
                        }
                        if ([string]$currentRecorderRecord.SessionId -ne [string]$acceptedRecorderRecord.SessionId -or
                            [int]$currentRecorderRecord.MinimumCyclesPerHost -ne $minimumCycles -or
                            [int]$currentRecorderRecord.EventCount -ne [int]$acceptedRecorderRecord.EventCount -or
                            [string]$currentRecorderRecord.TerminalEvent -ne [string]$acceptedRecorderRecord.TerminalEvent) {
                            $acceptanceIssues.Add('recorder session identity or terminal snapshot does not match the acceptance')
                        }
                        foreach ($recorderHost in @($currentRecorderRecord.HostRecords)) {
                            $acceptedRecorderHost = @($acceptedRecorderRecord.HostRecords | Where-Object HostId -eq $recorderHost.HostId) | Select-Object -First 1
                            $acceptedHostOutcome = @($acceptance.HostOutcomeRecords | Where-Object RecorderHostId -eq $recorderHost.HostId) | Select-Object -First 1
                            if (-not $acceptedRecorderHost -or -not $acceptedHostOutcome -or
                                [int]$acceptedRecorderHost.First -ne [int]$recorderHost.First -or
                                [int]$acceptedRecorderHost.Middle -ne [int]$recorderHost.Middle -or
                                [int]$acceptedRecorderHost.Final -ne [int]$recorderHost.Final -or
                                [int]$acceptedRecorderHost.Failures -ne [int]$recorderHost.Failures -or
                                [int]$acceptedHostOutcome.FirstSegmentSwitches -ne [int]$recorderHost.First -or
                                [int]$acceptedHostOutcome.MiddleSegmentSwitches -ne [int]$recorderHost.Middle -or
                                [int]$acceptedHostOutcome.FinalSegmentSwitches -ne [int]$recorderHost.Final -or
                                [int]$acceptedHostOutcome.FailureCount -ne [int]$recorderHost.Failures -or
                                [int]$acceptedHostOutcome.ForegroundEventCount -ne [int]$recorderHost.ForegroundEventCount) {
                                $acceptanceIssues.Add("recorder host evidence does not match: $($recorderHost.Host)")
                            }
                        }
                        if (@($currentRecorderRecord.ForegroundIdentityRecords).Count -ne
                            @($acceptedRecorderRecord.ForegroundIdentityRecords).Count) {
                            $acceptanceIssues.Add('recorder foreground identity count does not match the acceptance')
                        }
                    } catch {
                        $acceptanceIssues.Add("recorder record is invalid: $($_.Exception.Message)")
                    }
                }
            }
            if ([string]$acceptance.PagingOwnership.Owner -ne 'rime-native-backend' -or
                [string]$acceptance.PagingOwnership.Status -ne 'guarded') {
                $acceptanceIssues.Add('Rime-owned candidate paging guard is not recorded')
            }
            $pagingImplementationPath = Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo.go'
            $pagingTestPath = Join-Path $repoRoot 'go-backend\input_methods\yime\native_cgo_test.go'
            if (-not (Test-Path -LiteralPath $pagingImplementationPath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $pagingTestPath -PathType Leaf)) {
                $acceptanceIssues.Add('Rime-owned paging guard sources are missing')
            } else {
                $pagingImplementationText = Get-Content -LiteralPath $pagingImplementationPath -Raw
                $pagingTestText = Get-Content -LiteralPath $pagingTestPath -Raw
                $pagingImplementationHash = (Get-FileHash -LiteralPath $pagingImplementationPath -Algorithm SHA256).Hash
                $pagingTestHash = (Get-FileHash -LiteralPath $pagingTestPath -Algorithm SHA256).Hash
                if ($pagingImplementationText -notmatch '(?s)func \(b \*nativeBackend\) UsesBackendCandidatePaging\(\) bool\s*\{.*?return true\s*\}' -or
                    -not $pagingTestText.Contains('TestNativeBackendKeepsRimeOwnedCandidatePaging') -or
                    $pagingImplementationHash -ne [string]$acceptance.PagingOwnership.ImplementationSha256 -or
                    $pagingTestHash -ne [string]$acceptance.PagingOwnership.TestSha256) {
                    $acceptanceIssues.Add('Rime-owned paging guard changed after acceptance')
                }
            }
            $requiredPerPosition = [int]$acceptance.RequiredClassifiedTransactionsPerPosition
            if ($minimumCycles -lt 1 -or
                $requiredPerPosition -ne $minimumCycles * @($acceptance.HostOutcomeRecords).Count) {
                $acceptanceIssues.Add('classified RPC threshold is inconsistent with the host cycle count')
            }
            if ([int]$acceptance.Rpc.SuccessfulTransactionCount -lt [int]$acceptance.MinimumCorrelatedRpcTransactions) {
                $acceptanceIssues.Add('successful RPC count is below the acceptance threshold')
            }
            foreach ($position in @('first', 'middle', 'final')) {
                if ([int]$acceptance.Rpc.ClassifiedPositionCounts.$position -lt $requiredPerPosition) {
                    $acceptanceIssues.Add("insufficient classified $position segment RPC evidence")
                }
            }
            $longSessionAcceptance.status = if ($acceptanceIssues.Count -eq 0) { 'match' } else { 'mismatch' }
        } catch {
            $acceptanceIssues.Add("acceptance record is invalid: $($_.Exception.Message)")
            $longSessionAcceptance.status = 'invalid'
        }
    }
    $longSessionAcceptance.issues = @($acceptanceIssues)
}

$hardFailures = @($files | Where-Object {
    $_.required -and $_.status -ne 'match' -and -not ($AllowTextServiceMismatch -and $_.textService -and $_.status -eq 'mismatch')
})
$allowedDllMismatches = @($files | Where-Object { $_.textService -and $_.status -eq 'mismatch' })
if (-not $registryMatches) {
    $hardFailures += [pscustomobject]@{ name = 'HKLM/Software/YIME'; status = 'mismatch' }
}
if ($RequireRunningLauncher -and -not $launcherRunning) {
    $hardFailures += [pscustomobject]@{ name = 'PIMELauncher process'; status = 'not-running' }
}
if ($RequireFreshRimeCache) {
    foreach ($record in @($rimeCacheRecords | Where-Object { $_.status -ne 'match' })) {
        $hardFailures += [pscustomobject]@{ name = $record.name; status = $record.status }
    }
}
if ($RequireLongSessionAcceptance -and $longSessionAcceptance.status -ne 'match') {
    $hardFailures += [pscustomobject]@{ name = 'long-session acceptance'; status = $longSessionAcceptance.status }
}
foreach ($fileName in $retiredLeakage) {
    $hardFailures += [pscustomobject]@{ name = "retired/$fileName"; status = 'runtime-leak' }
}

$overall = if ($hardFailures.Count -gt 0) {
    'failed'
} elseif ($allowedDllMismatches.Count -gt 0 -or $rimeCacheIssues.Count -gt 0 -or
    ($LongSessionAcceptancePath -and $longSessionAcceptance.status -ne 'match')) {
    'partial'
} else {
    'complete'
}
$report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    repoRoot = $repoRoot
    installRoot = $installRoot
    overall = $overall
    registryRoot = $registryRoot
    registryMatches = [bool]$registryMatches
    launcherRunning = $launcherRunning
    launcherPathUnavailable = $launcherPathUnavailable
    retiredRuntimeLeakage = @($retiredLeakage)
    files = @($files)
    rimeCompiledCaches = @($rimeCacheRecords)
    longSessionAcceptance = [pscustomobject]$longSessionAcceptance
}

if ($JsonPath) {
    $jsonParent = Split-Path -Parent $JsonPath
    if ($jsonParent) { New-Item -ItemType Directory -Path $jsonParent -Force | Out-Null }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $JsonPath -Encoding utf8
}

$report.files | Format-Table name, status -AutoSize
$report.rimeCompiledCaches | Format-Table name, status, sourceCount -AutoSize
if ($LongSessionAcceptancePath -or $RequireLongSessionAcceptance) {
    [pscustomobject]$longSessionAcceptance | Format-List path, status, sha256, buildVersion, buildCommit, issues
}
Write-Host "Installed runtime verification: $overall"
if ($overall -eq 'failed') {
    throw "Installed runtime verification failed: $($hardFailures.name -join ', ')"
}
if ($overall -eq 'partial') {
    if ($allowedDllMismatches.Count -gt 0) {
        Write-Warning 'Install is partial because one or more loaded TSF DLLs could not be replaced. Reboot, reinstall, and verify again for a complete result.'
    }
    if ($rimeCacheIssues.Count -gt 0) {
        Write-Warning 'Install is partial because one or more deployed Rime schemas have missing, invalid, or stale compiled caches. Redeploy those schemas and verify again.'
    }
    if ($LongSessionAcceptancePath -and $longSessionAcceptance.status -ne 'match') {
        Write-Warning 'Install is partial because the long-session acceptance record does not match the installed build and hashes.'
    }
}

[pscustomobject]$report
