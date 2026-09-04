[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Plan')]
    [string]$Action = 'Install',
    [string]$PackageRoot,
    [string]$InstallRoot,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [switch]$Force,
    [switch]$PurgeUserData,
    [switch]$NoAutoStart,
    [switch]$NoLaunch,
    [switch]$NoElevation,
    [switch]$Quiet,
    [switch]$NativeX64Rehearsal,
    [switch]$NativeX64Only,
    [switch]$NativeDesktop,
    [string]$TargetUserSid,
    [string]$StandardUserInitiator
)

$ErrorActionPreference = 'Stop'
$NativeLocalProduct = [bool]($NativeX64Only -or $NativeDesktop)
if ($NativeX64Only -and $NativeDesktop) { throw 'Choose exactly one local-product architecture mode.' }
$productName = 'Yime ' + (-join ([char[]](0x81EA, 0x7814, 0x6808, 0x8BD5, 0x9A8C, 0x7248)))
$productKeyName = 'YimeCoreExperimentalTrial'
$productRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'YimeCore Experimental Trial'))
$stateRootPath = [IO.Path]::GetFullPath($StateRoot)
$legacyMachineUninstallKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productKeyName"
if ([string]::IsNullOrWhiteSpace($TargetUserSid)) {
    $TargetUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
try {
    $TargetUserSid = ([Security.Principal.SecurityIdentifier]::new($TargetUserSid)).Value
} catch {
    throw "invalid target user SID: $TargetUserSid"
}
$runKey = "Registry::HKEY_USERS\$TargetUserSid\Software\Microsoft\Windows\CurrentVersion\Run"
$uninstallKey = "Registry::HKEY_USERS\$TargetUserSid\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productKeyName"
$nativeArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
	$env:PROCESSOR_ARCHITEW6432.ToUpperInvariant()
} else { ([string]$env:PROCESSOR_ARCHITECTURE).ToUpperInvariant() }
if ($nativeArchitecture -notin @('AMD64', 'ARM64')) {
	throw "unsupported Windows native architecture: $nativeArchitecture"
}
$clsid = '{E40FA752-BB96-461D-A51D-F40EB437EC65}'
$profile = '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
$legacyClsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$legacyProfile = '{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$tip = "0804:$clsid$profile"
$userTipKey = "Registry::HKEY_USERS\$TargetUserSid\Software\Microsoft\CTF\TIP\$clsid"
$legacyUserTipKey = "Registry::HKEY_USERS\$TargetUserSid\Software\Microsoft\CTF\TIP\$legacyClsid"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Windows PowerShell is missing: $windowsPowerShell"
}
function Get-YimeMaintenancePackageIdentity {
    if (-not ('YimeMaintenancePackageIdentity' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YimeMaintenancePackageIdentity {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, IntPtr name);
    public static int Query() { uint length=0; return GetCurrentPackageFullName(ref length, IntPtr.Zero); }
}
'@
    }
    return [YimeMaintenancePackageIdentity]::Query()
}
function Get-YimeMaintenancePackagedAncestor {
    $windowsAppsPrefix = (Join-Path $env:ProgramFiles 'WindowsApps\')
    $processId = $PID
    $seen = @{}
    for ($depth=0; $depth -lt 32 -and $processId -gt 0; $depth++) {
        if ($seen.ContainsKey($processId)) { break }
        $seen[$processId]=$true
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId"
        if (-not $process) { break }
        if ([string]$process.ExecutablePath -and
            ([string]$process.ExecutablePath).StartsWith($windowsAppsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            return [string]$process.ExecutablePath
        }
        if ($process.Name -ieq 'explorer.exe') { break }
        $processId = [int]$process.ParentProcessId
    }
    return ''
}
function Assert-UnpackagedTrialMaintenance {
    $packageResult = Get-YimeMaintenancePackageIdentity
    # APPMODEL_ERROR_NO_PACKAGE. A packaged caller's HKCU/HKU reads and writes
    # can agree inside its private overlay while Explorer sees an older install.
    # A breakaway command child can report NO_PACKAGE while still observing a
    # different registry view. Conservatively reject packaged-app ancestry too.
    $packagedAncestor = Get-YimeMaintenancePackagedAncestor
    if ($packageResult -ne 15700 -or -not [string]::IsNullOrEmpty($packagedAncestor)) {
        throw "Trial maintenance requires standalone Windows PowerShell launched from Explorer under the initiating user (package query=$packageResult; packaged ancestor=$packagedAncestor). Do not launch install/uninstall from a packaged application; registry virtualization can hide Run/TIP/uninstall writes. No maintenance mutation was performed."
    }
}
if ($Action -ne 'Plan') { Assert-UnpackagedTrialMaintenance }
if ($NativeLocalProduct -and $Action -ne 'Plan' -and $StandardUserInitiator) {
    $env:YIMECORE_MAINTENANCE_INITIATOR=$StandardUserInitiator
}
if ($NativeLocalProduct -and ($NativeX64Rehearsal -or $nativeArchitecture -ne 'AMD64' -or
    -not [Environment]::Is64BitProcess -or $env:COMPUTERNAME -ne 'MYCOMPUTER' -or $PurgeUserData -or
    ($Action -eq 'Install' -and $NoLaunch))) {
    throw 'Native local-product maintenance requires MYCOMPUTER native x64, preserved user data, and is not a fault-rehearsal mode.'
}
if ($NativeLocalProduct -and $Action -ne 'Plan' -and
    $stateRootPath -ine [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))) {
    throw 'Normal local maintenance must preserve the initiating user default state namespace used at logon.'
}
$maintenanceErrorPath = Join-Path $stateRootPath 'maintenance-last-error.txt'
trap {
    try {
        if ($Action -eq 'Plan') { throw 'Read-only plan: do not write a maintenance error into AppData.' }
        New-Item -ItemType Directory -Path $stateRootPath -Force | Out-Null
        $errorText = ($_ | Format-List * -Force | Out-String) + "`n" +
            ($_.ScriptStackTrace | Out-String)
        [IO.File]::WriteAllText($maintenanceErrorPath, $errorText, $utf8NoBom)
    } catch {}
    Write-Error $_
    exit 1
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument([string]$value) {
    return '"' + $value.Replace('"', '\"') + '"'
}

function Get-RegistryKeySnapshot([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{ exists = $false; values = @(); children = [ordered]@{} }
    }
    $key = Get-Item -LiteralPath $path
    try {
    $values = @($key.GetValueNames() | Sort-Object | ForEach-Object {
        [ordered]@{
            name = $_
            value = $key.GetValue($_, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            kind = [int]$key.GetValueKind($_)
        }
    })
    $children = [ordered]@{}
    foreach ($name in @($key.GetSubKeyNames() | Sort-Object)) {
        $children[$name] = Get-RegistryKeySnapshot ($path + '\' + $name)
    }
    return [ordered]@{ exists = $true; values = $values; children = $children }
    } finally { $key.Dispose() }
}

function Restore-RegistryKeySnapshot([string]$path, $snapshot) {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $snapshot -or -not $snapshot.exists) { return }
    New-Item -Path $path -Force | Out-Null
    foreach ($value in @($snapshot.values)) {
        New-ItemProperty -LiteralPath $path -Name ([string]$value.name) `
            -Value $value.value `
            -PropertyType ([Microsoft.Win32.RegistryValueKind]([int]$value.kind)) `
            -Force | Out-Null
    }
    if ($snapshot.children) {
        foreach ($name in $snapshot.children.Keys) {
            Restore-RegistryKeySnapshot ($path + '\' + $name) $snapshot.children[$name]
        }
    }
}

function Get-RegistryValueSnapshot([string]$path, [string]$name) {
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{ exists = $false }
    }
    $key = Get-Item -LiteralPath $path
    if ($key.GetValueNames() -notcontains $name) {
        return [ordered]@{ exists = $false }
    }
    return [ordered]@{
        exists = $true
        value = $key.GetValue($name, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        kind = [int]$key.GetValueKind($name)
    }
}

function Restore-RegistryValueSnapshot([string]$path, [string]$name, $snapshot) {
    if (-not $snapshot -or -not $snapshot.exists) {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
        return
    }
    Initialize-RegistryKeyPreservingValues $path
    New-ItemProperty -LiteralPath $path -Name $name -Value $snapshot.value `
        -PropertyType ([Microsoft.Win32.RegistryValueKind]([int]$snapshot.kind)) `
        -Force | Out-Null
}

function Initialize-RegistryKeyPreservingValues([string]$path) {
    # Registry New-Item -Force replaces an existing key, unlike a directory.
    # Never erase another application's Run values when ensuring our parent.
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -ErrorAction Stop | Out-Null }
}

function Restore-RegistryKeySnapshotInPlace([string]$path, $snapshot) {
    if (-not $snapshot -or -not $snapshot.exists) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Initialize-RegistryKeyPreservingValues $path
    $key = Get-Item -LiteralPath $path
    try {
        $currentValues = @($key.GetValueNames())
        $currentChildren = @($key.GetSubKeyNames())
        $expectedChildren = if ($snapshot.children) { @($snapshot.children.Keys) } else { @() }
    } finally { $key.Dispose() }
    $expectedValues = @($snapshot.values | ForEach-Object { [string]$_.name })
    foreach ($name in $currentValues) {
        if ($expectedValues -notcontains $name) {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop
        }
    }
    foreach ($value in @($snapshot.values)) {
        New-ItemProperty -LiteralPath $path -Name ([string]$value.name) -Value $value.value `
            -PropertyType ([Microsoft.Win32.RegistryValueKind]([int]$value.kind)) -Force | Out-Null
    }
    foreach ($name in $currentChildren) {
        if ($expectedChildren -notcontains $name) {
            Remove-Item -LiteralPath ($path + '\' + $name) -Recurse -Force -ErrorAction Stop
        }
    }
    if ($snapshot.children) {
        foreach ($name in $snapshot.children.Keys) {
            Restore-RegistryKeySnapshotInPlace ($path + '\' + $name) $snapshot.children[$name]
        }
    }
}

function Get-FrozenTipSnapshot {
    if (-not $NativeLocalProduct) { return $null }
    Get-RegistryKeySnapshot "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$legacyClsid"
}

function Restore-FrozenTipSnapshot($snapshot) {
    if (-not $NativeLocalProduct) { return }
    if ($null -eq $snapshot) { throw 'Missing frozen TIP snapshot; cannot declare native registration preservation.' }
    # x64 TSF profile APIs can also write the WOW64 profile metadata. Preserve
    # that exact owned subtree, including absence/value kinds, without executing
    # a frozen binary or changing its COM server, categories or profile identity.
    $path="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$legacyClsid"
    # Preserve the identity and ACL of every expected existing key. Removing
    # and recreating this frozen root would itself be a registration mutation.
    Restore-RegistryKeySnapshotInPlace $path $snapshot
    $actual=Get-RegistryKeySnapshot $path
    if (($actual|ConvertTo-Json -Depth 35 -Compress) -cne ($snapshot|ConvertTo-Json -Depth 35 -Compress)) {
        throw 'Frozen TIP snapshot restoration did not converge.'
    }
}

function Get-FrozenUserTipSnapshot {
    if (-not $NativeLocalProduct) { return $null }
    Get-RegistryKeySnapshot $legacyUserTipKey
}

function Restore-FrozenUserTipSnapshot($snapshot) {
    if (-not $NativeLocalProduct) { return }
    if ($null -eq $snapshot) { throw 'Missing frozen per-user TIP snapshot; cannot declare identity preservation.' }
    Restore-RegistryKeySnapshotInPlace $legacyUserTipKey $snapshot
    $actual=Get-RegistryKeySnapshot $legacyUserTipKey
    if (($actual|ConvertTo-Json -Depth 35 -Compress) -cne ($snapshot|ConvertTo-Json -Depth 35 -Compress)) {
        throw 'Frozen per-user TIP snapshot restoration did not converge.'
    }
}

function Enable-TargetUserTip([string]$path, [string]$profileGuid) {
    if ([string]::IsNullOrWhiteSpace($path) -or
        $profileGuid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
        throw 'Invalid per-user TIP enable target.'
    }
    $profileKey = Join-Path $path "LanguageProfile\0x00000804\$profileGuid"
    New-Item -Path $profileKey -Force | Out-Null
    New-ItemProperty -LiteralPath $profileKey -Name Enable -Value ([uint32]1) `
        -PropertyType DWord -Force | Out-Null
    $key = Get-Item -LiteralPath $profileKey
    try {
        if ($key.GetValueKind('Enable') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            [int]$key.GetValue('Enable') -ne 1) {
            throw 'New per-user TIP profile was not enabled.'
        }
    } finally { $key.Dispose() }
}

function Remove-TargetUserTipState {
    if (Test-Path -LiteralPath $userTipKey) {
        Remove-Item -LiteralPath $userTipKey -Recurse -Force
    }
    if (Test-Path -LiteralPath $userTipKey) {
        throw 'Active per-user local product TIP remained after removal.'
    }
}

function Test-RestorablePreviousUserTipSnapshot([string]$previousInstallRoot, $snapshot) {
    return (-not [string]::IsNullOrWhiteSpace($previousInstallRoot) -and
        $null -ne $snapshot -and [bool]$snapshot.exists)
}

function Restart-Elevated {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-Argument $PSCommandPath),
        '-Action', $Action, '-StateRoot', (Quote-Argument $stateRootPath),
        '-TargetUserSid', (Quote-Argument $TargetUserSid))
    if ($NativeLocalProduct) {
        # Keep this ordinary PowerShell alive through WaitForExit below. The
        # elevated worker may duplicate only this explicit primary token.
        $env:YIMECORE_MAINTENANCE_INITIATOR=$null
        Initialize-StandardUserLauncher
        $reference=[YimeCore.LocalMaintenance.StandardUserLauncher]::CaptureInitiatorReference($TargetUserSid)
        $arguments += @('-StandardUserInitiator',(Quote-Argument $reference))
    }
    if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
        $arguments += @('-PackageRoot', (Quote-Argument ([IO.Path]::GetFullPath($PackageRoot))))
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        $arguments += @('-InstallRoot', (Quote-Argument ([IO.Path]::GetFullPath($InstallRoot))))
    }
    foreach ($name in @('Force', 'PurgeUserData', 'NoAutoStart', 'NoLaunch', 'Quiet', 'NativeX64Rehearsal', 'NativeX64Only', 'NativeDesktop')) {
        if ((Get-Variable -Name $name -ValueOnly)) { $arguments += "-$name" }
    }
    $process = Start-Process -FilePath $windowsPowerShell -Verb RunAs `
        -ArgumentList ($arguments -join ' ') -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    exit $process.ExitCode
}

function Assert-ProductChild([string]$path, [string]$description) {
    $resolved = [IO.Path]::GetFullPath($path)
    $prefix = $productRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$description must be a child of ${productRoot}: $resolved"
    }
    if ($NativeLocalProduct) {
        $cursor = $resolved
        while ($cursor) {
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Local product paths must not traverse a symlink or junction: $cursor"
            }
            $cursor = Split-Path -Parent $cursor
        }
    }
    return $resolved
}

function Get-RegistrationArchitectures {
    if ($NativeX64Only) {
        return @([ordered]@{ name = 'x64'; action = 'register' })
    }
    if ($NativeDesktop) {
        return @(
            [ordered]@{ name = 'x64'; action = 'register' },
            [ordered]@{ name = 'x86'; action = 'register-com' })
    }
    if ($NativeX64Rehearsal) {
        return @([ordered]@{ name = 'x64'; action = 'register' })
    }
	if ($nativeArchitecture -eq 'ARM64') {
		return @(
			[ordered]@{ name = 'arm64'; action = 'register' },
			[ordered]@{ name = 'x64'; action = 'register-com' },
			[ordered]@{ name = 'x86'; action = 'register-com' })
	}
	return @(
		[ordered]@{ name = 'x64'; action = 'register' },
		[ordered]@{ name = 'x86'; action = 'register-com' })
}

function Get-CurrentIdentityArchitecturesForRoot([string]$root) {
    if (-not $NativeLocalProduct) { return @((Get-RegistrationArchitectures) | ForEach-Object { $_.name }) }
    $descriptorPath = Join-Path $root 'local-product.json'
    if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf)) { return @() }
    try {
        $descriptor = Get-Content -LiteralPath $descriptorPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$descriptor.identity.clsid -cne $clsid -or
            [string]$descriptor.identity.profile -cne $profile -or
            [string]$descriptor.identity.product_key -cne $productKeyName) {
            return @()
        }
        $active = @($descriptor.scope.active_architectures)
        if ($active.Count -lt 1 -or @($active | Where-Object { $_ -notin @('x64','x86') }).Count -ne 0 -or
            @($active | Select-Object -Unique).Count -ne $active.Count) {
            throw "Invalid current-identity architecture declaration: $descriptorPath"
        }
        return $active
    } catch {
        throw "Cannot validate current-identity registration tools in ${root}: $_"
    }
}

