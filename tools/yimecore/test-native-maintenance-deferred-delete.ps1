[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath,[switch]$RunNativeFixture)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Fresh repository .tmp output required'}
$cursor=Split-Path -Parent $output
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect evidence output'};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null
$source=Join-Path $PSScriptRoot 'native-maintenance-deferred-delete.psm1'
$module=Import-Module $source -Force -PassThru
$checks=New-Object 'Collections.Generic.List[string]'
try {
function Check([bool]$Passed,[string]$Name){if(-not $Passed){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$rejected=$false;try{& $Body|Out-Null}catch{$rejected=$true};Check $rejected $Name}
function Assert-OwnedDeferredCleanup($Children,$Members,$Value,[bool]$Written,[string[]]$ExpectedStrings){
    # This exact pure guard is also called immediately before native DeleteKey.
    function Fields($Object,[string[]]$Names){
        if($Object -isnot [pscustomobject] -and $Object -isnot [Collections.IDictionary]){throw 'Malformed cleanup object'}
        $keys=if($Object -is [Collections.IDictionary]){@($Object.Keys)}else{@($Object.PSObject.Properties.Name)}
        if($keys.Count -ne $Names.Count){throw 'Unexpected cleanup fields'}
        foreach($name in $Names){if($keys -cnotcontains $name){throw 'Missing cleanup field'}}
    }
    function Success($Code){if(($Code -isnot [int] -and $Code -isnot [uint32]) -or $Code -ne 0){throw 'Cleanup provider failure; key retained'}}
    Fields $Children @('ReturnValue','sNames');Success $Children.ReturnValue
    if($null -ne $Children.sNames -and ($Children.sNames -isnot [array] -or $Children.sNames.Count -ne 0)){throw 'Fixture contains unexpected child keys; retained'}
    Fields $Members @('ReturnValue','sNames','Types');Success $Members.ReturnValue
    $empty=($null -eq $Members.sNames -and $null -eq $Members.Types) -or ($Members.sNames -is [array] -and $Members.Types -is [array] -and $Members.sNames.Count -eq 0 -and $Members.Types.Count -eq 0)
    if($empty -and -not $Written){if($null -ne $Value){throw 'Unexpected value in empty initial fixture'};return}
    if($Members.sNames -isnot [array] -or $Members.Types -isnot [array] -or $Members.sNames.Count -ne 1 -or $Members.Types.Count -ne 1 -or
        $Members.sNames[0] -isnot [string] -or $Members.sNames[0] -cne 'PendingFileRenameOperations' -or
        ($Members.Types[0] -isnot [int] -and $Members.Types[0] -isnot [uint32]) -or $Members.Types[0] -ne 7){throw 'Fixture contains unexpected values; retained'}
    Fields $Value @('ReturnValue','sValue');Success $Value.ReturnValue
    if($Value.sValue -isnot [array] -or $Value.sValue.Count -ne $ExpectedStrings.Count){throw 'Fixture value length differs; retained'}
    for($i=0;$i -lt $ExpectedStrings.Count;$i++){if($Value.sValue[$i] -isnot [string] -or $Value.sValue[$i] -cne $ExpectedStrings[$i]){throw 'Fixture content differs; retained'}}
}
$protected=@('C:\Product\old','C:\Product\target','C:\SyntheticState')
# Production adapters never run in default CI. Replace only private definitions
# inside this freshly imported module; no public registry root/provider override.
& $module {
    $script:FakeValues=@{};$script:FakeMode='';$script:FakeCalls=0;$script:FakeClosed=0
    $script:OriginalDeferredInvoke=${function:Invoke-DeferredRegistryMethod}
    function script:New-DeferredRegistrySession {$script:FakeCalls++;@{fixture=$true}}
    function script:Close-DeferredRegistrySession($Session){$script:FakeClosed++}
    function script:Invoke-DeferredRegistryMethod($Session,$View,$Method,$Name=''){
        $script:FakeCalls++
        if($script:FakeMode -ceq 'throw'){throw 'private provider failure'}
        if($Method -ceq 'EnumValues'){
            $names=@('UnrelatedPrivateValue');$types=@(1)
            foreach($fixed in $script:DeferredNames){if($script:FakeValues.ContainsKey("$View/$fixed")){$names+=,$fixed;$types+=,7}}
            $reply=[pscustomobject]@{ReturnValue=0;sNames=$names;Types=$types}
            switch -CaseSensitive ($script:FakeMode){
                'enum-access' {$reply.ReturnValue=5}
                'enum-absent-key' {$reply.ReturnValue=2}
                'enum-string-return' {$reply.ReturnValue='0'}
                'enum-array-return' {$reply.ReturnValue=@(0)}
                'enum-bool-return' {$reply.ReturnValue=$false}
                'enum-long-return' {$reply.ReturnValue=[long]0}
                'enum-null-return' {$reply.ReturnValue=$null}
                'enum-missing-return' {$reply.PSObject.Properties.Remove('ReturnValue')}
                'enum-extra' {$reply|Add-Member extra 'never return this'}
                'enum-scalar-names' {$reply.sNames='UnrelatedPrivateValue'}
                'enum-scalar-types' {$reply.Types=1}
                'enum-mismatch' {$reply.Types=@()}
                'enum-string-kind' {$reply.Types=@('1')+@($types|Select-Object -Skip 1)}
                'enum-array-kind' {$reply.Types[0]=@(1)}
                'enum-negative-kind' {$reply.Types=@(-1)+@($types|Select-Object -Skip 1)}
                'enum-high-kind' {$reply.Types=@(12)+@($types|Select-Object -Skip 1)}
                'enum-duplicate' {$reply.sNames+=,'unrelatedprivatevalue';$reply.Types+=,1}
                'enum-null-name' {$reply.sNames[0]=$null}
                'enum-bad-unicode' {$reply.sNames[0]=[string][char]0xd800}
                'wrong-kind' {if($names.Count -gt 1){$reply.Types[1]=1}}
                'wrong-case' {if($names.Count -gt 1){$reply.sNames[1]=$reply.sNames[1].ToLowerInvariant()}}
                'view64-access' {if($View -eq 64){$reply.ReturnValue=5}}
                'membership-change' {if($script:FakeCalls -gt 3){$reply.sNames=@('UnrelatedPrivateValue');$reply.Types=@(1)}}
            }
            return $reply
        }
        $values=$script:FakeValues["$View/$Name"]
        $reply=[pscustomobject]@{ReturnValue=0;sValue=$values}
        switch -CaseSensitive ($script:FakeMode){
            'getter-access' {$reply.ReturnValue=5}
            'getter-disappeared' {$reply.ReturnValue=2}
            'getter-string-return' {$reply.ReturnValue='0'}
            'getter-array-return' {$reply.ReturnValue=@(0)}
            'getter-null' {$reply.sValue=$null}
            'getter-scalar' {$reply.sValue='C:\Unrelated'}
            'getter-missing' {$reply.PSObject.Properties.Remove('sValue')}
            'getter-extra' {$reply|Add-Member arbitrary 'never return this'}
            'two-pass-change' {if($script:FakeCalls -gt 7){$reply.sValue=@('C:\Changed','')}}
        }
        return $reply
    }
}
function Snapshot($Values=@{},[string]$Mode=''){
    & $module {param($v,$m)$script:FakeValues=$v;$script:FakeMode=$m;$script:FakeCalls=0;$script:FakeClosed=0} $Values $Mode
    Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot -ProtectedRoots $protected
}
function Queue($Strings,[int]$View=32,[string]$Name='PendingFileRenameOperations'){$values=@{};$values["$View/$Name"]=$Strings;return $values}
$empty=Snapshot
Check ($empty.point_in_time_clear -and $empty.all_queue_values_absent -and $empty.records.Count -eq 4 -and $empty.reported_pair_count -eq 0) 'all four absent values admit only the point absence gate'
Check (($empty.records|ForEach-Object {[string]$_.view+'/'+$_.name}) -join '|' -ceq '32/PendingFileRenameOperations|32/PendingFileRenameOperations2|64/PendingFileRenameOperations|64/PendingFileRenameOperations2') 'complete fixed coordinate order retained'
Check ($empty.two_pass_equal -and (& $module {$script:FakeClosed}) -eq 1) 'complete observations repeat and session closes'
foreach($flag in @('provider_raw_multisz_completeness_verified','registry_link_identity_verified','continuous_monitoring','atomic','execution_authorized','rollback_acceptance','L6_sealed','local_product_ready','public_release_ready')){Check ($empty.$flag -is [bool] -and -not $empty.$flag) ('honest false '+$flag)}
Check (@($module.ExportedFunctions.Keys).Count -eq 1) 'only explicit read API exported'
foreach($bad in @('C:\Product\old',@(),@('c:\Product\old'),@('C:\Product\old\'),@('C:\Product\old','c:\Product\old'),@('\??\C:\Product\old'),@('C:\Product\..\old'),@('C:\Product\old:ads'),@([string][char]0xd800),@($null))){
    Reject {Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot -ProtectedRoots $bad} ('invalid protected roots '+$checks.Count)
}
Reject {Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot -ProtectedRoots (,@('C:\Product\old'))} 'nested protected-root array rejected'
foreach($view in @(32,64)){foreach($name in @('PendingFileRenameOperations','PendingFileRenameOperations2')){
    $risk=Snapshot (Queue @('\??\C:\Product\old\locked.dll','') $view $name)
    Check (-not $risk.point_in_time_clear -and $risk.related_operation_count -eq 1 -and $risk.risks[0].operation -ceq 'delete' -and $risk.risks[0].relation -ceq 'descendant') ('empty deletion target and correct queue coordinate '+$view+'/'+$name)
}}
foreach($spec in @(
    @{path='C:\Product\old';side='source';relation='equal'},
    @{path='C:\Product';side='source';relation='ancestor'},
    @{path='C:\';side='source';relation='ancestor'},
    @{path='c:\pRoDuCt\OlD\part';side='source';relation='descendant'},
    @{path='\\?\C:\Product\target';side='source';relation='equal'},
    @{path='\DosDevices\C:\Product\old';side='source';relation='equal'},
    @{path='!\??\C:\Product\target\new';side='target';relation='descendant'},
    @{path='C:\Product';side='target';relation='ancestor'})){
    $strings=if($spec.side -ceq 'source'){@($spec.path,'C:\PrivateSystem\elsewhere')}else{@('C:\PrivateSystem\elsewhere',$spec.path)}
    $risk=Snapshot (Queue $strings)
    Check (@($risk.risks|Where-Object {$_.side -ceq $spec.side -and $_.relation -ceq $spec.relation}).Count -gt 0) ('protected intersection '+$spec.side+' '+$spec.relation+' '+$checks.Count)
    Check (($risk|ConvertTo-Json -Depth 20) -notmatch 'PrivateSystem|elsewhere|locked.dll') 'unrelated endpoint bodies are not returned'
}
$replace=Snapshot (Queue @('C:\Elsewhere\from','!\??\C:\Product\old'))
Check ($replace.risks[0].replace_existing -is [bool] -and $replace.risks[0].replace_existing) 'destination replace prefix preserved as typed metadata'
$outbound=Snapshot (Queue @('C:\Product\old','C:\PrivateSystem\out'))
Check ($outbound.related_operation_count -eq 1 -and $outbound.risks[0].side -ceq 'source') 'outbound rename protects source side'
$unrelated=Snapshot (Queue @('C:\Product\older','C:\Productivity\target'))
Check ($unrelated.risks.Count -eq 0 -and $unrelated.unknown_count -eq 0 -and -not $unrelated.point_in_time_clear) 'component boundaries avoid prefix false positives while present incomplete provider stays closed'
$presentEmpty=Snapshot (Queue @())
Check (-not $presentEmpty.point_in_time_clear -and -not $presentEmpty.all_queue_values_absent -and $presentEmpty.reported_pair_count -eq 0) 'present empty array cannot masquerade as absent raw queue'
$a=Snapshot (Queue @('C:\Unrelated\one','','C:\Unrelated\two','C:\Unrelated\three'))
$b=Snapshot (Queue @('C:\Unrelated\two','C:\Unrelated\three','C:\Unrelated\one',''))
Check ($a.ordered_queue_sha256 -cne $b.ordered_queue_sha256 -and $a.reported_pair_count -eq 2) 'full reported order including empty target affects queue digest'
$c=Snapshot (Queue @('c:\Unrelated\one','','C:\Unrelated\two','C:\Unrelated\three'))
Check ($a.ordered_queue_sha256 -cne $c.ordered_queue_sha256) 'raw spelling retained in digest even when matching ignores case'
foreach($path in @('\Device\HarddiskVolume3\Product\old','\??\Volume{00000000-0000-0000-0000-000000000000}\file','\\server\share\file','\??\UNC\server\share\file','C:relative','relative','\Windows\file','%TEMP%\file','C:\folder\..\Product\old','C:\folder\.\file','C:\folder\\file','C:\PROGRA~1\file','C:\file.','C:\file ','C:\file:stream','C:\NUL.txt','*1\??\C:\file','!\??\C:\file','\??\!C:\file')){
    $unknown=Snapshot (Queue @($path,''))
    Check ($unknown.unknown_count -eq 1 -and -not $unknown.point_in_time_clear -and $unknown.related_operation_count -eq 0) ('unknown namespace or syntax closes gate '+$checks.Count)
    Check (($unknown|ConvertTo-Json -Depth 24) -notmatch [regex]::Escape($path)) 'unknown endpoint text remains private'
}
foreach($strings in @(@(''),@('',''),@('C:\one','', 'C:\odd'),@('C:\one',$null),@('C:\one',1),@('C:\one',@('C:\two')),@('C:\one',[string][char]0xd800),@('C:\one',("C:\two"+[char]0+'tail')))){
    Reject {Snapshot (Queue $strings)} ('malformed typed queue '+$checks.Count)
}
foreach($mode in @('throw','enum-access','enum-absent-key','enum-string-return','enum-array-return','enum-bool-return','enum-long-return','enum-null-return','enum-missing-return','enum-extra','enum-scalar-names','enum-scalar-types','enum-mismatch','enum-string-kind','enum-array-kind','enum-negative-kind','enum-high-kind','enum-duplicate','enum-null-name','enum-bad-unicode','wrong-kind','wrong-case','view64-access','membership-change','getter-access','getter-disappeared','getter-string-return','getter-array-return','getter-null','getter-scalar','getter-missing','getter-extra','two-pass-change')){
    Reject {Snapshot (Queue @('C:\Unrelated','')) $mode} ('provider refuses fallback '+$mode)
    Check ((& $module {$script:FakeClosed}) -eq 1) ('provider failure releases session '+$mode)
}
foreach($spec in @(
    @{Name='ReturnValue';CIMType=19;IsArray=$false;Value=[int]0},
    @{Name='sValue';CIMType=8;IsArray=$true;Value=[string[]]@('one','','two')},
    @{Name='Types';CIMType=3;IsArray=$true;Value=[int[]]@(7)})){
    $result=& $module {param($p)ConvertFrom-DeferredNativeProperty ([pscustomobject]$p) $p.Name} $spec
    Check ($null -ne $result) ('native CIM declaration accepted '+$spec.Name)
    foreach($field in @('Name','CIMType','IsArray')){
        $bad=$spec.Clone();$bad[$field]=@($bad[$field]);Reject {& $module {param($p,$n)ConvertFrom-DeferredNativeProperty ([pscustomobject]$p) $n} $bad $spec.Name} ('native metadata array rejected '+$spec.Name+'/'+$field)
    }
}
$adapter=& $module {
    function PropertyCollection($Rows){
        $value=[pscustomobject]@{rows=$Rows}
        $value|Add-Member ScriptMethod Item {param($name) if(-not $this.rows.ContainsKey($name)){throw 'Unknown fake native property'};return $this.rows[$name]}
        return $value
    }
    $inputRows=@{};foreach($name in @('hDefKey','sSubKeyName','sValueName')){$inputRows[$name]=[pscustomobject]@{Value=$null}}
    $inputObject=[pscustomobject]@{Properties_=(PropertyCollection $inputRows)}
    $parameters=[pscustomobject]@{input=$inputObject};$parameters|Add-Member ScriptMethod SpawnInstance_ {return $this.input}
    $metadata=[pscustomobject]@{InParameters=$parameters}
    $methods=[pscustomobject]@{metadata=$metadata};$methods|Add-Member ScriptMethod Item {param($name) if($name -cne 'GetMultiStringValue'){throw 'Wrong fake method'};return $this.metadata}
    $outputRows=@{
        ReturnValue=[pscustomobject]@{Name='ReturnValue';CIMType=19;IsArray=$false;Value=[int]0}
        sValue=[pscustomobject]@{Name='sValue';CIMType=8;IsArray=$true;Value=[string[]]@('C:\PrivateFake\source','','C:\PrivateFake\rename','C:\PrivateFake\target')}
    }
    $provider=[pscustomobject]@{Methods_=$methods;reply=[pscustomobject]@{Properties_=(PropertyCollection $outputRows)};seen=''}
    $provider|Add-Member ScriptMethod ExecMethod_ {param($method,$arguments,$flags,$context) $this.seen=$method;return $this.reply}
    $session=@{32=@{provider=$provider;context=[pscustomobject]@{fixture=$true}}}
    $reply=& $script:OriginalDeferredInvoke $session 32 'GetMultiStringValue' 'PendingFileRenameOperations'
    [pscustomobject]@{reply=$reply;method=$provider.seen;hive=$inputRows.hDefKey.Value;key=$inputRows.sSubKeyName.Value;name=$inputRows.sValueName.Value}
}
Check ($adapter.method -ceq 'GetMultiStringValue' -and $adapter.hive -is [uint32] -and $adapter.hive -eq [uint32]2147483650 -and $adapter.key -is [string] -and $adapter.key -ceq 'SYSTEM\CurrentControlSet\Control\Session Manager' -and $adapter.name -is [string] -and $adapter.name -ceq 'PendingFileRenameOperations') 'actual COM invocation source supplies exact Automation input types and fixed coordinates'
Check ($adapter.reply.ReturnValue -is [int] -and $adapter.reply.ReturnValue -eq 0 -and $adapter.reply.sValue -is [array] -and $adapter.reply.sValue.Count -eq 4 -and $adapter.reply.sValue[1] -ceq '') 'actual native property adapter retains ordered empty target and suffix from private COM fixture'
$cleanupExpected=[string[]]@('C:\Owned\source','','C:\Owned\from','C:\Owned\to')
function Cleanup-Fixture {
    @{children=[pscustomobject]@{ReturnValue=0;sNames=$null};members=[pscustomobject]@{ReturnValue=0;sNames=@('PendingFileRenameOperations');Types=@(7)};
      value=[pscustomobject]@{ReturnValue=0;sValue=@($cleanupExpected)};written=$true}
}
$clean=Cleanup-Fixture
Assert-OwnedDeferredCleanup $clean.children $clean.members $clean.value $true $cleanupExpected
Check $true 'native cleanup guard accepts only exact expected sole value and no children'
foreach($nullArrays in @($true,$false)){
    $clean=Cleanup-Fixture;$clean.members.sNames=if($nullArrays){$null}else{@()};$clean.members.Types=if($nullArrays){$null}else{@()}
    Assert-OwnedDeferredCleanup $clean.children $clean.members $null $false $cleanupExpected
    Check $true 'native cleanup permits verified empty initial fixture before any write'
    Reject {Assert-OwnedDeferredCleanup $clean.children $clean.members $null $true $cleanupExpected} 'missing value after write is not empty initial ownership'
}
foreach($mode in @('child-present','children-scalar','children-return2','children-string-return','extra-value','wrong-value-name','wrong-value-case','wrong-value-kind','string-value-kind',
    'member-scalar','members-return5','members-extra-field','value-return5','value-string-return','value-null','value-scalar','value-missing','value-added','value-changed','value-array-element')){
    $clean=Cleanup-Fixture
    switch($mode){
        'child-present' {$clean.children.sNames=@('unexpected')}
        'children-scalar' {$clean.children.sNames=''}
        'children-return2' {$clean.children.ReturnValue=2}
        'children-string-return' {$clean.children.ReturnValue='0'}
        'extra-value' {$clean.members.sNames+=,'unexpected';$clean.members.Types+=,1}
        'wrong-value-name' {$clean.members.sNames=@('Other')}
        'wrong-value-case' {$clean.members.sNames=@('pendingfilerenameoperations')}
        'wrong-value-kind' {$clean.members.Types=@(1)}
        'string-value-kind' {$clean.members.Types=@('7')}
        'member-scalar' {$clean.members.sNames='PendingFileRenameOperations'}
        'members-return5' {$clean.members.ReturnValue=5}
        'members-extra-field' {$clean.members|Add-Member extra 'unowned'}
        'value-return5' {$clean.value.ReturnValue=5}
        'value-string-return' {$clean.value.ReturnValue='0'}
        'value-null' {$clean.value.sValue=$null}
        'value-scalar' {$clean.value.sValue='C:\Owned\source'}
        'value-missing' {$clean.value.sValue=@($cleanupExpected|Select-Object -Skip 1)}
        'value-added' {$clean.value.sValue+=,'unowned'}
        'value-changed' {$clean.value.sValue[2]='changed'}
        'value-array-element' {$clean.value.sValue[2]=@('C:\Owned\from')}
    }
    Reject {Assert-OwnedDeferredCleanup $clean.children $clean.members $clean.value $clean.written $cleanupExpected} ('exact native cleanup guard retains on '+$mode)
}
$native=[ordered]@{requested=[bool]$RunNativeFixture;production_queue_accessed=$false;fixture_registry_path='';fixture_raw_sha256='';fixture_created=$false;fixture_removed=$false;native_fixture_completed=$false;raw_multisz_lossless_observed=$false;views=@();provider_diagnostics=@();error='';error_stage='';error_script_stack='';cleanup_error=''}
$providerNative=[ordered]@{requested=[bool]$RunNativeFixture;fixture_registry_path='';created_views=@();removed_views=@();already_absent_views=@();initial_absence_clear=$false;present_gate_rejected=$false;
    native_fixture_completed=$false;provider_roundtrip_exact=$false;raw_multisz_completeness_verified=$false;creation_ownership_authenticated=$false;production_queue_accessed=$false;
    views=@();error='';cleanup_error='';cleanup_retained=$false}
if($RunNativeFixture){
    # This option writes only a newly created random HKCU fixture. Never call
    # MoveFileEx, production queues, product keys or ambient user state.
    $fixtureKey='Software\YimeMaintenanceFixtures\'+[guid]::NewGuid().ToString('N')
    if($fixtureKey -cnotmatch '^Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$'){throw 'Unsafe native fixture key'}
    $native.fixture_registry_path='HKEY_CURRENT_USER\'+$fixtureKey
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $namespace='Yime.DeferredFixture.N'+[guid]::NewGuid().ToString('N')
    $nativeSource=@'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Yime.DeferredFixture {
 public static class Registry {
  static readonly IntPtr HKCU=new IntPtr(unchecked((int)0x80000001));
  static string owned;
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegCreateKeyEx(IntPtr key,string sub,int reserved,string cls,int options,int access,IntPtr security,out IntPtr opened,out int disposition);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegOpenKeyEx(IntPtr key,string sub,int options,int access,out IntPtr opened);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegSetValueEx(IntPtr key,string name,int reserved,int kind,byte[] data,int bytes);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegDeleteKeyEx(IntPtr key,string sub,int access,int reserved);
  [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr key);
  static void Validate(string path){if(path==null||!System.Text.RegularExpressions.Regex.IsMatch(path,@"\ASoftware\\YimeMaintenanceFixtures\\[a-f0-9]{32}\z"))throw new InvalidOperationException("Unsafe fixture key");}
  public static void Create(string path){Validate(path);if(owned!=null)throw new InvalidOperationException("Fixture already owns a key");IntPtr key;int disposition;
   int rc=RegCreateKeyEx(HKCU,path,0,null,0,0x20106,IntPtr.Zero,out key,out disposition);if(rc!=0)throw new Win32Exception(rc);
   try{if(disposition!=1)throw new InvalidOperationException("Fixture key already existed");owned=path;}finally{RegCloseKey(key);}
  }
  public static void Write(string path,byte[] bytes){Validate(path);if(path!=owned)throw new InvalidOperationException("Fixture does not own key");IntPtr key;
   int rc=RegOpenKeyEx(HKCU,path,0,0x20106,out key);if(rc!=0)throw new Win32Exception(rc);
   try{rc=RegSetValueEx(key,"PendingFileRenameOperations",0,7,bytes,bytes.Length);if(rc!=0)throw new Win32Exception(rc);}finally{RegCloseKey(key);}
  }
  public static void Remove(string path){Validate(path);if(path!=owned)throw new InvalidOperationException("Fixture does not own key");int rc=RegDeleteKeyEx(HKCU,path,0x100,0);if(rc!=0)throw new Win32Exception(rc);owned=null;}
 }
}
'@
    $types=@(Add-Type -TypeDefinition ($nativeSource.Replace('namespace Yime.DeferredFixture {',('namespace '+$namespace+' {'))) -PassThru)
    $nativeType=@($types|Where-Object {$_.FullName -ceq ($namespace+'.Registry')})[0]
    $expected=[string[]]@('\??\C:\SyntheticQueueFixture\delete','','\??\C:\SyntheticQueueFixture\from','!\??\C:\SyntheticQueueFixture\to')
    $raw=([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes(($expected -join [char]0)+[char]0+[char]0)
    $digest=[Security.Cryptography.SHA256]::Create()
    try{$native.fixture_raw_sha256=([BitConverter]::ToString($digest.ComputeHash($raw))).Replace('-','').ToLowerInvariant()}finally{$digest.Dispose()}
    $diagnostics=New-Object 'Collections.Generic.List[object]'
    try{
        $nativeType::Create($fixtureKey);$native.fixture_created=$true
        $nativeType::Write($fixtureKey,$raw)
        Remove-Module $module;$module=$null;$module=Import-Module $source -Force -PassThru
        # Use the original adapter, fixed to this exact newly created HKCU key
        # through its equivalent HKEY_USERS SID coordinate. No GetSnapshot call.
        $native.views=@(& $module {param($key,$targetSid,$expectedStrings,$diagnostics)
            if($key -cnotmatch '^Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$' -or $targetSid -cnotmatch '^S-1-5-21-[0-9-]+$'){throw 'Invalid private native fixture binding'}
            $script:DeferredHive=[uint32]2147483651;$script:DeferredKey=$targetSid+'\'+$key
            $session=New-DeferredRegistrySession
            try{foreach($view in @(32,64)){
                $enumReply=Invoke-DeferredRegistryMethod $session $view 'EnumValues'
                $enumCode=$enumReply.ReturnValue
                $diagnostics.Add([pscustomobject]@{stage='EnumValues';view=$view;hive=$script:DeferredHive;key=$script:DeferredKey;
                    return_type=$(if($null -eq $enumCode){'null'}else{$enumCode.GetType().FullName});
                    return_code=$(if($enumCode -is [int] -or $enumCode -is [uint32]){$enumCode}else{$null});
                    names_type=$(if($null -eq $enumReply.sNames){'null'}else{$enumReply.sNames.GetType().FullName});
                    names_count=$(if($enumReply.sNames -is [array]){$enumReply.sNames.Count}else{0});
                    types_type=$(if($null -eq $enumReply.Types){'null'}else{$enumReply.Types.GetType().FullName})})
                Assert-DeferredReturn $enumCode
                $enumeration=Read-DeferredEnumeration $session $view
                if(-not $enumeration.ContainsKey('PendingFileRenameOperations')){throw 'Native fixture value missing'}
                $reply=Invoke-DeferredRegistryMethod $session $view 'GetMultiStringValue' 'PendingFileRenameOperations'
                Assert-DeferredFields $reply @('ReturnValue','sValue');Assert-DeferredReturn $reply.ReturnValue
                $valid=$reply.sValue -is [array];$count=if($valid){$reply.sValue.Count}else{0}
                $equal=$valid -and $count -eq $expectedStrings.Count
                if($equal){for($i=0;$i -lt $count;$i++){if($reply.sValue[$i] -isnot [string] -or $reply.sValue[$i] -cne $expectedStrings[$i]){$equal=$false}}}
                [pscustomobject]@{view=$view;expected_string_count=$expectedStrings.Count;captured_string_count=$count;exact_empty_target_and_suffix_preserved=[bool]$equal}
            }}finally{Close-DeferredRegistrySession $session}
        } $fixtureKey $sid $expected $diagnostics)
        $native.native_fixture_completed=$true
        $native.raw_multisz_lossless_observed=($native.views.Count -eq 2 -and @($native.views|Where-Object {-not $_.exact_empty_target_and_suffix_preserved}).Count -eq 0)
    }catch{$native.error=$_.Exception.GetType().FullName+': '+$_.Exception.Message;$native.error_stage='owned-registry-fixture';$native.error_script_stack=$_.ScriptStackTrace}
    finally{
        $native.provider_diagnostics=@($diagnostics.ToArray())
        if($native.fixture_created){try{
            if($fixtureKey -cnotmatch '^Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup'}
            $nativeType::Remove($fixtureKey);$native.fixture_removed=$true
        }catch{$native.cleanup_error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}}
    }
}
if($RunNativeFixture){
    # Separate from the native raw-byte fixture. WMI owns this random HKU key,
    # so its successful round trip proves the COM adapter only, not raw MULTI_SZ
    # byte preservation or identity across inherited application registry views.
    if($null -ne $module){Remove-Module $module;$module=$null}
    $module=Import-Module $source -Force -PassThru
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $providerKey=$sid+'\Software\YimeMaintenanceFixtures\'+[guid]::NewGuid().ToString('N')
    if($providerKey -cnotmatch ('^'+[regex]::Escape($sid)+'\\Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$')){throw 'Unsafe provider-owned fixture key'}
    $providerNative.fixture_registry_path='HKEY_USERS\'+$providerKey
    & $module {param($key,$targetSid,$evidence,$roots,$cleanupGuard)
        if($key -cnotmatch ('^'+[regex]::Escape($targetSid)+'\\Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$')){throw 'Unsafe provider-owned fixture coordinate'}
        $script:DeferredHive=[uint32]2147483651;$script:DeferredKey=$key
        function Invoke-OwnedDeferredFixture($Session,[int]$View,[string]$Method,$Strings=$null){
            if($View -notin @(32,64) -or $Method -cnotin @('CreateKey','SetMultiStringValue','DeleteKey','EnumKey')){throw 'Unsupported owned fixture mutation'}
            if($script:DeferredKey -cnotmatch ('^'+[regex]::Escape($targetSid)+'\\Software\\YimeMaintenanceFixtures\\[a-f0-9]{32}$')){throw 'Fixture mutation left GUID boundary'}
            $entry=$Session[$View];$metadata=$null;$arguments=$null;$output=$null
            try{
                $metadata=$entry.provider.Methods_.Item($Method);$arguments=$metadata.InParameters.SpawnInstance_()
                $arguments.Properties_.Item('hDefKey').Value=[uint32]2147483651
                $arguments.Properties_.Item('sSubKeyName').Value=[string]$script:DeferredKey
                if($Method -ceq 'SetMultiStringValue'){
                    $arguments.Properties_.Item('sValueName').Value=[string]'PendingFileRenameOperations'
                    $arguments.Properties_.Item('sValue').Value=[string[]]$Strings
                }
                $output=$entry.provider.ExecMethod_($Method,$arguments,0,$entry.context)
                $reply=[ordered]@{ReturnValue=(ConvertFrom-DeferredNativeProperty ($output.Properties_.Item('ReturnValue')) 'ReturnValue')}
                if($Method -ceq 'EnumKey'){$reply.sNames=ConvertFrom-DeferredNativeProperty ($output.Properties_.Item('sNames')) 'sNames'}
                [pscustomobject]$reply
            }finally{foreach($item in @($output,$arguments,$metadata)){if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)}}}
        }
        function Assert-OwnedAbsent($Reply){
            Assert-DeferredFields $Reply @('ReturnValue','sNames','Types')
            if(($Reply.ReturnValue -isnot [int] -and $Reply.ReturnValue -isnot [uint32]) -or $Reply.ReturnValue -ne 2 -or
                $null -ne $Reply.sNames -or $null -ne $Reply.Types){throw 'Random provider-owned fixture already exists or absence is unproved'}
        }
        function Test-OwnedExact($Actual,[string[]]$Expected){
            if($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count){return $false}
            for($i=0;$i -lt $Expected.Count;$i++){if($Actual[$i] -isnot [string] -or $Actual[$i] -cne $Expected[$i]){return $false}}
            return $true
        }
        $session=$null;$created=New-Object 'Collections.Generic.List[int]';$removed=New-Object 'Collections.Generic.List[int]';$absent=New-Object 'Collections.Generic.List[int]'
        $views=New-Object 'Collections.Generic.List[object]';$written=$false;$cleanupErrors=New-Object 'Collections.Generic.List[string]'
        $strings=[string[]]@('\??\C:\SyntheticQueueFixture\delete','','\??\C:\SyntheticQueueFixture\from','!\??\C:\SyntheticQueueFixture\to')
        try{
            $session=New-DeferredRegistrySession
            # Both views must be absent before either CreateKey. StdRegProv has
            # no atomic creation disposition; ownership remains explicitly false.
            foreach($view in @(32,64)){Assert-OwnedAbsent (Invoke-DeferredRegistryMethod $session $view 'EnumValues')}
            foreach($view in @(32,64)){
                $reply=Invoke-OwnedDeferredFixture $session $view 'CreateKey';Assert-DeferredReturn $reply.ReturnValue;$created.Add($view)
            }
            $before=Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot -ProtectedRoots $roots
            if($before.point_in_time_clear -isnot [bool] -or -not $before.point_in_time_clear -or -not $before.all_queue_values_absent){throw 'Owned empty fixture failed real absence capture'}
            $evidence.initial_absence_clear=$true
            foreach($view in @(32,64)){
                $reply=Invoke-OwnedDeferredFixture $session $view 'SetMultiStringValue' $strings;Assert-DeferredReturn $reply.ReturnValue;$written=$true
                $enumeration=Read-DeferredEnumeration $session $view
                if(-not $enumeration.ContainsKey('PendingFileRenameOperations')){throw 'Owned provider fixture write was not observed'}
                $reply=Invoke-DeferredRegistryMethod $session $view 'GetMultiStringValue' 'PendingFileRenameOperations'
                Assert-DeferredFields $reply @('ReturnValue','sValue');Assert-DeferredReturn $reply.ReturnValue
                if($reply.sValue -isnot [array]){throw 'Owned provider getter did not return a string array'}
                foreach($text in $reply.sValue){Assert-DeferredText $text}
                $views.Add([pscustomobject]@{view=$view;return_type=$reply.ReturnValue.GetType().FullName;return_code=$reply.ReturnValue;
                    expected_string_count=$strings.Count;captured_string_count=$reply.sValue.Count;exact_roundtrip=(Test-OwnedExact $reply.sValue $strings)})
            }
            try{$after=Get-YimeCoreNativeMaintenanceDeferredDeleteSnapshot -ProtectedRoots $roots
                if($after.point_in_time_clear -isnot [bool] -or $after.point_in_time_clear){throw 'Present fixture incorrectly admitted'}
                $evidence.present_gate_rejected=$true
            }catch{
                if($_.Exception.Message -ceq 'Present fixture incorrectly admitted'){throw}
                # A malformed/lossy provider reply must fail closed as well.
                $evidence.present_gate_rejected=$true
            }
            $evidence.provider_roundtrip_exact=($views.Count -eq 2 -and @($views|Where-Object {-not $_.exact_roundtrip}).Count -eq 0)
            $evidence.native_fixture_completed=($evidence.initial_absence_clear -and $evidence.present_gate_rejected -and $views.Count -eq 2)
        }catch{$evidence.error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+'; '+$_.ScriptStackTrace}
        finally{
            if($null -ne $session){
                foreach($view in $created){try{
                    if($script:DeferredKey -cne $key){throw 'Owned cleanup coordinate changed'}
                    $children=Invoke-OwnedDeferredFixture $session $view 'EnumKey'
                    Assert-DeferredFields $children @('ReturnValue','sNames')
                    if(($children.ReturnValue -is [int] -or $children.ReturnValue -is [uint32]) -and $children.ReturnValue -eq 2 -and $null -eq $children.sNames -and $removed.Count -gt 0){$absent.Add($view);continue}
                    $members=Invoke-DeferredRegistryMethod $session $view 'EnumValues';Assert-DeferredFields $members @('ReturnValue','sNames','Types');Assert-DeferredReturn $members.ReturnValue
                    $empty=($null -eq $members.sNames -and $null -eq $members.Types) -or ($members.sNames -is [array] -and $members.Types -is [array] -and $members.sNames.Count -eq 0 -and $members.Types.Count -eq 0)
                    $value=$null;if(-not $empty){$value=Invoke-DeferredRegistryMethod $session $view 'GetMultiStringValue' 'PendingFileRenameOperations'}
                    & $cleanupGuard $children $members $value $written $strings
                    $reply=Invoke-OwnedDeferredFixture $session $view 'DeleteKey';Assert-DeferredReturn $reply.ReturnValue;$removed.Add($view)
                }catch{$cleanupErrors.Add('view '+$view+': '+$_.Exception.Message)}}
                Close-DeferredRegistrySession $session
            }
            $evidence.created_views=@($created.ToArray());$evidence.removed_views=@($removed.ToArray());$evidence.already_absent_views=@($absent.ToArray());$evidence.views=@($views.ToArray())
            $evidence.cleanup_error=$cleanupErrors -join '; ';$evidence.cleanup_retained=($cleanupErrors.Count -gt 0)
        }
    } $providerKey $sid $providerNative $protected ${function:Assert-OwnedDeferredCleanup}
}
$report=[ordered]@{schema_version='yimecore-native-maintenance-deferred-delete-tests-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();powershell_version=$PSVersionTable.PSVersion.ToString();
    module_sha256=(Get-FileHash $source).Hash.ToLowerInvariant();test_sha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant();private_fake_provider_only=(-not $RunNativeFixture);native_fixture=$native;provider_owned_fixture=$providerNative;
    production_queue_read=$false;product_registry_read=$false;product_executed=$false;user_state_read=$false;rollback_acceptance=$false;L6_sealed=$false}
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $output -Encoding UTF8
Write-Output ('PASS: deferred delete observer '+$checks.Count+' synthetic checks; native fixture completed='+$native.native_fixture_completed+'; '+$output)
} finally {
    # This test owns its fresh module instance. Do not leave private fake
    # providers or the temporary HKU coordinate for a later same-session test.
    if($null -ne $module){Remove-Module $module}
}
