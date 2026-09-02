[CmdletBinding()]
param([Parameter(Mandatory)][int]$HostProcessId,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
$hostProcess=Get-Process -Id $HostProcessId
$start=$hostProcess.StartTime.ToUniversalTime()
$modules=@($hostProcess.Modules|Where-Object {$_.ModuleName -in @('YimeTextServiceExperiment.dll','PIMETextService.dll')}|ForEach-Object {
    [ordered]@{module=$_.ModuleName;path=$_.FileName;sha256=(Get-FileHash -LiteralPath $_.FileName).Hash.ToLowerInvariant()}
})
$stateRoot=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$config=Get-Content (Join-Path $stateRoot 'runtime-config.json') -Raw|ConvertFrom-Json
$events=@(Get-Content -LiteralPath (Join-Path $stateRoot 'evidence\language-bar-events.jsonl')|ForEach-Object {
    $event=$_|ConvertFrom-Json
    if($event.process_id -eq $HostProcessId -and ([DateTime]$event.timestamp).ToUniversalTime() -ge $start){$event}
})
$matches=@($modules|Where-Object {$_.path -eq (Join-Path $config.install_root 'x64\YimeTextServiceExperiment.dll')})
[ordered]@{schema_version='yimecore-live-local-host-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;
    process_id=$HostProcessId;process_name=$hostProcess.ProcessName;start_time_utc=$start.ToString('o');
    modules=$modules;trial_installed_dll_loaded=($matches.Count -eq 1);package_root=$config.install_root;
    manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $config.install_root 'package-manifest.json')).Hash.ToLowerInvariant();
    language_bar_events=$events;left_click_passed=(@($events|Where-Object {$_.event -eq 'left_click' -and $_.hresult -eq 0}).Count -gt 0);
    right_click_open_passed=(@($events|Where-Object {$_.event -eq 'right_click_open' -and $_.hresult -eq 0}).Count -gt 0);
    right_click_command_passed=(@($events|Where-Object {$_.event -eq 'right_click_command' -and $_.hresult -eq 0}).Count -gt 0);
    note='Loaded modules alone do not prove active profile or successful input; join with desktop-checks and saved host text.'
}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath -Encoding utf8
