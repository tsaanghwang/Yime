# DP1-U native read-only observation increment. No execution/maintenance capability.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Initialize-Dp1UNativeFacts {
    if (-not ('Yime.Dp1UNative.Facts' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-facts.cs')
    }
}

function Assert-Dp1UNativeShape($Value, $Schema, [string]$At) {
    if ($Schema.type -eq 'object') {
        if ($Value -isnot [pscustomobject]) { throw "$At must be object" }
        $names = @($Value.PSObject.Properties.Name)
        if ($names.Count -ne @($Schema.required).Count) { throw "$At field set mismatch" }
        foreach ($name in $Schema.required) {
            if ($names -cnotcontains $name) { throw "$At missing field: $name" }
            Assert-Dp1UNativeShape $Value.$name $Schema.properties.$name "$At.$name"
        }
    } elseif ($Schema.type -eq 'boolean') {
        if ($Value -isnot [bool]) { throw "$At must be boolean" }
    } elseif ($Schema.type -eq 'string') {
        if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or
            $Value -cne $Value.Trim() -or $Value -match '[\x00-\x1f]') { throw "$At must be canonical string" }
    } else { throw 'Unsupported authorization schema type' }
    if ($Schema.PSObject.Properties['const'] -and $Value -cne $Schema.const) { throw "$At constant mismatch" }
    if ($Schema.PSObject.Properties['pattern'] -and $Value -cnotmatch $Schema.pattern) { throw "$At pattern mismatch" }
}

