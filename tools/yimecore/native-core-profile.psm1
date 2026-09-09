#Requires -Version 5.1
# YimeCore-only CPU diagnostics. No benchmark verdict or installation action.
Set-StrictMode -Version Latest
$script:NPModulePath = $PSCommandPath
$script:NPModuleHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$script:NPHelperHash = '13593d3c36ccb81b90966af37b0d9546f1b1c44777577a5e67930dbc4b0acd45'
$script:NPLearningMainHash = '2a632cd3ff235a8672c53ab189604b5c303b791ee7886e7743b209c19ca39825'

$script:NPDriverSource = @'
package main

import (
    "context"
    "flag"
    "fmt"
    "os"
    "path/filepath"
    "runtime/pprof"
    "time"

    "github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

var nativeCPUReplays = flag.Int("cpu-replays", 1000000, "diagnostic replays per engine")

func collectNativeCPU(staticEngine, learnedEngine *yimecore.Engine, code, mode, output string) error {
    if *nativeCPUReplays < 1 || *nativeCPUReplays > 4000000 {
        return fmt.Errorf("invalid diagnostic replay count")
    }
    if _, err := os.Stat(output); !os.IsNotExist(err) {
        return fmt.Errorf("diagnostic report must be new: %s", output)
    }
    const warmup = 2000
    for i := 0; i < warmup; i++ {
        applyCode(staticEngine, code)
        applyCode(learnedEngine, code)
    }
    profilePath := filepath.Join(filepath.Dir(output), "cpu.pprof")
    f, err := os.OpenFile(profilePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
    if err != nil { return err }
    defer f.Close()
    base := context.Background()
    staticLabels := pprof.Labels("engine", "static")
    learnedLabels := pprof.Labels("engine", "learned")
    if err := pprof.StartCPUProfile(f); err != nil { return err }
    stopped := false
    defer func() { if !stopped { pprof.StopCPUProfile() } }()
    started := time.Now()
    replay := func(engine *yimecore.Engine, labels pprof.LabelSet, count int) {
        pprof.Do(base, labels, func(context.Context) {
            for i := 0; i < count; i++ { applyCode(engine, code) }
        })
    }
    chunks := 0
    for completed := 0; completed < *nativeCPUReplays; chunks++ {
        count := 50
        if remaining := *nativeCPUReplays-completed; remaining < count { count = remaining }
        if chunks%2 == 0 {
            replay(staticEngine, staticLabels, count)
            replay(learnedEngine, learnedLabels, count)
        } else {
            replay(learnedEngine, learnedLabels, count)
            replay(staticEngine, staticLabels, count)
        }
        completed += count
    }
    elapsed := time.Since(started)
    pprof.StopCPUProfile()
    stopped = true
    if err := f.Close(); err != nil { return err }
    writeJSON(output, map[string]interface{}{
        "schema_version": "yimecore-native-cpu-profile-v1",
        "diagnostic_only": true, "eligible_for_acceptance": false,
        "profile_complete": true, "functional_setup_passed": true,
        "mode": mode, "code": code, "profile_file": "cpu.pprof",
        "replays_per_engine": *nativeCPUReplays,
        "static_replays": *nativeCPUReplays, "learned_replays": *nativeCPUReplays,
        "warmup_per_engine": warmup, "chunk_size": 50, "chunks_per_engine": chunks,
        "measurement_order": "interleaved_alternating_static_learned",
        "profile_sha256": hashFile(profilePath),
        "elapsed_with_profiling_ns": elapsed.Nanoseconds(),
    })
    fmt.Printf("CPU diagnostic collected: mode=%s replays_per_engine=%d\n", mode, *nativeCPUReplays)
    return nil
}
'@

function Get-NPCanonicalText([string]$Text) {
    $lf = [string][char]10
    $Text.Replace(([string][char]13 + $lf), $lf).TrimEnd([char]10) + $lf
}
function Get-NPTextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Get-NPCanonicalText $Text))))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function New-NPInstrumentedMain([string]$Original) {
    if ((Get-NPTextHash $Original) -cne $script:NPLearningMainHash) {
        throw 'Unsupported E3 source version; preserve this snapshot and review the diagnostic adapter'
    }
    $source = Get-NPCanonicalText $Original
    $start = $source.IndexOf('staticLatency, learnedLatency := measurePair(', [StringComparison]::Ordinal)
    $end = $source.IndexOf('func applyCode(', [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) { throw 'Missing verified E3 adapter boundaries' }
    $replacement = @'
if !promotionPassed || !persistencePassed || !contextPassed || !forgetPassed {
        fail(fmt.Errorf("E3 functional preparation failed; no CPU profile accepted"))
    }
    if err := collectNativeCPU(staticEngine, learnedEngine, code, *mode, *output); err != nil {
        fail(err)
    }
}

'@
    $source.Substring(0, $start) + $replacement + ([string][char]10) + $source.Substring($end)
}
function Assert-NPBootstrapPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\' -or
        [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Diagnostic inputs must use an absolute path on a local fixed drive'
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Diagnostic paths must not traverse reparse points' }
            if ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $cursor '.git'))) {
                throw 'Diagnostic inputs and outputs must be outside Git working trees'
            }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor.TrimEnd('\', '/'))
    }
    return $full
}
function Import-NPGuard([string]$PackageRoot, [string]$ManifestSHA256) {
    $package = Assert-NPBootstrapPath $PackageRoot
    $manifestPath = Assert-NPBootstrapPath (Join-Path $package 'package-manifest.json')
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ManifestSHA256) {
        throw 'Package manifest changed before helper import'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $record = @($manifest.files | Where-Object path -CEQ 'native-core-benchmark.psm1')
    $helperPath = Assert-NPBootstrapPath (Join-Path $package 'native-core-benchmark.psm1')
    if ($record.Count -ne 1 -or
        (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record[0].sha256 -or
        (Get-NPTextHash (Get-Content -LiteralPath $helperPath -Raw -Encoding UTF8)) -cne $script:NPHelperHash) {
        throw 'Unrecognized or changed benchmark helper; it was not imported'
    }
    Import-Module $helperPath -PassThru -Scope Local -ErrorAction Stop
}
function ConvertTo-NPArgument([AllowEmptyString()][string]$Value) {
    if ($Value.Contains([string][char]0)) { throw 'NUL is not a valid process argument' }
    $text = [Text.StringBuilder]::new()
    $null = $text.Append('"'); $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') { $null = $text.Append(('\' * (2 * $slashes + 1))) }
        else { $null = $text.Append(('\' * $slashes)) }
        $null = $text.Append($character); $slashes = 0
    }
    $null = $text.Append(('\' * (2 * $slashes))); $null = $text.Append('"')
    return $text.ToString()
}
function Invoke-NPProcess([string]$File, [string[]]$Arguments, [string]$WorkingDirectory, [string]$Log) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $File
    $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NPArgument $_ }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    $started = $false
    try {
        if (-not $process.Start()) { throw 'Could not start diagnostic child process' }
        $started = $true
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($Log, ($stdout + [Environment]::NewLine + $stderr), [Text.UTF8Encoding]::new($false))
        if ($process.ExitCode -ne 0) {
            throw "Diagnostic child exited $($process.ExitCode); preserve log $Log. $stderr"
        }
        [pscustomobject]@{ stdout = $stdout; stderr = $stderr }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Assert-NPReport($Report, [string]$Mode, [int]$Replays) {
    $expectedCode = if ($Mode -ceq 'full') { 'bjjj' } else { 'bj' }
    foreach ($name in @('diagnostic_only', 'profile_complete', 'functional_setup_passed')) {
        if ($Report.$name -isnot [bool] -or -not $Report.$name) { throw 'Incomplete CPU diagnostic evidence' }
    }
    if ($Report.eligible_for_acceptance -isnot [bool] -or $Report.eligible_for_acceptance -or
        $Report.schema_version -cne 'yimecore-native-cpu-profile-v1' -or $Report.mode -cne $Mode -or $Report.code -cne $expectedCode -or
        $Report.replays_per_engine -ne $Replays -or $Report.static_replays -ne $Replays -or $Report.learned_replays -ne $Replays -or
        $Report.warmup_per_engine -ne 2000 -or $Report.chunk_size -ne 50 -or
        $Report.chunks_per_engine -ne [math]::Ceiling($Replays / 50.0) -or
        $Report.measurement_order -cne 'interleaved_alternating_static_learned' -or
        $Report.profile_file -cne 'cpu.pprof' -or $Report.profile_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Report.elapsed_with_profiling_ns -le 0) {
        throw 'Mismatched CPU diagnostic evidence'
    }
}
function Get-NPSafeTopRows([string]$Text) {
    # Only numeric function rows are copied to the concise, user-shareable report.
    # Local filenames, profile headers, timestamps and stderr stay in local logs.
    @($Text -split '\r?\n' | Where-Object {
        $_ -match '^\s*(?:[0-9.]+ms|0)\s+[0-9.]+%\s+[0-9.]+%\s+(?:[0-9.]+ms|0)\s+[0-9.]+%\s+[\w.*()/<>-]+' -and
        $_ -notmatch '[A-Za-z]:[\\/]|\\\\'
    })
}
function Invoke-YimeCoreNativeLearningProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSHA256,
        [string]$BenchmarkRoot = 'C:\YimeBench',
        [ValidateRange(250000, 4000000)][int]$Replays = 1000000
    )
    $ErrorActionPreference = 'Stop'
    if ((Get-FileHash -LiteralPath $script:NPModulePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $script:NPModuleHash) {
        throw 'Diagnostic module changed since import'
    }
    $guard = Import-NPGuard $PackageRoot $ManifestSHA256
    $package = & $guard { param($p) Assert-NBLocalRoot $p } $PackageRoot
    $root = & $guard { param($p) Assert-NBLocalRoot $p } $BenchmarkRoot
    if ($root -ieq $package -or $root.StartsWith(($package.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Diagnostic output must not be inside the immutable package'
    }
    $manifest = & $guard { param($p,$h) Assert-NBPackage $p $h } $package $ManifestSHA256
    $hostFacts = & $guard { Get-NBHost 'baseline' }
    $preparation = & $guard { param($r,$id) Resolve-NBChild $r ("preparations/" + $id) } $root $manifest.package_id
    if ([IO.Path]::GetFullPath($manifest.preparation_evidence) -cne $preparation) { throw 'Use the original preparation root beside this benchmark package' }
    $snapshot = & $guard { param($p) Resolve-NBChild $p 'source' } $preparation
    $state = Get-Content -LiteralPath (Join-Path $package 'source-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.git_commit -cne $manifest.git_commit -or $state.git_dirty -ne $manifest.git_dirty) { throw 'Source provenance mismatch' }
    $checkSnapshot = { param($p,$s) Assert-NBRecords $p $s.files; Assert-NBNames @($s.files.path | Sort-Object) @(Get-NBFileNames $p) }
    & $guard $checkSnapshot $snapshot $state
    $go = (Get-Command go -CommandType Application -ErrorAction Stop).Source
    $lock = [IO.File]::Open((Join-Path $root 'native-benchmark.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $run = $null; $old = $null; $before = $null; $failure = $null
    $allRecords = $null; $driverRecords = @(); $copy = $null; $exeHash = $null
    $packageOK = $false; $sourceOK = $false; $protected = $false
    $modeRows = [Collections.Generic.List[object]]::new()
    try {
        $id = 'learning-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $run = & $guard { param($r,$i) Resolve-NBChild $r ("profiles/" + $i) } $root $id
        if (Test-Path -LiteralPath $run) { throw 'Preserve existing diagnostic outputs' }
        $null = New-Item -ItemType Directory -Path $run
        $provider = Join-Path $package 'support/native-maintenance-evidence.psm1'
        $before = & $guard { param($p) Get-NBRegistration $p } $provider
        & $guard { param($v,$p) Write-NBJson $v $p } $before (Join-Path $run 'registration-before.json')
        & $guard { param($v,$p) Write-NBJson $v $p } $hostFacts (Join-Path $run 'host.json')
        $copy = Join-Path $run 'source'
        $null = New-Item -ItemType Directory -Path $copy
        Write-Host 'Verifying and copying the existing local source snapshot for CPU diagnostics.'
        foreach ($record in $state.files) {
            $from = & $guard { param($r,$p) Resolve-NBChild $r $p } $snapshot $record.path
            $to = & $guard { param($r,$p) Resolve-NBChild $r $p } $copy $record.path
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to)
            Copy-Item -LiteralPath $from -Destination $to
        }
        & $guard $checkSnapshot $snapshot $state
        & $guard $checkSnapshot $copy $state
        $originalMain = Get-Content -LiteralPath (Join-Path $copy 'go-backend/cmd/yimecore-learning-experiment/main.go') -Raw -Encoding UTF8
        $driverRoot = Join-Path $copy 'go-backend/cmd/yimecore-native-profile'
        if (Test-Path -LiteralPath $driverRoot) { throw 'Diagnostic command already exists in this source snapshot' }
        $null = New-Item -ItemType Directory -Path $driverRoot
        [IO.File]::WriteAllText((Join-Path $driverRoot 'main.go'), (New-NPInstrumentedMain $originalMain), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $driverRoot 'native_cpu.go'), $script:NPDriverSource, [Text.UTF8Encoding]::new($false))
        $driverRecords = @(& $guard {
            param($c)
            Get-NBFileRecord $c 'go-backend/cmd/yimecore-native-profile/main.go'
            Get-NBFileRecord $c 'go-backend/cmd/yimecore-native-profile/native_cpu.go'
        } $copy)
        $allRecords = @($state.files) + $driverRecords
        $old = & $guard { param($r) Set-NBBuildEnvironment $r } $run
        foreach ($name in @('PPROF_TMPDIR','PPROF_BINARY_PATH')) {
            $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $binRoot = Join-Path $run 'bin'; $pprofTemp = Join-Path $run 'pprof-temp'
        $null = New-Item -ItemType Directory -Path $binRoot, $pprofTemp
        [Environment]::SetEnvironmentVariable('PPROF_TMPDIR', $pprofTemp, 'Process')
        [Environment]::SetEnvironmentVariable('PPROF_BINARY_PATH', $binRoot, 'Process')
        $working = Join-Path $copy 'go-backend'
        $version = Invoke-NPProcess $go @('version') $working (Join-Path $run 'go-version.log')
        if ($version.stdout.Trim() -cne $manifest.go_version) { throw 'Use the same Go version that built the benchmark package' }
        $native = Invoke-NPProcess $go @('env','GOHOSTOS','GOHOSTARCH') $working (Join-Path $run 'go-host.log')
        if ((($native.stdout.Trim() -split '\r?\n') -join '|') -cne 'windows|amd64') { throw 'Native windows/amd64 Go required' }
        $moduleInfo = Invoke-NPProcess $go @('mod','edit','-json') $working (Join-Path $run 'go-module.log')
        $moduleData = $moduleInfo.stdout | ConvertFrom-Json
        $external = @($moduleData.PSObject.Properties | Where-Object {
            $_.Name -in @('Require','Replace') -and $null -ne $_.Value -and @($_.Value).Count -gt 0
        })
        if ($moduleData.Module.Path -cne 'github.com/tsaanghwang/Yime/go-backend' -or $external.Count -ne 0) { throw 'Unexpected Go module dependency boundary' }
        $exe = Join-Path $binRoot 'yimecore-native-profile.exe'
        Write-Host 'Building the diagnostic executable from the verified local snapshot.'
        $null = Invoke-NPProcess $go @('build','-trimpath','-buildvcs=false','-o',$exe,'./cmd/yimecore-native-profile') $working (Join-Path $run 'build.log')
        & $guard { param($p) Assert-NBPE $p } $exe
        $exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        foreach ($mode in @('full','variable','shorthand')) {
            $modeRoot = Join-Path $run $mode
            $null = New-Item -ItemType Directory -Path $modeRoot
            $reportPath = Join-Path $modeRoot 'diagnostic.json'
            Write-Host "Collecting CPU samples: $mode, static and learned paths."
            $arguments = @('-index',(Join-Path $package "indexes/$mode.yidx"),'-mode',$mode,
                '-model',(Join-Path $modeRoot 'synthetic-model.json'),'-output',$reportPath,'-cpu-replays',$Replays.ToString())
            $null = Invoke-NPProcess $exe $arguments $working (Join-Path $modeRoot 'capture.log')
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-NPReport $report $mode $Replays
            $cpuFile = Join-Path $modeRoot 'cpu.pprof'
            if ((Get-FileHash -LiteralPath $cpuFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $report.profile_sha256) { throw 'CPU profile changed' }
            $share = [Collections.Generic.List[string]]::new()
            $share.Add("CPU diagnostic only; source commit $($manifest.git_commit); mode $mode; replays per engine $Replays")
            $share.Add('Rows show sampled CPU time, not benchmark latency or acceptance.')
            foreach ($engine in @('static','learned','all')) {
                foreach ($order in @('flat','cum')) {
                    $pprofArguments = @('tool','pprof','-top','-nodecount=20','-unit=ms','-symbolize=local')
                    if ($engine -ne 'all') { $pprofArguments += "-tagfocus=engine=$engine" }
                    if ($order -eq 'cum') { $pprofArguments += '-cum' }
                    $pprofArguments += @($exe,$cpuFile)
                    $top = Invoke-NPProcess $go $pprofArguments $working (Join-Path $modeRoot "$engine-$order.log")
                    $safeRows = @(Get-NPSafeTopRows $top.stdout)
                    if ($safeRows.Count -eq 0 -or $top.stderr -match '(?i)matched no samples|no samples') { throw "Missing $engine CPU samples for $mode" }
                    $share.Add(""); $share.Add("$engine / $order")
                    $share.Add('flat flat% sum% cum cum% function')
                    foreach ($line in $safeRows) { $share.Add($line) }
                }
            }
            $sharePath = Join-Path $run "share-$mode.txt"
            [IO.File]::WriteAllLines($sharePath, $share.ToArray(), [Text.UTF8Encoding]::new($false))
            $modeRows.Add([pscustomobject]@{ mode = $mode; diagnostic_complete = $true; profile_sha256 = $report.profile_sha256;
                replays_per_engine = $Replays; share_report = $sharePath })
        }
        if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeHash -or
            (Get-FileHash -LiteralPath $script:NPModulePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $script:NPModuleHash) { throw 'Diagnostic code changed during collection' }
    } catch { $failure = $_.Exception.Message }
    finally {
        try { $null = & $guard { param($p,$h) Assert-NBPackage $p $h } $package $ManifestSHA256; $packageOK = $true }
        catch { $failure = "$failure; package verification: $($_.Exception.Message)" }
        try {
            & $guard $checkSnapshot $snapshot $state
            if ($null -ne $allRecords) {
                & $guard { param($p,$r) Assert-NBRecords $p $r; Assert-NBNames @($r.path | Sort-Object) @(Get-NBFileNames $p) } $copy $allRecords
            }
            $sourceOK = $true
        } catch { $failure = "$failure; source verification: $($_.Exception.Message)" }
        if ($null -ne $before) {
            try {
                $after = & $guard { param($p) Get-NBRegistration $p } $provider
                & $guard { param($v,$p) Write-NBJson $v $p } $after (Join-Path $run 'registration-after.json')
                $protected = $before.snapshot_sha256 -ceq $after.snapshot_sha256
            } catch { $failure = "$failure; registration verification: $($_.Exception.Message)" }
        }
        if ($null -ne $old) { & $guard { param($o) Restore-NBEnvironment $o } $old }
        $lock.Dispose()
        $complete = $modeRows.Count -eq 3 -and $packageOK -and $sourceOK -and $protected -and -not $failure
        if ($run) {
            $summary = [ordered]@{ schema_version = 'yimecore-native-cpu-diagnostic-run-v1'; diagnostic_only = $true;
                eligible_for_acceptance = $false; diagnostic_complete = $complete; failure = $failure;
                git_commit = $manifest.git_commit; package_manifest_sha256 = $ManifestSHA256; go_version = $manifest.go_version;
                diagnostic_tool_sha256 = $script:NPModuleHash; executable_sha256 = $exeHash; derived_entrypoint_files = $driverRecords;
                rows = @($modeRows.ToArray()); package_unchanged = $packageOK; source_unchanged = $sourceOK;
                protected_registration_unchanged = $protected; replays_per_engine = $Replays;
                notes = @('Profiles include instrumentation overhead; no p95/p99 gate is evaluated.',
                    'Tagged reports cover tagged execution. Untagged runtime work remains in all-engine reports.',
                    'Model preparation and warmup precede CPU capture. Synthetic files remain in this result directory.',
                    'No files are uploaded; no production installation, default-input or hardware setting is changed.') }
            & $guard { param($v,$p) Write-NBJson $v $p } $summary (Join-Path $run 'summary.json')
        }
    }
    if (-not $complete) { throw "CPU diagnostic incomplete; preserve evidence in $run. $failure" }
    Write-Host "CPU diagnostics complete: $run"
    [pscustomobject]@{ ResultDirectory = $run; ShareReport = (Join-Path $run 'share-variable.txt'); SummaryPath = (Join-Path $run 'summary.json') }
}
Export-ModuleMember -Function Invoke-YimeCoreNativeLearningProfile
