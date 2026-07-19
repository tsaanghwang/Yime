param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = "C:\Program Files (x86)\YIME"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script from an elevated PowerShell session."
    }
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }
}

function Resolve-FirstExistingPath {
    param(
        [string[]]$Paths,
        [string]$Description
    )

    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    throw "$Description not found. Tried: $($Paths -join ', ')"
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/MIR",
        "/R:1",
        "/W:1",
        "/NFL",
        "/NDL",
        "/NJH",
        "/NJS",
        "/NP"
    )

    if ($ExcludeDirs.Count -gt 0) {
        $robocopyArgs += "/XD"
        $robocopyArgs += $ExcludeDirs
    }
    if ($ExcludeFiles.Count -gt 0) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $ExcludeFiles
    }

    & robocopy @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed for $Source -> $Destination with exit code $LASTEXITCODE"
    }
}

function Copy-RequiredFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description,
        [switch]$AllowLocked
    )

    if (Test-Path -LiteralPath $Destination) {
        $sourceHash = (Get-FileHash -LiteralPath $Source).Hash
        $destinationHash = (Get-FileHash -LiteralPath $Destination).Hash
        if ($sourceHash -eq $destinationHash) {
            Write-Host "$Description is already up to date."
            return
        }
    }

    Write-Host "Copying $Description..."
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    } catch {
        if ($AllowLocked) {
            Write-Warning "Could not replace locked file $Description. Reboot for a clean DLL update."
            return
        }
        throw
    }
}

Assert-Admin

. (Join-Path $PSScriptRoot "pime-registry-cleanup.ps1")

$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$buildRoot = Join-Path $repoRoot "build"
$build64Root = Join-Path $repoRoot "build64"
$launcherExe = Resolve-FirstExistingPath -Description "Win32 PIMELauncher" -Paths @(
    (Join-Path $buildRoot "PIMELauncher\PIMELauncher.exe"),
    (Join-Path $buildRoot "PIMELauncher\Release\PIMELauncher.exe")
)
$x86Dll = Join-Path $buildRoot "PIMETextService\Release\PIMETextService.dll"
$x64Dll = Join-Path $build64Root "PIMETextService\Release\PIMETextService.dll"
$versionFile = Join-Path $repoRoot "version.txt"
$backendsFile = Join-Path $repoRoot "backends.json"
$goBackendRoot = Join-Path $repoRoot "go-backend\build\go-backend"

Assert-PathExists -Path $x86Dll -Description "Win32 PIMETextService.dll"
Assert-PathExists -Path $x64Dll -Description "x64 PIMETextService.dll"
Assert-PathExists -Path $versionFile -Description "version.txt"
Assert-PathExists -Path $backendsFile -Description "backends.json"
Assert-PathExists -Path (Join-Path $goBackendRoot "server.exe") -Description "go-backend server.exe"

& (Join-Path $PSScriptRoot 'verify-pe-architectures.ps1') `
    -RepoRoot $repoRoot `
    -X86TextService $x86Dll `
    -X64TextService $x64Dll `
    -X86Launcher $launcherExe
foreach ($toolExe in @(
    "tool-hub.exe",
    "lexicon-manager.exe",
    "system-lexicon-audit.exe",
    "blocklist-manager.exe",
    "reverse-lookup.exe",
    "settings-tool.exe",
    "diagnostics-tool.exe"
    "yime-layout-designer.exe"
)) {
    Assert-PathExists -Path (Join-Path $goBackendRoot $toolExe) -Description "go-backend $toolExe"
}

