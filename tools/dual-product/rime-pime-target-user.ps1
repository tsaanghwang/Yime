# Rime/PIME target-user identity contract. Definitions only; importing this
# file never elevates, reads the registry, changes a profile or starts a process.

function Assert-YimePimeSidValue {
    param([Parameter(Mandatory)][string]$Sid)
    if ($Sid -cnotmatch '^S-1-(5-21|12-1)-[0-9]+(?:-[0-9]+){2,}$') {
        throw 'Rime/PIME requires one canonical Windows user SID.'
    }
    return $Sid
}

function Get-YimePimePackageIdentityResult {
    if(-not ('YimePimePackageIdentity' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YimePimePackageIdentity {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, IntPtr name);
    public static int Query() {
        uint length = 0;
        return GetCurrentPackageFullName(ref length, IntPtr.Zero);
    }
}
'@
    }
    return [YimePimePackageIdentity]::Query()
}

function Assert-YimePimeUnpackagedExplorerInitiator {
    param([int]$RootProcessId=$PID)
    # APPMODEL_ERROR_NO_PACKAGE is necessary but not sufficient: a breakaway
    # child of a packaged app can report it while retaining a virtualized
    # registry view. Require an unbroken, non-WindowsApps chain to Explorer.
    $packageResult=Get-YimePimePackageIdentityResult
    if($packageResult -ne 15700) {
        throw "Rime/PIME maintenance requires an unpackaged initiator (package query=$packageResult)."
    }
    $windowsAppsPrefix=Join-Path $env:ProgramFiles 'WindowsApps\'
    $processId=$RootProcessId
    $seen=@{}
    for($depth=0;$depth -lt 32 -and $processId -gt 0;$depth++) {
        if($seen.ContainsKey($processId)){throw 'Rime/PIME initiator ancestry contains a cycle.'}
        $seen[$processId]=$true
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
        if($null -eq $process -or [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
            throw 'Rime/PIME initiator ancestry cannot be proven.'
        }
        if(([string]$process.ExecutablePath).StartsWith($windowsAppsPrefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Rime/PIME maintenance cannot start from a packaged application ancestry.'
        }
        if([string]$process.Name -ieq 'explorer.exe'){return $true}
        $processId=[int]$process.ParentProcessId
    }
    throw 'Rime/PIME maintenance requires standalone Windows PowerShell or the installer launched from Explorer.'
}

function Assert-YimePimeElevationEnvelope {
    param(
        [Parameter(Mandatory,Position=0)][string]$InitiatingSid,
        [Parameter(Mandatory,Position=1)][string]$TargetUserSid,
        [Parameter(Mandatory,Position=2)][string]$WorkerSid,
        [Parameter(Mandatory,Position=3)][bool]$InitiatingTokenElevated,
        [Parameter(Mandatory,Position=4)][bool]$WorkerTokenElevated
    )
    $initiator=Assert-YimePimeSidValue $InitiatingSid
    $target=Assert-YimePimeSidValue $TargetUserSid
    $worker=Assert-YimePimeSidValue $WorkerSid
    if ($InitiatingTokenElevated -or -not $WorkerTokenElevated) {
        throw 'Rime/PIME maintenance requires a non-elevated initiator and an elevated worker.'
    }
    if ($initiator -cne $target -or $worker -cne $target) {
        throw 'Elevation changed the initiating SID; no maintenance action is allowed.'
    }
    return [pscustomobject][ordered]@{
        initiating_sid=$initiator
        target_user_sid=$target
        worker_sid=$worker
        initiating_token_elevated=$false
        worker_token_elevated=$true
    }
}

function Assert-YimePimeCorrelationId {
    param([Parameter(Mandatory)][string]$CorrelationId)
    if($CorrelationId -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid target-user correlation identity.'}
    return $CorrelationId
}

function Assert-YimePimeElevationEnvelopePath {
    param([Parameter(Mandatory)][string]$Path,[switch]$RequireExisting)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or
        [IO.Path]::GetFileName($Path) -cne 'rime-pime-target-user-envelope.json'){
        throw 'Target-user elevation envelope must use its private canonical filename.'
    }
    $full=[IO.Path]::GetFullPath($Path)
    if($full -cne $Path -or $full.Substring(2).Contains(':')){throw 'Ambiguous target-user elevation envelope path.'}
    for($cursor=Split-Path -Parent $full;$cursor;$cursor=Split-Path -Parent $cursor){
        if((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
            throw 'Target-user elevation envelope traverses an indirect path.'
        }
        if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
    }
    if($RequireExisting -and -not (Test-Path -LiteralPath $full -PathType Leaf)){
        throw 'Target-user elevation envelope is unavailable.'
    }
    if((Test-Path -LiteralPath $full) -and
        ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Target-user elevation envelope cannot be a reparse point.'
    }
    return $full
}

function New-YimePimeElevationEnvelopeRecord {
    param(
        [Parameter(Mandatory)][string]$InitiatingSid,
        [Parameter(Mandatory)][string]$TargetUserSid,
        [datetime]$CreatedUtc=([datetime]::UtcNow),
        [string]$CorrelationId=([guid]::NewGuid().ToString('N'))
    )
    $sid=Assert-YimePimeSidValue $InitiatingSid
    $target=Assert-YimePimeSidValue $TargetUserSid
    if($sid -cne $target){throw 'Target user differs from the non-elevated initiator.'}
    return [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-target-user-envelope-v1'
        correlation_id=(Assert-YimePimeCorrelationId $CorrelationId)
        initiating_sid=$sid
        target_user_sid=$target
        initiating_token_elevated=$false
        created_utc=$CreatedUtc.ToUniversalTime().ToString('o')
    }
}

function Assert-YimePimeElevationEnvelopeRecord {
    param(
        [Parameter(Mandatory)]$Envelope,
        [Parameter(Mandatory)][string]$CorrelationId,
        [Parameter(Mandatory)][string]$WorkerSid,
        [Parameter(Mandatory)][bool]$WorkerTokenElevated,
        [datetime]$NowUtc=([datetime]::UtcNow)
    )
    if($Envelope.schema_version -cne 'yime-rime-pime-target-user-envelope-v1' -or
        [string]$Envelope.correlation_id -cne (Assert-YimePimeCorrelationId $CorrelationId)){
        throw 'Target-user elevation correlation does not match.'
    }
    $created=[datetime]::Parse([string]$Envelope.created_utc).ToUniversalTime()
    $age=($NowUtc.ToUniversalTime()-$created).TotalMinutes
    if($age -lt -1 -or $age -gt 10){throw 'Target-user elevation envelope is outside its one-time time window.'}
    return Assert-YimePimeElevationEnvelope -InitiatingSid ([string]$Envelope.initiating_sid) `
        -TargetUserSid ([string]$Envelope.target_user_sid) -WorkerSid $WorkerSid `
        -InitiatingTokenElevated:([bool]$Envelope.initiating_token_elevated) `
        -WorkerTokenElevated:$WorkerTokenElevated
}

function New-YimePimeElevationEnvelopeFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$InitiatingSid,
        [Parameter(Mandatory)][string]$TargetUserSid
    )
    $full=Assert-YimePimeElevationEnvelopePath $Path
    if(Test-Path -LiteralPath $full){throw 'Target-user elevation envelope already exists.'}
    $record=New-YimePimeElevationEnvelopeRecord $InitiatingSid $TargetUserSid
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 5 -Compress))
    $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
    return $record
}

function Confirm-YimePimeElevationEnvelopeFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$CorrelationId,
        [Parameter(Mandatory)][string]$WorkerSid,
        [Parameter(Mandatory)][bool]$WorkerTokenElevated,
        [switch]$Consume
    )
    $full=Assert-YimePimeElevationEnvelopePath $Path -RequireExisting
    $item=Get-Item -LiteralPath $full -Force
    if($item.Length -gt 4096){throw 'Target-user elevation envelope exceeds its size bound.'}
    $owner=$item.GetAccessControl().Owner
    try{$ownerSid=([Security.Principal.NTAccount]$owner).Translate([Security.Principal.SecurityIdentifier]).Value}
    catch{$ownerSid=[string]$owner}
    $json=[IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if($ownerSid -cne [string]$json.initiating_sid){throw 'Target-user elevation envelope owner differs from the initiator.'}
    $result=Assert-YimePimeElevationEnvelopeRecord $json $CorrelationId $WorkerSid $WorkerTokenElevated
    if($Consume){Remove-Item -LiteralPath $full -Force -ErrorAction Stop}
    return $result
}

function Get-YimePimeTargetUserRegistryPath {
    param(
        [Parameter(Mandatory,Position=0)][string]$TargetUserSid,
        [Parameter(Mandatory,Position=1)][string]$RelativePath
    )
    $sid=Assert-YimePimeSidValue $TargetUserSid
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath -match '^[\\/]|[/:*?"<>|]|(^|[\\/])\.\.?($|[\\/])') {
        throw 'Target-user registry relative path is ambiguous.'
    }
    return "Registry::HKEY_USERS\$sid\$RelativePath"
}

function Get-YimePimeCurrentTokenObservation {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity.User) { throw 'Current Windows user SID is unavailable.' }
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return [pscustomobject][ordered]@{
        sid=(Assert-YimePimeSidValue $identity.User.Value)
        elevated=[bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}
