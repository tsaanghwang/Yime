[CmdletBinding()]
param(
    [string]$StateRoot=(Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'),
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$Apply
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
$targetSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$subKey="$targetSid\Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial"
function Invoke-UninstallSystemRegistry([string]$Method,[hashtable]$Values) {
    $arguments=@{hDefKey=[uint32]2147483651;sSubKeyName=$subKey}
    foreach($entry in $Values.GetEnumerator()){$arguments[$entry.Key]=$entry.Value}
    $result=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $Method -Arguments $arguments
    if($null -eq $result.ReturnValue -or $result.ReturnValue -ne 0){throw "System uninstall registry $Method failed: $($result.ReturnValue)"}
    return $result
}
function Get-SystemUninstallSnapshot {
    $enumeration=Invoke-UninstallSystemRegistry 'EnumValues' @{}
    $values=[ordered]@{}
    for($i=0;$i -lt @($enumeration.sNames).Count;$i++) {
        $name=[string]$enumeration.sNames[$i]
        $kind=[int]$enumeration.Types[$i]
        if($kind -notin @(1,4)){throw "Refusing to alter uninstall metadata with unsupported original registry kind: $name/$kind"}
        $method=if($kind -eq 1){'GetStringValue'}else{'GetDWORDValue'}
        $read=Invoke-UninstallSystemRegistry $method @{sValueName=$name}
        $value=if($kind -eq 1){[string]$read.sValue}else{[uint32]$read.uValue}
        $values[$name]=@{kind=$kind;value=$value}
    }
    return $values
}
function Set-SystemUninstallValue([string]$Name,$Record) {
    if($Name -notin @('DisplayName','DisplayVersion','Publisher','InstallLocation','UninstallString','QuietUninstallString','NoModify','NoRepair','EstimatedSize')){throw "Unapproved uninstall value: $Name"}
    $args=@{sValueName=$Name}
    if($Record.kind -eq 1){$method='SetStringValue';$args.sValue=[string]$Record.value}
    elseif($Record.kind -eq 4){$method='SetDWORDValue';$args.uValue=[uint32]$Record.value}
    else{throw 'Unsupported registry value kind'}
    $null=Invoke-UninstallSystemRegistry $method $args
}
function Repair-SystemUninstallTransaction($Before,$Expected) {
    $changed=@()
    try {
        foreach($name in $Expected.Keys) {
            if(-not $Before.Contains($name)){throw "Original uninstall value is missing: $name; use a standalone installer instead"}
            if($Before[$name].kind -ne $Expected[$name].kind -or $Before[$name].value -cne $Expected[$name].value) {
                $changed+=@($name)
                Set-SystemUninstallValue $name $Expected[$name]
            }
        }
        $after=Get-SystemUninstallSnapshot
        foreach($name in $Expected.Keys) {
            if($after[$name].kind -ne $Expected[$name].kind -or $after[$name].value -cne $Expected[$name].value){throw "System uninstall readback mismatch: $name"}
        }
        return @{changed_names=$changed;after=$after}
    }catch {
        $original=$_.Exception.Message
        foreach($name in $changed){Set-SystemUninstallValue $name $Before[$name]}
        $restored=Get-SystemUninstallSnapshot
        foreach($name in $changed){if($restored[$name].kind -ne $Before[$name].kind -or $restored[$name].value -cne $Before[$name].value){throw "Repair failed: $original; rollback mismatch: $name"}}
        throw "Repair failed and original changed values restored: $original"
    }
}
$output=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'Refusing to overwrite uninstall repair evidence'}
# Only accept a real manifest-verified installation whose machine COM already
# points to this DLL. No COM, TIP, production key or default-IME writes occur.
$config=Get-Content (Join-Path $StateRoot 'runtime-config.json') -Raw -Encoding UTF8|ConvertFrom-Json
$root=[IO.Path]::GetFullPath([string]$config.install_root)
$prefix=(Join-Path $env:ProgramFiles 'YimeCore Experimental Trial\')
if(-not $root.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFullPath([string]$config.state_root) -ine [IO.Path]::GetFullPath($StateRoot)){throw 'Invalid trial configuration'}
$manifestPath=Join-Path $root 'package-manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($record in $manifest.files) {
    $payload=[IO.Path]::GetFullPath((Join-Path $root $record.path))
    if(-not $payload.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $payload).Hash -ine $record.sha256){throw "Invalid payload: $($record.path)"}
}
$com=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
    hDefKey=[uint32]2147483650;sSubKeyName='SOFTWARE\Classes\CLSID\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}\InprocServer32';sValueName=''
}
if($com.ReturnValue -ne 0 -or $com.sValue -ine (Join-Path $root 'x64\YimeTextServiceExperiment.dll')){throw 'System COM does not identify this installed package'}
$installedScript=Join-Path $root 'maintenance\Manage-YimeCoreTrial.ps1'
if(-not (Test-Path -LiteralPath $installedScript)){throw 'Installed maintenance script is missing'}
# The installer writes UTF-8 without BOM. Windows PowerShell 5.1 otherwise
# decodes this as the ANSI codepage and falsely rejects the Chinese product name.
$metadata=Get-Content (Join-Path $root 'install-metadata.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($metadata.product_key -ne 'YimeCoreExperimentalTrial' -or $metadata.install_root -ine $root -or
    $metadata.package_manifest_sha256 -ine (Get-FileHash -LiteralPath $manifestPath).Hash){throw 'Installed metadata does not match this package'}
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command='"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Action Uninstall -StateRoot "{2}" -TargetUserSid "{3}"' -f $shell,$installedScript,([IO.Path]::GetFullPath($StateRoot)),$targetSid
$expected=[ordered]@{}
$strings=[ordered]@{DisplayName=[string]$metadata.product_name;DisplayVersion=([string]$manifest.git_commit).Substring(0,12);Publisher='Yime';InstallLocation=$root;UninstallString=$command;QuietUninstallString=$command+' -Quiet'}
foreach($name in $strings.Keys){$expected[$name]=@{kind=1;value=$strings[$name]}}
$expected.NoModify=@{kind=4;value=[uint32]1};$expected.NoRepair=@{kind=4;value=[uint32]1}
$expected.EstimatedSize=@{kind=4;value=[uint32][math]::Ceiling((Get-ChildItem -LiteralPath $root -Recurse -File|Measure-Object Length -Sum).Sum/1KB)}
$before=Get-SystemUninstallSnapshot
foreach($name in $expected.Keys){if(-not $before.Contains($name)){throw "Original uninstall value is missing: $name"}}
$evidence=[ordered]@{schema_version='yimecore-system-uninstall-repair-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;target_user_sid=$targetSid;
    registry_reader='StdRegProv/HKEY_USERS';subkey=$subKey;before=$before;expected=$expected;applied=[bool]$Apply;passed=$false;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash}
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force|Out-Null
$evidence|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding utf8
try {
    if($Apply){$result=Repair-SystemUninstallTransaction $before $expected;$evidence.changed_names=$result.changed_names}
    $after=Get-SystemUninstallSnapshot
    $evidence.after=$after
    $evidence.passed=$true
    foreach($name in $expected.Keys){if($after[$name].kind -ne $expected[$name].kind -or $after[$name].value -cne $expected[$name].value){$evidence.passed=$false}}
}catch {$evidence.error=$_.Exception.Message;throw}
finally {$evidence|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding utf8}
if(-not $evidence.passed){throw 'System-visible uninstall metadata does not match installed package; no repair requested'}
Write-Host "System-visible uninstall metadata verified: $output"
