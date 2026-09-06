# Rime/PIME-specific maintenance ownership. Definitions only; no action on import.
# This file is shipped in the Rime/PIME installer, independently of YimeCore.
# Directed maintenance uses a process-bound pipe and never the historical
# shared PIMELauncher2_QuitEvent or a force stop.
$directedContract=Join-Path $PSScriptRoot 'rime-pime-directed-stop-contract.ps1'
if(Test-Path -LiteralPath $directedContract -PathType Leaf){. $directedContract}
$targetUserContract=Join-Path $PSScriptRoot 'rime-pime-target-user.ps1'
if(-not (Test-Path -LiteralPath $targetUserContract -PathType Leaf)){throw 'Rime/PIME target-user contract is unavailable.'}
. $targetUserContract
$script:YimePimeTextServiceClsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$script:YimePimeProfileGuid='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'
$script:YimePimeBaseCategoryGuids=@(
    '{34745C63-B2F0-4784-8B67-5E12C8701A31}', # TIP keyboard
    '{046B8C80-1647-40F7-9B21-B93B81AABC1B}', # display attribute provider
    '{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}', # input-mode compartment
    '{CCF05DD7-4A87-11D7-A6E2-00065B84435C}'  # UI element enabled
)
$script:YimePimeWindows8CategoryGuids=@(
    '{13A016DF-560B-46CD-947A-4C3AF1E0E35D}', # immersive support
    '{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}'  # system-tray support
)
function Get-YimePimeCurrentSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Assert-YimePimeTargetSid([string]$TargetUserSid,[switch]$RequireExplicit) {
    $current=Get-YimePimeCurrentSid
    if ([string]::IsNullOrWhiteSpace($TargetUserSid)) {
        if($RequireExplicit){throw 'Rime/PIME mutating maintenance requires an explicit initiating user SID.'}
        $TargetUserSid=$current
    }
    $TargetUserSid=Assert-YimePimeSidValue $TargetUserSid
    if ($TargetUserSid -cne $current) {
        throw 'Rime/PIME maintenance must use the same explicit Windows user SID; no cross-user stop is allowed.'
    }
    return $TargetUserSid
}

function Assert-YimePimePlainPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or
        $Path -match '[/<>|"?*]|(^|\\)\.\.?($|\\)|[. ]($|\\)' -or $Path.Substring(2).Contains(':')) {
        throw 'Rime/PIME requires a canonical local absolute path without ADS, devices or dot segments.'
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full.Length -le 3) { throw 'A volume root is not a product directory.' }
    foreach($part in $full.Substring(3).Split('\')) {
        if(-not $part -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Ambiguous device path rejected.' }
    }
    $cursor=$full
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Indirect maintenance path rejected.' }
        }
        $cursor=Split-Path -Parent $cursor
    }
    return $full
}

function Assert-YimePimeNoReparseTree([string]$Root) {
    $pending=[Collections.Generic.Stack[string]]::new(); $pending.Push($Root)
    while($pending.Count) {
        foreach($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Product tree contains an indirect path; no maintenance permitted.' }
            if($item.PSIsContainer){$pending.Push($item.FullName)}
        }
    }
}

