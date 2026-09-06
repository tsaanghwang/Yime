[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot,[switch]$SyntheticOnly)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd([char]92)
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-nsis-toolchain-closure-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-nsis-toolchain-closure-test-* root.'
}
if(-not(Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null
Import-Module (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force
. (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.ps1')

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action,[string]$Like='*'){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notlike $Like){throw "Unexpected rejection: $($_.Exception.Message)"};return}
    throw 'Unsafe NSIS toolchain fixture was accepted.'
}
function Get-FixtureTreeRecord([string]$Root){
    $relativeRoots=@('Bin','Contrib','Include','Plugins/x86-unicode','Stubs')
    $directories=[Collections.Generic.List[string]]::new();$files=[Collections.Generic.List[object]]::new()
    $rootRows=[Collections.Generic.List[object]]::new()
    foreach($relativeRoot in $relativeRoots){
        $full=Join-Path $Root $relativeRoot.Replace('/','\')
        $rootDirectories=@((Get-Item -LiteralPath $full -Force)) + @(Get-ChildItem -LiteralPath $full -Recurse -Force -Directory)
        $rootFiles=@(Get-ChildItem -LiteralPath $full -Recurse -Force -File)
        foreach($directory in $rootDirectories){$directories.Add($directory.FullName.Substring($Root.Length+1).Replace('\','/'))}
        foreach($file in $rootFiles){$files.Add([pscustomobject][ordered]@{
            path=$file.FullName.Substring($Root.Length+1).Replace('\','/');bytes=[long]$file.Length
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })}
        $rootRows.Add([pscustomobject][ordered]@{path=$relativeRoot;directory_count=$rootDirectories.Count;file_count=$rootFiles.Count})
    }
    $directoryArray=$directories.ToArray();[Array]::Sort($directoryArray,[StringComparer]::Ordinal)
    $fileArray=$files.ToArray();[Array]::Sort($fileArray,[Comparison[object]]{param($a,$b);[StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path)})
    $builder=[Text.StringBuilder]::new();foreach($path in $directoryArray){$null=$builder.Append("D`t$path`n")}
    foreach($row in $fileArray){$null=$builder.Append("F`t$($row.path)`t$($row.bytes)`t$($row.sha256)`n")}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
    $required=@($fileArray|ForEach-Object{[pscustomobject][ordered]@{class=$(if($_.path -ceq 'Bin/makensis.exe'){'compiler'}elseif($_.path -ceq 'Bin/zlib1.dll'){'compiler-runtime'}elseif($_.path.StartsWith('Plugins/')){'plugin-scan'}elseif($_.path.StartsWith('Stubs/')){'stub'}elseif($_.path.StartsWith('Contrib/')){'resource'}else{'include'});path=$_.path}})
    return [pscustomobject][ordered]@{
        scope='repository-pinned-nsis-distribution-non-os-v1'
        canonical_tree_algorithm='sha256-directory-then-file-tab-records-utf8-lf-v1';roots=@($rootRows)
        directory_count=$directoryArray.Count;file_count=$fileArray.Count;canonical_tree_bytes=$bytes.Length
        tree_sha256=Get-RimePimeNsisClosureSha256Bytes $bytes;required_inputs=$required
    }
}
function New-Fixture([string]$Name){
    $root=Join-Path $output $Name;New-Item -ItemType Directory -Path $root|Out-Null
    $rows=[ordered]@{
        'Bin/makensis.exe'='compiler';'Bin/zlib1.dll'='runtime';'Contrib/resource.bin'='resource'
        'Include/base.nsh'='include';'Plugins/x86-unicode/plugin.dll'='plugin';'Stubs/stub.bin'='stub'
    }
    foreach($entry in $rows.GetEnumerator()){
        $path=Join-Path $root $entry.Key.Replace('/','\');$parent=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        [IO.File]::WriteAllText($path,[string]$entry.Value,[Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject]@{Root=$root;Record=Get-FixtureTreeRecord $root}
}
function Assert-CoreActive($Closure){
    foreach($lease in @($Closure.FileLeases)){$null=Assert-RimePimeNsisClosureFileLease $lease}
    foreach($lease in @($Closure.DirectoryLeases)){$null=Assert-RimePimeNsisClosureDirectoryLease $lease}
    $snapshot=Get-RimePimeNsisCompilerInputTreeSnapshot $Closure.NsisRoot $ClosureRecordByRoot[$Closure.NsisRoot]
    Assert-True ([string]$snapshot.tree_sha256 -ceq [string]$Closure.TreeSha256) 'Fixture tree changed under active closure.'
}
$ClosureRecordByRoot=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)

Check 'repository-lock-v2-is-code-pinned-and-current' {
    $lock=Read-RimePimeNsisCompilerToolchainLockDocument
    Assert-True ([string]$lock.Digest -ceq '01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45') 'Toolchain lock digest drifted.'
    Assert-True ([int]$lock.Document.nsis.compiler_input_closure.file_count -eq 303) 'Pinned NSIS file count drifted.'
    $required=@($lock.Document.nsis.compiler_input_closure.required_inputs)
    $requiredPaths=@($required|ForEach-Object{[string]$_.path})
    Assert-True (@($required|Where-Object{[string]$_.class -ceq 'plugin-scan'}).Count -eq 16 -and
        $requiredPaths -ccontains 'Bin/makensis.exe' -and $requiredPaths -ccontains 'Bin/zlib1.dll' -and
        $requiredPaths -ccontains 'Stubs/lzma_solid-x86-unicode' -and $requiredPaths -ccontains 'Stubs/uninst' -and
        $requiredPaths -ccontains 'Include/MUI2.nsh' -and $requiredPaths -ccontains 'Contrib/Modern UI 2/MUI2.nsh' -and
        $requiredPaths -ccontains 'Contrib/UIs/modern.exe' -and
        $requiredPaths -ccontains 'Contrib/Language files/English.nlf' -and
        $requiredPaths -ccontains 'Contrib/Language files/SimpChinese.nlf' -and
        $requiredPaths -ccontains 'Contrib/Language files/TradChinese.nlf' -and
        $requiredPaths -ccontains 'Contrib/Graphics/Icons/orange-install.ico' -and
        $requiredPaths -ccontains 'Contrib/Graphics/Icons/orange-uninstall.ico' -and
        $requiredPaths -ccontains 'Contrib/Graphics/Wizard/win.bmp') 'Pinned compiler/runtime/include/plugin/stub/locale/resource classification drifted.'
}
if($SyntheticOnly){
    Check 'synthetic-only-mode-does-not-claim-repository-tree-examination' {
        Assert-True $SyntheticOnly 'Synthetic-only boundary was lost.'
    }
}else{
    Check 'repository-nsis-tree-exact-set-and-leases-validate' {
        $closure=Open-RimePimeNsisCompilerInputClosure
        try{
            $evidence=Test-RimePimeNsisCompilerInputClosure $closure
            Assert-True (-not $evidence.nsis_non_os_compiler_input_closure -and -not $evidence.full_nsis_toolchain_input_closure -and
                $evidence.nsis_known_input_file_replacement_closure -and
                -not $evidence.active_same_sid_transient_tree_membership_interference_excluded -and
                [int]$evidence.nsis_compiler_input_read_lease_count -eq 303 -and
                [int]$evidence.nsis_compiler_input_directory_lease_count -eq 19 -and
                [int]$evidence.nsis_compiler_input_anchor_directory_lease_count -eq 2 -and
                [int]$evidence.nsis_compiler_input_directory_lease_count -eq
                    ([int]$evidence.nsis_compiler_input_directory_count+[int]$evidence.nsis_compiler_input_anchor_directory_lease_count) -and
                [string]$evidence.nsis_compiler_input_tree_sha256 -ceq 'a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352') 'Repository NSIS closure evidence is wrong.'
        }finally{Close-RimePimeNsisCompilerInputClosure $closure}
    }
    Check 'repository-makensis-synthetic-fixture-runs-under-known-input-leases' {
        $compileRoot=Join-Path $output 'leased-compile'
        New-Item -ItemType Directory -Path $compileRoot|Out-Null
        $source=Join-Path $compileRoot 'minimal.nsi'
        $candidate=Join-Path $compileRoot 'candidate.exe'
        $sourceText="Unicode true`nName `"Yime NSIS closure synthetic fixture`"`nOutFile `"candidate.exe`"`nRequestExecutionLevel user`nSection`nSectionEnd`n"
        [IO.File]::WriteAllText($source,$sourceText,[Text.UTF8Encoding]::new($false))
        $closure=Open-RimePimeNsisCompilerInputClosure
        try{
            $before=Test-RimePimeNsisCompilerInputClosure $closure
            Push-Location $compileRoot
            try{
                & (Join-Path $closure.NsisRoot 'Bin\makensis.exe') /NOCD /NOCONFIG /V2 $source 2>&1|Out-Null
                if($LASTEXITCODE -ne 0){throw "Synthetic makensis fixture failed with exit code $LASTEXITCODE."}
            }finally{Pop-Location}
            $after=Test-RimePimeNsisCompilerInputClosure $closure
            Assert-True ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
                [bool]$before.nsis_distribution_tree_exact_at_open_and_test -and
                [bool]$after.nsis_distribution_tree_exact_at_open_and_test -and
                -not [bool]$after.active_same_sid_transient_tree_membership_interference_excluded -and
                -not [bool]$after.nsis_non_os_compiler_input_closure -and
                -not [bool]$after.full_nsis_toolchain_input_closure) 'Synthetic compiler run did not preserve the reviewed boundary.'
        }finally{Close-RimePimeNsisCompilerInputClosure $closure}
    }
}
Check 'scope-explicitly-excludes-os-and-generic-full-closure' {
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.ps1'))
    Assert-True ($source.Contains("full_nsis_toolchain_input_closure=`$false") -and
        $source.Contains('Windows loader DLLs, process environment') -and
        $source.Contains("active_same_sid_transient_tree_membership_interference_excluded=`$false")) 'NSIS non-OS boundary is not explicit.'
}
Check 'fake-lock-tree-digest-is-rejected-by-code-pin' {
    $lock=Read-RimePimeNsisCompilerToolchainLockDocument
    $fake=$lock.Document|ConvertTo-Json -Depth 16 -Compress|ConvertFrom-Json
    $fake.nsis.compiler_input_closure.tree_sha256=('0'*64)-join ''
    Assert-Rejected {Test-RimePimeNsisCompilerToolchainLockDocument $fake} '*code-pinned identity*'
}
Check 'synthetic-exact-tree-opens-and-remains-stable' {
    $case=New-Fixture 'positive';$ClosureRecordByRoot.Add($case.Root,$case.Record)
    $closure=Open-RimePimeNsisCompilerInputClosureCore $case.Root $case.Record
    try{Assert-CoreActive $closure}finally{Close-RimePimeNsisCompilerInputClosure $closure}
}
Check 'synthetic-unlisted-file-is-rejected' {
    $case=New-Fixture 'extra-file';[IO.File]::WriteAllText((Join-Path $case.Root 'Include\extra.nsh'),'extra')
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*exact-set*'
}
Check 'synthetic-content-change-is-rejected' {
    $case=New-Fixture 'changed-file';[IO.File]::WriteAllText((Join-Path $case.Root 'Include\base.nsh'),'changed')
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*exact set*'
}
Check 'synthetic-missing-input-is-rejected' {
    $case=New-Fixture 'missing-file';[IO.File]::Delete((Join-Path $case.Root 'Include\base.nsh'))
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*exact-set count*'
}
Check 'synthetic-hardlink-is-rejected' {
    $case=New-Fixture 'hardlink';$sentinel=Join-Path $output 'hardlink-sentinel.bin'
    [IO.File]::WriteAllText($sentinel,'sentinel');$target=Join-Path $case.Root 'Include\extra.nsh'
    New-Item -ItemType HardLink -Path $target -Target $sentinel|Out-Null
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*Hard-linked*'
}
Check 'synthetic-alternate-data-stream-is-rejected' {
    $case=New-Fixture 'ads';Set-Content -LiteralPath (Join-Path $case.Root 'Include\base.nsh') -Stream foreign -Value foreign -NoNewline
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*Alternate data stream*'
}
Check 'synthetic-junction-is-rejected' {
    $case=New-Fixture 'junction';$outside=Join-Path $output 'junction-outside';New-Item -ItemType Directory -Path $outside|Out-Null
    New-Item -ItemType Junction -Path (Join-Path $case.Root 'Include\foreign') -Target $outside|Out-Null
    Assert-Rejected {Get-RimePimeNsisCompilerInputTreeSnapshot $case.Root $case.Record} '*Reparse directory*'
}
Check 'same-sid-file-write-and-replacement-are-blocked-by-lease' {
    $case=New-Fixture 'leased-file';$ClosureRecordByRoot.Add($case.Root,$case.Record)
    $closure=Open-RimePimeNsisCompilerInputClosureCore $case.Root $case.Record
    try{
        $target=Join-Path $case.Root 'Include\base.nsh';$replacement=Join-Path $output 'leased-file-replacement.bin';$backup=Join-Path $output 'leased-file-backup.bin'
        [IO.File]::WriteAllText($replacement,'replacement');$writeBlocked=$false;$replaceBlocked=$false
        try{[IO.File]::WriteAllText($target,'attacker')}catch{$writeBlocked=$true}
        try{[IO.File]::Replace($replacement,$target,$backup,$true)}catch{$replaceBlocked=$true}
        Assert-True ($writeBlocked -and $replaceBlocked) 'Same-SID write or replacement bypassed the file lease.'
        Assert-CoreActive $closure
    }finally{Close-RimePimeNsisCompilerInputClosure $closure}
}
Check 'same-sid-directory-replacement-is-blocked-by-lease' {
    $case=New-Fixture 'leased-directory';$ClosureRecordByRoot.Add($case.Root,$case.Record)
    $closure=Open-RimePimeNsisCompilerInputClosureCore $case.Root $case.Record
    try{
        $blocked=$false;try{[IO.Directory]::Move((Join-Path $case.Root 'Include'),(Join-Path $case.Root 'Include-swapped'))}catch{$blocked=$true}
        Assert-True $blocked 'Same-SID directory replacement bypassed the directory lease.';Assert-CoreActive $closure
    }finally{Close-RimePimeNsisCompilerInputClosure $closure}
}
Check 'same-sid-transient-unlisted-child-is-not-excluded-by-directory-leases' {
    $case=New-Fixture 'transient-child-boundary';$ClosureRecordByRoot.Add($case.Root,$case.Record)
    $closure=Open-RimePimeNsisCompilerInputClosureCore $case.Root $case.Record
    $transient=Join-Path $case.Root 'Plugins\x86-unicode\foreign.dll'
    try{
        [IO.File]::WriteAllText($transient,'foreign',[Text.UTF8Encoding]::new($false))
        Assert-True (Test-Path -LiteralPath $transient -PathType Leaf) 'Fixture did not demonstrate child creation under directory leases.'
        [IO.File]::Delete($transient)
        Assert-True (-not(Test-Path -LiteralPath $transient)) 'Fixture did not demonstrate child deletion under directory leases.'
        foreach($lease in @($closure.FileLeases)){$null=Assert-RimePimeNsisClosureFileLease $lease}
        $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.ps1'))
        Assert-True ($source.Contains("active_same_sid_transient_tree_membership_interference_excluded=`$false") -and
            $source.Contains("nsis_non_os_compiler_input_closure=`$false")) 'Transient child boundary is not fail-closed.'
    }finally{
        if(Test-Path -LiteralPath $transient){[IO.File]::Delete($transient)}
        Close-RimePimeNsisCompilerInputClosure $closure
    }
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-nsis-toolchain-closure-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    passed=$failed.Count -eq 0;check_count=$checks.Count;checks=@($checks)
    synthetic_only=[bool]$SyntheticOnly;repository_nsis_tree_examined=[bool](-not $SyntheticOnly)
    nsis_toolchain_lock_sha256='01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45'
    nsis_compiler_input_scope='repository-pinned-nsis-distribution-non-os-v1'
    nsis_compiler_input_tree_sha256='a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352'
    nsis_known_input_lease_contract_available_to_builder=$true
    active_same_sid_transient_tree_membership_interference_excluded=$false
    nsis_non_os_compiler_input_closure=$false
    makensis_executed_under_test_leases=[bool](-not $SyntheticOnly);full_nsis_toolchain_input_closure=$false
    installer_or_uninstaller_executed=$false;registry_touched=$false;product_process_touched=$false
}
$resultPath=Join-Path $output 'result.json';$digest=Write-RimePimeStageSealedJson $result $resultPath
if($failed.Count){$failed|Format-Table -AutoSize|Out-String|Write-Host;throw "$($failed.Count) of $($checks.Count) NSIS toolchain closure checks failed."}
Write-Host "PASS: $($checks.Count) isolated NSIS toolchain closure checks passed. Evidence: $resultPath ($digest)"
