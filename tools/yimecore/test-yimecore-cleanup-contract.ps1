[CmdletBinding()]
param(
    [string]$ManagerPath,
    [string]$StopPath,
    [string]$ParallelExperimentPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManagerPath)) {
    $ManagerPath = Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
}
if ([string]::IsNullOrWhiteSpace($StopPath)) {
    $StopPath = Join-Path $PSScriptRoot 'stop-e6c-trial-runtime.ps1'
}
if ([string]::IsNullOrWhiteSpace($ParallelExperimentPath)) {
    $ParallelExperimentPath = Join-Path $PSScriptRoot 'run-e6b7-parallel-package-experiment.ps1'
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function New-MockLanguage([string]$tag, [string[]]$tips) {
    $values = [Collections.Generic.List[string]]::new()
    foreach ($value in $tips) { $values.Add($value) }
    [pscustomobject]@{ LanguageTag = $tag; InputMethodTips = $values }
}

$tokens = $null
$errors = $null
$managerAst = [Management.Automation.Language.Parser]::ParseFile(
    [IO.Path]::GetFullPath($ManagerPath), [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'maintenance manager did not parse'
$removeFunction = $managerAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Remove-InputMethodTip'
}, $true)
Assert-True ($null -ne $removeFunction) 'Remove-InputMethodTip function is missing'
Invoke-Expression $removeFunction.Extent.Text

$tip = '0804:{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$otherTip = '0409:{00000000-0000-0000-0000-000000000001}{00000000-0000-0000-0000-000000000002}'
$script:mockLanguageList = @(
    (New-MockLanguage 'zh-Hans-CN' @($tip, $otherTip)),
    (New-MockLanguage 'zh-Hant-TW' @($tip, $tip)),
    (New-MockLanguage 'en-US' @($otherTip)))
$script:setCalls = 0
function Get-WinUserLanguageList { return $script:mockLanguageList }
function Set-WinUserLanguageList {
    param($LanguageList, [switch]$Force)
    $script:setCalls++
}
Remove-InputMethodTip
Assert-True ($script:setCalls -eq 1) 'TIP cleanup did not persist the language list exactly once'
Assert-True (-not (@($script:mockLanguageList.InputMethodTips) -contains $tip)) `
    'TIP cleanup left the exact trial TIP in a non-default language entry'
Assert-True (@($script:mockLanguageList[0].InputMethodTips) -contains $otherTip) `
    'TIP cleanup removed an unrelated input method'

$script:mockLanguageList = @((New-MockLanguage 'zh-Hans-CN' @($tip)))
function Set-WinUserLanguageList { throw 'injected language-list persistence failure' }
$Force = $true
$failedLoud = $false
try { Remove-InputMethodTip } catch { $failedLoud = $true }
Assert-True $failedLoud 'TIP cleanup suppressed a language-list failure under -Force'

$stopText = Get-Content -LiteralPath $StopPath -Raw
Assert-True ($stopText -match 'foreach \(\$language in @\(\$languageList\)\)' -and
    $stopText -match 'YimeCore trial TIP remained in language entries' -and
    $stopText -notmatch "Where-Object LanguageTag -eq 'zh-Hans-CN'") `
    'standalone stop cleanup does not remove and verify the trial TIP across all language entries'

$parallelText = Get-Content -LiteralPath $ParallelExperimentPath -Raw
Assert-True ($parallelText -notmatch 'unregister \*> \$null') `
    'E6-B7 fallback still suppresses unregister output and exit status'
foreach ($required in @('fallback-unregister.txt', 'fallback-verify-absent.txt',
                         '$cleanupFailures', 'installation files were preserved')) {
    Assert-True $parallelText.Contains($required) "E6-B7 fallback cleanup contract is missing: $required"
}
$fallbackStart = $parallelText.IndexOf('$verifiedCleanup =')
Assert-True ($fallbackStart -ge 0) 'E6-B7 fallback cleanup block is missing'
$fallbackText = $parallelText.Substring($fallbackStart)
$fallbackLoop = [regex]::Match(
    $fallbackText,
    '(?s)foreach \(\$architecture in @\(''x64'', ''x86''\)\) \{.*?\r?\n        \}').Value
Assert-True ($fallbackLoop -match
    '(?s)if \(\$verifiedCleanup\.Contains\(\$architecture\)\) \{ continue \}\s*try \{\s*\$cleanupDirectory') `
    'E6-B7 fallback can fail before entering its per-architecture error collector'
Assert-True ($fallbackLoop -match '(?s)catch \{.*?\$cleanupFailures\.Add') `
    'E6-B7 fallback does not collect per-architecture failures before continuing'

Write-Host 'YimeCore cleanup contracts passed.'
