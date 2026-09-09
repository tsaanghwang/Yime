#Requires -Version 5.1
# YimeCore-only tooling for the user-identified i7-7820X physical test PC.
# This module does not install/register an input method or change hardware limits.
Set-StrictMode -Version Latest
$script:NBModulePath = $PSCommandPath
$script:NBModuleHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()

function Get-NBDigest([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Write-NBJson($Value, [string]$Path) {
    $text = ConvertTo-Json -InputObject $Value -Depth 90
    [IO.File]::WriteAllText($Path, $text + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
function Assert-NBPlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Benchmark paths must not traverse reparse points: $cursor"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor.TrimEnd('\', '/'))
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
function Resolve-NBChild([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '[:\x00-\x1f]' -or $Relative -match '(^|[\\/])(\.|\.\.|)([\\/]|$)' -or
        $Relative -match '[. ]([\\/]|$)') { throw "Invalid relative benchmark path: $Relative" }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes benchmark root' }
    Assert-NBPlainPath $path
    return $path
}
function Assert-NBLocalRoot([string]$Root) {
    $full = [IO.Path]::GetFullPath($Root)
    if ($full -notmatch '^[A-Za-z]:\\') { throw 'Use an absolute path on a local fixed drive' }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'Benchmark output must use a local fixed drive' }
    Assert-NBPlainPath $full
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor '.git')) { throw 'Benchmark output must be outside Git working trees' }
        $cursor = [IO.Path]::GetDirectoryName($cursor.TrimEnd('\', '/'))
    }
    return $full
}
function Get-NBFileRecord([string]$Root, [string]$Relative) {
    $path = Resolve-NBChild $Root $Relative
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer) { throw "Expected file: $Relative" }
    [pscustomobject][ordered]@{ path = $Relative.Replace('\', '/'); bytes = $item.Length; sha256 = (Get-NBDigest $path) }
}
function Get-NBFileNames([string]$Root) {
    Assert-NBPlainPath $Root
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($base)
    $names = [Collections.Generic.List[string]]::new()
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in benchmark tree: $($item.FullName)" }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $names.Add($item.FullName.Substring($base.Length + 1).Replace('\', '/')) }
        }
    }
    @($names.ToArray() | Sort-Object)
}
function Assert-NBRecords([string]$Root, $Records) {
    if (@($Records).Count -eq 0) { throw 'Empty file inventory' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $Records) {
        if (-not $seen.Add([string]$record.path) -or $record.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid file inventory' }
        $actual = Get-NBFileRecord $Root $record.path
        if ($actual.bytes -ne $record.bytes -or $actual.sha256 -cne $record.sha256) { throw "File changed: $($record.path)" }
    }
}
function Assert-NBNames($Before, $After) {
    if ((ConvertTo-Json -InputObject @($Before) -Compress) -cne (ConvertTo-Json -InputObject @($After) -Compress)) {
        throw 'Source or package file set changed'
    }
}
function Invoke-NBGit([string]$Root, [string[]]$Arguments) {
    $output = @(& git --no-optional-locks -c core.fsmonitor=false -c core.quotepath=false -C $Root @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Git read failed: $($Arguments -join ' ')" }
    @($output | ForEach-Object { $_.ToString() })
}
function Get-NBSourceNames([string]$Root) {
    $fixed = @('go-backend/go.mod', 'AGENTS.md', 'tools/yimecore/development-scope.json',
        'tools/yimecore/performance-tiers.json', 'tools/yimecore/native-maintenance-evidence.psm1')
    foreach ($mode in @('full', 'variable', 'shorthand')) { $fixed += "go-backend/input_methods/yime/data/yime_$mode.dict.yaml" }
    foreach ($probe in @('e1_probes.json', 'e2_sentence_probes.json')) { $fixed += "go-backend/input_methods/yime/yimecore/testdata/$probe" }
    foreach ($path in $fixed) {
        if (-not (Test-Path -LiteralPath (Resolve-NBChild $Root $path) -PathType Leaf)) { throw "Missing required source: $path" }
    }
    $listed = @(Invoke-NBGit $Root @('ls-files', '--cached', '--others', '--exclude-standard', '--', 'go-backend'))
    $selected = @($listed | Where-Object {
        ($_ -match '^go-backend/.+\.go$' -or $_ -eq 'go-backend/go.sum' -or
         $_ -match '^go-backend/input_methods/yime/yimecore/testdata/.+\.json$') -and
        (Test-Path -LiteralPath (Resolve-NBChild $Root $_) -PathType Leaf)
    })
    @($fixed + $selected | Sort-Object -Unique)
}
function Copy-NBSourceSnapshot([string]$SourceRoot, [string]$SnapshotRoot) {
    if (@(Invoke-NBGit $SourceRoot @('rev-parse', '--show-prefix')) -join '') { throw 'SourceRoot must be the repository root' }
    $head = (@(Invoke-NBGit $SourceRoot @('rev-parse', 'HEAD')) -join '').Trim()
    if ($head -cnotmatch '^[a-f0-9]{40}$') { throw 'Invalid source commit' }
    $status = @(Invoke-NBGit $SourceRoot @('status', '--porcelain', '--untracked-files=all'))
    $names = @(Get-NBSourceNames $SourceRoot)
    $records = @($names | ForEach-Object { Get-NBFileRecord $SourceRoot $_ })
    foreach ($record in $records) {
        $destination = Resolve-NBChild $SnapshotRoot $record.path
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath (Resolve-NBChild $SourceRoot $record.path) -Destination $destination
    }
    Assert-NBRecords $SnapshotRoot $records
    Assert-NBRecords $SourceRoot $records
    Assert-NBNames $names @(Get-NBSourceNames $SourceRoot)
    if ((@(Invoke-NBGit $SourceRoot @('rev-parse', 'HEAD')) -join '').Trim() -cne $head) { throw 'HEAD changed during snapshot capture' }
    Assert-NBNames $status @(Invoke-NBGit $SourceRoot @('status', '--porcelain', '--untracked-files=all'))
    [pscustomobject][ordered]@{ git_commit = $head; git_status = $status; git_dirty = [bool]$status.Count;
        source_root = $SourceRoot; files = $records; capture_policy = 'copy-and-check-source-and-snapshot-hashes-and-file-set';
        atomic_snapshot = $false; installed_payloads_copied = $false }
}
function Assert-NBHostFacts($HostFacts, [string]$MemoryProfile) {
    if ($HostFacts.native_architecture -ne 9 -or -not $HostFacts.process_64bit -or
        $HostFacts.cpu -notmatch '\bi7-7820X\b' -or $HostFacts.cores -ne 8 -or $HostFacts.logical_processors -ne 16) {
        throw 'This experiment requires the identified i7-7820X, 8-core/16-thread native x64 host and a 64-bit PowerShell process'
    }
    if ($HostFacts.process_affinity -ne 65535 -or $HostFacts.process_priority -cne 'Normal') {
        throw 'Start from a normal-priority PowerShell with all 16 logical processors available'
    }
    $range = switch ($MemoryProfile) { 'baseline' { @(90, 98) } 'os32gb' { @(30, 33) } 'os16gb' { @(14, 17) } default { throw 'Unknown memory profile' } }
    $visible = [double]$HostFacts.os_visible_memory_bytes / 1GB
    if ($visible -lt $range[0] -or $visible -gt $range[1]) { throw "OS-visible RAM ($visible GiB) does not match $MemoryProfile; this runner does not alter Windows memory limits" }
}
function Get-NBHost([string]$MemoryProfile) {
    if ($env:OS -ne 'Windows_NT') { throw 'Native Windows execution required' }
    $cpus = @(Get-CimInstance Win32_Processor)
    if ($cpus.Count -ne 1) { throw 'Expected the identified single-socket host' }
    $cpu = $cpus[0]; $computer = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem
    $self = [Diagnostics.Process]::GetCurrentProcess()
    $hostFacts = [ordered]@{ computer_name = $env:COMPUTERNAME; computer_model = $computer.Model; cpu = $cpu.Name;
        native_architecture = [int]$cpu.Architecture; process_64bit = [Environment]::Is64BitProcess;
        cores = [int]$cpu.NumberOfCores; logical_processors = [int]$cpu.NumberOfLogicalProcessors;
        reported_physical_memory_bytes = [uint64]$computer.TotalPhysicalMemory;
        os_visible_memory_bytes = [uint64]$os.TotalVisibleMemorySize * 1KB; os_caption = $os.Caption;
        os_version = $os.Version; os_build = $os.BuildNumber; memory_profile = $MemoryProfile;
        power_plan = ((& powercfg /getactivescheme) -join '').Trim(); process_affinity = $self.ProcessorAffinity.ToInt64();
        process_priority = $self.PriorityClass.ToString(); disks = @(Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size);
        measured_at = [DateTime]::UtcNow.ToString('o'); runner_changes_cpu_or_os_memory_limits = $false }
    Assert-NBHostFacts $hostFacts $MemoryProfile
    return $hostFacts
}
function Invoke-NBTool([string]$File, [string[]]$Arguments, [string]$Log) {
    & $File @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
    $code = $LASTEXITCODE
    if ($null -eq $code) { throw "Missing process exit code: $File" }
    return [int]$code
}
function Assert-NBPE([string]$Path) {
    $stream = [IO.File]::OpenRead($Path); $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw 'Invalid executable header' }
        $stream.Position = 0x3c; $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt $stream.Length - 6) { throw 'Invalid PE header offset' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Expected Windows x64 executable' }
    } finally { $reader.Dispose() }
}
function Get-NBRegistration([string]$ModulePath) {
    $provider = Import-Module $ModulePath -Force -PassThru
    try {
        & $provider { Get-YimeCoreNativeMaintenanceSnapshot -TargetUserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) }
    } finally { Remove-Module $provider }
}
function Set-NBBuildEnvironment([string]$WorkRoot) {
    $values = @{ GOOS = 'windows'; GOARCH = 'amd64'; GOAMD64 = 'v1'; CGO_ENABLED = '0'; GOENV = 'off';
        GOTOOLCHAIN = 'local'; GOWORK = 'off'; GOFLAGS = '-mod=readonly'; GOEXPERIMENT = ''; GOPROXY = 'off';
        GOSUMDB = 'off'; GOMAXPROCS = ''; GOMEMLIMIT = ''; GODEBUG = ''; GO111MODULE = 'on';
        GOCACHE = (Join-Path $WorkRoot 'go-cache'); GOPATH = (Join-Path $WorkRoot 'go-path');
        GOMODCACHE = (Join-Path $WorkRoot 'go-mod-cache'); GOTMPDIR = (Join-Path $WorkRoot 'go-temp');
        TEMP = (Join-Path $WorkRoot 'temp'); TMP = (Join-Path $WorkRoot 'temp') }
    $old = @{}
    foreach ($name in $values.Keys) { $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    foreach ($name in @('GOCACHE', 'GOPATH', 'GOMODCACHE', 'GOTMPDIR', 'TEMP')) { $null = New-Item -ItemType Directory -Force -Path $values[$name] }
    foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name, $values[$name], 'Process') }
    return $old
}
function Restore-NBEnvironment($Old) {
    foreach ($name in $Old.Keys) { [Environment]::SetEnvironmentVariable($name, $Old[$name], 'Process') }
}
function Assert-NBPackage([string]$Root, [string]$ExpectedManifestHash) {
    $manifestPath = Resolve-NBChild $Root 'package-manifest.json'
    if ((Get-NBDigest $manifestPath) -cne $ExpectedManifestHash) { throw 'Package manifest changed' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema_version -cne 'yimecore-native-core-benchmark-v1' -or
        $manifest.target -cne 'mainstream_x64' -or $manifest.cpu_model -cne 'i7-7820X' -or
        $manifest.installable -isnot [bool] -or $manifest.installable -or
        $manifest.build_passed -isnot [bool] -or -not $manifest.build_passed) { throw 'Unsupported or incomplete benchmark package' }
    Assert-NBRecords $Root $manifest.files
    Assert-NBNames @($manifest.files.path | Sort-Object) @(Get-NBFileNames $Root | Where-Object { $_ -cne 'package-manifest.json' })
    foreach ($required in @('native-core-benchmark.psm1', 'support/native-maintenance-evidence.psm1',
        'performance-tiers.json', 'source-state.json', 'bin/yimecore-index-bench.exe', 'bin/yimecore-learning-experiment.exe',
        'indexes/full.yidx', 'indexes/variable.yidx', 'indexes/shorthand.yidx', 'probes/e1_probes.json', 'probes/e2_sentence_probes.json')) {
        if (@($manifest.files.path) -cnotcontains $required) { throw "Package is missing: $required" }
    }
    $self = @($manifest.files | Where-Object path -CEQ 'native-core-benchmark.psm1')
    if ($self.Count -ne 1 -or $self[0].sha256 -cne $script:NBModuleHash -or (Get-NBDigest $script:NBModulePath) -cne $script:NBModuleHash) {
        throw 'Import the unchanged native-core-benchmark.psm1 from this package'
    }
    foreach ($tool in @('yimecore-index-bench', 'yimecore-learning-experiment')) { Assert-NBPE (Join-Path $Root "bin/$tool.exe") }
    return $manifest
}

