[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$allowed=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ([IO.Path]::GetDirectoryName($output) -ine $allowed -or
    [IO.Path]::GetFileName($output) -cnotmatch '^dp1-i-journal-[a-z0-9-]{1,80}$' -or
    [IO.File]::Exists($output) -or [IO.Directory]::Exists($output)) {
    throw 'Use a fresh immediate .tmp/dual-product/dp1-i-journal-* output root.'
}
$null=[IO.Directory]::CreateDirectory($output)
$fixture=Join-Path $output 'fixture'
$null=[IO.Directory]::CreateDirectory($fixture)

$modulePath=Join-Path $PSScriptRoot 'rime-pime-fixture-transaction-journal.psm1'
$helperPath=Join-Path $PSScriptRoot 'rime-pime-fixture-transaction-journal.ps1'
Import-Module -Name $modulePath -Force -DisableNameChecking

$script:checkCount=0
function Invoke-FixtureCheck {
    param([Parameter(Mandatory)][scriptblock]$Body)
    $script:checkCount++
    try { $null=$Body.InvokeReturnAsIs() }
    catch { throw "Synthetic DP1-I check failed at ordinal $script:checkCount." }
}
function Assert-FixtureTrue {
    param($Value)
    if (-not $Value) { throw 'Synthetic assertion was false.' }
}
function Assert-FixtureRejected {
    param([Parameter(Mandatory)][scriptblock]$Body)
    $rejected=$false
    try { $null=$Body.InvokeReturnAsIs() } catch { $rejected=$true }
    if (-not $rejected) { throw 'Synthetic rejection did not occur.' }
}
function Get-FixtureDigest {
    param([Parameter(Mandatory)][char]$Character)
    return ([string]$Character) * 64
}
function Write-FixtureTestBytes {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes)
    $full=[IO.Path]::GetFullPath($Path)
    $fixturePrefix=[IO.Path]::GetFullPath($fixture).TrimEnd('\')+'\'
    if (-not $full.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase) -or $full.IndexOf(':',3) -ge 0) {
        throw 'Synthetic test writer left its fixture root.'
    }
    $parent=[IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($parent)) { $null=[IO.Directory]::CreateDirectory($parent) }
    $stream=New-Object IO.FileStream($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Get-FixtureTestBytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Write-FixtureTestSealedJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $text=($Value | ConvertTo-Json -Depth 20 -Compress)+"`n"
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text)
    Write-FixtureTestBytes $Path $bytes
    $digest=Get-FixtureTestBytesSha256 $bytes
    Write-FixtureTestBytes ($Path+'.sha256') ([Text.Encoding]::ASCII.GetBytes(
        "$digest  $([IO.Path]::GetFileName($Path))`n"))
    return [pscustomobject]@{ sha256=$digest; bytes=[long]$bytes.Length }
}
function Read-FixtureTestJson {
    param([Parameter(Mandatory)][string]$Path)
    $text=[IO.File]::ReadAllText($Path,(New-Object Text.UTF8Encoding($false,$true)))
    $command=Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey('DateKind')) { return $text | ConvertFrom-Json -DateKind String }
    return $text | ConvertFrom-Json
}
function New-FixtureRegistryState {
    param([int]$SidTail=401)
    $records=@(
        (New-RimePimeFixtureRegistryRecord 'machine-com-server-x86' 'String' 'fixture:server-x86'),
        (New-RimePimeFixtureRegistryRecord 'machine-com-server-native' 'String' 'fixture:server-native'),
        (New-RimePimeFixtureRegistryRecord 'machine-profile-icon-index' 'DWord' '7'),
        (New-RimePimeFixtureRegistryRecord 'machine-product-root' 'ExpandString' 'fixture:product-root'),
        (New-RimePimeFixtureRegistryRecord 'target-profile-enabled' 'DWord' '1'),
        (New-RimePimeFixtureRegistryRecord 'target-profile-metadata' 'MultiString' @('fixture:alpha','','fixture:alpha'))
    )
    return New-RimePimeFixtureRegistryState "S-1-5-21-100-200-300-$SidTail" $records
}
function New-FixturePayload {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$ManifestId)
    $definitions=@(
        [pscustomobject]@{ path='bin/core.dll'; text='fixture-core'; class='ordinary' },
        [pscustomobject]@{ path='data/nested/table.bin'; text='fixture-table'; class='ordinary' },
        [pscustomobject]@{ path='install-payload-manifest.json'; text='fixture-ledger'; class='installed-manifest' },
        [pscustomobject]@{ path='Uninstall.exe'; text='fixture-self'; class='special-self' }
    )
    $rows=@()
    foreach ($definition in $definitions) {
        $observation=Write-RimePimeFixtureInstallFile $Context $definition.path `
            ([Text.Encoding]::UTF8.GetBytes([string]$definition.text))
        $rows += [pscustomobject][ordered]@{
            path=$observation.path; bytes=$observation.bytes; sha256=$observation.sha256
            removal_class=[string]$definition.class
        }
    }
    $manifest=New-RimePimeFixtureRemovalManifest $ManifestId $rows
    $receipt=Write-RimePimeFixtureRemovalManifest $Context $manifest
    return [pscustomobject]@{ manifest=$manifest; receipt=$receipt }
}
function New-FixtureTransactionArtifacts {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    $registry=Write-RimePimeFixtureRegistryState $Context (New-FixtureRegistryState) 'before.json'
    $manifest=New-RimePimeFixtureRemovalManifest $TransactionId @(
        [pscustomobject]@{path='bin/core.dll';bytes=1;sha256=('1'*64);removal_class='ordinary'},
        [pscustomobject]@{path='install-payload-manifest.json';bytes=1;sha256=('2'*64);removal_class='installed-manifest'},
        [pscustomobject]@{path='Uninstall.exe';bytes=1;sha256=('3'*64);removal_class='special-self'}
    )
    $removal=Write-RimePimeFixtureRemovalManifest $Context $manifest
    return [pscustomobject]@{ registry=$registry; removal=$removal }
}
function New-FixturePrepared {
    param([string]$TransactionId,[string]$RegistrySha,[string]$ManifestSha,[string]$RecordedUtc='2026-09-06T00:00:00Z')
    return New-RimePimeFixturePreparedRecord -TransactionId $TransactionId -Action upgrade `
        -NativeArchitecture x64 -SyntheticTargetUserSid 'S-1-5-21-100-200-300-401' `
        -RegistrySnapshotSha256 $RegistrySha -RemovalManifestSha256 $ManifestSha `
        -BeforeStateSha256 (Get-FixtureDigest 'a') -ProtectedStateSha256 (Get-FixtureDigest 'b') `
        -OperationPlanSha256 (Get-FixtureDigest 'c') -RecordedUtc $RecordedUtc
}

# Definitions-only import and root confinement.
Invoke-FixtureCheck { Assert-FixtureTrue ([IO.Directory]::GetFileSystemEntries($fixture).Count -eq 0) }
Invoke-FixtureCheck { Assert-FixtureRejected {
    New-RimePimeFixtureTransactionContext $repo (Join-Path $repo '.tmp\dual-product\not-a-run\fixture') 'bad'
} }
$registryContext=New-RimePimeFixtureTransactionContext $repo $fixture 'registry-types'
Invoke-FixtureCheck { Assert-FixtureTrue ($registryContext.fixture_only -eq $true) }
Invoke-FixtureCheck { Assert-FixtureRejected {
    New-RimePimeFixtureTransactionContext $repo $fixture '..'
} }
$forgedContext=[pscustomobject][ordered]@{}
foreach ($property in $registryContext.PSObject.Properties) {
    $forgedContext | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
}
$forgedOutside=Join-Path $output 'must-not-be-created.bin'
$forgedContext.install_root=$output
Invoke-FixtureCheck { Assert-FixtureRejected {
    Write-RimePimeFixtureInstallFile $forgedContext 'must-not-be-created.bin' ([byte[]](1))
} }
Invoke-FixtureCheck { Assert-FixtureTrue (-not [IO.File]::Exists($forgedOutside)) }
$wholeForged=[pscustomobject][ordered]@{}
foreach ($property in $registryContext.PSObject.Properties) {
    $wholeForged | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
}
$syntheticOutside=[IO.Path]::Combine([IO.Path]::GetPathRoot($repo),'dp1-i-outside-synthetic')
$wholeForged.repo_root=$syntheticOutside
$wholeForged.fixture_root=Join-Path $syntheticOutside '.tmp\dual-product\dp1-i-journal-forged\fixture'
$wholeForged.case_root=Join-Path $wholeForged.fixture_root 'cases\forged'
$wholeForged.state_root=Join-Path $wholeForged.case_root 'state'
$wholeForged.records_root=Join-Path $wholeForged.state_root 'records'
$wholeForged.registry_root=Join-Path $wholeForged.case_root 'registry'
$wholeForged.trusted_root=Join-Path $wholeForged.case_root 'trusted'
$wholeForged.install_root=Join-Path $wholeForged.case_root 'install'
$wholeForged.case_id='forged'
Invoke-FixtureCheck { Assert-FixtureRejected { Open-RimePimeFixtureJournalLock $wholeForged } }

# Closed, typed, privacy-safe registry fixture state.
$registryState=New-FixtureRegistryState
$registryReceipt=Write-RimePimeFixtureRegistryState $registryContext $registryState 'before.json'
$registryRead=Read-RimePimeFixtureRegistryState $registryContext 'before.json'
Invoke-FixtureCheck { Assert-FixtureTrue ($registryReceipt.sha256 -ceq $registryRead.sha256) }
Invoke-FixtureCheck { Assert-FixtureTrue (@($registryRead.value.records).Count -eq 6) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$registryRead.value.records[2].value -ceq '7') }
Invoke-FixtureCheck { Assert-FixtureTrue (@($registryRead.value.records[5].value).Count -eq 3) }
Invoke-FixtureCheck { Assert-FixtureTrue ($registryRead.value.contains_user_text -eq $false) }
$absentState=New-FixtureRegistryState 402
$absentState.records[0]=New-RimePimeFixtureRegistryRecord 'machine-com-server-x86' 'Absent' $null
$absentReceipt=Write-RimePimeFixtureRegistryState $registryContext $absentState 'absent.json'
$absentRead=Read-RimePimeFixtureRegistryState $registryContext 'absent.json'
Invoke-FixtureCheck { Assert-FixtureTrue ($absentReceipt.sha256 -ceq $absentRead.sha256) }
Invoke-FixtureCheck { Assert-FixtureTrue ($absentRead.value.records[0].present -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$absentRead.value.records[0].value_kind -ceq 'Absent') }
Invoke-FixtureCheck { Assert-FixtureTrue ($null -eq $absentRead.value.records[0].value) }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records[2].value='07'
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records[0]=New-RimePimeFixtureRegistryRecord 'machine-com-server-x86' 'DWord' '1'
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records[2].value='4294967296'
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records[0].value='not-fixture-text'
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records[5].value='fixture:not-an-array'
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad.records=@($bad.records[0..4])
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    $bad=New-FixtureRegistryState
    $bad | Add-Member -NotePropertyName extra -NotePropertyValue $false
    Assert-RimePimeFixtureRegistryState $bad
} }
Invoke-FixtureCheck {
    $bad=New-FixtureRegistryState
    $bad.PSObject.Properties.Remove('schema_version')
    $bad | Add-Member -NotePropertyName Schema_version -NotePropertyValue 'yime-rime-pime-fixture-registry-state-v1'
    Assert-FixtureRejected { Assert-RimePimeFixtureRegistryState $bad }
}
Invoke-FixtureCheck { Assert-FixtureRejected {
    New-RimePimeFixtureRegistryState 'S-1-5-18' @($registryState.records)
} }

# Exact payload manifest and deterministic, leaf-first removal.
$removalContext=New-RimePimeFixtureTransactionContext $repo $fixture 'exact-removal'
$payload=New-FixturePayload $removalContext ('1'*32)
$manifestRead=Read-RimePimeFixtureRemovalManifest $removalContext
$preflight=Test-RimePimeFixtureRemovalClosure $removalContext $manifestRead.value -RequireExact
$plan=Get-RimePimeFixtureRemovalPlan $manifestRead.value
Invoke-FixtureCheck { Assert-FixtureTrue ($payload.receipt.sha256 -ceq $manifestRead.sha256) }
Invoke-FixtureCheck { Assert-FixtureTrue ($preflight.exact -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$plan.files[0].path -ceq 'data/nested/table.bin') }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$plan.files[$plan.files.Count-2].path -ceq 'install-payload-manifest.json') }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$plan.files[$plan.files.Count-1].path -ceq 'Uninstall.exe') }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$plan.directories[0] -ceq 'data/nested') }
Invoke-FixtureCheck { Assert-FixtureRejected {
    New-RimePimeFixtureRemovalManifest ('2'*32) @(
        [pscustomobject]@{path='../escape';bytes=1;sha256=('1'*64);removal_class='ordinary'},
        [pscustomobject]@{path='install-payload-manifest.json';bytes=1;sha256=('2'*64);removal_class='installed-manifest'},
        [pscustomobject]@{path='Uninstall.exe';bytes=1;sha256=('3'*64);removal_class='special-self'}
    )
} }
$removed=Invoke-RimePimeFixtureExactRemoval $removalContext $manifestRead.value
Invoke-FixtureCheck { Assert-FixtureTrue ($removed.removed_file_count -eq 4) }
Invoke-FixtureCheck { Assert-FixtureTrue ($removed.install_root_removed -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ($removed.changed_or_foreign_preserved -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ($removed.recursive_delete_used -eq $false) }
$removedAgain=Invoke-RimePimeFixtureExactRemoval $removalContext $manifestRead.value
Invoke-FixtureCheck { Assert-FixtureTrue ($removedAgain.already_absent_file_count -eq 4) }
Invoke-FixtureCheck { Assert-FixtureTrue ($removedAgain.install_root_removed -eq $true) }

# Changed and unexpected content is retained, and public results disclose no name.
$preserveContext=New-RimePimeFixtureTransactionContext $repo $fixture 'preserve-foreign'
$preservePayload=New-FixturePayload $preserveContext ('3'*32)
$changedPath=Join-Path $preserveContext.install_root 'bin\core.dll'
[IO.File]::Delete($changedPath)
$null=Write-RimePimeFixtureInstallFile $preserveContext 'bin/core.dll' ([Text.Encoding]::UTF8.GetBytes('fixture-changed'))
$privateUnexpectedName='private-unexpected-token.bin'
$null=Write-RimePimeFixtureInstallFile $preserveContext ("foreign/$privateUnexpectedName") `
    ([Text.Encoding]::UTF8.GetBytes('fixture-foreign'))
$preserveAudit=Test-RimePimeFixtureRemovalClosure $preserveContext $preservePayload.manifest
Invoke-FixtureCheck { Assert-FixtureTrue ($preserveAudit.exact -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ($preserveAudit.changed_count -eq 1) }
Invoke-FixtureCheck { Assert-FixtureTrue ($preserveAudit.unexpected_file_count -eq 1) }
Invoke-FixtureCheck { Assert-FixtureRejected {
    Test-RimePimeFixtureRemovalClosure $preserveContext $preservePayload.manifest -RequireExact
} }
$preserved=Invoke-RimePimeFixtureExactRemoval $preserveContext $preservePayload.manifest
$preservedPublic=$preserved | ConvertTo-Json -Depth 8 -Compress
Invoke-FixtureCheck { Assert-FixtureTrue ($preserved.preserved_changed_file_count -eq 1) }
Invoke-FixtureCheck { Assert-FixtureTrue ($preserved.changed_or_foreign_preserved -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ([IO.File]::Exists($changedPath)) }
Invoke-FixtureCheck { Assert-FixtureTrue ([IO.File]::Exists((Join-Path $preserveContext.install_root ("foreign\$privateUnexpectedName")))) }
Invoke-FixtureCheck { Assert-FixtureTrue (-not $preservedPublic.Contains($privateUnexpectedName)) }
Invoke-FixtureCheck { Assert-FixtureTrue ($preserved.unexpected_filenames_disclosed -eq $false) }

# Prepared admission is bound to sealed artifacts in the same fixture case.
$missingArtifactContext=New-RimePimeFixtureTransactionContext $repo $fixture 'missing-artifacts'
$missingArtifactLock=Open-RimePimeFixtureJournalLock $missingArtifactContext
Invoke-FixtureCheck { Assert-FixtureRejected {
    Start-RimePimeFixtureTransaction $missingArtifactContext $missingArtifactLock `
        (New-FixturePrepared ('d'*32) $registryReceipt.sha256 $payload.receipt.sha256)
} }
Invoke-FixtureCheck { Assert-FixtureTrue ((Read-RimePimeFixtureJournal $missingArtifactContext).record_count -eq 0) }
Close-RimePimeFixtureJournalLock $missingArtifactLock

$crossArtifactA=New-RimePimeFixtureTransactionContext $repo $fixture 'cross-artifact-a'
$crossArtifactB=New-RimePimeFixtureTransactionContext $repo $fixture 'cross-artifact-b'
$crossA=New-FixtureTransactionArtifacts $crossArtifactA ('d'*32)
$crossB=New-FixtureTransactionArtifacts $crossArtifactB ('e'*32)
$crossLock=Open-RimePimeFixtureJournalLock $crossArtifactA
Invoke-FixtureCheck { Assert-FixtureRejected {
    Start-RimePimeFixtureTransaction $crossArtifactA $crossLock `
        (New-FixturePrepared ('d'*32) $crossA.registry.sha256 $crossB.removal.sha256)
} }
Invoke-FixtureCheck { Assert-FixtureTrue ((Read-RimePimeFixtureJournal $crossArtifactA).record_count -eq 0) }
Close-RimePimeFixtureJournalLock $crossLock

$resumeMissingContext=New-RimePimeFixtureTransactionContext $repo $fixture 'resume-missing-artifact'
$resumeMissingArtifacts=New-FixtureTransactionArtifacts $resumeMissingContext ('d'*32)
$resumeMissingLock=Open-RimePimeFixtureJournalLock $resumeMissingContext
$null=Start-RimePimeFixtureTransaction $resumeMissingContext $resumeMissingLock `
    (New-FixturePrepared ('d'*32) $resumeMissingArtifacts.registry.sha256 $resumeMissingArtifacts.removal.sha256)
[IO.File]::Delete((Join-Path $resumeMissingContext.trusted_root 'removal-manifest.json.sha256'))
Invoke-FixtureCheck { Assert-FixtureRejected { Resume-RimePimeFixtureTransaction $resumeMissingContext $resumeMissingLock } }
Close-RimePimeFixtureJournalLock $resumeMissingLock

$resumeTamperContext=New-RimePimeFixtureTransactionContext $repo $fixture 'resume-tampered-artifact'
$resumeTamperArtifacts=New-FixtureTransactionArtifacts $resumeTamperContext ('e'*32)
$resumeTamperLock=Open-RimePimeFixtureJournalLock $resumeTamperContext
$null=Start-RimePimeFixtureTransaction $resumeTamperContext $resumeTamperLock `
    (New-FixturePrepared ('e'*32) $resumeTamperArtifacts.registry.sha256 $resumeTamperArtifacts.removal.sha256)
$resumeManifestPath=Join-Path $resumeTamperContext.trusted_root 'removal-manifest.json'
$resumeManifest=Read-FixtureTestJson $resumeManifestPath
[IO.File]::Delete($resumeManifestPath); [IO.File]::Delete($resumeManifestPath+'.sha256')
$resumeManifest.manifest_id='f'*32
$null=Write-FixtureTestSealedJson $resumeManifest $resumeManifestPath
Invoke-FixtureCheck { Assert-FixtureRejected { Resume-RimePimeFixtureTransaction $resumeTamperContext $resumeTamperLock } }
Close-RimePimeFixtureJournalLock $resumeTamperLock

# Prepared -> forward -> restart decision -> rollback -> terminal.
$rollbackContext=New-RimePimeFixtureTransactionContext $repo $fixture 'journal-rollback'
$rollbackArtifacts=New-FixtureTransactionArtifacts $rollbackContext ('4'*32)
$rollbackPrepared=New-FixturePrepared ('4'*32) $rollbackArtifacts.registry.sha256 $rollbackArtifacts.removal.sha256
$rollbackLock=Open-RimePimeFixtureJournalLock $rollbackContext
$started=Start-RimePimeFixtureTransaction $rollbackContext $rollbackLock $rollbackPrepared
$forwardId=Get-RimePimeFixtureOperationId ('4'*32) 'stage-forward'
$forward=Add-RimePimeFixtureStep $rollbackContext $rollbackLock $forwardId 'stage-forward' 'forward' `
    (Get-FixtureDigest 'a') (Get-FixtureDigest 'd') (Get-FixtureDigest 'd') -RecordedUtc '2026-09-06T00:00:01Z'
Close-RimePimeFixtureJournalLock $rollbackLock
Remove-Module -Name rime-pime-fixture-transaction-journal -Force
Import-Module -Name $modulePath -Force -DisableNameChecking
$rollbackLock=Open-RimePimeFixtureJournalLock $rollbackContext
$rollbackDecision=Resume-RimePimeFixtureTransaction $rollbackContext $rollbackLock
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$rollbackDecision.disposition -ceq 'rollback-to-before') }
Invoke-FixtureCheck { Assert-FixtureTrue ($rollbackDecision.uncommitted_tail_discarded -eq $false) }
$rollbackId=Get-RimePimeFixtureOperationId ('4'*32) 'stage-rollback'
$null=Add-RimePimeFixtureStep $rollbackContext $rollbackLock $rollbackId 'stage-rollback' 'rollback' `
    (Get-FixtureDigest 'd') (Get-FixtureDigest 'a') (Get-FixtureDigest 'a') -RecordedUtc '2026-09-06T00:00:02Z'
$rollbackTerminal=Complete-RimePimeFixtureTerminal $rollbackContext $rollbackLock 'rolled-back' `
    (Get-FixtureDigest 'a') $false '2026-09-06T00:00:03Z'
$rollbackTerminalRetry=Complete-RimePimeFixtureTerminal $rollbackContext $rollbackLock 'rolled-back' `
    (Get-FixtureDigest 'a') $false '2026-09-06T00:00:03Z'
$rollbackChain=Read-RimePimeFixtureJournal $rollbackContext
Invoke-FixtureCheck { Assert-FixtureTrue ($started.new_record -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ($forward.new_record -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ($rollbackTerminalRetry.new_record -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ($rollbackChain.record_count -eq 4) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$rollbackChain.terminal.value.outcome -ceq 'rolled-back') }
Close-RimePimeFixtureJournalLock $rollbackLock
Invoke-FixtureCheck { Assert-FixtureTrue ([IO.File]::Exists((Join-Path $rollbackContext.state_root 'journal.lock'))) }

# Prepared -> forward -> commit -> restart decision -> cleanup -> terminal.
$commitContext=New-RimePimeFixtureTransactionContext $repo $fixture 'journal-commit'
$commitArtifacts=New-FixtureTransactionArtifacts $commitContext ('5'*32)
$commitPrepared=New-FixturePrepared ('5'*32) $commitArtifacts.registry.sha256 $commitArtifacts.removal.sha256
$commitLock=Open-RimePimeFixtureJournalLock $commitContext
$null=Start-RimePimeFixtureTransaction $commitContext $commitLock $commitPrepared
$commitForwardId=Get-RimePimeFixtureOperationId ('5'*32) 'apply-new-state'
$commitForward=Add-RimePimeFixtureStep $commitContext $commitLock $commitForwardId 'apply-new-state' 'forward' `
    (Get-FixtureDigest 'a') (Get-FixtureDigest 'e') (Get-FixtureDigest 'e') -RecordedUtc '2026-09-06T00:01:01Z'
$commitForwardRetry=Add-RimePimeFixtureStep $commitContext $commitLock $commitForwardId 'apply-new-state' 'forward' `
    (Get-FixtureDigest 'a') (Get-FixtureDigest 'e') (Get-FixtureDigest 'e') -RecordedUtc '2026-09-06T00:01:01Z'
Invoke-FixtureCheck { Assert-FixtureTrue ($commitForwardRetry.new_record -eq $false) }
Invoke-FixtureCheck { Assert-FixtureRejected {
    Add-RimePimeFixtureStep $commitContext $commitLock $commitForwardId 'apply-new-state' 'forward' `
        (Get-FixtureDigest 'a') (Get-FixtureDigest 'f') (Get-FixtureDigest 'f') -RecordedUtc '2026-09-06T00:01:01Z'
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    Add-RimePimeFixtureStep $commitContext $commitLock (Get-FixtureDigest 'f') 'unbound-operation' 'forward' `
        (Get-FixtureDigest 'a') (Get-FixtureDigest 'f') (Get-FixtureDigest 'f') -RecordedUtc '2026-09-06T00:01:01Z'
} }
Invoke-FixtureCheck { Assert-FixtureRejected {
    Add-RimePimeFixtureStep $commitContext $commitLock (Get-RimePimeFixtureOperationId ('5'*32) 'empty-step') `
        'empty-step' 'forward' (Get-FixtureDigest 'a') (Get-FixtureDigest 'a') (Get-FixtureDigest 'a') `
        -RecordedUtc '2026-09-06T00:01:01Z'
} }
$commit=Complete-RimePimeFixtureCommit $commitContext $commitLock (Get-FixtureDigest 'e') '2026-09-06T00:01:02Z'
Close-RimePimeFixtureJournalLock $commitLock
Remove-Module -Name rime-pime-fixture-transaction-journal -Force
Import-Module -Name $modulePath -Force -DisableNameChecking
$commitLock=Open-RimePimeFixtureJournalLock $commitContext
$commitDecision=Resume-RimePimeFixtureTransaction $commitContext $commitLock
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$commitDecision.disposition -ceq 'roll-forward-cleanup') }
$cleanupId=Get-RimePimeFixtureOperationId ('5'*32) 'cleanup-old-state'
$null=Add-RimePimeFixtureStep $commitContext $commitLock $cleanupId 'cleanup-old-state' 'cleanup' `
    (Get-FixtureDigest '6') (Get-FixtureDigest '7') (Get-FixtureDigest '7') -RecordedUtc '2026-09-06T00:01:03Z'
$commitTerminal=Complete-RimePimeFixtureTerminal $commitContext $commitLock 'committed' `
    (Get-FixtureDigest 'e') $false '2026-09-06T00:01:04Z'
$commitRetry=Complete-RimePimeFixtureCommit $commitContext $commitLock (Get-FixtureDigest 'e') '2026-09-06T00:01:02Z'
$commitChain=Read-RimePimeFixtureJournal $commitContext
Invoke-FixtureCheck { Assert-FixtureTrue ($commitRetry.new_record -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ($commitChain.record_count -eq 5) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$commitChain.records[1].value.protected_state_sha256 -ceq (Get-FixtureDigest 'b')) }
$commitDone=Resume-RimePimeFixtureTransaction $commitContext $commitLock
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$commitDone.disposition -ceq 'complete-noop') }
Close-RimePimeFixtureJournalLock $commitLock

# Persistent FileShare.None lock excludes a concurrent fixture writer.
$lockContext=New-RimePimeFixtureTransactionContext $repo $fixture 'exclusive-lock'
$firstLock=Open-RimePimeFixtureJournalLock $lockContext
Invoke-FixtureCheck { Assert-FixtureRejected { Open-RimePimeFixtureJournalLock $lockContext } }
Close-RimePimeFixtureJournalLock $firstLock
$secondLock=Open-RimePimeFixtureJournalLock $lockContext
Close-RimePimeFixtureJournalLock $secondLock
Invoke-FixtureCheck { Assert-FixtureTrue ([IO.File]::Exists((Join-Path $lockContext.state_root 'journal.lock'))) }

# Sidecar-last fault points: JSON-only tails are discarded; durable pairs replay.
$faultJsonContext=New-RimePimeFixtureTransactionContext $repo $fixture 'fault-prepared-json'
$faultJsonArtifacts=New-FixtureTransactionArtifacts $faultJsonContext ('6'*32)
$faultLock=Open-RimePimeFixtureJournalLock $faultJsonContext
$faultPrepared=New-FixturePrepared ('6'*32) $faultJsonArtifacts.registry.sha256 $faultJsonArtifacts.removal.sha256
Invoke-FixtureCheck { Assert-FixtureRejected {
    Start-RimePimeFixtureTransaction $faultJsonContext $faultLock $faultPrepared -FaultAt 'after-json-flush'
} }
Close-RimePimeFixtureJournalLock $faultLock
Remove-Module -Name rime-pime-fixture-transaction-journal -Force
Import-Module -Name $modulePath -Force -DisableNameChecking
$faultLock=Open-RimePimeFixtureJournalLock $faultJsonContext
$faultJsonDecision=Resume-RimePimeFixtureTransaction $faultJsonContext $faultLock
Invoke-FixtureCheck { Assert-FixtureTrue ($faultJsonDecision.uncommitted_tail_discarded -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$faultJsonDecision.disposition -ceq 'no-mutation-admitted') }
Close-RimePimeFixtureJournalLock $faultLock

$faultPreparedContext=New-RimePimeFixtureTransactionContext $repo $fixture 'fault-prepared-sealed'
$faultPreparedArtifacts=New-FixtureTransactionArtifacts $faultPreparedContext ('7'*32)
$faultLock=Open-RimePimeFixtureJournalLock $faultPreparedContext
$faultPrepared=New-FixturePrepared ('7'*32) $faultPreparedArtifacts.registry.sha256 $faultPreparedArtifacts.removal.sha256
Invoke-FixtureCheck { Assert-FixtureRejected {
    Start-RimePimeFixtureTransaction $faultPreparedContext $faultLock $faultPrepared -FaultAt 'after-sidecar-flush'
} }
Close-RimePimeFixtureJournalLock $faultLock
$faultLock=Open-RimePimeFixtureJournalLock $faultPreparedContext
$faultPreparedDecision=Resume-RimePimeFixtureTransaction $faultPreparedContext $faultLock
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$faultPreparedDecision.disposition -ceq 'rollback-to-before') }
Close-RimePimeFixtureJournalLock $faultLock

