param(
    [switch]$IncludeInstaller,
    [switch]$RequireComplete
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(
    'build\PIMELauncher\PIMELauncher.exe',
    'build\PIMETextService\Release\PIMETextService.dll',
    'build64\PIMETextService\Release\PIMETextService.dll',
    'go-backend\build\go-backend\server.exe',
    'go-backend\build\go-backend\tool-hub.exe',
    'go-backend\build\go-backend\settings-tool.exe',
    'go-backend\build\go-backend\diagnostics-tool.exe',
    'go-backend\build\go-backend\lexicon-manager.exe',
    'go-backend\build\go-backend\reverse-lookup.exe',
    'go-backend\build\go-backend\system-lexicon-audit.exe',
    'go-backend\build\go-backend\blocklist-manager.exe',
    'go-backend\build\go-backend\input_methods\yime\rime_deployer.exe',
    'go-backend\build\go-backend\input_methods\yime\rime.dll'
)

$arm64 = Join-Path $root 'build_arm64\PIMETextService\Release\PIMETextService.dll'
if (Test-Path -LiteralPath $arm64) {
    $files += 'build_arm64\PIMETextService\Release\PIMETextService.dll'
}
if ($IncludeInstaller) {
    $installers = @(Get-ChildItem -LiteralPath (Join-Path $root 'installer') -Filter 'YIME-*-setup.exe')
    if ($RequireComplete -and $installers.Count -eq 0) {
        throw 'No YIME installer was found.'
    }
    $files += $installers.FullName
}

foreach ($file in $files) {
    $path = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $root $file }
    if (-not (Test-Path -LiteralPath $path)) {
        if ($RequireComplete) {
            throw "Required release file is missing: $path"
        }
        Write-Warning "Release file is missing: $path"
        continue
    }
    & (Join-Path $PSScriptRoot 'sign-file.ps1') -Path $path
}
