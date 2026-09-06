param(
    [string]$InstallRoot = "C:\Program Files (x86)\YIME",
    [switch]$KeepInstallRoot,
    [string]$TargetUserSid
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

$ownershipHelper = Join-Path $PSScriptRoot 'dual-product\rime-pime-ownership.ps1'
if (-not (Test-Path -LiteralPath $ownershipHelper -PathType Leaf)) { throw 'Required Rime/PIME ownership helper is unavailable.' }
. $ownershipHelper
$TargetUserSid = Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit

. (Join-Path $PSScriptRoot "pime-registry-cleanup.ps1")

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

function Get-TextServiceDllUsers {
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

    $Path = (Assert-YimePimeOwnedRoot -Root $Path).path
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

function Add-InstallRootCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $owned = Assert-YimePimeOwnedRoot -Root $Path -AllowAbsent
    if (-not $owned.exists) { return }
    $normalized = $owned.path
    foreach ($existing in $Candidates) {
        if ($existing.Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $Candidates.Add($normalized)
}

function Get-InstallRootsForMaintenance {
    param([string]$SelectedRoot)
    # Only the explicitly selected/default current product root is maintained.
    # An unrelated legacy PIME directory or registry entry is not a dependency.
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    Add-InstallRootCandidate -Candidates $candidates -Path $SelectedRoot
    if ($candidates.Count -eq 0) { throw 'No identified Rime/PIME install root; refusing registry or directory cleanup.' }
    return ,$candidates
}
$installRoots = Get-InstallRootsForMaintenance -SelectedRoot $InstallRoot

$stopScript = Join-Path $PSScriptRoot "dev-stop-pime.ps1"
$stopResult = Invoke-YimePimeRequiredStopScript -ScriptPath $stopScript -InstallRoots $installRoots.ToArray() -TargetUserSid $TargetUserSid
if ($stopResult -eq 2) {
    Write-Host "PIMETextService.dll is still loaded; keeping installation tree for in-place upgrade."
    $KeepInstallRoot = $true
}
foreach ($root in $installRoots) { Assert-YimePimeOwnedRoot -Root $root | Out-Null }

Write-Host "Unregistering text service DLLs ..."
Unregister-PIMETextServiceDlls -InstallRoots $installRoots

Write-Host "Removing launcher autorun and install markers ..."
Remove-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryValue -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "PIMELauncher"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\YIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\WOW6432Node\YIME"
Remove-RegistryTree -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME"
# Legacy PIME install/uninstall keys are not this explicit root's cleanup targets.
# A legacy migration requires separate root/registration ownership validation.
Remove-PIMETextServiceRegistry -TargetUserSid $TargetUserSid -IncludeClassRegistration

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

