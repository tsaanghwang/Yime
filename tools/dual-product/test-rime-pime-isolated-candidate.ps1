[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$allowedParent = Join-Path $repo '.tmp\dual-product'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $output) -ine $allowedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-o-runner-contract-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-o-runner-contract-* directory.'
}
if (-not (Test-Path -LiteralPath $allowedParent)) {
    New-Item -ItemType Directory -Path $allowedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$runner = Join-Path $PSScriptRoot 'run-rime-pime-isolated-candidate.ps1'
$source = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
$passed = 0
$failed = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS: $Name"
    } catch {
        $script:failed.Add([pscustomobject][ordered]@{ name = $Name; message = [string]$_.Exception.Message })
        Write-Host "FAIL: $Name - $($_.Exception.Message)"
    }
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Rejected([scriptblock]$Body, [string]$Pattern) {
    $caught = $null
    try { & $Body } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'Expected fail-closed rejection did not occur.' }
    if ([string]$caught.Exception.Message -notlike $Pattern) {
        throw "Unexpected rejection: $($caught.Exception.Message)"
    }
}

Check 'runner-parses-under-current-powershell' {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) (($errors | ForEach-Object Message) -join '; ')
}

Check 'fresh-immediate-output-contract-is-explicit' {
    foreach ($anchor in @(
        "'^dp1-o-candidate-[A-Za-z0-9-]+$'",
        'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-o-candidate-* directory.',
        '(Split-Path -Parent $output) -ine $workParent',
        '(Test-Path -LiteralPath $output)'
    )) { Assert-True $source.Contains($anchor) "Missing output guard: $anchor" }
}

Check 'executed-runner-must-match-exact-head-blob' {
    foreach ($anchor in @(
        "`$runnerRelativePath = 'tools/dual-product/run-rime-pime-isolated-candidate.ps1'",
        "`$runnerPath = [IO.Path]::GetFullPath(`$PSCommandPath)",
        "'hash-object', ('--path=' + `$runnerRelativePath), '--', `$runnerPath",
        'Runner must execute from its tracked repository path.',
        'Runner file differs from exact source HEAD.',
        'runner_matches_exact_head = $true'
    )) { Assert-True $source.Contains($anchor) "Missing runner/HEAD binding anchor: $anchor" }
}

