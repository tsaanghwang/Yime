param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'installer\build-manifest.json'),
    [string]$PackagePlanPath,
    [string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'version.txt') -Raw).Trim()
$headCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headCommit)) {
    throw 'Cannot resolve the manifest source HEAD commit.'
}
$commit = if ($env:GITHUB_SHA) { $env:GITHUB_SHA.Trim() } else { $headCommit }
if (-not [string]::Equals($commit,$headCommit,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Requested manifest commit does not match the checked-out source HEAD.'
}
$ref = if ($env:GITHUB_REF) { $env:GITHUB_REF } else { (& git -C $repoRoot branch --show-current).Trim() }
$sourceStatus = @(& git -C $repoRoot status --porcelain=v1 --untracked-files=all 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine whether the manifest source tree is dirty.' }
$sourceTreeDirty = $sourceStatus.Count -gt 0

$packageModule=Join-Path $PSScriptRoot 'dual-product\rime-pime-package-plan.ps1'
. $packageModule
if (-not $PackagePlanPath) { $PackagePlanPath=Join-Path $repoRoot 'installer\package-plan.json' }
if (-not $ReceiptPath) { $ReceiptPath=Join-Path $repoRoot 'installer\package-build-receipt.json' }
$package=Read-RimePimePackagePlan -RepoRoot $repoRoot -PlanPath $PackagePlanPath -VerifyArtifacts
$receipt=Read-RimePimePackageBuildReceipt -Package $package -ReceiptPath $ReceiptPath
$relativePlan=$package.Path.Substring($repoRoot.TrimEnd('\').Length+1).Replace('\','/')
$relativePlanSidecar=$package.Sidecar.Substring($repoRoot.TrimEnd('\').Length+1).Replace('\','/')
$relativeReceipt=$receipt.Path.Substring($repoRoot.TrimEnd('\').Length+1).Replace('\','/')
$relativeReceiptSidecar=$receipt.Sidecar.Substring($repoRoot.TrimEnd('\').Length+1).Replace('\','/')
$patterns=@($package.Plan.artifacts | ForEach-Object { $_.path })+@(
    $relativePlan,$relativePlanSidecar,$relativeReceipt,$relativeReceiptSidecar,
    [string]$receipt.Receipt.installer_path)
$files = [Collections.Generic.List[object]]::new()
foreach ($pattern in $patterns) {
    $file=Get-Item -LiteralPath (Join-Path $repoRoot $pattern.Replace('/','\')) -ErrorAction Stop
    $relative=$file.FullName.Substring($repoRoot.TrimEnd('\').Length+1).Replace('\','/')
    if ($files.path -contains $relative) { throw "Duplicate package-plan/receipt manifest input: $relative" }
    $files.Add([pscustomobject]@{
        path=$relative
        size=[long]$file.Length
        sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    })
}
$manifest = [ordered]@{
    schemaVersion = 3
    product = 'YIME'
    version = $version
    commit = $commit
    ref = $ref
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    signedRelease = [bool]($env:YIME_RELEASE_SIGNING_REQUIRED -eq '1')
    sourceIdentity = [ordered]@{
        kind = if ($sourceTreeDirty) { 'working-tree' } else { 'git-commit' }
        treeDirty = [bool]$sourceTreeDirty
        commitIsCompleteSourceIdentity = [bool](-not $sourceTreeDirty)
    }
    packagePlan = [ordered]@{
        path=$relativePlan
        sha256=$package.Digest
        closureScope='declared-packaged-product-pe-inputs-only-not-installed-payload'
        architectures=@($package.Plan.architectures)
        receiptPath=$relativeReceipt
        receiptSha256=$receipt.Digest
    }
    files = @($files | Sort-Object path)
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Build manifest written: $OutputPath"
