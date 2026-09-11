# Actual fixed-identity registration provider for an explicitly admitted clean
# x64 target. Import defines functions only. The controller owns the durable
# transaction, package authentication, staging leases and mutation ordering.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -Scope Local
$script:CandidateProbe=$null
$script:CandidateChildType=$null
$script:CandidateClsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'
$script:CandidateProfile='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'

function Open-CandidateRegistrationContext($Request,[bool]$RequireElevated) {
    # Reject the daily-use host before opening approval, registry or product files.
    if([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|$)'){throw 'MYCOMPUTER daily-use target prohibited.'}
    if($Request.CoordinationHandle -eq [IntPtr]::Zero -or $Request.CoordinationHandle -eq [IntPtr]::new(-1)){throw 'Retained candidate coordination gate handle required.'}
    if($null -eq $script:CandidateProbe){$script:CandidateProbe=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -PassThru -Force}
    $leases=[Collections.Generic.List[object]]::new()
    try {
        $pair=& $script:CandidateProbe {
            param($request)
            Initialize-Dp1UNativeFacts
            $a=Open-Dp1UNativeArtifact $request.AuthorizationPath '' -Json
            try {
                $b=Open-Dp1UNativeArtifact $request.BoundaryPath '' -Json
                try {Assert-Dp1UNativeRequest $a.value $b.value $request.TrustedApprovalSha256 ([Environment]::MachineName) ([DateTime]::UtcNow)}
                catch{$b.stream.Dispose();throw}
                [pscustomobject]@{approval=$a;boundary=$b}
            }catch{$a.stream.Dispose();throw}
        } $Request
        $leases.Add($pair.approval.stream);$leases.Add($pair.boundary.stream)
        $a=$pair.approval.value;$b=$pair.boundary.value
        if($a.install_root -cne $Request.InstallRoot -or $a.initiating_sid -cne $Request.TargetUserSid){throw 'Provider root/SID differs from original approval.'}
        if($Request.PackageManifestSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Concrete package manifest SHA256 required.'}
        $current=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID);$leases.Add($current)
        if([Yime.Dp1UNative.Facts]::Architecture() -cne 'x64' -or [IntPtr]::Size -ne 8 -or $current.Sid -cne $a.initiating_sid){throw 'Native x64 same-SID provider required.'}
        if($current.PackageQuery -ne 15700 -or $current.Image -match '(?i)\\WindowsApps\\'){throw 'Packaged or unknown worker context prohibited.'}
        if($RequireElevated -and -not $current.Elevated){throw 'Registration writes require the approved elevated same-SID worker.'}
        $machine=Invoke-YimePimeSystemRegistryMethod GetStringValue 2147483650 'SOFTWARE\Microsoft\Cryptography' 64 @{sValueName='MachineGuid'}
        if($machine.ReturnValue -ne 0 -or [string]$machine.sValue -cne $a.target_machine_id){throw 'System-visible MachineGuid differs from original approval.'}
        Assert-YimePimePlainPath $Request.PackageRoot | Out-Null
        Assert-YimePimePlainPath $Request.InstallRoot | Out-Null
        # Full native Explorer ancestry/UAC parent binding is additionally checked
        # by the outer controller; a caller-supplied success Boolean is not used.
        $peer=Get-RimePimePeerProtectionSnapshot $b $a.initiating_sid
        Assert-YimePimeNoLegacyMarkers | Out-Null
        Assert-YimePimeNoWrongViewProductMarkers | Out-Null
        Assert-YimePimeTargetUserComShadowsAbsent -TargetUserSid $a.initiating_sid -Architectures @('x86','x64') | Out-Null
        return [pscustomobject]@{authorization=$a;boundary=$b;leases=$leases;peer_protection=$peer;request=$Request;current=$current}
    }catch{foreach($lease in $leases){$lease.Dispose()};throw}
}

function New-CandidateTree([string]$Id,[string]$Hive,[string]$View,[string]$Key,$Values,$Children) {
    [pscustomobject]@{id=$Id;hive=$Hive;view=$View;key=$Key;values=@($Values);children=@($Children)}
}
function New-CandidateValue([string]$Name,[string]$Kind,[string]$Value) {
    [pscustomobject]@{name=$Name;value_kind=$Kind;value=$Value}
}
function Get-CandidateRegistrationLayout($Context) {
    $r=$Context.request;$root=$r.InstallRoot;$sid=$r.TargetUserSid
    $result=[Collections.Generic.List[object]]::new()
    foreach($arch in @('x86','x64')) {
        $view=if($arch -ceq 'x86'){'Registry32'}else{'Registry64'};$key="SOFTWARE\Classes\CLSID\$script:CandidateClsid"
        $result.Add((New-CandidateTree "com-$arch" 'LocalMachine' $view $key @((New-CandidateValue '' 'String' 'PIMETextService')) @('InprocServer32')))
        $result.Add((New-CandidateTree "com-$arch-server" 'LocalMachine' $view "$key\InprocServer32" @((New-CandidateValue '' 'String' (Join-Path $root "$arch\PIMETextService.dll")),(New-CandidateValue 'ThreadingModel' 'String' 'Apartment')) @()))
    }
    $tip="SOFTWARE\Microsoft\CTF\TIP\$script:CandidateClsid";$cats=@(Get-YimePimeExpectedCategoryGuids)
    $result.Add((New-CandidateTree 'tip' 'LocalMachine' 'Shared' $tip @((New-CandidateValue 'Enable' 'String' '1')) @('Category','LanguageProfile')))
    foreach($item in @(
        @{id='categories';key="$tip\Category";children=@('Category','Item')},
        @{id='categories-by-category';key="$tip\Category\Category";children=$cats},
        @{id='categories-by-item';key="$tip\Category\Item";children=@($script:CandidateClsid)},
        @{id='category-item';key="$tip\Category\Item\$script:CandidateClsid";children=$cats},
        @{id='languages';key="$tip\LanguageProfile";children=@('0x00000804')},
        @{id='language';key="$tip\LanguageProfile\0x00000804";children=@($script:CandidateProfile)}
    )){$result.Add((New-CandidateTree $item.id 'LocalMachine' 'Shared' $item.key @() $item.children))}
    foreach($cat in $cats) {
        $result.Add((New-CandidateTree "category-$cat" 'LocalMachine' 'Shared' "$tip\Category\Category\$cat" @() @($script:CandidateClsid)))
        $result.Add((New-CandidateTree "category-service-$cat" 'LocalMachine' 'Shared' "$tip\Category\Category\$cat\$script:CandidateClsid" @() @()))
        $result.Add((New-CandidateTree "category-item-$cat" 'LocalMachine' 'Shared' "$tip\Category\Item\$script:CandidateClsid\$cat" @() @()))
    }
    $description=-join @([char]0x97F3,[char]0x5143)
    $result.Add((New-CandidateTree 'profile' 'LocalMachine' 'Shared' "$tip\LanguageProfile\0x00000804\$script:CandidateProfile" @(
        (New-CandidateValue 'Description' 'String' $description),
        (New-CandidateValue 'IconFile' 'String' (Join-Path $root 'go-backend\input_methods\yime\icon.ico')),
        (New-CandidateValue 'IconIndex' 'DWord' ([string](Get-YimePimeExpectedProfileIconIndex)))
    ) @()))
    $userTip="$sid\SOFTWARE\Microsoft\CTF\TIP\$script:CandidateClsid"
    foreach($item in @(
        @{id='user-tip';key=$userTip;children=@('LanguageProfile')},
        @{id='user-languages';key="$userTip\LanguageProfile";children=@('0x00000804')},
        @{id='user-language';key="$userTip\LanguageProfile\0x00000804";children=@($script:CandidateProfile)}
    )){$result.Add((New-CandidateTree $item.id 'Users' 'Shared' $item.key @() $item.children))}
    $result.Add((New-CandidateTree 'user-profile' 'Users' 'Shared' "$userTip\LanguageProfile\0x00000804\$script:CandidateProfile" @((New-CandidateValue 'Enable' 'DWord' '1')) @()))
    $result.Add((New-CandidateTree 'marker-root' 'LocalMachine' 'Registry64' 'SOFTWARE\YIME' @((New-CandidateValue '' 'String' $root)) @()))
    $result.Add((New-CandidateTree 'marker-uninstall' 'LocalMachine' 'Registry64' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YIME' @(
        (New-CandidateValue 'DisplayName' 'String' 'Yime Rime/PIME isolated candidate'),
        (New-CandidateValue 'UninstallString' 'String' ('"'+(Join-Path $Context.authorization.recovery_root 'maintenance-candidate.exe')+'" /Mode=Remove')),
        (New-CandidateValue 'InstallLocation' 'String' $root),
        (New-CandidateValue 'Publisher' 'String' 'Yime'),
        (New-CandidateValue 'DisplayVersion' 'String' $r.DisplayVersion),
        (New-CandidateValue 'URLInfoAbout' 'String' 'https://github.com/tsaanghwang/Yime')
    ) @()))
    return $result.ToArray()
}

