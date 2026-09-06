[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-directed-stop-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-directed-stop-* fixture root.'
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Directed-stop evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value){throw $Message} }
function Must-Reject([scriptblock]$Body) {
    $rejected=$false
    try { & $Body | Out-Null } catch { $rejected=$true }
    Assert-True $rejected 'Expected fail-closed rejection.'
}

$ownershipPath=Join-Path $PSScriptRoot 'rime-pime-ownership.ps1'
$contractPath=Join-Path $PSScriptRoot 'rime-pime-directed-stop-contract.ps1'
$ownership=Get-Content -LiteralPath $ownershipPath -Raw
$launcherMainPath=Join-Path $repo 'PIMELauncher\src\main.rs'
$launcherMaintenancePath=Join-Path $repo 'PIMELauncher\src\maintenance.rs'
$backendManagerPath=Join-Path $repo 'PIMELauncher\src\backend_manager.rs'
$goServerPath=Join-Path $repo 'go-backend\server.go'
$goServerShutdownTestPath=Join-Path $repo 'go-backend\server_shutdown_test.go'
$goYimePath=Join-Path $repo 'go-backend\input_methods\yime\yime.go'
$goNativePath=Join-Path $repo 'go-backend\input_methods\yime\native_cgo.go'
$goLibrimePath=Join-Path $repo 'go-backend\input_methods\yime\librime.go'
$goRimeRuntimeTestPath=Join-Path $repo 'go-backend\input_methods\yime\rime_runtime_test.go'
$installerPath=Join-Path $repo 'installer\installer.nsi'
$launcherMain=Get-Content -LiteralPath $launcherMainPath -Raw
$launcherMaintenance=Get-Content -LiteralPath $launcherMaintenancePath -Raw
$backendManager=Get-Content -LiteralPath $backendManagerPath -Raw
$goServer=Get-Content -LiteralPath $goServerPath -Raw
$goServerShutdownTest=Get-Content -LiteralPath $goServerShutdownTestPath -Raw
$goYime=Get-Content -LiteralPath $goYimePath -Raw
$goNative=Get-Content -LiteralPath $goNativePath -Raw
$goLibrime=Get-Content -LiteralPath $goLibrimePath -Raw
$goRimeRuntimeTest=Get-Content -LiteralPath $goRimeRuntimeTestPath -Raw
$installer=Get-Content -LiteralPath $installerPath -Raw
$contract=$null
if(Test-Path -LiteralPath $contractPath -PathType Leaf){$contract=Get-Content -LiteralPath $contractPath -Raw}

