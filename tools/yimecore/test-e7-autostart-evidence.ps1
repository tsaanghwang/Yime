[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$E6CSummaryPath,
    [Parameter(Mandatory)] [string]$E6DSummaryPath,
    [Parameter(Mandatory)] [string]$PerformanceSummaryPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputRoot = Join-Path $repoRoot ('.tmp\yimecore-experiment\e7-readiness\autostart-regression-' +
    [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$baseE6D = Get-Content -LiteralPath $E6DSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$baseAutostart = Get-Content -LiteralPath $baseE6D.autostart_evidence_path -Raw -Encoding UTF8
$cases = @('valid', 'missing_evidence', 'hash_mismatch', 'wrong_kind', 'stale_command',
    'repair_not_validation', 'wrong_package', 'missing_value', 'process_view_only', 'system_not_verified')
$results = foreach ($name in $cases) {
    $caseRoot = Join-Path $outputRoot $name
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $e6d = $baseE6D | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $autostart = $baseAutostart | ConvertFrom-Json
    switch ($name) {
        'process_view_only' { $autostart.PSObject.Properties.Remove('registry_reader') }
        'system_not_verified' { $autostart.system_registry_verified = $false }
        'wrong_kind' { $autostart.after.kind = 'ExpandString' }
        'stale_command' {
            # Both reported values agree with each other, but not with the
            # runtime independently identified by the installed-package audit.
            $autostart.after.value = '"C:\old-trial\bin\YimeCoreTrialRuntime.exe" -no-toolbar'
            $autostart.expected_value = $autostart.after.value
        }
        'repair_not_validation' {
            $autostart.validated_only = $false
            $autostart.registry_mutation_requested = $true
        }
        'wrong_package' { $autostart.package_manifest_sha256 = '0' * 64 }
        'missing_value' { $autostart.after.exists = $false }
    }
    $autostartPath = Join-Path $caseRoot 'autostart.json'
    $autostart | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $autostartPath -Encoding utf8
    $e6d.autostart_evidence_path = $autostartPath
    $e6d.autostart_evidence_sha256 = (Get-FileHash -LiteralPath $autostartPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($name -eq 'missing_evidence') { $e6d.autostart_evidence_path = Join-Path $caseRoot 'missing.json' }
    if ($name -eq 'hash_mismatch') { $e6d.autostart_evidence_sha256 = '0' * 64 }
    $e6dPath = Join-Path $caseRoot 'e6d.json'
    $e6d | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $e6dPath -Encoding utf8
    $preflightRoot = Join-Path $caseRoot 'preflight'
    try {
        & (Join-Path $PSScriptRoot 'run-e7-cutover-readiness.ps1') `
            -E6CSummaryPath $E6CSummaryPath -E6DSummaryPath $e6dPath `
            -PerformanceSummaryPath $PerformanceSummaryPath -OutputRoot $preflightRoot
    } catch {
        # Other release gates (hardware, signing, source freshness) may remain
        # pending. Only the exact autostart check is under test here.
        if ($_.Exception.Message -notmatch '^E7 cutover readiness is blocked by') { throw }
    }
    $summary = Get-Content -LiteralPath (Join-Path $preflightRoot 'summary.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $check = @($summary.checks | Where-Object name -eq 'e6d_autostart_evidence')
    if ($check.Count -ne 1 -or [bool]$check[0].passed -ne ($name -eq 'valid') -or
        $summary.production_rime_pime_changed -or $summary.cutover_or_registration_command_executed) {
        throw "E7 autostart evidence regression failed: $name"
    }
    [ordered]@{ name = $name; passed = $true; evidence_path = (Join-Path $preflightRoot 'summary.json') }
}
$result = [ordered]@{
    schema_version = 'yimecore-e7-autostart-regression-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    cases = @($results)
    production_rime_pime_changed = $false
    cutover_or_registration_command_executed = $false
    passed = $true
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputRoot 'summary.json') -Encoding utf8
Write-Host "E7 autostart evidence regressions passed: $outputRoot"
