#Requires -Version 5.1
param([switch]$RunGoSmoke)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$diagnosticModule = Import-Module (Join-Path $PSScriptRoot 'native-core-profile.psm1') -Force -PassThru
$fixtureParent = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$work = Join-Path $fixtureParent ('Yime CPU fixture ' + [guid]::NewGuid().ToString('N').Substring(0,8))
$null = New-Item -ItemType Directory -Path $work
$utf8 = [Text.UTF8Encoding]::new($false)
$originalPath = Join-Path $repo 'go-backend/cmd/yimecore-learning-experiment/main.go'
$original = Get-Content -LiteralPath $originalPath -Raw -Encoding UTF8
$originalHash = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash
$oldEnvironment = @{}
$junction = $null
function Assert-ProfileTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-ProfileRejected([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    if ($null -eq $message -or $message -notmatch $Pattern) { throw "Expected rejection '$Pattern'; received '$message'" }
}
try {
    $generated = & $diagnosticModule { param($s) New-NPInstrumentedMain $s } $original
    Assert-ProfileTest ($generated.Contains('collectNativeCPU(staticEngine, learnedEngine')) 'Missing diagnostic call'
    Assert-ProfileTest (-not $generated.Contains('staticLatency, learnedLatency := measurePair(')) 'Timed acceptance path must not execute in diagnostic main'
    Assert-ProfileTest ($generated.Contains('!promotionPassed || !persistencePassed || !contextPassed || !forgetPassed')) 'Functional preparation gates were lost'
    Assert-ProfileTest ($generated.Contains('func measurePair(')) 'Original helpers unexpectedly altered'
    $crlf = $original.Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]10, ([string][char]13 + [char]10))
    $fromCRLF = & $diagnosticModule { param($s) New-NPInstrumentedMain $s } $crlf
    Assert-ProfileTest ($generated -ceq $fromCRLF) 'LF and CRLF must produce identical generated code'
    Assert-ProfileRejected { & $diagnosticModule { param($s) New-NPInstrumentedMain $s } ($original + 'unexpected code') } 'Unsupported E3 source'
    $fakePackage = Join-Path $work 'untrusted package'
    $null = New-Item -ItemType Directory -Path $fakePackage
    $sentinel = Join-Path $fakePackage 'executed.txt'
    $fakeHelper = Join-Path $fakePackage 'native-core-benchmark.psm1'
    [IO.File]::WriteAllText($fakeHelper, "[IO.File]::WriteAllText('$sentinel', 'unexpected import')", $utf8)
    $helperHash = (Get-FileHash -LiteralPath $fakeHelper -Algorithm SHA256).Hash.ToLowerInvariant()
    $fakeManifest = Join-Path $fakePackage 'package-manifest.json'
    [IO.File]::WriteAllText($fakeManifest, (ConvertTo-Json -Depth 5 @{files=@(@{path='native-core-benchmark.psm1';sha256=$helperHash})}), $utf8)
    $manifestHash = (Get-FileHash -LiteralPath $fakeManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-ProfileRejected { & $diagnosticModule { param($p,$h) Import-NPGuard $p $h } $fakePackage $manifestHash } 'not imported'
    Assert-ProfileTest (-not (Test-Path -LiteralPath $sentinel)) 'Untrusted helper executed before validation'
    Assert-ProfileRejected { & $diagnosticModule { param($p) Import-NPGuard $p ('0' * 64) } $fakePackage } 'manifest changed'
    $gitRoot = Join-Path $work 'git fixture'
    $null = New-Item -ItemType Directory -Path (Join-Path $gitRoot '.git')
    Assert-ProfileRejected { & $diagnosticModule { param($p) Assert-NPBootstrapPath $p } $gitRoot } 'outside Git'
    Assert-ProfileRejected { & $diagnosticModule { Assert-NPBootstrapPath '\\localhost\share\package' } } 'local fixed drive'
    $junction = Join-Path $work 'junction'
    $null = New-Item -ItemType Junction -Path $junction -Target $fakePackage
    Assert-ProfileRejected { & $diagnosticModule { param($p) Assert-NPBootstrapPath $p } $junction } 'reparse'
    $good = [pscustomobject]@{schema_version='yimecore-native-cpu-profile-v1'; diagnostic_only=$true;
        eligible_for_acceptance=$false; profile_complete=$true; functional_setup_passed=$true;
        mode='variable'; code='bj'; profile_file='cpu.pprof'; profile_sha256=('a' * 64);
        replays_per_engine=250013; static_replays=250013; learned_replays=250013;
        warmup_per_engine=2000; chunk_size=50; chunks_per_engine=5001;
        measurement_order='interleaved_alternating_static_learned'; elapsed_with_profiling_ns=1000}
    & $diagnosticModule { param($r) Assert-NPReport $r 'variable' 250013 } $good
    foreach ($mutation in @(@{name='eligible_for_acceptance';value=$true},@{name='functional_setup_passed';value=$false},
        @{name='static_replays';value=250012},@{name='code';value='wrong'},@{name='profile_file';value='../outside.pprof'})) {
        $bad = ($good | ConvertTo-Json) | ConvertFrom-Json
        $bad.($mutation.name) = $mutation.value
        Assert-ProfileRejected { & $diagnosticModule { param($r) Assert-NPReport $r 'variable' 250013 } $bad } 'evidence'
    }
    $safeText = '   10ms 20.00% 20.00% 30ms 60.00% runtime.mapaccess'
    $unsafeText = '   10ms 20.00% 20.00% 30ms 60.00% C:\Users\private\source.go'
    $sanitized = @(& $diagnosticModule { param($s) Get-NPSafeTopRows $s } ($safeText + [char]10 + $unsafeText))
    Assert-ProfileTest ($sanitized.Count -eq 1 -and $sanitized[0] -ceq $safeText) 'Share report leaked a local path'
    Write-Host 'CPU diagnostic PowerShell contracts passed.'
    if ($RunGoSmoke) {
        $go = (Get-Command go -CommandType Application | Select-Object -First 1).Source
        foreach ($name in @('GOOS','GOARCH','GOAMD64','CGO_ENABLED','GOWORK','GOFLAGS','GOENV','GOTOOLCHAIN','GOPROXY','GOSUMDB')) {
            $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
        }
        $values = @{GOOS='windows';GOARCH='amd64';GOAMD64='v1';CGO_ENABLED='0';GOWORK='off';GOFLAGS='-mod=readonly';
            GOENV='off';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off'}
        foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name,$values[$name],'Process') }
        $working = Join-Path $repo 'go-backend'
        $driver = & $diagnosticModule { $script:NPDriverSource }
        $mainFile = Join-Path $work 'main.go'; $driverFile = Join-Path $work 'native_cpu.go'
        [IO.File]::WriteAllText($mainFile, $generated, $utf8)
        [IO.File]::WriteAllText($driverFile, $driver, $utf8)
        $exe = Join-Path $work 'diagnostic fixture.exe'; $indexExe = Join-Path $work 'index fixture.exe'
        $runChild = { param($file,$arguments,$directory,$log) Invoke-NPProcess -File $file -Arguments $arguments -WorkingDirectory $directory -Log $log }
        $null = & $diagnosticModule $runChild $go @('build','-trimpath','-buildvcs=false','-o',$exe,$mainFile,$driverFile) $working (Join-Path $work 'build.log')
        $null = & $diagnosticModule $runChild $go @('build','-trimpath','-buildvcs=false','-o',$indexExe,'./cmd/yimecore-index') $working (Join-Path $work 'index-build.log')
        $argumentSource = @'
package main
import ("encoding/json"; "fmt"; "os")
func main() {
 if len(os.Args)>1 && os.Args[1]=="fail" { fmt.Fprintln(os.Stderr,"intentional failure"); os.Exit(7) }
 fmt.Fprintln(os.Stderr,"successful child may write stderr")
 json.NewEncoder(os.Stdout).Encode(os.Args[1:])
}
'@
        $argumentFile = Join-Path $work 'arguments.go'; $argumentExe = Join-Path $work 'arguments fixture.exe'
        [IO.File]::WriteAllText($argumentFile, $argumentSource, $utf8)
        $null = & $diagnosticModule $runChild $go @('build','-o',$argumentExe,$argumentFile) $working (Join-Path $work 'arguments-build.log')
        $expectedArguments = @('','with spaces','C:\trailing path\','a"quote','two\\slashes')
        $argumentResult = & $diagnosticModule $runChild $argumentExe $expectedArguments $work (Join-Path $work 'arguments.log')
        $observedArguments = @($argumentResult.stdout | ConvertFrom-Json)
        Assert-ProfileTest (($observedArguments | ConvertTo-Json -Compress) -ceq ($expectedArguments | ConvertTo-Json -Compress)) 'Windows process argument round trip failed'
        Assert-ProfileTest ($argumentResult.stderr.Contains('successful child')) 'Stderr from successful child was lost'
        Assert-ProfileRejected { & $diagnosticModule $runChild $argumentExe @('fail') $work (Join-Path $work 'failure.log') } 'exited 7'
        foreach ($mode in @('full','variable','shorthand')) {
            $modeRoot = Join-Path $work $mode
            $null = New-Item -ItemType Directory -Path $modeRoot
            $code = if ($mode -ceq 'full') { 'bjjj' } else { 'bj' }
            $dictionary = Join-Path $modeRoot 'fixture.dict.yaml'
            $lines = @('---','name: fixture','version: "1"','sort: by_weight','...',
                ([string][char]0x7532 + [char]9 + $code + [char]9 + '100'),
                ([string][char]0x4e59 + [char]9 + $code + [char]9 + '1'))
            [IO.File]::WriteAllLines($dictionary, $lines, $utf8)
            $index = Join-Path $modeRoot 'fixture.yidx'
            $buildArgs = @('-mode',$mode,'-source',$dictionary,'-output',$index,'-manifest',(Join-Path $modeRoot 'index.json'),
                '-allowed-source-root',$work,'-allowed-output-root',$work)
            $null = & $diagnosticModule $runChild $indexExe $buildArgs $work (Join-Path $modeRoot 'index.log')
            $reportPath = Join-Path $modeRoot 'diagnostic.json'
            $arguments = @('-index',$index,'-mode',$mode,'-model',(Join-Path $modeRoot 'model.json'),'-output',$reportPath,'-cpu-replays','250013')
            $null = & $diagnosticModule $runChild $exe $arguments $work (Join-Path $modeRoot 'capture.log')
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            & $diagnosticModule { param($r,$m) Assert-NPReport $r $m 250013 } $report $mode
            $cpu = Join-Path $modeRoot 'cpu.pprof'
            $profileHash = (Get-FileHash -LiteralPath $cpu -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-ProfileTest ($profileHash -ceq $report.profile_sha256) 'Unflushed or changed CPU profile'
            foreach ($engine in @('static','learned')) {
                foreach ($order in @('flat','cum')) {
                    $pprofArgs = @('tool','pprof','-top','-nodecount=20','-unit=ms','-symbolize=local',"-tagfocus=engine=$engine")
                    if ($order -eq 'cum') { $pprofArgs += '-cum' }
                    $pprofArgs += @($exe,$cpu)
                    $top = & $diagnosticModule $runChild $go $pprofArgs $work (Join-Path $modeRoot "$engine-$order.log")
                    $rows = @(& $diagnosticModule { param($s) Get-NPSafeTopRows $s } $top.stdout)
                    Assert-ProfileTest ($rows.Count -gt 0 -and $top.stderr -notmatch 'matched no samples') "Missing real $mode/$engine/$order CPU samples"
                }
            }
            Assert-ProfileRejected { & $diagnosticModule $runChild $exe $arguments $work (Join-Path $modeRoot 'reuse.log') } 'exited'
            Assert-ProfileTest ((Get-FileHash -LiteralPath $cpu -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $profileHash) 'Existing CPU evidence was overwritten'
            Write-Host "Real Go CPU profile fixture passed: $mode"
        }
        # Exercise the complete public orchestration against a synthetic package.
        # Only hardware discovery and registry reads are stubbed in this private
        # fixture module instance; production hashes, paths, build and pprof run.
        $bench = Join-Path $work 'public flow'
        $package = Join-Path $bench 'packages/fixture'
        $preparation = Join-Path $bench 'preparations/fixture'
        $snapshot = Join-Path $preparation 'source'
        $null = New-Item -ItemType Directory -Force -Path $package,$snapshot
        $copiedHelper = Join-Path $package 'native-core-benchmark.psm1'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native-core-benchmark.psm1') -Destination $copiedHelper
        $fixtureGuard = Import-Module $copiedHelper -PassThru
        & $fixtureGuard {
            function script:Get-NBHost { param($memory) [ordered]@{ fixture_only=$true; memory_profile='fixture' } }
            function script:Get-NBRegistration { param($path) [pscustomobject]@{ fixture_only=$true; snapshot_sha256=('b' * 64) } }
        }
        $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'go-backend') -Recurse -File -Filter '*.go')
        $sourceFiles += Get-Item -LiteralPath (Join-Path $repo 'go-backend/go.mod')
        foreach ($file in $sourceFiles) {
            $relative = $file.FullName.Substring($repo.TrimEnd('\','/').Length+1)
            $destination = Join-Path $snapshot $relative
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
            Copy-Item -LiteralPath $file.FullName -Destination $destination
        }
        $sourceRecords = @(& $fixtureGuard { param($r) Get-NBFileNames $r | ForEach-Object { Get-NBFileRecord $r $_ } } $snapshot)
        $state = [pscustomobject]@{ git_commit=('0' * 40); git_dirty=$false; files=$sourceRecords }
        & $fixtureGuard { param($v,$p) Write-NBJson $v $p } $state (Join-Path $package 'source-state.json')
        foreach ($relative in @('support/native-maintenance-evidence.psm1','performance-tiers.json','probes/e1_probes.json','probes/e2_sentence_probes.json')) {
            $destination = Join-Path $package $relative
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
            [IO.File]::WriteAllText($destination,'{}',$utf8)
        }
        foreach ($mode in @('full','variable','shorthand')) {
            $destination = Join-Path $package "indexes/$mode.yidx"
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
            Copy-Item -LiteralPath (Join-Path $work "$mode/fixture.yidx") -Destination $destination
        }
        foreach ($name in @('yimecore-index-bench','yimecore-learning-experiment')) {
            $destination = Join-Path $package "bin/$name.exe"
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
            Copy-Item -LiteralPath $indexExe -Destination $destination
        }
        $inventory = @(& $fixtureGuard { param($r) Get-NBFileNames $r | ForEach-Object { Get-NBFileRecord $r $_ } } $package)
        $goVersion = (& $go version) -join ''
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read fixture Go version' }
        $manifest = [ordered]@{schema_version='yimecore-native-core-benchmark-v1';target='mainstream_x64';
            cpu_model='i7-7820X';installable=$false;build_passed=$true;files=$inventory;
            package_id='fixture';git_commit=$state.git_commit;git_dirty=$false;go_version=$goVersion;preparation_evidence=$preparation}
        $manifestPath = Join-Path $package 'package-manifest.json'
        & $fixtureGuard { param($v,$p) Write-NBJson $v $p } $manifest $manifestPath
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $outcome = Invoke-YimeCoreNativeLearningProfile -PackageRoot $package -ManifestSHA256 $manifestHash -BenchmarkRoot $bench -Replays 250013
        $summary = Get-Content -LiteralPath $outcome.SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-ProfileTest ($summary.diagnostic_complete -and -not $summary.eligible_for_acceptance -and $summary.rows.Count -eq 3) 'Public profile orchestration incomplete'
        Assert-ProfileTest ($summary.package_unchanged -and $summary.source_unchanged -and $summary.protected_registration_unchanged) 'Public profile preservation failed'
        Assert-ProfileTest (Test-Path -LiteralPath $outcome.ShareReport -PathType Leaf) 'Missing public share report'
        Write-Host 'Public profiling orchestration fixture passed; hardware and registry checks were fixture stubs, not native acceptance.'
    }
    Assert-ProfileTest ((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash -ceq $originalHash) 'Source entry point was changed'
    Write-Host 'CPU diagnostic checks complete. This is fixture evidence, not physical-host performance acceptance.'
} finally {
    foreach ($name in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$oldEnvironment[$name],'Process') }
    if ($junction -and (Test-Path -LiteralPath $junction)) { [IO.Directory]::Delete($junction) }
    Write-Host "CPU diagnostic fixture evidence: $work"
}