function Assert-YimePimeOwnedRoot {
    param([Parameter(Mandatory)][string]$Root,[switch]$AllowNew,[switch]$AllowAbsent)
    $full=Assert-YimePimePlainPath $Root
    foreach($name in @('Windows','System','SystemX86','ProgramFiles','ProgramFilesX86','CommonProgramFiles','CommonProgramFilesX86',
        'UserProfile','ApplicationData','LocalApplicationData','CommonApplicationData','Desktop','MyDocuments','Programs','CommonPrograms')) {
        $broad=[Environment]::GetFolderPath([Environment+SpecialFolder]::$name)
        if($broad -and $full -ieq $broad.TrimEnd('\')) { throw 'A shared system/user directory is not a product root.' }
    }
    if($full -match '(?i)(^|\\)(YimeCore Experimental Trial|YimeCore Recovery Archives|YimeCore Isolated Fixtures)($|\\)') {
        throw 'Another product owns the requested root.'
    }
    if(-not (Test-Path -LiteralPath $full)) {
        if(-not ($AllowNew -or $AllowAbsent)){throw 'Required Rime/PIME installation is absent.'}
        return [pscustomobject]@{path=$full;exists=$false;identity='absent';marker_sha256=$null}
    }
    if(-not (Get-Item -LiteralPath $full -Force).PSIsContainer){throw 'Product root is not a directory.'}
    Assert-YimePimeNoReparseTree $full
    $children=@(Get-ChildItem -LiteralPath $full -Force)
    if($children.Count -eq 0 -and $AllowNew) {
        return [pscustomobject]@{path=$full;exists=$true;identity='new-empty';marker_sha256=$null}
    }
    if((Test-Path -LiteralPath (Join-Path $full 'local-product.json')) -or (Test-Path -LiteralPath (Join-Path $full 'bin\YimeBroker.exe'))) {
        throw 'YimeCore payload cannot be treated as a Rime/PIME install.'
    }
    $marker=Join-Path $full 'go-backend\input_methods\yime\ime.json'
    if(-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Item -LiteralPath $marker).Length -gt 16384 -or
        -not (Test-Path -LiteralPath (Join-Path $full 'PIMELauncher.exe') -PathType Leaf)) {
        throw 'Unknown or incomplete root: verify/repair this installation separately; no automatic overwrite or cleanup is permitted.'
    }
    $profile=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$profile.guid -ine '{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}') { throw 'Rime/PIME product marker has a foreign profile.' }
    return [pscustomobject]@{path=$full;exists=$true;identity='rime-pime-yime-profile';marker_sha256=(Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash}
}

function Assert-YimePimeArchitectureSet([string[]]$Architectures) {
    $normalized=@($Architectures | ForEach-Object {
        if($null -eq $_){''}else{([string]$_).Trim().ToLowerInvariant()}
    } | Where-Object {$_})
    if($normalized.Count -ne 2 -or @($normalized|Select-Object -Unique).Count -ne 2 -or
        $normalized -notcontains 'x86' -or
        @($normalized|Where-Object{$_ -in @('x64','arm64')}).Count -ne 1 -or
        @($normalized|Where-Object{$_ -notin @('x64','x86','arm64')}).Count) {
        throw 'Rime/PIME registration requires x86 plus exactly one native architecture (x64 or arm64).'
    }
    return @($normalized|Sort-Object)
}

function New-YimePimeExpectedRegistrationRecord {
    param([string]$Id,[ValidateSet('Registry32','Registry64','Shared')][string]$View,
        [string]$Key,[AllowEmptyString()][string]$Name,
        [string]$ValueKind,[string]$Value,[string]$Hive='LocalMachine')
    return [pscustomobject][ordered]@{
        id=$Id;hive=$Hive;view=$View;key=$Key;name=$Name
        value_kind=$ValueKind;value=$Value
    }
}

function Get-YimePimeExpectedProfileIconIndex {
    param([version]$WindowsVersion=[Environment]::OSVersion.Version)
    # Keep this threshold identical to DllEntry.cpp's IsWindows8OrGreater()
    # branch: classic icon 0 on Windows 7, Windows 8+ icon 1 otherwise.
    if($WindowsVersion -ge [version]'6.2'){return [uint32]1}
    return [uint32]0
}

function Get-YimePimeExpectedCategoryGuids {
    param([version]$WindowsVersion=[Environment]::OSVersion.Version)
    $result=@($script:YimePimeBaseCategoryGuids)
    if($WindowsVersion -ge [version]'6.2'){$result+=@($script:YimePimeWindows8CategoryGuids)}
    return $result
}

function Get-YimePimeExpectedRegistrationRecords {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures,[switch]$OmitTargetUserEnable)
    $root=Assert-YimePimePlainPath $InstallRoot
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    $comClassKey="SOFTWARE\Classes\CLSID\$script:YimePimeTextServiceClsid"
    $comKey="$comClassKey\InprocServer32"
    $machineProfileKey="SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid\LanguageProfile\0x00000804\$script:YimePimeProfileGuid"
    $profileIconIndex=[string](Get-YimePimeExpectedProfileIconIndex)
    # Windows PowerShell 5.1 reads UTF-8-without-BOM scripts through the active
    # ANSI code page. Construct this registry value from code points so the
    # embedded helper remains invariant on every supported system locale.
    $profileDescription=-join @([char]0x97F3,[char]0x5143)
    $records=[Collections.Generic.List[object]]::new()
    foreach($architecture in $architectureSet) {
        $view=if($architecture -eq 'x86'){'Registry32'}else{'Registry64'}
        $records.Add((New-YimePimeExpectedRegistrationRecord "com-$architecture-display-name" $view $comClassKey '' 'String' 'PIMETextService'))
        $records.Add((New-YimePimeExpectedRegistrationRecord "com-$architecture-path" $view $comKey '' 'String' (Join-Path $root "$architecture\PIMETextService.dll")))
        $records.Add((New-YimePimeExpectedRegistrationRecord "com-$architecture-threading" $view $comKey 'ThreadingModel' 'String' 'Apartment'))
    }
    # HKLM\SOFTWARE\Microsoft\CTF\TIP is a WOW64 shared key. The native
    # architecture owns one physical TSF profile/category set; x86 contributes
    # only its redirected COM server registration.
    $records.Add((New-YimePimeExpectedRegistrationRecord 'machine-tip-enable' 'Shared' `
        "SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid" 'Enable' 'String' '1'))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'machine-profile-description' 'Shared' $machineProfileKey 'Description' 'String' $profileDescription))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'machine-profile-icon' 'Shared' $machineProfileKey 'IconFile' 'String' (Join-Path $root 'go-backend\input_methods\yime\icon.ico')))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'machine-profile-icon-index' 'Shared' $machineProfileKey 'IconIndex' 'DWord' $profileIconIndex))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'product-install-root' 'Registry64' 'SOFTWARE\YIME' '' 'String' $root))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'run-command' 'Registry64' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'PIMELauncher' 'String' ('"'+(Join-Path $root 'PIMELauncher.exe')+'"')))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'uninstall-command' 'Registry64' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME' 'UninstallString' 'String' ('"'+(Join-Path $root 'Uninstall.exe')+'"')))
    $records.Add((New-YimePimeExpectedRegistrationRecord 'uninstall-location' 'Registry64' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME' 'InstallLocation' 'String' $root))
    if(-not $OmitTargetUserEnable) {
        $targetProfileKey="$sid\SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid\LanguageProfile\0x00000804\$script:YimePimeProfileGuid"
        $records.Add((New-YimePimeExpectedRegistrationRecord 'target-user-profile-enable' 'Shared' `
            $targetProfileKey 'Enable' 'DWord' '1' 'Users'))
    }
    return $records.ToArray()
}

function Convert-YimePimeSystemRegistryCoordinate {
    param([Parameter(Mandatory)][string]$Hive,[Parameter(Mandatory)][string]$View,
        [Parameter(Mandatory)][string]$Key)
    if($Hive -notin @('LocalMachine','Users') -or $View -notin @('Registry32','Registry64','Shared') -or
        [string]::IsNullOrWhiteSpace($Key) -or $Key -match '^[\\/]|/|(^|\\)\.\.?($|\\)') {
        throw 'Unsupported or ambiguous system registry coordinate.'
    }
    $providerHive=if($Hive -eq 'LocalMachine'){[uint32]2147483650}else{[uint32]2147483651}
    $providerArchitecture=if($View -eq 'Registry32'){32}else{64}
    # Never hard-code the reserved physical redirector implementation path. The WMI
    # Registry Provider selects redirected views through its documented context;
    # Shared keys keep the same logical coordinate in either provider.
    return [pscustomobject][ordered]@{
        hive=$providerHive;key=$Key;view=$View
        provider_architecture=$providerArchitecture;required_architecture=$true
    }
}

