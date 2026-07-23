param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Invoke-GoCommand {
    param([string[]]$Arguments)

    & go @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "go $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$goBackendRoot = Join-Path $repoRoot 'go-backend'
if (-not (Test-Path -LiteralPath (Join-Path $goBackendRoot 'go.mod'))) {
    throw "go-backend/go.mod was not found under $repoRoot"
}

if (-not $env:GOCACHE) {
    $env:GOCACHE = Join-Path $repoRoot '.tmp\go-cache'
}
if (-not $env:GOTMPDIR) {
    $env:GOTMPDIR = Join-Path $repoRoot '.tmp\go-tmp'
}
New-Item -ItemType Directory -Path $env:GOCACHE, $env:GOTMPDIR -Force | Out-Null

$requiredYimeTests = @(
    'TestNativeBackendKeepsRimeOwnedCandidatePaging'
    'TestAllSchemasKeepNavigatorBeforeEditor'
    'TestReturnKeyUpAfterHostCandidateSelectionDoesNotCommitRawComposition'
    'TestLanguageBarToggleButtonsUseStableTwoCharacterLabels'
    'TestDeployCommandQueuesConfirmedExternalBuildWithoutNativeRedeploy'
    'TestApplyUserLexiconWritesAllThreeModes'
    'TestApplyUserLexiconRunsExternalBuildAndSchedulesReload'
    'TestUserLexiconManagerLaunchesNativeExecutable'
    'TestToolHubLaunchesNativeExecutable'
    'TestReverseLookupToolLaunchesNativeExecutable'
    'TestSettingsToolLaunchesNativeExecutable'
    'TestDiagnosticsToolLaunchesNativeExecutable'
)

Push-Location $goBackendRoot
try {
    Invoke-GoCommand -Arguments @('vet', './...')
    # Keep package compilation serial. On SAC/antivirus-controlled Windows hosts,
    # a wide compile fan-out can terminate compile.exe without a Go diagnostic.
    Invoke-GoCommand -Arguments @('test', '-p=1', './...', '-timeout', "${TimeoutSeconds}s")

    $listedYimeTests = @(& go test ./input_methods/yime -list '^Test')
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not enumerate Yime regression tests.'
    }
    foreach ($testName in $requiredYimeTests) {
        if ($listedYimeTests -notcontains $testName) {
            throw "Required Yime regression test is missing: $testName"
        }
    }

    $requiredPattern = '^(' + (($requiredYimeTests | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ')$'
    Invoke-GoCommand -Arguments @('test', './input_methods/yime', '-run', $requiredPattern, '-count=1', '-timeout', "${TimeoutSeconds}s")
} finally {
    Pop-Location
}

Write-Host 'Go stable verification passed.'
