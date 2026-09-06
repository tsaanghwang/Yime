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
        throw "Missing command template: $templatePath"
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    Copy-Item -LiteralPath $templatePath -Destination $Destination -Force
    $item = Get-Item -LiteralPath $Destination
    $now = Get-Date
    $item.CreationTime = $now
    $item.LastWriteTime = $now
    $item.LastAccessTime = $now
}

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

Copy-TestCommandTemplate -TemplateName "Install-PIME-Test.cmd" -Destination (Join-Path $repoRoot "Install-PIME-Test.cmd")

Copy-TestCommandTemplate -TemplateName "Reinstall-PIME-Test.cmd" -Destination (Join-Path $repoRoot "Reinstall-PIME-Test.cmd")

Copy-TestCommandTemplate -TemplateName "Uninstall-PIME-Test.cmd" -Destination (Join-Path $repoRoot "Uninstall-PIME-Test.cmd")
