[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ExpectedManifestSha256,
    [int[]]$HostProcessId = @()
)
# Read-only, metadata-only. No host text, titles, command lines, clipboard,
# user settings, learning files, event payloads, or screenshots are read.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope = Get-YimeCoreDevelopmentScope
$root = [IO.Path]::GetFullPath($InstallRoot)
$manifestPath = Join-Path $root 'package-manifest.json'
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifestHash -ne $ExpectedManifestSha256) { throw 'Installed manifest differs from the pinned acceptance candidate.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$descriptor = Get-Content -LiteralPath (Join-Path $root 'local-product.json') -Raw | ConvertFrom-Json
if ($manifest.product_version -ne $descriptor.version) { throw 'Manifest/descriptor version mismatch.' }
$prefix = $root.TrimEnd('\') + '\'
$mismatches = @()
foreach ($file in $manifest.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $file.path))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes package root.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $mismatches += $file.path; continue }
    if ((Get-Item -LiteralPath $path).Length -ne $file.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { $mismatches += $file.path }
}
function Get-RecordHash($Record) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Record | ConvertTo-Json -Depth 60 -Compress))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$protected = [ordered]@{}
foreach ($clsid in @('{35F67E9D-A54D-4177-9697-8B0AB71A9E04}', [string]$descriptor.identity.legacy_clsid)) {
    foreach ($key in @("SOFTWARE\Classes\CLSID\$clsid", "SOFTWARE\Classes\WOW6432Node\CLSID\$clsid",
        "SOFTWARE\Microsoft\CTF\TIP\$clsid", "SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$clsid")) {
        $protected[$key] = Get-RecordHash (Read-YimeCoreSystemKey 2147483650 $key)
    }
    $key = "Software\Microsoft\CTF\TIP\$clsid"
    $protected["user/$key"] = Get-RecordHash (Read-YimeCoreSystemKey 2147483651 "$sid\$key")
}
foreach ($key in @('Control Panel\International\User Profile', 'Keyboard Layout\Preload')) {
    $protected["user/$key"] = Get-RecordHash (Read-YimeCoreSystemKey 2147483651 "$sid\$key")
}
$activeKey = "SOFTWARE\Classes\CLSID\$($descriptor.identity.clsid)\InprocServer32"
$activeCom = Read-YimeCoreSystemKey 2147483650 $activeKey
$registeredDll = @($activeCom.values | Where-Object { $_.name -eq '' } | ForEach-Object { $_.value })
$boot = (Get-CimInstance Win32_OperatingSystem -Property LastBootUpTime).LastBootUpTime
# Restrict the provider query itself; filtering output alone would still fetch
# unneeded fields such as CommandLine before serialization.
$processes = @(Get-CimInstance Win32_Process -Filter "Name='YimeCoreTrialRuntime.exe' OR Name='YimeBroker.exe'" -Property Name,ProcessId,ExecutablePath,CreationDate | ForEach-Object {
    [ordered]@{name=$_.Name;pid=$_.ProcessId;image=$_.ExecutablePath;started_at=$_.CreationDate.ToString('o');
        current_package=($_.ExecutablePath -ieq (Join-Path $root "bin\$($_.Name)"));after_boot=($_.CreationDate -ge $boot)}
})
$hosts = @(foreach ($hostId in $HostProcessId) {
    $process = Get-Process -Id $hostId
    if ($process.ProcessName -notin @('notepad', 'WINWORD', 'msedge', 'Code')) { throw 'Only explicitly selected x64 daily-use host names are supported.' }
    $modules = @($process.Modules | Where-Object { $_.ModuleName -eq 'YimeTextServiceExperiment.dll' } | ForEach-Object {
        [ordered]@{path=$_.FileName;sha256=(Get-FileHash -LiteralPath $_.FileName).Hash.ToLowerInvariant();
            current_x64=($_.FileName -ieq (Join-Path $root 'x64\YimeTextServiceExperiment.dll'))}
    })
    [ordered]@{name=$process.ProcessName;pid=$process.Id;image=$process.Path;version=$process.MainModule.FileVersionInfo.FileVersion;
        yime_modules=$modules;note='Loaded module is not proof of current active profile; physical selection must also be confirmed.'}
})
[ordered]@{
    schema_version='yimecore-l5-metadata-v1';generated_at=(Get-Date).ToString('o');computer=$env:COMPUTERNAME;
    development_scope=$scope.id;package_version=$manifest.product_version;install_root=$root;
    manifest_sha256=$manifestHash;package_file_count=@($manifest.files).Count;package_mismatches=$mismatches;
    package_integrity_passed=($mismatches.Count -eq 0);boot_at=$boot.ToString('o');processes=$processes;
    runtime_identity_passed=(@($processes | Where-Object {$_.current_package -and $_.after_boot}).Count -eq 2 -and $processes.Count -eq 2);
    registered_x64_dll=$registeredDll;registered_x64_matches=($registeredDll.Count -eq 1 -and $registeredDll[0] -ieq (Join-Path $root 'x64\YimeTextServiceExperiment.dll'));
    protected_registry_provider='out-of-process StdRegProv; no process-view fallback';protected_registry_sha256=$protected;
    hosts=$hosts;user_text_read=$false;learning_data_read=$false;frozen_targets_executed=$false;
    writes_to_product=$false;manual_daily_use_passed=$null;logon_autostart_verified=$null
} | ConvertTo-Json -Depth 12
