[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
$parent = Join-Path $repo '.tmp\dual-product'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd([char]92)
if ((Split-Path -Parent $output) -ine $parent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-j-membership-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh immediate .tmp/dual-product/dp1-j-membership-test-* root.'
}
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
New-Item -ItemType Directory -Path $output | Out-Null

$modulePath = Join-Path $PSScriptRoot 'rime-pime-nsis-membership-monitor-v1.psm1'
$helperPath = Join-Path $PSScriptRoot 'rime-pime-nsis-membership-monitor-v1.ps1'
$workerPath = Join-Path $PSScriptRoot 'invoke-rime-pime-nsis-membership-fixture-writer-v1.ps1'
$beforeImport = @(Get-ChildItem -LiteralPath $output -Force -Recurse).Count
$module = Import-Module $modulePath -Force -PassThru
$afterImport = @(Get-ChildItem -LiteralPath $output -Force -Recurse).Count

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Action) {
    try { & $Action; $checks.Add([pscustomobject][ordered]@{ name = $Name; passed = $true }) }
    catch { $checks.Add([pscustomobject][ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message }) }
}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Like = '*') {
    try { & $Action | Out-Null }
    catch { if ($_.Exception.Message -notlike $Like) { throw 'Fixture failed closed for an unexpected reason.' }; return }
    throw 'Unsafe membership interval was accepted.'
}
function New-Case([string]$Name) {
    $root = Join-Path $output $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'nested') | Out-Null
    return $root
}
function Touch-Then-Delete([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.WriteByte(0x4a); $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Delete($Path)
}
function Hash-Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Invoke-ChildWriter([string]$Root) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sidDigest = Hash-Text $sid
    $escapedWorker = $workerPath.Replace("'", "''")
    $escapedRoot = $Root.Replace("'", "''")
    $command = "& '$escapedWorker' -Root '$escapedRoot' -ExpectedSidSha256 '$sidDigest'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $hostExe
    $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Could not start isolated fixture writer.' }
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill(); $process.WaitForExit() } catch { }
            throw 'Isolated fixture writer timed out.'
        }
        if ($process.ExitCode -ne 0) { throw 'Isolated fixture writer failed.' }
    }
    finally { $process.Dispose() }
}

