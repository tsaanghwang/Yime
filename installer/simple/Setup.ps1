[CmdletBinding()]
param([ValidateSet('Install','Uninstall','Check')][string]$Action='Install',
    [switch]$ResetData,[switch]$Silent,[string]$InitiatingSid,
    [ValidatePattern('^[a-f0-9]{32}$')][string]$LogId)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
function Wait-SetupExit([Diagnostics.Process]$Process){
    # Hold the process handle while waiting for this process, not its descendants.
    $null=$Process.Handle
    $Process.WaitForExit()
    $code=$Process.ExitCode
    if($null -eq $code){throw 'Elevated setup exited without a readable exit code'}
    return [int]$code
}
$administrator=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $LogId){$LogId=[guid]::NewGuid().ToString('N')}
$logRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Yime Setup Logs'
$null=[IO.Directory]::CreateDirectory($logRoot)
$logName=$LogId+$(if($administrator){'.admin.log'}else{'.user.log'})
$logPath=Join-Path $logRoot $logName
Start-Transcript -LiteralPath $logPath -Append | Out-Null
$stage='package check'
try{
Write-Output ('Setup log: '+$logPath)
Write-Output ('Action: '+$Action+'; package: '+$PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot 'Product.psm1') -Force
$installedEntry=([IO.Path]::GetFileName($PSScriptRoot) -eq '.setup')
if($installedEntry){
    if($Action -ne 'Uninstall'){throw 'Use the downloaded package to install or check'}
    $record=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'product-package.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $package=[pscustomobject]@{root=$PSScriptRoot;manifest=$record;product=(Get-Product $record.product)}
}else{$package=Read-Package $PSScriptRoot}
$product=$package.product
if($Action -eq 'Check'){Write-Output 'PASS: package files and required binaries';exit 0}
if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'This package entry currently supports x64 Windows with x86 applications'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($InitiatingSid -and $InitiatingSid -cne $sid){throw 'Run with the same Windows account that started setup'}
if(-not $administrator){
    $stage='UAC elevation'
    Write-Output ('Elevated setup log: '+(Join-Path $logRoot ($LogId+'.admin.log')))
    $args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -InitiatingSid "{2}" -LogId {3}' -f $PSCommandPath,$Action,$sid,$LogId
    if($ResetData){$args+=' -ResetData'};if($Silent){$args+=' -Silent'}
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Hidden
    $code=Wait-SetupExit $p
    Write-Output ('Elevated setup exit code: '+$code)
    exit $code
}
$stage='installed product ownership check'
$root=Join-Path $env:ProgramFiles $product.directory
$state=if($product.id -eq 'yimecore'){Join-Path $env:LOCALAPPDATA $product.state}else{Join-Path $env:APPDATA $product.state}
$root=Assert-PlainPath $root;$state=Assert-PlainPath $state
if($installedEntry -and [IO.Path]::GetDirectoryName($PSScriptRoot) -ine $root){throw 'Uninstaller is outside this product directory'}
Assert-OwnedDirectory $root $product.id
# Never replace a different installation using the same CLSID implicitly.
$hasRegistration=$false
foreach($view in @('Registry64','Registry32')){
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine',$view)
    try{
        $key=$hive.OpenSubKey('SOFTWARE\Classes\CLSID\'+$product.clsid+'\InprocServer32')
        if($key){try{$hasRegistration=$true;$path=[string]$key.GetValue('');if($path -and -not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw ('Existing installation must be removed first: '+$path)}}finally{$key.Dispose()}}
    }finally{$hive.Dispose()}
}
function Run-Native([string]$Path,[string[]]$Arguments){
    & $Path @Arguments | Out-Host
    if($LASTEXITCODE -ne 0){throw ('Native operation failed: '+[IO.Path]::GetFileName($Path)+' ('+$LASTEXITCODE+')')}
}
function Set-Registration([bool]$Install,[string]$Payload){
    if($product.id -eq 'yimecore'){
        if($Install){
            Run-Native (Join-Path $Payload 'x64\YimeTextServiceRegistration.exe') @('register',(Join-Path $root ('x64\'+$product.dll)))
            Run-Native (Join-Path $Payload 'x86\YimeTextServiceRegistration.exe') @('register-com',(Join-Path $root ('x86\'+$product.dll)))
        }else{
            foreach($arch in @('x86','x64')){Run-Native (Join-Path $Payload ($arch+'\YimeTextServiceRegistration.exe')) @('unregister')}
        }
    }else{
        foreach($arch in @('x86','x64')){
            $regsvr=Join-Path $env:SystemRoot $(if($arch -eq 'x86'){'SysWOW64\regsvr32.exe'}else{'System32\regsvr32.exe'})
            $args='/s';if(-not $Install){$args+=' /u'}
            $args+=' "'+(Join-Path $Payload ($arch+'\'+$product.dll))+'"'
            $registration=Start-Process -FilePath $regsvr -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            if($registration.ExitCode -ne 0){throw ('Native registration failed: '+$arch+' ('+$registration.ExitCode+')')}
        }
    }
}
Add-Type @'
using System.Runtime.InteropServices;
public static class SimpleInputProfile {
 [DllImport("input.dll", CharSet=CharSet.Unicode)] [return:MarshalAs(UnmanagedType.Bool)]
 public static extern bool InstallLayoutOrTip(string profile, uint flags);
}
'@
$tip='0804:'+$product.clsid+$product.profile
$uninstallKey='Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeSimple-'+$product.id
$runKey='Software\Microsoft\Windows\CurrentVersion\Run'
$runName='YimeSimple-'+$product.id
function Set-UserStartup([string]$Value){
    $key=$sid+'\'+$runKey
    $address=@{hDefKey=[uint32]2147483651;sSubKeyName=$key}
    if(-not $Value){
        $before=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments $address
        if($before.ReturnValue -eq 2){return}
        if($before.ReturnValue -ne 0){throw ('Startup enumeration failed: '+$before.ReturnValue)}
        if($runName -notin @($before.sNames)){return}
    }else{
        $created=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName CreateKey -Arguments $address
        if($created.ReturnValue -ne 0){throw ('Startup key creation failed: '+$created.ReturnValue)}
    }
    $parameters=$address.Clone();$parameters.sValueName=$runName
    if($Value){$parameters.sValue=$Value;$method='SetStringValue'}else{$method='DeleteValue'}
    $result=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $method -Arguments $parameters
    if($result.ReturnValue -ne 0){throw ('Startup '+$method+' failed: '+$result.ReturnValue)}
    if(-not $Value){
        $after=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments $address
        if($after.ReturnValue -eq 2){return}
        if($after.ReturnValue -ne 0 -or $runName -in @($after.sNames)){throw ('Startup deletion readback failed: code='+$after.ReturnValue+'; value still listed='+($runName -in @($after.sNames)))}
    }else{
        $parameters.Remove('sValue')
        $read=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments $parameters
        if($read.ReturnValue -ne 0 -or $read.sValue -cne $Value){throw ('Startup write readback failed: code='+$read.ReturnValue+'; actual='+$read.sValue)}
    }
}
$stage='stop selected product background programs'
    # Only this product's own executable paths; never terminate a typing host.
    foreach($p in Get-Process){
        try{$path=$p.Path}catch{continue}
        if($path -and $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
            $null=$p.Handle
            $record=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$p.Id)
            $owner=Invoke-CimMethod -InputObject $record -MethodName GetOwnerSid
            if($owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid){throw 'Another user is using this product; ask them to exit first'}
            if($product.id -eq 'yimecore' -and $path -ieq (Join-Path $root $product.exe)){
                Run-Native $path @('-stop','-state-root',$state)
                $null=$p.WaitForExit(10000)
            }elseif(-not $p.HasExited){$p.Kill();$null=$p.WaitForExit(5000)}
        }
    }
    $stage='wait for installed files to be released'
    Wait-ProductFiles $root -Silent:$Silent
    if($ResetData){
        if(Test-Path -LiteralPath $state){$null=@(Get-ProductFiles $state);Wait-ProductFiles $state -Silent:$Silent}
    }
    # Registration tools run from the new package even after an interrupted copy.
    $stage='unregister selected product'
    if($hasRegistration){Set-Registration $false (Join-Path $package.root $(if($installedEntry){'native'}else{'payload'}))}
    $null=[SimpleInputProfile]::InstallLayoutOrTip($tip,1)
    Set-UserStartup ''
    $stage='remove selected product files'
    Remove-ProductDirectory $root $product.id
    if($ResetData -and (Test-Path -LiteralPath $state)){Remove-Item -LiteralPath (Assert-PlainPath $state) -Recurse -Force}
    if($Action -eq 'Uninstall'){
        [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($uninstallKey,$false)
        Write-Output 'Uninstalled. Other products were not removed.';exit 0
    }
    $stage='copy new product files'
    Copy-ProductPayload $package $root
    $maintenance=Join-Path $root '.setup';$null=[IO.Directory]::CreateDirectory($maintenance)
    foreach($name in @('Product.psm1','Setup.ps1','Setup.cmd','product-package.json')){
        [IO.File]::Copy((Join-Path $package.root $name),(Join-Path $maintenance $name),$true)
    }
    foreach($arch in @('x64','x86')){
        $dir=Join-Path $maintenance ('native\'+$arch);$null=[IO.Directory]::CreateDirectory($dir)
        $name=if($product.id -eq 'yimecore'){'YimeTextServiceRegistration.exe'}else{$product.dll}
        [IO.File]::Copy((Join-Path $root ($arch+'\'+$name)),(Join-Path $dir $name),$true)
    }
    $stage='register new product'
    Set-Registration $true $root
    if(-not [SimpleInputProfile]::InstallLayoutOrTip($tip,0)){throw 'Could not enable the installed input profile'}
    $null=[IO.Directory]::CreateDirectory($state)
    $exe=Join-Path $root $product.exe
    $arguments=if($product.id -eq 'yimecore'){'-install-root "{0}" -state-root "{1}"' -f $root,$state}else{''}
    if($product.id -eq 'yimecore'){
        [IO.File]::WriteAllText((Join-Path $state 'runtime-config.json'),(@{install_root=$root;state_root=$state;runtime_path=$exe;broker_path=(Join-Path $root 'bin\YimeBroker.exe')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    $stage='write user startup and uninstall entry'
    Set-UserStartup ('"'+$exe+'" '+$arguments)
    # Small installed uninstaller; no downloaded package or recovery archive required.
    $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($uninstallKey)
    try{
        $key.SetValue('DisplayName',$product.name);$key.SetValue('DisplayVersion',$package.manifest.version)
        $key.SetValue('InstallLocation',$root)
        $key.SetValue('UninstallString',('"'+(Join-Path $PSHOME 'powershell.exe')+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $maintenance 'Setup.ps1')+'" -Action Uninstall'))
    }finally{$key.Dispose()}
    foreach($arch in @('x86','x64')){
        if($product.id -eq 'rime-pime'){Run-Native (Join-Path $root ($arch+'\PIMERegistrationStatus.exe')) @('verify-registered')}
    }
    $stage='start installed runtime'
    $start=@{FilePath=$exe;WindowStyle='Hidden';PassThru=$true}
    if($arguments){$start.ArgumentList=$arguments}
    $p=Start-Process @start
    Start-Sleep -Milliseconds 800
    if($p.HasExited){throw 'Installed runtime exited at startup; inspect its log, then reinstall'}
    Write-Output ('Installed: '+$product.name+'. Select it from the Windows input-method menu.')
}catch{
    Write-Output ('FAILED stage: '+$stage)
    Write-Output ($_ | Format-List * -Force | Out-String)
    Write-Output ('Exception: '+$_.Exception.ToString())
    Write-Error ('Setup stopped: '+$_.Exception.Message+' Log: '+$logPath) -ErrorAction Continue
    $exitCode=1
    for($failure=$_.Exception;$failure;$failure=$failure.InnerException){
        if($failure -is [OperationCanceledException]){$exitCode=2}
        if($failure -is [ComponentModel.Win32Exception] -and $failure.NativeErrorCode -eq 1223){$exitCode=3}
    }
    Write-Output ('Setup exit code: '+$exitCode)
    exit $exitCode
}finally{
    Stop-Transcript | Out-Null
}