function Get-RegistrationArchitecturesForRoot([string]$root) {
    if (-not $NativeLocalProduct) { return @(Get-RegistrationArchitectures) }
    $active = @(Get-CurrentIdentityArchitecturesForRoot $root)
    $result = @()
    if ($active -contains 'x64') { $result += [ordered]@{ name='x64'; action='register' } }
    if ($active -contains 'x86') { $result += [ordered]@{ name='x86'; action='register-com' } }
    return $result
}

function Find-CurrentRegistrationTool([string[]]$roots, [string]$architecture) {
    foreach ($root in $roots) {
        $declared = @(Get-CurrentIdentityArchitecturesForRoot $root)
        if ($NativeLocalProduct -and $declared -notcontains $architecture) { continue }
        $tool = Join-Path $root "$architecture\YimeTextServiceRegistration.exe"
        if (Test-Path -LiteralPath $tool -PathType Leaf) { return $tool }
    }
    return ''
}

function Get-PackageRecords([string]$root) {
    $normalizedRoot = [IO.Path]::GetFullPath($root)
	$rootInfo = Get-Item -LiteralPath $normalizedRoot -Force
	if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
		throw "package root must not be a reparse point: $normalizedRoot"
	}
	$items = @(Get-ChildItem -LiteralPath $normalizedRoot -Recurse -Force)
	$reparsePoint = $items | Where-Object {
		($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
	} | Select-Object -First 1
	if ($reparsePoint) { throw "package contains a reparse point: $($reparsePoint.FullName)" }
    return @($items | Where-Object { -not $_.PSIsContainer } | Where-Object {
        $_.Name -notin @('package-manifest.json', 'install-metadata.json')
    } | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($normalizedRoot.Length + 1).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Sort-Object path)
}

