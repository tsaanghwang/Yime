param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'C:\Program Files (x86)\YIME',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Requesting elevation for developer install verification...'
    $elevatedArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"'),
        '-RepoRoot', ('"' + $repoRoot + '"'),
        '-InstallRoot', ('"' + $InstallRoot + '"')
    )
    if ($SkipBuild) { $elevatedArgs += '-SkipBuild' }
    # Start-Process -Wait follows the elevated process tree and would wait on
    # the intentionally persistent PIMELauncher started by dev-install.ps1.
    # Process.WaitForExit waits only for the elevated PowerShell wrapper.
    $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevatedArgs -PassThru
    $elevated.WaitForExit()
    exit $elevated.ExitCode
}

if (-not $SkipBuild) {
    Write-Host '=== Build source and package inputs ==='
    & (Join-Path $repoRoot 'build.bat')
    if ($LASTEXITCODE -ne 0) { throw "build.bat failed with exit code $LASTEXITCODE" }
}

& (Join-Path $PSScriptRoot 'assert-win32-build-prerequisites.ps1') -RepoRoot $repoRoot -RequireBuildArtifacts

Write-Host '=== Canonical reinstall (including DLL-lock fallback) ==='
& cmd.exe /d /c (Join-Path $repoRoot 'Reinstall-PIME-Test.cmd')
if ($LASTEXITCODE -ne 0) { throw "Reinstall-PIME-Test.cmd failed with exit code $LASTEXITCODE" }

Write-Host '=== Verify installed hashes, registry and launcher process ==='
$reportPath = Join-Path $repoRoot '.tmp\last-dev-end-to-end-verification.json'
& (Join-Path $PSScriptRoot 'verify-installed-runtime.ps1') `
    -RepoRoot $repoRoot `
    -InstallRoot $InstallRoot `
    -JsonPath $reportPath `
    -RequireRunningLauncher

Write-Host "Developer build/install/runtime verification passed. Report: $reportPath"
