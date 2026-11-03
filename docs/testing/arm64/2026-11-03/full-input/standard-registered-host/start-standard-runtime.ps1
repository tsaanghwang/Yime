$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$reportRoot=Join-Path $PSScriptRoot 'standard-installed-startup'
if(Test-Path -LiteralPath $reportRoot){throw 'Startup evidence already exists; do not repeat startup automatically.'}
$null=New-Item -ItemType Directory -Path $reportRoot
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class YimeTokenRead {
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool b,uint p);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr h,uint a,out IntPtr t);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr t,int c,IntPtr b,int n,out int r);
 [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr s);
 [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr s,uint i);
 public static uint[] Read(uint pid) {
  IntPtr p=OpenProcess(0x1000,false,pid),t=IntPtr.Zero,b=IntPtr.Zero;
  if(p==IntPtr.Zero) throw new Win32Exception();
  try { if(!OpenProcessToken(p,8,out t))throw new Win32Exception();
   int n; b=Marshal.AllocHGlobal(4);
   if(!GetTokenInformation(t,20,b,4,out n))throw new Win32Exception();
   uint e=(uint)Marshal.ReadInt32(b); Marshal.FreeHGlobal(b);b=IntPtr.Zero;
   GetTokenInformation(t,25,IntPtr.Zero,0,out n); b=Marshal.AllocHGlobal(n);
   if(!GetTokenInformation(t,25,b,n,out n))throw new Win32Exception();
   IntPtr sid=Marshal.ReadIntPtr(b);byte c=Marshal.ReadByte(GetSidSubAuthorityCount(sid));
   uint il=(uint)Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)c-1));
   return new uint[]{e,il};
  } finally {if(b!=IntPtr.Zero)Marshal.FreeHGlobal(b);if(t!=IntPtr.Zero)CloseHandle(t);CloseHandle(p);}
 }
}
'@
$parentToken=[YimeTokenRead]::Read([uint32]$PID)
if($parentToken[0] -ne 0 -or $parentToken[1] -ge 0x3000){throw 'Startup parent must be an ordinary unelevated user process.'}
$root=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'YimeCore'
$state=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'YimeCore Experimental Trial'
$manifest=Join-Path $root '.setup/product-package.json'
if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne '5f976f70ace424340b6d9f7138a63e57eb4167b493e1a56afa0b277386fd994b'){throw 'Installed manifest mismatch.'}
$package=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
foreach($row in $package.files){$path=Join-Path $root $row.path;if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw ('Installed payload mismatch: '+$row.path)}}
$prior=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)})
if($prior.Count){throw 'Installed standard processes already exist; do not duplicate or stop them.'}
$status=Join-Path $state 'runtime-status.json'
if(Test-Path -LiteralPath $status){Copy-Item -LiteralPath $status -Destination (Join-Path $reportRoot 'runtime-status-before.json')}
$runtime=Join-Path $root 'bin/YimeCoreTrialRuntime.exe'
$proc=Start-Process -FilePath $runtime -ArgumentList ('--install-root "'+$root+'" --state-root "'+$state+'"') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $reportRoot 'startup-out.txt') -RedirectStandardError (Join-Path $reportRoot 'startup-err.txt')
Start-Sleep -Seconds 8
$observed=@(foreach($p in Get-CimInstance Win32_Process){if($p.ExecutablePath -and $p.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){$t=[YimeTokenRead]::Read([uint32]$p.ProcessId);[ordered]@{pid=$p.ProcessId;image=$p.ExecutablePath;commandLine=$p.CommandLine;startedUtc=$p.CreationDate.ToUniversalTime().ToString('o');elevated=($t[0] -ne 0);integrityRid=$t[1]}}})
$proc.Refresh()
$exit=if($proc.HasExited){$proc.ExitCode}else{$null}
if(Test-Path -LiteralPath $status){Copy-Item -LiteralPath $status -Destination (Join-Path $reportRoot 'runtime-status-after.json')}
$result=[ordered]@{schema='standard-installed-runtime-start-v1';installRoot=$root;stateRoot=$state;manifestSHA256='5f976f70ace424340b6d9f7138a63e57eb4167b493e1a56afa0b277386fd994b';payloadsVerified=$package.files.Count;parentPid=$PID;parentElevated=($parentToken[0] -ne 0);parentIntegrityRid=$parentToken[1];launchedPid=$proc.Id;launchedProcessExited=$proc.HasExited;exitCode=$exit;processes=$observed;observedUtc=[DateTime]::UtcNow.ToString('o')}
$json=$result|ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $reportRoot 'startup.json'),$json,[Text.UTF8Encoding]::new($false))
Write-Output $json
if($proc.HasExited){Write-Output (Get-Content -LiteralPath (Join-Path $reportRoot 'startup-err.txt') -Raw)}
$proc.Dispose()
