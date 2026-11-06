[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ReceiptPath,
    [switch]$CheckOnly = $true
)

# Default is read-only preparation. Only an explicit CheckOnly=false registers.
# No installer invocation, reboot, elevation, product startup change, or rearming.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$delivery = 'C:\dev\Yime-deliveries\18u-binding-636cef68-20261106'
$launcher = Join-Path $delivery '开始安装18u修复版.cmd'
$valueName = 'Yime18uRepair-636cef68'
$runOnceKey = 'Software\Microsoft\Windows\CurrentVersion\RunOnce'
$command = '"C:\Windows\System32\cmd.exe" /d /c ""' + $launcher + '""'
$pins = [ordered]@{
    '开始安装18u修复版.cmd' = '12a4ca79dd00c443bce1623f94e142ef726e95ed2c3f7c3d2f0095903209d490'
    'run_18u_binding_install.py' = '98b80e6ba5afe659714b9a0003f9a741c55a6cf5aa5332510bd0c778823ab218'
    'package\YimeMaintenance.exe' = '36d655beca9f5bcca485ee9d143ce9a7c2d8c9fb79218a4506f516000832b2b9'
    'package\maintenance-plan.json' = '60f1ea319de814858086dd1383a521389bb1cc7aa57870005f0f37ccd6b55180'
    'package\payload\installed-18u-product.json' = 'd536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be'
}

function Assert-PlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    $full = $cursor
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $entry = Get-Item -LiteralPath $cursor -Force
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw ('Reparse path refused: ' + $cursor)
            }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function Invoke-Provider([string]$Method, [hashtable]$Arguments) {
    # StdRegProv runs out of process, avoiding a packaged caller's registry view.
    Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $Method -Arguments $Arguments
}

function Get-TargetValue([hashtable]$Address, [string]$Name) {
    $listed = Invoke-Provider 'EnumValues' $Address
    if ($listed.ReturnValue -eq 2) { return [ordered]@{exists=$false} }
    if ($listed.ReturnValue -ne 0) { throw ('RunOnce enumeration failed: ' + $listed.ReturnValue) }
    $names = @($listed.sNames)
    $types = @($listed.Types)
    for ($i=0; $i -lt $names.Count; $i++) {
        if ([string]::Equals([string]$names[$i], $Name, [StringComparison]::OrdinalIgnoreCase)) {
            if ($types[$i] -ne 1) { return [ordered]@{exists=$true;type=[int]$types[$i];value=$null} }
            $args = $Address.Clone(); $args.sValueName = $Name
            $read = Invoke-Provider 'GetStringValue' $args
            if ($read.ReturnValue -ne 0) { throw ('RunOnce value read failed: ' + $read.ReturnValue) }
            return [ordered]@{exists=$true;type=1;value=[string]$read.sValue}
        }
    }
    return [ordered]@{exists=$false}
}

function Save-Receipt {
    $script:record.updatedUtc = [DateTime]::UtcNow.ToString('o')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($script:record | ConvertTo-Json -Depth 8) + "`n")
    $script:receiptStream.Position = 0
    $script:receiptStream.SetLength(0)
    $script:receiptStream.Write($bytes, 0, $bytes.Length)
    $script:receiptStream.Flush($true)
}

