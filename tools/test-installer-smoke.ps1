param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [switch]$StaticOnly,
    [string]$ExpectedCommit,
    [string]$ExpectedRef,
    [ValidateSet('true','false')][string]$ExpectedSignedRelease,
    [ValidateSet('true','false')][string]$ExpectedSourceTreeDirty,
    [string]$PackagePlanPath,
    [string]$ReceiptPath,
    [switch]$AllowLocalMachine
)

$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$verifyScript = Join-Path $PSScriptRoot 'verify-installed-runtime.ps1'

if ($StaticOnly) {
    function Assert-ExactJsonProperties($Value,[string[]]$Expected,[string]$Context) {
        if ($null -eq $Value -or $Value -is [string] -or $null -eq $Value.PSObject) {
            throw "$Context must be an object."
        }
        $actual=@($Value.PSObject.Properties | ForEach-Object Name)
        if ($actual.Count -ne $Expected.Count) { throw "$Context has an open or incomplete schema." }
        foreach ($name in $Expected) {
            if ($actual -cnotcontains $name) { throw "$Context is missing exact property $name." }
        }
    }
    function ConvertTo-CanonicalArtifactPath([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
            $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.EndsWith('/') -or
            $Path.Contains('//') -or $Path -match '[\x00-\x1f<>:"|?*]' -or
            -not $Path.IsNormalized([Text.NormalizationForm]::FormC)) {
            throw "Non-canonical build-manifest path: $Path"
        }
        foreach ($segment in $Path.Split('/')) {
            if (-not $segment -or $segment -ceq '.' -or $segment -ceq '..' -or
                $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
                $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
                throw "Ambiguous build-manifest path: $Path"
            }
        }
        return $Path
    }
    function Assert-NoArtifactReparsePath([string]$Path) {
        for ($cursor=[IO.Path]::GetFullPath($Path); $cursor; $cursor=Split-Path -Parent $cursor) {
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Indirect build artifact path: $cursor"
            }
            if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
        }
    }

    $repo=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    Assert-NoArtifactReparsePath $repo
    $packageModule=Join-Path $PSScriptRoot 'dual-product\rime-pime-package-plan.ps1'
    . $packageModule
    if (-not $PackagePlanPath) { $PackagePlanPath=Join-Path $repo 'installer\package-plan.json' }
    if (-not $ReceiptPath) { $ReceiptPath=Join-Path $repo 'installer\package-build-receipt.json' }
    $package=Read-RimePimePackagePlan -RepoRoot $repo -PlanPath $PackagePlanPath -VerifyArtifacts
    $expectedInstaller=[IO.Path]::GetFullPath((Join-Path $repo ('installer\'+[IO.Path]::GetFileName($installer))))
    if ($installer -ine $expectedInstaller) { throw 'Installer must use its canonical repository installer path.' }
    $item=Get-Item -LiteralPath $installer -ErrorAction Stop
    if($item.Length -lt 65536){throw 'Compiled installer is unexpectedly small.'}
    $stream=[IO.File]::OpenRead($installer)
    $reader=[IO.BinaryReader]::new($stream)
    try {
        if($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D){
            throw 'Compiled installer is not a PE image.'
        }
        $stream.Position=0x3C
        $peOffset=[uint32]$reader.ReadUInt32()
        if([uint64]$peOffset+24 -gt [uint64]$stream.Length){
            throw 'Compiled installer has an invalid PE header offset.'
        }
        $stream.Position=$peOffset
        if($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x014C){
            throw 'Compiled installer is not the expected Win32 NSIS bootstrap image.'
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
    $receipt=Read-RimePimePackageBuildReceipt -Package $package -ReceiptPath $ReceiptPath
    if ($installer -ine $receipt.InstallerPath) { throw 'Installer path does not match the sealed package build receipt.' }
    $manifestPath=Join-Path $repo 'installer\build-manifest.json'
    if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){
        throw 'Static installer validation requires the build manifest.'
    }
    Assert-NoArtifactReparsePath $manifestPath
    try { $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Invalid build manifest JSON: $($_.Exception.Message)" }
    Assert-ExactJsonProperties $manifest @(
        'schemaVersion','product','version','commit','ref','builtAtUtc','signedRelease','sourceIdentity','packagePlan','files') 'build manifest'
    Assert-ExactJsonProperties $manifest.sourceIdentity @(
        'kind','treeDirty','commitIsCompleteSourceIdentity') 'build manifest source identity'
    Assert-ExactJsonProperties $manifest.packagePlan @(
        'path','sha256','closureScope','architectures','receiptPath','receiptSha256') 'build manifest package plan'
    $version=(Get-Content -LiteralPath (Join-Path $repo 'version.txt') -Raw).Trim()
    $builtAt=[DateTimeOffset]::MinValue
    $builtAtValid=$false
    if ($manifest.builtAtUtc -is [datetime]) {
        $builtAtValid=([datetime]$manifest.builtAtUtc).Kind -eq [DateTimeKind]::Utc
    } elseif ([string]$manifest.builtAtUtc -cmatch 'Z$') {
        $builtAtValid=[DateTimeOffset]::TryParse([string]$manifest.builtAtUtc,[ref]$builtAt)
    }
    if ([int]$manifest.schemaVersion -ne 3 -or [string]$manifest.product -cne 'YIME' -or
        [string]$manifest.version -cne $version -or
        [string]$manifest.commit -cnotmatch '^[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?$' -or
        [string]::IsNullOrWhiteSpace([string]$manifest.ref) -or -not $builtAtValid -or
        -not ($manifest.signedRelease -is [bool])) {
        throw 'Build manifest identity or build metadata is invalid.'
    }
    if (-not ($manifest.sourceIdentity.treeDirty -is [bool]) -or
        -not ($manifest.sourceIdentity.commitIsCompleteSourceIdentity -is [bool]) -or
        ([bool]$manifest.sourceIdentity.treeDirty -and
            ([string]$manifest.sourceIdentity.kind -cne 'working-tree' -or
             [bool]$manifest.sourceIdentity.commitIsCompleteSourceIdentity)) -or
        (-not [bool]$manifest.sourceIdentity.treeDirty -and
            ([string]$manifest.sourceIdentity.kind -cne 'git-commit' -or
             -not [bool]$manifest.sourceIdentity.commitIsCompleteSourceIdentity))) {
        throw 'Build manifest source identity is inconsistent.'
    }
    $planRelative=$package.Path.Substring($repo.Length+1).Replace('\','/')
    $receiptRelative=$receipt.Path.Substring($repo.Length+1).Replace('\','/')
    $manifestArchitectures=@($manifest.packagePlan.architectures)
    if ([string]$manifest.packagePlan.path -cne $planRelative -or
        [string]$manifest.packagePlan.sha256 -cne $package.Digest -or
        [string]$manifest.packagePlan.closureScope -cne 'declared-packaged-product-pe-inputs-only-not-installed-payload' -or
        $manifestArchitectures.Count -ne 2 -or $manifestArchitectures[0] -cne 'x86' -or
        $manifestArchitectures[1] -cne 'x64' -or
        [string]$manifest.packagePlan.receiptPath -cne $receiptRelative -or
        [string]$manifest.packagePlan.receiptSha256 -cne $receipt.Digest) {
        throw 'Build manifest package-plan or build-receipt binding is invalid.'
    }
    if ($ExpectedCommit -and [string]$manifest.commit -cne $ExpectedCommit) { throw 'Build manifest commit does not match the requested commit.' }
    if ($ExpectedRef -and [string]$manifest.ref -cne $ExpectedRef) { throw 'Build manifest ref does not match the requested ref.' }
    if ($ExpectedSignedRelease) {
        $wantedSigned=$ExpectedSignedRelease -ceq 'true'
        if ([bool]$manifest.signedRelease -ne $wantedSigned) { throw 'Build manifest signed-release state does not match the requested state.' }
    }
    if ($ExpectedSourceTreeDirty) {
        $wantedDirty=$ExpectedSourceTreeDirty -ceq 'true'
        if ([bool]$manifest.sourceIdentity.treeDirty -ne $wantedDirty) {
            throw 'Build manifest source-tree state does not match the requested state.'
        }
    }

    $expectedPaths=@($package.Plan.artifacts | ForEach-Object { $_.path })+@(
        [string]$receipt.Receipt.installer_path,
        $planRelative,
        $package.Sidecar.Substring($repo.Length+1).Replace('\','/'),
        $receiptRelative,
        $receipt.Sidecar.Substring($repo.Length+1).Replace('\','/'))

    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $expectedPaths) { $expected.Add($path,$path) }
    $actual=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $installerBasenameMatches=0
    foreach ($row in @($manifest.files)) {
        Assert-ExactJsonProperties $row @('path','size','sha256') 'build manifest file record'
        $relative=ConvertTo-CanonicalArtifactPath ([string]$row.path)
        if (-not ($row.size -is [int] -or $row.size -is [long]) -or [long]$row.size -lt 0 -or
            [string]$row.sha256 -cnotmatch '^[0-9A-F]{64}$') {
            throw "Invalid build artifact size or SHA-256: $relative"
        }
        if ($actual.ContainsKey($relative)) { throw "Case-folded duplicate build artifact: $relative" }
        $actual.Add($relative,$row)
        if ([IO.Path]::GetFileName($relative) -ceq [IO.Path]::GetFileName($installer)) { $installerBasenameMatches++ }
    }
    if ($actual.Count -ne $expected.Count -or $installerBasenameMatches -ne 1) {
        throw 'Build manifest does not contain the exact declared product-PE evidence set.'
    }
    foreach ($relative in $expected.Keys) {
        if (-not $actual.ContainsKey($relative) -or [string]$actual[$relative].path -cne $expected[$relative]) {
            throw "Build manifest is missing or case-mismatches required artifact: $relative"
        }
        $path=[IO.Path]::GetFullPath((Join-Path $repo $relative.Replace('/','\')))
        if (-not $path.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Build artifact is absent or outside the repository root: $relative"
        }
        Assert-NoArtifactReparsePath $path
        $artifact=Get-Item -LiteralPath $path
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ([long]$actual[$relative].size -ne $artifact.Length -or
            [string]$actual[$relative].sha256 -cne $hash) {
            throw "Build manifest content mismatch: $relative"
        }
    }
    Write-Host "PASS: static installer and declared product-PE evidence manifest match; installer was not executed: $installer"
    return
}

if (-not $AllowLocalMachine) {
    throw 'Installer smoke testing mutates machine-wide registration. Pass -AllowLocalMachine explicitly only on an authorized physical acceptance target.'
}

function Invoke-SmokeProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [string]$Description
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(300000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Description timed out after 300 seconds."
    }
    if ($process.ExitCode -ne 0) {
        throw "$Description failed with exit code $($process.ExitCode)"
    }
}

$failure = $null
try {
    Invoke-SmokeProcess -FilePath $installer -Arguments '/S' -Description 'Installer'
    Start-Sleep -Seconds 3
    & $verifyScript -RepoRoot $RepoRoot -InstallRoot $InstallRoot -RequireRunningLauncher
} catch {
    $failure = $_
} finally {
    $uninstaller = Join-Path $InstallRoot 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        try {
            Invoke-SmokeProcess -FilePath $uninstaller -Arguments '/S' -Description 'Uninstaller'
        } catch {
            if (-not $failure) { $failure = $_ }
        }
    }
}
if ($failure) { throw $failure }
Write-Host 'Unsigned installer smoke test passed and the ephemeral installation was removed.'
