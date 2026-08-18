param(
    [string[]]$InstallRoots = @(
        "C:\Program Files (x86)\YIME",
        "C:\Program Files (x86)\PIME"
    ),
    [switch]$Quiet,
    [switch]$Auto
)

$ErrorActionPreference = "Stop"
$stopFailures = [Collections.Generic.List[string]]::new()

function Write-Step {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Stop-ProcessByPathPrefix {
    param(
        [string]$Name,
        [string]$PathPrefix
    )

    $stopped = 0
    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $path = ""
        try {
            $path = $process.Path
        } catch {
            $path = ""
        }
        $normalizedPrefix = [IO.Path]::GetFullPath($PathPrefix).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $normalizedPath = if ($path) { [IO.Path]::GetFullPath($path) } else { '' }
        if ($normalizedPath.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Step "Stopping $Name pid=$($process.Id)"
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $stopped++
            } catch {
                $stopFailures.Add("$Name pid=$($process.Id): $($_.Exception.Message)")
            }
        }
    }
    return $stopped
}

if (-not $Quiet -and -not $Auto) {
    Write-Host ""
    Write-Host "Before reinstall, please:"
    Write-Host "  1. Switch input method to English or another IME (not Yime)."
    Write-Host "  2. Close apps where you are typing (Notepad, browser, IDE, etc.)."
    Write-Host ""
    Read-Host "Press Enter when ready"
    Write-Host ""
} elseif (-not $Quiet -and $Auto) {
    Write-Host "Auto mode: stopping PIME processes (switch away from Yime if you can)."
    Write-Host ""
}

foreach ($root in $InstallRoots) {
    $launcherExe = Join-Path $root "PIMELauncher.exe"
    if (Test-Path -LiteralPath $launcherExe) {
        Write-Step "Requesting graceful quit: $launcherExe"
        Start-Process -FilePath $launcherExe -ArgumentList "/quit" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
}

Start-Sleep -Seconds 2

foreach ($root in $InstallRoots) {
    Stop-ProcessByPathPrefix -Name "PIMELauncher" -PathPrefix $root | Out-Null
    Stop-ProcessByPathPrefix -Name "server" -PathPrefix (Join-Path $root "go-backend") | Out-Null
    Stop-ProcessByPathPrefix -Name "input-toolbar" -PathPrefix (Join-Path $root "go-backend") | Out-Null
    Stop-ProcessByPathPrefix -Name "yime-trainer" -PathPrefix (Join-Path $root "go-backend") | Out-Null
}

Start-Sleep -Seconds 2

$remainingProcesses = [Collections.Generic.List[string]]::new()
foreach ($root in $InstallRoots) {
    foreach ($target in @(
        @{ Name = 'PIMELauncher'; Root = $root },
        @{ Name = 'server'; Root = (Join-Path $root 'go-backend') },
        @{ Name = 'input-toolbar'; Root = (Join-Path $root 'go-backend') },
        @{ Name = 'yime-trainer'; Root = (Join-Path $root 'go-backend') }
    )) {
        $normalizedPrefix = [IO.Path]::GetFullPath($target.Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        foreach ($process in @(Get-Process -Name $target.Name -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = $process.Path } catch { $path = '' }
            if ($path -and [IO.Path]::GetFullPath($path).StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $remainingProcesses.Add("$($target.Name) pid=$($process.Id) path=$path")
            }
        }
    }
}
if ($stopFailures.Count -gt 0 -or $remainingProcesses.Count -gt 0) {
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Error: one or more PIME/YIME processes could not be stopped:'
        foreach ($failure in $stopFailures) { Write-Host "  stop failed: $failure" }
        foreach ($remaining in $remainingProcesses) { Write-Host "  still running: $remaining" }
        Write-Host 'Close the listed process or run this command from an elevated PowerShell, then retry.'
        Write-Host ''
    }
    exit 3
}

$dllUsers = & tasklist.exe /m PIMETextService.dll 2>$null
if ($LASTEXITCODE -eq 0 -and $dllUsers -and ($dllUsers.Count -gt 1)) {
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "Warning: PIMETextService.dll is still loaded (often explorer.exe):"
        $dllUsers | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Will skip full uninstall and do an in-place install (go-backend can still update)."
        Write-Host "For a clean reinstall, reboot Windows first, then run this script again."
        Write-Host ""
    }
    exit 2
}

Write-Step "PIME/YIME processes stopped."
exit 0
