Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Get-Product([string]$Id){
    switch($Id){
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
function Get-PackageContract($Manifest){
    $product=Get-Product $Manifest.product
    if($Manifest.format -ceq 'yime-simple-package-1'){
        foreach($name in @('target','host_architecture','tsf64_architecture')){
            if($Manifest.PSObject.Properties[$name]){throw 'Legacy packages must not declare a new architecture contract'}
        }
        return [pscustomobject]@{target='windows-amd64';hostArchitecture='amd64';nativeDirectory='x64';nativeDirectories=@('x64','x86');tsf64Architecture='x64'}
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
}
function Get-MaintenanceMembers($Product,$Contract){
    $name=if($Product.id -eq 'yimecore'){'YimeTextServiceRegistration.exe'}else{$Product.dll}
    foreach($arch in $Contract.nativeDirectories){$arch+'/'+$name}
}
function Assert-ProductPe([string]$Path,[ValidateSet('arm64','arm64x','x86')][string]$Architecture){
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
            if((image.Machine==0x14c && wide) || (image.Machine==0xaa64 && !wide)) throw new InvalidDataException("PE machine and optional header disagree");
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
    $expected=if($Architecture -ceq 'x86'){0x014c}else{0xaa64}
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
        if($product.id -eq 'yimecore' -and -not $seen.Contains($arch+'/YimeTextServiceRegistration.exe')){throw 'Missing native registration tool'}
        if($product.id -eq 'rime-pime' -and -not $seen.Contains($arch+'/PIMERegistrationStatus.exe')){throw 'Missing native registration verifier'}
    }
    if(-not $seen.Contains($product.exe.Replace('\','/'))){throw 'Missing runtime'}
    $required=if($product.id -eq 'yimecore'){@('bin/YimeBroker.exe','bin/YimeCoreInputToolbar.exe','bin/YimeCoreTrainer.exe','bin/YimeCoreToolCenter.exe','profile-icon.ico','indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx','data/yime_pinyin_codes.tsv','data/fonts/YinYuan-Regular.ttf')}else{@('backends.json','go-backend/server.exe','go-backend/input_methods/yime/ime.json','go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf')}
    foreach($name in $required){if(-not $seen.Contains($name)){throw ('Missing product resource: '+$name)}}
    if($contract.target -ceq 'windows-arm64'){
        Assert-Arm64ProductPayload $root $manifest $product $seen
    }elseif(@($manifest.files | Where-Object {$_.path -match '^arm64/'}).Count){throw 'ARM64 payload cannot use the legacy x64 contract'}
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
        if($contract.target -ceq 'windows-arm64'){
            $expected=if($member.StartsWith('arm64/')){'arm64'}else{'x86'}
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
function Wait-ProductFiles([string]$Root,[switch]$Silent){
    if(-not (Test-Path -LiteralPath $Root)){return}
    while($true){
        $busy=@(foreach($file in Get-ProductFiles $Root){
            try{$s=[IO.File]::Open($file.FullName,'Open','ReadWrite','None');$s.Dispose()}
            catch{$file.Name}
        })
        if(-not $busy.Count){return}
        Write-Output ('Files unavailable under '+$Root+': '+($busy -join ', '))
        if($Silent){throw ('Files unavailable: '+($busy -join ', '))}
        Add-Type -AssemblyName System.Windows.Forms
        $text="请保存工作并退出正在使用本输入法的应用，再选择重试。`r`n仍被占用或不可写：`r`n"+($busy -join "`r`n")+"`r`n无法释放时可以取消，正常重启后再运行。不会强制关闭文档应用。"
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
