[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$SevenZipRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$parent = Join-Path $repo '.tmp\dual-product'
if ($OutputRoot -cnotmatch '^[A-Za-z]:\\' -or $OutputRoot.Contains('/') -or
    $OutputRoot -cne [IO.Path]::GetFullPath($OutputRoot) -or
    (Split-Path -Parent $OutputRoot) -cne $parent -or
    (Split-Path -Leaf $OutputRoot) -cnotmatch '^dp1-nsis-distribution-[A-Za-z0-9][A-Za-z0-9-]*$') {
    throw 'OutputRoot must be a canonical fresh repository .tmp\dual-product\dp1-nsis-distribution-* directory.'
}
if (Test-Path -LiteralPath $OutputRoot) { throw 'NSIS preparation output already exists.' }

# Reuse an already loaded module: its native helper initialization is part of
# the existing trust boundary and must not be reset by Import-Module -Force.
$module = Import-Module (Join-Path $repo 'tools\dual-product\rime-pime-nsis-toolchain-closure.psm1') -PassThru
& $module {
    param($archivePath, $outputRoot, $parent, $sevenZipRoot)
    $archiveRecord = [pscustomobject]@{
        bytes = [long]1566914
        sha256 = '3bc2b06253a7e4957111be152ac6a536e0c7478a706e19da814038db5d706495'
    }
    $files = [Collections.Generic.List[object]]::new()
    $directories = [Collections.Generic.List[object]]::new()
    $directoryPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $closure = $null
    function Add-PreparationDirectoryPins([string]$Path) {
        $chain = [Collections.Generic.List[string]]::new()
        $cursor = $Path
        while ($cursor.Length -gt 3) { $chain.Add($cursor); $cursor = Split-Path -Parent $cursor }
        for ($i = $chain.Count - 1; $i -ge 0; $i--) {
            $path = $chain[$i]
            if ($directoryPaths.Add($path)) {
                $directories.Add((Open-RimePimeNsisClosureDirectoryLease $path 'NSIS preparation ancestor'))
            }
        }
    }
    function Write-PreparationLog([string]$Path, [string]$Text) {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    }
    try {
        $null = Assert-YimePimePayloadAbsolutePath $outputRoot
        Assert-RimePimeNoReparsePath $outputRoot
        if (Test-Path -LiteralPath $outputRoot) { throw 'NSIS preparation output already exists.' }
        $archiveFull = Assert-YimePimePayloadAbsolutePath $archivePath
        Add-PreparationDirectoryPins (Split-Path -Parent $archiveFull)
        # No output is created until the official archive has passed its pin.
        $archiveLease = Open-RimePimeNsisClosureFileLease $archiveFull $archiveRecord 'Official NSIS setup archive'
        $files.Add($archiveLease)
        $lock = Read-RimePimeNsisCompilerToolchainLockDocument
        $controls = [Collections.Generic.List[object]]::new()
        foreach ($controlPath in @($lock.Path, $lock.Sidecar)) {
            Add-PreparationDirectoryPins (Split-Path -Parent $controlPath)
            $lease = Open-RimePimeNsisClosureFileLease $controlPath (Get-YimePimePayloadFileRecord $controlPath) 'NSIS preparation toolchain control'
            $files.Add($lease); $controls.Add($lease)
        }
        $heldLock = Read-RimePimeNsisCompilerToolchainLockDocument
        if ($heldLock.Digest -cne $lock.Digest) { throw 'NSIS preparation toolchain lock changed.' }
        # CI supplies an isolated, bootstrapped copy. The executable and parser
        # library must still match the original repository pins, never the host
        # version or a caller-provided digest. Local callers keep the old default.
        if ([string]::IsNullOrEmpty($sevenZipRoot)) {
            $sevenZipRoot = Split-Path -Parent (([string]$lock.Document.seven_zip.path).Replace('/', '\'))
        } else {
            $null = Assert-YimePimePayloadAbsolutePath $sevenZipRoot
            $toolStage = Split-Path -Parent $sevenZipRoot
            if ($sevenZipRoot -cne [IO.Path]::GetFullPath($sevenZipRoot) -or
                (Split-Path -Leaf $sevenZipRoot) -cne '7-Zip' -or
                (Split-Path -Parent $toolStage) -cne $parent -or
                (Split-Path -Leaf $toolStage) -cnotmatch '^dp1-sevenzip-distribution-[A-Za-z0-9][A-Za-z0-9-]*$') {
                throw 'SevenZipRoot must be an isolated repository 7-Zip preparation root.'
            }
        }
        $sevenZipExe = Join-Path $sevenZipRoot '7z.exe'
        foreach ($record in @($lock.Document.seven_zip, $lock.Document.seven_zip.library)) {
            $path = Join-Path $sevenZipRoot ([IO.Path]::GetFileName([string]$record.path))
            Add-PreparationDirectoryPins (Split-Path -Parent $path)
            $files.Add((Open-RimePimeNsisClosureFileLease $path $record 'NSIS preparation 7-Zip input'))
        }
        # Only these two fixed repository parents may be created if absent.
        foreach ($path in @((Split-Path -Parent $parent), $parent)) {
            Assert-RimePimeNoReparsePath $path
            if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path }
            Add-PreparationDirectoryPins $path
        }
        $null = New-Item -ItemType Directory -Path $outputRoot
        Add-PreparationDirectoryPins $outputRoot
        $nsisRoot = Join-Path $outputRoot 'NSIS'
        $null = New-Item -ItemType Directory -Path $nsisRoot
        Add-PreparationDirectoryPins $nsisRoot
        $roots = @($lock.Document.nsis.compiler_input_closure.roots | ForEach-Object { [string]$_.path })
        if (($roots -join '|') -cne 'Bin|Contrib|Include|Plugins/x86-unicode|Stubs') { throw 'Unexpected NSIS extraction scope.' }
        # The pinned setup is opened as archive data by pinned 7-Zip. Nothing
        # inside these five trees is filtered, patched, executed, or installed.
        $arguments = @('x', '-y', '-bd', '-bsp0', '-r', ('"-o' + $nsisRoot + '"'), '--', ('"' + $archiveFull + '"'))
        $arguments += @($roots | ForEach-Object { '"' + $_.Replace('/', '\') + '\*"' })
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName = $sevenZipExe
        $process.StartInfo.Arguments = $arguments -join ' '
        $process.StartInfo.WorkingDirectory = $outputRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $started = $false; $stdout = $null; $stderr = $null
        try {
            if (-not $process.Start()) { throw '7-Zip archive extraction did not start.' }
            $started = $true
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(60000)) { throw '7-Zip archive extraction exceeded 60 seconds.' }
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw '7-Zip output did not close.' }
            Write-PreparationLog (Join-Path $outputRoot '7zip.stdout.txt') $stdout.GetAwaiter().GetResult()
            Write-PreparationLog (Join-Path $outputRoot '7zip.stderr.txt') $stderr.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) { throw "7-Zip archive extraction failed with exit code $($process.ExitCode)." }
        } finally {
            try {
                if ($started -and -not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
            } finally {
                # Closing our redirected streams cancels any remaining reads;
                # retain no asynchronous reader after leaving this operation.
                if ($started) { $process.StandardOutput.Dispose(); $process.StandardError.Dispose() }
                foreach ($task in @($stdout, $stderr)) { if ($null -ne $task) { try { $null = $task.GetAwaiter().GetResult() } catch { } } }
                $process.Dispose()
            }
        }
        foreach ($lease in $files) { $null = Assert-RimePimeNsisClosureFileLease $lease }
        foreach ($lease in $directories) { $null = Assert-RimePimeNsisClosureDirectoryLease $lease }
        # The official setup spells exactly these three names differently from
        # the existing repository lock. Preserve their bytes and canonicalize
        # only the reviewed names; the original full tree check follows.
        $caseMappings = [Collections.Generic.List[object]]::new()
        $pluginRoot = Join-Path $nsisRoot 'Plugins\x86-unicode'
        Add-PreparationDirectoryPins $pluginRoot
        foreach ($pair in @(@('AdvSplash.dll', 'advsplash.dll'), @('NSISdl.dll', 'nsisdl.dll'), @('Splash.dll', 'splash.dll'))) {
            $source = Join-Path $pluginRoot $pair[0]
            $destination = Join-Path $pluginRoot $pair[1]
            $item = Get-Item -LiteralPath $source -Force
            if ($item.Name -cne $pair[0]) { throw 'Official NSIS plugin name differs from the reviewed case mapping.' }
            $before = Get-YimePimePayloadFileRecord $source
            $temporary = Join-Path $pluginRoot ('case-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Move($source, $temporary)
            [IO.File]::Move($temporary, $destination)
            $after = Get-YimePimePayloadFileRecord $destination
            if ((Get-Item -LiteralPath $destination -Force).Name -cne $pair[1] -or
                $before.bytes -ne $after.bytes -or $before.sha256 -cne $after.sha256 -or $before.file_id -cne $after.file_id) {
                throw 'NSIS plugin case mapping changed file identity or content.'
            }
            $caseMappings.Add([pscustomobject][ordered]@{
                from = 'Plugins/x86-unicode/' + $pair[0]; to = 'Plugins/x86-unicode/' + $pair[1]
                bytes = $after.bytes; sha256 = $after.sha256; content_and_identity_preserved = $true
            })
        }
        $closure = Open-RimePimeNsisCompilerInputClosureCore $nsisRoot $lock.Document.nsis.compiler_input_closure
        $closure.ControlLeases = @($controls)
        $closure.ToolchainLockPath = $lock.Path
        $closure.ToolchainLockDigest = $lock.Digest
        $evidence = Test-RimePimeNsisCompilerInputClosure $closure
        $evidence | Add-Member -NotePropertyMembers ([ordered]@{
            official_archive_sha256 = $archiveLease.Record.sha256
            official_archive_bytes = $archiveLease.Record.bytes
            seven_zip_exe_sha256 = [string]$lock.Document.seven_zip.sha256
            seven_zip_library_sha256 = [string]$lock.Document.seven_zip.library.sha256
            seven_zip_root = $sevenZipRoot
            extraction_scope = $roots
            canonical_case_mappings = @($caseMappings)
            extraction_input_read_leases_held = $true
            verification_scope = 'held-during-staged-verification-only'
            leases_released_before_return = $true
            installer_executed = $false
            compiler_executed = $false
            installed_nsis_modified = $false
            execution_authorized = $false
            full_acceptance = $false
        })
        return [pscustomobject][ordered]@{ Root = $nsisRoot; Evidence = $evidence }
    } finally {
        try { if ($null -ne $closure) { Close-RimePimeNsisCompilerInputClosure $closure } }
        finally {
            foreach ($lease in $files) { $lease.Stream.Dispose() }
            for ($i = $directories.Count - 1; $i -ge 0; $i--) { $directories[$i].Native.Dispose() }
        }
    }
} $ArchivePath $OutputRoot $parent $SevenZipRoot
