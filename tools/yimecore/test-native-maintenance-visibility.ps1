[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath,[switch]$RunNativeFixture)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\');$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp test output required'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory((Split-Path -Parent $out))|Out-Null
$fixture=Join-Path $repo ('.tmp\native-visibility-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($fixture)|Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-visibility.psm1';$module=Import-Module $modulePath -Force -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body|Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Require $failed 'Expected rejection'}
function Clone($Value){ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 30)}
function Write-Fixture([string]$Path,[string]$Value){[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
function Record([string]$Path){[pscustomobject][ordered]@{path=$Path;bytes=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}}
function Observe($Rows=$expected,$Root=$fixture){Get-YimeCoreNativeMaintenanceFileVisibility -ApprovedRoot $Root -ExpectedFiles $Rows}
$a=Join-Path $fixture 'package-manifest.json';$b=Join-Path $fixture 'backup-manifest.json'
Write-Fixture $a 'PRIVATE METADATA BODY A';Write-Fixture $b 'PRIVATE METADATA BODY B'
$expected=@((Record $a),(Record $b))
& $module {
    $script:SavedVisibilityOpen=${function:Open-VisibilityProvider};$script:SavedVisibilityQuery=${function:Invoke-VisibilityQuery};$script:SavedVisibilityClose=${function:Close-VisibilityProvider}
    $script:VisibilityTestMode='normal';$script:VisibilityTestPatch=$null;$script:VisibilityTestQueries=0;$script:VisibilityTestClosed=0
    function script:Open-VisibilityProvider {
        if($script:VisibilityTestMode -ceq 'open-error'){throw 'Synthetic provider error'}
        if($script:VisibilityTestMode -ceq 'open-null'){return $null}
        return @{fixture=$true}
    }
    function script:Close-VisibilityProvider($Session){if($null -ne $Session){$script:VisibilityTestClosed++}}
    function script:Invoke-VisibilityQuery($Session,[string]$Path){
        $script:VisibilityTestQueries++
        if($script:VisibilityTestMode -ceq 'query-error'){throw 'Synthetic query error'}
        if($script:VisibilityTestMode -ceq 'query-null'){return $null}
        if($script:VisibilityTestMode -ceq 'query-empty'){return ,@()}
        function Property([string]$Name,[int]$Type,$Value){[pscustomobject][ordered]@{name=$Name;cim_type=$Type;is_array=$false;value=$Value}}
        $row=[pscustomobject][ordered]@{object_path=[pscustomobject][ordered]@{class='CIM_DataFile';is_class=$false;server=[Environment]::MachineName;namespace='root\cimv2'};
            name=(Property 'Name' 8 $Path);file_size=(Property 'FileSize' 21 ([string](Get-Item -LiteralPath $Path).Length))}
        if($null -ne $script:VisibilityTestPatch){& $script:VisibilityTestPatch $row $Path}
        if($script:VisibilityTestMode -ceq 'query-multiple'){return ,@($row,$row)}
        if($script:VisibilityTestMode -ceq 'query-scalar'){return $row}
        return ,@($row)
    }
}
function Mode([string]$Value){& $module {param($mode)$script:VisibilityTestMode=$mode} $Value}
function With-Patch([scriptblock]$Patch,[scriptblock]$Body){
    & $module {param($patch)$script:VisibilityTestPatch=$patch} $Patch
    try{& $Body}finally{& $module {$script:VisibilityTestPatch=$null}}
}
$native=[ordered]@{requested=[bool]$RunNativeFixture;attempted=$false;passed=$false;provider_error=$null;metadata=$null;only_owned_fixture_files=$true;acceptance_inferred=$false}
try{
    $receipt=Observe
    Check 'explicit-two-file-observation' {Require ($receipt.file_count -eq 2 -and $receipt.records.Count -eq 2 -and $receipt.system_metadata_visible -and $receipt.bound_metadata) 'Missing bound system metadata'}
    Check 'only-local-hashes-and-minimal-system-metadata-returned' {
        $text=ConvertTo-Json -InputObject $receipt -Depth 30
        Require (-not $text.Contains('PRIVATE METADATA BODY')) 'Metadata body escaped'
        foreach($row in $receipt.records){Require ($row.local_sha256 -cmatch '^[a-f0-9]{64}$' -and $row.local_file_identity -cmatch '^[a-f0-9]{8}:[a-f0-9]{16}$' -and $row.system_metadata.class -ceq 'CIM_DataFile') 'Missing native binding'}
    }
    foreach($flag in @('independent_content_hash_verified','independent_file_identity_verified','expected_manifest_origin_authenticated','loaded_provider_identity_authenticated','continuous_membership_protection','atomic','execution_authorized','ready_to_execute','full_acceptance','L6_sealed','local_product_ready','public_release_ready')){
        Check ('honest-false-'+$flag){Require ($receipt.$flag -is [bool] -and -not $receipt.$flag) 'Unsupported acceptance claim'}
    }
    Check 'public-api-has-no-provider-or-session-override' {
        Require (@($module.ExportedFunctions.Keys).Count -eq 1) 'Unexpected export'
        $command=Get-Command Get-YimeCoreNativeMaintenanceFileVisibility
        foreach($name in @('Provider','Session','Query','Read','NativeType','ExpectedHost','AllowedLeaf')){Require (-not $command.Parameters.ContainsKey($name)) 'Public provider override'}
    }
    Check 'private-random-native-type-identity' {
        $valid=& $module {$script:VisibilityFactsType.Namespace -cmatch '^Yime\.Visibility_[a-f0-9]{32}$' -and $script:VisibilityPathsType.Namespace -ceq $script:VisibilityFactsType.Namespace}
        Require $valid 'Native helper type is globally adopted'
    }
    Check 'actual-query-with-base-SWbemObject-Path-and-no-Ex-SystemProperties' {
        function Native-Property([string]$Name,[int]$Type,$Value){[pscustomobject]@{Name=$Name;CIMType=$Type;IsArray=$false;Value=$Value}}
        $objectPath=[pscustomobject]@{Class='CIM_DataFile';IsClass=$false;Server=[Environment]::MachineName;Namespace='root\cimv2'}
        $data=[pscustomobject]@{map=@{'Name'=(Native-Property 'Name' 8 $a);'FileSize'=(Native-Property 'FileSize' 21 ([string]$expected[0].bytes))}}
        $data|Add-Member -MemberType ScriptMethod -Name Item -Value {param($name)if(-not $this.map.ContainsKey($name)){throw 'Unavailable SWbemProperty'};$this.map[$name]}
        # Model the actual COM ABI: a non-enumerable SWbemObjectSet with Count
        # and ItemIndex, not an array that PowerShell can silently unwrap.
        $set=[pscustomobject]@{Count=[int]1;item_calls=0;items=@([pscustomobject]@{Path_=$objectPath;Properties_=$data})}
        $set|Add-Member -MemberType ScriptMethod -Name ItemIndex -Value {param($index)$this.item_calls++;if($index -isnot [int] -or $index -ne 0){throw 'Unexpected item index'};return $this.items[$index]}
        $services=[pscustomobject]@{query=$null;language=$null;flags=$null;result=$set}
        $services|Add-Member -MemberType ScriptMethod -Name ExecQuery -Value {param($query,$language,$flags)$this.query=$query;$this.language=$language;$this.flags=$flags;return $this.result}
        $rows=& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a
        $actual=& $module {param($r,$p,$b)Assert-VisibilityReply $r $p $b} $rows $a $expected[0].bytes
        Require ($actual.bytes -eq $expected[0].bytes -and $services.query -ceq ("SELECT Name, FileSize FROM CIM_DataFile WHERE Name='"+$a.Replace('\','\\')+"'") -and
            $services.language -ceq 'WQL' -and $services.flags -eq 272 -and $set.item_calls -eq 1) 'Actual query source or native property copy changed'
        Require ($rows[0].object_path.is_class -is [bool] -and -not $rows[0].object_path.is_class -and
            @($rows[0].object_path.PSObject.Properties.Name).Count -eq 4 -and -not $rows[0].object_path.PSObject.Properties['cim_type']) 'Path scalar values were disguised as CIM declarations'
        foreach($name in @('Class','IsClass','Server','Namespace')){
            $saved=$objectPath.$name;$objectPath.$name=$null
            try{Reject {$bad=& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a;& $module {param($r,$p,$b)Assert-VisibilityReply $r $p $b} $bad $a $expected[0].bytes}}
            finally{$objectPath.$name=$saved}
        }
        foreach($badCount in @($null,'1',$true,[double]1,[long]1,@(1),0,2,-1,[int]::MaxValue)){
            $set.Count=$badCount;$before=$set.item_calls
            Reject {& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a}
            Require ($set.item_calls -eq $before) 'Invalid count was indexed'
        }
        $set.Count=[int]1;$savedItem=$set.items[0];$set.items[0]=$null
        Reject {& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a}
        $set.items[0]=$savedItem;$set.items[0].PSObject.Properties.Remove('Path_')
        Reject {& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a}
        $set.PSObject.Properties.Remove('Count')
        $set|Add-Member -MemberType ScriptProperty -Name Count -Value {throw 'Synthetic Count provider failure'}
        Reject {& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a}
        $services.result=$null
        Reject {& $module {param($s,$p)& $script:SavedVisibilityQuery $s $p} @{services=$services} $a}
    }
    foreach($mode in @('open-error','open-null','query-error','query-null','query-empty','query-multiple','query-scalar')){
        Check ('reject-'+$mode){try{Mode $mode;Reject {Observe}}finally{Mode 'normal'}}
    }
    foreach($spec in @(@('class','Win32_Directory'),@('class','cim_datafile'),@('server','REMOTE-HOST'),@('namespace','root\default'),@('namespace','ROOT\CIMV2'),@('is_class',$true),@('is_class','false'),@('is_class',0))){
        Check ('reject-wrong-provider-identity-'+$spec[0]+'-'+$checks.Count){
            $patch={param($row,$path)$row.object_path.($spec[0])=$spec[1]}.GetNewClosure()
            With-Patch $patch {Reject {Observe}}
        }
    }
    foreach($property in @('class','is_class','server','namespace')){
        Check ('reject-path-identity-array-'+$property){$patch={param($row,$path)$row.object_path.$property=@($row.object_path.$property)}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
        Check ('reject-path-identity-null-'+$property){$patch={param($row,$path)$row.object_path.$property=$null}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
        Check ('reject-path-identity-key-case-'+$property){$patch={param($row,$path)$value=$row.object_path.$property;$row.object_path.PSObject.Properties.Remove($property);$row.object_path|Add-Member -NotePropertyName $property.ToUpperInvariant() -NotePropertyValue $value}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
    }
    Check 'reject-path-identity-array-container' {With-Patch {param($row,$path)$row.object_path=@($row.object_path)} {Reject {Observe}}}
    Check 'reject-path-identity-extra-field' {With-Patch {param($row,$path)$row.object_path|Add-Member -NotePropertyName cim_type -NotePropertyValue 8} {Reject {Observe}}}
    foreach($property in @('name','file_size')){
        Check ('reject-provider-array-'+$property){$patch={param($row,$path)$row.$property.value=@($row.$property.value)}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
        Check ('reject-provider-key-case-'+$property){$patch={param($row,$path)$row.$property.name=$row.$property.name.ToLowerInvariant()+'X'}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
        Check ('reject-provider-declared-array-'+$property){$patch={param($row,$path)$row.$property.is_array=$true}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
    }
    Check 'reject-provider-property-key-only-case-change' {With-Patch {param($row,$path)$row.name.name='name'} {Reject {Observe}}}
    Check 'reject-coerced-cim-type' {With-Patch {param($row,$path)$row.file_size.cim_type='21'} {Reject {Observe}}}
    Check 'reject-coerced-array-flag' {With-Patch {param($row,$path)$row.name.is_array='false'} {Reject {Observe}}}
    Check 'reject-extra-provider-field' {With-Patch {param($row,$path)$row|Add-Member -NotePropertyName unvalidated -NotePropertyValue 'content'} {Reject {Observe}}}
    Check 'reject-extra-property-field' {With-Patch {param($row,$path)$row.name|Add-Member -NotePropertyName extra -NotePropertyValue 'content'} {Reject {Observe}}}
    foreach($bad in @($null,$true,[double]22,[int]22,[long]22,'022','22.0','2.2e1','+22','-22',' 22','18446744073709551616','wrong')){
        Check ('reject-noncanonical-provider-size-'+$checks.Count){$patch={param($row,$path)$row.file_size.value=$bad}.GetNewClosure();With-Patch $patch {Reject {Observe}}}
    }
    Check 'accept-cim-uint64-numeric-representation' {With-Patch {param($row,$path)$row.file_size.value=[uint64]$row.file_size.value} {Require ((Observe).bound_metadata) 'Native uint64 representation rejected'}}
    Check 'case-insensitive-native-file-path-is-explicit-windows-metadata' {With-Patch {param($row,$path)$row.name.value=$path.ToLowerInvariant()} {Require ((Observe).bound_metadata) 'Canonical Windows provider casing rejected'}}
    Check 'reject-wrong-system-size' {With-Patch {param($row,$path)$row.file_size.value='9999'} {Reject {Observe}}}
    Check 'reject-different-system-path' {With-Patch {param($row,$path)$row.name.value=Join-Path (Split-Path -Parent $path) 'plan.json'} {Reject {Observe}}}
    Check 'reject-system-UNC-path' {With-Patch {param($row,$path)$row.name.value='\\localhost\c$\plan.json'} {Reject {Observe}}}
    Check 'reject-system-path-traversal' {With-Patch {param($row,$path)$row.name.value=(Split-Path -Parent $path)+'\..\plan.json'} {Reject {Observe}}}
    Check 'input-expected-hash-is-verified-before-provider-use' {
        $bad=Clone $expected;$bad[0].sha256='a'*64;$before=& $module {$script:VisibilityTestQueries}
        Reject {Observe $bad};Require ((& $module {$script:VisibilityTestQueries}) -eq $before) 'Provider called before fixed hash validation'
    }
    Check 'reject-input-size-mismatch' {$bad=Clone $expected;$bad[0].bytes++;Reject {Observe $bad}}
    Check 'reject-expected-files-scalar' {Reject {Observe $expected[0]}}
    Check 'reject-empty-expected-files' {Reject {Observe @()}}
    Check 'reject-array-root' {Reject {Observe $expected @($fixture)}}
    foreach($field in @('path','bytes','sha256')){Check ('reject-input-array-'+$field){$bad=Clone $expected;$bad[0].$field=@($bad[0].$field);Reject {Observe $bad}}}
    Check 'reject-input-key-case' {$bad=@([pscustomobject]@{Path=$a;bytes=$expected[0].bytes;sha256=$expected[0].sha256});Reject {Observe $bad}}
    Check 'reject-duplicate-case-input-paths' {$bad=@($expected[0],(Clone $expected[0]));$bad[1].path=$bad[1].path.ToUpperInvariant();Reject {Observe $bad}}
    Check 'reject-input-file-outside-approved-root' {Reject {Observe $expected (Join-Path $fixture 'subdir')}}
    Check 'reject-prefix-sibling-escape' {$bad=Clone $expected;$bad[0].path=$fixture+'-sibling\package-manifest.json';Reject {Observe $bad}}
    foreach($bad in @('C:\x\..\plan.json','\\server\share\plan.json','C:\x\plan.json:hidden','C:\x\plan.json.','C:\x\CON\plan.json',"C:\x\a' OR Name='x\plan.json",'C:\x\%TEMP%\plan.json')){
        Check ('reject-ambiguous-file-path-'+$checks.Count){$rows=Clone $expected;$rows[0].path=$bad;Reject {Observe $rows}}
    }
    Check 'reject-unlisted-state-or-executable-leaf' {
        foreach($leaf in @('runtime-config.json','learning.json','user-model.json','YimeBroker.exe','PACKAGE-MANIFEST.JSON')){$rows=Clone $expected;$rows[0].path=Join-Path $fixture $leaf;Reject {Observe $rows}}
    }
    Check 'missing-file-error-does-not-produce-visible' {$rows=Clone $expected;$rows[0].path=Join-Path $fixture 'plan.json';Reject {Observe $rows}}
    Check 'open-writer-rejected' {$writer=[IO.File]::Open($a,'Open','Write','ReadWrite');try{Reject {Observe}}finally{$writer.Dispose()}}
    Check 'file-write-and-root-rename-blocked-through-provider-call' {
        With-Patch {param($row,$path)
            $blocked=$false;try{$writer=[IO.File]::Open($path,'Open','Write','ReadWrite');$writer.Dispose()}catch{$blocked=$true};if(-not $blocked){throw 'Ordinary writer not excluded'}
            $root=Split-Path -Parent $path;$moved=$root+'-renamed';$blocked=$false
            try{[IO.Directory]::Move($root,$moved)}catch{$blocked=$true};if(-not $blocked){[IO.Directory]::Move($moved,$root);throw 'Root rename not excluded'}
        } {Require ((Observe).bound_metadata) 'Read leases not held through query'}
    }
    Check 'named-file-stream-rejected' {
        Set-Content -LiteralPath $a -Stream hidden -Value 'synthetic ADS'
        try{Reject {Observe}}finally{Remove-Item -LiteralPath $a -Stream hidden}
    }
    Check 'hard-link-rejected' {
        $link=Join-Path $fixture 'alias.json';New-Item -ItemType HardLink -Path $link -Value $a|Out-Null
        try{Reject {Observe}}finally{Remove-Item -LiteralPath $link}
    }
    Check 'junction-parent-rejected-before-query' {
        $linked=Join-Path $fixture 'linked';New-Item -ItemType Junction -Path $linked -Value $fixture|Out-Null
        try{$rows=@([pscustomobject]@{path=(Join-Path $linked 'package-manifest.json');bytes=$expected[0].bytes;sha256=$expected[0].sha256});Reject {Observe $rows}}
        finally{[IO.Directory]::Delete($linked,$false)}
    }
    Check 'all-session-and-file-handles-released-after-error' {
        $before=& $module {$script:VisibilityTestClosed};try{Mode 'query-error';Reject {Observe}}finally{Mode 'normal'}
        Require ((& $module {$script:VisibilityTestClosed}) -eq $before+1) 'Provider session leaked'
        $stream=[IO.File]::Open($a,'Open','ReadWrite','None');$stream.Dispose()
    }
    Check 'same-size-system-metadata-does-not-authenticate-independent-content' {
        $same=Observe
        Require ($same.system_metadata_visible -and -not $same.independent_content_hash_verified -and -not $same.expected_manifest_origin_authenticated -and -not $same.full_acceptance) 'Size equality became content authentication'
    }
    if($RunNativeFixture){
        & $module {Set-Item function:script:Open-VisibilityProvider $script:SavedVisibilityOpen;Set-Item function:script:Invoke-VisibilityQuery $script:SavedVisibilityQuery;Set-Item function:script:Close-VisibilityProvider $script:SavedVisibilityClose}
        $native.attempted=$true
        try{$native.metadata=Observe;$native.passed=$true}catch{$native.provider_error=$_.Exception.Message}
    }
}finally{
    & $module {Set-Item function:script:Open-VisibilityProvider $script:SavedVisibilityOpen;Set-Item function:script:Invoke-VisibilityQuery $script:SavedVisibilityQuery;Set-Item function:script:Close-VisibilityProvider $script:SavedVisibilityClose;
        Remove-Variable SavedVisibilityOpen,SavedVisibilityQuery,SavedVisibilityClose,VisibilityTestMode,VisibilityTestPatch,VisibilityTestQueries,VisibilityTestClosed -Scope Script}
}
$result=[ordered]@{schema_version='yimecore-native-maintenance-visibility-tests-v1';powershell_version=$PSVersionTable.PSVersion.ToString();passed=(@($checks|Where-Object {-not $_.passed}).Count -eq 0);
    checks_passed=@($checks|Where-Object passed).Count;checks=$checks.ToArray();native_fixture=$native;fixture_root=$fixture;module_sha256=(Get-FileHash -LiteralPath $modulePath).Hash.ToLowerInvariant();test_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
    default_provider_private_fixture_only=$true;actual_candidate_or_backup_queried=$false;actual_user_state_read=$false;product_executed=$false;registry_written=$false;process_create_provider_used=$false;
    independent_content_hash_verified=$false;full_acceptance=$false;execution_authorized=$false;L6_sealed=$false}
[IO.File]::WriteAllText($out,((ConvertTo-Json -InputObject $result -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw ('Visibility fixture failed: '+(@($checks|Where-Object {-not $_.passed}|ForEach-Object {$_.name+': '+$_.error}) -join '; '))}
Write-Output ('PASS: '+$result.checks_passed+' visibility checks; native attempted='+$native.attempted+' passed='+$native.passed+'; '+$out)
