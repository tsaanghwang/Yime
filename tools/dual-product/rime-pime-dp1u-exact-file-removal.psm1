# First DP1-U native deletion primitive. Only explicitly named repository fixtures.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:RemovalSourceHash='38ca72ec665187b1ecb958797660508e9f755a7b6f9d57b64eff6e7396e3b5a6'
$script:RemovalNamespace='Yime.Dp1UExactRemoval_'+[guid]::NewGuid().ToString('N')
$script:RemovalType=$null
$script:RemovalExpectedType=$null
$script:RemovalNativeType=$null
$script:RemovalContexts=@{}
$script:RemovalRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

function Open-ExactRemovalSource {
    $path=Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.cs'
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($digest -cne $script:RemovalSourceHash){throw 'Exact removal native source pin mismatch.'}
        if($null -eq $script:RemovalType){
            $stream.Position=0
            $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
            try {$source=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $types=Add-Type -TypeDefinition ($source.Replace('namespace Yime.Dp1UExactRemoval {',('namespace '+$script:RemovalNamespace+' {'))) -PassThru
            $script:RemovalType=@($types|Where-Object{$_.FullName -ceq ($script:RemovalNamespace+'.RemovalContext')})[0]
            $script:RemovalExpectedType=@($types|Where-Object{$_.FullName -ceq ($script:RemovalNamespace+'.ExpectedFile')})[0]
            $script:RemovalNativeType=@($types|Where-Object{$_.FullName -ceq ($script:RemovalNamespace+'.Native')})[0]
        }
        return $stream
    }catch{$stream.Dispose();throw}
}
function Assert-ExactRemovalRoot($Path) {
    if($Path -isnot [string]){throw 'PayloadRoot must be a literal string.'}
    $script:RemovalNativeType::CanonicalPath($Path)
    if([IO.Path]::GetFileName($Path) -cne 'payload'){throw 'Only a fixture payload root is admitted.'}
    $run=[IO.Path]::GetDirectoryName($Path)
    if([IO.Path]::GetDirectoryName($run) -cne (Join-Path $script:RemovalRepo '.tmp\dual-product') -or
        [IO.Path]::GetFileName($run) -cnotmatch '^dp1-u-exact-removal-[A-Za-z0-9][A-Za-z0-9-]*$'){
        throw 'Only this repository .tmp/dual-product/dp1-u-exact-removal-*/payload is admitted.'
    }
}
function Get-ExactRemovalBundle($Context) {
    if($null -ne $Context -and $Context -is [pscustomobject]){
        foreach($bundle in $script:RemovalContexts.Values){
            if([object]::ReferenceEquals($bundle.public,$Context)){return $bundle}
        }
    }
    throw 'Original retained removal context required; unknown or closed context.'
}
function Open-RimePimeDp1UExactFileRemoval {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$PayloadRoot,[Parameter(Mandatory)]$ExpectedFiles)
    $source=Open-ExactRemovalSource;$native=$null
    try {
        Assert-ExactRemovalRoot $PayloadRoot
        if($ExpectedFiles -isnot [array] -or $ExpectedFiles.Count -lt 1 -or $ExpectedFiles.Count -gt 4096){throw 'ExpectedFiles must be a nonempty literal array.'}
        $expected=[Array]::CreateInstance($script:RemovalExpectedType,$ExpectedFiles.Count)
        for($i=0;$i -lt $ExpectedFiles.Count;$i++){
            $row=$ExpectedFiles[$i]
            if($row -isnot [pscustomobject]){throw 'Expected file must be an object.'}
            $names=@($row.PSObject.Properties|ForEach-Object{$_.Name})
            if($names.Count -ne 4 -or @('path','bytes','sha256','file_id'|Where-Object{$names -cnotcontains $_}).Count){throw 'Expected file field set mismatch.'}
            if($row.path -isnot [string] -or $row.sha256 -isnot [string] -or $row.file_id -isnot [string] -or
                ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 0){throw 'Expected file fields require literal string/integer types.'}
            $value=[Activator]::CreateInstance($script:RemovalExpectedType,[object[]]@($row.path,[long]$row.bytes,$row.sha256,$row.file_id))
            $expected.SetValue($value,$i)
        }
        $native=$script:RemovalType::Open($PayloadRoot,$expected)
        $id=[guid]::NewGuid().ToString('N')
        $public=[pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-exact-file-removal-context-v1';id=$id;payload_root=$PayloadRoot;approved_file_count=$ExpectedFiles.Count}
        $script:RemovalContexts[$id]=@{key=$id;public=$public;native=$native;source=$source}
        $native=$null;$source=$null
        return $public
    }finally{if($null -ne $native){$native.Dispose()};if($null -ne $source){$source.Dispose()}}
}
function Close-RimePimeDp1UExactFileRemoval {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    $bundle=Get-ExactRemovalBundle $Context
    $script:RemovalContexts.Remove($bundle.key)
    try{$bundle.native.Dispose()}finally{$bundle.source.Dispose()}
}
function Invoke-RimePimeDp1UExactFileRemoval {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    $bundle=Get-ExactRemovalBundle $Context
    try {
        $check=Open-ExactRemovalSource;try{$bundle.native.ValidateAll()}finally{$check.Dispose()}
        $rows=@($bundle.native.Remove()|ForEach-Object{[pscustomobject][ordered]@{path=$_.Path;status=$_.Status;marked_for_deletion=$_.MarkedForDeletion;removed=$_.Removed;native_error=$_.ErrorCode}})
        return [pscustomobject][ordered]@{
            schema_version='yime-rime-pime-dp1u-exact-file-removal-result-v1';affected_product='rime-pime';fixture_only=$true
            payload_root=$bundle.native.Root;native_source_sha256=$script:RemovalSourceHash;files=$rows
            all_approved_files_removed=(@($rows|Where-Object{-not $_.removed}).Count -eq 0)
            directory_or_root_removal_performed=$false;path_delete_fallback_used=$false;reboot_deletion_queued=$false
            continuous_membership_protection=$false;hostile_same_sid_prevention_verified=$false
            independent_system_visibility_verified=$false;in_memory_caller_authenticated=$false
            installer_executed=$false;uninstaller_executed=$false;product_registration_modified=$false
            installed_yimecore_local12_touched=$false;production_user_data_accessed=$false
            full_removal_acceptance_passed=$false;dp1_u_acceptance_passed=$false
        }
    }finally{Close-RimePimeDp1UExactFileRemoval $Context}
}
$ExecutionContext.SessionState.Module.OnRemove={
    foreach($bundle in @($script:RemovalContexts.Values)){try{$bundle.native.Dispose()}finally{$bundle.source.Dispose()}}
    $script:RemovalContexts.Clear()
}
Export-ModuleMember -Function Open-RimePimeDp1UExactFileRemoval,Invoke-RimePimeDp1UExactFileRemoval,Close-RimePimeDp1UExactFileRemoval
