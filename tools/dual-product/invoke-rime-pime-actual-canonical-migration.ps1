[CmdletBinding()]
param(
    [ValidateSet('Plan','Apply','Resume')][string]$Mode='Plan',
    [string]$RepoRoot='',
    [Parameter(Mandatory)][string]$ArchiveRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$AuthorizationPath,
    [string]$HistoricalV1Path,
    [string]$FaultMatrixPs5Path='',
    [string]$FaultMatrixPs7Path=''
)

# DP1-T's dedicated actual-checkout adapter. It publishes only the reviewed,
# disabled Rime/PIME installer identity and its strict receipt. It never runs an
# installer, uninstaller, product process, registry command, signing tool or
# user-data operation.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:AdapterSchema='yime-rime-pime-actual-canonical-adapter-result-v1'
$script:AuthorizationSchema='yime-rime-pime-actual-canonical-authorization-v1'
$script:ShaPattern='^[0-9a-f]{64}$'
$script:ExpectedUserInstruction=[Text.UTF8Encoding]::new($false).GetString([Convert]::FromBase64String(
    '5oyJ6aG65bqP5a6M5oiQIERQMS1TIOS7k+WkluivgeaNruW9kuaho+OAgURQMS1UIOWunumZhei/geenu+mAgumFjeWZqOOAgURQMS1VIOazqOWGjC/lm57mu5ov5Y246L29L1J1bnRpbWUg6Zeo56aB'))
$script:ExactWriteRoles=@(
    'unique-staging-leaves','retained-evidence-objects','retained-evidence-sidecars',
    'successor-installer-stage','successor-installer','pending-intent','canonical-receipt',
    'canonical-sidecar','completed-intent'
)

function Get-Dp1TSha256([string]$Path){
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Dp1TBytes([string]$Path){return [long](Get-Item -LiteralPath $Path).Length}

function Get-Dp1TUtf8Bytes([string]$Text){return [Text.UTF8Encoding]::new($false).GetBytes($Text)}

function Get-Dp1THashBytes([byte[]]$Bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function ConvertTo-Dp1TJsonBytes($Value){
    $json=ConvertTo-Json -InputObject $Value -Depth 40 -Compress
    return Get-Dp1TUtf8Bytes ($json+"`n")
}

function Assert-Dp1TExactProperties($Value,[string[]]$Names,[string]$Context){
    if($null -eq $Value -or $null -eq $Value.PSObject){throw "$Context is not an object."}
    $actual=@($Value.PSObject.Properties | ForEach-Object {
        if($_.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty){
            throw "$Context contains a non-data property."
        }
        [string]$_.Name
    })
    if(($actual -join "`n") -cne ($Names -join "`n")){throw "$Context field set or order is not exact."}
}

function Read-Dp1TJson([string]$Path,[string]$Context){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Context is missing: $Path"}
    $bytes=[IO.File]::ReadAllBytes($Path)
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){
        return $text | ConvertFrom-Json -DateKind String
    }
    return $text | ConvertFrom-Json
}

function Assert-Dp1TNoReparse([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    $cursor=$full
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            $item=Get-Item -LiteralPath $cursor -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Reparse paths are not allowed: $cursor"
            }
        }
        $parent=Split-Path -Parent $cursor
        if(-not $parent -or $parent -eq $cursor){break}
        $cursor=$parent
    }
}