function Assert-Package([string]$root) {
    $resolved = [IO.Path]::GetFullPath($root)
    $manifestPath = Join-Path $resolved 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "missing package manifest: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $localContract = $manifest.PSObject.Properties['package_contract'] -and
        [string]$manifest.package_contract -eq 'yimecore-local-product-package-v1'
    if ($localContract) {
        . (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
        . (Join-Path $PSScriptRoot 'local-package-contract.ps1')
        $localPackage = Assert-LocalProductPackage $resolved
        $active = @($localPackage.descriptor.scope.active_architectures)
        if ($NativeX64Rehearsal -or
            (($active.Count -eq 1 -and $active[0] -eq 'x64') -and -not $NativeX64Only) -or
            (($active.Count -eq 2 -and $active[0] -eq 'x64' -and $active[1] -eq 'x86') -and -not $NativeDesktop) -or
            ($active.Count -notin @(1,2))) {
            throw 'Local product package architecture scope does not match its maintenance mode.'
        }
        $script:productName = [string]$localPackage.descriptor.display_name
        return [ordered]@{ root=$resolved; manifest=$manifest; manifest_path=$manifestPath;
            manifest_sha256=$localPackage.manifest_sha256; records=@(Get-PackageRecords $resolved);
            descriptor=$localPackage.descriptor }
    }
    if ([string]$manifest.tool_version -notlike 'yimecore-e6c-staged-package-*' -or
        ($manifest.PSObject.Properties['package_contract'] -and $manifest.package_contract)) {
        throw "not an E6-C trial package: $manifestPath"
    }
    $expected = @{}
    foreach ($record in @($manifest.files)) { $expected[[string]$record.path] = $record }
    $records = @(Get-PackageRecords $resolved)
    if ($records.Count -ne $expected.Count) { throw "package file count mismatch: $resolved" }
    foreach ($record in $records) {
        $wanted = $expected[$record.path]
        if (-not $wanted -or [int64]$wanted.bytes -ne [int64]$record.bytes -or
            [string]$wanted.sha256 -ne [string]$record.sha256) {
            throw "package hash mismatch: $($record.path)"
        }
    }
    foreach ($required in @(
        'x64\YimeTextServiceExperiment.dll', 'x64\YimeTextServiceRegistration.exe',
        'x86\YimeTextServiceExperiment.dll', 'x86\YimeTextServiceRegistration.exe',
		'arm64\YimeTextServiceExperiment.dll', 'arm64\YimeTextServiceRegistration.exe',
        'bin\YimeBroker.exe', 'bin\YimeCoreTrialRuntime.exe',
        'bin\YimeCoreInputToolbar.exe', 'bin\YimeCoreReverseLookup.exe',
        'bin\YimeCoreLexiconManager.exe', 'bin\YimeCoreTrainer.exe',
        'bin\YimeCoreToolCenter.exe', 'bin\YimeCoreSettingsTool.exe',
        'bin\YimeCoreLexiconCenter.exe', 'bin\YimeCoreBlocklistManager.exe',
        'bin\YimeCoreSystemLexiconAudit.exe', 'bin\YimeCoreLearningManager.exe',
        'bin\YimeCorePromotionScan.exe',
		'bin\YimeCoreProfessionalLexicon.exe',
		'bin\YimeCoreLayoutDesigner.exe', 'bin\YimeCoreDiagnostics.exe',
        'bin\YimeCoreExplain.exe', 'bin\YimeCoreSentenceRegression.exe',
        'profile-icon.ico',
        'indexes\full.yidx', 'indexes\variable.yidx', 'indexes\shorthand.yidx',
        'data\yime_yinyuan_layout.json', 'data\yime_syllable_decomposition.tsv',
        'data\yime_full.dict.yaml', 'data\trainer\foundation.json',
        'data\trainer\curriculum.json', 'data\trainer\yinyuan_catalog.json',
		'data\trainer\yinyuan_groups.json', 'data\dynamic_sentence_cases.json',
        'professional-lexicons\catalog.json',
		'help\README.html', 'help\trial-feedback.html', 'help\diagnostics.html'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolved $required) -PathType Leaf)) {
            throw "incomplete E6-C trial package: $required"
        }
    }
    return [ordered]@{
        root = $resolved
        manifest = $manifest
        manifest_path = $manifestPath
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
		records = $records
    }
}

function Assert-PrivilegedPackageCopy([string]$root, $trustedPackage) {
	$copy = Assert-Package $root
	if ([string]$copy.manifest_sha256 -ne [string]$trustedPackage.manifest_sha256) {
		throw "staged package manifest changed after initial validation: $root"
	}
	if (@($copy.records).Count -ne @($trustedPackage.records).Count) {
		throw "staged package record count changed after initial validation: $root"
	}
	$trusted = @{}
	foreach ($record in @($trustedPackage.records)) { $trusted[[string]$record.path] = $record }
	foreach ($record in @($copy.records)) {
		$wanted = $trusted[[string]$record.path]
		if (-not $wanted -or [int64]$wanted.bytes -ne [int64]$record.bytes -or
			[string]$wanted.sha256 -ne [string]$record.sha256) {
			throw "staged package differs from initially validated bytes: $($record.path)"
		}
	}
	return $copy
}

