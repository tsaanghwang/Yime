[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$developmentScope = Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$goBackend = Join-Path $repoRoot 'go-backend'
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment\e6d-independence'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $allowedRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
}
$outputDir = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($outputDir -ne $allowedRoot -and
    -not $outputDir.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "E6-D evidence must stay under $allowedRoot"
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if (-not ('YimeCoreProcessImageQuery' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class YimeCoreProcessImageQuery {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool QueryFullProcessImageName(
        IntPtr process, uint flags, StringBuilder path, ref uint size);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
}

function Get-LiveProcessImagePath([int]$ProcessId) {
    $processQueryLimitedInformation = [uint32]0x1000
    $handle = [YimeCoreProcessImageQuery]::OpenProcess(
        $processQueryLimitedInformation, $false, $ProcessId)
    if ($handle -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "could not open live process $ProcessId for image query: Win32 $errorCode"
    }
    try {
        $buffer = [Text.StringBuilder]::new(32768)
        $size = [uint32]$buffer.Capacity
        if (-not [YimeCoreProcessImageQuery]::QueryFullProcessImageName(
                $handle, 0, $buffer, [ref]$size)) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "could not read live process $ProcessId image path: Win32 $errorCode"
        }
        return $buffer.ToString()
    }
    finally {
        [YimeCoreProcessImageQuery]::CloseHandle($handle) | Out-Null
    }
}

$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$runtimeConfigPath = Join-Path $stateRootPath 'runtime-config.json'
$runtimeStatusPath = Join-Path $stateRootPath 'runtime-status.json'
foreach ($path in @($runtimeConfigPath, $runtimeStatusPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "active trial runtime evidence is missing: $path"
    }
}
$runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeStatus = Get-Content -LiteralPath $runtimeStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = [string]$runtimeConfig.install_root
}
$packageRootPath = [IO.Path]::GetFullPath($PackageRoot)
$configuredRoot = [IO.Path]::GetFullPath([string]$runtimeConfig.install_root)
if (-not $packageRootPath.Equals($configuredRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'E6-D must audit the package selected by the active runtime configuration'
}
$autostartValidator = Join-Path $PSScriptRoot 'repair-e6c-trial-autostart.ps1'
# A running new process does not prove that the next login will start that build.
# Validation must not repair the registry or hide the observed mismatch.
& $autostartValidator -StateRoot $stateRootPath -ValidateOnly `
    -OutputPath (Join-Path $outputDir 'autostart-before.json') | Out-Null
if ($runtimeStatus.state -ne 'running' -or [int]$runtimeStatus.runtime_pid -le 0 -or
    [int]$runtimeStatus.broker_pid -le 0) {
    throw 'E6-D requires the active trial runtime and Broker to be running'
}
$runtimeExecutable = [IO.Path]::GetFullPath((Get-LiveProcessImagePath ([int]$runtimeStatus.runtime_pid)))
$brokerExecutable = [IO.Path]::GetFullPath((Get-LiveProcessImagePath ([int]$runtimeStatus.broker_pid)))
$expectedRuntimeExecutable = [IO.Path]::GetFullPath((Join-Path $packageRootPath 'bin\YimeCoreTrialRuntime.exe'))
$expectedBrokerExecutable = [IO.Path]::GetFullPath((Join-Path $packageRootPath 'bin\YimeBroker.exe'))
if (-not $runtimeExecutable.Equals($expectedRuntimeExecutable, [StringComparison]::OrdinalIgnoreCase) -or
    -not $brokerExecutable.Equals($expectedBrokerExecutable, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'live trial runtime or Broker executable does not converge on the active package'
}

function Get-RegistryDefaultValue([string]$Key, [ValidateSet('32', '64')][string]$View) {
    $lines = @(& reg.exe query $Key /ve "/reg:$View" 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return [ordered]@{ exists = $false; type = ''; value = '' }
    }
    foreach ($line in $lines) {
        if ([string]$line -match '^\s+.*?\s+(REG_\S+)\s+(.*)$') {
            return [ordered]@{ exists = $true; type = $matches[1]; value = $matches[2].Trim() }
        }
    }
    throw "could not parse registry value for $Key ($View-bit view)"
}

$experimentalClsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$productionClsid = '{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$experimentalKey = "HKLM\SOFTWARE\Classes\CLSID\$experimentalClsid\InprocServer32"
$productionKey = "HKLM\SOFTWARE\Classes\CLSID\$productionClsid\InprocServer32"
$productionBefore = [ordered]@{
    x64 = Get-RegistryDefaultValue $productionKey '64'
    x86 = Get-RegistryDefaultValue $productionKey '32'
}
$experimental = [ordered]@{
    x64 = Get-RegistryDefaultValue $experimentalKey '64'
    x86 = Get-RegistryDefaultValue $experimentalKey '32'
}
$expectedExperimentalX64 = [IO.Path]::GetFullPath((Join-Path $packageRootPath 'x64\YimeTextServiceExperiment.dll'))
if (-not $experimental.x64.exists -or
    -not ([IO.Path]::GetFullPath([string]$experimental.x64.value)).Equals($expectedExperimentalX64, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'experimental x64 COM registration does not converge on the active package'
}
foreach ($view in @('x64', 'x86')) {
    if ($productionBefore[$view].exists -and
        ([string]$productionBefore[$view].value).StartsWith($packageRootPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "production PIME $view registration points inside the YimeCore trial package"
    }
}

$auditTool = Join-Path $outputDir 'YimeCoreIndependenceAudit.exe'
$packageEvidencePath = Join-Path $outputDir 'package-audit.json'
$dependencyPath = Join-Path $outputDir 'go-runtime-dependencies.txt'
$testLog = Join-Path $outputDir 'go-test.txt'
Push-Location $goBackend
try {
    & go test ./input_methods/yime/yimecore ./cmd/yimecore-independence-audit -count=1 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) { throw "E6-D dependency tests failed; see $testLog" }
    $dependencies = @(& go list -deps ./cmd/yimebroker ./cmd/yimecore-trial-runtime `
        ./input_methods/yime/yimecore ./input_methods/yime/engineapi)
    if ($LASTEXITCODE -ne 0) { throw 'could not enumerate YimeCore runtime dependencies' }
    $dependencies | Set-Content -LiteralPath $dependencyPath -Encoding utf8
    $forbiddenDependencies = @($dependencies | Where-Object {
        $_ -match '(^|/)pime($|/)' -or $_ -match 'librime|native_cgo|win32ui' -or
        $_ -eq 'github.com/tsaanghwang/Yime/go-backend/input_methods/yime'
    })
    if ($forbiddenDependencies.Count -ne 0) {
        throw "YimeCore runtime imports forbidden source packages: $($forbiddenDependencies -join ', ')"
    }
    & go build -o $auditTool ./cmd/yimecore-independence-audit
    if ($LASTEXITCODE -ne 0) { throw 'could not build YimeCore independence auditor' }
}
finally {
    Pop-Location
}
& $auditTool -package $packageRootPath -output $packageEvidencePath
if ($LASTEXITCODE -ne 0) { throw "installed package independence audit failed; see $packageEvidencePath" }
$packageEvidence = Get-Content -LiteralPath $packageEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $packageEvidence.passed) { throw 'installed package independence report did not pass' }