Check 'directed-contract-source-exists' {
    Assert-True ($null -ne $contract) 'Directed stop contract source is missing.'
}
if($null -ne $contract) {
    Check 'directed-contract-is-definitions-only-and-never-force-stops' {
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($contract,[ref]$tokens,[ref]$errors)
        Assert-True ($errors.Count -eq 0) 'Directed stop contract does not parse.'
        $topCommands=@($ast.EndBlock.Statements | Where-Object {$_ -isnot [Management.Automation.Language.FunctionDefinitionAst]})
        Assert-True ($topCommands.Count -eq 0) 'Importing the directed stop contract would execute an action.'
        Assert-True ($contract -notmatch '(?i)\bStop-Process\b|\btaskkill(?:\.exe)?\b|PIMELauncher2_QuitEvent|/quit(?:\s|\x27|\x22)') 'Force/name/global quit primitive appears in directed contract.'
    }
    Check 'directed-contract-binds-root-sid-pid-start-observations-and-ack' {
        foreach($fragment in @('install_root','target_user_sid','launcher_pid','launcher_start_utc','launcher_start_filetime_utc',
                'worker_pid','worker_start_utc','worker_start_filetime_utc','observation_sha256','request_id',
                'watchdog_restart_suppressed','accepted','yime-rime-directed-stop-request-v1','yime-rime-directed-stop-ack-v1')) {
            Assert-True $contract.Contains($fragment) "Missing directed protocol field: $fragment"
        }
    }
    Check 'legacy-shared-quit-remains-explicitly-unusable' {
        Assert-True ($ownership -match 'shared PIMELauncher2_QuitEvent') 'Legacy shared-event warning was lost.'
        Assert-True ($contract -notmatch 'signal_quit_event|wait_for_quit_event|SetEvent') 'New contract reuses the shared event.'
    }
    Check 'launcher-worker-pipe-ack-and-watchdog-restart-suppression-are-wired' {
        Assert-True ($launcherMaintenance -match 'PIME\\Maintenance' -and $launcherMaintenance -match 'validate_request' -and
            $launcherMaintenance -match 'watchdog_restart_suppressed') 'Worker maintenance pipe/ACK validation is not wired.'
        Assert-True ($launcherMaintenance -notmatch 'PIMELauncher2_QuitEvent|SetEvent|TerminateProcess') 'Directed worker source reuses a broadcast/force primitive.'
        Assert-True ($launcherMain -match 'DIRECTED_MAINTENANCE_EXIT_CODE' -and $launcherMain -match 'restart is suppressed' -and
            $launcherMain -match '/watchdog-start-filetime-utc') 'Watchdog does not bind the worker and suppress restart after directed exit.'
        Assert-True ($backendManager -match 'shutdown_gracefully' -and $backendManager -match 'closing stdin without force' -and
            $backendManager -match 'MAINTENANCE_BACKEND_EXIT_TIMEOUT' -and $backendManager -match 'std::mem::forget\(child_process\)' -and
            $backendManager -match '!status\.success\(\)' -and $backendManager -match 'exited unsuccessfully during EOF maintenance shutdown') 'Backend EOF shutdown is missing bounded non-force/nonzero failure handling.'
    }
    Check 'installer-ships-the-independent-directed-contract' {
        Assert-True ($installer -match 'File /oname=\$PLUGINSDIR\\rime-pime-directed-stop-contract\.ps1') 'Installer maintenance helper set omits the directed contract.'
        Assert-True ($ownership -match 'Invoke-YimePimeDirectedStop') 'Owned-process entry is not connected to directed stop.'
    }
    Check 'go-backend-eof-closes-owned-rime-sessions-and-propagates-failure' {
        Assert-True ($goServer -match 'runErr\s*=\s*errors\.Join\(runErr,\s*s\.closeAllClients\(\)\)' -and
            $goServer -match 'type fallibleTextServiceCloser interface' -and $goServer -match 'CloseWithError\(\) error') 'Go stdin EOF does not close every tracked service with error propagation.'
        Assert-True ($goYime -match 'func \(ime \*IME\) CloseWithError\(\) error' -and
            $goYime -match '!ime\.destroySession\(nil\)') 'IME close does not reject a failed native session destroy.'
        Assert-True ($goNative -match '!EndSession\(b\.sessionID\)' -and
            $goLibrime -match 'func EndSession\(sessionId RimeSessionId\) bool' -and
            $goLibrime -match 'return boolResult\(r1\)') 'Native Rime destroy result is not checked.'
        foreach($testName in @('TestServerRunEOFClosesEveryTrackedService','TestServerRunEOFReportsCloseFailureAfterTryingEveryService')) {
            Assert-True $goServerShutdownTest.Contains($testName) "Missing Go EOF regression: $testName"
        }
        Assert-True $goRimeRuntimeTest.Contains('TestRealRimeEndSessionPersistsLearningAcrossRestart') 'Missing isolated real-Rime persistence regression.'
    }
}

