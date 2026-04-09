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
        throw 'Failed to launch the elevated unregister process.'
    }

    exit $process.ExitCode
}

function Get-YinyuanSlots {
    $layoutsRoot = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
    Get-ChildItem -Path $layoutsRoot | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $textProp = if ($null -ne $props) { $props.PSObject.Properties['Layout Text'] } else { $null }
        $fileProp = if ($null -ne $props) { $props.PSObject.Properties['Layout File'] } else { $null }
        if (($null -ne $textProp -and [string]$textProp.Value -like '*Yinyuan*') -or ($null -ne $fileProp -and [string]$fileProp.Value -eq 'Yinyuan.dll')) {
            [PSCustomObject]@{
                Klid = $_.PSChildName
                Path = $_.PSPath
            }
        }
    }
}

function Remove-UserKlidReferences {
    param(
        [string[]]$Klids
    )

    $preloadPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Preload'
    if (Test-Path -Path $preloadPath) {
        $preloadValues = Get-ItemProperty -Path $preloadPath -ErrorAction SilentlyContinue
        if ($null -ne $preloadValues) {
            foreach ($property in $preloadValues.PSObject.Properties) {
                if ($property.Name -match '^[0-9]+$' -and $Klids -contains [string]$property.Value) {
                    Remove-ItemProperty -Path $preloadPath -Name $property.Name -ErrorAction SilentlyContinue
                }
            }
        }
        $remaining = (Get-ItemProperty -Path $preloadPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -match '^[0-9]+$' }
        if (-not $remaining) {
            New-ItemProperty -Path $preloadPath -Name '1' -Value '00000804' -PropertyType String -Force | Out-Null
        }
    }

    $substitutesPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Substitutes'
    if (Test-Path -Path $substitutesPath) {
        $substituteValues = Get-ItemProperty -Path $substitutesPath -ErrorAction SilentlyContinue
        if ($null -ne $substituteValues) {
            foreach ($property in $substituteValues.PSObject.Properties) {
                if ($Klids -contains [string]$property.Value) {
                    Remove-ItemProperty -Path $substitutesPath -Name $property.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

try {
    Ensure-Administrator

    $slots = @(Get-YinyuanSlots)
    if ($slots.Count -eq 0) {
        Write-Host 'No Yinyuan machine-level keyboard layout registration was found.'
        exit 0
    }

    $klids = $slots | ForEach-Object { $_.Klid }
    Remove-UserKlidReferences -Klids $klids

    foreach ($slot in $slots) {
        Remove-Item -Path $slot.Path -Recurse -Force -ErrorAction Stop
        Write-Host ("Removed HKLM keyboard layout slot: {0}" -f $slot.Klid)
    }

    foreach ($dllPath in @(
        (Join-Path $env:WINDIR 'System32\Yinyuan.dll'),
        (Join-Path $env:WINDIR 'SysWOW64\Yinyuan.dll')
    )) {
        if (Test-Path -Path $dllPath) {
            Remove-Item -Path $dllPath -Force -ErrorAction SilentlyContinue
            Write-Host ("Removed DLL: {0}" -f $dllPath)
        }
    }

    Write-Host 'Yinyuan machine-level registration was removed.'
    Write-Host 'Sign out and sign back in before rebuilding in MSKLC.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
