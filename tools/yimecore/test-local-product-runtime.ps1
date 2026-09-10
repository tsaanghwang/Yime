[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$MultimodeVerifier,
    [Parameter(Mandatory)][hashtable]$TsfTests,
    [ValidateSet('mainstream_x64')][string]$ExperimentTarget
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
. (Join-Path $PSScriptRoot 'local-product-test-isolation.ps1')
$null = if ($ExperimentTarget) { Get-YimeCoreExperimentBuildScope $ExperimentTarget } else { Get-YimeCoreDevelopmentScope }
$product = Get-LocalProductDescriptor (Join-Path $PackageRoot 'local-product.json')
if (Test-Path -LiteralPath $OutputRoot) { throw 'Runtime verification requires a new evidence directory' }
Assert-LocalProductPlainPath $OutputRoot
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
# Exercise a copied package under the caller's temporary root, with explicit
# disposable state. A caller may itself isolate TEMP inside the repository;
# this test alone therefore does not claim an outside-repository execution.
# Never rename/move the user's repository or touch installed state.
$relocated = Join-Path ([IO.Path]::GetTempPath()) ('YimeCore-Local-' + [guid]::NewGuid().ToString('N'))
Assert-LocalProductPlainPath $relocated
New-Item -ItemType Directory -Path $relocated | Out-Null
Copy-Item -LiteralPath $PackageRoot -Destination (Join-Path $relocated 'package') -Recurse
$package = Join-Path $relocated 'package'
$broker = Join-Path $package 'bin\YimeBroker.exe'
$runtime = Join-Path $package 'bin\YimeCoreTrialRuntime.exe'
$runtimeState = Join-Path $relocated 'runtime-state'
$statusPath = Join-Path $runtimeState 'runtime-status.json'
$pipeName = '\\.\pipe\YimeBroker.LocalBundle.' + [guid]::NewGuid().ToString('N')
$runtimeArgs = '-install-root "{0}" -state-root "{1}" -pipe "{2}" -no-toolbar' -f $package, $runtimeState, $pipeName
$runtimeProcess = $null
$runtimeBefore = $null
$runtimeAfter = $null
$passed = $false
$stopped = $false
$directTsfArchitectures = @()

function Wait-LocalTestRuntime([int]$PreviousBroker = 0) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($runtimeProcess.HasExited) { throw "Isolated runtime exited: $($runtimeProcess.ExitCode)" }
        $status = $null
        try { $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if ($null -ne $status -and $status.state -eq 'running' -and $status.runtime_pid -eq $runtimeProcess.Id -and
            $status.broker_pid -ne $PreviousBroker -and $status.install_root -ieq $package -and $status.pipe_name -eq $pipeName) {
            $child = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$status.broker_pid)"
            if ($child -and $child.ParentProcessId -eq $runtimeProcess.Id -and $child.ExecutablePath -ieq $broker -and
                $child.CreationDate -ge $runtimeProcess.StartTime) {
                # The supervisor publishes the child PID before the Broker has
                # finished loading indexes and retained its input listener. On
                # a cold/older machine that gap can exceed the TSF activation
                # timeout, so require one real transport connection before
                # dispatching the direct TSF tests.
                $pipeLeaf = $pipeName.Substring('\\.\pipe\'.Length)
                $probe = [IO.Pipes.NamedPipeClientStream]::new(
                    '.', $pipeLeaf, [IO.Pipes.PipeDirection]::InOut,
                    [IO.Pipes.PipeOptions]::Asynchronous,
                    [Security.Principal.TokenImpersonationLevel]::Identification)
                try {
                    $probe.Connect(100)
                    return [ordered]@{ status = $status; broker = ($child | Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate) }
                } catch {
                    # The process is alive but the real input endpoint is not
                    # ready yet. Keep polling within the existing 30s bound.
                } finally {
                    $probe.Dispose()
                }
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Isolated runtime readiness/actual child identity did not converge'
}

Push-Location $relocated
try {
    & (Join-Path $package 'bin\YimeCoreIndependenceAudit.exe') -package $package -output (Join-Path $OutputRoot 'relocated-audit.json')
    if ($LASTEXITCODE -ne 0) { throw 'Relocated package is invalid' }
    & (Join-Path $package 'bin\YimeCoreSentenceRegression.exe') -index-root (Join-Path $package 'indexes') `
        -cases (Join-Path $package 'data\dynamic_sentence_cases.json') -output (Join-Path $OutputRoot 'sentence-regression.json')
    if ($LASTEXITCODE -ne 0) { throw 'Fresh-index sentence regression failed' }
    $model = Join-Path $relocated 'multimode-model'
    New-Item -ItemType Directory -Path $model | Out-Null
    & $MultimodeVerifier -broker $broker -index-root (Join-Path $package 'indexes') `
        -snapshot (Join-Path $model 'user-model.json') -journal (Join-Path $model 'user-model.journal') `
        -manifest (Join-Path $model 'index-control.json') -status (Join-Path $model 'index-control-status.json') `
        -output (Join-Path $OutputRoot 'multimode.json')
    if ($LASTEXITCODE -ne 0) { throw 'Fresh-index multimode/learning/rollback verification failed' }
    $multimode = Get-Content -LiteralPath (Join-Path $OutputRoot 'multimode.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $multimode.passed) { throw 'Multimode evidence did not pass' }
    # Exercise the packaged recovery executable, without Go or live user data.
    New-Item -ItemType File -Path (Join-Path $model '.yime-recovery-clone') | Out-Null
    & (Join-Path $package 'bin\YimeCoreRecoveryProbe.exe') -clone $model -source-id $product.identity.model_source_id `
        -output (Join-Path $OutputRoot 'packaged-recovery.json')
    if ($LASTEXITCODE -ne 0) { throw 'Packaged offline recovery probe failed' }
    $runtimeProcess = Start-Process -FilePath $runtime -ArgumentList $runtimeArgs -WorkingDirectory $relocated -WindowStyle Hidden -PassThru
    $runtimeBefore = Wait-LocalTestRuntime
    foreach ($architecture in @('x64','x86')) {
        $test = [string]$TsfTests[$architecture]
        if ([string]::IsNullOrWhiteSpace($test) -or -not (Test-Path -LiteralPath $test -PathType Leaf)) {
            throw "Direct isolated $architecture TSF test executable is unavailable"
        }
        Invoke-LocalProductIsolatedTestTool -Tool $test `
            -Arguments @((Join-Path $package "$architecture\YimeTextServiceExperiment.dll"), $pipeName, 'bjbjbj') `
            -BuildRoot $BuildRoot -EvidenceRoot $OutputRoot -LogName "tsf-composition-$architecture.txt"
        $directTsfArchitectures += $architecture
    }
    # Kill only the freshly verified child owned by our test supervisor. Nothing
    # is selected by global executable name or persisted installed status.
    $child = Get-Process -Id $runtimeBefore.broker.ProcessId
    if ($child.Path -ine $broker -or [Math]::Abs(($child.StartTime - $runtimeBefore.broker.CreationDate).TotalMilliseconds) -gt 2) {
        throw 'Broker identity changed before fault injection'
    }
    $child.Kill()
    $runtimeAfter = Wait-LocalTestRuntime ([int]$runtimeBefore.broker.ProcessId)
    if ($runtimeAfter.status.restarts -le $runtimeBefore.status.restarts) { throw 'Supervisor restart counter did not advance' }
    $passed = $true
} finally {
    try {
        if ($null -ne $runtimeProcess) {
            $stopper = Start-Process -FilePath $runtime -ArgumentList ('-stop ' + $runtimeArgs) -WorkingDirectory $relocated -WindowStyle Hidden -PassThru
            if (-not $stopper.WaitForExit(15000) -or $stopper.ExitCode -ne 0 -or -not $runtimeProcess.WaitForExit(15000)) {
                throw 'Isolated runtime did not stop; retained evidence identifies the test processes'
            }
            $stopped = $true
        }
    } finally {
        Write-LocalProductJson ([ordered]@{
            passed = [bool]($passed -and $stopped); relocated_root = $relocated; pipe = $pipeName
            runtime_before = $runtimeBefore; runtime_after_broker_failure = $runtimeAfter; runtime_stopped = $stopped
            direct_tsf_architectures = $directTsfArchitectures
            direct_tsf_default_mode = 'variable'; direct_tsf_long_session_requested = $true
            native_test_environment_evidence = 'tsf-composition-<architecture>.txt.fixture.json'
            registered_host_test_executed = $false; live_word_acceptance = $false
            note = 'Direct isolated x64/x86 TSF and disposable data only; not physical taskbar/installed host acceptance. Retain relocated files for inspection.'
        }) (Join-Path $OutputRoot 'summary.json')
        Pop-Location
    }
}
