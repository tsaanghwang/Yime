Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:HealthClientType=$null;$script:HealthClientHash=$null
$script:HealthNamespace='Yime.Health_'+[guid]::NewGuid().ToString('N')
# Keep the existing retained-observation registry; Force would invalidate leases.
$script:HealthProcessModule=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-processes.psm1') -Scope Local -PassThru

function Read-HealthProcesses($Observation) {
    & $script:HealthProcessModule {param($value)Assert-YimeCoreNativeMaintenanceProcessesCurrent -Observation $value} $Observation
}
function Assert-HealthPipe($Name) {
    if($Name -isnot [string] -or ($Name.Length-9+18) -gt 128 -or $Name -cnotmatch '\A\\\\\.\\pipe\\[A-Za-z0-9][A-Za-z0-9._-]*\z'){throw 'Explicit canonical bounded local broker pipe required'}
}
function Initialize-HealthClient {
    $path=Join-Path $PSScriptRoot 'native-maintenance-health-client.cs'
    $cursor=$path
    while($cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect health client source'};$cursor=Split-Path -Parent $cursor}
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($null -ne $script:HealthClientType){if($hash -cne $script:HealthClientHash){throw 'Loaded health client source changed'};return}
        $stream.Position=0;$reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try{$source=$reader.ReadToEnd()}finally{$reader.Dispose()}
        $types=@(Add-Type -TypeDefinition ($source.Replace('namespace Yime.MaintenanceHealth {',('namespace '+$script:HealthNamespace+' {'))) -PassThru)
        $script:HealthClientType=@($types|Where-Object {$_.FullName -ceq ($script:HealthNamespace+'.Client')})[0]
        $script:HealthClientHash=$hash
    }finally{$stream.Dispose()}
}
function Invoke-HealthPipePair($Pipe,$Runtime,$Broker) {
    $script:HealthClientType::ProbePair($Pipe,$Runtime.pid,$Runtime.creation_filetime,$Broker.pid,$Broker.creation_filetime)
}
function Assert-HealthProcessEvidence($Evidence) {
    if($null -eq $Evidence -or $Evidence.schema_version -isnot [string] -or $Evidence.schema_version -cne 'yimecore-native-maintenance-processes-v1' -or
        $Evidence.processes -isnot [array] -or $Evidence.processes.Count -ne 2){throw 'Complete current process evidence required'}
    foreach($name in @('native_handle_identity_observed','native_parent_relation_observed','public_image_hash_verified')){
        if($Evidence.$name -isnot [bool] -or -not $Evidence.$name){throw 'Native process binding is incomplete'}
    }
    $roles=@{}
    foreach($row in $Evidence.processes){
        if($row.role -isnot [string] -or $row.role -cnotin @('runtime','broker') -or $roles.ContainsKey($row.role) -or
            $row.pid -isnot [int] -or $row.pid -le 0 -or $row.creation_filetime -isnot [long] -or $row.creation_filetime -le 0 -or
            $row.parent_pid -isnot [int] -or $row.parent_pid -le 0){throw 'Malformed current process role identity'}
        $roles[$row.role]=$row
    }
    if($roles.runtime.pid -eq $roles.broker.pid -or $roles.broker.parent_pid -ne $roles.runtime.pid -or
        $roles.broker.creation_filetime -lt $roles.runtime.creation_filetime){throw 'Runtime and Broker relation differs'}
    return $roles
}
function Get-YimeCoreNativeMaintenanceHealth {
    [CmdletBinding()]param([Parameter(Mandatory)]$ProcessObservation,[Parameter(Mandatory)]$BrokerPipeName)
    Assert-HealthPipe $BrokerPipeName
    # Never use caller-editable ProcessObservation.evidence as native evidence.
    $before=Read-HealthProcesses $ProcessObservation;$roles=Assert-HealthProcessEvidence $before
    Initialize-HealthClient
    try{$replies=@(Invoke-HealthPipePair $BrokerPipeName $roles.runtime $roles.broker)}
    finally{$after=Read-HealthProcesses $ProcessObservation;$again=Assert-HealthProcessEvidence $after}
    foreach($role in @('runtime','broker')){
        foreach($name in @('pid','parent_pid','creation_filetime','image','sid','image_sha256','image_bytes','file_identity')){
            if($roles[$role].$name -cne $again[$role].$name){throw 'Process observation changed across health challenge'}
        }
    }
    if($replies.Count -ne 2){throw 'Both health services must answer'}
    $records=@();$seen=@{}
    foreach($reply in $replies){
        if($reply.Role -isnot [string] -or $reply.Role -cnotin @('runtime','broker') -or $seen.ContainsKey($reply.Role)){throw 'Invalid health service role'}
        $role=$reply.Role;$seen[$role]=$true;$suffix=if($role -ceq 'broker'){'.health-v1'}else{'.runtime-health-v1'}
        if($reply.PipeName -isnot [string] -or $reply.PipeName -cne ($BrokerPipeName+$suffix) -or
            $reply.ProcessId -isnot [int] -or $reply.ProcessId -ne $roles[$role].pid -or
            $reply.CreationFileTime -isnot [long] -or $reply.CreationFileTime -ne $roles[$role].creation_filetime){throw 'Health reply identity differs'}
        foreach($name in @('HealthServiceResponsive','NonceVerified','PipeServerIdentityBound')){if($reply.$name -isnot [bool] -or -not $reply.$name){throw 'Health client binding failed'}}
        $records+=,[pscustomobject][ordered]@{role=$role;pid=$reply.ProcessId;creation_filetime=$reply.CreationFileTime;pipe_name=$reply.PipeName;
            health_service_responsive=$true;nonce_verified=$true;pipe_server_identity_bound=$true}
    }
    [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-health-v1';records=$records;client_source_sha256=$script:HealthClientHash;
        protocol_deadline_ms=1000;pair_shares_protocol_deadline=$true;cancellation_cleanup_hard_realtime=$false;
        health_service_responsive=$true;nonce_verified=$true;pipe_server_identity_bound=$true;retained_process_observation_rechecked=$true;
        runtime_ready=$false;runtime_ready_verified=$false;startup_path_verified=$false;E7_accepted=$false;L6_sealed=$false;full_acceptance=$false;
        execution_authorized=$false;in_memory_code_identity_verified=$false;local_product_ready=$false;public_release_ready=$false;user_state_read=$false}
}
Export-ModuleMember -Function Get-YimeCoreNativeMaintenanceHealth
