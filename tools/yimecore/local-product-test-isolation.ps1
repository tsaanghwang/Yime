# Build-validation only. Callers pass newly built current-product tools; this
# helper never discovers an installed executable or reuses a test state root.
function Invoke-LocalProductIsolatedTestTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tool,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$BuildRoot,
        [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$LogName
    )
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $allowedRoots = @((Join-Path $repo '.tmp\yimecore-local-product'), (Join-Path $repo '.tmp\yimecore-platform-experiments'))
    $build = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
    $evidence = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
    if (-not (@($allowedRoots | Where-Object { $build.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 1) -or
        ($evidence -ine $build -and -not $evidence.StartsWith($build + '\', [StringComparison]::OrdinalIgnoreCase)) -or
        $LogName -notmatch '^[a-z0-9][a-z0-9-]*\.txt$') {
        throw 'Test tools require attributable build-local evidence paths.'
    }
    Assert-LocalProductPlainPath $build
    Assert-LocalProductPlainPath $evidence
    if (-not (Test-Path -LiteralPath $evidence -PathType Container)) { throw 'Test evidence root is missing.' }
    if ($Tool -eq 'go') {
        $image = (Get-Command go -CommandType Application -ErrorAction Stop).Source
    } else {
        $image = [IO.Path]::GetFullPath($Tool)
        $nativeNames = @('YimeTextServiceContractTests.exe', 'YimeFocusCancellationTests.exe', 'YimeTsfCompositionTests.exe')
        if ((Split-Path -Leaf $image) -notin $nativeNames -or
            -not $image.StartsWith($build + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Native validation must use a test executable from this current source build.'
        }
    }
    Assert-LocalProductPlainPath $image
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw 'Test executable is missing.' }
    $log = Join-Path $evidence $LogName
    $metadata = $log + '.fixture.json'
    if ((Test-Path -LiteralPath $log) -or (Test-Path -LiteralPath $metadata)) { throw 'Do not overwrite earlier test evidence.' }
    # Native state helpers use MAX_PATH APIs, so TEMP must stay short no matter how
    # deep the repository or build root lives (worktrees, long branch names). Run
    # against a short per-invocation root outside the repository, then move the
    # retained synthetic state under the build root so evidence stays attributable.
    $fixtureBase = Get-LocalProductFixtureBase
    $fixtureId = [guid]::NewGuid().ToString('N').Substring(0,16)
    $fixture = Join-Path $fixtureBase $fixtureId
    $retained = Join-Path $build ('t\' + $fixtureId)
    $fixtureTemp = Join-Path $fixture 'tmp'
    if ($fixtureTemp.Length -gt 120) { throw ('Test TEMP is too long for native state-file APIs (' + $fixtureTemp.Length + ' chars): ' + $fixtureTemp) }
    Assert-LocalProductPlainPath $fixture
    if ((Test-Path -LiteralPath $fixture) -or (Test-Path -LiteralPath $retained)) { throw 'Test state must be new for every invocation.' }
    $environment = [ordered]@{
        TEMP=$fixtureTemp; TMP=$fixtureTemp
        LOCALAPPDATA=(Join-Path $fixture 'local'); APPDATA=(Join-Path $fixture 'roaming')
    }
    New-Item -ItemType Directory -Path @($environment.Values | Select-Object -Unique) | Out-Null
    foreach ($path in $environment.Values) { Assert-LocalProductPlainPath $path }
    $previous = @{}
    foreach ($name in $environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $record = [ordered]@{
        executable=$image; fixture_root=$retained; fixture_runtime_root=$fixture; fixture_retained=$false; environment=$environment
        environment_isolated=$false; environment_restored=$false
        executed=$false; exit_code=$null; passed=$false
        scope='Fresh per-invocation TEMP/TMP/LOCALAPPDATA/APPDATA at a short runtime root; synthetic state is moved under the build root afterwards; previous environment values are never recorded.'
    }
    try {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, [string]$environment[$name], 'Process')
        }
        foreach ($name in $environment.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $environment[$name]) {
                throw 'Test environment could not be isolated.'
            }
        }
        $record.environment_isolated = $true
        $record.executed = $true
        & $image @Arguments 2>&1 | Tee-Object -LiteralPath $log
        $record.exit_code = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) { throw "Isolated test exited $LASTEXITCODE; inspect $log" }
        $record.passed = $true
    } finally {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
        $restored = $true
        foreach ($name in $environment.Keys) {
            if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $previous[$name]) { $restored = $false }
        }
        $record.environment_restored = $restored
        $record.passed = [bool]($record.passed -and $restored)
        # Retain the synthetic state next to the build for attribution. A failed move
        # keeps the runtime root in place and is recorded; it never discards evidence.
        try {
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $retained) -Force
            Move-Item -LiteralPath $fixture -Destination $retained
            $record.fixture_retained = [bool]((Test-Path -LiteralPath $retained -PathType Container) -and -not (Test-Path -LiteralPath $fixture))
        } catch { $record['fixture_retention_error'] = $_.Exception.Message }
        Write-LocalProductJson $record $metadata
        if (-not $restored) { throw 'Calling process environment was not restored after an isolated test.' }
    }
}

# Short, repository-independent root for per-invocation synthetic state. The
# caller's own LOCALAPPDATA is only the anchor; each fixture is a fresh child that
# never touches a product state directory.
function Get-LocalProductFixtureBase {
    $anchor = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
    if (-not $anchor -or -not [IO.Path]::IsPathRooted($anchor)) { throw 'LOCALAPPDATA is required to anchor short test fixtures.' }
    $base = Join-Path ([IO.Path]::GetFullPath($anchor).TrimEnd('\')) 'YimeBuildFixtures'
    if ($base.Length -gt 90) { throw ('Fixture anchor is too long for native state-file APIs: ' + $base) }
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { New-Item -ItemType Directory -Path $base | Out-Null }
    Assert-LocalProductPlainPath $base
    return $base
}
