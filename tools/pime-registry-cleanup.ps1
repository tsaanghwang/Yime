# Shared registry cleanup for PIME/YIME text service profiles.
# Dot-source this file from install/uninstall/deploy scripts.

$script:PIMETextServiceClsid = "{35F67E9D-A54D-4177-9697-8B0AB71A9E04}"
$script:YimeProfileGuid = "{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"
$script:PIMETargetUserContract = Join-Path $PSScriptRoot 'dual-product\rime-pime-target-user.ps1'
if (-not (Test-Path -LiteralPath $script:PIMETargetUserContract -PathType Leaf)) {
    throw 'Rime/PIME target-user contract is unavailable.'
}
. $script:PIMETargetUserContract

function Assert-PIMERegistryTargetUserSid {
    param([Parameter(Mandatory = $true)][string]$TargetUserSid)
    $sid=Assert-YimePimeSidValue $TargetUserSid
    $current=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -cne $current) {
        throw 'Rime/PIME registry cleanup is restricted to the verified initiating user SID.'
    }
    return $sid
}

function Remove-RegistryTreeSafely {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-PIMEUserLanguageProfileValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUserSid,
        [string]$TextServiceClsid = $script:PIMETextServiceClsid
    )

    $TargetUserSid=Assert-PIMERegistryTargetUserSid $TargetUserSid
    $profileRoot=Get-YimePimeTargetUserRegistryPath -TargetUserSid $TargetUserSid `
        -RelativePath 'Control Panel\International\User Profile'
    if (-not (Test-Path -LiteralPath $profileRoot)) { return }
    foreach ($localeKey in @(Get-ChildItem -LiteralPath $profileRoot -ErrorAction SilentlyContinue)) {
        $properties = Get-ItemProperty -LiteralPath $localeKey.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) { continue }
        foreach ($property in $properties.PSObject.Properties) {
            if ($property.Name -like "*$TextServiceClsid*") {
                Write-Host "Removing target-user language profile value $($property.Name)"
                Remove-ItemProperty -LiteralPath $localeKey.PSPath -Name $property.Name -ErrorAction SilentlyContinue
            }
        }
    }
}

function Remove-PIMETextServiceRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUserSid,
        [string]$TextServiceClsid = $script:PIMETextServiceClsid,
        [switch]$IncludeClassRegistration
    )

    $TargetUserSid=Assert-PIMERegistryTargetUserSid $TargetUserSid
    $userTipRoot=Get-YimePimeTargetUserRegistryPath -TargetUserSid $TargetUserSid `
        -RelativePath "SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"
    Write-Host "Cleaning PIME text service registry entries ..."
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid"
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$TextServiceClsid"
    Remove-RegistryTreeSafely -Path $userTipRoot

    # Drop stale language-profile description keys (e.g. old 音元拼音 label).
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TextServiceClsid\LanguageProfile\0x00000804\$($script:YimeProfileGuid)"
    Remove-RegistryTreeSafely -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$TextServiceClsid\LanguageProfile\0x00000804\$($script:YimeProfileGuid)"

    Remove-PIMEUserLanguageProfileValues -TargetUserSid $TargetUserSid -TextServiceClsid $TextServiceClsid

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
        [Parameter(Mandatory = $true)]
        [string]$TargetUserSid,
        [string]$InstallRoot = "C:\Program Files (x86)\YIME",
        [switch]$IncludeClassRegistration
    )

    Unregister-PIMETextServiceDlls -InstallRoots @($InstallRoot)
    Remove-PIMETextServiceRegistry -TargetUserSid $TargetUserSid -IncludeClassRegistration:$IncludeClassRegistration
    Register-PIMETextServiceDlls -InstallRoot $InstallRoot
}
