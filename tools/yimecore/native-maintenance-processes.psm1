Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ProcessObservations=@{}
$script:ProcessModulePath=$PSCommandPath
$script:ProcessNativeNamespace='Yime.MaintenanceProcessLease_'+[guid]::NewGuid().ToString('N')
$script:ProcessFactsType=$null;$script:ProcessPinType=$null
$script:ProcessHelperHashes=@{
    'rime-pime-dp1u-native-facts.cs'='9969b68b42bc11428d4af6a8bb348a9658e248c0758b953bd9e3834109f97be4'
    'native-maintenance-process-facts.cs'='55e81dc42c9280aed1f054a816534d9961d5e52b99e2a098d89a5be0392b2370'
}
function Initialize-MaintenanceProcessFacts($Sources) {
    foreach($spec in @(
        @{name='rime-pime-dp1u-native-facts.cs';old='namespace Yime.Dp1UNative {';type='Facts';variable='ProcessFactsType'},
        @{name='native-maintenance-process-facts.cs';old='namespace Yime.MaintenanceProcesses {';type='ProcessPin';variable='ProcessPinType'})){
        $files=@($Sources.files|Where-Object {$_.name -ceq $spec.name})
        if($files.Count -ne 1 -or $files[0].sha256 -cne $script:ProcessHelperHashes[$spec.name]){throw 'Reviewed process helper source is missing or differs'}
        $file=$files[0]
        if((Get-MaintenanceProcessStreamHash $file.stream) -cne $file.sha256){throw 'Held process helper source changed before compilation'}
        $reader=[IO.StreamReader]::new($file.stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$file.stream.Position=0}
        if($null -eq (Get-Variable -Scope Script -Name $spec.variable -ValueOnly)){
            if(($text.Split(@($spec.old),[StringSplitOptions]::None)).Count -ne 2){throw 'Process helper namespace is ambiguous'}
            $types=@(Add-Type -TypeDefinition ($text.Replace($spec.old,('namespace '+$script:ProcessNativeNamespace+' {'))) -PassThru)
            $wanted=@($types|Where-Object {$_.FullName -ceq ($script:ProcessNativeNamespace+'.'+$spec.type)})
            if($wanted.Count -ne 1){throw 'Private process helper Type was not compiled'}
            Set-Variable -Scope Script -Name $spec.variable -Value $wanted[0]
        }
    }
    foreach($file in $Sources.files){$file.file_identity=$script:ProcessFactsType::VerifyFileHandle($file.stream,$file.path)}
    Assert-MaintenanceProcessSources $Sources
}
function Assert-MaintenanceProcessRoot([string]$Root) {
    if($Root -cnotmatch '^[A-Z]:\\[^\\]+' -or $Root -match '[\x00-\x1f/"<>|?*%]' -or $Root.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Root) -cne $Root){throw 'Canonical explicit local install root required'}
    foreach($part in $Root.Substring(3).Split('\')){if(-not $part -or $part -in @('.','..') -or $part -match '[ .]$|~|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Ambiguous install root'}}
    [void]([Text.UnicodeEncoding]::new($false,$false,$true)).GetBytes($Root)
}
function Assert-MaintenanceProcessPlainPath([string]$Path) {
    $cursor=$Path
    while($cursor){
        if(-not (Test-Path -LiteralPath $cursor)){throw 'Expected public image path is absent'}
        if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect public image path rejected'}
        $cursor=Split-Path -Parent $cursor
    }
}
function Get-MaintenanceProcessRows {
    # Discovery only: no owner/path/startup assertion is taken from CIM JSON.
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name='YimeCoreTrialRuntime.exe' OR Name='YimeBroker.exe'" -Property ProcessId,Name -ErrorAction Stop)
}
function Get-MaintenanceProcessIds {
    $rows=@(Get-MaintenanceProcessRows)
    if($rows.Count -ne 2){throw 'Exactly one Runtime and one Broker must be observed; absent/partial/multiple state rejected'}
    $result=[ordered]@{}
    foreach($name in @('YimeCoreTrialRuntime.exe','YimeBroker.exe')){
        $matches=@($rows | Where-Object {$null -ne $_ -and $_.Name -is [string] -and $_.Name -ieq $name})
        if($matches.Count -ne 1){throw 'Ambiguous or unknown process discovery'}
        $value=$matches[0].ProcessId
        if(($value -isnot [int] -and $value -isnot [uint32]) -or $value -le 0 -or $value -gt [int]::MaxValue){throw 'Invalid discovered PID'}
        $result[$name]=[int]$value
    }
    if($result['YimeCoreTrialRuntime.exe'] -eq $result['YimeBroker.exe']){throw 'Process identities overlap'}
    return $result
}
function Open-MaintenanceProcessPin([int]$ProcessId){$script:ProcessPinType::Open($ProcessId)}
function Open-MaintenanceProcessReferencePin($Process){$script:ProcessPinType::OpenReference($Process)}
function Read-MaintenanceProcessPin($Pin){$Pin.Capture()}
function Open-MaintenanceProcessTokenFacts([int]$ProcessId){$script:ProcessFactsType::OpenProcessFacts($ProcessId)}
function Get-MaintenanceProcessCallerSid {[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
function Open-MaintenanceProcessFile([string]$Path,[string]$ExpectedSha256) {
    Assert-MaintenanceProcessPlainPath $Path
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $identity=$script:ProcessFactsType::VerifyFileHandle($stream,$Path)
        if($stream.Length -le 0 -or $stream.Length -gt 268435456){throw 'Public process image exceeds bounded read'}
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($hash -cne $ExpectedSha256){throw 'Expected process image hash differs'}
        Assert-MaintenanceProcessPlainPath $Path
        [pscustomobject]@{stream=$stream;path=$Path;sha256=$hash;bytes=$stream.Length;file_identity=$identity}
    } catch {$stream.Dispose();throw}
}
function Assert-MaintenanceProcessFile($File) {
    Assert-MaintenanceProcessPlainPath $File.path
    if($script:ProcessFactsType::VerifyFileHandle($File.stream,$File.path) -cne $File.file_identity -or $File.stream.Length -ne $File.bytes){throw 'Pinned public image identity changed'}
}
function Close-MaintenanceProcessFile($File){$File.stream.Dispose()}
function Get-MaintenanceProcessStreamHash([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-','').ToLowerInvariant()}
    finally{$Stream.Position=0;$sha.Dispose()}
}
function Open-MaintenanceProcessSources {
    $files=[Collections.Generic.List[object]]::new();$records=@()
    try{
        foreach($path in @($script:ProcessModulePath,(Join-Path $PSScriptRoot 'native-maintenance-process-facts.cs'),
            ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../dual-product/rime-pime-dp1u-native-facts.cs'))))){
            Assert-MaintenanceProcessPlainPath $path
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $file=[pscustomobject]@{name=(Split-Path -Leaf $path);path=$path;stream=$stream;sha256=$null;bytes=$null;file_identity=$null};$files.Add($file)
            if($stream.Length -lt 1 -or $stream.Length -gt 1048576){throw 'Bounded process observer source required'}
            $file.sha256=Get-MaintenanceProcessStreamHash $stream;$file.bytes=$stream.Length
            if($script:ProcessHelperHashes.ContainsKey($file.name) -and $file.sha256 -cne $script:ProcessHelperHashes[$file.name]){throw 'Reviewed process helper source changed'}
            $records+=,[pscustomobject][ordered]@{name=$file.name;sha256=$file.sha256}
        }
        [pscustomobject]@{files=$files;records=$records}
    }catch{foreach($file in $files){$file.stream.Dispose()};throw}
}
function Assert-MaintenanceProcessSources($Sources) {
    foreach($file in $Sources.files){
        Assert-MaintenanceProcessPlainPath $file.path
        if($script:ProcessFactsType::VerifyFileHandle($file.stream,$file.path) -cne $file.file_identity -or
            $file.stream.Length -ne $file.bytes -or (Get-MaintenanceProcessStreamHash $file.stream) -cne $file.sha256){throw 'Retained process observer source changed'}
    }
}
function Close-MaintenanceProcessSources($Sources){
    $failure=$null
    if($null -ne $Sources){foreach($file in $Sources.files){try{$file.stream.Dispose()}catch{if($null -eq $failure){$failure=$_}}}}
    if($null -ne $failure){throw $failure}
}
function Get-MaintenanceProcessSourcePins {
    $sources=Open-MaintenanceProcessSources
    try{Initialize-MaintenanceProcessFacts $sources;$sources.records}finally{Close-MaintenanceProcessSources $sources}
}
function Assert-MaintenanceProcessReferences($RuntimeProcess,$BrokerProcess) {
    foreach($process in @($RuntimeProcess,$BrokerProcess)){
        if($null -eq $process -or $process -isnot [Diagnostics.Process] -or $process.GetType() -ne [Diagnostics.Process]){throw 'Original exact Runtime and Broker Process references required'}
    }
    if([object]::ReferenceEquals($RuntimeProcess,$BrokerProcess)){throw 'Runtime and Broker Process references must differ'}
}
function Assert-MaintenanceProcessIdentity($Pin,$Token,[int]$ProcessId,[string]$Image,[string]$Sid) {
    if($null -eq $Pin -or $null -eq $Token -or $Pin.Pid -isnot [int] -or $Token.Pid -isnot [int] -or
        $Pin.ParentPid -isnot [int] -or $Pin.ParentPid -le 0 -or $Pin.CreationFileTime -isnot [long] -or $Token.CreationFileTime -isnot [long] -or
        $Token.PackageQuery -isnot [int] -or ($Pin.ProcessMachine -isnot [uint16] -and $Pin.ProcessMachine -isnot [int]) -or
        ($Pin.NativeMachine -isnot [uint16] -and $Pin.NativeMachine -isnot [int]) -or $Pin.Pid -ne $ProcessId -or $Token.Pid -ne $ProcessId -or
        $Pin.CreationFileTime -le 0 -or $Pin.CreationFileTime -ne $Token.CreationFileTime -or
        $Pin.Image -isnot [string] -or $Token.Image -isnot [string] -or $Pin.Image -ine $Image -or $Token.Image -ine $Image -or
        $Token.Sid -isnot [string] -or $Token.Sid -cne $Sid -or $Token.Elevated -isnot [bool] -or $Token.Elevated -or
        $Token.PackageQuery -ne 15700 -or $Pin.ProcessMachine -ne 0 -or $Pin.NativeMachine -ne 0x8664){throw 'Native handle/token/image/SID/architecture identity rejected'}
}
function Close-MaintenanceProcessBundle($Bundle) {
    $failure=$null
    foreach($item in $Bundle.items){
        try{if($null -ne $item.file){Close-MaintenanceProcessFile $item.file}}catch{if($null -eq $failure){$failure=$_}}
        try{if($null -ne $item.token){$item.token.Dispose()}}catch{if($null -eq $failure){$failure=$_}}
        try{if($null -ne $item.pin){$item.pin.Dispose()}}catch{if($null -eq $failure){$failure=$_}}
    }
    try{Close-MaintenanceProcessSources $Bundle.source_leases}catch{if($null -eq $failure){$failure=$_}}
    if($null -ne $failure){throw $failure}
}
function Read-MaintenanceProcessBundle($Bundle) {
    if($Bundle.discovery_scope -ceq 'global_exact_pair'){
        $ids=Get-MaintenanceProcessIds
        if(($ids.Values -join ',') -cne ($Bundle.ids.Values -join ',')){throw 'Process set changed or PID reused'}
    }
    $records=@()
    foreach($item in $Bundle.items){
        $actual=Read-MaintenanceProcessPin $item.pin
        $freshToken=Open-MaintenanceProcessTokenFacts $item.process_id
        try {
            Assert-MaintenanceProcessIdentity $actual $freshToken $item.process_id $item.image $Bundle.sid
            if($actual.CreationFileTime -ne $item.initial.CreationFileTime -or $actual.ParentPid -ne $item.initial.ParentPid){throw 'Retained process identity changed'}
            Assert-MaintenanceProcessFile $item.file
            $records += [pscustomobject][ordered]@{role=$item.role;pid=$actual.Pid;parent_pid=$actual.ParentPid;creation_filetime=$actual.CreationFileTime;
                image=$actual.Image;sid=$freshToken.Sid;elevated=[bool]$freshToken.Elevated;package_query=$freshToken.PackageQuery;
                process_machine=$actual.ProcessMachine;native_machine=$actual.NativeMachine;image_sha256=$item.file.sha256;image_bytes=$item.file.bytes;file_identity=$item.file.file_identity}
        } finally {$freshToken.Dispose()}
    }
    if($records[1].parent_pid -ne $records[0].pid -or $records[1].creation_filetime -lt $records[0].creation_filetime){throw 'Broker is not the observed Runtime child'}
    if($Bundle.discovery_scope -ceq 'global_exact_pair'){
        $again=Get-MaintenanceProcessIds
        if(($again.Values -join ',') -cne ($Bundle.ids.Values -join ',')){throw 'Process membership changed at capture boundary'}
    }
    foreach($item in $Bundle.items){$end=Read-MaintenanceProcessPin $item.pin;if($end.CreationFileTime -ne $item.initial.CreationFileTime){throw 'Pinned process ended or changed'}}
    Assert-MaintenanceProcessSources $Bundle.source_leases
    $sourceCopy=@($Bundle.sources | ForEach-Object {[pscustomobject][ordered]@{name=$_.name;sha256=$_.sha256}})
    [pscustomobject][ordered]@{schema_version='yimecore-native-maintenance-processes-v1';target_user_sid=$Bundle.sid;expected_install_root=$Bundle.root;processes=$records;source_pins=$sourceCopy;
        discovery_scope=$Bundle.discovery_scope;process_start_origin_authenticated=$false;
        native_handle_identity_observed=$true;native_parent_relation_observed=$true;public_image_hash_verified=$true;atomic=$false;continuous_monitoring=$false;
        in_memory_code_identity_verified=$false;desktop_session_verified=$false;startup_path_verified=$false;runtime_ready_verified=$false;execution_authorized=$false}
}
function Open-YimeCoreNativeMaintenanceProcesses {
    [CmdletBinding(DefaultParameterSetName='Discovery')]param([Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$ExpectedInstallRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedRuntimeSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedBrokerSha256,
        [Parameter(Mandatory,ParameterSetName='References')]$RuntimeProcess,
        [Parameter(Mandatory,ParameterSetName='References')]$BrokerProcess)
    $references=$PSCmdlet.ParameterSetName -ceq 'References'
    if($references){Assert-MaintenanceProcessReferences $RuntimeProcess $BrokerProcess}
    if($TargetUserSid -cnotmatch '^S-1-5-21-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*-[1-9][0-9]*$' -or
        ([Security.Principal.SecurityIdentifier]::new($TargetUserSid)).Value -cne $TargetUserSid -or (Get-MaintenanceProcessCallerSid) -cne $TargetUserSid){throw 'Same explicit initiating SID required'}
    Assert-MaintenanceProcessRoot $ExpectedInstallRoot
    $bundle=[pscustomobject]@{sid=$TargetUserSid;root=$ExpectedInstallRoot;sources=@();source_leases=$null;ids=[ordered]@{};
        discovery_scope=$(if($references){'explicit_process_references'}else{'global_exact_pair'});items=[Collections.Generic.List[object]]::new();public=$null}
    try {
        $bundle.source_leases=Open-MaintenanceProcessSources
        Initialize-MaintenanceProcessFacts $bundle.source_leases;$bundle.sources=@($bundle.source_leases.records)
        if(-not $references){$bundle.ids=Get-MaintenanceProcessIds}
        foreach($spec in @(@{role='runtime';name='YimeCoreTrialRuntime.exe';sha=$ExpectedRuntimeSha256;reference=$RuntimeProcess},
            @{role='broker';name='YimeBroker.exe';sha=$ExpectedBrokerSha256;reference=$BrokerProcess})){
            $image=Join-Path $ExpectedInstallRoot ('bin\'+$spec.name);$processId=0
            $item=[pscustomobject]@{role=$spec.role;image=$image;process_id=$processId;pin=$null;token=$null;file=$null;initial=$null};$bundle.items.Add($item)
            if($references){$item.pin=Open-MaintenanceProcessReferencePin $spec.reference}
            else{$processId=$bundle.ids[$spec.name];$item.pin=Open-MaintenanceProcessPin $processId}
            $item.initial=Read-MaintenanceProcessPin $item.pin
            if($references){$processId=$item.initial.Pid;$bundle.ids[$spec.name]=$processId}
            $item.process_id=$processId;$item.token=Open-MaintenanceProcessTokenFacts $processId
            Assert-MaintenanceProcessIdentity $item.initial $item.token $processId $image $TargetUserSid
            $item.file=Open-MaintenanceProcessFile $image $spec.sha
        }
        if($bundle.ids['YimeCoreTrialRuntime.exe'] -eq $bundle.ids['YimeBroker.exe']){throw 'Process reference identities overlap'}
        $evidence=Read-MaintenanceProcessBundle $bundle
        $id=[guid]::NewGuid().ToString('N')
        $public=[pscustomobject]@{id=$id;evidence=$evidence};$bundle.public=$public;$script:ProcessObservations[$id]=$bundle
        return $public
    } catch {Close-MaintenanceProcessBundle $bundle;throw}
}
function Assert-YimeCoreNativeMaintenanceProcessesCurrent {
    [CmdletBinding()]param([Parameter(Mandatory)]$Observation)
    if($null -eq $Observation.PSObject.Properties['id'] -or $Observation.id -isnot [string] -or
        -not $script:ProcessObservations.ContainsKey($Observation.id) -or -not [object]::ReferenceEquals($Observation,$script:ProcessObservations[$Observation.id].public)){throw 'A live owned observation handle is required; serialized evidence is not accepted'}
    Read-MaintenanceProcessBundle $script:ProcessObservations[$Observation.id]
}
function Close-YimeCoreNativeMaintenanceProcesses {
    [CmdletBinding()]param([Parameter(Mandatory)]$Observation)
    if($null -eq $Observation.PSObject.Properties['id'] -or $Observation.id -isnot [string]){throw 'Invalid observation object'}
    if(-not $script:ProcessObservations.ContainsKey($Observation.id)){return}
    $bundle=$script:ProcessObservations[$Observation.id]
    if(-not [object]::ReferenceEquals($Observation,$bundle.public)){throw 'Observation is not owned by this module instance'}
    try{Close-MaintenanceProcessBundle $bundle}finally{$script:ProcessObservations.Remove($Observation.id)}
}
function Get-YimeCoreNativeMaintenanceProcesses {
    [CmdletBinding(DefaultParameterSetName='Discovery')]param([Parameter(Mandatory)][string]$TargetUserSid,[Parameter(Mandatory)][string]$ExpectedInstallRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedRuntimeSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedBrokerSha256,
        [Parameter(Mandatory,ParameterSetName='References')]$RuntimeProcess,
        [Parameter(Mandatory,ParameterSetName='References')]$BrokerProcess)
    $observation=Open-YimeCoreNativeMaintenanceProcesses @PSBoundParameters
    try{Assert-YimeCoreNativeMaintenanceProcessesCurrent $observation}finally{Close-YimeCoreNativeMaintenanceProcesses $observation}
}
$ExecutionContext.SessionState.Module.OnRemove={
    $failure=$null
    try{foreach($bundle in $script:ProcessObservations.Values){try{Close-MaintenanceProcessBundle $bundle}catch{if($null -eq $failure){$failure=$_}}}}
    finally{$script:ProcessObservations.Clear()}
    if($null -ne $failure){throw $failure}
}
Export-ModuleMember -Function Open-YimeCoreNativeMaintenanceProcesses,Assert-YimeCoreNativeMaintenanceProcessesCurrent,Close-YimeCoreNativeMaintenanceProcesses,Get-YimeCoreNativeMaintenanceProcesses
