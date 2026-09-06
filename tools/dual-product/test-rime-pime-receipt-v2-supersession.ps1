[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$allowed=Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $allowed -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-j-receipt-v2-supersession-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a fresh immediate .tmp/dual-product/dp1-j-receipt-v2-supersession-* fixture root.'
}
$modulePath=Join-Path $PSScriptRoot 'rime-pime-receipt-v2-supersession.psm1'
$helperPath=Join-Path $PSScriptRoot 'rime-pime-receipt-v2-supersession.ps1'
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true;error=$null}) }
    catch { $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message}) }
}
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Rejected([scriptblock]$Body,[string]$Pattern='*') {
    try { & $Body } catch { if ($_.Exception.Message -like $Pattern) { return };throw }
    throw 'Unsafe supersession fixture operation was accepted.'
}
function Receipt-Bytes([string]$Id) {
    return ,[Text.UTF8Encoding]::new($false,$true).GetBytes('{"schema_version":"yime-rime-pime-package-build-receipt-v2","fixture_id":"'+$Id+'"}'+"`n")
}
function Artifact([string]$Role,[string]$Text) {
    return [pscustomobject][ordered]@{role=$Role;bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($Text+"`n")}
}
function Tx([int]$Value) { return ('{0:x32}' -f $Value) }
function Sha256-Bytes([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

Assert-True (-not(Test-Path -LiteralPath $output)) 'Fixture root unexpectedly exists before definitions-only import.'
$script:loadedModule=Import-Module -Name $modulePath -Force -PassThru
Assert-True (-not(Test-Path -LiteralPath $output)) 'Definitions-only module import created fixture state.'
$context=New-RimePimeReceiptV2SupersessionFixture -RepoRoot $repo -OutputRoot $output
$expectedExports=@(
    'Get-RimePimeReceiptV2SupersessionHead','Get-RimePimeReceiptV2SupersessionJournal',
    'Invoke-RimePimeReceiptV2Supersession','New-RimePimeReceiptV2SupersessionFixture',
    'Open-RimePimeReceiptV2SupersessionFixture','Resume-RimePimeReceiptV2Supersession'
)

Check 'definitions-only-module-has-an-exact-public-surface' {
    $actual=@($script:loadedModule.ExportedFunctions.Keys|Sort-Object)
    Assert-True (($actual -join '|') -ceq (($expectedExports|Sort-Object)-join '|')) 'Supersession module export surface is open or incomplete.'
}

$head0=Get-RimePimeReceiptV2SupersessionHead $context
Check 'initial-v2-generation-commits-through-one-head' {
    $result=Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId (Tx 1) -MutationId (Tx 101) `
        -GenerationOrdinal 1 -ReceiptBytes (Receipt-Bytes 'one') -Artifacts @((Artifact 'build-result' 'build-one'))
    $script:head1=Get-RimePimeReceiptV2SupersessionHead $context
    Assert-True ($result.status -ceq 'committed' -and $script:head1.present -and $script:head1.generation_ordinal -eq 1) 'Initial head did not commit.'
    Assert-True (-not $script:head1.head.retention_durability_claimed -and
        -not $script:head1.head.directory_metadata_durability_verified -and
        -not $script:head1.head.power_loss_verified -and -not $script:head1.head.canonical_receipt_mutated) 'Initial head elevated a forbidden claim.'
}

Check 'atomic-v2-to-v2-switch-replays-after-switch-before-journal' {
    $tx=Tx 2;$mutation=Tx 102;$before=$script:head1.sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId $mutation `
        -ExpectedHeadSha256 $before -GenerationOrdinal 2 -ReceiptBytes (Receipt-Bytes 'two') `
        -Artifacts @((Artifact 'build-result' 'build-two')) -FaultPoint after-head-switch } '*Injected fixture fault*'
    $switched=Get-RimePimeReceiptV2SupersessionHead $context
    Assert-True ($switched.sha256 -cne $before -and $switched.generation_ordinal -eq 2) 'Fault did not occur after the atomic head switch.'
    $blockedTx=Tx 20;$blockedRoot=Join-Path $context.transactions_root ('tx-'+$blockedTx)
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $blockedTx -MutationId (Tx 120) `
        -ExpectedHeadSha256 $switched.sha256 -GenerationOrdinal 3 -ReceiptBytes (Receipt-Bytes 'must-not-pass-unresolved-owner') } '*current-head owner is unresolved*'
    Assert-True (-not(Test-Path -LiteralPath $blockedRoot)) 'Unresolved head owner allowed a successor transaction to mutate state.'
    $script:loadedModule=Import-Module -Name $modulePath -Force -PassThru
    $script:context=Open-RimePimeReceiptV2SupersessionFixture -RepoRoot $repo -OutputRoot $output
    $resumed=Resume-RimePimeReceiptV2Supersession -Context $script:context -TransactionId $tx
    $script:head2=Get-RimePimeReceiptV2SupersessionHead $script:context
    Assert-True ($resumed.record_count -eq 4 -and $script:head2.sha256 -ceq $switched.sha256) 'Head-switched replay did not converge.'
}

Check 'stale-cas-is-rejected-before-transaction-write' {
    $tx=Tx 3;$before=$script:head2.sha256;$path=Join-Path $context.transactions_root ('tx-'+$tx)
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId (Tx 103) `
        -ExpectedHeadSha256 $head0.sha256 -GenerationOrdinal 3 -ReceiptBytes (Receipt-Bytes 'stale') } '*compare-and-swap*'
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $before) 'Stale CAS changed the current head.'
    Assert-True (-not(Test-Path -LiteralPath $path)) 'Stale CAS created a transaction directory.'
}

Check 'prepared-record-survives-module-reimport-and-replays' {
    $tx=Tx 4;$before=(Get-RimePimeReceiptV2SupersessionHead $context).sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId (Tx 104) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 3 -ReceiptBytes (Receipt-Bytes 'three') -FaultPoint after-prepared } '*Injected fixture fault*'
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $before) 'Prepared-only fault changed the head.'
    $blockedTx=Tx 21;$blockedRoot=Join-Path $context.transactions_root ('tx-'+$blockedTx)
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $blockedTx -MutationId (Tx 121) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 3 -ReceiptBytes (Receipt-Bytes 'must-not-bypass-prepared') } '*unresolved transaction*'
    Assert-True (-not(Test-Path -LiteralPath $blockedRoot)) 'Prepared-only transaction allowed a competing successor to mutate state.'
    $script:loadedModule=Import-Module -Name $modulePath -Force -PassThru;$script:context=Open-RimePimeReceiptV2SupersessionFixture -RepoRoot $repo -OutputRoot $output
    $null=Resume-RimePimeReceiptV2Supersession $script:context $tx
    $script:head3=Get-RimePimeReceiptV2SupersessionHead $script:context
    Assert-True ($script:head3.generation_ordinal -eq 3 -and @(Get-RimePimeReceiptV2SupersessionJournal $script:context $tx).Count -eq 4) 'Prepared replay did not converge.'
}

Check 'unique-json-only-journal-tail-is-discarded-and-rewritten' {
    $tx=Tx 5;$before=$script:head3.sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId (Tx 105) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 4 -ReceiptBytes (Receipt-Bytes 'four') `
        -FaultPoint after-head-switched-json } '*Injected fixture fault*'
    $journal=Join-Path (Join-Path $context.transactions_root ('tx-'+$tx)) 'journal'
    Assert-True ((Test-Path -LiteralPath (Join-Path $journal '00000002-head-switched.json')) -and
        -not(Test-Path -LiteralPath (Join-Path $journal '00000002-head-switched.json.sha256'))) 'Fault did not leave the expected unique JSON-only tail.'
    [IO.File]::WriteAllBytes((Join-Path $journal '00000002-head-switched.json.sha256'),[byte[]](1,2,3))
    $null=Resume-RimePimeReceiptV2Supersession $context $tx
    $script:head4=Get-RimePimeReceiptV2SupersessionHead $context
    Assert-True (@(Get-RimePimeReceiptV2SupersessionJournal $context $tx).Count -eq 4) 'Torn-tail replay did not restore a sealed chain.'
}

