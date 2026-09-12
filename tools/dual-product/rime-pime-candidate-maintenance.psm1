# The executable candidate's maintenance controller with current-peer protection.
# Import has no product, registry, Runtime, or filesystem mutation.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:CandidatePackageModule=$null
$script:CandidateRegistrationModule=$null
$script:CandidateRuntimeModule=$null
$script:CandidateCoordinatorModule=$null

function Save-RimePimeMaintenanceFailure {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Failure,
        [Parameter(Mandatory)][string]$Phase,[switch]$PassThru)
    # Diagnostics never authorize recovery and never overwrite an earlier error.
    # Do not serialize the request: it contains approval and delegation material.
    try {
        $directory=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Yime Rime-PIME Test Archives\diagnostics'
        for($cursor=$directory;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
            if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Diagnostic path traverses a reparse point.'}
            if(Test-Path -LiteralPath (Join-Path $cursor '.git')){throw 'Diagnostics must remain outside Git.'}
        }
        $null=[IO.Directory]::CreateDirectory($directory)
        $path=Join-Path $directory ('failure-'+[guid]::NewGuid().ToString('N')+'.json')
        $record=[ordered]@{schema_version='yime-maintenance-failure-v1';utc=[DateTime]::UtcNow.ToString('o');
            pid=$PID;phase=$Phase;exception_type=$Failure.Exception.GetType().FullName;
            message=$Failure.Exception.Message;exception=$Failure.Exception.ToString();
            script_stack=$Failure.ScriptStackTrace;error_id=$Failure.FullyQualifiedErrorId;
            installed_acceptance_passed=$false}
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 8)+"`n")
        $stream=[IO.File]::Open($path,'CreateNew','Write','None')
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        Write-Host ('Maintenance failure evidence: '+$path)
        if($PassThru){return $path}
    }catch{
        # Never replace the original installation/rollback error with a log error.
        Write-Warning ('Could not persist maintenance failure: '+$_.Exception.Message) -WarningAction Continue
    }
}

