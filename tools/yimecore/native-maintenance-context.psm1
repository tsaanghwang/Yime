Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Reuse source-only Win32 observations. This has no installed Rime/PIME dependency.
function Initialize-MaintenanceContextFacts {
    if (-not ('Yime.Dp1UNative.Facts' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot '..\dual-product\rime-pime-dp1u-native-facts.cs')
    }
}
function Get-MaintenanceContextHost {
    Initialize-MaintenanceContextFacts
    [pscustomobject]@{machine=[Environment]::MachineName;architecture=[Yime.Dp1UNative.Facts]::Architecture();
        is64bit=[Environment]::Is64BitProcess;sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;
        process_id=$PID;windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)}
}
function Open-MaintenanceContextProcess([int]$ProcessId) { [Yime.Dp1UNative.Facts]::OpenProcessFacts($ProcessId) }
function Read-MaintenanceContextProcess([int]$ProcessId) {
    Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -Property ProcessId,ParentProcessId,ExecutablePath,CreationDate -ErrorAction Stop
}

function Open-YimeCoreNativeMaintenanceContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetUserSid)
    if ($TargetUserSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw 'Canonical initiating user SID required.' }
    $hostFacts=Get-MaintenanceContextHost
    if ($hostFacts.machine -cne 'MYCOMPUTER' -or $hostFacts.architecture -cne 'x64' -or
        $hostFacts.is64bit -isnot [bool] -or -not $hostFacts.is64bit -or $hostFacts.sid -cne $TargetUserSid) {
        throw 'The local maintenance observer requires MYCOMPUTER, native x64, 64-bit PowerShell and the initiating SID.'
    }
    $leases=New-Object 'Collections.Generic.List[object]'
    try {
        $processId=[int]$hostFacts.process_id; $seen=@{}; $ancestry=@(); $childCreated=[long]::MaxValue; $found=$false
        $explorer=Join-Path $hostFacts.windows 'explorer.exe'
        for ($depth=0;$depth -lt 32;$depth++) {
            if ($processId -le 0 -or $seen.ContainsKey($processId)) { throw 'Missing or cyclic native process ancestry.' }
            $seen[$processId]=$true
            $lease=Open-MaintenanceContextProcess $processId
            $leases.Add($lease)
            if ($lease.PackageQuery -ne 15700 -or $lease.Image -match '(?i)\\WindowsApps\\' -or
                $lease.Sid -cne $TargetUserSid -or $lease.Elevated) { throw 'Packaged, elevated, foreign-SID or unknown native ancestry rejected.' }
            if ($lease.CreationFileTime -le 0 -or $lease.CreationFileTime -gt $childCreated) { throw 'Reused or invalid parent process identity.' }
            $process=Read-MaintenanceContextProcess $processId
            if ($null -eq $process -or $process.ProcessId -ne $processId -or $process.ExecutablePath -ine $lease.Image -or
                [Math]::Abs($process.CreationDate.ToUniversalTime().ToFileTimeUtc()-$lease.CreationFileTime) -gt 10) {
                throw 'Native process identity changed during ancestry capture.'
            }
            if ($depth -eq 0 -and [IO.Path]::GetFileName($lease.Image) -notin @('powershell.exe','pwsh.exe')) {
                throw 'Standalone PowerShell observer required.'
            }
            $ancestry += [pscustomobject][ordered]@{pid=$processId;parent_pid=[int]$process.ParentProcessId;image=$lease.Image;
                sid=$lease.Sid;creation_filetime=$lease.CreationFileTime;package_query=$lease.PackageQuery;elevated=[bool]$lease.Elevated}
            if ($lease.Image -ieq $explorer) { $found=$true;break }
            $childCreated=$lease.CreationFileTime; $processId=[int]$process.ParentProcessId
        }
        if (-not $found) { throw 'Unpackaged same-SID ancestry to the system Explorer was not established.' }
        # Caller retains handles across capture. These prove observed process
        # identities, not atomic registry reads or prevention of same-SID writes.
        [pscustomobject]@{leases=$leases;evidence=[pscustomobject][ordered]@{
            schema_version='yimecore-native-maintenance-context-v1';machine=$hostFacts.machine;architecture='x64';
            sid=$TargetUserSid;ancestry=$ancestry;native_context_observed=$true;execution_authorized=$false}}
    } catch { foreach ($lease in $leases) { $lease.Dispose() };throw }
}

function Close-YimeCoreNativeMaintenanceContext($Context) {
    if ($null -ne $Context) { foreach ($lease in $Context.leases) { $lease.Dispose() } }
}

function Get-MaintenanceObservationParent {
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'YimeCore Recovery Archives'
}
function New-YimeCoreNativeObservationDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputRoot)
    $parent=Get-MaintenanceObservationParent
    $full=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
    if ($OutputRoot -cne $full -or (Split-Path -Parent $full) -ine $parent -or
        (Split-Path -Leaf $full) -cnotmatch '^native-maintenance-[a-zA-Z0-9][a-zA-Z0-9-]{0,95}$') { throw 'Observation output must be a new named direct child of the native recovery archive root.' }
    if (-not (Test-Path -LiteralPath $parent -PathType Container) -or (Test-Path -LiteralPath $full)) { throw 'Observation parent is absent or output already exists.' }
    $cursor=$parent
    while ($cursor) {
        $item=Get-Item -LiteralPath $cursor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Indirect observation path rejected.' }
        if (Test-Path -LiteralPath (Join-Path $cursor '.git')) { throw 'Observation output must be outside Git worktrees.' }
        $cursor=Split-Path -Parent $cursor
    }
    New-Item -ItemType Directory -Path $full -ErrorAction Stop | Out-Null
    return $full
}

Export-ModuleMember -Function Open-YimeCoreNativeMaintenanceContext,Close-YimeCoreNativeMaintenanceContext,New-YimeCoreNativeObservationDirectory
