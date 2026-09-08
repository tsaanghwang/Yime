Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:DeferredSource=$PSCommandPath
$script:DeferredHive=[uint32]2147483650
$script:DeferredKey='SYSTEM\CurrentControlSet\Control\Session Manager'
$script:DeferredNames=@('PendingFileRenameOperations','PendingFileRenameOperations2')
# Primary references for the intentionally limited interpretation:
# https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw
# https://learn.microsoft.com/en-us/windows/win32/wmisdk/requesting-wmi-data-on-a-64-bit-platform
# https://learn.microsoft.com/en-us/previous-versions/windows/desktop/regprov/getmultistringvalue-method-in-class-stdregprov
# MoveFileEx explicitly permits an empty delete target inside REG_MULTI_SZ.
# StdRegProv documentation does not promise preservation after embedded empty
# members. A present queue can be analyzed, but never grants the absence gate.

function Assert-DeferredText($Value) {
    if($Value -isnot [string] -or $Value.Length -gt 32767){throw 'Literal bounded queue string required'}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Value)
    if($Value.Contains([string][char]0)){throw 'Embedded queue string NUL rejected'}
}
function Get-DeferredDigest($Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash(([Text.UTF8Encoding]::new($false,$true)).GetBytes((ConvertTo-Json -InputObject $Value -Depth 24 -Compress))))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Assert-DeferredFields($Object,[string[]]$Fields) {
    if($Object -isnot [Collections.IDictionary] -and $Object -isnot [pscustomobject]){throw 'Literal provider object required'}
    $keys=if($Object -is [Collections.IDictionary]){@($Object.Keys)}else{@($Object.PSObject.Properties.Name)}
    if($keys.Count -ne $Fields.Count){throw 'Unexpected provider fields'}
    foreach($name in $Fields){if($keys -cnotcontains $name){throw 'Missing provider field'}}
}
function Assert-DeferredReturn($Value) {
    if(($Value -isnot [int] -and $Value -isnot [uint32]) -or $Value -ne 0){throw 'StdRegProv error; no registry-view fallback'}
}
function ConvertFrom-DeferredNativeProperty($Property,[string]$Name) {
    if($Property.Name -isnot [string] -or $Property.Name -cne $Name -or $Property.IsArray -isnot [bool]){throw 'Invalid native provider metadata'}
    $array=$Name -cne 'ReturnValue';$cim=if($Name -ceq 'ReturnValue'){19}elseif($Name -ceq 'Types'){3}else{8}
    if(($Property.CIMType -isnot [int] -and $Property.CIMType -isnot [uint32]) -or $Property.CIMType -ne $cim -or $Property.IsArray -ne $array){throw 'Unexpected native provider CIM declaration'}
    $value=$Property.Value
    if($value -is [DBNull]){return $null}
    if($Name -ceq 'ReturnValue' -and $value -is [int] -and $value -lt 0){return [BitConverter]::ToUInt32([BitConverter]::GetBytes($value),0)}
    return ,$value
}
function New-DeferredRegistrySession {
    $session=@{}
    try{
        foreach($view in @(32,64)){
            $context=New-Object -ComObject WbemScripting.SWbemNamedValueSet
            $session[$view]=[ordered]@{context=$context;locator=$null;services=$null;provider=$null}
            $null=$context.Add('__ProviderArchitecture',$view);$null=$context.Add('__RequiredArchitecture',$true)
            $locator=New-Object -ComObject WbemScripting.SWbemLocator;$session[$view].locator=$locator
            $services=$locator.ConnectServer('.','root\default','','','','',0,$context);$session[$view].services=$services
            $services.Security_.ImpersonationLevel=3;$session[$view].provider=$services.Get('StdRegProv')
        }
        return $session
    }catch{Close-DeferredRegistrySession $session;throw}
}
function Close-DeferredRegistrySession($Session) {
    foreach($entry in $Session.Values){foreach($name in @('provider','services','locator','context')){
        $item=$entry[$name];if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}
    }}
}
function Invoke-DeferredRegistryMethod($Session,[int]$View,[ValidateSet('EnumValues','GetMultiStringValue')][string]$Method,[string]$Name='') {
    if($View -notin @(32,64) -or ($Method -ceq 'GetMultiStringValue' -and $script:DeferredNames -cnotcontains $Name) -or ($Method -ceq 'EnumValues' -and $Name)){throw 'Read left fixed queue coordinates'}
    $entry=$Session[$View];$metadata=$null;$arguments=$null;$output=$null
    try{
        $metadata=$entry.provider.Methods_.Item($Method);$arguments=$metadata.InParameters.SpawnInstance_()
        # Give the SWbem input setters their declared Automation argument types.
        # Untyped script-variable assignments can bind Value as the preceding
        # CIM_UINT32 hDefKey setter when the next input is a CIM_STRING.
        $arguments.Properties_.Item('hDefKey').Value=[uint32]$script:DeferredHive
        $arguments.Properties_.Item('sSubKeyName').Value=[string]$script:DeferredKey
        if($Method -ceq 'GetMultiStringValue'){$arguments.Properties_.Item('sValueName').Value=[string]$Name}
        $output=$entry.provider.ExecMethod_($Method,$arguments,0,$entry.context)
        $names=if($Method -ceq 'EnumValues'){@('ReturnValue','sNames','Types')}else{@('ReturnValue','sValue')}
        $copy=[ordered]@{};foreach($name in $names){$copy[$name]=ConvertFrom-DeferredNativeProperty ($output.Properties_.Item($name)) $name}
        [pscustomobject]$copy
    }finally{foreach($item in @($output,$arguments,$metadata)){if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}}}
}
function Read-DeferredEnumeration($Session,[int]$View) {
    $reply=Invoke-DeferredRegistryMethod $Session $View 'EnumValues'
    Assert-DeferredFields $reply @('ReturnValue','sNames','Types');Assert-DeferredReturn $reply.ReturnValue
    if(($null -ne $reply.sNames -and $reply.sNames -isnot [array]) -or ($null -ne $reply.Types -and $reply.Types -isnot [array])){throw 'Malformed registry enumeration arrays'}
    $names=@();$types=@()
    if($null -ne $reply.sNames){$names=@($reply.sNames)};if($null -ne $reply.Types){$types=@($reply.Types)}
    if($names.Count -ne $types.Count -or $names.Count -gt 16384){throw 'Registry enumeration length mismatch'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$wanted=@{}
    for($i=0;$i -lt $names.Count;$i++){
        Assert-DeferredText $names[$i]
        if($names[$i].Length -gt 16383 -or -not $seen.Add($names[$i])){throw 'Invalid or duplicate registry value name'}
        $kind=$types[$i];if(($kind -isnot [int] -and $kind -isnot [uint32]) -or $kind -lt 0 -or $kind -gt 11){throw 'Invalid registry kind'}
        if($script:DeferredNames -icontains $names[$i]){
            if($script:DeferredNames -cnotcontains $names[$i] -or $kind -ne 7){throw 'Queue requires canonical REG_MULTI_SZ value'}
            $wanted[$names[$i]]=[int]$kind
        }
    }
    return ,$wanted
}
function ConvertFrom-DeferredPath($Text,[bool]$Target) {
    Assert-DeferredText $Text
    if($Text -ceq ''){if($Target){return [pscustomobject]@{known=$true;path='';replace=$false;reason='delete-target'}};throw 'Empty pending-operation source'}
    $path=$Text;$replace=$false
    if($path.StartsWith('!',[StringComparison]::Ordinal)){
        if(-not $Target){return [pscustomobject]@{known=$false;path='';replace=$false;reason='source-replace-prefix'}}
        $replace=$true;$path=$path.Substring(1)
    }
    if($path.StartsWith('\??\',[StringComparison]::Ordinal)){$path=$path.Substring(4)}
    elseif($path.StartsWith('\\?\',[StringComparison]::Ordinal)){$path=$path.Substring(4)}
    elseif($path.StartsWith('\DosDevices\',[StringComparison]::OrdinalIgnoreCase)){$path=$path.Substring(12)}
    if($path -notmatch '^[a-zA-Z]:\\' -or $path -match '[/\x00-\x1f"<>|?*%]' -or $path.Substring(2).Contains(':')){return [pscustomobject]@{known=$false;path='';replace=$replace;reason='unsupported-path-namespace'}}
    if($path.Length -gt 3 -and $path.EndsWith('\')){$path=$path.Substring(0,$path.Length-1)}
    if($path.Length -gt 3){foreach($part in $path.Substring(3).Split('\')){
        if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){
            return [pscustomobject]@{known=$false;path='';replace=$replace;reason='ambiguous-path-component'}
        }
    }}
    [pscustomobject]@{known=$true;path=$path;replace=$replace;reason=''}
}
function Get-DeferredRelation([string]$Path,[string]$Root) {
    if($Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase)){return 'equal'}
    $rootPrefix=if($Root.EndsWith('\')){$Root}else{$Root+'\'}
    $pathPrefix=if($Path.EndsWith('\')){$Path}else{$Path+'\'}
    if($Path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){return 'descendant'}
    if($Root.StartsWith($pathPrefix,[StringComparison]::OrdinalIgnoreCase)){return 'ancestor'}
    return ''
}
function Read-DeferredPass($Session,[string[]]$Roots) {
    $records=New-Object 'Collections.Generic.List[object]';$risks=New-Object 'Collections.Generic.List[object]';$unknown=New-Object 'Collections.Generic.List[object]'
    foreach($view in @(32,64)){
        $before=Read-DeferredEnumeration $Session $view
        foreach($name in $script:DeferredNames){
            $strings=@();$exists=$before.ContainsKey($name)
            if($exists){
                $reply=Invoke-DeferredRegistryMethod $Session $view 'GetMultiStringValue' $name
                Assert-DeferredFields $reply @('ReturnValue','sValue');Assert-DeferredReturn $reply.ReturnValue
                if($reply.sValue -isnot [array] -or $reply.sValue.Count -gt 16384 -or $reply.sValue.Count % 2 -ne 0){throw 'Queue requires bounded ordered source/target pairs'}
                $strings=@($reply.sValue);foreach($text in $strings){Assert-DeferredText $text}
            }
            $encoded=@(foreach($text in $strings){[Convert]::ToBase64String(([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($text))})
            $digestBody=[ordered]@{view=$view;name=$name;exists=$exists;kind=$(if($exists){7}else{$null});strings_utf16le_base64=$encoded}
            $records.Add([pscustomobject][ordered]@{view=$view;name=$name;exists=$exists;kind=$digestBody.kind;string_count=$strings.Count;pair_count=[int]($strings.Count/2);ordered_sha256=(Get-DeferredDigest $digestBody)})
            for($i=0;$i -lt $strings.Count;$i+=2){
                $source=ConvertFrom-DeferredPath $strings[$i] $false;$target=ConvertFrom-DeferredPath $strings[$i+1] $true
                $operation=if($strings[$i+1] -ceq ''){'delete'}else{'rename'}
                foreach($endpoint in @(@{side='source';value=$source},@{side='target';value=$target})){
                    if(-not $endpoint.value.known){$unknown.Add([pscustomobject]@{view=$view;name=$name;pair_index=([int]($i/2));side=$endpoint.side;reason=$endpoint.value.reason});continue}
                    if(-not $endpoint.value.path){continue}
                    for($j=0;$j -lt $Roots.Count;$j++){
                        $relation=Get-DeferredRelation $endpoint.value.path $Roots[$j]
                        if($relation){$risks.Add([pscustomobject]@{view=$view;name=$name;pair_index=([int]($i/2));operation=$operation;side=$endpoint.side;replace_existing=[bool]$target.replace;protected_root_index=$j;relation=$relation})}
                    }
                }
            }
        }
        $after=Read-DeferredEnumeration $Session $view
        foreach($name in $script:DeferredNames){if($before.ContainsKey($name) -ne $after.ContainsKey($name) -or ($before.ContainsKey($name) -and $before[$name] -ne $after[$name])){throw 'Queue membership or type changed during observation'}}
    }
    [pscustomobject]@{records=@($records.ToArray());risks=@($risks.ToArray());unknown=@($unknown.ToArray())}
}
function Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$ProtectedRoots)
    if($ProtectedRoots -isnot [array] -or $ProtectedRoots.Count -lt 1 -or $ProtectedRoots.Count -gt 16){throw 'Explicit protected roots array required'}
    $roots=New-Object 'Collections.Generic.List[string]';$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($root in $ProtectedRoots){
        Assert-DeferredText $root;$parsed=ConvertFrom-DeferredPath $root $false
        if(-not $parsed.known -or $parsed.path -cne $root -or $root -cnotmatch '^[A-Z]:\\' -or -not $seen.Add($root)){throw 'Canonical unique DOS protected roots required'}
        $roots.Add($root)
    }
    if(-not [Environment]::Is64BitOperatingSystem){throw 'Both required provider architectures are unavailable'}
    $sourceHash=(Get-FileHash -LiteralPath $script:DeferredSource -Algorithm SHA256).Hash.ToLowerInvariant()
    $session=New-DeferredRegistrySession
    try{
        $first=Read-DeferredPass $session $roots.ToArray();$second=Read-DeferredPass $session $roots.ToArray()
        if((Get-DeferredDigest $first) -cne (Get-DeferredDigest $second)){throw 'Queue changed between full observations'}
        if((Get-FileHash -LiteralPath $script:DeferredSource -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Deferred observer source changed'}
        $present=@($second.records|Where-Object {$_.exists}).Count
        $body=[ordered]@{schema_version='yimecore-native-maintenance-deferred-delete-v1';source_sha256=$sourceHash;
            provider='StdRegProv-required-32-and-64';protected_roots=@($roots.ToArray());records=$second.records;
            ordered_queue_sha256=(Get-DeferredDigest $second.records);reported_pair_count=[int](($second.records|Measure-Object pair_count -Sum).Sum);
            related_operation_count=@($second.risks|Select-Object view,name,pair_index -Unique).Count;
            risks=$second.risks;unknown_count=$second.unknown.Count;unknown=$second.unknown;two_pass_equal=$true;
            point_in_time_clear=($present -eq 0);all_queue_values_absent=($present -eq 0);
            provider_raw_multisz_completeness_verified=$false;registry_link_identity_verified=$false;
            continuous_monitoring=$false;atomic=$false;execution_authorized=$false;rollback_acceptance=$false;
            L6_sealed=$false;local_product_ready=$false;public_release_ready=$false}
        $body['snapshot_sha256']=Get-DeferredDigest $body
        [pscustomobject]$body
    }finally{Close-DeferredRegistrySession $session}
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot
