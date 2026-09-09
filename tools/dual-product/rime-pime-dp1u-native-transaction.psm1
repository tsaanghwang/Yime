# Native process-interruption transaction over explicitly owned repository fixtures.
# Prepared SHA is an external binding, not authentication of a hostile same-SID caller.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:TxRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$script:TxNativeHash='4859d2abcd3f8eafd17053f10b6063944572796fc81b853606d1ce0da34431b8'
$script:TxRemovalHash='38ca72ec665187b1ecb958797660508e9f755a7b6f9d57b64eff6e7396e3b5a6'
$script:TxNamespace='Yime.Dp1UTransaction_'+[guid]::NewGuid().ToString('N')
$script:TxStoreType=$null;$script:TxNativeType=$null;$script:TxJsonType=$null
$script:TxHiveModule=$null;$script:TxRemovalModule=$null
$script:TxSourceNames=@('rime-pime-dp1u-native-transaction.cs','rime-pime-dp1u-native-transaction.psm1','rime-pime-dp1u-application-hive.cs','rime-pime-dp1u-application-hive.psm1','rime-pime-dp1u-exact-file-removal.cs','rime-pime-dp1u-exact-file-removal.psm1')
function Hash-TxBytes([byte[]]$Bytes){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Assert-TxObject($Value,[string[]]$Names){
    if($Value -isnot [pscustomobject]){throw 'Transaction requires a literal object.'}
    $actual=@($Value.PSObject.Properties|ForEach-Object{$_.Name})
    if($actual.Count -ne $Names.Count -or @($Names|Where-Object{$actual -cnotcontains $_}).Count){throw 'Transaction field set mismatch.'}
}
function Assert-TxHash($Value){if($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-f]{64}$'){throw 'Literal SHA256 required.'}}
function Assert-TxId($Value){if($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$'){throw 'Literal file identity required.'}}
function Get-TxPaths($Root){
    if($Root -isnot [string]){throw 'TransactionRoot requires a literal string.'}
    if([IO.Path]::GetFullPath($Root) -cne $Root -or [IO.Path]::GetDirectoryName($Root) -cne (Join-Path $script:TxRepo '.tmp\dual-product') -or
        [IO.Path]::GetFileName($Root) -cnotmatch '^dp1-u-native-transaction-([0-9a-f]{32})$'){throw 'Only an exact repository native transaction fixture root is admitted.'}
    $id=$Matches[1];$parent=[IO.Path]::GetDirectoryName($Root)
    return [pscustomobject]@{id=$id;root=$Root;hive=(Join-Path $parent ('dp1-u-app-hive-'+$id+'\private.hiv'));payload=(Join-Path $parent ('dp1-u-exact-removal-'+$id+'\payload'))}
}
function Open-Tx($Root,[bool]$Create){
    $paths=Get-TxPaths $Root;$leases=[Collections.Generic.List[object]]::new();$store=$null
    try{
        $sources=[ordered]@{};$texts=@{}
        foreach($name in $script:TxSourceNames){
            $s=[IO.File]::Open((Join-Path $PSScriptRoot $name),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$leases.Add($s)
            if($s.Length -gt 1048576){throw 'Transaction source exceeds size limit.'}
            $reader=[IO.StreamReader]::new($s,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
            try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
            $s.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
            try{$sources[$name]=([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $texts[$name]=$text
        }
        if($sources['rime-pime-dp1u-native-transaction.cs'] -cne $script:TxNativeHash -or $sources['rime-pime-dp1u-exact-file-removal.cs'] -cne $script:TxRemovalHash){throw 'Transaction native source pin mismatch.'}
        if($null -eq $script:TxStoreType){
            $code=$texts['rime-pime-dp1u-exact-file-removal.cs']+"`n"+$texts['rime-pime-dp1u-native-transaction.cs']
            $types=Add-Type -TypeDefinition ($code.Replace('namespace Yime.Dp1UExactRemoval {',('namespace '+$script:TxNamespace+' {'))) -PassThru
            $script:TxStoreType=@($types|Where-Object{$_.FullName -ceq ($script:TxNamespace+'.TransactionStore')})[0]
            $script:TxNativeType=@($types|Where-Object{$_.FullName -ceq ($script:TxNamespace+'.Native')})[0]
            $script:TxJsonType=@($types|Where-Object{$_.FullName -ceq ($script:TxNamespace+'.TransactionJson')})[0]
            $script:TxHiveModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-application-hive.psm1') -PassThru -Scope Local
            $script:TxRemovalModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-exact-file-removal.psm1') -PassThru -Scope Local
        }
        $constructor=$script:TxStoreType.GetConstructor([type[]]@([string],[bool]))
        $store=$constructor.Invoke([object[]]@([string]$Root,[bool]$Create))
        $ids=[pscustomobject][ordered]@{journal=$store.PinDirectory($Root);hive=$store.PinDirectory([IO.Path]::GetDirectoryName($paths.hive));payload=$store.PinDirectory($paths.payload)}
        return @{paths=$paths;store=$store;sources=[pscustomobject]$sources;leases=$leases;ids=$ids}
    }catch{if($null -ne $store){$store.Dispose()};foreach($s in $leases){$s.Dispose()};throw}
}
function Close-Tx($Tx){if($null -ne $Tx){try{$Tx.store.Dispose()}finally{foreach($s in $Tx.leases){$s.Dispose()}}}}
function Read-Tx($Tx,[string]$Name){
    $bytes=$Tx.store.Read($Name);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $script:TxJsonType::Check($text)
    return [pscustomobject]@{value=($text|ConvertFrom-Json);sha256=(Hash-TxBytes $bytes)}
}
function Publish-Tx($Tx,[string]$Name,$Value){
    $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes(($Value|ConvertTo-Json -Depth 20 -Compress))
    $Tx.store.Publish($Name,$bytes)
}
function Get-TxFile($Path){$o=$script:TxNativeType::Inspect($Path);[pscustomobject]@{file_id=$o.FileId;bytes=$o.Bytes;sha256=$o.Sha256}}
function Assert-TxFiles($Files){
    if($Files -isnot [array] -or $Files.Count -lt 1 -or $Files.Count -gt 64){throw 'One to 64 explicitly named files required.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($f in $Files){
        Assert-TxObject $f @('path','file_id','bytes','sha256');Assert-TxId $f.file_id;Assert-TxHash $f.sha256
        if($f.path -isnot [string] -or $f.path -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or -not $seen.Add($f.path)){throw 'Unique plain filename required.'}
        $script:TxNativeType::RelativePath($f.path)
        if(($f.bytes -isnot [int] -and $f.bytes -isnot [long]) -or $f.bytes -lt 0){throw 'Literal file size required.'}
    }
}
function Check-TxFiles($Tx,$Files,[bool]$AllowAbsent){
    $rows=@(foreach($f in $Files){
        $path=Join-Path $Tx.paths.payload $f.path;$status=$Tx.store.LeafStatus($path)
        if($status -ceq 'removed'){
            if(-not $AllowAbsent){throw 'A precommit payload member is absent.'}
            [pscustomobject]@{path=$f.path;state='desired-absence-observed';removed_this_invocation=$false}
        }else{
            $actual=Get-TxFile $path
            if($actual.file_id -cne $f.file_id -or $actual.bytes -ne $f.bytes -or $actual.sha256 -cne $f.sha256){throw 'Payload member identity/bytes changed; preserved.'}
            [pscustomobject]@{path=$f.path;state='present';removed_this_invocation=$false}
        }
    })
    return ,$rows
}
function Encode-TxValues($Values){return ,@(foreach($v in $Values){[pscustomobject][ordered]@{value_id=$v.value_id;kind=$v.kind;base64=[Convert]::ToBase64String($v.raw_bytes)}})}
function Decode-TxValues($Rows){
    if($Rows -isnot [array] -or $Rows.Count -ne 6){throw 'Six persisted typed values required.'}
    return ,@(foreach($row in $Rows){
        Assert-TxObject $row @('value_id','kind','base64')
        if($row.value_id -isnot [string] -or $row.kind -isnot [string] -or $row.base64 -isnot [string] -or $row.base64.Length -gt 87384){throw 'Persisted value literal types/size invalid.'}
        $raw=[Convert]::FromBase64String($row.base64)
        if([Convert]::ToBase64String($raw) -cne $row.base64){throw 'Noncanonical value encoding.'}
        [pscustomobject]@{value_id=$row.value_id;kind=$row.kind;raw_bytes=[byte[]]$raw}
    })
}
function Same-TxValue($A,$B){return ($A.value_id -ceq $B.value_id -and $A.kind -ceq $B.kind -and [Convert]::ToBase64String($A.raw_bytes) -ceq [Convert]::ToBase64String($B.raw_bytes))}
function Open-TxHive($Tx,$FileId){
    $file=Get-TxFile $Tx.paths.hive
    if($file.file_id -cne $FileId){throw 'Private hive file identity changed.'}
    # Current digest is an observation for Reopen, not proof of original values.
    & $script:TxHiveModule {param($p,$e) Open-RimePimeDp1UExistingApplicationHive -HivePath $p -ExpectedFile $e} $Tx.paths.hive $file
}
function Close-TxHive($Context){if($null -ne $Context){& $script:TxHiveModule {param($c) Close-RimePimeDp1UApplicationHive $c} $Context|Out-Null}}
function Snapshot-TxHive($Context){& $script:TxHiveModule {param($c) Get-RimePimeDp1UApplicationHiveSnapshot $c} $Context}
function Export-TxHive($Context,$Snapshot){$rows=& $script:TxHiveModule {param($c,$s) Export-RimePimeDp1UApplicationHiveValues -Context $c -Snapshot $s} $Context $Snapshot;return ,$rows}
function Normalize-TxValues($Context,$Values){$rows=& $script:TxHiveModule {param($c,$v) ConvertTo-RimePimeDp1UApplicationHiveValues -Context $c -Values $v} $Context $Values;return ,$rows}
function Set-TxHive($Context,$Before,$Values){
    $r=& $script:TxHiveModule {param($c,$b,$v) Set-RimePimeDp1UApplicationHiveValues -Context $c -ExpectedBefore $b -Values $v} $Context $Before $Values
    if($r.passed -isnot [bool] -or -not $r.passed){throw 'Private hive write incomplete; recover from the retained transaction.'}
}
function Invoke-TxCheckpoint([string]$Name){} # Test replacement is confined to an owned child/module; no production fault switch.
function Read-TxPlan($Tx,$Expected){
    Assert-TxHash $Expected;$record=Read-Tx $Tx 'prepared.bin'
    if($record.sha256 -cne $Expected){throw 'Prepared record differs from external SHA256 binding.'}
    $p=$record.value
    Assert-TxObject $p @('schema_version','transaction_id','transaction_root','directory_ids','source_hashes','hive_file_id','old_values','new_values','files')
    if($p.schema_version -isnot [string] -or $p.transaction_id -isnot [string] -or $p.transaction_root -isnot [string] -or
        $p.schema_version -cne 'yime-rime-pime-dp1u-native-prepared-v1' -or $p.transaction_id -cne $Tx.paths.id -or $p.transaction_root -cne $Tx.paths.root){throw 'Transaction record root/identity mismatch.'}
    Assert-TxObject $p.directory_ids @('journal','hive','payload')
    foreach($name in @('journal','hive','payload')){Assert-TxId $p.directory_ids.$name;if($p.directory_ids.$name -cne $Tx.ids.$name){throw 'Prepared directory identity changed.'}}
    Assert-TxObject $p.source_hashes $script:TxSourceNames
    foreach($name in $script:TxSourceNames){Assert-TxHash $p.source_hashes.$name;if($p.source_hashes.$name -cne $Tx.sources.$name){throw 'Prepared transaction source changed.'}}
    Assert-TxId $p.hive_file_id;Assert-TxFiles $p.files
    return $p
}
function Read-TxDecision($Tx,[string]$Name,[string]$Digest){
    if(-not $Tx.store.Has($Name)){return $null}
    $r=(Read-Tx $Tx $Name).value
    Assert-TxObject $r @('schema_version','transaction_id','prepared_sha256','disposition')
    Assert-TxHash $r.prepared_sha256
    if($r.schema_version -isnot [string] -or $r.transaction_id -isnot [string] -or $r.disposition -isnot [string] -or
        $r.schema_version -cne 'yime-rime-pime-dp1u-native-decision-v1' -or $r.transaction_id -cne $Tx.paths.id -or $r.prepared_sha256 -cne $Digest -or
        $r.disposition -cnotin @('commit','rolled-back','commit-complete')){throw 'Transaction decision binding invalid.'}
    if(($Name -ceq 'commit.bin' -and $r.disposition -cne 'commit') -or ($Name -ceq 'terminal.bin' -and $r.disposition -ceq 'commit')){throw 'Wrong transaction decision role.'}
    return $r.disposition
}
function Write-TxDecision($Tx,[string]$Name,[string]$Digest,[string]$Disposition){
    $null=Publish-Tx $Tx $Name ([pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-native-decision-v1';transaction_id=$Tx.paths.id;prepared_sha256=$Digest;disposition=$Disposition})
    if((Read-TxDecision $Tx $Name $Digest) -cne $Disposition){throw 'Transaction decision readback failed.'}
}
function New-TxResult($Tx,$Digest,$Disposition,$Observations,[bool]$Replayed){
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1u-native-transaction-result-v1';affected_product='rime-pime';fixture_only=$true
        transaction_root=$Tx.paths.root;prepared_sha256=$Digest;disposition=$Disposition;replayed=$Replayed;desired_state_verified=$true
        payload_observations=@($Observations);native_private_hive_used=$true;process_interruption_protocol_wired=$true
        production_registration_modified=$false;installer_executed=$false;uninstaller_executed=$false;runtime_started=$false
        installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;directory_or_root_removal_performed=$false
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false;hostile_same_sid_prevention_verified=$false
        missing_members_attributed_to_this_process=$false;in_memory_caller_authenticated=$false
        full_native_product_transaction_complete=$false;dp1_u_acceptance_passed=$false
    }
}
function New-RimePimeDp1UNativeTransaction {
    [CmdletBinding()]param([Parameter(Mandatory)]$TransactionRoot,[Parameter(Mandatory)]$ExpectedHiveFile,[Parameter(Mandatory)]$DesiredValues,[Parameter(Mandatory)]$ExpectedFiles)
    $tx=$null;$hive=$null;$removal=$null
    try{
        $tx=Open-Tx $TransactionRoot $true
        if($tx.store.Has('prepared.bin') -or $tx.store.Has('commit.bin') -or $tx.store.Has('terminal.bin')){throw 'A fresh transaction is required.'}
        Assert-TxFiles $ExpectedFiles
        $null=Check-TxFiles $tx $ExpectedFiles $false
        $removal=& $script:TxRemovalModule {param($p,$f) Open-RimePimeDp1UExactFileRemoval -PayloadRoot $p -ExpectedFiles $f} $tx.paths.payload $ExpectedFiles
        $hive=& $script:TxHiveModule {param($p,$e) Open-RimePimeDp1UExistingApplicationHive -HivePath $p -ExpectedFile $e} $tx.paths.hive $ExpectedHiveFile
        $snapshot=Snapshot-TxHive $hive
        $old=Normalize-TxValues $hive (Export-TxHive $hive $snapshot)
        $new=Normalize-TxValues $hive $DesiredValues
        $plan=[pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-native-prepared-v1';transaction_id=$tx.paths.id;transaction_root=$tx.paths.root
            directory_ids=$tx.ids;source_hashes=$tx.sources;hive_file_id=$ExpectedHiveFile.file_id;old_values=(Encode-TxValues $old);new_values=(Encode-TxValues $new);files=$ExpectedFiles}
        $digest=Publish-Tx $tx 'prepared.bin' $plan
        $null=Read-TxPlan $tx $digest
        return [pscustomobject][ordered]@{schema_version='yime-rime-pime-dp1u-native-transaction-ticket-v1';transaction_root=$tx.paths.root;prepared_sha256=$digest;fixture_only=$true;execution_authorized=$false}
    }finally{try{Close-TxHive $hive}finally{try{if($null -ne $removal){& $script:TxRemovalModule {param($c) Close-RimePimeDp1UExactFileRemoval $c} $removal}}finally{Close-Tx $tx}}}
}
function Invoke-TxOperation($TransactionRoot,$PreparedSha256,[bool]$Apply){
    $tx=$null;$hive=$null
    try{
        $tx=Open-Tx $TransactionRoot $false;$plan=Read-TxPlan $tx $PreparedSha256
        # A malformed final decision is fatal. It is never treated as absent.
        $commit=Read-TxDecision $tx 'commit.bin' $PreparedSha256;$terminal=Read-TxDecision $tx 'terminal.bin' $PreparedSha256
        if($null -ne $terminal -and (($terminal -ceq 'commit-complete') -ne ($null -ne $commit))){throw 'Contradictory transaction decisions.'}
        if($Apply -and ($null -ne $commit -or $null -ne $terminal)){throw 'Apply cannot reuse a decided transaction; use Resume.'}
        $observations=Check-TxFiles $tx $plan.files ($null -ne $commit)
        $hive=Open-TxHive $tx $plan.hive_file_id
        $old=Normalize-TxValues $hive (Decode-TxValues $plan.old_values);$new=Normalize-TxValues $hive (Decode-TxValues $plan.new_values)
        $snapshot=Snapshot-TxHive $hive;$current=Export-TxHive $hive $snapshot
        for($i=0;$i -lt 6;$i++){
            $isOld=Same-TxValue $current[$i] $old[$i];$isNew=Same-TxValue $current[$i] $new[$i]
            if(-not ($isOld -or $isNew) -or ($Apply -and -not $isOld) -or ($null -ne $commit -and -not $isNew) -or ($terminal -ceq 'rolled-back' -and -not $isOld)){
                throw 'Unapproved current registry value; preserved.'
            }
        }
        if($Apply){
            Invoke-TxCheckpoint 'before-hive-write'
            Set-TxHive $hive $snapshot $new
            Invoke-TxCheckpoint 'after-hive-write'
            Write-TxDecision $tx 'commit.bin' $PreparedSha256 'commit'
            $commit='commit';Invoke-TxCheckpoint 'after-commit'
        }elseif($null -eq $commit){
            if($null -eq $terminal){
                Set-TxHive $hive $snapshot $old;Invoke-TxCheckpoint 'after-rollback'
                $observations=Check-TxFiles $tx $plan.files $false
                Write-TxDecision $tx 'terminal.bin' $PreparedSha256 'rolled-back'
            }
            return New-TxResult $tx $PreparedSha256 'rolled-back' $observations $true
        }
        if($null -eq $terminal){
            $rows=[Collections.Generic.List[object]]::new();$index=0
            foreach($file in $plan.files){
                $checked=Check-TxFiles $tx @($file) $true;$observed=$checked[0]
                if($observed.state -ceq 'present'){
                    $c=& $script:TxRemovalModule {param($p,$f) Open-RimePimeDp1UExactFileRemoval -PayloadRoot $p -ExpectedFiles $f} $tx.paths.payload @($file)
                    $result=& $script:TxRemovalModule {param($c) Invoke-RimePimeDp1UExactFileRemoval $c} $c
                    if($result.all_approved_files_removed -isnot [bool] -or -not $result.all_approved_files_removed){throw 'Payload removal pending or failed; transaction remains committed for Resume.'}
                    $observed=[pscustomobject]@{path=$file.path;state='removed';removed_this_invocation=$true}
                }
                $rows.Add($observed);$index++;Invoke-TxCheckpoint ('after-removal-'+$index)
            }
            $observations=@($rows.ToArray())
        }
        $final=Check-TxFiles $tx $plan.files $true
        if(@($final|Where-Object{$_.state -cne 'desired-absence-observed'}).Count){throw 'Payload final absence not verified.'}
        $end=Export-TxHive $hive (Snapshot-TxHive $hive)
        for($i=0;$i -lt 6;$i++){if(-not (Same-TxValue $end[$i] $new[$i])){throw 'Final private registry state changed.'}}
        if($null -eq $terminal){Write-TxDecision $tx 'terminal.bin' $PreparedSha256 'commit-complete'}
        Invoke-TxCheckpoint 'after-terminal'
        return New-TxResult $tx $PreparedSha256 'commit-complete' $observations (-not $Apply)
    }finally{try{Close-TxHive $hive}finally{Close-Tx $tx}}
}
function Invoke-RimePimeDp1UNativeTransaction {
    [CmdletBinding()]param([Parameter(Mandatory)]$TransactionRoot,[Parameter(Mandatory)]$PreparedSha256)
    Invoke-TxOperation $TransactionRoot $PreparedSha256 $true
}
function Resume-RimePimeDp1UNativeTransaction {
    [CmdletBinding()]param([Parameter(Mandatory)]$TransactionRoot,[Parameter(Mandatory)]$PreparedSha256)
    Invoke-TxOperation $TransactionRoot $PreparedSha256 $false
}
Export-ModuleMember -Function New-RimePimeDp1UNativeTransaction,Invoke-RimePimeDp1UNativeTransaction,Resume-RimePimeDp1UNativeTransaction
