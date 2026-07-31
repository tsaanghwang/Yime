$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$checker = Join-Path $PSScriptRoot 'check-libime2-change-boundary.ps1'
$tempRoot = Join-Path $root '.tmp\libime2-boundary-test'

if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Invoke-TestGit {
    param([string[]]$Arguments)
    & git -C $tempRoot @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "test git command failed: git $($Arguments -join ' ')"
    }
}

function Write-TestFile {
    param([string]$RelativePath, [string]$Content)
    $path = Join-Path $tempRoot $RelativePath
    $parent = Split-Path -Parent $path
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

function Commit-TestChange {
    param([string]$Message)
    Invoke-TestGit @('add', '-A')
    Invoke-TestGit @('commit', '-m', $Message)
    return (& git -C $tempRoot rev-parse HEAD).Trim()
}

function Assert-GatePasses {
    param([string]$Base, [string]$Head, [string]$Name)
    & $checker -RepoRoot $tempRoot -BaseRef $Base -HeadRef $Head -ReportPath (Join-Path $tempRoot ".git\$Name.tsv")
}

function Assert-GateFails {
    param([string]$Base, [string]$Head, [string]$Pattern)
    try {
        & $checker -RepoRoot $tempRoot -BaseRef $Base -HeadRef $Head
        throw "expected libIME2 gate failure matching: $Pattern"
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw
        }
    }
}

try {
    Invoke-TestGit @('init', '-b', 'main')
    Invoke-TestGit @('config', 'user.name', 'Yime Gate Test')
    Invoke-TestGit @('config', 'user.email', 'gate@example.invalid')
    Write-TestFile 'README.md' "test`n"
    $initial = Commit-TestChange 'initial'

    Invoke-TestGit @('update-index', '--add', '--cacheinfo', "160000,$initial,libIME2")
    Invoke-TestGit @('commit', '-m', "submodule pointer`n`nLibIME2-Change: advance pinned TSF source")
    $submodulePointer = (& git -C $tempRoot rev-parse HEAD).Trim()
    Assert-GatePasses $initial $submodulePointer 'submodule-pass'
    $submoduleReport = Get-Content -LiteralPath (Join-Path $tempRoot '.git\submodule-pass.tsv') -Raw -Encoding UTF8
    if (-not $submoduleReport.Contains('submodule-pointer')) {
        throw 'tracking report did not recognize the libIME2 gitlink'
    }
    Invoke-TestGit @('reset', '--hard', $initial)

    Write-TestFile 'libIME2/source.cpp' "int value = 1;`n"
    $component = Commit-TestChange "lib change`n`nLibIME2-Change: add source"
    Assert-GatePasses $initial $component 'component-pass'

    Write-TestFile 'libIME2/source.cpp' "int value = 2;`n"
    $missingTrailer = Commit-TestChange 'missing trailer'
    Assert-GateFails $component $missingTrailer 'rejected'

    Invoke-TestGit @('reset', '--hard', $component)
    Write-TestFile 'libIME2/source.cpp' "int value = 3;`n"
    Write-TestFile 'main.cpp' "int main() { return 0; }`n"
    $mixed = Commit-TestChange "mixed`n`nLibIME2-Change: mixed source"
    Assert-GateFails $component $mixed 'rejected'

    Invoke-TestGit @('reset', '--hard', $component)
    Write-TestFile 'libIME2/source.cpp' "int value = 4;`n"
    Write-TestFile '.gitmodules' ""
    Write-TestFile 'README.md' "vendored`n"
    $transition = Commit-TestChange "vendor libIME2`n`nLibIME2-Integration: vendor"
    Assert-GatePasses $component $transition 'transition-pass'

    $report = Get-Content -LiteralPath (Join-Path $tempRoot '.git\transition-pass.tsv') -Raw -Encoding UTF8
    foreach ($fragment in @('integration-transition', 'vendored-source', 'pass')) {
        if (-not $report.Contains($fragment)) {
            throw "tracking report is missing: $fragment"
        }
    }

    Write-TestFile 'libIME2/source.cpp' "int value = 5;`n"
    Invoke-TestGit @('add', 'libIME2/source.cpp')
    & $checker -RepoRoot $tempRoot -Staged
    $messagePath = Join-Path $tempRoot '.git\GATE_TEST_MSG'
    [IO.File]::WriteAllText($messagePath, "missing trailer`n", [Text.UTF8Encoding]::new($false))
    try {
        & $checker -RepoRoot $tempRoot -Staged -CommitMessagePath $messagePath
        throw 'expected commit-msg trailer gate to fail'
    } catch {
        if ($_.Exception.Message -notmatch 'rejected') {
            throw
        }
    }
    [IO.File]::WriteAllText($messagePath, "valid`n`nLibIME2-Change: test hook`n", [Text.UTF8Encoding]::new($false))
    & $checker -RepoRoot $tempRoot -Staged -CommitMessagePath $messagePath
    Invoke-TestGit @('reset', '--hard', $transition)

    Write-TestFile 'libIME2/source.cpp' "int value = 6;`n"
    Write-TestFile 'README.md' "transition hook`n"
    Invoke-TestGit @('add', '-A')
    & $checker -RepoRoot $tempRoot -Staged
    [IO.File]::WriteAllText($messagePath, "transition`n`nLibIME2-Integration: vendor`n", [Text.UTF8Encoding]::new($false))
    & $checker -RepoRoot $tempRoot -Staged -CommitMessagePath $messagePath
    Invoke-TestGit @('reset', '--hard', $transition)

    Write-Host 'libIME2 commit boundary tests passed.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
