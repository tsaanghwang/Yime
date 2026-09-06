# Pure Rime/PIME upgrade transaction model. Importing and invoking these
# functions performs no filesystem, registry, process, elevation, installer,
# recovery, or input-method operation. Native wiring is a later evidence gate.

function Get-YimePimeUpgradeStageCatalog {
    $definitions=@(
        @('validate-selected-root','preflight',$false),
        @('validate-complete-manifest','preflight',$false),
        @('validate-package-architectures','preflight',$false),
        @('stage-complete-package','staging',$false),
        @('verify-staged-hashes','staging',$false),
        @('snapshot-target','snapshot',$false),
        @('snapshot-protected','snapshot',$false),
        @('write-prepared-journal','journal',$false),
        @('directed-stop','activation',$true),
        @('verify-quiescence','activation',$true),
        @('quarantine-old-root','activation',$true),
        @('activate-staged-root','activation',$true),
        @('unregister-old','registration',$true),
        @('register-new','registration',$true),
        @('verify-registration','registration',$true),
        @('apply-target-user-profile','registration',$true),
        @('write-product-registration','registration',$true),
        @('verify-product-registration','registration',$true),
        @('start-runtime-non-elevated','runtime',$true),
        @('verify-runtime','runtime',$true),
        @('verify-protected-state','verification',$true),
        @('write-activation-commit','commit',$true),
        @('purge-quarantine','cleanup',$true),
        @('finalize-journal','cleanup',$true)
    )
    for($index=0;$index -lt $definitions.Count;$index++) {
        [pscustomobject][ordered]@{
            position=$index+1
            id=[string]$definitions[$index][0]
            phase=[string]$definitions[$index][1]
            active_product_mutation=[bool]$definitions[$index][2]
        }
    }
}

function Get-YimePimeRollbackDimensionCatalog {
    return @('package','registration','registry-kinds','run','uninstall','target-user-tip',
        'runtime','shortcut','font','pending-reboot')
}

