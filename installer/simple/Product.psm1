Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Get-Product([string]$Id){
    switch($Id){
        'yimecore-18u' { return [pscustomobject]@{id=$Id;name='YimeCore 18u Touch (development)';directory='YimeCore 18u Touch';state='YimeCore 18u Touch';clsid='{6DFACE1F-562E-4773-A9D6-D5753A314711}';profile='{1BD904AC-3194-4419-B70A-5574100F18B3}';dll='YimeTextService18u.dll';exe='bin\Yime18uInstalledRuntime.exe'} }
        'yimecore' { return [pscustomobject]@{id=$Id;name='YimeCore';directory='YimeCore';state='YimeCore Experimental Trial';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}';dll='YimeTextServiceExperiment.dll';exe='bin\YimeCoreTrialRuntime.exe'} }
        'rime-pime' { return [pscustomobject]@{id=$Id;name='Yime Rime-PIME';directory='Yime Rime-PIME';state='PIME\Rime';clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}';profile='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}';dll='PIMETextService.dll';exe='PIMELauncher.exe'} }
        default {throw 'Unknown product'}
    }
}
function Assert-PlainPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($full -notmatch '^[A-Za-z]:\\' -or $full.Substring(2).Contains(':') -or $full.Length -le 3){throw 'A local product directory is required'}
    for($p=$full;$p;$p=[IO.Path]::GetDirectoryName($p)){
        if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked product paths are not supported'}
    }
    return $full
}
function Get-ProductFiles([string]$Root){
    $root=Assert-PlainPath $Root
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked files are not supported'}
            if($item.PSIsContainer){$pending.Push($item.FullName)}else{$item}
        }
    }
}
function Get-ContentHash([string]$Path){
    $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$stream.Dispose()}
}
function Test-SetupAdministrator {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-ProductInstallPaths($Product){
    $root=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) $Product.directory
    $folder=if($Product.id -eq 'rime-pime'){'ApplicationData'}else{'LocalApplicationData'}
    $state=Join-Path ([Environment]::GetFolderPath($folder)) $Product.state
    return [pscustomobject]@{root=(Assert-PlainPath $root);state=(Assert-PlainPath $state)}
}
function Start-VerifiedInstalledRuntime($Package,[string]$ExpectedManifestHash){
    # Only the original ordinary-user caller may launch a product after UAC.
    # A successful elevated exit code alone is not proof of installed bytes.
    if(Test-SetupAdministrator){throw 'The installed runtime must be started by a non-elevated user process'}
    if($ExpectedManifestHash -cnotmatch '^[a-f0-9]{64}$'){throw 'Missing original package manifest hash'}
    $product=Get-Product $Package.manifest.product
    $contract=Get-PackageContract $Package.manifest
    $paths=Get-ProductInstallPaths $product
    $root=Assert-PlainPath $paths.root;$state=Assert-PlainPath $paths.state
    $manifestPath=Assert-PlainPath (Join-Path $root '.setup/product-package.json')
    if((Get-ContentHash $manifestPath) -cne $ExpectedManifestHash){throw 'Installed maintenance manifest differs from the original checked package'}
    # Assert-OwnedDirectory permits an empty directory during installation;
    # startup additionally requires its actual completed-install marker.
    Assert-OwnedDirectory $root $product.id $contract.target
    $marker=Get-Content -LiteralPath (Join-Path $root '.yime-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($marker.version -cne $Package.manifest.version){throw 'Installed marker version differs from the checked package'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $Package.manifest.files){
        if($row.path -match '(^[/\\]|:|(^|[/\\])\.\.?([/\\]|$))' -or -not $seen.Add($row.path)){throw 'Invalid installed startup member'}
        $path=Assert-PlainPath (Join-Path $root $row.path)
        if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Installed startup member escaped product root'}
        if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-ContentHash $path) -cne $row.sha256){throw ('Installed startup payload damaged: '+$row.path)}
    }
    if(-not $seen.Contains($product.exe.Replace('\','/'))){throw 'Installed startup runtime is not a checked payload member'}
    $arguments=if($product.id -eq 'yimecore'){'-install-root "{0}" -state-root "{1}"' -f $root,$state}else{''}
    if($product.id -eq 'yimecore-18u'){
        $descriptor=Join-Path $root 'installed-18u-product.json'
        if(-not $seen.Contains('installed-18u-product.json')){throw 'Installed 18u descriptor is not checked'}
        if((Get-Content -LiteralPath $descriptor -Raw -Encoding UTF8|ConvertFrom-Json).schema -cne 'installed-18u-product-v2'){
            Write-Output 'Installed 18u version one does not start a runtime automatically.'
            return
        }
        $arguments='--installed-18u-run --install-root "{0}" --manifest-sha256 {1}' -f $root,(Get-ContentHash $descriptor)
    }
    $start=@{FilePath=(Join-Path $root $product.exe);WorkingDirectory=$root;WindowStyle='Hidden';PassThru=$true}
    if($arguments){$start.ArgumentList=$arguments}
    $process=Start-Process @start
    try{
        Start-Sleep -Milliseconds 800
        if($process.HasExited){throw 'Installed runtime exited at startup; inspect its log, then reinstall'}
    }finally{$process.Dispose()}
    Write-Output ('Installed: '+$product.name+'. Started by the original non-elevated user. Select it from the Windows input-method menu.')
}
function Get-PackageContract($Manifest){
    $product=Get-Product $Manifest.product
    if($product.id -ceq 'yimecore-18u'){
        if($Manifest.format -cne 'yime-simple-package-18u-1'){throw 'Unsupported independent 18u contract'}
        if($Manifest.target -ceq 'windows-amd64' -and $Manifest.host_architecture -ceq 'amd64' -and $Manifest.tsf64_architecture -ceq 'x64'){
            return [pscustomobject]@{target='windows-amd64';hostArchitecture='amd64';nativeDirectory='x64';nativeDirectories=@('x64');tsf64Architecture='x64';requireNativeProcess=$true}
        }
        if($Manifest.target -ceq 'windows-arm64' -and $Manifest.host_architecture -ceq 'arm64' -and $Manifest.tsf64_architecture -ceq 'arm64'){
            return [pscustomobject]@{target='windows-arm64';hostArchitecture='arm64';nativeDirectory='arm64';nativeDirectories=@('arm64');tsf64Architecture='arm64';requireNativeProcess=$true}
        }
        throw 'Independent 18u requires an exact native architecture contract'
    }
    if($Manifest.format -ceq 'yime-simple-package-1'){
        foreach($name in @('target','host_architecture','tsf64_architecture')){
            if($Manifest.PSObject.Properties[$name]){throw 'Legacy packages must not declare a new architecture contract'}
        }
        return [pscustomobject]@{target='windows-amd64';hostArchitecture='amd64';nativeDirectory='x64';nativeDirectories=@('x64','x86');tsf64Architecture='x64'}
    }
    if($Manifest.format -ceq 'yime-simple-package-rime-arm64-1' -and $product.id -ceq 'rime-pime' -and
       $Manifest.target -ceq 'windows-arm64' -and $Manifest.host_architecture -ceq 'arm64' -and $Manifest.tsf64_architecture -ceq 'arm64x'){
        return [pscustomobject]@{target='windows-arm64';hostArchitecture='arm64';nativeDirectory='arm64';nativeDirectories=@('arm64','x86');tsf64Architecture='arm64x';requireNativeProcess=$true}
    }
    if($Manifest.format -cne 'yime-simple-package-2' -or $product.id -cne 'yimecore' -or
        $Manifest.target -cne 'windows-arm64' -or $Manifest.host_architecture -cne 'arm64' -or
        $Manifest.tsf64_architecture -cne 'arm64x'){throw 'Unsupported package architecture contract'}
    return [pscustomobject]@{target='windows-arm64';hostArchitecture='arm64';nativeDirectory='arm64';nativeDirectories=@('arm64','x86');tsf64Architecture='arm64x'}
}
function Get-NativeHostMachine {
    # The environment and the current executable's PE can describe an emulated
    # process. Only the OS-reported native machine determines package selection.
    if(-not ('YimeSimple.NativeMachine' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YimeSimple {
    public static class NativeMachine {
        [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
    }
}
'@
    }
    [System.UInt16]$processMachine=0;[System.UInt16]$nativeMachine=0
    if(-not [YimeSimple.NativeMachine]::IsWow64Process2([YimeSimple.NativeMachine]::GetCurrentProcess(),[ref]$processMachine,[ref]$nativeMachine)){
        throw 'IsWow64Process2 failed; native Windows architecture is unverified'
    }
    return [pscustomobject]@{source='IsWow64Process2';nativeMachine=[int]$nativeMachine;processMachine=[int]$processMachine;is64BitProcess=[Environment]::Is64BitProcess}
}
function Assert-PackageHost($Contract){
    $hostMachine=Get-NativeHostMachine
    $expected=if($Contract.hostArchitecture -ceq 'arm64'){0xaa64}elseif($Contract.hostArchitecture -ceq 'amd64'){0x8664}else{throw 'Unsupported package host architecture'}
    if($hostMachine.source -cne 'IsWow64Process2' -or -not $hostMachine.is64BitProcess -or $hostMachine.nativeMachine -ne $expected){
        throw ('Package '+$Contract.target+' requires matching native Windows and 64-bit PowerShell')
    }
    if($Contract.PSObject.Properties['requireNativeProcess'] -and $Contract.requireNativeProcess -and $hostMachine.processMachine -ne 0){throw 'Independent 18u requires a native, non-emulated process'}
}
function Get-SetupShell($Product,$Contract,[string]$CurrentShell,[int]$PowerShellMajor,
    [scriptblock]$VerifyArm64Pe={param([string]$Path) Assert-ProductPe $Path 'arm64'}){
    $systemShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if($Product.id -cnotin @('yimecore-18u','rime-pime') -or $Contract.target -cne 'windows-arm64'){return $systemShell}
    if($PowerShellMajor -lt 7 -or [IO.Path]::GetFileName($CurrentShell) -ine 'pwsh.exe'){
        throw 'Independent ARM64 18u elevation requires the current native PowerShell 7 process'
    }
    $shell=Assert-PlainPath $CurrentShell
    if(-not (Test-Path -LiteralPath $shell -PathType Leaf)){throw 'Current PowerShell 7 executable is unavailable'}
    & $VerifyArm64Pe $shell
    return $shell
}
function Assert-NativeMaintenanceEntry($Package,[string]$Stage,[string]$EntryHash,[string]$PlanHash){
    if($EntryHash -cnotmatch '^[0-9a-f]{64}$' -or $PlanHash -cnotmatch '^[0-9a-f]{64}$'){
        throw 'ARM64 maintenance requires a package-bound native entry'
    }
    $expected=Join-Path (Join-Path (Join-Path $env:ProgramFiles 'Yime Maintenance') $Package.product.id) $PlanHash
    $stage=Assert-PlainPath $Stage
    if($stage -ine $expected -or $Package.root -ine $stage){throw 'Native maintenance must execute its protected package'}
    $trusted=@('S-1-5-18','S-1-5-32-544')
    $cache=Join-Path $env:ProgramFiles 'Yime Maintenance'
    foreach($leaf in @('YimeMaintenance.exe','maintenance-plan.json','Setup.ps1','Product.psm1','maintenance/preflight.ps1')){
        $path=Assert-PlainPath (Join-Path $stage $leaf)
        for($item=$path;$item -and $item.StartsWith($cache,[StringComparison]::OrdinalIgnoreCase);$item=[IO.Path]::GetDirectoryName($item)){
            Assert-Arm64ProtectedAcl (Get-Acl -LiteralPath $item) $item $trusted
        }
    }
    if((Get-ContentHash (Join-Path $stage 'YimeMaintenance.exe')) -cne $EntryHash -or
       (Get-ContentHash (Join-Path $stage 'maintenance-plan.json')) -cne $PlanHash){throw 'Native maintenance identity changed'}
    $plan=Get-Content -LiteralPath (Join-Path $stage 'maintenance-plan.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($plan.schema -cne 'yime-native-maintenance-v1' -or $plan.product -cne $Package.product.id -or $plan.target -cne 'windows-arm64'){
        throw 'Native maintenance plan belongs to another product'
    }
    foreach($name in @('Setup.ps1','Product.psm1')){
        $record=$plan.files.PSObject.Properties[$name]
        if(-not $record -or (Get-ContentHash (Join-Path $stage $name)) -cne $record.Value.sha256){throw 'Unbound maintenance script'}
    }
    $current=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$PID)
    $parent=Get-Process -Id $current.ParentProcessId -ErrorAction Stop
    if(-not $parent.Path -or [IO.Path]::GetFileName($parent.Path) -ine 'YimeMaintenance.exe' -or
       (Get-ContentHash $parent.Path) -cne $EntryHash){throw 'Setup was not started by its bound native entry'}
    $shell=(Get-Process -Id $PID).Path
    if($plan.shell.path -cne 'maintenance/powershell/pwsh.exe' -or
       $shell -ine (Join-Path $stage $plan.shell.path) -or (Get-ContentHash $shell) -cne $plan.shell.sha256){throw 'Setup native shell changed'}
    Assert-PackageHost ([pscustomobject]@{target='windows-arm64';hostArchitecture='arm64';requireNativeProcess=$true})
    return (Join-Path $stage 'YimeMaintenance.exe')
}
function Test-Arm64MutatingRight([int]$Rights){
    # WriteData/CreateFiles and AppendData/CreateDirectories share their bits.
    # Modify also contains read rights, so it must not be used as an overlap mask.
    $mutation=[int][Security.AccessControl.FileSystemRights]::Write -bor
        [int][Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [int][Security.AccessControl.FileSystemRights]::Delete -bor
        [int][Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [int][Security.AccessControl.FileSystemRights]::TakeOwnership -bor
        0x10000000 -bor 0x40000000 # GENERIC_ALL and GENERIC_WRITE if not mapped
    return [bool]($Rights -band $mutation)
}
function Assert-Arm64ProtectedAcl([Security.AccessControl.FileSystemSecurity]$Acl,[string]$Path,[string[]]$Trusted){
    $owner=$Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($owner -cnotin $Trusted){throw ('Untrusted owner: '+$Path)}
    foreach($rule in $Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
           -not (Test-Arm64MutatingRight $rule.FileSystemRights)){continue}
        if($rule.IdentityReference.Value -cnotin $Trusted){throw ('Writable by an unapproved principal: '+$Path)}
    }
}
function Assert-Arm64ProtectedFile([string]$Path){
    $path=Assert-PlainPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544') # SYSTEM and Administrators
    $trustedInstaller=([Security.Principal.NTAccount]'NT SERVICE\TrustedInstaller').Translate([Security.Principal.SecurityIdentifier]).Value
    $trusted+= $trustedInstaller
    for($item=$path;$item;$item=[IO.Path]::GetDirectoryName($item)){
        $acl=Get-Acl -LiteralPath $item
        Assert-Arm64ProtectedAcl $acl $item $trusted
    }
}
function Read-Arm64IndependentApproval([string]$ApprovalPath,[string]$ExpectedApprovalPath,
    [string]$CurrentSid,[bool]$Administrator,
    [scriptblock]$VerifyProtected={param([string]$Path) Assert-Arm64ProtectedFile $Path}){
    if(-not $Administrator){throw 'Native administrator token required before ARM64 maintenance'}
    $approval=Assert-PlainPath $ApprovalPath;$expectedApproval=Assert-PlainPath $ExpectedApprovalPath
    if($approval -cne $expectedApproval){throw 'Independent ARM64 approval location mismatch'}
    & $VerifyProtected $approval
    $record=Get-Content -LiteralPath $approval -Raw -Encoding UTF8 | ConvertFrom-Json
    if($record.schema -cne 'yime-18u-arm64-manual-approval-v1' -or $record.product -cne 'yimecore-18u' -or
       $record.target -cne 'windows-arm64' -or $record.approvedUserSid -cne $CurrentSid -or
       $record.sourceCommit -cne '2bc222d92321daa29cea9951761cc1063db5f045' -or
       $record.archiveSha256 -cnotmatch '^[0-9a-f]{64}$'){
        throw 'Independent ARM64 approval identity or user mismatch'
    }
    if(@($record.files).Count -eq 0){throw 'Independent ARM64 approval has no members'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $record.files){
        if(-not ($row.path -is [string]) -or $row.path -match '(^[/\\]|:|(^|[/\\])\.\.?([/\\]|$))' -or
           -not $seen.Add($row.path) -or $row.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $row.bytes -le 0){
            throw 'Invalid independent ARM64 approval member'
        }
    }
    return $record
}
function Assert-Arm64FixedPackage([string]$Root,[string]$ExpectedRoot,[string]$ApprovalPath,
    [string]$ExpectedApprovalPath,[string]$CurrentSid,[bool]$Administrator,
    [scriptblock]$VerifyProtected={param([string]$Path) Assert-Arm64ProtectedFile $Path}){
    $root=Assert-PlainPath $Root;$expected=Assert-PlainPath $ExpectedRoot
    $approval=Assert-PlainPath $ApprovalPath
    if($root -cne $expected -or $approval.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'ARM64 package or independent approval location mismatch'
    }
    $record=Read-Arm64IndependentApproval $approval $ExpectedApprovalPath $CurrentSid $Administrator $VerifyProtected
    & $VerifyProtected $root
    $manifest=Get-Content -LiteralPath (Join-Path $root 'product-package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $descriptor=Get-Content -LiteralPath (Join-Path $root 'payload/installed-18u-product.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($manifest.product -cne 'yimecore-18u' -or $manifest.target -cne 'windows-arm64' -or
       $manifest.host_architecture -cne 'arm64' -or $manifest.tsf64_architecture -cne 'arm64' -or
       $descriptor.sourceCommit -cne $record.sourceCommit -or $descriptor.architecture -cne 'native-arm64' -or
       $descriptor.identity.clsid -ine '{6DFACE1F-562E-4773-A9D6-D5753A314711}' -or
       $descriptor.identity.profile -ine '{1BD904AC-3194-4419-B70A-5574100F18B3}'){
        throw 'Fixed ARM64 package contract differs from independent approval'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $record.files){
        $null=$seen.Add($row.path)
        $file=Assert-PlainPath (Join-Path $root $row.path)
        if(-not $file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Approved member escaped fixed package'}
        & $VerifyProtected $file
        if((Get-Item -LiteralPath $file).Length -ne $row.bytes -or (Get-ContentHash $file) -cne $row.sha256){
            throw ('Independent ARM64 approval hash mismatch: '+$row.path)
        }
    }
    $files=@(Get-ProductFiles $root)
    if($seen.Count -ne $files.Count){throw 'Fixed ARM64 package contains unapproved files'}
    foreach($file in $files){
        $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
        if(-not $seen.Contains($relative)){throw ('Unapproved ARM64 package member: '+$relative)}
    }
}
function Get-Arm64StageIdentity {
    $machine=Get-NativeHostMachine
    $windowsIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
    return [pscustomobject]@{source=$machine.source;nativeMachine=$machine.nativeMachine;
        processMachine=$machine.processMachine;is64BitProcess=$machine.is64BitProcess;
        sid=$windowsIdentity.User.Value;
        administrator=([Security.Principal.WindowsPrincipal]$windowsIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);
        shellPath=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName}
}
function Assert-Arm64StageIdentity($Observed,[string]$ExpectedSid,$Initial){
    if($Observed.source -cne 'IsWow64Process2' -or $Observed.nativeMachine -ne 0xaa64 -or
       $Observed.processMachine -ne 0 -or -not $Observed.is64BitProcess -or
       -not $Observed.administrator -or $Observed.sid -cne $ExpectedSid -or
       -not $Observed.shellPath){throw 'ARM64 stage requires the same native administrator identity'}
    if($Initial -and ($Observed.sid -cne $Initial.sid -or $Observed.shellPath -cne $Initial.shellPath -or
       $Observed.nativeMachine -ne $Initial.nativeMachine -or $Observed.processMachine -ne $Initial.processMachine -or
       $Observed.administrator -ne $Initial.administrator)){
        throw 'ARM64 stage process identity changed'
    }
}
function New-Arm64ProtectedStage([string]$SourceRoot,[string]$StageRoot,[string]$ExpectedStageRoot,
    [string]$ApprovalPath,[string]$ExpectedApprovalPath,[string]$CurrentSid,
    [scriptblock]$ObserveIdentity={Get-Arm64StageIdentity},
    [scriptblock]$VerifyProtected={param([string]$Path) Assert-Arm64ProtectedFile $Path}){
    $source=Assert-PlainPath $SourceRoot;$stage=Assert-PlainPath $StageRoot
    $expected=Assert-PlainPath $ExpectedStageRoot;$approval=Assert-PlainPath $ApprovalPath
    if($stage -cne $expected -or $stage.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or
       $source.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase) -or
       $approval.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase) -or
       $approval.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or
       (Test-Path -LiteralPath $stage)){
        throw 'A fresh, separate fixed ARM64 stage is required'
    }
    $before=& $ObserveIdentity
    Assert-Arm64StageIdentity $before $CurrentSid $null
    $record=Read-Arm64IndependentApproval $approval $ExpectedApprovalPath $CurrentSid $before.administrator $VerifyProtected
    & $VerifyProtected ([IO.Path]::GetDirectoryName($stage))
    $approved=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $record.files){$null=$approved.Add($row.path)}
    $sourceFiles=@(Get-ProductFiles $source)
    if($sourceFiles.Count -ne $approved.Count){throw 'Extracted ARM64 package differs from independent approval'}
    foreach($file in $sourceFiles){
        $relative=$file.FullName.Substring($source.Length+1).Replace('\','/')
        if(-not $approved.Contains($relative)){throw ('Unapproved extracted ARM64 member: '+$relative)}
    }
    $null=[IO.Directory]::CreateDirectory($stage)
    & $VerifyProtected $stage
    foreach($row in $record.files){
        $from=Assert-PlainPath (Join-Path $source $row.path)
        if(-not $from.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){
            throw 'Extracted ARM64 member escaped source'
        }
        $to=Join-Path $stage $row.path
        $directory=[IO.Path]::GetDirectoryName($to)
        $null=[IO.Directory]::CreateDirectory($directory)
        & $VerifyProtected $directory
        [IO.File]::Copy($from,$to,$false)
        & $VerifyProtected $to
    }
    Assert-Arm64FixedPackage $stage $expected $approval $ExpectedApprovalPath $CurrentSid $before.administrator $VerifyProtected
    $after=& $ObserveIdentity
    Assert-Arm64StageIdentity $after $CurrentSid $before
    return [pscustomobject]@{root=$stage;approval=$approval;sid=$CurrentSid;identity=$before}
}
function Assert-Arm64ProtectedStageBoundary($Stage,
    [scriptblock]$ObserveIdentity={Get-Arm64StageIdentity},
    [scriptblock]$VerifyProtected={param([string]$Path) Assert-Arm64ProtectedFile $Path}){
    $now=& $ObserveIdentity
    Assert-Arm64StageIdentity $now $Stage.sid $Stage.identity
    Assert-Arm64FixedPackage $Stage.root $Stage.root $Stage.approval $Stage.approval $Stage.sid $now.administrator $VerifyProtected
    $again=& $ObserveIdentity
    Assert-Arm64StageIdentity $again $Stage.sid $Stage.identity
}
function Get-MaintenanceMembers($Product,$Contract){
    $name=if($Product.id -eq 'yimecore-18u'){'Yime18uProductRegistration.exe'}elseif($Product.id -eq 'yimecore'){'YimeTextServiceRegistration.exe'}else{$Product.dll}
    foreach($arch in $Contract.nativeDirectories){$arch+'/'+$name}
}
function Assert-ProductPe([string]$Path,[ValidateSet('arm64','arm64x','x86','x64')][string]$Architecture){
    if(-not ('YimeSimple.PeImage' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.IO;
namespace YimeSimple {
    // Structural validation only. Native and x64 load tests of the same merged
    // DLL remain separate acceptance evidence. No image is loaded by this reader.
    public sealed class PeImage {
        private byte[] data;
        private int sections, sectionTable;
        private uint headers;
        private ulong imageBase;
        public ushort Machine;
        public bool IsDll;
        public bool IsArm64X;
        private void Range(long offset, long size) {
            if(offset < 0 || size < 0 || offset > data.LongLength || size > data.LongLength-offset)
                throw new InvalidDataException("PE data range is outside the file");
        }
        private ushort U16(int offset) { Range(offset,2); return BitConverter.ToUInt16(data,offset); }
        private uint U32(int offset) { Range(offset,4); return BitConverter.ToUInt32(data,offset); }
        private ulong U64(int offset) { Range(offset,8); return BitConverter.ToUInt64(data,offset); }
        private int Rva(ulong address, uint size) {
            if(address < headers && (ulong)size <= headers-address) {
                Range((long)address,size); return checked((int)address);
            }
            for(int i=0;i<sections;i++) {
                int s=sectionTable+40*i;
                uint start=U32(s+12), rawSize=U32(s+16), raw=U32(s+20);
                if(address >= start && address-start <= rawSize && (ulong)size <= rawSize-(address-start)) {
                    long offset=checked((long)((ulong)raw+address-start));
                    Range(offset,size); return checked((int)offset);
                }
            }
            throw new InvalidDataException("PE RVA is not backed by file data");
        }
        private int Va(ulong address,uint size) {
            if(address < imageBase) throw new InvalidDataException("PE VA is below the image base");
            return Rva(address-imageBase,size);
        }
        private bool Arm64X(int optional,int optionalSize) {
            if(Machine!=0xaa64 || optionalSize<200 || U32(optional+108)<=10) return false;
            uint loadRva=U32(optional+192), loadSize=U32(optional+196);
            if(loadRva==0 || loadSize<208) return false;
            int load=Rva(loadRva,loadSize);
            uint declared=U32(load);
            if(declared>loadSize) throw new InvalidDataException("Load config exceeds its PE directory");
            if(declared<208) return false;
            ulong metadata=U64(load+200);
            if(metadata==0) return false;
            Va(metadata,4);
            ulong tablePointer=U64(load+192);
            int table; uint tableCapacity=0;
            if(tablePointer!=0) table=Va(tablePointer,8);
            else {
                if(loadSize<232 || declared<232) throw new InvalidDataException("ARM64X dynamic relocation location is missing");
                uint offset=U32(load+224); ushort section=U16(load+228);
                if(section==0 || section>sections) throw new InvalidDataException("ARM64X dynamic relocation section is invalid");
                int s=sectionTable+40*(section-1);
                uint rawSize=U32(s+16);
                if(offset>rawSize || rawSize-offset<8) throw new InvalidDataException("ARM64X dynamic relocation offset is invalid");
                tableCapacity=rawSize-offset;
                table=checked((int)((ulong)U32(s+20)+offset)); Range(table,8);
            }
            uint version=U32(table), size=U32(table+4);
            if(version!=1) throw new InvalidDataException("Unsupported ARM64X dynamic relocation version");
            if(tablePointer!=0) Va(tablePointer,checked(size+8));
            else if(size>tableCapacity-8) throw new InvalidDataException("Dynamic relocation table exceeds its section");
            Range((long)table+8,size);
            long end=(long)table+8+size, cursor=(long)table+8;
            bool found=false;
            while(cursor<end) {
                if(end-cursor<12) throw new InvalidDataException("Truncated dynamic relocation entry");
                int entry=checked((int)cursor); ulong symbol=U64(entry); uint bytes=U32(entry+8);
                cursor+=12;
                if(bytes>end-cursor) throw new InvalidDataException("Dynamic relocation payload exceeds its table");
                if(symbol==6) {
                    long block=cursor, limit=cursor+bytes;
                    while(block<limit) {
                        if(limit-block<10) throw new InvalidDataException("Empty or truncated ARM64X fixup block");
                        uint blockSize=U32(checked((int)block+4));
                        if(blockSize<10 || (blockSize&1)!=0 || blockSize>limit-block)
                            throw new InvalidDataException("ARM64X fixup block is invalid");
                        block+=blockSize; found=true;
                    }
                }
                cursor+=bytes;
            }
            return found;
        }
        public static PeImage Read(string path) {
            PeImage image=new PeImage(); image.data=File.ReadAllBytes(path);
            if(image.U16(0)!=0x5a4d) throw new InvalidDataException("Missing PE DOS header");
            int pe=checked((int)image.U32(0x3c)); image.Range(pe,24);
            if(image.U32(pe)!=0x4550) throw new InvalidDataException("Missing PE signature");
            image.Machine=image.U16(pe+4); image.sections=image.U16(pe+6);
            int optionalSize=image.U16(pe+20), optional=pe+24;
            image.Range(optional,optionalSize);
            ushort magic=image.U16(optional);
            bool wide=magic==0x20b;
            if((!wide && magic!=0x10b) || optionalSize<(wide?112:96)) throw new InvalidDataException("Invalid PE optional header");
            if((image.Machine==0x14c && wide) || ((image.Machine==0xaa64 || image.Machine==0x8664) && !wide)) throw new InvalidDataException("PE machine and optional header disagree");
            image.headers=image.U32(optional+60);
            image.imageBase=wide?image.U64(optional+24):image.U32(optional+28);
            image.sectionTable=optional+optionalSize;
            image.Range(image.sectionTable,(long)image.sections*40);
            image.IsDll=(image.U16(pe+22)&0x2000)!=0;
            image.IsArm64X=wide && image.Arm64X(optional,optionalSize);
            return image;
        }
    }
}
'@
    }
    $image=[YimeSimple.PeImage]::Read($Path)
    $expected=if($Architecture -ceq 'x86'){0x014c}elseif($Architecture -ceq 'x64'){0x8664}else{0xaa64}
    $isDll=[IO.Path]::GetExtension($Path) -ieq '.dll'
    if($image.Machine -ne $expected -or $image.IsDll -ne $isDll -or
        ($Architecture -ceq 'arm64x' -and -not $image.IsArm64X) -or
        ($Architecture -ceq 'arm64' -and $image.IsArm64X)){
        throw ('PE architecture mismatch: '+$Path+'; expected '+$Architecture)
    }
}
function Assert-Arm64ProductPayload([string]$Root,$Manifest,$Product,$Members){
    foreach($required in @('local-product.json','package-manifest.json','speech-capability.json')){
        if(-not $Members.Contains($required)){throw ('Missing ARM64 product resource: '+$required)}
    }
    $speechFiles=@('speech/product.json','speech/admission.json','speech/forward-source.json','speech/admitted-records.json')
    foreach($mode in @('full','variable','shorthand')){foreach($stage in @('core','stage5c')){$speechFiles+=('speech/indexes/'+$mode+'-'+$stage+'.yidx')}}
    foreach($required in $speechFiles){if(-not $Members.Contains($required)){throw ('Missing ARM64 speech resource: '+$required)}}
    $descriptor=Get-Content -LiteralPath (Join-Path $Root 'payload/local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($descriptor.package_contract -cne 'yimecore-arm64-product-package-v1' -or
        $descriptor.identity.clsid -ine $Product.clsid -or $descriptor.identity.profile -ine $Product.profile -or
        $descriptor.scope.target -cne 'windows-arm64' -or $descriptor.scope.tsf64_architecture -cne 'arm64x' -or
        (@($descriptor.scope.active_architectures) -join '|') -cne 'arm64|x86'){
        throw 'ARM64 source descriptor does not match this product contract'
    }
    if(-not @($descriptor.go_binaries).Count -or -not @($descriptor.assets).Count -or
        (@($descriptor.native_binaries) -join '|') -cne 'YimeTextServiceExperiment.dll|YimeTextServiceRegistration.exe|YimeRegisteredHostTests.exe'){
        throw 'ARM64 source descriptor has incomplete payload requirements'
    }
    foreach($entry in @($descriptor.go_binaries)+@($descriptor.assets)){
        if(-not $Members.Contains($entry.path)){throw ('Missing declared ARM64 product resource: '+$entry.path)}
    }
    foreach($arch in @('arm64','x86')){
        foreach($name in $descriptor.native_binaries){
            if(-not $Members.Contains($arch+'/'+$name)){throw ('Missing declared ARM64 native resource: '+$arch+'/'+$name)}
        }
    }
    foreach($row in $Manifest.files){
        if($row.path -match '^x64[/\\]'){throw 'ARM64 packages must not contain a separate x64 COM payload'}
        if($row.path -notmatch '\.(exe|dll)$'){continue}
        $expected=if($row.path -ceq 'arm64/YimeTextServiceExperiment.dll'){'arm64x'}
            elseif($row.path -match '^x86/'){ 'x86' }
            elseif($row.path -match '^(arm64|bin|speech)/'){ 'arm64' }
            else{throw ('Unexpected ARM64 package executable location: '+$row.path)}
        Assert-ProductPe (Join-Path $Root ('payload/'+$row.path)) $expected
    }
}
function Assert-18uPackageIdentity([string]$Root,$Manifest,$Product,$Members){
    $contract=Get-PackageContract $Manifest
    $expectedArchitecture=if($contract.hostArchitecture -ceq 'arm64'){'native-arm64'}else{'native-x64'}
    $descriptor=Get-Content -LiteralPath (Join-Path $Root 'installed-18u-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($descriptor.schema -cnotin @('installed-18u-product-v1','installed-18u-product-v2') -or $descriptor.product -cne 'yimecore-18u' -or
       $descriptor.sourceCommit -cnotmatch '^[0-9a-f]{40}$' -or $descriptor.identity.clsid -ine $Product.clsid -or
       $descriptor.identity.profile -ine $Product.profile -or $descriptor.architecture -cne $expectedArchitecture){throw 'Independent 18u source identity mismatch'}
    if($descriptor.schema -ceq 'installed-18u-product-v1'){
        if($descriptor.language -cne 'CN' -or $descriptor.mode -cne 'variable' -or $descriptor.autostart -ne $false){throw 'Legacy 18u scope mismatch'}
    }else{
        if($descriptor.PSObject.Properties['language'] -or $descriptor.PSObject.Properties['mode'] -or $descriptor.autostart -ne $true -or
           (@($descriptor.languages)-join ',') -cne 'CN,EN' -or (@($descriptor.modes)-join ',') -cne 'full,variable,shorthand' -or
           (@($descriptor.capabilities)-join ',') -cne 'installed-tsf-frontend,composition,candidates,literal,host-editing'){throw 'Complete 18u capabilities mismatch'}
        foreach($name in Get-18uFrontendMembers){if(-not $Members.Contains($name)){throw ('Missing 18u frontend resource: '+$name)}}
    }
    $sourceProductName=if($contract.nativeDirectory -ceq 'arm64'){'18u-touch-product-arm64.json'}else{'18u-touch-product.json'}
    $sourceProduct=Get-Content -LiteralPath (Join-Path $Root ('source/tools/yimecore/'+$sourceProductName)) -Raw -Encoding UTF8|ConvertFrom-Json
    $lock=Get-Content -LiteralPath (Join-Path $Root 'source/prototypes/touch-terminal/desktop/resources.lock.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $layout='995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c'
    $dictionary='43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353'
    if($sourceProduct.identity.clsid -ine $Product.clsid -or $sourceProduct.identity.profile -ine $Product.profile -or $sourceProduct.scope.architecture -cne $contract.nativeDirectory -or $sourceProduct.data.layout_sha256 -cne $layout -or $sourceProduct.data.dictionary_sha256 -cne $dictionary -or $sourceProduct.data.standard_index_fallback -ne $false -or $lock.schemaVersion -ne 1 -or $lock.layoutProjectionSHA256 -cne $layout){throw '18u canonical source identity mismatch'}
    if($descriptor.schema -ceq 'installed-18u-product-v2'){
        if($sourceProduct.schema_version -cne 'yimecore-18u-touch-product-v2' -or $sourceProduct.installable -ne $true -or
           $sourceProduct.scope.installed_frontend -ne $true -or (@($sourceProduct.scope.languages)-join ',') -cne 'CN,EN' -or
           (@($sourceProduct.scope.modes)-join ',') -cne 'full,variable,shorthand' -or
           (@($sourceProduct.scope.capabilities)-join ',') -cne (@($descriptor.capabilities)-join ',')){throw '18u frontend source scope mismatch'}
        foreach($mode in @('full','variable','shorthand')){
            if($sourceProduct.data.dictionary_sha256_by_mode.$mode -cne $lock.files.('yime_'+$mode+'.dict.yaml').sha256){throw '18u frontend dictionary identity mismatch'}
        }
    }
    $names=@('ascii_keyboard_manifest.json','yime_variable.dict.yaml','yime_full.dict.yaml','yime_shorthand.dict.yaml')
    if(@($lock.files.PSObject.Properties).Count -ne $names.Count){throw 'Incomplete dedicated resource lock'}
    foreach($name in $names){
        $record=$lock.files.PSObject.Properties[$name]
        $rows=@($Manifest.files|Where-Object {$_.path -ceq ('data/'+$name)})
        if(-not $record -or $rows.Count -ne 1 -or $record.Value.sha256 -cne $rows[0].sha256 -or $record.Value.bytes -ne $rows[0].bytes){throw '18u locked payload mismatch'}
    }
    if($lock.files.'yime_variable.dict.yaml'.sha256 -cne $dictionary){throw '18u dictionary mismatch'}
    $physical=Get-Content -LiteralPath (Join-Path $Root 'source/prototypes/touch-terminal/data/physical-layout.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($physical.layoutId -cne $layout){throw '18u physical layout mismatch'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $descriptor.files){
        if(-not $seen.Add($row.path) -or -not $Members.Contains($row.path)){throw '18u descriptor members mismatch'}
        $matches=@($Manifest.files|Where-Object {$_.path -ceq $row.path})
        if($matches.Count -ne 1 -or $row.sha256 -cne $matches[0].sha256 -or $row.bytes -ne $matches[0].bytes){throw '18u descriptor hash mismatch'}
    }
    if($seen.Count -ne $Members.Count-1 -or $seen.Contains('installed-18u-product.json')){throw '18u descriptor must cover every other payload exactly'}
    $foreign=if($contract.nativeDirectory -ceq 'arm64'){'x64'}else{'arm64'}
    if(@($Manifest.files|Where-Object {$_.path -match ('^(indexes|x86|'+$foreign+')/|YimeCoreTrialRuntime|YimeBroker\.exe|RegistrationProbe|ActivationStage1|ActivatedLoopOnce')}).Count){throw 'Standard, foreign-architecture or temporary-registration payload forbidden in installed 18u'}
}
function Get-18uFrontendMembers {
    return @('bin/YimeTouchKeyboard.exe',
        'source/prototypes/touch-terminal/encoding/manual_key_layout.resolved.json',
        'source/prototypes/touch-terminal/desktop/profiles/main-only.json',
        'source/go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf')
}
function Assert-RimeArm64Payload([string]$Root,$Manifest,$Members){
    $required=@('PIMELauncher.exe','arm64/PIMETextService.dll','arm64/PIMERegistrationStatus.exe',
        'x86/PIMETextService.dll','x86/PIMERegistrationStatus.exe','go-backend/server.exe',
        'go-backend/input_methods/yime/rime_runtime.lock.json')
    foreach($name in $required){if(-not $Members.Contains($name)){throw ('Missing ARM64 Rime member: '+$name)}}
    $engineRoot='go-backend/input_methods/yime/'
    $lock=Get-Content -LiteralPath (Join-Path $Root 'payload/go-backend/input_methods/yime/rime_runtime.lock.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($lock.schema_version -ne 1 -or $lock.platform -cne 'Windows-msvc-arm64' -or
       $lock.librime_version -cne '1.17.0' -or $lock.librime_commit -cne '33e78140250125871856cdc5b42ddc6a5fcd3cd4'){
        throw 'ARM64 Rime runtime source identity mismatch'
    }
    foreach($name in @('rime.dll','rime_deployer.exe','rime_dict_manager.exe')){
        $member=$engineRoot+$name
        $rows=@($Manifest.files|Where-Object {$_.path -ceq $member})
        $record=$lock.files.PSObject.Properties[$name]
        if($rows.Count -ne 1 -or -not $record -or $record.Value -cne $rows[0].sha256){throw 'ARM64 Rime runtime hash mismatch'}
    }
    foreach($row in $Manifest.files){
        if($row.path -match '^x64[/\\]'){throw 'ARM64 Rime must use one ARM64X 64-bit COM payload'}
        if($row.path -notmatch '\.(exe|dll)$'){continue}
        $architecture=if($row.path -ceq 'arm64/PIMETextService.dll'){'arm64x'}elseif($row.path.StartsWith('x86/')){'x86'}else{'arm64'}
        Assert-ProductPe (Join-Path $Root ('payload/'+$row.path)) $architecture
    }
}
function Read-Package([string]$Root){
    $root=Assert-PlainPath $Root
    $manifest=Get-Content -LiteralPath (Join-Path $root 'product-package.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $product=Get-Product $manifest.product
    $contract=Get-PackageContract $manifest
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $manifest.files){
        if($row.path -match '(^[/\\]|:|(^|[/\\])\.\.?([/\\]|$))' -or -not $seen.Add($row.path)){throw 'Invalid package member'}
        $path=Assert-PlainPath (Join-Path $root ('payload\'+$row.path))
        if(-not $path.StartsWith($root+'\payload\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package member escaped payload'}
        if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-ContentHash $path) -cne $row.sha256){throw ('Package damaged: '+$row.path)}
    }
    $actual=@(Get-ProductFiles (Join-Path $root 'payload'))
    if($actual.Count -ne $seen.Count){throw 'Package contains unlisted files'}
    foreach($arch in $contract.nativeDirectories){
        if(-not $seen.Contains($arch+'/'+$product.dll)){throw ('Missing text service: '+$arch)}
        if($product.id -eq 'yimecore-18u' -and -not $seen.Contains($arch+'/Yime18uProductRegistration.exe')){throw 'Missing independent 18u registration tool'}
        if($product.id -eq 'yimecore' -and -not $seen.Contains($arch+'/YimeTextServiceRegistration.exe')){throw 'Missing native registration tool'}
        if($product.id -eq 'rime-pime' -and -not $seen.Contains($arch+'/PIMERegistrationStatus.exe')){throw 'Missing native registration verifier'}
    }
    if(-not $seen.Contains($product.exe.Replace('\','/'))){throw 'Missing runtime'}
    $sourceProductName=if($contract.nativeDirectory -ceq 'arm64'){'18u-touch-product-arm64.json'}else{'18u-touch-product.json'}
    $required=if($product.id -eq 'yimecore-18u'){@('profile-icon.ico','source/prototypes/touch-terminal/desktop/resources.lock.json','bin/YimeBroker18u.exe',($contract.nativeDirectory+'/YimeTouchRegisteredFormalHostTests.exe'),'installed-18u-product.json',('source/tools/yimecore/'+$sourceProductName),'source/prototypes/touch-terminal/data/physical-layout.json','source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json','source/internal_data/yime_syllable_decomposition.tsv','data/ascii_keyboard_manifest.json','data/yime_variable.dict.yaml','data/yime_full.dict.yaml','data/yime_shorthand.dict.yaml')}elseif($product.id -eq 'yimecore'){@('bin/YimeBroker.exe','bin/YimeCoreInputToolbar.exe','bin/YimeCoreTrainer.exe','bin/YimeCoreToolCenter.exe','profile-icon.ico','indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx','data/yime_pinyin_codes.tsv','data/fonts/YinYuan-Regular.ttf')}else{@('backends.json','go-backend/server.exe','go-backend/input_methods/yime/ime.json','go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf')}
    foreach($name in $required){if(-not $seen.Contains($name)){throw ('Missing product resource: '+$name)}}
    if($product.id -ceq 'yimecore-18u'){
        Assert-18uPackageIdentity (Join-Path $root 'payload') $manifest $product $seen
        foreach($row in $manifest.files){if($row.path -match '\.(exe|dll)$'){Assert-ProductPe (Join-Path $root ('payload/'+$row.path)) $contract.nativeDirectory}}
    }
    if($contract.target -ceq 'windows-arm64' -and $product.id -ceq 'yimecore'){
        Assert-Arm64ProductPayload $root $manifest $product $seen
    }elseif($contract.target -ceq 'windows-arm64' -and $product.id -ceq 'rime-pime'){
        Assert-RimeArm64Payload $root $manifest $seen
    }elseif($contract.target -cne 'windows-arm64' -and @($manifest.files | Where-Object {$_.path -match '^arm64/'}).Count){throw 'ARM64 payload cannot use the legacy x64 contract'}
    return [pscustomobject]@{root=$root;manifest=$manifest;product=$product;contract=$contract}
}
function Read-MaintenancePackage([string]$Root){
    $root=Assert-PlainPath $Root
    $manifest=Get-Content -LiteralPath (Join-Path $root 'product-package.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $product=Get-Product $manifest.product;$contract=Get-PackageContract $manifest
    foreach($member in Get-MaintenanceMembers $product $contract){
        $rows=@($manifest.files | Where-Object {$_.path -ceq $member})
        if($rows.Count -ne 1){throw ('Missing maintenance manifest member: '+$member)}
        $path=Assert-PlainPath (Join-Path $root ('native/'+$member))
        if((Get-Item -LiteralPath $path).Length -ne $rows[0].bytes -or (Get-ContentHash $path) -cne $rows[0].sha256){throw ('Maintenance resource damaged: '+$member)}
        if($product.id -ceq 'yimecore-18u'){Assert-ProductPe $path $contract.nativeDirectory}
        if($contract.target -ceq 'windows-arm64' -and $product.id -ceq 'yimecore'){
            $expected=if($member.StartsWith('arm64/')){'arm64'}else{'x86'}
            Assert-ProductPe $path $expected
        }
        if($contract.target -ceq 'windows-arm64' -and $product.id -ceq 'rime-pime'){
            $expected=if($member.StartsWith('x86/')){'x86'}elseif($member -ceq 'arm64/PIMETextService.dll'){'arm64x'}else{'arm64'}
            Assert-ProductPe $path $expected
        }
    }
    return [pscustomobject]@{root=$root;manifest=$manifest;product=$product;contract=$contract}
}
function Assert-OwnedDirectory([string]$Root,[string]$Product,[string]$Target){
    $root=Assert-PlainPath $Root
    if(-not (Test-Path -LiteralPath $root)){return}
    $marker=Join-Path $root '.yime-product.json'
    if(-not (Test-Path -LiteralPath $marker)){
        if(@(Get-ChildItem -LiteralPath $root -Force).Count){throw 'Directory is not owned by this installer; do not erase it'}
        return
    }
    $record=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
    if($record.product -cne $Product -or $record.format -cne 'yime-simple-install-1'){throw 'Directory belongs to another product'}
    if($Target){
        $installedTarget=if($record.PSObject.Properties['target']){$record.target}else{'windows-amd64'}
        if($installedTarget -cne $Target){throw 'Existing product target differs; use its original package to uninstall it first'}
    }
    $null=@(Get-ProductFiles $root)
}
function Assert-Installed18uOwnership([string]$Root){
    # Local installation consistency, not publisher authentication or a recovery ticket.
    # Use the OLD installation's own manifest: an upgrade package has different hashes.
    $root=Assert-PlainPath $Root
    $marker=Get-Content -LiteralPath (Join-Path $root '.yime-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $maintenance=Read-MaintenancePackage (Join-Path $root '.setup')
    $manifest=$maintenance.manifest
    Assert-OwnedDirectory $root 'yimecore-18u' $maintenance.contract.target
    if($maintenance.product.id -cne 'yimecore-18u' -or
       -not ($marker.version -is [string]) -or [string]::IsNullOrWhiteSpace($marker.version) -or
       $marker.version -cne $manifest.version){throw 'Installed 18u marker and maintenance manifest disagree'}
    $arch=$maintenance.contract.nativeDirectory
    $sourceProductName=if($arch -ceq 'arm64'){'18u-touch-product-arm64.json'}else{'18u-touch-product.json'}
    $expected=@(($arch+'/YimeTextService18u.dll'),($arch+'/Yime18uProductRegistration.exe'),($arch+'/YimeTouchRegisteredFormalHostTests.exe'),
        'bin/YimeBroker18u.exe','bin/Yime18uInstalledRuntime.exe','profile-icon.ico','installed-18u-product.json',
        'source/prototypes/touch-terminal/desktop/resources.lock.json',('source/tools/yimecore/'+$sourceProductName),
        'source/prototypes/touch-terminal/data/physical-layout.json','source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json',
        'source/internal_data/yime_syllable_decomposition.tsv','data/ascii_keyboard_manifest.json','data/yime_variable.dict.yaml',
        'data/yime_full.dict.yaml','data/yime_shorthand.dict.yaml')
    $installedDescriptor=Get-Content -LiteralPath (Join-Path $root 'installed-18u-product.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($installedDescriptor.schema -ceq 'installed-18u-product-v2'){$expected+=@(Get-18uFrontendMembers)}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $manifest.files){
        if(-not ($row.path -is [string]) -or $row.path -cnotin $expected -or -not $seen.Add($row.path) -or
           $row.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $row.bytes -lt 0){throw 'Invalid installed 18u manifest member'}
        $path=Assert-PlainPath (Join-Path $root $row.path)
        if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Installed member escaped product root'}
        if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-ContentHash $path) -cne $row.sha256){throw ('Installed 18u payload damaged: '+$row.path)}
        if($row.path -match '\.(exe|dll)$'){Assert-ProductPe $path $arch}
    }
    if($seen.Count -ne $expected.Count){throw 'Incomplete installed 18u manifest'}
    Assert-18uPackageIdentity $root $manifest $maintenance.product $seen
    # User data is outside this program directory. Unknown program files stop removal.
    $allowed=@($expected)+@('.yime-product.json','.setup/Product.psm1','.setup/Setup.ps1','.setup/Setup.cmd',
        '.setup/product-package.json',('.setup/native/'+$arch+'/Yime18uProductRegistration.exe'))
    foreach($file in Get-ProductFiles $root){
        $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
        if($relative -cnotin $allowed){throw ('Unknown installed 18u file: '+$relative)}
    }
    Write-Output ('Installed ownership verified: product=yimecore-18u; version='+$marker.version+'; payload_count='+$seen.Count+'; publisher_authentication=false')
}
function Get-ProductFileUsers([string[]]$Paths){
    # Query only. Never ask Restart Manager to close or restart an application.
    if(-not ('YimeSimple.FileUsers' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace YimeSimple {
    public static class FileUsers {
        [StructLayout(LayoutKind.Sequential)]
        public struct UniqueProcess { public uint Pid; public System.Runtime.InteropServices.ComTypes.FILETIME Start; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct ProcessInfo {
            public UniqueProcess Process;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Application;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string Service;
            public int Type; public uint Status; public uint Session;
            [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
        }
        [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)]
        static extern int RmStartSession(out uint session, uint flags, StringBuilder key);
        [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)]
        static extern int RmRegisterResources(uint session, uint count, string[] paths,
            uint applications, IntPtr processes, uint services, IntPtr names);
        [DllImport("rstrtmgr.dll")]
        static extern int RmGetList(uint session, out uint needed, ref uint count,
            [In, Out] ProcessInfo[] processes, ref uint rebootReasons);
        [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint session);
        public static ProcessInfo[] Query(string[] paths) {
            uint session; int error=RmStartSession(out session, 0, new StringBuilder(33));
            if(error!=0) throw new Win32Exception(error, "RmStartSession");
            try {
                error=RmRegisterResources(session, (uint)paths.Length, paths, 0, IntPtr.Zero, 0, IntPtr.Zero);
                if(error!=0) throw new Win32Exception(error, "RmRegisterResources");
                uint needed=0, count=0, reasons=0;
                ProcessInfo[] rows=null;
                // The process list can change during enumeration; bound retries.
                for(int attempt=0; attempt<3; attempt++) {
                    error=RmGetList(session, out needed, ref count, rows, ref reasons);
                    if(error==0) {
                        if(rows==null) return new ProcessInfo[0];
                        Array.Resize(ref rows, checked((int)count)); return rows;
                    }
                    if(error!=234) throw new Win32Exception(error, "RmGetList");
                    rows=new ProcessInfo[needed]; count=needed;
                }
                throw new Win32Exception(error, "RmGetList changed repeatedly");
            } finally { RmEndSession(session); }
        }
    }
}
'@
    }
    [YimeSimple.FileUsers]::Query($Paths)
}
function Get-ProductFileAccessFailure([string]$Path,[Exception]$Exception){
    $cause=$Exception
    while($cause.InnerException){$cause=$cause.InnerException}
    $hr=$cause.HResult
    $code=if(($hr -band 0xffff0000L) -eq 0x80070000L){$hr -band 0xffff}else{$null}
    $kind=switch($code){
        32 {'sharing-violation'}
        33 {'lock-violation'}
        5 {'access-denied-or-mapped-image'}
        default {'other-file-error'}
    }
    [pscustomobject]@{path=$Path;kind=$kind;exception=$cause.GetType().FullName;
        hresult=('0x{0:X8}' -f $hr);win32=$code;message=$cause.Message}
}
function Wait-ProductFiles([string]$Root,[switch]$Silent){
    if(-not (Test-Path -LiteralPath $Root)){return}
    while($true){
        $busy=@(foreach($file in Get-ProductFiles $Root){
            try{$s=[IO.File]::Open($file.FullName,'Open','ReadWrite','None');$s.Dispose()}
            catch{Get-ProductFileAccessFailure $file.FullName $_.Exception}
        })
        if(-not $busy.Count){return}
        foreach($failure in $busy){Write-Output ('File access failure: '+($failure|ConvertTo-Json -Compress))}
        try{
            $users=@(Get-ProductFileUsers @($busy.path))
            Write-Output ('File users query: '+(@{source='RestartManager';status='ok';count=$users.Count;users=@($users|ForEach-Object {
                [ordered]@{pid=$_.Process.Pid;startTimeHigh=$_.Process.Start.dwHighDateTime;startTimeLow=$_.Process.Start.dwLowDateTime;
                    application=$_.Application;service=$_.Service;session=$_.Session}
            })}|ConvertTo-Json -Depth 5 -Compress))
        }catch{Write-Output ('File users query unavailable: '+$_.Exception.Message)}
        # An empty/inaccessible process list never makes the failed open safe.
        # Error 5 alone does not prove an ACL fault (mapped images may also deny writes).
        $paths=@($busy.path)
        Write-Output ('Files unavailable under '+$Root+': '+($paths -join ', '))
        if($Silent){throw ('Files unavailable: '+($paths -join ', '))}
        Add-Type -AssemblyName System.Windows.Forms
        $text="请保存工作并退出正在使用本输入法的应用，再选择重试。`r`n仍被占用或不可写：`r`n"+($paths -join "`r`n")+"`r`n错误码和占用查询已写入日志。无法释放时请取消，正常重启后再安装或卸载。不会强制关闭文档应用，也不会覆盖已加载 DLL。"
        if([Windows.Forms.MessageBox]::Show($text,'输入法安装维护','RetryCancel','Warning') -ne 'Retry'){throw [OperationCanceledException]::new('Cancelled')}
    }
}
function Copy-ProductPayload($Package,[string]$Destination){
    $target=if($Package.manifest.PSObject.Properties['target']){$Package.manifest.target}else{'windows-amd64'}
    Assert-OwnedDirectory $Destination $Package.product.id $target
    $null=[IO.Directory]::CreateDirectory($Destination)
    # Write ownership first. A partially copied install can be removed/reinstalled.
    [IO.File]::WriteAllText((Join-Path $Destination '.yime-product.json'),(@{format='yime-simple-install-1';product=$Package.product.id;version=$Package.manifest.version;target=$target}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    foreach($row in $Package.manifest.files){
        $target=Join-Path $Destination $row.path
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [IO.File]::Copy((Join-Path $Package.root ('payload\'+$row.path)),$target,$true)
    }
}
function Remove-ProductDirectory([string]$Root,[string]$Product){
    Assert-OwnedDirectory $Root $Product
    if(Test-Path -LiteralPath $Root){
        $root=Assert-PlainPath $Root
        # Keep ownership until all other children are gone, including partial deletion.
        foreach($item in Get-ChildItem -LiteralPath $root -Force){
            if($item.Name -ne '.yime-product.json'){Remove-Item -LiteralPath $item.FullName -Recurse -Force}
        }
        $marker=Join-Path $root '.yime-product.json'
        if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker -Force}
        Remove-Item -LiteralPath $root
    }
}
Export-ModuleMember -Function *-*
