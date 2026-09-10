Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This module only reads public package files and writes new preparation output.
# It must never dot-source a package script or launch a package executable.
function Assert-PreparationPlainPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '["\r\n]') { throw 'Invalid preparation path.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Indirect preparation path rejected.' }
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}

function Assert-PreparationNewChild([string]$Path, [string]$Parent) {
    $full = Assert-PreparationPlainPath $Path
    $allowed = Assert-PreparationPlainPath $Parent
    if ((Split-Path -Parent $full) -ine $allowed -or (Test-Path -LiteralPath $full)) {
        throw 'Preparation output must be a new direct child of its approved parent.'
    }
    return $full
}

function Assert-PreparationRecordPath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or
        $Relative -match '[\\:"\x00-\x1f<>|?*]|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)' -or
        [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(?i)(^|/)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|/|$)' -or
        $Relative -in @('package-manifest.json','install-metadata.json')) {
        throw 'Invalid public package member path.'
    }
}

function Get-PreparationVersion([hashtable]$Contract) {
    if (-not $Contract.ContainsKey('product_version')) { return '0.1.0-local.12' }
    if ($Contract.product_version -isnot [string] -or $Contract.product_version -notin @('0.1.0-local.12','0.1.0-local.13')) { throw 'Unsupported preparation version.' }
    return $Contract.product_version
}

function Assert-PreparationStringProperty($Object,[string]$Name) {
    $property=$Object.PSObject.Properties[$Name]
    if (-not $property -or $property.Value -isnot [string]) { throw 'Preparation identity requires literal JSON strings.' }
}

function Test-PreparationGuard([hashtable]$Contract) {
    if (-not $Contract.ContainsKey('guarded_native_desktop_rehearsal')) { return $false }
    if ($Contract.guarded_native_desktop_rehearsal -isnot [bool]) { throw 'Preparation guard claim must be a JSON boolean.' }
    if ($Contract.guarded_native_desktop_rehearsal -and (Get-PreparationVersion $Contract) -ne '0.1.0-local.13') { throw 'Legacy preparation cannot claim the new guard.' }
    # Guard availability is a reviewed source policy, not a caller-supplied claim.
    # A future controller must receive a separate review before entering this list.
    # These pins approve guard source only; fixed candidate entries retain their
    # own single controller pin and never acquire execution authorization here.
    # The startup-health controller was reviewed on 2026-09-09: the terminal
    # rollback barrier, old-root retention and finalizer remain intact.
    # 2026-09-10: reviewed e346a1dad/fc2d7db65 controller changes (initiator
    # handoff, registration snapshot, target scope and bounded health retry).
    # The rehearsal rollback barrier and old-root retention remain mandatory.
    # See docs/project/YIMECORE_CI_CONTROLLER_POLICY_2026-09-10.md.
    if ($Contract.guarded_native_desktop_rehearsal -and
        ($Contract.manager_sha256 -isnot [string] -or $Contract.manager_sha256 -cnotin @(
            'e65ea013b5c947c68604bc633e180563a811b856ed6c2aa7b09f3d5c291cd95a',
            '9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d',
            'c4585051463c18b1164a4bf5eeb624f232fcc4b2c4177180feebe2e3c4448d75',
            '24bbfce74039cef780db095edfb1667b65f15b68bc76956723afbbb99f2c155e'))) { throw 'Controller is not approved for guarded NativeDesktop rehearsal.' }
    return $Contract.guarded_native_desktop_rehearsal
}

function Get-PreparationStreamHash([IO.Stream]$Stream) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $Stream.Position=0;return ([BitConverter]::ToString($hash.ComputeHash($Stream))).Replace('-','').ToLowerInvariant() }
    finally { $Stream.Position=0;$hash.Dispose() }
}