function Get-YimePimeSyntheticRollbackFieldMap {
    return [ordered]@{
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
}

function Copy-YimePimeSyntheticValue($Value) {
    return ($Value|ConvertTo-Json -Depth 30|ConvertFrom-Json)
}

function Assert-YimePimeSyntheticHash([string]$Value,[string]$Name) {
    if($Value -cnotmatch '^[0-9a-f]{64}$'){throw "Invalid synthetic hash: $Name"}
}

function Assert-YimePimeSyntheticClosedProperties($Value,[string[]]$Expected,[string]$Name) {
    $actual=@($Value.PSObject.Properties.Name)
    if($actual.Count -ne $Expected.Count){throw "$Name field set is not closed."}
    foreach($field in $Expected) {
        if($actual -cnotcontains $field){throw "$Name field is missing: $field"}
    }
    foreach($field in $actual) {
        if($Expected -cnotcontains [string]$field){throw "$Name contains an unknown field: $field"}
    }
}

function Assert-YimePimeSyntheticFixturePath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -cnotmatch '^[A-Za-z]:\\' -or
        $Path -match '[/<>|"?*\x00-\x1f]' -or $Path.Substring(2).Contains(':')) {
        throw 'Synthetic Rime/PIME transaction requires a canonical local fixture path.'
    }
    $parts=@($Path.Substring(3).Split([char]92))
    if($parts.Count -eq 0){throw 'Synthetic Rime/PIME transaction requires a product directory.'}
    foreach($part in $parts) {
        if([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part -match '[. ]$' -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'Synthetic Rime/PIME transaction path contains an ambiguous component.'
        }
    }
    $resolved=[IO.Path]::GetFullPath($Path)
    if(-not [string]::Equals($resolved,$Path,[StringComparison]::OrdinalIgnoreCase) -or
        -not $resolved.StartsWith('C:\DP1-Fixture\RimePime\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Synthetic Rime/PIME transaction root is outside the owned namespace.'
    }
    return $resolved
}

function Get-YimePimeSyntheticStateFingerprint($State) {
    $json=$State|ConvertTo-Json -Depth 20 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Assert-YimePimeSyntheticUpgradeInputs {
    param($InitialState,$Candidate,[string]$InstallRoot,[string]$TargetUserSid,
        [string]$FaultAt,[string]$FaultPoint,[bool]$FaultPointSpecified,[string]$RollbackFault)
    if($null -eq $InitialState -or [string]$InitialState.schema_version -cne 'yime-pime-synthetic-state-v1') {
        throw 'Unknown synthetic initial state.'
    }
    if($null -eq $Candidate -or [string]$Candidate.schema_version -cne 'yime-pime-synthetic-candidate-v1') {
        throw 'Unknown synthetic candidate.'
    }
    $stateFields=@('schema_version','target_present','package_hash','registration_hash','registry_kinds_hash',
        'run_hash','uninstall_hash','user_tip_hash','runtime_hash','runtime_running','runtime_sid',
        'runtime_integrity','shortcut_hash','font_hash','pending_reboot_hash','settings_hash','learning_hash',
        'peer_hash','default_input_hash')
    $candidateFields=@('schema_version','package_hash','manifest_hash','registration_hash','registry_kinds_hash',
        'run_hash','uninstall_hash','user_tip_hash','runtime_hash','shortcut_hash','font_hash',
        'pending_reboot_hash','architectures')
    Assert-YimePimeSyntheticClosedProperties $InitialState $stateFields 'Initial state'
    Assert-YimePimeSyntheticClosedProperties $Candidate $candidateFields 'Candidate'
    if($InitialState.target_present -isnot [bool] -or $InitialState.runtime_running -isnot [bool] -or
        [string]$InitialState.runtime_integrity -cne 'medium') {
        throw 'Synthetic initial booleans or runtime integrity are invalid.'
    }
    $resolved=Assert-YimePimeSyntheticFixturePath $InstallRoot
    if($TargetUserSid -cnotmatch '^S-1-(?:5-21|12-1)(?:-[0-9]+){2,}$' -or
        [string]$InitialState.runtime_sid -cne $TargetUserSid) {
        throw 'Synthetic transaction SID differs from the initiating runtime owner.'
    }
    $architectures=@($Candidate.architectures|ForEach-Object{([string]$_).Trim().ToLowerInvariant()})
    if($architectures.Count -ne 2 -or @($architectures|Select-Object -Unique).Count -ne 2 -or
        $architectures -notcontains 'x86' -or @($architectures|Where-Object{$_ -in @('x64','arm64')}).Count -ne 1 -or
        @($architectures|Where-Object{$_ -notin @('x64','x86','arm64')}).Count) {
        throw 'Synthetic candidate architecture set is incomplete or ambiguous.'
    }
    $initialHashFields=@('package_hash','registration_hash','registry_kinds_hash','run_hash','uninstall_hash',
        'user_tip_hash','runtime_hash','shortcut_hash','font_hash','pending_reboot_hash','settings_hash',
        'learning_hash','peer_hash','default_input_hash')
    foreach($name in $initialHashFields){Assert-YimePimeSyntheticHash ([string]$InitialState.$name) "initial.$name"}
    $candidateHashFields=@('package_hash','manifest_hash','registration_hash','registry_kinds_hash','run_hash',
        'uninstall_hash','user_tip_hash','runtime_hash','shortcut_hash','font_hash','pending_reboot_hash')
    foreach($name in $candidateHashFields){Assert-YimePimeSyntheticHash ([string]$Candidate.$name) "candidate.$name"}
    foreach($name in @('package_hash','registration_hash','registry_kinds_hash','run_hash','uninstall_hash',
            'user_tip_hash','runtime_hash','shortcut_hash','font_hash','pending_reboot_hash')) {
        if([string]$InitialState.$name -ceq [string]$Candidate.$name) {
            throw "Synthetic candidate must exercise a changed rollback dimension: $name"
        }
    }
    $stages=@(Get-YimePimeUpgradeStageCatalog);$stageIds=@($stages.id)
    if($FaultPointSpecified -and [string]::IsNullOrWhiteSpace($FaultAt)) {
        throw 'A fault boundary requires a triggering transaction stage.'
    }
    if($FaultAt -and $stageIds -cnotcontains $FaultAt){throw 'Unknown synthetic transaction fault stage.'}
    $dimensions=@(Get-YimePimeRollbackDimensionCatalog)
    if($RollbackFault -and $dimensions -cnotcontains $RollbackFault){throw 'Unknown synthetic rollback fault dimension.'}
    if($RollbackFault) {
        if(-not $FaultAt){throw 'A rollback fault requires a triggering transaction failure.'}
        $faultPosition=@($stages|Where-Object id -eq $FaultAt)[0].position
        $firstMutationPosition=@($stages|Where-Object active_product_mutation)[0].position
        $commitPosition=@($stages|Where-Object id -eq 'write-activation-commit')[0].position
        $mutationApplied=($faultPosition -gt $firstMutationPosition -or
            ($faultPosition -eq $firstMutationPosition -and $FaultPoint -ceq 'after'))
        $commitApplied=($faultPosition -gt $commitPosition -or
            ($faultPosition -eq $commitPosition -and $FaultPoint -ceq 'after'))
        if(-not $mutationApplied -or $commitApplied) {
            throw 'A rollback fault may be injected only after mutation and before activation commit.'
        }
    }
    return [pscustomobject]@{install_root=$resolved;architectures=$architectures}
}

function Set-YimePimeSyntheticCandidateState {
    param($State,$Candidate,[string]$TargetUserSid,[string]$StageId)
    switch($StageId) {
        'directed-stop' {$State.runtime_running=$false}
        'quarantine-old-root' {$State.target_present=$false}
        'activate-staged-root' {
            $State.target_present=$true;$State.package_hash=[string]$Candidate.package_hash
            $State.pending_reboot_hash=[string]$Candidate.pending_reboot_hash
        }
        'unregister-old' {$State.registration_hash='0'*64;$State.registry_kinds_hash='0'*64}
        'register-new' {
            $State.registration_hash=[string]$Candidate.registration_hash
            $State.registry_kinds_hash=[string]$Candidate.registry_kinds_hash
        }
        'apply-target-user-profile' {$State.user_tip_hash=[string]$Candidate.user_tip_hash}
        'write-product-registration' {
            $State.run_hash=[string]$Candidate.run_hash
            $State.uninstall_hash=[string]$Candidate.uninstall_hash
            $State.shortcut_hash=[string]$Candidate.shortcut_hash
            $State.font_hash=[string]$Candidate.font_hash
        }
        'start-runtime-non-elevated' {
            $State.runtime_running=$true
            $State.runtime_sid=$TargetUserSid
            $State.runtime_integrity='medium'
            $State.runtime_hash=[string]$Candidate.runtime_hash
        }
    }
}

function Restore-YimePimeSyntheticDimension {
    param($State,$Before,[string]$Dimension)
    $map=Get-YimePimeSyntheticRollbackFieldMap
    if(-not $map.Contains($Dimension)){throw "Unknown synthetic rollback dimension: $Dimension"}
    foreach($field in @($map[$Dimension])){$State.$field=$Before.$field}
    foreach($field in @($map[$Dimension])) {
        if(-not [object]::Equals($State.$field,$Before.$field)) {
            throw "Synthetic rollback readback differs: $Dimension/$field"
        }
    }
}

function Invoke-YimePimeSyntheticRollback {
    param($State,$Before,[string[]]$Dimensions,[string]$RollbackFault,$Events)
    $restored=[Collections.Generic.List[string]]::new();$failed=$null
    foreach($dimension in $Dimensions) {
        $position=$Events.Count+1
        if($RollbackFault -and $dimension -ceq $RollbackFault) {
            $Events.Add([pscustomobject][ordered]@{
                position=$position;id="restore-$dimension";phase='rollback';dimension=$dimension
                status='failed';readback_verified=$false
            })
            $failed=$dimension
            break
        }
        Restore-YimePimeSyntheticDimension -State $State -Before $Before -Dimension $dimension
        $restored.Add($dimension)
        $Events.Add([pscustomobject][ordered]@{
            position=$position;id="restore-$dimension";phase='rollback';dimension=$dimension
            status='completed';readback_verified=$true
        })
    }
    return [pscustomobject][ordered]@{restored=$restored.ToArray();failed_dimension=$failed}
}

function Invoke-YimePimeSyntheticUpgradeTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InitialState,[Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [string]$FaultAt,[ValidateSet('before','after')][string]$FaultPoint='before',[string]$RollbackFault)
    $faultPointSpecified=$PSBoundParameters.ContainsKey('FaultPoint')
    $FaultPoint=$FaultPoint.ToLowerInvariant()
    $validated=Assert-YimePimeSyntheticUpgradeInputs -InitialState $InitialState -Candidate $Candidate `
        -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid -FaultAt $FaultAt -FaultPoint $FaultPoint `
        -FaultPointSpecified $faultPointSpecified -RollbackFault $RollbackFault
    $stages=@(Get-YimePimeUpgradeStageCatalog)
    $dimensions=@(Get-YimePimeRollbackDimensionCatalog)
    $before=Copy-YimePimeSyntheticValue $InitialState
    $current=Copy-YimePimeSyntheticValue $InitialState
    $beforeFingerprint=Get-YimePimeSyntheticStateFingerprint $before
    $events=[Collections.Generic.List[object]]::new()
    $activeMutationApplied=$false;$commitWritten=$false;$quarantinePurged=$false
    $journalPrepared=$false;$recoveryArchivePresent=$false
    foreach($stage in $stages) {
        if($FaultAt -and $stage.id -ceq $FaultAt -and $FaultPoint -ceq 'before') {
            $events.Add([pscustomobject][ordered]@{
                position=$stage.position;id=$stage.id;phase=$stage.phase;status='failed'
                fault_point='before';stage_effect_applied=$false
            })
            break
        }
        Set-YimePimeSyntheticCandidateState -State $current -Candidate $Candidate `
            -TargetUserSid $TargetUserSid -StageId $stage.id
        if($stage.active_product_mutation){$activeMutationApplied=$true}
        if($stage.id -eq 'snapshot-target'){$recoveryArchivePresent=$true}
        if($stage.id -eq 'write-prepared-journal'){$journalPrepared=$true}
        if($stage.id -eq 'write-activation-commit'){$commitWritten=$true}
        if($stage.id -eq 'purge-quarantine'){$quarantinePurged=$true}
        if($stage.id -eq 'finalize-journal'){$journalPrepared=$false;$recoveryArchivePresent=$false}
        if($FaultAt -and $stage.id -ceq $FaultAt -and $FaultPoint -ceq 'after') {
            $events.Add([pscustomobject][ordered]@{
                position=$stage.position;id=$stage.id;phase=$stage.phase;status='failed'
                fault_point='after';stage_effect_applied=$true
            })
            break
        }
        $events.Add([pscustomobject][ordered]@{
            position=$stage.position;id=$stage.id;phase=$stage.phase;status='completed'
            fault_point=$null;stage_effect_applied=$true
        })
    }

    $outcome='committed';$passed=$true;$cleanupPending=$false
    $recoveryArchiveRetained=$recoveryArchivePresent;$rollbackRestored=@();$rollbackFailed=$null;$rollbackStart=$null
    if($FaultAt) {
        $passed=$false
        if($commitWritten) {
            $outcome='committed-cleanup-pending';$cleanupPending=$true
            $recoveryArchiveRetained=$recoveryArchivePresent
        } elseif($activeMutationApplied) {
            $rollbackStart=Copy-YimePimeSyntheticValue $current
            $rollback=Invoke-YimePimeSyntheticRollback -State $current -Before $before `
                -Dimensions $dimensions -RollbackFault $RollbackFault -Events $events
            $rollbackRestored=@($rollback.restored);$rollbackFailed=$rollback.failed_dimension
            $recoveryArchiveRetained=$true;$quarantinePurged=$false
            if($rollbackFailed) {
                $outcome='recovery-required';$journalPrepared=$true
            } else {
                $outcome='rolled-back';$journalPrepared=$false
            }
        } else {
            $outcome='aborted-no-mutation'
            $current=Copy-YimePimeSyntheticValue $before
            $recoveryArchiveRetained=$recoveryArchivePresent
        }
    }
    $afterFingerprint=Get-YimePimeSyntheticStateFingerprint $current
    $restored=($beforeFingerprint -ceq $afterFingerprint)
    $protected=$true
    foreach($field in @('settings_hash','learning_hash','peer_hash','default_input_hash')) {
        if([string]$current.$field -cne [string]$before.$field){$protected=$false;break}
    }
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-synthetic-upgrade-result-v2';passed=$passed;outcome=$outcome
        install_root=$validated.install_root;target_user_sid=$TargetUserSid;architectures=$validated.architectures
        fault_at=$(if($FaultAt){$FaultAt}else{$null});fault_point=$(if($FaultAt){$FaultPoint}else{$null})
        events=$events.ToArray();initial_state=$before;final_state=$current;rollback_start_state=$rollbackStart
        initial_state_fingerprint=$beforeFingerprint;final_state_fingerprint=$afterFingerprint
        target_state_restored=$restored;peer_and_default_unchanged=$protected
        rollback_dimensions_restored=@($rollbackRestored);rollback_failed_dimension=$rollbackFailed
        rollback_dimensions_verified=@($rollbackRestored).Count;commit_written=$commitWritten
        quarantine_purged=$quarantinePurged;cleanup_pending=$cleanupPending
        journal_retained=$journalPrepared;recovery_archive_retained=$recoveryArchiveRetained
        actual_filesystem_registry_process_or_elevation_executed=$false
        actual_installer_or_uninstaller_executed=$false;default_input_method_changed=$false
        dp1_full_implementation_passed=$false;dp2_physical_acceptance_passed=$false
    }
}

