# Read-only protection for the current YimeCore peer. Never stops, repairs or
# restores the peer. An unreadable or changing protected surface fails closed.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')

function Get-PeerRegistryTree([string]$Hive,[string]$View,[string]$Key,[int]$Depth=0) {
    if($Depth -gt 32){throw 'Peer registry tree exceeds observation bound.'}
    $shape=Get-YimePimeSystemRegistryKeyShape $Hive $View $Key
    $values=@();$children=@()
    if($shape.exists){
        foreach($name in @($shape.value_names|Where-Object{$null -ne $_}|Sort-Object -CaseSensitive)){
            $record=Get-YimePimeSystemRegistryValueRecord ([pscustomobject]@{id='peer';hive=$Hive;view=$View;key=$Key;name=[string]$name})
            # The current product uses strings and DWORDs on these surfaces.
            # Unsupported kinds are rejected, never represented by a null hash.
            if(-not $record.exists -or $record.value_kind -cnotin @('String','DWord')){throw 'Peer registry changed or has an unsupported value kind.'}
            $values+=,$record
        }
        foreach($child in @($shape.subkey_names|Where-Object{$null -ne $_}|Sort-Object -CaseSensitive)){
            $children+=,(Get-PeerRegistryTree $Hive $View ($Key+'\'+$child) ($Depth+1))
        }
    }
    [pscustomobject][ordered]@{hive=$Hive;view=$View;key=$Key;exists=[bool]$shape.exists;values=$values;children=$children}
}
function Get-PeerFileTree([string]$Root,[switch]$State) {
    Assert-YimePimePlainPath $Root | Out-Null
    if(-not (Test-Path -LiteralPath $Root)){return [pscustomobject][ordered]@{root=$Root;exists=$false;directories=@();files=@()}}
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){throw 'Peer root is not a directory.'}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root)
    $directories=@();$files=@()
    while($pending.Count){
        $directory=$pending.Pop()
        foreach($entry in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop|Sort-Object Name -CaseSensitive)){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Peer tree contains a reparse point.'}
            $relative=$entry.FullName.Substring($Root.Length+1).Replace('\','/')
            # Operational logs/status are live outputs, not settings or learning.
            # All other files, including unknown future settings, are protected.
            if($State -and $relative -cin @('logs','runtime','runtime-status.json')){continue}
            if($entry.PSIsContainer){$directories+=,$relative;$pending.Push($entry.FullName);continue}
            $before=$entry.LastWriteTimeUtc
            $stream=[IO.File]::Open($entry.FullName,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try{
                $length=$stream.Length
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                if($stream.Length -ne $length -or (Get-Item -LiteralPath $entry.FullName -Force).LastWriteTimeUtc -ne $before){throw 'Peer file changed during observation.'}
                $files+=,[pscustomobject][ordered]@{path=$relative;bytes=[long]$length;sha256=$hash}
            }finally{$stream.Dispose()}
            if($files.Count -gt 50000){throw 'Peer file inventory exceeds bound.'}
        }
    }
    [pscustomobject][ordered]@{root=$Root;exists=$true;directories=@($directories|Sort-Object -CaseSensitive);files=@($files|Sort-Object path -CaseSensitive)}
}
function Get-PeerProcesses([string]$Root,[string]$Sid) {
    $rows=@()
    foreach($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)){
        if($process.Name -notin @('YimeCoreTrialRuntime.exe','YimeBroker.exe')){continue}
        if(-not $process.ExecutablePath){throw 'Peer process image is unreadable.'}
        if(-not $process.ExecutablePath.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Peer process is outside the bound installation.'}
        $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
        if($owner.ReturnValue -ne 0 -or $owner.Sid -cne $Sid){throw 'Peer process is not owned by the initiating SID.'}
        $rows+=,[pscustomobject][ordered]@{pid=[int]$process.ProcessId;image=[string]$process.ExecutablePath;sid=[string]$owner.Sid;creation_utc=$process.CreationDate.ToUniversalTime().ToString('o')}
    }
    return ,@($rows|Sort-Object pid)
}
function Get-RimePimePeerProtectionSnapshot($Boundary,[string]$Sid) {
    if($Sid -cnotmatch '^S-1-5-21-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*$'){throw 'Peer observation requires explicit initiating SID.'}
    $clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'
    $legacy='{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
    $registry=@();$runs=@();$comPaths=@()
    foreach($view in @('Registry32','Registry64')){
        foreach($hive in @('LocalMachine','Users')){
            $prefix=if($hive -ceq 'Users'){$Sid+'\'}else{''}
            foreach($relative in @("SOFTWARE\Classes\CLSID\$legacy","SOFTWARE\Microsoft\CTF\TIP\$legacy")){
                if(Test-YimePimeSystemRegistryKeyExists $hive $view ($prefix+$relative)){throw 'Historical YimeCore registration is not an admitted current peer.'}
            }
            foreach($relative in @("SOFTWARE\Classes\CLSID\$clsid","SOFTWARE\Microsoft\CTF\TIP\$clsid",'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial')){
                $registry+=,(Get-PeerRegistryTree $hive $view ($prefix+$relative))
            }
            $run=Get-YimePimeSystemRegistryValueRecord ([pscustomobject]@{id='peer-run';hive=$hive;view=$view;key=($prefix+'SOFTWARE\Microsoft\Windows\CurrentVersion\Run');name='YimeCoreExperimentalTrial'})
            if($run.exists -and $run.value_kind -cne 'String'){throw 'Peer Run has unsupported kind.'}
            $runs+=,$run
            $com=Get-YimePimeSystemRegistryValueRecord ([pscustomobject]@{id='peer-com';hive=$hive;view=$view;key=($prefix+"SOFTWARE\Classes\CLSID\$clsid\InprocServer32");name=''})
            if($com.exists){
                if($hive -cne 'LocalMachine' -or $com.value_kind -cne 'String' -or
                    $com.value -ine (Join-Path $Boundary.peer_install_root $(if($view -ceq 'Registry32'){'x86\YimeTextServiceExperiment.dll'}else{'x64\YimeTextServiceExperiment.dll'}))){throw 'Peer COM does not match the bound current installation.'}
                $comPaths+=,$com.value
            }
        }
    }
    $install=Get-PeerFileTree $Boundary.peer_install_root
    $present=(@($registry|Where-Object exists).Count -gt 0 -or @($runs|Where-Object exists).Count -gt 0)
    if($present -ne $install.exists -or ($present -and $comPaths.Count -eq 0)){throw 'Peer registration and bound payload presence disagree.'}
    if($present){
        $configPath=Join-Path $Boundary.peer_state_root 'runtime-config.json'
        Assert-YimePimePlainPath $configPath | Out-Null
        $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
        if($config.install_root -ine $Boundary.peer_install_root -or $config.state_root -ine $Boundary.peer_state_root){throw 'Peer runtime configuration does not bind the observed roots.'}
    }
    # Known installation locations cannot be hidden with invented boundary roots.
    foreach($fixed in @((Join-Path $env:ProgramFiles 'YimeCore Experimental Trial'),(Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))){
        if((Test-Path -LiteralPath $fixed) -and $fixed -ine $Boundary.peer_install_root -and
            -not $Boundary.peer_install_root.StartsWith($fixed+'\',[StringComparison]::OrdinalIgnoreCase) -and $fixed -ine $Boundary.peer_state_root){throw 'Unbound fixed YimeCore root exists.'}
    }
    [pscustomobject][ordered]@{schema_version='yime-rime-pime-peer-protection-v1';sid=$Sid;peer_present=$present;
        registry=$registry;run=$runs;payload=$install;state=(Get-PeerFileTree $Boundary.peer_state_root -State);
        recovery=(Get-PeerFileTree $Boundary.peer_recovery_root);processes=(Get-PeerProcesses $Boundary.peer_install_root $Sid)}
}
function ConvertTo-PeerComparisonJson($Snapshot) {
    # Keep raw snapshots intact. This exact file is append-only diagnostic output
    # from RecordLanguageBarHostResult, not settings or learning. Its presence,
    # path and all other fields remain protected; only content metadata is live.
    $copy=$Snapshot|ConvertTo-Json -Depth 90 -Compress|ConvertFrom-Json
    if($copy.PSObject.Properties['state'] -and $copy.state.PSObject.Properties['files']){
        $logs=@($copy.state.files|Where-Object {$_.path -ceq 'evidence/language-bar-host.log'})
        if($logs.Count -gt 1){throw 'Duplicate language-bar diagnostic entry.'}
        foreach($log in $logs){$log.bytes=0;$log.sha256='runtime-diagnostic-content'}
    }
    return ($copy|ConvertTo-Json -Depth 90 -Compress)
}
function Assert-RimePimePeerProtectionUnchanged($Before,$After) {
    if((ConvertTo-PeerComparisonJson $Before) -cne (ConvertTo-PeerComparisonJson $After)){
        throw 'Protected YimeCore peer changed; preserve both observations and do not report completion.'
    }
}
Export-ModuleMember -Function Get-RimePimePeerProtectionSnapshot,Assert-RimePimePeerProtectionUnchanged
