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
    [string]$TargetUserSid
)

$ErrorActionPreference = 'Stop'
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
$clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$profile = '{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$tip = "0804:$clsid$profile"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Windows PowerShell is missing: $windowsPowerShell"
}
$maintenanceErrorPath = Join-Path $stateRootPath 'maintenance-last-error.txt'
trap {
    try {
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
        return [ordered]@{ exists = $false; values = @() }
    }
    $key = Get-Item -LiteralPath $path
    $values = @($key.GetValueNames() | ForEach-Object {
        [ordered]@{
            name = $_
            value = $key.GetValue($_, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            kind = [int]$key.GetValueKind($_)
        }
    })
    return [ordered]@{ exists = $true; values = $values }
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
    New-Item -Path $path -Force | Out-Null
    New-ItemProperty -LiteralPath $path -Name $name -Value $snapshot.value `
        -PropertyType ([Microsoft.Win32.RegistryValueKind]([int]$snapshot.kind)) `
        -Force | Out-Null
}

function Restart-Elevated {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-Argument $PSCommandPath),
        '-Action', $Action, '-StateRoot', (Quote-Argument $stateRootPath),
        '-TargetUserSid', (Quote-Argument $TargetUserSid))
    if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
        $arguments += @('-PackageRoot', (Quote-Argument ([IO.Path]::GetFullPath($PackageRoot))))
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        $arguments += @('-InstallRoot', (Quote-Argument ([IO.Path]::GetFullPath($InstallRoot))))
    }
    foreach ($name in @('Force', 'PurgeUserData', 'NoAutoStart', 'NoLaunch', 'Quiet')) {
        if ((Get-Variable -Name $name -ValueOnly)) { $arguments += "-$name" }
    }
    $process = Start-Process -FilePath $windowsPowerShell -Verb RunAs `
        -ArgumentList ($arguments -join ' ') -PassThru
    $process.WaitForExit()
    exit $process.ExitCode
}

function Assert-ProductChild([string]$path, [string]$description) {
    $resolved = [IO.Path]::GetFullPath($path)
    $prefix = $productRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$description must be a child of ${productRoot}: $resolved"
    }
    return $resolved
}

function Get-RegistrationArchitectures {
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
    if ([string]$manifest.tool_version -notlike 'yimecore-e6c-staged-package-*') {
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
    try {
        $languageList = Get-WinUserLanguageList
        $chinese = $languageList | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
        if ($chinese -and @($chinese.InputMethodTips) -contains $tip) {
            $null = $chinese.InputMethodTips.Remove($tip)
            Set-WinUserLanguageList -LanguageList $languageList -Force
        }
    } catch {
        if (-not $Force) { throw }
    }
}

function Remove-TrialRegistration([string[]]$installRoots) {
	$tools = @{}
    foreach ($root in $installRoots) {
		foreach ($architecture in Get-RegistrationArchitectures) {
			$name = [string]$architecture.name
			$tool = Join-Path $root "$name\YimeTextServiceRegistration.exe"
			if (-not $tools.ContainsKey($name) -and
				(Test-Path -LiteralPath $tool -PathType Leaf)) { $tools[$name] = $tool }
        }
    }
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name = [string]$architecture.name
		$tool = [string]$tools[$name]
		if ([string]::IsNullOrWhiteSpace($tool)) {
			throw "$name TSF unregister tool is unavailable; installation files were preserved"
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
        Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
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
    Stop-TrialRuntime $roots
    Remove-ItemProperty -LiteralPath $runKey -Name $productKeyName -ErrorAction SilentlyContinue
    Remove-InputMethodTip
	Remove-TrialRegistration @($PreserveInstallRoots + $roots)
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

function Invoke-Registration([string]$tool, [string]$command, [string]$dll, [string]$label) {
    $output = (& $tool $command $dll 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "$label failed with exit ${LASTEXITCODE}: $output" }
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
    $process = Start-Process -FilePath ([string]$config.runtime_path) -ArgumentList $arguments `
        -WindowStyle Hidden -PassThru
    $statusPath = Join-Path $stateRootPath 'runtime-status.json'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
            try {
                $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($status.state -eq 'running' -and [int]$status.runtime_pid -eq $process.Id) { return $status }
            } catch {}
        }
    } while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited)
    throw 'trial runtime did not become ready within 15 seconds'
}

