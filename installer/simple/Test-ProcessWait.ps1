$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup parse failed'}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wait-SetupExit'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$elevation=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process' -and $node.Extent.Text -match '-Verb RunAs'},$true))
if($elevation.Count -ne 1 -or $elevation[0].Extent.Text -match '-Wait\b'){throw 'Elevation must not wait for the process tree'}
$work=Join-Path ([IO.Path]::GetTempPath()) ('yime-wait-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$childScript=Join-Path $work 'child.ps1'
# The test-owned child exits naturally when its private release file appears.
[IO.File]::WriteAllText($childScript,'param([string]$Release); $end=(Get-Date).AddSeconds(45); while(-not (Test-Path -LiteralPath $Release) -and (Get-Date) -lt $end){Start-Sleep -Milliseconds 100}')
$parentScript=Join-Path $work 'parent.ps1'
[IO.File]::WriteAllText($parentScript,@'
param([string]$Root,[int]$Code)
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -File "'+(Join-Path $Root 'child.ps1')+'" -Release "'+(Join-Path $Root ('release-'+$Code))+'"'
$p=Start-Process -FilePath $ps -ArgumentList $arguments -WindowStyle Hidden -PassThru
[IO.File]::WriteAllText((Join-Path $Root ('child-'+$Code)),[string]$p.Id)
exit $Code
'@)
foreach($expected in @(0,7)){
    $parent=$null;$child=$null
    try{
        $arguments='-NoProfile -File "'+$parentScript+'" -Root "'+$work+'" -Code '+$expected
        $parent=Start-Process -FilePath $ps -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $actual=Wait-SetupExit $parent
        if($actual -ne $expected){throw ('Exit code lost: '+$actual)}
        if($timer.Elapsed.TotalSeconds -gt 20){throw 'Parent wait was delayed by its child'}
        $child=Get-Process -Id ([int][IO.File]::ReadAllText((Join-Path $work ('child-'+$expected))))
        if($child.HasExited){throw 'Child should still run when installer wait completes'}
    }finally{
        [IO.File]::WriteAllText((Join-Path $work ('release-'+$expected)),'done')
        if($child){$null=$child.WaitForExit(5000);$child.Dispose()}
        if($parent){$parent.Dispose()}
    }
}
Write-Output 'PASS: installer-only wait returns while child lives; success and nonzero exit preserved. Synthetic processes only.'
exit 0
