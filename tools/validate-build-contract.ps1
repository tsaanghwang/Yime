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
    'Verify locked Windows toolchain metadata'
    'python .\tools\verify_toolchain_lock.py'
    'Verify detached lexicon archive identity'
    'python .\tools\lexicon\verify_external_archive_lock.py'
    'Verify internal PSC outline snapshot'
    'run: python .\tools\verify_psc_outline_snapshot.py'
    'core-build:'
    'Install MSYS2 UCRT64 GCC for Go race detector'
    'install: mingw-w64-ucrt-x86_64-gcc'
    'rustup toolchain install stable-i686-pc-windows-msvc --profile minimal'
    'rustup run stable-i686-pc-windows-msvc cargo test --verbose'
    'Verify vendored Win32 build dependencies'
    'python .\tools\verify_vendored_build_dependencies.py'
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
    '/.cargo/'
    '/tools/test-build-guards.ps1'
    '/tools/validate-build-contract.ps1'
    '/tools/verify_psc_outline_snapshot.py'
    '/tools/verify_vendored_build_dependencies.py'
    '/tools/toolchain.lock.json'
    '/tools/verify_toolchain_lock.py'
    '/tools/psc_outline_review_tool.py'
    '/tools/test_psc_outline_review_tool.py'
    '/tools/test-go-race.ps1'
    '/tools/verify-pe-architectures.ps1'
    '/internal_data/psc_outline/'
    '/PIMELauncher/vendor/'
    '/third_party/'
    '/installer/'
)

Require-Text 'CMakeLists.txt' @(
    'Rust_TOOLCHAIN "stable-i686-pc-windows-msvc"'
    'add_subdirectory(${PROJECT_SOURCE_DIR}/third_party/corrosion)'
)
Require-Text 'PIMELauncher/.cargo/config.toml' @(
    'target = "i686-pc-windows-msvc"'
    'offline = true'
    'replace-with = "vendored-sources"'
    'directory = "vendor"'
)
Require-Text '.cargo/config.toml' @(
    'offline = true'
    'replace-with = "vendored-sources"'
    'directory = "PIMELauncher/vendor"'
)
Require-Text 'tools/verify_vendored_build_dependencies.py' @(
    'CORROSION_VERSION = "0.6.1"'
    'CORROSION_COMMIT = "1499b14e4906a2890f5cee1547c8848db261753d"'
    'CORROSION_TREE_SHA256 = "3c01b36b86b3b9e0997903a1b0e885d2ae893083c19131b11647540718800864"'
    'GO_WINRES_VERSION = "0.3.3"'
    'GO_WINRES_TREE_SHA256 = "727e8eca52890e48f10fc41dfda6b8a2a7899e308e80e1f8937678df452e9dea"'
)
Require-Text 'tools/toolchain.lock.json' @(
    '"lock_id": "yime-windows-build-toolchain-20260822"'
    '"offline_recovery_note"'
    '"id": "go_winres"'
)
Require-Text 'tools/lexicon/data/external_archive.lock.json' @(
    '"archive_id": "yime-lexicon-external-inputs-20260821"'
    '"maximum_evidence_age_days": 90'
    '"sha256": "febf16107068e1434f40a13aef3c326fe6a2e63fb1375520895ee3253c3d9b0d"'
)
Require-Text 'go-backend/build.bat' @(
    'third_party\go-winres'
    'go build -mod=vendor -trimpath -buildvcs=false'
    '[ERROR] go-winres failed for'
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

$ciText = Get-Content -LiteralPath (Join-Path $root '.github\workflows\ci.yaml') -Raw
if ($ciText.Contains('go install github.com/tc-hib/go-winres')) {
    throw 'CI must build go-winres from the hash-locked offline source tree.'
}

Write-Host 'In-repository YIME build contract passed.'
