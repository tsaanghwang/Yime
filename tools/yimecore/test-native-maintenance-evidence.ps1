[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath,[switch]$RunNativeFixture)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Use new repository .tmp evidence output'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-evidence.psm1'
$module=Import-Module $modulePath -Force -PassThru
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body | Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body | Out-Null}catch{$failed=$true};Require $failed 'Expected rejection'}
$catalog=Get-YimeCoreNativeMaintenanceRegistryCatalog $sid
Check 'fixed-46-coordinate-dual-view-catalog' {Require ($catalog.records.Count -eq 46) 'Catalog count';foreach($v in @(32,64)){Require (@($catalog.records | Where-Object view -eq $v).Count -eq 23) 'Missing view'}}
Check 'fixed-three-identities-and-narrow-run' {
    foreach($clsid in @('{E40FA752-BB96-461D-A51D-F40EB437EC65}','{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}','{35F67E9D-A54D-4177-9697-8B0AB71A9E04}')){Require (@($catalog.records | Where-Object {$_.key.Contains($clsid)}).Count -eq 8) 'Identity incomplete'}
    foreach($row in @($catalog.records | Where-Object mode -eq 'value')){Require ($row.name -in @('YimeCoreExperimentalTrial','PIMELauncher') -and $row.key.EndsWith('\Run')) 'Run boundary'}
    Require (@($catalog.records | Where-Object {$_.key.Contains('Control Panel\International\User Profile')}).Count -eq 2) 'Default override metadata absent'
}
Check 'catalog-hash-deterministic' {Require ((Get-YimeCoreNativeMaintenanceRegistryCatalog $sid).catalog_sha256 -ceq $catalog.catalog_sha256) 'Catalog digest unstable'}
foreach($bad in @('S-1-5-18','S-1-5-21-1-2-3-04','S-1-5-21-1-2-3-4\Software','HKCU','')){Check ('reject-sid-'+$bad){Reject {Get-YimeCoreNativeMaintenanceRegistryCatalog $bad}}}
Check 'no-public-provider-or-root-override' {
    $cmd=Get-Command Get-YimeCoreNativeMaintenanceSnapshot
    foreach($name in @('Provider','Root','Hive','Key','ScriptBlock')){Require (-not $cmd.Parameters.ContainsKey($name)) 'Unexpected public override'}
    Require (@($module.ExportedFunctions.Keys).Count -eq 3) 'Export surface expanded'
}
Check 'wmi-declared-unsigned-bit-patterns-preserved' {
    $dword=& $module {ConvertFrom-YcWmiProperty ([pscustomobject]@{Value=[int]-1;CIMType=19;IsArray=$false})}
    $qword=& $module {ConvertFrom-YcWmiProperty ([pscustomobject]@{Value=[long]-1;CIMType=21;IsArray=$false})}
    Require ($dword -is [uint32] -and $dword -eq [uint32]::MaxValue) 'CIM UINT32 bits changed'
    Require ($qword -is [uint64] -and $qword -eq [uint64]::MaxValue) 'CIM UINT64 bits changed'
    $signed=& $module {ConvertFrom-YcWmiProperty ([pscustomobject]@{Value=[int]-1;CIMType=3;IsArray=$false})}
    Require ($signed -eq -1) 'Undeclared signed value reinterpreted'
}
Check 'wmi-null-and-single-member-array-shape-preserved' {
    $value=& $module {ConvertFrom-YcWmiProperty ([pscustomobject]@{Value=[string[]]@('one');CIMType=8;IsArray=$true})}
    Require ($value -is [Array] -and $value.Count -eq 1) 'WMI array was unwrapped'
    $empty=& $module {ConvertFrom-YcWmiProperty ([pscustomobject]@{Value=[DBNull]::Value;CIMType=8;IsArray=$true})}
    Require ($null -eq $empty) 'WMI empty field not normalized'
}

