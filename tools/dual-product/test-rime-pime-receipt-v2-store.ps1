[CmdletBinding()]
param([string]$OutputRoot,[string]$WorkerCasePath,[string]$Phase,[string]$CheckPattern='*')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
if ($WorkerCasePath) {
    $full=[IO.Path]::GetFullPath($WorkerCasePath)
    if (-not $full.StartsWith((Join-Path $repo '.tmp\dual-product\dp1-package-receipt-v2-test-'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Worker is fixture-only.' }
    Import-Module (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.psm1') -Force
    $case=[IO.File]::ReadAllText($full)|ConvertFrom-Json
    if (-not ([IO.Path]::GetFullPath($case.Root)).StartsWith((Split-Path -Parent $full)+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Worker root escaped case.' }
    $module=Get-Module rime-pime-package-receipt-v2
    & $module { param($StopPhase)
        $script:StopPhase=$StopPhase
        function script:Invoke-RimePimeReceiptPublicationCheckpoint([string]$Phase) {
            if ($Phase -ceq $script:StopPhase) { [Environment]::Exit(73) }
        }
    } $Phase
    if ($Phase -eq 'recover') {
        $null=Resume-RimePimePackageReceiptV2Publication $case.Root
    } elseif ($Phase -eq 'locked') {
        try { $null=Publish-RimePimePackageReceiptV2Supersession $case.Root $case.Next $case.Before $case.History }
        catch {
            [IO.File]::WriteAllText($full+'.lock-error.txt',($_|Out-String))
            for ($errorValue=$_.Exception;$null -ne $errorValue;$errorValue=$errorValue.InnerException) {
                if (($errorValue.HResult -band 65535) -in @(32,33) -or
                    ($errorValue -is [ComponentModel.Win32Exception] -and $errorValue.NativeErrorCode -in @(32,33))) { exit 74 }
            }
            throw
        }
    } else { $null=Publish-RimePimePackageReceiptV2Supersession $case.Root $case.Next $case.Before $case.History }
    exit 0
}
. (Join-Path $PSScriptRoot 'test-rime-pime-package-receipt-v2.ps1') -OutputRoot $OutputRoot -DefinitionsOnly
function Check([string]$Name,[scriptblock]$Body) {
    if ($Name -notlike $CheckPattern) { return }
    try { & $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true;detail='ok'}) }
    catch { $checks.Add([pscustomobject]@{name=$Name;passed=$false;detail=$_.Exception.Message}) }
}
function New-PublicationCase($Name) {
    $case=New-Case $Name
    $p=Prepare $case
    try { $null=Publish-RimePimePackageReceiptV2 $p $case.V1Path } finally { Close-RimePimePackageReceiptV2Preparation $p }
    $history=Join-Path $case.V2Output 'historical\package-build-receipt-v1.json'
    $next=Join-Path (Split-Path -Parent $case.Root) 'next.json'
    $value=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.V1Path))
    $value.sealed_at_utc='2031-02-03T04:05:06.0000000Z';$null=Seal $value $next
    $case|Add-Member -NotePropertyName Next -NotePropertyValue $next
    $case|Add-Member -NotePropertyName History -NotePropertyValue $history
    $case|Add-Member -NotePropertyName Before -NotePropertyValue (Hash $case.V1Path)
    return $case
}
function Stop-PublicationAtIntent($Case) {
    $module=Get-Module rime-pime-package-receipt-v2
    & $module { function script:Invoke-RimePimeReceiptPublicationCheckpoint($Phase) { if ($Phase -eq 'intent') { throw 'test interruption' } } }
    try { Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $Case.Root $Case.Next $Case.Before $Case.History } '*test interruption*' }
    finally { & $module { function script:Invoke-RimePimeReceiptPublicationCheckpoint($Phase) {} } }
    return Join-Path $Case.Root 'installer\receipt-evidence\pending.json'
}
function Get-TestReceiptObjectPath($Root,[string]$Digest) {
    return Join-Path $Root ('installer\receipt-evidence\sha256\'+$Digest.Substring(0,2)+'\'+$Digest+'.blob')
}
function Save-TestReceiptEvidence($Case,[string]$ReceiptPath) {
    $module=Get-Module rime-pime-package-receipt-v2
    return & $module {
        param($Root,$Path,$History)
        Save-RimePimeReceiptEvidence $Root $Path $History
    } $Case.Root $ReceiptPath $Case.History
}
function Write-TestPendingPublication($Case,[string]$NextReceiptPath) {
    $module=Get-Module rime-pime-package-receipt-v2
    return & $module {
        param($Root,$Canonical,$Next,$History)
        $current=Read-RimePimePackageBuildReceiptV2 $Root $Canonical
        $old=Save-RimePimeReceiptEvidence $Root $Canonical $History
        $new=Save-RimePimeReceiptEvidence $Root $Next $History
        $pending=Join-Path $Root 'installer\receipt-evidence\pending.json'
        $intent=[ordered]@{
            schema_version='yime-rime-pime-retained-publication-v1'
            previous=$current.Digest
            previous_retained=$old.Retained.Digest
            next=$new.Retained.Digest
            installer_path=$new.Retained.Receipt.installer.path
        }
        Write-RimePimeReceiptAtomicBytes $pending ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $intent)+"`n"))
        return [pscustomobject]@{Path=$pending;Intent=$intent}
    } $Case.Root $Case.V1Path $NextReceiptPath $Case.History
}
Check 'module-exports-only-six-explicit-receipt-apis' {
    $expected=@(
        'Close-RimePimePackageReceiptV2Preparation',
        'New-RimePimePackageReceiptV2Preparation',
        'Publish-RimePimePackageReceiptV2',
        'Publish-RimePimePackageReceiptV2Supersession',
        'Read-RimePimePackageBuildReceiptV2',
        'Resume-RimePimePackageReceiptV2Publication'
    ) | Sort-Object
    $actual=@((Get-Module rime-pime-package-receipt-v2).ExportedCommands.Keys | Sort-Object)
    Assert-True (($actual -join "`n") -ceq ($expected -join "`n")) ('Unexpected receipt-v2 exports: '+($actual -join ', '))
}
Check 'retained-evidence-survives-source-removal-and-repeated-v2-supersession' {
    $c=New-PublicationCase 'retain'
    $r=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
    Assert-True $r.Receipt.evidence_artifacts_durable 'Retention not recorded.'
    Assert-True (-not $r.Receipt.delivery_admitted) 'Delivery gate changed.'
    # Rename fixture sources, including the entire transient evidence tree.
    [IO.Directory]::Move((Join-Path $c.Root '.tmp'),(Join-Path $c.Root 'retired-transient'))
    [IO.File]::Move((Join-Path $c.Root 'installer\package-plan.json'),(Join-Path $c.Root 'old-plan.json'))
    [IO.File]::Move((Join-Path $c.Root 'installer\installer.nsi'),(Join-Path $c.Root 'old-source.nsi'))
    $read=Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path
    Assert-True ($read.Digest -ceq $r.Digest) 'Reader still depends on original evidence.'
    $r2=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.V1Path $r.Digest
    Assert-True ($r2.Digest -ceq $r.Digest) 'Idempotent retained publication changed bytes.'
}
foreach ($stop in @('object-temp','object-data','objects','intent-temp','intent','receipt','sidecar','complete')) {
    Check ('hard-exit-'+$stop+'-fresh-process-recovery') {
        $c=New-PublicationCase ('crash-'+$stop)
        $config=Join-Path (Split-Path -Parent $c.Root) 'worker.json'
        [IO.File]::WriteAllText($config,($c|ConvertTo-Json -Depth 20))
        $exe=(Get-Process -Id $PID).Path
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$config+'" -Phase '+$stop
        $child=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        Assert-True ($child.ExitCode -eq 73) ('Child did not stop at '+$stop)
        if ($stop -in @('object-temp','object-data','objects','intent-temp')) {
            Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Pre-intent interruption changed canonical.'
            $null=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
        } else {
            # Recovery runs in a new process, without parent/module state.
            $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$config+'" -Phase recover'
            $recovery=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
            Assert-True ($recovery.ExitCode -eq 0) 'Independent recovery process failed.'
        }
        $read=Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path
        Assert-True $read.Receipt.evidence_artifacts_durable 'Replay did not commit retained v2.'
        Assert-True (-not(Test-Path (Join-Path $c.Root 'installer\receipt-evidence\pending.json'))) 'Replay left pending transaction.'
        $again=Resume-RimePimePackageReceiptV2Publication $c.Root
        Assert-True ($again.Digest -ceq $read.Digest) 'Replay not idempotent.'
    }
}
Check 'shared-lock-blocks-supersession' {
    $c=New-PublicationCase 'lock'
    $module=Get-Module rime-pime-package-receipt-v2
    $lock=& $module { param($Installer,$Receipt) Open-RimePimePublicationLock $Installer $Receipt } $c.Installer $c.V1Path
    try {
        Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History }
        $config=Join-Path (Split-Path -Parent $c.Root) 'worker.json'
        [IO.File]::WriteAllText($config,($c|ConvertTo-Json -Depth 20))
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$config+'" -Phase locked'
        $child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        Assert-True ($child.ExitCode -eq 74) 'Independent process did not observe publication lock.'
    }
    finally { $lock.Stream.Dispose() }
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Busy lock changed receipt.'
}
Check 'stale-cas-and-v1-downgrade-rejected' {
    $c=New-PublicationCase 'cas'
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next ('0'*64) $c.History } '*Stale*'
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.History $c.Before $c.History }
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Rejected update changed receipt.'
}
Check 'changed-successor-with-legacy-v2-build-evidence-is-rejected' {
    $c=New-PublicationCase 'legacy-next'
    $null=Convert-ReceiptFileToHistoricalV2 $c $c.Next 'legacy-next-build.json'
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History } '*membership-interval build evidence*'
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Rejected legacy successor changed the canonical receipt.'
}
Check 'pending-resume-rejects-changed-legacy-v2-successor' {
    $c=New-PublicationCase 'legacy-resume'
    $null=Convert-ReceiptFileToHistoricalV2 $c $c.Next 'legacy-resume-build.json'
    $pending=Write-TestPendingPublication $c $c.Next
    Assert-True ($pending.Intent.next -cne $pending.Intent.previous_retained) 'Fixture did not create a changed successor intent.'
    Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*membership-interval build evidence*'
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Rejected legacy recovery changed the canonical receipt.'
    Assert-True (Test-Path -LiteralPath $pending.Path -PathType Leaf) 'Rejected legacy recovery removed its pending evidence.'
}
Check 'pending-receipt-switched-resume-rejects-changed-legacy-v2-successor-without-writing' {
    $c=New-PublicationCase 'legacy-resume-receipt'
    $null=Convert-ReceiptFileToHistoricalV2 $c $c.Next 'legacy-resume-receipt-build.json'
    $pending=Write-TestPendingPublication $c $c.Next
    Assert-True ($pending.Intent.next -cne $pending.Intent.previous_retained) 'Fixture did not create a changed successor intent.'
    $nextObject=Get-TestReceiptObjectPath $c.Root $pending.Intent.next
    [IO.File]::WriteAllBytes($c.V1Path,[IO.File]::ReadAllBytes($nextObject))
    $receiptBefore=[IO.File]::ReadAllBytes($c.V1Path)
    $sidecarBefore=[IO.File]::ReadAllBytes($c.V1Path+'.sha256')
    Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*membership-interval build evidence*'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($c.V1Path)) -ceq [Convert]::ToBase64String($receiptBefore)) 'Rejected legacy recovery rewrote the switched receipt leaf.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($c.V1Path+'.sha256')) -ceq [Convert]::ToBase64String($sidecarBefore)) 'Rejected legacy recovery rewrote the old sidecar leaf.'
    Assert-True (Test-Path -LiteralPath $pending.Path -PathType Leaf) 'Rejected legacy recovery removed its pending evidence.'
}
Check 'tagged-current-summary-cannot-mask-bound-legacy-build' {
    $c=New-PublicationCase 'legacy-masked'
    $null=Convert-ReceiptFileToHistoricalV2 $c $c.Next 'legacy-masked-build.json'
    $masked=ConvertFrom-TestJson ([IO.File]::ReadAllText($c.Next))
    $masked.disabled_build.schema_version=$currentBuildSchema
    $null=Seal $masked $c.Next
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next } '*open or incomplete schema*'
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History } '*open or incomplete schema*'
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Masked legacy successor changed the canonical receipt.'
}
Check 'same-digest-retention-only-historical-v2-remains-readable' {
    $c=New-PublicationCase 'legacy-same'
    $null=Convert-ReceiptFileToHistoricalV2 $c $c.Next 'legacy-same-build.json'
    $saved=Save-TestReceiptEvidence $c $c.Next
    $legacyDigest=Seal $saved.Retained.Receipt $c.V1Path
    Assert-True ($legacyDigest -ceq $saved.Retained.Digest) 'Fixture did not install the exact retained historical receipt.'
    $before=Hash $c.V1Path
    $read=Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path
    Assert-True ([string]$read.Receipt.disabled_build.schema_version -ceq $legacyBuildSchema) 'Historical retained receipt was not readable.'
    $again=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.V1Path $before $c.History
    Assert-True ($again.Digest -ceq $before) 'Same-digest historical retention-only publication changed bytes.'
}
Check 'corrupt-retained-object-fails-closed' {
    $c=New-PublicationCase 'corrupt'
    $r=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
    $path=Get-TestReceiptObjectPath $c.Root $r.Receipt.disabled_build.result_sha256
    [IO.File]::WriteAllText($path,'tampered')
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path }
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.V1Path $r.Digest }
}
Check 'missing-retained-object-sidecar-fails-closed' {
    $c=New-PublicationCase 'missing-object-sidecar'
    $r=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
    $path=Get-TestReceiptObjectPath $c.Root $r.Receipt.installer.source_sha256
    [IO.File]::Delete($path+'.sha256')
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path } '*sidecar is missing*'
}
Check 'corrupt-retained-object-sidecar-fails-closed' {
    $c=New-PublicationCase 'corrupt-object-sidecar'
    $r=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
    $path=Get-TestReceiptObjectPath $c.Root $r.Receipt.installer.sha256
    [IO.File]::WriteAllText($path+'.sha256',(('0'*64)+'  '+[IO.Path]::GetFileName($path)+"`n"),[Text.Encoding]::ASCII)
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path } '*does not bind*'
}
Check 'false-retention-claim-without-objects-rejected' {
    $c=New-PublicationCase 'false-retention'
    $value=(Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next).Receipt
    $value.evidence_artifacts_durable=$true;$null=Seal $value $c.Next
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next }
}
Check 'hardlinked-retained-object-rejected' {
    $c=New-PublicationCase 'hardlink'
    $r=Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History
    $path=Get-TestReceiptObjectPath $c.Root $r.Receipt.disabled_build.result_sha256
    $null=New-Item -ItemType HardLink -Path ($path+'.alias') -Target $path
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path } '*Hard-linked*'
}
Check 'pending-blocks-successor-and-rejects-unrelated-canonical-bytes' {
    $c=New-PublicationCase 'pending'
    $null=Stop-PublicationAtIntent $c
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History } '*requires explicit recovery*'
    [IO.File]::WriteAllText($c.V1Path,'unrelated receipt')
    $before=Hash $c.V1Path
    Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*conflicts*'
    Assert-True ((Hash $c.V1Path) -ceq $before) 'Recovery overwrote unrelated state.'
}
foreach ($ending in @('multiple-newlines','lone-carriage-return')) {
    Check ('malformed-canonical-sidecar-rejected-'+$ending) {
        $c=New-PublicationCase ('sidecar-format-'+@('multiple-newlines','lone-carriage-return').IndexOf($ending))
        $null=Stop-PublicationAtIntent $c
        $marker=$c.V1Path+'.sha256'
        $text=[IO.File]::ReadAllText($marker).TrimEnd("`r","`n")
        if ($ending -eq 'multiple-newlines') { $text+="`n`n" } else { $text+="`r" }
        [IO.File]::WriteAllText($marker,$text,[Text.Encoding]::ASCII)
        $before=Hash $c.V1Path
        Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*sidecar is malformed*'
        Assert-True ((Hash $c.V1Path) -ceq $before) 'Malformed sidecar recovery changed canonical receipt.'
    }
}
foreach ($bad in @('duplicate','case-duplicate','escaped-duplicate','comment','trailing-comma')) {
    Check ('strict-intent-json-rejects-'+$bad) {
        $c=New-PublicationCase ('intent-json-'+@('duplicate','case-duplicate','escaped-duplicate','comment','trailing-comma').IndexOf($bad))
        $pending=Stop-PublicationAtIntent $c
        $json=[IO.File]::ReadAllText($pending)
        $prefix=switch ($bad) {
            'duplicate' { '"schema_version":"yime-rime-pime-retained-publication-v1",' }
            'case-duplicate' { '"SCHEMA_VERSION":"yime-rime-pime-retained-publication-v1",' }
            'escaped-duplicate' { '"\u0073chema_version":"yime-rime-pime-retained-publication-v1",' }
            'comment' { '/* comment */' }
            'trailing-comma' { '' }
        }
        if ($bad -eq 'trailing-comma') { $json=$json.TrimEnd().TrimEnd('}')+',}' }
        else { $json=$json.Insert($json.IndexOf('{')+1,$prefix) }
        [IO.File]::WriteAllText($pending,$json,[Text.UTF8Encoding]::new($false))
        $before=Hash $c.V1Path
        Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*Invalid or ambiguous receipt JSON*'
        Assert-True ((Hash $c.V1Path) -ceq $before) 'Invalid intent changed canonical receipt.'
    }
}
Check 'intent-rejects-non-string-member' {
    $c=New-PublicationCase 'intent-type'
    $pending=Stop-PublicationAtIntent $c
    $intent=ConvertFrom-TestJson ([IO.File]::ReadAllText($pending))
    $intent.installer_path=@([string]$intent.installer_path)
    [IO.File]::WriteAllText($pending,(ConvertTo-Json $intent -Compress),[Text.UTF8Encoding]::new($false))
    $before=Hash $c.V1Path
    Assert-Rejected { Resume-RimePimePackageReceiptV2Publication $c.Root } '*Invalid receipt publication intent*'
    Assert-True ((Hash $c.V1Path) -ceq $before) 'Non-string intent changed canonical receipt.'
}
Check 'sidecar-sharing-failure-leaves-recoverable-intent' {
    $c=New-PublicationCase 'write-failure'
    $module=Get-Module rime-pime-package-receipt-v2
    & $module { param($Path)
        $script:FailureLeaf=$Path
        function script:Invoke-RimePimeReceiptPublicationCheckpoint($Phase) {
            if ($Phase -eq 'receipt') {
                $script:FailureLease=[IO.File]::Open($script:FailureLeaf,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            }
        }
    } ($c.V1Path+'.sha256')
    try { Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History } }
    finally { & $module {
        if ($script:FailureLease) { $script:FailureLease.Dispose() }
        function script:Invoke-RimePimeReceiptPublicationCheckpoint($Phase) {}
    } }
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.V1Path } '*sidecar does not match*'
    $read=Resume-RimePimePackageReceiptV2Publication $c.Root
    Assert-True $read.Receipt.evidence_artifacts_durable 'Sharing failure was not recovered.'
}
foreach ($field in @('product_version','copied_file_count','generated_uninstaller_bytes')) {
    Check ('reader-rejects-resealed-summary-contradiction-'+$field) {
        $c=New-PublicationCase ('summary-'+(@('product_version','copied_file_count','generated_uninstaller_bytes').IndexOf($field)))
        $r=(Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next).Receipt
        switch ($field) {
            'product_version' { $r.product_version='different-version' }
            'copied_file_count' { $r.sealed_stage.copied_file_count++ }
            'generated_uninstaller_bytes' { $r.static_postbuild.generated_uninstaller_bytes++ }
        }
        $null=Seal $r $c.Next
        Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History } '*contradict*'
        Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Invalid evidence changed canonical receipt.'
    }
}
Check 'reader-rejects-resealed-bound-build-execution-claim' {
    $c=New-PublicationCase 'bound-build'
    $r=(Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next).Receipt
    $path=Join-Path $c.Root $r.disabled_build.result_path
    $build=ConvertFrom-TestJson ([IO.File]::ReadAllText($path))
    $build.installer_executed=$true
    $r.disabled_build.result_sha256=Seal $build $path
    $null=Seal $r $c.Next
    Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next } '*non-mutating*'
    Assert-Rejected { Publish-RimePimePackageReceiptV2Supersession $c.Root $c.Next $c.Before $c.History }
    Assert-True ((Hash $c.V1Path) -ceq $c.Before) 'Contradictory evidence changed canonical receipt.'
}
foreach ($bad in @('duplicate','case-duplicate','escaped-duplicate','comment','trailing-comma')) {
    Check ('strict-json-rejects-'+$bad) {
        $c=New-PublicationCase ('json-'+$bad)
        $json=[IO.File]::ReadAllText($c.Next)
        $prefix=switch ($bad) {
            'duplicate' { '"product":"rime-pime",' }
            'case-duplicate' { '"PRODUCT":"rime-pime",' }
            'escaped-duplicate' { '"\u0070roduct":"rime-pime",' }
            'comment' { '/* comment */' }
            'trailing-comma' { '' }
        }
        if ($bad -eq 'trailing-comma') { $json=$json.TrimEnd().TrimEnd('}')+',}' }
        else { $json=$json.Insert($json.IndexOf('{')+1,$prefix) }
        [IO.File]::WriteAllText($c.Next,$json,[Text.UTF8Encoding]::new($false))
        Write-AsciiSidecar $c.Next (Hash $c.Next)
        Assert-Rejected { Read-RimePimePackageBuildReceiptV2 $c.Root $c.Next } '*Invalid or ambiguous receipt JSON*'
    }
}
$failed=@($checks|Where-Object{-not $_.passed})
if ($checks.Count -eq 0) { throw 'No checks selected.' }
$result=[ordered]@{schema_version='yime-rime-pime-receipt-store-test-v1';total=$checks.Count;passed=$checks.Count-$failed.Count;failed=$failed.Count;checks=@($checks);
    installer_or_uninstaller_executed=$false;product_processes_executed=$false;power_loss_verified=$false}
$resultPath=Join-Path $output 'store-result.json'
[IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 10))
if ($failed.Count) { $failed|Format-Table -AutoSize|Out-String|Write-Host;throw "Store checks failed: $resultPath" }
Write-Host "PASS: $($checks.Count) receipt store checks. $resultPath"