if($null -ne $contract) {
    . $ownershipPath
    . $contractPath
    $fixtureSid='S-1-5-21-100-200-300-1001'
    function Get-YimePimeCurrentSid { return $fixtureSid }
    function New-FixtureProduct([string]$Name,[string]$Guid='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}') {
        $root=Join-Path $output $Name
        $markerDir=Join-Path $root 'go-backend\input_methods\yime'
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $markerDir 'ime.json'),('{"guid":"'+$Guid+'"}'))
        [IO.File]::WriteAllText((Join-Path $root 'PIMELauncher.exe'),'DP1 SYNTHETIC NONEXECUTABLE PAYLOAD')
        return $root
    }
    $targetRoot=New-FixtureProduct 'target-rime'
    $peerRoot=New-FixtureProduct 'peer-rime'
    $coreRoot=New-FixtureProduct 'YimeCore Experimental Trial' '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
    $script:records=@();$script:processes=@{};$script:transportCalls=@();$script:waited=@();$script:transportMode='success'
    function Add-FixtureProcess([int]$Id,[string]$Path,[string]$Sid=$fixtureSid,[datetime]$Start=([datetime]'2026-09-05T12:00:00Z'),
            [string]$CommandLine=('"'+$Path+'"'),[int]$ParentProcessId=50) {
        $record=[pscustomobject]@{Name=[IO.Path]::GetFileName($Path);ProcessId=$Id;ExecutablePath=$Path;CreationDate=$Start;OwnerSid=$Sid
            CommandLine=$CommandLine;ParentProcessId=$ParentProcessId}
        $process=[pscustomobject]@{Id=$Id;Path=$Path;StartTime=$Start;Handle=123;HasExited=$false}
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        $script:records+=,$record;$script:processes[$Id]=$process
    }
    function Reset-Fixture {
        $script:records=@();$script:processes=@{};$script:transportCalls=@();$script:waited=@();$script:transportMode='success'
    }
    function Get-CimInstance { param($ClassName,$ErrorAction)
        if($ClassName -ne 'Win32_Process'){throw 'Unexpected CIM class'}
        return $script:records
    }
    function Get-Process { param($Id,$ErrorAction)
        if(-not $script:processes.ContainsKey([int]$Id)){throw 'Unexpected real process lookup'}
        return $script:processes[[int]$Id]
    }
    function Invoke-CimMethod { param($InputObject,$MethodName,$ErrorAction)
        if($MethodName -ne 'GetOwnerSid'){throw 'Unexpected CIM method'}
        return [pscustomobject]@{ReturnValue=0;Sid=$InputObject.OwnerSid}
    }
    function Wait-Process { param($InputObject,$Timeout,$ErrorAction)
        if($Timeout -ne 15){throw 'Unexpected wait budget'}
        foreach($item in @($InputObject)){
            if(-not $item.HasExited){throw 'Synthetic process did not exit'}
            $script:waited+=,[int]$item.Id
        }
    }
    function New-Ack($Request) {
        return [pscustomobject][ordered]@{
            schema_version='yime-rime-directed-stop-ack-v1';request_id=$Request.request_id;accepted=$true
            install_root=$Request.install_root;target_user_sid=$Request.target_user_sid
            launcher_pid=$Request.launcher_pid;launcher_start_utc=$Request.launcher_start_utc
            launcher_start_filetime_utc=$Request.launcher_start_filetime_utc
            worker_pid=$Request.worker_pid;worker_start_utc=$Request.worker_start_utc
            worker_start_filetime_utc=$Request.worker_start_filetime_utc
            observation_sha256=$Request.observation_sha256;watchdog_restart_suppressed=$true
        }
    }
    function Invoke-YimePimeDirectedStopTransport { param($Request)
        $script:transportCalls+=,$Request
        $ack=New-Ack $Request
        switch($script:transportMode) {
            'bad-request-id' {$ack.request_id='00000000000000000000000000000000'}
            'bad-root' {$ack.install_root=$peerRoot}
            'bad-sid' {$ack.target_user_sid='S-1-5-21-100-200-300-2002'}
            'bad-pid' {$ack.launcher_pid=[int]$Request.launcher_pid+1}
            'bad-start' {$ack.launcher_start_utc='2026-09-05T12:00:01.0000000Z'}
            'bad-worker' {$ack.worker_pid=[int]$Request.worker_pid+1}
            'bad-observation' {$ack.observation_sha256=('0'*64)}
            'not-accepted' {$ack.accepted=$false}
            'restart-not-suppressed' {$ack.watchdog_restart_suppressed=$false}
            'no-exit' {return $ack}
        }
        if($script:transportMode -notmatch '^bad-|not-accepted|restart-not-suppressed') {
            $ids=@($Request.observed_processes | ForEach-Object {[int]$_.pid})
            foreach($id in $ids){$script:processes[$id].HasExited=$true}
            $script:records=@($script:records | Where-Object {$ids -notcontains [int]$_.ProcessId})
        }
        return $ack
    }

    Check 'exact-target-request-stops-only-mocked-owned-product' {
        Reset-Fixture
        Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe')
        Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker /watchdog-pid 101') 101
        Add-FixtureProcess 103 (Join-Path $targetRoot 'go-backend\server.exe') $fixtureSid ([datetime]'2026-09-05T12:00:02Z') ('"'+(Join-Path $targetRoot 'go-backend\server.exe')+'"') 102
        Add-FixtureProcess 201 (Join-Path $peerRoot 'PIMELauncher.exe')
        Add-FixtureProcess 202 (Join-Path $coreRoot 'bin\YimeBroker.exe')
        $result=Invoke-YimePimeDirectedStop -InstallRoot $targetRoot -TargetUserSid $fixtureSid
        Assert-True ($result.stopped_count -eq 3 -and $script:transportCalls.Count -eq 1) 'Target batch was not acknowledged once.'
        $request=$script:transportCalls[0]
        Assert-True ($request.install_root -ieq $targetRoot -and $request.target_user_sid -ceq $fixtureSid) 'Root/SID binding drifted.'
        Assert-True ($request.launcher_pid -eq 101 -and $request.launcher_start_utc -ceq '2026-09-05T12:00:00.0000000Z' -and
            $request.worker_pid -eq 102 -and $request.worker_start_utc -ceq '2026-09-05T12:00:01.0000000Z') 'Watchdog/worker PID/start binding drifted.'
        Assert-True ($request.request_id -cmatch '^[0-9a-f]{32}$' -and $request.observation_sha256 -cmatch '^[0-9a-f]{64}$') 'Nonce/observation binding invalid.'
        Assert-True (@($request.observed_processes).Count -eq 3 -and $script:waited.Count -eq 3) 'Full owned process set was not bound and waited.'
        Assert-True (@($script:records | Where-Object {$_.ProcessId -in @(201,202)}).Count -eq 2) 'Peer Rime or YimeCore fixture was affected.'
    }
    Check 'quiescent-target-does-not-call-transport' {
        Reset-Fixture;Add-FixtureProcess 201 (Join-Path $peerRoot 'PIMELauncher.exe')
        $result=Invoke-YimePimeDirectedStop -InstallRoot $targetRoot -TargetUserSid $fixtureSid
        Assert-True ($result.stopped_count -eq 0 -and $script:transportCalls.Count -eq 0 -and $script:waited.Count -eq 0) 'Quiescent target caused a transport or wait.'
    }
    Check 'actual-owned-process-entry-uses-one-directed-request-and-preserves-peer' {
        Reset-Fixture
        Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe')
        Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker /watchdog-pid 101') 101
        Add-FixtureProcess 103 (Join-Path $targetRoot 'go-backend\server.exe') $fixtureSid ([datetime]'2026-09-05T12:00:02Z') ('"'+(Join-Path $targetRoot 'go-backend\server.exe')+'"') 102
        Add-FixtureProcess 201 (Join-Path $peerRoot 'PIMELauncher.exe')
        Add-FixtureProcess 202 (Join-Path $coreRoot 'bin\YimeBroker.exe')
        $count=Stop-YimePimeOwnedProcesses -InstallRoots @($targetRoot) -TargetUserSid $fixtureSid
        Assert-True ($count -eq 3 -and $script:transportCalls.Count -eq 1) 'Maintenance entry did not issue exactly one bound request.'
        Assert-True (@($script:records | Where-Object {$_.ProcessId -in @(201,202)}).Count -eq 2) 'Maintenance entry affected the peer product fixture.'
    }
    Check 'wrong-sid-and-foreign-owned-process-reject-before-transport' {
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot 'S-1-5-21-100-200-300-2002'}
        Assert-True ($script:transportCalls.Count -eq 0) 'Wrong maintenance SID reached transport.'
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe') 'S-1-5-21-100-200-300-2002';Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Foreign-owned target reached transport.'
    }
    Check 'pid-start-image-rebinding-rejects-before-transport' {
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101;$script:processes[101].StartTime=$script:processes[101].StartTime.AddSeconds(1)
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101;$script:processes[101].Path=Join-Path $peerRoot 'PIMELauncher.exe'
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Rebound identity reached transport.'
    }
    Check 'unreadable-relevant-image-and-orphan-worker-fail-closed' {
        Reset-Fixture;$script:records=@([pscustomobject]@{Name='PIMELauncher.exe';ProcessId=101;ExecutablePath=$null})
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Reset-Fixture;Add-FixtureProcess 102 (Join-Path $targetRoot 'go-backend\server.exe')
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Unbound/orphan process reached transport.'
    }
    Check 'standalone-tool-or-unbound-server-rejects-before-transport' {
        Reset-Fixture
        Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe')
        Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101
        Add-FixtureProcess 104 (Join-Path $targetRoot 'go-backend\settings-tool.exe') $fixtureSid ([datetime]'2026-09-05T12:00:02Z') ('"'+(Join-Path $targetRoot 'go-backend\settings-tool.exe')+'"') 102
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Standalone tool caused a partial launcher stop.'
        Reset-Fixture
        Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe')
        Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101
        Add-FixtureProcess 103 (Join-Path $targetRoot 'go-backend\server.exe') $fixtureSid ([datetime]'2026-09-05T12:00:02Z') ('"'+(Join-Path $targetRoot 'go-backend\server.exe')+'"') 999
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Unbound server caused a partial launcher stop.'
    }
    Check 'duplicate-launcher-fails-before-transport' {
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 103 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 0) 'Ambiguous launchers reached transport.'
    }
    Check 'ack-must-echo-every-binding-and-suppress-restart' {
        foreach($mode in @('bad-request-id','bad-root','bad-sid','bad-pid','bad-start','bad-worker','bad-observation','not-accepted','restart-not-suppressed')) {
            Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101;$script:transportMode=$mode
            Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
            Assert-True ($script:waited.Count -eq 0 -and -not $script:processes[101].HasExited) "Invalid ACK $mode advanced to wait/exit."
        }
    }
    Check 'ack-without-exit-does-not-admit-maintenance' {
        Reset-Fixture;Add-FixtureProcess 101 (Join-Path $targetRoot 'PIMELauncher.exe');Add-FixtureProcess 102 (Join-Path $targetRoot 'PIMELauncher.exe') $fixtureSid ([datetime]'2026-09-05T12:00:01Z') ('"'+(Join-Path $targetRoot 'PIMELauncher.exe')+'" /worker') 101;$script:transportMode='no-exit'
        Must-Reject {Invoke-YimePimeDirectedStop $targetRoot $fixtureSid}
        Assert-True ($script:transportCalls.Count -eq 1) 'No-exit case did not exercise acknowledged transport.'
    }
}

