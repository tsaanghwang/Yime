[CmdletBinding()]
param([ValidateSet('Plan','Prepare')][string]$Action='Plan',[string]$OutputRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'local12-maintenance-preparation.psm1') -Force
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source=Join-Path $repo '.tmp\w13o\.tmp\yimecore-local-product\outcome13\package'
$contract=@{
    product_version='0.1.0-local.13';package_id='yimecore-local-0.1.0-local.13-3687a998fda0'
    guarded_native_desktop_rehearsal=$true
    manifest_sha256='1fd54730bffe9b986249cdeaedbd7c8807b255da36e75c6463ff983e378275a9'
    manager_sha256='9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d'
    wrapper_sha256='ec206153c53d96b98aa43cd522167bb55eef83b7d7acedf745f8f966c6851479';member_count=85
}
$probeSource=Join-Path $PSScriptRoot 'rollback-failure-runtime.go'
$probeHash='c17ee123594a4453260583cb53c9ca8133ddde6df4defa2f50d37d3dc75d13b9'
$plan=Get-YimeCoreFaultPreparationPlan $source $contract $probeSource $probeHash
$plan.source_package_id=$contract.package_id
$plan.same_sid_execution_boundary=$false
$plan.required_maintenance_mode='NativeDesktopRehearsal'
if ($Action -eq 'Plan') {
    if ($OutputRoot) { throw 'Plan writes no output directory; use stdout for its JSON.' }
    $plan | ConvertTo-Json -Depth 8
    exit 0
}
$allowed=Join-Path $repo '.tmp\yimecore-local13-maintenance-preparation'
if (-not $OutputRoot) { $OutputRoot=Join-Path $allowed ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
$out=Assert-PreparationNewChild $OutputRoot $allowed
$go=(Get-Command go.exe -CommandType Application -ErrorAction Stop).Source
New-Item -ItemType Directory -Path $out | Out-Null
$stage='prepare-build-environment'
$process=$null
$compileSourceLease=$null
try {
    $build=Join-Path $out 'build'
    foreach ($directory in @($build,(Join-Path $build 'cache'),(Join-Path $build 'temp'),(Join-Path $build 'go-work'))) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    $buildSource=Join-Path $build 'rollback-failure-runtime.go'
    # Compile a verified private copy. Hold the reviewed input open while copying;
    # the compiler never reads the workspace source after this lease is released.
    $probeLease=[IO.File]::Open($probeSource,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $probeCopy=[IO.File]::Open($buildSource,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try { $probeLease.CopyTo($probeCopy) } finally { $probeCopy.Dispose() }
    } finally { $probeLease.Dispose() }
    # Keep the verified private compiler input read-only until the compiler exits.
    $compileSourceLease=[IO.File]::Open($buildSource,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $compileSourceHasher=[Security.Cryptography.SHA256]::Create()
    try { $compileSourceHash=([BitConverter]::ToString($compileSourceHasher.ComputeHash($compileSourceLease))).Replace('-','').ToLowerInvariant() }
    finally { $compileSourceHasher.Dispose();$compileSourceLease.Position=0 }
    if ($compileSourceHash -cne $probeHash) { throw 'Pinned probe source changed before compilation.' }
    $runtime=Join-Path $build 'YimeCoreTrialRuntime.exe'
    $stage='compile-exit-86-probe'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$go
    $start.Arguments='build -trimpath -buildvcs=false -ldflags "-H=windowsgui" -o "'+$runtime+'" "'+$buildSource+'"'
    $start.WorkingDirectory=$build
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach ($entry in @{
        GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GO111MODULE='off';GOTOOLCHAIN='local';GOFLAGS='';GOENV='off';GOWORK='off'
        GOPROXY='off';GOSUMDB='off';GOCACHE=(Join-Path $build 'cache');GOPATH=(Join-Path $build 'go-work')
        GOTMPDIR=(Join-Path $build 'temp');TEMP=(Join-Path $build 'temp');TMP=(Join-Path $build 'temp')
    }.GetEnumerator()) { $start.EnvironmentVariables[$entry.Key]=[string]$entry.Value }
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    if (-not $process.Start()) { throw 'Compiler did not start.' }
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) { $process.Kill();$process.WaitForExit();throw 'Probe compilation exceeded 60 seconds.' }
    $stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $build 'compiler-stdout.txt') -Encoding UTF8
    $stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $build 'compiler-stderr.txt') -Encoding UTF8
    if ($process.ExitCode -ne 0) { throw 'Probe compilation failed; retain compiler diagnostics.' }
    Assert-YimeCoreFailureProbePe $runtime
    $runtimeHash=(Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToLowerInvariant()
    $stage='assemble-preparation-package'
    $result=New-YimeCoreFaultPreparationOutput $source $contract $runtime $runtimeHash (Join-Path $out 'package') $out
    $result.probe_source_sha256=$probeHash
    $result.compiler_path=$go
    $result.probe_compiled=$true
    $result.preparation_entry_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.preparation_module_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'local12-maintenance-preparation.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'plan.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'preparation.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
} catch {
    [ordered]@{schema_version='yimecore-local13-fault-preparation-failure-v1';stage=$stage;message=$_.Exception.Message;
        prepared_only=$true;execution_authorized=$false;ready_to_execute=$false;installer_executed=$false;product_executed=$false} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'failure.json') -Encoding UTF8
    throw
} finally {
    if ($compileSourceLease) { $compileSourceLease.Dispose() }
    if ($process) { $process.Dispose() }
}
