[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$PatchedFixtureRoot,
    [string]$EnVarFixtureRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$parent = Join-Path $repo '.tmp\dual-product'
$module = Import-Module (Join-Path $repo 'tools\dual-product\rime-pime-nsis-toolchain-closure.psm1') -PassThru
$null = & $module { param($path) Assert-YimePimePayloadAbsolutePath $path } $OutputRoot
if ($OutputRoot -cne [IO.Path]::GetFullPath($OutputRoot) -or (Split-Path -Parent $OutputRoot) -cne $parent -or
    (Split-Path -Leaf $OutputRoot) -cnotmatch '^dp1-nsis-preparation-test-[A-Za-z0-9][A-Za-z0-9-]*$') { throw 'Test output must be a canonical repository NSIS preparation test root.' }
if (Test-Path -LiteralPath $OutputRoot) { throw 'Test output already exists.' }
$null = New-Item -ItemType Directory -Path $OutputRoot
$id = [Guid]::NewGuid().ToString('N')
$prepare = Join-Path $PSScriptRoot 'prepare-pinned-nsis.ps1'
$lock = Read-RimePimeNsisCompilerToolchainLockDocument
$results = [Collections.Generic.List[object]]::new()
$createdStages = [Collections.Generic.List[string]]::new()
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $results.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
    if (-not $Passed) { throw "NSIS preparation regression failed: $Name ($Detail)" }
}
function Assert-Rejected([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { $null = & $Action } catch { $message = $_.Exception.Message }
    Add-Check $Name ($null -ne $message -and $message -match $Pattern) ([string]$message)
}
function New-StagePath([string]$Leaf) {
    $path = Join-Path $parent ('dp1-nsis-distribution-' + $id + '-' + $Leaf)
    $createdStages.Add($path)
    return $path
}
function Copy-TestTree([string]$Source, [string]$Destination) {
    $null = & $module { param($path) Assert-YimePimePayloadAbsolutePath $path } $Source
    if (Test-Path -LiteralPath $Destination) { throw 'Fixture destination already exists.' }
    $null = New-Item -ItemType Directory -Path $Destination
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture source contains a reparse point.' }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-TestTree $item.FullName $target }
        else { [IO.File]::Copy($item.FullName, $target, $false) }
    }
}
function Assert-TreeRejected([string]$Name, [string]$Root) {
    Assert-Rejected $Name {
        & $module {
            param($root, $record)
            $closure = $null
            try { $closure = Open-RimePimeNsisCompilerInputClosureCore $root $record }
            finally { if ($null -ne $closure) { Close-RimePimeNsisCompilerInputClosure $closure } }
        } $Root $lock.Document.nsis.compiler_input_closure
    } 'NSIS.*(differ|mismatch|count|missing|changed|match)'
}
function Change-TestByte([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { $value = $stream.ReadByte(); $stream.Position = 0; $stream.WriteByte([byte]($value -bxor 1)); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function Test-CompositeGuards {
    $actionPath = Join-Path $repo '.github\actions\prepare-pinned-nsis\action.yml'
    $lines = [IO.File]::ReadAllLines($actionPath)
    $marker = -1
    for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -ceq '      run: |') { if ($marker -ge 0) { throw 'Ambiguous action body.' }; $marker = $i } }
    if ($marker -lt 0) { throw 'Action PowerShell body not found.' }
    $body = [Collections.Generic.List[string]]::new()
    for ($i = $marker + 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i].Length -eq 0) { $body.Add(''); continue }
        if (-not $lines[$i].StartsWith('        ', [StringComparison]::Ordinal)) { throw 'Unexpected action body indentation.' }
        $body.Add($lines[$i].Substring(8))
    }
    $action = [scriptblock]::Create(($body -join "`n"))
    $empty = Join-Path $OutputRoot 'empty-workspace'
    $null = New-Item -ItemType Directory -Path $empty
    $variables = @('GITHUB_ACTIONS', 'NSIS_RUNNER_ENVIRONMENT', 'NSIS_VERSION', 'GITHUB_WORKSPACE', 'GITHUB_PATH', 'GITHUB_OUTPUT')
    $saved = @{}
    foreach ($name in $variables) {
        $path = 'Env:\' + $name
        $saved[$name] = [pscustomobject]@{ present = Test-Path -LiteralPath $path; value = [Environment]::GetEnvironmentVariable($name, 'Process') }
    }
    try {
        $env:GITHUB_WORKSPACE = $empty; $env:GITHUB_PATH = ''; $env:GITHUB_OUTPUT = ''
        foreach ($case in @(
            @('non-ci', 'false', 'github-hosted', '3.12', 'Fixed-root NSIS preparation is restricted to GitHub-hosted CI.'),
            @('self-hosted', 'true', 'self-hosted', '3.12', 'Fixed-root NSIS preparation is restricted to GitHub-hosted CI.'),
            @('wrong-version', 'true', 'github-hosted', '3.11', 'Only the pinned NSIS 3.12 distribution is admissible.')
        )) {
            $env:GITHUB_ACTIONS = $case[1]; $env:NSIS_RUNNER_ENVIRONMENT = $case[2]; $env:NSIS_VERSION = $case[3]
            Assert-Rejected ('composite-' + $case[0]) $action ('^' + [regex]::Escape($case[4]) + '$')
        }
        Add-Check 'composite-rejections-did-not-write-fixture' (@(Get-ChildItem -LiteralPath $empty -Force).Count -eq 0)
    } finally {
        foreach ($name in $variables) {
            if ($saved[$name].present) { [Environment]::SetEnvironmentVariable($name, $saved[$name].value, 'Process') }
            else { Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue }
        }
    }
    foreach ($name in $variables) {
        Add-Check ('composite-restored-' + $name) ((Test-Path -LiteralPath ('Env:\' + $name)) -eq $saved[$name].present -and
            [Environment]::GetEnvironmentVariable($name, 'Process') -ceq $saved[$name].value)
    }
}

$failure = $null; $prepared = $null
try {
    Test-CompositeGuards
    $originalHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $goodStage = New-StagePath 'good'
    $success = @(& $prepare -ArchivePath $ArchivePath -OutputRoot $goodStage)
    Add-Check 'single-result-object' ($success.Count -eq 1 -and $null -ne $success[0].Evidence)
    $prepared = $success[0]
    Add-Check 'official-archive-pin' ($prepared.Evidence.official_archive_sha256 -ceq '3bc2b06253a7e4957111be152ac6a536e0c7478a706e19da814038db5d706495' -and $prepared.Evidence.official_archive_bytes -eq 1566914)
    Add-Check 'strict-tree-pin' ($prepared.Evidence.nsis_compiler_input_tree_sha256 -ceq 'a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352' -and
        $prepared.Evidence.nsis_compiler_input_file_count -eq 303 -and $prepared.Evidence.nsis_compiler_input_directory_count -eq 17)
    Add-Check 'original-incomplete-closure-fields-preserved' (-not $prepared.Evidence.active_same_sid_transient_tree_membership_interference_excluded -and
        -not $prepared.Evidence.nsis_non_os_compiler_input_closure -and -not $prepared.Evidence.full_nsis_toolchain_input_closure -and
        -not $prepared.Evidence.installer_executed -and -not $prepared.Evidence.compiler_executed -and -not $prepared.Evidence.installed_nsis_modified -and
        -not $prepared.Evidence.execution_authorized -and -not $prepared.Evidence.full_acceptance)
    Add-Check 'only-five-scoped-roots-extracted' ((@(Get-ChildItem -LiteralPath $prepared.Root -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join '|') -ceq 'Bin|Contrib|Include|Plugins|Stubs' -and
        (@(Get-ChildItem -LiteralPath (Join-Path $prepared.Root 'Plugins') -Force | ForEach-Object { $_.Name }) -join '|') -ceq 'x86-unicode')
    Add-Check 'three-reviewed-case-mappings-only' (@($prepared.Evidence.canonical_case_mappings).Count -eq 3 -and
        (@($prepared.Evidence.canonical_case_mappings | ForEach-Object { $_.from + '>' + $_.to }) -join '|') -ceq
        'Plugins/x86-unicode/AdvSplash.dll>Plugins/x86-unicode/advsplash.dll|Plugins/x86-unicode/NSISdl.dll>Plugins/x86-unicode/nsisdl.dll|Plugins/x86-unicode/Splash.dll>Plugins/x86-unicode/splash.dll')
    foreach ($name in @('advsplash.dll', 'nsisdl.dll', 'splash.dll')) {
        Add-Check ('canonical-plugin-name-' + $name) ((Get-Item -LiteralPath (Join-Path $prepared.Root ('Plugins\x86-unicode\' + $name))).Name -ceq $name)
    }
    # A real writer succeeds after return: the evidence does not imply an
    # execution lease continues to protect the returned pathname.
    $released = [IO.File]::Open((Join-Path $prepared.Root 'Bin\makensis.exe'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $released.Dispose()
    Add-Check 'verification-leases-released-before-return' $prepared.Evidence.leases_released_before_return

    $badArchive = Join-Path $OutputRoot 'wrong-archive.exe'
    [IO.File]::Copy($ArchivePath, $badArchive, $false); Change-TestByte $badArchive
    $badStage = New-StagePath 'wrong-archive'
    Assert-Rejected 'wrong-archive-pin-rejected' { & $prepare -ArchivePath $badArchive -OutputRoot $badStage } 'Official NSIS setup archive differs from the repository-pinned record'
    Add-Check 'wrong-archive-rejected-before-output-creation' (-not (Test-Path -LiteralPath $badStage))
    Assert-Rejected 'existing-output-rejected-first' { & $prepare -ArchivePath (Join-Path $OutputRoot 'absent.exe') -OutputRoot $goodStage } '^NSIS preparation output already exists\.$'
    Assert-Rejected 'outside-output-root-rejected' { & $prepare -ArchivePath $ArchivePath -OutputRoot (Join-Path $OutputRoot 'dp1-nsis-distribution-escape') } '^OutputRoot must be '
    $linkStage = New-StagePath 'junction'
    $target = Join-Path $OutputRoot 'junction-target'; $null = New-Item -ItemType Directory -Path $target
    $null = New-Item -ItemType Junction -Path $linkStage -Target $target
    Assert-Rejected 'reparse-output-rejected' { & $prepare -ArchivePath $ArchivePath -OutputRoot $linkStage } 'already exists|[Rr]eparse'
    $archiveLink = Join-Path $OutputRoot 'archive-link'; $null = New-Item -ItemType Junction -Path $archiveLink -Target $OutputRoot
    $linkedStage = New-StagePath 'archive-junction'
    Assert-Rejected 'reparse-archive-ancestor-rejected' { & $prepare -ArchivePath (Join-Path $archiveLink 'wrong-archive.exe') -OutputRoot $linkedStage } '[Rr]eparse'
    Add-Check 'reparse-archive-rejected-before-output-creation' (-not (Test-Path -LiteralPath $linkedStage))

    foreach ($case in @('extra-file', 'extra-directory', 'missing-file', 'changed-compiler', 'changed-stub')) {
        $tree = Join-Path $OutputRoot $case
        Copy-TestTree $prepared.Root $tree
        switch ($case) {
            'extra-file' { [IO.File]::WriteAllText((Join-Path $tree 'Contrib\unexpected.txt'), 'unlisted fixture') }
            'extra-directory' { $null = New-Item -ItemType Directory -Path (Join-Path $tree 'Contrib\unexpected-empty') }
            'missing-file' { Remove-Item -LiteralPath (Join-Path $tree 'Include\FileFunc.nsh') }
            'changed-compiler' { Change-TestByte (Join-Path $tree 'Bin\makensis.exe') }
            'changed-stub' { Change-TestByte (Join-Path $tree 'Stubs\lzma_solid-x86-unicode') }
        }
        Assert-TreeRejected ('original-closure-rejects-' + $case) $tree
    }
    foreach ($optional in @(@('real-8192-patch', $PatchedFixtureRoot, @('Bin', 'Stubs')), @('real-envar-contrib', $EnVarFixtureRoot, @('Contrib')))) {
        if ([string]::IsNullOrEmpty([string]$optional[1])) { continue }
        $fixtureRoot = [string]$optional[1]
        $null = & $module { param($path) Assert-YimePimePayloadAbsolutePath $path } $fixtureRoot
        # Optional inputs are public, pre-extracted repository cache fixtures.
        if (-not $fixtureRoot.StartsWith((Join-Path $repo '.tmp') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Optional fixture must be inside repository .tmp.' }
        $tree = Join-Path $OutputRoot $optional[0]; Copy-TestTree $prepared.Root $tree
        foreach ($scope in $optional[2]) {
            $source = Join-Path $fixtureRoot $scope
            foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force) {
                $null = & $module { param($path) Assert-YimePimePayloadAbsolutePath $path } $file.FullName
                $relative = $file.FullName.Substring($fixtureRoot.Length + 1)
                $destination = Join-Path $tree $relative
                $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
                [IO.File]::Copy($file.FullName, $destination, $true)
            }
        }
        Assert-TreeRejected ('original-closure-rejects-' + $optional[0]) $tree
    }
    Add-Check 'supplied-official-archive-unchanged' ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $originalHash)
} catch { $failure = $_; $results.Add([pscustomobject]@{ name = 'unexpected-error'; passed = $false; detail = $_.Exception.Message }) }
finally {
    $summary = [pscustomobject][ordered]@{
        schema_version = 'yime-pinned-nsis-preparation-test-v1'
        passed = ($null -eq $failure)
        powershell_version = $PSVersionTable.PSVersion.ToString()
        preparation_source_sha256 = (Get-FileHash -LiteralPath $prepare -Algorithm SHA256).Hash.ToLowerInvariant()
        test_source_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        preparation = $prepared
        checks = @($results); check_count = $results.Count; stage_paths = @($createdStages)
        installer_executed = $false; compiler_executed = $false; installed_nsis_modified = $false
        actual_user_state_accessed = $false; full_acceptance = $false
    }
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}
if ($null -ne $failure) { throw $failure }
$summary