function Get-CandidateRegistryShape([string]$Hive,[string]$View,[string]$Key) {
    $shape=Get-YimePimeSystemRegistryKeyShape $Hive $View $Key
    # WMI can return null SAFEARRAYs for an empty key; an empty default value
    # name is a real value and must not be normalized away with null entries.
    foreach($field in @('value_names','value_types','subkey_names')) {
        $items=@($shape.$field)
        if($items.Count -eq 1 -and $null -eq $items[0]){$shape.$field=@()}
        elseif(@($items|Where-Object{$null -eq $_}).Count){throw 'Inconsistent null registry enumeration.'}
    }
    if(@($shape.value_names).Count -ne @($shape.value_types).Count){throw 'Inconsistent registry name/type enumeration.'}
    return $shape
}
function Get-CandidateTreeObservation($Tree,[switch]$AllowDisabled) {
    $shape=Get-CandidateRegistryShape $Tree.hive $Tree.view $Tree.key
    # A required default-only REG_SZ key has null EnumValues arrays in StdRegProv.
    # Recover only this expected value through a typed system-provider read below.
    if($shape.exists -and @($shape.value_names).Count -eq 0 -and @($Tree.values|Where-Object{$_.name -ceq '' -and $_.value_kind -ceq 'String'}).Count -eq 1){
        $shape.value_names=@('');$shape.value_types=@(1)
    }
    $values=[Collections.Generic.List[object]]::new()
    if($shape.exists) {
        foreach($child in @($shape.subkey_names)){if(@($Tree.children) -inotcontains [string]$child){throw ('Foreign registration subkey preserved: '+$Tree.id)}}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        for($i=0;$i -lt @($shape.value_names).Count;$i++) {
            $name=[string]$shape.value_names[$i]
            if(-not $seen.Add($name)){throw 'Duplicate registry name observation.'}
            $wanted=@($Tree.values|Where-Object{$_.name -ieq $name})
            if($wanted.Count -ne 1){throw ('Foreign registration value preserved: '+$Tree.id)}
            $expected=[pscustomobject]@{id=$Tree.id+':'+$name;hive=$Tree.hive;view=$Tree.view;key=$Tree.key;name=$name}
            $actual=Get-YimePimeSystemRegistryValueRecord $expected
            if(-not $actual.exists -or $actual.value_kind -cne $wanted[0].value_kind){throw ('Registration changed or mistyped: '+$Tree.id)}
            $disabled=$AllowDisabled -and $Tree.id -ceq 'user-profile' -and $name -ceq 'Enable' -and $actual.value -ceq '0'
            if(-not $disabled -and $actual.value -cne $wanted[0].value){throw ('Registration value owned by another root or unknown state: '+$Tree.id)}
            $values.Add($actual)
        }
    }
    [pscustomobject]@{id=$Tree.id;hive=$Tree.hive;view=$Tree.view;key=$Tree.key;exists=[bool]$shape.exists;values=$values.ToArray();subkeys=@($shape.subkey_names);reader='StdRegProv'}
}

