[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$parent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $parent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-transaction-faults-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-transaction-faults-* fixture root.'
}
for($cursor=$parent;$cursor;$cursor=Split-Path -Parent $cursor) {
    if((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Transaction-fault evidence path traverses a reparse point.'
    }
    if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
}
if(-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$enginePath=Join-Path $PSScriptRoot 'rime-pime-transaction-engine.ps1'
if(Test-Path -LiteralPath $enginePath -PathType Leaf){. $enginePath}
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$checks.Add([ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message})}
}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Must-Reject([scriptblock]$Body){$rejected=$false;try{& $Body|Out-Null}catch{$rejected=$true};Assert-True $rejected 'Expected fail-closed rejection.'}
function New-FixtureHash([string]$Label){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Label)))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Copy-Fixture($Value){return ($Value|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
function Assert-ExactSequence($Actual,[string[]]$Expected,[string]$Name) {
    $values=@($Actual)
    Assert-True ($values.Count -eq $Expected.Count) "$Name count differs: expected $($Expected.Count), actual $($values.Count)."
    for($index=0;$index -lt $Expected.Count;$index++) {
        Assert-True ([string]$values[$index] -ceq [string]$Expected[$index]) "$Name differs at index $index."
    }
    Assert-True (@($values|Select-Object -Unique).Count -eq $values.Count) "$Name contains duplicates."
}
function Assert-DimensionState($Actual,$Expected,[string]$Dimension,[string]$Context) {
    foreach($field in @($script:dimensionFields[$Dimension])) {
        Assert-True ($null -ne $Actual.PSObject.Properties[$field]) "$Context field is missing: $field"
        Assert-True ($null -ne $Expected.PSObject.Properties[$field]) "$Context expected field is missing: $field"
        Assert-True ([object]::Equals($Actual.$field,$Expected.$field)) "$Context differs for $Dimension/$field."
    }
}

# These catalogs are deliberately independent of the engine. Removing or
# reordering an engine stage/dimension must not make this test shrink with it.
$expectedStages=@(
    'validate-selected-root','validate-complete-manifest','validate-package-architectures',
    'stage-complete-package','verify-staged-hashes','snapshot-target','snapshot-protected',
    'write-prepared-journal','directed-stop','verify-quiescence','quarantine-old-root',
    'activate-staged-root','unregister-old','register-new','verify-registration',
    'apply-target-user-profile','write-product-registration','verify-product-registration',
    'start-runtime-non-elevated','verify-runtime','verify-protected-state',
    'write-activation-commit','purge-quarantine','finalize-journal'
)
$expectedRollbackDimensions=@('package','registration','registry-kinds','run','uninstall',
    'target-user-tip','runtime','shortcut','font','pending-reboot')
$script:dimensionFields=[ordered]@{
    package=@('target_present','package_hash')
    registration=@('registration_hash')
    'registry-kinds'=@('registry_kinds_hash')
    run=@('run_hash')
    uninstall=@('uninstall_hash')
    'target-user-tip'=@('user_tip_hash')
    runtime=@('runtime_hash','runtime_running','runtime_sid','runtime_integrity')
    shortcut=@('shortcut_hash')
    font=@('font_hash')
    'pending-reboot'=@('pending_reboot_hash')
}

function New-InitialState {
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-synthetic-state-v1';target_present=$true
        package_hash=New-FixtureHash 'initial.package';registration_hash=New-FixtureHash 'initial.registration'
        registry_kinds_hash=New-FixtureHash 'initial.registry-kinds';run_hash=New-FixtureHash 'initial.run'
        uninstall_hash=New-FixtureHash 'initial.uninstall';user_tip_hash=New-FixtureHash 'initial.user-tip'
        runtime_hash=New-FixtureHash 'initial.runtime';runtime_running=$true;runtime_sid='S-1-5-21-100-200-300-1001'
        runtime_integrity='medium';shortcut_hash=New-FixtureHash 'initial.shortcut';font_hash=New-FixtureHash 'initial.font'
        pending_reboot_hash=New-FixtureHash 'initial.pending-reboot';settings_hash=New-FixtureHash 'protected.settings'
        learning_hash=New-FixtureHash 'protected.learning';peer_hash=New-FixtureHash 'protected.peer'
        default_input_hash=New-FixtureHash 'protected.default-input'
    }
}
function New-Candidate([string[]]$Architectures=@('x64','x86')) {
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-synthetic-candidate-v1';package_hash=New-FixtureHash 'candidate.package'
        manifest_hash=New-FixtureHash 'candidate.manifest';registration_hash=New-FixtureHash 'candidate.registration'
        registry_kinds_hash=New-FixtureHash 'candidate.registry-kinds';run_hash=New-FixtureHash 'candidate.run'
        uninstall_hash=New-FixtureHash 'candidate.uninstall';user_tip_hash=New-FixtureHash 'candidate.user-tip'
        runtime_hash=New-FixtureHash 'candidate.runtime';shortcut_hash=New-FixtureHash 'candidate.shortcut'
        font_hash=New-FixtureHash 'candidate.font';pending_reboot_hash=New-FixtureHash 'candidate.pending-reboot'
        architectures=$Architectures
    }
}
function New-ExpectedCandidateState($Before,$Candidate,[string]$TargetUserSid) {
    $state=Copy-Fixture $Before
    $state.target_present=$true
    foreach($field in @('package_hash','registration_hash','registry_kinds_hash','run_hash','uninstall_hash',
            'user_tip_hash','runtime_hash','shortcut_hash','font_hash','pending_reboot_hash')) {
        $state.$field=[string]$Candidate.$field
    }
    $state.runtime_running=$true;$state.runtime_sid=$TargetUserSid;$state.runtime_integrity='medium'
    return $state
}
$sid='S-1-5-21-100-200-300-1001'
$root='C:\DP1-Fixture\RimePime\current'
$faultCaseCount=0