# Pure catalog shared by future upgrade and uninstall transaction adapters.
# The Upgrade branch delegates to the existing 24-stage catalog so its IDs,
# ordering and active-mutation boundary cannot silently fork.
function Get-YimePimeTransactionStageCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Upgrade','Uninstall')][string]$Action)
    if($Action -ieq 'Upgrade'){
        return @(Get-YimePimeUpgradeStageCatalog)
    }
    $definitions=@(
        @('validate-selected-root','preflight',$false),
        @('validate-complete-manifest','preflight',$false),
        @('validate-removal-plan','preflight',$false),
        @('snapshot-target','snapshot',$false),
        @('snapshot-protected','snapshot',$false),
        @('write-prepared-journal','journal',$false),
        @('directed-stop','activation',$true),
        @('verify-quiescence','activation',$true),
        @('unregister-current','registration',$true),
        @('verify-registration-absent','registration',$true),
        @('remove-target-user-profile','registration',$true),
        @('remove-product-registration','registration',$true),
        @('verify-product-registration-absent','registration',$true),
        @('remove-manifest-files','removal',$true),
        @('remove-manifest-directories','removal',$true),
        @('remove-install-root','removal',$true),
        @('verify-target-absent','verification',$true),
        @('verify-protected-state','verification',$true),
        @('write-activation-commit','commit',$true),
        @('purge-recovery-archive','cleanup',$true),
        @('finalize-journal','cleanup',$true)
    )
    for($index=0;$index -lt $definitions.Count;$index++){
        [pscustomobject][ordered]@{
            position=$index+1
            id=[string]$definitions[$index][0]
            phase=[string]$definitions[$index][1]
            active_product_mutation=[bool]$definitions[$index][2]
        }
    }
}