function Test-InstallMarker([string]$root) {
    $metadataPath = Join-Path $root 'install-metadata.json'
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return [string]$metadata.product_key -eq $productKeyName
        } catch { return $false }
    }
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return ([string]$manifest.tool_version -like 'yimecore-e6*') -or
                ([string]$manifest.tool_version -eq 'yimecore-experimental-package-v2' -and
                 [string]$manifest.package_id -like 'yimecore-e6*')
        } catch { return $false }
    }
    return $false
}

function Add-DeferredDeleteType {
    if (-not ('YimeCoreTrial.NativeFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YimeCoreTrial {
    public static class NativeFile {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool MoveFileEx(string existingName, string newName, int flags);
    }
}
'@
    }
}

function Remove-ProductTree([string]$root) {
    $resolved = Assert-ProductChild $root 'cleanup root'
    if ($NativeLocalProduct -and (Test-FrozenInstallRoot $resolved @(Get-FrozenRegistrationReferences))) {
        throw "refusing deletion or reboot-deletion of a frozen registration dependency: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) { return $false }
    if (-not (Test-InstallMarker $resolved)) {
        throw "refusing cleanup without a YimeCore trial marker: $resolved"
    }
    try {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        return $false
    } catch {
        Add-DeferredDeleteType
        $remaining = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending)
        foreach ($item in $remaining) {
            $null = [YimeCoreTrial.NativeFile]::MoveFileEx($item.FullName, $null, 4)
        }
        $null = [YimeCoreTrial.NativeFile]::MoveFileEx($resolved, $null, 4)
        return $true
    }
}

function Get-RegisteredInstallRoots {
    $roots = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $uninstallKey) {
        $location = [string](Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue).InstallLocation
        if (-not [string]::IsNullOrWhiteSpace($location)) { $roots.Add($location) }
    }
	if (Test-Path -LiteralPath $legacyMachineUninstallKey) {
		$location = [string](Get-ItemProperty -LiteralPath $legacyMachineUninstallKey -ErrorAction SilentlyContinue).InstallLocation
		if (-not [string]::IsNullOrWhiteSpace($location)) { $roots.Add($location) }
	}
    $configPath = Join-Path $stateRootPath 'runtime-config.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $configured = [string](Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json).install_root
            if (-not [string]::IsNullOrWhiteSpace($configured)) { $roots.Add($configured) }
        } catch {}
    }
    foreach ($registryPath in @(
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$clsid\InprocServer32",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid\InprocServer32",
        "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$clsid\InprocServer32",
        "Registry::HKEY_CURRENT_USER\Software\Classes\WOW6432Node\CLSID\$clsid\InprocServer32"
    )) {
        if (Test-Path -LiteralPath $registryPath) {
            $dll = [string](Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue).'(default)'
            if (-not [string]::IsNullOrWhiteSpace($dll)) {
                $candidate = Split-Path -Parent (Split-Path -Parent $dll)
                $roots.Add($candidate)
            }
        }
    }
    if (Test-Path -LiteralPath $productRoot -PathType Container) {
        foreach ($directory in Get-ChildItem -LiteralPath $productRoot -Directory -Force) {
            if (Test-InstallMarker $directory.FullName) { $roots.Add($directory.FullName) }
        }
    }
    return @($roots | ForEach-Object {
        try { Assert-ProductChild $_ 'registered install root' } catch { $null }
    } | Where-Object { $_ } | Select-Object -Unique)
}

