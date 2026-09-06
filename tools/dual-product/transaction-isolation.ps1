# Pure dual-product registration/SID/transaction fixture contract.
# Definitions only: importing this file performs no filesystem, process,
# registry, installer, elevation, recovery, or input-method operation.

function Get-DualProductTransactionFixturePolicy {
    return [ordered]@{
        schema_version = 'yime-dual-product-transaction-policy-v1'
        products = [ordered]@{
            'rime-pime' = [ordered]@{
                peer = 'yimecore'
                clsid = '{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
                profile = '{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'
                run_name = 'PIMELauncher'
                uninstall_name = 'YIME'
                install_root = 'C:\DP1-Fixture\RimePime\current'
                old_install_root = 'C:\DP1-Fixture\RimePime\previous'
                staging_root = 'C:\DP1-Fixture\RimePime\staging'
                state_root = 'C:\DP1-Fixture\RimePimeState'
                process_paths = @('PIMELauncher.exe', 'go-backend\server.exe')
            }
            'yimecore' = [ordered]@{
                peer = 'rime-pime'
                clsid = '{E40FA752-BB96-461D-A51D-F40EB437EC65}'
                profile = '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
                run_name = 'YimeCoreExperimentalTrial'
                uninstall_name = 'YimeCoreExperimentalTrial'
                install_root = 'C:\DP1-Fixture\YimeCore\current'
                old_install_root = 'C:\DP1-Fixture\YimeCore\previous'
                staging_root = 'C:\DP1-Fixture\YimeCore\staging'
                state_root = 'C:\DP1-Fixture\YimeCoreState'
                process_paths = @('bin\YimeCoreTrialRuntime.exe', 'bin\YimeBroker.exe')
            }
        }
    }
}

function Assert-DualProductFixtureSid([string]$Sid) {
    if ([string]::IsNullOrWhiteSpace($Sid) -or
        $Sid -cnotmatch '^S-1-(?:5-21|12-1)(?:-[0-9]+){2,}$') {
        throw 'A canonical fixture user SID is required.'
    }
    return $Sid
}

function Assert-DualProductSameSidChain($SidChain) {
    if ($null -eq $SidChain) { throw 'The initiating/elevated SID chain is required.' }
    $required = @('initiating_sid', 'elevated_sid', 'target_user_sid', 'maintenance_worker_sid')
    $values = @()
    foreach ($name in $required) {
        if (-not $SidChain.PSObject.Properties[$name]) { throw "SID chain field is missing: $name" }
        $values += Assert-DualProductFixtureSid ([string]$SidChain.$name)
    }
    if (@($values | Select-Object -Unique).Count -ne 1) {
        throw 'Elevation changed the initiating SID or selected a different target user.'
    }
    if (-not $SidChain.PSObject.Properties['initiating_token_elevated'] -or
        -not $SidChain.PSObject.Properties['worker_token_elevated'] -or
        [bool]$SidChain.initiating_token_elevated -or -not [bool]$SidChain.worker_token_elevated) {
        throw 'The fixture must start unelevated and bind the elevated worker to the same SID.'
    }
    if (-not $SidChain.PSObject.Properties['standard_user_runtime_sid'] -or
        -not $SidChain.PSObject.Properties['standard_user_runtime_elevated']) {
        throw 'The non-elevated runtime identity is required even when a fixture does not start it.'
    }
    $runtimeSid = Assert-DualProductFixtureSid ([string]$SidChain.standard_user_runtime_sid)
    if ($runtimeSid -cne $values[0] -or [bool]$SidChain.standard_user_runtime_elevated) {
        throw 'The normal runtime must return to a non-elevated token of the initiating SID.'
    }
    return $values[0]
}

