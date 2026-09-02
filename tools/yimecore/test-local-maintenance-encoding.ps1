[CmdletBinding()]
param([string]$BackupRoot,[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$plan=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $repo '.tmp\yimecore-experiment\native-closure-ready\plan.json') -Raw|ConvertFrom-Json
$paths=@($plan.inputs.path|Where-Object {$_ -like '*.ps1'})+@(
    (Join-Path $PSScriptRoot 'prepare-local-closure.ps1'),(Join-Path $PSScriptRoot 'prepare-local-rollback-package.ps1'))
$readCount=0
foreach($path in $paths) {
    $source=Get-Content -Encoding UTF8 -LiteralPath $path -Raw
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Parse failed: $path"}
    foreach($command in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-Content'},$true)) {
        $elements=@($command.CommandElements)
        $utf8=$false
        for($i=0;$i -lt $elements.Count-1;$i++) {
            if($elements[$i] -is [Management.Automation.Language.CommandParameterAst] -and
                $elements[$i].ParameterName -eq 'Encoding' -and $elements[$i+1].Extent.Text.Trim("'",'"') -ieq 'UTF8'){$utf8=$true}
        }
        if(-not $utf8){throw "Implicit text encoding in native maintenance chain: $path : $($command.Extent.Text)"}
        $readCount++
    }
}
$restoreSource=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'restore-local-trial-state.ps1') -Raw
$restoreAst=[Management.Automation.Language.Parser]::ParseInput($restoreSource,[ref]$tokens,[ref]$errors)
$firstReader=$restoreAst.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$first'},$true)
if(-not $firstReader){throw 'Restore journal reader not found'}
if(-not $OutputRoot){$OutputRoot=Join-Path $repo ('.tmp\yimecore-experiment\encoding-recovery-'+[guid]::NewGuid().ToString('N'))}
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith((Join-Path $repo '.tmp\yimecore-experiment\'),[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Use a new experiment directory for encoding tests.'}
Assert-YimeCorePlainPath $out
New-Item -ItemType Directory -Path $out|Out-Null
$clone=Join-Path $out 'utf8-fixture'
New-Item -ItemType Directory -Path $clone|Out-Null
# Odd-length UTF-8 Chinese followed by a quote reproduces the CP936 parse error;
# include non-BMP text and escaped quotes/backslashes to cover JSON boundaries.
$cases=@(([string][char]0x79CB),('abc'+[char]0x79CB),([char]0x79CB+'"\'+[char]::ConvertFromUtf32(0x20000)))
foreach($value in $cases) {
    $json=@{source_id='fixture';mutation=@{text=$value}}|ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText((Join-Path $clone 'user-model.journal'),$json+"`n",[Text.UTF8Encoding]::new($false))
    . ([scriptblock]::Create($firstReader.Extent.Text))
    if($first.source_id -cne 'fixture' -or $first.mutation.text -cne $value){throw 'Real restore reader corrupted UTF-8 journal content.'}
}
$recoveries=@()
if($BackupRoot) {
    $backup=[IO.Path]::GetFullPath($BackupRoot)
    if(-not $backup.StartsWith((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Only exported native recovery archives may be used.'}
    Assert-YimeCorePlainPath $backup
    $manifest=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw|ConvertFrom-Json
    if(-not $manifest.native_context_verified -or -not $manifest.passed){throw 'A successful native backup is required.'}
    $archiveState=Join-Path $backup 'state'
    $before=@(Get-YimeCoreDataRecords $archiveState)
    Assert-YimeCoreUnchangedData $manifest.data_files $before
    if((Get-FileHash -LiteralPath $plan.recovery_probe).Hash -ne $plan.recovery_probe_sha256){throw 'Recovery probe identity changed.'}
    foreach($record in @($manifest.data_files|Where-Object {$_.path -like '*user-model.journal'})) {
        $journal=Join-Path $archiveState $record.path
        # Strictly validate the original bytes before invoking the real reader.
        $decoded=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($journal))
        $lineCount=0
        foreach($line in ($decoded -split "`r?`n")){if($line){$null=$line|ConvertFrom-Json;$lineCount++}}
        $clone=Join-Path $out ('model-'+[guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Split-Path -Parent $journal) -Destination $clone -Recurse
        New-Item -ItemType File -Path (Join-Path $clone '.yime-recovery-clone')|Out-Null
        . ([scriptblock]::Create($firstReader.Extent.Text))
        $output=Join-Path $clone 'recovery.json'
        & $plan.recovery_probe -clone $clone -source-id ([string]$first.source_id) -output $output
        if($LASTEXITCODE -ne 0){throw "Real journal recovery failed: $($record.path)"}
        $recovery=Get-Content -Encoding UTF8 -LiteralPath $output -Raw|ConvertFrom-Json
        if(-not $recovery.passed){throw 'Go recovery evidence did not pass.'}
        $recoveries+=@([ordered]@{journal=$record.path;utf8_json_lines=$lineCount;first_text=$first.mutation.text;
            original_sha256=$record.sha256;result=$recovery})
    }
    Assert-YimeCoreUnchangedData $before @(Get-YimeCoreDataRecords $archiveState)
    if($recoveries.Count -ne @($manifest.data_files|Where-Object {$_.path -like '*user-model.journal'}).Count -or $recoveries.Count -eq 0){throw 'Missing real recovery result.'}
}
[ordered]@{passed=$true;ps_version=$PSVersionTable.PSVersion.ToString();explicit_utf8_read_count=$readCount;
    script_count=$paths.Count;fixture_cases=$cases.Count;backup_root=$BackupRoot;original_archive_unchanged=$true;
    live_state_mutated=$false;recoveries=$recoveries}|ConvertTo-Json -Depth 12|
    Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Host "Encoding regression passed: $readCount explicit readers, $($cases.Count) Unicode fixtures, $($recoveries.Count) real cloned journals. Evidence: $out"
