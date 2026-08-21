[CmdletBinding()]
param(
    [string]$Python,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ToolArguments
)

$ErrorActionPreference = 'Stop'
$minimum = [version]'3.14'

function Test-YimeLexiconPython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [string[]]$PrefixArguments = @()
    )

    try {
        $versionText = & $Executable @PrefixArguments -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        $resolvedVersion = [version]($versionText | Select-Object -Last 1)
        if ($resolvedVersion -lt $minimum) {
            return $null
        }
        return [pscustomobject]@{
            Executable = $Executable
            PrefixArguments = @($PrefixArguments)
            Version = $resolvedVersion
        }
    }
    catch {
        return $null
    }
}

$candidates = @()
if ($Python) {
    $candidates += [pscustomobject]@{ Executable = $Python; PrefixArguments = @() }
}
if ($env:YIME_LEXICON_PYTHON) {
    $candidates += [pscustomobject]@{ Executable = $env:YIME_LEXICON_PYTHON; PrefixArguments = @() }
}
if (Get-Command py -ErrorAction SilentlyContinue) {
    $candidates += [pscustomobject]@{ Executable = 'py'; PrefixArguments = @('-3.14') }
}
foreach ($name in @('python3.14', 'python')) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        $candidates += [pscustomobject]@{ Executable = $name; PrefixArguments = @() }
    }
}

$runtime = $null
foreach ($candidate in $candidates) {
    $runtime = Test-YimeLexiconPython `
        -Executable $candidate.Executable `
        -PrefixArguments $candidate.PrefixArguments
    if ($runtime) {
        break
    }
}

if (-not $runtime) {
    throw 'Yime offline lexicon tooling requires Python 3.14 or newer. Set YIME_LEXICON_PYTHON or install the current stable Python release.'
}

if (-not $ToolArguments -or $ToolArguments.Count -eq 0) {
    & $runtime.Executable @($runtime.PrefixArguments) --version
}
else {
    & $runtime.Executable @($runtime.PrefixArguments) @ToolArguments
}
exit $LASTEXITCODE