# Classify only an already-validated journal state token. Durable journal byte
# validation and replay execution belong to the journal/orchestrator layer.
function Get-YimePimeReplayDisposition {
    [CmdletBinding()]
    param([AllowNull()]$JournalState)
    if($null -eq $JournalState){$state='none'}
    elseif($JournalState -isnot [string]){throw 'Replay journal state must be a string or null.'}
    else{$state=$JournalState}
    switch -CaseSensitive ($state){
        'none' {$disposition='none'}
        'prepared' {$disposition='rollback'}
        'committed' {$disposition='cleanup'}
        'terminal' {$disposition='noop'}
        'rolled-back' {$disposition='noop'}
        'cleanup-complete' {$disposition='noop'}
        'finalized' {$disposition='noop'}
        default {throw "Invalid replay journal state: $state"}
    }
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-replay-disposition-v1'
        journal_state=$state
        disposition=$disposition
        rollback_required=($disposition -ceq 'rollback')
        cleanup_required=($disposition -ceq 'cleanup')
        terminal_noop=($disposition -ceq 'noop')
    }
}

function Assert-YimePimeLogicalIdentityRecord {
    param($Record,[Parameter(Mandatory)][string]$Name)
    if($null -eq $Record -or $Record -isnot [Management.Automation.PSCustomObject]){
        throw "$Name must be a logical identity object."
    }
    Assert-YimePimeSyntheticClosedProperties $Record @('type','digest') $Name
    if($Record.type -isnot [string] -or [string]$Record.type -cnotmatch '^[a-z][a-z0-9-]{0,63}$'){
        throw "$Name type is not a canonical logical type."
    }
    if($Record.digest -isnot [string] -or [string]$Record.digest -cnotmatch '^[0-9a-f]{64}$'){
        throw "$Name digest is not a canonical SHA-256 value."
    }
}

