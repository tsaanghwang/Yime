[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$output=Join-Path $PSScriptRoot 'arm64-r2-process-observer-diagnostic.json'
if(Test-Path -LiteralPath $output){throw 'Preserve previous diagnostic evidence.'}
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace YimeR2ProcessDiagnostic {
 public static class Native {
  [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder image,ref uint size);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool GetProcessTimes(IntPtr process,out long creation,out long exit,out long kernel,out long user);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool GetExitCodeProcess(IntPtr process,out uint exitCode);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool GetNamedPipeServerProcessId(IntPtr pipe,out uint pid);
  [DllImport("kernel32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool CloseHandle(IntPtr handle);
 }
}
'@
$statusPath='C:\Users\tsaan\AppData\Local\YimeCore Experimental Trial\runtime-status.json'
$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json
$record=[ordered]@{read_only_process_queries=$true;product_processes_started_or_stopped=$false;status_updated_at=$status.updated_at;observations=@();pipe_server_pid=$null;error=$null}
foreach($targetPid in @([uint32]$status.runtime_pid,[uint32]$status.broker_pid)){
 $row=[ordered]@{pid=$targetPid;cim_exists=$false;cim_image=$null;cim_created_at=$null;cim_error=$null;limited_access='0x1000';limited_image=$null;limited_created_at=$null;exit_code=$null;limited_error=$null}
 try{
  $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$targetPid) -Property ProcessId,ExecutablePath,CreationDate
  $row.cim_exists=$null -ne $cim
  if($null -ne $cim){$row.cim_image=$cim.ExecutablePath;if($null -ne $cim.CreationDate){$row.cim_created_at=$cim.CreationDate.ToUniversalTime().ToString('o')}}
 }catch{$row.cim_error=$_.Exception.Message}
 $handle=[YimeR2ProcessDiagnostic.Native]::OpenProcess(0x1000,$false,$targetPid)
 try{
  if($handle -eq [IntPtr]::Zero){throw ('OpenProcess: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
  $buffer=[Text.StringBuilder]::new(32768);[uint32]$capacity=32768
  if(-not [YimeR2ProcessDiagnostic.Native]::QueryFullProcessImageNameW($handle,0,$buffer,[ref]$capacity)){throw ('QueryFullProcessImageNameW: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
  $row.limited_image=$buffer.ToString()
  [long]$created=0;[long]$exited=0;[long]$kernel=0;[long]$user=0
  if(-not [YimeR2ProcessDiagnostic.Native]::GetProcessTimes($handle,[ref]$created,[ref]$exited,[ref]$kernel,[ref]$user)){throw ('GetProcessTimes: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
  $row.limited_created_at=[DateTime]::FromFileTimeUtc($created).ToString('o')
  [uint32]$exitCode=0
  if(-not [YimeR2ProcessDiagnostic.Native]::GetExitCodeProcess($handle,[ref]$exitCode)){throw ('GetExitCodeProcess: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
  $row.exit_code=$exitCode
 }catch{$row.limited_error=$_.Exception.Message}
 finally{if($handle -ne [IntPtr]::Zero){$null=[YimeR2ProcessDiagnostic.Native]::CloseHandle($handle)}}
 $record.observations+=@($row)
}
$pipe=[IO.Pipes.NamedPipeClientStream]::new('.',([string]$status.pipe_name).Substring(9),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous,[Security.Principal.TokenImpersonationLevel]::Identification)
try{
 $pipe.Connect(2000);[uint32]$serverPid=0
 if(-not [YimeR2ProcessDiagnostic.Native]::GetNamedPipeServerProcessId($pipe.SafePipeHandle.DangerousGetHandle(),[ref]$serverPid)){throw ('GetNamedPipeServerProcessId: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
 $record.pipe_server_pid=$serverPid
}catch{$record.error=$_.Exception.Message}
finally{$pipe.Dispose()}
$json=$record|ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($output,$json,[Text.UTF8Encoding]::new($false))
$json