Check 'transaction-engine-functions-are-present' {
    foreach($name in @('Get-YimePimeUpgradeStageCatalog','Get-YimePimeRollbackDimensionCatalog',
            'Invoke-YimePimeSyntheticUpgradeTransaction')) {
        Assert-True ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) "Missing function: $name"
    }
}
Check 'stage-and-rollback-catalogs-are-exact-independent-contracts' {
    $stages=@(Get-YimePimeUpgradeStageCatalog)
    Assert-ExactSequence @($stages.id) $expectedStages 'Upgrade stage catalog'
    Assert-ExactSequence @(Get-YimePimeRollbackDimensionCatalog) $expectedRollbackDimensions 'Rollback dimension catalog'
    for($index=0;$index -lt $stages.Count;$index++) {
        Assert-True ([int]$stages[$index].position -eq $index+1) "Stage position differs: $($stages[$index].id)"
    }
}
Check 'stage-order-places-journal-before-mutation-and-commit-before-purge' {
    $stages=@(Get-YimePimeUpgradeStageCatalog);$ids=@($stages.id)
    $firstMutation=@($stages|Where-Object active_product_mutation)[0]
    Assert-True ($firstMutation.id -eq 'directed-stop') 'A live-product mutation occurs before directed stop.'
    Assert-True ([array]::IndexOf($ids,'verify-staged-hashes') -lt [array]::IndexOf($ids,'snapshot-target')) 'Target snapshot precedes complete staged-package verification.'
    Assert-True ([array]::IndexOf($ids,'write-prepared-journal') -lt [array]::IndexOf($ids,'directed-stop')) 'Prepared journal is too late.'
    Assert-True ([array]::IndexOf($ids,'directed-stop') -lt [array]::IndexOf($ids,'verify-quiescence')) 'Quiescence is claimed before stop.'
    Assert-True ([array]::IndexOf($ids,'verify-registration') -lt [array]::IndexOf($ids,'start-runtime-non-elevated')) 'Runtime starts before registration convergence.'
    Assert-True ([array]::IndexOf($ids,'write-activation-commit') -lt [array]::IndexOf($ids,'purge-quarantine')) 'Recoverable predecessor is purged before commit.'
}
Check 'successful-upgrade-converges-every-owned-dimension-and-protects-independent-state' {
    foreach($architectureSet in @(@('x64','x86'),@('arm64','x86'))) {
        $before=New-InitialState;$candidate=New-Candidate $architectureSet;$expected=New-ExpectedCandidateState $before $candidate $sid
        $beforeFingerprint=($before|ConvertTo-Json -Depth 30 -Compress)
        $candidateFingerprint=($candidate|ConvertTo-Json -Depth 30 -Compress)
        $result=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState $before -Candidate $candidate `
            -InstallRoot $root -TargetUserSid $sid
        Assert-True ($result.passed -and $result.outcome -eq 'committed' -and $result.commit_written -and
            $result.quarantine_purged -and -not $result.cleanup_pending -and -not $result.journal_retained -and
            -not $result.recovery_archive_retained) 'Successful transaction did not commit and finalize cleanly.'
        Assert-ExactSequence @($result.events|Where-Object phase -ne 'rollback'|ForEach-Object id) $expectedStages 'Successful forward events'
        foreach($dimension in $expectedRollbackDimensions) {
            Assert-DimensionState $result.final_state $expected $dimension 'Successful candidate convergence'
        }
        foreach($field in @('settings_hash','learning_hash','peer_hash','default_input_hash')) {
            Assert-True ([object]::Equals($result.final_state.$field,$before.$field)) "Protected state changed: $field"
        }
        Assert-True (($before|ConvertTo-Json -Depth 30 -Compress) -ceq $beforeFingerprint -and
            ($candidate|ConvertTo-Json -Depth 30 -Compress) -ceq $candidateFingerprint) 'Input object was mutated.'
        Assert-True (-not $result.actual_filesystem_registry_process_or_elevation_executed) 'Synthetic engine claimed OS execution.'
    }
}
Check 'every-stage-supports-before-and-after-faults-with-the-commit-boundary-preserved' {
    $firstMutation=[array]::IndexOf($expectedStages,'directed-stop')
    $commit=[array]::IndexOf($expectedStages,'write-activation-commit')
    foreach($architectureSet in @(@('x64','x86'),@('arm64','x86'))) {
      for($index=0;$index -lt $expectedStages.Count;$index++) {
        foreach($point in @('before','after')) {
            $script:faultCaseCount++
            $result=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate $architectureSet) `
                -InstallRoot $root -TargetUserSid $sid -FaultAt $expectedStages[$index] -FaultPoint $point
            $mutationApplied=($index -gt $firstMutation -or ($index -eq $firstMutation -and $point -eq 'after'))
            $commitApplied=($index -gt $commit -or ($index -eq $commit -and $point -eq 'after'))
            $expectedOutcome=if($commitApplied){'committed-cleanup-pending'}elseif($mutationApplied){'rolled-back'}else{'aborted-no-mutation'}
            Assert-True (-not $result.passed -and [string]$result.outcome -ceq $expectedOutcome) `
                "Fault boundary was misclassified: $($expectedStages[$index])/$point"
            $failed=@($result.events|Where-Object{[string]$_.id -ceq $expectedStages[$index] -and [string]$_.status -ceq 'failed'})
            Assert-True ($failed.Count -eq 1 -and [string]$failed[0].fault_point -ceq $point -and
                [bool]$failed[0].stage_effect_applied -eq ($point -eq 'after')) `
                "Fault event is incomplete: $($expectedStages[$index])/$point"
            if($expectedOutcome -eq 'rolled-back') {
                Assert-True ($result.target_state_restored -and -not $result.commit_written) `
                    "Precommit failure was not restored: $($expectedStages[$index])/$point"
                Assert-ExactSequence @($result.rollback_dimensions_restored) $expectedRollbackDimensions 'Completed rollback dimensions'
            } elseif($expectedOutcome -eq 'aborted-no-mutation') {
                Assert-True ($result.target_state_restored -and @($result.rollback_dimensions_restored).Count -eq 0) `
                    "Pre-mutation failure changed state: $($expectedStages[$index])/$point"
            } else {
                Assert-True ($result.commit_written -and -not $result.target_state_restored) `
                    "Postcommit failure crossed back over commit: $($expectedStages[$index])/$point"
            }
        }
      }
    }
}
Check 'successful-rollback-restores-all-ten-dimensions-in-order-with-events' {
    $result=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'verify-protected-state' -FaultPoint before
    Assert-True ($result.outcome -eq 'rolled-back' -and $result.target_state_restored -and
        $result.rollback_dimensions_verified -eq $expectedRollbackDimensions.Count) 'Full rollback did not restore exact initial state.'
    Assert-ExactSequence @($result.rollback_dimensions_restored) $expectedRollbackDimensions 'Completed rollback dimensions'
    $events=@($result.events|Where-Object phase -eq 'rollback')
    Assert-ExactSequence @($events.id) @($expectedRollbackDimensions|ForEach-Object{"restore-$_"}) 'Rollback event IDs'
    Assert-True (@($events|Where-Object status -ne 'completed').Count -eq 0) 'A successful rollback event did not complete.'
}
Check 'rollback-fault-restores-only-the-prefix-and-records-the-failed-dimension' {
    foreach($failedDimension in $expectedRollbackDimensions) {
        $before=New-InitialState;$candidate=New-Candidate;$candidateState=New-ExpectedCandidateState $before $candidate $sid
        $failedIndex=[array]::IndexOf($expectedRollbackDimensions,$failedDimension)
        $prefix=@($expectedRollbackDimensions|Select-Object -First $failedIndex)
        $result=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState $before -Candidate $candidate `
            -InstallRoot $root -TargetUserSid $sid -FaultAt 'verify-protected-state' -FaultPoint before -RollbackFault $failedDimension
        Assert-True (-not $result.passed -and $result.outcome -eq 'recovery-required' -and
            $result.journal_retained -and $result.recovery_archive_retained -and -not $result.target_state_restored -and
            [string]$result.rollback_failed_dimension -ceq $failedDimension -and
            [int]$result.rollback_dimensions_verified -eq $failedIndex) "Rollback failure was hidden: $failedDimension"
        Assert-ExactSequence @($result.rollback_dimensions_restored) $prefix "Rollback prefix for $failedDimension"
        $events=@($result.events|Where-Object phase -eq 'rollback')
        Assert-True ($events.Count -eq $failedIndex+1) "Rollback suffix unexpectedly executed: $failedDimension"
        $expectedEventIds=@($prefix|ForEach-Object{"restore-$_"})+@("restore-$failedDimension")
        Assert-ExactSequence @($events.id) $expectedEventIds "Rollback events for $failedDimension"
        Assert-True ([string]$events[-1].status -ceq 'failed') "Failed rollback dimension lacks a failure event: $failedDimension"
        for($index=0;$index -lt $expectedRollbackDimensions.Count;$index++) {
            $expectedState=if($index -lt $failedIndex){$before}else{$candidateState}
            Assert-DimensionState $result.final_state $expectedState $expectedRollbackDimensions[$index] "Rollback boundary for $failedDimension"
        }
    }
}
Check 'postcommit-before-after-cleanup-state-is-not-misreported-as-rollback' {
    $commitAfter=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'write-activation-commit' -FaultPoint after
    Assert-True ($commitAfter.outcome -eq 'committed-cleanup-pending' -and $commitAfter.commit_written -and
        -not $commitAfter.target_state_restored) 'A failure after durable commit was rolled back.'
    $purgeBefore=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'purge-quarantine' -FaultPoint before
    $purgeAfter=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'purge-quarantine' -FaultPoint after
    Assert-True (-not $purgeBefore.quarantine_purged -and $purgeAfter.quarantine_purged) 'Purge before/after boundary is not modeled.'
    $finalizeBefore=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'finalize-journal' -FaultPoint before
    $finalizeAfter=Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'finalize-journal' -FaultPoint after
    Assert-True ($finalizeBefore.journal_retained -and -not $finalizeAfter.journal_retained) 'Journal finalize before/after boundary is not modeled.'
}
Check 'unknown-fault-path-sid-and-candidate-drift-are-rejected' {
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'not-a-stage'}
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultPoint after}
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid -FaultAt 'validate-selected-root' -FaultPoint before -RollbackFault package}
    foreach($badRoot in @('C:\Other\Root','C:\DP1-Fixture\RimePime/current','C:\DP1-Fixture\RimePime\CON',
            'C:\DP1-Fixture\RimePime\current.','C:\DP1-Fixture\RimePime\current ',
            'C:\DP1-Fixture\RimePime\\current')) {
        Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
            -InstallRoot $badRoot -TargetUserSid $sid}
    }
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid 'S-1-5-21-100-200-300-2002'}
    $bad=New-Candidate;$bad.architectures=@('x64')
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate $bad `
        -InstallRoot $root -TargetUserSid $sid}
    foreach($missing in @('runtime_hash','pending_reboot_hash')) {
        $bad=New-Candidate;$bad.PSObject.Properties.Remove($missing)
        Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate $bad `
            -InstallRoot $root -TargetUserSid $sid}
    }
    $bad=New-InitialState;$bad|Add-Member -NotePropertyName unclassified_hash -NotePropertyValue (New-FixtureHash 'foreign.state')
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState $bad -Candidate (New-Candidate) `
        -InstallRoot $root -TargetUserSid $sid}
    $bad=New-Candidate;$bad|Add-Member -NotePropertyName unclassified_hash -NotePropertyValue (New-FixtureHash 'foreign.candidate')
    Must-Reject {Invoke-YimePimeSyntheticUpgradeTransaction -InitialState (New-InitialState) -Candidate $bad `
        -InstallRoot $root -TargetUserSid $sid}
}

