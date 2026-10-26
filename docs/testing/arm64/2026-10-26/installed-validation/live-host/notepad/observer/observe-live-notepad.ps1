$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YimeLiveHostForeground {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint processId);
}
'@
[uint32]$foregroundProcessId=0
$null=[YimeLiveHostForeground]::GetWindowThreadProcessId([YimeLiveHostForeground]::GetForegroundWindow(),[ref]$foregroundProcessId)
$rows=@(Get-Process -Name Notepad -ErrorAction SilentlyContinue | ForEach-Object {
 $p=$_;$modules=@();$failure=$null
 try{$modules=@($p.Modules | Where-Object ModuleName -eq 'YimeTextServiceExperiment.dll' | ForEach-Object {
  [ordered]@{path=$_.FileName;sha256=(Get-FileHash -LiteralPath $_.FileName -Algorithm SHA256).Hash.ToLowerInvariant()}
 })}catch{$failure=$_.Exception.Message}
 [ordered]@{pid=$p.Id;image=$p.Path;foreground=($p.Id -eq $foregroundProcessId);has_main_window=($p.MainWindowHandle -ne 0);loaded_current_tip=$modules;module_observation_error=$failure}
})
$record=[ordered]@{captured_at=[DateTime]::UtcNow.ToString('o');foreground_pid=$foregroundProcessId;processes=$rows;read_only=$true}
$output='C:\dev\Yime\.tmp\notepad-observation-'+[guid]::NewGuid().ToString('N')+'.json'
$record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $output -Encoding UTF8
$record|ConvertTo-Json -Depth 6
Write-Output ('Evidence: '+$output)