function Read-PreparationPinnedJson([string]$Path,[string]$ExpectedSha256) {
    $full=Assert-PreparationPlainPath $Path
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ((Get-PreparationStreamHash $stream) -cne $ExpectedSha256) { throw 'Pinned JSON input hash mismatch.' }
        # Hash and parse from the same held stream, never two path-based reads.
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Open-PreparationInputLeases($Catalog,[string]$ReplacementRuntime,[string]$ExpectedRuntimeSha256) {
    $leases=@{}
    try {
        $records=@([pscustomobject]@{path='package-manifest.json';sha256=$Catalog.manifest_sha256;bytes=$null})+@($Catalog.manifest.files)
        foreach ($record in $records) {
            $path=Assert-PreparationPlainPath (Join-Path $Catalog.root $record.path)
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $leases[$record.path]=$stream
            if (($null -ne $record.bytes -and $stream.Length -ne $record.bytes) -or (Get-PreparationStreamHash $stream) -cne $record.sha256) { throw 'Public input changed before its copy lease.' }
        }
        $path=Assert-PreparationPlainPath $ReplacementRuntime
        $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $leases['replacement-runtime']=$stream
        if ((Get-PreparationStreamHash $stream) -cne $ExpectedRuntimeSha256) { throw 'Replacement runtime changed before its copy lease.' }
        return $leases
    } catch { foreach ($stream in $leases.Values) { $stream.Dispose() };throw }
}

function Copy-PreparationLeasedFile([IO.Stream]$InputStream,[string]$Destination,[string]$ExpectedSha256,[long]$ExpectedBytes) {
    $null=Assert-PreparationPlainPath $Destination
    $output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try {
        $InputStream.Position=0;$InputStream.CopyTo($output);$output.Flush()
        if ($output.Length -ne $ExpectedBytes -or (Get-PreparationStreamHash $output) -cne $ExpectedSha256) { throw 'Prepared member copy failed hash verification.' }
    } finally { $output.Dispose() }
}

function Get-YimeCoreFaultPreparationCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][hashtable]$Contract)
    $version = Get-PreparationVersion $Contract
    $guarded = Test-PreparationGuard $Contract
    $root = Assert-PreparationPlainPath $PackageRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $root 'install-metadata.json'))) {
        throw 'Preparation requires a public source package, never an installed package.'
    }
    foreach ($key in @('manifest_sha256','manager_sha256','wrapper_sha256')) {
        if ($Contract[$key] -isnot [string] -or $Contract[$key] -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid pinned preparation contract.' }
    }
    if (($Contract.member_count -isnot [int] -and $Contract.member_count -isnot [long]) -or $Contract.member_count -lt 1) { throw 'Preparation member count must be a positive integer.' }
    $manifestPath = Join-Path $root 'package-manifest.json'
    $null = Assert-PreparationPlainPath $manifestPath
    $manifestHash = $Contract.manifest_sha256
    $manifest = Read-PreparationPinnedJson $manifestPath $manifestHash
    foreach ($name in @('package_contract','tool_version','product_version')) { Assert-PreparationStringProperty $manifest $name }
    if ($manifest.package_contract -cne 'yimecore-local-product-package-v1' -or
        $manifest.tool_version -cne 'yimecore-local-builder-v1' -or
        $manifest.product_version -cne $version -or
        @($manifest.files).Count -ne $Contract.member_count) { throw 'Unexpected package identity or member count.' }
    if ($Contract.ContainsKey('package_id') -and
        ($Contract.package_id -isnot [string] -or -not $manifest.PSObject.Properties['package_id'] -or
            $manifest.package_id -isnot [string] -or $manifest.package_id -cne $Contract.package_id)) { throw 'Pinned public package ID mismatch.' }
    if ($guarded -and (-not $Contract.ContainsKey('package_id') -or [string]::IsNullOrWhiteSpace($Contract.package_id))) { throw 'Guarded preparation requires a pinned package ID.' }
    $expected = @{}
    $directories = @{}
    foreach ($record in @($manifest.files)) {
        if ($record.path -isnot [string]) { throw 'Non-string public package member path.' }
        $relative = $record.path
        Assert-PreparationRecordPath $relative
        if ($expected.ContainsKey($relative) -or $record.sha256 -isnot [string] -or
            $record.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            ($record.bytes -isnot [int] -and $record.bytes -isnot [long]) -or $record.bytes -lt 0) {
            throw 'Duplicate member or invalid hash/size in package catalog.'
        }
        $expected[$relative] = $record
        $parts = $relative.Split('/')
        for ($i = 1; $i -lt $parts.Count; $i++) { $directories[($parts[0..($i-1)] -join '/')] = $true }
    }
    $required = @('local-product.json','maintenance/Manage-YimeCoreTrial.ps1','maintenance/manage-local-product.ps1',
        'maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1',
        'x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll',
        'x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
        'bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','bin/YimeCoreRecoveryProbe.exe')
    foreach ($member in $required) { if (-not $expected.ContainsKey($member)) { throw 'Required dual-architecture package member missing.' } }
    $actualCount = 0
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue($root)
    while ($queue.Count) {
        $directory = $queue.Dequeue()
        $null = Assert-PreparationPlainPath $directory
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Indirect package member rejected.' }
            $relative = $item.FullName.Substring($root.Length+1).Replace('\','/')
            if ($item.PSIsContainer) {
                if (-not $directories.ContainsKey($relative)) { throw 'Unlisted public package directory.' }
                $queue.Enqueue($item.FullName)
                continue
            }
            if ($relative -ceq 'package-manifest.json') { continue }
            $record = $expected[$relative]
            if (-not $record -or $item.Length -ne $record.bytes -or
                (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ine $record.sha256) {
                throw 'Public package member size/hash mismatch or unlisted file.'
            }
            $actualCount++
        }
    }
    if ($actualCount -ne $expected.Count) { throw 'Public package catalog is incomplete.' }
    if ($expected['maintenance/Manage-YimeCoreTrial.ps1'].sha256 -cne $Contract.manager_sha256 -or
        $expected['maintenance/manage-local-product.ps1'].sha256 -cne $Contract.wrapper_sha256) { throw 'Pinned maintenance controller mismatch.' }
    $descriptor = Read-PreparationPinnedJson (Join-Path $root 'local-product.json') $expected['local-product.json'].sha256
    foreach ($name in @('schema_version','version')) { Assert-PreparationStringProperty $descriptor $name }
    Assert-PreparationStringProperty $descriptor.scope 'computer_name'
    foreach ($name in @('product_key','clsid','profile')) { Assert-PreparationStringProperty $descriptor.identity $name }
    $active=$descriptor.scope.active_architectures
    if ($active -isnot [array] -or $active.Count -ne 2 -or $active[0] -isnot [string] -or $active[1] -isnot [string]) { throw 'Preparation architectures require an ordered JSON string array.' }
    if ($descriptor.schema_version -cne 'yimecore-local-product-v1' -or $descriptor.version -cne $version -or
        $descriptor.scope.computer_name -cne 'MYCOMPUTER' -or
        (@($descriptor.scope.active_architectures) -join '|') -cne 'x64|x86' -or
        $descriptor.identity.product_key -cne 'YimeCoreExperimentalTrial' -or
        $descriptor.identity.clsid -cne '{E40FA752-BB96-461D-A51D-F40EB437EC65}' -or
        $descriptor.identity.profile -cne '{126F54C6-E9B1-4E22-8652-03224CBD49F9}') { throw 'Current dual-architecture product descriptor mismatch.' }
    return [pscustomobject]@{root=$root;manifest_path=$manifestPath;manifest_sha256=$manifestHash;manifest=$manifest;files=$expected;file_count=$actualCount}
}

function Get-YimeCoreFaultPreparationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][hashtable]$Contract,
        [Parameter(Mandatory)][string]$ProbeSource, [Parameter(Mandatory)][string]$ExpectedProbeSourceSha256)
    $catalog = Get-YimeCoreFaultPreparationCatalog $PackageRoot $Contract
    $version=Get-PreparationVersion $Contract
    $guarded=Test-PreparationGuard $Contract
    $tag=if ($version -ceq '0.1.0-local.13') {'local13'} else {'local12'}
    $probe = Assert-PreparationPlainPath $ProbeSource
    $probeHash = (Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedProbeSourceSha256 -cnotmatch '^[a-f0-9]{64}$' -or $probeHash -cne $ExpectedProbeSourceSha256) { throw 'Reviewed exit-86 probe source changed.' }
    return [ordered]@{
        schema_version=('yimecore-'+$tag+'-fault-preparation-plan-v1');action='Plan';package_version=$version
        source_package=$catalog.root;source_manifest_sha256=$catalog.manifest_sha256;verified_member_count=$catalog.file_count
        manager_sha256=$Contract.manager_sha256;wrapper_sha256=$Contract.wrapper_sha256
        target_computer='MYCOMPUTER';native_architecture='x64';tsf_architectures=@('x64','x86')
        expected_initiating_sid='S-1-5-21-2783006668-770716121-2150155084-1001';initiating_sid_currently_verified=$false
        probe_source=$probe;probe_source_sha256=$probeHash;expected_probe_exit_code=86;probe_exit_observed=$false
        source_catalog_verified=$true;prepared_only=$true;failure_package_prepared=$false
        execution_authorized=$false;ready_to_execute=$false;installer_executed=$false;product_executed=$false
        installed_package_read=$false;user_state_read=$false;product_mutated=$false
        unexpected_success_rollback_guard_available=$guarded
        pending=$(if ($guarded) { @('reviewed same-SID native execution harness and fresh backup','explicit maintenance window') } else { @('NativeDesktop unexpected-success rollback guard','reviewed same-SID native execution harness and fresh backup','explicit maintenance window') })
    }
}