function Get-CandidateRunExpected($Context) {
    $root=$Context.request.InstallRoot
    # The manifest admits only the dedicated dp1-candidate launcher build. Every
    # startup path in that build requires its fixed isolated state configuration.
    New-CandidateValue 'PIMELauncher' 'String' ('"'+(Join-Path $root 'PIMELauncher.exe')+'"')
}
function Get-CandidateRunObservation($Context) {
    $wanted=Get-CandidateRunExpected $Context
    $expected=[pscustomobject]@{id='run';hive='LocalMachine';view='Registry64';key='SOFTWARE\Microsoft\Windows\CurrentVersion\Run';name='PIMELauncher'}
    $actual=Get-YimePimeSystemRegistryValueRecord $expected
    if($actual.exists -and ($actual.value_kind -cne 'String' -or $actual.value -cne $wanted.value)){throw 'Foreign or changed candidate autostart preserved.'}
    return $actual
}
function Get-CandidateDefaultObservation([string]$Sid) {
    $expected=[pscustomobject]@{id='default-input-override';hive='Users';view='Shared';key=($Sid+'\Control Panel\International\User Profile');name='InputMethodOverride'}
    $value=Get-YimePimeSystemRegistryValueRecord $expected
    if($value.exists -and $value.value_kind -cne 'String'){throw 'Unsupported default input override type; no fallback or coercion.'}
    return $value
}
function Get-CandidateAllObservation($Context,[switch]$AllowDisabled) {
    [pscustomobject]@{schema_version='yime-rime-pime-candidate-registration-observation-v1';target_user_sid=$Context.request.TargetUserSid;install_root=$Context.request.InstallRoot;trees=@(Get-CandidateRegistrationLayout $Context|ForEach-Object{Get-CandidateTreeObservation $_ -AllowDisabled:$AllowDisabled});run=(Get-CandidateRunObservation $Context);default_input=(Get-CandidateDefaultObservation $Context.request.TargetUserSid);peer_protection=$Context.peer_protection;actual_registration_probe_executed=$false;dp1_u_acceptance_passed=$false;local12_touched=$false;production_user_data_accessed=$false}
}
function Assert-CandidateObservationAbsent($Observation) {
    if(@($Observation.trees|Where-Object{$_.exists}).Count -gt 0 -or $Observation.run.exists){throw 'Fresh registration vacancy or exact removal absence not established.'}
    if(Test-YimePimeTargetUserControlPanelReference $Observation.target_user_sid){throw 'Target user language list still references Rime/PIME.'}
}
function Assert-CandidateObservationPresent($Context,$Observation) {
    foreach($tree in @(Get-CandidateRegistrationLayout $Context)) {
        $actual=@($Observation.trees|Where-Object{$_.id -ceq $tree.id})
        if($actual.Count -ne 1 -or -not $actual[0].exists -or @($actual[0].values).Count -ne @($tree.values).Count -or @($actual[0].subkeys).Count -ne @($tree.children).Count){throw ('Registration not complete: '+$tree.id)}
        if($tree.id -ceq 'user-profile' -and $actual[0].values[0].value -cne '1'){throw 'Target user profile is not enabled.'}
    }
    if(-not $Observation.run.exists){throw 'Candidate runtime autostart is absent.'}
}
function Assert-CandidateMachineRegistration($Context,$Observation,[switch]$NativeOnly) {
    foreach($tree in @(Get-CandidateRegistrationLayout $Context|Where-Object{$_.hive -ceq 'LocalMachine' -and $_.id -notlike 'marker-*' -and (-not $NativeOnly -or $_.id -notlike 'com-x86*')})) {
        $actual=@($Observation.trees|Where-Object{$_.id -ceq $tree.id})
        if($actual.Count -ne 1 -or -not $actual[0].exists -or @($actual[0].values).Count -ne @($tree.values).Count -or @($actual[0].subkeys).Count -ne @($tree.children).Count){
            $detail=[ordered]@{id=$tree.id;view=$tree.view;matches=$actual.Count;expected_values=@($tree.values).Count;expected_subkeys=@($tree.children).Count}
            if($actual.Count -eq 1){$detail.exists=[bool]$actual[0].exists;$detail.actual_values=@($actual[0].values).Count;$detail.actual_subkeys=@($actual[0].subkeys).Count}
            throw ('Machine registration not complete: '+$tree.id+'; '+($detail|ConvertTo-Json -Compress))
        }
    }
}