Check 'terminal-retry-is-idempotent-and-changed-context-conflicts' {
    $same=Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId (Tx 5) -MutationId (Tx 105) `
        -ExpectedHeadSha256 $script:head3.sha256 -GenerationOrdinal 4 -ReceiptBytes (Receipt-Bytes 'four')
    Assert-True ($same.status -ceq 'terminal-noop' -and (Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $script:head4.sha256) 'Exact terminal retry was not a no-op.'
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId (Tx 5) -MutationId (Tx 105) `
        -ExpectedHeadSha256 $script:head3.sha256 -GenerationOrdinal 4 -ReceiptBytes (Receipt-Bytes 'changed') } '*conflicts*'
}

Check 'flushed-head-temp-is-reused-by-replay' {
    $tx=Tx 8;$before=$script:head4.sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId (Tx 108) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 5 -ReceiptBytes (Receipt-Bytes 'five') `
        -FaultPoint after-head-temp } '*Injected fixture fault*'
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $before) 'Head-temp fault changed the public head.'
    [IO.File]::WriteAllBytes((Join-Path $context.output_root ('.'+$tx+'.head.next')),[byte[]](4,5,6))
    $null=Resume-RimePimeReceiptV2Supersession $context $tx
    $script:head5=Get-RimePimeReceiptV2SupersessionHead $context
    Assert-True ($script:head5.generation_ordinal -eq 5) 'Head-temp replay did not converge.'
}

Check 'sealed-commit-without-terminal-replays-to-terminal' {
    $tx=Tx 9;$before=$script:head5.sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId (Tx 109) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 6 -ReceiptBytes (Receipt-Bytes 'six') `
        -FaultPoint after-commit } '*Injected fixture fault*'
    Assert-True (@(Get-RimePimeReceiptV2SupersessionJournal $context $tx).Count -eq 3) 'Commit fault did not leave three sealed records.'
    $null=Resume-RimePimeReceiptV2Supersession $context $tx
    $script:head6=Get-RimePimeReceiptV2SupersessionHead $context
    Assert-True (@(Get-RimePimeReceiptV2SupersessionJournal $context $tx).Count -eq 4) 'Commit replay did not append terminal.'
}

