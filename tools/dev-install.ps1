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
        [string]$Description
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
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

Assert-Admin

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
$pythonRoot = Join-Path $repoRoot "python"
$nodeRoot = Join-Path $repoRoot "node"
$goBackendRoot = Join-Path $repoRoot "go-backend\build\go-backend"

Assert-PathExists -Path $x86Dll -Description "Win32 PIMETextService.dll"
Assert-PathExists -Path $x64Dll -Description "x64 PIMETextService.dll"
Assert-PathExists -Path $versionFile -Description "version.txt"
Assert-PathExists -Path $backendsFile -Description "backends.json"
Assert-PathExists -Path (Join-Path $pythonRoot "python3\python.exe") -Description "bundled Python runtime"
Assert-PathExists -Path (Join-Path $nodeRoot "node.exe") -Description "bundled Node runtime"
Assert-PathExists -Path (Join-Path $goBackendRoot "server.exe") -Description "go-backend server.exe"

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

$installedX64Dll = Join-Path $InstallRoot "x64\PIMETextService.dll"
$installedX86Dll = Join-Path $InstallRoot "x86\PIMETextService.dll"
if ((Test-Path -LiteralPath $installedX64Dll) -or (Test-Path -LiteralPath $installedX86Dll)) {
    Write-Host "Unregistering installed text service DLLs before copying..."
    if (Test-Path -LiteralPath $installedX64Dll) {
        & "$env:WINDIR\System32\regsvr32.exe" /u /s $installedX64Dll
    }
    if (Test-Path -LiteralPath $installedX86Dll) {
        & "$env:WINDIR\SysWOW64\regsvr32.exe" /u /s $installedX86Dll
    }
}

Write-Host "Creating installation layout at $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "x86") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "x64") -Force | Out-Null

Copy-RequiredFile -Source $versionFile -Destination (Join-Path $InstallRoot "version.txt") -Description "version.txt"
Copy-RequiredFile -Source $backendsFile -Destination (Join-Path $InstallRoot "backends.json") -Description "backends.json"
Copy-RequiredFile -Source $launcherExe -Destination (Join-Path $InstallRoot "PIMELauncher.exe") -Description "PIMELauncher.exe"
Copy-RequiredFile -Source $x86Dll -Destination (Join-Path $InstallRoot "x86\PIMETextService.dll") -Description "Win32 PIMETextService.dll"
Copy-RequiredFile -Source $x64Dll -Destination (Join-Path $InstallRoot "x64\PIMETextService.dll") -Description "x64 PIMETextService.dll"

Write-Host "Copying Python backend..."
Copy-Tree -Source $pythonRoot -Destination (Join-Path $InstallRoot "python") -ExcludeDirs @("__pycache__")

Write-Host "Copying Node backend..."
Copy-Tree -Source $nodeRoot -Destination (Join-Path $InstallRoot "node") -ExcludeDirs @("node_modules\.cache")

Write-Host "Copying Go backend..."
Copy-Tree -Source $goBackendRoot -Destination (Join-Path $InstallRoot "go-backend")

Write-Host "Registering text service DLLs..."
& "$env:WINDIR\System32\regsvr32.exe" /s (Join-Path $InstallRoot "x64\PIMETextService.dll")
& "$env:WINDIR\SysWOW64\regsvr32.exe" /s (Join-Path $InstallRoot "x86\PIMETextService.dll")

Write-Host "Writing launcher autorun and install markers..."
New-Item -Path "HKLM:\SOFTWARE\YIME" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\YIME" -Name "(default)" -Value $InstallRoot
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher" -Value (Join-Path $InstallRoot "PIMELauncher.exe")

Write-Host "Starting PIMELauncher..."
Start-Process -FilePath (Join-Path $InstallRoot "PIMELauncher.exe")

Write-Host "Developer install completed: $InstallRoot"
