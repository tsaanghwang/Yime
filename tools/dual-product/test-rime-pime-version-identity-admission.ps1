[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$allowedParent = Join-Path $repo '.tmp\dual-product'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $output) -ine $allowedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-version-identity-test-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-version-identity-test-* directory.'
}
if (-not (Test-Path -LiteralPath $allowedParent)) {
    New-Item -ItemType Directory -Path $allowedParent -Force | Out-Null
}
foreach ($path in @($repo, (Split-Path -Parent $allowedParent), $allowedParent)) {
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Version-identity fixture path must not traverse a reparse point: $path"
    }
}
New-Item -ItemType Directory -Path $output | Out-Null

$modulePath = Join-Path $PSScriptRoot 'rime-pime-version-identity-admission.psm1'
$module = Import-Module -Name $modulePath -Force -PassThru
$passed = 0
$failures = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++ }
    catch { $script:failures.Add("$Name`: $($_.Exception.Message)") }
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Reasons($Result, [string[]]$Expected) {
    foreach ($reason in $Expected) {
        Assert-True ($result.reasons -ccontains $reason) "Missing rejection reason: $reason"
    }
}
function New-Identity(
    [string]$Version,
    [string]$Path,
    [string]$Sha256,
    [long]$Bytes,
    [bool]$Strict = $true,
    [bool]$Durable = $true,
    [bool]$Current = $true
) {
    [pscustomobject][ordered]@{
        product_version = $Version
        installer_path = $Path
        installer_sha256 = $Sha256
        installer_bytes = $Bytes
        strict_receipt = $Strict
        evidence_artifacts_durable = $Durable
        current_build_evidence = $Current
    }
}

Check 'module-exports-only-pure-admission-function' {
    $exports = @($module.ExportedFunctions.Keys)
    Assert-True ($exports.Count -eq 1 -and $exports[0] -ceq 'Get-RimePimeVersionIdentityAdmission') `
        "Unexpected module exports: $($exports -join ', ')"
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) 'Admission module has PowerShell parse errors.'
    $allowedCommands = @(
        'Compare-RimePimeProductVersionPrecedence',
        'Export-ModuleMember',
        'Get-RimePimeIdentityProperty',
        'Select-Object',
        'Set-StrictMode',
        'Test-RimePimePositiveIntegerValue',
        'Test-RimePimeProductVersionValue'
    )
    $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        Assert-True (-not [string]::IsNullOrWhiteSpace($name) -and $allowedCommands -ccontains $name) `
            "Admission module contains an unreviewed command invocation: $name"
    }
}

$old = New-Identity '1.4.0-dev' 'installer/YIME-1.4.0-dev-setup.exe' ('1' * 64) 100
$successor = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.1-setup.exe' ('2' * 64) 101

Check 'distinct-canonical-successor-is-admitted-only-at-identity-layer' {
    $result = Get-RimePimeVersionIdentityAdmission $old $successor '1.4.0-dev.1'
    Assert-True $result.identity_transition_admitted 'Distinct canonical identity was rejected.'
    Assert-True ($result.reasons.Count -eq 0) 'Admitted identity has rejection reasons.'
    Assert-True (-not $result.actual_canonical_migration_admitted -and -not $result.actual_canonical_migrated) `
        'Identity admission was promoted to actual migration admission.'
    Assert-True $result.paths_compared_case_insensitively_for_windows 'Windows path comparison boundary is missing.'
    Assert-True ($result.schema_version -ceq 'yime-rime-pime-version-identity-admission-v1') `
        'Identity admission schema changed.'
    Assert-True (-not $result.installer_or_uninstaller_executed -and
        -not $result.registry_or_product_process_touched) 'Pure-data action boundaries changed.'
}

Check 'same-leaf-different-hash-is-rejected' {
    $next = New-Identity '1.4.0-dev' 'installer/YIME-1.4.0-dev-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev'
    Assert-True (-not $result.identity_transition_admitted) 'Same leaf was admitted.'
    Assert-Reasons $result @(
        'successor-product-version-is-not-strictly-greater-by-semver',
        'old-and-successor-product-version-not-distinct',
        'old-and-successor-installer-path-not-distinct-on-windows'
    )
}

