param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Write-TestCommandFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }

    Set-Content -LiteralPath $Path -Value $Lines -Encoding Ascii
    $item = Get-Item -LiteralPath $Path
    $now = Get-Date
    $item.CreationTime = $now
    $item.LastWriteTime = $now
    $item.LastAccessTime = $now
}

function Copy-TestCommandTemplate {
    param(
        [string]$TemplateName,
        [string]$Destination
    )

    $templatePath = Join-Path $PSScriptRoot "templates\$TemplateName"
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Missing reinstall template: $templatePath"
    }

    Copy-Item -LiteralPath $templatePath -Destination $Destination -Force
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

Write-TestCommandFile -Path (Join-Path $repoRoot "Install-PIME-Test.cmd") -Lines @(
    "@echo off"
    "setlocal"
    ""
    "net session >nul 2>&1"
    "if not ""%errorlevel%""==""0"" ("
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""Start-Process -FilePath '%~f0' -Verb RunAs"""
    "    exit /b"
    ")"
    ""
    "cd /d ""%~dp0"""
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0dev-install.ps1"""
    "set ""EXIT_CODE=%errorlevel%"""
    ""
    "echo."
    "if ""%EXIT_CODE%""==""0"" ("
    "    echo YIME test install completed."
    ") else ("
    "    echo YIME test install failed with exit code %EXIT_CODE%."
    ")"
    "pause"
    "exit /b %EXIT_CODE%"
)

Copy-TestCommandTemplate -TemplateName "Reinstall-PIME-Test.cmd" -Destination (Join-Path $repoRoot "Reinstall-PIME-Test.cmd")

Write-TestCommandFile -Path (Join-Path $repoRoot "Uninstall-PIME-Test.cmd") -Lines @(
    "@echo off"
    "setlocal"
    ""
    "net session >nul 2>&1"
    "if not ""%errorlevel%""==""0"" ("
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""Start-Process -FilePath '%~f0' -Verb RunAs"""
    "    exit /b"
    ")"
    ""
    "cd /d ""%~dp0"""
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0dev-uninstall.ps1"""
    "set ""EXIT_CODE=%errorlevel%"""
    ""
    "echo."
    "if ""%EXIT_CODE%""==""0"" ("
    "    echo YIME test uninstall completed."
    ") else ("
    "    echo YIME test uninstall failed with exit code %EXIT_CODE%."
    ")"
    "pause"
    "exit /b %EXIT_CODE%"
)