function New-YimeCoreNativeBenchmark {
    [CmdletBinding()]
    param([string]$SourceRoot = 'Z:\', [string]$BenchmarkRoot = 'C:\YimeBench')
    $ErrorActionPreference = 'Stop'
    $hostFacts = Get-NBHost 'baseline'
    $root = Assert-NBLocalRoot $BenchmarkRoot
    $go = (Get-Command go -CommandType Application -ErrorAction Stop).Source
    $null = Get-Command git -CommandType Application -ErrorAction Stop
    $id = 'i7-7820x-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $work = Resolve-NBChild $root "preparations/$id"
    $package = Resolve-NBChild $root "packages/$id"
    if ((Test-Path -LiteralPath $work) -or (Test-Path -LiteralPath $package)) { throw 'Preserve existing preparation outputs' }
    $null = New-Item -ItemType Directory -Force -Path $work, $package
    $snapshot = Join-Path $work 'source'
    $null = New-Item -ItemType Directory -Path $snapshot
    $before = $null; $old = $null; $failure = $null; $built = $false; $protected = $false
    try {
        Write-Host 'Copying and verifying the selected shared source. Keep it stable during this phase.'
        $state = Copy-NBSourceSnapshot $SourceRoot $snapshot
        Write-NBJson $state (Join-Path $package 'source-state.json')
        $policy = Get-Content -LiteralPath (Join-Path $snapshot 'tools/yimecore/development-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $target = @($policy.experiment_targets | Where-Object { $_.id -ceq 'mainstream_x64' -and $_.status -ceq 'active' })
        if ($target.Count -ne 1 -or $target[0].architecture -cne 'x64' -or $target[0].go_arch -cne 'amd64') { throw 'The source policy does not authorize the mainstream x64 experiment' }
        Write-Host 'Source snapshot verified. Development may continue; building now reads the local snapshot only.'
        foreach ($dir in @('bin', 'indexes', 'probes', 'support')) { $null = New-Item -ItemType Directory -Path (Join-Path $package $dir) }
        Copy-Item -LiteralPath (Join-Path $snapshot 'tools/yimecore/native-maintenance-evidence.psm1') -Destination (Join-Path $package 'support/native-maintenance-evidence.psm1')
        Copy-Item -LiteralPath (Join-Path $snapshot 'tools/yimecore/performance-tiers.json') -Destination (Join-Path $package 'performance-tiers.json')
        if ((Get-NBDigest $script:NBModulePath) -cne $script:NBModuleHash) { throw 'Benchmark module changed since import' }
        Copy-Item -LiteralPath $script:NBModulePath -Destination (Join-Path $package 'native-core-benchmark.psm1')
        $provider = Join-Path $package 'support/native-maintenance-evidence.psm1'
        $before = Get-NBRegistration $provider
        Write-NBJson $before (Join-Path $work 'registration-before.json')
        $old = Set-NBBuildEnvironment $work
        Push-Location (Join-Path $snapshot 'go-backend')
        try {
            $hostArch = @(& $go env GOHOSTOS GOHOSTARCH)
            if ($LASTEXITCODE -ne 0 -or ($hostArch -join '|') -cne 'windows|amd64') { throw 'Use native windows/amd64 Go' }
            $hostFacts['go_version'] = (& $go version) -join ''
            if ($LASTEXITCODE -ne 0) { throw 'Could not query Go version' }
            $moduleText = @(& $go mod edit -json)
            if ($LASTEXITCODE -ne 0) { throw 'Could not parse the snapshot Go module' }
            $module = ($moduleText -join "`n") | ConvertFrom-Json
            $external = @($module.PSObject.Properties | Where-Object {
                $_.Name -in @('Require', 'Replace') -and $null -ne $_.Value -and @($_.Value).Count -gt 0
            })
            if ($module.Module.Path -cne 'github.com/tsaanghwang/Yime/go-backend' -or
                $external.Count -gt 0) {
                throw 'This self-contained core package requires the canonical module without external requirements or replacement roots'
            }
            $testArgs = @('test', '-count=1', './input_methods/yime/yimecore', './cmd/yimecore-index', './cmd/yimecore-index-bench', './cmd/yimecore-learning-experiment')
            if ((Invoke-NBTool $go $testArgs (Join-Path $work 'go-tests.log')) -ne 0) { throw 'Core prerequisite tests failed' }
            foreach ($name in @('yimecore-index', 'yimecore-index-bench', 'yimecore-learning-experiment')) {
                $destination = Join-Path $package "bin/$name.exe"
                if ((Invoke-NBTool $go @('build', '-trimpath', '-buildvcs=false', '-o', $destination, "./cmd/$name") (Join-Path $work "$name-build.log")) -ne 0) { throw "Build failed: $name" }
                Assert-NBPE $destination
            }
        } finally { Pop-Location }
        foreach ($probe in @('e1_probes.json', 'e2_sentence_probes.json')) {
            Copy-Item -LiteralPath (Join-Path $snapshot "go-backend/input_methods/yime/yimecore/testdata/$probe") -Destination (Join-Path $package "probes/$probe")
        }
        $dataRoot = Join-Path $snapshot 'go-backend/input_methods/yime/data'
        foreach ($mode in @('full', 'variable', 'shorthand')) {
            $buildReport = Join-Path $work "$mode-index.json"
            $arguments = @('-mode', $mode, '-source', (Join-Path $dataRoot "yime_$mode.dict.yaml"),
                '-output', (Join-Path $package "indexes/$mode.yidx"), '-manifest', $buildReport,
                '-allowed-source-root', $dataRoot, '-allowed-output-root', $root)
            if ((Invoke-NBTool (Join-Path $package 'bin/yimecore-index.exe') $arguments (Join-Path $work "$mode-index.log")) -ne 0) { throw "Index build failed: $mode" }
            $report = Get-Content -LiteralPath $buildReport -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($report.verified -isnot [bool] -or -not $report.verified) { throw "Index verification failed: $mode" }
        }
        Assert-NBRecords $snapshot $state.files
        Assert-NBNames @($state.files.path | Sort-Object) @(Get-NBFileNames $snapshot)
        $after = Get-NBRegistration $provider
        Write-NBJson $after (Join-Path $work 'registration-after.json')
        $protected = $before.snapshot_sha256 -ceq $after.snapshot_sha256
        if (-not $protected) { throw 'Protected registry/default-input state changed during preparation' }
        Write-NBJson $hostFacts (Join-Path $work 'build-host.json')
        $records = @(Get-NBFileNames $package | ForEach-Object { Get-NBFileRecord $package $_ })
        $manifest = [ordered]@{ schema_version = 'yimecore-native-core-benchmark-v1'; target = 'mainstream_x64'; cpu_model = 'i7-7820X';
            package_id = $id; generated_at = [DateTime]::UtcNow.ToString('o'); build_passed = $true; installable = $false;
            go_version = $hostFacts.go_version; goamd64 = 'v1'; git_commit = $state.git_commit; git_dirty = $state.git_dirty;
            source_state_sha256 = (Get-NBDigest (Join-Path $package 'source-state.json')); files = $records;
            preparation_evidence = $work; protected_registration_unchanged = $protected;
            core_benchmark_passed = $null; installed_host_passed = $null; physical_ime_compatibility_passed = $null; release_ready = $false }
        Write-NBJson $manifest (Join-Path $package 'package-manifest.json')
        $built = $true
        $receipt = [pscustomobject]@{ PackageRoot = $package; ManifestSHA256 = (Get-NBDigest (Join-Path $package 'package-manifest.json')); PreparationRoot = $work }
        Write-NBJson $receipt (Join-Path $work 'receipt.json')
        Write-Host "Prepared core benchmark package: $package"
        return $receipt
    } catch { $failure = $_.Exception.Message; throw }
    finally {
        if ($null -ne $old) { Restore-NBEnvironment $old }
        if (-not $built -and $null -ne $before) {
            try {
                $after = Get-NBRegistration (Join-Path $package 'support/native-maintenance-evidence.psm1')
                Write-NBJson $after (Join-Path $work 'registration-after-failure.json')
                $protected = $before.snapshot_sha256 -ceq $after.snapshot_sha256
            } catch { $failure = "$failure; registration verification: $($_.Exception.Message)" }
        }
        Write-NBJson ([ordered]@{ prepared = $built; failure = $failure; protected_registration_unchanged = $protected; package_root = $package; benchmark_executed = $false }) (Join-Path $work 'summary.json')
    }
}

function Get-NBQueryRow($Report, [int]$ExitCode, [string]$Stage, [string]$Mode, [int]$Iterations, [double]$BudgetMS, [uint64]$MemoryBudget) {
    $count = if ($Stage -ceq 'e1') { 9 } else { 5 }
    if ($Report.mode -cne $Mode -or $Report.iterations -ne $Iterations -or $Report.probe_count -ne $count -or
        $Report.latency.samples -ne [math]::Ceiling($Iterations / 10.0) -or $Report.latency.batch_size -ne 10 -or
        $Report.latency.p95_ns -le 0 -or $Report.process_memory.private_bytes -le 0 -or
        $Report.passed -isnot [bool]) { throw 'Incomplete or mismatched query evidence' }
    $correct = $Report.passed -and $ExitCode -eq 0
    $latency = [double]$Report.latency.p95_ns / 1e6 -le $BudgetMS
    $memory = [uint64]$Report.process_memory.private_bytes -le $MemoryBudget
    [pscustomobject][ordered]@{ stage = $Stage; mode = $Mode; exit_code = $ExitCode; correctness_passed = $correct;
        p95_ms = [double]$Report.latency.p95_ns / 1e6; p99_ms = [double]$Report.latency.p99_ns / 1e6;
        private_bytes = $Report.process_memory.private_bytes; interaction_budget_ms = $BudgetMS; memory_budget_bytes = $MemoryBudget;
        interaction_budget_passed = $latency; memory_budget_passed = $memory; passed = ($correct -and $latency -and $memory) }
}
function Get-NBLearningRow($Report, [int]$ExitCode, [string]$Mode, [int]$Iterations, [double]$P95Budget, [double]$P99Budget) {
    foreach ($name in @('promotion_passed', 'persistence_passed', 'context_passed', 'forget_passed', 'latency_gate_passed', 'passed')) {
        if ($Report.$name -isnot [bool]) { throw 'Incomplete learning evidence' }
    }
    if ($Report.mode -cne $Mode -or $Report.static_latency.samples -ne $Iterations -or $Report.learned_latency.samples -ne $Iterations -or
        $Report.static_latency.batch_size -ne 5000 -or $Report.learned_latency.batch_size -ne 5000 -or
        $Report.static_latency.p95_ns -le 0 -or $Report.static_latency.p99_ns -le 0 -or
        $Report.learned_latency.p95_ns -le 0 -or $Report.learned_latency.p99_ns -le 0) { throw 'Mismatched learning samples' }
    $p95 = [double]$Report.learned_latency.p95_ns / [double]$Report.static_latency.p95_ns
    $p99 = [double]$Report.learned_latency.p99_ns / [double]$Report.static_latency.p99_ns
    $correct = $Report.promotion_passed -and $Report.persistence_passed -and $Report.context_passed -and $Report.forget_passed
    $latency = $Report.latency_gate_passed -and $p95 -le $P95Budget -and $p99 -le $P99Budget
    [pscustomobject][ordered]@{ stage = 'e3'; mode = $Mode; exit_code = $ExitCode; correctness_passed = $correct;
        p95_overhead_ratio = $p95; p99_overhead_ratio = $p99; latency_gate_passed = $latency;
        passed = ($correct -and $latency -and $Report.passed -and $ExitCode -eq 0) }
}
function Invoke-YimeCoreNativeBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSHA256,
        [string]$BenchmarkRoot = 'C:\YimeBench', [ValidateSet('baseline', 'os32gb', 'os16gb')][string]$MemoryProfile = 'baseline',
        [ValidateRange(100, 10000)][int]$Iterations = 1000, [ValidateRange(100, 10000)][int]$LearningIterations = 100)
    $ErrorActionPreference = 'Stop'
    $root = Assert-NBLocalRoot $BenchmarkRoot
    $package = Assert-NBLocalRoot $PackageRoot
    $manifest = Assert-NBPackage $package $ManifestSHA256
    $hostFacts = Get-NBHost $MemoryProfile
    $null = New-Item -ItemType Directory -Force -Path $root
    $lock = [IO.File]::Open((Join-Path $root 'native-benchmark.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $run = $null; $before = $null; $failure = $null; $integrity = $false; $protected = $false
    $rows = [Collections.Generic.List[object]]::new(); $old = @{}
    try {
        $id = $MemoryProfile + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $run = Resolve-NBChild $root "results/$id"
        if (Test-Path -LiteralPath $run) { throw 'Preserve existing benchmark results' }
        $null = New-Item -ItemType Directory -Force -Path $run
        foreach ($name in @('GOMAXPROCS', 'GOMEMLIMIT', 'GODEBUG')) {
            $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        $hostFacts['cleared_process_environment'] = $old
        Write-NBJson $hostFacts (Join-Path $run 'host.json')
        $before = Get-NBRegistration (Join-Path $package 'support/native-maintenance-evidence.psm1')
        Write-NBJson $before (Join-Path $run 'registration-before.json')
        $profiles = Get-Content -LiteralPath (Join-Path $package 'performance-tiers.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = @($profiles.experiment_profiles | Where-Object { $_.id -ceq 'mainstream' -and $_.architecture -ceq 'x64' })
        if ($profile.Count -ne 1 -or $profile[0].private_memory_budget_mb -le 0) { throw 'Missing physical x64 memory budget' }
        $budgets = $profiles.provisional_interaction_budgets_ms
        foreach ($stage in @('e1', 'e2')) {
            $probe = if ($stage -ceq 'e1') { 'e1_probes.json' } else { 'e2_sentence_probes.json' }
            $budget = if ($stage -ceq 'e1') { [double]$budgets.e1_complete_9_probe_set_p95 } else { [double]$budgets.e2_complete_5_probe_set_p95 }
            if ($budget -le 0) { throw 'Invalid interaction budget' }
            foreach ($mode in @('full', 'variable', 'shorthand')) {
                $output = Join-Path $run "$stage-$mode.json"
                $arguments = @('-index', (Join-Path $package "indexes/$mode.yidx"), '-probes', (Join-Path $package "probes/$probe"),
                    '-mode', $mode, '-iterations', $Iterations.ToString(), '-output', $output)
                $code = Invoke-NBTool (Join-Path $package 'bin/yimecore-index-bench.exe') $arguments (Join-Path $run "$stage-$mode.log")
                $report = Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
                $rows.Add((Get-NBQueryRow $report $code $stage $mode $Iterations $budget ([uint64]$profile[0].private_memory_budget_mb * 1MB)))
            }
        }
        foreach ($mode in @('full', 'variable', 'shorthand')) {
            $modelRoot = Join-Path $run "learning-$mode"
            $null = New-Item -ItemType Directory -Path $modelRoot
            $output = Join-Path $modelRoot 'learning.json'
            $arguments = @('-index', (Join-Path $package "indexes/$mode.yidx"), '-mode', $mode,
                '-model', (Join-Path $modelRoot 'synthetic-model.json'), '-iterations', $LearningIterations.ToString(), '-batch-size', '5000', '-output', $output)
            $code = Invoke-NBTool (Join-Path $package 'bin/yimecore-learning-experiment.exe') $arguments (Join-Path $modelRoot 'learning.log')
            $report = Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
            $rows.Add((Get-NBLearningRow $report $code $mode $LearningIterations ([double]$budgets.learning_p95_overhead_ratio) ([double]$budgets.learning_p99_overhead_ratio)))
        }
    } catch { $failure = $_.Exception.Message }
    finally {
        try { $null = Assert-NBPackage $package $ManifestSHA256; $integrity = $true }
        catch { $failure = "$failure; package verification: $($_.Exception.Message)" }
        if ($null -ne $before) {
            try {
                $after = Get-NBRegistration (Join-Path $package 'support/native-maintenance-evidence.psm1')
                if ($run) { Write-NBJson $after (Join-Path $run 'registration-after.json') }
                $protected = $before.snapshot_sha256 -ceq $after.snapshot_sha256
            } catch { $failure = "$failure; registration verification: $($_.Exception.Message)" }
        }
        Restore-NBEnvironment $old
        $lock.Dispose()
        if ($run) {
            $passed = $rows.Count -eq 9 -and @($rows.ToArray() | Where-Object { -not $_.passed }).Count -eq 0 -and $integrity -and $protected -and -not $failure
            $summary = [ordered]@{ schema_version = 'yimecore-native-core-measurement-v1'; target = 'mainstream_x64';
                package_id = $manifest.package_id; package_manifest_sha256 = $ManifestSHA256; git_commit = $manifest.git_commit; git_dirty = $manifest.git_dirty;
                host = $hostFacts; iterations = $Iterations; learning_iterations = $LearningIterations; rows = @($rows.ToArray()); failure = $failure;
                package_unchanged = $integrity; protected_registration_unchanged = $protected; core_benchmark_passed = $passed;
                installed_host_passed = $null; physical_ime_compatibility_passed = $null; rime_comparison_passed = $null; release_ready = $false;
                limitations = @('E1/E2 report batch-amortized complete probe sets, not individual keystrokes or end-to-end input latency.',
                    'Memory is a post-workload process snapshot, not a measured peak. Index-open timing is not a controlled cold boot.',
                    'E3 uses new synthetic learning files in this result directory.',
                    'No IPC, TSF, installed desktop host, Rime comparison or broad x64-machine acceptance is claimed.',
                    'OS-visible RAM limits do not reproduce another CPU, memory-channel layout, SSD or machine.') }
            Write-NBJson $summary (Join-Path $run 'summary.json')
        }
    }
    if (-not $run -or -not $passed) { throw "Native core benchmark incomplete or failed; preserve evidence in $run. $failure" }
    Write-Host "Core benchmark passed: $run"
    return (Join-Path $run 'summary.json')
}
Export-ModuleMember -Function New-YimeCoreNativeBenchmark, Invoke-YimeCoreNativeBenchmark