function Assert-YimeCoreFailureProbePe([string]$Path) {
    $full = Assert-PreparationPlainPath $Path
    $stream = [IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 128 -or $reader.ReadUInt16() -ne 0x5a4d) { throw 'Failure probe is not PE.' }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        if ($offset -lt 0x40 -or $offset -gt $stream.Length - 26) { throw 'Invalid failure probe PE header offset.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Failure probe must be AMD64 PE.' }
        $stream.Position = $offset + 22
        if (($reader.ReadUInt16() -band 0x2000) -ne 0) { throw 'Failure probe must not be a DLL.' }
        $stream.Position = $offset + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw 'Failure probe must be PE32+.' }
    } finally { $reader.Dispose() }
}

function New-YimeCoreFaultPreparationOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][hashtable]$Contract,
        [Parameter(Mandatory)][string]$ReplacementRuntime, [Parameter(Mandatory)][string]$ExpectedRuntimeSha256,
        [Parameter(Mandatory)][string]$OutputRoot, [Parameter(Mandatory)][string]$ApprovedOutputParent)
    $catalog = Get-YimeCoreFaultPreparationCatalog $PackageRoot $Contract
    $version=Get-PreparationVersion $Contract
    $guarded=Test-PreparationGuard $Contract
    $tag=if ($version -ceq '0.1.0-local.13') {'local13'} else {'local12'}
    $out = Assert-PreparationNewChild $OutputRoot $ApprovedOutputParent
    if ($out.StartsWith($catalog.root+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $catalog.root.StartsWith($out+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Preparation source and output overlap.' }
    Assert-YimeCoreFailureProbePe $ReplacementRuntime
    if ($ExpectedRuntimeSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $ReplacementRuntime -Algorithm SHA256).Hash -ine $ExpectedRuntimeSha256) { throw 'Compiled failure probe hash mismatch.' }
    if ($ExpectedRuntimeSha256 -ceq $catalog.files['bin/YimeCoreTrialRuntime.exe'].sha256) { throw 'Failure probe cannot be the ordinary runtime.' }
    $leases=Open-PreparationInputLeases $catalog $ReplacementRuntime $ExpectedRuntimeSha256
    try {
    New-Item -ItemType Directory -Path $out | Out-Null
    # Copy only enumerated public files, never a recursive wildcard or state/archive metadata.
    foreach ($record in $catalog.manifest.files) {
        $destination = Join-Path $out $record.path
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $null = Assert-PreparationPlainPath $parent
        $replacement=$record.path -ceq 'bin/YimeCoreTrialRuntime.exe'
        $inputStream=if ($replacement) { $leases['replacement-runtime'] } else { $leases[$record.path] }
        $expectedHash=if ($replacement) { $ExpectedRuntimeSha256 } else { $record.sha256 }
        Copy-PreparationLeasedFile $inputStream $destination $expectedHash $inputStream.Length
    }
    $manifest = $catalog.manifest
    $runtimeRecord = @($manifest.files | Where-Object { $_.path -ceq 'bin/YimeCoreTrialRuntime.exe' })[0]
    $runtimePath = Join-Path $out 'bin/YimeCoreTrialRuntime.exe'
    $runtimeRecord.bytes = (Get-Item -LiteralPath $runtimePath).Length
    $runtimeRecord.sha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($runtimeRecord.sha256 -cne $ExpectedRuntimeSha256) { throw 'Failure probe changed during preparation.' }
    $manifest.scope = 'PREPARATION ONLY: runtime expected to exit 86; native execution is not authorized.'
    $manifest | Add-Member -NotePropertyName rehearsal_only -NotePropertyValue $true -Force
    $manifest | Add-Member -NotePropertyName preparation_only -NotePropertyValue $true -Force
    $manifest | Add-Member -NotePropertyName source_package_manifest_sha256 -NotePropertyValue $catalog.manifest_sha256 -Force
    if ($guarded) {
        $sourceId=$manifest.package_id
        $manifest.package_id=$sourceId+'-rollback-failure-'+$ExpectedRuntimeSha256.Substring(0,12)
        $manifest | Add-Member -NotePropertyName source_package_id -NotePropertyValue $sourceId -Force
        $manifest | Add-Member -NotePropertyName rehearsal_mode -NotePropertyValue 'NativeDesktopRehearsal' -Force
        $manifest | Add-Member -NotePropertyName expected_runtime_exit_code -NotePropertyValue 86 -Force
    }
    $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $out 'package-manifest.json') -Encoding UTF8
    $derivedContract = $Contract.Clone()
    $derivedContract.manifest_sha256 = (Get-FileHash -LiteralPath (Join-Path $out 'package-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($guarded) { $derivedContract.package_id=$manifest.package_id }
    $verified = Get-YimeCoreFaultPreparationCatalog $out $derivedContract
    # Input handles stay open through source/output verification. These copy leases
    # do not seal directory membership, deny preexisting mappings, or authorize execution.
    $null = Get-YimeCoreFaultPreparationCatalog $PackageRoot $Contract
    return [ordered]@{
        schema_version=('yimecore-'+$tag+'-fault-preparation-output-v1');prepared_only=$true;failure_package_prepared=$true
        source_package=$catalog.root;source_manifest_sha256=$catalog.manifest_sha256;output_root=$out
        failure_manifest_sha256=$verified.manifest_sha256;file_count=$verified.file_count;failure_runtime_sha256=$runtimeRecord.sha256
        changed_package_members=@('bin/YimeCoreTrialRuntime.exe','package-manifest.json');maintenance_controller_preserved=$true
        expected_probe_exit_code=86;probe_exit_observed=$false;probe_pe_machine='AMD64';static_package_verification_passed=$true
        execution_authorized=$false;ready_to_execute=$false;installer_executed=$false;product_executed=$false
        installed_package_read=$false;user_state_read=$false;product_mutated=$false;unexpected_success_rollback_guard_available=$guarded
        input_copy_leases='FileShare.Read; held through output/source verification';same_sid_execution_boundary=$false
        source_package_id=$(if ($guarded) {$sourceId} else {$null});failure_package_id=$(if ($guarded) {$manifest.package_id} else {$null})
    }
    } finally { foreach ($stream in $leases.Values) { $stream.Dispose() } }
}

Export-ModuleMember -Function Get-YimeCoreFaultPreparationCatalog,Get-YimeCoreFaultPreparationPlan,New-YimeCoreFaultPreparationOutput,Assert-YimeCoreFailureProbePe,Assert-PreparationNewChild
