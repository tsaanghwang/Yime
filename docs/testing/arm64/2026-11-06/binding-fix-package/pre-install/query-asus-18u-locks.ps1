param([Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../../installer/simple/Product.psm1') -Force
$root=Join-Path $env:ProgramFiles 'YimeCore 18u Touch'
$dll=Join-Path $root 'arm64/YimeTextService18u.dll'
if(-not (Test-Path -LiteralPath $dll -PathType Leaf)){throw 'Expected old installed 18u DLL is absent'}
$users=@(Get-ProductFileUsers @($dll))
$rows=@($users|ForEach-Object {
    [ordered]@{pid=$_.Process.Pid;creationTicks=[uint64](([int64]$_.Process.Start.dwHighDateTime -shl 32) -bor ([int64]$_.Process.Start.dwLowDateTime -band 4294967295L));
        application=$_.Application;service=$_.Service;session=$_.Session}
})
$result=[ordered]@{schema='18u-read-only-dll-users-v1';observedUTC=[DateTime]::UtcNow.ToString('o');dll=$dll;query='RestartManager';shutdownOrRestartRequested=$false;users=$rows}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report),($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output ('Read-only installed 18u DLL users: '+$rows.Count)
