# Build the current source and produce an unsigned, deliberately disabled
# Rime/PIME development installer plus its sealed evidence files. This entry is
# not a release-signing path and never installs the result.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

foreach ($name in @(
    'YIME_SIGN_CERT_SHA1',
    'YIME_RELEASE_SIGNING_REQUIRED',
    'YIME_SIGNTOOL_EXE',
    'YIME_TIMESTAMP_URL'
)) {
    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Build.ps1 is an unsigned development entry; clear process signing variable $name and use the protected release workflow for signing."
    }
}

$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
Push-Location $repoRoot
try {
    cmd /c build.bat
    if ($LASTEXITCODE -ne 0) {
        throw "build.bat failed with exit code $LASTEXITCODE"
    }

    $planPath = Join-Path $repoRoot 'installer\package-plan.json'
    & (Join-Path $repoRoot 'tools\dual-product\rime-pime-package-plan.ps1') `
        -WritePlan -PlanRepoRoot $repoRoot -OutputPlanPath $planPath | Out-Null
    & (Join-Path $repoRoot 'tools\build-rime-pime-installer.ps1') `
        -RepoRoot $repoRoot -PackagePlanPath $planPath
    & (Join-Path $repoRoot 'tools\write-build-manifest.ps1') `
        -RepoRoot $repoRoot -PackagePlanPath $planPath
} finally {
    Pop-Location
}

$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'version.txt') -Raw).Trim()
$installer = Join-Path $repoRoot "installer\YIME-$version-setup.exe"
Write-Host "Done. Unsigned disabled installer (do not run): $installer"


