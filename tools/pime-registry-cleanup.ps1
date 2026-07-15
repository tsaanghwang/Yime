# Shared registry cleanup for PIME/YIME text service profiles.
# Dot-source this file from install/uninstall/deploy scripts.

$script:PIMETextServiceClsid = "{35F67E9D-A54D-4177-9697-8B0AB71A9E04}"
$script:YimeProfileGuid = "{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"

function Remove-RegistryTreeSafely {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-PIMEUserLanguageProfileValues {
    param(
        [string]$TextServiceClsid = $script:PIMETextServiceClsid
    )

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
                if ($property.Name -like "*$TextServiceClsid*") {
                    Write-Host "Removing user language profile value $($property.Name)"
                    Remove-ItemProperty -LiteralPath $localeKey.PSPath -Name $property.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Remove-PIMETextServiceRegistry {
    param(
        [string]$TextServiceClsid = $script:PIMETextServiceClsid,
        [switch]$IncludeClassRegistration
    )

    Write-Host "Cleaning PIME text service registry entries ..."
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$TextServiceClsid"
    Remove-RegistryTreeSafely -Path "HKCU:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"

    # Drop stale language-profile description keys (e.g. old 音元拼音 label).
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid\LanguageProfile\0x00000804\$($script:YimeProfileGuid)"
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$TextServiceClsid\LanguageProfile\0x00000804\$($script:YimeProfileGuid)"

    Remove-PIMEUserLanguageProfileValues -TextServiceClsid $TextServiceClsid

    if ($IncludeClassRegistration) {
        Remove-RegistryTreeSafely -Path "Registry::HKEY_CLASSES_ROOT\CLSID\$TextServiceClsid"
        Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\Classes\CLSID\$TextServiceClsid"
        Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$TextServiceClsid"
    }
}

function Unregister-PIMETextServiceDlls {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$InstallRoots
    )

    Write-Host "Unregistering text service DLLs ..."
    foreach ($root in $InstallRoots) {
        $x64Dll = Join-Path $root "x64\PIMETextService.dll"
        $x86Dll = Join-Path $root "x86\PIMETextService.dll"
        if (Test-Path -LiteralPath $x64Dll) {
            & "$env:WINDIR\System32\regsvr32.exe" /u /s $x64Dll
        }
        if (Test-Path -LiteralPath $x86Dll) {
            & "$env:WINDIR\SysWOW64\regsvr32.exe" /u /s $x86Dll
        }
    }
}

function Register-PIMETextServiceDlls {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot
    )

    $x86Dll = Join-Path $InstallRoot "x86\PIMETextService.dll"
    $x64Dll = Join-Path $InstallRoot "x64\PIMETextService.dll"
    if (-not (Test-Path -LiteralPath $x86Dll) -or -not (Test-Path -LiteralPath $x64Dll)) {
        throw "PIMETextService.dll not found under $InstallRoot"
    }

    Write-Host "Registering text service DLLs and refreshing language profile names from ime.json ..."
    & "$env:WINDIR\System32\regsvr32.exe" /s $x64Dll
    & "$env:WINDIR\SysWOW64\regsvr32.exe" /s $x86Dll
}

function Reset-PIMETextServiceProfiles {
    param(
        [string]$InstallRoot = "C:\Program Files (x86)\YIME",
        [switch]$IncludeClassRegistration
    )

    Unregister-PIMETextServiceDlls -InstallRoots @($InstallRoot)
    Remove-PIMETextServiceRegistry -IncludeClassRegistration:$IncludeClassRegistration
    Register-PIMETextServiceDlls -InstallRoot $InstallRoot
}
