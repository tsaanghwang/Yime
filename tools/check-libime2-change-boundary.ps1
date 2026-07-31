param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseRef,
    [string]$HeadRef = 'HEAD',
    [switch]$Staged,
    [string]$CommitMessagePath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

$transitionCompanionPaths = @(
    '.gitmodules',
    '.github/CODEOWNERS',
    '.github/workflows/ci.yaml',
    'AGENTS.md',
    'CMakeLists.txt',
    'README.md',
    'docs/project/LIBIME2_COMPONENT_BOUNDARY.md',
    'tools/test-build-guards.ps1'
)

function Invoke-RepoGit {
    param([string[]]$Arguments)

    $output = @(& git -C $script:repoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Normalize-RepoPath {
    param([string]$Path)
    return ([string]$Path).Trim().Replace('\', '/')
}

function Test-LibIME2Path {
    param([string]$Path)
    $normalized = Normalize-RepoPath $Path
    return $normalized -eq 'libIME2' -or $normalized.StartsWith('libIME2/')
}

function Test-TransitionCompanionPath {
    param([string]$Path)
    $normalized = Normalize-RepoPath $Path
    return $script:transitionCompanionPaths -contains $normalized
}

function Test-ZeroObjectID {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^0+$'
}

function Test-GitObject {
    param([string]$Object)
    if ([string]::IsNullOrWhiteSpace($Object)) {
        return $false
    }
    & git -C $script:repoRoot cat-file -e "$Object^{commit}" 2>$null
    return $LASTEXITCODE -eq 0
}

function Resolve-RangeBase {
    param([string]$RequestedBase, [string]$Head)

    if (-not [string]::IsNullOrWhiteSpace($RequestedBase) -and
        -not (Test-ZeroObjectID $RequestedBase) -and
        (Test-GitObject $RequestedBase)) {
        return $RequestedBase
    }

    foreach ($candidate in @('refs/remotes/origin/main', 'refs/heads/main')) {
        if (Test-GitObject $candidate) {
            $mergeBase = @(Invoke-RepoGit @('merge-base', $Head, $candidate))
            if ($mergeBase.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($mergeBase[0])) {
                return $mergeBase[0].Trim()
            }
        }
    }

    if (Test-GitObject "$Head^") {
        return "$Head^"
    }
    return ''
}

function Get-CommitMode {
    param([string]$Commit)
    $entry = @(Invoke-RepoGit @('ls-tree', $Commit, '--', 'libIME2'))
    if ($entry.Count -gt 0 -and $entry[0] -match '^160000\s') {
        return 'submodule-pointer'
    }
    return 'vendored-source'
}

function Get-Subject {
    param([string]$Message)
    $first = @(([string]$Message) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($first.Count -eq 0) {
        return ''
    }
    return $first[0].Replace("`t", ' ').Trim()
}

function Test-ChangeSet {
    param(
        [string]$Identity,
        [string]$Message,
        [string[]]$Paths,
        [string]$Mode
    )

    $normalizedPaths = @($Paths | ForEach-Object { Normalize-RepoPath $_ } | Where-Object { $_ })
    $libPaths = @($normalizedPaths | Where-Object { Test-LibIME2Path $_ })
    if ($libPaths.Count -eq 0) {
        return $null
    }

    $outsidePaths = @($normalizedPaths | Where-Object { -not (Test-LibIME2Path $_) })
    $hasChangeTrailer = $Message -match '(?im)^LibIME2-Change:\s*\S.+$'
    $hasTransitionTrailer = $Message -match '(?im)^LibIME2-Integration:\s*(vendor|submodule|extract)\s*$'
    $issues = [Collections.Generic.List[string]]::new()

    if (-not $hasChangeTrailer -and -not $hasTransitionTrailer) {
        $issues.Add('missing LibIME2-Change: <summary> tracking trailer')
    }
    if ($outsidePaths.Count -gt 0) {
        if (-not $hasTransitionTrailer) {
            $issues.Add("component commit also changes main-project paths: $($outsidePaths -join ', ')")
        } else {
            $unexpected = @($outsidePaths | Where-Object { -not (Test-TransitionCompanionPath $_) })
            if ($unexpected.Count -gt 0) {
                $issues.Add("integration transition contains unapproved companion paths: $($unexpected -join ', ')")
            }
        }
    }

    $kind = if ($hasTransitionTrailer) { 'integration-transition' } else { 'component-change' }
    return [pscustomobject]@{
        Identity = $Identity
        Subject = Get-Subject $Message
        Mode = $Mode
        Kind = $kind
        Paths = $normalizedPaths
        Issues = @($issues)
    }
}

function Write-TrackingReport {
    param([object[]]$Records, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("commit`tmode`tkind`tsubject`tpaths`tstatus")
    foreach ($record in $Records) {
        $status = if ($record.Issues.Count -eq 0) { 'pass' } else { 'fail: ' + ($record.Issues -join ' | ') }
        $lines.Add(
            "$($record.Identity)`t$($record.Mode)`t$($record.Kind)`t$($record.Subject)`t$($record.Paths -join ';')`t$status"
        )
    }
    [IO.File]::WriteAllLines($fullPath, $lines, [Text.UTF8Encoding]::new($false))
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$records = [Collections.Generic.List[object]]::new()

if ($Staged) {
    $paths = @(Invoke-RepoGit @('diff', '--cached', '--name-only', '--diff-filter=ACDMRTUXB'))
    $message = ''
    if (-not [string]::IsNullOrWhiteSpace($CommitMessagePath)) {
        $message = Get-Content -LiteralPath $CommitMessagePath -Raw -Encoding UTF8
    } elseif (@($paths | Where-Object { Test-LibIME2Path $_ }).Count -gt 0) {
        # pre-commit runs before the message exists. It still enforces the
        # component boundary; commit-msg performs the actual trailer check.
        $outsidePaths = @($paths | Where-Object { -not (Test-LibIME2Path $_) })
        $transitionShape = $outsidePaths.Count -gt 0 -and
            @($outsidePaths | Where-Object { -not (Test-TransitionCompanionPath $_) }).Count -eq 0
        $message = if ($transitionShape) {
            'LibIME2-Integration: vendor'
        } else {
            'LibIME2-Change: pre-commit boundary check'
        }
    }
    $record = Test-ChangeSet 'STAGED' $message $paths 'staged'
    if ($null -ne $record) {
        $records.Add($record)
    }
} else {
    if (-not (Test-GitObject $HeadRef)) {
        throw "Cannot find the commit to check: $HeadRef"
    }
    $resolvedBase = Resolve-RangeBase $BaseRef $HeadRef
    $revision = if ($resolvedBase) { "$resolvedBase..$HeadRef" } else { $HeadRef }
    $commits = if ($resolvedBase) {
        @(Invoke-RepoGit @('rev-list', '--reverse', '--no-merges', $revision))
    } else {
        @(Invoke-RepoGit @('rev-list', '--reverse', '--no-merges', '--max-count=1', $HeadRef))
    }
    foreach ($commit in $commits) {
        $commit = ([string]$commit).Trim()
        if (-not $commit) {
            continue
        }
        $paths = @(Invoke-RepoGit @('diff-tree', '--root', '--no-commit-id', '--name-only', '-r', $commit))
        $message = (Invoke-RepoGit @('show', '-s', '--format=%B', $commit)) -join [Environment]::NewLine
        $record = Test-ChangeSet $commit $message $paths (Get-CommitMode $commit)
        if ($null -ne $record) {
            $records.Add($record)
        }
    }
}

Write-TrackingReport @($records) $ReportPath

$failures = @($records | Where-Object { $_.Issues.Count -gt 0 })
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "libIME2 gate rejected: $($failure.Identity)" -ForegroundColor Red
        foreach ($issue in $failure.Issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
    }
    throw "libIME2 commit boundary gate rejected $($failures.Count) commit(s)."
}

if ($records.Count -eq 0) {
    Write-Host 'libIME2 gate: no libIME2 changes in this range.'
} else {
    foreach ($record in $records) {
        Write-Host "libIME2 gate passed: $($record.Identity) [$($record.Mode)] $($record.Subject)"
    }
}
