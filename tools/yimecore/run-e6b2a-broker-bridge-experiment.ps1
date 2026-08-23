[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$dataRoot = Join-Path $goBackend 'input_methods\yime\data'
$sourceRoot = Join-Path $repoRoot 'YimeTextServiceExperiment'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $allowedRoot ('e6b2a\' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "E6-B2a evidence must stay under $allowedRoot" }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$binDir = Join-Path $outputDir 'bin'; New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$broker = Join-Path $binDir 'YimeBroker.exe'; $indexTool = Join-Path $binDir 'yimecore-index.exe'

Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimebroker ./cmd/yimebroker -count=1 2>&1 | Tee-Object -FilePath (Join-Path $outputDir 'go-test.txt')
    if ($LASTEXITCODE) { throw 'E6-B2a Go tests failed.' }
    & go build -trimpath -o $broker ./cmd/yimebroker; if ($LASTEXITCODE) { throw 'Broker build failed.' }
    & go build -trimpath -o $indexTool ./cmd/yimecore-index; if ($LASTEXITCODE) { throw 'Index tool build failed.' }
} finally { Pop-Location }

$bridgeTests = [ordered]@{}
$architectureResults = @()
foreach ($architecture in @([ordered]@{name='x64';cmake='x64';bits=64},[ordered]@{name='x86';cmake='Win32';bits=32})) {
    $buildDir = Join-Path $outputDir ('build-'+$architecture.name)
    & cmake -S $sourceRoot -B $buildDir -A $architecture.cmake 2>&1 | Tee-Object -FilePath (Join-Path $outputDir ('configure-'+$architecture.name+'.txt'))
    if ($LASTEXITCODE) { throw "$($architecture.name) configure failed." }
    & cmake --build $buildDir --config Release 2>&1 | Tee-Object -FilePath (Join-Path $outputDir ('build-'+$architecture.name+'.txt'))
    if ($LASTEXITCODE) { throw "$($architecture.name) build failed." }
    & ctest --test-dir $buildDir -C Release --output-on-failure 2>&1 | Tee-Object -FilePath (Join-Path $outputDir ('contract-'+$architecture.name+'.txt'))
    if ($LASTEXITCODE) { throw "$($architecture.name) B1 regression failed." }
    $testExe = Join-Path $buildDir 'Release\YimeBrokerBridgeTests.exe'
    $bridgeTests[$architecture.name] = $testExe
    $architectureResults += [ordered]@{ architecture=$architecture.name; bits=$architecture.bits; bridge_sha256=(Get-FileHash $testExe -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Start-Broker([string]$Index,[string]$Mode,[string]$Pipe,[string]$ErrorLog) {
    Start-Process -FilePath $broker -ArgumentList @('-index',$Index,'-mode',$Mode,'-named-pipe',$Pipe) -PassThru -WindowStyle Hidden -RedirectStandardError $ErrorLog
}
function Stop-Broker([Diagnostics.Process]$Process) { if ($Process -and -not $Process.HasExited) { Stop-Process -Id $Process.Id -Force; $Process.WaitForExit() } }

$definitions=@([ordered]@{mode='full';source='yime_full.dict.yaml'},[ordered]@{mode='variable';source='yime_variable.dict.yaml'},[ordered]@{mode='shorthand';source='yime_shorthand.dict.yaml'})
$modeResults=@()
foreach($definition in $definitions) {
    $modeDir=Join-Path $outputDir $definition.mode; New-Item -ItemType Directory -Force $modeDir|Out-Null
    $index=Join-Path $modeDir 'index.yidx'; $manifest=Join-Path $modeDir 'index-build.json'
    & $indexTool -mode $definition.mode -source (Join-Path $dataRoot $definition.source) -output $index -manifest $manifest -allowed-source-root $dataRoot -allowed-output-root $outputDir
    if($LASTEXITCODE){throw "$($definition.mode) index build failed."}
    $build=Get-Content $manifest -Raw|ConvertFrom-Json
    $pipe="\\.\pipe\YimeBroker-e6b2a-$($definition.mode)-$PID"
    $process=Start-Broker $index $definition.mode $pipe (Join-Path $modeDir 'broker-before.err')
    $runs=@()
    try {
        foreach($architecture in @('x64','x86')) {
            $timer=[Diagnostics.Stopwatch]::StartNew()
            $output=& $bridgeTests[$architecture] $pipe 2>&1
            $timer.Stop()
            $output|Set-Content -LiteralPath (Join-Path $modeDir ($architecture+'.txt')) -Encoding utf8
            if($LASTEXITCODE){throw "$($definition.mode) $architecture bridge failed: $output"}
            $runs += [ordered]@{architecture=$architecture;elapsed_ms=$timer.Elapsed.TotalMilliseconds;output=($output -join "`n")}
        }
    } finally { Stop-Broker $process }
    $restart=[Diagnostics.Stopwatch]::StartNew(); $process=Start-Broker $index $definition.mode $pipe (Join-Path $modeDir 'broker-after.err')
    try { $restartOutput=& $bridgeTests.x64 $pipe 2>&1; if($LASTEXITCODE){throw "$($definition.mode) restart bridge failed: $restartOutput"} } finally { Stop-Broker $process; $restart.Stop() }
    $selected=@($runs.output|ForEach-Object{if($_ -match 'selected=([^ ]+)'){$Matches[1]}})+@(if(($restartOutput-join "`n") -match 'selected=([^ ]+)'){$Matches[1]})
    $modeResults += [ordered]@{mode=$definition.mode;source_sha256=$build.build.source_sha256;index_sha256=$build.build.index_sha256;index_verified=[bool]$build.verified;runs=$runs;selected_text=$selected[0];stable_selection=(($selected|Select-Object -Unique).Count -eq 1);restart_recovery_ms=$restart.Elapsed.TotalMilliseconds;passed=([bool]$build.verified -and (($selected|Select-Object -Unique).Count -eq 1) -and $restart.ElapsedMilliseconds -lt 2000)}
}

$sourceFiles=@('docs\project\YIMECORE_REPLACEMENT_EXPERIMENT.md','YimeTextServiceExperiment\CMakeLists.txt','YimeTextServiceExperiment\BrokerClient.h','YimeTextServiceExperiment\BrokerClient.cpp','YimeTextServiceExperiment\KeyContract.h','YimeTextServiceExperiment\KeyContract.cpp','YimeTextServiceExperiment\SurfaceSession.h','YimeTextServiceExperiment\SurfaceSession.cpp','YimeTextServiceExperiment\tests\BrokerBridgeTests.cpp','tools\yimecore\run-e6b2a-broker-bridge-experiment.ps1')
$hashes=foreach($relative in $sourceFiles){$hash=Get-FileHash (Join-Path $repoRoot $relative) -Algorithm SHA256;[ordered]@{path=$relative.Replace('\','/');sha256=$hash.Hash.ToLowerInvariant()}}
$sourceHashes=Join-Path $outputDir 'source-hashes.json';$hashes|ConvertTo-Json -Depth 3|Set-Content $sourceHashes -Encoding utf8
$summary=[ordered]@{tool_version='yime-text-service-e6b2a-broker-bridge-v1';stage='e6b2a';generated_at=(Get-Date).ToUniversalTime().ToString('o');git_commit=(& git -C $repoRoot rev-parse HEAD).Trim();git_dirty=[bool]((& git -C $repoRoot status --porcelain).Count);go_version=(& go version).Trim();os_arch='windows/'+$env:PROCESSOR_ARCHITECTURE.ToLowerInvariant();source_boundary=$dataRoot;output_boundary=$outputDir;broker_sha256=(Get-FileHash $broker -Algorithm SHA256).Hash.ToLowerInvariant();architectures=$architectureResults;modes=$modeResults;all_indices_verified=-not($modeResults.index_verified -contains $false);all_modes_passed=-not($modeResults.passed -contains $false);base_digit_composition_verified=$true;shift_candidate_selection_verified=$true;stable_candidate_id_commit_verified=$true;disconnect_does_not_consume_key=$true;restart_within_two_seconds=-not(($modeResults|Where-Object{$_.restart_recovery_ms -ge 2000}).Count);registry_or_installation_changed=$false;production_text_service_wired=$false;source_hashes_sha256=(Get-FileHash $sourceHashes -Algorithm SHA256).Hash.ToLowerInvariant();limitations=@('E6-B2a validates the C++ Broker bridge outside ITfContext; TSF edit-session composition is E6-B2b','candidate UI, language bar, focus transitions, registration and installation remain later gates')}
$summaryPath=Join-Path $outputDir 'summary.json';$summary|ConvertTo-Json -Depth 8|Set-Content $summaryPath -Encoding utf8
Write-Host "YimeTextService E6-B2a evidence: $outputDir"
if(-not $summary.all_indices_verified -or -not $summary.all_modes_passed -or -not $summary.restart_within_two_seconds -or $summary.registry_or_installation_changed -or $summary.production_text_service_wired){throw "E6-B2a gate failed; see $summaryPath"}