function Assert-DualProductFixturePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cnotmatch '^[A-Za-z]:\\' -or
        $Path -match '[/<>|"?*]|(^|\\)\.\.?($|\\)|[. ]($|\\)' -or
        $Path.Substring(2).Contains(':')) {
        throw 'A canonical local fixture path is required.'
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $full.StartsWith('C:\DP1-Fixture\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Transaction fixtures may name only the synthetic DP1 fixture namespace.'
    }
    return $full
}

function Test-DualProductFixtureDescendant([string]$Path, [string]$Root, [switch]$OrEqual) {
    $pathFull = Assert-DualProductFixturePath $Path
    $rootFull = Assert-DualProductFixturePath $Root
    if ($OrEqual -and $pathFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $pathFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-DualProductOwnedTransactionEvent($Event, [string]$TargetProduct, $Policy,
                                                  [string]$TargetSid, [string[]]$Architectures) {
    if ($null -eq $Event -or -not $Event.PSObject.Properties['kind'] -or
        -not $Event.PSObject.Properties['owner']) {
        throw 'Every transaction event needs a kind and owner.'
    }
    $kind = [string]$Event.kind
    $owner = [string]$Event.owner
    $item = $Policy.products[$TargetProduct]
    $peer = [string]$item.peer
    if ($kind -eq 'snapshot-peer') {
        if ($owner -cne $peer) { throw 'Peer observation has the wrong owner.' }
        return
    }
    if ($owner -cne $TargetProduct) { throw 'A transaction event targets the other product.' }
    if ($Event.PSObject.Properties['dependency_product'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Event.dependency_product)) {
        throw 'Installed-product dependencies are forbidden.'
    }
    if ($kind -in @('default-input-write', 'purge-peer', 'cross-product-fallback')) {
        throw 'The requested operation is outside the selected product boundary.'
    }
    $sidRequiredKinds=@('stop-owned-process','start-runtime','register-tip','unregister-tip',
        'restore-user-tip','write-state','restore-config','restore-runtime-state',
        'write-run','restore-run','write-uninstall','restore-uninstall')
    if ($kind -in $sidRequiredKinds -and -not $Event.PSObject.Properties['sid']) {
        throw 'A per-user or process transaction event has no explicit SID.'
    }
    if ($Event.PSObject.Properties['sid']) {
        if ((Assert-DualProductFixtureSid ([string]$Event.sid)) -cne $TargetSid) {
            throw 'A per-user transaction event targets a different SID.'
        }
    }
    switch ($kind) {
        'stage-package' {
            if (-not (Test-DualProductFixtureDescendant ([string]$Event.path) ([string]$item.staging_root) -OrEqual)) {
                throw 'Package staging escaped the selected product staging root.'
            }
        }
        { $_ -in @('write-state', 'restore-config', 'restore-runtime-state') } {
            if (-not (Test-DualProductFixtureDescendant ([string]$Event.path) ([string]$item.state_root))) {
                throw 'Writable state escaped the selected product state root.'
            }
        }
        { $_ -in @('write-file', 'remove-owned-resource') } {
            if (-not (Test-DualProductFixtureDescendant ([string]$Event.path) ([string]$item.install_root))) {
                throw 'Payload mutation escaped the selected product install root.'
            }
        }
        'delete-old-root' {
            if ((Assert-DualProductFixturePath ([string]$Event.path)) -ine
                (Assert-DualProductFixturePath ([string]$item.old_install_root))) {
                throw 'Old-root deletion is not bound to the selected product predecessor.'
            }
        }
        { $_ -in @('stop-owned-process', 'start-runtime') } {
            $path = Assert-DualProductFixturePath ([string]$Event.path)
            $allowed = @($item.process_paths | ForEach-Object {
                [IO.Path]::GetFullPath((Join-Path ([string]$item.install_root) $_))
            })
            if ($allowed -inotcontains $path) { throw 'Process event is not bound to an exact selected-product image.' }
        }
        { $_ -in @('register-com', 'unregister-com', 'restore-registration') } {
            if ([string]$Event.clsid -cne [string]$item.clsid) { throw 'COM registration identity belongs to another product.' }
            $eventArchitectures=@($Event.architectures)
            if ($eventArchitectures.Count -ne $Architectures.Count -or
                (Compare-Object $Architectures $eventArchitectures).Count -ne 0) {
                throw 'COM registration does not cover the exact declared architecture set.'
            }
        }
        { $_ -in @('register-tip', 'unregister-tip', 'restore-user-tip') } {
            if ([string]$Event.clsid -cne [string]$item.clsid -or
                [string]$Event.profile -cne [string]$item.profile) {
                throw 'TIP registration identity belongs to another product.'
            }
        }
        { $_ -in @('write-run', 'restore-run') } {
            if ([string]$Event.name -cne [string]$item.run_name) { throw 'Run mutation targets a foreign value.' }
        }
        { $_ -in @('write-uninstall', 'restore-uninstall') } {
            if ([string]$Event.name -cne [string]$item.uninstall_name) { throw 'Uninstall mutation targets a foreign key.' }
        }
        'verify-registration' {
            $verifiedRoot=Assert-DualProductFixturePath ([string]$Event.install_root)
            $selectedRoot=Assert-DualProductFixturePath ([string]$item.install_root)
            if ($verifiedRoot -ine $selectedRoot) {
                throw 'Registration verification is not bound to the selected install root.'
            }
            $eventArchitectures=@($Event.architectures)
            if($eventArchitectures.Count -ne $Architectures.Count -or
                (Compare-Object $Architectures $eventArchitectures).Count -ne 0) {
                throw 'Registration verification does not cover the exact package architecture set.'
            }
        }
        { $_ -in @('snapshot-target', 'quiescence-verified', 'verify-registration', 'verify-runtime',
                   'failure-marker', 'rollback-begin', 'verify-rollback', 'rollback-complete',
                   'verify-target-absent', 'commit') } { }
        default { throw "Unknown transaction event kind: $kind" }
    }
}

function Assert-DualProductHash([string]$Value, [string]$Name) {
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid fixture hash: $Name" }
    return $Value
}

function Assert-DualProductTransactionFixture($Fixture) {
    if ($null -eq $Fixture -or [string]$Fixture.schema_version -cne 'yime-dual-product-transaction-fixture-v1') {
        throw 'Unknown dual-product transaction fixture.'
    }
    $policy = Get-DualProductTransactionFixturePolicy
    $target = [string]$Fixture.target_product
    if (-not $policy.products.Contains($target)) { throw 'Unknown target product.' }
    if ([string]$Fixture.peer_product -cne [string]$policy.products[$target].peer) {
        throw 'The fixture peer does not match the independent product pair.'
    }
    $action = [string]$Fixture.action
    $outcome = [string]$Fixture.outcome
    if ($action -notin @('install', 'upgrade', 'uninstall') -or $outcome -notin @('success', 'rolled-back')) {
        throw 'Unsupported transaction action or outcome.'
    }
    $targetSid = Assert-DualProductSameSidChain $Fixture.sid_chain
    $architectures=@($Fixture.architectures)
    $uniqueArchitectures=@($architectures|Select-Object -Unique)
    $unsupportedArchitectures=@($architectures|Where-Object{$_ -notin @('x64','x86','arm64')})
    if ($architectures.Count -eq 0 -or
        $uniqueArchitectures.Count -ne $architectures.Count -or
        $unsupportedArchitectures.Count -ne 0) {
        throw 'The fixture architecture set is missing, duplicated, or unsupported.'
    }
    $events = @($Fixture.events)
    if ($events.Count -lt 4) { throw 'Transaction event sequence is incomplete.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $events.Count; $index++) {
        $event = $events[$index]
        if ([int]$event.sequence -ne $index + 1 -or
            -not $event.PSObject.Properties['id'] -or
            [string]::IsNullOrWhiteSpace([string]$event.id) -or
            -not $seen.Add([string]$event.id)) {
            throw 'Transaction sequence or event identity is ambiguous.'
        }
        Assert-DualProductOwnedTransactionEvent $event $target $policy $targetSid $architectures
    }
    $positions = @{}
    $positionCounts = @{}
    foreach ($kind in @($events.kind | Select-Object -Unique)) {
        $matches = @(for ($index = 0; $index -lt $events.Count; $index++) {
            if ([string]$events[$index].kind -ceq [string]$kind) { $index }
        })
        $positions[[string]$kind] = $matches
        $positionCounts[[string]$kind] = $matches.Count
    }
    foreach ($required in @('snapshot-target', 'snapshot-peer')) {
        if ([int]$positionCounts[$required] -ne 1) { throw "Missing or duplicate event: $required" }
    }
    $mutationKinds = @('stop-owned-process', 'unregister-com', 'unregister-tip', 'register-com', 'register-tip',
        'write-run', 'write-uninstall', 'write-state', 'write-file', 'start-runtime', 'delete-old-root',
        'remove-owned-resource', 'restore-registration', 'restore-run', 'restore-uninstall',
        'restore-user-tip', 'restore-config', 'restore-runtime-state')
    $mutationPositions = @(for ($index = 0; $index -lt $events.Count; $index++) {
        if ([string]$events[$index].kind -in $mutationKinds) { $index }
    })
    if ($mutationPositions.Count -eq 0) { throw 'A transaction fixture must exercise an owned mutation.' }
    $firstMutation = ($mutationPositions | Measure-Object -Minimum).Minimum
    if ($positions['snapshot-target'][0] -ge $firstMutation -or $positions['snapshot-peer'][0] -ge $firstMutation) {
        throw 'Target and peer snapshots must precede every active mutation.'
    }
    if ($action -in @('install', 'upgrade')) {
        if ([int]$positionCounts['stage-package'] -ne 1 -or
            $positions['stage-package'][0] -ge $positions['snapshot-target'][0] -or
            $positions['stage-package'][0] -ge $positions['snapshot-peer'][0] -or
            $positions['stage-package'][0] -ge $firstMutation) {
            throw 'A complete private package stage must precede protected snapshots and active mutation.'
        }
    } elseif ([int]$positionCounts['stage-package'] -ne 0) {
        throw 'Uninstall fixtures must not stage an installation package.'
    }
    if($action -in @('upgrade','uninstall')) {
        foreach($required in @('stop-owned-process','quiescence-verified')) {
            if([int]$positionCounts[$required] -ne 1){throw "Missing or duplicate quiescence event: $required"}
        }
        if($positions['stop-owned-process'][0] -ge $positions['quiescence-verified'][0]) {
            throw 'Owned runtime must be stopped before quiescence is verified.'
        }
        $firstRegistrationMutation=(@($positions['unregister-com'][0],
            $positions['unregister-tip'][0])|Measure-Object -Minimum).Minimum
        if($positions['quiescence-verified'][0] -ge $firstRegistrationMutation) {
            throw 'Registration mutation began before quiescence verification.'
        }
    }
    $state = $Fixture.state_fingerprints
    if ($null -eq $state) { throw 'Before/after fingerprints are required.' }
    foreach ($name in @('target_before', 'target_after', 'target_registry_kinds_before',
            'target_registry_kinds_after', 'peer_before', 'peer_after', 'default_input_before', 'default_input_after')) {
        if (-not $state.PSObject.Properties[$name]) { throw "Fingerprint is missing: $name" }
        $null = Assert-DualProductHash ([string]$state.$name) $name
    }
    if ([string]$state.peer_before -cne [string]$state.peer_after) {
        throw 'The non-target product changed during the transaction.'
    }
    if ([string]$state.default_input_before -cne [string]$state.default_input_after) {
        throw 'The user default input method changed during the transaction.'
    }
    if ($outcome -eq 'success') {
        if ([int]$positionCounts['commit'] -ne 1) { throw 'A successful transaction requires one activation commit.' }
        if ([string]$state.target_before -ceq [string]$state.target_after) {
            throw 'A successful fixture did not record a target-product state transition.'
        }
        if ($action -in @('install', 'upgrade')) {
            foreach ($required in @('verify-registration', 'verify-runtime')) {
                if ([int]$positionCounts[$required] -ne 1) { throw "Missing success verification: $required" }
            }
            foreach($required in @('register-com','register-tip','write-run','write-uninstall','start-runtime')) {
                if([int]$positionCounts[$required] -ne 1){throw "Missing or duplicate successful install event: $required"}
            }
            $registrationPosition=$positions['verify-registration'][0]
            foreach($required in @('register-com','register-tip','write-run','write-uninstall')) {
                if($positions[$required][0] -ge $registrationPosition) {
                    throw 'Registration ownership must be verified after every path-bearing registration write.'
                }
            }
            if($registrationPosition -ge $positions['start-runtime'][0] -or
                $positions['start-runtime'][0] -ge $positions['verify-runtime'][0]) {
                throw 'Runtime startup or readiness occurred before registration ownership convergence.'
            }
        }
        if ($action -eq 'upgrade') {
            if ([int]$positionCounts['delete-old-root'] -ne 1 -or
                $positions['delete-old-root'][0] -le $positions['verify-registration'][0] -or
                $positions['delete-old-root'][0] -le $positions['verify-runtime'][0] -or
                $positions['delete-old-root'][0] -le $positions['commit'][0] -or
                $positions['delete-old-root'][0] -ne $events.Count - 1) {
                throw 'The recoverable predecessor may be purged only after activation commit and must be final cleanup.'
            }
        } elseif($positions['commit'][0] -ne $events.Count - 1) {
            throw 'A successful install or uninstall requires a final commit.'
        }
        foreach ($forbidden in @('failure-marker', 'rollback-begin', 'verify-rollback', 'rollback-complete')) {
            if ([int]$positionCounts[$forbidden]) { throw 'A successful fixture contains rollback events.' }
        }
    } else {
        foreach ($forbidden in @('commit', 'delete-old-root')) {
            if ([int]$positionCounts[$forbidden]) { throw 'A failed transaction committed or deleted its recoverable predecessor.' }
        }
        $rollbackKinds = @('failure-marker', 'rollback-begin', 'restore-registration', 'restore-run',
            'restore-uninstall', 'restore-user-tip', 'restore-config', 'restore-runtime-state',
            'verify-rollback', 'rollback-complete')
        foreach ($required in $rollbackKinds) {
            if ([int]$positionCounts[$required] -ne 1) { throw "Missing or duplicate rollback event: $required" }
        }
        for ($index = 1; $index -lt $rollbackKinds.Count; $index++) {
            if ($positions[$rollbackKinds[$index]][0] -le $positions[$rollbackKinds[$index - 1]][0]) {
                throw 'Rollback restoration order is incomplete or ambiguous.'
            }
        }
        if ($positions['rollback-complete'][0] -ne $events.Count - 1 -or
            [string]$state.target_before -cne [string]$state.target_after -or
            [string]$state.target_registry_kinds_before -cne [string]$state.target_registry_kinds_after) {
            throw 'Rollback did not restore exact target state and registry value kinds.'
        }
    }
    return [ordered]@{
        passed = $true
        test_level = 'source-and-pure-synthetic-transaction-contract'
        target_product = $target
        action = $action
        outcome = $outcome
        architectures = $architectures
        same_sid_chain = $true
        peer_product_unchanged = $true
        default_input_method_unchanged = $true
        actual_elevation_executed = $false
        actual_registry_or_install_mutation_executed = $false
        dp1_full_implementation_passed = $false
        dp2_physical_acceptance_passed = $false
    }
}