# Resolve one intended before -> after mutation without touching the resource.
# Equality includes both the exact logical type and the lowercase digest.
function Resolve-YimePimeIdempotentTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Current,
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )
    Assert-YimePimeLogicalIdentityRecord $Current 'Current identity'
    Assert-YimePimeLogicalIdentityRecord $Before 'Before identity'
    Assert-YimePimeLogicalIdentityRecord $After 'After identity'
    if([string]$Current.type -cne [string]$Before.type -or
        [string]$Before.type -cne [string]$After.type){
        throw 'Idempotent transition logical types differ.'
    }
    if([string]$Before.digest -ceq [string]$After.digest){
        throw 'Idempotent transition before and after identities must differ.'
    }
    if([string]$Current.digest -ceq [string]$Before.digest){$disposition='apply'}
    elseif([string]$Current.digest -ceq [string]$After.digest){$disposition='already-converged'}
    else{$disposition='recovery-required'}
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-idempotent-transition-v1'
        resource_type=[string]$Before.type
        current_digest=[string]$Current.digest
        before_digest=[string]$Before.digest
        after_digest=[string]$After.digest
        disposition=$disposition
        apply_required=($disposition -ceq 'apply')
        already_converged=($disposition -ceq 'already-converged')
        recovery_required=($disposition -ceq 'recovery-required')
    }
}