$productionAfter = [ordered]@{
    x64 = Get-RegistryDefaultValue $productionKey '64'
    x86 = Get-RegistryDefaultValue $productionKey '32'
}
$productionUnchanged = ($productionBefore | ConvertTo-Json -Compress -Depth 4) -eq
    ($productionAfter | ConvertTo-Json -Compress -Depth 4)
if (-not $productionUnchanged) {
    throw 'production PIME COM registration changed during the read-only E6-D audit'
}

$summaryPath = Join-Path $outputDir 'summary.json'
$autostartEvidencePath = Join-Path $outputDir 'autostart.json'
$autostart = (& $autostartValidator -StateRoot $stateRootPath -ValidateOnly `
    -OutputPath $autostartEvidencePath) | ConvertFrom-Json
$sourceFiles = @(
    'go-backend/cmd/yimecore-independence-audit/main.go',
    'go-backend/cmd/yimecore-independence-audit/main_test.go',
    'go-backend/input_methods/yime/yimecore/dependency_boundary_test.go',
    'YimeTextServiceExperiment/CMakeLists.txt',
    'YimeTextServiceExperiment/YimeTextServiceIds.h',
    'tools/yimecore/run-e6d-independence-readiness.ps1',
    'tools/yimecore/development-scope.ps1',
    'tools/yimecore/development-scope.json',
    'tools/yimecore/repair-e6c-trial-autostart.ps1'
)
$sourceHashes = foreach ($relative in $sourceFiles) {
    $absolute = Join-Path $repoRoot $relative.Replace('/', '\')
    [ordered]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
[ordered]@{
    schema_version = 'yimecore-e6d-independence-readiness-v1'
    development_scope = $developmentScope
    tested_architectures = @('x64')
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    git_dirty = [bool]((& git -C $repoRoot status --porcelain).Count)
    package_root = $packageRootPath
    package_manifest_sha256 = [string]$packageEvidence.manifest_sha256
    package_audit_path = $packageEvidencePath
    package_audit_sha256 = (Get-FileHash -LiteralPath $packageEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    package_file_count = [int]$packageEvidence.manifest_file_count
    pe_file_count = @($packageEvidence.pe_files).Count
    package_integrity_passed = [bool]$packageEvidence.manifest_integrity_passed
    install_metadata_consistency_passed = [bool]$packageEvidence.install_metadata_passed
    required_independent_components_passed = [bool]$packageEvidence.required_components_passed
    x64_x86_arm64_machine_types_passed = [bool]$packageEvidence.pe_architecture_passed
    forbidden_rime_pime_artifacts_absent = [bool]$packageEvidence.forbidden_artifacts_absent
    forbidden_rime_pime_pe_imports_absent = [bool]$packageEvidence.forbidden_pe_imports_absent
    forbidden_go_runtime_dependencies_absent = $true
    runtime_state = [string]$runtimeStatus.state
    runtime_pid = [int]$runtimeStatus.runtime_pid
    broker_pid = [int]$runtimeStatus.broker_pid
    runtime_executable = $runtimeExecutable
    broker_executable = $brokerExecutable
    runtime_package_convergence_passed = $true
    current_user_autostart_convergence_passed = [bool]$autostart.passed
    autostart_evidence_path = $autostartEvidencePath
    autostart_evidence_sha256 = (Get-FileHash -LiteralPath $autostartEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    experimental_registration = $experimental
    production_registration_before = $productionBefore
    production_registration_after = $productionAfter
    production_registration_unchanged = $productionUnchanged
    production_registration_mutated_by_audit = $false
    installer_or_registration_command_executed = $false
    source_hashes = $sourceHashes
    passed = [bool]$packageEvidence.passed -and $productionUnchanged -and [bool]$autostart.passed
    limitations = @(
        'This gate proves package, static source-dependency and active registration separation; it does not uninstall Rime/PIME.',
        'Legacy x86 and ARM64 retained payloads receive static integrity checks only. Current-identity x86 is an active separate build/package/host gate; ARM64 and other hardware remain frozen.',
        'Trusted package signing remains deferred while the signing certificate application is pending.'
    )
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "YimeCore E6-D independence readiness passed: $summaryPath"
