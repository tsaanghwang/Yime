[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository .tmp evidence file required'}
$cursor=Split-Path -Parent $out
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test output'};$cursor=Split-Path -Parent $cursor}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$fixture=Join-Path $repo ('.tmp\native-maintenance-runtime-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$source=Join-Path $PSScriptRoot 'native-maintenance-runtime.psm1'
$module=Import-Module $source -Force -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){try{& $Body | Out-Null;$checks.Add([ordered]@{name=$Name;passed=$true})}catch{$checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$failed=$false;try{& $Body | Out-Null}catch{$failed=$true};Require $failed 'Expected fail-closed rejection'}
$fakeLease=[pscustomobject]@{id='fixture-original-reference'}
Check 'real lease reader rejects serialized object before opening any config' {
    Reject {Get-YimeCoreNativeMaintenanceRuntime -ProcessObservation $fakeLease -StateRoot (Join-Path $fixture 'absent') -ExpectedRuntimeConfigSha256 ('a'*64)}
}
Check 'public API has no arbitrary provider path or protocol payload' {
    $names=(Get-Command Get-YimeCoreNativeMaintenanceRuntime).Parameters.Keys
    foreach($forbidden in @('Provider','ScriptBlock','ConfigPath','PipeName','Command','Operation')){Require ($names -notcontains $forbidden) 'Unexpected override'}
}
& $module {
    param($lease,$install)
    $script:RuntimeFixtureLease=$lease;$script:RuntimeFixtureInstall=$install;$script:RuntimeFixtureMode='valid';$script:RuntimeFixtureReads=0
    function script:Read-MaintenanceRuntimeProcesses($Observation) {
        if(-not [object]::ReferenceEquals($Observation,$script:RuntimeFixtureLease)){throw 'Synthetic fixture requires original reference'}
        $script:RuntimeFixtureReads++
        if($script:RuntimeFixtureMode -ceq 'provider-failure' -or ($script:RuntimeFixtureMode -ceq 'exit-during-config' -and $script:RuntimeFixtureReads -eq 2)){throw 'Synthetic retained process exit'}
        $rows=@(
            [pscustomobject][ordered]@{role='runtime';pid=101;parent_pid=100;creation_filetime=133333333333333333L;image=(Join-Path $script:RuntimeFixtureInstall 'bin\YimeCoreTrialRuntime.exe');sid='S-1-5-21-1-2-3-4';elevated=$false;image_sha256=('a'*64)},
            [pscustomobject][ordered]@{role='broker';pid=102;parent_pid=101;creation_filetime=133333333333333334L;image=(Join-Path $script:RuntimeFixtureInstall 'bin\YimeBroker.exe');sid='S-1-5-21-1-2-3-4';elevated=$false;image_sha256=('b'*64)})
        $result=[pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-processes-v1';target_user_sid='S-1-5-21-1-2-3-4';expected_install_root=$script:RuntimeFixtureInstall;
            native_handle_identity_observed=$true;native_parent_relation_observed=$true;public_image_hash_verified=$true;processes=$rows}
        switch -CaseSensitive ($script:RuntimeFixtureMode){
            'null' {return $null}
            'string-true' {$result.native_handle_identity_observed='true'}
            'array-true' {$result.public_image_hash_verified=@($true)}
            'missing-process' {$result.processes=@($rows[0])}
            'extra-process' {$result.processes+=,$rows[1]}
            'wrong-role' {$rows[1].role='runtime'}
            'overlap-pid' {$rows[1].pid=101}
            'wrong-parent' {$rows[1].parent_pid=666}
            'older-broker' {$rows[1].creation_filetime=133333333333333332L}
            'string-pid' {$rows[0].pid='101'}
            'array-hash' {$rows[0].image_sha256=@('a'*64)}
            'wrong-path' {$rows[0].image='C:\other\YimeCoreTrialRuntime.exe'}
            'wrong-sid' {$rows[1].sid='S-1-5-21-1-2-3-5'}
            'elevated' {$rows[1].elevated=$true}
            'string-false' {$rows[1].elevated='false'}
            'reused-pid' {if($script:RuntimeFixtureReads -eq 2){$rows[0].creation_filetime=133333333333333335L;$rows[1].creation_filetime=133333333333333336L}}
            'changed-image' {if($script:RuntimeFixtureReads -eq 2){$rows[1].image_sha256='c'*64}}
            'write-sharing-barrier' {
                if($script:RuntimeFixtureReads -eq 2){
                    $opened=$null;$denied=$false
                    try{$opened=[IO.File]::Open($script:RuntimeFixtureConfig,'Open','Write','ReadWrite')}catch{$denied=$true}finally{if($opened){$opened.Dispose()}}
                    if(-not $denied){throw 'Configuration writer was not excluded'}
                    $script:RuntimeFixtureWriteDenied=$true
                }
            }
        }
        $result
    }
} $fakeLease (Join-Path $fixture 'installed')
function New-ConfigFixture {
    $state=Join-Path $fixture ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $state | Out-Null
    [pscustomobject]@{state=$state;path=(Join-Path $state 'runtime-config.json');config=[ordered]@{
        schema_version='yimecore-trial-runtime-config-v1';generated_at='2026-09-01T01:02:03.0000000Z';install_root=(Join-Path $fixture 'installed');
        runtime_path=(Join-Path $fixture 'installed\bin\YimeCoreTrialRuntime.exe');broker_path=(Join-Path $fixture 'installed\bin\YimeBroker.exe');
        state_root=$state;pipe_name='\\.\pipe\YimeBroker.YimeCoreTrial.v1';experimental_clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';
        experimental_input_method_tip='0804:{E40FA752-BB96-461D-A51D-F40EB437EC65}{126F54C6-E9B1-4E22-8652-03224CBD49F9}'}}
}
function Write-ConfigFixture($Case,[string]$Text='') {
    if(-not $Text){$Text=ConvertTo-Json -InputObject $Case.config -Depth 5 -Compress}
    [IO.File]::WriteAllText($Case.path,$Text,[Text.UTF8Encoding]::new($false))
    (Get-FileHash -LiteralPath $Case.path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Observe($Case,[string]$Hash,[string]$Mode='valid') {
    & $module {param($mode,$path)$script:RuntimeFixtureMode=$mode;$script:RuntimeFixtureReads=0;$script:RuntimeFixtureConfig=$path;$script:RuntimeFixtureWriteDenied=$false} $Mode $Case.path
    Get-YimeCoreNativeMaintenanceRuntime -ProcessObservation $fakeLease -StateRoot $Case.state -ExpectedRuntimeConfigSha256 $Hash
}
Check 'actual fixed config writer schema and active identity match fixture catalog' {
    $controller=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') -Raw
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($controller,[ref]$tokens,[ref]$errors)
    $writer=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Write-RuntimeConfiguration'},$true))
    Require ($writer.Count -eq 1) 'Missing source writer'
    foreach($key in (New-ConfigFixture).config.Keys){Require ($writer[0].Extent.Text.Contains($key)) 'Source writer schema changed'}
    Require ($controller.Contains('$clsid = ''{E40FA752-BB96-461D-A51D-F40EB437EC65}''') -and $controller.Contains('$profile = ''{126F54C6-E9B1-4E22-8652-03224CBD49F9}''')) 'Source identity changed'
}
Check 'ordinary input protocol remains separate from the session-free health service' {
    $protocol=Get-Content -LiteralPath (Join-Path $repo 'go-backend/input_methods/yime/yimebroker/protocol.go') -Raw
    $ops=@([regex]::Matches($protocol,'(?m)^\s*\w+\s+Operation\s*=\s*"([a-z]+)"')|ForEach-Object {$_.Groups[1].Value})
    Require (($ops -join ',') -ceq 'open,apply,select,forget,reset,close') 'Protocol changed; re-evaluate read-only health support'
}
Check 'flat native same-stream config and retained process facts converge without readiness claim' {
    $case=New-ConfigFixture;$hash=Write-ConfigFixture $case;$value=Observe $case $hash
    Require ($value.context_consistent -and $value.config_bound_to_expected_sha256 -and $value.config_semantics_verified -and $value.retained_process_lease_checked_twice) 'Missing concrete prerequisite evidence'
    Require ($value.runtime_config.sha256 -ceq $hash -and $value.runtime_config.metadata.Count -eq 9 -and $value.processes.processes[0].pid -eq 101) 'Metadata projection differs'
    foreach($flag in @('loaded_helper_identity_authenticated','runtime_consumed_config_verified','runtime_ready_verified','startup_verified','rollback_restart_verified','reboot_logon_startup_verified','E7_verified','L6_sealed','local_product_ready','public_release_ready','execution_authorized','health_endpoint_contacted','session_created','runtime_status_read','settings_or_learning_read')){Require ($value.$flag -is [bool] -and -not $value.$flag) ('Overclaimed '+$flag)}
    Require ((& $module {$script:RuntimeFixtureReads}) -eq 2) 'Process lease was not checked at both ends'
}
Check 'paired deploy metadata hashes must match held process images' {
    $case=New-ConfigFixture;$case.config.runtime_sha256='a'*64;$case.config.broker_sha256='b'*64
    $value=Observe $case (Write-ConfigFixture $case);Require ($value.runtime_config.metadata.Count -eq 11) 'Paired source variant rejected'
}
Check 'same config stream excludes a concurrent writer until the second process observation' {
    $case=New-ConfigFixture;$value=Observe $case (Write-ConfigFixture $case) 'write-sharing-barrier'
    Require ($value.context_consistent -and (& $module {$script:RuntimeFixtureWriteDenied})) 'Same-stream sharing barrier missing'
    $writer=[IO.File]::Open($case.path,'Open','Write','ReadWrite');$writer.Dispose()
}
Check 'neighbor status and settings bodies are not opened or returned' {
    $case=New-ConfigFixture;$hash=Write-ConfigFixture $case;$streams=@()
    try {
        foreach($name in @('runtime-status.json','learning.json','speech.json')){$path=Join-Path $case.state $name;[IO.File]::WriteAllText($path,'private-fixture-secret',[Text.UTF8Encoding]::new($false));$streams+=,[IO.File]::Open($path,'Open','ReadWrite','None')}
        $value=Observe $case $hash;Require (-not (ConvertTo-Json -InputObject $value -Depth 20 -Compress).Contains('private-fixture-secret')) 'Private neighbor content exposed'
    }finally{foreach($stream in $streams){$stream.Dispose()}}
}
foreach($mode in @('provider-failure','null','string-true','array-true','missing-process','extra-process','wrong-role','overlap-pid','wrong-parent','older-broker','string-pid','array-hash','wrong-path','wrong-sid','elevated','string-false','exit-during-config','reused-pid','changed-image')){
    Check ('reject process provider anomaly '+$mode) {$case=New-ConfigFixture;Reject {Observe $case (Write-ConfigFixture $case) $mode}}
}
foreach($field in @('schema_version','generated_at','install_root','runtime_path','broker_path','state_root','pipe_name','experimental_clsid','experimental_input_method_tip')){
    Check ('reject missing source config field '+$field) {$case=New-ConfigFixture;$case.config.Remove($field);Reject {Observe $case (Write-ConfigFixture $case)}}
    Check ('reject semantically changed config field '+$field) {$case=New-ConfigFixture;$case.config[$field]='different';Reject {Observe $case (Write-ConfigFixture $case)}}
}
foreach($replacement in @('$null','$true','array','object','number')){
    Check ('reject nonstring config value '+$replacement) {
        $case=New-ConfigFixture
        $case.config.pipe_name=switch($replacement){'$null'{$null}'$true'{$true}'array'{,@('\\.\pipe\YimeBroker.YimeCoreTrial.v1')}'object'{@{value='pipe'}}'number'{1}}
        Reject {Observe $case (Write-ConfigFixture $case)}
    }
}
foreach($mode in @('extra-field','unpaired-hash','wrong-optional-hash','unknown-paired-fields','future-time','offset-time','duplicate-key','case-key','trailing-json','unpaired-surrogate','empty-object','top-array','utf8-bom','invalid-utf8','oversize')){
    Check ('reject strict config encoding or schema '+$mode) {
        $case=New-ConfigFixture;$text=''
        switch($mode){
            'extra-field' {$case.config.diagnostic='must-not-return'}
            'unpaired-hash' {$case.config.runtime_sha256='a'*64}
            'wrong-optional-hash' {$case.config.runtime_sha256='c'*64;$case.config.broker_sha256='b'*64}
            'unknown-paired-fields' {$case.config.extra1='x';$case.config.extra2='y'}
            'future-time' {$case.config.generated_at=[DateTime]::UtcNow.AddDays(1).ToString('o')}
            'offset-time' {$case.config.generated_at='2026-09-01T01:02:03.0000000+00:00'}
            'duplicate-key' {$text=(ConvertTo-Json -InputObject $case.config -Compress).Replace('"schema_version":','"schema_version":"ignored","schema_version":')}
            'case-key' {$text=(ConvertTo-Json -InputObject $case.config -Compress).Replace('"schema_version":','"SCHEMA_VERSION":"ignored","schema_version":')}
            'trailing-json' {$text=(ConvertTo-Json -InputObject $case.config -Compress)+' {}'}
            'unpaired-surrogate' {$text=(ConvertTo-Json -InputObject $case.config -Compress).Replace('yimecore-trial-runtime-config-v1','\ud800')}
            'empty-object' {$text='{}'}
            'top-array' {$text='[]'}
            'oversize' {$text=' ' * 16385}
        }
        $hash=Write-ConfigFixture $case $text
        if($mode -eq 'utf8-bom'){$bytes=[byte[]]@(239,187,191)+[IO.File]::ReadAllBytes($case.path);[IO.File]::WriteAllBytes($case.path,$bytes);$hash=(Get-FileHash -LiteralPath $case.path).Hash.ToLowerInvariant()}
        if($mode -eq 'invalid-utf8'){[IO.File]::WriteAllBytes($case.path,[byte[]]@(255,254,123,0));$hash=(Get-FileHash -LiteralPath $case.path).Hash.ToLowerInvariant()}
        Reject {Observe $case $hash}
    }
}
Check 'different file hash cannot be replaced by semantically valid config' {$case=New-ConfigFixture;$hash=Write-ConfigFixture $case;Reject {Observe $case ('f'*64)}}
Check 'expected digest must be a literal string' {$case=New-ConfigFixture;Write-ConfigFixture $case;Reject {Get-YimeCoreNativeMaintenanceRuntime -ProcessObservation $fakeLease -StateRoot $case.state -ExpectedRuntimeConfigSha256 @('a'*64)}}
Check 'noncanonical relative or indirect input roots are rejected before reading' {
    foreach($bad in @('relative','C:\x\..\state','C:\x\state\','C:\x\state:stream','C:/x/state','C:\x\CON','C:\x\state.')){Reject {Get-YimeCoreNativeMaintenanceRuntime -ProcessObservation $fakeLease -StateRoot $bad -ExpectedRuntimeConfigSha256 ('a'*64)}}
}
Check 'configuration file with multiple hard links is rejected by actual native file handle' {
    $case=New-ConfigFixture;$hash=Write-ConfigFixture $case;$alias=Join-Path $fixture ('hard-'+[guid]::NewGuid().ToString('N')+'.json')
    New-Item -ItemType HardLink -Path $alias -Target $case.path | Out-Null
    Reject {Observe $case $hash}
}
Check 'junction root rejected without following private target content' {
    $case=New-ConfigFixture;$hash=Write-ConfigFixture $case;$link=Join-Path $fixture ('junction-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Junction -Path $link -Target $case.state | Out-Null
    $case.state=$link;Reject {Observe $case $hash}
}
Check 'config streams close after hash or semantic failure' {
    $case=New-ConfigFixture;$hash=Write-ConfigFixture $case;Reject {Observe $case ('f'*64)}
    $writer=[IO.File]::Open($case.path,'Open','Write','None');$writer.Dispose()
    $case.config.pipe_name='wrong';$hash=Write-ConfigFixture $case;Reject {Observe $case $hash}
    $writer=[IO.File]::Open($case.path,'Open','Write','None');$writer.Dispose()
}
Check 'source has no protocol connection launch session stop or installed script execution' {
    $text=Get-Content -LiteralPath $source -Raw
    Require (-not ($text -match 'NamedPipeClientStream|\.Connect\(|Start-Process|Stop-Process|\.Kill\(|Diagnostics\.Process.*Start|runtime-status\.json')) 'Observer contains active product operation'
}
Remove-Module $module
$failed=@($checks|Where-Object {-not $_.passed})
$result=[ordered]@{schema_version='yimecore-native-maintenance-runtime-tests-v1';passed=($failed.Count -eq 0);checks_passed=($checks.Count-$failed.Count);checks_failed=$failed.Count;checks=@($checks.ToArray());
    powershell_version=$PSVersionTable.PSVersion.ToString();module_sha256=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();test_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
    config_files_synthetic_only=$true;process_provider_private_fixture_only=$true;actual_native_config_file_handles_tested=$true;actual_product_processes_queried=$false;
    actual_installed_product_accessed=$false;actual_user_state_accessed=$false;actual_protocol_connection_created=$false;actual_installer_executed=$false;runtime_ready_verified=$false;L6_sealed=$false}
[IO.File]::WriteAllText($out,((ConvertTo-Json -InputObject $result -Depth 12)+"`n"),[Text.UTF8Encoding]::new($false))
if($failed.Count){$failed|ForEach-Object {Write-Output ('FAIL: '+$_.name+' - '+$_.error)};throw "$($failed.Count) runtime observation regressions failed"}
Write-Output "PASS: native runtime prerequisites $($checks.Count) checks; synthetic config/process observations only."