function Assert-YimePimeLogicalRemovalPath {
    param($Value,[Parameter(Mandatory)][string]$Name)
    if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value) -or
        $Value.Length -gt 1024 -or -not $Value.IsNormalized([Text.NormalizationForm]::FormC) -or
        $Value.StartsWith([string][char]92) -or $Value.EndsWith([string][char]92) -or
        $Value.Contains([string]([char]92)+[char]92) -or $Value -match '[/<>|"?*:\x00-\x1f]'){
        throw "$Name is not a canonical logical relative path."
    }
    foreach($part in @($Value.Split([char]92))){
        if([string]::IsNullOrEmpty($part) -or $part.Length -gt 255 -or $part -in @('.','..') -or
            $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){
            throw "$Name contains an ambiguous logical path component."
        }
    }
    return [string]$Value
}

function Get-YimePimeDepthSortedLogicalPaths {
    param([Parameter(Mandatory)][string[]]$Paths)
    $sorted=[Collections.Generic.List[string]]::new()
    foreach($path in $Paths){
        $depth=$path.Split([char]92).Count;$insert=$sorted.Count
        for($index=0;$index -lt $sorted.Count;$index++){
            $other=[string]$sorted[$index];$otherDepth=$other.Split([char]92).Count
            if($depth -gt $otherDepth -or
                ($depth -eq $otherDepth -and [StringComparer]::Ordinal.Compare($path,$other) -lt 0)){
                $insert=$index;break
            }
        }
        $sorted.Insert($insert,$path)
    }
    return $sorted.ToArray()
}

function Assert-YimePimeManifestParentClosure {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$DirectorySet)
    $cursor=$Path
    while($cursor.Contains([string][char]92)){
        $cursor=$cursor.Substring(0,$cursor.LastIndexOf([char]92))
        if(-not $DirectorySet.Contains($cursor)){
            throw "Logical removal manifest omits parent directory: $cursor"
        }
    }
}

