param([Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Report){throw 'Preserve prior observation'}
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class Live18uReadOnly {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left,top,right,bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct GUI { public uint cbSize,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public RECT rcCaret; }
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint flags);
 [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid,ref GUI g);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 public static string Class(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,256);return s.ToString();}
}
'@
$foreground=[Live18uReadOnly]::GetForegroundWindow()
[uint32]$foregroundProcessId=0
$foregroundThreadId=[Live18uReadOnly]::GetWindowThreadProcessId($foreground,[ref]$foregroundProcessId)
$info=New-Object Live18uReadOnly+GUI
$info.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($info)
$guiRead=[Live18uReadOnly]::GetGUIThreadInfo(0,[ref]$info)
[uint32]$focusProcessId=0
$focusThreadId=[Live18uReadOnly]::GetWindowThreadProcessId($info.focus,[ref]$focusProcessId)
$rows=@(Get-Process -Name Notepad,YimeTouchKeyboard,YimeBroker18u,Yime18uInstalledRuntime -ErrorAction SilentlyContinue | ForEach-Object {
 $p=$_; $modules=@(); $failure=$null
 try{$modules=@($p.Modules | Where-Object {$_.ModuleName -like 'Yime*.dll'} | ForEach-Object {
  [ordered]@{path=$_.FileName;sha256=(Get-FileHash -LiteralPath $_.FileName -Algorithm SHA256).Hash.ToLowerInvariant()}
 })}catch{$failure=$_.Exception.Message}
 [ordered]@{pid=$p.Id;name=$p.ProcessName;image=$p.Path;startUtc=$p.StartTime.ToUniversalTime().ToString('o');mainHwnd=$p.MainWindowHandle.ToInt64();loadedYimeModules=$modules;moduleObservationError=$failure}
})
$record=[ordered]@{schema='18u-notepad-live-readonly-v1';observedUtc=[DateTime]::UtcNow.ToString('o');foreground=[ordered]@{hwnd=$foreground.ToInt64();pid=$foregroundProcessId;tid=$foregroundThreadId;class=[Live18uReadOnly]::Class($foreground)};guiRead=$guiRead;focus=[ordered]@{hwnd=$info.focus.ToInt64();pid=$focusProcessId;tid=$focusThreadId;class=[Live18uReadOnly]::Class($info.focus);root=[Live18uReadOnly]::GetAncestor($info.focus,2).ToInt64()};processes=$rows;readOnly=$true;uiAutomationOrInput=$false}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report),($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ($record|ConvertTo-Json -Depth 8)