function Get-FrozenRegistrationReferences {
    # StdRegProv is intentionally outside this process's registry view. Never
    # fall back to HKCU if the provider cannot read the initiating user's hive.
    $references = @()
    foreach ($entry in @(
        [ordered]@{ hive = [uint32]2147483650; path = "SOFTWARE\Classes\WOW6432Node\CLSID\$legacyClsid\InprocServer32" },
        [ordered]@{ hive = [uint32]2147483651; path = "$TargetUserSid\Software\Classes\WOW6432Node\CLSID\$legacyClsid\InprocServer32" }
    )) {
        $read = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue `
            -Arguments @{ hDefKey=$entry.hive; sSubKeyName=$entry.path; sValueName='' }
        if ($read.ReturnValue -eq 2) { continue }
        if ($null -eq $read.ReturnValue -or $read.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace([string]$read.sValue)) {
            throw "Cannot resolve frozen registration; no cleanup permitted: $($entry.path)"
        }
        $dll = [string]$read.sValue
        if (-not [IO.Path]::IsPathRooted($dll) -or $dll.Contains('%') -or $dll.Contains('"')) {
            throw "Ambiguous frozen DLL path; no cleanup permitted: $($entry.path)"
        }
        $dll = [IO.Path]::GetFullPath($dll)
        $references += [ordered]@{ hive=$entry.hive; registry_path=$entry.path; dll_path=$dll
            install_root=(Split-Path -Parent (Split-Path -Parent $dll)); architecture='x86'; tested=$false }
    }
    return $references
}

function Test-FrozenInstallRoot([string]$Root, $References) {
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + '\'
    foreach ($reference in $References) {
        if (([IO.Path]::GetFullPath([string]$reference.dll_path)).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-PreviousRuntimeIdentity($Config, $Status, $Runtime, $Broker, $Boot, [string]$UserSid, $Owners) {
    try {
        if (-not $Config -or -not $Status -or -not $Runtime -or -not $Broker -or $Status.state -ne 'running') { return $false }
        $root = [IO.Path]::GetFullPath([string]$Config.install_root)
        $runtimePath = Join-Path $root 'bin\YimeCoreTrialRuntime.exe'
        $brokerPath = Join-Path $root 'bin\YimeBroker.exe'
        $runtimeTime = ([DateTimeOffset]$Runtime.CreationDate).UtcDateTime
        $brokerTime = ([DateTimeOffset]$Broker.CreationDate).UtcDateTime
        $bootTime = ([DateTimeOffset]$Boot).UtcDateTime
        $updated = if ($Status.updated_at -is [DateTime]) { $Status.updated_at.ToUniversalTime() } else {
            [DateTimeOffset]::Parse([string]$Status.updated_at).UtcDateTime
        }
        return [bool]($Runtime.ProcessId -eq $Status.runtime_pid -and $Broker.ProcessId -eq $Status.broker_pid -and
            $Broker.ParentProcessId -eq $Runtime.ProcessId -and
            [string]$Runtime.ExecutablePath -ieq $runtimePath -and [string]$Broker.ExecutablePath -ieq $brokerPath -and
            [string]$Config.runtime_path -ieq $runtimePath -and [string]$Config.broker_path -ieq $brokerPath -and
            [string]$Status.install_root -ieq $root -and [string]$Status.broker_path -ieq $brokerPath -and
            [string]$Status.state_root -ieq [string]$Config.state_root -and
            $runtimeTime -ge $bootTime -and $brokerTime -ge $runtimeTime -and $updated -ge $runtimeTime -and
            $updated -le [DateTime]::UtcNow.AddSeconds(5) -and
            @($Owners).Count -eq 2 -and @($Owners | Where-Object { $_.sid -ne $UserSid -or $_.result -ne 0 }).Count -eq 0)
    } catch { return $false }
}

function Get-PreviousRuntimeWasRunning([string]$ConfigText) {
    if ([string]::IsNullOrWhiteSpace($ConfigText)) {
        $active = @(Get-CimInstance Win32_Process -Filter "Name='YimeCoreTrialRuntime.exe' OR Name='YimeBroker.exe'" |
            Where-Object { $_.ExecutablePath -and ([string]$_.ExecutablePath).StartsWith($productRoot+'\',[StringComparison]::OrdinalIgnoreCase) })
        if ($active.Count) { throw 'Installed runtime exists without a configuration; restore identity before maintenance.' }
        return $false
    }
    $config = $ConfigText | ConvertFrom-Json
    if ([IO.Path]::GetFullPath([string]$config.state_root) -ine $stateRootPath) { throw 'Previous runtime has a different state root.' }
    $expectedRuntime = Join-Path ([string]$config.install_root) 'bin\YimeCoreTrialRuntime.exe'
    $expectedBroker = Join-Path ([string]$config.install_root) 'bin\YimeBroker.exe'
    $candidates = @(Get-CimInstance Win32_Process -Filter "Name='YimeCoreTrialRuntime.exe' OR Name='YimeBroker.exe'")
    $matching = @($candidates | Where-Object { $_.ExecutablePath -ieq $expectedRuntime -or $_.ExecutablePath -ieq $expectedBroker })
    # In a native elevated maintenance context these images must be visible.
    if (@($candidates | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) }).Count) {
        throw 'Cannot inspect a runtime/Broker process; previous running state is unverified.'
    }
    if ($matching.Count -eq 0) { return $false } # Stale persisted "running" is not a live process.
    $status = Get-Content -LiteralPath (Join-Path $stateRootPath 'runtime-status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runtime = @($matching | Where-Object { $_.ProcessId -eq $status.runtime_pid })
    $broker = @($matching | Where-Object { $_.ProcessId -eq $status.broker_pid })
    if ($runtime.Count -ne 1 -or $broker.Count -ne 1 -or $matching.Count -ne 2) { throw 'Previous runtime PID/status is ambiguous; no mutation allowed.' }
    $owners = @($runtime[0],$broker[0] | ForEach-Object {
        $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid
        [ordered]@{ sid=$owner.Sid; result=$owner.ReturnValue }
    })
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    if (-not (Test-PreviousRuntimeIdentity $config $status $runtime[0] $broker[0] $boot $TargetUserSid $owners)) {
        throw 'Previous runtime/Broker image, owner, parent or boot identity is unverified; no mutation allowed.'
    }
    return $true
}

function Get-NativeRegisteredInstallRoot {
    foreach ($path in @(
        "Registry::HKEY_USERS\$TargetUserSid\Software\Classes\CLSID\$clsid\InprocServer32",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
    )) {
        $snapshot = Get-RegistryKeySnapshot $path
        if (-not $snapshot.exists) { continue }
        $value = @($snapshot.values | Where-Object { $_.name -eq '' })
        if ($value.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$value[0].value)) {
            throw 'Native COM registration has no unambiguous DLL path.'
        }
        return Assert-ProductChild (Split-Path -Parent (Split-Path -Parent ([string]$value[0].value))) 'previous native install root'
    }
    return ''
}

function Stop-TrialRuntime([string[]]$installRoots) {
    $configPath = Join-Path $stateRootPath 'runtime-config.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $runtime = [string]$config.runtime_path
            if (Test-Path -LiteralPath $runtime -PathType Leaf) {
                $arguments = '-stop -install-root {0} -broker {1} -state-root {2}' -f
                    (Quote-Argument ([string]$config.install_root)),
                    (Quote-Argument ([string]$config.broker_path)), (Quote-Argument $stateRootPath)
                $process = Start-Process -FilePath $runtime -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
                if ($process.ExitCode -eq 0) { return }
            }
        } catch {}
    }
    $allowedExecutables = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $installRoots) {
        $null = $allowedExecutables.Add((Join-Path $root 'bin\YimeCoreTrialRuntime.exe'))
        $null = $allowedExecutables.Add((Join-Path $root 'bin\YimeBroker.exe'))
    }
    $null = $allowedExecutables.Add((Join-Path $stateRootPath 'runtime\bin\YimeCoreTrialRuntime.exe'))
    $null = $allowedExecutables.Add((Join-Path $stateRootPath 'runtime\bin\YimeBroker.exe'))
    foreach ($process in @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $allowedExecutables.Contains([IO.Path]::GetFullPath($_.ExecutablePath))
    })) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Remove-InputMethodTip {
    $languageList = Get-WinUserLanguageList
    $changed = $false
    foreach ($language in @($languageList)) {
        while (@($language.InputMethodTips) -contains $tip) {
            if (-not $language.InputMethodTips.Remove($tip)) {
                throw "failed to remove the YimeCore trial TIP from $($language.LanguageTag)"
            }
            $changed = $true
        }
    }
    if ($changed) {
        Set-WinUserLanguageList -LanguageList $languageList -Force
        $remaining = @(Get-WinUserLanguageList | Where-Object {
            @($_.InputMethodTips) -contains $tip
        })
        if ($remaining.Count -ne 0) {
            throw ('YimeCore trial TIP remained in language entries: ' +
                (($remaining | ForEach-Object LanguageTag) -join ', '))
        }
    }
    # Set-WinUserLanguageList can leave a disabled Enable=0 shell for this
    # profile. A completed uninstall owns this exact per-user product subtree;
    # remove the shell so a later first install cannot mistake it for an
    # upgrade snapshot.
    Remove-TargetUserTipState
}

function Remove-TrialRegistration([string[]]$installRoots) {
	$frozenTip = Get-FrozenTipSnapshot
    $frozenUserTip = Get-FrozenUserTipSnapshot
    try {
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name = [string]$architecture.name
		$tool = Find-CurrentRegistrationTool $installRoots $name
		if ([string]::IsNullOrWhiteSpace($tool)) {
			throw "$name current-identity TSF unregister tool is unavailable; installation files were preserved"
		}
		$output = (& $tool unregister 2>&1) -join "`n"
		if ($LASTEXITCODE -ne 0) {
			throw "$name TSF unregister failed with exit ${LASTEXITCODE}: $output"
		}
		Wait-RegistrationState $tool $false $false 0
		$verification = (& $tool verify-absent 2>&1) -join "`n"
		if ($LASTEXITCODE -ne 0) {
			throw "$name TSF absence verification failed with exit ${LASTEXITCODE}: $verification"
		}
	}
    foreach ($registryPath in @(
        "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$clsid",
        "Registry::HKEY_CURRENT_USER\Software\Classes\WOW6432Node\CLSID\$clsid"
    )) {
        if ($NativeX64Rehearsal -and $registryPath -like '*WOW6432Node*') { continue }
        if ($NativeX64Only -and $registryPath -like '*WOW6432Node*') { continue }
        Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    } finally {
        try { Restore-FrozenTipSnapshot $frozenTip }
        finally { Restore-FrozenUserTipSnapshot $frozenUserTip }
    }
}

function Remove-StateRuntime([switch]$Purge) {
    if ($Purge) {
        if ($stateRootPath -ne [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))) {
            throw "refusing to purge a non-default state root: $stateRootPath"
        }
        if (Test-Path -LiteralPath $stateRootPath) {
            Remove-Item -LiteralPath $stateRootPath -Recurse -Force
        }
        return
    }
    foreach ($relative in @('runtime', 'runtime-config.json', 'runtime-status.json')) {
        $path = Join-Path $stateRootPath $relative
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-UninstallCore([switch]$ForReinstall, [string[]]$PreserveInstallRoots = @()) {
    $roots = @(Get-RegisteredInstallRoots)
    $preserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $PreserveInstallRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $null = $preserved.Add([IO.Path]::GetFullPath($root))
        }
    }
    $frozenReferences = @(if ($NativeLocalProduct) { Get-FrozenRegistrationReferences })
    foreach ($root in $roots) {
        if (Test-FrozenInstallRoot $root $frozenReferences) { $null = $preserved.Add([IO.Path]::GetFullPath($root)) }
    }
    Stop-TrialRuntime $roots
    Remove-ItemProperty -LiteralPath $runKey -Name $productKeyName -ErrorAction SilentlyContinue
    # Set-WinUserLanguageList can normalize or delete unrelated legacy user
    # TIP state. Snapshot the frozen subtree before that call, not inside the
    # later registration boundary after the damage has already happened.
    $frozenUserTipBeforeLanguageList = Get-FrozenUserTipSnapshot
    try {
        Remove-InputMethodTip
	    Remove-TrialRegistration @($PreserveInstallRoots + $roots)
    } finally {
        Restore-FrozenUserTipSnapshot $frozenUserTipBeforeLanguageList
    }
    Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $legacyMachineUninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    $deferred = $false
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            if ($preserved.Contains([IO.Path]::GetFullPath($root))) { continue }
            if (-not (Test-InstallMarker $root)) {
                [IO.File]::WriteAllText((Join-Path $root 'install-metadata.json'),
                    (([ordered]@{ schema_version = 'yimecore-trial-cleanup-recovery-v1';
                        product_key = $productKeyName; recovered_from_registration = $true } |
                        ConvertTo-Json) + "`n"), $utf8NoBom)
            }
            if (Remove-ProductTree $root) { $deferred = $true }
        }
    }
    Remove-StateRuntime -Purge:($PurgeUserData -and -not $ForReinstall)
    return [ordered]@{
        action = if ($ForReinstall) { 'forced_preinstall_cleanup' } else { 'uninstall' }
        removed_install_roots = @($roots | Where-Object {
            -not $preserved.Contains([IO.Path]::GetFullPath($_))
        })
        preserved_install_roots = @($roots | Where-Object {
            $preserved.Contains([IO.Path]::GetFullPath($_))
        })
        deferred_delete_until_reboot = $deferred
        user_model_preserved = [bool](-not $PurgeUserData -or $ForReinstall)
        production_rime_pime_changed = $false
        frozen_registration_references = $frozenReferences
    }
}