# Compile a logical manifest into an exact, leaf-first removal plan. The plan is
# data only: every directory/root operation is explicitly non-recursive and no
# filesystem API is called by this function.
function Get-YimePimeManifestRemovalPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Manifest)
    if($null -eq $Manifest -or $Manifest -isnot [Management.Automation.PSCustomObject]){
        throw 'Removal manifest must be a logical manifest object.'
    }
    Assert-YimePimeSyntheticClosedProperties $Manifest @(
        'schema_version','root_id','manifest_path','uninstaller_path','files','directories') 'Removal manifest'
    if($Manifest.schema_version -isnot [string] -or
        [string]$Manifest.schema_version -cne 'yime-pime-logical-removal-manifest-v1' -or
        $Manifest.root_id -isnot [string] -or [string]$Manifest.root_id -cne 'rime-pime-install-root' -or
        $Manifest.files -isnot [array] -or $Manifest.directories -isnot [array]){
        throw 'Removal manifest schema or collection types are invalid.'
    }
    $manifestPath=Assert-YimePimeLogicalRemovalPath $Manifest.manifest_path 'Manifest path'
    $uninstallerPath=Assert-YimePimeLogicalRemovalPath $Manifest.uninstaller_path 'Uninstaller path'
    if($manifestPath.Contains([string][char]92) -or $uninstallerPath -cne 'Uninstall.exe'){
        throw 'Manifest metadata and Uninstall.exe must be root-level logical files.'
    }
    $files=[Collections.Generic.List[string]]::new()
    $directories=[Collections.Generic.List[string]]::new()
    $all=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($value in @($Manifest.files)){
        $path=Assert-YimePimeLogicalRemovalPath $value 'Manifest file'
        if(-not $all.Add($path)){throw "Duplicate or case-folded manifest path: $path"}
        $files.Add($path)
    }
    foreach($value in @($Manifest.directories)){
        $path=Assert-YimePimeLogicalRemovalPath $value 'Manifest directory'
        if(-not $all.Add($path)){throw "Duplicate or case-folded manifest path: $path"}
        $directories.Add($path)
    }
    if(-not $files.Contains($manifestPath) -or -not $files.Contains($uninstallerPath)){
        throw 'Removal manifest must list its manifest file and Uninstall.exe exactly.'
    }
    $directorySet=[Collections.Generic.HashSet[string]]::new($directories,[StringComparer]::OrdinalIgnoreCase)
    foreach($path in $directories){Assert-YimePimeManifestParentClosure $path $directorySet}
    foreach($path in $files){Assert-YimePimeManifestParentClosure $path $directorySet}
    $ordinary=[Collections.Generic.List[string]]::new()
    foreach($path in $files){if($path -cne $manifestPath -and $path -cne $uninstallerPath){$ordinary.Add($path)}}
    $fileOrder=[Collections.Generic.List[string]]::new()
    foreach($path in @(Get-YimePimeDepthSortedLogicalPaths $ordinary.ToArray())){$fileOrder.Add($path)}
    $fileOrder.Add($manifestPath);$fileOrder.Add($uninstallerPath)
    $directoryOrder=@(Get-YimePimeDepthSortedLogicalPaths $directories.ToArray())
    $operations=[Collections.Generic.List[object]]::new();$position=0
    foreach($path in $fileOrder){
        $position++
        $role=if($path -ceq $manifestPath){'manifest'}elseif($path -ceq $uninstallerPath){'uninstaller'}else{'payload'}
        $operations.Add([pscustomobject][ordered]@{
            position=$position;operation='remove-file';relative_path=$path;role=$role;recursive=$false
        })
    }
    foreach($path in $directoryOrder){
        $position++
        $operations.Add([pscustomobject][ordered]@{
            position=$position;operation='remove-directory';relative_path=$path;role='payload-directory';recursive=$false
        })
    }
    $position++
    $operations.Add([pscustomobject][ordered]@{
        position=$position;operation='remove-root';relative_path=$null;role=[string]$Manifest.root_id;recursive=$false
    })
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-manifest-removal-plan-v1'
        root_id=[string]$Manifest.root_id
        source_manifest_schema=[string]$Manifest.schema_version
        file_order=$fileOrder.ToArray()
        directory_order=@($directoryOrder)
        operations=$operations.ToArray()
        operation_count=$operations.Count
        manifest_file_near_last=$true
        uninstaller_file_last=$true
        directories_non_recursive=$true
        root_last=$true
        physical_deletion_executed=$false
    }
}