Check 'fault-after-terminal-is-an-exact-idempotent-noop' {
    $tx=Tx 10;$mutation=Tx 110;$before=$script:head6.sha256
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId $mutation `
        -ExpectedHeadSha256 $before -GenerationOrdinal 7 -ReceiptBytes (Receipt-Bytes 'seven') `
        -FaultPoint after-terminal } '*Injected fixture fault*'
    $script:head7=Get-RimePimeReceiptV2SupersessionHead $context
    $retry=Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $tx -MutationId $mutation `
        -ExpectedHeadSha256 $before -GenerationOrdinal 7 -ReceiptBytes (Receipt-Bytes 'seven')
    Assert-True ($retry.status -ceq 'terminal-noop' -and (Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $script:head7.sha256) 'Terminal fault retry mutated state.'
}

Check 'fixed-exclusive-lock-blocks-a-second-writer' {
    $lease=& $script:loadedModule { param($c) Open-RimePimeSupersessionExclusiveLock $c } $context
    try {
        Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId (Tx 6) -MutationId (Tx 106) `
            -ExpectedHeadSha256 $script:head7.sha256 -GenerationOrdinal 8 -ReceiptBytes (Receipt-Bytes 'eight') } '*used by another process*'
    } finally { $lease.Dispose() }
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).sha256 -ceq $script:head7.sha256) 'Blocked second writer changed the head.'
}

