[CmdletBinding()]
param(
    [string]$TaskName = 'Yime Daily BCC Validation',
    [datetime]$DailyAt = '03:00',
    [string]$Python,
    [string]$Go = 'go',
    [string]$IndexRoot,
    [string]$OutputRoot,
    [int]$SampleLimit = 20,
    [int]$ScanLimit = 5000,
    [switch]$FailOnMismatch,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$runner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'run-daily-bcc-validation.ps1'))

function Quote-TaskArgument([string]$Value) {
    if ($Value.Contains('"')) {
        throw "task argument contains an unsupported quote: $Value"
    }
    return '"' + $Value + '"'
}

$arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Quote-TaskArgument $runner),
    '-SampleLimit',
    $SampleLimit,
    '-ScanLimit',
    $ScanLimit
)
if (-not [string]::IsNullOrWhiteSpace($Python)) {
    $arguments += @('-Python', (Quote-TaskArgument ([IO.Path]::GetFullPath($Python))))
}
if (-not [string]::IsNullOrWhiteSpace($Go)) {
    $arguments += @('-Go', (Quote-TaskArgument $Go))
}
if (-not [string]::IsNullOrWhiteSpace($IndexRoot)) {
    $arguments += @('-IndexRoot', (Quote-TaskArgument ([IO.Path]::GetFullPath($IndexRoot))))
}
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $arguments += @('-OutputRoot', (Quote-TaskArgument ([IO.Path]::GetFullPath($OutputRoot))))
}
if ($FailOnMismatch) {
    $arguments += '-FailOnMismatch'
}
$argumentLine = $arguments -join ' '
$plan = [ordered]@{
    task_name = $TaskName
    schedule = 'daily'
    local_time = $DailyAt.ToString('HH:mm')
    executable = 'powershell.exe'
    arguments = $argumentLine
    apply = [bool]$Apply
    writes_only_generated_reports = $true
    imports_runtime_or_user_candidates = $false
}

if (-not $Apply) {
    $plan | ConvertTo-Json -Depth 4
    Write-Host 'Dry run only. Pass -Apply to register or replace the task.'
    exit 0
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentLine -WorkingDirectory (Split-Path $runner -Parent)
$trigger = New-ScheduledTaskTrigger -Daily -At $DailyAt
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
$plan | ConvertTo-Json -Depth 4
