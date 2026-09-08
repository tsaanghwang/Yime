Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:YcEvidenceSource=$PSCommandPath

function Get-YcDigest($Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80 -Compress))))).Replace('-','').ToLowerInvariant() }
    finally {$sha.Dispose()}
}
function Assert-YcFields($Value,[string[]]$Names) {
    if ($null -eq $Value) {throw 'Missing evidence object'}
    $actual=if($Value -is [Collections.IDictionary]) {@($Value.Keys)} else {@($Value.PSObject.Properties.Name)}
    if($actual.Count -ne $Names.Count){throw 'Unexpected evidence fields'}
    foreach($name in $Names){if($actual -cnotcontains $name){throw 'Missing evidence field'}}
}
function Assert-YcSid([string]$Sid) {
    if($Sid -cnotmatch '^S-1-5-21-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*$'){throw 'Explicit canonical initiating user SID required'}
    if(([Security.Principal.SecurityIdentifier]::new($Sid)).Value -cne $Sid){throw 'Noncanonical SID'}
}
function ConvertTo-YcText([string]$Value){[Convert]::ToBase64String(([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Value))}
function Assert-YcText($Value) {
    if($Value -isnot [string]){throw 'Encoded string required'}
    try{$bytes=[Convert]::FromBase64String($Value)}catch{throw 'Invalid base64'}
    if($bytes.Length % 2 -ne 0 -or [Convert]::ToBase64String($bytes) -cne $Value){throw 'Noncanonical UTF16 representation'}
    # Reject unpaired surrogates instead of normalizing distinct registry text
    # into the same replacement character in evidence or comparisons.
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetString($bytes)
}
function Get-YimeCoreNativeMaintenanceRegistryCatalog {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$TargetUserSid)
    Assert-YcSid $TargetUserSid
    $records=@()
    foreach($view in @(32,64)) {
        foreach($identity in @(
            @{id='active';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'},
            @{id='frozen';clsid='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'},
            @{id='production';clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'})) {
            foreach($hive in @([uint32]2147483650,[uint32]2147483651)) {
                foreach($kind in @('com','tip')) {
                    $key=if($kind -ceq 'com'){"SOFTWARE\Classes\CLSID\$($identity.clsid)"}else{"SOFTWARE\Microsoft\CTF\TIP\$($identity.clsid)"}
                    if($hive -eq 2147483651){$key=$TargetUserSid+'\'+$key}
                    $records += [pscustomobject][ordered]@{id="$view/$hive/$($identity.id)/$kind";view=$view;hive=$hive;key=$key;mode='tree';name=''}
                }
            }
        }
        foreach($product in @(@{id='active';uninstall='YimeCoreExperimentalTrial';run='YimeCoreExperimentalTrial'},@{id='production';uninstall='YIME';run='PIMELauncher'})) {
            foreach($hive in @([uint32]2147483650,[uint32]2147483651)) {
                $prefix=if($hive -eq 2147483651){$TargetUserSid+'\'}else{''}
                $records += [pscustomobject][ordered]@{id="$view/$hive/$($product.id)/uninstall";view=$view;hive=$hive;key=($prefix+'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\'+$product.uninstall);mode='tree';name=''}
                $records += [pscustomobject][ordered]@{id="$view/$hive/$($product.id)/run";view=$view;hive=$hive;key=($prefix+'SOFTWARE\Microsoft\Windows\CurrentVersion\Run');mode='value';name=$product.run}
            }
        }
        foreach($key in @('Control Panel\International\User Profile','Keyboard Layout\Preload','Keyboard Layout\Substitutes')) {
            $records += [pscustomobject][ordered]@{id="$view/default/$key";view=$view;hive=[uint32]2147483651;key=($TargetUserSid+'\'+$key);mode='tree';name=''}
        }
    }
    $body=[ordered]@{schema_version='yimecore-native-maintenance-catalog-v1';target_user_sid=$TargetUserSid;records=$records}
    [pscustomobject][ordered]@{schema_version=$body.schema_version;target_user_sid=$TargetUserSid;records=$records;catalog_sha256=(Get-YcDigest $body)}
}

# These internal functions have no public provider/root override. Tests replace
# them only inside a freshly imported module, never in the production interface.
function New-YcRegistrySession {
    $session=@{}
    try {
        foreach($view in @(32,64)) {
            $context=New-Object -ComObject WbemScripting.SWbemNamedValueSet
            $session[$view]=[ordered]@{context=$context;locator=$null;services=$null;provider=$null}
            $null=$context.Add('__ProviderArchitecture',$view)
            $null=$context.Add('__RequiredArchitecture',$true)
            $locator=New-Object -ComObject WbemScripting.SWbemLocator; $session[$view].locator=$locator
            $services=$locator.ConnectServer('.','root\default','','','','',0,$context); $session[$view].services=$services
            $services.Security_.ImpersonationLevel=3
            $session[$view].provider=$services.Get('StdRegProv')
        }
        return $session
    } catch {Close-YcRegistrySession $session;throw}
}
function Close-YcRegistrySession($Session) {
    foreach($entry in $Session.Values){foreach($name in @('provider','services','locator','context')){
        $item=$entry[$name]
        if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}
    }}
}
function ConvertFrom-YcWmiProperty($Property) {
    $value=$Property.Value
    if($value -is [DBNull]){return $null}
    # Automation may expose the bit pattern of CIM_UINT32/64 as signed Int32/64.
    # Reinterpret only with the native provider's unsigned CIM type declaration;
    # the evidence parser itself still rejects arbitrary negative input values.
    if(-not $Property.IsArray -and $Property.CIMType -eq 19 -and $value -is [int] -and $value -lt 0){return [BitConverter]::ToUInt32([BitConverter]::GetBytes($value),0)}
    if(-not $Property.IsArray -and $Property.CIMType -eq 21 -and $value -is [long] -and $value -lt 0){return [BitConverter]::ToUInt64([BitConverter]::GetBytes($value),0)}
    return ,$value
}
function Invoke-YcRegistryMethod($Session,$Coordinate,[ValidateSet('EnumKey','EnumValues','GetStringValue','GetBinaryValue','GetDWORDValue','GetMultiStringValue','GetQWORDValue')][string]$Method,[string]$Key,[string]$Name='') {
    if($Key -cne $Coordinate.key -and -not $Key.StartsWith($Coordinate.key+'\',[StringComparison]::Ordinal)){throw 'Read left fixed coordinate'}
    if($Coordinate.mode -ceq 'value' -and ($Key -cne $Coordinate.key -or $Method -ceq 'EnumKey' -or ($Method -cne 'EnumValues' -and $Name -cne $Coordinate.name))){throw 'Read left fixed single value'}
    $entry=$Session[[int]$Coordinate.view];$metadata=$null;$input=$null;$output=$null
    try {
        $metadata=$entry.provider.Methods_.Item($Method);$input=$metadata.InParameters.SpawnInstance_()
        $input.Properties_.Item('hDefKey').Value=[uint32]$Coordinate.hive
        $input.Properties_.Item('sSubKeyName').Value=$Key
        if($Method -notin @('EnumKey','EnumValues')){$input.Properties_.Item('sValueName').Value=$Name}
        $output=$entry.provider.ExecMethod_($Method,$input,0,$entry.context)
        $copy=[ordered]@{}
        foreach($property in $output.Properties_){$copy[[string]$property.Name]=ConvertFrom-YcWmiProperty $property}
        [pscustomobject]$copy
    } finally {
        foreach($item in @($output,$input,$metadata)){if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}}
    }
}
function Assert-YcReturn($Reply,[switch]$AllowAbsent) {
    if($null -eq $Reply -or $null -eq $Reply.PSObject.Properties['ReturnValue']){throw 'Missing provider return value'}
    $code=$Reply.ReturnValue
    if(($code -isnot [int] -and $code -isnot [uint32]) -or ($code -ne 0 -and -not($AllowAbsent -and $code -eq 2))){throw 'StdRegProv error; no process-view fallback'}
}
function Get-YcEnumeration($Session,$Coordinate,[string]$Key,[switch]$Children) {
    $method=if($Children){'EnumKey'}else{'EnumValues'}
    $reply=Invoke-YcRegistryMethod $Session $Coordinate $method $Key
    Assert-YcReturn $reply -AllowAbsent
    if($null -eq $reply.PSObject.Properties['sNames']){throw 'Missing enumeration names field'}
    $names=$reply.sNames
    if($null -ne $names -and $names -isnot [Array]){throw ('Malformed enumeration names: '+$names.GetType().FullName)}
    if($null -eq $names){$names=@()}else{$names=@($names)}
    $types=@()
    if(-not $Children){
        if($null -eq $reply.PSObject.Properties['Types']){throw 'Missing enumeration type field'}
        if($null -ne $reply.Types -and $reply.Types -isnot [Array]){throw 'Malformed enumeration types'}
        if($null -ne $reply.Types){$types=@($reply.Types)}
        if($types.Count -ne $names.Count){throw 'Enumeration names/types mismatch'}
    }
    if($reply.ReturnValue -eq 2 -and ($names.Count -gt 0 -or $types.Count -gt 0)){throw 'Absent key returned values'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows=@()
    for($i=0;$i -lt $names.Count;$i++){
        $name=$names[$i]
        if($name -isnot [string] -or $name.Length -gt 16383 -or $name.Contains([string][char]0) -or -not $seen.Add($name)){throw 'Invalid or duplicate registry name'}
        if($Children -and (-not $name -or $name -match '[\\/]')){throw 'Invalid child key name'}
        $kind=-1
        if(-not $Children){$kind=$types[$i];if(($kind -isnot [int] -and $kind -isnot [uint32]) -or $kind -lt 0 -or $kind -gt 11){throw 'Invalid registry type'}}
        $rows += [pscustomobject]@{name=$name;kind=[int]$kind}
    }
    $ordered=[string[]]@($names);[Array]::Sort($ordered,[StringComparer]::Ordinal)
    $sorted=@();foreach($name in $ordered){$sorted += @($rows | Where-Object {$_.name -ceq $name})}
    [pscustomobject]@{exists=($reply.ReturnValue -eq 0);rows=$sorted}
}
function Get-YcTypedValue($Session,$Coordinate,[string]$Key,$Row) {
    # REG_NONE has no typed StdRegProv getter. REG_EXPAND_SZ expands variables
    # and cannot prove unexpanded preservation; neither is silently coerced.
    $method=switch($Row.kind){1{'GetStringValue'}3{'GetBinaryValue'}4{'GetDWORDValue'}7{'GetMultiStringValue'}11{'GetQWORDValue'}default{throw 'Registry type cannot be captured losslessly by this provider'}}
    $reply=Invoke-YcRegistryMethod $Session $Coordinate $method $Key $Row.name
    Assert-YcReturn $reply
    $property=if($Row.kind -in @(1,7)){'sValue'}else{'uValue'}
    if($null -eq $reply.PSObject.Properties[$property]){throw 'Missing typed provider data'}
    $value=$reply.$property;$data=$null
    switch($Row.kind){
        1 {if($value -isnot [string]){throw 'Invalid REG_SZ'};$data=ConvertTo-YcText $value}
        3 {
            if($value -isnot [Array] -or $value.Count -gt 1048576){throw 'Invalid or ambiguous REG_BINARY'}
            foreach($byte in $value){if(($byte -isnot [byte] -and $byte -isnot [int] -and $byte -isnot [uint32]) -or $byte -lt 0 -or $byte -gt 255){throw 'Invalid binary byte'}}
            $data=[Convert]::ToBase64String([byte[]]$value)
        }
        7 {
            if($value -isnot [Array] -or $value.Count -gt 16384){throw 'Invalid or ambiguous REG_MULTI_SZ'}
            $data=@();foreach($text in $value){if($text -isnot [string]){throw 'Invalid multi-string member'};$data += ConvertTo-YcText $text}
        }
        default {
            $numeric=($value -is [uint64] -or $value -is [uint32] -or $value -is [int64] -or $value -is [int32])
            if(-not $numeric -and ($Row.kind -ne 11 -or $value -isnot [string])){throw 'Invalid unsigned integer provider value'}
            $text=[string]$value
            if($text -cnotmatch '^(0|[1-9][0-9]*)$'){throw 'Noncanonical unsigned integer'}
            $number=[uint64]0
            if(-not [uint64]::TryParse($text,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or ($Row.kind -eq 4 -and $number -gt [uint32]::MaxValue)){throw 'Unsigned integer out of range'}
            $data=$number.ToString([Globalization.CultureInfo]::InvariantCulture)
        }
    }
    [pscustomobject][ordered]@{name_utf16le_base64=(ConvertTo-YcText $Row.name);kind=[int]$Row.kind;data=$data}
}
function Read-YcCoordinateTree($Session,$Coordinate,[string]$Key,[int]$Depth,$Budget) {
    $Budget.nodes++;if($Depth -gt 16 -or $Budget.nodes -gt 4096){throw 'Registry tree exceeds bounded snapshot'}
    $values=Get-YcEnumeration $Session $Coordinate $Key
    $children=if($Coordinate.mode -ceq 'tree'){Get-YcEnumeration $Session $Coordinate $Key -Children}else{$null}
    if($null -ne $children -and $values.exists -ne $children.exists){throw 'Key disappeared during enumeration'}
    $captured=@();$subtrees=@()
    if($values.exists){
        $wanted=@($values.rows)
        if($Coordinate.mode -ceq 'value'){$wanted=@($wanted | Where-Object {$_.name -ieq $Coordinate.name})}
        foreach($row in $wanted){
            $Budget.values++;if($Budget.values -gt 16384){throw 'Registry value count exceeds bound'}
            # Require the exact fixed Run spelling before reading its data.
            if($Coordinate.mode -ceq 'value' -and $row.name -cne $Coordinate.name){throw 'Noncanonical fixed Run value name'}
            $captured += Get-YcTypedValue $Session $Coordinate $Key $row
        }
        if($null -ne $children){foreach($child in $children.rows){
            $tree=Read-YcCoordinateTree $Session $Coordinate ($Key+'\'+$child.name) ($Depth+1) $Budget
            if(-not $tree.exists){throw 'Enumerated child disappeared'}
            $subtrees += [pscustomobject][ordered]@{name_utf16le_base64=(ConvertTo-YcText $child.name);tree=$tree}
        }}
    }
    $again=Get-YcEnumeration $Session $Coordinate $Key
    if((Get-YcDigest $again) -cne (Get-YcDigest $values)){throw 'Value membership/type changed during snapshot'}
    if($null -ne $children){$againChildren=Get-YcEnumeration $Session $Coordinate $Key -Children;if((Get-YcDigest $againChildren) -cne (Get-YcDigest $children)){throw 'Subkey membership changed during snapshot'}}
    [pscustomobject][ordered]@{exists=[bool]$values.exists;values=$captured;children=$subtrees}
}
function Get-YimeCoreNativeMaintenanceSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$TargetUserSid)
    $catalog=Get-YimeCoreNativeMaintenanceRegistryCatalog $TargetUserSid
    if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $TargetUserSid){throw 'Initiating SID differs from current token'}
    if(-not [Environment]::Is64BitOperatingSystem){throw 'Both native 32/64 provider views are required'}
    $source=(Get-FileHash -LiteralPath $script:YcEvidenceSource -Algorithm SHA256).Hash.ToLowerInvariant()
    $session=New-YcRegistrySession
    try {
        $passes=@()
        foreach($pass in @(1,2)) {
            $records=@();$budget=@{nodes=0;values=0}
            foreach($coordinate in $catalog.records){$records += [pscustomobject][ordered]@{id=$coordinate.id;tree=(Read-YcCoordinateTree $session $coordinate $coordinate.key 0 $budget)}}
            $passes += ,$records
        }
        if((Get-YcDigest $passes[0]) -cne (Get-YcDigest $passes[1])){throw 'Registry changed between complete observations'}
        if((Get-FileHash -LiteralPath $script:YcEvidenceSource -Algorithm SHA256).Hash.ToLowerInvariant() -cne $source){throw 'Evidence source changed'}
        $body=[ordered]@{schema_version='yimecore-native-maintenance-snapshot-v1';target_user_sid=$TargetUserSid;catalog_sha256=$catalog.catalog_sha256;source_sha256=$source;provider='StdRegProv-required-32-and-64';two_pass_equal=$true;atomic=$false;continuous_monitoring=$false;registry_link_identity_verified=$false;records=$passes[1]}
        $body['snapshot_sha256']=Get-YcDigest $body
        [pscustomobject]$body
    } finally {Close-YcRegistrySession $session}
}
function Assert-YcSnapshotTree($Tree,[int]$Depth,$Budget) {
    Assert-YcFields $Tree @('exists','values','children')
    $Budget.nodes++;if($Depth -gt 16 -or $Budget.nodes -gt 4096){throw 'Invalid evidence tree size'}
    if($Tree.exists -isnot [bool] -or $Tree.values -isnot [Array] -or $Tree.children -isnot [Array]){throw 'Invalid evidence tree types'}
    if(-not $Tree.exists -and ($Tree.values.Count -gt 0 -or $Tree.children.Count -gt 0)){throw 'Absent evidence tree is not empty'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $Tree.values){
        $Budget.values++;if($Budget.values -gt 16384){throw 'Invalid evidence value count'}
        Assert-YcFields $row @('name_utf16le_base64','kind','data');Assert-YcText $row.name_utf16le_base64
        $name=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($row.name_utf16le_base64))
        if(-not $seen.Add($name)){throw 'Duplicate evidence value'}
        if(($row.kind -isnot [int] -and $row.kind -isnot [long]) -or $row.kind -notin @(1,3,4,7,11)){throw 'Unsupported evidence value type'}
        switch($row.kind){
            1 {Assert-YcText $row.data}
            3 {if($row.data -isnot [string]){throw 'Invalid binary evidence'};$bytes=[Convert]::FromBase64String($row.data);if([Convert]::ToBase64String($bytes) -cne $row.data){throw 'Noncanonical binary evidence'}}
            7 {if($row.data -isnot [Array]){throw 'Invalid multisz evidence'};foreach($text in $row.data){Assert-YcText $text}}
            default {if($row.data -isnot [string] -or $row.data -cnotmatch '^(0|[1-9][0-9]*)$'){throw 'Invalid integer evidence'};$number=[uint64]::Parse($row.data,[Globalization.CultureInfo]::InvariantCulture);if($row.kind -eq 4 -and $number -gt [uint32]::MaxValue){throw 'DWORD evidence overflow'}}
        }
    }
    $seen.Clear()
    foreach($child in $Tree.children){
        Assert-YcFields $child @('name_utf16le_base64','tree');Assert-YcText $child.name_utf16le_base64
        $name=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($child.name_utf16le_base64))
        if(-not $name -or $name -match '[\\/\x00]' -or -not $seen.Add($name)){throw 'Invalid evidence child name'}
        Assert-YcSnapshotTree $child.tree ($Depth+1) $Budget
        if(-not $child.tree.exists){throw 'Missing listed evidence child'}
    }
}
function Assert-YcSnapshot($Snapshot) {
    Assert-YcFields $Snapshot @('schema_version','target_user_sid','catalog_sha256','source_sha256','provider','two_pass_equal','atomic','continuous_monitoring','registry_link_identity_verified','records','snapshot_sha256')
    foreach($name in @('schema_version','target_user_sid','catalog_sha256','source_sha256','provider','snapshot_sha256')){if($Snapshot.$name -isnot [string]){throw 'Snapshot metadata requires literal strings'}}
    if($Snapshot.schema_version -cne 'yimecore-native-maintenance-snapshot-v1' -or $Snapshot.provider -cne 'StdRegProv-required-32-and-64' -or
        $Snapshot.two_pass_equal -isnot [bool] -or -not $Snapshot.two_pass_equal -or $Snapshot.atomic -isnot [bool] -or $Snapshot.atomic -or
        $Snapshot.continuous_monitoring -isnot [bool] -or $Snapshot.continuous_monitoring -or
        $Snapshot.registry_link_identity_verified -isnot [bool] -or $Snapshot.registry_link_identity_verified -or
        $Snapshot.source_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Snapshot.snapshot_sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Unsupported snapshot provenance'}
    $catalog=Get-YimeCoreNativeMaintenanceRegistryCatalog $Snapshot.target_user_sid
    if($Snapshot.catalog_sha256 -cne $catalog.catalog_sha256 -or $Snapshot.records -isnot [Array] -or $Snapshot.records.Count -ne $catalog.records.Count){throw 'Snapshot catalog closure mismatch'}
    $budget=@{nodes=0;values=0}
    for($i=0;$i -lt $catalog.records.Count;$i++){
        $row=$Snapshot.records[$i];Assert-YcFields $row @('id','tree')
        if($row.id -isnot [string] -or $row.id -cne $catalog.records[$i].id){throw 'Snapshot coordinate/view missing or reordered'}
        Assert-YcSnapshotTree $row.tree 0 $budget
        if($catalog.records[$i].mode -ceq 'value'){
            if($row.tree.children.Count -ne 0 -or $row.tree.values.Count -gt 1){throw 'Single-value evidence exceeds boundary'}
            if($row.tree.values.Count -eq 1 -and $row.tree.values[0].name_utf16le_base64 -cne (ConvertTo-YcText $catalog.records[$i].name)){throw 'Wrong fixed value in snapshot'}
        }
    }
    $body=[ordered]@{};foreach($name in @('schema_version','target_user_sid','catalog_sha256','source_sha256','provider','two_pass_equal','atomic','continuous_monitoring','registry_link_identity_verified','records')){$body[$name]=$Snapshot.$name}
    if((Get-YcDigest $body) -cne $Snapshot.snapshot_sha256){throw 'Snapshot digest mismatch'}
}
function Assert-YimeCoreNativeMaintenanceSnapshotEqual {
    [CmdletBinding()]param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After)
    Assert-YcSnapshot $Before;Assert-YcSnapshot $After
    if($Before.snapshot_sha256 -cne $After.snapshot_sha256){throw 'Native typed registry snapshots differ'}
    [pscustomobject]@{equal=$true;catalog_sha256=$Before.catalog_sha256;snapshot_sha256=$Before.snapshot_sha256;atomic=$false;continuous_monitoring=$false;registry_link_identity_verified=$false}
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceRegistryCatalog,Get-YimeCoreNativeMaintenanceSnapshot,Assert-YimeCoreNativeMaintenanceSnapshotEqual
