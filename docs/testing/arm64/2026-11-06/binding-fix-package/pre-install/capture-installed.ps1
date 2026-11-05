param([Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../../installer/simple/Product.psm1') -Force
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class YimeProcessObservation {
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool inherit,uint pid);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr p,uint flags,StringBuilder b,ref uint length);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr h,uint a,out IntPtr t);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr t,int c,out uint value,int n,out int needed);
 public static string Image(uint pid){
  IntPtr p=OpenProcess(0x1000,false,pid); if(p==IntPtr.Zero)return null;
  try {uint n=32768;var b=new StringBuilder((int)n);return QueryFullProcessImageName(p,0,b,ref n)?b.ToString():null;}
  finally {CloseHandle(p);}
 }
 public static int Elevated(uint pid){
  IntPtr p=OpenProcess(0x1000,false,pid),t=IntPtr.Zero;if(p==IntPtr.Zero)return -1;
  try {if(!OpenProcessToken(p,8,out t))return -1;uint value;int needed;return GetTokenInformation(t,20,out value,4,out needed)?(int)value:-1;}
  finally {if(t!=IntPtr.Zero)CloseHandle(t);CloseHandle(p);}
 }
}
'@
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$products=@()
foreach($id in @('yimecore','rime-pime','yimecore-18u')){
    $product=Get-Product $id
    $root=Join-Path $env:ProgramFiles $product.directory
    $manifest=Join-Path $root '.setup/product-package.json'
    $payload=@();$version=$null
    if(Test-Path -LiteralPath $manifest){
        $package=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
        $version=$package.version
        foreach($row in $package.files){
            $path=Join-Path $root $row.path
            $exists=Test-Path -LiteralPath $path -PathType Leaf
            $actual=if($exists){Get-ContentHash $path}else{$null}
            $payload+=[ordered]@{path=$row.path;exists=$exists;sha256=$actual;expected=$row.sha256;match=($actual -ceq $row.sha256)}
        }
    }
    $registrations=@()
    foreach($view in @('Registry64','Registry32')){
        $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine',$view)
        try{
            $key=$hive.OpenSubKey('SOFTWARE\Classes\CLSID\'+$product.clsid+'\InprocServer32')
            $value=$null
            if($key){try{$value=$key.GetValue('')}finally{$key.Dispose()}}
            $registrations+=[ordered]@{view=$view;path=$value}
        }finally{$hive.Dispose()}
    }
    $address=@{hDefKey=[uint32]2147483651;sSubKeyName=($sid+'\Software\Microsoft\Windows\CurrentVersion\Run')}
    $values=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments $address
    if($values.ReturnValue -notin @(0,2)){throw ('Startup enumeration failed: '+$values.ReturnValue)}
    $runName='YimeSimple-'+$id
    $startup=[pscustomobject]@{ReturnValue=2;sValue=$null}
    if($values.ReturnValue -eq 0 -and $runName -in @($values.sNames)){
        $address.sValueName=$runName
        $startup=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments $address
        if($startup.ReturnValue -ne 0){throw ('Startup query failed: '+$id+' '+$startup.ReturnValue)}
    }
    $processes=@(Get-Process | ForEach-Object {
        $image=[YimeProcessObservation]::Image([uint32]$_.Id)
        try{if($image -and $image.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
            $token=[YimeProcessObservation]::Elevated([uint32]$_.Id)
            [ordered]@{pid=$_.Id;path=$image;startUtc=$_.StartTime.ToUniversalTime().ToString('o');elevated=if($token -lt 0){$null}else{$token -ne 0}}
        }}catch{}
    })
    $products+=[ordered]@{id=$id;root=$root;exists=(Test-Path -LiteralPath $root);version=$version;payload=$payload;registrations=$registrations;startup=[ordered]@{result=$startup.ReturnValue;value=$startup.sValue};processes=$processes}
}
$override=Get-WinDefaultInputMethodOverride
$default=if($null -eq $override){''}else{[string]$override.InputMethodTip}
$result=[ordered]@{schema='yime-installed-protection-snapshot-v1';observedUtc=[DateTime]::UtcNow.ToString('o');computer=$env:COMPUTERNAME;defaultInputOverride=$default;products=$products}
$destination=[IO.Path]::GetFullPath($Report)
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
[IO.File]::WriteAllText($destination,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ('Snapshot: '+$destination)
foreach($p in $products){Write-Output ($p.id+': exists='+$p.exists+'; version='+$p.version+'; payload='+$p.payload.Count+'; mismatches='+@($p.payload|Where-Object {-not $_.match}).Count+'; processes='+$p.processes.Count)}
