param(
    [ValidateSet('x64', 'x86')][string]$Architecture = 'x64',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$hostPath = if ($Architecture -eq 'x86') {
    Join-Path $env:WINDIR 'SysWOW64\charmap.exe'
} else {
    Join-Path $env:WINDIR 'System32\charmap.exe'
}
if (-not (Test-Path -LiteralPath $hostPath)) { throw "TSF debug host was not found: $hostPath" }

$process = Start-Process -FilePath $hostPath -PassThru
$pidPath = Join-Path $RepoRoot ".tmp\tsf-debug-host-$Architecture.pid"
New-Item -ItemType Directory -Path (Split-Path -Parent $pidPath) -Force | Out-Null
Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ascii
Write-Host "Started $Architecture TSF debug host: $hostPath"
Write-Host "PID: $($process.Id)"
Write-Host "PID file: $pidPath"
[pscustomobject]@{ Architecture = $Architecture; ProcessId = $process.Id; Path = $hostPath; PidFile = $pidPath }
