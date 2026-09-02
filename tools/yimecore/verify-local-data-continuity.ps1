[CmdletBinding()]
param([Parameter(Mandatory)][string]$BeforeBackup,[Parameter(Mandatory)][string]$AfterBackup,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
$allowed=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'))+'\'
$snapshots=@()
foreach($path in @($BeforeBackup,$AfterBackup)) {
    $resolved=[IO.Path]::GetFullPath($path)
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid recovery archive.'}
    $m=Get-Content -LiteralPath (Join-Path $resolved 'backup-manifest.json') -Raw|ConvertFrom-Json
    if(-not $m.passed -or -not $m.writers_stopped -or -not (Test-YimeCoreScopeEvidence $m.development_scope $scope)){throw 'Unverified snapshot.'}
    $snapshots+=@{root=$resolved;manifest=$m}
}
$results=@()
foreach($record in $snapshots[0].manifest.state_files|Where-Object {$_.path -like 'user-model/*.journal' -or $_.path -in @('yime_user_phrases.txt','yime_blocklist.txt','professional-lexicons.json')}) {
    $new=@($snapshots[1].manifest.state_files|Where-Object path -eq $record.path)
    if($new.Count -ne 1){throw "Missing preserved data: $($record.path)"}
    $paths=@((Join-Path ($snapshots[0].root+'\state') $record.path),(Join-Path ($snapshots[1].root+'\state') $record.path))
    if((Get-FileHash -LiteralPath $paths[0]).Hash -ne $record.sha256 -or (Get-FileHash -LiteralPath $paths[1]).Hash -ne $new[0].sha256){throw 'Archive integrity mismatch.'}
    if($record.path -like '*.journal') {
        $oldBytes=[IO.File]::ReadAllBytes($paths[0]);$newBytes=[IO.File]::ReadAllBytes($paths[1])
        if($newBytes.Length -lt $oldBytes.Length){throw 'Journal shortened; use semantic recovery review instead of claiming byte preservation.'}
        for($i=0;$i -lt $oldBytes.Length;$i++){if($oldBytes[$i] -ne $newBytes[$i]){throw 'Journal prefix changed; semantic recovery review required.'}}
        $results+=@{path=$record.path;old_bytes=$oldBytes.Length;new_bytes=$newBytes.Length;original_prefix_preserved=$true}
    }else{
        if($record.sha256 -ne $new[0].sha256){throw "User lexicon/settings changed: $($record.path)"}
        $results+=@{path=$record.path;sha256_unchanged=$true}
    }
}
if($results.Count -lt 3){throw 'Insufficient continuity evidence.'}
[ordered]@{schema_version='yimecore-local-data-continuity-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;
    before_backup=$snapshots[0].root;after_backup=$snapshots[1].root;results=$results;passed=$true}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host 'Original learning journal bytes and user lexicon data preserved across maintenance.'
