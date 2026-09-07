[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$parent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $parent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-registration-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-registration-* fixture root.'
}
for ($cursor = $parent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Registration evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$sourceFiles = @(
    'installer/installer.nsi',
    'tools/dual-product/rime-pime-ownership.ps1',
    'tools/dual-product/invoke-rime-pime-maintenance.ps1'
)
$source = @{}
$sourceHashes = [ordered]@{}
foreach ($relative in $sourceFiles) {
    $path = Join-Path $repo $relative
    $source[$relative] = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $sourceHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{ name = $Name; passed = $true }) }
    catch { $checks.Add([ordered]@{ name = $Name; passed = $false; reason = $_.Exception.Message }) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Must-Reject([scriptblock]$Body) {
    $rejected = $false
    try { & $Body | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Expected fail-closed rejection.'
}
function Copy-Fixture($Value) { return ($Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }

. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
$fixtureSid = 'S-1-5-21-100-200-300-1001'
function Get-YimePimeCurrentSid { return $fixtureSid }
$fixtureRoot = Join-Path $output 'selected root'
$marker = Join-Path $fixtureRoot 'go-backend\input_methods\yime'
New-Item -ItemType Directory -Path $marker -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $marker 'ime.json'), '{"guid":"{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"}')
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'PIMELauncher.exe'), 'DP1 FAKE NONEXECUTABLE PAYLOAD')

