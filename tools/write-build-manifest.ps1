param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'installer\build-manifest.json')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'version.txt') -Raw).Trim()
$commit = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { (& git -C $repoRoot rev-parse HEAD).Trim() }
$ref = if ($env:GITHUB_REF) { $env:GITHUB_REF } else { (& git -C $repoRoot branch --show-current).Trim() }

$patterns = @(
    'installer\YIME-*-setup.exe',
    'build\PIMELauncher\PIMELauncher.exe',
    'build\PIMETextService\Release\PIMETextService.dll',
    'build64\PIMETextService\Release\PIMETextService.dll',
    'go-backend\build\go-backend\*.exe',
    'go-backend\build\go-backend\input_methods\yime\rime.dll',
    'go-backend\build\go-backend\input_methods\yime\rime_deployer.exe'
)
$files = [Collections.Generic.List[object]]::new()
foreach ($pattern in $patterns) {
    foreach ($file in @(Get-ChildItem -Path (Join-Path $repoRoot $pattern) -File -ErrorAction SilentlyContinue)) {
        $relative = $file.FullName.Substring($repoRoot.TrimEnd('\').Length + 1).Replace('\', '/')
        if ($files.path -contains $relative) { continue }
        $files.Add([pscustomobject]@{
            path = $relative
            size = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        })
    }
}
if (-not ($files.path -like 'installer/YIME-*-setup.exe')) {
    throw 'No installer was found for the build manifest.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    product = 'YIME'
    version = $version
    commit = $commit
    ref = $ref
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    signedRelease = [bool]($env:YIME_RELEASE_SIGNING_REQUIRED -eq '1')
    files = @($files | Sort-Object path)
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Build manifest written: $OutputPath"
