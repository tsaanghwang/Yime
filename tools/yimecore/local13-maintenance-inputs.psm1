Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Private fixed catalog. Tests may replace it inside the module's own session;
# no exported function accepts a root, hash, policy, or provider override.
$script:InputCatalog=@{
    root='C:\Users\tsaan\YimeCore Recovery Archives\local13-maintenance-candidates-20260908-7a42bbe7efe245d89f6faae080d8f4ea'
    archive_manifest_sha256='1d74e0d714231e36f2300eca534de60165c2c3d94492d35f08a831962ff8af4e'
    archive_summary_sha256='38317725084b264d4ef216cf88f72f19ec12613f39f330c17c8f742581c0706a'
    normal_manifest_sha256='1fd54730bffe9b986249cdeaedbd7c8807b255da36e75c6463ff983e378275a9'
    fault_manifest_sha256='7a70ba727e0cc157358680213ea5e4cbb52b711631c74d0d2182b5029cc141ef'
    normal_id='yimecore-local-0.1.0-local.13-3687a998fda0'
    fault_id='yimecore-local-0.1.0-local.13-3687a998fda0-rollback-failure-5ae5a75eb47a'
    package_members=85;archive_inputs=182
    controller_sha256='9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d'
    wrapper_sha256='ec206153c53d96b98aa43cd522167bb55eef83b7d7acedf745f8f966c6851479'
    preparation_sha256='4efc8eebf8629c196f74d32ef163545470ae0ba60f14e137c2e71731b3ba0712'
    plan_sha256='817feacf00b871a06e1dd35773f2f22c716803fc6b2fff57c53443314d33a712'
    runtime_sha256='5ae5a75eb47a69abe1378ac86c6e5695daebbd3b4ed91af5712bfdc1729b168e'
    probe_source_sha256='c17ee123594a4453260583cb53c9ca8133ddde6df4defa2f50d37d3dc75d13b9'
    preparation_entry_sha256='f2ec9c3b0f9e9780fe4fdabbd2628d370dcb31707488f936c1d59fa9cf5d5f52'
    preparation_module_sha256='462d5184c48c223e22cbcfa6dfc53c73d4ddcfb0693d832286b9f7101e75ab84'
}
$script:NativeFactsHash='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
$script:InputSessions=@{}
$script:ClosedSessions=@{}

