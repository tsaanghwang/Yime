[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'native-maintenance-context.psm1') -Force -PassThru
$entry=Join-Path $PSScriptRoot 'capture-native-maintenance-registry.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-native-observer-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Pass,[string]$Name) {if(-not $Pass){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Code,[string]$Name) {$caught=$false;try {& $Code | Out-Null}catch{$caught=$true};Check $caught $Name}
try {
    # Only inspect our own native process/file primitives. Never substitute a fake
    # Win32 type in the actual product/shared namespace.
    & $module { Initialize-MaintenanceContextFacts }
    $self=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID)
    try {Check ($self.Pid -eq $PID -and $self.CreationFileTime -gt 0 -and $self.Image -and $self.Sid) 'real own-process handle provides bounded identity'}finally{$self.Dispose()}
    $result=& $module {
        $script:leases=@();$script:mode='valid'
        function Get-MaintenanceContextHost {
            [pscustomobject]@{machine=if($script:mode -eq 'host'){'OTHER'}else{'MYCOMPUTER'};architecture=if($script:mode -eq 'architecture'){'arm64'}else{'x64'};
                is64bit=($script:mode -ne 'bitness');sid='S-1-5-21-1-2-3-1001';process_id=42;windows='C:\Windows'}
        }
        function Open-MaintenanceContextProcess([int]$ProcessId) {
            $current=($ProcessId -eq 42)
            $value=[pscustomobject]@{Pid=$ProcessId;Image=if($current){'C:\test\powershell.exe'}else{'C:\Windows\explorer.exe'};
                Sid='S-1-5-21-1-2-3-1001';CreationFileTime=if($current){200000000L}else{100000000L};PackageQuery=15700;Elevated=$false;Disposed=$false}
            if($script:mode -eq 'packaged' -and -not $current){$value.PackageQuery=122}
            if($script:mode -eq 'unknown-package'){$value.PackageQuery=5}
            if($script:mode -eq 'windowsapps'){$value.Image='C:\Program Files\WindowsApps\fake\powershell.exe'}
            if($script:mode -eq 'foreign-sid' -and -not $current){$value.Sid='S-1-5-21-4-5-6-1001'}
            if($script:mode -eq 'elevated'){$value.Elevated=$true}
            if($script:mode -eq 'reused-parent' -and -not $current){$value.CreationFileTime=300000000L}
            if($script:mode -eq 'wrong-entry' -and $current){$value.Image='C:\test\cmd.exe'}
            if($script:mode -eq 'fake-explorer' -and -not $current){$value.Image='C:\test\explorer.exe'}
            $value|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$this.Disposed=$true}
            $script:leases+=@($value)
            return $value
        }
        function Read-MaintenanceContextProcess([int]$ProcessId) {
            if($script:mode -eq 'provider-error'){throw 'synthetic CIM error'}
            if($script:mode -eq 'missing-process'){return $null}
            $value=$script:leases[-1]
            [pscustomobject]@{ProcessId=if($script:mode -eq 'wrong-pid'){99}else{$ProcessId};ParentProcessId=if($script:mode -eq 'cycle'){42}elseif($ProcessId -eq 42){10}else{0};
                ExecutablePath=if($script:mode -eq 'changed-image'){'C:\changed.exe'}else{$value.Image};
                CreationDate=[DateTime]::FromFileTimeUtc($value.CreationFileTime+$(if($script:mode -eq 'changed-time'){1000}else{0}))}
        }
        $results=@()
        foreach($mode in @('valid','host','architecture','bitness','packaged','unknown-package','windowsapps','foreign-sid','elevated',
            'reused-parent','wrong-entry','fake-explorer','provider-error','missing-process','wrong-pid','cycle','changed-image','changed-time')) {
            $script:mode=$mode;$script:leases=@();$context=$null;$caught=$false
            try {$context=Open-YimeCoreNativeMaintenanceContext -TargetUserSid 'S-1-5-21-1-2-3-1001'}catch{$caught=$true}
            $retained=if($mode -eq 'valid'){@($script:leases|Where-Object Disposed).Count -eq 0}else{$true}
            if($context){Close-YimeCoreNativeMaintenanceContext $context}
            $released=@($script:leases|Where-Object {-not $_.Disposed}).Count -eq 0
            $results+=[pscustomobject]@{mode=$mode;accepted=($null -ne $context);caught=$caught;retained=$retained;released=$released}
        }
        return $results
    }
    foreach($case in $result) {
        Check ($case.accepted -eq ($case.mode -eq 'valid') -and $case.caught -eq ($case.mode -ne 'valid')) ($case.mode+' uses native identity and rejects unproved context')
        Check ($case.retained -and $case.released) ($case.mode+' holds successful leases and closes every acquired handle')
    }
    Reject {Open-YimeCoreNativeMaintenanceContext -TargetUserSid 'S-1-5-18'} 'system SID cannot initiate user maintenance'
    Reject {Open-YimeCoreNativeMaintenanceContext -TargetUserSid 'S-1-5-21-7-8-9-1001'} 'claimed SID must match observed user'

    # Exercise the actual directory function only within an owned temporary root.
    & $module {param($parent) $script:observationParent=$parent;function script:Get-MaintenanceObservationParent {$script:observationParent}} $root
    $created=New-YimeCoreNativeObservationDirectory -OutputRoot (Join-Path $root 'native-maintenance-positive')
    Check (Test-Path -LiteralPath $created -PathType Container) 'fresh observation child created'
    Reject {New-YimeCoreNativeObservationDirectory -OutputRoot $created} 'existing observation cannot be overwritten'
    Reject {New-YimeCoreNativeObservationDirectory -OutputRoot (Join-Path $root 'other-name')} 'unreviewed observation name rejected'
    Reject {New-YimeCoreNativeObservationDirectory -OutputRoot (Join-Path $root 'nested\native-maintenance-x')} 'nested or escaped output rejected'
    New-Item -ItemType Directory -Path (Join-Path $root '.git') | Out-Null
    Reject {New-YimeCoreNativeObservationDirectory -OutputRoot (Join-Path $root 'native-maintenance-git')} 'Git-worktree observation output rejected'

    $entryTrace=@{reads=0;writes=0;closed=$false;rejected=$false}
    & {
        function Import-Module {}
        function Open-YimeCoreNativeMaintenanceContext {throw 'synthetic native context rejection'}
        function New-YimeCoreNativeObservationDirectory {$entryTrace.writes++;throw 'directory must not be reached'}
        function Get-YimeCoreNativeMaintenanceSnapshot {$entryTrace.reads++;throw 'registry must not be reached'}
        function Close-YimeCoreNativeMaintenanceContext {$entryTrace.closed=$true}
        try {& $entry -Action Capture -OutputRoot 'C:\must-not-touch' -TargetUserSid 'S-1-5-21-1-2-3-1001'}catch{
            if($_.Exception.Message -cne 'synthetic native context rejection'){throw}
            $entryTrace.rejected=$true
        }
    }
    Check ($entryTrace.reads -eq 0 -and $entryTrace.writes -eq 0 -and $entryTrace.closed -and $entryTrace.rejected) 'actual entry rejects context before product provider or output creation'
    $captureFixture=Join-Path $root 'capture-fixture'
    New-Item -ItemType Directory -Path $captureFixture | Out-Null
    $entryTrace=@{closed=$false;provider_failure=$true;rejected=$false}
    & {
        function Import-Module {}
        function Open-YimeCoreNativeMaintenanceContext {[pscustomobject]@{evidence=@{synthetic=$true};leases=@()}}
        function New-YimeCoreNativeObservationDirectory {$captureFixture}
        function Get-YimeCoreNativeMaintenanceSnapshot {throw 'synthetic provider failure'}
        function Close-YimeCoreNativeMaintenanceContext {$entryTrace.closed=$true}
        try {& $entry -Action Capture -OutputRoot $captureFixture -TargetUserSid 'S-1-5-21-1-2-3-1001'}catch{
            if($_.Exception.Message -cne 'synthetic provider failure'){throw};$entryTrace.rejected=$true
        }
    }
    Check ($entryTrace.closed -and $entryTrace.rejected -and -not (Test-Path -LiteralPath (Join-Path $captureFixture 'registry-observation.json'))) 'provider failure closes context without emitting a success artifact'
    $entryTrace.closed=$false
    $receipt=& {
        function Import-Module {}
        function Open-YimeCoreNativeMaintenanceContext {[pscustomobject]@{evidence=@{synthetic=$true};leases=@()}}
        function New-YimeCoreNativeObservationDirectory {$captureFixture}
        function Get-YimeCoreNativeMaintenanceSnapshot {[pscustomobject]@{synthetic=$true;records=@()}}
        function Close-YimeCoreNativeMaintenanceContext {$entryTrace.closed=$true}
        & $entry -Action Capture -OutputRoot $captureFixture -TargetUserSid 'S-1-5-21-1-2-3-1001'
    }
    $receipt=($receipt -join "`n")|ConvertFrom-Json
    $capture=Get-Content -LiteralPath $receipt.path -Raw|ConvertFrom-Json
    Check ($entryTrace.closed -and $receipt.bytes -eq (Get-Item -LiteralPath $receipt.path).Length -and $receipt.sha256 -ceq (Get-FileHash -LiteralPath $receipt.path).Hash.ToLowerInvariant()) 'actual output writer preserves and hashes the same native file handle'
    Check ($capture.context.synthetic -and $capture.registry.synthetic -and -not $capture.execution_authorized -and -not $capture.L6_sealed -and -not $capture.local_product_ready -and -not $capture.maintenance_executed) 'synthetic capture writer cannot promote maintenance or readiness'
    $record=[ordered]@{schema_version='yimecore-native-maintenance-context-test-v1';passed=$true;checks_passed=$checks.Count;checks=$checks.ToArray();
        powershell_version=$PSVersionTable.PSVersion.ToString();native_self_process_observed=$true;positive_explorer_context_synthetic=$true;positive_capture_synthetic=$true;
        product_registry_read=$false;product_or_user_data_read=$false;installer_executed=$false;local_product_ready=$false}
    if($OutputPath){$record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8}
    Write-Host ('PASS: native maintenance context '+$checks.Count+' contracts; own process and temporary output only.')
} finally {
    Remove-Module $module -Force
    $resolved=[IO.Path]::GetFullPath($root)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'yimecore-native-observer-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
}
