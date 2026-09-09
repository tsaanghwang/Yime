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
if ($OutputRoot -cnotmatch '^[A-Za-z]:\\' -or $OutputRoot.Contains('/') -or
    $OutputRoot -cne [IO.Path]::GetFullPath($OutputRoot) -or
    (Split-Path -Parent $OutputRoot) -cne $parent -or
    (Split-Path -Leaf $OutputRoot) -cnotmatch '^dp1-sevenzip-distribution-[A-Za-z0-9][A-Za-z0-9-]*$') {
    throw 'OutputRoot must be a canonical fresh repository .tmp\dual-product\dp1-sevenzip-distribution-* directory.'
}
if (Test-Path -LiteralPath $OutputRoot) { throw '7-Zip preparation output already exists.' }

# The official 26.02 bootstrap and setup are independently pinned to their
# release asset SHA256 values. Only the standalone bootstrap is executed;
# the setup remains archive data. No runner-installed archiver is consulted.
# Source: https://github.com/ip7z/7zip/releases/tag/26.02
$module = Import-Module (Join-Path $repo 'tools\dual-product\rime-pime-nsis-toolchain-closure.psm1') -PassThru
& $module {
    param($bootstrapPath, $archivePath, $outputRoot, $parent)
    $bootstrapRecord = [pscustomobject]@{
        bytes = [long]602112
        sha256 = '56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72'
    }
    $archiveRecord = [pscustomobject]@{
        bytes = [long]1657896
        sha256 = '6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0'
    }
    $files = [Collections.Generic.List[object]]::new()
    $directories = [Collections.Generic.List[object]]::new()
    $directoryPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-SevenZipPreparationDirectoryPins([string]$Path) {
        $chain = [Collections.Generic.List[string]]::new()
        $cursor = $Path
        while ($cursor.Length -gt 3) { $chain.Add($cursor); $cursor = Split-Path -Parent $cursor }
        for ($i = $chain.Count - 1; $i -ge 0; $i--) {
            $path = $chain[$i]
            if ($directoryPaths.Add($path)) {
                $directories.Add((Open-RimePimeNsisClosureDirectoryLease $path '7-Zip preparation ancestor'))
            }
        }
    }
    function Write-SevenZipPreparationLog([string]$Path, [string]$Text) {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    }
    try {
        $null = Assert-YimePimePayloadAbsolutePath $outputRoot
        Assert-RimePimeNoReparsePath $outputRoot
        if (Test-Path -LiteralPath $outputRoot) { throw '7-Zip preparation output already exists.' }
        $bootstrapFull = Assert-YimePimePayloadAbsolutePath $bootstrapPath
        $archiveFull = Assert-YimePimePayloadAbsolutePath $archivePath
        Add-SevenZipPreparationDirectoryPins (Split-Path -Parent $bootstrapFull)
        Add-SevenZipPreparationDirectoryPins (Split-Path -Parent $archiveFull)
        # Both pins must pass before creating output or starting any process.
        $bootstrapLease = Open-RimePimeNsisClosureFileLease $bootstrapFull $bootstrapRecord 'Official 7-Zip bootstrap'
        $files.Add($bootstrapLease)
        $archiveLease = Open-RimePimeNsisClosureFileLease $archiveFull $archiveRecord 'Official 7-Zip setup archive'
        $files.Add($archiveLease)
        $lock = Read-RimePimeNsisCompilerToolchainLockDocument
        foreach ($controlPath in @($lock.Path, $lock.Sidecar)) {
            Add-SevenZipPreparationDirectoryPins (Split-Path -Parent $controlPath)
            $files.Add((Open-RimePimeNsisClosureFileLease $controlPath (Get-YimePimePayloadFileRecord $controlPath) '7-Zip preparation toolchain control'))
        }
        $heldLock = Read-RimePimeNsisCompilerToolchainLockDocument
        if ($heldLock.Digest -cne $lock.Digest) { throw '7-Zip preparation toolchain lock changed.' }
        foreach ($path in @((Split-Path -Parent $parent), $parent)) {
            Assert-RimePimeNoReparsePath $path
            if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path }
            Add-SevenZipPreparationDirectoryPins $path
        }
        $null = New-Item -ItemType Directory -Path $outputRoot
        Add-SevenZipPreparationDirectoryPins $outputRoot
        $sevenZipRoot = Join-Path $outputRoot '7-Zip'
        $null = New-Item -ItemType Directory -Path $sevenZipRoot
        Add-SevenZipPreparationDirectoryPins $sevenZipRoot
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName = $bootstrapFull
        $process.StartInfo.Arguments = (@('x', '-y', '-bd', '-bsp0', '-r-', '-spd',
            ('"-o' + $sevenZipRoot + '"'), '--', ('"' + $archiveFull + '"'), '7z.exe', '7z.dll') -join ' ')
        $process.StartInfo.WorkingDirectory = $outputRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $started = $false; $stdout = $null; $stderr = $null
        try {
            if (-not $process.Start()) { throw '7-Zip bootstrap extraction did not start.' }
            $started = $true
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(60000)) { throw '7-Zip bootstrap extraction exceeded 60 seconds.' }
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw '7-Zip bootstrap output did not close.' }
            Write-SevenZipPreparationLog (Join-Path $outputRoot 'bootstrap.stdout.txt') $stdout.GetAwaiter().GetResult()
            Write-SevenZipPreparationLog (Join-Path $outputRoot 'bootstrap.stderr.txt') $stderr.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) { throw "7-Zip bootstrap extraction failed with exit code $($process.ExitCode)." }
        } finally {
            try {
                if ($started -and -not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
            } finally {
                if ($started) { $process.StandardOutput.Dispose(); $process.StandardError.Dispose() }
                foreach ($task in @($stdout, $stderr)) { if ($null -ne $task) { try { $null = $task.GetAwaiter().GetResult() } catch { } } }
                $process.Dispose()
            }
        }
        $items = @(Get-ChildItem -LiteralPath $sevenZipRoot -Force)
        if ($items.Count -ne 2 -or @($items | Where-Object { $_.PSIsContainer }).Count -ne 0 -or
            (@($items.Name | Sort-Object) -join '|') -cne '7z.dll|7z.exe') { throw 'Prepared 7-Zip inventory differs from the exact two-file scope.' }
        $exeLease = Open-RimePimeNsisClosureFileLease (Join-Path $sevenZipRoot '7z.exe') $lock.Document.seven_zip 'Prepared 7-Zip executable'
        $files.Add($exeLease)
        $libraryLease = Open-RimePimeNsisClosureFileLease (Join-Path $sevenZipRoot '7z.dll') $lock.Document.seven_zip.library 'Prepared 7-Zip parser library'
        $files.Add($libraryLease)
        foreach ($lease in $files) { $null = Assert-RimePimeNsisClosureFileLease $lease }
        foreach ($lease in $directories) { $null = Assert-RimePimeNsisClosureDirectoryLease $lease }
        return [pscustomobject][ordered]@{
            Root = $sevenZipRoot
            Evidence = [pscustomobject][ordered]@{
                schema_version = 'yime-pinned-sevenzip-preparation-v1'
                official_release = 'https://github.com/ip7z/7zip/releases/tag/26.02'
                bootstrap_sha256 = $bootstrapLease.Record.sha256
                bootstrap_bytes = $bootstrapLease.Record.bytes
                official_archive_sha256 = $archiveLease.Record.sha256
                official_archive_bytes = $archiveLease.Record.bytes
                toolchain_lock_sha256 = $lock.Digest
                seven_zip_exe_sha256 = $exeLease.Record.sha256
                seven_zip_exe_bytes = $exeLease.Record.bytes
                seven_zip_library_sha256 = $libraryLease.Record.sha256
                seven_zip_library_bytes = $libraryLease.Record.bytes
                extraction_scope = @('7z.exe', '7z.dll')
                extraction_input_read_leases_held = $true
                verification_scope = 'held-during-staged-verification-only'
                leases_released_before_return = $true
                bootstrap_executed = $true
                installer_executed = $false
                compiler_executed = $false
                installed_seven_zip_modified = $false
                runner_installed_archiver_used = $false
                active_same_sid_transient_tree_membership_interference_excluded = $false
                full_toolchain_input_closure = $false
                execution_authorized = $false
                full_acceptance = $false
            }
        }
    } finally {
        foreach ($lease in $files) { $lease.Stream.Dispose() }
        for ($i = $directories.Count - 1; $i -ge 0; $i--) { $directories[$i].Native.Dispose() }
    }
} $BootstrapPath $ArchivePath $OutputRoot $parent
