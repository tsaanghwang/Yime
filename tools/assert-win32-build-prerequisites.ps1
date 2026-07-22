param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$RequireToolchain,
    [switch]$RequireBuildArtifacts
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$toolchain = 'stable-i686-pc-windows-msvc'

$cmakeText = Get-Content -LiteralPath (Join-Path $repoRoot 'CMakeLists.txt') -Raw
if ($cmakeText -notmatch 'set\(Rust_TOOLCHAIN\s+"stable-i686-pc-windows-msvc"') {
    throw 'CMake must pin Rust_TOOLCHAIN to stable-i686-pc-windows-msvc.'
}
if ($cmakeText -notmatch 'GIT_TAG\s+v0\.6\.1') {
    throw 'CMake must pin Corrosion to v0.6.1.'
}
$cargoConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'PIMELauncher\.cargo\config.toml') -Raw
if ($cargoConfig -notmatch 'target\s*=\s*"i686-pc-windows-msvc"') {
    throw 'PIMELauncher/.cargo/config.toml must target i686-pc-windows-msvc.'
}

if ($RequireToolchain) {
    $rustupCommand = Get-Command rustup.exe -ErrorAction SilentlyContinue
    $rustupPath = if ($rustupCommand) { $rustupCommand.Source } else { $null }
    if (-not $rustupPath) {
        $directRustup = Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'
        if (Test-Path -LiteralPath $directRustup) { $rustupPath = $directRustup }
    }
    if (-not $rustupPath) {
        throw 'rustup.exe was not found. Check %USERPROFILE%\.cargo\bin before reinstalling Rust.'
    }
    $toolchains = @(& $rustupPath toolchain list)
    if ($LASTEXITCODE -ne 0 -or -not ($toolchains -match '^stable-i686-pc-windows-msvc')) {
        throw "Pinned i686 host toolchain is missing. Run: rustup toolchain install $toolchain --profile minimal"
    }
    $hostLine = @(& $rustupPath run $toolchain rustc -vV) | Where-Object { $_ -like 'host:*' }
    if ($LASTEXITCODE -ne 0 -or $hostLine -ne 'host: i686-pc-windows-msvc') {
        throw "Pinned Rust toolchain is not an i686 host: $($hostLine -join ', ')"
    }
    & $rustupPath run $toolchain cargo --version
    if ($LASTEXITCODE -ne 0) { throw 'Pinned i686 host cargo could not run.' }
}

if ($RequireBuildArtifacts) {
    $required = @(
        'build\PIMELauncher\PIMELauncher.exe',
        'build\PIMETextService\Release\PIMETextService.dll',
        'build64\PIMETextService\Release\PIMETextService.dll',
        'go-backend\build\go-backend\server.exe'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf) })
    if ($missing.Count -gt 0) {
        throw "Required developer-install artifacts are missing: $($missing -join ', '). Rebuild with build.bat; do not weaken dev-install assertions."
    }
}

Write-Host 'Win32 build prerequisites passed.'