$failed=@($checks|Where-Object{-not $_.passed})
$receipt=[ordered]@{
    schema_version='yime-rime-pime-transaction-fault-matrix-v2';passed=($failed.Count -eq 0)
    checks=$checks.ToArray();checks_count=$checks.Count;failed_count=$failed.Count
    expected_stage_count=$expectedStages.Count;expected_rollback_dimension_count=$expectedRollbackDimensions.Count
    fault_case_count=$faultCaseCount
    stage_count=$(if(Get-Command Get-YimePimeUpgradeStageCatalog -ErrorAction SilentlyContinue){@(Get-YimePimeUpgradeStageCatalog).Count}else{0})
    rollback_dimension_count=$(if(Get-Command Get-YimePimeRollbackDimensionCatalog -ErrorAction SilentlyContinue){@(Get-YimePimeRollbackDimensionCatalog).Count}else{0})
    engine_sha256=$(if(Test-Path -LiteralPath $enginePath){(Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null})
    test_sha256=(Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    actual_filesystem_registry_process_or_elevation_executed=$false;installed_runtime_examined=$false
    production_or_user_data_read=$false;default_input_method_changed=$false;dp1_full_implementation_passed=$false
    dp2_physical_acceptance_passed=$false
}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),(($receipt|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Output "Rime/PIME synthetic transaction fault matrix: $($checks.Count) checks; $($failed.Count) failed; evidence $output"
if($failed.Count){exit 1}
