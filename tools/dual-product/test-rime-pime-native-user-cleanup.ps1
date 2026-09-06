[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-native-user-cleanup-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-native-user-cleanup-* fixture root.'
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Native user-cleanup evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$sourceFiles = @(
    'libIME2/src/ImeModule.cpp',
    'PIMETextService/DllEntry.cpp',
    'installer/installer.nsi',
    'tools/dual-product/rime-pime-target-user.ps1',
    'tools/dual-product/rime-pime-ownership.ps1',
    'tools/dual-product/invoke-rime-pime-maintenance.ps1'
)
$source = @{}
$beforeHashes = [ordered]@{}
foreach ($relative in $sourceFiles) {
    $path = Join-Path $repo $relative
    $source[$relative] = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $beforeHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Must-Reject([scriptblock]$Body) {
    $rejected=$false
    try{& $Body|Out-Null}catch{$rejected=$true}
    Assert-True $rejected 'Expected fail-closed rejection.'
}

$cpp = $source['libIME2/src/ImeModule.cpp']
$matches = [regex]::Matches($cpp,
    '(?ms)^HRESULT\s+ImeModule::unregisterServer\([^\r\n]*\)\s*\{.*?(?=^[A-Za-z_][^\r\n]*\s+ImeModule::|\z)')
$unregister = if ($matches.Count -eq 1) { $matches[0].Value } else { '' }
$registerMatches = [regex]::Matches($cpp,
    '(?ms)^HRESULT\s+ImeModule::registerLangProfiles\([^\r\n]*\)\s*\{.*?(?=^HRESULT\s+ImeModule::|\z)')
$registerProfiles = if ($registerMatches.Count -eq 1) { $registerMatches[0].Value } else { '' }
$dllEntry = $source['PIMETextService/DllEntry.cpp']
$installer = $source['installer/installer.nsi']
$targetUser = $source['tools/dual-product/rime-pime-target-user.ps1']
$ownership = $source['tools/dual-product/rime-pime-ownership.ps1']
$maintenanceEntry = $source['tools/dual-product/invoke-rime-pime-maintenance.ps1']
$uninstallSection = [regex]::Match($installer, '(?ms)^Section "Uninstall"\s+(.*?)^SectionEnd').Groups[1].Value
. (Join-Path $repo 'tools\dual-product\rime-pime-ownership.ps1')

Check 'native-unregister-body-is-uniquely-bounded' {
    Assert-True ($matches.Count -eq 1 -and $unregister.Contains('ImeModule::unregisterServer')) `
        'Could not uniquely bound ImeModule::unregisterServer.'
}
Check 'native-unregister-does-not-enumerate-hkey-users' {
    Assert-True ($unregister -notmatch 'RegEnumKeyExW\s*\(\s*HKEY_USERS') `
        'DllUnregisterServer still enumerates every loaded user hive.'
}
Check 'native-unregister-does-not-load-or-unload-default-user-hive' {
    Assert-True ($unregister -notmatch 'loadDefaultUserRegistry|RegLoadKeyW|RegUnLoadKeyW') `
        'DllUnregisterServer still loads or unloads the Default User hive.'
}
Check 'native-unregister-does-not-traverse-per-user-control-panel' {
    Assert-True ($unregister -notmatch 'HKEY_USERS|Control Panel\\{2}International\\{2}User Profile') `
        'DllUnregisterServer still owns cross-user Control Panel cleanup.'
}
Check 'native-dll-owns-shared-tsf-once-and-unregisters-categories-before-profile' {
    Assert-True ($dllEntry.Contains('#if defined(_WIN64)') -and
        $dllEntry.Contains('constexpr bool kOwnsSharedTsfRegistration = true') -and
        $dllEntry.Contains('constexpr bool kOwnsSharedTsfRegistration = false') -and
        $dllEntry.Contains('unregisterServer(kOwnsSharedTsfRegistration)') -and
        $dllEntry.Contains('kOwnsSharedTsfRegistration);')) `
        'x86 and native DLLs do not explicitly split redirected COM from one shared TSF owner.'
    Assert-True ($unregister.Contains('if(ownsSharedTsfRegistration)') -and
        $unregister.IndexOf('UnregisterCategory(') -ge 0 -and
        $unregister.IndexOf('UnregisterCategory(') -lt $unregister.IndexOf('inputProcessProfiles->Unregister(') -and
        $unregister.IndexOf('inputProcessProfiles->Unregister(') -lt $unregister.IndexOf('SHDeleteKey(')) `
        'Shared TSF removal is not guarded or does not use Category -> Profile -> COM order.'
}
Check 'native-register-profile-body-is-uniquely-bounded' {
    Assert-True ($registerMatches.Count -eq 1 -and $registerProfiles.Contains('ImeModule::registerLangProfiles')) `
        'Could not uniquely bound ImeModule::registerLangProfiles.'
}
Check 'native-register-does-not-enumerate-or-write-hkey-users' {
    Assert-True ($registerProfiles -notmatch 'HKEY_USERS|RegEnumKeyExW|RegCreateKeyExW') `
        'Native profile registration still enumerates or writes other user hives.'
}
Check 'native-register-does-not-load-default-user-hive' {
    Assert-True ($registerProfiles -notmatch 'loadDefaultUserRegistry|RegLoadKeyW|RegUnLoadKeyW') `
        'Native profile registration still mutates the Default User hive.'
}
Check 'target-user-cleanup-helper-is-explicit-and-does-not-enumerate-hku-root' {
    Assert-True ($ownership.Contains('function Remove-YimePimeTargetUserProfileValues') -and
        $ownership.Contains('Get-YimePimeTargetUserRegistryPath -TargetUserSid $sid') -and
        $ownership.Contains('Control Panel\International\User Profile') -and
        -not $ownership.Contains('Get-ChildItem -LiteralPath "Registry::HKEY_USERS"') -and
        $targetUser.Contains('return "Registry::HKEY_USERS\$sid\$RelativePath"')) `
        'The dedicated target-SID cleanup helper is absent or can enumerate the HKU root.'
    Assert-True ($maintenanceEntry.Contains("'CleanupTargetUserProfile'") -and
        $maintenanceEntry.Contains("'ValidateTargetUserProfileAbsent'") -and
        $maintenanceEntry.Contains('Invoke-YimePimeMaintenanceGuard -Action $Action') -and
        $maintenanceEntry.Contains('-TargetUserSid $TargetUserSid') -and
        $ownership.Contains("'CleanupTargetUserProfile' { Remove-YimePimeTargetUserProfileValues -TargetUserSid `$sid }") -and
        $ownership.Contains('function Assert-YimePimeTargetUserProfileAbsent')) `
        'The maintenance entry does not expose explicit cleanup and absence verification for TargetUserSid.'
}
Check 'target-user-control-panel-classification-is-symmetric-and-exact' {
    $clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
    Assert-True (Test-YimePimeProfileRegistryReference -Name "0x0804:$clsid" -Value '') `
        'CLSID in a profile value name was not classified.'
    Assert-True (Test-YimePimeProfileRegistryReference -Name 'InputMethodTips' -Value "0x0804:$clsid") `
        'CLSID in a profile string value was not classified.'
    Assert-True (Test-YimePimeProfileRegistryReference -Name 'InputMethodTips' -Value @('foreign',"0x0804:$clsid")) `
        'CLSID in a profile multi-string value was not classified.'
    Assert-True (-not (Test-YimePimeProfileRegistryReference -Name 'InputMethodTips' `
        -Value '0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E05}')) `
        'Near-match foreign CLSID was incorrectly classified as Rime/PIME.'
    Must-Reject {Test-YimePimeProfileRegistryReference -Name 'InputMethodTips' `
        -Value "prefix-$clsid-suffix"}
    Assert-True ($ownership.Contains('$paths=@($profileRoot)+@(') -and
        $ownership.Contains('$kept=[Collections.Generic.List[string]]::new()') -and
        $ownership.Contains('Set-ItemProperty -LiteralPath $path -Name $property.Name') -and
        $ownership.Contains('Assert-YimePimeTargetUserTipTreeClosed -TargetUserSid $sid')) `
        'Cleanup does not preserve foreign multi-string elements or close the target TIP tree before recursive deletion.'
}
Check 'uninstaller-delays-raw-target-user-cleanup-until-native-absence' {
    $profile = $uninstallSection.IndexOf('Call un.InstallLayoutOrTipForUser')
    $cleanup = $uninstallSection.IndexOf('Call un.cleanupTargetUserProfile')
    $absence = $uninstallSection.IndexOf('Call un.verifyTargetUserProfileAbsent')
    $native = $uninstallSection.IndexOf('/u /s')
    $nativeAbsent = $uninstallSection.IndexOf('Call un.verifyNativeRegistrationAbsent')
    $lastTsfAbsent = $uninstallSection.LastIndexOf('verify-absent')
    $productDelete = $uninstallSection.IndexOf('DeleteRegKey')
    Assert-True ($installer.Contains('Function un.cleanupTargetUserProfile') -and
        $installer.Contains('Function un.verifyTargetUserProfileAbsent') -and
        $installer.Contains('StrCpy $RimeOwnershipAction "CleanupTargetUserProfile"') -and
        $installer.Contains('StrCpy $RimeOwnershipAction "ValidateTargetUserProfileAbsent"') -and
        $profile -ge 0 -and $native -gt $profile -and $nativeAbsent -gt $native -and
        $lastTsfAbsent -gt $nativeAbsent -and $cleanup -gt $lastTsfAbsent -and
        $absence -gt $cleanup -and $productDelete -gt $absence) `
        'Raw TargetUserSid cleanup is not delayed until native COM/Profile/category absence is proven.'
}
Check 'source-snapshot-unchanged-during-run' {
    foreach ($relative in $sourceFiles) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($actual -ceq [string]$beforeHashes[$relative]) "Source changed during run: $relative"
    }
}

$failed = @($checks | Where-Object {-not $_.passed})
$receipt = [ordered]@{
    schema_version = 'yime-rime-pime-native-user-cleanup-test-v1'
    test_level = 'source-only-no-native-or-registry-execution'
    source_sha256 = $beforeHashes
    test_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition = $PSVersionTable.PSEdition
    powershell_version = $PSVersionTable.PSVersion.ToString()
    check_count = $checks.Count
    passed_count = $checks.Count - $failed.Count
    failed_count = $failed.Count
    passed = $failed.Count -eq 0
    checks = $checks
    native_unregister_cross_sid_cleanup_removed = (
        @($checks | Where-Object {$_.name -like 'native-unregister-*' -and -not $_.passed}).Count -eq 0)
    native_register_cross_sid_write_removed = (
        @($checks | Where-Object {$_.name -like 'native-register-*' -and -not $_.passed}).Count -eq 0)
    installer_target_sid_cleanup_wired = (
        @($checks | Where-Object {$_.name -in @(
            'target-user-cleanup-helper-is-explicit-and-does-not-enumerate-hku-root',
            'uninstaller-delays-raw-target-user-cleanup-until-native-absence') -and -not $_.passed}).Count -eq 0)
    actual_installer_or_uninstaller_executed = $false
    actual_registry_or_profile_mutation_executed = $false
    user_registry_or_data_read = $false
    dp1_full_implementation_passed = $false
    dp2_physical_acceptance_passed = $false
}
$receiptPath = Join-Path $output 'result.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
if ($failed.Count) {
    Write-Host "FAIL: $($failed.Count) of $($checks.Count) native user-cleanup source checks failed. Evidence: $receiptPath"
    foreach ($item in $failed) { Write-Host " - $($item.name): $($item.reason)" }
    exit 1
}
Write-Host "PASS: $($checks.Count) native user-cleanup source checks passed without OS mutation. Evidence: $receiptPath"
