[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$MultimodeVerifier,
    [Parameter(Mandatory)][string]$TsfTest
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$null = Get-YimeCoreDevelopmentScope
$product = Get-LocalProductDescriptor (Join-Path $PackageRoot 'local-product.json')
if (Test-Path -LiteralPath $OutputRoot) { throw 'Runtime verification requires a new evidence directory' }
Assert-LocalProductPlainPath $OutputRoot
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
# Exercise a copied package outside the repository, with explicit disposable
# state. Never rename/move the user's repository or touch installed state.
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
                return [ordered]@{ status = $status; broker = ($child | Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate) }
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
    & $TsfTest (Join-Path $package 'x64\YimeTextServiceExperiment.dll') $pipeName 2>&1 |
        Tee-Object -LiteralPath (Join-Path $OutputRoot 'tsf-composition.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Direct isolated x64 TSF/language-bar regression failed' }
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
            registered_host_test_executed = $false; live_word_acceptance = $false
            note = 'Direct isolated TSF and disposable data only; not physical taskbar/installed host acceptance. Retain relocated files for inspection.'
        }) (Join-Path $OutputRoot 'summary.json')
        Pop-Location
    }
}
