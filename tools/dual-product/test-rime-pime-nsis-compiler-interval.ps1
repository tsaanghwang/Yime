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
try{
    $builderPath=Join-Path $repo 'tools\build-rime-pime-installer.ps1'
    $builderTokens=$null;$builderParseErrors=$null
    $builderAst=[Management.Automation.Language.Parser]::ParseFile($builderPath,[ref]$builderTokens,[ref]$builderParseErrors)
    if(@($builderParseErrors).Count -ne 0){
        throw ('Builder has PowerShell parse errors: '+(($builderParseErrors|ForEach-Object{$_.Message}) -join '; '))
    }
    $builderCommands=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
    $builderAssignments=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst]},$true))
    $requiredCommands=@{}
    foreach($commandName in @(
        'Open-RimePimeMonitoredNsisStage',
        'Complete-RimePimeMonitoredNsisStage',
        'New-RimePimePreparedPublication',
        'Invoke-RimePimePublicationCommit',
        'Close-RimePimeMonitoredNsisStage'
    )){
        $matches=@($builderCommands|Where-Object{$_.GetCommandName() -ceq $commandName})
        if($matches.Count -ne 1){throw "Builder must contain exactly one real $commandName command node."}
        $requiredCommands[$commandName]=$matches[0]
    }
    $open=$requiredCommands['Open-RimePimeMonitoredNsisStage']
    $complete=$requiredCommands['Complete-RimePimeMonitoredNsisStage']
    $prepared=$requiredCommands['New-RimePimePreparedPublication']
    $commit=$requiredCommands['Invoke-RimePimePublicationCommit']
    $close=$requiredCommands['Close-RimePimeMonitoredNsisStage']
    foreach($binding in @(
        @{Left='$compilerStage';Command=$open},
        @{Left='$membershipInterval';Command=$complete},
        @{Left='$prepared';Command=$prepared},
        @{Left='$receipt';Command=$commit}
    )){
        $bound=@($builderAssignments|Where-Object{
            $_.Left.Extent.Text -ceq $binding.Left -and
            $_.Right.Extent.StartOffset -le $binding.Command.Extent.StartOffset -and
            $_.Right.Extent.EndOffset -ge $binding.Command.Extent.EndOffset
        })
        if($bound.Count -ne 1){throw "Builder command is not uniquely bound to $($binding.Left): $($binding.Command.GetCommandName())."}
    }
    $buildResultAssignments=@($builderAssignments|Where-Object{$_.Left.Extent.Text -ceq '$buildResult'})
    $buildResultHashtables=@()
    if($buildResultAssignments.Count -eq 1){
        $buildResultHashtables=@($buildResultAssignments[0].Right.FindAll({param($node) $node -is [Management.Automation.Language.HashtableAst]},$true)|Where-Object{
            $ancestor=$_.Parent
            while($ancestor -is [Management.Automation.Language.ConvertExpressionAst]){$ancestor=$ancestor.Parent}
            $ancestor -eq $buildResultAssignments[0].Right
        })
    }
    $schemaResultPairs=@()
    $membershipResultPairs=@()
    if($buildResultHashtables.Count -eq 1){
        $schemaResultPairs=@($buildResultHashtables[0].KeyValuePairs|Where-Object{
            $_.Item1 -is [Management.Automation.Language.StringConstantExpressionAst] -and
            [string]$_.Item1.Value -ceq 'schema_version'
        })
        $membershipResultPairs=@($buildResultHashtables[0].KeyValuePairs|Where-Object{
            $_.Item1 -is [Management.Automation.Language.StringConstantExpressionAst] -and
            [string]$_.Item1.Value -ceq 'nsis_compiler_membership_interval'
        })
    }
    if($buildResultAssignments.Count -ne 1 -or $buildResultHashtables.Count -ne 1 -or
        $schemaResultPairs.Count -ne 1 -or $membershipResultPairs.Count -ne 1){
        throw 'The successful buildResult must contain one exact schema_version and one nsis_compiler_membership_interval binding.'
    }
    $schemaResultValue=$schemaResultPairs[0].Item2
    if($schemaResultValue -isnot [Management.Automation.Language.PipelineAst] -or
        $schemaResultValue.PipelineElements.Count -ne 1 -or
        $schemaResultValue.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or
        $schemaResultValue.PipelineElements[0].Expression -isnot [Management.Automation.Language.StringConstantExpressionAst] -or
        [string]$schemaResultValue.PipelineElements[0].Expression.Value -cne 'yime-rime-pime-staged-nsis-build-result-membership-interval-v1'){
        throw 'The successful buildResult schema_version must be the exact literal yime-rime-pime-staged-nsis-build-result-membership-interval-v1; bare result-v3 is not admissible.'
    }
    $membershipResultValue=$membershipResultPairs[0].Item2
    if($membershipResultValue -isnot [Management.Automation.Language.PipelineAst] -or
        $membershipResultValue.PipelineElements.Count -ne 1 -or
        $membershipResultValue.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or
        $membershipResultValue.PipelineElements[0].Expression -isnot [Management.Automation.Language.VariableExpressionAst] -or
        $membershipResultValue.PipelineElements[0].Expression.VariablePath.UserPath -cne 'membershipInterval'){
        throw 'The successful buildResult membership binding must have the exact value $membershipInterval.'
    }
    $stagedMakensisAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $joins=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Join-Path'},$true))
        $assignment.Left.Extent.Text -ceq '$MakensisPath' -and $joins.Count -eq 1 -and
        $joins[0].CommandElements.Count -eq 3 -and $joins[0].CommandElements[1].Extent.Text -ceq '$compilerStage.Root' -and
        $joins[0].CommandElements[2] -is [Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$joins[0].CommandElements[2].Value -ceq 'Bin\makensis.exe'
    })
    $stagedIncludeAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $joins=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Join-Path'},$true))
        $assignment.Left.Extent.Text -ceq '$nsisIncludeRoot' -and $joins.Count -eq 1 -and
        $joins[0].CommandElements.Count -eq 3 -and $joins[0].CommandElements[1].Extent.Text -ceq '$compilerStage.Root' -and
        $joins[0].CommandElements[2] -is [Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$joins[0].CommandElements[2].Value -ceq 'Include'
    })
    $nsisDirAssignments=@($builderAssignments|Where-Object{
        $_.Left.Extent.Text -ceq '$env:NSISDIR' -and $_.Right.Extent.Text -ceq '$compilerStage.Root'
    })
    $cwdCommands=@($builderCommands|Where-Object{
        $_.GetCommandName() -ceq 'Push-Location' -and $_.CommandElements.Count -eq 2 -and
        $_.CommandElements[1].Extent.Text -ceq '$nsisIncludeRoot'
    })
    if($stagedMakensisAssignments.Count -ne 1 -or $stagedIncludeAssignments.Count -ne 1 -or
        $nsisDirAssignments.Count -ne 1 -or $cwdCommands.Count -ne 1){
        throw 'Builder does not uniquely bind makensis, NSISDIR, and the compiler CWD to the fresh monitored stage.'
    }
    $argumentAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $values=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object{[string]$_.Value})
        $assignment.Left.Extent.Text -ceq '$arguments' -and $values -ccontains '/NOCD' -and
        $values -ccontains '/NOCONFIG' -and $values -ccontains '/DPACKAGE_UNSIGNED_DISABLED_BUILD=1'
    })
    $makensisCalls=@($builderCommands|Where-Object{
        $_.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -and
        $_.CommandElements.Count -gt 0 -and $_.CommandElements[0] -is [Management.Automation.Language.VariableExpressionAst] -and
        $_.CommandElements[0].VariablePath.UserPath -ceq 'MakensisPath'
    })
    if($argumentAssignments.Count -ne 1 -or $makensisCalls.Count -ne 1){
        throw 'Builder must have one disabled compiler argument assignment and one real makensis invocation.'
    }
    $makensisCall=$makensisCalls[0]
    if($makensisCall.CommandElements.Count -ne 2 -or
        $makensisCall.CommandElements[1] -isnot [Management.Automation.Language.VariableExpressionAst] -or
        -not $makensisCall.CommandElements[1].Splatted -or
        $makensisCall.CommandElements[1].VariablePath.UserPath -cne 'arguments'){
        throw 'The sole makensis command must consume only the reviewed splatted disabled-build arguments.'
    }
    $exitGates=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst]},$true)|Where-Object{
        $ifNode=$_
        $binary=$null
        if($ifNode.Clauses.Count -eq 1){
            $condition=$ifNode.Clauses[0].Item1
            if($condition.PipelineElements.Count -eq 1 -and
                $condition.PipelineElements[0] -is [Management.Automation.Language.CommandExpressionAst] -and
                $condition.PipelineElements[0].Expression -is [Management.Automation.Language.BinaryExpressionAst]){
                $binary=$condition.PipelineElements[0].Expression
            }
        }
        $null -ne $binary -and $null -eq $ifNode.ElseClause -and
        $binary.Operator -eq [Management.Automation.Language.TokenKind]::Ine -and
        $binary.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $binary.Left.VariablePath.UserPath -ceq 'LASTEXITCODE' -and
        $binary.Right -is [Management.Automation.Language.ConstantExpressionAst] -and
        $binary.Right.Value -is [int] -and [int]$binary.Right.Value -eq 0 -and
        $ifNode.Clauses[0].Item2.Statements.Count -eq 1 -and
        $ifNode.Clauses[0].Item2.Statements[0] -is [Management.Automation.Language.ThrowStatementAst]
    })
    $candidateProbeCommands=@($builderCommands|Where-Object{
        $_.GetCommandName() -ceq 'Test-Path' -and $_.CommandElements.Count -eq 5 -and
        $_.CommandElements[1] -is [Management.Automation.Language.CommandParameterAst] -and
        $_.CommandElements[1].ParameterName -ceq 'LiteralPath' -and
        $_.CommandElements[2] -is [Management.Automation.Language.VariableExpressionAst] -and
        $_.CommandElements[2].VariablePath.UserPath -ceq 'candidate' -and
        $_.CommandElements[3] -is [Management.Automation.Language.CommandParameterAst] -and
        $_.CommandElements[3].ParameterName -ceq 'PathType' -and
        $_.CommandElements[4] -is [Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$_.CommandElements[4].Value -ceq 'Leaf'
    })
    $candidateRecordAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $records=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Get-YimePimePayloadFileRecord'},$true))
        $assignment.Left.Extent.Text -ceq '$candidateRecord' -and $records.Count -eq 1 -and
        $records[0].CommandElements.Count -eq 2 -and
        $records[0].CommandElements[1] -is [Management.Automation.Language.VariableExpressionAst] -and
        $records[0].CommandElements[1].VariablePath.UserPath -ceq 'candidate'
    })
    $inputLeaseCommands=@($builderCommands|Where-Object{$_.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'})
    $prebuildLeaseAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $opens=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'},$true))
        $assignment.Left.Extent.Text -ceq '$leases' -and $opens.Count -eq 1 -and
        $opens[0].CommandElements.Count -eq 2 -and $opens[0].CommandElements[1].Extent.Text -ceq '$expected'
    })
    $candidateLeaseAssignments=@($builderAssignments|Where-Object{
        $assignment=$_
        $opens=@($assignment.Right.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Open-RimePimeBuildInputLeases'},$true))
        $assignment.Left.Extent.Text -ceq '$candidateLeases' -and $opens.Count -eq 1 -and
        $opens[0].CommandElements.Count -eq 2 -and $opens[0].CommandElements[1].Extent.Text -ceq '$candidateExpected'
    })
    if($exitGates.Count -ne 1 -or $candidateProbeCommands.Count -ne 1 -or
        $candidateRecordAssignments.Count -ne 1 -or $inputLeaseCommands.Count -ne 2 -or
        $prebuildLeaseAssignments.Count -ne 1 -or $candidateLeaseAssignments.Count -ne 1){
        throw 'Builder must gate compiler success before its unique candidate probe, record, and lease admission.'
    }
    $owningTries=@($builderAst.FindAll({param($node) $node -is [Management.Automation.Language.TryStatementAst]},$true)|Where-Object{
        $null -ne $_.Finally -and
        $_.Body.Extent.StartOffset -le $open.Extent.StartOffset -and $_.Body.Extent.EndOffset -ge $commit.Extent.EndOffset -and
        $_.Finally.Extent.StartOffset -le $close.Extent.StartOffset -and $_.Finally.Extent.EndOffset -ge $close.Extent.EndOffset
    })
    if($owningTries.Count -ne 1){throw 'The monitored compiler lifecycle and publication must share one try with Close in its finally.'}
    $closeGuards=@($owningTries[0].Finally.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst]},$true)|Where-Object{
        $_.Clauses.Count -eq 1 -and $_.Clauses[0].Item1.Extent.Text -cmatch '^\s*\$null\s+-ne\s+\$compilerStage\s*$' -and
        $_.Clauses[0].Item2.Extent.StartOffset -le $close.Extent.StartOffset -and
        $_.Clauses[0].Item2.Extent.EndOffset -ge $close.Extent.EndOffset
    })
    if($closeGuards.Count -ne 1){throw 'Close-RimePimeMonitoredNsisStage is not guarded in the owning finally.'}
    $ordered=@(
        $open.Extent.StartOffset,
        $stagedMakensisAssignments[0].Extent.StartOffset,
        $stagedIncludeAssignments[0].Extent.StartOffset,
        $nsisDirAssignments[0].Extent.StartOffset,
        $cwdCommands[0].Extent.StartOffset,
        $argumentAssignments[0].Extent.StartOffset,
        $makensisCall.Extent.StartOffset,
        $exitGates[0].Extent.StartOffset,
        $complete.Extent.StartOffset,
        $candidateProbeCommands[0].Extent.StartOffset,
        $candidateRecordAssignments[0].Extent.StartOffset,
        $candidateLeaseAssignments[0].Extent.StartOffset,
        $prepared.Extent.StartOffset,
        $buildResultAssignments[0].Extent.StartOffset,
        $commit.Extent.StartOffset,
        $close.Extent.StartOffset
    )
    for($i=1;$i -lt $ordered.Count;$i++){
        if($ordered[$i] -le $ordered[$i-1]){throw 'Builder compiler membership lifecycle is out of admission order.'}
    }
    $checks.Add([pscustomobject]@{name='builder-rejects-before-publication';passed=$true})
}catch{
    $checks.Add([pscustomobject]@{name='builder-rejects-before-publication';passed=$false;error=$_.Exception.Message})
}
$result=[pscustomobject]@{schema_version='dp1-nsis-interval-regression-v1';powershell=$PSVersionTable.PSVersion.ToString();checks=@($checks);passed=(@($checks|Where-Object{-not $_.passed}).Count -eq 0);actual_makensis_executed=$true;installer_executed=$false;installed_yimecore_local12_touched=$false;full_nsis_toolchain_input_closure=$false}
$result|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $output 'result.json')
$digest=(Get-FileHash (Join-Path $output 'result.json') -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'result.json.sha256'),$digest+"`n",[Text.UTF8Encoding]::new($false))
$checks|Format-Table -AutoSize
if(-not $result.passed){throw 'Compiler interval regressions failed.'}