$faultCommitContext=New-RimePimeFixtureTransactionContext $repo $fixture 'fault-commit-json'
$faultCommitArtifacts=New-FixtureTransactionArtifacts $faultCommitContext ('8'*32)
$faultLock=Open-RimePimeFixtureJournalLock $faultCommitContext
$null=Start-RimePimeFixtureTransaction $faultCommitContext $faultLock `
    (New-FixturePrepared ('8'*32) $faultCommitArtifacts.registry.sha256 $faultCommitArtifacts.removal.sha256)
$null=Add-RimePimeFixtureStep $faultCommitContext $faultLock (Get-RimePimeFixtureOperationId ('8'*32) 'forward') `
    'forward' 'forward' (Get-FixtureDigest 'a') (Get-FixtureDigest '8') (Get-FixtureDigest '8') `
    -RecordedUtc '2026-09-06T00:02:01Z'
Invoke-FixtureCheck { Assert-FixtureRejected {
    Complete-RimePimeFixtureCommit $faultCommitContext $faultLock (Get-FixtureDigest '8') `
        '2026-09-06T00:02:02Z' -FaultAt 'before-sidecar-create'
} }
Close-RimePimeFixtureJournalLock $faultLock
$faultLock=Open-RimePimeFixtureJournalLock $faultCommitContext
$faultCommitDecision=Resume-RimePimeFixtureTransaction $faultCommitContext $faultLock
Invoke-FixtureCheck { Assert-FixtureTrue ($faultCommitDecision.uncommitted_tail_discarded -eq $true) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$faultCommitDecision.disposition -ceq 'rollback-to-before') }
Close-RimePimeFixtureJournalLock $faultLock

