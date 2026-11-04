[CmdletBinding()]
param([string]$OutputDirectory,[int]$NotepadProcessId=28936)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
if(Test-Path -LiteralPath $OutputDirectory){throw 'Evidence directory already exists'}
$null=[IO.Directory]::CreateDirectory($OutputDirectory)
function Write-Json([string]$Name,$Value){[IO.File]::WriteAllText((Join-Path $OutputDirectory $Name),($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
$from=[DateTimeOffset]::Parse('2026-11-04T08:22:00+08:00');$until=[DateTimeOffset]::Now
$record=[ordered]@{schema='18u-notepad-readonly-load-audit-v1';observedUTC=$until.UtcDateTime.ToString('o');startUTC=$from.UtcDateTime.ToString('o');readOnly=$true;productProcessesStartedOrStopped=$false;profileActivated=$false;registrationProbeExecuted=$false;inputSent=$false;notepadPID=$NotepadProcessId;logs=@();registration=@()}
foreach($name in @('Microsoft-Windows-CodeIntegrity/Operational','Application')){
    $row=[ordered]@{name=$name;querySucceeded=$false;eventsExamined=0;targetEvents=@();hostOnlyEvents=@()}
    try{
        $config=Get-WinEvent -ListLog $name -ErrorAction Stop
        $row.configuration=[ordered]@{enabled=$config.IsEnabled;recordCount=$config.RecordCount;lastWriteTime=$config.LastWriteTime;logMode=[string]$config.LogMode}
        $events=@()
        try{$events=@(Get-WinEvent -FilterHashtable @{LogName=$name;StartTime=$from.LocalDateTime;EndTime=$until.LocalDateTime} -ErrorAction Stop)}
        catch{if($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'){throw};$row.noEventsInTimeRange=$true}
        $row.eventsExamined=$events.Count
        foreach($event in $events){
            $message=$event.Message;$xml=$event.ToXml();$combined=[string]$message+' '+$xml
            $isTarget=$combined -match '(?i)(YimeCore 18u Touch|YimeTextService18u\.dll|6DFACE1F-562E-4773-A9D6-D5753A314711|1BD904AC-3194-4419-B70A-5574100F18B3)'
            $isHost=$combined -match '(?i)(notepad\.exe|Microsoft\.WindowsNotepad)'
            if(-not $isTarget -and -not $isHost){continue}
            $item=[ordered]@{timeUTC=$event.TimeCreated.ToUniversalTime().ToString('o');id=$event.Id;recordId=$event.RecordId;provider=$event.ProviderName;level=$event.LevelDisplayName;message=$message;xml=$xml;matches18uPathOrIdentity=$isTarget;matchesNotepad=$isHost}
            if($isTarget){$row.targetEvents+=,$item}else{$row.hostOnlyEvents+=,$item}
        }
        $row.querySucceeded=$true
    }catch{$row.error=$_.Exception.ToString();$row.errorId=$_.FullyQualifiedErrorId}
    $record.logs+=,$row
}
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
public static class NotepadReadOnlyIdentity {
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder path,ref uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr process,out long created,out long exited,out long kernel,out long user);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsWow64Process2(IntPtr process,out ushort machine,out ushort native);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,int size,out int required);
 static uint TokenUInt(IntPtr token,int kind) {
  IntPtr p=Marshal.AllocHGlobal(4);
  try { int required;if(!GetTokenInformation(token,kind,p,4,out required))throw new Win32Exception(Marshal.GetLastWin32Error(),"GetTokenInformation "+kind);return (uint)Marshal.ReadInt32(p); }
  finally { Marshal.FreeHGlobal(p); }
 }
 static string TokenSID(IntPtr token,int kind) {
  int required;GetTokenInformation(token,kind,IntPtr.Zero,0,out required);
  if(required==0)throw new Win32Exception(Marshal.GetLastWin32Error(),"Token SID size "+kind);
  IntPtr p=Marshal.AllocHGlobal(required);
  try {if(!GetTokenInformation(token,kind,p,required,out required))throw new Win32Exception(Marshal.GetLastWin32Error(),"Token SID "+kind);IntPtr sid=Marshal.ReadIntPtr(p);return sid==IntPtr.Zero?null:new SecurityIdentifier(sid).Value;}
  finally {Marshal.FreeHGlobal(p);}
 }
 public static Dictionary<string,object> Read(int pid) {
  IntPtr process=OpenProcess(0x1000,false,pid),token=IntPtr.Zero;
  if(process==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcess");
  try {
   var result=new Dictionary<string,object>();uint n=32768;var image=new StringBuilder((int)n);
   if(!QueryFullProcessImageNameW(process,0,image,ref n))throw new Win32Exception(Marshal.GetLastWin32Error(),"QueryFullProcessImageNameW");
   long created,exited,kernel,user;if(!GetProcessTimes(process,out created,out exited,out kernel,out user))throw new Win32Exception(Marshal.GetLastWin32Error(),"GetProcessTimes");
   ushort machine,native;if(!IsWow64Process2(process,out machine,out native))throw new Win32Exception(Marshal.GetLastWin32Error(),"IsWow64Process2");
   if(!OpenProcessToken(process,8,out token))throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenProcessToken");
   result["pid"]=pid;result["image"]=image.ToString();result["creationTicks"]=created;result["processMachine"]="0x"+machine.ToString("x");result["nativeMachine"]="0x"+native.ToString("x");
   result["sid"]=TokenSID(token,1);result["integritySID"]=TokenSID(token,25);result["elevated"]=TokenUInt(token,20)!=0;result["session"]=TokenUInt(token,12);
   bool container=TokenUInt(token,29)!=0;result["tokenIsAppContainer"]=container;result["appContainerSID"]=container?TokenSID(token,31):null;
   return result;
  } finally {if(token!=IntPtr.Zero)CloseHandle(token);CloseHandle(process);}
 }
}
'@
function Read-PE([string]$Path){
    $file=[IO.File]::OpenRead($Path);$reader=[IO.BinaryReader]::new($file)
    try{
        if($reader.ReadUInt16() -ne 0x5a4d){throw 'No DOS header'}
        $file.Position=0x3c;$offset=$reader.ReadUInt32();$file.Position=$offset
        if($reader.ReadUInt32() -ne 0x4550){throw 'No PE signature'}
        $machine=$reader.ReadUInt16()
        return [ordered]@{path=$Path;bytes=$file.Length;machine=('0x{0:x}' -f $machine);sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }finally{$reader.Dispose();$file.Dispose()}
}
try{$record.notepad=[NotepadReadOnlyIdentity]::Read($NotepadProcessId);$record.notepad['imagePE']=Read-PE $record.notepad.image}catch{$record.notepadError=$_.Exception.ToString()}
try{
    $process=Get-Process -Id $NotepadProcessId -ErrorAction Stop
    try{
        $modules=@($process.Modules);$selected=@()
        foreach($module in $modules){if($module.ModuleName -match '(?i)(yime|rime|pime|msctf)'){$selected+=,(Read-PE $module.FileName)}}
        $record.modules=[ordered]@{querySucceeded=$true;examined=$modules.Count;related=$selected;installed18uDLLObserved=(@($selected|Where-Object {$_.path -ieq 'C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll'}).Count -gt 0);presenceIsNotActiveProfileProof=$true}
    }finally{$process.Dispose()}
}catch{$record.modules=[ordered]@{querySucceeded=$false;error=$_.Exception.ToString()}}
function Read-RegistryTree($Hive,[string]$Path,[int]$Depth=0){
    if($Depth -gt 8){throw 'Unexpected product registry depth'}
    $key=$Hive.OpenSubKey($Path,$false)
    if(-not $key){return [ordered]@{path=$Path;exists=$false}}
    try{
        $values=[ordered]@{};foreach($n in $key.GetValueNames()){$values[$n]=[ordered]@{kind=[string]$key.GetValueKind($n);value=$key.GetValue($n,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}}
        $children=@();foreach($n in $key.GetSubKeyNames()){$children+=,(Read-RegistryTree $Hive ($Path+'\'+$n) ($Depth+1))}
        return [ordered]@{path=$Path;exists=$true;values=$values;children=$children}
    }finally{$key.Dispose()}
}
foreach($hiveName in @('LocalMachine','CurrentUser')){foreach($view in @('Registry64','Registry32')){
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hiveName,[Microsoft.Win32.RegistryView]::$view)
    try{foreach($path in @('SOFTWARE\Classes\CLSID\{6DFACE1F-562E-4773-A9D6-D5753A314711}','SOFTWARE\Microsoft\CTF\TIP\{6DFACE1F-562E-4773-A9D6-D5753A314711}')){
        $record.registration+=,[ordered]@{hive=$hiveName;view=$view;tree=(Read-RegistryTree $hive $path)}
    }}catch{$record.registration+=,[ordered]@{hive=$hiveName;view=$view;error=$_.Exception.ToString()}}finally{$hive.Dispose()}
}}
try{$record.installedDLL=Read-PE 'C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll'}catch{$record.installedDLLError=$_.Exception.ToString()}
Write-Json 'observation.json' $record
Write-Output ('Evidence: '+(Join-Path $OutputDirectory 'observation.json'))
if($record.Contains('notepad')){Write-Output ('Notepad observation: '+($record.notepad|ConvertTo-Json -Compress -Depth 5))}
foreach($log in $record.logs){Write-Output ($log.name+': query='+$log.querySucceeded+' examined='+$log.eventsExamined+' 18u='+$log.targetEvents.Count+' hostOnly='+$log.hostOnlyEvents.Count)}