function Assert-InputPlainPath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\');$cursor=$full
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Indirect maintenance input path rejected.'}
        }
        $parent=Split-Path -Parent $cursor;if(-not $parent -or $parent -eq $cursor){break};$cursor=$parent
    };return $full
}
function Assert-InputRelativePath($Path) {
    if($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path) -or
        $Path -match '[\\:"\x00-\x1f<>|?*]|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)' -or [IO.Path]::IsPathRooted($Path) -or
        $Path -match '(?i)(^|/)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]|\.git)(\.|/|$)') {throw 'Invalid maintenance input member path.'}
}
function Assert-InputString($Value,[string]$Expected) {
    if($Value -isnot [string] -or $Value -cne $Expected){throw 'Maintenance input string identity mismatch.'}
}
function Assert-InputBoolean($Value,[bool]$Expected) {
    if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Maintenance input boolean claim mismatch.'}
}
function Assert-InputInteger($Value,[long]$Expected) {
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -ne $Expected){throw 'Maintenance input integer mismatch.'}
}
function Get-InputStreamHash([IO.Stream]$Stream) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;return ([BitConverter]::ToString($hash.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$Stream.Position=0;$hash.Dispose()}
}
function Read-InputJson([IO.FileStream]$Stream,[string]$ExpectedHash) {
    if((Get-InputStreamHash $Stream) -cne $ExpectedHash){throw 'Pinned maintenance JSON hash mismatch.'}
    $reader=[IO.StreamReader]::new($Stream,[Text.Encoding]::UTF8,$true,4096,$true)
    try{return ($reader.ReadToEnd()|ConvertFrom-Json)}finally{$reader.Dispose();$Stream.Position=0}
}
function Initialize-InputNativeFacts {
    $source=Assert-InputPlainPath (Join-Path $PSScriptRoot '..\dual-product\rime-pime-dp1u-native-facts.cs')
    $stream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if((Get-InputStreamHash $stream) -cne $script:NativeFactsHash){throw 'Reviewed native input facts source changed.'}
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
    if(-not ('Yime.Local13InputFacts.Facts' -as [type])) {
        Add-Type -TypeDefinition ($text.Replace('namespace Yime.Dp1UNative {','namespace Yime.Local13InputFacts {'))
    }
    if(-not ('Yime.Local13InputDirectories' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Yime {
    public static class Local13InputDirectories {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint size, uint flags);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int kind, out AttributeTag info, uint size);
        [StructLayout(LayoutKind.Sequential)] private struct AttributeTag { public uint Attributes, Tag; }
        public static SafeFileHandle Open(string path) {
            // Read attributes, FILE_SHARE_READ, OPEN_EXISTING, backup semantics
            // and OPEN_REPARSE_POINT. This denies ordinary rename/delete while
            // held; it is not a continuous directory-membership enforcement API.
            var handle=CreateFile(path,0x80,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
            if(handle.IsInvalid){handle.Dispose();throw new Win32Exception(Marshal.GetLastWin32Error());}
            try { Verify(handle,path);return handle; } catch {handle.Dispose();throw;}
        }
        public static void Verify(SafeFileHandle handle,string path) {
            AttributeTag info;
            if(!GetFileInformationByHandleEx(handle,9,out info,8))throw new Win32Exception(Marshal.GetLastWin32Error());
            if((info.Attributes&0x10)==0 || (info.Attributes&0x400)!=0)throw new InvalidOperationException("Indirect or non-directory input rejected.");
            var final=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(handle,final,(uint)final.Capacity,0);
            if(n==0 || n>=final.Capacity)throw new Win32Exception(Marshal.GetLastWin32Error());
            if(!String.Equals(final.ToString(),@"\\?\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Input directory final path mismatch.");
        }
    }
}
'@
    }
}
function Add-InputFileLease($State,[string]$Relative,[string]$Hash,[long]$Bytes=-1) {
    Assert-InputRelativePath $Relative
    if($State.files.ContainsKey($Relative)){throw 'Duplicate maintenance input lease.'}
    $path=Assert-InputPlainPath (Join-Path $State.root $Relative)
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $State.files[$Relative]=$stream
    $State.file_ids[$Relative]=[Yime.Local13InputFacts.Facts]::VerifyFileHandle($stream,$path)
    if(($Bytes -ge 0 -and $stream.Length -ne $Bytes) -or (Get-InputStreamHash $stream) -cne $Hash){throw 'Pinned maintenance input bytes changed.'}
}
function Assert-InputRecords($Records,[int]$Count) {
    if($Records -isnot [array] -or $Records.Count -ne $Count){throw 'Maintenance input file list must be an exact JSON array.'}
    $map=@{}
    foreach($row in $Records) {
        Assert-InputRelativePath $row.path
        if($map.ContainsKey($row.path) -or $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 0){throw 'Invalid or duplicate maintenance input record.'}
        $map[$row.path]=$row
    };return $map
}
function Assert-InputTree($State) {
    $seenFiles=@{};$seenDirs=@{};$queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($State.root)
    while($queue.Count){$dir=$queue.Dequeue()
        [Yime.Local13InputDirectories]::Verify($State.directories[$dir],$dir)
        foreach($item in Get-ChildItem -LiteralPath $dir -Force){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect maintenance input tree member.'}
            if($item.PSIsContainer){if(-not $State.directories.ContainsKey($item.FullName)){throw 'Unlisted maintenance input directory.'};$seenDirs[$item.FullName]=1;$queue.Enqueue($item.FullName)}
            else{$relative=$item.FullName.Substring($State.root.Length+1).Replace('\','/')
                if(-not $State.files.ContainsKey($relative)){throw 'Unlisted maintenance input file.'};$seenFiles[$relative]=1
                $id=[Yime.Local13InputFacts.Facts]::VerifyFileHandle($State.files[$relative],$item.FullName)
                if($id -cne $State.file_ids[$relative]){throw 'Maintenance input file identity changed.'}
            }
        }
    }
    if($seenFiles.Count -ne $State.files.Count -or $seenDirs.Count+1 -ne $State.directories.Count){throw 'Incomplete maintenance input tree.'}
}
function Assert-InputPackage($State,[string]$Lane,[string]$ManifestHash,[string]$PackageId,[bool]$Fault) {
    $prefix=$Lane+'/package/'
    $manifest=Read-InputJson $State.files[$prefix+'package-manifest.json'] $ManifestHash
    Assert-InputString $manifest.package_contract 'yimecore-local-product-package-v1'
    Assert-InputString $manifest.tool_version 'yimecore-local-builder-v1'
    Assert-InputString $manifest.product_version '0.1.0-local.13'
    Assert-InputString $manifest.package_id $PackageId
    $members=Assert-InputRecords $manifest.files $script:InputCatalog.package_members
    $actual=@($State.records.Keys|Where-Object {$_.StartsWith($prefix,[StringComparison]::Ordinal)} )
    if($actual.Count -ne $members.Count+1){throw 'Package member closure differs from archive.'}
    foreach($row in $manifest.files){
        if($row.path -in @('package-manifest.json','install-metadata.json')){throw 'Installed metadata cannot be a public input.'}
        $archiveRow=$State.records[$prefix+$row.path]
        if(-not $archiveRow -or $archiveRow.bytes -ne $row.bytes -or $archiveRow.sha256 -cne $row.sha256){throw 'Package/archive record mismatch.'}
    }
    foreach($name in @('local-product.json','maintenance/Manage-YimeCoreTrial.ps1','maintenance/manage-local-product.ps1',
        'x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll','x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
        'bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','bin/YimeCoreRecoveryProbe.exe')){if(-not $members.ContainsKey($name)){throw 'Required dual-architecture package input missing.'}}
    Assert-InputString $members['maintenance/Manage-YimeCoreTrial.ps1'].sha256 $script:InputCatalog.controller_sha256
    Assert-InputString $members['maintenance/manage-local-product.ps1'].sha256 $script:InputCatalog.wrapper_sha256
    $descriptor=Read-InputJson $State.files[$prefix+'local-product.json'] $members['local-product.json'].sha256
    Assert-InputString $descriptor.schema_version 'yimecore-local-product-v1';Assert-InputString $descriptor.version '0.1.0-local.13'
    Assert-InputString $descriptor.package_contract 'yimecore-local-product-package-v1';Assert-InputBoolean $descriptor.installable $true
    Assert-InputString $descriptor.scope.computer_name 'MYCOMPUTER'
    $active=$descriptor.scope.active_architectures
    if($active -isnot [array] -or $active.Count -ne 2){throw 'Input architecture list must be a dual-architecture JSON array.'}
    Assert-InputString $active[0] 'x64';Assert-InputString $active[1] 'x86'
    Assert-InputString $descriptor.identity.product_key 'YimeCoreExperimentalTrial'
    Assert-InputString $descriptor.identity.clsid '{E40FA752-BB96-461D-A51D-F40EB437EC65}'
    Assert-InputString $descriptor.identity.profile '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
    foreach($name in @('rehearsal_only','preparation_only')){
        $property=$manifest.PSObject.Properties[$name]
        if($Fault){if(-not $property){throw 'Fault-only marker missing.'};Assert-InputBoolean $property.Value $true}
        elseif($property){Assert-InputBoolean $property.Value $false}
    }
    if($Fault){
        Assert-InputString $manifest.source_package_manifest_sha256 $script:InputCatalog.normal_manifest_sha256
        Assert-InputString $manifest.source_package_id $script:InputCatalog.normal_id
        Assert-InputString $manifest.rehearsal_mode 'NativeDesktopRehearsal';Assert-InputInteger $manifest.expected_runtime_exit_code 86
        Assert-InputString $members['bin/YimeCoreTrialRuntime.exe'].sha256 $script:InputCatalog.runtime_sha256
    }
    return [pscustomobject]@{root=(Join-Path $State.root ($Lane+'/package'));package_id=$PackageId;manifest_sha256=$ManifestHash;member_count=$members.Count;members=$members}
}
function Get-YimeCoreLocal13MaintenanceInputPlan {
    [CmdletBinding()]param()
    return [pscustomobject]@{
        schema_version='yimecore-local13-maintenance-input-plan-v1';archive_root=$script:InputCatalog.root
        archive_manifest_sha256=$script:InputCatalog.archive_manifest_sha256
        normal=[pscustomobject]@{root=(Join-Path $script:InputCatalog.root 'normal/package');package_id=$script:InputCatalog.normal_id;manifest_sha256=$script:InputCatalog.normal_manifest_sha256;member_count=$script:InputCatalog.package_members}
        fault=[pscustomobject]@{root=(Join-Path $script:InputCatalog.root 'fault/package');package_id=$script:InputCatalog.fault_id;manifest_sha256=$script:InputCatalog.fault_manifest_sha256;member_count=$script:InputCatalog.package_members}
        controller_sha256=$script:InputCatalog.controller_sha256;verification_performed=$false;input_files_opened=$false
        continuous_membership_protection=$false;execution_authorized=$false;ready_to_execute=$false
        installed_package_read=$false;user_state_read=$false;artifact_executed=$false
    }
}
function Open-YimeCoreLocal13MaintenanceInputs {
    [CmdletBinding()]param()
    Initialize-InputNativeFacts
    $state=@{root=(Assert-InputPlainPath $script:InputCatalog.root);files=@{};file_ids=@{};directories=@{};records=@{}}
    $success=$false
    try {
        $state.directories[$state.root]=[Yime.Local13InputDirectories]::Open($state.root)
        Add-InputFileLease $state 'archive-manifest.json' $script:InputCatalog.archive_manifest_sha256
        $archive=Read-InputJson $state.files['archive-manifest.json'] $script:InputCatalog.archive_manifest_sha256
        Assert-InputString $archive.schema_version 'yimecore-local13-public-archive-v1';Assert-InputString $archive.root $state.root
        Assert-InputString $archive.normal_manifest_sha256 $script:InputCatalog.normal_manifest_sha256
        Assert-InputString $archive.fault_manifest_sha256 $script:InputCatalog.fault_manifest_sha256
        Assert-InputInteger $archive.source_file_count $script:InputCatalog.archive_inputs
        foreach($name in @('user_state_read','installed_package_touched','artifact_executed','execution_authorized','ready_to_execute','L6_closed')){Assert-InputBoolean $archive.$name $false}
        $state.records=Assert-InputRecords $archive.files $script:InputCatalog.archive_inputs
        $directories=@{}
        foreach($row in $archive.files){
            if($row.path -in @('archive-manifest.json','archive-summary.json')){throw 'Archive metadata cannot be an input member.'}
            $parts=$row.path.Split('/');for($i=1;$i -lt $parts.Count;$i++){$directories[(Join-Path $state.root ($parts[0..($i-1)] -join '/'))]=1}
        }
        foreach($directory in @($directories.Keys|Sort-Object Length,{$_})){$null=Assert-InputPlainPath $directory;$state.directories[$directory]=[Yime.Local13InputDirectories]::Open($directory)}
        Add-InputFileLease $state 'archive-summary.json' $script:InputCatalog.archive_summary_sha256
        foreach($row in $archive.files){Add-InputFileLease $state $row.path $row.sha256 $row.bytes}
        Assert-InputTree $state
        $summary=Read-InputJson $state.files['archive-summary.json'] $script:InputCatalog.archive_summary_sha256
        Assert-InputString $summary.schema_version 'yimecore-local13-public-archive-summary-v1';Assert-InputBoolean $summary.passed $true
        Assert-InputString $summary.archive_root $state.root;Assert-InputString $summary.archive_manifest_sha256 $script:InputCatalog.archive_manifest_sha256
        Assert-InputInteger $summary.archived_public_inputs $script:InputCatalog.archive_inputs
        foreach($name in @('user_state_backup','execution_authorized','ready_to_execute','L6_closed')){Assert-InputBoolean $summary.$name $false}
        $normal=Assert-InputPackage $state 'normal' $script:InputCatalog.normal_manifest_sha256 $script:InputCatalog.normal_id $false
        $fault=Assert-InputPackage $state 'fault' $script:InputCatalog.fault_manifest_sha256 $script:InputCatalog.fault_id $true
        if($normal.package_id -ceq $fault.package_id){throw 'Fault package must have an independent identity.'}
        foreach($path in $normal.members.Keys){
            if($path -cne 'bin/YimeCoreTrialRuntime.exe' -and ($fault.members[$path].sha256 -cne $normal.members[$path].sha256 -or $fault.members[$path].bytes -ne $normal.members[$path].bytes)){throw 'Fault package changed a non-Runtime public member.'}
        }
        $preparation=Read-InputJson $state.files['fault/evidence/preparation.json'] $script:InputCatalog.preparation_sha256
        $plan=Read-InputJson $state.files['fault/evidence/plan.json'] $script:InputCatalog.plan_sha256
        Assert-InputString $preparation.schema_version 'yimecore-local13-fault-preparation-output-v1'
        Assert-InputString $plan.schema_version 'yimecore-local13-fault-preparation-plan-v1'
        foreach($object in @($preparation,$plan)){
            Assert-InputString $object.source_manifest_sha256 $script:InputCatalog.normal_manifest_sha256
            Assert-InputString $object.source_package_id $script:InputCatalog.normal_id
            foreach($name in @('execution_authorized','ready_to_execute','probe_exit_observed','installer_executed','product_executed','installed_package_read','user_state_read','product_mutated','same_sid_execution_boundary')){Assert-InputBoolean $object.$name $false}
            Assert-InputBoolean $object.unexpected_success_rollback_guard_available $true
            Assert-InputString $object.probe_source_sha256 $script:InputCatalog.probe_source_sha256
        }
        Assert-InputString $preparation.failure_manifest_sha256 $script:InputCatalog.fault_manifest_sha256
        Assert-InputString $preparation.failure_package_id $script:InputCatalog.fault_id
        Assert-InputString $preparation.failure_runtime_sha256 $script:InputCatalog.runtime_sha256
        Assert-InputInteger $preparation.file_count $script:InputCatalog.package_members
        Assert-InputString $preparation.preparation_entry_sha256 $script:InputCatalog.preparation_entry_sha256
        Assert-InputString $preparation.preparation_module_sha256 $script:InputCatalog.preparation_module_sha256
        Assert-InputString $plan.manager_sha256 $script:InputCatalog.controller_sha256;Assert-InputString $plan.wrapper_sha256 $script:InputCatalog.wrapper_sha256
        Assert-InputString $plan.required_maintenance_mode 'NativeDesktopRehearsal'
        Assert-InputString $state.records['fault/evidence/prepare-local13-maintenance.ps1'].sha256 $script:InputCatalog.preparation_entry_sha256
        Assert-InputString $state.records['fault/evidence/local12-maintenance-preparation.psm1'].sha256 $script:InputCatalog.preparation_module_sha256
        Assert-InputString $state.records['fault/evidence/rollback-failure-runtime.go'].sha256 $script:InputCatalog.probe_source_sha256
        foreach($path in $state.files.Keys){$expected=if($path -ceq 'archive-manifest.json'){$script:InputCatalog.archive_manifest_sha256}elseif($path -ceq 'archive-summary.json'){$script:InputCatalog.archive_summary_sha256}else{$state.records[$path].sha256}
            if((Get-InputStreamHash $state.files[$path]) -cne $expected){throw 'Held input hash changed during validation.'}}
        Assert-InputTree $state
        $token=[guid]::NewGuid().ToString('N')
        $result=[pscustomobject]@{schema_version='yimecore-local13-maintenance-input-lease-v1';session_id=$token;closed=$false;verified=$true
            archive_root=$state.root;archive_manifest_sha256=$script:InputCatalog.archive_manifest_sha256
            normal=$normal;fault=$fault;controller_sha256=$script:InputCatalog.controller_sha256
            file_lease_count=$state.files.Count;directory_lease_count=$state.directories.Count;leases_held=$true
            final_paths_and_single_file_links_verified=$true;membership_snapshots=2;continuous_membership_protection=$false
            independent_native_system_visibility_verified=$false;execution_authorized=$false;ready_to_execute=$false
            installed_package_read=$false;user_state_read=$false;artifact_executed=$false
            boundary='Read leases and two membership snapshots do not prove continuous membership protection or authorize maintenance execution.'}
        $state.result=$result;$script:InputSessions[$token]=$state;$success=$true;return $result
    }finally{if(-not $success){foreach($stream in $state.files.Values){$stream.Dispose()};foreach($handle in $state.directories.Values){$handle.Dispose()}}}
}
function Close-YimeCoreLocal13MaintenanceInputs {
    [CmdletBinding()]param([Parameter(Mandatory)]$Inputs)
    if(-not $Inputs.PSObject.Properties['session_id'] -or $Inputs.session_id -isnot [string]){throw 'Invalid maintenance input lease token.'}
    $token=$Inputs.session_id
    if($script:ClosedSessions.ContainsKey($token)){return}
    if(-not $script:InputSessions.ContainsKey($token)){throw 'Unknown maintenance input lease token.'}
    $state=$script:InputSessions[$token]
    try{foreach($stream in $state.files.Values){$stream.Dispose()};foreach($handle in $state.directories.Values){$handle.Dispose()}}
    finally{$state.result.closed=$true;$state.result.leases_held=$false;$script:InputSessions.Remove($token);$script:ClosedSessions[$token]=$true}
}
Export-ModuleMember -Function Get-YimeCoreLocal13MaintenanceInputPlan,Open-YimeCoreLocal13MaintenanceInputs,Close-YimeCoreLocal13MaintenanceInputs