function Restore-PreviousInstallation([string]$root, [string]$configText,
                                     $runSnapshot, $uninstallSnapshot, $legacyUninstallSnapshot,
                                     [bool]$runtimeWasRunning) {
    if ([string]::IsNullOrWhiteSpace($root) -or
        -not (Test-Path -LiteralPath $root -PathType Container)) { return }
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name = [string]$architecture.name
		$tool = Join-Path $root "$name\YimeTextServiceRegistration.exe"
		Invoke-Registration $tool ([string]$architecture.action) `
			(Join-Path $root "$name\YimeTextServiceExperiment.dll") "rollback $name TSF registration"
		Wait-RegistrationState $tool $true $true 5
	}
    Add-InputMethodTip
    if (-not [string]::IsNullOrWhiteSpace($configText)) {
        New-Item -ItemType Directory -Path $stateRootPath -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $stateRootPath 'runtime-config.json'),
            $configText, $utf8NoBom)
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
        x64_x86_tsf_registration = $true
		arm64_tsf_artifacts_required = $true
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
    $result = Invoke-UninstallCore
    if (-not $Quiet) { $result | ConvertTo-Json -Depth 5 }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) { throw 'Install requires -PackageRoot' }
$package = Assert-Package $PackageRoot
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
    $previousRoot = if ($previousRoots.Count -gt 0) { [string]$previousRoots[0] } else { '' }
}
$previousRunSnapshot = Get-RegistryValueSnapshot $runKey $productKeyName
$previousUninstallSnapshot = Get-RegistryKeySnapshot $uninstallKey
$previousLegacyUninstallSnapshot = Get-RegistryKeySnapshot $legacyMachineUninstallKey
$previousStatusPath = Join-Path $stateRootPath 'runtime-status.json'
$previousRuntimeWasRunning = $false
if (Test-Path -LiteralPath $previousStatusPath -PathType Leaf) {
    try {
        $previousRuntimeWasRunning =
            (Get-Content -LiteralPath $previousStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json).state -eq 'running'
    } catch {}
}

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

	foreach ($architecture in Get-RegistrationArchitectures) {
		$tool = Join-Path $targetRoot (([string]$architecture.name) + '\YimeTextServiceRegistration.exe')
		Wait-RegistrationState $tool $false $false 0
	}
	$registrationStarted = $true
	foreach ($architecture in Get-RegistrationArchitectures) {
		$name = [string]$architecture.name
		$tool = Join-Path $targetRoot "$name\YimeTextServiceRegistration.exe"
		Invoke-Registration $tool ([string]$architecture.action) `
			(Join-Path $targetRoot "$name\YimeTextServiceExperiment.dll") "$name TSF registration"
		Wait-RegistrationState $tool $true $true 5
	}
    Add-InputMethodTip

    $runtimeConfig = Write-RuntimeConfiguration $targetRoot
    $runValue = '{0} -no-toolbar' -f (Quote-Argument ([string]$runtimeConfig.runtime_path))
    New-Item -Path $runKey -Force | Out-Null
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
    New-Item -Path $uninstallKey -Force | Out-Null
    $estimatedSize = [int]([math]::Ceiling((Get-ChildItem -LiteralPath $targetRoot -Recurse -File |
        Measure-Object Length -Sum).Sum / 1KB))
    $properties = [ordered]@{
        DisplayName = $productName
        DisplayVersion = ([string]$package.manifest.git_commit).Substring(0, 12)
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
    foreach ($oldRoot in $previousRoots) {
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
				$previousRuntimeWasRunning
        }
        if (Test-Path -LiteralPath $stagingRoot) { Remove-ProductTree $stagingRoot | Out-Null }
    } catch {
        $rollbackFailure = $_
    }
    if ($rollbackFailure) {
        throw "${failure}; restoring the previous trial installation also failed: $rollbackFailure"
    }
    throw $failure
}
