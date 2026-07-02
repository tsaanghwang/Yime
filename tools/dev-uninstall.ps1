param(
    [string]$InstallRoot = "C:\Program Files (x86)\PIME",
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

$TextServiceClsid = "{35F67E9D-A54D-4177-9697-8B0AB71A9E04}"
$launcherExe = Join-Path $InstallRoot "PIMELauncher.exe"
$x64Dll = Join-Path $InstallRoot "x64\PIMETextService.dll"
$x86Dll = Join-Path $InstallRoot "x86\PIMETextService.dll"

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

function Remove-UserProfileValuesForTextService {
    param([string]$Clsid)

    $sidKeys = @(Get-ChildItem -LiteralPath "Registry::HKEY_USERS" -ErrorAction SilentlyContinue)
    foreach ($sidKey in $sidKeys) {
        $profileRoot = Join-Path $sidKey.PSPath "Control Panel\International\User Profile"
        if (-not (Test-Path -LiteralPath $profileRoot)) {
            continue
        }
        foreach ($localeKey in @(Get-ChildItem -LiteralPath $profileRoot -ErrorAction SilentlyContinue)) {
            $properties = Get-ItemProperty -LiteralPath $localeKey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) {
                continue
            }
            foreach ($property in $properties.PSObject.Properties) {
                if ($property.Name -like "*$Clsid*") {
                    Write-Host "Removing user language profile value $($property.Name)"
                    Remove-ItemProperty -LiteralPath $localeKey.PSPath -Name $property.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Report-TextServiceDllUsers {
    $output = & tasklist.exe /m PIMETextService.dll 2>$null
    if ($LASTEXITCODE -eq 0 -and $output) {
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
        Report-TextServiceDllUsers
        Write-Host "The installation tree could not be removed because one or more files are still locked."
        Write-Host "Switch to another input method, sign out or reboot Windows, then run Reinstall-PIME-Test.cmd again."
        throw
    }
}

$installRootFull = $InstallRoot
if (Test-Path -LiteralPath $InstallRoot) {
    $installRootFull = (Resolve-Path -LiteralPath $InstallRoot).Path
}

Write-Host "Stopping PIMELauncher and installed Go backend if they are running..."
if (Test-Path -LiteralPath $launcherExe) {
    & $launcherExe /quit | Out-Null
    Start-Sleep -Seconds 1
}
Stop-ProcessByPathPrefix -Name "PIMELauncher" -PathPrefix $installRootFull
Stop-ProcessByPathPrefix -Name "server" -PathPrefix (Join-Path $installRootFull "go-backend")
Start-Sleep -Milliseconds 500

Write-Host "Unregistering text service DLLs..."
if (Test-Path -LiteralPath $x64Dll) {
    & "$env:WINDIR\System32\regsvr32.exe" /u /s $x64Dll
}
if (Test-Path -LiteralPath $x86Dll) {
    & "$env:WINDIR\SysWOW64\regsvr32.exe" /u /s $x86Dll
}

Write-Host "Removing launcher autorun and install markers..."
Remove-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\PIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\PIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$TextServiceClsid"
Remove-RegistryTree -Path "HKCU:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"
Remove-RegistryTree -Path "Registry::HKEY_CLASSES_ROOT\CLSID\$TextServiceClsid"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\Classes\CLSID\$TextServiceClsid"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$TextServiceClsid"
Remove-UserProfileValuesForTextService -Clsid $TextServiceClsid

if (-not $KeepInstallRoot -and (Test-Path -LiteralPath $InstallRoot)) {
    Remove-InstallTree -Path $InstallRoot
} elseif ($KeepInstallRoot) {
    Write-Host "Keeping installation tree $InstallRoot"
}

Write-Host "Developer uninstall completed."
