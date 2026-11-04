$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root '.generated/exit-signal-contract'
$result=@()
function Get-Process {return $script:fake}
function Get-CimInstance {throw 'Already-exited fixture must not query a provider'}
function Invoke-CimMethod {throw 'Already-exited fixture must not query a provider'}
foreach($name in @('before-cb77','after-completion-wait')){
    $path=if($name -eq 'before-cb77'){Join-Path $out 'source-snapshots/Setup-cb77-before.ps1'}else{Join-Path $root 'installer/simple/Setup.ps1'}
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Source parse failed'}
    $function=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Stop-SetupProductProcesses'},$true))
    if($function.Count -ne 1){throw 'Expected one real source stop function'}
    . ([scriptblock]::Create($function[0].Extent.Text))
    $script:fake=[pscustomobject]@{Id=123;Path='C:\inert-owned-fixture\owned.exe';Handle=[IntPtr]123;HasExited=$true;waits=0;disposed=$false}
    $script:fake|Add-Member ScriptMethod Refresh {}
    $script:fake|Add-Member ScriptMethod WaitForExit {param($Milliseconds);$this.waits++;return $false}
    $script:fake|Add-Member ScriptMethod Dispose {$this.disposed=$true}
    $caught=$null
    try{Stop-SetupProductProcesses ([pscustomobject]@{id='yimecore-18u';exe='unused.exe'}) 'C:\inert-owned-fixture' 'unused-state' 'inert-user'}catch{$caught=$_.Exception.Message}
    $row=[ordered]@{version=$name;fixture='simulated HasExited=true, held-handle wait=false';returnedToFileGate=($null -eq $caught);completionWaits=$script:fake.waits;disposed=$script:fake.disposed;error=$caught}
    if($name -eq 'before-cb77' -and (-not $row.returnedToFileGate -or $row.completionWaits -ne 0)){throw 'Before-source gap was not observed'}
    if($name -ne 'before-cb77' -and ($row.returnedToFileGate -or $row.completionWaits -ne 1)){throw 'Completion wait fix did not block the next gate'}
    $result+=,$row
}
$record=[ordered]@{schema='stop-completion-wait-controlled-comparison-v1';simulatedProcessState=$true;nativeExitCodeSignalEvidence='native-observation.stdout.log';historicalBrokerLockCauseProven=$false;productTouched=$false;results=$result}
[IO.File]::WriteAllText((Join-Path $out 'stop-before-after.json'),($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ($record|ConvertTo-Json -Depth 8)
