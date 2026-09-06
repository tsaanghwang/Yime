[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$OutputRoot,
    [string]$PowerShellPath = (Get-Process -Id $PID).Path,
    [string]$MakensisPath = 'C:\Program Files (x86)\NSIS\Bin\makensis.exe',
    [string]$GitPath = 'git.exe'
)

$ErrorActionPreference = 'Stop'

function Assert-NoReparsePath([string]$Path) {
    for ($cursor = [IO.Path]::GetFullPath($Path); $cursor; $cursor = Split-Path -Parent $cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Path traverses a reparse point: $cursor"
        }
        if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
    }
}

function Assert-PlainFile([string]$Path, [string]$Context) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Context is missing: $full" }
    Assert-NoReparsePath $full
    $item = Get-Item -LiteralPath $full -Force
    if ([string]$item.LinkType -ceq 'HardLink') { throw "$Context is hard-linked: $full" }
    $streams = @(Get-Item -LiteralPath $full -Stream * -Force)
    if ($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA') {
        throw "$Context has an alternate data stream: $full"
    }
    return $full
}

function Assert-ToolApplicationFile([string]$Path, [string]$Context) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Context is missing: $full" }
    Assert-NoReparsePath $full
    $streams = @(Get-Item -LiteralPath $full -Stream * -Force)
    if ($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA') {
        throw "$Context has an alternate data stream: $full"
    }
    return $full
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-CompactJson($Value) {
    return (ConvertTo-Json -InputObject $Value -Depth 100 -Compress)
}

function Get-RelativePath([string]$Base, [string]$Path) {
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($baseFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected root: $full"
    }
    return $full.Substring($baseFull.Length + 1).Replace('\', '/')
}

function Get-FileSnapshot([string]$Path, [string]$RelativePath) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) {
        return [pscustomobject][ordered]@{ path = $RelativePath; kind = 'absent'; bytes = 0; sha256 = '' }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        return [pscustomobject][ordered]@{ path = $RelativePath; kind = 'unexpected-non-file'; bytes = 0; sha256 = '' }
    }
    $null = Assert-PlainFile $full $RelativePath
    $item = Get-Item -LiteralPath $full -Force
    return [pscustomobject][ordered]@{
        path = $RelativePath; kind = 'file'; bytes = [long]$item.Length; sha256 = Get-Sha256 $full
    }
}

function Get-DirectorySnapshot([string]$Path, [string]$RelativePath) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full)) {
        $records = @()
        $present = $false
    } elseif (-not (Test-Path -LiteralPath $full -PathType Container)) {
        $records = @([pscustomobject][ordered]@{ path = '.'; kind = 'unexpected-non-directory'; bytes = 0; sha256 = '' })
        $present = $true
    } else {
        Assert-NoReparsePath $full
        $records = @(
            Get-ChildItem -LiteralPath $full -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($full.Length + 1).Replace('\', '/')
                if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Protected tree contains a reparse point: $($_.FullName)"
                }
                if ($_.PSIsContainer) {
                    [pscustomobject][ordered]@{ path = $relative; kind = 'directory'; bytes = 0; sha256 = '' }
                } else {
                    $null = Assert-PlainFile $_.FullName "protected tree file $relative"
                    [pscustomobject][ordered]@{
                        path = $relative; kind = 'file'; bytes = [long]$_.Length; sha256 = Get-Sha256 $_.FullName
                    }
                }
            }
        )
        $present = $true
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-CompactJson @($records)))
    return [pscustomobject][ordered]@{
        path = $RelativePath; present = $present; entry_count = [int]$records.Count
        tree_sha256 = Get-Sha256Bytes $bytes
    }
}

function Get-GitOutput([string[]]$Arguments, [string]$Context) {
    $output = @(& $GitPath @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "$Context failed with exit code $exitCode." }
    return @($output)
}