$faultSealedContext=New-RimePimeFixtureTransactionContext $repo $fixture 'fault-commit-sealed'
$faultSealedArtifacts=New-FixtureTransactionArtifacts $faultSealedContext ('9'*32)
$faultLock=Open-RimePimeFixtureJournalLock $faultSealedContext
$null=Start-RimePimeFixtureTransaction $faultSealedContext $faultLock `
    (New-FixturePrepared ('9'*32) $faultSealedArtifacts.registry.sha256 $faultSealedArtifacts.removal.sha256)
$null=Add-RimePimeFixtureStep $faultSealedContext $faultLock (Get-RimePimeFixtureOperationId ('9'*32) 'forward') `
    'forward' 'forward' (Get-FixtureDigest 'a') (Get-FixtureDigest '9') (Get-FixtureDigest '9') `
    -RecordedUtc '2026-09-06T00:03:01Z'
Invoke-FixtureCheck { Assert-FixtureRejected {
    Complete-RimePimeFixtureCommit $faultSealedContext $faultLock (Get-FixtureDigest '9') `
        '2026-09-06T00:03:02Z' -FaultAt 'after-sidecar-flush'
} }
Close-RimePimeFixtureJournalLock $faultLock
$faultLock=Open-RimePimeFixtureJournalLock $faultSealedContext
$faultSealedDecision=Resume-RimePimeFixtureTransaction $faultSealedContext $faultLock
Invoke-FixtureCheck { Assert-FixtureTrue ($faultSealedDecision.uncommitted_tail_discarded -eq $false) }
Invoke-FixtureCheck { Assert-FixtureTrue ([string]$faultSealedDecision.disposition -ceq 'roll-forward-cleanup') }
Close-RimePimeFixtureJournalLock $faultLock