function Resolve-Dp1TActualRoot([string]$Value){
    $expected=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
    $actual=[IO.Path]::GetFullPath($Value).TrimEnd('\')
    if($actual -ine $expected -or -not(Test-Path -LiteralPath (Join-Path $actual '.git'))){
        throw 'DP1-T actual migration is bound to the checkout containing this adapter.'
    }
    Assert-Dp1TNoReparse $actual
    Assert-Dp1TNoReparse (Join-Path $actual 'installer')
    return $actual
}

function Resolve-Dp1TOutputRoot([string]$Root,[string]$Value){
    $outer=[IO.Path]::GetFullPath((Join-Path $Root '.tmp\dual-product')).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Value).TrimEnd('\')
    if(-not $full.StartsWith($outer+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $full) -cnotmatch '^dp1-t-[A-Za-z0-9._-]+$'){
        throw 'DP1-T output must be a fresh .tmp/dual-product/dp1-t-* directory.'
    }
    if(Test-Path -LiteralPath $full){throw 'DP1-T output already exists.'}
    New-Item -ItemType Directory -Path $full | Out-Null
    Assert-Dp1TNoReparse $full
    return $full
}

function Read-Dp1TArchive([string]$Root){
    $full=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fixed=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Yime Rime-PIME Evidence Archives\DP1-S')).TrimEnd('\')
    if(-not $full.StartsWith($fixed+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $full) -cnotmatch '^[0-9a-f]{64}\.capsule$'){
        throw 'DP1-T requires a content-addressed capsule below the fixed DP1-S external archive root.'
    }
    Assert-Dp1TNoReparse $full
    $manifestPath=Join-Path $full 'manifest.json'
    $sidecarPath=$manifestPath+'.sha256'
    $manifest=Read-Dp1TJson $manifestPath 'archive manifest'
    $sidecar=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sidecarPath))
    $digest=Get-Dp1TSha256 $manifestPath
    if($sidecar -cnotmatch '\A([0-9a-f]{64})  manifest\.json(?:\r\n|\n)?\z' -or $Matches[1] -cne $digest){
        throw 'Archive manifest sidecar is invalid.'
    }
    if([string]$manifest.schema_version -cne 'yime-rime-pime-candidate-evidence-archive-manifest-v1' -or
        [string]$manifest.product -cne 'rime-pime' -or [string]$manifest.archive_id+'.capsule' -cne (Split-Path -Leaf $full)){
        throw 'Archive identity is invalid.'
    }
    $receiptRows=@($manifest.artifacts | Where-Object {[string]$_.kind -ceq 'retained-v2-receipt'})
    $installerRows=@($manifest.artifacts | Where-Object {[string]$_.kind -ceq 'candidate-installer'})
    if($receiptRows.Count -ne 1 -or $installerRows.Count -ne 1){throw 'Archive successor identities are not unique.'}
    foreach($row in @($manifest.artifacts)){
        $sha=[string]$row.sha256
        if($sha -cnotmatch $script:ShaPattern -or [long]$row.bytes -lt 1){throw 'Archive artifact identity is invalid.'}
        $object=Join-Path $full ('objects\sha256\'+$sha.Substring(0,2)+'\'+$sha+'.blob')
        if(-not(Test-Path -LiteralPath $object -PathType Leaf) -or (Get-Dp1TSha256 $object) -cne $sha -or
            (Get-Dp1TBytes $object) -ne [long]$row.bytes){throw 'Archive object differs from its manifest.'}
    }
    return [pscustomobject]@{Root=$full;Manifest=$manifest;ManifestPath=$manifestPath;ManifestSha256=$digest;
        Receipt=$receiptRows[0];Installer=$installerRows[0]}
}

