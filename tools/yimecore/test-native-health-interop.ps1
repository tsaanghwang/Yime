[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Fresh repository .tmp output required'}
$cursor=Split-Path -Parent $output
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect fixture output'};$cursor=Split-Path -Parent $cursor}
$root=Join-Path $repo ('.tmp\health-interop-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
$exe=Join-Path $root 'health-interop.test.exe'
$base='\\.\pipe\YimeBroker-health-interop-'+[guid]::NewGuid().ToString('N')
$children=[Collections.Generic.List[object]]::new()
$previousEnvironment=@{}
foreach($name in @('GOCACHE','GOTMPDIR')){$previousEnvironment[$name]=@{present=(Test-Path -LiteralPath ('Env:\'+$name));value=[Environment]::GetEnvironmentVariable($name,'Process')}}
function File-Reference([string]$Path){[ordered]@{path=$Path;bytes=(Get-Item -LiteralPath $Path).Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}}
$sources=@(Get-ChildItem -LiteralPath (Join-Path $repo 'go-backend/input_methods/yime/yimebroker') -Filter '*.go' -File | Sort-Object Name | ForEach-Object {File-Reference $_.FullName})
$clientPath=Join-Path $PSScriptRoot 'native-maintenance-health-client.cs'
$clientSource=File-Reference $clientPath
$testSource=File-Reference $PSCommandPath
$result=[ordered]@{schema_version='yimecore-health-go-native-client-interop-v1';passed=$false;powershell_version=$PSVersionTable.PSVersion.ToString();
    test_source=$testSource;client_source=$clientSource;go_package_sources=$sources;binary=$null;round_trips=@();children=@();error='';cleanup_error='';
    separate_owned_processes=$true;retained_product_lease_integration_verified=$false;parentage_verified=$false;wire_fixture_only=$true;
    actual_product_executed=$false;installed_local12_mutated=$false;production_endpoint_contacted=$false;user_state_read=$false;
    runtime_ready_verified=$false;E7_verified=$false;L6_sealed=$false;full_acceptance=$false;in_memory_code_identity_verified=$false}
function Start-Fixture([int]$Role,$Broker=$null){
    $ready=Join-Path $root ('health-interop-ready-'+[guid]::NewGuid().ToString('N')+'.json')
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.Arguments='-test.run=^TestHealthInteropServer$ -test.timeout=40s'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['YIME_HEALTH_INTEROP']='1'
    $info.EnvironmentVariables['YIME_HEALTH_INTEROP_BASE']=$base
    $info.EnvironmentVariables['YIME_HEALTH_INTEROP_ROLE']=[string]$Role
    $info.EnvironmentVariables['YIME_HEALTH_INTEROP_READY']=$ready
    if($Role -eq 2){$info.EnvironmentVariables['YIME_HEALTH_INTEROP_BROKER_PID']=[string]$Broker.pid;$info.EnvironmentVariables['YIME_HEALTH_INTEROP_BROKER_CREATION']=[string]$Broker.creation_filetime}
    $process=[Diagnostics.Process]::Start($info)
    # Register the original handle before any redirected-reader setup can fail.
    $item=[pscustomobject]@{process=$process;stdout=$null;stderr=$null;stdout_reader=$null;stderr_reader=$null;ready=$ready;role=$Role}
    $children.Add($item)
    $item.stdout_reader=$process.StandardOutput;$item.stdout=$item.stdout_reader.ReadToEndAsync()
    $item.stderr_reader=$process.StandardError;$item.stderr=$item.stderr_reader.ReadToEndAsync()
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while($true){
        if($process.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Owned Go wire fixture did not publish readiness'}
        if(Test-Path -LiteralPath $ready){
            $text=Get-Content -LiteralPath $ready -Raw
            $parsed=$false;$record=$null
            if(-not [string]::IsNullOrWhiteSpace($text)){
                # O_EXCL publication creates the file before JSON encoding ends.
                # Retry incomplete JSON, but validate a parsed value immediately.
                try{$record=ConvertFrom-Json -InputObject $text -ErrorAction Stop;$parsed=$true}catch{}
            }
            if($parsed){
                if($record -isnot [pscustomobject]){throw 'Own fixture readiness must be a complete object'}
                $fields=@('pipe_name','role','pid','creation_filetime','broker_pid','broker_creation_filetime','wire_fixture_only','parentage_verified')
                $keys=@($record.PSObject.Properties.Name)
                if($keys.Count -ne $fields.Count){throw 'Own fixture readiness fields differ'}
                foreach($name in $fields){if($keys -cnotcontains $name){throw 'Own fixture readiness field name differs'}}
                foreach($name in @('role','pid','creation_filetime','broker_pid','broker_creation_filetime')){
                    if($record.$name -isnot [int] -and $record.$name -isnot [long]){throw 'Own fixture readiness requires literal integer identities'}
                }
                $suffix=if($Role -eq 1){'.health-v1'}else{'.runtime-health-v1'}
                $relatedPid=if($Role -eq 1){0}else{$Broker.pid};$relatedCreation=if($Role -eq 1){0}else{$Broker.creation_filetime}
                if($record.pid -ne $process.Id -or $record.role -ne $Role -or $record.creation_filetime -le 0 -or
                    $record.broker_pid -ne $relatedPid -or $record.broker_creation_filetime -ne $relatedCreation -or
                    $record.pipe_name -isnot [string] -or $record.pipe_name -cne ($base+$suffix) -or
                    $record.wire_fixture_only -isnot [bool] -or -not $record.wire_fixture_only -or
                    $record.parentage_verified -isnot [bool] -or $record.parentage_verified){throw 'Own fixture identity differs'}
                return $record
            }
        }
        Start-Sleep -Milliseconds 20
    }
}
try{
    if(-not $env:GOCACHE){$env:GOCACHE=Join-Path $repo '.tmp/go-health-cache'}
    if(-not $env:GOTMPDIR){$env:GOTMPDIR=Join-Path $repo '.tmp/go-health-tmp'}
    [void][IO.Directory]::CreateDirectory($env:GOCACHE);[void][IO.Directory]::CreateDirectory($env:GOTMPDIR)
    Push-Location (Join-Path $repo 'go-backend')
    try {& go test -c -o $exe ./input_methods/yime/yimebroker; if($LASTEXITCODE -ne 0){throw 'Compile own Go test helper failed'}}finally{Pop-Location}
    $result.binary=File-Reference $exe
    $namespace='Yime.HealthInterop_'+[guid]::NewGuid().ToString('N')
    $types=@(Add-Type -TypeDefinition ([IO.File]::ReadAllText($clientPath).Replace('namespace Yime.MaintenanceHealth {',('namespace '+$namespace+' {'))) -PassThru)
    $client=@($types|Where-Object FullName -CEQ ($namespace+'.Client'))[0]
    $broker=Start-Fixture 1
    $runtime=Start-Fixture 2 $broker
    for($i=0;$i -lt 2;$i++){
        $replies=@($client::ProbePair($base,[int]$runtime.pid,[long]$runtime.creation_filetime,[int]$broker.pid,[long]$broker.creation_filetime))
        if($replies.Count -ne 2 -or $client::OutstandingIo -ne 0){throw 'Incomplete wire exchange or outstanding IO'}
        foreach($reply in $replies){if(-not $reply.HealthServiceResponsive -or -not $reply.NonceVerified -or -not $reply.PipeServerIdentityBound){throw 'Unbound Go health response'}}
        $result.round_trips+=,[ordered]@{round=$i+1;roles=@($replies|ForEach-Object Role);nonce_verified=$true;os_pid_and_creation_verified=$true;outstanding_io=$client::OutstandingIo}
    }
    if((File-Reference $clientPath).sha256 -cne $clientSource.sha256 -or (File-Reference $PSCommandPath).sha256 -cne $testSource.sha256){throw 'Client or interop test source changed'}
    foreach($source in $sources){if((File-Reference $source.path).sha256 -cne $source.sha256){throw 'Go source changed during interop'}}
    $result.passed=$true
}catch{$result.error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
finally{
    try{
        foreach($item in $children){
            $problems=[Collections.Generic.List[string]]::new();$exited=$false;$captured=@{stdout='';stderr=''}
            try{
                # Only this test's original helper process may be terminated.
                # Preserve the timeout, but first drain both redirected readers.
                try{
                    if(-not $item.process.WaitForExit(35000)){
                        $problems.Add('Owned helper exceeded its bounded lifetime')
                        $item.process.Kill()
                        if(-not $item.process.WaitForExit(5000)){throw 'Owned helper did not exit after termination'}
                    }
                    $exited=$true
                }catch{$problems.Add($_.Exception.Message)}
                finally{
                    foreach($name in @('stdout','stderr')){
                        $task=$item.$name;$reader=$item.($name+'_reader')
                        try{
                            # Closing the owned reader cancels an outstanding
                            # read if process termination itself failed. Drain
                            # the original task even when normal setup failed.
                            if(-not $exited -and $null -ne $reader){try{$reader.Dispose()}catch{$problems.Add($name+' close: '+$_.Exception.Message)}}
                            if($null -ne $task){$captured[$name]=$task.GetAwaiter().GetResult()}
                        }catch{$problems.Add($name+': '+$_.Exception.Message)}
                        finally{if($null -ne $reader){try{$reader.Dispose()}catch{$problems.Add($name+' dispose: '+$_.Exception.Message)}}}
                    }
                }
                $exitCode=if($exited){$item.process.ExitCode}else{$null}
                $readyReference=if(Test-Path -LiteralPath $item.ready){File-Reference $item.ready}else{$null}
                $result.children+=,[ordered]@{pid=$item.process.Id;role=$item.role;exit_code=$exitCode;ready_file=$readyReference;stdout=$captured.stdout;stderr=$captured.stderr}
                if($exited -and $exitCode -ne 0){$problems.Add('Owned helper failed')}
            }catch{$problems.Add($_.Exception.Message)}
            finally{
                try{$item.process.Dispose()}catch{$problems.Add('process dispose: '+$_.Exception.Message)}
                if($problems.Count -gt 0){$result.passed=$false;$result.cleanup_error+=($problems -join '; ')+'; '}
            }
        }
        $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $output -Encoding UTF8
    }finally{
        foreach($name in @('GOCACHE','GOTMPDIR')){
            $prior=$previousEnvironment[$name]
            if($prior.present){[Environment]::SetEnvironmentVariable($name,$prior.value,'Process')}
            else{Remove-Item -LiteralPath ('Env:\'+$name) -ErrorAction SilentlyContinue}
        }
    }
}
if(-not $result.passed){throw ('Native Go health interop failed: '+$result.error+' '+$result.cleanup_error)}
Write-Output ('PASS: two Go fixture roles and two fresh pair exchanges; '+$output)