Check 'core-version-downgrade-is-rejected' {
    $next = New-Identity '1.3.9-dev' 'installer/YIME-1.3.9-dev-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.3.9-dev'
    Assert-True (-not $result.identity_transition_admitted) 'Core-version downgrade was admitted as a successor.'
    Assert-Reasons $result @('successor-product-version-is-not-strictly-greater-by-semver')
}

Check 'semver-prerelease-precedence-is-enforced' {
    $cases = @(
        @('1.4.0-dev.2', '1.4.0-dev.1', $false),
        @('1.4.0', '1.4.0-rc.1', $false),
        @('1.4.0-alpha', '1.4.0-1', $false),
        @('1.4.0-alpha.9', '1.4.0-alpha.10', $true),
        @('1.4.0-1', '1.4.0-alpha', $true),
        @('1.4.0-rc.1', '1.4.0', $true)
    )
    foreach ($case in $cases) {
        $beforeVersion = [string]$case[0]
        $afterVersion = [string]$case[1]
        $expectedAdmission = [bool]$case[2]
        $before = New-Identity $beforeVersion ("installer/YIME-$beforeVersion-setup.exe") ('3' * 64) 102
        $after = New-Identity $afterVersion ("installer/YIME-$afterVersion-setup.exe") ('4' * 64) 103
        $result = Get-RimePimeVersionIdentityAdmission $before $after $afterVersion
        Assert-True ($result.identity_transition_admitted -eq $expectedAdmission) `
            "Unexpected SemVer precedence decision: $beforeVersion -> $afterVersion"
        if (-not $expectedAdmission) {
            Assert-Reasons $result @('successor-product-version-is-not-strictly-greater-by-semver')
        }
    }
}

Check 'case-only-version-and-leaf-change-is-rejected-on-windows' {
    $upper = New-Identity '1.4.0-DEV' 'installer/YIME-1.4.0-DEV-setup.exe' ('1' * 64) 100
    $lower = New-Identity '1.4.0-dev' 'installer/YIME-1.4.0-dev-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $upper $lower '1.4.0-dev'
    Assert-True (-not $result.identity_transition_admitted) 'Case-only Windows path change was admitted.'
    Assert-Reasons $result @('old-and-successor-installer-path-not-distinct-on-windows')
}

Check 'distinct-leaf-same-hash-is-rejected' {
    $next = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.1-setup.exe' ('1' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Same installer hash was admitted.'
    Assert-Reasons $result @('old-and-successor-installer-sha256-not-distinct')
}

Check 'same-version-with-invented-different-leaf-is-rejected' {
    $next = New-Identity '1.4.0-dev' 'installer/YIME-invented-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev'
    Assert-True (-not $result.identity_transition_admitted) 'Invented leaf for the same version was admitted.'
    Assert-Reasons $result @(
        'successor-installer-path-is-not-canonical-versioned-leaf',
        'successor-product-version-is-not-strictly-greater-by-semver',
        'old-and-successor-product-version-not-distinct'
    )
}

Check 'successor-version-and-canonical-leaf-mismatch-is-rejected' {
    $next = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.2-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Version/leaf mismatch was admitted.'
    Assert-Reasons $result @('successor-installer-path-is-not-canonical-versioned-leaf')
}

Check 'illegal-version-is-rejected' {
    $next = New-Identity 'bad version' 'installer/YIME-bad version-setup.exe' ('2' * 64) 101
    $result = Get-RimePimeVersionIdentityAdmission $old $next 'bad version'
    Assert-True (-not $result.identity_transition_admitted) 'Illegal version was admitted.'
    Assert-Reasons $result @('expected-successor-invalid-product-version', 'successor-invalid-product-version')
}

Check 'unsupported-or-ambiguous-version-forms-are-rejected' {
    foreach ($version in @('1.4', '01.4.0-dev', '1.4.0+build.7', '1.4.0_dev', '1.4.0-dev.01', '65536.0.0-dev')) {
        $next = New-Identity $version ("installer/YIME-$version-setup.exe") ('2' * 64) 101
        $result = Get-RimePimeVersionIdentityAdmission $old $next $version
        Assert-True (-not $result.identity_transition_admitted) "Unsupported version was admitted: $version"
        Assert-Reasons $result @('expected-successor-invalid-product-version', 'successor-invalid-product-version')
    }
}

Check 'expected-version-mismatch-is-rejected' {
    $result = Get-RimePimeVersionIdentityAdmission $old $successor '1.4.0-dev.2'
    Assert-True (-not $result.identity_transition_admitted) 'Unexpected successor version was admitted.'
    Assert-Reasons $result @('successor-product-version-differs-from-expected')
}

Check 'successor-strict-receipt-is-required' {
    $next = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.1-setup.exe' ('2' * 64) 101 $false
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Non-strict successor was admitted.'
    Assert-Reasons $result @('successor-strict-receipt-not-proven')
}

Check 'successor-durable-evidence-is-required' {
    $next = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.1-setup.exe' ('2' * 64) 101 $true $false
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Non-durable successor was admitted.'
    Assert-Reasons $result @('successor-durable-evidence-not-proven')
}

Check 'successor-current-build-evidence-is-required' {
    $next = New-Identity '1.4.0-dev.1' 'installer/YIME-1.4.0-dev.1-setup.exe' ('2' * 64) 101 $true $true $false
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Non-current successor was admitted.'
    Assert-Reasons $result @('successor-current-build-evidence-not-proven')
}

Check 'old-strict-receipt-is-required' {
    $previous = New-Identity '1.4.0-dev' 'installer/YIME-1.4.0-dev-setup.exe' ('1' * 64) 100 $false
    $result = Get-RimePimeVersionIdentityAdmission $previous $successor '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Non-strict old receipt was admitted.'
    Assert-Reasons $result @('old-strict-receipt-not-proven')
}

Check 'missing-and-invalid-installer-values-fail-closed' {
    $next = [pscustomobject]@{ product_version = '1.4.0-dev.1'; installer_path = 'installer/YIME-1.4.0-dev.1-setup.exe'; installer_sha256 = 'ABC'; installer_bytes = 0 }
    $result = Get-RimePimeVersionIdentityAdmission $old $next '1.4.0-dev.1'
    Assert-True (-not $result.identity_transition_admitted) 'Incomplete successor was admitted.'
    Assert-Reasons $result @(
        'successor-missing-strict-receipt', 'successor-missing-evidence-artifacts-durable',
        'successor-missing-current-build-evidence', 'successor-invalid-installer-sha256',
        'successor-invalid-installer-bytes'
    )
}

$result = [pscustomobject][ordered]@{
    schema_version = 'yime-rime-pime-version-identity-admission-test-v1'
    passed = $failures.Count -eq 0
    passed_count = $passed
    failed_count = $failures.Count
    failures = @($failures)
    boundaries = [pscustomobject][ordered]@{
        fixture_only = $true
        actual_canonical_read_or_written = $false
        build_or_product_process_executed = $false
        installer_or_uninstaller_executed = $false
        registry_or_default_input_method_touched = $false
        production_user_data_read_or_written = $false
        actual_canonical_migration_admitted = $false
    }
}
$json = ($result | ConvertTo-Json -Depth 12 -Compress) + "`n"
$resultPath = Join-Path $output 'result.json'
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$stream = [IO.File]::Open($resultPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
finally { $stream.Dispose() }
$digest = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sidecarBytes = [Text.Encoding]::ASCII.GetBytes("$digest  result.json`n")
$sidecar = [IO.File]::Open($resultPath + '.sha256', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $sidecar.Write($sidecarBytes, 0, $sidecarBytes.Length); $sidecar.Flush($true) }
finally { $sidecar.Dispose() }

if ($failures.Count -ne 0) {
    throw "Version-identity admission fixture failed: $($failures.Count) checks. Evidence: $resultPath ($digest)"
}
Write-Host "PASS: version-identity admission fixture $passed checks; no actual canonical, build, installer or product action ran. Evidence: $resultPath ($digest)"
