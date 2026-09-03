[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Name}
foreach($spec in @(
    @{file='invoke-local-product-native-install.ps1';names=@('Require-CutoverValue','Assert-CutoverRegistry')},
    @{file='repair-local3-registration.ps1';names=@('Same-RepairValue','Get-ProfileValues','Get-RepairOperations')})) {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $spec.file),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "parse $($spec.file)"
    foreach($name in $spec.names){
        $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}
$archive='C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-075343-65e06cb5'
$before=Get-Content -LiteralPath (Join-Path $archive 'system-before.json') -Raw -Encoding UTF8|ConvertFrom-Json
$damaged=Get-Content -LiteralPath (Join-Path $archive 'system-after.json') -Raw -Encoding UTF8|ConvertFrom-Json
$summary=Get-Content -LiteralPath (Join-Path $archive 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
$installed=$summary.planned_install_root
# The successfully replaced local.3 directory is expected to be gone. The
# historical regression needs only the stable product display contract.
$displayName=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product.json') -Raw -Encoding UTF8|ConvertFrom-Json).display_name
$expectedSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$state=Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'
$frozenKey='SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$profile='{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$ops=@(Get-RepairOperations $damaged)
Check ($ops.Count -eq 3 -and ($ops.name -join ',') -ceq 'OneDrive,Description,IconFile') 'real failed evidence proposes exactly three values'
Check ($ops[0].hive -eq 'Users' -and $ops[1].hive -eq 'LocalMachine') 'restore paths keep the exact hive and original user SID'
Reject {Assert-CutoverRegistry $before $damaged $installed $displayName $expectedSid $state} 'unchanged strict validator still rejects original real damage'
function Clone($Object){return ($Object|ConvertTo-Json -Depth 40|ConvertFrom-Json)}
$fixed=Clone $damaged
$fixed.protected.other_autostart_values=$before.protected.other_autostart_values
foreach($v in (Get-ProfileValues $fixed)) {
    $orig=@((Get-ProfileValues $before)|Where-Object{$_.name -ceq $v.name})[0]
    $v.value=$orig.value;$v.kind=$orig.kind
}
Check (@(Get-RepairOperations $fixed).Count -eq 0) 'already restored values require no writes'
foreach($name in @('Description','IconFile')) {
    $bad=Clone $damaged
    $value=@((Get-ProfileValues $bad)|Where-Object{$_.name -ceq $name})[0]
    $value.value='independent new choice'
    Reject {Get-RepairOperations $bad} "reject independently changed $name"
}
$bad=Clone $damaged
$bad.protected.other_autostart_values=@(@{name='OneDrive';kind=1;value='new independent setting'})
Reject {Get-RepairOperations $bad} 'do not overwrite independent OneDrive setting'
$bad=Clone $damaged
$bad.protected.default_override='changed'
Reject {Get-RepairOperations $bad} 'default input method drift is not waived by repair'
$bad=Clone $damaged
$bad.protected.other_autostart_values=@(@{name='UnexpectedApp';kind=1;value='new'})
Reject {Get-RepairOperations $bad} 'other unrelated Run drift is not silently normalized'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'repair-local3-registration.ps1') -Raw -Encoding UTF8
Check ($source -notmatch '\b(Stop-Process|Restart-Computer|Remove-ItemProperty|New-ItemProperty|DeleteValue|DeleteSubKeyTree)\b') 'repair cannot stop runtime reboot delete values or use blanket registry recreation'
Check ($source.Contains('$key.SetValue($op.name,[string]$op.restore.value,[Microsoft.Win32.RegistryValueKind]::String)')) 'repair uses only exact string value writes'
Check ($source.IndexOf('Assert-YimeCoreUnpackagedDataMaintenance') -lt $source.IndexOf('Start-Process')) 'native ancestry required before repair UAC'
Check ($source.Contains('sourceHash -cne $ExpectedSourcesHash') -and $source.Contains('source_set_sha256=$sourceHash')) 'repair source content is bound across UAC'
Check ($source.Contains('installed_maintenance_source_fixed=$false') -and $source.Contains('local_product_ready=$false')) 'three-value recovery cannot claim installed source or product closure'
$out=Join-Path (Join-Path $PSScriptRoot '..\..\.tmp\yimecore-local-product') ('local3-repair-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();actual_registry_writes=$false;native_repair_executed=$false}|
    ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) local.3 repair contracts. Evidence: $out"
