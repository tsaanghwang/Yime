param(
    [string]$SourceRoot,
    [string]$ExpectedRunnerResultSha256,
    [string]$OutputRoot,
    [string]$WorkerConfig
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$archiveBase = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Yime Rime-PIME Evidence Archives\DP1-S')).TrimEnd('\')
$candidateModulePath = Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.psm1'
$receiptModulePath = Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.psm1'
$resultSchema = 'yime-rime-pime-dp1s-off-repository-archive-result-v1'
$workerSchema = 'yime-rime-pime-dp1s-off-repository-archive-worker-v1'

function Get-Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileRecord([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [IO.File]::Exists($full)) { throw "Required file is missing: $full" }
    $bytes = [IO.File]::ReadAllBytes($full)
    return [pscustomobject][ordered]@{ path=$full;bytes=[long]$bytes.Length;sha256=Get-Sha256 $bytes }
}

function Copy-ArchiveSourceFile([string]$SourceBase,[string]$ProjectionBase,[string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('\') -or $RelativePath -match '(^|/)\.\.?(/|$)') {
        throw 'DP1-S source projection path is not canonical.'
    }
    $sourcePath = Assert-CanonicalContainedPath $SourceBase (Join-Path $SourceBase $RelativePath.Replace('/','\')) 'DP1-S source artifact'
    $destination = Assert-CanonicalContainedPath $ProjectionBase (Join-Path $ProjectionBase $RelativePath.Replace('/','\')) 'DP1-S projected artifact'
    $record = Get-FileRecord $sourcePath
    $parent = Split-Path -Parent $destination
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $bytes = [IO.File]::ReadAllBytes($sourcePath)
    $stream = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    return $record
}

function New-ArchiveSourceProjection([string]$SourceBase,[string]$ProjectionBase,[string]$ExpectedResult) {
    if ([IO.Directory]::Exists($ProjectionBase)) { throw 'DP1-S archive source projection must be fresh.' }
    [IO.Directory]::CreateDirectory($ProjectionBase) | Out-Null
    $runner = Copy-ArchiveSourceFile $SourceBase $ProjectionBase 'result.json'
    if ($runner.sha256 -cne $ExpectedResult) { throw 'DP1-S source runner result differs from the expected digest.' }
    $null = Copy-ArchiveSourceFile $SourceBase $ProjectionBase 'result.json.sha256'
    $value = Get-Content -Raw -LiteralPath (Join-Path $SourceBase 'result.json') | ConvertFrom-Json
    $primary = @(
        [string]$value.evidence.package_plan.path,
        [string]$value.evidence.build_result.path,
        [string]$value.evidence.build_manifest.path,
        [string]$value.evidence.postbuild_result.path,
        [string]$value.evidence.historical_v1_receipt.path,
        [string]$value.evidence.durable_v2_receipt.path
    )
    foreach ($relative in $primary) {
        $record = Copy-ArchiveSourceFile $SourceBase $ProjectionBase $relative
        $sidecarRelative = $relative+'.sha256'
        $sidecarSource = Join-Path $SourceBase $sidecarRelative.Replace('/','\')
        if ([IO.File]::Exists($sidecarSource)) {
            $null = Copy-ArchiveSourceFile $SourceBase $ProjectionBase $sidecarRelative
        } elseif ($relative -ceq [string]$value.evidence.build_manifest.path) {
            $sidecarDestination = Assert-CanonicalContainedPath $ProjectionBase `
                (Join-Path $ProjectionBase $sidecarRelative.Replace('/','\')) 'DP1-S derived build-manifest sidecar'
            $marker = [Text.Encoding]::ASCII.GetBytes($record.sha256+'  '+[IO.Path]::GetFileName($relative)+"`n")
            $stream = [IO.File]::Open($sidecarDestination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $stream.Write($marker,0,$marker.Length);$stream.Flush($true) } finally { $stream.Dispose() }
        } else {
            throw "DP1-S source evidence sidecar is missing: $relative"
        }
    }
    $null = Copy-ArchiveSourceFile $SourceBase $ProjectionBase ([string]$value.evidence.installer.path)
    $storeRoot = Join-Path $SourceBase 'repo\installer\receipt-evidence\sha256'
    if (-not [IO.Directory]::Exists($storeRoot)) { throw 'DP1-S retained evidence store is missing.' }
    foreach ($file in @(Get-ChildItem -LiteralPath $storeRoot -File -Recurse -Force)) {
        $relative = $file.FullName.Substring($SourceBase.Length+1).Replace('\','/')
        $null = Copy-ArchiveSourceFile $SourceBase $ProjectionBase $relative
    }
    return [pscustomobject][ordered]@{
        projection_root=$ProjectionBase
        derived_build_manifest_sidecar= -not [IO.File]::Exists((Join-Path $SourceBase ([string]$value.evidence.build_manifest.path+'.sha256').Replace('/','\')))
    }
}

function Write-SealedJsonCreateNew([string]$Path,$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $json = (ConvertTo-Json $Value -Depth 30 -Compress) + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $digest = Get-Sha256 $bytes
    $stream = [IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    $marker = [Text.Encoding]::ASCII.GetBytes($digest+'  '+[IO.Path]::GetFileName($full)+"`n")
    $sidecar = [IO.File]::Open($full+'.sha256',[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $sidecar.Write($marker,0,$marker.Length);$sidecar.Flush($true) } finally { $sidecar.Dispose() }
    return [pscustomobject][ordered]@{ path=$full;bytes=[long]$bytes.Length;sha256=$digest;sidecar_path=$full+'.sha256' }
}

function Assert-CanonicalContainedPath([string]$Root,[string]$Path,[string]$Context) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -ieq $rootFull -or -not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes its approved root."
    }
    return $full
}

function Get-GitWorktreeRoots {
    $lines = @(& git -C $workspaceRoot worktree list --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Git worktrees for the DP1-S boundary.' }
    $roots = @($lines | Where-Object { $_ -clike 'worktree *' } | ForEach-Object {
        [IO.Path]::GetFullPath($_.Substring(9)).TrimEnd('\')
    })
    if ($roots.Count -lt 1) { throw 'No Git worktree root was discovered.' }
    return $roots
}

function Assert-OutsideWorktrees([string]$Path,[string[]]$WorktreeRoots) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($root in $WorktreeRoots) {
        if ($full -ieq $root -or $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'DP1-S archive destination is inside a Git worktree.'
        }
    }
}

function Invoke-CapsuleRead([string]$ArchiveRoot) {
    $module = Import-Module -Name $candidateModulePath -Force -PassThru
    try {
        return & $module {
            param($Root)
            $context = [pscustomobject]@{
                case_root = Split-Path -Parent $Root
                source_root = Join-Path (Split-Path -Parent $Root) '.source-not-used'
                archive_root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
                lock_path = Join-Path (Split-Path -Parent $Root) '.rime-pime-dp1s-archive.lock'
            }
            return Read-RimePimeCandidateArchiveAtRoot $context $context.archive_root
        } $ArchiveRoot
    } finally { Remove-Module $module -Force }
}

function Invoke-Worker {
    $configPath = [IO.Path]::GetFullPath($WorkerConfig)
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if ([string]$config.schema_version -cne $workerSchema) { throw 'DP1-S worker configuration schema is invalid.' }
    $archiveRoot = [IO.Path]::GetFullPath([string]$config.archive_root).TrimEnd('\')
    $projectionRoot = [IO.Path]::GetFullPath([string]$config.projection_root).TrimEnd('\')
    $workerOutput = [IO.Path]::GetFullPath([string]$config.output_path)
    $projectionNonce = [string]$config.projection_nonce
    if ($projectionNonce -cnotmatch '^[0-9a-f]{32}$') { throw 'DP1-S worker projection nonce is invalid.' }
    if ([IO.Directory]::Exists($projectionRoot) -or [IO.File]::Exists($workerOutput) -or [IO.File]::Exists($workerOutput+'.sha256')) {
        throw 'DP1-S worker requires fresh projection and output paths.'
    }
    $status = Invoke-CapsuleRead $archiveRoot
    [IO.Directory]::CreateDirectory($projectionRoot) | Out-Null
    $projectionMarker = Join-Path $projectionRoot '.dp1s-archive-reconstruction'
    [IO.File]::WriteAllText($projectionMarker,$projectionNonce+"`n",[Text.Encoding]::ASCII)
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $archiveRoot 'manifest.json') | ConvertFrom-Json
    foreach ($row in @($manifest.artifacts)) {
        $relative = [string]$row.source_relative_path
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
            $relative.Contains('\') -or $relative -match '(^|/)\.\.?(/|$)') {
            throw 'DP1-S archive manifest contains a non-canonical projection path.'
        }
        $destination = Assert-CanonicalContainedPath $projectionRoot (Join-Path $projectionRoot $relative.Replace('/','\')) 'DP1-S projection path'
        $parent = Split-Path -Parent $destination
        if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        $object = Join-Path $archiveRoot ('objects\sha256\'+([string]$row.sha256).Substring(0,2)+'\'+[string]$row.sha256+'.blob')
        $bytes = [IO.File]::ReadAllBytes($object)
        if ([long]$bytes.Length -ne [long]$row.bytes -or (Get-Sha256 $bytes) -cne [string]$row.sha256) {
            throw 'DP1-S projection object differs from its manifest binding.'
        }
        $stream = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    }
    $repoProjection = Join-Path $projectionRoot 'repo'
    $receiptPath = Join-Path $projectionRoot ([string]$manifest.retained_receipt_path).Replace('/','\')
    $receiptModule = Import-Module -Name $receiptModulePath -Force -PassThru
    try {
        $receiptRead = Read-RimePimePackageBuildReceiptV2 -RepoRoot $repoProjection -ReceiptPath $receiptPath
        $receipt = $receiptRead.Receipt
    }
    finally { Remove-Module $receiptModule -Force }
    $installerPath = Join-Path $repoProjection ([string]$manifest.installer_path).Replace('/','\')
    $installer = Get-FileRecord $installerPath
    if ($installer.sha256 -cne [string]$manifest.installer_sha256 -or $installer.bytes -ne [long]$manifest.installer_bytes) {
        throw 'DP1-S reconstructed installer differs from the archive manifest.'
    }
    $sig = '[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetCurrentPackageFullName(ref uint len, System.Text.StringBuilder name);'
    Add-Type -MemberDefinition $sig -Name PackageProbe -Namespace YimeDp1SWorker
    [uint32]$length = 0
    $builder = New-Object Text.StringBuilder 1024
    $length = [uint32]$builder.Capacity
    $packageResult = [YimeDp1SWorker.PackageProbe]::GetCurrentPackageFullName([ref]$length,$builder)
    $result = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1s-source-independent-reopen-v1'
        powershell_edition=[string]$PSVersionTable.PSEdition
        powershell_version=$PSVersionTable.PSVersion.ToString()
        current_process_package_identity_absent=($packageResult -eq 15700)
        get_current_package_full_name_result=[int]$packageResult
        source_root_supplied_to_worker=$false
        source_independent_capsule_reopen_passed=$true
        strict_receipt_read_without_source=$true
        candidate_hash_verified_without_source=$true
        archive_id=[string]$status.archive_id
        manifest_sha256=[string]$status.manifest_sha256
        artifact_count=[int]$status.artifact_count
        product_version=[string]$receipt.product_version
        receipt_sha256=(Get-FileRecord $receiptPath).sha256
        installer_sha256=$installer.sha256
        installer_bytes=$installer.bytes
        installer_or_uninstaller_executed=$false
        registry_or_product_process_touched=$false
        installed_yimecore_local12_touched=$false
        production_user_data_read_or_written=$false
    }
    if ([IO.File]::ReadAllText($projectionMarker) -cne $projectionNonce+"`n") {
        throw 'DP1-S reconstructed projection ownership marker changed.'
    }
    [IO.Directory]::Delete($projectionRoot,$true)
    if ([IO.Directory]::Exists($projectionRoot)) { throw 'DP1-S worker could not remove its reconstructed projection.' }
    $null = Write-SealedJsonCreateNew $workerOutput $result
    return
}

if (-not [string]::IsNullOrWhiteSpace($WorkerConfig)) {
    Invoke-Worker
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SourceRoot) -or [string]::IsNullOrWhiteSpace($ExpectedRunnerResultSha256) -or
    [string]::IsNullOrWhiteSpace($OutputRoot)) {
    throw 'SourceRoot, ExpectedRunnerResultSha256 and OutputRoot are required.'
}
if ($ExpectedRunnerResultSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Expected runner result SHA-256 is invalid.' }

$source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$approvedSourceBase = Join-Path $workspaceRoot '.tmp\dual-product'
$null = Assert-CanonicalContainedPath $approvedSourceBase $source 'DP1-S source root'
if ((Split-Path -Leaf $source) -cnotmatch '^dp1-o-candidate-[A-Za-z0-9._-]+$' -or
    -not [IO.Directory]::Exists($source)) {
    throw 'DP1-S source must be an existing isolated DP1-O/P candidate root.'
}
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$null = Assert-CanonicalContainedPath (Join-Path $workspaceRoot '.tmp\dual-product') $output 'DP1-S output root'
if ([IO.Directory]::Exists($output)) { throw 'DP1-S output root must be fresh.' }
[IO.Directory]::CreateDirectory($output) | Out-Null

$worktrees = @(Get-GitWorktreeRoots)
Assert-OutsideWorktrees $archiveBase $worktrees
if (-not [IO.Directory]::Exists($archiveBase)) { [IO.Directory]::CreateDirectory($archiveBase) | Out-Null }
$archiveSource = Join-Path $output 'archive-source-projection'
$projectionInfo = New-ArchiveSourceProjection $source $archiveSource $ExpectedRunnerResultSha256

$candidateModule = Import-Module -Name $candidateModulePath -Force -PassThru
try {
    $published = & $candidateModule {
        param($Source,$Base,$Expected)
        foreach ($path in @($Base,(Split-Path -Parent $Base))) { Assert-RimePimeNoReparsePath $path }
        $context = [pscustomobject]@{
            case_root=$Base;source_root=$Source;archive_root='';lock_path=(Join-Path $Base '.rime-pime-dp1s-archive.lock')
        }
        $lock = Open-RimePimeCandidateArchiveLock $context
        try {
            $material = Get-RimePimeCandidateArchiveSourceMaterial $context $Expected
            $context.archive_root = Join-Path $Base ([string]$material.ArchiveId+'.capsule')
            if (Test-Path -LiteralPath $context.archive_root) {
                return Assert-RimePimeCandidateArchiveExpectedResult `
                    (Read-RimePimeCandidateArchiveAtRoot $context $context.archive_root) $Expected
            }
            $stages = @(Get-RimePimeCandidateArchiveStages $context)
            if ($stages.Count -gt 1) { throw 'DP1-S archive has multiple pending transaction stages.' }
            if ($stages.Count -eq 1) {
                $intent = Join-Path $stages[0] 'transactions\intent.json'
                if ((Test-Path -LiteralPath $intent -PathType Leaf) -and (Test-Path -LiteralPath ($intent+'.sha256') -PathType Leaf)) {
                    $state = Read-RimePimeCandidateArchiveIntentStage $context $stages[0]
                    if ([string]$state.Owner.runner_result_sha256 -cne $Expected) { throw 'DP1-S pending archive belongs to another candidate.' }
                    return Complete-RimePimeCandidateArchiveStage $context $stages[0]
                }
            }
            $stage = Initialize-RimePimeCandidateArchiveStage $context $material
            return Complete-RimePimeCandidateArchiveStage $context $stage
        } finally { $lock.Dispose() }
    } $archiveSource $archiveBase $ExpectedRunnerResultSha256
} finally { Remove-Module $candidateModule -Force }

$archiveRoot = [IO.Path]::GetFullPath([string]$published.archive_root).TrimEnd('\')
Assert-OutsideWorktrees $archiveRoot $worktrees
$projectionFull = Assert-CanonicalContainedPath $output $archiveSource 'DP1-S disposable source projection'
if (-not [IO.Directory]::Exists($projectionFull)) { throw 'DP1-S source projection disappeared before publication completed.' }
[IO.Directory]::Delete($projectionFull,$true)
if ([IO.Directory]::Exists($projectionFull)) { throw 'DP1-S source projection could not be removed before source-independent verification.' }
$sourceParent = Split-Path -Parent $source
$withheld = Join-Path $sourceParent ('.dp1s-source-withheld-'+[guid]::NewGuid().ToString('N'))
$null = Assert-CanonicalContainedPath $approvedSourceBase $withheld 'DP1-S withheld source path'
$verificationRoot = Join-Path $archiveBase 'verifications'
if (-not [IO.Directory]::Exists($verificationRoot)) { [IO.Directory]::CreateDirectory($verificationRoot) | Out-Null }
$ps5Output = Join-Path $verificationRoot ([string]$published.archive_id+'-ps5.json')
$ps7Output = Join-Path $verificationRoot ([string]$published.archive_id+'-ps7.json')
foreach ($path in @($ps5Output,$ps5Output+'.sha256',$ps7Output,$ps7Output+'.sha256')) {
    if ([IO.Directory]::Exists($path)) { throw 'DP1-S verification path is occupied by a directory.' }
}

function Invoke-ReopenProcess([string]$Shell,[string]$Name,[string]$ResultPath) {
    $hasResult = [IO.File]::Exists($ResultPath)
    $hasSidecar = [IO.File]::Exists($ResultPath+'.sha256')
    if ($hasResult -ne $hasSidecar) { throw "$Name archived verification is a partial JSON/sidecar pair." }
    if ($hasResult) {
        $sealed = Get-FileRecord $ResultPath
        $expected = $sealed.sha256+'  '+[IO.Path]::GetFileName($ResultPath)+"`n"
        if ([IO.File]::ReadAllText($ResultPath+'.sha256') -cne $expected) { throw "$Name archived verification sidecar is invalid." }
        $value = Get-Content -Raw -LiteralPath $ResultPath | ConvertFrom-Json
        if ([string]$value.archive_id -cne [string]$published.archive_id -or
            [string]$value.manifest_sha256 -cne [string]$published.manifest_sha256 -or
            -not [bool]$value.source_independent_capsule_reopen_passed -or
            -not [bool]$value.strict_receipt_read_without_source -or
            -not [bool]$value.candidate_hash_verified_without_source) {
            throw "$Name archived verification does not bind the current capsule."
        }
        return [pscustomobject][ordered]@{ path=$ResultPath;bytes=$sealed.bytes;sha256=$sealed.sha256;value=$value;reused=$true }
    }
    $configPath = Join-Path $output ($Name+'-worker.json')
    $projection = $source
    $projectionNonce = [guid]::NewGuid().ToString('N')
    $config = [pscustomobject][ordered]@{
        schema_version=$workerSchema;archive_root=$archiveRoot;projection_root=$projection
        projection_nonce=$projectionNonce;output_path=$ResultPath
    }
    [IO.File]::WriteAllText($configPath,((ConvertTo-Json $config -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    $stdoutPath = Join-Path $output ($Name+'-stdout.txt')
    $stderrPath = Join-Path $output ($Name+'-stderr.txt')
    $process = Start-Process -FilePath $Shell -ArgumentList @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-WorkerConfig',$configPath
    ) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        $errorText = if ([IO.File]::Exists($stderrPath)) { [IO.File]::ReadAllText($stderrPath).Trim() } else { '' }
        throw "$Name source-independent archive reopen failed with exit code $($process.ExitCode): $errorText"
    }
    if ([IO.Directory]::Exists($projection)) { throw "$Name left its reconstructed projection behind." }
    $sealed = Get-FileRecord $ResultPath
    $expected = $sealed.sha256+'  '+[IO.Path]::GetFileName($ResultPath)+"`n"
    if ([IO.File]::ReadAllText($ResultPath+'.sha256') -cne $expected) { throw "$Name result sidecar is invalid." }
    $value = Get-Content -Raw -LiteralPath $ResultPath | ConvertFrom-Json
    if (-not [bool]$value.source_independent_capsule_reopen_passed -or
        -not [bool]$value.strict_receipt_read_without_source -or
        -not [bool]$value.candidate_hash_verified_without_source) {
        throw "$Name did not complete the required source-independent checks."
    }
    return [pscustomobject][ordered]@{ path=$ResultPath;bytes=$sealed.bytes;sha256=$sealed.sha256;value=$value;reused=$false }
}

$sourceWasWithheld = $false
try {
    Move-Item -LiteralPath $source -Destination $withheld
    $sourceWasWithheld = $true
    if ([IO.Directory]::Exists($source)) { throw 'DP1-S source remained visible after withholding rename.' }
    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ps7 = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $verify5 = Invoke-ReopenProcess $ps5 'ps5' $ps5Output
    $verify7 = Invoke-ReopenProcess $ps7 'ps7' $ps7Output
} finally {
    if ($sourceWasWithheld) {
        if ([IO.Directory]::Exists($source)) {
            $marker = Join-Path $source '.dp1s-archive-reconstruction'
            $ownedNonces = @()
            foreach ($configPath in @(Get-ChildItem -LiteralPath $output -Filter '*-worker.json' -File -ErrorAction SilentlyContinue)) {
                try { $ownedNonces += [string](Get-Content -Raw -LiteralPath $configPath.FullName | ConvertFrom-Json).projection_nonce } catch {}
            }
            if (-not [IO.File]::Exists($marker) -or $ownedNonces -notcontains [IO.File]::ReadAllText($marker).Trim()) {
                throw 'DP1-S cannot safely remove an unowned path before restoring the withheld source.'
            }
            $ownedProjection = Assert-CanonicalContainedPath $approvedSourceBase $source 'DP1-S failed worker projection cleanup'
            [IO.Directory]::Delete($ownedProjection,$true)
        }
        Move-Item -LiteralPath $withheld -Destination $source
    }
}

$manifest = Get-FileRecord (Join-Path $archiveRoot 'manifest.json')
$final = [pscustomobject][ordered]@{
    schema_version=$resultSchema;generated_at_utc=(Get-Date).ToUniversalTime().ToString('o');affected_product='rime-pime'
    status='pass';archive_root=$archiveRoot;archive_id=[string]$published.archive_id
    archive_manifest_sha256=$manifest.sha256;archive_manifest_bytes=$manifest.bytes
    archived_object_count=[int]$published.artifact_count
    actual_archive_root_published=$true;actual_evidence_archived_outside_repository_tmp=$true
    outside_repository=$true;outside_outer_tmp=$true;outside_all_git_worktrees=$true
    source_temporarily_unavailable_during_reverification=$true
    fresh_process_reopen_ps5=$true;fresh_process_reopen_ps7=$true
    strict_receipt_read_ps5_without_source=$true;strict_receipt_read_ps7_without_source=$true
    candidate_hash_verified_without_source=$true
    ps5_verification=[pscustomobject][ordered]@{path=$verify5.path;bytes=$verify5.bytes;sha256=$verify5.sha256;powershell_version=[string]$verify5.value.powershell_version;current_process_package_identity_absent=[bool]$verify5.value.current_process_package_identity_absent;reused_existing=[bool]$verify5.reused}
    ps7_verification=[pscustomobject][ordered]@{path=$verify7.path;bytes=$verify7.bytes;sha256=$verify7.sha256;powershell_version=[string]$verify7.value.powershell_version;current_process_package_identity_absent=[bool]$verify7.value.current_process_package_identity_absent;reused_existing=[bool]$verify7.reused}
    system_visible_from_current_nonpackaged_child_processes=([bool]$verify5.value.current_process_package_identity_absent -and [bool]$verify7.value.current_process_package_identity_absent)
    child_processes_have_packaged_codex_ancestor=$true
    explorer_launched_independent_reopen_verified=$false
    inner_capsule_preserves_fixture_protocol_markers=$true
    source_projection_derived_missing_build_manifest_sidecar=[bool]$projectionInfo.derived_build_manifest_sidecar
    source_candidate_bytes_changed=$false
    directory_metadata_durability_verified=$false;hardware_power_loss_verified=$false
    active_hostile_same_sid_physical_replacement_prevented=$false
    actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
    installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_read_or_written=$false
    dp1_s_complete_for_current_process_and_static_scope=$true
    dp1_complete=$false;dp2_complete=$false;dp3_complete=$false
}
$null = Write-SealedJsonCreateNew (Join-Path $output 'result.json') $final
$final | ConvertTo-Json -Depth 10
