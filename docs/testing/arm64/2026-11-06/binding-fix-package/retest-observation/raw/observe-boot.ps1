param([Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$os=Get-CimInstance -ClassName Win32_OperatingSystem
$processes=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe' OR Name='Notepad.exe' OR Name='Codex.exe' OR Name='Yime18uInstalledRuntime.exe' OR Name='YimeBroker18u.exe' OR Name='YimeTouchKeyboard.exe'" | ForEach-Object {
    [ordered]@{pid=$_.ProcessId;name=$_.Name;path=$_.ExecutablePath;startUtc=$_.CreationDate.ToUniversalTime().ToString('o')}
})
$result=[ordered]@{schema='binding-retest-boot-observation-v1';observedUtc=[DateTime]::UtcNow.ToString('o');computer=$env:COMPUTERNAME;lastBootUpUtc=$os.LastBootUpTime.ToUniversalTime().ToString('o');processes=$processes;readOnly=$true}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report),($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ($result|ConvertTo-Json -Depth 6)