# Integrity, closed-schema, chain-binding, and journal namespace tamper rejection.
$digestTamperContext=New-RimePimeFixtureTransactionContext $repo $fixture 'digest-tamper'
$digestTamperArtifacts=New-FixtureTransactionArtifacts $digestTamperContext ('a'*32)
$digestLock=Open-RimePimeFixtureJournalLock $digestTamperContext
$null=Start-RimePimeFixtureTransaction $digestTamperContext $digestLock `
    (New-FixturePrepared ('a'*32) $digestTamperArtifacts.registry.sha256 $digestTamperArtifacts.removal.sha256)
Close-RimePimeFixtureJournalLock $digestLock
$digestSidecar=Join-Path $digestTamperContext.records_root '00000000-prepared.json.sha256'
[IO.File]::Delete($digestSidecar)
Write-FixtureTestBytes $digestSidecar ([Text.Encoding]::ASCII.GetBytes((('f'*64)+'  00000000-prepared.json'+"`n")))
Invoke-FixtureCheck { Assert-FixtureRejected { Read-RimePimeFixtureJournal $digestTamperContext } }

$bindingContext=New-RimePimeFixtureTransactionContext $repo $fixture 'binding-tamper'
$bindingArtifacts=New-FixtureTransactionArtifacts $bindingContext ('b'*32)
$bindingLock=Open-RimePimeFixtureJournalLock $bindingContext
$null=Start-RimePimeFixtureTransaction $bindingContext $bindingLock `
    (New-FixturePrepared ('b'*32) $bindingArtifacts.registry.sha256 $bindingArtifacts.removal.sha256)
$null=Add-RimePimeFixtureStep $bindingContext $bindingLock (Get-RimePimeFixtureOperationId ('b'*32) 'forward') `
    'forward' 'forward' (Get-FixtureDigest 'a') (Get-FixtureDigest 'd') (Get-FixtureDigest 'd') `
    -RecordedUtc '2026-09-06T00:04:01Z'
Close-RimePimeFixtureJournalLock $bindingLock
$bindingPath=Join-Path $bindingContext.records_root '00000001-step.json'
$bindingValue=Read-FixtureTestJson $bindingPath
[IO.File]::Delete($bindingPath); [IO.File]::Delete($bindingPath+'.sha256')
$bindingValue.protected_state_sha256=Get-FixtureDigest 'e'
$null=Write-FixtureTestSealedJson $bindingValue $bindingPath
Invoke-FixtureCheck { Assert-FixtureRejected { Read-RimePimeFixtureJournal $bindingContext } }

$openSchemaContext=New-RimePimeFixtureTransactionContext $repo $fixture 'open-schema-tamper'
$openSchemaArtifacts=New-FixtureTransactionArtifacts $openSchemaContext ('c'*32)
$openLock=Open-RimePimeFixtureJournalLock $openSchemaContext
$null=Start-RimePimeFixtureTransaction $openSchemaContext $openLock `
    (New-FixturePrepared ('c'*32) $openSchemaArtifacts.registry.sha256 $openSchemaArtifacts.removal.sha256)
