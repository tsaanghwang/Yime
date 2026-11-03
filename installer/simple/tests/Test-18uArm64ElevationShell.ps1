$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force

function MustReject([scriptblock]$Case){
    $rejected=$false
    try{& $Case | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe elevation shell accepted'}
}

$arm=[pscustomobject]@{target='windows-arm64'}
$x64=[pscustomobject]@{target='windows-amd64'}
$product=[pscustomobject]@{id='yimecore-18u'}
$shell=(Get-Process -Id $PID).Path
$legacy=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$rejectPe={param([string]$Path) throw 'opposite PE architecture'}
$acceptPe={param([string]$Path) if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'missing test shell'}}

if((Get-SetupShell $product $x64 $shell 7 $rejectPe) -cne $legacy){throw 'x64 elevation path changed'}
if((Get-SetupShell $product $x64 $legacy 5 $rejectPe) -cne $legacy){throw 'x64 PS5 elevation path changed'}
if((Get-SetupShell ([pscustomobject]@{id='yimecore'}) $arm $shell 7 $rejectPe) -cne $legacy){throw 'standard product elevation path changed'}
if((Get-SetupShell $product $arm $shell 7 $acceptPe) -cne $shell){throw 'ARM64 did not select current native PS7'}
# Both host classes exercise the actual PE gate. An x64 CI shell is a real
# negative case, not an ARM64 positive or a skipped contract. The native ARM64
# development host retains the real, non-mocked positive check.
$machine=Get-NativeHostMachine
$actualArm64Positive=$machine.nativeMachine -eq 0xaa64 -and $machine.processMachine -eq 0
if($actualArm64Positive){
    if((Get-SetupShell $product $arm $shell 7) -cne $shell){throw 'ARM64 PE verification rejected current native PS7'}
}else{MustReject {Get-SetupShell $product $arm $shell 7}}
MustReject {Get-SetupShell $product $arm $shell 5 $acceptPe}
MustReject {Get-SetupShell $product $arm $legacy 7 $acceptPe}
MustReject {Get-SetupShell $product $arm $shell 7 $rejectPe}
MustReject {Get-SetupShell $product $arm 'C:\nonexistent-18u-shell\pwsh.exe' 7 $acceptPe}

# The elevated script repeats the process/SID checks before any installed-file
# or registry work. ARM64 mutation requires the protected package-bound native
# launcher; direct script entry cannot perform maintenance.
$setup=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Setup.ps1') -Raw -Encoding UTF8
$packageGate=$setup.IndexOf('Assert-PackageHost $contract')
$sidGate=$setup.IndexOf('if($InitiatingSid -and $InitiatingSid -cne $sid)')
$adminGate=$setup.IndexOf('if($InitiatingSid -and -not $administrator)')
$elevation=$setup.IndexOf('Start-Process -FilePath $setupShell')
$maintenanceGate=$setup.IndexOf('$nativeMaintenance=Assert-NativeMaintenanceEntry')
$bothActions=$setup.IndexOf("`$Action -in @('Install','Uninstall')")
$installedWork=$setup.IndexOf("`$stage='installed product ownership check'")
if($packageGate -lt 0 -or $sidGate -le $packageGate -or $adminGate -le $sidGate -or
   $bothActions -le $adminGate -or $maintenanceGate -le $bothActions -or
   $elevation -le $maintenanceGate -or $installedWork -le $elevation){throw 'Elevated pre-mutation checks changed'}
Write-Output 'PASS ARM64 native PS7 shell selection, opposite-PE refusal, x64 preservation and pre-mutation gate'
Write-Output ('Actual current-process ARM64 positive exercised='+$actualArm64Positive+'; nativeMachine=0x'+$machine.nativeMachine.ToString('x4')+'; processMachine=0x'+$machine.processMachine.ToString('x4')+'; other hosts exercise real opposite-PE refusal, not ARM64 execution acceptance')