function Get-Dp1TModule([string]$Root){
    return Import-Module (Join-Path $Root 'tools\dual-product\rime-pime-installer-receipt-transaction.psm1') `
        -Force -PassThru
}

function Read-Dp1TStrictReceipt($Module,[string]$Root,[string]$Path){
    return & $Module {param($r,$p) Read-RimePimePackageBuildReceiptV2 $r $p} $Root $Path
}

function Get-Dp1TFileRecord([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return [ordered]@{path=$Path;present=$false}}
    return [ordered]@{path=$Path;present=$true;bytes=Get-Dp1TBytes $Path;sha256=Get-Dp1TSha256 $Path}
}

function Get-Dp1TActualSnapshot([string]$Root,$OldReceipt,$Archive){
    $installer=Join-Path $Root ([string]$OldReceipt.Receipt.installer.path).Replace('/','\')
    $successor=Join-Path $Root ([string]$Archive.Manifest.installer_path).Replace('/','\')
    $pending=Join-Path $Root 'installer\receipt-evidence\pending.json'
    $records=@(
        Get-Dp1TFileRecord (Join-Path $Root 'installer\package-build-receipt.json')
        Get-Dp1TFileRecord (Join-Path $Root 'installer\package-build-receipt.json.sha256')
        Get-Dp1TFileRecord $installer
        Get-Dp1TFileRecord $successor
        Get-Dp1TFileRecord $pending
    )
    return Get-Dp1THashBytes (ConvertTo-Dp1TJsonBytes ([ordered]@{schema_version='yime-rime-pime-actual-canonical-snapshot-v1';records=$records}))
}

function Get-Dp1TSourceSet([string]$Root){
    $paths=@(
        'tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1',
        'tools/dual-product/rime-pime-installer-receipt-transaction.ps1',
        'tools/dual-product/rime-pime-installer-receipt-transaction.psm1',
        'tools/dual-product/rime-pime-package-receipt-v2.ps1',
        'tools/dual-product/rime-pime-receipt-v2-store.ps1'
    )
    $rows=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=Get-Dp1TSha256 (Join-Path $Root $_)}})
    $digest=Get-Dp1THashBytes (ConvertTo-Dp1TJsonBytes $rows)
    return [pscustomobject]@{Rows=$rows;Digest=$digest}
}

function Get-Dp1TFaultMatrix([string]$Ps5Path,[string]$Ps7Path){
    if(-not $Ps5Path -and -not $Ps7Path){
        return [pscustomobject]@{Verified=$false;Digest=('0'*64);Ps5Sha256=('0'*64);Ps7Sha256=('0'*64)}
    }
    if(-not $Ps5Path -or -not $Ps7Path){throw 'Both PS5 and PS7 full fault-matrix results are required together.'}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($pair in @(@('ps5',$Ps5Path),@('ps7',$Ps7Path))){
        $full=[IO.Path]::GetFullPath([string]$pair[1])
        $value=Read-Dp1TJson $full ($pair[0]+' fault matrix')
        if([string]$value.schema_version -cne 'yime-rime-pime-installer-receipt-transaction-test-v1' -or
            $value.full_suite_executed -isnot [bool] -or -not [bool]$value.full_suite_executed -or
            $value.all_executed_checks_passed -isnot [bool] -or -not [bool]$value.all_executed_checks_passed -or
            [long]$value.failed -ne 0 -or [long]$value.total -ne [long]$value.expected_check_count){
            throw ($pair[0]+' fault matrix is not a passing full suite.')
        }
        $sha=Get-Dp1TSha256 $full
        $rows.Add([ordered]@{shell=[string]$pair[0];sha256=$sha;bytes=Get-Dp1TBytes $full})
    }
    return [pscustomobject]@{Verified=$true;Digest=Get-Dp1THashBytes (ConvertTo-Dp1TJsonBytes @($rows));
        Ps5Sha256=[string]$rows[0].sha256;Ps7Sha256=[string]$rows[1].sha256}
}

function Get-Dp1TPlan([string]$Root,$Archive,$Old,$SourceSet,$FaultMatrix,[string]$Snapshot){
    $oldInstaller=[string]$Old.Receipt.installer.path
    $plan=[ordered]@{
        schema_version='yime-rime-pime-actual-canonical-migration-plan-v1'
        affected_product='rime-pime'
        actual_repo_root=$Root
        adapter_path='tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1'
        adapter_sha256=Get-Dp1TSha256 (Join-Path $Root 'tools\dual-product\invoke-rime-pime-actual-canonical-migration.ps1')
        adapter_source_set_sha256=$SourceSet.Digest
        fault_matrix_sha256=$FaultMatrix.Digest
        fault_matrix_ps5_sha256=$FaultMatrix.Ps5Sha256
        fault_matrix_ps7_sha256=$FaultMatrix.Ps7Sha256
        archive_root=$Archive.Root
        archive_manifest_sha256=$Archive.ManifestSha256
        expected_actual_snapshot_sha256=$Snapshot
        expected_old_receipt_sha256=[string]$Old.Digest
        expected_old_installer_path=$oldInstaller
        expected_old_installer_sha256=[string]$Old.Receipt.installer.sha256
        expected_successor_receipt_sha256=[string]$Archive.Receipt.sha256
        expected_successor_installer_path=[string]$Archive.Manifest.installer_path
        expected_successor_installer_sha256=[string]$Archive.Installer.sha256
        write_set_roles=$script:ExactWriteRoles
        installer_or_uninstaller_execution_in_scope=$false
        registry_or_product_process_action_in_scope=$false
        installed_yimecore_local12_action_in_scope=$false
        production_user_data_access_in_scope=$false
        hardware_power_loss_recovery_verified=$false
        directory_metadata_durability_verified=$false
        hostile_same_sid_replacement_prevented=$false
    }
    $bytes=ConvertTo-Dp1TJsonBytes $plan
    return [pscustomobject]@{Value=[pscustomobject]$plan;Bytes=$bytes;Digest=Get-Dp1THashBytes $bytes}
}

function Assert-Dp1TAuthorization([string]$Path,$Plan){
    if(-not $Path){throw 'Apply and Resume require an exact one-time authorization record.'}
    $full=[IO.Path]::GetFullPath($Path)
    $allowed=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Yime Rime-PIME Evidence Archives\DP1-T\authorizations')).TrimEnd('\')
    if(-not $full.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Authorization record is outside the fixed DP1-T authorization directory.'}
    Assert-Dp1TNoReparse $full
    $auth=Read-Dp1TJson $full 'authorization record'
    $fields=@('schema_version','authorization_kind','authorization_id','explicit_user_authorization',
        'one_time_authorization','user_instruction','repo_root','scope','migration_plan_sha256',
        'old_receipt_sha256','successor_receipt_sha256','successor_installer_sha256',
        'actual_snapshot_sha256','archive_manifest_sha256','adapter_sha256','adapter_source_set_sha256')
    Assert-Dp1TExactProperties $auth $fields 'authorization record'
    if([string]$auth.schema_version -cne $script:AuthorizationSchema -or
        [string]$auth.authorization_kind -cne 'one-time-actual-canonical-artifact-migration' -or
        $auth.explicit_user_authorization -isnot [bool] -or -not [bool]$auth.explicit_user_authorization -or
        $auth.one_time_authorization -isnot [bool] -or -not [bool]$auth.one_time_authorization -or
        [string]$auth.scope -cne 'actual-canonical-artifacts-only' -or
        [string]$auth.user_instruction -cne $script:ExpectedUserInstruction){
        throw 'Authorization record does not carry the exact user-approved migration scope.'
    }
    $digest=Get-Dp1TSha256 $full
    $sidecar=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($full+'.sha256'))
    if($sidecar -cnotmatch '\A([0-9a-f]{64})  [^\\\r\n]+(?:\r\n|\n)?\z' -or $Matches[1] -cne $digest){throw 'Authorization sidecar is invalid.'}
    if($null -ne $Plan){
        $bindings=@{
            repo_root=$Plan.Value.actual_repo_root;migration_plan_sha256=$Plan.Digest
            old_receipt_sha256=$Plan.Value.expected_old_receipt_sha256
            successor_receipt_sha256=$Plan.Value.expected_successor_receipt_sha256
            successor_installer_sha256=$Plan.Value.expected_successor_installer_sha256
            actual_snapshot_sha256=$Plan.Value.expected_actual_snapshot_sha256
            archive_manifest_sha256=$Plan.Value.archive_manifest_sha256
            adapter_sha256=$Plan.Value.adapter_sha256;adapter_source_set_sha256=$Plan.Value.adapter_source_set_sha256
        }
        foreach($name in $bindings.Keys){if([string]$auth.$name -cne [string]$bindings[$name]){throw "Authorization binding mismatch: $name"}}
    }
    return [pscustomobject]@{Value=$auth;Path=$full;Digest=$digest}
}

function Initialize-Dp1TNativeMove{
    if(-not('YimeDp1T.Native' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YimeDp1T { public static class Native {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern bool MoveFileEx(string source, string destination, uint flags);
}}
'@}
}

function Copy-Dp1TNoReplace([string]$Source,[string]$Destination,[string]$Sha,[long]$Bytes){
    if(Test-Path -LiteralPath $Destination){
        if((Get-Dp1TSha256 $Destination) -cne $Sha -or (Get-Dp1TBytes $Destination) -ne $Bytes){throw 'Existing retained object differs.'}
        return $false
    }
    $parent=Split-Path -Parent $Destination
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    Assert-Dp1TNoReparse $parent
    $temp=Join-Path $parent ('.dp1-t-writing-'+[guid]::NewGuid().ToString('N'))
    $input=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $output=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::WriteThrough)
    try{$input.CopyTo($output);$output.Flush($true)}finally{$output.Dispose();$input.Dispose()}
    if((Get-Dp1TSha256 $temp) -cne $Sha -or (Get-Dp1TBytes $temp) -ne $Bytes){throw 'Copied retained object differs.'}
    Initialize-Dp1TNativeMove
    if(-not[YimeDp1T.Native]::MoveFileEx($temp,$Destination,8)){
        $error=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if(Test-Path -LiteralPath $Destination -PathType Leaf -and (Get-Dp1TSha256 $Destination) -ceq $Sha){Remove-Item -LiteralPath $temp -Force;return $false}
        throw [ComponentModel.Win32Exception]::new($error)
    }
    return $true
}

function Copy-Dp1TArchiveObjects([string]$Root,$Archive){
    $copied=0
    $objectRoot=Join-Path $Archive.Root 'objects\sha256'
    foreach($blob in @(Get-ChildItem -LiteralPath $objectRoot -Recurse -File -Filter '*.blob' | Sort-Object FullName)){
        $sha=$blob.BaseName
        if($sha -cnotmatch $script:ShaPattern){throw 'Archive object leaf is invalid.'}
        $destination=Join-Path $Root ('installer\receipt-evidence\sha256\'+$sha.Substring(0,2)+'\'+$sha+'.blob')
        if(Copy-Dp1TNoReplace $blob.FullName $destination $sha ([long]$blob.Length)){$copied++}
        $sourceSidecar=$blob.FullName+'.sha256'
        $sidecarSha=Get-Dp1TSha256 $sourceSidecar
        if(Copy-Dp1TNoReplace $sourceSidecar ($destination+'.sha256') $sidecarSha (Get-Dp1TBytes $sourceSidecar)){$copied++}
    }
    return $copied
}

if(-not $RepoRoot){$RepoRoot=Join-Path $PSScriptRoot '..\..'}
$root=Resolve-Dp1TActualRoot $RepoRoot
$out=Resolve-Dp1TOutputRoot $root $OutputRoot
$archive=Read-Dp1TArchive $ArchiveRoot
$module=Get-Dp1TModule $root
try{
    $canonical=Join-Path $root 'installer\package-build-receipt.json'
    $pending=Join-Path $root 'installer\receipt-evidence\pending.json'
    $authorizationCandidate=$null
    if($Mode -ne 'Plan'){$authorizationCandidate=Assert-Dp1TAuthorization $AuthorizationPath $null}
    $current=Read-Dp1TStrictReceipt $module $root $canonical
    $recovering=[bool]($null -ne $authorizationCandidate -and
        ((Test-Path -LiteralPath $pending) -or
         [string]$current.Digest -ceq [string]$authorizationCandidate.Value.successor_receipt_sha256))
    if($recovering){
        $originalDigest=[string]$authorizationCandidate.Value.old_receipt_sha256
        $originalObject=Join-Path $root ('installer\receipt-evidence\sha256\'+$originalDigest.Substring(0,2)+'\'+$originalDigest+'.blob')
        $old=Read-Dp1TStrictReceipt $module $root $originalObject
        if([string]$old.Digest -cne $originalDigest){throw 'Recovery old receipt object differs from authorization.'}
        $snapshot=[string]$authorizationCandidate.Value.actual_snapshot_sha256
    }else{
        $old=$current
        $snapshot=Get-Dp1TActualSnapshot $root $old $archive
    }
    $oldInstaller=Join-Path $root ([string]$old.Receipt.installer.path).Replace('/','\')
    if((Get-Dp1TSha256 $oldInstaller) -cne [string]$old.Receipt.installer.sha256 -or
        (Get-Dp1TBytes $oldInstaller) -ne [long]$old.Receipt.installer.bytes){throw 'Old physical installer differs from its strict receipt.'}
$sourceSet=Get-Dp1TSourceSet $root
$faultMatrix=Get-Dp1TFaultMatrix $FaultMatrixPs5Path $FaultMatrixPs7Path
$plan=Get-Dp1TPlan $root $archive $old $sourceSet $faultMatrix $snapshot
    [IO.File]::WriteAllBytes((Join-Path $out 'migration-plan.json'),$plan.Bytes)
    [IO.File]::WriteAllText((Join-Path $out 'migration-plan.json.sha256'),$plan.Digest+'  migration-plan.json'+"`n",[Text.UTF8Encoding]::new($false))

    $authorization=$null
    $copied=0
    $transactionDisposition='not-run'
    $resultReceipt=$old
    if($Mode -ne 'Plan'){
        if(-not $faultMatrix.Verified){throw 'Apply and Resume require passing full PS5 and PS7 fault matrices.'}
        $authorization=Assert-Dp1TAuthorization $AuthorizationPath $plan
        if(-not $HistoricalV1Path){throw 'Apply and Resume require the exact old historical v1 receipt path.'}
        $historical=[IO.Path]::GetFullPath($HistoricalV1Path)
        if(-not $historical.StartsWith(([IO.Path]::GetFullPath((Join-Path $root '.tmp\dual-product')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -or
            (Get-Dp1TSha256 $historical) -cne [string]$old.Receipt.predecessor_v1.sha256){throw 'Historical v1 receipt does not match the old canonical predecessor.'}
        $copied=Copy-Dp1TArchiveObjects $root $archive
        $successorObject=Join-Path $root ('installer\receipt-evidence\sha256\'+([string]$archive.Receipt.sha256).Substring(0,2)+'\'+[string]$archive.Receipt.sha256+'.blob')
        $successor=Read-Dp1TStrictReceipt $module $root $successorObject
        if([string]$successor.Digest -cne [string]$archive.Receipt.sha256){throw 'Seeded successor receipt differs from the archive.'}
        if($Mode -ceq 'Resume' -or (Test-Path -LiteralPath $pending) -or
            [string]$current.Digest -ceq [string]$archive.Receipt.sha256){
            $resultReceipt=& $module {param($r) Resume-RimePimeInstallerReceiptTransactionActual -RepoRoot $r} $root
            $transactionDisposition='resumed'
        }else{
            $resultReceipt=& $module {param($r,$n,$o,$h) Publish-RimePimeInstallerReceiptTransactionActual `
                -RepoRoot $r -NextReceiptDigest $n -ExpectedPreviousDigest $o -HistoricalV1Path $h} `
                $root ([string]$archive.Receipt.sha256) ([string]$old.Digest) $historical
            $transactionDisposition='published'
        }
    }
    $final=Read-Dp1TStrictReceipt $module $root $canonical
    $migrated=[bool]($final.Digest -ceq [string]$archive.Receipt.sha256)
    $result=[ordered]@{
        schema_version=$script:AdapterSchema;generated_at_utc=[DateTime]::UtcNow.ToString('o')
        affected_product='rime-pime';mode=$Mode;status='pass';actual_repo_root=$root
        archive_manifest_sha256=$archive.ManifestSha256;migration_plan_sha256=$plan.Digest
        fault_matrix_sha256=$faultMatrix.Digest;fault_matrix_ps5_sha256=$faultMatrix.Ps5Sha256
        fault_matrix_ps7_sha256=$faultMatrix.Ps7Sha256
        adapter_sha256=$plan.Value.adapter_sha256;adapter_source_set_sha256=$sourceSet.Digest
        authorization_id=if($authorization){[string]$authorization.Value.authorization_id}else{''}
        authorization_record_sha256=if($authorization){[string]$authorization.Digest}else{''}
        expected_old_receipt_sha256=[string]$old.Digest
        expected_successor_receipt_sha256=[string]$archive.Receipt.sha256
        final_canonical_receipt_sha256=[string]$final.Digest
        expected_successor_installer_sha256=[string]$archive.Installer.sha256
        actual_snapshot_sha256=$snapshot;write_set_roles=$script:ExactWriteRoles
        archive_object_leaves_copied=[long]$copied;transaction_disposition=$transactionDisposition
        actual_canonical_migration_admitted=[bool]($Mode -ne 'Plan')
        actual_canonical_migrated=$migrated
        old_installer_preserved=(Test-Path -LiteralPath $oldInstaller -PathType Leaf)
        successor_installer_published=(Test-Path -LiteralPath (Join-Path $root ([string]$archive.Manifest.installer_path).Replace('/','\')) -PathType Leaf)
        dp1n_fixture_gate_preserved=$true;fixture_api_rejects_actual_checkout=$true
        installer_or_uninstaller_executed=$false;registry_or_product_process_touched=$false
        default_input_method_touched=$false;production_user_data_read_or_written=$false
        installed_yimecore_local12_touched=$false;hardware_power_loss_recovery_verified=$false
        directory_metadata_durability_verified=$false;hostile_same_sid_replacement_prevented=$false
        dp1_complete=$false;dp2_complete=$false;dp3_complete=$false
    }
    $resultBytes=ConvertTo-Dp1TJsonBytes $result
    $resultPath=Join-Path $out 'result.json'
    [IO.File]::WriteAllBytes($resultPath,$resultBytes)
    $digest=Get-Dp1THashBytes $resultBytes
    [IO.File]::WriteAllText($resultPath+'.sha256',$digest+'  result.json'+"`n",[Text.UTF8Encoding]::new($false))
    Write-Host "PASS: DP1-T $Mode. Evidence: $resultPath ($digest)"
}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
