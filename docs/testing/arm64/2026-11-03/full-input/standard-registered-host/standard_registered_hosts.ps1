[CmdletBinding()]
param([switch]$Execute,[string]$EvidenceRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source='C:\dev\Yime\.generated\arm64-standard-src'
$build=Join-Path $source '.tmp/yimecore-platform-experiments/arm64-package-20261103-204612-a5f1a434'
$packageRoot=Join-Path $source '.generated/standard-arm64-validation/YimeCore-0.1.0-local.13-main64a785a7-arm64-20261103'
$manifestHash='5f976f70ace424340b6d9f7138a63e57eb4167b493e1a56afa0b277386fd994b'
$x64Host=Join-Path $build 'native-x64-test/Release/YimeRegisteredHostTests.exe'
$x64Hash='464068c26fc559efac3982d9437003cefa6b637a091b9a41d1aabfc7211c5fd5'
. (Join-Path $source 'tools/yimecore/build-system-observation.ps1')
. (Join-Path $source 'tools/yimecore/local-product-build-common.ps1')
. (Join-Path $source 'tools/yimecore/local-product-test-isolation.ps1')
Import-Module (Join-Path $packageRoot 'Product.psm1') -Force
$package=Read-Package $packageRoot
Assert-PackageHost $package.contract
if([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -cne 'Arm64'){throw 'Run the checked script in native ARM64 PS7.'}
if((Get-ContentHash (Join-Path $packageRoot 'product-package.json')) -cne $manifestHash -or (Get-ContentHash $x64Host) -cne $x64Hash){throw 'Pinned standard package or same-source x64 host changed.'}
if(-not $Execute){
    Write-Output 'PREPARED ONLY: pinned 69-file standard main64a785a7 package and x64 host verified. No installed-host activation executed.'
    Write-Output 'After root agent confirms installation, invoke this same script with Execute=true. It refuses open Word, isolates all synthetic state, and never closes document applications.'
    return
}
$install=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'YimeCore'
$allowed=Join-Path $repo '.generated'
if(-not $EvidenceRoot){$EvidenceRoot=Join-Path $allowed ('standard-registered-host-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
$out=[IO.Path]::GetFullPath($EvidenceRoot)
Assert-LocalProductPlainPath $out
if(-not $out.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Choose a fresh evidence child under this worktree .generated directory.'}
$null=New-Item -ItemType Directory -Path $out
$before=$null;$after=$null;$passed=$false;$failure=$null;$runs=@();$ownedBrokers=@()
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Digest-Value($Value){
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 40 -Compress))
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Assert-NoWord {
    $word=@(Get-Process -Name WINWORD -ErrorAction SilentlyContinue)
    if($word.Count){throw ('Word is open (PID '+(($word.Id|Sort-Object)-join ',')+'). Do not close or kill it automatically; root must arrange a safe test window.')}
}
function Get-ProtectedSnapshot {
    $keys=[ordered]@{}
    foreach($id in @('{35F67E9D-A54D-4177-9697-8B0AB71A9E04}','{6DFACE1F-562E-4773-A9D6-D5753A314711}')){
        foreach($path in @(('SOFTWARE\Classes\CLSID\'+$id),('SOFTWARE\Classes\Wow6432Node\CLSID\'+$id),('SOFTWARE\Microsoft\CTF\TIP\'+$id),('SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\'+$id))){
            $keys['HKLM\'+$path]=Digest-Value (Read-YimeCoreSystemKey 2147483650 $path)
        }
        $path=$sid+'\Software\Microsoft\CTF\TIP\'+$id
        $keys['HKU\'+$path]=Digest-Value (Read-YimeCoreSystemKey 2147483651 $path)
    }
    foreach($suffix in @('Control Panel\International\User Profile','Keyboard Layout\Preload','Keyboard Layout\Substitutes')){
        $path=$sid+'\'+$suffix
        $keys['HKU\'+$path]=Digest-Value (Read-YimeCoreSystemKey 2147483651 $path)
    }
    $programFiles=[Environment]::GetFolderPath('ProgramFiles')
    $roots=@((Join-Path $programFiles 'Yime Rime-PIME'),(Join-Path $programFiles 'YimeCore 18u Touch'),'C:\Program Files (x86)\YIME')
    $processes=@(foreach($p in Get-CimInstance Win32_Process){
        if(-not $p.ExecutablePath){continue}
        foreach($root in $roots){
            if($p.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
                [ordered]@{pid=[uint32]$p.ProcessId;image=[string]$p.ExecutablePath;started=$p.CreationDate.ToUniversalTime().ToString('o')}
                break
            }
        }
    })
    return [ordered]@{registry_hashes=$keys;other_product_runtime_processes=@($processes|Sort-Object {$_.image},{$_.pid})}
}
function Assert-Protected {
    $now=Get-ProtectedSnapshot
    if((Digest-Value $now) -cne (Digest-Value $before)){throw 'Other product registration/runtime process or default-input snapshot changed. Stop; do not repair automatically.'}
}
# Reuse exact process-ownership checks from the immutable standard source.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'tools/yimecore/test-focus-cancellation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Immutable owned-Broker helpers did not parse.'}
foreach($name in @('Wait-IsolatedBroker','Stop-IsolatedBroker')){
    $definition=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name)
    if($definition.Count -ne 1){throw 'Owned process helper missing.'}
    Invoke-Expression $definition[0].Extent.Text
}
try{
    Assert-NoWord
    Assert-LocalProductPlainPath $install
    if((Get-ContentHash (Join-Path $install '.setup/product-package.json')) -cne $manifestHash){throw 'The exact final standard package is not installed.'}
    foreach($row in $package.manifest.files){
        $path=Join-Path $install $row.path
        Assert-LocalProductPlainPath $path
        if((Get-Item -LiteralPath $path).Length -ne $row.bytes -or (Get-ContentHash $path) -cne $row.sha256){throw ('Installed payload mismatch: '+$row.path)}
    }
    $id='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
    foreach($arch in @('arm64','x86')){
        $prefix=if($arch -eq 'arm64'){'SOFTWARE\Classes\CLSID\'}else{'SOFTWARE\Classes\Wow6432Node\CLSID\'}
        $key=Read-YimeCoreSystemKey 2147483650 ($prefix+$id+'\InprocServer32')
        if(-not $key.exists){throw ('Installed '+$arch+' COM registration is absent.')}
        $value=@($key.values|Where-Object {$_.name -ceq ''})
        if(-not $key.exists -or $value.Count -ne 1 -or $value[0].value -ine (Join-Path $install ($arch+'/YimeTextServiceExperiment.dll'))){throw ('Installed '+$arch+' registration does not point to the current standard product.')}
    }
    $before=Get-ProtectedSnapshot
    Write-LocalProductJson $before (Join-Path $out 'protection-before.json')
    Write-LocalProductJson ([ordered]@{source_commit='64a785a7ede5fb2a53e2560b873075950160668b';package_manifest_sha256=$manifestHash;installed_root=$install;x64_host=$x64Host;x64_host_sha256=$x64Hash;installed_payload_hashes_verified=69;registration_executed=$false;registered_host_activation_authorized=$true}) (Join-Path $out 'inputs.json')
    foreach($mode in @('full','variable','shorthand')){
        $modeRoot=Join-Path $out $mode;$null=New-Item -ItemType Directory -Path $modeRoot
        $pipe='\\.\pipe\YimeBroker.StandardRegistered.'+[guid]::NewGuid().ToString('N')
        $broker=Join-Path $install 'bin/YimeBroker.exe'
        $arguments='-index "{0}" -mode {1} -named-pipe "{2}"' -f (Join-Path $install ('indexes/'+$mode+'.yidx')),$mode,$pipe
        $process=Start-Process -FilePath $broker -ArgumentList $arguments -WorkingDirectory $modeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $modeRoot 'broker-out.txt') -RedirectStandardError (Join-Path $modeRoot 'broker-err.txt')
        $started=$process.StartTime
        $owned=[ordered]@{mode=$mode;pid=$process.Id;image=$broker;started=$started.ToUniversalTime().ToString('o');pipe=$pipe;stopped=$false}
        $ownedBrokers+=$owned
        try{
            Wait-IsolatedBroker $process $broker $started $pipe
            foreach($arch in @('arm64','x64','x86')){
                Assert-NoWord
                $exe=if($arch -eq 'x64'){$x64Host}else{Join-Path $install ($arch+'/YimeRegisteredHostTests.exe')}
                $fixture=Join-Path (Get-LocalProductFixtureBase) ([guid]::NewGuid().ToString('N').Substring(0,16))
                $null=New-Item -ItemType Directory -Path $fixture
                $childEnvironment=@{TEMP=(Join-Path $fixture 'tmp');TMP=(Join-Path $fixture 'tmp');LOCALAPPDATA=(Join-Path $fixture 'local');APPDATA=(Join-Path $fixture 'roaming')}
                foreach($path in @($childEnvironment.Values|Select-Object -Unique)){$null=New-Item -ItemType Directory -Path $path}
                $settingsRoot=Join-Path $childEnvironment.LOCALAPPDATA 'YimeCore Experimental Trial'
                $null=New-Item -ItemType Directory -Path $settingsRoot
                Write-LocalProductJson ([ordered]@{experiment_mode=$mode;ascii_mode=$false;full_shape=$false;ascii_punctuation=$false;candidate_page_size=5}) (Join-Path $settingsRoot 'yimecore_experimental_toolbar_state.json')
                $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
                $info.WorkingDirectory=$modeRoot;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
                $info.ArgumentList.Add($pipe)
                foreach($name in $childEnvironment.Keys){$info.Environment[$name]=$childEnvironment[$name]}
                foreach($name in @('YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE','YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST')){$null=$info.Environment.Remove($name)}
                $record=[ordered]@{mode=$mode;architecture=$arch;executable=$exe;sha256=(Get-ContentHash $exe);fixture=$fixture;passed=$false;exit_code=$null}
                $runs+=$record
                Write-Output ('RUN installed standard registered host: '+$mode+'/'+$arch)
                $hostProcess=[Diagnostics.Process]::Start($info);$hostStart=$hostProcess.StartTime
                $stdout=$hostProcess.StandardOutput.ReadToEndAsync();$stderr=$hostProcess.StandardError.ReadToEndAsync()
                try{
                    if(-not $hostProcess.WaitForExit(120000)){
                        Stop-IsolatedBroker $hostProcess $exe $hostStart
                        throw 'The owned synthetic registered-host process exceeded its timeout; no document application was stopped.'
                    }
                    $record.exit_code=$hostProcess.ExitCode
                    $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
                    [IO.File]::WriteAllText((Join-Path $modeRoot ('host-'+$arch+'.txt')),$text,[Text.UTF8Encoding]::new($false))
                    [IO.File]::WriteAllText((Join-Path $modeRoot ('host-'+$arch+'-err.txt')),$errorText,[Text.UTF8Encoding]::new($false))
                    if($record.exit_code -ne 0){throw ('Registered host failed: '+$mode+'/'+$arch+'; '+$errorText)}
                    foreach($marker in @('registered_key_sink_verified=true','registered_candidate_commit=true','registered_focus_cancellation_preserves_committed_text_verified=true','failed_async_edit_recovery_verified=true','registered_failed_focus_cancellation_text_preservation_verified=true','retained_language_bar_after_deactivation_verified=true')){
                        if(-not $text.Contains($marker)){throw ('Required registered-host evidence missing: '+$marker)}
                    }
                    $bits=if($arch -eq 'x86'){32}else{64}
                    if(-not $text.Contains('architecture_bits='+$bits)){throw 'Registered host bitness marker mismatch.'}
                    $record.passed=$true
                }finally{
                    if($hostProcess.HasExited){
                        $record.exit_code=$hostProcess.ExitCode
                        [IO.File]::WriteAllText((Join-Path $modeRoot ('host-'+$arch+'.txt')),$stdout.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
                        [IO.File]::WriteAllText((Join-Path $modeRoot ('host-'+$arch+'-err.txt')),$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
                    }
                    $hostProcess.Dispose()
                    $retained=[IO.Path]::GetFullPath((Join-Path $modeRoot ('fixture-'+$arch)))
                    $fixtureBase=[IO.Path]::GetFullPath((Get-LocalProductFixtureBase)).TrimEnd('\')
                    if(-not $retained.StartsWith($out+'\',[StringComparison]::OrdinalIgnoreCase) -or
                       -not [IO.Path]::GetFullPath($fixture).StartsWith($fixtureBase+'\',[StringComparison]::OrdinalIgnoreCase) -or
                       (Test-Path -LiteralPath $retained)){throw 'Fixture retention path is not a fresh owned evidence child.'}
                    Assert-LocalProductPlainPath $fixture;Assert-LocalProductPlainPath $retained
                    Move-Item -LiteralPath $fixture -Destination $retained
                    $record.fixture=$retained
                }
                Assert-Protected
                Write-Output ('PASS installed standard registered host: '+$mode+'/'+$arch)
            }
        }finally{
            try{Stop-IsolatedBroker $process $broker $started;$owned.stopped=$true}finally{$process.Dispose()}
        }
    }
    $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
    $preserved=$false
    if($before){
        try{$after=Get-ProtectedSnapshot;$preserved=(Digest-Value $before) -ceq (Digest-Value $after);Write-LocalProductJson $after (Join-Path $out 'protection-after.json')}
        catch{if(-not $failure){$failure='Protection observation failed: '+$_.Exception.Message}}
    }
    Write-LocalProductJson ([ordered]@{schema='standard-arm64-registered-host-v1';passed=($passed -and $preserved);failure=$failure;runs=$runs;owned_private_brokers=$ownedBrokers;other_products_and_default_preserved=$preserved;installer_executed=$false;registration_executed=$false;registered_host_executed=($runs.Count -gt 0);live_document_acceptance=$false;physical_acceptance=$false;scope='Installed current standard DLLs, fresh owned TSF hosts, three installed indexes and private in-memory Brokers. No existing process stopped, document app closed, default input set, live user state read or test state merged.'}) (Join-Path $out 'summary.json')
}
if(-not $preserved){throw 'Final other-product/default protection comparison failed.'}
Write-Output ('PASS '+$runs.Count+' installed registered-host architecture/mode checks. Evidence: '+$out)