$failed=@($checks | Where-Object {-not $_.passed})
$receipt=[ordered]@{
    schema_version='yime-rime-directed-stop-isolated-v1';passed=($failed.Count -eq 0)
    checks=$checks.ToArray();checks_count=$checks.Count;failed_count=$failed.Count
    synthetic_processes_only=$true;transport_mocked=$true;actual_launcher_executed=$false
    real_stop_process_or_taskkill_executed=$false;actual_install_or_uninstall_executed=$false
    registry_mutated=$false;production_or_user_data_read=$false;other_product_affected=$false
    live_transport_source_present=($null -ne $contract -and $contract -match 'NamedPipeClientStream')
    live_transport_executed=$false;ack_restart_suppression_is_acceptance_commitment=$true
    final_maintenance_admission_requires_bound_process_exit_recheck=$true;backend_eof_wait_seconds=8
    dp1_full_implementation_passed=$false;dp2_physical_acceptance_passed=$false
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
}
$receipt.source_sha256=[ordered]@{
    'tools/dual-product/rime-pime-ownership.ps1'=(Get-FileHash -LiteralPath $ownershipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'tools/dual-product/test-rime-pime-directed-stop.ps1'=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'PIMELauncher/src/main.rs'=(Get-FileHash -LiteralPath $launcherMainPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'PIMELauncher/src/maintenance.rs'=(Get-FileHash -LiteralPath $launcherMaintenancePath -Algorithm SHA256).Hash.ToLowerInvariant()
    'PIMELauncher/src/backend_manager.rs'=(Get-FileHash -LiteralPath $backendManagerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/server.go'=(Get-FileHash -LiteralPath $goServerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/server_shutdown_test.go'=(Get-FileHash -LiteralPath $goServerShutdownTestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/input_methods/yime/yime.go'=(Get-FileHash -LiteralPath $goYimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/input_methods/yime/native_cgo.go'=(Get-FileHash -LiteralPath $goNativePath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/input_methods/yime/librime.go'=(Get-FileHash -LiteralPath $goLibrimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    'go-backend/input_methods/yime/rime_runtime_test.go'=(Get-FileHash -LiteralPath $goRimeRuntimeTestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    'installer/installer.nsi'=(Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
if($null -ne $contract){$receipt.source_sha256['tools/dual-product/rime-pime-directed-stop-contract.ps1']=(Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
Write-Output "DP1 directed stop contract: $($checks.Count) checks; $($failed.Count) failed; evidence $output"
if($failed.Count){exit 1}
