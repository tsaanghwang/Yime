[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BootstrapPath,
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$parent = Join-Path $repo '.tmp\dual-product'
$module = Import-Module (Join-Path $repo 'tools\dual-product\rime-pime-nsis-toolchain-closure.psm1') -PassThru
$null = & $module { param($path) Assert-YimePimePayloadAbsolutePath $path } $OutputRoot
if ($OutputRoot -cne [IO.Path]::GetFullPath($OutputRoot) -or (Split-Path -Parent $OutputRoot) -cne $parent -or
    (Split-Path -Leaf $OutputRoot) -cnotmatch '^dp1-sevenzip-preparation-test-[A-Za-z0-9][A-Za-z0-9-]*$') {
    throw 'Test output must be a canonical repository 7-Zip preparation test root.'
}
if (Test-Path -LiteralPath $OutputRoot) { throw 'Test output already exists.' }
$null = New-Item -ItemType Directory -Path $OutputRoot
$id = [Guid]::NewGuid().ToString('N')
$prepare = Join-Path $PSScriptRoot 'prepare-pinned-sevenzip.ps1'
$lock = Read-RimePimeNsisCompilerToolchainLockDocument
$results = [Collections.Generic.List[object]]::new()
$createdStages = [Collections.Generic.List[string]]::new()
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $results.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
    if (-not $Passed) { throw "7-Zip preparation regression failed: $Name ($Detail)" }
}
function Assert-Rejected([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { $null = & $Action } catch { $message = $_.Exception.Message }
    Add-Check $Name ($null -ne $message -and $message -match $Pattern) ([string]$message)
}
function New-StagePath([string]$Leaf) {
    $path = Join-Path $parent ('dp1-sevenzip-distribution-' + $id + '-' + $Leaf)
    $createdStages.Add($path)
    return $path
}
function Change-TestByte([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { $value = $stream.ReadByte(); $stream.Position = 0; $stream.WriteByte([byte]($value -bxor 1)); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function Get-TestHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$failure = $null; $prepared = $null
try {
    foreach ($path in @($BootstrapPath, $ArchivePath)) {
        $null = & $module { param($inputPath) Assert-YimePimePayloadAbsolutePath $inputPath } $path
    }
    $originalBootstrapHash = Get-TestHash $BootstrapPath
    $originalArchiveHash = Get-TestHash $ArchivePath
    $lockHash = Get-TestHash $lock.Path
    $sidecarHash = Get-TestHash $lock.Sidecar
    $inputs = Join-Path $OutputRoot 'inputs with spaces'
    $null = New-Item -ItemType Directory -Path $inputs
    $bootstrap = Join-Path $inputs 'bootstrap 7zr.exe'
    $archive = Join-Path $inputs 'official setup.exe'
    [IO.File]::Copy($BootstrapPath, $bootstrap, $false)
    [IO.File]::Copy($ArchivePath, $archive, $false)

    # Guard the execution boundary as well as checking its observable failures:
    # both input pins precede process creation, and only the bootstrap is a
    # process image. The setup path must remain an archive argument.
    $source = [IO.File]::ReadAllText($prepare)
    $bootstrapPin = $source.IndexOf('Open-RimePimeNsisClosureFileLease $bootstrapFull $bootstrapRecord', [StringComparison]::Ordinal)
    $archivePin = $source.IndexOf('Open-RimePimeNsisClosureFileLease $archiveFull $archiveRecord', [StringComparison]::Ordinal)
    $processStart = $source.IndexOf('[Diagnostics.Process]::new()', [StringComparison]::Ordinal)
    $imageAssignments = [regex]::Matches($source, '(?m)^\s*\$process\.StartInfo\.FileName\s*=\s*(.+)$')
    Add-Check 'both-input-pins-precede-process-creation' ($bootstrapPin -ge 0 -and $archivePin -ge 0 -and $processStart -gt $bootstrapPin -and $processStart -gt $archivePin)
    Add-Check 'only-pinned-bootstrap-used-as-process-image' ($imageAssignments.Count -eq 1 -and $imageAssignments[0].Groups[1].Value.Trim() -ceq '$bootstrapFull' -and
        $source -notmatch '(?im)^\s*(?:&\s+|Start-Process\s|Invoke-Expression\s)\$?(?:archive|ArchivePath|sevenZipExe)\b')

    $goodStage = New-StagePath 'good'
    $savedPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('Path', (Join-Path $OutputRoot 'absent-command-search-path'), 'Process')
        $success = @(& $prepare -BootstrapPath $bootstrap -ArchivePath $archive -OutputRoot $goodStage)
    } finally { [Environment]::SetEnvironmentVariable('Path', $savedPath, 'Process') }
    Add-Check 'path-restored-after-isolated-preparation' ([Environment]::GetEnvironmentVariable('Path', 'Process') -ceq $savedPath)
    Add-Check 'single-result-object-with-no-path-discovery' ($success.Count -eq 1 -and $null -ne $success[0].Evidence)
    $prepared = $success[0]
    Add-Check 'root-and-schema' ($prepared.Root -ceq (Join-Path $goodStage '7-Zip') -and $prepared.Evidence.schema_version -ceq 'yime-pinned-sevenzip-preparation-v1')
    Add-Check 'official-bootstrap-pin' ($prepared.Evidence.bootstrap_bytes -eq 602112 -and $prepared.Evidence.bootstrap_sha256 -ceq '56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72')
    Add-Check 'official-setup-pin' ($prepared.Evidence.official_archive_bytes -eq 1657896 -and $prepared.Evidence.official_archive_sha256 -ceq '6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0')
    $members = @(Get-ChildItem -LiteralPath $prepared.Root -Force)
    Add-Check 'exactly-two-plain-output-members' ($members.Count -eq 2 -and @($members | Where-Object { $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }).Count -eq 0 -and
        (@($members.Name | Sort-Object) -join '|') -ceq '7z.dll|7z.exe' -and ($prepared.Evidence.extraction_scope -join '|') -ceq '7z.exe|7z.dll')
    foreach ($record in @($lock.Document.seven_zip, $lock.Document.seven_zip.library)) {
        $name = [IO.Path]::GetFileName([string]$record.path)
        $path = Join-Path $prepared.Root $name
        Add-Check ('original-lock-pin-' + $name) ((Get-Item -LiteralPath $path).Length -eq $record.bytes -and (Get-TestHash $path) -ceq $record.sha256)
    }
    Add-Check 'evidence-matches-original-exe-and-dll-lock' ($prepared.Evidence.toolchain_lock_sha256 -ceq $lock.Digest -and
        $prepared.Evidence.seven_zip_exe_bytes -eq $lock.Document.seven_zip.bytes -and $prepared.Evidence.seven_zip_exe_sha256 -ceq $lock.Document.seven_zip.sha256 -and
        $prepared.Evidence.seven_zip_library_bytes -eq $lock.Document.seven_zip.library.bytes -and $prepared.Evidence.seven_zip_library_sha256 -ceq $lock.Document.seven_zip.library.sha256)
    Add-Check 'held-verification-is-not-persistent-execution-authority' ($prepared.Evidence.extraction_input_read_leases_held -and
        $prepared.Evidence.verification_scope -ceq 'held-during-staged-verification-only' -and $prepared.Evidence.leases_released_before_return -and $prepared.Evidence.bootstrap_executed -and
        -not $prepared.Evidence.installer_executed -and -not $prepared.Evidence.compiler_executed -and -not $prepared.Evidence.installed_seven_zip_modified -and
        -not $prepared.Evidence.runner_installed_archiver_used -and -not $prepared.Evidence.active_same_sid_transient_tree_membership_interference_excluded -and
        -not $prepared.Evidence.full_toolchain_input_closure -and -not $prepared.Evidence.execution_authorized -and -not $prepared.Evidence.full_acceptance)
    foreach ($path in @($bootstrap, $archive, (Join-Path $prepared.Root '7z.exe'), (Join-Path $prepared.Root '7z.dll'))) {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $stream.Dispose()
    }
    Add-Check 'all-verification-leases-released' $true

    foreach ($kind in @('bootstrap', 'setup')) {
        $sourcePath = if ($kind -ceq 'bootstrap') { $bootstrap } else { $archive }
        $badInput = Join-Path $inputs ('corrupt-' + $kind + '.exe')
        [IO.File]::Copy($sourcePath, $badInput, $false); Change-TestByte $badInput
        Add-Check ('corrupt-' + $kind + '-preserves-length') ((Get-Item -LiteralPath $badInput).Length -eq (Get-Item -LiteralPath $sourcePath).Length)
        $stage = New-StagePath ('corrupt-' + $kind)
        $testBootstrap = if ($kind -ceq 'bootstrap') { $badInput } else { $bootstrap }
        $testArchive = if ($kind -ceq 'setup') { $badInput } else { $archive }
        Assert-Rejected ('same-length-' + $kind + '-hash-rejected') { & $prepare -BootstrapPath $testBootstrap -ArchivePath $testArchive -OutputRoot $stage } '^Official 7-Zip (bootstrap|setup archive) differs from the repository-pinned record\.$'
        Add-Check ('corrupt-' + $kind + '-rejected-before-output') (-not (Test-Path -LiteralPath $stage))
        $stage = New-StagePath ('missing-' + $kind)
        $missing = Join-Path $inputs ('absent-' + $kind + '.exe')
        $testBootstrap = if ($kind -ceq 'bootstrap') { $missing } else { $bootstrap }
        $testArchive = if ($kind -ceq 'setup') { $missing } else { $archive }
        Assert-Rejected ('missing-' + $kind + '-rejected') { & $prepare -BootstrapPath $testBootstrap -ArchivePath $testArchive -OutputRoot $stage } 'missing|exist|find|not found'
        Add-Check ('missing-' + $kind + '-rejected-before-output') (-not (Test-Path -LiteralPath $stage))
    }

    $inputLink = Join-Path $OutputRoot 'input-junction'
    $null = New-Item -ItemType Junction -Path $inputLink -Target $inputs
    foreach ($kind in @('bootstrap', 'setup')) {
        $stage = New-StagePath ('reparse-' + $kind)
        $testBootstrap = if ($kind -ceq 'bootstrap') { Join-Path $inputLink 'bootstrap 7zr.exe' } else { $bootstrap }
        $testArchive = if ($kind -ceq 'setup') { Join-Path $inputLink 'official setup.exe' } else { $archive }
        Assert-Rejected ('reparse-' + $kind + '-ancestor-rejected') { & $prepare -BootstrapPath $testBootstrap -ArchivePath $testArchive -OutputRoot $stage } '[Rr]eparse'
        Add-Check ('reparse-' + $kind + '-rejected-before-output') (-not (Test-Path -LiteralPath $stage))
    }
    $existing = New-StagePath 'existing'; $null = New-Item -ItemType Directory -Path $existing
    $sentinel = Join-Path $existing 'preserve.txt'; [IO.File]::WriteAllText($sentinel, 'owned regression sentinel')
    Assert-Rejected 'existing-output-rejected-before-input-read' { & $prepare -BootstrapPath $missing -ArchivePath $missing -OutputRoot $existing } '^7-Zip preparation output already exists\.$'
    Add-Check 'existing-output-preserved' ([IO.File]::ReadAllText($sentinel) -ceq 'owned regression sentinel' -and @(Get-ChildItem -LiteralPath $existing -Force).Count -eq 1)
    $linkStage = New-StagePath 'junction'
    $target = Join-Path $OutputRoot 'output-junction-target'; $null = New-Item -ItemType Directory -Path $target
    $null = New-Item -ItemType Junction -Path $linkStage -Target $target
    Assert-Rejected 'reparse-output-rejected' { & $prepare -BootstrapPath $bootstrap -ArchivePath $archive -OutputRoot $linkStage } 'already exists|[Rr]eparse'
    Add-Check 'reparse-output-target-preserved-empty' (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 0)
    foreach ($path in @((Join-Path $OutputRoot 'dp1-sevenzip-distribution-nested'), '.tmp\dual-product\dp1-sevenzip-distribution-relative',
        (Join-Path $parent 'dp1-sevenzip-distribution-..\escape'), $goodStage.Replace('\', '/'))) {
        Assert-Rejected 'malformed-or-outside-output-rejected' { & $prepare -BootstrapPath $bootstrap -ArchivePath $archive -OutputRoot $path } '^OutputRoot must be '
    }
    Add-Check 'supplied-bootstrap-and-setup-unchanged' ((Get-TestHash $BootstrapPath) -ceq $originalBootstrapHash -and (Get-TestHash $ArchivePath) -ceq $originalArchiveHash)
    Add-Check 'fixture-inputs-unchanged' ((Get-TestHash $bootstrap) -ceq $originalBootstrapHash -and (Get-TestHash $archive) -ceq $originalArchiveHash)
    Add-Check 'original-postbuild-lock-and-sidecar-unchanged' ((Get-TestHash $lock.Path) -ceq $lockHash -and (Get-TestHash $lock.Sidecar) -ceq $sidecarHash)
} catch { $failure = $_; $results.Add([pscustomobject]@{ name = 'unexpected-error'; passed = $false; detail = $_.Exception.Message }) }
finally {
    $summary = [pscustomobject][ordered]@{
        schema_version = 'yime-pinned-sevenzip-preparation-test-v1'
        passed = ($null -eq $failure)
        powershell_version = $PSVersionTable.PSVersion.ToString()
        preparation_source_sha256 = Get-TestHash $prepare
        test_source_sha256 = Get-TestHash $PSCommandPath
        preparation = $prepared
        checks = @($results); check_count = $results.Count; stage_paths = @($createdStages)
        installer_executed = $false; compiler_executed = $false; installed_seven_zip_modified = $false
        actual_user_state_accessed = $false; local12_touched = $false; full_acceptance = $false
    }
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}
if ($null -ne $failure) { throw $failure }
$summary