$receiptFull = Assert-PlainPath $ReceiptPath
if (-not [string]::Equals([IO.Path]::GetDirectoryName($receiptFull), [IO.Path]::GetFullPath($PSScriptRoot), [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($receiptFull) -ne '.json') {
    throw 'ReceiptPath must be a new JSON file beside this script.'
}
# CreateNew preserves every old receipt, including failed registration evidence.
$script:receiptStream = [IO.File]::Open($receiptFull, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$script:record = [ordered]@{
    schema='18u-next-logon-registration-v1'; startedUtc=[DateTime]::UtcNow.ToString('o'); updatedUtc=$null
    sourceCommit='636cef681ee995a21a9c45fd750f8cb4b0acb4a1'; version='0.2.0-18u-arm64.5'
    checkOnly=[bool]$CheckOnly; status='started'; currentSid=$null; elevated=$null; elevationType=$null
    logicalKey=('HKCU\'+$runOnceKey); providerKey=$null; valueName=$valueName; command=$command
    commandLength=$command.Length; checkedFiles=@(); before=$null; beforeWrite=$null; after=$null
    addedByThisCall=$false; containerEnsured=$false; rollback=$null; error=$null
    installLaunched=$false; rebootRequested=$false; receipt=$receiptFull
}
$added = $false
$failure = $null
$address = $null
$mutex = $null
$mutexHeld = $false
try {
    Save-Receipt
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class NextLogonIdentity {
    public sealed class Snapshot { public string Sid; public bool Elevated; public int ElevationType; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr data, int size, out int needed);
    static int Dword(IntPtr token, int kind) {
        IntPtr data=Marshal.AllocHGlobal(4);
        try { int n; if(!GetTokenInformation(token,kind,data,4,out n)) throw new System.ComponentModel.Win32Exception(); return Marshal.ReadInt32(data); }
        finally { Marshal.FreeHGlobal(data); }
    }
    public static Snapshot Read() {
        IntPtr token;
        if(!OpenProcessToken(GetCurrentProcess(),8,out token)) throw new System.ComponentModel.Win32Exception();
        try {
            int n; GetTokenInformation(token,1,IntPtr.Zero,0,out n);
            if(n<=0) throw new System.ComponentModel.Win32Exception();
            IntPtr data=Marshal.AllocHGlobal(n);
            try {
                if(!GetTokenInformation(token,1,data,n,out n)) throw new System.ComponentModel.Win32Exception();
                return new Snapshot { Sid=new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value,
                    Elevated=Dword(token,20)!=0, ElevationType=Dword(token,18) };
            } finally { Marshal.FreeHGlobal(data); }
        } finally { CloseHandle(token); }
    }
}
'@
    $identity = [NextLogonIdentity]::Read()
    $record.currentSid = $identity.Sid; $record.elevated = $identity.Elevated; $record.elevationType = $identity.ElevationType
    if ($identity.Elevated -or $identity.ElevationType -ne 3) {
        throw 'A non-elevated TokenElevationTypeLimited account is required; no startup value was written.'
    }
    $address = @{hDefKey=[uint32]2147483651; sSubKeyName=($identity.Sid+'\'+$runOnceKey)}
    $record.providerKey = 'HKEY_USERS\'+$address.sSubKeyName
    $mutex = [Threading.Mutex]::new($false, ('Local\Yime18uRepair-636cef68-'+$identity.Sid))
    try { $mutexHeld = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $mutexHeld=$true }
    if (-not $mutexHeld) { throw 'Another registration check is in progress.' }
    if ($command.Length -gt 260 -or $valueName.StartsWith('!') -or $valueName.StartsWith('*')) {
        throw 'Invalid one-time launch command or name.'
    }
    foreach ($member in $pins.Keys) {
        $path = Assert-PlainPath (Join-Path $delivery $member)
        if (-not [IO.File]::Exists($path)) { throw ('Missing fixed entry file: '+$member) }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $pins[$member]) { throw ('Fixed entry hash mismatch: '+$member) }
        $record.checkedFiles += [ordered]@{path=$path;sha256=$actual}
    }
    $cmdBytes = [IO.File]::ReadAllBytes($launcher)
    $cr=0; $lf=0
    for ($i=0; $i -lt $cmdBytes.Length; $i++) {
        if ($cmdBytes[$i] -eq 13) { $cr++; if ($i+1 -ge $cmdBytes.Length -or $cmdBytes[$i+1] -ne 10) { throw 'CMD has a lone CR.' } }
        if ($cmdBytes[$i] -eq 10) { $lf++; if ($i -eq 0 -or $cmdBytes[$i-1] -ne 13) { throw 'CMD has a lone LF.' } }
    }
    if ($cmdBytes.Length -ne 1005 -or $cr -ne 20 -or $lf -ne 20) { throw 'Fixed CMD CRLF contract failed.' }
    $attemptPath = Assert-PlainPath (Join-Path $delivery '18u-standard-install-attempt.json')
    if (Test-Path -LiteralPath $attemptPath) { throw 'An installation attempt already exists; preserve it and do not schedule another.' }
    $record.before = Get-TargetValue $address $valueName
    if ($record.before.exists -and ($record.before.type -ne 1 -or $record.before.value -cne $command)) {
        throw 'The unique RunOnce value already has different content or type; it was not overwritten.'
    }
    $record.status = if ($record.before.exists) {'already-registered-identical'} else {'prepared-not-registered'}
    Save-Receipt
    if (-not $CheckOnly -and -not $record.before.exists) {
        # Re-read immediately before the write. Never overwrite a pre-existing value.
        $record.beforeWrite = Get-TargetValue $address $valueName
        if ($record.beforeWrite.exists) {
            if ($record.beforeWrite.type -ne 1 -or $record.beforeWrite.value -cne $command) {
                throw 'RunOnce changed during preparation; no value was written.'
            }
            $record.status = 'already-registered-identical'
        } else {
            if (Test-Path -LiteralPath $attemptPath) { throw 'An installation attempt appeared during preparation.' }
            Save-Receipt
            $created = Invoke-Provider 'CreateKey' $address
            if ($created.ReturnValue -ne 0) { throw ('RunOnce container unavailable: '+$created.ReturnValue) }
            $record.containerEnsured = $true
            $setArgs=$address.Clone(); $setArgs.sValueName=$valueName; $setArgs.sValue=$command
            $written = Invoke-Provider 'SetStringValue' $setArgs
            if ($written.ReturnValue -ne 0) { throw ('RunOnce write failed: '+$written.ReturnValue) }
            $added=$true; $record.addedByThisCall=$true; $record.status='written-awaiting-provider-readback'
            Save-Receipt
            $record.after = Get-TargetValue $address $valueName
            if (-not $record.after.exists -or $record.after.type -ne 1 -or $record.after.value -cne $command) {
                throw 'Out-of-process RunOnce readback did not match.'
            }
            $record.status = 'registered-next-logon-only'
        }
    }
    if ($record.status -eq 'already-registered-identical') {
        $record.after=Get-TargetValue $address $valueName
        if (-not $record.after.exists -or $record.after.type -ne 1 -or $record.after.value -cne $command) {
            throw 'The pre-existing RunOnce value changed during readback; it was not modified.'
        }
    }
    Save-Receipt
} catch {
    $failure = $_.Exception.Message
    $record.status='failed'; $record.error=$failure
    if ($added) {
        # Only this invocation's previously absent, exact value is eligible for rollback.
        # Do not delete the key/container, any other name, or any pre-existing entry.
        try {
            $rollbackCurrent=Get-TargetValue $address $valueName
            if ($rollbackCurrent.exists -and ($rollbackCurrent.type -ne 1 -or $rollbackCurrent.value -cne $command)) {
                throw 'RunOnce content changed after this write; preserve the externally changed value.'
            }
            if (-not $rollbackCurrent.exists) {
                $record.rollback=[ordered]@{attempted=$true;removedNewValue=$false;alreadyAbsent=$true;error=$null}
            } else {
            $deleteArgs=$address.Clone(); $deleteArgs.sValueName=$valueName
            $deleted=Invoke-Provider 'DeleteValue' $deleteArgs
            if ($deleted.ReturnValue -ne 0 -and $deleted.ReturnValue -ne 2) { throw ('DeleteValue failed: '+$deleted.ReturnValue) }
            $remaining=Get-TargetValue $address $valueName
            if ($remaining.exists) { throw 'The newly added value still exists after rollback.' }
            $record.rollback=[ordered]@{attempted=$true;removedNewValue=$true;error=$null}
            }
        } catch {
            $record.rollback=[ordered]@{attempted=$true;removedNewValue=$false;error=$_.Exception.Message}
        }
    } else { $record.rollback=[ordered]@{attempted=$false;removedNewValue=$false;error=$null} }
    Save-Receipt
} finally {
    if ($mutexHeld) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
    $receiptStream.Dispose()
}
$record | ConvertTo-Json -Depth 8
if ($failure) { throw ('One-time registration failed; inspect the preserved receipt: '+$receiptFull+'; '+$failure) }
