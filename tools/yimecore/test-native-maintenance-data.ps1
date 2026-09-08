[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Use new repository .tmp evidence output'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-data.psm1'
$module=Import-Module $modulePath -Force -PassThru
$schema='yimecore-native-maintenance-data-v1'
$fixture=Join-Path $repo ('.tmp\native-maintenance-data-'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body | Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body | Out-Null}catch{$failed=$true};Require $failed 'Expected rejection'}
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
if(-not ('Yime.NativeDataTestStreams' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Yime {
    public static class NativeDataTestStreams {
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool DeleteFile(string path);
        public static void Create(string path) {
            using(var handle=CreateFile(path,0x40000000,7,IntPtr.Zero,2,0,IntPtr.Zero)) {
                if(handle.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
                using(var stream=new System.IO.FileStream(handle,System.IO.FileAccess.Write)){stream.WriteByte(86);stream.Flush(true);}
            }
        }
        public static void Remove(string path){if(!DeleteFile(path))throw new Win32Exception(Marshal.GetLastWin32Error());}
    }
}
'@}
function Set-FixtureStream([string]$Path,[switch]$Remove){
    if(-not $Path.StartsWith($fixture+'\',[StringComparison]::Ordinal) -or -not $Path.EndsWith(':hidden',[StringComparison]::Ordinal)){throw 'Unsafe fixture stream path'}
    if($Remove){[Yime.NativeDataTestStreams]::Remove($Path)}else{[Yime.NativeDataTestStreams]::Create($Path)}
}
function Snapshot([string]$Root,[switch]$Shared){Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $Root -BaselineSchemaVersion $schema -SharedObservation:$Shared}
function Clone-Snapshot($Value){ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 30)}
function Reseal($Value){$Value.snapshot_sha256=& $module {param($v)Get-YcDataDigest (Get-YcDataSnapshotBody $v)} $Value;return $Value}
function Invoke-InventoryMutation([scriptblock]$Mutation,[scriptblock]$Body){
    & $module {param($action)
        $script:SavedDataInventory=${function:Get-YcDataInventory};$script:DataInventoryCount=0;$script:DataMutation=$action
        function script:Get-YcDataInventory([string]$Root,$Directories){
            $script:DataInventoryCount++
            if($script:DataInventoryCount -eq 2){& $script:DataMutation $Root}
            & $script:SavedDataInventory $Root $Directories
        }
    } $Mutation
    try{& $Body}finally{& $module {Set-Item -Path function:script:Get-YcDataInventory -Value $script:SavedDataInventory;Remove-Variable SavedDataInventory,DataInventoryCount,DataMutation -Scope Script}}
}
New-Item -ItemType Directory -Path $fixture | Out-Null
$state=Join-Path $fixture 'state';$backup=Join-Path $fixture 'backup'
New-Item -ItemType Directory -Path (Join-Path $state 'user-model\empty'),$backup -Force | Out-Null
Write-Fixture (Join-Path $state 'user-model\journal.jsonl') '{"synthetic":"learning-secret-marker"}'
foreach($name in @('learning.json','professional-lexicons.json','speech.json','yime_blocklist.txt','yime_user_phrases.txt','yimecore_experimental_toolbar_state.json')){Write-Fixture (Join-Path $state $name) 'synthetic-settings-secret-marker'}
Write-Fixture (Join-Path $state 'runtime-config.json') '{"synthetic":"config-secret-marker"}'
Write-Fixture (Join-Path $state 'runtime-status.json') 'excluded-status-marker'
try{
    Check 'public-surface-only-explicit-roots-and-schema' {
        Require (@($module.ExportedFunctions.Keys).Count -eq 2) 'Export surface expanded'
        $cmd=Get-Command Get-YimeCoreNativeMaintenanceDataSnapshot
        foreach($name in @('StateRoot','BaselineSchemaVersion','SharedObservation')){Require $cmd.Parameters.ContainsKey($name) 'Missing explicit input'}
        foreach($name in @('Provider','Reader','Contract','PackageRoot','InstalledPackage')){Require (-not $cmd.Parameters.ContainsKey($name)) 'Unsafe provider override'}
    }
    Check 'caller-preloaded-fixed-types-cannot-substitute-native-facts' {
        # Poison names only inside a disposable child, never the caller's PS7
        # session (which may run unrelated regressions after this script).
        $childPath=Join-Path $fixture 'spoof-types.ps1';$childResult=Join-Path $fixture 'spoof-types.json'
        $childSource=@'
param([string]$ModulePath,[string]$Root,[string]$ResultPath)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;
using System.IO;
using Microsoft.Win32.SafeHandles;
namespace Yime.MaintenanceDataFacts {
    public static class Facts {
        public static string VerifyFileHandle(FileStream stream,string path){throw new Exception("preloaded fake facts invoked");}
    }
}
namespace Yime {
    public static class MaintenanceDataPaths {
        public static SafeFileHandle OpenDirectory(string path){throw new Exception("preloaded fake directory helper invoked");}
        public static void VerifyDirectory(SafeFileHandle handle,string path){throw new Exception("preloaded fake verification invoked");}
        public static void RejectNamedStreams(string path){throw new Exception("preloaded fake streams invoked");}
    }
}
"@
$m=Import-Module $ModulePath -Force -PassThru
$snapshot=Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $Root -BaselineSchemaVersion 'yimecore-native-maintenance-data-v1'
$privateTypes=& $m {($script:DataFactsType.Namespace -cmatch '^Yime\.MaintenanceData_[a-f0-9]{32}$') -and ($script:DataPathsType.Namespace -ceq $script:DataFactsType.Namespace)}
if(-not $privateTypes -or -not $snapshot.native_handle_paths_verified){throw 'Private native types were not used'}
[IO.File]::WriteAllText($ResultPath,'{"passed":true}',[Text.UTF8Encoding]::new($false))
'@
        Write-Fixture $childPath $childSource
        $shell=Join-Path $PSHOME $(if($PSVersionTable.PSVersion.Major -ge 7){'pwsh.exe'}else{'powershell.exe'})
        & $shell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $childPath -ModulePath $modulePath -Root $state -ResultPath $childResult
        Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $childResult)) 'Disposable spoof regression failed'
        Require ((Get-Content -LiteralPath $childResult -Raw|ConvertFrom-Json).passed) 'Preloaded helper substituted'
    }
    $before=Snapshot $state
    Check 'fixed-seven-categories-and-recursive-empty-directory' {
        Require ($before.categories.Count -eq 7 -and $before.records.Count -eq 9) 'Incorrect category records'
        Require (@($before.records|Where-Object {$_.path -ceq 'user-model/empty' -and $_.kind -ceq 'directory'}).Count -eq 1) 'Empty directory missing'
        Require (@($before.records|Where-Object {$_.path -like '*runtime*'}).Count -eq 0) 'Runtime metadata mixed with user data'
    }
    Check 'catalog-matches-maintenance-safety-source-without-loading-helper' {
        $tokens=$null;$parseErrors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'local-maintenance-safety.ps1'),[ref]$tokens,[ref]$parseErrors)
        Require ($parseErrors.Count -eq 0) 'Maintenance safety source parse failed'
        $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-YimeCoreDataRecords'},$true)
        $loop=$function.Body.Find({param($node)$node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -ceq 'name'},$true)
        $names=@($loop.Condition.FindAll({param($node)$node -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object Value)
        Require (($names -join '|') -ceq (($before.categories|Select-Object -Skip 1) -join '|')) 'Data file category drifted from maintenance backup'
        $model=@($function.Body.FindAll({param($node)$node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -ceq 'user-model'},$true))
        Require ($model.Count -eq 1 -and $before.categories[0] -ceq 'user-model/') 'Recursive model category drifted'
    }
    Check 'runtime-config-only-separate-fingerprint-no-plaintext' {
        Require ($before.runtime_config.kind -ceq 'file' -and $before.runtime_config.sha256 -ceq (Get-FileHash -LiteralPath (Join-Path $state 'runtime-config.json')).Hash.ToLowerInvariant()) 'Config fingerprint missing'
        $text=ConvertTo-Json -InputObject $before -Depth 30
        Require (-not $text.Contains('secret-marker') -and -not $text.Contains('excluded-status-marker')) 'Plaintext leaked'
    }
    Check 'native-file-path-identity-and-default-sharing-claims' {
        Require ($before.sharing_mode -ceq 'read' -and $before.ordinary_file_writers_excluded_during_observation -and $before.native_handle_paths_verified -and $before.single_link_files_verified) 'Native facts missing'
        foreach($row in @($before.records|Where-Object kind -eq file)){Require ($row.file_identity -cmatch '^[a-f0-9]{8}:[a-f0-9]{16}$') 'File identity malformed'}
        foreach($name in @('atomic','quiescent','continuous_membership_protection','authenticated','execution_authorized')){Require (-not $before.$name) 'Overstated observation'}
    }
    Check 'unchanged-recapture-and-serialized-roundtrip' {
        $result=Compare-YimeCoreNativeMaintenanceDataSnapshots (Clone-Snapshot $before) (Clone-Snapshot (Snapshot $state))
        Require ($result.unchanged -and $result.data_unchanged -and $result.runtime_config_unchanged -and $result.serialized_evidence_only -and -not $result.authenticated) 'Unchanged comparison incorrect'
    }
    Check 'file-addition-observed' {
        $path=Join-Path $state 'user-model\new.json';Write-Fixture $path '{}'
        try{$result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Snapshot $state);Require (-not $result.data_unchanged -and $result.added_paths -ccontains 'user-model/new.json') 'Addition missed'}finally{Remove-Item -LiteralPath $path}
    }
    Check 'file-deletion-observed' {
        $path=Join-Path $state 'speech.json';Remove-Item -LiteralPath $path
        try{$result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Snapshot $state);Require ($result.deleted_paths -ccontains 'speech.json') 'Deletion missed'}finally{Write-Fixture $path 'synthetic-settings-secret-marker'}
    }
    Check 'same-length-content-change-observed' {
        $path=Join-Path $state 'learning.json';Write-Fixture $path 'synthetic-settings-secret-markeR'
        try{$result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Snapshot $state);Require ($result.changed_paths -ccontains 'learning.json') 'Same-size change missed'}finally{Write-Fixture $path 'synthetic-settings-secret-marker'}
    }
    Check 'empty-directory-addition-and-deletion-observed' {
        $path=Join-Path $state 'user-model\new-empty';New-Item -ItemType Directory -Path $path | Out-Null
        $with=Snapshot $state;Require ((Compare-YimeCoreNativeMaintenanceDataSnapshots $before $with).added_paths -ccontains 'user-model/new-empty') 'Empty directory addition missed'
        Remove-Item -LiteralPath $path;Require ((Compare-YimeCoreNativeMaintenanceDataSnapshots $with (Snapshot $state)).deleted_paths -ccontains 'user-model/new-empty') 'Empty directory deletion missed'
    }
    Check 'runtime-config-change-is-independent-from-user-data' {
        $path=Join-Path $state 'runtime-config.json';Write-Fixture $path 'different config'
        try{$result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Snapshot $state);Require ($result.data_unchanged -and -not $result.runtime_config_unchanged -and -not $result.unchanged) 'Config change mixed or missed'}finally{Write-Fixture $path '{"synthetic":"config-secret-marker"}'}
    }
    Check 'absent-config-and-empty-user-data-supported' {
        $empty=Snapshot $backup
        Require ($empty.records -is [array] -and $empty.records.Count -eq 0 -and $empty.runtime_config.kind -ceq 'absent') 'Absent data not represented'
        Require ((Compare-YimeCoreNativeMaintenanceDataSnapshots $empty (Clone-Snapshot $empty)).unchanged) 'Empty serialized snapshot rejected'
    }
    Check 'different-root-requires-explicit-mapping' {
        Copy-Item -LiteralPath (Join-Path $state 'user-model') -Destination $backup -Recurse
        foreach($name in $before.categories|Where-Object {$_ -ne 'user-model/'}){Copy-Item -LiteralPath (Join-Path $state $name) -Destination $backup}
        Copy-Item -LiteralPath (Join-Path $state 'runtime-config.json') -Destination $backup
        $other=Snapshot $backup;Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before $other}
        $result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before $other -AllowDifferentRoots
        Require ($result.unchanged -and $result.different_roots_explicitly_allowed -and -not $result.authenticated -and $result.file_identity_changed_paths.Count -eq 0) 'Explicit mapping failed'
    }
    Check 'strict-default-rejects-live-write-handle-and-closes-failed-leases' {
        $writer=[IO.File]::Open((Join-Path $state 'user-model\journal.jsonl'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
        try{Reject {Snapshot $state}}finally{$writer.Dispose()}
        $after=Snapshot $state;Require $after.two_pass_equal 'Failed observation leaked handles'
    }
    Check 'explicit-shared-mode-observes-persistent-writer-without-exclusive-claim' {
        $writer=[IO.File]::Open((Join-Path $state 'user-model\journal.jsonl'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
        try{$after=Snapshot $state -Shared;Require ($after.sharing_mode -ceq 'read-write-delete' -and -not $after.ordinary_file_writers_excluded_during_observation) 'Sharing claim incorrect'
            $result=Compare-YimeCoreNativeMaintenanceDataSnapshots $before $after
            Require ($result.unchanged -and $result.after_sharing_mode -ceq 'read-write-delete' -and -not $result.quiescent) 'Shared observation compared incorrectly'
        }finally{$writer.Dispose()}
    }
    Check 'shared-mode-detects-during-observation-content-write' {
        try{Invoke-InventoryMutation {param($root)[IO.File]::WriteAllText((Join-Path $root 'learning.json'),'changed')} {Reject {Snapshot $state -Shared}}}
        finally{Write-Fixture (Join-Path $state 'learning.json') 'synthetic-settings-secret-marker'}
    }
    Check 'shared-mode-rejects-same-content-path-replacement' {
        try{
            Invoke-InventoryMutation {param($root)
                $path=Join-Path $root 'learning.json';$saved=Join-Path (Split-Path -Parent $root) 'displaced-learning.json'
                [IO.File]::Move($path,$saved);[IO.File]::WriteAllText($path,'synthetic-settings-secret-marker')
            } {Reject {Snapshot $state -Shared}}
        }finally{
            $saved=Join-Path $fixture 'displaced-learning.json'
            if(Test-Path -LiteralPath $saved){Remove-Item -LiteralPath $saved}
            Write-Fixture (Join-Path $state 'learning.json') 'synthetic-settings-secret-marker'
        }
    }
    Check 'strict-mode-blocks-write-during-observation' {
        Invoke-InventoryMutation {param($root)
            $blocked=$false;try{$writer=[IO.File]::Open((Join-Path $root 'learning.json'),[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$writer.Dispose()}catch{$blocked=$true}
            if(-not $blocked){throw 'Expected ordinary writer to be denied'}
        } {Require ((Snapshot $state).two_pass_equal) 'Strict read observation failed'}
    }
    Check 'held-directory-list-handles-deny-real-root-and-subdirectory-rename' {
        Invoke-InventoryMutation {param($root)
            foreach($path in @($root,(Join-Path $root 'user-model\empty'))){
                $destination=$path+'-renamed';$blocked=$false
                try{[IO.Directory]::Move($path,$destination)}catch{$blocked=$true}
                if(-not $blocked){[IO.Directory]::Move($destination,$path);throw 'Directory rename bypassed held observation handle'}
            }
        } {Require ((Snapshot $state).two_pass_equal) 'Directory rename barrier failed'}
    }
    Check 'observed-new-membership-fails-closed' {
        try{Invoke-InventoryMutation {param($root)[IO.File]::WriteAllText((Join-Path $root 'user-model\raced.json'),'{}')} {Reject {Snapshot $state}}}
        finally{$path=Join-Path $state 'user-model\raced.json';if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}}
    }
    Check 'unlisted-transient-does-not-upgrade-continuous-claim' {
        Invoke-InventoryMutation {param($root)
            $path=Join-Path $root 'user-model\transient.json';[IO.File]::WriteAllText($path,'{}');[IO.File]::Delete($path)
        } {$after=Snapshot $state;Require (-not $after.continuous_membership_protection -and -not $after.quiescent -and -not $after.authenticated) 'Transient overstated'}
    }
    Check 'file-named-stream-rejected' {
        $path=(Join-Path $state 'learning.json')+':hidden';Set-FixtureStream $path
        try{Reject {Snapshot $state}}finally{Set-FixtureStream $path -Remove}
    }
    Check 'directory-named-stream-rejected' {
        $path=(Join-Path $state 'user-model\empty')+':hidden';Set-FixtureStream $path
        try{Reject {Snapshot $state}}finally{Set-FixtureStream $path -Remove}
    }
    Check 'hard-link-rejected' {
        $path=Join-Path $state 'user-model\hard.json';New-Item -ItemType HardLink -Path $path -Target (Join-Path $state 'learning.json') | Out-Null
        try{Reject {Snapshot $state}}finally{Remove-Item -LiteralPath $path}
    }
    Check 'junction-subtree-rejected-without-traversal' {
        $path=Join-Path $state 'user-model\junction';New-Item -ItemType Junction -Path $path -Target $backup | Out-Null
        try{Reject {Snapshot $state}}finally{[IO.Directory]::Delete($path,$false)}
    }
    Check 'root-junction-rejected' {
        $path=Join-Path $fixture 'root-junction';New-Item -ItemType Junction -Path $path -Target $state | Out-Null
        try{Reject {Snapshot $path}}finally{[IO.Directory]::Delete($path,$false)}
    }
    foreach($bad in @(($state+'\..\state'),($state+'\'),($state+'/'),'state',($state+':hidden'),$state.ToLowerInvariant())){Check ('reject-noncanonical-root-'+$bad){Reject {Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $bad -BaselineSchemaVersion $schema}}}
    Check 'reject-array-root-and-schema' {
        Reject {Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot @($state) -BaselineSchemaVersion $schema}
        Reject {Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $state -BaselineSchemaVersion @($schema)}
        Reject {Get-YimeCoreNativeMaintenanceDataSnapshot -StateRoot $state -BaselineSchemaVersion 'unknown'}
    }
    Check 'reject-wrong-category-kind' {
        $path=Join-Path $state 'speech.json';Remove-Item -LiteralPath $path;New-Item -ItemType Directory -Path $path | Out-Null
        try{Reject {Snapshot $state}}finally{Remove-Item -LiteralPath $path;Write-Fixture $path 'synthetic-settings-secret-marker'}
    }
    foreach($claim in @('atomic','quiescent','continuous_membership_protection','authenticated','execution_authorized')){Check ('reject-resealed-overclaim-'+$claim){$bad=Clone-Snapshot $before;$bad.$claim=$true;Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}}
    Check 'reject-resealed-sharing-contradiction' {$bad=Clone-Snapshot $before;$bad.sharing_mode='read-write-delete';Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    Check 'reject-resealed-array-identities-and-booleans' {
        foreach($name in @('schema_version','state_root','sharing_mode','native_handle_paths_verified')){$bad=Clone-Snapshot $before;$bad.$name=@($bad.$name);Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    }
    Check 'reject-digest-tamper' {$bad=Clone-Snapshot $before;$bad.records[0].sha256=('a'*64);Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before $bad}}
    Check 'reject-resealed-case-duplicate-records' {
        $bad=Clone-Snapshot $before;$duplicate=Clone-Snapshot $bad.records[0];$duplicate.path=$duplicate.path.ToUpperInvariant();$bad.records+=,$duplicate
        Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}
    }
    Check 'reject-resealed-outside-relative-path' {$bad=Clone-Snapshot $before;$bad.records[0].path='../learning.json';Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    Check 'reject-resealed-ads-relative-path' {$bad=Clone-Snapshot $before;$bad.records[0].path='learning.json:stream';Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    Check 'reject-resealed-missing-directory-closure' {$bad=Clone-Snapshot $before;$bad.records=@($bad.records|Where-Object path -ne 'user-model');Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    Check 'reject-resealed-file-array-values' {
        foreach($field in @('path','kind','bytes','sha256','file_identity')){$bad=Clone-Snapshot $before;$bad.records[0].$field=@($bad.records[0].$field);Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    }
    Check 'reject-record-plaintext-extra-field' {$bad=Clone-Snapshot $before;$bad.records[0]|Add-Member -NotePropertyName content -NotePropertyValue 'secret';Reject {Compare-YimeCoreNativeMaintenanceDataSnapshots $before (Reseal $bad)}}
    Check 'metadata-reseal-cannot-claim-authenticated-origin' {
        $bad=Clone-Snapshot $before;$bad.records[0].sha256=('b'*64);$bad=Reseal $bad
        $result=Compare-YimeCoreNativeMaintenanceDataSnapshots $bad $bad
        Require ($result.unchanged -and $result.serialized_evidence_only -and -not $result.authenticated -and -not $result.execution_authorized) 'Self-hash mistaken for origin authentication'
    }
    Check 'successful-observation-closes-all-file-leases' {
        $handle=[IO.File]::Open((Join-Path $state 'learning.json'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $handle.Dispose()
    }
}finally{
    $expectedPrefix=Join-Path $repo '.tmp\native-maintenance-data-'
    if(-not $fixture.StartsWith($expectedPrefix,[StringComparison]::Ordinal) -or $fixture.Substring($expectedPrefix.Length) -cnotmatch '^[a-f0-9]{32}$' -or [IO.Path]::GetFullPath($fixture) -cne $fixture){throw 'Unsafe fixture cleanup target'}
    # Junctions are removed explicitly in their owning test, never recursively.
    if(@(Get-ChildItem -LiteralPath $fixture -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Refuse recursive cleanup with remaining reparse point'}
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
$result=[ordered]@{schema_version='yimecore-native-maintenance-data-test-v1';powershell=$PSVersionTable.PSVersion.ToString();passed=(@($checks|Where-Object {-not $_.passed}).Count -eq 0);checks=$checks.ToArray();check_count=$checks.Count;
    source_sha256=(Get-FileHash -LiteralPath $modulePath).Hash.ToLowerInvariant();test_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();actual_user_state_accessed=$false;product_executed=$false;execution_authorized=$false}
[IO.File]::WriteAllText($out,((ConvertTo-Json -InputObject $result -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw ('Native data regressions failed: '+(@($checks|Where-Object {-not $_.passed}|ForEach-Object {$_.name+': '+$_.error}) -join '; '))}
Write-Output ('PASS: '+$checks.Count+' native data observations; evidence '+$out)