function Add-InputMethodTip {
    $languageList = Get-WinUserLanguageList
    $chinese = $languageList | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
    if (-not $chinese) { throw 'current user has no zh-Hans-CN language entry' }
    if (@($chinese.InputMethodTips) -notcontains $tip) {
        $null = $chinese.InputMethodTips.Add($tip)
        Set-WinUserLanguageList -LanguageList $languageList -Force
    }
}

function Convert-RegistrationStatus([string]$text) {
    $values = @{}
    foreach ($line in ($text -split "`r?`n")) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return $values
}

function Wait-RegistrationState([string]$tool, [bool]$comRegistered,
                                [bool]$profileRegistered, [int]$categoryCount) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $statusText = (& $tool status 2>&1) -join "`n"
        $status = Convert-RegistrationStatus $statusText
        if ($LASTEXITCODE -eq 0 -and
            $status.com_registered_current_view -eq $(if ($comRegistered) { 'true' } else { 'false' }) -and
            $status.profile_registered -eq $(if ($profileRegistered) { 'true' } else { 'false' }) -and
            [int]$status.categories_registered_count -eq $categoryCount) {
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "TSF registration state did not converge: $statusText"
}

function Resolve-RegistrationAction([string]$tool,[string]$requestedAction) {
    if (-not $NativeLocalProduct -or $requestedAction -ne 'register') {
        Wait-RegistrationState $tool $false $false 0
        return $requestedAction
    }
    # A frozen architecture can keep the shared TSF profile/categories alive
    # after the active x64 COM view is removed. In that exact state, creating a
    # new profile returns ERROR_ALREADY_EXISTS; only repoint the active COM view.
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do {
        $statusText=(& $tool status 2>&1)-join "`n"
        $status=Convert-RegistrationStatus $statusText
        if($LASTEXITCODE -eq 0 -and $status.com_registered_current_view -eq 'false') {
            if($status.profile_registered -eq 'false' -and [int]$status.categories_registered_count -eq 0){return 'register'}
            if($status.profile_registered -eq 'true' -and [int]$status.categories_registered_count -eq 5){return 'repoint'}
        }
        Start-Sleep -Milliseconds 100
    } while([DateTime]::UtcNow -lt $deadline)
    throw "Native x64 registration is neither clean nor an exact frozen-profile handoff: $statusText"
}

function Invoke-Registration([string]$tool, [string]$command, [string]$dll, [string]$label) {
    $frozenTip = Get-FrozenTipSnapshot
    $frozenUserTip = Get-FrozenUserTipSnapshot
    try {
        $output = (& $tool $command $dll 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "$label failed with exit ${LASTEXITCODE}: $output" }
    } finally {
        try { Restore-FrozenTipSnapshot $frozenTip }
        finally { Restore-FrozenUserTipSnapshot $frozenUserTip }
    }
}

function Write-RuntimeConfiguration([string]$root) {
    New-Item -ItemType Directory -Path $stateRootPath -Force | Out-Null
    $runtime = Join-Path $root 'bin\YimeCoreTrialRuntime.exe'
    $broker = Join-Path $root 'bin\YimeBroker.exe'
    $config = [ordered]@{
        schema_version = 'yimecore-trial-runtime-config-v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        install_root = $root
        runtime_path = $runtime
        broker_path = $broker
        state_root = $stateRootPath
        pipe_name = '\\.\pipe\YimeBroker.YimeCoreTrial.v1'
        experimental_clsid = $clsid
        experimental_input_method_tip = $tip
    }
    [IO.File]::WriteAllText((Join-Path $stateRootPath 'runtime-config.json'),
        (($config | ConvertTo-Json -Depth 4) + "`n"), $utf8NoBom)
    return $config
}

function Start-TrialRuntime($config) {
    $arguments = '-install-root {0} -broker {1} -state-root {2} -no-toolbar' -f
        (Quote-Argument ([string]$config.install_root)), (Quote-Argument ([string]$config.broker_path)),
        (Quote-Argument ([string]$config.state_root))
    if ($NativeLocalProduct) {
        Initialize-StandardUserLauncher
        $process = [YimeCore.LocalMaintenance.StandardUserLauncher]::Start(
            [string]$config.runtime_path, $arguments, [string]$config.install_root, $TargetUserSid)
    } else {
        $process = Start-Process -FilePath ([string]$config.runtime_path) -ArgumentList $arguments `
            -WindowStyle Hidden -PassThru
    }
    $statusPath = Join-Path $stateRootPath 'runtime-status.json'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    try {
    do {
        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
            $status = $null
            try { $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            if ($null -ne $status) {
                if ($status.state -eq 'running' -and [int]$status.runtime_pid -eq $process.Id) {
                    if ($NativeLocalProduct) {
                        $verified = Get-PreviousRuntimeWasRunning ($config | ConvertTo-Json -Depth 6)
                        foreach ($childPid in @([int]$status.runtime_pid,[int]$status.broker_pid)) {
                            $token = [YimeCore.LocalMaintenance.StandardUserLauncher]::InspectProcess($childPid)
                            if (-not [YimeCore.LocalMaintenance.StandardUserLauncher]::IsExpectedStandardToken(
                                $token, $TargetUserSid, [Diagnostics.Process]::GetCurrentProcess().SessionId)) {
                                throw 'Runtime/Broker did not start under the initiating standard-user token.'
                            }
                        }
                        if (-not $verified) { throw 'Runtime live identity missing after standard-user launch.' }
                    }
                    return $status
                }
            }
        }
    } while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited)
    throw 'trial runtime did not become ready within 15 seconds'
    } catch {
        # The runtime's job owns its children. Do not leave an unaccepted runtime
        # running, or select other processes by executable name for cleanup.
        if (-not $process.HasExited) { $process.Kill() }
        throw
    }
}

function Initialize-StandardUserLauncher {
    . (Join-Path $PSScriptRoot 'development-scope.ps1')
    Assert-YimeCoreMaintenanceInitiator
    if (-not ('YimeCore.LocalMaintenance.StandardUserLauncher' -as [type])) {
        $source = Join-Path $PSScriptRoot 'local-runtime-launcher.cs'
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Packaged standard-user launch helper is missing.' }
        Add-Type -Path $source
    }
}

function Assert-NativeX64LaunchSupport($Package) {
    if (-not (Test-NativeX64LauncherContent $Package)) {
        throw 'Native x64 maintenance requires the manifest-pinned standard-user launcher from this maintenance version.'
    }
    Initialize-StandardUserLauncher
    $null = [YimeCore.LocalMaintenance.StandardUserLauncher]::ValidateLaunchToken($TargetUserSid)
}

function Test-NativeX64LauncherContent($Package) {
    $records = @($Package.records | Where-Object { $_.path -eq 'maintenance/local-runtime-launcher.cs' })
    $source = Join-Path $PSScriptRoot 'local-runtime-launcher.cs'
    if ($records.Count -ne 1 -or -not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine [string]$records[0].sha256) {
        return $false
    }
    return $true
}

function Restore-PreviousInstallation([string]$root, [string]$configText,
                                     $runSnapshot, $uninstallSnapshot, $legacyUninstallSnapshot,
                                     [bool]$runtimeWasRunning, $userTipSnapshot) {
    if (-not [string]::IsNullOrWhiteSpace($root)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Previous package is missing: $root" }
	$restoreArchitectures = @(Get-RegistrationArchitecturesForRoot $root)
    if ($NativeLocalProduct -and $restoreArchitectures.Count -eq 0) {
        throw "Previous package has no validated current-identity registration tools: $root"
    }
	foreach ($architecture in $restoreArchitectures) {
		$name = [string]$architecture.name
		$tool = Join-Path $root "$name\YimeTextServiceRegistration.exe"
		$action=Resolve-RegistrationAction $tool ([string]$architecture.action)
		Invoke-Registration $tool $action `
			(Join-Path $root "$name\YimeTextServiceExperiment.dll") "rollback $name TSF registration"
		Wait-RegistrationState $tool $true $true 5
	}
    Add-InputMethodTip
    }
    # Profile re-registration alone does not restore the per-user Enable flag.
    Restore-RegistryKeySnapshot $userTipKey $userTipSnapshot
    if (-not [string]::IsNullOrWhiteSpace($configText)) {
        New-Item -ItemType Directory -Path $stateRootPath -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $stateRootPath 'runtime-config.json'),
            $configText, $utf8NoBom)
    } else {
        Remove-Item -LiteralPath (Join-Path $stateRootPath 'runtime-config.json') -Force -ErrorAction SilentlyContinue
    }
    Restore-RegistryValueSnapshot $runKey $productKeyName $runSnapshot
    Restore-RegistryKeySnapshot $uninstallKey $uninstallSnapshot
	Restore-RegistryKeySnapshot $legacyMachineUninstallKey $legacyUninstallSnapshot
    if ($runtimeWasRunning -and -not [string]::IsNullOrWhiteSpace($configText)) {
        $previousConfig = $configText | ConvertFrom-Json
        Start-TrialRuntime $previousConfig | Out-Null
    }
}