function Invoke-YimePimeStdRegProvMethod {
    param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][hashtable]$Arguments,
        [Parameter(Mandatory)][ValidateSet(32,64)][int]$ProviderArchitecture)
    $context=$null;$locator=$null;$services=$null;$provider=$null;$metadata=$null;$input=$null;$output=$null
    try {
        $context=New-Object -ComObject WbemScripting.SWbemNamedValueSet
        $context.Add('__ProviderArchitecture',$ProviderArchitecture)
        $context.Add('__RequiredArchitecture',$true)
        $locator=New-Object -ComObject WbemScripting.SWbemLocator
        $services=$locator.ConnectServer('.', 'root\default', '', '', '', '', 0, $context)
        $provider=$services.Get('StdRegProv')
        $metadata=$provider.Methods_.Item($Method)
        $input=$metadata.InParameters.SpawnInstance_()
        foreach($entry in $Arguments.GetEnumerator()) {
            $input.Properties_.Item([string]$entry.Key).Value=$entry.Value
        }
        $output=$provider.ExecMethod_($Method,$input,0,$context)
        $copy=[ordered]@{}
        foreach($property in $output.Properties_) {$copy[[string]$property.Name]=$property.Value}
        return [pscustomobject]$copy
    } finally {
        foreach($item in @($output,$input,$metadata,$provider,$services,$locator,$context)) {
            if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)) {
                $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)
            }
        }
    }
}

function Invoke-YimePimeSystemRegistryMethod {
    param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][uint32]$Hive,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][ValidateSet(32,64)][int]$ProviderArchitecture,
        [hashtable]$Values=@{})
    $arguments=@{hDefKey=$Hive;sSubKeyName=$Key}
    foreach($entry in $Values.GetEnumerator()){$arguments[$entry.Key]=$entry.Value}
    $result=Invoke-YimePimeStdRegProvMethod -Method $Method -Arguments $arguments `
        -ProviderArchitecture $ProviderArchitecture
    if($null -eq $result -or $null -eq $result.ReturnValue -or [int]$result.ReturnValue -notin @(0,2)) {
        $code=if($null -eq $result){'null'}else{[string]$result.ReturnValue}
        throw "System registry $Method failed ($code); process-view fallback is forbidden."
    }
    return $result
}

function Get-YimePimeSystemRegistryValueRecord($Expected) {
    $coordinate=Convert-YimePimeSystemRegistryCoordinate -Hive ([string]$Expected.hive) `
        -View ([string]$Expected.view) -Key ([string]$Expected.key)
    $record=[ordered]@{
        id=[string]$Expected.id;hive=[string]$Expected.hive;view=[string]$Expected.view
        key=[string]$Expected.key;name=[string]$Expected.name;exists=$false
        value_kind=$null;value=$null;reader='StdRegProv'
    }
    $values=Invoke-YimePimeSystemRegistryMethod -Method EnumValues -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    if([int]$values.ReturnValue -eq 2){return [pscustomobject]$record}
    $names=@($values.sNames)
    $types=@($values.Types)
    if($names.Count -ne $types.Count){throw 'System registry value names/types are inconsistent.'}
    $index=-1
    for($candidate=0;$candidate -lt $names.Count;$candidate++) {
        if([string]::Equals([string]$names[$candidate],[string]$Expected.name,[StringComparison]::Ordinal)) {
            $index=$candidate;break
        }
    }
    if($index -lt 0){return [pscustomobject]$record}
    $record.exists=$true
    $kind=[int]$types[$index]
    $record.value_kind=[string]([Microsoft.Win32.RegistryValueKind]$kind)
    $method=switch($kind){1{'GetStringValue'}4{'GetDWORDValue'}default{$null}}
    if($null -eq $method){return [pscustomobject]$record}
    $read=Invoke-YimePimeSystemRegistryMethod -Method $method -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture -Values @{sValueName=[string]$Expected.name}
    if([int]$read.ReturnValue -eq 2){$record.exists=$false;return [pscustomobject]$record}
    $record.value=[string]$(if($kind -eq 1){$read.sValue}else{$read.uValue})
    return [pscustomobject]$record
}

function Get-YimePimeRegistrationValueRecord($Expected) {
    return Get-YimePimeSystemRegistryValueRecord $Expected
}

function Test-YimePimeSystemRegistryKeyExists {
    param([Parameter(Mandatory)][string]$Hive,[Parameter(Mandatory)][string]$View,
        [Parameter(Mandatory)][string]$Key)
    $coordinate=Convert-YimePimeSystemRegistryCoordinate $Hive $View $Key
    $values=Invoke-YimePimeSystemRegistryMethod -Method EnumValues -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    return [int]$values.ReturnValue -eq 0
}

function Test-YimePimeSystemRegistryValueExists {
    param([Parameter(Mandatory)][string]$Hive,[Parameter(Mandatory)][string]$View,
        [Parameter(Mandatory)][string]$Key,[AllowEmptyString()][string]$Name)
    $coordinate=Convert-YimePimeSystemRegistryCoordinate $Hive $View $Key
    $values=Invoke-YimePimeSystemRegistryMethod -Method EnumValues -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    if([int]$values.ReturnValue -eq 2){return $false}
    foreach($candidate in @($values.sNames)) {
        if([string]::Equals([string]$candidate,$Name,[StringComparison]::Ordinal)){return $true}
    }
    return $false
}

function Get-YimePimeSystemRegistryKeyShape {
    param([Parameter(Mandatory)][string]$Hive,[Parameter(Mandatory)][string]$View,
        [Parameter(Mandatory)][string]$Key)
    $coordinate=Convert-YimePimeSystemRegistryCoordinate $Hive $View $Key
    $values=Invoke-YimePimeSystemRegistryMethod -Method EnumValues -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    $children=Invoke-YimePimeSystemRegistryMethod -Method EnumKey -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    if([int]$values.ReturnValue -eq 2 -and [int]$children.ReturnValue -eq 2) {
        return [pscustomobject][ordered]@{exists=$false;value_names=@();value_types=@();subkey_names=@()}
    }
    if([int]$values.ReturnValue -eq 2 -or [int]$children.ReturnValue -eq 2) {
        throw 'System registry key shape changed during closed-set verification.'
    }
    $names=@($values.sNames);$types=@($values.Types)
    if($names.Count -ne $types.Count){throw 'System registry key value names/types are inconsistent.'}
    return [pscustomobject][ordered]@{
        exists=$true;value_names=$names;value_types=$types;subkey_names=@($children.sNames)
    }
}

