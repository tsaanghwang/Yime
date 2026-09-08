[CmdletBinding()]param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($repo+'\.tmp\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Fresh repository .tmp result required'}
$parent=Split-Path -Parent $output;$cursor=$parent
while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Indirect test directory'};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory($parent)|Out-Null
$fixture=Join-Path $parent ('child-owned-fixture-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$modulePath=Join-Path $PSScriptRoot 'native-maintenance-child.psm1'
$module=Import-Module $modulePath -Force -PassThru
$checks=New-Object 'Collections.Generic.List[string]'
$children=New-Object 'Collections.Generic.List[object]'
$cmd=Join-Path $env:SystemRoot 'System32\cmd.exe'
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Body,[string]$Name){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Check $caught $Name}
function Start-OwnedChild([string]$Arguments,[string]$Image=$cmd){
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Image;$info.Arguments=$Arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    if(-not $process.Start()){throw 'Owned fixture did not start'}
    $null=$process.SafeHandle;$children.Add($process);return $process
}
function Stop-OwnedChildren {
    foreach($child in $children){
        try{
            if(-not $child.HasExited){try{$child.StandardInput.WriteLine('finish');$child.StandardInput.Close()}catch{};if(-not $child.WaitForExit(10000)){throw 'Owned fixture failed to exit; no product process is terminated'}}
        }catch [InvalidOperationException] {} finally{$child.Dispose()}
    }
    $children.Clear()
}
try {
    $commands=@(Get-Command -Module $module.Name)
    Check ($commands.Count -eq 3 -and @($commands|Where-Object {$_.Name -match 'Start|Stop|Kill'}).Count -eq 0) 'public interface only opens waits and closes borrowed child leases'
    foreach($command in $commands){Check (@($command.Parameters.Keys|Where-Object {$_ -in @('Provider','ScriptBlock','ProcessId','Pid','Command','FilePath','Arguments')}).Count -eq 0) ('no arbitrary provider PID reopen or launch surface '+$command.Name)}
    $text=[IO.File]::ReadAllText($modulePath)
    Check (-not $text.Contains('OpenProcess(') -and -not $text.Contains('GetProcessById(') -and -not $text.Contains('.Kill(') -and -not $text.Contains('ReadToEnd(')) 'adapter has no PID reopen termination or stdio EOF implementation'
    foreach($code in @(0,1,20,21,22,23,24,25,26,86)){
        $child=Start-OwnedChild ('/d /c "set /p fixture= & exit '+$code+'"')
        $lease=Open-YimeCoreNativeMaintenanceChild -Process $child -ExpectedImagePath $cmd
        try {
            $child.StandardInput.WriteLine('finish');$child.StandardInput.Close()
            $facts=Wait-YimeCoreNativeMaintenanceChild -Lease $lease -TimeoutMilliseconds 5000
            Check ($facts.exit_observed -and $facts.actual_exit_os_observed -and $facts.exit_code -eq $code -and -not $facts.timed_out) ('real original child exit '+$code)
            Check ($facts.pid -eq $child.Id -and $facts.creation_filetime -eq $child.StartTime.ToUniversalTime().ToFileTimeUtc() -and $facts.image_path -ieq $cmd) ('real held-handle identity '+$code)
            Check (-not $facts.may_advance_maintenance -and -not $facts.loaded_script_authenticated -and -not $facts.target_sid_authenticated -and -not $facts.registration_restore_verified -and -not $facts.local_product_ready -and -not $facts.public_release_ready -and -not $facts.L6_sealed) ('exit alone grants no maintenance or readiness '+$code)
        }finally{Close-YimeCoreNativeMaintenanceChild $lease}
    }
    $child=Start-OwnedChild '/d /c exit 20';$null=$child.WaitForExit(5000)
    $lease=$null
    try{$lease=Open-YimeCoreNativeMaintenanceChild $child $cmd;Check (Wait-YimeCoreNativeMaintenanceChild $lease 0).exit_observed 'quick exit accepted only with actual native image evidence'}
    catch{Check ($_.Exception.ToString().Contains('Native child image unavailable before a bound exit observation.')) 'quick exit missing native image evidence is rejected without StartInfo fallback'}
    finally{if($null -ne $lease){Close-YimeCoreNativeMaintenanceChild $lease}}
    # Explicitly cover the orchestration-facing Start-Process -PassThru shape.
    $passRelease=Join-Path $fixture 'passthru-release'
    $passScript='$end=[DateTime]::UtcNow.AddSeconds(5); while(-not [IO.File]::Exists('''+$passRelease+''') -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 25}; exit 21'
    $passEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($passScript))
    $child=Start-Process -FilePath $powershell -ArgumentList ('-NoProfile -NonInteractive -EncodedCommand '+$passEncoded) -WindowStyle Hidden -PassThru
    $children.Add($child);$lease=Open-YimeCoreNativeMaintenanceChild $child $powershell
    try{[IO.File]::WriteAllText($passRelease,'finish');Check ((Wait-YimeCoreNativeMaintenanceChild $lease 5000).exit_code -eq 21) 'actual Start-Process PassThru object accepted'}finally{Close-YimeCoreNativeMaintenanceChild $lease}
    $child=Start-OwnedChild '/d /c set /p fixture='
    $lease=Open-YimeCoreNativeMaintenanceChild $child $cmd
    try {
        $facts=Wait-YimeCoreNativeMaintenanceChild $lease 25
        Check ($facts.timed_out -and -not $facts.exit_observed -and -not $facts.actual_exit_os_observed -and $null -eq $facts.exit_code -and -not $facts.may_consume_outcome -and -not $facts.may_advance_maintenance -and -not $facts.termination_requested) 'timeout never kills or permits next maintenance step'
        Check (-not $child.HasExited -and $facts.liveness -ceq 'not_signaled_at_wait_timeout' -and -not $facts.current_liveness_guaranteed) 'timeout records only bounded wait liveness'
        $facts.exit_observed=$true;$facts.exit_code=20;$lease.initial.pid=99;$lease.initial.actual_exit_os_observed=$true
        $again=Wait-YimeCoreNativeMaintenanceChild $lease 0
        Check (-not $again.exit_observed -and $again.pid -eq $child.Id) 'caller evidence edits cannot fabricate OS exit or identity'
        $clone=$lease|ConvertTo-Json -Depth 6|ConvertFrom-Json
        Reject {Wait-YimeCoreNativeMaintenanceChild $clone 0} 'serialized child lease cannot wait'
        Reject {Close-YimeCoreNativeMaintenanceChild $clone} 'serialized child lease cannot close'
        Reject {Open-YimeCoreNativeMaintenanceChild $child $cmd} 'duplicate live lease for same Process rejected'
        foreach($timeout in @(-1,60001,'1',$true,@(1))){Reject {Wait-YimeCoreNativeMaintenanceChild $lease $timeout} ('reject nonliteral or unbounded timeout '+$checks.Count)}
        $id=$lease.lease_id;$lease.lease_id='0'*32
        try{Reject {Wait-YimeCoreNativeMaintenanceChild $lease 0} 'tampered lease identifier rejected'}finally{$lease.lease_id=$id}
        $child.StandardInput.WriteLine('finish');$child.StandardInput.Close()
        Check (Wait-YimeCoreNativeMaintenanceChild $lease 5000).exit_observed 'same handle can observe exit after earlier timeout'
    }finally{Close-YimeCoreNativeMaintenanceChild $lease}
    Close-YimeCoreNativeMaintenanceChild $lease
    Reject {Wait-YimeCoreNativeMaintenanceChild $lease 0} 'closed lease cannot wait'
    Reject {Close-YimeCoreNativeMaintenanceChild $clone} 'cloned closed lease cannot claim idempotent cleanup'
    foreach($fake in @([pscustomobject]@{Id=123;Handle=1},[Diagnostics.Process]::new(),'123',@(123))){Reject {Open-YimeCoreNativeMaintenanceChild $fake $cmd} ('reject invalid original Process '+$checks.Count)}
    $child=Start-OwnedChild '/d /c exit 20';$null=$child.WaitForExit(5000)
    Reject {Open-YimeCoreNativeMaintenanceChild $child 'C:\Wrong\cmd.exe'} 'native image cannot be supplied by caller fiction'
    foreach($image in @('cmd.exe','C:\Windows\..\Windows\System32\cmd.exe','C:\Windows\System32\cmd.exe:stream','\\host\share\cmd.exe',@($cmd))){Reject {Open-YimeCoreNativeMaintenanceChild $child $image} ('reject ambiguous expected child path '+$checks.Count)}
    $child.Dispose();Reject {Open-YimeCoreNativeMaintenanceChild $child $cmd} 'disposed Process rejected at acquisition'
    $child=Start-OwnedChild '/d /c "set /p fixture= & exit 20"';$lease=Open-YimeCoreNativeMaintenanceChild $child $cmd
    $child.StandardInput.WriteLine('finish');$child.StandardInput.Close();$null=$child.WaitForExit(5000);$child.Dispose()
    try{Reject {Wait-YimeCoreNativeMaintenanceChild $lease 0} 'external Process disposal invalidates live lease'}finally{Close-YimeCoreNativeMaintenanceChild $lease}
    $child=Start-OwnedChild '/d /c "set /p fixture= & exit 20"';$lease=Open-YimeCoreNativeMaintenanceChild $child $cmd
    $child.StandardInput.WriteLine('finish');$child.StandardInput.Close();$null=$child.WaitForExit(5000);$child.StartInfo.Arguments='/d /c exit 21';$null=$child.Start()
    try{Reject {Wait-YimeCoreNativeMaintenanceChild $lease 5000} 'reusing original Process for another child cannot replace retained target'}finally{Close-YimeCoreNativeMaintenanceChild $lease}
    # The child owns this bounded resident grandchild; pipe EOF is deliberately
    # later than the child exit. We never call stdout/stderr ReadToEnd.
    $signal=Join-Path $fixture 'grandchild-started.json';$release=Join-Path $fixture 'grandchild-release'
    $grandScript='$ErrorActionPreference="Stop"; [IO.File]::WriteAllText('''+$signal+''',([string]$PID)); $end=[DateTime]::UtcNow.AddSeconds(10); while(-not [IO.File]::Exists('''+$release+''') -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 25}; exit 0'
    $grandEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($grandScript))
    $parentScript='$ErrorActionPreference="Stop"; $info=New-Object Diagnostics.ProcessStartInfo; $info.FileName='''+$powershell+'''; $info.Arguments=''-NoProfile -NonInteractive -EncodedCommand '+$grandEncoded+'''; $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $p=[Diagnostics.Process]::Start($info); $end=[DateTime]::UtcNow.AddSeconds(5); while(-not [IO.File]::Exists('''+$signal+''') -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 25}; if(-not [IO.File]::Exists('''+$signal+''')){exit 99}; exit 20'
    $parentEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($parentScript))
    $child=Start-OwnedChild ('-NoProfile -NonInteractive -EncodedCommand '+$parentEncoded) $powershell
    $lease=Open-YimeCoreNativeMaintenanceChild $child $powershell
    try{
        $watch=[Diagnostics.Stopwatch]::StartNew();$facts=Wait-YimeCoreNativeMaintenanceChild $lease 7000;$watch.Stop()
        Check ($facts.exit_observed -and $facts.exit_code -eq 20 -and -not $facts.descendants_waited -and -not $facts.stdio_eof_waited -and $watch.ElapsedMilliseconds -lt 7000) 'child wait returns without resident descendant or stdio EOF'
        $grandId=[int][IO.File]::ReadAllText($signal)
        $grand=[Diagnostics.Process]::GetProcessById($grandId) # Only own signaled fixture PID, outside adapter.
        try{Check (-not $grand.HasExited) 'owned descendant is still live after controller child observation'}finally{[IO.File]::WriteAllText($release,'finish');$null=$grand.WaitForExit(5000);$grand.Dispose()}
    }finally{Close-YimeCoreNativeMaintenanceChild $lease;[IO.File]::WriteAllText($release,'finish')}
    $child=Start-OwnedChild '/d /c set /p fixture=';$lease=Open-YimeCoreNativeMaintenanceChild $child $cmd
    $native=& $module {param($id)$script:ChildLeases[$id].native} $lease.lease_id
    Close-YimeCoreNativeMaintenanceChild $lease
    Reject {$native.Initial()} 'close releases retained native lease handle reference'
    Check (-not $child.HasExited) 'close neither terminates child nor disposes caller Process'
    $lease=Open-YimeCoreNativeMaintenanceChild $child $cmd
    $native=& $module {param($id)$script:ChildLeases[$id].native} $lease.lease_id
    Remove-Module $module
    Reject {$native.Initial()} 'module removal releases remaining child lease references'
    Check (-not $child.HasExited) 'module removal does not terminate caller child'
    Stop-OwnedChildren
    $result=[ordered]@{schema_version='yimecore-native-maintenance-child-tests-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();powershell_version=$PSVersionTable.PSVersion.ToString();
        module_sha256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant();
        owned_test_child_processes_only=$true;product_or_installer_executed=$false;product_process_enumeration=$false;product_registry_accessed=$false;installed_local12_read_or_changed=$false;user_state_read=$false;L6_sealed=$false}
    [IO.File]::WriteAllText($output,(($result|ConvertTo-Json -Depth 8).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
    Write-Output ('PASS: native maintenance child '+$checks.Count+' checks; owned child fixtures only; '+$output)
}finally{Stop-OwnedChildren}
