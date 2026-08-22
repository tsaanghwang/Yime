$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Require-Text {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string[]] $Fragments
    )

    $resolvedPath = Join-Path $root $Path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Required build-contract file is missing: $Path"
    }

    $text = Get-Content -LiteralPath $resolvedPath -Raw
    foreach ($fragment in $Fragments) {
        if (-not $text.Contains($fragment)) {
            throw "Build contract violation in ${Path}: missing $fragment"
        }
    }
}

Require-Text '.github/workflows/ci.yaml' @(
    'pull_request:'
    'branches: [main, yime-stable]'
    'build-contract:'
    'name: build-contract / validate-build-contract'
    'run: .\tools\validate-build-contract.ps1'
    'core-build:'
    'Install MSYS2 UCRT64 GCC for Go race detector'
    'install: mingw-w64-ucrt-x86_64-gcc'
    'rustup toolchain install stable-i686-pc-windows-msvc --profile minimal'
    'rustup run stable-i686-pc-windows-msvc cargo test --verbose'
    'Build Win32 C++ components'
    'cmake . -Bbuild -G "Visual Studio 17 2022" -A Win32'
    'Build x64 C++ components'
    'Run native C++ regression tests'
    'Run Go regression tests'
    '.\tools\test-go-race.ps1 -GccPath $gcc -TimeoutSeconds 300'
    '.\tools\test-build-guards.ps1'
    'Build the installer'
    'if-no-files-found: error'
    'native-build:'
    'rust-i686-host:'
    'go-tests:'
    'go-race-msys2:'
    'installer-package:'
)

Require-Text 'AGENTS.md' @(
    'nativeBackend.UsesBackendCandidatePaging()` must keep returning `true`'
    'Do not simplify `Reinstall-PIME-Test.cmd`'
    'stable-i686-pc-windows-msvc'
    'Do not assume a source fix is live until you verify the installed `server.exe`'
)

Require-Text '.github/CODEOWNERS' @(
    '/AGENTS.md'
    '/.github/'
    '/Build.ps1'
    '/build.bat'
    '/CMakeLists.txt'
    '/tools/test-build-guards.ps1'
    '/tools/validate-build-contract.ps1'
    '/tools/test-go-race.ps1'
    '/tools/verify-pe-architectures.ps1'
    '/installer/'
)

Require-Text 'CMakeLists.txt' @(
    'Rust_TOOLCHAIN "stable-i686-pc-windows-msvc"'
    'GIT_TAG v0.6.1'
)
Require-Text 'PIMELauncher/.cargo/config.toml' @(
    'target = "i686-pc-windows-msvc"'
)
Require-Text 'tools/test-go-race.ps1' @(
    'go test -race ./...'
)
Require-Text 'tools/test-build-guards.ps1' @(
    'CI MSYS2 Go race guard test passed.'
    'CI cross-repository reusable-workflow rejection test passed.'
    'YIME-only build and installer guard test passed.'
)
Require-Text 'tools/verify-pe-architectures.ps1' @(
    'PE architecture verification passed.'
)

$externalReusableWorkflowPattern = '(?m)^\s*uses:\s+(?!\./)[^/\s]+/[^/\s]+/\.github/workflows/'
$workflowDirectory = Join-Path $root '.github\workflows'
foreach ($workflowFile in Get-ChildItem -LiteralPath $workflowDirectory -File) {
    if ($workflowFile.Extension -notin @('.yml', '.yaml')) {
        continue
    }

    $workflowText = Get-Content -LiteralPath $workflowFile.FullName -Raw
    if ($workflowText -match $externalReusableWorkflowPattern) {
        $relativePath = [IO.Path]::GetRelativePath($root, $workflowFile.FullName)
        throw "Cross-repository reusable workflow is forbidden in ${relativePath}: $($Matches[0].Trim())"
    }
}

Write-Host 'In-repository YIME build contract passed.'