function Assert-YimePimeExactRegistryKeyShape {
    param([Parameter(Mandatory)][string]$Hive,[Parameter(Mandatory)][string]$View,
        [Parameter(Mandatory)][string]$Key,[string[]]$ValueNames=@(),[string[]]$SubKeyNames=@(),
        [switch]$AllowAbsent)
    $shape=Get-YimePimeSystemRegistryKeyShape -Hive $Hive -View $View -Key $Key
    if(-not $shape.exists) {
        if($AllowAbsent){return $shape}
        throw "Required owned registry key is absent: $Hive\$Key"
    }
    foreach($pair in @(
            [pscustomobject]@{label='value';actual=@($shape.value_names);expected=@($ValueNames)},
            [pscustomobject]@{label='subkey';actual=@($shape.subkey_names);expected=@($SubKeyNames)})) {
        $actual=@($pair.actual|ForEach-Object{[string]$_}|Sort-Object -Unique)
        $expected=@($pair.expected|ForEach-Object{[string]$_}|Sort-Object -Unique)
        if($actual.Count -ne @($pair.actual).Count -or $expected.Count -ne @($pair.expected).Count -or
            $actual.Count -ne $expected.Count -or (Compare-Object $expected $actual -SyncWindow 0)) {
            throw "Owned registry $($pair.label) set is not closed: $Hive\$Key"
        }
    }
    return $shape
}