if ($Action -ne 'Plan' -and -not (Test-Administrator)) {
    if ($NoElevation) { throw "$Action requires an elevated administrator token" }
    Restart-Elevated
}
if ($Action -ne 'Plan') {
    $effectiveUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if (-not $effectiveUserSid.Equals($TargetUserSid, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Action must be elevated with the same Windows account that started the operation"
    }
    Remove-Item -LiteralPath $maintenanceErrorPath -Force -ErrorAction SilentlyContinue
}

if ($Action -eq 'Plan') {
    if ([string]::IsNullOrWhiteSpace($PackageRoot)) { throw 'Plan requires -PackageRoot' }
    $package = Assert-Package $PackageRoot
    $packageId = 'yimecore-e6c-' + ([string]$package.manifest.git_commit).Substring(0, 12) + '-' +
        ([string]$package.manifest_sha256).Substring(0, 8)
    $target = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { Join-Path $productRoot $packageId } else { $InstallRoot }
    $target = Assert-ProductChild $target 'install root'
    [ordered]@{
        action = 'plan'
        product_name = $productName
        package_root = $package.root
        install_root = $target
        state_root = $stateRootPath
        installed_apps_registry_key = $uninstallKey
        autostart_registry_key = $runKey
        target_user_sid = $TargetUserSid
        forced_preinstall_cleanup = $true
        upgrade_rollback_supported = $true
        package_staged_before_preinstall_cleanup = $true
        x64_x86_tsf_registration = [bool]$NativeDesktop
		arm64_tsf_artifacts_required = [bool](-not ($package.manifest.PSObject.Properties['package_contract'] -and
            $package.manifest.package_contract -eq 'yimecore-local-product-package-v1'))
		active_registration_architectures = @((Get-RegistrationArchitectures) | ForEach-Object { $_.name })
        frozen_registration_references = @(if ($NativeLocalProduct) { Get-FrozenRegistrationReferences })
        standard_user_runtime_required = [bool]$NativeLocalProduct
        standard_user_launcher_package_ready = if ($NativeLocalProduct) { Test-NativeX64LauncherContent $package } else { $null }
		native_registration_architecture = $nativeArchitecture
        taskbar_language_bar_categories = $true
        windows_native_language_bar_only = $true
        user_model_preserved_on_reinstall = $true
        loaded_dll_cleanup_policy = 'defer exact marked leftovers until reboot'
        production_rime_pime_changed = $false
        bare_digit_selection_rules_changed = $false
    } | ConvertTo-Json -Depth 5
    exit 0
}

if ($Action -eq 'Uninstall') {
    if ($NativeX64Rehearsal) { throw 'NativeX64Rehearsal is only valid for the isolated failed-install exercise.' }
    $result = Invoke-UninstallCore
    if (-not $Quiet) { $result | ConvertTo-Json -Depth 5 }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) { throw 'Install requires -PackageRoot' }
$package = Assert-Package $PackageRoot
if ($NativeLocalProduct) { Assert-NativeX64LaunchSupport $package }
if ($NativeX64Rehearsal -and ($nativeArchitecture -ne 'AMD64' -or -not [Environment]::Is64BitProcess -or
    -not $package.manifest.rehearsal_only -or $NoLaunch -or $NoAutoStart -or $PurgeUserData)) {
    throw 'NativeX64Rehearsal requires the isolated failure-only package, x64 host and full rollback exercise.'
}
$packageId = 'yimecore-e6c-' + ([string]$package.manifest.git_commit).Substring(0, 12) + '-' +
    ([string]$package.manifest_sha256).Substring(0, 8)
$requestedInstallRoot = -not [string]::IsNullOrWhiteSpace($InstallRoot)
$targetRoot = if ($requestedInstallRoot) { Assert-ProductChild $InstallRoot 'install root' } else {
    Assert-ProductChild (Join-Path $productRoot $packageId) 'install root'
}

$previousRoots = @(Get-RegisteredInstallRoots)
$previousConfigPath = Join-Path $stateRootPath 'runtime-config.json'
$previousConfigText = if (Test-Path -LiteralPath $previousConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $previousConfigPath -Raw -Encoding UTF8
} else { '' }
$previousRoot = if (-not [string]::IsNullOrWhiteSpace($previousConfigText)) {
    try { [string](($previousConfigText | ConvertFrom-Json).install_root) } catch { '' }
} else { '' }
if ([string]::IsNullOrWhiteSpace($previousRoot) -or
    $previousRoots -notcontains $previousRoot) {
    $previousRoot = if ($NativeLocalProduct) { Get-NativeRegisteredInstallRoot } elseif ($previousRoots.Count -gt 0) { [string]$previousRoots[0] } else { '' }
}
$previousRunSnapshot = Get-RegistryValueSnapshot $runKey $productKeyName
$previousUninstallSnapshot = Get-RegistryKeySnapshot $uninstallKey
$previousLegacyUninstallSnapshot = Get-RegistryKeySnapshot $legacyMachineUninstallKey
$previousUserTipSnapshot = Get-RegistryKeySnapshot $userTipKey
$migrationLegacyUserTipSnapshot = Get-FrozenUserTipSnapshot
$previousStatusPath = Join-Path $stateRootPath 'runtime-status.json'
$previousRuntimeWasRunning = Get-PreviousRuntimeWasRunning $previousConfigText

if (Test-Path -LiteralPath $targetRoot) {
    if ($requestedInstallRoot) { throw "requested install root is still occupied: $targetRoot" }
    $targetRoot = Assert-ProductChild ($targetRoot + '-' + (Get-Date -Format 'yyyyMMddHHmmss')) 'fallback install root'
}
$stagingRoot = Assert-ProductChild ($targetRoot + ".staging-$PID") 'staging root'
if (Test-Path -LiteralPath $stagingRoot) { throw "staging root already exists: $stagingRoot" }

$preinstall = $null
$preinstallStarted = $false
$registrationStarted = $false
try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $stagingRoot 'install-metadata.json'),
        (([ordered]@{ schema_version = 'yimecore-trial-install-v1'; product_key = $productKeyName;
            install_root = $targetRoot; staging = $true } | ConvertTo-Json) + "`n"), $utf8NoBom)
    foreach ($item in Get-ChildItem -LiteralPath $package.root -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $stagingRoot -Recurse -Force
    }
    $maintenanceRoot = Join-Path $stagingRoot 'maintenance'
    New-Item -ItemType Directory -Path $maintenanceRoot -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $maintenanceRoot 'Manage-YimeCoreTrial.ps1') -Force
    if ($package.manifest.PSObject.Properties['package_contract'] -and
        $package.manifest.package_contract -eq 'yimecore-local-product-package-v1') {
        # Audit the staging path as the actual current path, with full identity.
        # The final-path metadata below is only used after the atomic directory move.
        [IO.File]::WriteAllText((Join-Path $stagingRoot 'install-metadata.json'),
            (([ordered]@{schema_version='yimecore-trial-install-v1';product_key=$productKeyName;
                install_root=$stagingRoot;staging=$true;package_manifest_sha256=$package.manifest_sha256;
                git_commit=[string]$package.manifest.git_commit}|ConvertTo-Json)+"`n"),$utf8NoBom)
    }
	$null = Assert-PrivilegedPackageCopy $stagingRoot $package
    $metadata = [ordered]@{
        schema_version = 'yimecore-trial-install-v1'
        product_key = $productKeyName
        product_name = $productName
        installed_at = (Get-Date).ToUniversalTime().ToString('o')
        install_root = $targetRoot
        state_root = $stateRootPath
        package_manifest_sha256 = $package.manifest_sha256
        git_commit = [string]$package.manifest.git_commit
    }
    [IO.File]::WriteAllText((Join-Path $stagingRoot 'install-metadata.json'),
        (($metadata | ConvertTo-Json -Depth 4) + "`n"), $utf8NoBom)
    $preinstallStarted = $true
    $preinstall = Invoke-UninstallCore -ForReinstall `
        -PreserveInstallRoots @($previousRoots + $stagingRoot)
    Move-Item -LiteralPath $stagingRoot -Destination $targetRoot
	$null = Assert-PrivilegedPackageCopy $targetRoot $package

	$registrationActions=@{}
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name=[string]$architecture.name
		$tool = Join-Path $targetRoot ($name + '\YimeTextServiceRegistration.exe')
		$registrationActions[$name]=Resolve-RegistrationAction $tool ([string]$architecture.action)
	}
	$registrationStarted = $true
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name = [string]$architecture.name
		$tool = Join-Path $targetRoot "$name\YimeTextServiceRegistration.exe"
		Invoke-Registration $tool ([string]$registrationActions[$name]) `
			(Join-Path $targetRoot "$name\YimeTextServiceExperiment.dll") "$name TSF registration"
		Wait-RegistrationState $tool $true $true 5
	}
    Add-InputMethodTip

    if (Test-RestorablePreviousUserTipSnapshot $previousRoot $previousUserTipSnapshot) {
        Restore-RegistryKeySnapshot $userTipKey $previousUserTipSnapshot
    } else { Enable-TargetUserTip $userTipKey $profile }
    $runtimeConfig = Write-RuntimeConfiguration $targetRoot
    $runValue = '{0} -no-toolbar' -f (Quote-Argument ([string]$runtimeConfig.runtime_path))
    Initialize-RegistryKeyPreservingValues $runKey
    if ($NoAutoStart) {
        Remove-ItemProperty -LiteralPath $runKey -Name $productKeyName -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -LiteralPath $runKey -Name $productKeyName -Value $runValue `
            -PropertyType String -Force | Out-Null
    }

    $installedScript = Join-Path $targetRoot 'maintenance\Manage-YimeCoreTrial.ps1'
    $uninstallCommand = '{0} -NoProfile -ExecutionPolicy Bypass -File {1} -Action Uninstall -StateRoot {2} -TargetUserSid {3}' -f
        (Quote-Argument $windowsPowerShell), (Quote-Argument $installedScript),
        (Quote-Argument $stateRootPath), (Quote-Argument $TargetUserSid)
    if ($NativeX64Only) { $uninstallCommand += ' -NativeX64Only' }
    if ($NativeDesktop) { $uninstallCommand += ' -NativeDesktop' }
    New-Item -Path $uninstallKey -Force | Out-Null
    $estimatedSize = [int]([math]::Ceiling((Get-ChildItem -LiteralPath $targetRoot -Recurse -File |
        Measure-Object Length -Sum).Sum / 1KB))
    $properties = [ordered]@{
        DisplayName = $productName
        DisplayVersion = if ($package.manifest.PSObject.Properties['product_version']) { [string]$package.manifest.product_version } else { ([string]$package.manifest.git_commit).Substring(0, 12) }
        Publisher = 'Yime'
        InstallLocation = $targetRoot
        UninstallString = $uninstallCommand
        QuietUninstallString = $uninstallCommand + ' -Quiet'
        NoModify = 1
        NoRepair = 1
        EstimatedSize = $estimatedSize
    }
    foreach ($entry in $properties.GetEnumerator()) {
        $type = if ($entry.Value -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -LiteralPath $uninstallKey -Name $entry.Key -Value $entry.Value `
            -PropertyType $type -Force | Out-Null
    }
	# Migrate pre-fix machine-wide visibility to the target user's Installed Apps
	# hive. Maintenance still requires the same initiating SID.
	Remove-Item -LiteralPath $legacyMachineUninstallKey -Recurse -Force -ErrorAction SilentlyContinue

    $runtimeStatus = if ($NoLaunch) { $null } else { Start-TrialRuntime $runtimeConfig }
    # The failure-only exercise must never become a successful install or remove
    # the old roots still referenced by frozen architectures.
    if ($NativeX64Rehearsal) { throw 'Failure-only rehearsal unexpectedly started; restoring previous installation.' }
    foreach ($oldRoot in $previousRoots) {
        if ($NativeLocalProduct -and (Test-FrozenInstallRoot $oldRoot @(Get-FrozenRegistrationReferences))) { continue }
        if (-not ([IO.Path]::GetFullPath($oldRoot)).Equals(
                [IO.Path]::GetFullPath($targetRoot), [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $oldRoot)) {
            Remove-ProductTree $oldRoot | Out-Null
        }
    }
    $result = [ordered]@{
        action = 'install'
        product_name = $productName
        install_root = $targetRoot
        installed_apps_registry_key = $uninstallKey
        forced_preinstall_cleanup = $preinstall
        runtime_started = [bool](-not $NoLaunch -and $runtimeStatus.state -eq 'running')
        user_model_preserved = $true
        production_rime_pime_changed = $false
        bare_digit_selection_rules_changed = $false
    }
    if (-not $Quiet) { $result | ConvertTo-Json -Depth 6 }
} catch {
    $failure = $_
    $rollbackFailure = $null
    try {
        if ($preinstallStarted) {
			if ($registrationStarted) {
				Invoke-UninstallCore -ForReinstall `
					-PreserveInstallRoots @($previousRoots + $targetRoot) | Out-Null
			}
            if (Test-Path -LiteralPath $targetRoot) { Remove-ProductTree $targetRoot | Out-Null }
            Restore-PreviousInstallation $previousRoot $previousConfigText `
				$previousRunSnapshot $previousUninstallSnapshot $previousLegacyUninstallSnapshot `
				$previousRuntimeWasRunning $previousUserTipSnapshot
        }
        if (Test-Path -LiteralPath $stagingRoot) { Remove-ProductTree $stagingRoot | Out-Null }
    } catch {
        $rollbackFailure = $_
    }
    if ($rollbackFailure) {
        throw "${failure}; restoring the previous trial installation also failed: $rollbackFailure"
    }
    throw $failure
} finally {
    # Set-WinUserLanguageList can normalize per-user TIP keys after registration.
    # The legacy subtree belongs to the frozen profile and must remain exact on
    # both successful migration and rollback.
    Restore-FrozenUserTipSnapshot $migrationLegacyUserTipSnapshot
}