$nativeResults=@()
if($RunNativeFixture){
    # Only this script's fresh exact HKU subtree may be created/deleted. Reads
    # exercise the same internal provider/typed reader, never product catalog.
    $fixtureKey=$sid+'\Software\YimeCoreTests\NativeEvidence-'+[guid]::NewGuid().ToString('N')
    $nativeSession=& $module {New-YcRegistrySession}
    function Fixture-Write([int]$View,[string]$Method,$Values){
        if($fixtureKey -cnotmatch ('^'+[regex]::Escape($sid)+'\\Software\\YimeCoreTests\\NativeEvidence-[a-f0-9]{32}$')){throw 'Unsafe native fixture target'}
        $entry=$nativeSession[$View];$meta=$null;$input=$null;$reply=$null
        try{
            $meta=$entry.provider.Methods_.Item($Method);$input=$meta.InParameters.SpawnInstance_()
            $input.Properties_.Item('hDefKey').Value=[uint32]2147483651;$input.Properties_.Item('sSubKeyName').Value=$fixtureKey
            if($Method -notin @('CreateKey','DeleteKey')){$input.Properties_.Item('sValueName').Value=[string]$Values.sValueName}
            # Separate typed COM setter call sites avoid caching a string
            # setter for byte/multisz arrays. No arbitrary setter is accepted.
            switch($Method){
                CreateKey {}
                DeleteKey {}
                DeleteValue {}
                SetStringValue {$input.Properties_.Item('sValue').Value=[string]$Values.sValue}
                SetBinaryValue {$input.Properties_.Item('uValue').Value=[byte[]]$Values.uValue}
                SetDWORDValue {$input.Properties_.Item('uValue').Value=[uint32]$Values.uValue}
                SetQWORDValue {$input.Properties_.Item('uValue').Value=[string]$Values.uValue}
                SetMultiStringValue {$input.Properties_.Item('sValue').Value=[string[]]$Values.sValue}
                SetExpandedStringValue {$input.Properties_.Item('sValue').Value=[string]$Values.sValue}
                default {throw 'Unsupported fixture writer method'}
            }
            $reply=$entry.provider.ExecMethod_($Method,$input,0,$entry.context)
            $code=$reply.Properties_.Item('ReturnValue').Value
            if($null -eq $code -or ($code -ne 0 -and -not($Method -ceq 'DeleteKey' -and $code -eq 2))){throw "Native fixture $Method view $View returned $code"}
        }finally{foreach($item in @($reply,$input,$meta)){if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}}}
    }
    try{
        foreach($view in @(32,64)){
            Fixture-Write $view 'CreateKey' @{}
            Fixture-Write $view 'SetStringValue' @{sValueName='Text';sValue='synthetic %TEMP% string'}
            Fixture-Write $view 'SetBinaryValue' @{sValueName='Binary';uValue=[byte[]]@(0,1,255)}
            Fixture-Write $view 'SetDWORDValue' @{sValueName='DWORD';uValue=[uint32]::MaxValue}
            Fixture-Write $view 'SetQWORDValue' @{sValueName='QWORD';uValue='18446744073709551615'}
            Fixture-Write $view 'SetMultiStringValue' @{sValueName='Multi';sValue=[string[]]@('first','second')}
            Check "native-$view-typed-random-fixture" {
                $coordinate=[pscustomobject]@{view=$view;hive=[uint32]2147483651;key=$fixtureKey;mode='tree';name=''}
                $tree=& $module {param($s,$c) Read-YcCoordinateTree $s $c $c.key 0 @{nodes=0;values=0}} $nativeSession $coordinate
                Require ($tree.exists -and $tree.values.Count -eq 5) 'Native typed fixture incomplete'
                $encodedText=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('synthetic %TEMP% string'))
                Require (@($tree.values | Where-Object {$_.kind -eq 1 -and $_.data -ceq $encodedText}).Count -eq 1) 'Native REG_SZ changed or expanded'
                Require (@($tree.values | Where-Object {$_.kind -eq 3 -and $_.data -ceq 'AAH/'}).Count -eq 1) 'Native REG_BINARY changed'
                Require (@($tree.values | Where-Object {$_.kind -eq 4 -and $_.data -ceq '4294967295'}).Count -eq 1) 'Native DWORD lost unsigned bits'
                $multi=@($tree.values | Where-Object kind -eq 7)
                Require ($multi.Count -eq 1 -and ($multi[0].data -join '|') -ceq 'ZgBpAHIAcwB0AA==|cwBlAGMAbwBuAGQA') 'Native multisz order or values changed'
                Require (@($tree.values | Where-Object {$_.kind -eq 11 -and $_.data -ceq '18446744073709551615'}).Count -eq 1) 'QWORD lost precision'
                $script:nativeResults += [ordered]@{view=$view;typed_values=5;qword_max_preserved=$true;random_fixture_only=$true}
            }
            Fixture-Write $view 'SetExpandedStringValue' @{sValueName='Expand';sValue='%TEMP%'}
            Check "native-$view-expand-rejected" {
                $coordinate=[pscustomobject]@{view=$view;hive=[uint32]2147483651;key=$fixtureKey;mode='tree';name=''}
                Reject {& $module {param($s,$c) Read-YcCoordinateTree $s $c $c.key 0 @{nodes=0;values=0}} $nativeSession $coordinate}
            }
            Fixture-Write $view 'DeleteValue' @{sValueName='Expand'}
        }
    } finally {try {
        foreach($view in @(32,64)){Fixture-Write $view 'DeleteKey' @{}}
        foreach($view in @(32,64)){Check "native-$view-cleanup-verified" {
            $coordinate=[pscustomobject]@{view=$view;hive=[uint32]2147483651;key=$fixtureKey;mode='tree';name=''}
            $entry=& $module {param($s,$c) Get-YcEnumeration $s $c $c.key} $nativeSession $coordinate
            Require (-not $entry.exists -and $entry.rows.Count -eq 0) 'Native random fixture remained'
        }}
    }finally{& $module {param($s) Close-YcRegistrySession $s} $nativeSession}}
}