Check 'existing-output-is-rejected-before-clone' {
    $existing = Join-Path $allowedParent ('dp1-o-candidate-existing-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $existing | Out-Null
    try {
        Assert-Rejected { & $runner -RepoRoot $repo -OutputRoot $existing } '*fresh immediate*'
        Assert-True (@(Get-ChildItem -LiteralPath $existing -Force).Count -eq 0) 'Rejected existing output was modified.'
    } finally {
        if ((Test-Path -LiteralPath $existing -PathType Container) -and
            @(Get-ChildItem -LiteralPath $existing -Force).Count -eq 0) {
            Remove-Item -LiteralPath $existing
        }
    }
}

Check 'nested-output-is-rejected-before-creation' {
    $nested = Join-Path $output ('dp1-o-candidate-nested-' + [Guid]::NewGuid().ToString('N'))
    Assert-Rejected { & $runner -RepoRoot $repo -OutputRoot $nested } '*fresh immediate*'
    Assert-True (-not (Test-Path -LiteralPath $nested)) 'Rejected nested output was created.'
}

Check 'wrong-prefix-output-is-rejected-before-creation' {
    $wrong = Join-Path $allowedParent ('dp1-o-not-candidate-' + [Guid]::NewGuid().ToString('N'))
    Assert-Rejected { & $runner -RepoRoot $repo -OutputRoot $wrong } '*fresh immediate*'
    Assert-True (-not (Test-Path -LiteralPath $wrong)) 'Rejected wrong-prefix output was created.'
}

$junction = Join-Path $allowedParent ('dp1-o-runner-source-link-' + [Guid]::NewGuid().ToString('N'))
try {
    try { New-Item -ItemType Junction -Path $junction -Target $repo -ErrorAction Stop | Out-Null }
    catch {
        $skipped.Add([pscustomobject][ordered]@{
            name = 'reparse-repository-root-is-rejected'
            reason = 'Junction creation was unavailable; this negative case is skipped and not counted as a pass.'
        })
        Write-Host 'SKIP: reparse-repository-root-is-rejected - junction creation unavailable'
    }
    if (Test-Path -LiteralPath $junction) {
        Check 'reparse-repository-root-is-rejected' {
            $linkedOutput = Join-Path $junction ('.tmp\dual-product\dp1-o-candidate-link-' + [Guid]::NewGuid().ToString('N'))
            Assert-Rejected { & $runner -RepoRoot $junction -OutputRoot $linkedOutput } '*reparse point*'
            Assert-True (-not (Test-Path -LiteralPath $linkedOutput)) 'Rejected reparse-root output was created.'
        }
    }
} finally {
    if (Test-Path -LiteralPath $junction) {
        $junctionItem = Get-Item -LiteralPath $junction -Force
        if (-not ($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not $junction.StartsWith($allowedParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to clean an unexpected junction-test path.'
        }
        # Windows PowerShell 5.1 can throw a provider NullReferenceException
        # when Remove-Item targets a directory junction. Delete only the
        # already verified junction leaf through the same .NET filesystem API.
        [IO.Directory]::Delete($junction, $false)
    }
}

Check 'clone-is-local-nonhardlinked-nocheckout-and-exact-detached-head' {
    foreach ($anchor in @(
        "'clone', '--local', '--no-hardlinks', '--no-checkout', '--no-tags', '--', `$root, `$clone",
        "`$gitCommand = @(Get-Command -Name `$GitPath -CommandType Application -ErrorAction Stop)[0]",
        "`$GitPath = Assert-ToolApplicationFile `$gitCommand.Source 'Git client'",
        "'checkout', '--detach', `$head",
        "'HEAD^{commit}'", "'HEAD^{tree}'",
        "'status', '--porcelain=v1', '--untracked-files=all'",
        'Detached clone is not the exact clean source HEAD.',
        'Ignored actual publication state entered the clone:'
    )) { Assert-True $source.Contains($anchor) "Missing clone identity anchor: $anchor" }
    $clonePattern = '(?m)^[ \t]*''clone'', ''--local'', ''--no-hardlinks'', ''--no-checkout'', ''--no-tags'', ''--'', \$root, \$clone[ \t]*\r?$'
    $checkoutPattern = '(?m)^[ \t]*''-C'', \$clone, ''checkout'', ''--detach'', \$head[ \t]*\r?$'
    Assert-True ([regex]::Matches($source, $clonePattern).Count -eq 1) 'Clone argument vector is not exact.'
    Assert-True ([regex]::Matches($source, $checkoutPattern).Count -eq 1) 'Checkout argument vector is not exact.'
}

Check 'signing-environment-is-cleared-and-restored' {
    foreach ($name in @('YIME_SIGN_CERT_SHA1', 'YIME_RELEASE_SIGNING_REQUIRED', 'YIME_SIGNTOOL_EXE', 'YIME_TIMESTAMP_URL')) {
        Assert-True ($source.IndexOf("[Environment]::SetEnvironmentVariable(`$name, `$null, 'Process')") -ge 0) 'Signing environment clear loop is missing.'
    }
    Assert-True $source.Contains("[Environment]::SetEnvironmentVariable(`$name, `$savedEnvironment[`$name], 'Process')") 'Environment restoration is missing.'
}

Check 'full-static-chain-order-is-fixed' {
    $anchors = @(
        "'build-current-source'",
        "'seal-package-plan'",
        "'build-disabled-installer'",
        "'write-build-manifest'",
        "'static-installer-manifest-check'",
        "'static-postbuild-extraction'",
        "'finalize-canonical-receipt-v2'",
        '$retainedV2 = Publish-RimePimePackageReceiptV2Supersession',
        '$strictV2 = Read-RimePimePackageBuildReceiptV2'
    )
    $last = -1
    foreach ($anchor in $anchors) {
        $next = $source.IndexOf($anchor, $last + 1, [StringComparison]::Ordinal)
        Assert-True ($next -gt $last) "Missing or reordered chain anchor: $anchor"
        $last = $next
    }
    Assert-True $source.Contains("'-StaticOnly'") 'StaticOnly switch is absent from installer validation.'
}

Check 'postbuild-current-membership-and-exact-counts-are-required' {
    foreach ($anchor in @(
        'yime-rime-pime-staged-nsis-build-result-membership-interval-v1',
        'unexpected_membership_event_count -ne 0',
        'package_plan_artifact_count -ne 20',
        'package_plan_matching_stage_binding_count -ne 22',
        "'evidence\result.json'",
        'installer_archive.entry_count -ne 181',
        'uninstaller_archive.entry_count -ne 11',
        'generated_uninstaller_trusted',
        'final_payload_closure'
    )) { Assert-True $source.Contains($anchor) "Missing static closure guard: $anchor" }
}

Check 'actual-publication-and-user-worktree-snapshot-is-protected' {
    foreach ($anchor in @(
        'package-build-receipt.json',
        "Get-ChildItem -LiteralPath `$installerRoot -File -Filter 'YIME-*-setup.exe'",
        'installer/receipt-evidence',
        'docs/YIMECORE_L5_DAILY_USE_TEST_LOG.md',
        'tools/yimecore/get-l5-daily-use-baseline.ps1',
        'docs/YIMECORE_LOCAL12_L5_FINAL_CONFIRMATION_2026-09-06.md',
        'ConvertTo-Json -InputObject $Value -Depth 100 -Compress',
        'Protected actual repository state changed during isolated candidate work.'
    )) { Assert-True $source.Contains($anchor) "Missing protected snapshot anchor: $anchor" }
}

Check 'product-install-sign-and-dp1n-entrypoints-are-absent' {
    foreach ($prohibited in @(
        '-AllowLocalMachine', 'sign-release.ps1', 'verify-release-signatures.ps1',
        'Install-PIME-Test.cmd', 'Uninstall-PIME-Test.cmd',
        'rime-pime-installer-receipt-transaction.ps1'
    )) { Assert-True (-not $source.Contains($prohibited)) "Prohibited entrypoint is present: $prohibited" }
}

Check 'migration-version-and-trust-boundaries-stay-negative' {
    foreach ($anchor in @(
        'distinct_versioned_installer_leaf_for_dp1n = [bool]$distinctVersionedInstallerLeaf',
        'actual_canonical_migration_admitted = $false',
        'actual_canonical_migrated = $false',
        'actual_installer_published = $false',
        'real_installer_transaction_adapter_wired = $false',
        'release_signing_complete = $false',
        'delivery_admitted = $false',
        'hardware_power_loss_durability_verified = $false',
        'directory_metadata_durability_verified = $false',
        'outer_tmp_retention_guaranteed = $false',
        'evidence_archived_outside_tmp = $false',
        "durability_scope = 'isolated-clone-content-addressed-process-interruption-protocol'",
        'active_same_sid_physical_replacement_prevented = $false',
        'full_nsis_toolchain_input_closure = $false'
    )) { Assert-True $source.Contains($anchor) "Missing negative boundary: $anchor" }
}

Check 'outcome-is-create-new-flushed-and-sidecar-bound' {
    foreach ($anchor in @(
        '[IO.FileMode]::CreateNew', '$stream.Flush($true)', '$sidecar.Flush($true)',
        "schema_version = 'yime-rime-pime-isolated-candidate-result-v1'",
        'actual_protected_snapshot_unchanged = [bool]$sourceUnchanged'
    )) { Assert-True $source.Contains($anchor) "Missing outcome sealing anchor: $anchor" }
}

$result = [pscustomobject][ordered]@{
    schema_version = 'yime-rime-pime-isolated-candidate-contract-test-v1'
    passed = $failed.Count -eq 0
    passed_count = $passed
    failed_count = $failed.Count
    skipped_count = $skipped.Count
    failures = @($failed)
    skips = @($skipped)
    runner_sha256 = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash.ToLowerInvariant()
    boundaries = [pscustomobject][ordered]@{
        full_candidate_build_executed = $false
        installer_or_uninstaller_executed = $false
        signing_process_executed = $false
        product_process_touched = $false
        registry_or_default_input_method_touched = $false
        production_user_data_read_or_written = $false
        actual_canonical_touched = $false
    }
}
$json = ($result | ConvertTo-Json -Depth 12 -Compress) + "`n"
$resultPath = Join-Path $output 'result.json'
$jsonBytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$stream = [IO.File]::Open($resultPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($jsonBytes, 0, $jsonBytes.Length); $stream.Flush($true) }
finally { $stream.Dispose() }
$digest = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sidecarBytes = [Text.Encoding]::ASCII.GetBytes("$digest  result.json`n")
$sidecar = [IO.File]::Open($resultPath + '.sha256', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $sidecar.Write($sidecarBytes, 0, $sidecarBytes.Length); $sidecar.Flush($true) }
finally { $sidecar.Dispose() }
if ($failed.Count -ne 0) { throw "Isolated-candidate runner contract failed: $($failed.Count) checks. Evidence: $resultPath ($digest)" }
Write-Host "PASS: isolated-candidate runner contract $passed checks, $($skipped.Count) skipped; no build or product entrypoint ran. Evidence: $resultPath ($digest)"
