[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-postbuild-extraction-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-postbuild-extraction-test-* root.'
}
if(-not(Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null
$modulePath=Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.psm1'
Import-Module -Name $modulePath -Force
Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action,[string]$Like='*'){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notlike $Like){throw "Unexpected rejection: $($_.Exception.Message)"};return}
    throw 'Unsafe post-build extraction fixture was accepted.'
}
function Get-TextDigest([string]$Text){
    $bytes=[Text.Encoding]::UTF8.GetBytes($Text);$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Copy-JsonValue($Value){
    return $Value|ConvertTo-Json -Depth 16 -Compress|ConvertFrom-Json
}
function New-PlanStageBindingFixture {
    $planDigest=('1'*64)-join '';$artifactDigest=('2'*64)-join ''
    return [pscustomobject]@{
        Package=[pscustomobject]@{Digest=$planDigest;Plan=[pscustomobject]@{artifacts=@(
            [pscustomobject][ordered]@{path='build/tool.exe';architecture='x86';size=[long]4;sha256=$artifactDigest}
        )}}
        Manifest=[pscustomobject]@{package_plan_sha256=$planDigest;files=@(
            [pscustomobject][ordered]@{source_path='build/tool.exe';architecture='x86';bytes=[long]4;sha256=$artifactDigest}
        )}
    }
}
function New-ContentRow([string]$Path,[string]$Text,[string]$Category){
    return [pscustomobject][ordered]@{
        path=$Path;bytes=[long][Text.Encoding]::UTF8.GetByteCount($Text);sha256=Get-TextDigest $Text
        category=$Category;text=$Text
    }
}
function New-PostbuildFixtureContract {
    $content=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $payloadA=New-ContentRow 'alpha.txt' 'alpha' 'installed-payload';$content.Add($payloadA.path,$payloadA.text)
    $payloadB=New-ContentRow 'go-backend/tool.exe' 'tool' 'installed-payload';$content.Add($payloadB.path,$payloadB.text)
    $bootA=New-ContentRow '$PLUGINSDIR/helper.ps1' 'helper' 'product-bootstrap';$content.Add($bootA.path,$bootA.text)
    $bootB=New-ContentRow '$PLUGINSDIR/status.exe' 'status' 'product-bootstrap';$content.Add($bootB.path,$bootB.text)
    $manifest=[pscustomobject][ordered]@{files=@(
        [pscustomobject][ordered]@{stage_scope='payload';path='alpha.txt';bytes=$payloadA.bytes;sha256=$payloadA.sha256},
        [pscustomobject][ordered]@{stage_scope='payload';path='go-backend/tool.exe';bytes=$payloadB.bytes;sha256=$payloadB.sha256},
        [pscustomobject][ordered]@{stage_scope='bootstrap';path='helper.ps1';bytes=$bootA.bytes;sha256=$bootA.sha256},
        [pscustomobject][ordered]@{stage_scope='bootstrap';path='status.exe';bytes=$bootB.bytes;sha256=$bootB.sha256}
    )}
    $support=[Collections.Generic.List[object]]::new()
    foreach($name in @('modern-wizard.bmp','LangDLL.dll','nsDialogs.dll','nsExec.dll','System.dll')){
        $text='nsis:'+$name;$path='$PLUGINSDIR/'+$name;$row=New-ContentRow $path $text 'nsis-support'
        $content.Add($path,$text)
        $support.Add([pscustomobject][ordered]@{
            archive_path=$path;origin_path='fixture/'+$name;bytes=$row.bytes;sha256=$row.sha256;file_id='fixture:'+ $name
        })
    }
    $content.Add('Uninstall.exe','synthetic uninstaller bytes')
    $top=@(Get-RimePimePostbuildExpectedArchiveRows $manifest @($support) installer)
    $nested=@(Get-RimePimePostbuildExpectedArchiveRows $manifest @($support) uninstaller)
    return [pscustomobject]@{Manifest=$manifest;Support=@($support);Top=$top;Nested=$nested;Content=$content}
}
function New-ListingText([string]$Kind,[object[]]$Rows,[string]$BlankPath,[switch]$BlankFirst,[string]$SubtypeOverride){
    $subtype=if($SubtypeOverride){$SubtypeOverride}elseif($Kind -ceq 'installer'){'NSIS-3 Unicode'}else{'NSIS-3 Unicode (Uninstall)'}
    $ordered=@($Rows|Where-Object{[string]$_.path -cne $BlankPath})
    $blank=@($Rows|Where-Object{[string]$_.path -ceq $BlankPath})
    if($blank.Count -ne 1){throw 'Synthetic listing requires one blank-size path.'}
    if($BlankFirst){$ordered=@($blank)+@($ordered)}else{$ordered=@($ordered)+@($blank)}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('7-Zip synthetic');$lines.Add('Path = fixture.exe');$lines.Add('Type = Nsis')
    $lines.Add('Physical Size = 100000');$lines.Add('SubType = '+$subtype);$lines.Add('----------')
    foreach($row in $ordered){
        $lines.Add('Path = '+([string]$row.path).Replace('/','\'))
        $lines.Add('Size = '+$(if([string]$row.path -ceq $BlankPath){''}else{[string]$row.bytes}))
        $lines.Add('Method = LZMA:24');$lines.Add('')
    }
    return [string]::Join("`n",@($lines))
}
function Write-FixtureTree([string]$Root,[object[]]$Rows,$Content){
    New-Item -ItemType Directory -Path $Root|Out-Null
    foreach($row in $Rows){
        $path=Join-Path $Root ([string]$row.path).Replace('/','\')
        $parent=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        [IO.File]::WriteAllText($path,[string]$Content[[string]$row.path],(New-Object Text.UTF8Encoding($false)))
    }
}

$fixture=New-PostbuildFixtureContract
Check 'repository-toolchain-lock-is-code-pinned-and-current' {
    $toolchain=Read-RimePimePostbuildToolchainLockDocument
    Assert-True ([string]$toolchain.Digest -ceq '01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45') 'Toolchain lock digest drifted.'
    Assert-True (@($toolchain.Document.nsis.support).Count -eq 5 -and
        [int]$toolchain.Document.nsis.compiler_input_closure.file_count -eq 303 -and
        [int]$toolchain.Document.nsis.compiler_input_closure.directory_count -eq 17 -and
        [long]$toolchain.Document.seven_zip.bytes -eq 576000 -and
        [long]$toolchain.Document.seven_zip.library.bytes -eq 1906688) 'Toolchain lock exact set is wrong.'
}
Check 'toolchain-lock-fake-seven-zip-hash-is-rejected' {
    $toolchain=Read-RimePimePostbuildToolchainLockDocument;$fake=Copy-JsonValue $toolchain.Document
    $fake.seven_zip.sha256=('0'*64)-join ''
    Assert-Rejected {Test-RimePimePostbuildToolchainLockDocument $fake} '*code-pinned identity*'
}
Check 'toolchain-lock-swapped-nsis-root-is-rejected' {
    $toolchain=Read-RimePimePostbuildToolchainLockDocument;$fake=Copy-JsonValue $toolchain.Document
    $fake.nsis.root='C:/fake/NSIS'
    Assert-Rejected {Test-RimePimePostbuildToolchainLockDocument $fake} '*code-pinned identity*'
}
Check 'toolchain-lock-fake-seven-zip-library-hash-is-rejected' {
    $toolchain=Read-RimePimePostbuildToolchainLockDocument;$fake=Copy-JsonValue $toolchain.Document
    $fake.seven_zip.library.sha256=('0'*64)-join ''
    Assert-Rejected {Test-RimePimePostbuildToolchainLockDocument $fake} '*code-pinned identity*'
}
Check 'seven-zip-info-binds-one-pinned-parser-library' {
    $toolchain=Read-RimePimePostbuildToolchainLockDocument
    $path=([string]$toolchain.Document.seven_zip.library.path).Replace('/','\')
    $version=[string]$toolchain.Document.seven_zip.library.file_version
    $text="7-Zip synthetic`n`nLibs:`n 0 : $version : $path`n`nFormats:`n synthetic"
    $binding=Test-RimePimePostbuildSevenZipLibraryBinding $text $path $version
    Assert-True ($binding.binding_verified -and [string]$binding.path -ceq $path) 'Pinned parser library binding was not accepted.'
    $wrong=$text.Replace($path,'C:\isolated\swapped\7z.dll')
    Assert-Rejected {Test-RimePimePostbuildSevenZipLibraryBinding $wrong $path $version} '*differs from the repository-pinned binding*'
}
Check 'postbuild-api-does-not-accept-tool-path-and-self-approved-digest' {
    $invoke=@((Get-Command Invoke-RimePimePostbuildExtraction).Parameters.Keys)
    $seven=@((Get-Command Invoke-RimePimePostbuildSevenZip).Parameters.Keys)
    $raw=@((Get-Command Invoke-RimePimePostbuildSevenZipRawEntry).Parameters.Keys)
    foreach($name in @('SevenZipPath','ExpectedSevenZipDigest','NsisRoot','ExpectedMakensisDigest')){
        Assert-True ($invoke -cnotcontains $name) "Post-build API still accepts $name."
    }
    Assert-True ($seven -ccontains 'SevenZipLease' -and $seven -ccontains 'SevenZipLibraryLease' -and
        $seven -cnotcontains 'SevenZipPath') '7-Zip helper is not executable-and-library-lease-only.'
    Assert-True ($raw -ccontains 'SevenZipLease' -and $raw -ccontains 'SevenZipLibraryLease' -and $raw -ccontains 'ArchiveLease' -and
        $raw -cnotcontains 'SevenZipPath' -and $raw -cnotcontains 'ExpectedSevenZipDigest') 'Raw-entry helper is not lease-only.'
}
Check 'evidence-claims-per-entry-origin-but-keeps-final-delivery-false' {
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.ps1'))
    Assert-True ($source -cmatch 'installer_archive_per_entry_raw_stdout_verified=\$true' -and
        $source -cmatch 'nested_uninstaller_archive_per_entry_raw_stdout_verified=\$true' -and
        $source -cmatch 'archive_content_origin_proven=\$true' -and
        $source -cmatch 'seven_zip_parser_library_read_lease_held_for_all_calls=\$true' -and
        $source -cmatch 'result_json_and_sidecar_create_new_digest_bound_leases_held_through_runner_pass=\$true' -and
        $source -cmatch 'seven_zip_never_received_snapshot_output_paths=\$true' -and
        $source -cmatch 'nsis_distribution_inputs_exact_and_read_leased_during_postbuild=\$true' -and
        $source -cmatch 'nsis_known_input_file_replacement_closure=\$true' -and
        $source -cmatch 'active_same_sid_transient_tree_membership_interference_excluded=\$false' -and
        $source -cmatch 'nsis_compiler_input_leases_held_during_makensis=\$false' -and
        $source -cmatch 'nsis_non_os_compiler_input_closure=\$false' -and
        $source -cmatch 'full_nsis_toolchain_input_closure=\$false' -and
        $source -cmatch 'generated_uninstaller_trusted=\$false' -and
        $source -cmatch 'final_payload_closure=\$false;delivery_admitted=\$false') 'Post-build evidence boundary fields are incomplete.'
    Assert-True ($source -cnotmatch '\bstatic_archive_exact\b|\barchive_owned_files_match_stage\b|\bstable_extracted_snapshot_files_match_stage\b') 'Post-build evidence still contains an overbroad exactness claim.'
    Assert-True ($source -cnotmatch 'active_same_sid_extraction_interference_excluded=') 'Post-build evidence contains an unbounded same-SID interference claim.'
    Assert-True ($source -cnotmatch [regex]::Escape("Invoke-RimePimePostbuildSevenZip `$sevenZipLease `$sevenZipLibraryLease @('x'")) 'Post-build verifier still sends a snapshot output path to 7-Zip.'
    Assert-True ($source -cnotmatch 'Write-RimePimeStageSealedJson \$result') 'Post-build verifier still uses the replaceable shared result writer.'
}
Check 'sealed-result-create-new-memory-digest-and-leases-are-stable' {
    $root=Join-Path $output 'sealed-result-positive';New-Item -ItemType Directory -Path $root|Out-Null
    $path=Join-Path $root 'result.json';$value=[pscustomobject][ordered]@{schema='synthetic';passed=$true}
    $seal=Write-RimePimePostbuildSealedJson $value $path
    try{
        Assert-True ((Get-RimePimePostbuildSha256Text ((ConvertTo-RimePimeStageCanonicalJson $value)+"`n")) -ceq $seal.Digest) 'Sealed result digest is not from canonical in-memory bytes.'
        $replacement=Join-Path $root 'replacement.json';$backup=Join-Path $root 'backup.json'
        [IO.File]::WriteAllText($replacement,'attacker')
        $blocked=$false
        try{[IO.File]::Replace($replacement,$seal.Path,$backup,$true)}catch{$blocked=$true}
        Assert-True $blocked 'Replacement unexpectedly swapped the leased sealed result.'
        $writeBlocked=$false;$deleteBlocked=$false
        try{[IO.File]::WriteAllText($seal.Path,'attacker')}catch{$writeBlocked=$true}
        try{[IO.File]::Delete($seal.Sidecar)}catch{$deleteBlocked=$true}
        Assert-True ($writeBlocked -and $deleteBlocked) 'Write or delete unexpectedly changed the leased result pair.'
        $null=Assert-RimePimePostbuildReadLease $seal.JsonLease
        $null=Assert-RimePimePostbuildReadLease $seal.SidecarLease
    }finally{$seal.SidecarLease.Stream.Dispose();$seal.JsonLease.Stream.Dispose()}
}
Check 'precreated-hardlink-result-is-rejected-with-sentinel-unchanged' {
    $root=Join-Path $output 'sealed-result-hardlink';New-Item -ItemType Directory -Path $root|Out-Null
    $sentinel=Join-Path $root 'sentinel.txt';$path=Join-Path $root 'result.json'
    [IO.File]::WriteAllText($sentinel,'sentinel')
    New-Item -ItemType HardLink -Path $path -Target $sentinel|Out-Null
    Assert-Rejected {Write-RimePimePostbuildSealedJson ([pscustomobject]@{passed=$true}) $path} '*already exists*'
    Assert-True ([IO.File]::ReadAllText($sentinel) -ceq 'sentinel') 'Precreated result hardlink changed its external sentinel.'
}
Check 'precreated-hardlink-capture-is-rejected-with-sentinel-unchanged' {
    $root=Join-Path $output 'capture-hardlink';New-Item -ItemType Directory -Path $root|Out-Null
    $sentinel=Join-Path $output 'capture-hardlink-sentinel.txt';$path=Join-Path $root 'file.bin'
    [IO.File]::WriteAllText($sentinel,'sentinel')
    New-Item -ItemType HardLink -Path $path -Target $sentinel|Out-Null
    Assert-Rejected {Open-RimePimePostbuildCreateNewCaptureStream $path} '*already exists*'
    Assert-True ([IO.File]::ReadAllText($sentinel) -ceq 'sentinel') 'Precreated capture hardlink changed its external sentinel.'
}
Check 'precreated-junction-extraction-directory-is-rejected-with-sentinel-unchanged' {
    $root=Join-Path $output 'capture-junction-root';$outside=Join-Path $output 'capture-junction-outside'
    New-Item -ItemType Directory -Path $root,$outside|Out-Null
    $sentinel=Join-Path $outside 'sentinel.txt';[IO.File]::WriteAllText($sentinel,'sentinel')
    New-Item -ItemType Junction -Path (Join-Path $root 'child') -Target $outside|Out-Null
    $rows=@([pscustomobject]@{path='child/file.bin'})
    Assert-Rejected {Open-RimePimePostbuildExpectedDirectoryLeases $root $rows 'synthetic junction injection'} '*reparse*'
    Assert-True ([IO.File]::ReadAllText($sentinel) -ceq 'sentinel') 'Rejected extraction junction changed its external sentinel.'
}
Check 'runner-explicitly-binds-real-package-to-stage-before-extraction' {
    $runner=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run-rime-pime-postbuild-extraction.ps1'))
    Assert-True ($runner -cmatch 'Assert-RimePimePackagePlanStageBindings -Package \$package -ContentManifest \$content\.Manifest') 'Runner lacks the explicit real-Package stage binding call.'
    $preImportGuard=$runner.IndexOf('Alternate data stream on post-build execution logic rejected before import',[StringComparison]::Ordinal)
    $firstImport=$runner.IndexOf('Import-Module -Name $postbuildModule',[StringComparison]::Ordinal)
    Assert-True ($preImportGuard -ge 0 -and $firstImport -gt $preImportGuard) 'Execution-logic reparse/hardlink/ADS guards do not precede module import.'
    Assert-True ($runner -cmatch '-ExecutionLogicLeases @\(\$logicLeases\)') 'Runner does not carry execution-logic leases through the verifier.'
    Assert-True ($runner -cmatch "tools\\verify-pe-architectures\.ps1") 'Runner does not lease the PE verifier executed by package-plan verification.'
    Assert-True ($runner -cmatch "rime-pime-nsis-toolchain-closure\.psm1" -and
        $runner -cmatch "rime-pime-nsis-toolchain-closure\.ps1") 'Runner does not lease the NSIS toolchain closure implementation before import.'
    foreach($name in @('ExpectedSevenZipDigest','ExpectedMakensisDigest')){
        Assert-True ($runner -cnotmatch ('\$'+$name+'\b')) "Runner still accepts $name."
    }
}
Check 'plan-stage-artifact-binding-is-accepted' {
    $bound=New-PlanStageBindingFixture
    $result=Assert-RimePimePackagePlanStageBindings -Package $bound.Package -ContentManifest $bound.Manifest
    Assert-True ($result.passed -and $result.package_plan_artifact_count -eq 1 -and $result.matching_stage_binding_count -eq 1) 'Plan-stage binding count is wrong.'
}
Check 'same-plan-digest-but-artifact-size-mismatch-is-rejected' {
    $bound=New-PlanStageBindingFixture;$bound.Manifest.files[0].bytes=[long]5
    Assert-Rejected {Assert-RimePimePackagePlanStageBindings -Package $bound.Package -ContentManifest $bound.Manifest} '*differs from its sealed package-plan artifact*'
}
Check 'same-plan-digest-but-artifact-hash-mismatch-is-rejected' {
    $bound=New-PlanStageBindingFixture;$bound.Manifest.files[0].sha256=('3'*64)-join ''
    Assert-Rejected {Assert-RimePimePackagePlanStageBindings -Package $bound.Package -ContentManifest $bound.Manifest} '*differs from its sealed package-plan artifact*'
}
Check 'same-plan-digest-but-artifact-architecture-mismatch-is-rejected' {
    $bound=New-PlanStageBindingFixture;$bound.Manifest.files[0].architecture='x64'
    Assert-Rejected {Assert-RimePimePackagePlanStageBindings -Package $bound.Package -ContentManifest $bound.Manifest} '*differs from its sealed package-plan artifact*'
}
Check 'all-four-raw-byte-bindings-are-required' {
    $digests=@((('a'*64)-join ''),(('b'*64)-join ''),(('c'*64)-join ''),(('d'*64)-join ''))
    $bytes=[Text.Encoding]::Unicode.GetBytes('prefix'+[string]::Join('|',$digests)+'suffix')
    $result=Test-RimePimePostbuildRawByteBindings $bytes $digests[0] $digests[1] $digests[2] $digests[3]
    Assert-True ($result.payload_nsh_raw_byte_binding -and $result.package_plan_raw_byte_binding) 'Four-way raw-byte result is incomplete.'
    Assert-Rejected {Test-RimePimePostbuildRawByteBindings $bytes $digests[0] $digests[1] $digests[2] (('e'*64)-join '')} '*payload_nsh raw-byte binding*'
}
Check 'stable-file-read-lease-is-accepted' {
    $path=Join-Path $output 'lease-stable.bin';[IO.File]::WriteAllText($path,'lease-stable')
    $lease=Open-RimePimePostbuildReadLease $path $null 'synthetic stable file'
    try{$record=Assert-RimePimePostbuildReadLease $lease;Assert-True ([long]$record.bytes -gt 0) 'Stable lease has no record.'}
    finally{$lease.Stream.Dispose()}
}
Check 'fake-expected-record-is-rejected-after-lease-acquisition' {
    $path=Join-Path $output 'lease-fake-record.bin';[IO.File]::WriteAllText($path,'lease-real')
    $fake=[pscustomobject]@{bytes=[long]10;sha256=(('0'*64)-join '')}
    Assert-Rejected {Open-RimePimePostbuildReadLease $path $fake 'synthetic fake record'} '*sealed expected file record*'
}
Check 'leased-file-write-is-blocked' {
    $path=Join-Path $output 'lease-write.bin';[IO.File]::WriteAllText($path,'before')
    $lease=Open-RimePimePostbuildReadLease $path $null 'synthetic write-blocked file'
    try{
        $blocked=$false
        try{[IO.File]::WriteAllText($path,'after')}catch{$blocked=$true}
        Assert-True $blocked 'Write unexpectedly replaced a read-leased file.'
        $null=Assert-RimePimePostbuildReadLease $lease
    }finally{$lease.Stream.Dispose()}
}
Check 'leased-file-swap-is-blocked' {
    $path=Join-Path $output 'lease-swap.bin';$replacement=Join-Path $output 'lease-swap-replacement.bin'
    $backup=Join-Path $output 'lease-swap-backup.bin'
    [IO.File]::WriteAllText($path,'original');[IO.File]::WriteAllText($replacement,'replacement')
    $lease=Open-RimePimePostbuildReadLease $path $null 'synthetic swap-blocked file'
    try{
        $blocked=$false
        try{[IO.File]::Replace($replacement,$path,$backup,$true)}catch{$blocked=$true}
        Assert-True $blocked 'Atomic swap unexpectedly replaced a read-leased file.'
        $null=Assert-RimePimePostbuildReadLease $lease
    }finally{$lease.Stream.Dispose()}
}
Check 'leased-seven-zip-parser-library-replacement-is-blocked' {
    $path=Join-Path $output 'seven-zip-parser-library.dll';$replacement=Join-Path $output 'seven-zip-parser-library-swapped.dll'
    $backup=Join-Path $output 'seven-zip-parser-library-backup.dll'
    [IO.File]::WriteAllText($path,'pinned parser');[IO.File]::WriteAllText($replacement,'swapped parser')
    $lease=Open-RimePimePostbuildReadLease $path $null 'synthetic 7-Zip parser library'
    try{
        $blocked=$false
        try{[IO.File]::Replace($replacement,$path,$backup,$true)}catch{$blocked=$true}
        Assert-True $blocked 'Atomic swap unexpectedly replaced the leased 7-Zip parser library.'
        $null=Assert-RimePimePostbuildReadLease $lease
    }finally{$lease.Stream.Dispose()}
}
Check 'forged-lease-record-is-rejected' {
    $path=Join-Path $output 'lease-forged.bin';[IO.File]::WriteAllText($path,'lease-forged')
    $lease=Open-RimePimePostbuildReadLease $path $null 'synthetic forged lease'
    try{$lease.Record.sha256=('f'*64)-join '';Assert-Rejected {Assert-RimePimePostbuildReadLease $lease} '*changed while its read lease was held*'}
    finally{$lease.Stream.Dispose()}
}
Check 'leased-extracted-child-write-is-blocked' {
    $root=Join-Path $output 'extracted-child-write';$directory=Join-Path $root 'child'
    New-Item -ItemType Directory -Path $directory -Force|Out-Null
    $path=Join-Path $directory 'file.bin';[IO.File]::WriteAllText($path,'original')
    $record=Get-YimePimePayloadFileRecord $path
    $row=[pscustomobject]@{path='child/file.bin';bytes=$record.bytes;sha256=$record.sha256;category='installed-payload'}
    $leases=@(Open-RimePimePostbuildExtractedFileLeases $root @($row) 'synthetic extracted child')
    try{
        $blocked=$false
        try{[IO.File]::WriteAllText($path,'changed')}catch{$blocked=$true}
        Assert-True $blocked 'Write unexpectedly changed a leased extracted child file.'
        $null=Test-RimePimePostbuildExtractedFileLeases $leases 1
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}
Check 'leased-extracted-child-delete-is-blocked' {
    $root=Join-Path $output 'extracted-child-delete';New-Item -ItemType Directory -Path $root|Out-Null
    $path=Join-Path $root 'file.bin';[IO.File]::WriteAllText($path,'original')
    $record=Get-YimePimePayloadFileRecord $path
    $row=[pscustomobject]@{path='file.bin';bytes=$record.bytes;sha256=$record.sha256;category='installed-payload'}
    $leases=@(Open-RimePimePostbuildExtractedFileLeases $root @($row) 'synthetic extracted child')
    try{
        $blocked=$false
        try{[IO.File]::Delete($path)}catch{$blocked=$true}
        Assert-True ($blocked -and (Test-Path -LiteralPath $path -PathType Leaf)) 'Delete unexpectedly removed a leased extracted child file.'
        $null=Test-RimePimePostbuildExtractedFileLeases $leases 1
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}
Check 'leased-extracted-child-replacement-is-blocked' {
    $root=Join-Path $output 'extracted-child-replacement';New-Item -ItemType Directory -Path $root|Out-Null
    $path=Join-Path $root 'file.bin';$replacement=Join-Path $output 'extracted-child-replacement-source.bin'
    $backup=Join-Path $output 'extracted-child-replacement-backup.bin'
    [IO.File]::WriteAllText($path,'original');[IO.File]::WriteAllText($replacement,'replacement')
    $record=Get-YimePimePayloadFileRecord $path
    $row=[pscustomobject]@{path='file.bin';bytes=$record.bytes;sha256=$record.sha256;category='installed-payload'}
    $leases=@(Open-RimePimePostbuildExtractedFileLeases $root @($row) 'synthetic extracted child')
    try{
        $blocked=$false
        try{[IO.File]::Replace($replacement,$path,$backup,$true)}catch{$blocked=$true}
        Assert-True $blocked 'Replacement unexpectedly swapped a leased extracted child file.'
        $null=Test-RimePimePostbuildExtractedFileLeases $leases 1
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}
Check 'incomplete-extracted-file-lease-set-is-rejected' {
    Assert-Rejected {Test-RimePimePostbuildExtractedFileLeases @() 1} '*lease count mismatch*'
}
Check 'incomplete-execution-logic-lease-set-is-rejected' {
    Assert-Rejected {Test-RimePimePostbuildExecutionLogicLeases @()} '*lease set is incomplete*'
}
Check 'preloaded-weak-directory-lease-type-is-rejected' {
    $child=Join-Path $output 'weak-directory-type-negative.ps1'
    $escapedModule=$modulePath.Replace("'","''")
    $lines=@(
        '$ErrorActionPreference=''Stop''',
        'Add-Type -TypeDefinition @''',
        'namespace YimePime.Postbuild { public static class DirectoryLeasesV1 { public static void Dummy() {} } }',
        '''@',
        "Import-Module -Name '$escapedModule' -Force",
        'try { Initialize-RimePimePostbuildDirectoryLeaseType; exit 91 } catch {',
        '  if($_.Exception.Message -like ''*preloaded outside this verified module instance*''){ exit 0 }',
        '  exit 92',
        '}'
    )
    [IO.File]::WriteAllText($child,[string]::Join("`r`n",$lines),(New-Object Text.UTF8Encoding($false)))
    $hostPath=(Get-Process -Id $PID).Path
    & $hostPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $child
    Assert-True ($LASTEXITCODE -eq 0) "Weak directory lease type child rejected with exit $LASTEXITCODE."
}
Check 'stable-extraction-directory-lease-is-accepted' {
    $path=Join-Path $output 'directory-lease-stable';New-Item -ItemType Directory -Path $path|Out-Null
    $lease=Open-RimePimePostbuildDirectoryLease $path 'synthetic stable directory'
    try{Assert-True (Assert-RimePimePostbuildDirectoryLease $lease) 'Stable directory lease was rejected.'}
    finally{$lease.Native.Dispose()}
}
Check 'leased-expected-child-directory-swap-is-blocked' {
    $path=Join-Path $output 'directory-lease-swap';$child=Join-Path $path 'expected-child'
    $moved=Join-Path $path 'moved-child';New-Item -ItemType Directory -Path $path|Out-Null
    $rootLease=Open-RimePimePostbuildDirectoryLease $path 'synthetic extraction root'
    $rows=@([pscustomobject]@{path='expected-child/file.txt'})
    $childLeases=@(Open-RimePimePostbuildExpectedDirectoryLeases $path $rows 'synthetic expected path')
    try{
        Assert-True ($childLeases.Count -eq 1 -and (Test-Path -LiteralPath $child -PathType Container)) 'Expected child directory lease was not created.'
        $blocked=$false
        try{[IO.Directory]::Move($child,$moved)}catch{$blocked=$true}
        Assert-True $blocked 'Directory rename unexpectedly replaced a leased expected child path.'
        $null=Test-RimePimePostbuildDirectoryLeases $childLeases
    }finally{
        foreach($lease in $childLeases){$lease.Native.Dispose()}
        $rootLease.Native.Dispose()
    }
}
Check 'forged-extraction-directory-identity-is-rejected' {
    $path=Join-Path $output 'directory-lease-forged';New-Item -ItemType Directory -Path $path|Out-Null
    $lease=Open-RimePimePostbuildDirectoryLease $path 'synthetic forged directory'
    try{$lease.FileId='00000000:0000000000000000';Assert-Rejected {Assert-RimePimePostbuildDirectoryLease $lease} '*identity changed while leased*'}
    finally{$lease.Native.Dispose()}
}
Check 'installer-listing-exact-multiset-is-accepted' {
    $text=New-ListingText installer $fixture.Top 'Uninstall.exe'
    $listing=Read-RimePimePostbuildSevenZipListing $text installer
    $result=Test-RimePimePostbuildArchiveListing $listing $fixture.Top
    Assert-True ($result.passed -and $result.entry_count -eq 10 -and
        $result.category_counts.'installed-payload' -eq 2 -and
        $result.category_counts.'product-bootstrap' -eq 2 -and
        $result.category_counts.'nsis-support' -eq 5 -and
        $result.category_counts.'generated-uninstaller' -eq 1) 'Installer listing partition is wrong.'
}
Check 'nested-uninstaller-listing-exact-multiset-is-accepted' {
    $blank=[string]$fixture.Nested[-1].path
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText uninstaller $fixture.Nested $blank) uninstaller
    $result=Test-RimePimePostbuildArchiveListing $listing $fixture.Nested
    Assert-True ($result.entry_count -eq 4 -and $result.category_counts.'product-bootstrap' -eq 2 -and
        $result.category_counts.'nsis-support' -eq 2) 'Nested listing partition is wrong.'
}
Check 'wrong-nsis-subtype-is-rejected' {
    Assert-Rejected {Read-RimePimePostbuildSevenZipListing `
        (New-ListingText installer $fixture.Top 'Uninstall.exe' -SubtypeOverride 'NSIS-2') installer} '*type or subtype*'
}
Check 'duplicate-archive-entry-is-rejected-before-extraction' {
    $rows=@($fixture.Top)+@($fixture.Top[0])
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer $rows 'Uninstall.exe') installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*Duplicate or case-folded*'
}
Check 'case-folded-archive-entry-is-rejected-before-extraction' {
    $rows=@($fixture.Top|ForEach-Object{$_})
    $copy=[pscustomobject][ordered]@{path='ALPHA.txt';bytes=$rows[0].bytes;sha256=$rows[0].sha256;category=$rows[0].category}
    $rows=@($rows)+@($copy)
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer $rows 'Uninstall.exe') installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*Duplicate or case-folded*'
}
Check 'extra-archive-entry-is-rejected-before-extraction' {
    $extra=New-ContentRow 'foreign.dat' 'foreign' 'installed-payload'
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer (@($fixture.Top)+@($extra)) 'Uninstall.exe') installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*count mismatch*'
}
Check 'missing-archive-entry-is-rejected-before-extraction' {
    $rows=@($fixture.Top|Where-Object{[string]$_.path -cne 'alpha.txt'})
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer $rows 'Uninstall.exe') installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*count mismatch*'
}
Check 'archive-listing-size-change-is-rejected' {
    $rows=@($fixture.Top|ForEach-Object{[pscustomobject][ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256;category=$_.category}})
    $rows[0].bytes=[long]$rows[0].bytes+1
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer $rows 'Uninstall.exe') installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*size mismatch*'
}
Check 'nonfinal-blank-size-is-rejected' {
    $listing=Read-RimePimePostbuildSevenZipListing (New-ListingText installer $fixture.Top 'Uninstall.exe' -BlankFirst) installer
    Assert-Rejected {Test-RimePimePostbuildArchiveListing $listing $fixture.Top} '*final NSIS solid member*'
}
Check 'noncanonical-archive-path-is-rejected' {
    $text=(New-ListingText installer $fixture.Top 'Uninstall.exe').Replace('Path = alpha.txt','Path = ..\alpha.txt')
    Assert-Rejected {Read-RimePimePostbuildSevenZipListing $text installer} '*Ambiguous archive path*'
}
Check 'installer-extracted-tree-exact-hashes-are-accepted' {
    $root=Join-Path $output 'tree-positive';Write-FixtureTree $root $fixture.Top $fixture.Content
    $snapshot=Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top
    Assert-True ($snapshot.file_count -eq 10 -and $snapshot.directory_count -eq 2) 'Extracted snapshot count is wrong.'
}
Check 'nested-extracted-tree-exact-hashes-are-accepted' {
    $root=Join-Path $output 'nested-positive';Write-FixtureTree $root $fixture.Nested $fixture.Content
    $snapshot=Get-RimePimePostbuildExtractedSnapshot $root $fixture.Nested
    Assert-True ($snapshot.file_count -eq 4 -and $snapshot.directory_count -eq 1) 'Nested snapshot count is wrong.'
}
Check 'changed-extracted-file-is-rejected' {
    $root=Join-Path $output 'tree-changed';Write-FixtureTree $root $fixture.Top $fixture.Content
    [IO.File]::AppendAllText((Join-Path $root 'alpha.txt'),'changed')
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*content mismatch*'
}
Check 'extra-extracted-file-is-rejected' {
    $root=Join-Path $output 'tree-extra';Write-FixtureTree $root $fixture.Top $fixture.Content
    [IO.File]::WriteAllText((Join-Path $root 'extra.txt'),'extra')
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*Unlisted*'
}
Check 'missing-extracted-file-is-rejected' {
    $root=Join-Path $output 'tree-missing';Write-FixtureTree $root $fixture.Top $fixture.Content
    Remove-Item -LiteralPath (Join-Path $root 'alpha.txt')
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*missing files*'
}
Check 'extra-empty-directory-is-rejected' {
    $root=Join-Path $output 'tree-empty-dir';Write-FixtureTree $root $fixture.Top $fixture.Content
    New-Item -ItemType Directory -Path (Join-Path $root 'empty')|Out-Null
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*Unlisted*'
}
Check 'hard-linked-extracted-file-is-rejected' {
    $root=Join-Path $output 'tree-hardlink';Write-FixtureTree $root $fixture.Top $fixture.Content
    New-Item -ItemType HardLink -Path (Join-Path $output 'outside-hardlink.txt') -Target (Join-Path $root 'alpha.txt')|Out-Null
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*Hard-linked*'
}
Check 'alternate-data-stream-on-extracted-file-is-rejected' {
    $root=Join-Path $output 'tree-ads';Write-FixtureTree $root $fixture.Top $fixture.Content
    Set-Content -LiteralPath ((Join-Path $root 'alpha.txt')+':hidden') -Value 'private' -Encoding UTF8
    Assert-Rejected {Get-RimePimePostbuildExtractedSnapshot $root $fixture.Top} '*Alternate data stream*'
}

$failed=@($checks|Where-Object{-not $_.passed})
$toolchainLockPath=Join-Path $PSScriptRoot 'rime-pime-postbuild-toolchain-lock.json'
$runnerPath=Join-Path $PSScriptRoot 'run-rime-pime-postbuild-extraction.ps1'
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-postbuild-extraction-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    test_level='isolated-filesystem-listing-lock-lease-and-stage-binding-contract-only';checks_count=$checks.Count
    passed=$failed.Count -eq 0;seven_zip_or_makensis_executed=$false
    powershell_child_process_executed_for_type_spoof_negative=$true
    actual_installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
    default_input_method_changed=$false;production_user_data_read_or_written=$false
    generated_uninstaller_trusted=$false;final_payload_closure=$false
    helper_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    module_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    runner_sha256=(Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    toolchain_lock_sha256=(Get-FileHash -LiteralPath $toolchainLockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();checks=@($checks)
}
$resultPath=Join-Path $output 'result.json'
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
if($failed.Count){foreach($failure in $failed){Write-Host "FAIL: $($failure.name): $($failure.error)"};throw "$($failed.Count) of $($checks.Count) post-build extraction checks failed."}
Write-Host "PASS: $($checks.Count) synthetic post-build extraction checks passed. Evidence: $resultPath"