$stopScript = Join-Path $PSScriptRoot "dev-stop-pime.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & $stopScript -InstallRoots @($InstallRoot, "C:\Program Files (x86)\PIME") -Quiet
} else {
    Write-Host "Stopping any running PIMELauncher instance..."
    $installedLauncher = Join-Path $InstallRoot "PIMELauncher.exe"
    $runningLaunchers = @(Get-Process -Name "PIMELauncher" -ErrorAction SilentlyContinue)
    if ($runningLaunchers.Count -gt 0) {
        if (Test-Path -LiteralPath $installedLauncher) {
            Start-Process -FilePath $installedLauncher -ArgumentList "/quit" -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 2
        }
        $runningLaunchers = @(Get-Process -Name "PIMELauncher" -ErrorAction SilentlyContinue)
        if ($runningLaunchers.Count -gt 0) {
            $runningLaunchers | Stop-Process -Force
            Start-Sleep -Seconds 1
        }
    }
}

$installedX64Dll = Join-Path $InstallRoot "x64\PIMETextService.dll"
$installedX86Dll = Join-Path $InstallRoot "x86\PIMETextService.dll"
if ((Test-Path -LiteralPath $installedX64Dll) -or (Test-Path -LiteralPath $installedX86Dll)) {
    Write-Host "Unregistering installed text service DLLs before copying ..."
    Unregister-PIMETextServiceDlls -InstallRoots @($InstallRoot)
    Remove-PIMETextServiceRegistry
}

Write-Host "Creating installation layout at $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "x86") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "x64") -Force | Out-Null

Copy-RequiredFile -Source $versionFile -Destination (Join-Path $InstallRoot "version.txt") -Description "version.txt"
Copy-RequiredFile -Source $backendsFile -Destination (Join-Path $InstallRoot "backends.json") -Description "backends.json"
Copy-RequiredFile -Source $launcherExe -Destination (Join-Path $InstallRoot "PIMELauncher.exe") -Description "PIMELauncher.exe"
Copy-RequiredFile -Source $x86Dll -Destination (Join-Path $InstallRoot "x86\PIMETextService.dll") -Description "Win32 PIMETextService.dll" -AllowLocked
Copy-RequiredFile -Source $x64Dll -Destination (Join-Path $InstallRoot "x64\PIMETextService.dll") -Description "x64 PIMETextService.dll" -AllowLocked

Write-Host "Copying Go backend..."
Copy-Tree -Source $goBackendRoot -Destination (Join-Path $InstallRoot "go-backend")

Write-Host "Copying legal notices..."
$licensesRoot = Join-Path $InstallRoot "licenses"
New-Item -ItemType Directory -Path $licensesRoot -Force | Out-Null
foreach ($relativePath in @(
    "LICENSE.txt",
    "NOTICE.md",
    "AUTHORS.txt",
    "THIRD_PARTY_NOTICES.md",
    "LGPL-2.0.txt",
    "APACHE-2.0.txt",
    "json\LICENSE.MIT",
    "LICENSES\PIME-UPSTREAM-LICENSE.txt",
    "LICENSES\RIME-BSD-3-Clause.txt",
    "LICENSES\RIME-FROST-GPL-3.0.txt",
    "LICENSES\SIL-OFL-1.1.txt",
    "LICENSES\UNICODE-3.0.txt",
    "LICENSES\RUST-DEPENDENCIES.md"
)) {
    $source = Join-Path $repoRoot $relativePath
    Assert-PathExists -Path $source -Description "legal notice $relativePath"
    Copy-RequiredFile -Source $source -Destination (Join-Path $licensesRoot ([IO.Path]::GetFileName($relativePath))) -Description "legal notice $relativePath"
}

Write-Host "Registering text service DLLs ..."
Register-PIMETextServiceDlls -InstallRoot $InstallRoot

Write-Host "Writing launcher autorun and install markers..."
New-Item -Path "HKLM:\SOFTWARE\YIME" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\YIME" -Name "(default)" -Value $InstallRoot

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher" -Value (Join-Path $InstallRoot "PIMELauncher.exe")

Write-Host "Starting PIMELauncher..."
Start-Process -FilePath (Join-Path $InstallRoot "PIMELauncher.exe")

Write-Host "Developer install completed: $InstallRoot"
