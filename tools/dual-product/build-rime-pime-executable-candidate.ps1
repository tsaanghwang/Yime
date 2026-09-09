[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePayloadRoot,[Parameter(Mandatory)][string]$ExpectedSourceInventorySha256,
    [Parameter(Mandatory)][string]$OutputRoot,[string]$ProductVersion)
# Builds a new guarded artifact from explicit source-build output. Never executes it.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $ProductVersion){$ProductVersion=([IO.File]::ReadAllText((Join-Path $repo 'version.txt'))).Trim()}
if($ProductVersion -cnotmatch '^1\.4\.0-dev\.[1-9][0-9]*$' -or $ProductVersion -cne ([IO.File]::ReadAllText((Join-Path $repo 'version.txt'))).Trim()){throw 'Candidate product version must match current version.txt.'}
$candidateModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -Scope Local -PassThru
Import-Module (Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1') -Scope Local
$leases=[Collections.Generic.List[object]]::new();$stage=$null;$bundleLease=$null
function Get-BuildHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-BuildJson($Value,[string]$Path){$raw=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Value -Depth 70 -Compress)+"`n");$s=[IO.File]::Open($Path,'CreateNew','Write','None');try{$s.Write($raw,0,$raw.Length);$s.Flush($true)}finally{$s.Dispose()};Get-BuildHash $Path}
function Assert-BuildPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($full -cnotmatch '^[A-Za-z]:\\[A-Za-z0-9_. ()+\\-]+$'){throw 'Build path has unsupported NSIS metacharacters.'}
    for($p=$full;$p;$p=[IO.Path]::GetDirectoryName($p)){if(Test-Path -LiteralPath $p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Build path traverses a reparse point.'}}}
    return $full
}
function Open-BuildFile([string]$Path,$Expected){$lease=Open-RimePimePostbuildReadLease -Path $Path -ExpectedRecord $Expected -Context 'candidate build input';$leases.Add($lease);return $lease}
function Get-BuildSourcePath([string]$Relative){
    if($Relative -cnotmatch '^[A-Za-z0-9_.+() -]+(?:/[A-Za-z0-9_.+() -]+)*$'){throw 'Non-literal source inventory path.'}
    foreach($part in $Relative.Split('/')){if($part -in @('.','..') -or $part -cne $part.Trim() -or $part.EndsWith('.') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Ambiguous source inventory path.'}}
    return Join-Path $repo $Relative.Replace('/','\')
}
function Copy-BuildFile($Lease,[string]$Destination){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination));$s=[IO.File]::Open($Destination,'CreateNew','Write','None');try{$Lease.Stream.Position=0;$Lease.Stream.CopyTo($s);$s.Flush($true)}finally{$s.Dispose();$Lease.Stream.Position=0};if((Get-BuildHash $Destination) -cne $Lease.Record.sha256){throw 'Source payload copy changed.'}}
try{
    $versionLease=Open-BuildFile (Join-Path $repo 'version.txt') $null
    $versionReader=[IO.StreamReader]::new($versionLease.Stream,[Text.UTF8Encoding]::new($false,$true),$false,1024,$true)
    try{if($versionReader.ReadToEnd().Trim() -cne $ProductVersion){throw 'Version changed while acquiring its build lease.'}}finally{$versionReader.Dispose();$versionLease.Stream.Position=0}
    $out=Assert-BuildPath $OutputRoot;$sourceRoot=Assert-BuildPath $SourcePayloadRoot
    $allowed=Join-Path $repo '.tmp\dual-product'
    if([IO.Path]::GetDirectoryName($out) -ine $allowed -or [IO.Path]::GetFileName($out) -cnotmatch '^dp1-package-build-stage-[A-Za-z0-9-]+$' -or (Test-Path -LiteralPath $out)){throw 'Output must be a fresh dp1-package-build-stage-* child of repository .tmp/dual-product.'}
    if(-not $sourceRoot.StartsWith((Join-Path $repo '.tmp')+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourceRoot -PathType Container) -or $out.StartsWith($sourceRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $sourceRoot.StartsWith($out+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Explicit, disjoint source-build payload under repository .tmp required.'}
    & $candidateModule {param($hash)Assert-CandidateHash $hash} $ExpectedSourceInventorySha256
    $inventoryPath=Join-Path $sourceRoot 'source-payload-inventory.json'
    $inventoryLease=Open-BuildFile $inventoryPath $null
    if($inventoryLease.Record.sha256 -cne $ExpectedSourceInventorySha256){throw 'Source payload inventory differs from external digest.'}
    $m=[IO.MemoryStream]::new();try{$inventoryLease.Stream.CopyTo($m);$inventory=& $candidateModule {param($b)ConvertFrom-CandidateJson $b} $m.ToArray()}finally{$m.Dispose();$inventoryLease.Stream.Position=0}
    & $candidateModule {param($i)
        Assert-CandidateObject $i @('schema_version','product','source_commit','launcher_features','runtime_protocol','files','sources')
        foreach($pair in @(@('schema_version','yime-rime-pime-source-payload-inventory-v1'),@('product','rime-pime'),@('launcher_features','dp1-candidate'),@('runtime_protocol','maintenanceReady-v1'))){if($i.($pair[0]) -isnot [string] -or $i.($pair[0]) -cne $pair[1]){throw 'Unsupported source-build inventory.'}}
        if($i.source_commit -isnot [string] -or $i.source_commit -cnotmatch '^[0-9a-f]{40}$'){throw 'Source commit required.'}
        foreach($name in @('files','sources')){if($i.$name -isnot [array] -or $i.$name.Count -lt 4 -or $i.$name.Count -gt 4096){throw 'Bounded explicit source and payload lists required.'};$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($r in $i.$name){Assert-CandidateObject $r @('path','bytes','sha256');if($r.path -isnot [string]){throw 'Literal source path required.'};if($name -eq 'files'){$null=Get-CandidatePath 'C:\Source' $r.path};Assert-CandidateHash $r.sha256;if(-not $seen.Add($r.path) -or ($r.bytes -isnot [int] -and $r.bytes -isnot [long]) -or $r.bytes -lt 0 -or $r.bytes -gt 536870912){throw 'Invalid source-build file record.'}}}
    } $inventory
    $head=(& git -C $repo rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0 -or $head -cne $inventory.source_commit){throw 'Source payload belongs to another source commit.'}
    # Bind every supplied source to actual current bytes; HEAD alone is insufficient.
    foreach($row in $inventory.sources){$p=Get-BuildSourcePath $row.path;$null=Open-BuildFile $p $row}
    foreach($required in @('PIMELauncher/src/main.rs','PIMELauncher/Cargo.toml')){if(@($inventory.sources.path) -cnotcontains $required){throw 'Candidate feature build source evidence is missing.'}}
    $null=[IO.Directory]::CreateDirectory($out);$bundle=Join-Path $out 'bundle';$null=[IO.Directory]::CreateDirectory($bundle)
    foreach($row in $inventory.files){
        if($row.path -imatch '^(maintenance/|candidate\.json$|rime-pime-candidate-state\.json$|source-payload-inventory\.json$|maintenance-candidate\.exe$)'){throw 'Source payload cannot override candidate maintenance or generated members.'}
        $src=& $candidateModule {param($root,$rel)Get-CandidatePath $root $rel} $sourceRoot $row.path
        $dst=& $candidateModule {param($root,$rel)Get-CandidatePath $root $rel} $bundle $row.path
        Copy-BuildFile (Open-BuildFile $src $row) $dst
    }
    Copy-BuildFile $inventoryLease (Join-Path $bundle 'source-payload-inventory.json')
    $maintenance=@('invoke-rime-pime-candidate.ps1','rime-pime-candidate-maintenance.psm1','rime-pime-executable-candidate.psm1','rime-pime-executable-receipt.psm1',
        'rime-pime-dp1u-candidate-registration.psm1','rime-pime-dp1u-candidate-registration-child.cs','rime-pime-dp1u-candidate-runtime.psm1','rime-pime-dp1u-candidate-runtime.cs',
        'rime-pime-candidate-coordinator.cs','rime-pime-candidate-coordinator.psm1','rime-pime-ownership.ps1','rime-pime-directed-stop-contract.ps1','rime-pime-target-user.ps1',
        'rime-pime-dp1u-native-probe.psm1','rime-pime-dp1u-native-facts.cs','rime-pime-dp1u-isolated-preflight.schema.json',
        'rime-pime-dp1u-exact-file-removal.cs','rime-pime-dp1u-native-transaction.cs')
    foreach($name in $maintenance){Copy-BuildFile (Open-BuildFile (Join-Path $PSScriptRoot $name) $null) (Join-Path $bundle ('maintenance\'+$name))}
    $files=@(Get-ChildItem -LiteralPath $bundle -File -Recurse | ForEach-Object{[pscustomobject][ordered]@{path=$_.FullName.Substring($bundle.Length+1).Replace('\','/');bytes=[long]$_.Length;sha256=Get-BuildHash $_.FullName}} | Sort-Object path -CaseSensitive)
    $manifest=[ordered]@{schema_version='yime-rime-pime-executable-candidate-v1';product='rime-pime';product_version=$ProductVersion;architectures='x86,x64';installation_scope='approved-clean-isolated-x64-target';launcher_mode='required-dp1-candidate-state';maintenance_entry='maintenance/invoke-rime-pime-candidate.ps1';registration_provider='maintenance/rime-pime-dp1u-candidate-registration.psm1';runtime_provider='maintenance/rime-pime-dp1u-candidate-runtime.psm1';files=$files;source_inventory_sha256=$ExpectedSourceInventorySha256;public_release_admitted=$false;installed_acceptance_passed=$false}
    $manifestPath=Join-Path $bundle 'candidate.json';$manifestHash=Write-BuildJson $manifest $manifestPath
    $bundleLease=Open-RimePimeExecutableCandidate -PackageRoot $bundle -ExpectedManifestSha256 $manifestHash
    $peVerifier=Join-Path $repo 'tools\verify-pe-architectures.ps1'
    $null=Open-BuildFile $peVerifier $null
    & $peVerifier -RepoRoot $bundle -X86TextService (Join-Path $bundle 'x86\PIMETextService.dll') `
        -X64TextService (Join-Path $bundle 'x64\PIMETextService.dll') -X86Launcher (Join-Path $bundle 'PIMELauncher.exe') `
        -X86RegistrationStatus (Join-Path $bundle 'x86\PIMERegistrationStatus.exe') -X64RegistrationStatus (Join-Path $bundle 'x64\PIMERegistrationStatus.exe') `
        -RimeDll (Join-Path $bundle 'go-backend\input_methods\yime\rime.dll') -RimeDeployer (Join-Path $bundle 'go-backend\input_methods\yime\rime_deployer.exe') `
        -RimeDictManager (Join-Path $bundle 'go-backend\input_methods\yime\rime_dict_manager.exe') -GoBackendRoot (Join-Path $bundle 'go-backend') 6>$null | Out-Null
    # Exact paths only; unknown payload members can never be discovered by File /r.
    $includePath=Join-Path $out 'candidate-payload.nsh';$lines=[Collections.Generic.List[string]]::new()
    $archiveRows=@($files)+@([pscustomobject]@{path='candidate.json';bytes=[long](Get-Item -LiteralPath $manifestPath).Length;sha256=$manifestHash})
    foreach($row in $archiveRows){$dir=[IO.Path]::GetDirectoryName($row.path.Replace('/','\'));$path=Join-Path $bundle $row.path.Replace('/','\');$leaf=[IO.Path]::GetFileName($path);$lines.Add(('SetOutPath "$PLUGINSDIR\bundle'+$(if($dir){'\'+$dir}else{''})+'"'));$lines.Add(('File /oname="'+$leaf+'" "'+$path+'"'))}
    [IO.File]::WriteAllText($includePath,($lines -join "`r`n")+"`r`n",[Text.UTF8Encoding]::new($false));$null=Open-BuildFile $includePath $null
    $buildRelative=@('version.txt','tools/dual-product/build-rime-pime-executable-candidate.ps1','installer/rime-pime-candidate.nsi','tools/verify-pe-architectures.ps1','tools/dual-product/rime-pime-executable-receipt.psm1','tools/dual-product/rime-pime-executable-candidate.psm1',
        'tools/dual-product/rime-pime-nsis-toolchain-closure.psm1','tools/dual-product/rime-pime-nsis-toolchain-closure.ps1','tools/dual-product/rime-pime-nsis-compiler-interval.ps1','tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1',
        'tools/dual-product/rime-pime-package-staging.psm1','tools/dual-product/rime-pime-package-staging.ps1','tools/dual-product/rime-pime-package-plan.ps1','tools/dual-product/rime-pime-payload-closure.ps1',
        'tools/dual-product/rime-pime-nsis-stage.psm1','tools/dual-product/rime-pime-nsis-stage.ps1','tools/dual-product/rime-pime-postbuild-extraction.psm1','tools/dual-product/rime-pime-postbuild-extraction.ps1')
    $buildSources=@();foreach($rel in $buildRelative){$l=Open-BuildFile (Join-Path $repo $rel.Replace('/','\')) $null;$buildSources+=@([pscustomobject][ordered]@{path=$rel;bytes=$l.Record.bytes;sha256=$l.Record.sha256})}
    $toolchain=Read-RimePimePostbuildToolchainLock
    $seven=Open-BuildFile $toolchain.SevenZip.path $toolchain.Document.seven_zip;$sevenLib=Open-BuildFile $toolchain.SevenZipLibrary.path $toolchain.Document.seven_zip.library
    $info=Invoke-RimePimePostbuildSevenZip -SevenZipLease $seven -SevenZipLibraryLease $sevenLib -Arguments @('i','-sccUTF-8') -Operation 'parser identity'
    $null=Test-RimePimePostbuildSevenZipLibraryBinding -Text $info.text -ExpectedLibraryPath $toolchain.SevenZipLibrary.path -ExpectedVersion $toolchain.Document.seven_zip.library.file_version
    $stage=Open-RimePimeMonitoredNsisStage (Join-Path $out 'NSIS');$makensis=Join-Path $stage.Root 'Bin\makensis.exe'
    $installer=Join-Path $out ('YIME-RimePime-'+$ProductVersion+'-candidate.exe');$nsisSource=Join-Path $repo 'installer\rime-pime-candidate.nsi'
    foreach($l in $leases){$null=Assert-RimePimePostbuildReadLease $l}
    $saved=[Environment]::GetEnvironmentVariable('NSISDIR','Process');$env:NSISDIR=$stage.Root
    Push-Location (Join-Path $stage.Root 'Include')
    try{& $makensis '/NOCD' '/NOCONFIG' ('/DCANDIDATE_OUTPUT='+$installer) ('/DCANDIDATE_INCLUDE='+$includePath) ('/DCANDIDATE_MANIFEST_SHA256='+$manifestHash) $nsisSource;if($LASTEXITCODE -ne 0){throw 'Guarded candidate makensis failed.'}}
    finally{Pop-Location;[Environment]::SetEnvironmentVariable('NSISDIR',$saved,'Process')}
    $interval=Complete-RimePimeMonitoredNsisStage $stage
    $installerLease=Open-BuildFile $installer $null
    $listing=Invoke-RimePimePostbuildSevenZip -SevenZipLease $seven -SevenZipLibraryLease $sevenLib -Arguments @('l','-slt','-sccUTF-8','--',$installer) -Operation 'candidate listing'
    [IO.File]::WriteAllText((Join-Path $out 'archive-listing.txt'),$listing.text,[Text.UTF8Encoding]::new($false))
    $parsed=Read-RimePimePostbuildSevenZipListing -Text $listing.text -Kind installer
    if($parsed.physical_size -ne $installerLease.Record.bytes){throw 'Static archive physical size mismatch.'}
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $archiveRows){$expected.Add(('$PLUGINSDIR/bundle/'+$row.path),$row)}
    $system=@($toolchain.Document.nsis.support | Where-Object archive_path -CEQ '$PLUGINSDIR/System.dll')[0];$expected.Add('$PLUGINSDIR/System.dll',$system)
    if($parsed.entries.Count -ne $expected.Count){throw 'Static archive membership count differs from exact bundle and System plugin.'}
    $verified=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $parsed.entries){if(-not $expected.ContainsKey($entry.path) -or -not $seen.Add($entry.path) -or ($null -ne $entry.bytes -and $entry.bytes -ne $expected[$entry.path].bytes)){throw ('Unlisted, duplicate or changed static archive member: '+$entry.path)};$v=Invoke-RimePimePostbuildSevenZipRawEntry -SevenZipLease $seven -SevenZipLibraryLease $sevenLib -ArchiveLease $installerLease -ArchivePath $entry.path -ExpectedRecord $expected[$entry.path] -Operation 'candidate raw payload';$verified.Add([pscustomobject][ordered]@{path=$entry.path;bytes=$v.bytes;sha256=$v.sha256})}
    $staticPath=Join-Path $out 'static-payload.json';$staticHash=Write-BuildJson @($verified|Sort-Object path -CaseSensitive) $staticPath
    foreach($l in $leases){$null=Assert-RimePimePostbuildReadLease $l}
    $receipt=[pscustomobject][ordered]@{schema_version='yime-rime-pime-executable-build-receipt-v1';product='rime-pime';product_version=$ProductVersion;installer=[ordered]@{sha256=$installerLease.Record.sha256;bytes=$installerLease.Record.bytes};manifest_sha256=$manifestHash;source_inventory_sha256=$ExpectedSourceInventorySha256;build_sources=$buildSources;compiler_interval=$interval;static_payload=[ordered]@{verified=$true;member_count=$verified.Count;tree_sha256=$staticHash};makensis_sha256=(Get-BuildHash $makensis);nsis_toolchain_lock_sha256=$toolchain.Digest;signing_complete=$false;installed_acceptance_passed=$false;public_release_admitted=$false}
    $receiptPath=Join-Path $out 'executable-build-receipt.json';$receiptHash=Write-BuildJson $receipt $receiptPath
    Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-receipt.psm1') -Scope Local
    $null=Read-RimePimeExecutableReceipt -ReceiptPath $receiptPath -ExpectedReceiptSha256 $receiptHash -InstallerPath $installer -ExpectedInstallerSha256 $installerLease.Record.sha256 -ExpectedManifestSha256 $manifestHash
    [pscustomobject]@{installer_path=$installer;installer_sha256=$installerLease.Record.sha256;receipt_path=$receiptPath;receipt_sha256=$receiptHash;manifest_sha256=$manifestHash;source_inventory_sha256=$ExpectedSourceInventorySha256;source_build_candidate_prepared=$true;execution_authorized=$false;installer_executed=$false;uninstaller_executed=$false;installed_acceptance_passed=$false;public_release_admitted=$false}
}finally{if($null -ne $bundleLease){Close-RimePimeExecutableCandidate $bundleLease};if($null -ne $stage){Close-RimePimeMonitoredNsisStage $stage};for($i=$leases.Count-1;$i -ge 0;$i--){$leases[$i].Stream.Dispose()}}