function Invoke-CandidateCheckedProcess([string]$Path,[string]$Arguments,[IntPtr]$CoordinationHandle) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw ('Candidate registration executable absent: '+$Path)}
    $result=Invoke-CandidateContainedProcess $Path $Arguments 60000 $CoordinationHandle
    if(-not $result.JobEmptyBeforeReturn){throw 'Registration job completion not established.'}
    if($result.TimedOut){throw 'Registration job exceeded deadline and was terminated; all owned children have exited; partial state retained for recovery.'}
    if($result.DescendantsTerminated){throw 'Registration child job remained active after the bounded exit observation; its job was terminated and drained; partial state retained for recovery.'}
    if($result.ExitCode -ne 0){throw ('Registration child returned '+$result.ExitCode+'; all owned children have exited; partial state retained for journal recovery.')}
}
function Invoke-CandidateContainedProcess([string]$Path,[string]$Arguments,[int]$TimeoutMilliseconds,[IntPtr]$CoordinationHandle) {
    if($null -eq $script:CandidateChildType) {
        $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'rime-pime-dp1u-candidate-registration-child.cs'),[Text.UTF8Encoding]::new($false,$true))
        $namespace='Yime.CandidateRegistrationChild_'+[guid]::NewGuid().ToString('N')
        $types=Add-Type -TypeDefinition ($source.Replace('namespace Yime.CandidateRegistrationChild {',('namespace '+$namespace+' {'))) -PassThru
        $script:CandidateChildType=@($types|Where-Object{$_.FullName -ceq ($namespace+'.OwnedChild')})[0]
    }
    $script:CandidateChildType::Run($Path,$Arguments,$TimeoutMilliseconds,$CoordinationHandle)
}
function Invoke-CandidateNativeRegistration($Context,[string]$Architecture,[bool]$Remove) {
    $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $regsvr=Join-Path $windows $(if($Architecture -ceq 'x86'){'SysWOW64\regsvr32.exe'}else{'System32\regsvr32.exe'})
    $dll=Join-Path $Context.request.InstallRoot ($Architecture+'\PIMETextService.dll')
    Invoke-CandidateCheckedProcess $regsvr ($(if($Remove){'/u /s "'}else{'/s "'})+$dll+'"') $Context.request.CoordinationHandle
}
function Invoke-CandidateNativeProbe($Context,[string]$Mode) {
    foreach($arch in @('x86','x64')){Invoke-CandidateCheckedProcess (Join-Path $Context.request.PackageRoot ($arch+'\PIMERegistrationStatus.exe')) $Mode $Context.request.CoordinationHandle}
}
function Invoke-CandidateTip([bool]$Remove) {
    if(-not ('Yime.CandidateInputLayout' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace Yime { public static class CandidateInputLayout {
 [DllImport("input.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 [return: MarshalAs(UnmanagedType.Bool)] private static extern bool InstallLayoutOrTip(string value, uint flags);
 public static bool Apply(bool remove) { return InstallLayoutOrTip("0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}",remove ? 1U : 0U); }
} }
'@
    }
    if(-not [Yime.CandidateInputLayout]::Apply($Remove)){throw 'InstallLayoutOrTip failed; preserve transaction for recovery.'}
}
function Set-CandidateMarkerValue($Tree,$Value) {
    $coord=Convert-YimePimeSystemRegistryCoordinate $Tree.hive $Tree.view $Tree.key
    $created=Invoke-YimePimeSystemRegistryMethod CreateKey $coord.hive $coord.key $coord.provider_architecture
    if($created.ReturnValue -ne 0){throw 'Registry marker key creation failed.'}
    $written=Invoke-YimePimeSystemRegistryMethod SetStringValue $coord.hive $coord.key $coord.provider_architecture @{sValueName=$Value.name;sValue=$Value.value}
    if($written.ReturnValue -ne 0){throw 'Registry marker write failed.'}
    $actual=Get-YimePimeSystemRegistryValueRecord ([pscustomobject]@{id=$Tree.id;hive=$Tree.hive;view=$Tree.view;key=$Tree.key;name=$Value.name})
    if(-not $actual.exists -or $actual.value_kind -cne 'String' -or $actual.value -cne $Value.value){throw 'Independent marker readback failed.'}
}
function Remove-CandidateKnownTree($Tree,[switch]$AllowDisabled) {
    # Child-first, closed sets, exact values. No recursive registry deletion.
    $actual=Get-CandidateTreeObservation $Tree -AllowDisabled:$AllowDisabled
    if(-not $actual.exists){return}
    if(@($actual.subkeys).Count -gt 0){throw 'Registry key has remaining children; preserve it.'}
    $coord=Convert-YimePimeSystemRegistryCoordinate $Tree.hive $Tree.view $Tree.key
    foreach($value in $actual.values) {
        $fresh=Get-CandidateTreeObservation $Tree -AllowDisabled:$AllowDisabled
        if(@($fresh.subkeys).Count){throw 'Registry changed before value removal.'}
        $deleted=Invoke-YimePimeSystemRegistryMethod DeleteValue $coord.hive $coord.key $coord.provider_architecture @{sValueName=$value.name}
        if($deleted.ReturnValue -ne 0 -and $deleted.ReturnValue -ne 2){throw 'Registry value removal failed.'}
    }
    $empty=Get-CandidateRegistryShape $Tree.hive $Tree.view $Tree.key
    if(@($empty.value_names).Count -or @($empty.subkey_names).Count){throw 'Registry key is no longer empty; preserve it.'}
    $null=Invoke-YimePimeSystemRegistryMethod DeleteKey $coord.hive $coord.key $coord.provider_architecture
}

function Get-RimePimeDp1UCandidateRegistrationObservation {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$AuthorizationPath,[Parameter(Mandatory)][string]$TrustedApprovalSha256,[Parameter(Mandatory)][string]$BoundaryPath,[Parameter(Mandatory)][string]$PackageManifestSha256,[Parameter(Mandatory)][IntPtr]$CoordinationHandle,[string]$UninstallerSha256,[string]$DisplayVersion='DP1-U',[ValidateSet('Vacant','Present','Absent','Partial')][string]$ExpectedState='Partial')
    $request=@{};foreach($entry in $PSBoundParameters.GetEnumerator()){$request[$entry.Key]=$entry.Value};$request.DisplayVersion=$DisplayVersion
    $context=Open-CandidateRegistrationContext $request $false
    try {
        $observation=Get-CandidateAllObservation $context -AllowDisabled
        if($ExpectedState -in @('Vacant','Absent')){Assert-CandidateObservationAbsent $observation;Invoke-CandidateNativeProbe $context 'verify-absent';$observation.actual_registration_probe_executed=$true}
        if($ExpectedState -ceq 'Present'){Assert-CandidateObservationPresent $context $observation;Invoke-CandidateNativeProbe $context 'verify-present';$observation.actual_registration_probe_executed=$true}
        return $observation
    }finally{foreach($lease in $context.leases){$lease.Dispose()}}
}
function Invoke-RimePimeDp1UCandidateRegistration {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][ValidateSet('AssertVacant','RegisterNative','RegisterWow64','EnableTip','PublishMarkers','VerifyPresent','DisableTip','UnregisterWow64','UnregisterNative','RemoveMarkers','VerifyAbsent')][string]$Action,
        [Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$TargetUserSid,
        [Parameter(Mandatory)][string]$AuthorizationPath,[Parameter(Mandatory)][string]$TrustedApprovalSha256,[Parameter(Mandatory)][string]$BoundaryPath,
        [Parameter(Mandatory)][string]$PackageManifestSha256,[Parameter(Mandatory)][IntPtr]$CoordinationHandle,[string]$UninstallerSha256,[string]$DisplayVersion='DP1-U')
    $request=@{};foreach($entry in $PSBoundParameters.GetEnumerator()){$request[$entry.Key]=$entry.Value};$request.DisplayVersion=$DisplayVersion
    $context=Open-CandidateRegistrationContext $request ($Action -notin @('AssertVacant','VerifyPresent','VerifyAbsent'))
    try {
        $before=Get-CandidateAllObservation $context -AllowDisabled
        switch($Action) {
            AssertVacant {Assert-CandidateObservationAbsent $before;Invoke-CandidateNativeProbe $context 'verify-absent'}
            RegisterNative {
                # Both native and WOW64 must be absent at the initial transition.
                Assert-CandidateObservationAbsent $before
                Invoke-CandidateNativeRegistration $context 'x64' $false
                Assert-CandidateMachineRegistration $context (Get-CandidateAllObservation $context) -NativeOnly
            }
            RegisterWow64 {
                Assert-CandidateMachineRegistration $context $before -NativeOnly
                if(@($before.trees|Where-Object{$_.id -like 'com-x86*' -and $_.exists}).Count){throw 'WOW64 registration already exists; preserve it.'}
                Invoke-CandidateNativeRegistration $context 'x86' $false
                Assert-CandidateMachineRegistration $context (Get-CandidateAllObservation $context)
            }
            EnableTip {Assert-CandidateMachineRegistration $context $before;Invoke-CandidateNativeProbe $context 'verify-registered';Invoke-CandidateTip $false;Invoke-CandidateNativeProbe $context 'verify-present'}
            PublishMarkers {
                if($UninstallerSha256 -cnotmatch '^[0-9a-f]{64}$' -or $UninstallerSha256 -cne $context.authorization.package_sha256){throw 'Uninstaller must be the original explicitly approved candidate bytes.'}
                foreach($candidate in @((Join-Path $InstallRoot 'maintenance-candidate.exe'),(Join-Path $context.authorization.recovery_root 'maintenance-candidate.exe'))) {
                    if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -cne $UninstallerSha256){throw 'Candidate maintenance executable digest mismatch.'}
                }
                Invoke-CandidateNativeProbe $context 'verify-present'
                foreach($tree in @(Get-CandidateRegistrationLayout $context|Where-Object{$_.id -like 'marker-*'})){foreach($value in $tree.values){Set-CandidateMarkerValue $tree $value}}
                $runTree=[pscustomobject]@{id='run';hive='LocalMachine';view='Registry64';key='SOFTWARE\Microsoft\Windows\CurrentVersion\Run'}
                Set-CandidateMarkerValue $runTree (Get-CandidateRunExpected $context)
            }
            VerifyPresent {Assert-CandidateObservationPresent $context $before;Invoke-CandidateNativeProbe $context 'verify-present'}
            DisableTip {
                if(@($before.trees|Where-Object{$_.id -like 'user-*' -and $_.exists}).Count -or (Test-YimePimeTargetUserControlPanelReference $TargetUserSid)){Invoke-CandidateTip $true}
            }
            UnregisterWow64 {
                if(@($before.trees|Where-Object{$_.id -like 'com-x86*' -and $_.exists}).Count){Invoke-CandidateNativeRegistration $context 'x86' $true}
            }
            UnregisterNative {
                if(@($before.trees|Where-Object{$_.id -like 'com-x86*' -and $_.exists}).Count){throw 'Remove WOW64 COM before the shared native TSF registration.'}
                if(@($before.trees|Where-Object{$_.hive -ceq 'LocalMachine' -and $_.id -notlike 'marker-*' -and $_.exists}).Count){Invoke-CandidateNativeRegistration $context 'x64' $true}
            }
            RemoveMarkers {
                if(@($before.trees|Where-Object{($_.id -like 'com-*' -or $_.hive -ceq 'LocalMachine' -and $_.id -notlike 'marker-*') -and $_.exists}).Count){throw 'Native COM/TIP must be absent before marker cleanup.'}
                foreach($tree in @(Get-CandidateRegistrationLayout $context|Where-Object{$_.id -like 'user-*'}|Sort-Object {$_.key.Length} -Descending)){Remove-CandidateKnownTree $tree -AllowDisabled}
                if(Test-YimePimeTargetUserControlPanelReference $TargetUserSid){throw 'Language list retains product references; no unrelated user values will be edited.'}
                $run=Get-CandidateRunObservation $context
                if($run.exists){$null=Invoke-YimePimeSystemRegistryMethod DeleteValue 2147483650 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 64 @{sValueName='PIMELauncher'}}
                foreach($tree in @(Get-CandidateRegistrationLayout $context|Where-Object{$_.id -like 'marker-*'})){Remove-CandidateKnownTree $tree}
            }
            VerifyAbsent {Assert-CandidateObservationAbsent $before;Invoke-CandidateNativeProbe $context 'verify-absent'}
        }
        $after=Get-CandidateAllObservation $context -AllowDisabled
        Assert-RimePimePeerProtectionUnchanged $context.peer_protection (Get-RimePimePeerProtectionSnapshot $context.boundary $context.request.TargetUserSid)
        if(($before.default_input|ConvertTo-Json -Compress) -cne ($after.default_input|ConvertTo-Json -Compress)){throw 'Default input override changed during candidate registration; preserve evidence.'}
        [pscustomobject]@{schema_version='yime-rime-pime-candidate-registration-result-v1';action=$Action;before=$before;after=$after;native_provider_invoked=($Action -notin @('AssertVacant','VerifyPresent','VerifyAbsent'));actual_registration_probe_executed=($Action -in @('AssertVacant','EnableTip','PublishMarkers','VerifyPresent','VerifyAbsent'));full_native_product_transaction_complete=$false;dp1_u_acceptance_passed=$false;local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false;hostile_same_sid_prevention_verified=$false}
    }finally{foreach($lease in $context.leases){$lease.Dispose()}}
}
Export-ModuleMember -Function Invoke-RimePimeDp1UCandidateRegistration,Get-RimePimeDp1UCandidateRegistrationObservation