function Assert-CandidateTargetHost {
    # This guard intentionally precedes every caller-path read in public entry points.
    if([Environment]::MachineName -match '(?i)^MYCOMPUTER(?:\.|$)') {
        throw 'MYCOMPUTER daily-use local.12 and production Rime/PIME are prohibited candidate targets.'
    }
}
function Initialize-CandidateMaintenance {
    if($null -eq $script:CandidatePackageModule){
        $script:CandidatePackageModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru -Scope Local
        $script:CandidateCoordinatorModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-candidate-coordinator.psm1') -PassThru -Scope Local
    }
}
function Open-MaintenanceCandidate {
    param([string]$PackageRoot,[string]$ExpectedManifestSha256,[object[]]$InstalledGeneratedFiles=@())
    & $script:CandidatePackageModule {param($r,$h,$g) Open-RimePimeExecutableCandidate -PackageRoot $r -ExpectedManifestSha256 $h -InstalledGeneratedFiles $g} $PackageRoot $ExpectedManifestSha256 $InstalledGeneratedFiles
}
function Close-MaintenanceCandidate($Candidate){
    & $script:CandidatePackageModule {param($c) Close-RimePimeExecutableCandidate -Candidate $c} $Candidate
}
function Get-MaintenanceHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-MaintenanceRootDisjoint([string]$Left,[string]$Right){
    if($Left -ieq $Right -or $Left.StartsWith($Right+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate source and transaction roots overlap.'}
}
function Assert-MaintenanceRecoveryRoot([string]$Root){
    if($Root -match '(?i)\\AppData(?:\\|$)'){throw 'Recovery must be outside AppData.'}
    for($path=$Root;$path;$path=[IO.Path]::GetDirectoryName($path)){
        if(Test-Path -LiteralPath (Join-Path $path '.git')){throw 'Recovery must be outside every Git worktree.'}
    }
}
function Open-MaintenanceAuthorization([string]$AuthorizationPath,[string]$TrustedApprovalSha256,[string]$BoundaryPath){
    $probe=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -PassThru -Scope Local
    & $probe {Initialize-Dp1UNativeFacts}
    $a=$null;$b=$null
    try{
        $a=& $probe {param($p) Open-Dp1UNativeArtifact $p ''} $AuthorizationPath
        $b=& $probe {param($p) Open-Dp1UNativeArtifact $p ''} $BoundaryPath
        $values=@()
        foreach($artifact in @($a,$b)){
            $artifact.stream.Position=0;$memory=[IO.MemoryStream]::new()
            try{$artifact.stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
            $values += & $script:CandidatePackageModule {param($v) ConvertFrom-CandidateJson $v} $bytes
        }
        & $probe {param($a,$b,$hash) Assert-Dp1UNativeRequest $a $b $hash ([Environment]::MachineName) ([DateTime]::UtcNow)} $values[0] $values[1] $TrustedApprovalSha256
        Assert-MaintenanceRecoveryRoot $values[0].recovery_root
        return [pscustomobject]@{authorization=$values[0];boundary=$values[1];approval_sha256=$TrustedApprovalSha256;
            authorization_path=$AuthorizationPath;boundary_path=$BoundaryPath;authorization_raw_sha256=$a.sha256;
            boundary_raw_sha256=$b.sha256;leases=@($a,$b);probe=$probe}
    }catch{if($a){$a.stream.Dispose()};if($b){$b.stream.Dispose()};throw}
}
function Close-MaintenanceAuthorization($Context){foreach($lease in $Context.leases){$lease.stream.Dispose()}}
function Write-MaintenancePeerEvidence([string]$Path,$Value){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 90 -Compress))
    $stream=[IO.File]::Open($Path,'CreateNew','Write','None')
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Start-MaintenancePeerProtection($Context){
    $module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-peer-protection.psm1') -PassThru -Scope Local
    $a=$Context.authorization
    $before=& $module {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $Context.boundary $a.initiating_sid
    # Keep observations outside the transaction tree even if staging fails.
    $directory=[IO.Path]::GetDirectoryName($Context.authorization_path)
    foreach($root in @($a.install_root,$a.state_root,$a.recovery_root,$Context.boundary.peer_install_root,$Context.boundary.peer_state_root,$Context.boundary.peer_recovery_root)){
        Assert-MaintenanceRootDisjoint $directory $root
    }
    Assert-MaintenanceRecoveryRoot $directory
    $prefix=Join-Path $directory ('peer-'+$a.run_id+'-'+[guid]::NewGuid().ToString('N'))
    Write-MaintenancePeerEvidence ($prefix+'-before.json') $before
    $result=[pscustomobject]@{module=$module;boundary=$Context.boundary;sid=$a.initiating_sid;before=$before;prefix=$prefix}
    $Context|Add-Member -NotePropertyName peer_protection -NotePropertyValue $result -Force
    return $result
}
function Assert-MaintenancePeerProtection($Protection){
    if($null -eq $Protection){throw 'Peer protection baseline is required before completion.'}
    $after=& $Protection.module {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $Protection.boundary $Protection.sid
    & $Protection.module {param($b,$a) Assert-RimePimePeerProtectionUnchanged $b $a} $Protection.before $after
}
function Complete-MaintenancePeerProtection($Protection){
    $after=& $Protection.module {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $Protection.boundary $Protection.sid
    Write-MaintenancePeerEvidence ($Protection.prefix+'-after.json') $after
    & $Protection.module {param($b,$a) Assert-RimePimePeerProtectionUnchanged $b $a} $Protection.before $after
    Write-MaintenancePeerEvidence ($Protection.prefix+'-result.json') ([ordered]@{
        schema_version='yime-rime-pime-peer-comparison-v1';unchanged=$true;
        before_sha256=(Get-MaintenanceHash ($Protection.prefix+'-before.json'));
        after_sha256=(Get-MaintenanceHash ($Protection.prefix+'-after.json'));
        installed_acceptance_passed=$false})
}
function Assert-MaintenanceInitiator($Context,[switch]$RequireVacant){
    $a=$Context.authorization
    # A normal candidate is started from an unpackaged Explorer ancestor, including
    # the NSIS -> Windows PowerShell hop. Keep each process handle through the walk.
    $leases=[Collections.Generic.List[object]]::new();$processId=$PID;$seen=@{};$created=[long]::MaxValue;$found=$false
    try{
        for($depth=0;$depth -lt 32;$depth++){
            if($processId -le 0 -or $seen.ContainsKey($processId)){throw 'Incomplete candidate initiator ancestry.'}
            $seen[$processId]=$true;$lease=[Yime.Dp1UNative.Facts]::OpenProcessFacts($processId);$leases.Add($lease)
            if($lease.PackageQuery -ne 15700 -or $lease.Elevated -or $lease.Sid -cne $a.initiating_sid -or
                $lease.Image -match '(?i)\\WindowsApps\\' -or $lease.CreationFileTime -gt $created){throw 'Candidate requires unpackaged non-elevated same-SID ancestry.'}
            $record=Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
            if($null -eq $record -or $record.ExecutablePath -ine $lease.Image -or
                [Math]::Abs($record.CreationDate.ToUniversalTime().ToFileTimeUtc()-$lease.CreationFileTime) -gt 10){throw 'Candidate ancestry identity changed.'}
            if($lease.Image -ieq (Join-Path $env:SystemRoot 'explorer.exe')){$found=$true;break}
            $created=$lease.CreationFileTime;$processId=[int]$record.ParentProcessId
        }
        if(-not $found){throw 'Candidate did not establish its native Explorer initiator.'}
        if([Yime.Dp1UNative.Facts]::Architecture() -cne 'x64'){throw 'Candidate requires native x64 Windows.'}
        $machine=& $Context.probe {Invoke-Dp1UNativeRegistryRead GetStringValue 2147483650 'SOFTWARE\Microsoft\Cryptography' 'MachineGuid' 64}
        if($machine.ReturnValue -ne 0 -or $machine.sValue -ine $a.target_machine_id){throw 'Candidate native MachineGuid mismatch.'}
        if($RequireVacant){$null=& $Context.probe {param($sid,$id) Get-Dp1UNativeContext $sid $id -AllowCurrentYimeCore} $a.initiating_sid $a.target_machine_id}
    }finally{foreach($lease in $leases){$lease.Dispose()}}
}
function Get-MaintenanceDefaultInput {
    # This runs only after the native unpackaged same-SID ancestry checks above.
    # No setter or automatic restoration of an unrelated input method is provided.
    $override=Get-WinDefaultInputMethodOverride -ErrorAction Stop
    $languages=@(Get-WinUserLanguageList -ErrorAction Stop)
    $firstTip=''
    if($languages.Count -and @($languages[0].InputMethodTips).Count){$firstTip=[string]$languages[0].InputMethodTips[0]}
    [pscustomobject][ordered]@{override=if($null -eq $override){''}else{[string]$override.InputMethodTip};
        first_language=if($languages.Count){[string]$languages[0].LanguageTag}else{''};first_tip=$firstTip}
}
function Assert-MaintenanceDefaultInput($Expected){
    $actual=Get-MaintenanceDefaultInput
    if(($actual|ConvertTo-Json -Compress) -cne ($Expected|ConvertTo-Json -Compress)){throw 'Default input method changed; preserving evidence and refusing completion.'}
}
function New-MaintenanceDirectory([string]$Path){
    if(Test-Path -LiteralPath $Path){throw ('Fresh candidate directory already exists: '+$Path)}
    $null=[IO.Directory]::CreateDirectory($Path)
}
function Copy-MaintenanceStream([IO.FileStream]$Source,[string]$Destination){
    $Source.Position=0
    $target=[IO.File]::Open($Destination,'CreateNew','Write','None')
    try{$Source.CopyTo($target);$target.Flush($true)}finally{$target.Dispose();$Source.Position=0}
}
function Export-MaintenanceRecoveryTicket($Context,[string]$JournalRoot,[string]$PreparedSha256){
    # Export the original digest before registration; recovery never substitutes
    # a digest recomputed from a possibly replaced journal. The operator retains
    # this ticket beside their original approval, outside the transaction tree.
    $directory=[IO.Path]::GetDirectoryName($Context.authorization_path)
    foreach($root in @($Context.authorization.install_root,$Context.authorization.state_root,$Context.authorization.recovery_root)){
        Assert-MaintenanceRootDisjoint $directory $root
    }
    $path=Join-Path $directory ('candidate-recovery-'+$Context.authorization.run_id+'.json')
    $ticket=[ordered]@{schema_version='yime-rime-pime-candidate-recovery-ticket-v1';journal_root=$JournalRoot;
        prepared_sha256=$PreparedSha256;approval_sha256=$Context.approval_sha256;package_sha256=$Context.authorization.package_sha256}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($ticket|ConvertTo-Json -Compress))
    $stream=[IO.File]::Open($path,'CreateNew','Write','None')
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    Write-Host ('Retain the original recovery ticket independently: '+$path)
}
function New-MaintenancePreparedPlan($Context,$Package,[string]$InstallerPath,[byte[]]$RuntimeConfiguration){
    $a=$Context.authorization
    foreach($root in @($a.install_root,$a.state_root,$a.recovery_root)){
        Assert-MaintenanceRootDisjoint $root $Package.root
        Assert-MaintenanceRootDisjoint $root ([IO.Path]::GetDirectoryName($InstallerPath))
        if(Test-Path -LiteralPath $root){throw 'A fresh installation requires absent install, state and recovery roots.'}
    }
    $default=Get-MaintenanceDefaultInput
    # Complete private staging before any registration or product Runtime action.
    New-MaintenanceDirectory $a.recovery_root
    $journalRoot=Join-Path $a.recovery_root ('install-'+$a.run_id)
    New-MaintenanceDirectory $journalRoot
    $store=& $script:CandidatePackageModule {param($r) Open-CandidateJournal $r $true} $journalRoot
    try{
        New-MaintenanceDirectory $a.install_root
        $installId=$store.PinDirectory($a.install_root)
        New-MaintenanceDirectory $a.state_root
        $stateId=$store.PinDirectory($a.state_root)
        foreach($child in @('Roaming','Local')){
            $stateChild=Join-Path $a.state_root $child
            New-MaintenanceDirectory $stateChild;$null=$store.PinDirectory($stateChild)
        }
        $sourceDirectories=@($Package.directory_ids.Keys|Where-Object{ $_.StartsWith($Package.root+'\',[StringComparison]::OrdinalIgnoreCase) }|Sort-Object Length)
        foreach($sourceDirectory in $sourceDirectories){
            $destination=Join-Path $a.install_root $sourceDirectory.Substring($Package.root.Length+1)
            New-MaintenanceDirectory $destination;$null=$store.PinDirectory($destination)
        }
        foreach($row in $Package.files){Copy-MaintenanceStream $row.stream (Join-Path $a.install_root $row.path.Replace('/','\'))}
        $manifestStream=[IO.File]::Open((Join-Path $a.install_root 'candidate.json'),'CreateNew','Write','None')
        try{$manifestStream.Write($Package.manifest_bytes,0,$Package.manifest_bytes.Length);$manifestStream.Flush($true)}finally{$manifestStream.Dispose()}
        $launcherConfig=Join-Path $a.install_root 'rime-pime-candidate-state.json'
        $configStream=[IO.File]::Open($launcherConfig,'CreateNew','Write','None')
        try{$configStream.Write($RuntimeConfiguration,0,$RuntimeConfiguration.Length);$configStream.Flush($true)}finally{$configStream.Dispose()}
        $installerStream=[IO.File]::Open($InstallerPath,'Open','Read','Read')
        try{
            Copy-MaintenanceStream $installerStream (Join-Path $a.install_root 'maintenance-candidate.exe')
            Copy-MaintenanceStream $installerStream (Join-Path $a.recovery_root 'maintenance-candidate.exe')
        }finally{$installerStream.Dispose()}
        $recoveryExecutable=& $script:CandidatePackageModule {param($path) $script:CandidateNative::Inspect($path)} (Join-Path $a.recovery_root 'maintenance-candidate.exe')
        if($recoveryExecutable.Sha256 -cne $a.package_sha256){throw 'Independent recovery executable differs from approved candidate.'}
        $paths=@($Package.files|ForEach-Object{$_.path})+@('candidate.json','rime-pime-candidate-state.json','maintenance-candidate.exe')
        $files=@()
        foreach($relative in $paths){
            $record=& $script:CandidatePackageModule {param($path) $script:CandidateNative::Inspect($path)} (Join-Path $a.install_root $relative.Replace('/','\'))
            $files += [pscustomobject][ordered]@{path=$relative;bytes=[long]$record.Bytes;sha256=$record.Sha256;file_id=$record.FileId}
        }
        $generated=@($files|Where-Object{$_.path -in @('rime-pime-candidate-state.json','maintenance-candidate.exe')}|ForEach-Object{
            [pscustomobject][ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})
        $installed=Open-MaintenanceCandidate -PackageRoot $a.install_root -ExpectedManifestSha256 $Package.manifest_sha256 -InstalledGeneratedFiles $generated
        try{
            if(@($generated|Where-Object path -CEQ 'maintenance-candidate.exe')[0].sha256 -cne $a.package_sha256){throw 'Copied maintenance candidate differs from approved executable.'}
            $plan=[pscustomobject][ordered]@{schema_version='yime-rime-pime-candidate-install-plan-v1';run_id=$a.run_id;
                install_root=$a.install_root;state_root=$a.state_root;recovery_root=$a.recovery_root;install_directory_id=$installId;state_directory_id=$stateId;
                initiating_sid=$a.initiating_sid;target_machine_id=$a.target_machine_id;target_name=$a.target_name;
                manifest_sha256=$Package.manifest_sha256;package_sha256=$a.package_sha256;product_version=$Package.manifest.product_version;
                original_approval_sha256=$Context.approval_sha256;default_input=$default;files=$files;generated_files=$generated;
                recovery_executable=[pscustomobject]@{file_id=$recoveryExecutable.FileId;bytes=$recoveryExecutable.Bytes;sha256=$recoveryExecutable.Sha256}}
            $preparedSha=& $script:CandidatePackageModule {param($s,$v) Publish-CandidateJournal $s 'prepared.bin' $v} $store $plan
            Export-MaintenanceRecoveryTicket $Context $journalRoot $preparedSha
            return [pscustomobject]@{journal_root=$journalRoot;prepared_sha256=$preparedSha;plan=$plan}
        }finally{Close-MaintenanceCandidate $installed}
    }finally{$store.Dispose()}
}

function Read-MaintenancePreparedPlan($Context,[string]$JournalRoot,[string]$PreparedSha256){
    $store=& $script:CandidatePackageModule {param($r) Open-CandidateJournal $r $false} $JournalRoot
    try{
        $plan=& $script:CandidatePackageModule {param($s,$h) Read-CandidateJournal $s 'prepared.bin' $h} $store $PreparedSha256
        & $script:CandidatePackageModule {
            param($v)
            Assert-CandidateObject $v @('schema_version','run_id','install_root','state_root','recovery_root','install_directory_id','state_directory_id',
                'initiating_sid','target_machine_id','target_name','manifest_sha256','package_sha256','product_version','original_approval_sha256','default_input','files','generated_files','recovery_executable')
            if($v.schema_version -isnot [string] -or $v.schema_version -cne 'yime-rime-pime-candidate-install-plan-v1'){throw 'Unsupported install plan.'}
            foreach($field in @('manifest_sha256','package_sha256','original_approval_sha256')){Assert-CandidateHash $v.$field}
            if($v.run_id -isnot [string] -or $v.run_id -cnotmatch '^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$'){throw 'Invalid install plan run identity.'}
            if($v.files -isnot [array] -or $v.files.Count -lt 12 -or $v.files.Count -gt 4096){throw 'Invalid install plan member count.'}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($row in $v.files){
                Assert-CandidateObject $row @('path','bytes','sha256','file_id')
                $null=Get-CandidatePath 'C:\Candidate' $row.path
                Assert-CandidateHash $row.sha256
                if(-not $seen.Add($row.path) -or $row.file_id -isnot [string] -or $row.file_id -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$' -or
                    ($row.bytes -isnot [long] -and $row.bytes -isnot [int]) -or $row.bytes -lt 0){throw 'Invalid install plan file identity.'}
            }
            Assert-CandidateObject $v.default_input @('override','first_language','first_tip')
            foreach($property in $v.default_input.PSObject.Properties){if($property.Value -isnot [string]){throw 'Invalid default-input baseline.'}}
            foreach($field in @('install_directory_id','state_directory_id')){
                if($v.$field -isnot [string] -or $v.$field -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$'){throw 'Invalid retained directory identity.'}
            }
            if($v.product_version -isnot [string] -or $v.product_version -cnotmatch '^1\.4\.0-dev\.[1-9][0-9]*$'){throw 'Invalid prepared product version.'}
            Assert-CandidateObject $v.recovery_executable @('file_id','bytes','sha256')
            Assert-CandidateHash $v.recovery_executable.sha256
            if($v.recovery_executable.file_id -isnot [string] -or $v.recovery_executable.file_id -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$' -or
                ($v.recovery_executable.bytes -isnot [int] -and $v.recovery_executable.bytes -isnot [long]) -or $v.recovery_executable.bytes -le 0 -or
                $v.recovery_executable.sha256 -cne $v.package_sha256){throw 'Invalid recovery executable binding.'}
            if($v.generated_files -isnot [array] -or $v.generated_files.Count -ne 2){throw 'Invalid generated installed members.'}
            foreach($g in $v.generated_files){
                Assert-CandidateObject $g @('path','bytes','sha256')
                $matching=@($v.files|Where-Object path -CEQ $g.path)
                if($g.path -cnotin @('rime-pime-candidate-state.json','maintenance-candidate.exe') -or $matching.Count -ne 1 -or
                    $g.bytes -cne $matching[0].bytes -or $g.sha256 -cne $matching[0].sha256){throw 'Generated member differs from prepared file.'}
            }
            if($v.generated_files[0].path -ceq $v.generated_files[1].path){throw 'Duplicate generated installed member.'}
        } $plan
        $a=$Context.authorization
        foreach($field in @('install_root','state_root','recovery_root','initiating_sid','target_machine_id','target_name','package_sha256')){
            if($plan.$field -isnot [string] -or $plan.$field -cne $a.$field){throw ('New approval differs from retained install plan: '+$field)}
        }
        if($JournalRoot -cne (Join-Path $a.recovery_root ('install-'+$plan.run_id))){throw 'Install journal root binding mismatch.'}
        if($store.PinDirectory($plan.install_root) -cne $plan.install_directory_id -or $store.PinDirectory($plan.state_root) -cne $plan.state_directory_id){throw 'Retained install or state directory identity changed.'}
        $recovery=& $script:CandidatePackageModule {param($p) $script:CandidateNative::Inspect($p)} (Join-Path $a.recovery_root 'maintenance-candidate.exe')
        if($recovery.FileId -cne $plan.recovery_executable.file_id -or $recovery.Bytes -ne $plan.recovery_executable.bytes -or $recovery.Sha256 -cne $plan.package_sha256){throw 'Independent recovery executable identity changed.'}
        return [pscustomobject]@{store=$store;plan=$plan;journal_root=$JournalRoot;prepared_sha256=$PreparedSha256}
    }catch{$store.Dispose();throw}
}
function Get-MaintenanceDecision($Store,[string]$Name,[string]$PreparedSha256,[string[]]$Allowed){
    if(-not $Store.Has($Name)){return $null}
    $bytes=$Store.Read($Name)
    $decision=& $script:CandidatePackageModule {param($b) ConvertFrom-CandidateJson $b} $bytes
    & $script:CandidatePackageModule {param($d) Assert-CandidateObject $d @('schema_version','prepared_sha256','disposition');Assert-CandidateHash $d.prepared_sha256} $decision
    if($decision.schema_version -isnot [string] -or $decision.schema_version -cne 'yime-rime-pime-candidate-decision-v1' -or
        $decision.prepared_sha256 -cne $PreparedSha256 -or $decision.disposition -isnot [string] -or $Allowed -cnotcontains $decision.disposition){throw 'Malformed or contradictory candidate decision; preserved.'}
    $decision
}
function Publish-MaintenanceDecision($Store,[string]$Name,[string]$PreparedSha256,[string]$Disposition){
    $value=[pscustomobject][ordered]@{schema_version='yime-rime-pime-candidate-decision-v1';prepared_sha256=$PreparedSha256;disposition=$Disposition}
    $null=& $script:CandidatePackageModule {param($s,$n,$v) Publish-CandidateJournal $s $n $v} $Store $Name $value
}
function Open-MaintenanceRemoval($Ticket,[switch]$Create){
    # One deterministic removal history per prepared install, even when recovery
    # uses a new (unexpired) approval/run ID. It cannot revert to install replay.
    $root=Join-Path $Ticket.plan.recovery_root ('remove-'+$Ticket.plan.run_id)
    $exists=Test-Path -LiteralPath $root
    if(-not $exists -and -not $Create){return $null}
    if(-not $exists){New-MaintenanceDirectory $root}
    $store=& $script:CandidatePackageModule {param($r,$c) Open-CandidateJournal $r $c} $root (-not $exists)
    try{
        $intent=[pscustomobject][ordered]@{schema_version='yime-rime-pime-candidate-removal-intent-v1';
            install_prepared_sha256=$Ticket.prepared_sha256;original_approval_sha256=$Ticket.plan.original_approval_sha256;
            install_root=$Ticket.plan.install_root;disposition='remove-or-rollback'}
        $expectedBytes=[Text.UTF8Encoding]::new($false).GetBytes(($intent|ConvertTo-Json -Compress))
        $hash=& $script:CandidatePackageModule {param($b) Get-CandidateBytesHash $b} $expectedBytes
        if(-not $exists){$published=& $script:CandidatePackageModule {param($s,$v) Publish-CandidateJournal $s 'prepared.bin' $v} $store $intent
            if($published -cne $hash){throw 'Removal intent serialization changed.'}}
        $null=& $script:CandidatePackageModule {param($s,$h) Read-CandidateJournal $s 'prepared.bin' $h} $store $hash
        $commit=Get-MaintenanceDecision $store 'commit.bin' $hash @('remove-requested')
        $terminal=Get-MaintenanceDecision $store 'terminal.bin' $hash @('remove-complete')
        if($terminal -and -not $commit){throw 'Removal terminal lacks durable decision.'}
        return [pscustomobject]@{store=$store;hash=$hash;commit=$commit;terminal=$terminal}
    }catch{$store.Dispose();throw}
}
function Request-MaintenanceRemoval($Ticket){
    $removal=Open-MaintenanceRemoval $Ticket -Create
    try{if(-not $removal.commit){Publish-MaintenanceDecision $removal.store 'commit.bin' $removal.hash 'remove-requested'}}
    finally{$removal.store.Dispose()}
}
function Assert-MaintenanceWorkerDecision($Ticket,[string]$Action,$Context){
    $commit=Get-MaintenanceDecision $Ticket.store 'commit.bin' $Ticket.prepared_sha256 @('installed')
    $terminal=Get-MaintenanceDecision $Ticket.store 'terminal.bin' $Ticket.prepared_sha256 @('install-complete','rolled-back')
    if(($terminal -and $terminal.disposition -ceq 'install-complete' -and -not $commit) -or
        ($terminal -and $terminal.disposition -ceq 'rolled-back' -and $commit)){throw 'Contradictory install decision.'}
    $removal=Open-MaintenanceRemoval $Ticket
    try{
        if($Action -eq 'Remove'){
            if($null -eq $removal -or $null -eq $removal.commit){throw 'Worker removal requires durable removal decision.'}
        }elseif($commit -or $terminal -or $removal -or $Context.approval_sha256 -cne $Ticket.plan.original_approval_sha256){
            throw 'Registration worker cannot replay a decided or differently approved install.'
        }
    }finally{if($removal){$removal.store.Dispose()}}
}
function Complete-MaintenanceRemoval($Context,$Ticket,[hashtable]$WorkerArguments,$Runtime,$InstalledLease=$null){
    Request-MaintenanceRemoval $Ticket
    Stop-MaintenanceRuntime $Ticket.plan $Runtime
    Invoke-MaintenanceWorker -Action Remove @WorkerArguments
    $null=Get-MaintenanceRegistration $Context $Ticket.plan $WorkerArguments.PackageRoot 'Absent'
    Assert-MaintenancePeerProtection $Context.peer_protection
    Assert-MaintenanceDefaultInput $Ticket.plan.default_input
    if($InstalledLease){Close-MaintenanceCandidate $InstalledLease}
    Remove-MaintenanceInstalledFiles $Ticket.plan -EvidenceRoot ([IO.Path]::GetDirectoryName($Context.authorization_path))
    Assert-MaintenancePeerProtection $Context.peer_protection
    $removal=Open-MaintenanceRemoval $Ticket
    try{if(-not $removal.terminal){Publish-MaintenanceDecision $removal.store 'terminal.bin' $removal.hash 'remove-complete'}}
    finally{$removal.store.Dispose()}
    $opened=Read-MaintenancePreparedPlan $Context $Ticket.journal_root $Ticket.prepared_sha256
    try{
        $commit=Get-MaintenanceDecision $opened.store 'commit.bin' $Ticket.prepared_sha256 @('installed')
        $terminal=Get-MaintenanceDecision $opened.store 'terminal.bin' $Ticket.prepared_sha256 @('install-complete','rolled-back')
        if(-not $commit -and -not $terminal){Publish-MaintenanceDecision $opened.store 'terminal.bin' $Ticket.prepared_sha256 'rolled-back'}
    }finally{$opened.store.Dispose()}
}
function Test-MaintenanceInstalledFiles($Plan,[switch]$AllowAbsent){
    $present=@()
    foreach($row in $Plan.files){
        $path=Join-Path $Plan.install_root $row.path.Replace('/','\')
        $status=& $script:CandidatePackageModule {param($p) Get-CandidateLeafStatus $p} $path
        if($status -ceq 'removed'){
            if(-not $AllowAbsent){throw ('Prepared installed member missing: '+$row.path)}
            continue
        }
        $actual=& $script:CandidatePackageModule {param($p) $script:CandidateNative::Inspect($p)} $path
        if($actual.FileId -cne $row.file_id -or $actual.Bytes -ne $row.bytes -or $actual.Sha256 -cne $row.sha256){throw ('Installed member changed; retained: '+$row.path)}
        $present += $row
    }
    return ,$present
}
function Remove-MaintenanceInstalledFiles($Plan,[string]$EvidenceRoot){
    if(-not $EvidenceRoot){$EvidenceRoot=$Plan.recovery_root}
    $present=Test-MaintenanceInstalledFiles $Plan -AllowAbsent
    $evidencePath=Join-Path $EvidenceRoot ('exact-removal-'+[guid]::NewGuid().ToString('N')+'.json')
    $outcomes=@()
    if($present.Count){
        try{$outcomes=@(& $script:CandidatePackageModule {param($r,$f) Remove-CandidateExactFiles $r $f} $Plan.install_root $present)}
        catch{
            Write-MaintenancePeerEvidence $evidencePath @{install_root=$Plan.install_root;utc=[DateTime]::UtcNow.ToString('o');pid=$PID;attempted_members=$present;error=$_.Exception.ToString();outcomes_available=$false}
            Write-Host ('Exact removal evidence: '+$evidencePath)
            throw
        }
    }
    # Persist the native outcomes before asserting completion. Later members can
    # be not-attempted after a single blocked leaf; never infer their cause.
    Write-MaintenancePeerEvidence $evidencePath @{install_root=$Plan.install_root;utc=[DateTime]::UtcNow.ToString('o');pid=$PID;initially_absent_count=(@($Plan.files).Count-$present.Count);outcomes_available=$true;outcomes=@($outcomes|ForEach-Object{[ordered]@{path=$_.Path;status=$_.Status;marked_for_deletion=$_.MarkedForDeletion;removed=$_.Removed;native_error=$_.ErrorCode}})}
    Write-Host ('Exact removal evidence: '+$evidencePath)
    if(@($outcomes|Where-Object{-not $_.Removed}).Count){throw ('Exact removal is pending or incomplete; no completion decision published. Evidence: '+$evidencePath)}
    $remaining=Test-MaintenanceInstalledFiles $Plan -AllowAbsent
    if($remaining.Count){throw 'Installed desired absence was not observed.'}
    # User learning/state, unlisted files, directories and durable recovery remain.
}
function Get-MaintenanceProviderParameters($Context,$Plan,[string]$PackageRoot){
    @{
        InstallRoot=[string]$Plan.install_root;TargetUserSid=[string]$Plan.initiating_sid
        AuthorizationPath=$Context.authorization_path;TrustedApprovalSha256=$Context.approval_sha256;BoundaryPath=$Context.boundary_path
        PackageRoot=$PackageRoot;PackageManifestSha256=[string]$Plan.manifest_sha256
        UninstallerSha256=[string]$Plan.package_sha256;DisplayVersion=[string]$Plan.product_version
        CoordinationHandle=[IntPtr]$Context.coordinator_handle
    }
}
function Initialize-MaintenanceProviders([string]$PackageRoot){
    $script:CandidateRegistrationModule=Import-Module (Join-Path $PackageRoot 'maintenance\rime-pime-dp1u-candidate-registration.psm1') -PassThru -Scope Local
    $script:CandidateRuntimeModule=Import-Module (Join-Path $PackageRoot 'maintenance\rime-pime-dp1u-candidate-runtime.psm1') -PassThru -Scope Local
}
function Get-MaintenanceRegistration($Context,$Plan,[string]$PackageRoot,[string]$State){
    $parameters=Get-MaintenanceProviderParameters $Context $Plan $PackageRoot
    & $script:CandidateRegistrationModule {param($p,$s) Get-RimePimeDp1UCandidateRegistrationObservation @p -ExpectedState $s} $parameters $State
}
function New-MaintenanceRuntimeConfiguration($Context){
    $a=$Context.authorization
    $value=[ordered]@{schema_version='yime-rime-pime-candidate-state-v1';install_root=$a.install_root;state_root=$a.state_root;target_user_sid=$a.initiating_sid}
    return ,[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Compress))
}
function Get-MaintenanceRuntimeParameters($Plan){
    $launcher=@($Plan.files|Where-Object path -CEQ 'PIMELauncher.exe')
    $backend=@($Plan.files|Where-Object path -CEQ 'go-backend/server.exe')
    $configuration=@($Plan.files|Where-Object path -CEQ 'rime-pime-candidate-state.json')
    if($launcher.Count -ne 1 -or $backend.Count -ne 1 -or $configuration.Count -ne 1){throw 'Runtime executable/configuration inventory is not exact.'}
    @{InstallRoot=$Plan.install_root;StateRoot=$Plan.state_root;TargetUserSid=$Plan.initiating_sid;
        LauncherSha256=$launcher[0].sha256;BackendSha256=$backend[0].sha256;ConfigurationSha256=$configuration[0].sha256}
}
function Start-MaintenanceRuntime($Plan){
    $parameters=Get-MaintenanceRuntimeParameters $Plan
    & $script:CandidateRuntimeModule {param($p) Start-RimePimeCandidateRuntime @p} $parameters
}
function Resume-MaintenanceRuntime($Plan){
    $parameters=Get-MaintenanceRuntimeParameters $Plan
    $runtime=& $script:CandidateRuntimeModule {param($p) Get-RimePimeCandidateRuntimeContext @p} $parameters
    if($null -eq $runtime){$runtime=Start-MaintenanceRuntime $Plan}
    $runtime
}
function Test-MaintenanceRuntime($Runtime){
    $result=& $script:CandidateRuntimeModule {param($c) Test-RimePimeCandidateRuntimeReady -Context $c} $Runtime
    if($result.ready -isnot [bool] -or -not $result.ready){throw 'Actual native Rime Runtime readiness did not pass.'}
    $result
}
function Stop-MaintenanceRuntime($Plan,$Runtime){
    if($null -ne $Runtime){& $script:CandidateRuntimeModule {param($c) Stop-RimePimeCandidateRuntime -Context $c} $Runtime | Out-Null}
    else{
        $parameters=Get-MaintenanceRuntimeParameters $Plan
        & $script:CandidateRuntimeModule {param($p) Stop-RimePimeCandidateOwnedRuntime @p} $parameters | Out-Null
    }
}
function Invoke-MaintenanceWorker([string]$Action,$Context,$Ticket,[string]$PackageRoot,[string]$ExpectedManifestSha256,
    [string]$InstallerPath,[string]$ReceiptPath,$Coordinator){
    $self=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID)
    try{
        $request=[ordered]@{Action=$Action;PackageRoot=$PackageRoot;ExpectedManifestSha256=$ExpectedManifestSha256;
            InstallerPath=$InstallerPath;AuthorizationPath=$Context.authorization_path;TrustedApprovalSha256=$Context.approval_sha256;
            BoundaryPath=$Context.boundary_path;ReceiptPath=$ReceiptPath;JournalRoot=$Ticket.journal_root;
            PreparedSha256=$Ticket.prepared_sha256;ParentPid=$PID;ParentCreationFileTime=$self.CreationFileTime;
            DelegationToken=$Coordinator.delegation_token}
        $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Compress)))
        $modulePath=(Join-Path $PackageRoot 'maintenance\rime-pime-candidate-maintenance.psm1').Replace("'","''")
        $command="`$ErrorActionPreference='Stop'; try { `$v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload'))|ConvertFrom-Json; `$p=@{}; foreach(`$x in `$v.PSObject.Properties){`$p[`$x.Name]=`$x.Value}; Import-Module '$modulePath'; Invoke-RimePimeCandidateWorker @p; exit 0 } catch { if(Get-Command Save-RimePimeMaintenanceFailure -ErrorAction SilentlyContinue){Save-RimePimeMaintenanceFailure -Failure `$_ -Phase 'elevated-$Action'}; Write-Error `$_ -ErrorAction Continue; exit 51 }"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $process=Start-Process -FilePath $hostPath -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru
        try{
            # Never begin rollback while an elevated registrar may still mutate.
            # The worker/provider job contains descendants if the worker exits.
            $process.WaitForExit()
            if($process.ExitCode -ne 0){throw ('Candidate elevated worker failed with exit code '+$process.ExitCode+'; persistent plan retained.')}
        }finally{$process.Dispose()}
    }finally{$self.Dispose()}
}
function Open-MaintenanceVerifiedPackage([string]$PackageRoot,[string]$ExpectedManifestSha256,$Context,[string]$InstallerPath,[string]$ReceiptPath){
    $package=Open-MaintenanceCandidate -PackageRoot $PackageRoot -ExpectedManifestSha256 $ExpectedManifestSha256
    try{
        $reader=Import-Module (Join-Path $PackageRoot 'maintenance\rime-pime-executable-receipt.psm1') -PassThru -Scope Local
        $null=& $reader {param($r,$rh,$i,$ih,$m) Read-RimePimeExecutableReceipt -ReceiptPath $r -ExpectedReceiptSha256 $rh -InstallerPath $i -ExpectedInstallerSha256 $ih -ExpectedManifestSha256 $m} `
            $ReceiptPath $Context.authorization.canonical_receipt_sha256 $InstallerPath $Context.authorization.package_sha256 $ExpectedManifestSha256
        return $package
    }catch{Close-MaintenanceCandidate $package;throw}
}
function Invoke-RimePimeCandidateWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Register','PublishMarkers','Remove')][string]$Action,
        [Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$AuthorizationPath,
        [Parameter(Mandatory)][string]$TrustedApprovalSha256,[Parameter(Mandatory)][string]$BoundaryPath,
        [Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)][string]$JournalRoot,
        [Parameter(Mandatory)][string]$PreparedSha256,[Parameter(Mandatory)][int]$ParentPid,
        [Parameter(Mandatory)][long]$ParentCreationFileTime,[Parameter(Mandatory)][string]$DelegationToken)
    Assert-CandidateTargetHost
    Initialize-CandidateMaintenance
    $protection=$null;$context=$null;$package=$null;$ticket=$null;$parent=$null;$self=$null;$coordinator=$null;$installed=$null
    try{
        $context=Open-MaintenanceAuthorization $AuthorizationPath $TrustedApprovalSha256 $BoundaryPath
        $coordinator=& $script:CandidateCoordinatorModule {param($p,$t,$s,$d) Join-RimePimeCandidateCoordinator -ParentPid $p -ParentCreationFileTime $t -TargetUserSid $s -DelegationToken $d} `
            $ParentPid $ParentCreationFileTime $context.authorization.initiating_sid $DelegationToken
        $context|Add-Member -NotePropertyName coordinator_handle -NotePropertyValue (& $script:CandidateCoordinatorModule {param($c) Get-RimePimeCandidateCoordinatorHandle -Context $c} $coordinator) -Force
        $parent=[Yime.Dp1UNative.Facts]::OpenProcessFacts($ParentPid)
        $self=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID)
        if($parent.CreationFileTime -ne $ParentCreationFileTime -or $parent.Elevated -or $parent.PackageQuery -ne 15700 -or
            $parent.Sid -cne $context.authorization.initiating_sid -or $self.Sid -cne $parent.Sid -or -not $self.Elevated -or $self.PackageQuery -ne 15700 -or
            $parent.Image -ine (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')){throw 'Elevated worker lost its exact non-elevated initiating process/SID binding.'}
        $package=Open-MaintenanceVerifiedPackage $PackageRoot $ExpectedManifestSha256 $context $InstallerPath $ReceiptPath
        Initialize-MaintenanceProviders $PackageRoot
        $protection=Start-MaintenancePeerProtection $context
        $ticket=Read-MaintenancePreparedPlan $context $JournalRoot $PreparedSha256
        if($ticket.plan.manifest_sha256 -cne $ExpectedManifestSha256){throw 'Worker candidate differs from retained plan.'}
        Assert-MaintenanceWorkerDecision $ticket $Action $context
        Assert-MaintenancePeerProtection $protection
        Assert-MaintenanceDefaultInput $ticket.plan.default_input
        $parameters=Get-MaintenanceProviderParameters $context $ticket.plan $PackageRoot
        if($Action -eq 'Remove'){
            # A prior interrupted removal can have already deleted DLLs. Native
            # observation must prove complete absence before skipping registrars.
            $absent=$false
            try{$null=Get-MaintenanceRegistration $context $ticket.plan $PackageRoot 'Absent';$absent=$true}catch{}
            if(-not $absent){
                $null=Test-MaintenanceInstalledFiles $ticket.plan
                $installed=Open-MaintenanceCandidate -PackageRoot $ticket.plan.install_root -ExpectedManifestSha256 $ExpectedManifestSha256 -InstalledGeneratedFiles $ticket.plan.generated_files
                foreach($step in @('DisableTip','UnregisterWow64','UnregisterNative','RemoveMarkers','VerifyAbsent')){
                    Assert-MaintenancePeerProtection $protection
                    Write-MaintenancePeerEvidence ($protection.prefix+'-'+$step+'-started.json') @{step=$step;utc=[DateTime]::UtcNow.ToString('o');pid=$PID}
                    & $script:CandidateRegistrationModule {param($p,$s) Invoke-RimePimeDp1UCandidateRegistration @p -Action $s} $parameters $step | Out-Null
                    $stepPeer=& $protection.module {param($b,$s) Get-RimePimePeerProtectionSnapshot $b $s} $protection.boundary $protection.sid
                    Write-MaintenancePeerEvidence ($protection.prefix+'-'+$step+'-after.json') $stepPeer
                    & $protection.module {param($b,$a) Assert-RimePimePeerProtectionUnchanged $b $a} $protection.before $stepPeer
                }
            }
        }else{
            $null=Test-MaintenanceInstalledFiles $ticket.plan
            $installed=Open-MaintenanceCandidate -PackageRoot $ticket.plan.install_root -ExpectedManifestSha256 $ExpectedManifestSha256 -InstalledGeneratedFiles $ticket.plan.generated_files
            $steps=if($Action -eq 'Register'){@('AssertVacant','RegisterNative','RegisterWow64','EnableTip')}else{@('PublishMarkers','VerifyPresent')}
            foreach($step in $steps){& $script:CandidateRegistrationModule {param($p,$s) Invoke-RimePimeDp1UCandidateRegistration @p -Action $s} $parameters $step | Out-Null}
        }
        Assert-MaintenancePeerProtection $protection
        Assert-MaintenanceDefaultInput $ticket.plan.default_input
    }catch{
        # Preserve the original error even when the final peer assertion also fails.
        Save-RimePimeMaintenanceFailure -Failure $_ -Phase ('worker-original-'+$Action)
        throw
    }finally{
        try{if($protection){Complete-MaintenancePeerProtection $protection}}finally{
        if($installed){Close-MaintenanceCandidate $installed}
        if($ticket){$ticket.store.Dispose()};if($package){Close-MaintenanceCandidate $package};if($context){Close-MaintenanceAuthorization $context}
        if($parent){$parent.Dispose()};if($self){$self.Dispose()}
        if($coordinator){& $script:CandidateCoordinatorModule {param($c) Close-RimePimeCandidateCoordinator -Context $c} $coordinator}
        }
    }
}

function Invoke-RimePimeCandidateMaintenance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Install','Remove','Resume')][string]$Mode,
        [Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][string]$InstallerPath,[Parameter(Mandatory)][string]$AuthorizationPath,
        [Parameter(Mandatory)][string]$TrustedApprovalSha256,[Parameter(Mandatory)][string]$BoundaryPath,
        [Parameter(Mandatory)][string]$ReceiptPath,[string]$PreparedSha256)
    Assert-CandidateTargetHost
    Initialize-CandidateMaintenance
    $protection=$null;$context=$null;$package=$null;$ticket=$null;$runtime=$null;$runtimeReady=$null;$coordinator=$null;$installed=$null
    try{
        $context=Open-MaintenanceAuthorization $AuthorizationPath $TrustedApprovalSha256 $BoundaryPath
        $coordinator=& $script:CandidateCoordinatorModule {Open-RimePimeCandidateCoordinator}
        $context|Add-Member -NotePropertyName coordinator_handle -NotePropertyValue (& $script:CandidateCoordinatorModule {param($c) Get-RimePimeCandidateCoordinatorHandle -Context $c} $coordinator) -Force
        Assert-MaintenanceInitiator $context -RequireVacant:($Mode -eq 'Install')
        $package=Open-MaintenanceVerifiedPackage $PackageRoot $ExpectedManifestSha256 $context $InstallerPath $ReceiptPath
        Initialize-MaintenanceProviders $PackageRoot
        $protection=Start-MaintenancePeerProtection $context
        if($Mode -eq 'Install'){
            if($PreparedSha256){throw 'Initial installation cannot reuse a prepared transaction.'}
            $configuration=New-MaintenanceRuntimeConfiguration $context
            $ticket=New-MaintenancePreparedPlan $context $package $InstallerPath $configuration
            $installed=Open-MaintenanceCandidate -PackageRoot $ticket.plan.install_root -ExpectedManifestSha256 $ExpectedManifestSha256 -InstalledGeneratedFiles $ticket.plan.generated_files
            # Emit the original binding before the first registry action. Recovery
            # requires this external digest; it must not be guessed from the journal.
            Write-Host ('Candidate prepared journal: '+$ticket.journal_root)
            Write-Host ('Retain PreparedSha256: '+$ticket.prepared_sha256)
            $workerArguments=@{Context=$context;Ticket=$ticket;PackageRoot=$PackageRoot;ExpectedManifestSha256=$ExpectedManifestSha256;
                InstallerPath=$InstallerPath;ReceiptPath=$ReceiptPath;Coordinator=$coordinator}
            try{
                Invoke-MaintenanceWorker -Action Register @workerArguments
                $null=Get-MaintenanceRegistration $context $ticket.plan $PackageRoot 'Partial'
                Assert-MaintenancePeerProtection $protection
                Assert-MaintenanceDefaultInput $ticket.plan.default_input
                $runtime=Start-MaintenanceRuntime $ticket.plan
                $runtimeReady=Test-MaintenanceRuntime $runtime
                Invoke-MaintenanceWorker -Action PublishMarkers @workerArguments
                $null=Get-MaintenanceRegistration $context $ticket.plan $PackageRoot 'Present'
                $runtimeReady=Test-MaintenanceRuntime $runtime
                Assert-MaintenancePeerProtection $protection
                Assert-MaintenanceDefaultInput $ticket.plan.default_input
                $opened=Read-MaintenancePreparedPlan $context $ticket.journal_root $ticket.prepared_sha256
                try{
                    $null=Test-MaintenanceInstalledFiles $opened.plan
                    if($opened.store.Has('commit.bin') -or $opened.store.Has('terminal.bin')){throw 'Unexpected prior decision before first install commit.'}
                    Publish-MaintenanceDecision $opened.store 'commit.bin' $ticket.prepared_sha256 'installed'
                    Publish-MaintenanceDecision $opened.store 'terminal.bin' $ticket.prepared_sha256 'install-complete'
                }finally{$opened.store.Dispose()}
                return New-MaintenanceOutcome $Mode 'install-complete' $ticket $runtimeReady
            }catch{
                Save-RimePimeMaintenanceFailure -Failure $_ -Phase 'install-original'
                $original=$_.Exception.Message
                # A published install commit is never changed into rollback.
                $opened=Read-MaintenancePreparedPlan $context $ticket.journal_root $ticket.prepared_sha256
                try{$commit=Get-MaintenanceDecision $opened.store 'commit.bin' $ticket.prepared_sha256 @('installed')}
                finally{$opened.store.Dispose()}
                if($null -ne $commit){throw ('Install commit is durable; resume forward verification. '+$original)}
                try{
                    Complete-MaintenanceRemoval $context $ticket $workerArguments $runtime $installed
                    $installed=$null
                    $runtime=$null
                }catch{Save-RimePimeMaintenanceFailure -Failure $_ -Phase 'rollback';throw ('Install failed: '+$original+'; rollback incomplete, retain plan '+$ticket.prepared_sha256+': '+$_.Exception.Message)}
                throw ('Install failed and its native transaction rolled back: '+$original+'; retained plan '+$ticket.prepared_sha256)
            }
        }
        if(-not $PreparedSha256){throw 'Remove/Resume requires the original externally retained PreparedSha256.'}
        $journals=@(Get-ChildItem -LiteralPath $context.authorization.recovery_root -Directory -Filter 'install-*' -ErrorAction Stop)
        if($journals.Count -ne 1){throw 'Exactly one retained install journal is required; no automatic choice among histories.'}
        $opened=Read-MaintenancePreparedPlan $context $journals[0].FullName $PreparedSha256
        try{
            $ticket=[pscustomobject]@{journal_root=$opened.journal_root;prepared_sha256=$PreparedSha256;plan=$opened.plan}
            if($ticket.plan.manifest_sha256 -cne $ExpectedManifestSha256){throw 'Recovery candidate differs from installed source manifest.'}
            $commit=Get-MaintenanceDecision $opened.store 'commit.bin' $PreparedSha256 @('installed')
            $terminal=Get-MaintenanceDecision $opened.store 'terminal.bin' $PreparedSha256 @('install-complete','rolled-back')
            if(($terminal -and $terminal.disposition -ceq 'install-complete' -and -not $commit) -or
                ($terminal -and $terminal.disposition -ceq 'rolled-back' -and $commit)){throw 'Install decisions contradict one another.'}
        }finally{$opened.store.Dispose()}
        $workerArguments=@{Context=$context;Ticket=$ticket;PackageRoot=$PackageRoot;ExpectedManifestSha256=$ExpectedManifestSha256;
            InstallerPath=$InstallerPath;ReceiptPath=$ReceiptPath;Coordinator=$coordinator}
        $removal=Open-MaintenanceRemoval $ticket
        if($removal){$removal.store.Dispose()}
        if($Mode -eq 'Resume' -and $commit -and $null -eq $removal){
            # Existing removal intent always takes priority over the older install
            # commit. Only a never-removed committed install may resume Runtime.
            $null=Test-MaintenanceInstalledFiles $ticket.plan
            $installed=Open-MaintenanceCandidate -PackageRoot $ticket.plan.install_root -ExpectedManifestSha256 $ExpectedManifestSha256 -InstalledGeneratedFiles $ticket.plan.generated_files
            $null=Get-MaintenanceRegistration $context $ticket.plan $PackageRoot 'Present'
            Assert-MaintenancePeerProtection $protection
            Assert-MaintenanceDefaultInput $ticket.plan.default_input
            $runtime=Resume-MaintenanceRuntime $ticket.plan
            $runtimeReady=Test-MaintenanceRuntime $runtime
            $opened=Read-MaintenancePreparedPlan $context $ticket.journal_root $PreparedSha256
            try{if(-not $terminal){Publish-MaintenanceDecision $opened.store 'terminal.bin' $PreparedSha256 'install-complete'}}
            finally{$opened.store.Dispose()}
            return New-MaintenanceOutcome $Mode 'install-complete' $ticket $runtimeReady
        }
        Complete-MaintenanceRemoval $context $ticket $workerArguments $null
        return New-MaintenanceOutcome $Mode $(if($commit){'remove-complete'}else{'rolled-back'}) $ticket $null

    }finally{
        try{if($protection){Complete-MaintenancePeerProtection $protection}}finally{
        if($installed){Close-MaintenanceCandidate $installed}
        if($package){Close-MaintenanceCandidate $package};if($context){Close-MaintenanceAuthorization $context}
        if($coordinator){& $script:CandidateCoordinatorModule {param($c) Close-RimePimeCandidateCoordinator -Context $c} $coordinator}
        }
    }
}
function New-MaintenanceOutcome([string]$Mode,[string]$Disposition,$Ticket,$RuntimeReady){
    [pscustomobject][ordered]@{schema_version='yime-rime-pime-candidate-maintenance-outcome-v1';mode=$Mode;disposition=$Disposition;
        install_root=$Ticket.plan.install_root;retained_journal_root=$Ticket.journal_root;prepared_sha256=$Ticket.prepared_sha256;
        current_runtime_observation=$RuntimeReady;state_and_recovery_retained=$true;unlisted_payload_preserved=$true;
        hardware_power_loss_verified=$false;hostile_same_sid_prevention_verified=$false;directory_metadata_durability_verified=$false;
        installed_acceptance_passed=$false;dp1_u_acceptance_passed=$false;public_release_admitted=$false}
}
Export-ModuleMember -Function Invoke-RimePimeCandidateMaintenance,Invoke-RimePimeCandidateWorker,Save-RimePimeMaintenanceFailure