Close-RimePimeFixtureJournalLock $openLock
$openPath=Join-Path $openSchemaContext.records_root '00000000-prepared.json'
$openValue=Read-FixtureTestJson $openPath
[IO.File]::Delete($openPath); [IO.File]::Delete($openPath+'.sha256')
$openValue | Add-Member -NotePropertyName extra -NotePropertyValue $false
$null=Write-FixtureTestSealedJson $openValue $openPath
Invoke-FixtureCheck { Assert-FixtureRejected { Read-RimePimeFixtureJournal $openSchemaContext } }

$namespaceContext=New-RimePimeFixtureTransactionContext $repo $fixture 'namespace-tamper'
Write-FixtureTestBytes (Join-Path $namespaceContext.records_root 'foreign-control.tmp') ([byte[]](1,2,3))
Invoke-FixtureCheck { Assert-FixtureRejected { Read-RimePimeFixtureJournal $namespaceContext } }
$namespaceDirectoryContext=New-RimePimeFixtureTransactionContext $repo $fixture 'namespace-directory-tamper'
$null=[IO.Directory]::CreateDirectory((Join-Path $namespaceDirectoryContext.records_root 'foreign-control-dir'))
Invoke-FixtureCheck { Assert-FixtureRejected { Read-RimePimeFixtureJournal $namespaceDirectoryContext } }

