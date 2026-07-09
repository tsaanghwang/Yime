param(
    [string]$InstallRoot = "C:\Program Files (x86)\YIME",
    [switch]$KeepInstallRoot
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script from an elevated PowerShell session."
    }
}

Assert-Admin

. (Join-Path $PSScriptRoot "pime-registry-cleanup.ps1")

$LegacyDefaultInstallRoot = "C:\Program Files (x86)\PIME"

function Remove-RegistryTree {
    param([string]$Path)
    Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
}

function Stop-ProcessByPathPrefix {
    param(
        [string]$Name,
        [string]$PathPrefix
    )

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $path = ""
        try {
            $path = $process.Path
        } catch {
            $path = ""
        }
        if ($path -and $path.StartsWith($PathPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "Stopping $Name pid=$($process.Id)"
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-RegistryValue {
    $output = @(& tasklist.exe /m PIMETextService.dll 2>$null)
    if ($LASTEXITCODE -eq 0 -and $output.Count -gt 1) {
        return $output
    }
    return @()
}

function Test-TextServiceDllLoaded {
    return (Get-TextServiceDllUsers).Count -gt 0
}

function Show-TextServiceDllUsers {
    $output = Get-TextServiceDllUsers
    if ($output) {
        Write-Host ""
        Write-Host "PIMETextService.dll is still loaded by these processes:"
        $output | ForEach-Object { Write-Host $_ }
        Write-Host ""
    }
}

function Remove-InstallTree {
    param([string]$Path)

    Write-Host "Removing installation tree $Path"
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } catch {
        Show-TextServiceDllUsers
        Write-Host "The installation tree could not be removed because one or more files are still locked."
        Write-Host "Switch to another input method, sign out or reboot Windows, then run Reinstall-PIME-Test.cmd again."
        throw
    }
}

function Get-NormalizedPath {
    param([string]$Path)

    if (-not $Path) {
        return $null
    }

    try {
        if (Test-Path -LiteralPath $Path) {
            return (Resolve-Path -LiteralPath $Path).Path
        }
    } catch {
    }

    return $Path.TrimEnd("\")
}

function Add-InstallRootCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Path
    )

    $normalized = Get-NormalizedPath -Path $Path
    if (-not $normalized) {
        return
    }
    foreach ($existing in $Candidates) {
        if ($existing.Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $Candidates.Add($normalized)
}

$installRoots = New-Object 'System.Collections.Generic.List[string]'
Add-InstallRootCandidate -Candidates $installRoots -Path $InstallRoot

try {
    $legacyInstallKey = Get-Item -Path "HKLM:\SOFTWARE\PIME" -ErrorAction SilentlyContinue
    if ($legacyInstallKey) {
        $legacyInstallRootFromRegistry = $legacyInstallKey.GetValue("")
    }
    Add-InstallRootCandidate -Candidates $installRoots -Path $legacyInstallRootFromRegistry
} catch {
}

Add-InstallRootCandidate -Candidates $installRoots -Path $LegacyDefaultInstallRoot

$stopScript = Join-Path $PSScriptRoot "dev-stop-pime.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & $stopScript -InstallRoots $installRoots -Quiet
    if ($LASTEXITCODE -eq 2) {
        Write-Host "PIMETextService.dll is still loaded; keeping installation tree for in-place upgrade."
        $KeepInstallRoot = $true
    }
} else {
    Write-Host "Stopping PIMELauncher and installed Go backend if they are running..."
    foreach ($root in $installRoots) {
        $launcherExe = Join-Path $root "PIMELauncher.exe"
        if (Test-Path -LiteralPath $launcherExe) {
            & $launcherExe /quit | Out-Null
            Start-Sleep -Seconds 1
        }
        Stop-ProcessByPathPrefix -Name "PIMELauncher" -PathPrefix $root
        Stop-ProcessByPathPrefix -Name "server" -PathPrefix (Join-Path $root "go-backend")
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "Unregistering text service DLLs ..."
Unregister-PIMETextServiceDlls -InstallRoots $installRoots

Write-Host "Removing launcher autorun and install markers ..."
Remove-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\YIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\YIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\PIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\PIME"
Remove-PIMETextServiceRegistry -IncludeClassRegistration

if (-not $KeepInstallRoot -and (Test-TextServiceDllLoaded)) {
    Show-TextServiceDllUsers
    Write-Host "Skipping installation tree removal because PIMETextService.dll is still loaded."
    Write-Host "Continuing with in-place upgrade; reboot later for a clean DLL replacement."
    $KeepInstallRoot = $true
}

if (-not $KeepInstallRoot) {
    foreach ($root in $installRoots) {
        if (Test-Path -LiteralPath $root) {
            Remove-InstallTree -Path $root
        }
    }
} elseif ($KeepInstallRoot) {
    Write-Host "Keeping installation trees under:"
    foreach ($root in $installRoots) {
        Write-Host "  $root"
    }
}

Write-Host "Developer uninstall completed."

