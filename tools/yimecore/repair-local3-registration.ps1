[CmdletBinding()]
param([switch]$Execute,[switch]$Worker,[string]$EvidenceRoot,[string]$ExpectedSourcesHash)
$ErrorActionPreference='Stop'
$installed='C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-75485fda5d79-6964099f'
$originalArchive='C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-075343-65e06cb5'
$manifestHash='6964099f48e0b6f534b763728d4a1806e4d4edfb1e7d7053b42c6d78d9fee74a'
$expectedSid='S-1-5-21-2783006668-770716121-2150155084-1001'
$manifestFile=Join-Path $installed 'package-manifest.json'
if((Get-FileHash -LiteralPath $manifestFile).Hash -ine $manifestHash){throw 'Installed candidate changed; this one-time repair no longer applies.'}
$manifest=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('development-scope.ps1','local-maintenance-safety.ps1','local-package-contract.ps1')) {
    $path=Join-Path $installed "maintenance\$name"
    $record=@($manifest.files|Where-Object{$_.path -ceq "maintenance/$name"})
    if($record.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ine $record[0].sha256){throw "Installed helper mismatch: $name"}
    . $path
}
$null=Get-YimeCoreDevelopmentScope
if($Execute){Assert-YimeCoreUnpackagedDataMaintenance}
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid){throw 'Use the original Windows account.'}
$administrator=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Execute -and $PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if($Execute -and $administrator -and -not $Worker){throw 'Use normal File Explorer double-click, not Run as administrator. The repair requests UAC itself.'}
if(($Worker -or $EvidenceRoot -or $ExpectedSourcesHash) -and -not ($Execute -and $Worker -and $administrator -and $EvidenceRoot -and $ExpectedSourcesHash)){throw 'Incomplete internal repair worker arguments.'}
$acceptanceScript=Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'
$sources=@($PSCommandPath,$acceptanceScript|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
$sha=[Security.Cryptography.SHA256]::Create()
try {$sourceHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sources|ConvertTo-Json -Compress))))).Replace('-','').ToLowerInvariant()}
finally {$sha.Dispose()}
# Import only these read-only functions, never the installation script body.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($acceptanceScript,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Get-CutoverRegistrySnapshot','Require-CutoverValue','Assert-CutoverRegistry')) {
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing read-only validator: $name"}
    . ([scriptblock]::Create($fn.Extent.Text))
}
$archiveBase=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'
trap {
    $bootstrapError=$_
    try {
        if($Execute -and $Worker -and $EvidenceRoot) {
            $safeRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
            Assert-YimeCorePlainPath $safeRoot
            if((Split-Path -Parent $safeRoot) -ieq $archiveBase -and (Split-Path -Leaf $safeRoot) -match '^local3-registration-repair-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$' -and
                (Test-Path -LiteralPath (Join-Path $safeRoot 'initiator.json')) -and -not (Test-Path -LiteralPath (Join-Path $safeRoot 'summary.json'))) {
                [ordered]@{passed=$false;stage='worker-preflight';failure=$bootstrapError.Exception.Message;source_set_sha256=$sourceHash;
                    install_executed=$false;user_data_written=$false}|ConvertTo-Json -Depth 8|
                    Set-Content -LiteralPath (Join-Path $safeRoot 'summary.json') -Encoding UTF8
            }
        }
    } catch {}
    Write-Error $bootstrapError -ErrorAction Continue
    exit 1
}
$frozenKey='SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$profile='{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
function Read-PinnedOriginal([string]$Name,[string]$Hash) {
    $path=Join-Path $originalArchive $Name
    $null=Assert-YimeCoreNativeFile $path
    if((Get-FileHash -LiteralPath $path).Hash -ine $Hash){throw "Original evidence changed: $Name"}
    Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
}
$before=Read-PinnedOriginal 'system-before.json' '4ff1f84f29b442f006ae6a76c849d4ea1636b18ca20de56f695624ba3c03c67e'
$damaged=Read-PinnedOriginal 'system-after.json' '0464c9f62b8293baf20f1cbd67a2c163c7409debd78ae9473b0f5ecb061271d0'
function Get-ProfileValues($Snapshot){$Snapshot.protected.$frozenKey.children.LanguageProfile.children.'0x00000804'.children.$profile.values}
function Same-RepairValue($Left,$Right){return (($Left|ConvertTo-Json -Depth 6 -Compress) -ceq ($Right|ConvertTo-Json -Depth 6 -Compress))}
function Get-RepairOperations($Current) {
    $operations=@()
    $old=@($before.protected.other_autostart_values|Where-Object{$_.name -ceq 'OneDrive'})
    if($old.Count -ne 1 -or $old[0].kind -ne 1){throw 'No exact original OneDrive string in pinned evidence.'}
    $actual=@($Current.protected.other_autostart_values|Where-Object{$_.name -ceq 'OneDrive'})
    if($actual.Count -gt 1 -or ($actual.Count -eq 1 -and -not (Same-RepairValue $actual[0] $old[0]))){throw 'OneDrive changed independently; refuse overwrite.'}
    if(-not $actual.Count){$operations+=@([ordered]@{hive='Users';path="$expectedSid\Software\Microsoft\Windows\CurrentVersion\Run";name='OneDrive';expected=$null;restore=$old[0]})}
    foreach($name in @('Description','IconFile')) {
        $oldValue=@((Get-ProfileValues $before)|Where-Object{$_.name -ceq $name})
        $badValue=@((Get-ProfileValues $damaged)|Where-Object{$_.name -ceq $name})
        $now=@((Get-ProfileValues $Current)|Where-Object{$_.name -ceq $name})
        if($oldValue.Count -ne 1 -or $badValue.Count -ne 1 -or $now.Count -ne 1 -or $oldValue[0].kind -ne 1){throw "Frozen original/current value is not exact: $name"}
        if(Same-RepairValue $now[0] $oldValue[0]){continue}
        if(-not (Same-RepairValue $now[0] $badValue[0])){throw "Frozen $name changed independently; refuse overwrite."}
        $operations+=@([ordered]@{hive='LocalMachine';path="$frozenKey\LanguageProfile\0x00000804\$profile";name=$name;expected=$badValue[0];restore=$oldValue[0]})
    }
    # Project ONLY the three authorized old values. If anything else differs,
    # the original strict protection guard must still fail before any write.
    $projected=$Current|ConvertTo-Json -Depth 40|ConvertFrom-Json
    $projected.protected.other_autostart_values=@($projected.protected.other_autostart_values|Where-Object{$_.name -cne 'OneDrive'})+@($old[0])
    $projected.protected.other_autostart_values=@($projected.protected.other_autostart_values|Sort-Object name)
    $originalValues=@(Get-ProfileValues $before)
    foreach($name in @('Description','IconFile')) {
        $desired=@($originalValues|Where-Object{$_.name -ceq $name})[0]
        $now=@((Get-ProfileValues $projected)|Where-Object{$_.name -ceq $name})[0]
        $now.value=$desired.value;$now.kind=$desired.kind
    }
    Assert-CutoverRegistry $before $projected $installed $displayName $expectedSid $state
    return $operations
}
function Write-RepairJson($Value,[string]$Name){$Value|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $EvidenceRoot $Name) -Encoding UTF8}
$validated=Assert-LocalProductPackage $installed
$displayName=[string]$validated.descriptor.display_name
$current=Get-CutoverRegistrySnapshot
$operations=@(Get-RepairOperations $current)
if(-not $Execute){
    [ordered]@{action='repair-plan-only';original_archive=$originalArchive;candidate_manifest_sha256=$manifestHash;
        operations=$operations;writes_requested=$false;no_install_stop_data_or_reboot=$true}|ConvertTo-Json -Depth 8
    exit 0
}
if(-not $Worker) {
    $EvidenceRoot=Join-Path $archiveBase ('local3-registration-repair-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    Assert-YimeCorePlainPath $EvidenceRoot
    if(Test-Path -LiteralPath $EvidenceRoot){throw 'Repair archive must be new.'}
    New-Item -ItemType Directory -Path $EvidenceRoot|Out-Null
    Write-RepairJson ([ordered]@{sid=$expectedSid;sources=$sources;source_set_sha256=$sourceHash;manifest_sha256=$manifestHash}) 'initiator.json'
    Write-RepairJson $current 'parent-system-before.json'
    Write-RepairJson $operations 'planned-values.json'
    $workerProcess=$null
    try {
        Write-Host 'Restoring only the original OneDrive Run value and two frozen profile strings. No input-method stop, install, data restore or reboot.'
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Execute -Worker -EvidenceRoot "'+$EvidenceRoot+'" -ExpectedSourcesHash "'+$sourceHash+'"'
        $workerProcess=Start-Process -FilePath $ps -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $workerProcess.WaitForExit()
        $summaryPath=Join-Path $EvidenceRoot 'summary.json'
        if(-not (Test-Path -LiteralPath $summaryPath)){throw "Repair worker exited $($workerProcess.ExitCode) without a summary; preserve $EvidenceRoot"}
        $result=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($workerProcess.ExitCode -ne 0 -or -not $result.passed -or $result.source_set_sha256 -cne $sourceHash){throw "Repair failed: $($result.failure). Preserve $EvidenceRoot"}
        $null=Assert-YimeCoreNativeFile $summaryPath
        Write-Host "PASS: original OneDrive autostart and frozen profile restored; no stop, install, user-data change or reboot. Evidence: $EvidenceRoot"
    } catch {Write-RepairJson ([ordered]@{message=$_.Exception.Message;stack=$_.ScriptStackTrace}) 'parent-failure.json';throw}
    finally {if($workerProcess){$workerProcess.Dispose()}}
    exit 0
}
$EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
if((Split-Path -Parent $EvidenceRoot) -ine $archiveBase -or (Split-Path -Leaf $EvidenceRoot) -notmatch '^local3-registration-repair-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'Unexpected repair evidence root.'}
Assert-YimeCorePlainPath $EvidenceRoot
$origin=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'initiator.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($sourceHash -cne $ExpectedSourcesHash -or $origin.source_set_sha256 -cne $sourceHash -or $origin.sid -cne $expectedSid -or $origin.manifest_sha256 -cne $manifestHash){throw 'Repair source or initiating user changed across UAC.'}
if(Test-Path -LiteralPath (Join-Path $EvidenceRoot 'summary.json')){throw 'Do not reuse a completed repair archive.'}
$passed=$false;$failure=$null;$written=@()
try {
    Write-RepairJson $current 'system-before.json'
    foreach($op in $operations) {
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]([string]$op.hive),[Microsoft.Win32.RegistryView]::Registry64)
        $key=$null
        try {
            $key=$base.OpenSubKey($op.path,$true)
            if(-not $key){throw "Expected existing repair key missing: $($op.path)"}
            $actual=$null
            if($key.GetValueNames() -ccontains $op.name){$actual=[ordered]@{name=$op.name;kind=[int]$key.GetValueKind($op.name);value=$key.GetValue($op.name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}}
            if(-not (Same-RepairValue $actual $op.expected)){throw "Repair value changed since independent preflight: $($op.name)"}
            # No key creation/deletion, no blanket restore, only pinned strings.
            $key.SetValue($op.name,[string]$op.restore.value,[Microsoft.Win32.RegistryValueKind]::String)
            $written+=@($op)
            Write-RepairJson $written 'written-values.json'
        } finally {if($key){$key.Dispose()};$base.Dispose()}
    }
    $after=Get-CutoverRegistrySnapshot
    Write-RepairJson $after 'system-after.json'
    Assert-CutoverRegistry $before $after $installed $displayName $expectedSid $state
    $passed=$true
} catch {$failure=$_.Exception.Message}
finally {
    Write-RepairJson ([ordered]@{passed=$passed;source_set_sha256=$sourceHash;candidate_manifest_sha256=$manifestHash;
        original_archive=$originalArchive;values_written=$written;failure=$failure;protected_registry_restored=$passed;
        runtime_stopped=$false;install_executed=$false;user_data_written=$false;reboot_requested=$false;
        installed_maintenance_source_fixed=$false;local_product_ready=$false}) 'summary.json'
}
if(-not $passed){exit 1}