# Static negative surface: no product mutation APIs, recursive deletion, or registry provider access.
$sourceText=[IO.File]::ReadAllText($helperPath)+"`n"+[IO.File]::ReadAllText($modulePath)
foreach ($pattern in @(
        '(?i)\bStart-Process\b','(?i)\bGet-Process\b','(?i)\bStop-Process\b','(?i)\bInvoke-Expression\b',
        '(?i)\bInvoke-Command\b','(?i)\bGet-CimInstance\b','(?i)\bStdRegProv\b','(?i)\breg(?:\.exe)?\b',
        '(?i)\bGet-ItemProperty\b','(?i)\bSet-ItemProperty\b','(?i)\bNew-ItemProperty\b',
        '(?i)\bRemove-ItemProperty\b','(?i)Registry::','(?i)HKLM:','(?i)HKCU:',
        '(?i)HKEY_USERS','(?i)HKU:','(?i)Program Files','(?i)\bAPPDATA\b','(?i)\bLOCALAPPDATA\b',
        '(?i)\bRemove-Item\b[^\r\n]*\b-Recurse\b','(?i)\bRMDir\b[^\r\n]*/[rs]',
        '(?i)\b(?:cmd|powershell|pwsh|msiexec|makensis)\.exe\b',
        '(?i)\[IO\.Directory\]::Delete\([^\r\n]+,\s*\$true\)')) {
    Invoke-FixtureCheck { Assert-FixtureTrue ($sourceText -notmatch $pattern) }
}

