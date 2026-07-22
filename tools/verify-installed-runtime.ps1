param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [string]$JsonPath,
    [switch]$AllowTextServiceMismatch,
    [switch]$RequireRunningLauncher
)

$ErrorActionPreference = 'Stop'

function Get-FileRecord {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Installed,
        [bool]$Required = $true,
        [bool]$TextService = $false
    )

    $record = [ordered]@{
        name = $Name
        source = $Source
        installed = $Installed
        required = $Required
        textService = $TextService
        sourceHash = $null
        installedHash = $null
        status = 'unknown'
    }
    if (-not (Test-Path -LiteralPath $Source)) {
        $record.status = if ($Required) { 'source-missing' } else { 'not-built' }
        return [pscustomobject]$record
    }
    $record.sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if (-not (Test-Path -LiteralPath $Installed)) {
        $record.status = 'installed-missing'
        return [pscustomobject]$record
    }
    $record.installedHash = (Get-FileHash -LiteralPath $Installed -Algorithm SHA256).Hash
    $record.status = if ($record.sourceHash -eq $record.installedHash) { 'match' } else { 'mismatch' }
    return [pscustomobject]$record
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$installRoot = [IO.Path]::GetFullPath($InstallRoot)
$goSourceRoot = Join-Path $repoRoot 'go-backend\build\go-backend'
$goInstallRoot = Join-Path $installRoot 'go-backend'

$files = [Collections.Generic.List[object]]::new()
$files.Add((Get-FileRecord 'version.txt' (Join-Path $repoRoot 'version.txt') (Join-Path $installRoot 'version.txt')))
$files.Add((Get-FileRecord 'backends.json' (Join-Path $repoRoot 'backends.json') (Join-Path $installRoot 'backends.json')))

$launcherCandidates = @(
    (Join-Path $repoRoot 'build\PIMELauncher\PIMELauncher.exe'),
    (Join-Path $repoRoot 'build\PIMELauncher\Release\PIMELauncher.exe')
)
$launcherSource = $launcherCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $launcherSource) { $launcherSource = $launcherCandidates[0] }
$files.Add((Get-FileRecord 'PIMELauncher.exe' $launcherSource (Join-Path $installRoot 'PIMELauncher.exe')))
$files.Add((Get-FileRecord 'x86/PIMETextService.dll' (Join-Path $repoRoot 'build\PIMETextService\Release\PIMETextService.dll') (Join-Path $installRoot 'x86\PIMETextService.dll') $true $true))
$files.Add((Get-FileRecord 'x64/PIMETextService.dll' (Join-Path $repoRoot 'build64\PIMETextService\Release\PIMETextService.dll') (Join-Path $installRoot 'x64\PIMETextService.dll') $true $true))

foreach ($relativePath in @(
    'server.exe',
    'tool-hub.exe',
    'lexicon-manager.exe',
    'system-lexicon-audit.exe',
    'blocklist-manager.exe',
    'reverse-lookup.exe',
    'settings-tool.exe',
    'diagnostics-tool.exe',
    'yime-layout-designer.exe',
    'input_methods\yime\rime.dll'
)) {
    $files.Add((Get-FileRecord "go-backend/$($relativePath.Replace('\', '/'))" (Join-Path $goSourceRoot $relativePath) (Join-Path $goInstallRoot $relativePath)))
}
$files.Add((Get-FileRecord 'go-backend/input_methods/yime/rime_deployer.exe' (Join-Path $goSourceRoot 'input_methods\yime\rime_deployer.exe') (Join-Path $goInstallRoot 'input_methods\yime\rime_deployer.exe') $false))

$registryRoot = $null
try {
    $registryRoot = (Get-Item -Path 'HKLM:\SOFTWARE\YIME' -ErrorAction Stop).GetValue('')
} catch {
}
$registryMatches = $registryRoot -and ([IO.Path]::GetFullPath($registryRoot).TrimEnd('\') -eq $installRoot.TrimEnd('\'))

$launcherRunning = $false
foreach ($process in @(Get-Process -Name PIMELauncher -ErrorAction SilentlyContinue)) {
    try {
        if ($process.Path -and $process.Path.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $launcherRunning = $true
            break
        }
    } catch {
    }
}

$hardFailures = @($files | Where-Object {
    $_.required -and $_.status -ne 'match' -and -not ($AllowTextServiceMismatch -and $_.textService -and $_.status -eq 'mismatch')
})
$allowedDllMismatches = @($files | Where-Object { $_.textService -and $_.status -eq 'mismatch' })
if (-not $registryMatches) {
    $hardFailures += [pscustomobject]@{ name = 'HKLM/Software/YIME'; status = 'mismatch' }
}
if ($RequireRunningLauncher -and -not $launcherRunning) {
    $hardFailures += [pscustomobject]@{ name = 'PIMELauncher process'; status = 'not-running' }
}

$overall = if ($hardFailures.Count -gt 0) {
    'failed'
} elseif ($allowedDllMismatches.Count -gt 0) {
    'partial'
} else {
    'complete'
}
$report = [ordered]@{
    schemaVersion = 1
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    repoRoot = $repoRoot
    installRoot = $installRoot
    overall = $overall
    registryRoot = $registryRoot
    registryMatches = [bool]$registryMatches
    launcherRunning = $launcherRunning
    files = @($files)
}

if ($JsonPath) {
    $jsonParent = Split-Path -Parent $JsonPath
    if ($jsonParent) { New-Item -ItemType Directory -Path $jsonParent -Force | Out-Null }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $JsonPath -Encoding utf8
}

$report.files | Format-Table name, status -AutoSize
Write-Host "Installed runtime verification: $overall"
if ($overall -eq 'failed') {
    throw "Installed runtime verification failed: $($hardFailures.name -join ', ')"
}
if ($overall -eq 'partial') {
    Write-Warning 'Install is partial because one or more loaded TSF DLLs could not be replaced. Reboot, reinstall, and verify again for a complete result.'
}

[pscustomobject]$report