& $module {
    $script:mode='valid';$script:calls=[Collections.Generic.List[object]]::new();$script:passReads=0;$script:textReads=0
    function script:New-YcRegistrySession { @{} }
    function script:Close-YcRegistrySession($Session) {}
    function script:Invoke-YcRegistryMethod($Session,$Coordinate,$Method,$Key,$Name=''){
        $script:calls.Add([pscustomobject]@{id=$Coordinate.id;method=$Method;key=$Key;name=$Name;view=$Coordinate.view})
        if($script:mode -ceq 'provider_throw'){throw 'synthetic provider exception'}
        if($script:mode -ceq 'provider_null'){return $null}
        if($script:mode -ceq 'provider_nonzero'){return [pscustomobject]@{ReturnValue=5}}
        if($script:mode -ceq 'provider_string_code'){return [pscustomobject]@{ReturnValue='0'}}
        if($script:mode -ceq 'provider_missing_code'){return [pscustomobject]@{sNames=$null;Types=$null}}
        if($script:mode -ceq 'provider_unknown'){return [pscustomobject]@{ReturnValue=87}}
        $target=($Coordinate.id -match '/active/com$' -and $Coordinate.hive -eq 2147483650)
        $isRun=($Coordinate.mode -ceq 'value')
        $child=$Key.EndsWith('\Child')
        if($Method -ceq 'EnumKey'){
            if($script:mode -ceq 'child_nonzero' -and $target){return [pscustomobject]@{ReturnValue=5;sNames=$null}}
            if($script:mode -ceq 'absent_disagreement' -and $target){return [pscustomobject]@{ReturnValue=2;sNames=$null}}
            $names=$null;if($target -and -not $child){$names=[string[]]@('Child')}
            if($script:mode -ceq 'invalid_child' -and $target -and -not $child){$names=[string[]]@('..\escape')}
            return [pscustomobject]@{ReturnValue=[int]$(if($target){0}else{2});sNames=$names}
        }
        if($Method -ceq 'EnumValues'){
            if($target){
                if($child){return [pscustomobject]@{ReturnValue=0;sNames=[string[]]@('Enable');Types=[int[]]@(4)}}
                $names=[string[]]@('Text','Binary','DWORD','Multi','QWORD');$types=[int[]]@(1,3,4,7,11)
                switch($script:mode){
                    'missing_types' {return [pscustomobject]@{ReturnValue=0;sNames=$names}}
                    'null_types' {$types=$null}
                    'scalar_names' {return [pscustomobject]@{ReturnValue=0;sNames='Text';Types=[int[]]@(1)}}
                    'duplicate_names' {$names[1]='text'}
                    'bad_type' {return [pscustomobject]@{ReturnValue=0;sNames=[string[]]@('Text');Types=@('1')}}
                    'reg_none' {$types[0]=0}
                    'reg_expand' {$types[0]=2}
                    'reg_link' {$types[0]=6}
                    'unknown_type' {$types[0]=12}
                    'view_missing' {if($Coordinate.view -eq 64){return [pscustomobject]@{ReturnValue=5;sNames=$null;Types=$null}}}
                    'membership_changed' {$script:passReads++;if($script:passReads -gt 1){$names=$names[0..3];$types=$types[0..3]}}
                }
                return [pscustomobject]@{ReturnValue=0;sNames=$names;Types=$types}
            }
            if($isRun){return [pscustomobject]@{ReturnValue=0;sNames=[string[]]@($Coordinate.name,'OtherPrivateApp');Types=[int[]]@(1,2)}}
            if($script:mode -ceq 'absent_with_rows'){return [pscustomobject]@{ReturnValue=2;sNames=[string[]]@('Unexpected');Types=[int[]]@(1)}}
            return [pscustomobject]@{ReturnValue=2;sNames=$null;Types=$null}
        }
        if($Name -ceq 'OtherPrivateApp'){throw 'Unrelated Run value was read'}
        if($script:mode -ceq 'getter_nonzero'){return [pscustomobject]@{ReturnValue=2;sValue=$null;uValue=$null}}
        if($script:mode -ceq 'getter_null'){return [pscustomobject]@{ReturnValue=0;sValue=$null;uValue=$null}}
        if($script:mode -ceq 'getter_missing'){return [pscustomobject]@{ReturnValue=0}}
        switch($Method){
            GetStringValue {$value='synthetic '+$Name;if($Name -ceq 'Text'){$script:textReads++;if($script:mode -ceq 'two_pass_value_changed' -and $script:textReads -gt 2){$value='changed between full passes'}};if($script:mode -ceq 'string_number'){$value=123};if($script:mode -ceq 'unpaired_high'){$value=[string][char]0xD800};if($script:mode -ceq 'unpaired_low'){$value=[string][char]0xDC00};[pscustomobject]@{ReturnValue=0;sValue=$value}}
            GetBinaryValue {$value=[byte[]]@(0,1,255);if($script:mode -ceq 'binary_bad'){$value=@(256)};[pscustomobject]@{ReturnValue=0;uValue=$value}}
            GetDWORDValue {$value=[uint32]::MaxValue;if($Name -ceq 'Enable'){$value=[uint32]1};if($script:mode -ceq 'dword_negative'){$value=-1};if($script:mode -ceq 'dword_overflow'){$value=[uint64]4294967296};if($script:mode -ceq 'dword_bool'){$value=$true};[pscustomobject]@{ReturnValue=0;uValue=$value}}
            GetMultiStringValue {$value=[string[]]@('first','','last');if($script:mode -ceq 'multi_bad'){$value=@('first',1)};[pscustomobject]@{ReturnValue=0;sValue=$value}}
            GetQWORDValue {$value='18446744073709551615';if($script:mode -ceq 'qword_float'){$value=[double]1};if($script:mode -ceq 'qword_overflow'){$value='18446744073709551616'};if($script:mode -ceq 'qword_leading_zero'){$value='01'};[pscustomobject]@{ReturnValue=0;uValue=$value}}
            default {throw 'Unexpected fixture method'}
        }
    }
}
function Set-Mode([string]$Name){& $module {param($m) $script:mode=$m;$script:calls.Clear();$script:passReads=0;$script:textReads=0} $Name}
$baseline=$null
Check 'mocked-whole-catalog-two-pass-typed-snapshot' {Set-Mode valid;$script:baseline=Get-YimeCoreNativeMaintenanceSnapshot $sid;Require ($baseline.records.Count -eq 46 -and $baseline.two_pass_equal -and -not $baseline.atomic) 'Incomplete snapshot'}
Check 'mocked-only-exact-run-value-data-read' {$calls=& $module {$script:calls.ToArray()};Require (@($calls | Where-Object {$_.name -ceq 'OtherPrivateApp'}).Count -eq 0) 'Private Run value read';Require (@($calls | Where-Object {$_.key.Contains('\Run\')}).Count -eq 0) 'Run descendants read'}
Check 'mocked-qword-binary-multisz-types-preserved' {
    $values=$baseline.records[0].tree.values
    Require (@($values | Where-Object {$_.kind -eq 11 -and $_.data -ceq '18446744073709551615'}).Count -eq 1) 'QWORD precision'
    Require (@($values | Where-Object {$_.kind -eq 3 -and $_.data -ceq 'AAH/'}).Count -eq 1) 'Binary representation'
    Require (@($values | Where-Object {$_.kind -eq 7 -and $_.data.Count -eq 3 -and $_.data[1] -ceq ''}).Count -eq 1) 'Multisz order/empty member'
    Require ($baseline.records[0].tree.children.Count -eq 1) 'Subtree omitted'
}
foreach($mode in @('provider_throw','provider_null','provider_nonzero','provider_string_code','provider_missing_code','provider_unknown','child_nonzero','absent_disagreement','invalid_child','missing_types','null_types','scalar_names','duplicate_names','bad_type','reg_none','reg_expand','reg_link','unknown_type','view_missing','membership_changed','two_pass_value_changed','absent_with_rows','getter_nonzero','getter_null','getter_missing','string_number','unpaired_high','unpaired_low','binary_bad','dword_negative','dword_overflow','dword_bool','multi_bad','qword_float','qword_overflow','qword_leading_zero')){
    Check ('reject-'+$mode){Set-Mode $mode;Reject {Get-YimeCoreNativeMaintenanceSnapshot $sid}}
}
Check 'compare-serialized-identical-snapshot' {$copy=$baseline | ConvertTo-Json -Depth 80 | ConvertFrom-Json;Require (Assert-YimeCoreNativeMaintenanceSnapshotEqual $baseline $copy).equal 'Roundtrip rejected'}
function Clone-Snapshot {$baseline | ConvertTo-Json -Depth 80 | ConvertFrom-Json}
function Rehash($Value){& $module {param($v) $b=[ordered]@{};foreach($n in @('schema_version','target_user_sid','catalog_sha256','source_sha256','provider','two_pass_equal','atomic','continuous_monitoring','registry_link_identity_verified','records')){$b[$n]=$v.$n};$v.snapshot_sha256=Get-YcDigest $b} $Value}
foreach($kind in @('missing_view','kind_changed','value_changed','child_removed','catalog_changed','source_changed','string_true','raw_digest_changed','extra_field','wrong_run_name','extra_run_child','missing_field','qword_noncanonical','unpaired_utf16','link_attestation_true','link_attestation_string')){
    Check ('compare-reject-'+$kind){
        $changed=Clone-Snapshot
        switch($kind){
            missing_view {$changed.records=@($changed.records | Where-Object {$_.id -notlike '64/*'})}
            kind_changed {$dword=@($changed.records[0].tree.values | Where-Object kind -eq 4)[0];$dword.kind=11}
            value_changed {$changed.records[0].tree.values[0].data='AAA='}
            child_removed {$changed.records[0].tree.children=@()}
            catalog_changed {$changed.catalog_sha256='a'*64}
            source_changed {$changed.source_sha256='a'*64}
            string_true {$changed.two_pass_equal='true'}
            raw_digest_changed {$changed.snapshot_sha256='a'*64}
            extra_field {$changed | Add-Member extra $true}
            wrong_run_name {$run=@($changed.records | Where-Object {$_.id.EndsWith('/run')})[0];$run.tree.values[0].name_utf16le_base64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('OtherPrivateApp'))}
            extra_run_child {$run=@($changed.records | Where-Object {$_.id.EndsWith('/run')})[0];$run.tree.children=$changed.records[0].tree.children}
            missing_field {$changed.PSObject.Properties.Remove('records')}
            qword_noncanonical {$q=@($changed.records[0].tree.values | Where-Object kind -eq 11)[0];$q.data='01'}
            unpaired_utf16 {$text=@($changed.records[0].tree.values | Where-Object kind -eq 1)[0];$text.data='ANg='}
            link_attestation_true {$changed.registry_link_identity_verified=$true}
            link_attestation_string {$changed.registry_link_identity_verified='false'}
        }
        if($kind -notin @('raw_digest_changed','missing_field')){Rehash $changed}
        if($kind -in @('unpaired_utf16','link_attestation_true','link_attestation_string')){Reject {Assert-YimeCoreNativeMaintenanceSnapshotEqual $changed $changed}}
        else {Reject {Assert-YimeCoreNativeMaintenanceSnapshotEqual $baseline $changed}}
    }
}
foreach($field in @('schema_version','target_user_sid','catalog_sha256','source_sha256','provider','snapshot_sha256')){
    foreach($count in @(1,2)){Check ("compare-reject-array-metadata-$field-$count"){$changed=Clone-Snapshot;$changed.$field=@($changed.$field)*$count;if($field -cne 'snapshot_sha256'){Rehash $changed};Reject {Assert-YimeCoreNativeMaintenanceSnapshotEqual $changed $changed}}}
}
$failed=@($checks | Where-Object {-not $_.passed})
$result=[ordered]@{schema_version='yimecore-native-maintenance-evidence-tests-v1';passed=($failed.Count -eq 0);powershell=$PSVersionTable.PSVersion.ToString();checks_count=$checks.Count;failed_count=$failed.Count;checks=$checks.ToArray();catalog_sha256=$catalog.catalog_sha256;mock_snapshot_sha256=if($null -ne $baseline){$baseline.snapshot_sha256}else{$null};native_random_fixture_executed=[bool]$RunNativeFixture;native_results=$nativeResults;product_registry_read=$false;product_registry_written=$false;installer_or_installed_product_executed=$false;user_data_read=$false;source_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant();test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();unsupported_types_fail_closed=@('REG_NONE','REG_EXPAND_SZ','REG_LINK','other unsupported kinds');limitation='Two consistent read passes are not an atomic snapshot or a monitor for transient changes; fixture success is not product-system acceptance.'}
[IO.File]::WriteAllText($out,(($result | ConvertTo-Json -Depth 12).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Native maintenance evidence: $($checks.Count) checks, $($failed.Count) failed; $out"
if($failed.Count){$failed | ForEach-Object {[pscustomobject]$_} | Format-Table name,error -AutoSize;exit 1}