$expectedExports=[string[]]@(
    'Add-RimePimeFixtureStep','Assert-RimePimeFixtureRegistryState','Assert-RimePimeFixtureRemovalManifest',
    'Assert-RimePimeFixtureTransactionContext','Close-RimePimeFixtureJournalLock',
    'Complete-RimePimeFixtureCommit','Complete-RimePimeFixtureTerminal','Get-RimePimeFixtureOperationId',
    'Get-RimePimeFixtureRegistryCoordinateCatalog','Get-RimePimeFixtureRemovalPlan',
    'Invoke-RimePimeFixtureExactRemoval','New-RimePimeFixturePreparedRecord',
    'New-RimePimeFixtureRegistryRecord','New-RimePimeFixtureRegistryState',
    'New-RimePimeFixtureRemovalManifest','New-RimePimeFixtureTransactionContext',
    'Open-RimePimeFixtureJournalLock','Read-RimePimeFixtureJournal',
    'Read-RimePimeFixtureRegistryState','Read-RimePimeFixtureRemovalManifest',
    'Resume-RimePimeFixtureTransaction','Start-RimePimeFixtureTransaction',
    'Test-RimePimeFixtureRemovalClosure','Write-RimePimeFixtureInstallFile',
    'Write-RimePimeFixtureRegistryState','Write-RimePimeFixtureRemovalManifest'
)
[Array]::Sort($expectedExports,[StringComparer]::Ordinal)
$actualExports=[string[]]@((Get-Command -Module rime-pime-fixture-transaction-journal).Name)
[Array]::Sort($actualExports,[StringComparer]::Ordinal)
Invoke-FixtureCheck {
    Assert-FixtureTrue ($actualExports.Count -eq $expectedExports.Count)
    for ($i=0;$i -lt $expectedExports.Count;$i++) { Assert-FixtureTrue ($actualExports[$i] -ceq $expectedExports[$i]) }
}