function Get-Dp1UNativeBytesDigest([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Dp1UNativeObjectDigest($Value, $Schema, [string]$Domain) {
    $text = $Domain + ';'
    foreach ($name in $Schema.required) {
        $scalar = $Value.$name
        if ($scalar -is [bool]) { $scalar = $scalar.ToString().ToLowerInvariant() }
        $text += $name + ':' + [Text.Encoding]::UTF8.GetByteCount($scalar).ToString([Globalization.CultureInfo]::InvariantCulture) + ':' + $scalar + ';'
    }
    Get-Dp1UNativeBytesDigest ([Text.Encoding]::UTF8.GetBytes($text))
}

function Assert-Dp1UNativePlainPath([string]$Path) {
    if ($Path -cnotmatch '^[A-Z]:\\[^\\]+' -or $Path -match '[\x00-\x1f/"<>|?*%]' -or $Path.Substring(2).Contains(':')) {
        throw 'Canonical local path required'
    }
    foreach ($part in $Path.Substring(3).Split('\')) {
        if (-not $part -or $part -in @('.', '..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw 'Ambiguous path component' }
    }
    $cursor = $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse path rejected' }
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Open-Dp1UNativeArtifact([string]$Path, [string]$ExpectedDigest, [long]$MaxBytes = 16777216, [switch]$Json) {
    Assert-Dp1UNativePlainPath $Path
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $identity = [Yime.Dp1UNative.Facts]::VerifyFileHandle($stream, $Path)
        if ($stream.Length -le 0 -or $stream.Length -gt $MaxBytes) { throw 'Artifact size outside bounded read' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($ExpectedDigest -and $digest -cne $ExpectedDigest) { throw 'Approved artifact digest mismatch' }
        $value = $null
        if ($Json) {
            $stream.Position = 0
            $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true, 4096, $true)
            try { $jsonText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            # Preserve timestamp strings across PS5 and newer PS7 ConvertFrom-Json.
            $options = @{}
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
            $value = ConvertFrom-Json -InputObject $jsonText @options
        }
        [pscustomobject]@{ stream=$stream; path=$Path; sha256=$digest; bytes=$stream.Length; file_identity=$identity; value=$value }
    } catch { $stream.Dispose(); throw }
}

function Assert-Dp1UNativeRequest($Authorization, $Boundary, [string]$TrustedApprovalSha256, [string]$MachineName, [DateTime]$NowUtc) {
    $schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.schema.json') -Raw | ConvertFrom-Json
    Assert-Dp1UNativeShape $Authorization $schema.properties.authorization 'authorization'
    Assert-Dp1UNativeShape $Boundary $schema.properties.product_boundary 'product_boundary'
    if ($MachineName -match '(?i)^MYCOMPUTER(?:\.|$)' -or $Authorization.target_name -match '(?i)^MYCOMPUTER(?:\.|$)') { throw 'MYCOMPUTER daily-use local.12 target prohibited' }
    if ($Authorization.target_name -ine $MachineName) { throw 'Explicit target does not match native computer name' }
    if ($TrustedApprovalSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-Dp1UNativeObjectDigest $Authorization $schema.properties.authorization 'dp1u-authorization-v1') -cne $TrustedApprovalSha256) { throw 'Independent approval digest mismatch' }
    if ((Get-Dp1UNativeObjectDigest $Boundary $schema.properties.product_boundary 'dp1u-product-boundary-v1') -cne $Authorization.product_boundary_sha256) { throw 'Approved product boundary mismatch' }
    $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $start = [DateTime]::ParseExact($Authorization.approved_at_utc, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, $style)
    $end = [DateTime]::ParseExact($Authorization.expires_at_utc, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, $style)
    if ($start -gt $NowUtc -or $end -le $NowUtc -or $end -le $start -or ($end-$start).TotalHours -gt 24) { throw 'Approval outside bounded validity' }
    # Source identities are fixed; caller-provided fictitious peer GUIDs cannot hide local.12.
    $identity = @{
        clsid='{35f67e9d-a54d-4177-9697-8b0ab71a9e04}'; profile_guid='{3f6b5a12-8d44-4e71-9a2e-6b4f9c1d2a30}'
        peer_clsid='{e40fa752-bb96-461d-a51d-f40eb437ec65}'; peer_profile_guid='{126f54c6-e9b1-4e22-8652-03224cbd49f9}'
        run_value_name='PIMELauncher'; uninstall_key_name='YIME'
        peer_run_value_name='YimeCoreExperimentalTrial'; peer_uninstall_key_name='YimeCoreExperimentalTrial'
    }
    foreach ($entry in $identity.GetEnumerator()) { if ($Boundary.($entry.Key) -cne $entry.Value) { throw ('Source product identity mismatch: '+$entry.Key) } }
    if ($Boundary.runtime_endpoint -ieq $Boundary.peer_runtime_endpoint) { throw 'Runtime endpoints overlap' }
    $roots = @()
    foreach ($name in @('install_root','state_root','recovery_root')) {
        if ($Authorization.$name -cne $Boundary.$name) { throw 'Approval root binding mismatch' }
        if ($Authorization.$name -match '(?i)\\(?:AppData|Windows|Program Files(?: \(x86\))?|YimeCore Experimental Trial|YimeCore Recovery Archives)(?:\\|$)') { throw 'Product root in protected or private location' }
        $roots += $Authorization.$name
    }
    $roots += @($Boundary.peer_install_root,$Boundary.peer_state_root,$Boundary.peer_recovery_root,$Boundary.production_install_root,$Boundary.production_state_root)
    foreach ($root in $roots) { Assert-Dp1UNativePlainPath $root }
    for ($i=0; $i -lt $roots.Count; $i++) {
        for ($j=$i+1; $j -lt $roots.Count; $j++) {
            if ($roots[$i] -ieq $roots[$j] -or $roots[$i].StartsWith($roots[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or $roots[$j].StartsWith($roots[$i]+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Product roots overlap' }
        }
    }
}

function Invoke-Dp1UNativeRegistryRead([ValidateSet('EnumValues','GetStringValue','GetBinaryValue')][string]$Method,
    [uint32]$Hive, [string]$Key, [string]$Name, [ValidateSet(32,64)][int]$View) {
    $context=$null; $locator=$null; $services=$null; $provider=$null; $metadata=$null; $input=$null; $output=$null
    try {
        $context = New-Object -ComObject WbemScripting.SWbemNamedValueSet
        $null = $context.Add('__ProviderArchitecture', $View)
        $null = $context.Add('__RequiredArchitecture', $true)
        $locator = New-Object -ComObject WbemScripting.SWbemLocator
        $services = $locator.ConnectServer('.', 'root\default', '', '', '', '', 0, $context)
        $provider = $services.Get('StdRegProv')
        $metadata = $provider.Methods_.Item($Method)
        $input = $metadata.InParameters.SpawnInstance_()
        $input.Properties_.Item('hDefKey').Value = $Hive
        $input.Properties_.Item('sSubKeyName').Value = $Key
        if ($Method -ne 'EnumValues') { $input.Properties_.Item('sValueName').Value = $Name }
        $output = $provider.ExecMethod_($Method, $input, 0, $context)
        $copy = [ordered]@{}
        foreach ($property in $output.Properties_) { $copy[[string]$property.Name] = $property.Value }
        if ($null -eq $copy.ReturnValue -or [int]$copy.ReturnValue -notin @(0,2)) { throw 'StdRegProv failure; no process registry fallback' }
        [pscustomobject]$copy
    } finally {
        foreach ($item in @($output,$input,$metadata,$provider,$services,$locator,$context)) {
            if ($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) }
        }
    }
}

function Get-Dp1UNativeRegistryCatalog([string]$Sid) {
    if ($Sid -cnotmatch '^S-1-5-21-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*$') { throw 'Canonical initiating SID required' }
    $result = @()
    foreach ($clsid in @('{E40FA752-BB96-461D-A51D-F40EB437EC65}','{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}','{35F67E9D-A54D-4177-9697-8B0AB71A9E04}')) {
        foreach ($coordinate in @(
            @{hive=[uint32]2147483650; key="SOFTWARE\Classes\CLSID\$clsid"},
            @{hive=[uint32]2147483650; key="SOFTWARE\Microsoft\CTF\TIP\$clsid"},
            @{hive=[uint32]2147483651; key="$Sid\SOFTWARE\Classes\CLSID\$clsid"},
            @{hive=[uint32]2147483651; key="$Sid\SOFTWARE\Microsoft\CTF\TIP\$clsid"}
        )) { $result += [pscustomobject]$coordinate }
    }
    foreach ($name in @('YIME','YimeCoreExperimentalTrial')) {
        $result += [pscustomobject]@{hive=[uint32]2147483650;key="SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$name"}
        $result += [pscustomobject]@{hive=[uint32]2147483651;key="$Sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$name"}
    }
    $result += [pscustomobject]@{hive=[uint32]2147483650;key='SOFTWARE\YIME'}
    $result
}

function Test-Dp1UNativeNamedValuePresent($Reply, [string]$Name) {
    if ($null -eq $Reply -or ($Reply.ReturnValue -isnot [int] -and $Reply.ReturnValue -isnot [uint32]) -or $Reply.ReturnValue -notin @(0,2)) { throw 'Invalid native registry enumeration result' }
    if ($Reply.ReturnValue -eq 2) { return $false }
    $names=@(); $types=@()
    if ($null -ne $Reply.sNames) { $names=@($Reply.sNames) }
    if ($null -ne $Reply.Types) { $types=@($Reply.Types) }
    if ($names.Count -ne $types.Count) { throw 'Inconsistent native registry names/types' }
    foreach ($valueName in $names) {
        if ($valueName -isnot [string]) { throw 'Invalid native registry value name' }
        # Presence alone rejects the target. Wrong types must never look absent.
        if ($valueName -ieq $Name) { return $true }
    }
    return $false
}

function Get-Dp1UNativeContext([string]$Sid, [string]$MachineGuid, [switch]$AllowCurrentYimeCore) {
    if ([Yime.Dp1UNative.Facts]::Architecture() -cne 'x64') { throw 'Native x64 target required' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $Sid) { throw 'Same initiating SID required' }
    $leases = [Collections.Generic.List[object]]::new()
    try {
        $processId = $PID; $seen = @{}; $ancestry = @(); $childCreated = [long]::MaxValue; $explorerFound = $false
        for ($depth=0; $depth -lt 32; $depth++) {
            if ($processId -le 0 -or $seen.ContainsKey($processId)) { throw 'Missing or cyclic process ancestry' }
            $seen[$processId] = $true
            $lease = [Yime.Dp1UNative.Facts]::OpenProcessFacts($processId); $leases.Add($lease)
            if ($lease.PackageQuery -ne 15700 -or $lease.Image -match '(?i)\\WindowsApps\\') { throw 'Packaged or unknown ancestry prohibited' }
            if ($lease.Sid -cne $Sid -or $lease.Elevated) { throw 'Unpackaged non-elevated same-SID Explorer initiator required' }
            if ($lease.CreationFileTime -gt $childCreated) { throw 'Reused parent PID rejected' }
            $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$processId" -Property ProcessId,ParentProcessId,ExecutablePath,CreationDate -ErrorAction Stop
            if ($null -eq $process -or $process.ExecutablePath -ine $lease.Image -or
                [Math]::Abs($process.CreationDate.ToUniversalTime().ToFileTimeUtc() - $lease.CreationFileTime) -gt 10) { throw 'Process identity changed during ancestry read' }
            $ancestry += [pscustomobject][ordered]@{pid=$processId;parent_pid=[int]$process.ParentProcessId;image=$lease.Image;sid=$lease.Sid;creation_filetime=$lease.CreationFileTime;package_query=$lease.PackageQuery;elevated=$lease.Elevated}
            $explorer = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'explorer.exe'
            if ($lease.Image -ieq $explorer) { $explorerFound=$true; break }
            if ($depth -eq 0 -and [IO.Path]::GetFileName($lease.Image) -notin @('powershell.exe','pwsh.exe')) { throw 'Standalone PowerShell entry required' }
            $childCreated=$lease.CreationFileTime; $processId=[int]$process.ParentProcessId
        }
        if (-not $explorerFound) { throw 'Complete same-SID ancestry to native Explorer not established' }
        # Only after unpackaged ancestry is established, read required native provider.
        # Never use environment or process registry as a MachineGuid fallback.
        $machine = Invoke-Dp1UNativeRegistryRead GetStringValue 2147483650 'SOFTWARE\Microsoft\Cryptography' 'MachineGuid' 64
        if ($machine.ReturnValue -ne 0 -or [string]$machine.sValue -ine $MachineGuid) { throw 'Native MachineGuid mismatch' }
        $registry = @()
        foreach ($view in @(32,64)) {
            $hku = Invoke-Dp1UNativeRegistryRead EnumValues 2147483651 $Sid '' $view
            if ($hku.ReturnValue -ne 0) { throw 'Initiating HKU hive is not system visible' }
            foreach ($coordinate in @(Get-Dp1UNativeRegistryCatalog $Sid)) {
                # Only the current peer is admitted by the executable controller,
                # which separately binds and protects its complete observation.
                # The historical readonly probe retains its clean-target default.
                if($AllowCurrentYimeCore -and ($coordinate.key -imatch '\{E40FA752-BB96-461D-A51D-F40EB437EC65\}|\\Uninstall\\YimeCoreExperimentalTrial$')){continue}
                $record = Invoke-Dp1UNativeRegistryRead EnumValues $coordinate.hive $coordinate.key '' $view
                if ($record.ReturnValue -ne 2) { throw 'Protected YimeCore/local.12 or production Rime/PIME registration exists' }
                $registry += [pscustomobject][ordered]@{view=$view;hive=$coordinate.hive;key=$coordinate.key;name=$null;exists=$false}
            }
            foreach ($hive in @([uint32]2147483650,[uint32]2147483651)) {
                $runKey='SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                if ($hive -eq 2147483651) { $runKey=$Sid+'\'+$runKey }
                $runNames = Invoke-Dp1UNativeRegistryRead EnumValues $hive $runKey '' $view
                foreach ($runName in @('PIMELauncher','YimeCoreExperimentalTrial')) {
                    if($AllowCurrentYimeCore -and $runName -ceq 'YimeCoreExperimentalTrial'){continue}
                    if (Test-Dp1UNativeNamedValuePresent $runNames $runName) { throw 'Protected product autostart exists (any registry value kind)' }
                    $registry += [pscustomobject][ordered]@{view=$view;hive=$hive;key=$runKey;name=$runName;exists=$false}
                }
            }
        }
        [pscustomobject][ordered]@{machine_guid=$machine.sValue;native_architecture='x64';process_sid=$Sid;registry_provider='out-of-process-StdRegProv';registry_hku_path=('HKEY_USERS\'+$Sid);protected_registration_absence=$registry;ancestry_to_explorer=$ancestry}
    } finally { foreach ($lease in $leases) { $lease.Dispose() } }
}

function Get-Dp1UNativeCandidateAssessment([string]$EvidenceRoot, $PackageLease, $ReceiptLease) {
    Assert-Dp1UNativePlainPath $EvidenceRoot
    $root=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Explicit receipt evidence root is missing' }
    foreach ($path in @($PackageLease.path,$ReceiptLease.path)) {
        if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Approved artifact is outside its explicit receipt evidence root' }
    }
    # Reuse the source-owned strict reader, including retained objects/sidecars,
    # cross-evidence semantics and NSIS raw digest bindings. No execution callbacks.
    Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.psm1') -Scope Local
    $strict = rime-pime-package-receipt-v2\Read-RimePimePackageBuildReceiptV2 -RepoRoot $root -ReceiptPath $ReceiptLease.path
    if ($strict.Digest -cne $ReceiptLease.sha256 -or $strict.Receipt.installer.sha256 -cne $PackageLease.sha256 -or
        [long]$strict.Receipt.installer.bytes -ne $PackageLease.bytes) { throw 'Strict receipt differs from approved leased candidate' }
    $r=$strict.Receipt
    # The understood canonical-v2 schema is explicitly disabled/unsigned. A new
    # executable schema needs its own trusted reader; it cannot be admitted by
    # flipping these booleans, adding a signature to this file, or a caller flag.
    if ($r.receipt_state -cne 'canonical-static-closure-disabled' -or
        $r.unsigned_disabled_build -isnot [bool] -or -not $r.unsigned_disabled_build -or
        $r.delivery_admitted -isnot [bool] -or $r.delivery_admitted -or
        $r.signing_complete -isnot [bool] -or $r.signing_complete) { throw 'Strict reader returned an unsupported executable-candidate contract' }
    [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-dp1u-native-candidate-assessment-v1'
        strict_reader='Read-RimePimePackageBuildReceiptV2'; strict_receipt_evidence_chain_verified=$true
        evidence_root=$root; receipt_sha256=$strict.Digest; package_sha256=$PackageLease.sha256
        product_version=$r.product_version; receipt_state=$r.receipt_state
        retained_evidence_used=$r.evidence_artifacts_durable
        executable_candidate_safe=$false; candidate_execution_admitted=$false
        rejection_reasons=@('canonical-v2 is a disabled NSIS artifact, not an executable candidate',
            'trusted executable-release identity and signing have not been admitted',
            'canonical delivery_admitted remains false; DP1-R derived disabled-static trust is not execution permission')
        strict_reader_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
        retained_store_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
        execution_authorized=$false; installer_executed=$false; uninstaller_executed=$false
    }
}

function Invoke-RimePimeDp1UNativeReadOnlyProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AuthorizationPath, [Parameter(Mandatory)][string]$TrustedApprovalSha256,
        [Parameter(Mandatory)][string]$BoundaryPath, [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][string]$CanonicalReceiptPath, [Parameter(Mandatory)][string]$ReceiptEvidenceRoot)
    # MUST precede reading any caller path, package, registry, or product fact.
    if ([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|$)') { throw 'MYCOMPUTER daily-use local.12 target prohibited before probing' }
    Initialize-Dp1UNativeFacts
    $leases = [Collections.Generic.List[object]]::new()
    try {
        $approval = Open-Dp1UNativeArtifact $AuthorizationPath '' -Json; $leases.Add($approval)
        $boundary = Open-Dp1UNativeArtifact $BoundaryPath '' -Json; $leases.Add($boundary)
        $a=$approval.value; $b=$boundary.value
        Assert-Dp1UNativeRequest $a $b $TrustedApprovalSha256 ([Environment]::MachineName) ([DateTime]::UtcNow)
        $context = Get-Dp1UNativeContext $a.initiating_sid $a.target_machine_id
        # Fixed installed-product roots cannot be hidden by alternate roots in the approval.
        foreach ($fixedRoot in @(
            (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)) 'YIME'),
            (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'YimeCore Experimental Trial'),
            (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'YimeCore Experimental Trial')
        )) { if (Test-Path -LiteralPath $fixedRoot) { throw 'Fixed protected product install root exists' } }
        # This increment supports a clean isolated initial-install target only.
        foreach ($root in @($a.install_root,$a.state_root,$a.recovery_root)) {
            if (Test-Path -LiteralPath $root) { throw 'Initial native probe requires new absent product roots' }
        }
        if (Test-Path -LiteralPath $b.production_install_root) { throw 'Protected production install root exists' }
        if (Test-Path -LiteralPath $b.peer_install_root) { throw 'Protected YimeCore install root exists' }
        $package = Open-Dp1UNativeArtifact $PackagePath $a.package_sha256 4294967296; $leases.Add($package)
        $receipt = Open-Dp1UNativeArtifact $CanonicalReceiptPath $a.canonical_receipt_sha256 -Json; $leases.Add($receipt)
        $candidate = Get-Dp1UNativeCandidateAssessment $ReceiptEvidenceRoot $package $receipt
        # Recheck bounded approval time at completion, while all artifact leases remain held.
        Assert-Dp1UNativeRequest $a $b $TrustedApprovalSha256 ([Environment]::MachineName) ([DateTime]::UtcNow)
        [pscustomobject][ordered]@{
            schema_version='yime-rime-pime-dp1u-native-readonly-observation-v2'; observed_at_utc=[DateTime]::UtcNow.ToString('o')
            run_id=$a.run_id; target_name=[Environment]::MachineName; target_machine_id=$a.target_machine_id; initiating_sid=$a.initiating_sid
            authorization_sha256=$TrustedApprovalSha256; authorization_raw_sha256=$approval.sha256; boundary_raw_sha256=$boundary.sha256
            product_boundary_sha256=$a.product_boundary_sha256; package_sha256=$package.sha256; canonical_receipt_sha256=$receipt.sha256
            package_file_identity=$package.file_identity; receipt_file_identity=$receipt.file_identity; native_context=$context
            candidate_assessment=$candidate; candidate_execution_admitted=$candidate.candidate_execution_admitted
            native_readonly_observation_completed=$true; native_preflight_complete=$false; execution_authorized=$false
            registration_gate_passed=$false; rollback_gate_passed=$false; removal_gate_passed=$false; runtime_gate_passed=$false; dp1_u_acceptance_passed=$false
            pending=@('independent approval authentication/revocation and run-id consumption','trusted runnable candidate with a supported executable receipt contract',
                'system-visible root identity leases through complete transaction','default-input-method preservation baseline',
                'same-SID elevation worker and non-elevated runtime native observations','native registration/rollback/removal/runtime transaction providers and actual acceptance')
            privacy=[ordered]@{installer_executed=$false;registry_mutated=$false;product_processes_started_or_stopped=$false;user_data_read=$false;default_input_method_changed=$false}
        }
    } finally { foreach ($lease in $leases) { $lease.stream.Dispose() } }
}

Export-ModuleMember -Function Invoke-RimePimeDp1UNativeReadOnlyProbe
