[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$scope = Get-YimeCoreDevelopmentScope
if (@($scope.active_architectures) -notcontains 'x86' -or @($scope.frozen_targets) -contains 'x86') {
    throw 'The current development scope does not authorize x86 surface work.'
}
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\yimecore-experiment\x86-local-surface'))
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $allowedRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$out = [IO.Path]::GetFullPath($OutputRoot)
$allowedPrefix = $allowedRoot.TrimEnd('\') + '\'
if (-not $out.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $out)) {
    throw "x86 evidence must use a new child of $allowedRoot"
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt') | Out-Null
$before = $null
$passed = $false
try {
    $before = Get-LocalProductProtectionEvidence
    $build = Join-Path $out 'build-win32'
    & cmake -S (Join-Path $repoRoot 'YimeTextServiceExperiment') -B $build `
        -G 'Visual Studio 17 2022' -A Win32 -DYIME_LOCAL_PRODUCT=ON
    if ($LASTEXITCODE -ne 0) { throw 'Current-identity Win32 TSF configure failed.' }
    & cmake --build $build --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Current-identity Win32 TSF build failed.' }
    $release = Join-Path $build 'Release'
    $dll = Join-Path $release 'YimeTextServiceExperiment.dll'
    $contract = Join-Path $release 'YimeTextServiceContractTests.exe'
    & $contract $dll 2>&1 | Tee-Object -LiteralPath (Join-Path $out 'contract.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Current-identity Win32 TSF contract regression failed.' }
    $records = @('YimeTextServiceExperiment.dll','YimeTextServiceRegistration.exe',
        'YimeRegisteredHostTests.exe','YimeTextServiceContractTests.exe','YimeTsfCompositionTests.exe') |
        ForEach-Object {
            $path = Join-Path $release $_
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Win32 artifact: $_" }
            $stream = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            try {
                $reader = [IO.BinaryReader]::new($stream)
                $stream.Position = 0x3c
                $peOffset = $reader.ReadInt32()
                $stream.Position = $peOffset + 4
                $machine = $reader.ReadUInt16()
            } finally { $stream.Dispose() }
            if ($machine -ne 0x014c) { throw "Artifact is not x86 PE: $_" }
            [ordered]@{ name=$_; path=$path; bytes=(Get-Item -LiteralPath $path).Length;
                sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); pe_machine='0x014c' }
        }
    $after = Get-LocalProductProtectionEvidence
    $preserved = ($before | ConvertTo-Json -Depth 30 -Compress) -ceq ($after | ConvertTo-Json -Depth 30 -Compress)
    if (-not $preserved) { throw 'Build-only x86 work changed protected registration or the default input method.' }
    $passed = $true
    [ordered]@{
        schema_version='yimecore-local-x86-surface-build-v1'; passed=$true
        generated_at=[DateTime]::UtcNow.ToString('o'); git_commit=(& git -C $repoRoot rev-parse HEAD).Trim()
        development_scope=$scope; architecture='x86'; execution_model='WOW64 user-mode TSF surface with native x64 runtime/Broker'
        local_product_identity=$true; artifacts=@($records); contract_test_passed=$true
        registry_changed=$false; default_input_method_changed=$false; installed=$false
        registered_host_test_passed=$false; live_firefox_passed=$false; live_notepad_plus_plus_passed=$false
        next_step='Add transaction-safe dual-architecture packaging and registration before installed-host acceptance.'
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
} finally {
    if (-not $passed -and $null -ne $before) {
        $after = Get-LocalProductProtectionEvidence
        [ordered]@{ passed=$false; registration_and_default_preserved=(($before|ConvertTo-Json -Depth 30 -Compress) -ceq ($after|ConvertTo-Json -Depth 30 -Compress)) } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'failure-summary.json') -Encoding UTF8
    }
    Stop-Transcript | Out-Null
}
Write-Output "PASS: current-identity x86 TSF surface build and isolated contract. Evidence: $out"