Check 'unknown-receipt-schema-and-forged-context-are-rejected' {
    $bad=[Text.UTF8Encoding]::new($false,$true).GetBytes('{"schema_version":"unknown-v9"}'+"`n")
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId (Tx 7) -MutationId (Tx 107) `
        -ExpectedHeadSha256 $script:head7.sha256 -GenerationOrdinal 8 -ReceiptBytes $bad } '*receipt-v2 schema marker*'
    $forged=$context.PSObject.Copy();$forged.head_path=Join-Path $repo 'installer\package-build-receipt.json'
    Assert-Rejected { Get-RimePimeReceiptV2SupersessionHead $forged } '*closed derived set*'
}

Check 'unsealed-content-object-and-torn-sidecar-are-rebuilt-before-publication' {
    $partialBytes=[Text.UTF8Encoding]::new($false,$true).GetBytes("partial-object-complete`n")
    $markerBytes=[Text.UTF8Encoding]::new($false,$true).GetBytes("torn-sidecar-object`n")
    $partialDigest=Sha256-Bytes $partialBytes;$markerDigest=Sha256-Bytes $markerBytes
    $partialDirectory=Join-Path $context.objects_root $partialDigest.Substring(0,2)
    $markerDirectory=Join-Path $context.objects_root $markerDigest.Substring(0,2)
    $null=[IO.Directory]::CreateDirectory($partialDirectory);$null=[IO.Directory]::CreateDirectory($markerDirectory)
    $partialPath=Join-Path $partialDirectory ($partialDigest+'.blob')
    $markerPath=Join-Path $markerDirectory ($markerDigest+'.blob')
    [IO.File]::WriteAllBytes($partialPath,[byte[]](7,8,9))
    [IO.File]::WriteAllBytes($markerPath,$markerBytes)
    $before=(Get-RimePimeReceiptV2SupersessionHead $context).sha256
    $script:repairTx=Tx 11
    $repairArtifacts=@(
        [pscustomobject][ordered]@{role='partial-data';bytes=$partialBytes},
        [pscustomobject][ordered]@{role='torn-marker';bytes=$markerBytes}
    )
    $fullWrongMarker=[Text.Encoding]::ASCII.GetBytes((('0'*64)+'  '+[IO.Path]::GetFileName($markerPath)+"`n"))
    [IO.File]::WriteAllBytes(($markerPath+'.sha256'),$fullWrongMarker)
    Assert-Rejected { Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $script:repairTx -MutationId (Tx 111) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 8 -ReceiptBytes (Receipt-Bytes 'eight') -Artifacts $repairArtifacts } '*sidecar does not seal*'
    Assert-True (-not(Test-Path -LiteralPath (Join-Path $context.transactions_root ('tx-'+$script:repairTx)))) 'Full-length invalid marker reached transaction publication.'
    [IO.File]::WriteAllBytes(($markerPath+'.sha256'),[byte[]](10,11))
    $null=Invoke-RimePimeReceiptV2Supersession -Context $context -TransactionId $script:repairTx -MutationId (Tx 111) `
        -ExpectedHeadSha256 $before -GenerationOrdinal 8 -ReceiptBytes (Receipt-Bytes 'eight') -Artifacts @(
            [pscustomobject][ordered]@{role='partial-data';bytes=$partialBytes},
            [pscustomobject][ordered]@{role='torn-marker';bytes=$markerBytes}
        )
    Assert-True ((Sha256-Bytes ([IO.File]::ReadAllBytes($partialPath))) -ceq $partialDigest) 'Unsealed partial object was not rebuilt.'
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).generation_ordinal -eq 8) 'Repaired objects were not published through the next head.'
}

Check 'journal-rejects-unlisted-directory-membership' {
    $journal=Join-Path (Join-Path $context.transactions_root ('tx-'+$script:repairTx)) 'journal'
    $unexpected=Join-Path $journal 'unlisted-directory'
    $null=[IO.Directory]::CreateDirectory($unexpected)
    try { Assert-Rejected { Get-RimePimeReceiptV2SupersessionJournal $context $script:repairTx } '*unexpected non-file entry*' }
    finally { [IO.Directory]::Delete($unexpected) }
}

Check 'catalog-object-and-journal-chain-tamper-are-rejected-on-reread' {
    $markerBytes=[Text.UTF8Encoding]::new($false,$true).GetBytes("torn-sidecar-object`n")
    $markerDigest=Sha256-Bytes $markerBytes
    $markerPath=Join-Path (Join-Path $context.objects_root $markerDigest.Substring(0,2)) ($markerDigest+'.blob')
    $savedObject=[IO.File]::ReadAllBytes($markerPath)
    try {
        [IO.File]::WriteAllBytes($markerPath,[byte[]](12,13,14))
        Assert-Rejected { Get-RimePimeReceiptV2SupersessionHead $context } '*sidecar does not seal*'
    } finally { [IO.File]::WriteAllBytes($markerPath,$savedObject) }

    $journal=Join-Path (Join-Path $context.transactions_root ('tx-'+$script:repairTx)) 'journal'
    $terminal=Join-Path $journal '00000004-terminal.json';$terminalSidecar=$terminal+'.sha256'
    $savedTerminal=[IO.File]::ReadAllBytes($terminal);$savedTerminalSidecar=[IO.File]::ReadAllBytes($terminalSidecar)
    try {
        [IO.File]::WriteAllBytes($terminal,[byte[]](15,16,17))
        Assert-Rejected { Get-RimePimeReceiptV2SupersessionJournal $context $script:repairTx } '*sidecar does not seal*'
    } finally {
        [IO.File]::WriteAllBytes($terminal,$savedTerminal)
        [IO.File]::WriteAllBytes($terminalSidecar,$savedTerminalSidecar)
    }
    try {
        $fullWrongMarker=[Text.Encoding]::ASCII.GetBytes((('0'*64)+'  '+[IO.Path]::GetFileName($terminal)+"`n"))
        [IO.File]::WriteAllBytes($terminalSidecar,$fullWrongMarker)
        Assert-Rejected { Get-RimePimeReceiptV2SupersessionJournal $context $script:repairTx } '*sidecar does not seal*'
    } finally { [IO.File]::WriteAllBytes($terminalSidecar,$savedTerminalSidecar) }
    Assert-True ((Get-RimePimeReceiptV2SupersessionHead $context).generation_ordinal -eq 8) 'Fixture did not return to its sealed terminal state after negative probes.'
}

