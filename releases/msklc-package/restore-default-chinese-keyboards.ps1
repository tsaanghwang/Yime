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

function Start-CtfMonIfNeeded {
    $ctfmonPath = Join-Path $env:WINDIR 'System32\ctfmon.exe'
    if (-not (Get-Process -Name 'ctfmon' -ErrorAction SilentlyContinue) -and (Test-Path -Path $ctfmonPath)) {
        Start-Process -FilePath $ctfmonPath | Out-Null
    }
}

try {
    $defaultChineseKlid = '00000804'
    $preloadPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Preload'
    $substitutesPath = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Substitutes'

    Ensure-RegistryKey -Path $preloadPath
    Ensure-RegistryKey -Path $substitutesPath

    New-ItemProperty -Path $preloadPath -Name '1' -Value $defaultChineseKlid -PropertyType String -Force | Out-Null

    $preloadValues = Get-ItemProperty -Path $preloadPath -ErrorAction SilentlyContinue
    if ($null -ne $preloadValues) {
        foreach ($property in $preloadValues.PSObject.Properties) {
            if ($property.Name -match '^[0-9]+$' -and $property.Name -ne '1') {
                Remove-ItemProperty -Path $preloadPath -Name $property.Name -ErrorAction SilentlyContinue
            }
        }
    }

    Remove-ItemProperty -Path $substitutesPath -Name $defaultChineseKlid -ErrorAction SilentlyContinue
    Start-CtfMonIfNeeded

    Write-Host 'Current user keyboard preload was restored to the default Chinese keyboard only.'
    Write-Host 'Sign out and sign back in if your IME toolbar or punctuation state still looks stale.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
