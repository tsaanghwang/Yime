$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/yimecore/arm64-go-environment.ps1')
foreach($value in @($null,'','-tags=synthetic')) {
    [Environment]::SetEnvironmentVariable('GOFLAGS',$value,'Process')
    $before=[Environment]::GetEnvironmentVariable('GOFLAGS','Process')
    $beforePresent=[Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS')
    Invoke-Arm64ProductGoEnvironment {}
    [ordered]@{requested=$value;before=$before;beforePresent=$beforePresent;after=[Environment]::GetEnvironmentVariable('GOFLAGS','Process');afterPresent=[Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS')}|ConvertTo-Json -Compress
}
[Environment]::SetEnvironmentVariable('GOFLAGS',[NullString]::Value,'Process')
$before=[Environment]::GetEnvironmentVariable('GOFLAGS','Process')
$beforePresent=[Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS')
Invoke-Arm64ProductGoEnvironment {}
[ordered]@{requested='NullString';before=$before;beforePresent=$beforePresent;after=[Environment]::GetEnvironmentVariable('GOFLAGS','Process');afterPresent=[Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS')}|ConvertTo-Json -Compress
