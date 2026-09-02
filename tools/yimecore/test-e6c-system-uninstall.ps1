[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'repair-e6c-system-uninstall.ps1') -Raw
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Uninstall repair parse failed'}
$fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Repair-SystemUninstallTransaction'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
foreach($case in @('success','write_failure','readback_mismatch','already_current','missing_value')) {
    $fixture=@{values=[ordered]@{InstallLocation=@{kind=1;value='old'};EstimatedSize=@{kind=4;value=10}};count=0;reads=0}
    $before=[ordered]@{InstallLocation=@{kind=1;value='old'};EstimatedSize=@{kind=4;value=10}}
    $expected=[ordered]@{InstallLocation=@{kind=1;value='new'};EstimatedSize=@{kind=4;value=20}}
    if($case -eq 'already_current'){$expected=$before}
    if($case -eq 'missing_value'){$expected['NoModify']=@{kind=4;value=1}}
    function Set-SystemUninstallValue($Name,$Record) {
        if($Name -notin @('InstallLocation','EstimatedSize')){throw 'Unexpected write'}
        $fixture.count++
        if($case -eq 'write_failure' -and $fixture.count -eq 2){throw 'simulated write failure'}
        $fixture.values[$Name]=$Record
    }
    function Get-SystemUninstallSnapshot {
        $fixture.reads++
        if($case -eq 'readback_mismatch' -and $fixture.reads -eq 1){return $before}
        return $fixture.values
    }
    $failed=$false
    try{$null=Repair-SystemUninstallTransaction $before $expected}catch{$failed=$true}
    if($failed -ne ($case -in @('write_failure','readback_mismatch','missing_value'))){throw "Unexpected transaction outcome: $case"}
    $wanted=if($failed){$before}else{$expected}
    foreach($name in $before.Keys){if($fixture.values[$name].value -cne $wanted[$name].value -or $fixture.values[$name].kind -ne $wanted[$name].kind){throw "Original kind/value not restored: $case/$name"}}
    if($case -eq 'already_current' -and $fixture.count -ne 0){throw 'Unneeded writes'}
}
Write-Host 'System uninstall repair: 5 transaction cases passed with mocked writes.'
# Reproduce the actual native PS 5.1 failure: install metadata is UTF-8 without
# BOM, not the system ANSI codepage. Execute the reader from the real script.
$reader=$ast.Find({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$metadata'},$true)
if(-not $reader){throw 'Missing installed metadata reader'}
$root=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-experiment\metadata-utf8-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$name='Yime '+(-join ([char[]](0x81EA,0x7814,0x6808,0x8BD5,0x9A8C,0x7248)))
[IO.File]::WriteAllText((Join-Path $root 'install-metadata.json'),(@{product_name=$name}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
. ([scriptblock]::Create($reader.Extent.Text))
if($metadata.product_name -cne $name){throw 'BOM-less UTF-8 product name was misdecoded; native preflight would fail.'}
Write-Host 'Native metadata UTF-8 reader regression passed; no system registry writes.'
