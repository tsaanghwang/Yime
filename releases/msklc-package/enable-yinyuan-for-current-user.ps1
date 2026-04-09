param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-RegistryKey {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Get-YinyuanKlid {
    $productCode = '{5B9270C8-24B5-4092-A38E-123E4BBC9728}'
    $layoutsRoot = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'

    $slot = Get-ChildItem -Path $layoutsRoot | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $productCodeProperty = if ($null -ne $props) { $props.PSObject.Properties['Layout Product Code'] } else { $null }
        if ($null -ne $productCodeProperty -and [string]$productCodeProperty.Value -eq $productCode) {
            $_.PSChildName
        }
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($slot)) {
        throw 'Yinyuan is not registered in HKLM. Run install-amd64-manual.cmd as administrator first.'
    }

    return [string]$slot
}

function Start-CtfMonIfNeeded {
    $ctfmonPath = Join-Path $env:WINDIR 'System32\ctfmon.exe'
    if (-not (Get-Process -Name 'ctfmon' -ErrorAction SilentlyContinue) -and (Test-Path -Path $ctfmonPath)) {
        Start-Process -FilePath $ctfmonPath | Out-Null
    }
}

try {
    $yinyuanKlid = Get-YinyuanKlid
    $defaultChineseKlid = '00000804'
    $preloadPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Preload'
    $substitutesPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Substitutes'

    Ensure-RegistryKey -Path $preloadPath
    Ensure-RegistryKey -Path $substitutesPath

    Remove-ItemProperty -Path $substitutesPath -Name $defaultChineseKlid -ErrorAction SilentlyContinue

    $preloadValues = Get-ItemProperty -Path $preloadPath -ErrorAction SilentlyContinue
    $numericProperties = @()
    if ($null -ne $preloadValues) {
        $numericProperties = $preloadValues.PSObject.Properties | Where-Object { $_.Name -match '^[0-9]+$' }
    }

    $hasDefaultChinese = $false
    $hasYinyuan = $false
    foreach ($property in $numericProperties) {
        if ([string]$property.Value -ieq $defaultChineseKlid) {
            $hasDefaultChinese = $true
        }
        if ([string]$property.Value -ieq $yinyuanKlid) {
            $hasYinyuan = $true
        }
    }

    if (-not $hasDefaultChinese) {
        New-ItemProperty -Path $preloadPath -Name '1' -Value $defaultChineseKlid -PropertyType String -Force | Out-Null
    }

    if (-not $hasYinyuan) {
        $indices = $numericProperties | ForEach-Object { [int]$_.Name }
        $nextIndex = if ($indices.Count -eq 0) { 2 } else { [Math]::Max((($indices | Measure-Object -Maximum).Maximum + 1), 2) }
        New-ItemProperty -Path $preloadPath -Name ([string]$nextIndex) -Value $yinyuanKlid -PropertyType String -Force | Out-Null
    }

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class KeyboardLayoutNativeMethods
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadKeyboardLayoutW(string pwszKLID, uint Flags);
}
"@

    [KeyboardLayoutNativeMethods]::LoadKeyboardLayoutW($yinyuanKlid, 1) | Out-Null
    Start-CtfMonIfNeeded

    Write-Host 'Yinyuan was added as a separate current-user keyboard entry.'
    Write-Host ("Default Chinese keyboard remains: {0}" -f $defaultChineseKlid)
    Write-Host ("Yinyuan keyboard added as: {0}" -f $yinyuanKlid)
    Write-Host 'If it does not appear immediately, sign out and sign back in.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
