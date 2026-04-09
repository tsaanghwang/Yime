param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    if (Test-IsAdministrator) {
        return
    }

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
    )

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($arguments -join ' ') -Wait -PassThru
    if ($null -eq $process) {
        throw 'Failed to launch the elevated installer process.'
    }

    exit $process.ExitCode
}

function Get-ExistingOrNewLayoutSlot {
    param(
        [string]$LayoutsRoot,
        [string]$LcidValue,
        [string]$ProductCode
    )

    $existing = Get-ChildItem -Path $LayoutsRoot | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $layoutProductCodeProperty = if ($null -ne $props) { $props.PSObject.Properties['Layout Product Code'] } else { $null }
        $layoutIdProperty = if ($null -ne $props) { $props.PSObject.Properties['Layout Id'] } else { $null }
        $layoutProductCode = if ($null -ne $layoutProductCodeProperty) { [string]$layoutProductCodeProperty.Value } else { $null }
        $layoutId = if ($null -ne $layoutIdProperty) { [string]$layoutIdProperty.Value } else { $null }

        if ($null -ne $layoutProductCode -and $layoutProductCode -eq $ProductCode) {
            [PSCustomObject]@{
                Klid = $_.PSChildName
                LayoutId = $layoutId
            }
        }
    } | Select-Object -First 1

    if ($null -ne $existing) {
        return $existing
    }

    for ($slot = 0; $slot -le 0x0FFF; $slot++) {
        $klid = 'A{0:X3}{1}' -f $slot, $LcidValue
        $candidatePath = Join-Path $LayoutsRoot $klid
        if (-not (Test-Path -Path $candidatePath)) {
            return [PSCustomObject]@{
                Klid = $klid
                LayoutId = '{0:X4}' -f $slot
            }
        }
    }

    throw 'No free custom keyboard layout slot was found under HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts.'
}

function Set-RegistryStringValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Ensure-RegistryKey {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Start-CtfMonIfNeeded {
    $ctfmonPath = Join-Path $env:WINDIR 'System32\ctfmon.exe'
    if (-not (Test-Path -Path $ctfmonPath)) {
        Write-Warning "ctfmon.exe was not found at $ctfmonPath"
        return
    }

    if (-not (Get-Process -Name 'ctfmon' -ErrorAction SilentlyContinue)) {
        Write-Host 'Starting ctfmon.exe to refresh the language switcher...'
        Start-Process -FilePath $ctfmonPath | Out-Null
    }
}

try {
    Ensure-Administrator

    $scriptDir = Split-Path -Parent $PSCommandPath
    $packageName = 'Chinese (Simplified) - Yinyuan'
    $layoutFileName = 'Yinyuan.dll'
    $lcidValue = '0804'
    $productCode = '{5B9270C8-24B5-4092-A38E-123E4BBC9728}'

    $amd64Source = Join-Path $scriptDir 'amd64\Yinyuan.dll'
    $wow64Source = Join-Path $scriptDir 'wow64\Yinyuan.dll'

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This manual installer currently supports only 64-bit Windows.'
    }

    if (-not (Test-Path -Path $amd64Source)) {
        throw "Missing amd64 DLL: $amd64Source"
    }

    if (-not (Test-Path -Path $wow64Source)) {
        throw "Missing wow64 DLL: $wow64Source"
    }

    $system32Target = Join-Path $env:WINDIR 'System32\Yinyuan.dll'
    $syswow64Target = Join-Path $env:WINDIR 'SysWOW64\Yinyuan.dll'

    Write-Host 'Copying keyboard DLLs into system directories...'
    Copy-Item -Path $amd64Source -Destination $system32Target -Force
    Copy-Item -Path $wow64Source -Destination $syswow64Target -Force

    $layoutsRoot = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
    $slot = Get-ExistingOrNewLayoutSlot -LayoutsRoot $layoutsRoot -LcidValue $lcidValue -ProductCode $productCode
    $layoutKeyPath = Join-Path $layoutsRoot $slot.Klid
    Write-Host ("Registering keyboard layout {0} with Layout Id {1}..." -f $slot.Klid, $slot.LayoutId)
    New-Item -Path $layoutKeyPath -Force | Out-Null
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout Display Name' -Value ('@%SystemRoot%\system32\{0},-1000' -f $layoutFileName)
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout File' -Value $layoutFileName
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout Id' -Value $slot.LayoutId
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout Locale Name' -Value ('@%SystemRoot%\system32\{0},-1100' -f $layoutFileName)
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout Product Code' -Value $productCode
    Set-RegistryStringValue -Path $layoutKeyPath -Name 'Layout Text' -Value $packageName

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class KeyboardLayoutNativeMethods
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadKeyboardLayoutW(string pwszKLID, uint Flags);
}
"@

    $KLF_ACTIVATE = 0x00000001
    $loadResult = [KeyboardLayoutNativeMethods]::LoadKeyboardLayoutW($slot.Klid, $KLF_ACTIVATE)
    if ($loadResult -eq [IntPtr]::Zero) {
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Warning ("LoadKeyboardLayoutW failed for {0} (Win32 error {1}). The layout is registered but you may need to sign out and sign back in." -f $slot.Klid, $lastError)
    } else {
        Write-Host ("LoadKeyboardLayoutW succeeded for {0}." -f $slot.Klid)
    }

    Start-CtfMonIfNeeded

    Write-Host ''
    Write-Host 'Manual keyboard installation finished.'
    Write-Host ("KLID: {0}" -f $slot.Klid)
    Write-Host ("Layout Id: {0}" -f $slot.LayoutId)
    Write-Host 'The installer did not modify HKCU\Keyboard Layout\Preload or HKCU\Keyboard Layout\Substitutes.'
    Write-Host 'This avoids replacing the keyboard used by Microsoft Pinyin, Sogou, or other Chinese IMEs.'
    Write-Host 'If you want to test Yinyuan, first sign out and sign back in, then add or activate it manually without replacing your default Chinese keyboard.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
