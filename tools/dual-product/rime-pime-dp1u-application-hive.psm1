# Fixture-only native typed registry operations through a private application hive.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:HiveSourceHash='4cf061813ae60f3d0f6d62606d6394388e40be1f4d07c52afe2a72217968694a'
$script:HiveNamespace='Yime.Dp1UApplicationHive_'+[guid]::NewGuid().ToString('N')
$script:HiveType=$null;$script:HiveInputType=$null;$script:HiveNativeType=$null
$script:HiveContexts=@{}
$script:HiveRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
function Open-AppHiveSource {
    $stream=[IO.File]::Open((Join-Path $PSScriptRoot 'rime-pime-dp1u-application-hive.cs'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($digest -cne $script:HiveSourceHash){throw 'Application hive source pin mismatch.'}
        if($null -eq $script:HiveType){
            $stream.Position=0;$reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
            try{$source=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $types=Add-Type -TypeDefinition ($source.Replace('namespace Yime.Dp1UApplicationHive {',('namespace '+$script:HiveNamespace+' {'))) -PassThru
            $script:HiveType=@($types|Where-Object{$_.FullName -ceq ($script:HiveNamespace+'.HiveContext')})[0]
            $script:HiveInputType=@($types|Where-Object{$_.FullName -ceq ($script:HiveNamespace+'.ValueInput')})[0]
            $script:HiveNativeType=@($types|Where-Object{$_.FullName -ceq ($script:HiveNamespace+'.Native')})[0]
        }
        return $stream
    }catch{$stream.Dispose();throw}
}
function Assert-AppHivePath($Path) {
    if($Path -isnot [string]){throw 'HivePath must be a literal string.'}
    $script:HiveNativeType::Canonical($Path)
    $run=[IO.Path]::GetDirectoryName($Path)
    if([IO.Path]::GetFileName($Path) -cne 'private.hiv' -or [IO.Path]::GetDirectoryName($run) -cne (Join-Path $script:HiveRepo '.tmp\dual-product') -or [IO.Path]::GetFileName($run) -cnotmatch '^dp1-u-app-hive-[A-Za-z0-9][A-Za-z0-9-]*$'){
        throw 'Only this repository .tmp/dual-product/dp1-u-app-hive-*/private.hiv is admitted.'
    }
}
function Get-AppHiveBundle($Context) {
    foreach($bundle in $script:HiveContexts.Values){if([object]::ReferenceEquals($bundle.public,$Context)){return $bundle}}
    throw 'Original retained application hive context required; unknown or closed context.'
}
function Get-AppHiveSnapshot($Bundle,$Snapshot) {
    foreach($entry in $Bundle.snapshots){if([object]::ReferenceEquals($entry.public,$Snapshot)){return $entry.native}}
    throw 'Original same-context snapshot required; unknown or closed snapshot.'
}
function New-AppHiveContext($HivePath,$ExpectedFile) {
    $source=Open-AppHiveSource;$native=$null
    try {
        Assert-AppHivePath $HivePath
        if($null -eq $ExpectedFile){$native=$script:HiveType::Open($HivePath)}
        else {
            if($ExpectedFile -isnot [pscustomobject]){throw 'ExpectedFile must be an identity object.'}
            $names=@($ExpectedFile.PSObject.Properties|ForEach-Object{$_.Name})
            if($names.Count -ne 3 -or @('file_id','bytes','sha256'|Where-Object{$names -cnotcontains $_}).Count){throw 'ExpectedFile field set mismatch.'}
            if($ExpectedFile.file_id -isnot [string] -or $ExpectedFile.sha256 -isnot [string] -or ($ExpectedFile.bytes -isnot [long] -and $ExpectedFile.bytes -isnot [int])){throw 'ExpectedFile fields require literal types.'}
            $native=$script:HiveType::Reopen($HivePath,$ExpectedFile.file_id,[long]$ExpectedFile.bytes,$ExpectedFile.sha256)
        }
        $id=[guid]::NewGuid().ToString('N')
        $public=[pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-app-hive-context-v1';id=$id;hive_path=$HivePath;fixture_only=$true}
        $script:HiveContexts[$id]=@{key=$id;public=$public;native=$native;source=$source;snapshots=[Collections.Generic.List[object]]::new()}
        $native=$null;$source=$null;return $public
    }finally{if($null -ne $native){$native.Dispose()};if($null -ne $source){$source.Dispose()}}
}
function Open-RimePimeDp1UApplicationHive {
    [CmdletBinding()]param([Parameter(Mandatory)]$HivePath)
    New-AppHiveContext $HivePath $null
}
function Open-RimePimeDp1UExistingApplicationHive {
    [CmdletBinding()]param([Parameter(Mandatory)]$HivePath,[Parameter(Mandatory)]$ExpectedFile)
    if($null -eq $ExpectedFile){throw 'ExpectedFile is mandatory for reopen.'}
    New-AppHiveContext $HivePath $ExpectedFile
}
function Get-RimePimeDp1UApplicationHiveSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    $bundle=Get-AppHiveBundle $Context
    $check=Open-AppHiveSource
    try{$native=$bundle.native.Capture()}finally{$check.Dispose()}
    $rows=@($native.Metadata()|ForEach-Object{[pscustomobject][ordered]@{value_id=$_.Name;kind=$_.Kind;bytes=$_.Bytes;sha256=$_.Sha256}})
    $public=[pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-app-hive-snapshot-v1';id=[guid]::NewGuid().ToString('N');values=$rows;raw_value_bytes_exported=$false;atomic_snapshot_verified=$false;quiescence_verified=$false}
    $bundle.snapshots.Add(@{public=$public;native=$native});return $public
}
function Write-AppHiveValue($Native,$Wanted,[int]$Index) { $Native.WriteIndex($Wanted,$Index) }
function Invoke-AppHiveWrite($Bundle,$Before,$Wanted,[string]$Operation) {
    $check=Open-AppHiveSource
    try {
        $Bundle.native.RequireCurrent($Before)
        $written=0;$errorText=$null;$passed=$false
        try {
            for($i=0;$i -lt 6;$i++){Write-AppHiveValue $Bundle.native $Wanted $i;$written++}
            $Bundle.native.Flush();$Bundle.native.RequireCurrent($Wanted);$passed=$true
        }catch{$errorText=$_.Exception.Message}
        return [pscustomobject][ordered]@{
            schema_version='yime-rime-pime-dp1u-app-hive-result-v1';affected_product='rime-pime';fixture_only=$true
            operation=$Operation;passed=$passed;completed_value_writes=$written;partial_change_possible=(-not $passed);error=$errorText
            native_application_hive_provider_used=$true;typed_readback_verified=$passed;native_source_sha256=$script:HiveSourceHash
            production_registry_accessed=$false;native_com_profile_registration_verified=$false;target_user_sid_verified=$false
            independent_system_registry_visibility_verified=$false;atomic_multi_value_transaction_verified=$false
            hostile_same_sid_creation_prevention_verified=$false;continuous_membership_protection=$false
            physical_crash_durability_verified=$false;in_memory_caller_authenticated=$false
            installer_executed=$false;installed_yimecore_local12_touched=$false;production_user_data_accessed=$false
            full_transaction_acceptance_passed=$false;dp1_u_acceptance_passed=$false
        }
    }finally{$check.Dispose()}
}
function Set-RimePimeDp1UApplicationHiveValues {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$ExpectedBefore,[Parameter(Mandatory)]$Values)
    $bundle=Get-AppHiveBundle $Context;$before=Get-AppHiveSnapshot $bundle $ExpectedBefore
    if($Values -isnot [array] -or $Values.Count -ne 6){throw 'Values must be a literal six-element array.'}
    $inputs=[Array]::CreateInstance($script:HiveInputType,6)
    for($i=0;$i -lt 6;$i++){
        $row=$Values[$i]
        if($row -isnot [pscustomobject]){throw 'Value must be an object.'}
        $names=@($row.PSObject.Properties|ForEach-Object{$_.Name})
        if($names.Count -ne 3 -or @('value_id','kind','raw_bytes'|Where-Object{$names -cnotcontains $_}).Count){throw 'Value field set mismatch.'}
        if($row.value_id -isnot [string] -or $row.kind -isnot [string] -or $row.raw_bytes -isnot [byte[]]){throw 'Value requires literal string/string/byte[] fields.'}
        $inputs.SetValue([Activator]::CreateInstance($script:HiveInputType,[object[]]@($row.value_id,$row.kind,$row.raw_bytes)),$i)
    }
    $wanted=$bundle.native.PrepareValues($inputs)
    Invoke-AppHiveWrite $bundle $before $wanted 'apply'
}
function Restore-RimePimeDp1UApplicationHive {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$ExpectedBefore)
    $bundle=Get-AppHiveBundle $Context;$wanted=Get-AppHiveSnapshot $bundle $Snapshot;$before=Get-AppHiveSnapshot $bundle $ExpectedBefore
    Invoke-AppHiveWrite $bundle $before $wanted 'rollback'
}
function Close-RimePimeDp1UApplicationHive {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    $bundle=Get-AppHiveBundle $Context;$script:HiveContexts.Remove($bundle.key)
    try {
        $file=$bundle.native.CloseAndInspect()
        return [pscustomobject][ordered]@{file_id=$file.FileId;bytes=$file.Bytes;sha256=$file.Sha256}
    }finally{try{$bundle.native.Dispose()}finally{$bundle.snapshots.Clear();$bundle.source.Dispose()}}
}
$ExecutionContext.SessionState.Module.OnRemove={
    $first=$null
    foreach($bundle in @($script:HiveContexts.Values)){
        try{$bundle.native.Dispose()}catch{if($null -eq $first){$first=$_}}
        finally{$bundle.snapshots.Clear();try{$bundle.source.Dispose()}catch{if($null -eq $first){$first=$_}}}
    }
    $script:HiveContexts.Clear();if($null -ne $first){throw $first}
}
Export-ModuleMember -Function Open-RimePimeDp1UApplicationHive,Open-RimePimeDp1UExistingApplicationHive,Get-RimePimeDp1UApplicationHiveSnapshot,Set-RimePimeDp1UApplicationHiveValues,Restore-RimePimeDp1UApplicationHive,Close-RimePimeDp1UApplicationHive
