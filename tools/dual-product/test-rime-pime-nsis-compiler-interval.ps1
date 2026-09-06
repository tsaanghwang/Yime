[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'rime-pime-nsis-toolchain-closure.psm1') -Force
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$output=[IO.Path]::GetFullPath($OutputRoot)
if((Split-Path -Parent $output) -ine (Join-Path $repo '.tmp\dual-product') -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-nsis-interval-test-[A-Za-z0-9-]+$' -or (Test-Path $output)) {throw 'Use a fresh DP1 interval test root.'}
$null=New-Item -ItemType Directory $output
$checks=[Collections.Generic.List[object]]::new()
foreach($mode in @('clean','file','directory','rename','root-file','compiler-error')){
    $work=Join-Path (Split-Path -Parent $output) ((Split-Path -Leaf $output)+'-'+$mode)
    $null=New-Item -ItemType Directory $work
    $stage=$null;$saved=[Environment]::GetEnvironmentVariable('NSISDIR','Process')
    try{
        $stage=Open-RimePimeMonitoredNsisStage (Join-Path $work 'NSIS')
        $candidate=Join-Path $work 'never-run.exe'
        $source=Join-Path $work 'fixture.nsi'
        $target=Join-Path $stage.Root 'Plugins\x86-unicode\transient.dll'
        if($mode -eq 'root-file'){$target=Join-Path $stage.Root 'transient.dll'}
        $escaped=$target.Replace("'","''")
        $action=switch($mode){
            'directory' {"[IO.Directory]::CreateDirectory('$escaped')|Out-Null;[IO.Directory]::Delete('$escaped')"}
            'rename' {"[IO.File]::WriteAllText('$escaped','x');[IO.File]::Move('$escaped','$escaped.new');[IO.File]::Delete('$escaped.new')"}
            default {"[IO.File]::WriteAllText('$escaped','x');[IO.File]::Delete('$escaped')"}
        }
        $text="Unicode true`nName `"DP1 membership fixture`"`nOutFile `"$candidate`"`nRequestExecutionLevel user`n"
        # makensis synchronously launches an independent same-SID child; it creates AND
        # removes the member before makensis exits. The endpoint tree stays identical.
        if($mode -notin @('clean','compiler-error')){
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$ErrorActionPreference=''Stop'';'+$action))
            $hostExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $text+='!system '+"'`"$hostExe`" -NoProfile -NonInteractive -EncodedCommand $encoded' = 0`n"
        }
        if($mode -eq 'compiler-error'){$text+="!error intentional-compiler-failure`n"}
        $text+='!if "${NSISDIR}" != "'+$stage.Root+'"'+"`n!error wrong-compiler-root`n!endif`n"
        $text+='!include "${NSISDIR}\Include\LogicLib.nsh"'+"`n"
        $text+="Section`nSectionEnd`n"
        [IO.File]::WriteAllText($source,$text,[Text.UTF8Encoding]::new($false))
        $env:NSISDIR=$stage.Root
        Push-Location (Join-Path $stage.Root 'Include')
        try{$ErrorActionPreference='Continue';& (Join-Path $stage.Root 'Bin\makensis.exe') /NOCD /NOCONFIG /V2 $source 2>&1|Out-Null;$code=$LASTEXITCODE}
        finally{$ErrorActionPreference='Stop';Pop-Location}
        if($mode -eq 'compiler-error'){
            if($code -eq 0){throw 'Expected compiler failure.'}
            if($stage.Completed){throw 'Failed compiler accepted.'}
        }else{
            if($code -ne 0){throw "Compiler fixture failed: $code"}
            $null=Test-RimePimeNsisCompilerInputClosure $stage.Closure
            $rejected=$false
            try{$result=Complete-RimePimeMonitoredNsisStage $stage}
            catch{if($_.Exception.Message -notmatch 'membership activity'){throw};$rejected=$true}
            if(($mode -eq 'clean') -eq $rejected){throw 'Wrong membership acceptance result.'}
            if($mode -eq 'clean' -and ($result.full_nsis_toolchain_input_closure -or $result.active_same_sid_transient_tree_membership_interference_excluded)){throw 'Overclaimed closure.'}
        }
        $checks.Add([pscustomobject]@{name=$mode;passed=$true});Write-Host "PASS: $mode"
    }catch{$checks.Add([pscustomobject]@{name=$mode;passed=$false;error=$_.Exception.Message})}
    finally{[Environment]::SetEnvironmentVariable('NSISDIR',$saved,'Process');if($null -ne $stage){Close-RimePimeMonitoredNsisStage $stage}}
}
$builder=[IO.File]::ReadAllText((Join-Path $repo 'tools\build-rime-pime-installer.ps1'))
$open=$builder.IndexOf('$compilerStage=Open-RimePimeMonitoredNsisStage')
$run=$builder.IndexOf('& $MakensisPath @arguments')
$complete=$builder.IndexOf('$membershipInterval=Complete-RimePimeMonitoredNsisStage')
$publish=$builder.IndexOf('$prepared=New-RimePimePreparedPublication')
$checks.Add([pscustomobject]@{name='builder-rejects-before-publication';passed=($open -gt 0 -and $run -gt $open -and $complete -gt $run -and $publish -gt $complete)})
$result=[pscustomobject]@{schema_version='dp1-nsis-interval-regression-v1';powershell=$PSVersionTable.PSVersion.ToString();checks=@($checks);passed=(@($checks|Where-Object{-not $_.passed}).Count -eq 0);actual_makensis_executed=$true;installer_executed=$false;installed_yimecore_local12_touched=$false;full_nsis_toolchain_input_closure=$false}
$result|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $output 'result.json')
$digest=(Get-FileHash (Join-Path $output 'result.json') -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'result.json.sha256'),$digest+"`n",[Text.UTF8Encoding]::new($false))
$checks|Format-Table -AutoSize
if(-not $result.passed){throw 'Compiler interval regressions failed.'}
