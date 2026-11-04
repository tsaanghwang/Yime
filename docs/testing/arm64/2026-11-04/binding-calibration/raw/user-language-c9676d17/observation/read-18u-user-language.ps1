[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if(Test-Path -LiteralPath $OutputDirectory){throw 'Evidence directory already exists'}
$null=[IO.Directory]::CreateDirectory($OutputDirectory)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -ne 'S-1-5-21-2466658430-60932705-3086004269-1001'){throw 'Wrong initiating user'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Expected ordinary user, not elevated'}
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ReadOnly18uProfiles {
 [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr reserved,uint flags);
 [DllImport("ole32.dll")] static extern void CoUninitialize();
 [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid clsid,IntPtr outer,uint context,ref Guid iid,out IntPtr result);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int IsEnabled(IntPtr self,ref Guid clsid,ushort language,ref Guid profile,out int enabled);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int EnumLanguage(IntPtr self,ushort language,out IntPtr enumerator);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int NextProfile(IntPtr self,uint count,out LanguageProfile profile,out uint fetched);
 [StructLayout(LayoutKind.Sequential)] struct LanguageProfile {public Guid clsid;public ushort language;public Guid category;public int active;public Guid profile;}
 static T Method<T>(IntPtr value,int index) where T:Delegate {return Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(value),index*IntPtr.Size));}
 public static Dictionary<string,object> Read(){
  var result=new Dictionary<string,object>();
  int initialized=CoInitializeEx(IntPtr.Zero,2);result["comInitializeHRESULT"]=initialized;
  if(initialized<0 && initialized!=unchecked((int)0x80010106))Marshal.ThrowExceptionForHR(initialized);
  IntPtr value=IntPtr.Zero,enumerator=IntPtr.Zero;
  try {
   Guid clsid=new Guid("33c53a50-f456-4884-b049-85fd643ecfed"),iid=new Guid("1f02b6c5-7842-4ee6-8a0b-9a24183a95ca");
   int hr=CoCreateInstance(ref clsid,IntPtr.Zero,1,ref iid,out value);result["createHRESULT"]=hr;
   if(hr<0)Marshal.ThrowExceptionForHR(hr);
   Guid tip=new Guid("6dface1f-562e-4773-a9d6-d5753a314711"),profile=new Guid("1bd904ac-3194-4419-b70a-5574100f18b3");
   // Read-only indices from SDK 10.0.26100.0 msctf.h: IUnknown + 16th/14th method.
   int enabled=0;hr=Method<IsEnabled>(value,18)(value,ref tip,0x0804,ref profile,out enabled);
   result["isEnabledHRESULT"]=hr;result["enabled"]=hr==0?(object)(enabled!=0):null;
   hr=Method<EnumLanguage>(value,16)(value,0x0804,out enumerator);result["enum0804HRESULT"]=hr;
   var rows=new List<object>();result["profiles0804"]=rows;
   if(hr==0 && enumerator!=IntPtr.Zero){
    for(int index=0;index<1024;index++){
     LanguageProfile row;uint fetched;hr=Method<NextProfile>(enumerator,4)(enumerator,1,out row,out fetched);
     if(hr==1 && fetched==0){result["enumComplete"]=true;break;}
     if(hr!=0 || fetched!=1)throw new InvalidOperationException("Profile enumeration failed: "+hr+" fetched "+fetched);
     rows.Add(new Dictionary<string,object>{{"clsid",row.clsid.ToString("B")},{"profile",row.profile.ToString("B")},{"language",row.language},{"category",row.category.ToString("B")},{"activeInQueryProcess",row.active!=0},{"exact18u",row.clsid==tip && row.profile==profile && row.language==0x0804}});
     if(index==1023)throw new InvalidOperationException("Profile enumeration bound reached");
    }
   }
   return result;
  }finally{if(enumerator!=IntPtr.Zero)Marshal.Release(enumerator);if(value!=IntPtr.Zero)Marshal.Release(value);if(initialized>=0)CoUninitialize();}
 }
}
'@
$tip='0804:{6DFACE1F-562E-4773-A9D6-D5753A314711}{1BD904AC-3194-4419-B70A-5574100F18B3}'
$result=[ordered]@{schema='18u-user-language-readonly-v1';observedUTC=[DateTime]::UtcNow.ToString('o');userSID=$sid;observerPID=$PID;readOnly=$true;profileActivationRequested=$false;registrationRequested=$false;defaultChangeRequested=$false;inputSent=$false;expected18uTip=$tip;errors=@()}
try{
 $list=@(Get-WinUserLanguageList)
 $result.languages=@($list|ForEach-Object {[ordered]@{LanguageTag=$_.LanguageTag;Autonym=$_.Autonym;EnglishName=$_.EnglishName;LocalizedName=$_.LocalizedName;ScriptName=$_.ScriptName;InputMethodTips=@($_.InputMethodTips);Spellchecking=$_.Spellchecking;Handwriting=$_.Handwriting}})
 $result.exact18uInUserInputMethodTips=(@($list|ForEach-Object {$_.InputMethodTips}|Where-Object {$_ -ieq $tip}).Count -gt 0)
}catch{$result.errors+=,[ordered]@{stage='Get-WinUserLanguageList';error=$_.Exception.ToString()}}
try{$override=Get-WinDefaultInputMethodOverride;$result.defaultInputOverride=if($null -eq $override){''}else{[string]$override.InputMethodTip}}catch{$result.errors+=,[ordered]@{stage='default-read';error=$_.Exception.ToString()}}
try{$result.tsf=[ReadOnly18uProfiles]::Read()}catch{$result.errors+=,[ordered]@{stage='tsf-read';error=$_.Exception.ToString()}}
$result.notepad=@()
foreach($process in @(Get-Process -Name Notepad -ErrorAction SilentlyContinue)){
 try{
  $row=[ordered]@{pid=$process.Id;path=$process.Path;startUTC=$process.StartTime.ToUniversalTime().ToString('o');relatedModules=@();modulePresenceIsNotActiveProfileProof=$true}
  $modules=@($process.Modules);$row.modulesExamined=$modules.Count
  foreach($module in $modules){if($module.ModuleName -match '(?i)(yime|rime|pime|msctf)'){$row.relatedModules+=,[ordered]@{name=$module.ModuleName;path=$module.FileName;sha256=(Get-FileHash -LiteralPath $module.FileName -Algorithm SHA256).Hash.ToLowerInvariant()}}}
  $row.installed18uDLLObserved=(@($row.relatedModules|Where-Object {$_.path -ieq 'C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll'}).Count -gt 0)
  $result.notepad+=,$row
 }catch{$result.errors+=,[ordered]@{stage='notepad-modules';pid=$process.Id;error=$_.Exception.ToString()}}finally{$process.Dispose()}
}
$destination=Join-Path $OutputDirectory 'observation.json'
[IO.File]::WriteAllText($destination,($result|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ($result|ConvertTo-Json -Depth 20)
if($result.errors.Count -gt 0){exit 1}