Check 'implementation-is-fixture-only-and-has-no-process-or-product-surface' {
    $source=[IO.File]::ReadAllText($helperPath)
    foreach ($pattern in @(
        '(?im)^\s*(Start-Process|Invoke-Expression|Invoke-Command|Start-Job)\b',
        '(?i)Registry::|HKEY_|\bHKLM:|\bHKCU:|StdRegProv|reg\.exe',
        '(?i)Program Files|APPDATA|LOCALAPPDATA|USERPROFILE',
        '(?i)installer\\package-build-receipt\.json|makensis|sign-release|msiexec'
    )) { Assert-True ($source -notmatch $pattern) "Supersession implementation violates static boundary: $pattern" }
    foreach ($required in @('retention_durability_claimed=$false','directory_metadata_durability_verified=$false',
        'power_loss_verified=$false','canonical_receipt_mutated=$false','[IO.File]::Replace','[IO.FileShare]::None',
        '[IO.FileOptions]::WriteThrough','$stream.Flush($true)')) {
        Assert-True ($source.Contains($required)) "Supersession implementation lacks boundary or atomic anchor: $required"
    }
}

$failed=@($checks|Where-Object{-not $_.passed})
$checkResults=@($checks|ForEach-Object{$_})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-receipt-v2-supersession-test-v1'
    fixture_only=$true
    checks_count=$checks.Count
    passed_count=$checks.Count-$failed.Count
    failed_count=$failed.Count
    checks=$checkResults
    content_addressed_objects_verified=($failed.Count -eq 0)
    content_addressed_generation_manifest_verified=($failed.Count -eq 0)
    generation_catalog_all_objects_read_and_verified=($failed.Count -eq 0)
    single_atomic_head_exercised=($failed.Count -eq 0)
    v2_to_v2_fixture_supersession_verified=($failed.Count -eq 0)
    hash_chain_journal_verified=($failed.Count -eq 0)
    same_process_module_reimport_replay_verified=($failed.Count -eq 0)
    unresolved_head_owner_successor_rejected=($failed.Count -eq 0)
    torn_sidecar_tail_replay_verified=($failed.Count -eq 0)
    unsealed_object_repair_verified=($failed.Count -eq 0)
    unpublished_head_temp_repair_verified=($failed.Count -eq 0)
    journal_exact_membership_verified=($failed.Count -eq 0)
    physical_object_immutability_enforced=$false
    concurrent_content_replacement_excluded=$false
    actual_receipt_v2_reader_used=$false
    actual_strict_receipt_v2_schema_verified=$false
    cross_process_crash_or_replay_verified=$false
    hardlink_negative_verified=$false
    retention_durability_claimed=$false
    directory_metadata_durability_verified=$false
    power_loss_verified=$false
    canonical_receipt_mutated=$false
    installer_or_uninstaller_executed=$false
    makensis_or_signing_executed=$false
    product_process_or_registry_touched=$false
    production_user_data_read_or_written=$false
    helper_sha256=(Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant()
    module_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$resultPath=Join-Path $output 'result.json'
$resultText=($result|ConvertTo-Json -Depth 16 -Compress)+"`n"
[IO.File]::WriteAllText($resultPath,$resultText,[Text.UTF8Encoding]::new($false))
$resultDigest=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($resultPath+'.sha256'),($resultDigest+' *result.json'+"`n"),[Text.UTF8Encoding]::new($false))
if ($failed.Count) {
    $summary=($failed|ForEach-Object{"$($_.name): $($_.error)"}) -join ' | '
    throw "$($failed.Count) receipt-v2 supersession fixture checks failed: $summary"
}
Write-Host "PASS: $($checks.Count) isolated receipt-v2 supersession checks passed. Evidence: $resultPath"