$helperSha=(Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant()
$moduleSha=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
$testSha=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$aggregate=Get-FixtureTestBytesSha256 ([Text.Encoding]::ASCII.GetBytes(
    "$($rollbackChain.head_sha256)`n$($commitChain.head_sha256)`n$($registryReceipt.sha256)`n$($payload.receipt.sha256)`n"))
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-fixture-journal-test-result-v1'
    powershell_edition=[string]$PSVersionTable.PSEdition
    powershell_version=$PSVersionTable.PSVersion.ToString()
    fixture_only=$true
    checks_total=[int]$script:checkCount
    checks_passed=[int]$script:checkCount
    checks_failed=0
    aggregate_evidence_sha256=$aggregate
    helper_sha256=$helperSha
    module_sha256=$moduleSha
    test_sha256=$testSha
    registry_snapshot_sha256=[string]$registryReceipt.sha256
    removal_manifest_sha256=[string]$payload.receipt.sha256
    installer_or_uninstaller_executed=$false
    registry_provider_used=$false
    product_process_accessed=$false
    production_user_data_accessed=$false
    recursive_delete_used=$false
    unexpected_filenames_disclosed=$false
    concurrent_replacement_excluded=$false
    real_crash_or_power_loss_claimed=$false
    cross_process_restart_executed=$false
    rollback_or_cleanup_adapter_executed=$false
    directory_metadata_durability_proven=$false
}
$resultReceipt=Write-FixtureTestSealedJson $result (Join-Path $fixture 'result.json')
Write-Output ("PASS: checks={0}; evidence_sha256={1}; unsafe_claims=false" -f $script:checkCount,$resultReceipt.sha256)
