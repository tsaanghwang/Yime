# Independent, externally pinned build evidence; never an execution authorization.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:ReceiptCandidate=$null
function Initialize-ExecutableReceipt {
    if($null -eq $script:ReceiptCandidate){$script:ReceiptCandidate=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -Scope Local -PassThru}
}
function Assert-ExecutableReceipt($r){
    Initialize-ExecutableReceipt
    & $script:ReceiptCandidate {param($r)
        Assert-CandidateObject $r @('schema_version','product','product_version','installer','manifest_sha256','source_inventory_sha256','build_sources','compiler_interval','static_payload','makensis_sha256','nsis_toolchain_lock_sha256','signing_complete','installed_acceptance_passed','public_release_admitted')
        foreach($pair in @(@('schema_version','yime-rime-pime-executable-build-receipt-v1'),@('product','rime-pime'))){if($r.($pair[0]) -isnot [string] -or $r.($pair[0]) -cne $pair[1]){throw 'Unsupported executable receipt identity.'}}
        if($r.product_version -isnot [string] -or $r.product_version -cnotmatch '^1\.4\.0-dev\.[1-9][0-9]*$'){throw 'Unsupported executable receipt version.'}
        foreach($name in @('manifest_sha256','source_inventory_sha256','makensis_sha256','nsis_toolchain_lock_sha256')){Assert-CandidateHash $r.$name}
        foreach($name in @('signing_complete','installed_acceptance_passed','public_release_admitted')){if($r.$name -isnot [bool] -or $r.$name){throw 'Development receipt cannot grant signing, acceptance or release.'}}
        Assert-CandidateObject $r.installer @('sha256','bytes');Assert-CandidateHash $r.installer.sha256
        if(($r.installer.bytes -isnot [int] -and $r.installer.bytes -isnot [long]) -or $r.installer.bytes -lt 65536 -or $r.installer.bytes -gt 536870912){throw 'Invalid executable receipt size.'}
        $i=$r.compiler_interval
        Assert-CandidateObject $i @('schema_version','armed_before_baseline','completion_barrier_after_compiler_exit','unexpected_membership_event_count','notification_batch_count','physical_membership_prevention_claimed','active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure','full_nsis_toolchain_input_closure')
        if($i.schema_version -isnot [string] -or $i.schema_version -cne 'yime-rime-pime-nsis-compiler-membership-interval-v1'){throw 'Unsupported compiler interval.'}
        foreach($name in @('armed_before_baseline','completion_barrier_after_compiler_exit')){if($i.$name -isnot [bool] -or -not $i.$name){throw 'Incomplete compiler interval.'}}
        foreach($name in @('physical_membership_prevention_claimed','active_same_sid_transient_tree_membership_interference_excluded','nsis_non_os_compiler_input_closure','full_nsis_toolchain_input_closure')){if($i.$name -isnot [bool] -or $i.$name){throw 'Unsupported physical compiler closure claim.'}}
        foreach($name in @('unexpected_membership_event_count','notification_batch_count')){if(($i.$name -isnot [int] -and $i.$name -isnot [long]) -or $i.$name -lt 0){throw 'Invalid compiler event count.'}}
        if($i.unexpected_membership_event_count -ne 0){throw 'Compiler interval observed interference.'}
        Assert-CandidateObject $r.static_payload @('verified','member_count','tree_sha256')
        if($r.static_payload.verified -isnot [bool] -or -not $r.static_payload.verified -or ($r.static_payload.member_count -isnot [int] -and $r.static_payload.member_count -isnot [long]) -or $r.static_payload.member_count -lt 10 -or $r.static_payload.member_count -gt 4098){throw 'Static payload comparison missing.'}
        Assert-CandidateHash $r.static_payload.tree_sha256
        if($r.build_sources -isnot [array] -or $r.build_sources.Count -lt 4 -or $r.build_sources.Count -gt 512){throw 'Missing build source closure.'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($row in $r.build_sources){Assert-CandidateObject $row @('path','bytes','sha256');$null=Get-CandidatePath 'C:\Source' $row.path;Assert-CandidateHash $row.sha256;if(-not $seen.Add($row.path) -or ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 1 -or $row.bytes -gt 16777216){throw 'Invalid build source record.'}}
        foreach($path in @('tools/dual-product/build-rime-pime-executable-candidate.ps1','installer/rime-pime-candidate.nsi','tools/dual-product/rime-pime-executable-receipt.psm1','tools/dual-product/rime-pime-executable-candidate.psm1')){if(-not $seen.Contains($path)){throw 'Executable build source missing.'}}
    } $r
}
function Read-RimePimeExecutableReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)][string]$ExpectedReceiptSha256,
        [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$ExpectedInstallerSha256,
        [Parameter(Mandatory)][string]$ExpectedManifestSha256)
    Initialize-ExecutableReceipt
    $leases=[Collections.Generic.List[object]]::new()
    try{
        $value=& $script:ReceiptCandidate {param($receiptPath,$receiptHash,$installerPath,$installerHash,$manifestHash,$leases)
            foreach($hash in @($receiptHash,$installerHash,$manifestHash)){Assert-CandidateHash $hash};Initialize-CandidateNative
            $verify=$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static')
            $noAds=$script:CandidateNative.GetMethod('RejectNamedStreams',[Reflection.BindingFlags]'NonPublic,Static')
            $openDir=$script:CandidateNative.GetMethod('OpenDirectory',[Reflection.BindingFlags]'NonPublic,Static')
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $records=@()
            foreach($input in @(@($receiptPath,$receiptHash,1048576),@($installerPath,$installerHash,536870912))){
                $full=[IO.Path]::GetFullPath($input[0]);$script:CandidateNative::CanonicalPath($full)
                for($dir=[IO.Path]::GetDirectoryName($full);$dir;$dir=[IO.Path]::GetDirectoryName($dir)){if($seen.Add($dir)){$h=$openDir.Invoke($null,[object[]]@([string]$dir));$leases.Add($h);$null=$verify.Invoke($null,[object[]]@($h,[string]$dir,$true));$null=$noAds.Invoke($null,[object[]]@([string]$dir))}}
                $s=[IO.File]::Open($full,'Open','Read','Read');$leases.Add($s);$id=$verify.Invoke($null,[object[]]@($s.SafeFileHandle,[string]$full,$false));$null=$noAds.Invoke($null,[object[]]@([string]$full))
                if($s.Length -lt 1 -or $s.Length -gt $input[2]){throw 'Executable receipt artifact exceeds bound.'}
                $sha=[Security.Cryptography.SHA256]::Create();try{$digest=([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$s.Position=0}
                if($digest -cne $input[1]){throw 'Executable artifact differs from external digest.'}
                $raw=$null;if($records.Count -eq 0){$m=[IO.MemoryStream]::new();try{$s.CopyTo($m);$raw=$m.ToArray()}finally{$m.Dispose();$s.Position=0}}
                $records+=@([pscustomobject]@{path=$full;bytes=[long]$s.Length;sha256=$digest;file_id=$id;raw=$raw})
            }
            $r=ConvertFrom-CandidateJson $records[0].raw
            [pscustomobject]@{receipt=$r;records=$records}
        } $ReceiptPath $ExpectedReceiptSha256 $InstallerPath $ExpectedInstallerSha256 $ExpectedManifestSha256 $leases
        Assert-ExecutableReceipt $value.receipt
        $r=$value.receipt
        if($r.installer.sha256 -cne $ExpectedInstallerSha256 -or $r.installer.bytes -ne $value.records[1].bytes -or $r.manifest_sha256 -cne $ExpectedManifestSha256){throw 'Executable receipt does not bind the supplied installer and manifest.'}
        [pscustomobject]@{Receipt=$r;Digest=$ExpectedReceiptSha256;InstallerSha256=$ExpectedInstallerSha256;ManifestSha256=$ExpectedManifestSha256;ArtifactIdentities=@($value.records|Select-Object path,bytes,sha256,file_id);execution_authorized=$false;installer_executed=$false;uninstaller_executed=$false}
    }finally{for($i=$leases.Count-1;$i -ge 0;$i--){$leases[$i].Dispose()}}
}
Export-ModuleMember -Function Read-RimePimeExecutableReceipt