function Assert-YimePimeRegistrationTreesClosed {
    param([Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures,[switch]$OmitTargetUserEnable)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    $comRoot="SOFTWARE\Classes\CLSID\$script:YimePimeTextServiceClsid"
    foreach($architecture in $architectureSet) {
        $view=if($architecture -eq 'x86'){'Registry32'}else{'Registry64'}
        Assert-YimePimeExactRegistryKeyShape 'LocalMachine' $view $comRoot @('') @('InprocServer32') | Out-Null
        Assert-YimePimeExactRegistryKeyShape 'LocalMachine' $view "$comRoot\InprocServer32" `
            @('','ThreadingModel') @() | Out-Null
    }
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Registry64' 'SOFTWARE\YIME' @('') @() | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Registry64' `
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME' `
        @('DisplayName','UninstallString','InstallLocation','Publisher','DisplayVersion','URLInfoAbout') @() | Out-Null
    $tipRoot="SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    $languageRoot="$tipRoot\LanguageProfile"
    $langRoot="$languageRoot\0x00000804"
    $profileRoot="$langRoot\$script:YimePimeProfileGuid"
    $categoryGuids=@(Get-YimePimeExpectedCategoryGuids)
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $tipRoot @('Enable') @('Category','LanguageProfile') | Out-Null
    $categoryRoot="$tipRoot\Category"
    $categoryByCategory="$categoryRoot\Category"
    $categoryByItem="$categoryRoot\Item"
    $itemRoot="$categoryByItem\$script:YimePimeTextServiceClsid"
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $categoryRoot @() @('Category','Item') | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $categoryByCategory @() $categoryGuids | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $categoryByItem @() @($script:YimePimeTextServiceClsid) | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $itemRoot @() $categoryGuids | Out-Null
    foreach($categoryGuid in $categoryGuids) {
        Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' `
            "$categoryByCategory\$categoryGuid" @() @($script:YimePimeTextServiceClsid) | Out-Null
        Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' `
            "$categoryByCategory\$categoryGuid\$script:YimePimeTextServiceClsid" @() @() | Out-Null
        Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' `
            "$itemRoot\$categoryGuid" @() @() | Out-Null
    }
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $languageRoot @() @('0x00000804') | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $langRoot @() @($script:YimePimeProfileGuid) | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'LocalMachine' 'Shared' $profileRoot `
        @('Description','IconFile','IconIndex') @() | Out-Null

    Assert-YimePimeTargetUserTipTreeClosed -TargetUserSid $sid `
        -AllowAbsent:$OmitTargetUserEnable -RequireEnable:(-not $OmitTargetUserEnable) | Out-Null
    return [pscustomobject][ordered]@{
        passed=$true;architectures=$architectureSet;machine_tsf_view='Shared'
        com_and_tip_trees_closed=$true;actual_registry_mutation_executed=$false
    }
}

function Assert-YimePimeTargetUserTipTreeClosed {
    param([Parameter(Mandatory)][string]$TargetUserSid,[switch]$AllowAbsent,[switch]$RequireEnable)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $userTipRoot="$sid\SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    $userShape=Assert-YimePimeExactRegistryKeyShape 'Users' 'Shared' $userTipRoot @() @('LanguageProfile') `
        -AllowAbsent:$AllowAbsent
    if(-not $userShape.exists) {
        if($RequireEnable){throw 'Required target-user TIP tree is absent.'}
        return [pscustomobject][ordered]@{passed=$true;exists=$false;tree_closed=$true}
    }
    $userLanguageRoot="$userTipRoot\LanguageProfile"
    $userLangRoot="$userLanguageRoot\0x00000804"
    $userProfileRoot="$userLangRoot\$script:YimePimeProfileGuid"
    Assert-YimePimeExactRegistryKeyShape 'Users' 'Shared' $userLanguageRoot @() @('0x00000804') | Out-Null
    Assert-YimePimeExactRegistryKeyShape 'Users' 'Shared' $userLangRoot @() @($script:YimePimeProfileGuid) | Out-Null
    $leaf=Get-YimePimeSystemRegistryKeyShape 'Users' 'Shared' $userProfileRoot
    if(-not $leaf.exists -or @($leaf.subkey_names).Count -ne 0 -or
        @($leaf.value_names|Where-Object{[string]$_ -cne 'Enable'}).Count -ne 0 -or
        ($RequireEnable -and
            (@($leaf.value_names).Count -ne 1 -or [string]$leaf.value_names[0] -cne 'Enable'))) {
        throw 'Target-user TIP profile tree is absent, ambiguous, or contains foreign state.'
    }
    if(@($leaf.value_names).Count -eq 1) {
        $enableIndex=[Array]::IndexOf([object[]]@($leaf.value_names),[object]'Enable')
        if($enableIndex -lt 0 -or [int]$leaf.value_types[$enableIndex] -ne 4) {
            throw 'Target-user TIP Enable must remain a REG_DWORD.'
        }
        $expected=New-YimePimeExpectedRegistrationRecord 'target-user-profile-enable-shape' 'Shared' `
            $userProfileRoot 'Enable' 'DWord' '0' 'Users'
        $actual=Get-YimePimeSystemRegistryValueRecord $expected
        if(-not $actual.exists -or $actual.value_kind -cne 'DWord' -or
            [string]$actual.value -notin @('0','1')) {
            throw 'Target-user TIP Enable must be an exact DWORD 0 or 1.'
        }
    }
    return [pscustomobject][ordered]@{passed=$true;exists=$true;tree_closed=$true}
}

function Test-YimePimeProfileRegistryReference {
    param([AllowEmptyString()][string]$Name,$Value)
    $exactTokens=@(
        $script:YimePimeTextServiceClsid,
        ($script:YimePimeTextServiceClsid+$script:YimePimeProfileGuid),
        ('0x0804:'+$script:YimePimeTextServiceClsid),
        ('0x0804:'+$script:YimePimeTextServiceClsid+$script:YimePimeProfileGuid)
    )
    $found=$false
    foreach($item in @($Name)+@($Value)) {
        $text=[string]$item
        if([string]::IsNullOrEmpty($text)){continue}
        if(@($exactTokens|Where-Object{[string]::Equals($_,$text,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) {
            $found=$true
        } elseif($text.IndexOf($script:YimePimeTextServiceClsid,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw 'Ambiguous mixed Control Panel profile reference; cleanup is forbidden.'
        }
    }
    return $found
}

function Test-YimePimeTargetUserControlPanelReference {
    param([Parameter(Mandatory)][string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $root="$sid\Control Panel\International\User Profile"
    $coordinate=Convert-YimePimeSystemRegistryCoordinate 'Users' 'Shared' $root
    $children=Invoke-YimePimeSystemRegistryMethod -Method EnumKey -Hive $coordinate.hive -Key $coordinate.key `
        -ProviderArchitecture $coordinate.provider_architecture
    if([int]$children.ReturnValue -eq 2){return $false}
    $paths=@($root)+@($children.sNames|ForEach-Object{$root+'\'+[string]$_})
    foreach($path in $paths) {
        $current=Convert-YimePimeSystemRegistryCoordinate 'Users' 'Shared' $path
        $values=Invoke-YimePimeSystemRegistryMethod -Method EnumValues -Hive $current.hive -Key $current.key `
            -ProviderArchitecture $current.provider_architecture
        if([int]$values.ReturnValue -eq 2){continue}
        $names=@($values.sNames);$types=@($values.Types)
        if($names.Count -ne $types.Count){throw 'Target-user profile registry names/types are inconsistent.'}
        for($index=0;$index -lt $names.Count;$index++) {
            $name=[string]$names[$index]
            if(Test-YimePimeProfileRegistryReference -Name $name -Value $null){return $true}
            $kind=[int]$types[$index]
            $method=switch($kind){1{'GetStringValue'}2{'GetExpandedStringValue'}7{'GetMultiStringValue'}default{$null}}
            if($null -eq $method){continue}
            $read=Invoke-YimePimeSystemRegistryMethod -Method $method -Hive $current.hive -Key $current.key `
                -ProviderArchitecture $current.provider_architecture -Values @{sValueName=$name}
            if([int]$read.ReturnValue -eq 2){throw 'Target-user profile registry changed during verification.'}
            if(Test-YimePimeProfileRegistryReference -Name '' -Value @($read.sValue)){return $true}
        }
    }
    return $false
}

function Assert-YimePimeTargetUserComShadowsAbsent {
    param([Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    foreach($architecture in $architectureSet) {
        $view=if($architecture -eq 'x86'){'Registry32'}else{'Registry64'}
        $key="$sid\SOFTWARE\Classes\CLSID\$script:YimePimeTextServiceClsid"
        if(Test-YimePimeSystemRegistryKeyExists 'Users' $view $key) {
            throw "Target-user COM shadow exists for Rime/PIME $architecture; it is foreign state and was not removed."
        }
    }
    return [pscustomobject][ordered]@{
        passed=$true;target_user_sid=$sid;architectures=$architectureSet
        user_com_shadows_absent=$true;registry_reader='StdRegProv'
        actual_registry_mutation_executed=$false
    }
}

function Assert-YimePimeNoLegacyMarkers {
    foreach($view in @('Registry64','Registry32')) {
        foreach($key in @('SOFTWARE\PIME','SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PIME')) {
            if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' $view $key) {
                throw "Historical PIME registration exists in $view at HKEY_LOCAL_MACHINE\$key; explicit migration is required."
            }
        }
    }
    return [pscustomobject][ordered]@{
        passed=$true;legacy_marker_keys_absent=$true;registry_reader='StdRegProv'
        actual_registry_mutation_executed=$false
    }
}

function Assert-YimePimeNoWrongViewProductMarkers {
    foreach($key in @('SOFTWARE\YIME','SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME')) {
        if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' 'Registry32' $key) {
            throw "Rime/PIME product registration exists in the forbidden Registry32 view: $key"
        }
    }
    if(Test-YimePimeSystemRegistryValueExists 'LocalMachine' 'Registry32' `
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'PIMELauncher') {
        throw 'Rime/PIME Run/PIMELauncher exists in the forbidden Registry32 view.'
    }
    return [pscustomobject][ordered]@{
        passed=$true;wrong_view_product_markers_absent=$true;registry_reader='StdRegProv'
        actual_registry_mutation_executed=$false
    }
}

function Get-YimePimeRegistrationSnapshot {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures,[switch]$OmitTargetUserEnable)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $owned=Assert-YimePimeOwnedRoot -Root $InstallRoot
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    $expected=@(Get-YimePimeExpectedRegistrationRecords -InstallRoot $owned.path -TargetUserSid $sid `
        -Architectures $architectureSet -OmitTargetUserEnable:$OmitTargetUserEnable)
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-registration-snapshot-v1'
        install_root=$owned.path
        target_user_sid=$sid
        target_user_enable_required=(-not $OmitTargetUserEnable)
        architectures=$architectureSet
        records=@($expected|ForEach-Object{Get-YimePimeRegistrationValueRecord $_})
    }
}

function Assert-YimePimeRegistrationSnapshot {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string[]]$Architectures,
        [switch]$OmitTargetUserEnable)
    if($null -eq $Snapshot -or [string]$Snapshot.schema_version -cne 'yime-pime-registration-snapshot-v1') {
        throw 'Unknown Rime/PIME registration snapshot.'
    }
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $owned=Assert-YimePimeOwnedRoot -Root $InstallRoot
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    if((Assert-YimePimePlainPath ([string]$Snapshot.install_root)) -ine $owned.path -or
        [string]$Snapshot.target_user_sid -cne $sid -or
        [bool]$Snapshot.target_user_enable_required -ne (-not $OmitTargetUserEnable)) {
        throw 'Registration snapshot is not bound to the selected root and initiating SID.'
    }
    $snapshotArchitectures=@(Assert-YimePimeArchitectureSet @($Snapshot.architectures))
    if(Compare-Object $architectureSet $snapshotArchitectures) { throw 'Registration snapshot architecture set differs from the selected package.' }
    $expected=@(Get-YimePimeExpectedRegistrationRecords -InstallRoot $owned.path -TargetUserSid $sid `
        -Architectures $architectureSet -OmitTargetUserEnable:$OmitTargetUserEnable)
    $actual=@($Snapshot.records)
    if($actual.Count -ne $expected.Count) { throw 'Registration snapshot record set is incomplete or contains foreign entries.' }
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($record in $actual) {
        if($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.id) -or -not $ids.Add([string]$record.id)) {
            throw 'Registration snapshot record identity is missing or duplicated.'
        }
    }
    foreach($wanted in $expected) {
        $matches=@($actual|Where-Object{[string]$_.id -ceq [string]$wanted.id})
        if($matches.Count -ne 1){throw "Registration value is missing: $($wanted.id)"}
        $record=$matches[0]
        foreach($field in @('hive','view','key','name')) {
            if([string]$record.$field -cne [string]$wanted.$field){throw "Registration coordinate differs: $($wanted.id)"}
        }
        if(-not [bool]$record.exists -or [string]$record.value_kind -cne [string]$wanted.value_kind -or
            -not [string]::Equals([string]$record.value,[string]$wanted.value,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Registration value is absent, mistyped, or owned by another root: $($wanted.id)"
        }
    }
    return [pscustomobject][ordered]@{
        passed=$true;test_level='exact-registration-snapshot-contract';install_root=$owned.path
        target_user_sid=$sid;architectures=$architectureSet;records_verified=$expected.Count
        actual_registry_mutation_executed=$false;default_input_method_changed=$false
    }
}

function Assert-YimePimeRegistrationOwnedByRoot {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures,[switch]$OmitTargetUserEnable)
    Assert-YimePimeNoLegacyMarkers | Out-Null
    Assert-YimePimeNoWrongViewProductMarkers | Out-Null
    $snapshot=Get-YimePimeRegistrationSnapshot -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid `
        -Architectures $Architectures -OmitTargetUserEnable:$OmitTargetUserEnable
    $result=Assert-YimePimeRegistrationSnapshot -Snapshot $snapshot -InstallRoot $InstallRoot `
        -TargetUserSid $TargetUserSid -Architectures $Architectures `
        -OmitTargetUserEnable:$OmitTargetUserEnable
    Assert-YimePimeRegistrationTreesClosed -TargetUserSid $TargetUserSid `
        -Architectures $Architectures -OmitTargetUserEnable:$OmitTargetUserEnable | Out-Null
    Assert-YimePimeTargetUserComShadowsAbsent -TargetUserSid $TargetUserSid `
        -Architectures $Architectures | Out-Null
    return $result
}

function Assert-YimePimeNativeRegistrationAbsent {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures)
    $owned=Assert-YimePimeOwnedRoot -Root $InstallRoot
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    $comKey="SOFTWARE\Classes\CLSID\$script:YimePimeTextServiceClsid"
    $machineTipKey="SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    foreach($architecture in $architectureSet) {
        $view=if($architecture -eq 'x86'){'Registry32'}else{'Registry64'}
        if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' $view $comKey) {
            throw "Rime/PIME COM registration still exists for $architecture."
        }
    }
    if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' 'Shared' $machineTipKey) {
        throw 'Rime/PIME shared machine TIP registration still exists.'
    }
    Assert-YimePimeTargetUserComShadowsAbsent -TargetUserSid $sid `
        -Architectures $architectureSet | Out-Null
    return [pscustomobject][ordered]@{
        passed=$true;install_root=$owned.path;target_user_sid=$sid
        architectures=$architectureSet;com_registration_absent=$true
        machine_tip_registration_absent=$true
        actual_registry_mutation_executed=$false
    }
}

function Assert-YimePimeRegistrationVacant {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string[]]$Architectures)
    $owned=Assert-YimePimeOwnedRoot -Root $InstallRoot -AllowAbsent -AllowNew
    if([string]$owned.identity -notin @('absent','new-empty')) {
        throw 'Rime/PIME fresh-install root is not empty; orphan payload requires recovery instead of overwrite.'
    }
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $architectureSet=@(Assert-YimePimeArchitectureSet $Architectures)
    Assert-YimePimeNoLegacyMarkers | Out-Null
    Assert-YimePimeNoWrongViewProductMarkers | Out-Null
    foreach($key in @('SOFTWARE\YIME','SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME')) {
        if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' 'Registry64' $key) {
            throw "Rime/PIME fresh-install registration is not vacant: HKEY_LOCAL_MACHINE\$key"
        }
    }
    if(Test-YimePimeSystemRegistryValueExists 'LocalMachine' 'Registry64' `
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'PIMELauncher') {
        throw 'Rime/PIME fresh-install registration is not vacant: Run/PIMELauncher.'
    }
    $comKey="SOFTWARE\Classes\CLSID\$script:YimePimeTextServiceClsid"
    $machineTipKey="SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    foreach($architecture in $architectureSet) {
        $view=if($architecture -eq 'x86'){'Registry32'}else{'Registry64'}
        if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' $view $comKey) {
            throw "Rime/PIME fresh-install COM registration is not vacant for $architecture."
        }
    }
    if(Test-YimePimeSystemRegistryKeyExists 'LocalMachine' 'Shared' $machineTipKey) {
        throw 'Rime/PIME fresh-install shared machine TIP registration is not vacant.'
    }
    Assert-YimePimeTargetUserComShadowsAbsent -TargetUserSid $sid `
        -Architectures $architectureSet | Out-Null
    $userTipKey="$sid\SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    if(Test-YimePimeSystemRegistryKeyExists 'Users' 'Shared' $userTipKey) {
        throw 'Rime/PIME fresh-install target-user TIP registration is not vacant.'
    }
    if(Test-YimePimeTargetUserControlPanelReference -TargetUserSid $sid) {
        throw 'Rime/PIME fresh-install target-user language list still references this CLSID.'
    }
    return [pscustomobject][ordered]@{
        passed=$true;install_root=$owned.path;target_user_sid=$sid
        architectures=$architectureSet;registration_vacant=$true
        registry_reader='StdRegProv';actual_registry_mutation_executed=$false
    }
}

function Remove-YimePimeTargetUserProfileValues {
    param([Parameter(Mandatory)][string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    # The product-specific TIP subtree is removed recursively only after its
    # complete shape is proven closed. Unknown values or children are foreign
    # state and must stop cleanup rather than being swept away.
    Assert-YimePimeTargetUserTipTreeClosed -TargetUserSid $sid -AllowAbsent | Out-Null
    $profileRoot=Get-YimePimeTargetUserRegistryPath -TargetUserSid $sid `
        -RelativePath 'Control Panel\International\User Profile'
    if(Test-Path -LiteralPath $profileRoot) {
        $paths=@($profileRoot)+@(Get-ChildItem -LiteralPath $profileRoot -ErrorAction Stop|ForEach-Object{$_.PSPath})
        foreach($path in $paths) {
            $key=Get-Item -LiteralPath $path -ErrorAction Stop
            $properties=Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach($property in $properties.PSObject.Properties) {
                if($property.Name -like 'PS*'){continue}
                $nameOwned=Test-YimePimeProfileRegistryReference -Name $property.Name -Value $null
                $kind=$key.GetValueKind($property.Name)
                if($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) {
                    $kept=[Collections.Generic.List[string]]::new()
                    $removed=0
                    foreach($item in @($property.Value)) {
                        if(Test-YimePimeProfileRegistryReference -Name '' -Value ([string]$item)) {$removed++}
                        else {$kept.Add([string]$item)}
                    }
                    if($nameOwned -and $kept.Count -gt 0) {
                        throw 'A product-named Control Panel value contains foreign entries; cleanup is forbidden.'
                    }
                    if($nameOwned -or $removed -gt 0) {
                        if($kept.Count -eq 0) {
                            Remove-ItemProperty -LiteralPath $path -Name $property.Name -ErrorAction Stop
                        } else {
                            Set-ItemProperty -LiteralPath $path -Name $property.Name `
                                -Value $kept.ToArray() -Type MultiString -ErrorAction Stop
                        }
                    }
                    continue
                }
                $valueOwned=Test-YimePimeProfileRegistryReference -Name '' -Value $property.Value
                if($nameOwned -or $valueOwned) {
                    if(-not $nameOwned -and $kind -notin @(
                            [Microsoft.Win32.RegistryValueKind]::String,
                            [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
                        throw 'An unsupported Control Panel value kind references this product; cleanup is forbidden.'
                    }
                    Remove-ItemProperty -LiteralPath $path -Name $property.Name -ErrorAction Stop
                }
            }
        }
    }
    $tipRoot=Get-YimePimeTargetUserRegistryPath -TargetUserSid $sid `
        -RelativePath "SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    if(Test-Path -LiteralPath $tipRoot) {
        Assert-YimePimeTargetUserTipTreeClosed -TargetUserSid $sid | Out-Null
        Remove-Item -LiteralPath $tipRoot -Recurse -Force -ErrorAction Stop
    }
}

function Assert-YimePimeTargetUserProfileAbsent {
    param([Parameter(Mandatory)][string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    $tipRoot="$sid\SOFTWARE\Microsoft\CTF\TIP\$script:YimePimeTextServiceClsid"
    if(Test-YimePimeSystemRegistryKeyExists 'Users' 'Shared' $tipRoot){
        throw 'Target-user Rime/PIME TIP subtree still exists.'
    }
    if(Test-YimePimeTargetUserControlPanelReference -TargetUserSid $sid){
        throw 'Target-user Control Panel profile value still references Rime/PIME.'
    }
    return [pscustomobject][ordered]@{
        passed=$true;target_user_sid=$sid;tip_subtree_absent=$true
        control_panel_profile_values_absent=$true;actual_registry_mutation_executed=$false
    }
}

function Get-YimePimeExecutablePaths([string]$Root) {
    foreach($relative in @('PIMELauncher.exe','go-backend\server.exe','go-backend\input-toolbar.exe','go-backend\yime-trainer.exe',
        'go-backend\tool-hub.exe','go-backend\settings-tool.exe','go-backend\diagnostics-tool.exe','go-backend\lexicon-manager.exe',
        'go-backend\reverse-lookup.exe','go-backend\system-lexicon-audit.exe','go-backend\lexicon-promotion-scan.exe',
        'go-backend\blocklist-manager.exe','go-backend\yime-layout-designer.exe',
        'go-backend\input_methods\yime\rime_deployer.exe','go-backend\input_methods\yime\rime_dict_manager.exe')) {
        Join-Path $Root $relative
    }
}

function Stop-YimePimeOwnedProcesses {
    param([Parameter(Mandatory)][string[]]$InstallRoots,[string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pathRoots=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $imageNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Validate ALL roots before admission. Absent peer products are not prerequisites.
    foreach($root in $InstallRoots) {
        $owned=Assert-YimePimeOwnedRoot -Root $root -AllowAbsent -AllowNew
        if($owned.identity -ceq 'rime-pime-yime-profile'){
            foreach($path in Get-YimePimeExecutablePaths $owned.path){
                $null=$paths.Add($path);$null=$imageNames.Add([IO.Path]::GetFileName($path));$pathRoots[$path]=$owned.path
            }
        }
    }
    $bound=[Collections.Generic.List[object]]::new()
    try {
        foreach($record in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            if(-not $record.ExecutablePath) {
                if($imageNames.Contains([string]$record.Name)){throw 'A relevant executable image path is unreadable; quiescence cannot be proved. Close or repair it separately.'}
                continue
            }
            if(-not $paths.Contains([string]$record.ExecutablePath)){continue}
            $process=Get-Process -Id ([int]$record.ProcessId) -ErrorAction Stop
            $bound.Add($process)
            # Bind the observed image and creation time before evaluating its SID.
            # This phase deliberately does not terminate even a proven owned process.
            $null=$process.Handle
            if($process.Path -ine [string]$record.ExecutablePath -or
                [Math]::Abs(($process.StartTime.ToUniversalTime()-([datetime]$record.CreationDate).ToUniversalTime()).TotalMilliseconds) -gt 1) {
                throw 'Process identity changed while binding maintenance target.'
            }
            $owner=Invoke-CimMethod -InputObject $record -MethodName GetOwnerSid -ErrorAction Stop
            if($owner.ReturnValue -ne 0 -or [string]$owner.Sid -cne $sid) { throw 'A target process belongs to another/unknown SID; close it separately.' }
        }
        if($bound.Count -gt 0) {
            $activeRoots=@($bound | ForEach-Object {$pathRoots[[string]$_.Path]} | Sort-Object -Unique)
            if($activeRoots.Count -ne 1){throw 'One maintenance transaction cannot stop processes from multiple product roots.'}
            if(-not (Get-Command Invoke-YimePimeDirectedStop -CommandType Function -ErrorAction SilentlyContinue)) {
                throw 'Directed stop contract is unavailable; no process was stopped.'
            }
            $result=Invoke-YimePimeDirectedStop -InstallRoot $activeRoots[0] -TargetUserSid $sid
            return [int]$result.stopped_count
        }
        return 0
    } finally {
        foreach($process in $bound){if($process -is [IDisposable]){$process.Dispose()}}
    }
}

function Invoke-YimePimeRequiredStopScript {
    param([Parameter(Mandatory)][string]$ScriptPath,[Parameter(Mandatory)][string[]]$InstallRoots,[string]$TargetUserSid)
    $sid=Assert-YimePimeTargetSid $TargetUserSid
    $script=Assert-YimePimePlainPath $ScriptPath
    if(-not (Test-Path -LiteralPath $script -PathType Leaf)){throw 'Required owned-process stop helper is unavailable; no unsafe fallback is permitted.'}
    & $script -InstallRoots $InstallRoots -TargetUserSid $sid -Quiet -Auto | Out-Host
    $result=$LASTEXITCODE
    if($result -notin @(0,2)){throw 'Owned-process preflight failed; no install/uninstall mutation is permitted.'}
    return $result
}

function Invoke-YimePimeMaintenanceGuard {
    param([ValidateSet('ValidateInstall','ValidateExisting','Stop','ValidateRegistration','ValidateRegistrationForRemoval','ValidateRegistrationVacant','CleanupTargetUserProfile','ValidateTargetUserProfileAbsent','ValidateNativeRegistrationAbsent')][string]$Action,
        [Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [string]$ArchitectureSet)
    $sid=Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit
    switch($Action) {
        'ValidateInstall' { Assert-YimePimeOwnedRoot -Root $InstallRoot -AllowNew | Out-Null }
        'ValidateExisting' { Assert-YimePimeOwnedRoot -Root $InstallRoot | Out-Null }
        'Stop' { Stop-YimePimeOwnedProcesses -InstallRoots @($InstallRoot) -TargetUserSid $sid | Out-Null }
        'ValidateRegistration' {
            $architectures=@($ArchitectureSet.Split(',',[StringSplitOptions]::RemoveEmptyEntries))
            Assert-YimePimeRegistrationOwnedByRoot -InstallRoot $InstallRoot -TargetUserSid $sid `
                -Architectures $architectures | Out-Null
        }
        'ValidateRegistrationForRemoval' {
            $architectures=@($ArchitectureSet.Split(',',[StringSplitOptions]::RemoveEmptyEntries))
            Assert-YimePimeRegistrationOwnedByRoot -InstallRoot $InstallRoot -TargetUserSid $sid `
                -Architectures $architectures -OmitTargetUserEnable | Out-Null
        }
        'ValidateRegistrationVacant' {
            $architectures=@($ArchitectureSet.Split(',',[StringSplitOptions]::RemoveEmptyEntries))
            Assert-YimePimeRegistrationVacant -InstallRoot $InstallRoot -TargetUserSid $sid `
                -Architectures $architectures | Out-Null
        }
        'CleanupTargetUserProfile' { Remove-YimePimeTargetUserProfileValues -TargetUserSid $sid }
        'ValidateTargetUserProfileAbsent' { Assert-YimePimeTargetUserProfileAbsent -TargetUserSid $sid | Out-Null }
        'ValidateNativeRegistrationAbsent' {
            $architectures=@($ArchitectureSet.Split(',',[StringSplitOptions]::RemoveEmptyEntries))
            Assert-YimePimeNativeRegistrationAbsent -InstallRoot $InstallRoot -TargetUserSid $sid `
                -Architectures $architectures | Out-Null
        }
    }
}
