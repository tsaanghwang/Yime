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
    $allowed = Join-Path $repo '.tmp\yimecore-local-product'
    $build = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
    $evidence = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
    if (-not $build.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase) -or
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
    # Keep TEMP short enough for native MAX_PATH state helpers, even when the
    # direct TSF test adds its own fresh GUID-named subdirectory.
    $fixture = Join-Path $evidence ('t\' + [guid]::NewGuid().ToString('N').Substring(0,16))
    $fixtureTemp = Join-Path $fixture 'tmp'
    if ($fixtureTemp.Length -gt 120) { throw 'Test TEMP is too long for native state-file APIs.' }
    Assert-LocalProductPlainPath $fixture
    if (Test-Path -LiteralPath $fixture) { throw 'Test state must be new for every invocation.' }
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
        executable=$image; fixture_root=$fixture; environment=$environment
        environment_isolated=$false; environment_restored=$false
        executed=$false; exit_code=$null; passed=$false
        scope='Fresh per-invocation TEMP/TMP/LOCALAPPDATA/APPDATA; retain synthetic state, never record previous environment values.'
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
        Write-LocalProductJson $record $metadata
        if (-not $restored) { throw 'Calling process environment was not restored after an isolated test.' }
    }
}
