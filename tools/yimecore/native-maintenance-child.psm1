Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ChildType=$null
$script:ChildLeases=@{}
$script:ClosedChildLeases=@{}
function Initialize-MaintenanceChildType {
    if($null -ne $script:ChildType){return}
    $source=@'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Yime.MaintenanceChild {
 public sealed class Facts {
  public int Pid {get;internal set;}
  public long CreationFileTime {get;internal set;}
  public string Image {get;internal set;}
  public bool ExitObserved {get;internal set;}
  public int? ExitCode {get;internal set;}
  public bool TimedOut {get;internal set;}
 }
 public sealed class Lease : IDisposable {
  readonly Process process; readonly SafeProcessHandle safeHandle; readonly IntPtr handle;
  readonly string expectedImage; readonly string capturedImage; readonly int pid; readonly long creation;
  bool referenceHeld; bool closed;
  [StructLayout(LayoutKind.Sequential)] struct FileTime {public uint Low,High;}
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetProcessId(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle,out FileTime created,out FileTime exited,out FileTime kernel,out FileTime user);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr handle,int flags,StringBuilder image,ref int size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  Lease(Process source,string image) {
   if(source==null || source.GetType()!=typeof(Process))throw new ArgumentException("Original exact Process instance required.");
   process=source;expectedImage=image;safeHandle=source.SafeHandle;
   try {
    safeHandle.DangerousAddRef(ref referenceHeld);handle=safeHandle.DangerousGetHandle();
    if(handle==IntPtr.Zero || handle==new IntPtr(-1))throw new InvalidOperationException("Invalid retained child handle.");
    var first=ReadIdentity();pid=first.Pid;creation=first.CreationFileTime;capturedImage=first.Image;AssertAssociation();
   } catch {Dispose();throw;}
  }
  public static Lease Open(Process source,string image){return new Lease(source,image);}
  Facts ReadIdentity() {
   if(closed || !referenceHeld)throw new ObjectDisposedException("Child lease");
   uint id=GetProcessId(handle);if(id==0 || id>Int32.MaxValue)throw new Win32Exception(Marshal.GetLastWin32Error());
   FileTime created,exited,kernel,user;
   if(!GetProcessTimes(handle,out created,out exited,out kernel,out user))throw new Win32Exception(Marshal.GetLastWin32Error());
   long start=((long)created.High<<32)|created.Low;if(start<=0)throw new InvalidOperationException("Invalid native creation time.");
   string observedImage=capturedImage;
   if(capturedImage==null){
    var path=new StringBuilder(32768);int size=path.Capacity;
    if(QueryFullProcessImageName(handle,0,path,ref size))observedImage=path.ToString();
    else throw new InvalidOperationException("Native child image unavailable before a bound exit observation.",new Win32Exception(Marshal.GetLastWin32Error()));
   }
   // After exit Windows may refuse the image query. Only an image already
   // observed from THIS retained handle may survive that race; StartInfo is
   // never an identity fallback for a child that exited before Open.
   if(!String.Equals(observedImage,expectedImage,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unexpected native child image.");
   return new Facts {Pid=(int)id,CreationFileTime=start,Image=observedImage};
  }
  Facts AssertAssociation() {
   if(closed || !referenceHeld)throw new ObjectDisposedException("Child lease");
   // The source must remain associated with this exact handle. Close/Dispose
   // or Start reusing the Process reference cannot silently switch the target.
   if(process.Id!=pid || !Object.ReferenceEquals(process.SafeHandle,safeHandle))throw new InvalidOperationException("Original Process association changed.");
   var facts=ReadIdentity();
   if(facts.Pid!=pid || facts.CreationFileTime!=creation || process.StartTime.ToUniversalTime().ToFileTimeUtc()!=creation)
    throw new InvalidOperationException("Retained child identity changed.");
   return facts;
  }
  public Facts Initial(){return AssertAssociation();}
  public Facts Wait(int milliseconds) {
   if(milliseconds<0 || milliseconds>60000)throw new ArgumentOutOfRangeException("milliseconds");
   AssertAssociation();
   // Unlike WaitForExit()/stdio EOF, this only waits on the original process
   // handle. A resident grandchild cannot extend this wait through pipe handles.
   uint result=WaitForSingleObject(handle,(uint)milliseconds);
   if(result==0xffffffff)throw new Win32Exception(Marshal.GetLastWin32Error());
   var facts=AssertAssociation();
   if(result==0x102){facts.TimedOut=true;return facts;}
   if(result!=0)throw new InvalidOperationException("Unknown native child wait result.");
   int code=process.ExitCode; // From the original retained Process, never JSON.
   AssertAssociation();
   if(WaitForSingleObject(handle,0)!=0)throw new InvalidOperationException("Child exit is not signaled.");
   facts.ExitObserved=true;facts.ExitCode=code;return facts;
  }
  public void Dispose(){if(closed)return;closed=true;if(referenceHeld){referenceHeld=false;safeHandle.DangerousRelease();}}
 }
}
'@
    $namespace='Yime.MaintenanceChild.N'+[guid]::NewGuid().ToString('N')
    $types=Add-Type -TypeDefinition ($source.Replace('namespace Yime.MaintenanceChild {','namespace '+$namespace+' {')) -PassThru
    $script:ChildType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Lease')})[0]
}
function Assert-MaintenanceChildImage($Path) {
    if($Path -isnot [string] -or $Path -cnotmatch '^[A-Z]:\\[^\\]+' -or $Path -match '[\x00-\x1f/"<>|?*%]' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'Canonical explicit child image path required'}
    foreach($part in $Path.Substring(3).Split('\')){if(-not $part -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)' -or $part -in @('.','..')){throw 'Ambiguous child image path'}}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Path)
}
function ConvertTo-MaintenanceChildEvidence($Facts,[int]$TimeoutMilliseconds) {
    [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-child-observation-v1';
        pid=$Facts.Pid;creation_filetime=$Facts.CreationFileTime;image_path=$Facts.Image;
        exit_observed=$Facts.ExitObserved;exit_code=$Facts.ExitCode;actual_exit_os_observed=$Facts.ExitObserved;
        timed_out=$Facts.TimedOut;timeout_milliseconds=$TimeoutMilliseconds;
        liveness=if($Facts.ExitObserved){'original_child_exit_signaled'}elseif($Facts.TimedOut){'not_signaled_at_wait_timeout'}else{'not_waited'};
        may_consume_outcome=$Facts.ExitObserved;may_advance_maintenance=$false;
        original_process_handle_identity_observed=$true;image_observed_from_original_handle_at_open=$true;process_start_origin_authenticated=$false;current_liveness_guaranteed=$false;
        descendants_waited=$false;termination_requested=$false;stdio_eof_waited=$false;
        loaded_script_authenticated=$false;target_sid_authenticated=$false;registration_restore_verified=$false;
        source_readiness=$false;local_product_ready=$false;public_release_ready=$false;execution_authorized=$false;L6_sealed=$false}
}
function Open-YimeCoreNativeMaintenanceChild {
    [CmdletBinding()]param([Parameter(Mandatory)]$Process,[Parameter(Mandatory)]$ExpectedImagePath)
    if($null -eq $Process -or $Process.GetType() -ne [Diagnostics.Process]){throw 'Original System.Diagnostics.Process instance required'}
    Assert-MaintenanceChildImage $ExpectedImagePath
    foreach($existing in $script:ChildLeases.Values){if([object]::ReferenceEquals($existing.process,$Process)){throw 'Process instance already has an active lease'}}
    Initialize-MaintenanceChildType
    $native=$script:ChildType::Open($Process,$ExpectedImagePath)
    try{
        $evidence=ConvertTo-MaintenanceChildEvidence ($native.Initial()) 0
        $id=[guid]::NewGuid().ToString('N');$public=[pscustomobject]@{lease_id=$id;initial=$evidence}
        $script:ChildLeases[$id]=@{native=$native;process=$Process;public=$public}
        return $public
    }catch{$native.Dispose();throw}
}
function Get-MaintenanceChildLease($Lease) {
    if($null -eq $Lease -or $null -eq $Lease.PSObject.Properties['lease_id'] -or $Lease.lease_id -isnot [string] -or
        -not $script:ChildLeases.ContainsKey($Lease.lease_id) -or -not [object]::ReferenceEquals($script:ChildLeases[$Lease.lease_id].public,$Lease)){throw 'A live original child lease is required'}
    return $script:ChildLeases[$Lease.lease_id]
}
function Wait-YimeCoreNativeMaintenanceChild {
    [CmdletBinding()]param([Parameter(Mandatory)]$Lease,[Parameter(Mandatory)]$TimeoutMilliseconds)
    if(($TimeoutMilliseconds -isnot [int] -and $TimeoutMilliseconds -isnot [long]) -or $TimeoutMilliseconds -lt 0 -or $TimeoutMilliseconds -gt 60000){throw 'Literal timeout milliseconds must be in 0..60000'}
    $owned=Get-MaintenanceChildLease $Lease
    ConvertTo-MaintenanceChildEvidence ($owned.native.Wait([int]$TimeoutMilliseconds)) ([int]$TimeoutMilliseconds)
}
function Close-YimeCoreNativeMaintenanceChild {
    [CmdletBinding()]param([Parameter(Mandatory)]$Lease)
    if($null -ne $Lease -and $null -ne $Lease.PSObject.Properties['lease_id'] -and $Lease.lease_id -is [string] -and $script:ClosedChildLeases.ContainsKey($Lease.lease_id)){
        if(-not [object]::ReferenceEquals($script:ClosedChildLeases[$Lease.lease_id],$Lease)){throw 'Closed child lease reference differs'};return
    }
    $owned=Get-MaintenanceChildLease $Lease
    try{$owned.native.Dispose()}finally{$script:ChildLeases.Remove($Lease.lease_id);$script:ClosedChildLeases[$Lease.lease_id]=$Lease}
    # Borrowed Process: caller still owns its Process.Dispose(). Only this
    # module's DangerousAddRef is released; no child/installer is terminated.
}
$ExecutionContext.SessionState.Module.OnRemove={foreach($owned in $script:ChildLeases.Values){$owned.native.Dispose()};$script:ChildLeases.Clear();$script:ClosedChildLeases.Clear()}
Export-ModuleMember -Function Open-YimeCoreNativeMaintenanceChild,Wait-YimeCoreNativeMaintenanceChild,Close-YimeCoreNativeMaintenanceChild