Check 'module-import-is-definitions-only' {
    Assert-True ($beforeImport -eq 0 -and $afterImport -eq 0) 'Import changed the fixture tree.'
}
Check 'module-exports-exact-public-api' {
    $expected = @(
        'Assert-RimePimeNsisMembershipMonitorArmedV1',
        'Close-RimePimeNsisMembershipMonitorV1',
        'Complete-RimePimeNsisMembershipMonitorV1',
        'Open-RimePimeNsisMembershipMonitorV1'
    )
    $actual = @($module.ExportedFunctions.Keys | Sort-Object)
    Assert-True (($actual -join '|') -ceq ($expected -join '|')) 'Module export surface drifted.'
}
Check 'no-change-interval-completes-at-unique-barrier' {
    $root = New-Case 'no-change'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        Assert-True (Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor) 'Monitor did not arm.'
        $result = Complete-RimePimeNsisMembershipMonitorV1 $monitor
        Assert-True ($result.completed_cleanly -and $result.unique_completion_barrier_observed -and
            $result.unexpected_membership_event_count -eq 0 -and $result.barrier_name_sha256 -cmatch '^[0-9a-f]{64}$' -and
            -not $result.physical_membership_prevention_claimed -and -not $result.makensis_interval_covered -and
            -not $result.active_same_sid_transient_tree_membership_interference_excluded -and
            -not $result.nsis_non_os_compiler_input_closure -and -not $result.full_nsis_toolchain_input_closure) `
            'Clean result overclaimed or omitted its barrier.'
        Assert-True (@(Get-ChildItem -LiteralPath $root -Force -Recurse -File).Count -eq 0) `
            'Completion barrier remained after the monitor settled.'
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*not armed*'
        Close-RimePimeNsisMembershipMonitorV1 $monitor
        Close-RimePimeNsisMembershipMonitorV1 $monitor
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'same-process-transient-file-invalidates-interval' {
    $root = New-Case 'same-process-file'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        Touch-Then-Delete (Join-Path $root 'TRANSIENT.TMP')
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*Unexpected directory membership activity*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'nested-subtree-transient-file-invalidates-interval' {
    $root = New-Case 'nested-subtree'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        Touch-Then-Delete (Join-Path $root 'nested\TRANSIENT.TMP')
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*Unexpected directory membership activity*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'independent-same-sid-process-transient-file-invalidates-interval' {
    $root = New-Case 'same-sid-child'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        Invoke-ChildWriter $root
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*Unexpected directory membership activity*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'transient-directory-invalidates-interval' {
    $root = New-Case 'directory'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        $foreign = Join-Path $root 'FOREIGNDIR'; [IO.Directory]::CreateDirectory($foreign) | Out-Null; [IO.Directory]::Delete($foreign)
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*Unexpected directory membership activity*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'rename-away-and-back-invalidates-interval' {
    $root = New-Case 'rename'; $original = Join-Path $root 'ORIGINAL.TMP'; [IO.File]::WriteAllText($original, 'fixture')
    $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        $renamed = Join-Path $root 'RENAMED.TMP'; [IO.File]::Move($original, $renamed); [IO.File]::Move($renamed, $original)
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*Unexpected directory membership activity*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'root-rename-and-replacement-prerequisite-are-blocked-while-armed' {
    $root = New-Case 'root-identity'
    [IO.Directory]::Delete((Join-Path $root 'nested'))
    $moved = $root + '-moved'
    $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        $renameBlocked = $false
        try { [IO.Directory]::Move($root, $moved) } catch { $renameBlocked = $true }
        $deleteBlocked = $false
        try { [IO.Directory]::Delete($root) } catch { $deleteBlocked = $true }
        Assert-True ($renameBlocked -and $deleteBlocked -and (Test-Path -LiteralPath $root -PathType Container)) `
            'The armed root could be renamed or removed before replacement.'
        $result = Complete-RimePimeNsisMembershipMonitorV1 $monitor
        Assert-True ($result.completed_cleanly -and $result.unexpected_membership_event_count -eq 0) `
            'Blocked root replacement invalidated an otherwise clean interval.'
    }
    finally {
        Close-RimePimeNsisMembershipMonitorV1 $monitor
        if ((Test-Path -LiteralPath $moved) -and -not (Test-Path -LiteralPath $root)) {
            [IO.Directory]::Move($moved, $root)
        }
    }
}
Check 'overlapping-notification-record-is-rejected-by-parser' {
    Assert-Rejected {
        & $module { Invoke-RimePimeNsisMembershipParserOverlapForTestV1 }
    } '*record offset*'
}
Check 'notification-overflow-or-zero-byte-completion-fails-closed' {
    $root = New-Case 'overflow'
    $monitor = & $module { param($fixtureRoot) Open-RimePimeNsisMembershipMonitorCoreV1 -Root $fixtureRoot -BufferBytes 128 } $root
    try {
        $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $monitor
        $longName = ('X' * 100) + '.TMP'; Touch-Then-Delete (Join-Path $root $longName)
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*overflow or zero-byte*'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'unexpected-overlapped-cancellation-fails-closed' {
    $root = New-Case 'cancel'
    $monitor = & $module { param($fixtureRoot) Open-RimePimeNsisMembershipMonitorCoreV1 -Root $fixtureRoot } $root
    try {
        & $module { param($handle) Invoke-RimePimeNsisMembershipMonitorCancellationForTestV1 $handle } $monitor
        Assert-Rejected { Complete-RimePimeNsisMembershipMonitorV1 $monitor } '*unexpectedly cancelled*'
        Assert-True ($monitor.Native.IsDisposed -and $monitor.Closed) `
            'Cancelled completion did not settle resources before reporting failure.'
    }
    finally { Close-RimePimeNsisMembershipMonitorV1 $monitor }
}
Check 'close-without-completion-releases-directory' {
    $root = New-Case 'release'; $monitor = Open-RimePimeNsisMembershipMonitorV1 $root
    Close-RimePimeNsisMembershipMonitorV1 $monitor
    Assert-True ($monitor.Native.IsDisposed -and $monitor.Closed) 'Close returned before native notification resources settled.'
    Touch-Then-Delete (Join-Path $root 'AFTER.TMP')
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'AFTER.TMP'))) 'Closed monitor retained a filesystem restriction.'
    $moved = $root + '-moved'; [IO.Directory]::Move($root, $moved); [IO.Directory]::Move($moved, $root)
}
Check 'outside-fixture-root-is-rejected' {
    Assert-Rejected { Open-RimePimeNsisMembershipMonitorV1 $repo } '*non-fixture root*'
}
Check 'static-boundary-has-no-product-or-compiler-execution-surface' {
    $source = [IO.File]::ReadAllText($helperPath) + "`n" + [IO.File]::ReadAllText($modulePath) +
        "`n" + [IO.File]::ReadAllText($workerPath)
    foreach ($forbidden in @(
        '(?i)Start-Process|Invoke-Expression|Invoke-Command',
        '(?i)Registry::|HKEY_|HKLM|HKCU|StdRegProv|reg\.exe',
        '(?i)Program Files|APPDATA|LOCALAPPDATA',
        '(?i)makensis\.exe|msiexec\.exe|PIMELauncher|server\.exe',
        '(?i)Remove-Item[^\r\n]*-Recurse',
        '(?i)FileSystemWatcher'
    )) { Assert-True ($source -notmatch $forbidden) 'Static safety boundary drifted.' }
    Assert-True ($source.Contains('ReadDirectoryChangesW') -and $source.Contains('FILE_FLAG_OVERLAPPED') -and
        $source.Contains('SettlePendingCancellation') -and $source.Contains('GetOverlappedResult') -and
        $source.Contains('byte[] random = new byte[16]') -and
        $source.Contains('GetFileInformationByHandle') -and $source.Contains('FILE_FLAG_OPEN_REPARSE_POINT') -and
        $source.Contains('System.Diagnostics.Stopwatch') -and $source.Contains('next < alignedRecordBytes') -and
        -not $source.Contains('FILE_SHARE_DELETE')) `
        'Native overlapped lifecycle, root identity, parser, or 128-bit barrier drifted.'
    foreach ($literal in @(
        'physical_membership_prevention_claimed = $false',
        'makensis_interval_covered = $false',
        'active_same_sid_transient_tree_membership_interference_excluded = $false',
        'nsis_non_os_compiler_input_closure = $false',
        'full_nsis_toolchain_input_closure = $false'
    )) { Assert-True ($source.Contains($literal)) 'An honest non-claim is missing.' }
}

$failed = @($checks | Where-Object { -not $_.passed })
function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
$result = [pscustomobject][ordered]@{
    schema_version = 'yime-rime-pime-nsis-membership-monitor-test-result-v1'
    fixture_only = $true
    passed = $failed.Count -eq 0
    check_count = $checks.Count
    passed_count = @($checks | Where-Object { $_.passed }).Count
    failed_count = $failed.Count
    checks = @($checks)
    helper_sha256 = Hash-File $helperPath
    module_sha256 = Hash-File $modulePath
    worker_sha256 = Hash-File $workerPath
    test_sha256 = Hash-File $MyInvocation.MyCommand.Path
    read_directory_changes_w_overlapped = $true
    unique_completion_barrier = $true
    actual_makensis_executed = $false
    actual_installer_or_uninstaller_executed = $false
    product_process_touched = $false
    registry_touched = $false
    user_text_read_or_written = $false
    physical_membership_prevention_claimed = $false
    makensis_interval_covered = $false
    active_same_sid_transient_tree_membership_interference_excluded = $false
    nsis_non_os_compiler_input_closure = $false
    full_nsis_toolchain_input_closure = $false
}
$json = ($result | ConvertTo-Json -Depth 8 -Compress) + "`n"
$resultPath = Join-Path $output 'result.json'
[IO.File]::WriteAllText($resultPath, $json, [Text.UTF8Encoding]::new($false))
$digest = Hash-File $resultPath
[IO.File]::WriteAllText($resultPath + '.sha256', $digest + "`n", [Text.UTF8Encoding]::new($false))
if ($failed.Count) {
    $failed | Format-Table -AutoSize | Out-String | Write-Host
    throw "$($failed.Count) of $($checks.Count) DP1-J membership monitor checks failed."
}
Write-Host "PASS: $($checks.Count) fixture-only membership monitor checks passed. Evidence: $resultPath ($digest)"