function Get-ProtectedSnapshot([string]$Root) {
    $installerRoot = Join-Path $Root 'installer'
    $canonical = @(
        Get-FileSnapshot (Join-Path $installerRoot 'package-build-receipt.json') 'installer/package-build-receipt.json'
        Get-FileSnapshot (Join-Path $installerRoot 'package-build-receipt.json.sha256') 'installer/package-build-receipt.json.sha256'
    )
    $installers = @(
        if (Test-Path -LiteralPath $installerRoot -PathType Container) {
            Get-ChildItem -LiteralPath $installerRoot -File -Filter 'YIME-*-setup.exe' | Sort-Object Name | ForEach-Object {
                Get-FileSnapshot $_.FullName ('installer/' + $_.Name)
            }
        }
    )
    $dirtyPaths = @(
        'docs/YIMECORE_L5_DAILY_USE_TEST_LOG.md',
        'tools/yimecore/get-l5-daily-use-baseline.ps1',
        'docs/YIMECORE_LOCAL12_L5_FINAL_CONFIRMATION_2026-09-06.md'
    )
    $dirty = @($dirtyPaths | ForEach-Object { Get-FileSnapshot (Join-Path $Root $_.Replace('/', '\')) $_ })
    $status = @(Get-GitOutput @('-C', $Root, 'status', '--porcelain=v1', '--untracked-files=all') 'Source status inspection')
    $statusBytes = [Text.UTF8Encoding]::new($false).GetBytes(($status -join "`n"))
    $head = ((Get-GitOutput @('-C', $Root, 'rev-parse', '--verify', 'HEAD') 'Source HEAD inspection') -join '').Trim().ToLowerInvariant()
    return [pscustomobject][ordered]@{
        head = $head
        git_status_entry_count = [int]$status.Count
        git_status_sha256 = Get-Sha256Bytes $statusBytes
        canonical_pair = $canonical
        installer_set = $installers
        receipt_evidence = Get-DirectorySnapshot (Join-Path $installerRoot 'receipt-evidence') 'installer/receipt-evidence'
        protected_user_worktree_files = $dirty
    }
}

function Test-SnapshotEqual($Before, $After) {
    return (ConvertTo-CompactJson $Before) -ceq (ConvertTo-CompactJson $After)
}

$commandResults = [Collections.Generic.List[object]]::new()
function Invoke-RecordedProcess([string]$Name, [string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
    $started = [DateTime]::UtcNow
    $exitCode = -1
    try {
        Push-Location $WorkingDirectory
        try {
            & $FilePath @Arguments
            $exitCode = [int]$LASTEXITCODE
        } finally { Pop-Location }
    } finally {
        $commandResults.Add([pscustomobject][ordered]@{
            name = $Name; executable = [IO.Path]::GetFileName($FilePath); exit_code = $exitCode
            started_at_utc = $started.ToString('o'); completed_at_utc = [DateTime]::UtcNow.ToString('o')
        })
    }
    if ($exitCode -ne 0) { throw "$Name failed with exit code $exitCode." }
}

function Read-SealedJson([string]$Path, [string]$Context) {
    $full = Assert-PlainFile $Path "$Context JSON"
    $sidecar = Assert-PlainFile ($full + '.sha256') "$Context sidecar"
    $digest = Get-Sha256 $full
    $markerBytes = [IO.File]::ReadAllBytes($sidecar)
    foreach ($one in $markerBytes) { if ($one -gt 127) { throw "$Context sidecar is not ASCII." } }
    $marker = [Text.Encoding]::ASCII.GetString($markerBytes)
    $name = [regex]::Escape([IO.Path]::GetFileName($full))
    if ($marker -cnotmatch ('\A' + $digest + '  ' + $name + '(?:\r\n|\n)?\z')) {
        throw "$Context sidecar does not bind the exact JSON bytes."
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $text = $utf8.GetString([IO.File]::ReadAllBytes($full)) }
    catch { throw "$Context is not strict UTF-8." }
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $value = $text | ConvertFrom-Json -DateKind String }
        else { $value = $text | ConvertFrom-Json }
    } catch { throw "$Context is not JSON: $($_.Exception.Message)" }
    return [pscustomobject]@{ Path = $full; Sidecar = $sidecar; Digest = $digest; Value = $value }
}

function Write-SealedResult([string]$Path, $Value) {
    $json = (ConvertTo-CompactJson $Value) + "`n"
    $encoding = [Text.UTF8Encoding]::new($false)
    $jsonBytes = $encoding.GetBytes($json)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($jsonBytes, 0, $jsonBytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    $digest = Get-Sha256 $Path
    $sidecarBytes = [Text.Encoding]::ASCII.GetBytes("$digest  $([IO.Path]::GetFileName($Path))`n")
    $sidecar = [IO.File]::Open($Path + '.sha256', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $sidecar.Write($sidecarBytes, 0, $sidecarBytes.Length); $sidecar.Flush($true) }
    finally { $sidecar.Dispose() }
    return $digest
}

$root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Repository root is missing: $root" }
Assert-NoReparsePath $root
$gitCommand = @(Get-Command -Name $GitPath -CommandType Application -ErrorAction Stop)[0]
$GitPath = Assert-ToolApplicationFile $gitCommand.Source 'Git client'
$gitDirectory = ((Get-GitOutput @('-C', $root, 'rev-parse', '--absolute-git-dir') 'Repository identity inspection') -join '').Trim()
if ([string]::IsNullOrWhiteSpace($gitDirectory)) { throw 'RepoRoot is not a Git worktree.' }
$head = ((Get-GitOutput @('-C', $root, 'rev-parse', '--verify', 'HEAD^{commit}') 'Exact source commit inspection') -join '').Trim().ToLowerInvariant()
$headTree = ((Get-GitOutput @('-C', $root, 'rev-parse', '--verify', 'HEAD^{tree}') 'Exact source tree inspection') -join '').Trim().ToLowerInvariant()
if ($head -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or $headTree -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$') {
    throw 'Source HEAD or tree is not a full Git object identity.'
}

$workParent = Join-Path $root '.tmp\dual-product'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $workParent ('dp1-o-candidate-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $output) -ine $workParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-o-candidate-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-o-candidate-* directory.'
}
$runnerRelativePath = 'tools/dual-product/run-rime-pime-isolated-candidate.ps1'
$runnerExpectedPath = [IO.Path]::GetFullPath((Join-Path $root $runnerRelativePath.Replace('/', '\')))
$runnerPath = [IO.Path]::GetFullPath($PSCommandPath)
if ($runnerPath -ine $runnerExpectedPath) { throw 'Runner must execute from its tracked repository path.' }
$runnerHeadBlob = ((Get-GitOutput @('-C', $root, 'rev-parse', '--verify', ($head + ':' + $runnerRelativePath)) `
    'Runner HEAD blob inspection') -join '').Trim().ToLowerInvariant()
$runnerWorktreeBlob = ((Get-GitOutput @('-C', $root, 'hash-object', ('--path=' + $runnerRelativePath), '--', $runnerPath) `
    'Runner worktree blob inspection') -join '').Trim().ToLowerInvariant()
if ($runnerHeadBlob -cnotmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$' -or $runnerWorktreeBlob -cne $runnerHeadBlob) {
    throw 'Runner file differs from exact source HEAD.'
}
$null = Assert-PlainFile $PowerShellPath 'PowerShell host'
$null = Assert-PlainFile $MakensisPath 'NSIS compiler'
$protectedBefore = Get-ProtectedSnapshot $root
if ([string]$protectedBefore.head -cne $head) { throw 'Source HEAD changed before isolated output creation.' }
$headVersion = ((Get-GitOutput @('-C', $root, 'show', ($head + ':version.txt')) 'HEAD version inspection') -join '').Trim()
if ([string]::IsNullOrWhiteSpace($headVersion)) { throw 'Exact source HEAD has no product version.' }
$actualCanonicalInstallerLeaf = ''
$actualCanonicalVersion = ''
$actualCanonicalPath = Join-Path $root 'installer\package-build-receipt.json'
if (Test-Path -LiteralPath $actualCanonicalPath -PathType Leaf) {
    $actualCanonical = Read-SealedJson $actualCanonicalPath 'actual canonical receipt'
    $actualCanonicalVersion = [string]$actualCanonical.Value.product_version
    $actualInstallerPath = if ($null -ne $actualCanonical.Value.PSObject.Properties['installer']) {
        [string]$actualCanonical.Value.installer.path
    } else { [string]$actualCanonical.Value.installer_path }
    $actualCanonicalInstallerLeaf = [IO.Path]::GetFileName($actualInstallerPath.Replace('/', '\'))
    if ([string]::IsNullOrWhiteSpace($actualCanonicalInstallerLeaf)) {
        throw 'Actual canonical receipt has no installer leaf identity.'
    }
}

if (-not (Test-Path -LiteralPath $workParent)) { New-Item -ItemType Directory -Path $workParent -Force | Out-Null }
Assert-NoReparsePath $workParent
New-Item -ItemType Directory -Path $output | Out-Null
Assert-NoReparsePath $output

$clone = Join-Path $output 'repo'
$resultPath = Join-Path $output 'result.json'
$failure = $null
$summary = $null
$protectedAfter = $null
$environmentNames = @(
    'YIME_SIGN_CERT_SHA1', 'YIME_RELEASE_SIGNING_REQUIRED', 'YIME_SIGNTOOL_EXE', 'YIME_TIMESTAMP_URL',
    'GITHUB_SHA', 'GITHUB_REF'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    foreach ($name in @('YIME_SIGN_CERT_SHA1', 'YIME_RELEASE_SIGNING_REQUIRED', 'YIME_SIGNTOOL_EXE', 'YIME_TIMESTAMP_URL')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    Invoke-RecordedProcess 'clone-exact-head' $GitPath @(
        'clone', '--local', '--no-hardlinks', '--no-checkout', '--no-tags', '--', $root, $clone
    ) $root
    Invoke-RecordedProcess 'checkout-detached-head' $GitPath @(
        '-C', $clone, 'checkout', '--detach', $head
    ) $root
    Assert-NoReparsePath $clone
    $cloneHead = ((Get-GitOutput @('-C', $clone, 'rev-parse', '--verify', 'HEAD^{commit}') 'Clone HEAD inspection') -join '').Trim().ToLowerInvariant()
    $cloneTree = ((Get-GitOutput @('-C', $clone, 'rev-parse', '--verify', 'HEAD^{tree}') 'Clone tree inspection') -join '').Trim().ToLowerInvariant()
    $cloneStatus = @(Get-GitOutput @('-C', $clone, 'status', '--porcelain=v1', '--untracked-files=all') 'Clone cleanliness inspection')
    if ($cloneHead -cne $head -or $cloneTree -cne $headTree -or $cloneStatus.Count -ne 0) {
        throw 'Detached clone is not the exact clean source HEAD.'
    }
    foreach ($path in @(
        'installer\package-build-receipt.json', 'installer\package-build-receipt.json.sha256',
        'installer\build-manifest.json', 'installer\receipt-evidence'
    )) {
        if (Test-Path -LiteralPath (Join-Path $clone $path)) { throw "Ignored actual publication state entered the clone: $path" }
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $clone 'installer') -File -Filter 'YIME-*-setup.exe').Count -ne 0) {
        throw 'An ignored actual installer entered the clone.'
    }

    Invoke-RecordedProcess 'build-current-source' $env:ComSpec @('/D', '/C', 'build.bat') $clone
    $planPath = Join-Path $clone 'installer\package-plan.json'
    Invoke-RecordedProcess 'seal-package-plan' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\dual-product\rime-pime-package-plan.ps1'),
        '-WritePlan', '-PlanRepoRoot', $clone, '-OutputPlanPath', $planPath
    ) $clone
    $buildRoot = Join-Path $clone ('.tmp\dual-product\dp1-package-build-stage-' + [Guid]::NewGuid().ToString('N'))
    Invoke-RecordedProcess 'build-disabled-installer' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\build-rime-pime-installer.ps1'),
        '-RepoRoot', $clone, '-PackagePlanPath', $planPath, '-MakensisPath', $MakensisPath,
        '-BuildEvidenceRoot', $buildRoot
    ) $clone

    $buildResult = Read-SealedJson (Join-Path $buildRoot 'evidence\build-result.json') 'build result'
    if ([string]$buildResult.Value.schema_version -cne 'yime-rime-pime-staged-nsis-build-result-membership-interval-v1') {
        throw 'Builder did not emit current membership-interval evidence.'
    }
    $interval = $buildResult.Value.nsis_compiler_membership_interval
    if ([string]$interval.schema_version -cne 'yime-rime-pime-nsis-compiler-membership-interval-v1' -or
        -not [bool]$interval.armed_before_baseline -or
        -not [bool]$interval.completion_barrier_after_compiler_exit -or
        [long]$interval.unexpected_membership_event_count -ne 0 -or
        [bool]$interval.physical_membership_prevention_claimed -or
        [bool]$interval.active_same_sid_transient_tree_membership_interference_excluded -or
        [bool]$interval.nsis_non_os_compiler_input_closure -or
        [bool]$interval.full_nsis_toolchain_input_closure) {
        throw 'Builder membership interval is incomplete or overclaims its boundary.'
    }
    if ([int]$buildResult.Value.package_plan_artifact_count -ne 20 -or
        [int]$buildResult.Value.package_plan_matching_stage_binding_count -ne 22 -or
        -not [bool]$buildResult.Value.staged_pe_architecture_verified_under_read_leases) {
        throw 'Builder did not preserve the reviewed x86/x64 package-plan bindings.'
    }
    $installerPath = [IO.Path]::GetFullPath([string]$buildResult.Value.published_installer_path)
    if ((Split-Path -Parent $installerPath) -ine (Join-Path $clone 'installer') -or
        [string]$buildResult.Value.package_build_receipt_path -ine (Join-Path $clone 'installer\package-build-receipt.json')) {
        throw 'Build result published outside the isolated canonical paths.'
    }
    $null = Assert-PlainFile $installerPath 'isolated disabled installer'
    $canonicalReceipt = Join-Path $clone 'installer\package-build-receipt.json'
    $v1Receipt = Read-SealedJson $canonicalReceipt 'interim v1 receipt'
    if ([string]$v1Receipt.Value.schema_version -cne 'yime-rime-pime-package-build-receipt-v1') {
        throw 'Builder did not publish an interim v1 receipt.'
    }

    $postBuildCloneStatus = @(Get-GitOutput @('-C', $clone, 'status', '--porcelain=v1', '--untracked-files=all') 'Post-build clone inspection')
    if ($postBuildCloneStatus.Count -ne 0) { throw 'Build changed tracked or non-ignored source in the isolated clone.' }
    $manifestRef = 'refs/heads/dp1-o-isolated-head'
    [Environment]::SetEnvironmentVariable('GITHUB_SHA', $head, 'Process')
    [Environment]::SetEnvironmentVariable('GITHUB_REF', $manifestRef, 'Process')
    $manifestPath = Join-Path $clone 'installer\build-manifest.json'
    Invoke-RecordedProcess 'write-build-manifest' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\write-build-manifest.ps1'),
        '-RepoRoot', $clone, '-OutputPath', $manifestPath, '-PackagePlanPath', $planPath, '-ReceiptPath', $canonicalReceipt
    ) $clone
    Invoke-RecordedProcess 'static-installer-manifest-check' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\test-installer-smoke.ps1'),
        '-InstallerPath', $installerPath, '-RepoRoot', $clone, '-StaticOnly', '-ExpectedCommit', $head,
        '-ExpectedRef', $manifestRef, '-ExpectedSignedRelease', 'false', '-ExpectedSourceTreeDirty', 'false',
        '-PackagePlanPath', $planPath, '-ReceiptPath', $canonicalReceipt
    ) $clone

    $manifestRecord = Get-Item -LiteralPath $manifestPath
    $contentManifestPath = Join-Path $buildRoot 'evidence\package-stage-content.json'
    $contentManifest = Read-SealedJson $contentManifestPath 'copied-content manifest'
    $payloadNshPath = Join-Path $buildRoot 'evidence\payload-files.nsh'
    $payloadReceiptPath = Join-Path $buildRoot 'evidence\payload-files-receipt.json'
    $payloadReceipt = Read-SealedJson $payloadReceiptPath 'payload include receipt'
    $postbuildRoot = Join-Path $clone ('.tmp\dual-product\dp1-postbuild-extraction-' + [Guid]::NewGuid().ToString('N'))
    Invoke-RecordedProcess 'static-postbuild-extraction' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\dual-product\run-rime-pime-postbuild-extraction.ps1'),
        '-OutputRoot', $postbuildRoot, '-StageRoot', (Join-Path $buildRoot 'stage'),
        '-ContentManifestPath', $contentManifestPath, '-ExpectedContentManifestDigest', $contentManifest.Digest,
        '-PayloadNshReceiptPath', $payloadReceiptPath, '-ExpectedPayloadNshReceiptDigest', $payloadReceipt.Digest,
        '-InstallerPath', $installerPath, '-PackagePlanPath', $planPath
    ) $clone
    $postbuildResult = Read-SealedJson (Join-Path $postbuildRoot 'evidence\result.json') 'postbuild result'
    if ([string]$postbuildResult.Value.schema_version -cne 'yime-rime-pime-postbuild-extraction-v1' -or
        [int]$postbuildResult.Value.installer_archive.entry_count -ne 181 -or
        [int]$postbuildResult.Value.uninstaller_archive.entry_count -ne 11 -or
        -not [bool]$postbuildResult.Value.installer_archive_listing_exact -or
        -not [bool]$postbuildResult.Value.nested_uninstaller_archive_listing_exact -or
        -not [bool]$postbuildResult.Value.archive_content_origin_proven -or
        [bool]$postbuildResult.Value.actual_installer_or_uninstaller_executed -or
        [bool]$postbuildResult.Value.generated_uninstaller_verified -or
        [bool]$postbuildResult.Value.generated_uninstaller_trusted -or
        [bool]$postbuildResult.Value.final_payload_closure -or
        [bool]$postbuildResult.Value.delivery_admitted) {
        throw 'Static postbuild evidence is incomplete or overclaims trust or delivery.'
    }

    $receiptV2Root = Join-Path $clone ('.tmp\dual-product\dp1-package-receipt-v2-' + [Guid]::NewGuid().ToString('N'))
    Invoke-RecordedProcess 'finalize-canonical-receipt-v2' $PowerShellPath @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $clone 'tools\dual-product\finalize-rime-pime-package-receipt-v2.ps1'),
        '-RepoRoot', $clone, '-BuildReceiptV1Path', $canonicalReceipt, '-BuildResultPath', $buildResult.Path,
        '-ContentManifestPath', $contentManifestPath, '-PayloadNshPath', $payloadNshPath,
        '-PayloadNshReceiptPath', $payloadReceiptPath, '-PostbuildResultPath', $postbuildResult.Path,
        '-OutputRoot', $receiptV2Root, '-PublishCanonical'
    ) $clone

    $receiptModule = Join-Path $clone 'tools\dual-product\rime-pime-package-receipt-v2.psm1'
    Import-Module -Name $receiptModule -Force
    try {
        $publishedV2 = Read-RimePimePackageBuildReceiptV2 -RepoRoot $clone -ReceiptPath $canonicalReceipt
        $historicalV1 = Join-Path $receiptV2Root 'historical\package-build-receipt-v1.json'
        $retainedV2 = Publish-RimePimePackageReceiptV2Supersession -RepoRoot $clone -ReceiptPath $canonicalReceipt `
            -ExpectedPreviousDigest $publishedV2.Digest -HistoricalV1Path $historicalV1
        $strictV2 = Read-RimePimePackageBuildReceiptV2 -RepoRoot $clone -ReceiptPath $canonicalReceipt
    } finally { Remove-Module -Name rime-pime-package-receipt-v2 -Force -ErrorAction SilentlyContinue }
    if (-not [bool]$strictV2.Receipt.evidence_artifacts_durable -or $strictV2.Digest -cne $retainedV2.Digest -or
        [bool]$strictV2.Receipt.delivery_admitted -or [bool]$strictV2.Receipt.installer_executed -or
        [bool]$strictV2.Receipt.uninstaller_executed) {
        throw 'Retention-only conversion did not produce a durable strict disabled receipt.'
    }

    $cloneVersion = [string]$strictV2.Receipt.product_version
    if ($cloneVersion -cne $headVersion) { throw 'Built clone version differs from exact HEAD version.txt.' }
    $cloneInstallerLeaf = [IO.Path]::GetFileName($installerPath)
    $distinctVersionedInstallerLeaf = -not [string]::IsNullOrWhiteSpace($actualCanonicalInstallerLeaf) -and
        $cloneInstallerLeaf -cne $actualCanonicalInstallerLeaf

    $summary = [pscustomobject][ordered]@{
        clone_path = Get-RelativePath $output $clone
        source_head = $head; source_tree = $headTree
        clone_current_version = $cloneVersion
        actual_canonical_product_version = $actualCanonicalVersion
        actual_canonical_installer_leaf = $actualCanonicalInstallerLeaf
        distinct_versioned_installer_leaf_for_dp1n = [bool]$distinctVersionedInstallerLeaf
        package_plan = [pscustomobject][ordered]@{ path = Get-RelativePath $output $planPath; sha256 = [string]$strictV2.Receipt.package_plan.sha256 }
        build_result = [pscustomobject][ordered]@{ path = Get-RelativePath $output $buildResult.Path; sha256 = $buildResult.Digest; schema_version = [string]$buildResult.Value.schema_version }
        build_manifest = [pscustomobject][ordered]@{ path = Get-RelativePath $output $manifestPath; bytes = [long]$manifestRecord.Length; sha256 = Get-Sha256 $manifestPath; static_only_passed = $true }
        postbuild_result = [pscustomobject][ordered]@{
            path = Get-RelativePath $output $postbuildResult.Path; sha256 = $postbuildResult.Digest
            schema_version = [string]$postbuildResult.Value.schema_version
            installer_archive_entry_count = [int]$postbuildResult.Value.installer_archive.entry_count
            nested_uninstaller_archive_entry_count = [int]$postbuildResult.Value.uninstaller_archive.entry_count
            generated_uninstaller_sha256 = [string]$postbuildResult.Value.generated_uninstaller.sha256
        }
        installer = [pscustomobject][ordered]@{
            path = Get-RelativePath $output $installerPath; bytes = [long]$strictV2.Receipt.installer.bytes
            sha256 = [string]$strictV2.Receipt.installer.sha256; unsigned_disabled = $true
        }
        historical_v1_receipt = [pscustomobject][ordered]@{ path = Get-RelativePath $output $historicalV1; sha256 = [string]$strictV2.Receipt.predecessor_v1.sha256 }
        durable_v2_receipt = [pscustomobject][ordered]@{
            path = Get-RelativePath $output $canonicalReceipt; sha256 = $strictV2.Digest
            schema_version = [string]$strictV2.Receipt.schema_version; evidence_artifacts_durable = $true
            durability_scope = 'isolated-clone-content-addressed-process-interruption-protocol'
        }
    }
} catch {
    $failure = $_
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    try { $protectedAfter = Get-ProtectedSnapshot $root }
    catch { if ($null -eq $failure) { $failure = $_ } }
}

$sourceUnchanged = $null -ne $protectedAfter -and (Test-SnapshotEqual $protectedBefore $protectedAfter)
if (-not $sourceUnchanged -and $null -eq $failure) {
    $failure = [Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Protected actual repository state changed during isolated candidate work.'),
        'ProtectedStateChanged', [Management.Automation.ErrorCategory]::InvalidData, $root)
}
$passed = $null -eq $failure
$result = [pscustomobject][ordered]@{
    schema_version = 'yime-rime-pime-isolated-candidate-result-v1'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    status = if ($passed) { 'pass' } else { 'fail' }
    source = [pscustomobject][ordered]@{
        repo_root = $root; exact_head = $head; exact_tree = $headTree
        runner_relative_path = $runnerRelativePath; runner_head_blob = $runnerHeadBlob
        runner_worktree_blob = $runnerWorktreeBlob; runner_matches_exact_head = $true
        clone_detached_exact_head = [bool]($null -ne $summary)
        actual_protected_snapshot_unchanged = [bool]$sourceUnchanged
        before_snapshot_sha256 = Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-CompactJson $protectedBefore)))
        after_snapshot_sha256 = if ($null -ne $protectedAfter) { Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-CompactJson $protectedAfter))) } else { '' }
    }
    commands = @($commandResults)
    evidence = $summary
    failure = if ($passed) { $null } else { [pscustomobject][ordered]@{ phase = if ($commandResults.Count) { $commandResults[$commandResults.Count - 1].name } else { 'preflight' }; message = [string]$failure.Exception.Message } }
    boundaries = [pscustomobject][ordered]@{
        installer_executed = $false; uninstaller_executed = $false; signing_process_executed = $false
        installed_product_processes_touched = $false; product_registry_mutated = $false
        default_input_method_changed = $false; production_user_data_read_or_written = $false
        installed_yimecore_local12_touched = $false; actual_canonical_migrated = $false
        actual_canonical_migration_admitted = $false
        actual_installer_published = $false; real_installer_transaction_adapter_wired = $false
        release_signing_complete = $false; delivery_admitted = $false
        hardware_power_loss_durability_verified = $false
        directory_metadata_durability_verified = $false
        outer_tmp_retention_guaranteed = $false
        evidence_archived_outside_tmp = $false
        active_same_sid_physical_replacement_prevented = $false
        full_nsis_toolchain_input_closure = $false
    }
}
$resultDigest = Write-SealedResult $resultPath $result
if (-not $passed) { throw "Isolated candidate run failed; sealed outcome: $resultPath ($resultDigest). $($failure.Exception.Message)" }
Write-Host "PASS: exact-HEAD isolated x86/x64 candidate build, StaticOnly, postbuild extraction, v2 finalization and retention-only strict read completed; no product code was executed. Evidence: $resultPath ($resultDigest)"