function New-RegistrationSnapshot([string[]]$Architectures = @('x64', 'x86'),
    [switch]$OmitTargetUserEnable) {
    $records = @(Get-YimePimeExpectedRegistrationRecords -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures $Architectures `
        -OmitTargetUserEnable:$OmitTargetUserEnable)
    return [pscustomobject][ordered]@{
        schema_version = 'yime-pime-registration-snapshot-v1'
        install_root = $fixtureRoot
        target_user_sid = $fixtureSid
        target_user_enable_required = (-not $OmitTargetUserEnable)
        architectures = $Architectures
        records = @($records | ForEach-Object {
            [pscustomobject][ordered]@{
                id = $_.id
                hive = $_.hive
                view = $_.view
                key = $_.key
                name = $_.name
                exists = $true
                value_kind = $_.value_kind
                value = $_.value
            }
        })
    }
}
Check 'removal-snapshot-omits-enabled-value-but-remains-root-and-sid-bound' {
    $snapshot=New-RegistrationSnapshot -OmitTargetUserEnable
    $result=Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86') -OmitTargetUserEnable
    Assert-True ($result.passed -and $result.records_verified -eq 14 -and
        @($snapshot.records|Where-Object id -eq 'target-user-profile-enable').Count -eq 0) `
        'Removal ownership snapshot is not independent of the user enabled/disabled choice.'
    Must-Reject {Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
}

Check 'pure-registration-contract-is-present' {
    foreach ($name in @('Get-YimePimeExpectedRegistrationRecords', 'Assert-YimePimeRegistrationSnapshot',
            'Get-YimePimeRegistrationSnapshot')) {
        Assert-True ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) "Missing function: $name"
    }
}
Check 'positive-x64-x86-registration-snapshot' {
    $result = Assert-YimePimeRegistrationSnapshot -Snapshot (New-RegistrationSnapshot) `
        -InstallRoot $fixtureRoot -TargetUserSid $fixtureSid -Architectures @('x64', 'x86')
    Assert-True ($result.passed -and $result.records_verified -eq 15 -and
        $result.install_root -ieq $fixtureRoot -and
        -not $result.actual_registry_mutation_executed) 'Positive registration ownership result is incomplete.'
}
Check 'positive-arm64-x86-registration-snapshot-is-native-exclusive' {
    $snapshot=New-RegistrationSnapshot -Architectures @('arm64','x86')
    $result=Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('arm64','x86')
    $ids=@($snapshot.records|ForEach-Object{[string]$_.id})
    Assert-True ($result.passed -and $result.records_verified -eq 15 -and
        $ids -contains 'com-arm64-path' -and $ids -contains 'machine-profile-icon' -and
        $ids -contains 'machine-profile-icon-index' -and
        $ids -notcontains 'com-x64-path' -and
        @($snapshot.records|Where-Object id -eq 'com-arm64-path')[0].value -ieq
            (Join-Path $fixtureRoot 'arm64\PIMETextService.dll')) `
        'ARM64/x86 registration snapshot is missing or contaminated by x64 state.'
}
Check 'expected-record-set-is-independent-and-includes-target-user-enable' {
    $expectedIds=@('com-x64-display-name','com-x64-path','com-x64-threading',
        'com-x86-display-name','com-x86-path','com-x86-threading',
        'machine-tip-enable',
        'machine-profile-description','machine-profile-icon','machine-profile-icon-index',
        'product-install-root','run-command','uninstall-command','uninstall-location',
        'target-user-profile-enable')
    $records=@((New-RegistrationSnapshot).records)
    Assert-True ($records.Count -eq $expectedIds.Count) 'Registration record count drifted.'
    foreach($id in $expectedIds) {
        Assert-True (@($records|Where-Object id -ceq $id).Count -eq 1) "Expected record is absent or duplicated: $id"
    }
    $user=@($records|Where-Object id -ceq 'target-user-profile-enable')[0]
    Assert-True ($user.hive -ceq 'Users' -and $user.view -ceq 'Shared' -and
        $user.key -ceq "$fixtureSid\SOFTWARE\Microsoft\CTF\TIP\{35F67E9D-A54D-4177-9697-8B0AB71A9E04}\LanguageProfile\0x00000804\{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}" -and
        $user.name -ceq 'Enable' -and $user.value_kind -ceq 'DWord' -and $user.value -ceq '1') `
        'Target-user enable coordinate, kind, or value is not exact.'
    $shared=@($records|Where-Object{$_.id -like 'machine-*'})
    Assert-True ($shared.Count -eq 4 -and @($shared|Where-Object{$_.view -cne 'Shared'}).Count -eq 0 -and
        @($shared|Where-Object{$_.id -eq 'machine-tip-enable' -and $_.name -ceq 'Enable' -and
            $_.value_kind -ceq 'String' -and $_.value -ceq '1'}).Count -eq 1) `
        'Machine TIP/Profile records are duplicated by architecture or omit the shared Enable value.'
    $description=@($records|Where-Object id -ceq 'machine-profile-description')[0].value
    Assert-True ($description.Length -eq 2 -and [int][char]$description[0] -eq 0x97F3 -and
        [int][char]$description[1] -eq 0x5143) `
        'Machine profile description is not invariant Unicode code points under Windows PowerShell 5.1.'
}
Check 'profile-icon-index-follows-the-existing-windows-version-threshold' {
    Assert-True ((Get-YimePimeExpectedProfileIconIndex -WindowsVersion ([version]'6.1')) -eq 0) `
        'Windows 7 must retain classic icon index 0.'
    foreach($version in @([version]'6.2',[version]'6.3',[version]'10.0')) {
        Assert-True ((Get-YimePimeExpectedProfileIconIndex -WindowsVersion $version) -eq 1) `
            "Windows 8+ must use icon index 1: $version"
    }
    $record=@((New-RegistrationSnapshot).records|Where-Object id -eq 'machine-profile-icon-index')[0]
    Assert-True ($record.name -ceq 'IconIndex' -and $record.value_kind -ceq 'DWord' -and
        $record.value -ceq [string](Get-YimePimeExpectedProfileIconIndex)) `
        'Machine profile IconIndex coordinate, type, or OS-derived value is not exact.'
    Assert-True (@(Get-YimePimeExpectedCategoryGuids -WindowsVersion ([version]'6.1')).Count -eq 4 -and
        @(Get-YimePimeExpectedCategoryGuids -WindowsVersion ([version]'6.2')).Count -eq 6) `
        'Windows 8 category threshold drifted from native registration behavior.'
}
Check 'wrong-registration-value-or-kind-is-rejected' {
    foreach ($mode in @('path', 'kind', 'missing')) {
        $snapshot = Copy-Fixture (New-RegistrationSnapshot)
        $record = @($snapshot.records | Where-Object id -eq 'com-x64-path')[0]
        if ($mode -eq 'path') { $record.value = 'C:\DP1-Fixture\Foreign\x64\PIMETextService.dll' }
        elseif ($mode -eq 'kind') { $record.value_kind = 'ExpandString' }
        else { $record.exists = $false }
        Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64', 'x86') }
    }
    $snapshot=Copy-Fixture (New-RegistrationSnapshot)
    @($snapshot.records|Where-Object id -eq 'com-x86-display-name')[0].value='ForeignTextService'
    Must-Reject {Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    $snapshot=Copy-Fixture (New-RegistrationSnapshot)
    @($snapshot.records|Where-Object id -eq 'machine-profile-icon')[0].value='C:\DP1-Fixture\Foreign\icon.ico'
    Must-Reject {Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    foreach($mode in @('value','kind')) {
        $snapshot=Copy-Fixture (New-RegistrationSnapshot)
        $record=@($snapshot.records|Where-Object id -eq 'machine-profile-icon-index')[0]
        if($mode -eq 'value'){$record.value=if($record.value -ceq '1'){'0'}else{'1'}}
        else{$record.value_kind='String'}
        Must-Reject {Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    }
    foreach($mode in @('value','kind')) {
        $snapshot=Copy-Fixture (New-RegistrationSnapshot)
        $record=@($snapshot.records|Where-Object id -eq 'machine-tip-enable')[0]
        if($mode -eq 'value'){$record.value='0'}else{$record.value_kind='DWord'}
        Must-Reject {Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    }
}
Check 'wrong-target-user-enable-coordinate-kind-or-value-is-rejected' {
    foreach($mode in @('coordinate','kind','value','missing')) {
        $snapshot=Copy-Fixture (New-RegistrationSnapshot)
        $record=@($snapshot.records|Where-Object id -eq 'target-user-profile-enable')[0]
        if($mode -eq 'coordinate'){$record.key=$record.key.Replace($fixtureSid,'S-1-5-21-100-200-300-2002')}
        elseif($mode -eq 'kind'){$record.value_kind='String'}
        elseif($mode -eq 'value'){$record.value='0'}
        else{$record.exists=$false}
        Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64','x86') }
    }
}
Check 'run-install-and-uninstall-roots-are-exact' {
    foreach ($id in @('run-command', 'product-install-root', 'uninstall-command', 'uninstall-location')) {
        $snapshot = Copy-Fixture (New-RegistrationSnapshot)
        @($snapshot.records | Where-Object id -eq $id)[0].value = 'C:\DP1-Fixture\Foreign\payload.exe'
        Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64', 'x86') }
    }
}
Check 'record-set-must-be-complete-unique-and-closed' {
    foreach ($mode in @('missing', 'duplicate', 'extra')) {
        $snapshot = Copy-Fixture (New-RegistrationSnapshot)
        if ($mode -eq 'missing') { $snapshot.records = @($snapshot.records | Select-Object -Skip 1) }
        elseif ($mode -eq 'duplicate') { $snapshot.records += Copy-Fixture $snapshot.records[0] }
        else {
            $extra = Copy-Fixture $snapshot.records[0]
            $extra.id = 'foreign-extra'
            $snapshot.records += $extra
        }
        Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64', 'x86') }
    }
}
Check 'sid-root-and-architecture-mismatch-is-rejected' {
    $snapshot = New-RegistrationSnapshot
    Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid 'S-1-5-21-100-200-300-2002' -Architectures @('x64', 'x86') }
    $snapshot = New-RegistrationSnapshot
    $snapshot.install_root = 'C:\DP1-Fixture\Foreign'
    Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64', 'x86') }
    $snapshot = New-RegistrationSnapshot
    Must-Reject { Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('arm64', 'x86') }
}
Check 'x64-and-arm64-cannot-share-one-native-registry-view' {
    Must-Reject { Get-YimePimeExpectedRegistrationRecords -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64', 'arm64', 'x86') }
}
Check 'maintenance-entry-exposes-read-only-registration-verification' {
    $invoke = $source['tools/dual-product/invoke-rime-pime-maintenance.ps1']
    Assert-True ($invoke.Contains("'ValidateRegistration'") -and
        $invoke.Contains("'ValidateRegistrationForRemoval'") -and
        $invoke.Contains("'ValidateRegistrationVacant'") -and
        $invoke.Contains('ArchitectureSet')) `
        'Maintenance CLI does not expose explicit registration verification and architecture scope.'
}
Check 'system-registry-reader-is-out-of-process-and-fail-closed' {
    $ownership=$source['tools/dual-product/rime-pime-ownership.ps1']
    foreach($anchor in @('WbemScripting.SWbemNamedValueSet','WbemScripting.SWbemLocator',
            "__ProviderArchitecture","__RequiredArchitecture",
            'process-view fallback is forbidden',
            "reader='StdRegProv'",'Assert-YimePimeTargetUserComShadowsAbsent',
            'Assert-YimePimeNoLegacyMarkers')) {
        Assert-True $ownership.Contains($anchor) "System registration reader is missing: $anchor"
    }
    Assert-True ($ownership -notmatch 'OpenBaseKey\(' -and -not $ownership.Contains('WOW6432Node')) `
        'Registration ownership uses a caller/physical implementation path instead of explicit WMI provider architecture.'
}
Check 'system-registry-reader-selects-provider-architecture-keeps-shared-logical-path-and-rejects-errors' {
    $coordinate=Convert-YimePimeSystemRegistryCoordinate -Hive LocalMachine -View Registry32 `
        -Key 'SOFTWARE\Classes\CLSID\{00000000-0000-0000-0000-000000000000}'
    Assert-True ($coordinate.hive -eq [uint32]2147483650 -and
        $coordinate.key -ceq 'SOFTWARE\Classes\CLSID\{00000000-0000-0000-0000-000000000000}' -and
        $coordinate.provider_architecture -eq 32 -and $coordinate.required_architecture) `
        'Registry32 COM coordinate did not select the 32-bit StdRegProv context.'
    foreach($view in @('Registry32','Registry64','Shared')) {
        $shared=Convert-YimePimeSystemRegistryCoordinate -Hive LocalMachine -View $view `
            -Key 'SOFTWARE\Microsoft\CTF\TIP\{00000000-0000-0000-0000-000000000000}'
        Assert-True ($shared.key -ceq 'SOFTWARE\Microsoft\CTF\TIP\{00000000-0000-0000-0000-000000000000}' -and
            $shared.provider_architecture -eq $(if($view -eq 'Registry32'){32}else{64})) `
            "Shared CTF/TIP coordinate was physically rewritten or selected the wrong provider: $view"
    }
    $script:providerDenied=$false
    $script:providerCalls=[Collections.Generic.List[object]]::new()
    function Invoke-YimePimeStdRegProvMethod {
        param([string]$Method,[hashtable]$Arguments,[int]$ProviderArchitecture)
        $script:providerCalls.Add([pscustomobject]@{
            method=$Method;arguments=$Arguments;provider_architecture=$ProviderArchitecture})
        if($script:providerDenied){return [pscustomobject]@{ReturnValue=5}}
        if($Method -eq 'EnumValues'){
            return [pscustomobject]@{ReturnValue=0;sNames=@('');Types=@(1)}
        }
        if($Method -eq 'GetStringValue'){
            return [pscustomobject]@{ReturnValue=0;sValue='fixture-value'}
        }
        throw "Unexpected provider method: $Method"
    }
    $expected=New-YimePimeExpectedRegistrationRecord 'fixture' 'Registry32' `
        'SOFTWARE\Classes\CLSID\{00000000-0000-0000-0000-000000000000}' '' 'String' 'fixture-value'
    $record=Get-YimePimeSystemRegistryValueRecord $expected
    Assert-True ($record.exists -and $record.value_kind -ceq 'String' -and
        $record.value -ceq 'fixture-value' -and $record.reader -ceq 'StdRegProv') `
        'System provider value read did not retain exact kind/value evidence.'
    Assert-True (@($script:providerCalls|Where-Object{
        $_.provider_architecture -eq 32 -and
        $_.arguments.sSubKeyName -ceq 'SOFTWARE\Classes\CLSID\{00000000-0000-0000-0000-000000000000}'}).Count -eq 2) `
        'System provider read escaped the explicit x86 provider context or logical coordinate.'
    $script:providerDenied=$true
    Must-Reject {Get-YimePimeSystemRegistryValueRecord $expected}
}
Check 'fresh-registration-vacancy-rejects-every-orphan-class-without-mutation' {
    $vacantRoot=Join-Path $output 'vacant root'
    New-Item -ItemType Directory -Path $vacantRoot | Out-Null
    $script:registryFixture=@{}
    $script:providerDenied=$false
    $script:providerMethods=[Collections.Generic.List[string]]::new()
    function Add-RegistryFixtureKey([uint32]$Hive,[string]$Key,[string[]]$Names=@(),[int[]]$Types=@()) {
        $script:registryFixture["$Hive|$Key"]=[pscustomobject]@{names=@($Names);types=@($Types)}
    }
    function Invoke-YimePimeStdRegProvMethod {
        param([string]$Method,[hashtable]$Arguments,[int]$ProviderArchitecture)
        $script:providerMethods.Add($Method)
        if($script:providerDenied){return [pscustomobject]@{ReturnValue=5}}
        $id="$ProviderArchitecture|$($Arguments.hDefKey)|$($Arguments.sSubKeyName)"
        if($Method -eq 'EnumValues') {
            if(-not $script:registryFixture.ContainsKey($id)){return [pscustomobject]@{ReturnValue=2}}
            $item=$script:registryFixture[$id]
            return [pscustomobject]@{ReturnValue=0;sNames=@($item.names);Types=@($item.types)}
        }
        if($Method -eq 'EnumKey') {
            $prefix=$id+'\';$children=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($candidate in @($script:registryFixture.Keys)) {
                if($candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
                    $tail=$candidate.Substring($prefix.Length).Split('\')[0]
                    if($tail){$null=$children.Add($tail)}
                }
            }
            if(-not $script:registryFixture.ContainsKey($id) -and $children.Count -eq 0){
                return [pscustomobject]@{ReturnValue=2}
            }
            return [pscustomobject]@{ReturnValue=0;sNames=@($children)}
        }
        throw "Unexpected provider method: $Method"
    }
    function Reset-RegistryFixture {$script:registryFixture=@{};$script:providerDenied=$false}
    $null=Assert-YimePimeRegistrationVacant -InstallRoot $vacantRoot -TargetUserSid $fixtureSid `
        -Architectures @('x64','x86')
    $hklm=[uint32]2147483650;$hku=[uint32]2147483651;$clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
    $cases=@(
        [pscustomobject]@{name='run-only';arch=64;hive=$hklm;key='SOFTWARE\Microsoft\Windows\CurrentVersion\Run';names=@('PIMELauncher');types=@(1)},
        [pscustomobject]@{name='current-empty-key';arch=64;hive=$hklm;key='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME'},
        [pscustomobject]@{name='wrong-view-current';arch=32;hive=$hklm;key='SOFTWARE\YIME'},
        [pscustomobject]@{name='legacy-empty-key';arch=32;hive=$hklm;key='SOFTWARE\PIME'},
        [pscustomobject]@{name='x86-com-parent';arch=32;hive=$hklm;key="SOFTWARE\Classes\CLSID\$clsid"},
        [pscustomobject]@{name='shared-machine-tip';arch=64;hive=$hklm;key="SOFTWARE\Microsoft\CTF\TIP\$clsid"},
        [pscustomobject]@{name='target-user-tip';arch=64;hive=$hku;key="$fixtureSid\SOFTWARE\Microsoft\CTF\TIP\$clsid"},
        [pscustomobject]@{name='target-user-com-shadow';arch=64;hive=$hku;key="$fixtureSid\SOFTWARE\Classes\CLSID\$clsid"},
        [pscustomobject]@{name='control-panel-reference';arch=64;hive=$hku;key="$fixtureSid\Control Panel\International\User Profile\zh-CN";names=@("0x0804:$clsid{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}");types=@(1)}
    )
    foreach($case in $cases) {
        Reset-RegistryFixture
        $script:registryFixture["$($case.arch)|$($case.hive)|$($case.key)"]=[pscustomobject]@{
            names=@($case.names);types=@($case.types)}
        Must-Reject {Assert-YimePimeRegistrationVacant -InstallRoot $vacantRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    }
    Reset-RegistryFixture
    $script:providerDenied=$true
    Must-Reject {Assert-YimePimeRegistrationVacant -InstallRoot $vacantRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    Reset-RegistryFixture
    Must-Reject {Assert-YimePimeRegistrationVacant -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    Assert-True (@($script:providerMethods|Where-Object{$_ -notin @('EnumValues','EnumKey')}).Count -eq 0) `
        'Vacancy test observed a registry mutation method.'
}
Check 'native-registration-absence-rejects-both-com-views-and-one-shared-machine-tip-shell' {
    $script:absenceRegistryFixture=@{}
    $script:absenceProviderMethods=[Collections.Generic.List[string]]::new()
    function Invoke-YimePimeStdRegProvMethod {
        param([string]$Method,[hashtable]$Arguments,[int]$ProviderArchitecture)
        $script:absenceProviderMethods.Add($Method)
        if($Method -ne 'EnumValues'){throw "Unexpected provider method: $Method"}
        $id="$ProviderArchitecture|$($Arguments.hDefKey)|$($Arguments.sSubKeyName)"
        if($script:absenceRegistryFixture.ContainsKey($id)){
            return [pscustomobject]@{ReturnValue=0;sNames=@();Types=@()}
        }
        return [pscustomobject]@{ReturnValue=2}
    }
    $null=Assert-YimePimeNativeRegistrationAbsent -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -Architectures @('x64','x86')
    $hklm=[uint32]2147483650;$clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
    foreach($case in @(
            [pscustomobject]@{arch=64;key="SOFTWARE\Microsoft\CTF\TIP\$clsid"},
            [pscustomobject]@{arch=64;key="SOFTWARE\Classes\CLSID\$clsid"},
            [pscustomobject]@{arch=32;key="SOFTWARE\Classes\CLSID\$clsid"})) {
        $script:absenceRegistryFixture=@{"$($case.arch)|$hklm|$($case.key)"=[pscustomobject]@{}}
        Must-Reject {Assert-YimePimeNativeRegistrationAbsent -InstallRoot $fixtureRoot `
            -TargetUserSid $fixtureSid -Architectures @('x64','x86')}
    }
    Assert-True (@($script:absenceProviderMethods|Where-Object{$_ -ne 'EnumValues'}).Count -eq 0) `
        'Native absence test observed a registry mutation method.'
}
Check 'live-registration-tree-closure-rejects-extra-com-tip-category-and-user-state' {
    $script:shapeFixture=@{}
    $script:shapeEnableValue=[uint32]1
    $hklm=[uint32]2147483650;$hku=[uint32]2147483651
    $clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
    $profile='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'
    $categories=@(
        '{34745C63-B2F0-4784-8B67-5E12C8701A31}',
        '{046B8C80-1647-40F7-9B21-B93B81AABC1B}',
        '{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}',
        '{CCF05DD7-4A87-11D7-A6E2-00065B84435C}',
        '{13A016DF-560B-46CD-947A-4C3AF1E0E35D}',
        '{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}'
    )
    function Add-Shape([int]$Arch,[uint32]$Hive,[string]$Key,[string[]]$Names,
        [string[]]$Children,[int[]]$Types=@()) {
        if($Types.Count -eq 0){$Types=@($Names|ForEach-Object{1})}
        $script:shapeFixture["$Arch|$Hive|$Key"]=[pscustomobject]@{
            names=@($Names);types=@($Types);children=@($Children)}
    }
    function Invoke-YimePimeStdRegProvMethod {
        param([string]$Method,[hashtable]$Arguments,[int]$ProviderArchitecture)
        $id="$ProviderArchitecture|$($Arguments.hDefKey)|$($Arguments.sSubKeyName)"
        if(-not $script:shapeFixture.ContainsKey($id)){return [pscustomobject]@{ReturnValue=2}}
        $item=$script:shapeFixture[$id]
        if($Method -eq 'EnumValues'){
            return [pscustomobject]@{ReturnValue=0;sNames=@($item.names);Types=@($item.types)}
        }
        if($Method -eq 'EnumKey'){
            return [pscustomobject]@{ReturnValue=0;sNames=@($item.children)}
        }
        if($Method -eq 'GetDWORDValue'){
            return [pscustomobject]@{ReturnValue=0;uValue=$script:shapeEnableValue}
        }
        throw "Unexpected shape provider method: $Method"
    }
    $com="SOFTWARE\Classes\CLSID\$clsid"
    foreach($arch in @(32,64)) {
        Add-Shape $arch $hklm $com @('') @('InprocServer32')
        Add-Shape $arch $hklm "$com\InprocServer32" @('','ThreadingModel') @()
    }
    Add-Shape 64 $hklm 'SOFTWARE\YIME' @('') @()
    Add-Shape 64 $hklm 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME' `
        @('DisplayName','UninstallString','InstallLocation','Publisher','DisplayVersion','URLInfoAbout') @()
    $tip="SOFTWARE\Microsoft\CTF\TIP\$clsid"
    Add-Shape 64 $hklm $tip @('Enable') @('Category','LanguageProfile')
    Add-Shape 64 $hklm "$tip\Category" @() @('Category','Item')
    Add-Shape 64 $hklm "$tip\Category\Category" @() $categories
    Add-Shape 64 $hklm "$tip\Category\Item" @() @($clsid)
    Add-Shape 64 $hklm "$tip\Category\Item\$clsid" @() $categories
    foreach($category in $categories) {
        Add-Shape 64 $hklm "$tip\Category\Category\$category" @() @($clsid)
        Add-Shape 64 $hklm "$tip\Category\Category\$category\$clsid" @() @()
        Add-Shape 64 $hklm "$tip\Category\Item\$clsid\$category" @() @()
    }
    Add-Shape 64 $hklm "$tip\LanguageProfile" @() @('0x00000804')
    Add-Shape 64 $hklm "$tip\LanguageProfile\0x00000804" @() @($profile)
    Add-Shape 64 $hklm "$tip\LanguageProfile\0x00000804\$profile" `
        @('Description','IconFile','IconIndex') @()
    $userTip="$fixtureSid\SOFTWARE\Microsoft\CTF\TIP\$clsid"
    Add-Shape 64 $hku $userTip @() @('LanguageProfile')
    Add-Shape 64 $hku "$userTip\LanguageProfile" @() @('0x00000804')
    Add-Shape 64 $hku "$userTip\LanguageProfile\0x00000804" @() @($profile)
    Add-Shape 64 $hku "$userTip\LanguageProfile\0x00000804\$profile" @('Enable') @() @(4)

    $null=Assert-YimePimeRegistrationTreesClosed -TargetUserSid $fixtureSid -Architectures @('x64','x86')
    foreach($mutation in @(
            [pscustomobject]@{id="32|$hklm|$com";field='children';value='LocalServer32'},
            [pscustomobject]@{id="64|$hklm|$tip";field='names';value='ForeignValue'},
            [pscustomobject]@{id="64|$hklm|$tip\Category\Category";field='children';value='{00000000-0000-0000-0000-000000000000}'},
            [pscustomobject]@{id="64|$hklm|SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME";field='children';value='ForeignChild'},
            [pscustomobject]@{id="64|$hku|$userTip\LanguageProfile\0x00000804\$profile";field='names';value='ForeignValue'})) {
        $item=$script:shapeFixture[$mutation.id]
        $item.($mutation.field)=@($item.($mutation.field))+@($mutation.value)
        if($mutation.field -eq 'names'){$item.types=@($item.types)+@(1)}
        Must-Reject {Assert-YimePimeRegistrationTreesClosed -TargetUserSid $fixtureSid `
            -Architectures @('x64','x86')}
        $item.($mutation.field)=@($item.($mutation.field)|Where-Object{$_ -cne $mutation.value})
        if($mutation.field -eq 'names'){$item.types=@($item.names|ForEach-Object{1})}
    }
    $userLeaf=$script:shapeFixture["64|$hku|$userTip\LanguageProfile\0x00000804\$profile"]
    $userLeaf.types=@(1)
    Must-Reject {Assert-YimePimeRegistrationTreesClosed -TargetUserSid $fixtureSid `
        -Architectures @('x64','x86') -OmitTargetUserEnable}
    $userLeaf.types=@(4)
    $script:shapeEnableValue=[uint32]2
    Must-Reject {Assert-YimePimeRegistrationTreesClosed -TargetUserSid $fixtureSid `
        -Architectures @('x64','x86') -OmitTargetUserEnable}
    $script:shapeEnableValue=[uint32]1
    Assert-True ($source['tools/dual-product/rime-pime-ownership.ps1'].Contains(
        'Assert-YimePimeRegistrationTreesClosed -TargetUserSid $TargetUserSid')) `
        'The live ownership gate does not invoke its registry tree closed-set verifier.'
}
Check 'maintenance-architecture-string-is-parsed-as-an-exact-set' {
    $script:capturedRegistrationArchitectures=@()
    function Assert-YimePimeRegistrationOwnedByRoot {
        param([string]$InstallRoot,[string]$TargetUserSid,[string[]]$Architectures)
        $script:capturedRegistrationArchitectures=@($Architectures)
        return [pscustomobject]@{passed=$true}
    }
    Invoke-YimePimeMaintenanceGuard -Action ValidateRegistration -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -ArchitectureSet 'x64,x86'
    Assert-True ($script:capturedRegistrationArchitectures.Count -eq 2 -and
        $script:capturedRegistrationArchitectures[0] -eq 'x64' -and
        $script:capturedRegistrationArchitectures[1] -eq 'x86') `
        'Maintenance CLI did not preserve the exact declared architecture set.'
    Invoke-YimePimeMaintenanceGuard -Action ValidateRegistration -InstallRoot $fixtureRoot `
        -TargetUserSid $fixtureSid -ArchitectureSet 'arm64,x86'
    Assert-True ($script:capturedRegistrationArchitectures.Count -eq 2 -and
        $script:capturedRegistrationArchitectures[0] -eq 'arm64' -and
        $script:capturedRegistrationArchitectures[1] -eq 'x86') `
        'Maintenance CLI did not preserve the ARM64/x86 architecture set.'
}
Check 'installer-checks-every-register-exit-before-owned-state-verification' {
    $nsis = $source['installer/installer.nsi']
    $register = [regex]::Match($nsis, '(?s)Section "" Register\s+(.*?)SectionEnd').Groups[1].Value
    Assert-True ([regex]::Matches($register,'!insertmacro RunCheckedRegistrationCommand').Count -ge 5 -and
        $register.Contains('"$RimeNativeRegsvr32" /s "$INSTDIR\x64\PIMETextService.dll"') -and
        $register.Contains('"$RimeX86Regsvr32" /s "$INSTDIR\x86\PIMETextService.dll"') -and
        $register.Contains('PIMERegistrationStatus_x86.exe" verify-present') -and
        $register.Contains('PIMERegistrationStatus_x64.exe" verify-present') -and
        $register.Contains('PIMERegistrationStatus_arm64.exe" verify-present') -and
        $register.Contains('Call verifyRegistrationOwnership')) 'Registration exit/state verification wiring is missing.'
    Assert-True ($register.IndexOf('WriteUninstaller') -ge 0 -and
        $register.IndexOf('WriteUninstaller') -lt $register.IndexOf('Call verifyRegistrationOwnership') -and
        $register.IndexOf('Call verifyRegistrationOwnership') -lt $register.IndexOf('Exec ')) `
        'Runtime starts before registration ownership is proven.'
    $uninstall = [regex]::Match($nsis, '(?s)Section "Uninstall"\s+(.*?)SectionEnd').Groups[1].Value
    Assert-True ($uninstall.IndexOf('Call un.verifyRegistrationOwnershipForRemoval') -ge 0 -and
        $uninstall.IndexOf('Call un.verifyRegistrationOwnershipForRemoval') -lt $uninstall.IndexOf('Call un.stopOwnedPime') -and
        $uninstall.IndexOf('Call un.verifyRegistrationOwnershipForRemoval') -lt $uninstall.IndexOf('DeleteRegKey')) `
        'Uninstall mutation begins before the selected root owns the active registration.'
}
Check 'installer-run-command-is-quoted-and-selected-root-bound' {
    $nsis = $source['installer/installer.nsi']
    Assert-True ($nsis.Contains('WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher" "$\"$INSTDIR\PIMELauncher.exe$\""')) `
        'Run command is not an exact quoted selected-root path.'
}

Check 'source-snapshot-unchanged-during-run' {
    foreach ($relative in $sourceFiles) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($actual -ceq [string]$sourceHashes[$relative]) "Source changed during run: $relative"
    }
}

$failed = @($checks | Where-Object { -not $_.passed })
$receipt = [ordered]@{
    schema_version = 'yime-rime-registration-ownership-isolated-v1'
    passed = ($failed.Count -eq 0)
    checks = $checks.ToArray()
    checks_count = $checks.Count
    failed_count = $failed.Count
    source_sha256 = $sourceHashes
    test_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition = $PSVersionTable.PSEdition
    powershell_version = $PSVersionTable.PSVersion.ToString()
    actual_registry_read_or_mutation_executed = $false
    actual_install_or_uninstall_executed = $false
    actual_elevation_executed = $false
    default_input_method_changed = $false
    production_rime_pime_touched = $false
    dp1_full_implementation_passed = $false
    dp2_physical_acceptance_passed = $false
}
[IO.File]::WriteAllText((Join-Path $output 'result.json'),
    (($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Output "Rime/PIME registration ownership fixtures: $($checks.Count) checks; $($failed.Count) failed; evidence $output"
if ($failed.Count) { exit 1 }
