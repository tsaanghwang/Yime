[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'
$source=Get-Content -LiteralPath $path -Raw
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Installer parse failed'}
$guard=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-UnpackagedTrialMaintenance'},$true)
if(-not $guard){throw 'Missing unpackaged maintenance guard'}
. ([scriptblock]::Create($guard.Extent.Text))
foreach($code in @(15700,122,0,5)) {
    function Get-YimeMaintenancePackageIdentity { return $code }
    function Get-YimeMaintenancePackagedAncestor { return '' }
    $failed=$false
    try { Assert-UnpackagedTrialMaintenance } catch { $failed=$true }
    if($failed -ne ($code -ne 15700)){throw "Package guard failed for result $code"}
}
function Get-YimeMaintenancePackageIdentity { return 15700 }
function Get-YimeMaintenancePackagedAncestor { return 'C:\Program Files\WindowsApps\PackagedCaller\caller.exe' }
$failed=$false
try { Assert-UnpackagedTrialMaintenance } catch { $failed=$true }
if(-not $failed){throw 'A NO_PACKAGE child of a packaged application must not mutate the install'}
$call=$source.IndexOf("if (`$Action -ne 'Plan') { Assert-UnpackagedTrialMaintenance }")
if($call -lt 0 -or $call -gt $source.IndexOf('$maintenanceErrorPath =') -or
    $call -gt $source.IndexOf('    Restart-Elevated')){throw 'Guard must precede elevation and all maintenance writes'}
Write-Host 'Unpackaged maintenance guard: 5 cases passed; no registry or installation writes.'
$scopeSource=Get-Content (Join-Path $PSScriptRoot 'development-scope.ps1') -Raw
$scopeAst=[System.Management.Automation.Language.Parser]::ParseInput($scopeSource,[ref]$tokens,[ref]$errors)
$dataGuard=$scopeAst.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-YimeCoreUnpackagedDataMaintenance'},$true)
if(-not $dataGuard){throw 'Missing data-maintenance guard'}
. ([scriptblock]::Create($dataGuard.Extent.Text))
foreach($case in @('native','packaged_parent','unknown_ancestry')) {
    function Get-CimInstance($ClassName,[string]$Filter) {
        if($case -eq 'unknown_ancestry'){return $null}
        if($Filter -eq "ProcessId=$PID"){return [pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';ParentProcessId=12345678}}
        if($case -eq 'native'){return [pscustomobject]@{Name='explorer.exe';ExecutablePath='C:\Windows\explorer.exe';ParentProcessId=0}}
        return [pscustomobject]@{Name='packaged.exe';ExecutablePath=(Join-Path $env:ProgramFiles 'WindowsApps\App\packaged.exe');ParentProcessId=0}
    }
    $failed=$false
    try{Assert-YimeCoreUnpackagedDataMaintenance}catch{$failed=$true}
    if($failed -ne ($case -ne 'native')){throw "Data maintenance guard failed: $case"}
}
Write-Host 'Data maintenance guard: 3 cases passed; no data writes.'
