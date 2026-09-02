[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
$sourceParent=Join-Path $env:LOCALAPPDATA 'YimeCore Recovery Archives'
$targetParent=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives'))
$output=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'Refusing to replace archive export evidence'}
if($targetParent.StartsWith([IO.Path]::GetFullPath($env:LOCALAPPDATA),[StringComparison]::OrdinalIgnoreCase)){throw 'Target must be outside AppData virtualization'}
$names=@('local-closure-20260902','local-closure-second-20260902','local-closure-final-20260902')
function Get-ArchiveRecords([string]$Root) {
    if((Get-Item -LiteralPath $Root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Archive root cannot be a reparse point'}
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force|ForEach-Object {
        if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Archive reparse point: $($_.FullName)"}
        if(-not $_.PSIsContainer){[ordered]@{path=$_.FullName.Substring($Root.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}}
    }|Sort-Object path)
}
foreach($name in $names){if(Test-Path -LiteralPath (Join-Path $targetParent $name)){throw "Destination already exists: $name"}}
if(Test-Path -LiteralPath $targetParent){if((Get-Item -LiteralPath $targetParent).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Destination parent cannot be a reparse point'}}
New-Item -ItemType Directory -Path $targetParent -Force|Out-Null
$exports=@()
foreach($name in $names) {
    $source=Join-Path $sourceParent $name
    $target=Join-Path $targetParent $name
    $manifest=Get-Content (Join-Path $source 'backup-manifest.json') -Raw|ConvertFrom-Json
    if(-not $manifest.passed -or -not (Test-YimeCoreScopeEvidence $manifest.development_scope $scope)){throw "Unverified archive: $name"}
    $before=Get-ArchiveRecords $source
    # Copy only; never move or delete the isolated original or live user state.
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    $copied=Get-ArchiveRecords $target
    $after=Get-ArchiveRecords $source
    if(($before|ConvertTo-Json -Depth 4 -Compress) -cne ($copied|ConvertTo-Json -Depth 4 -Compress) -or
        ($before|ConvertTo-Json -Depth 4 -Compress) -cne ($after|ConvertTo-Json -Depth 4 -Compress)){throw "Archive copy differs: $name"}
    $visible=@()
    foreach($relative in @('backup-manifest.json','state/user-model/installed-v1/user-model.journal','previous-package/package-manifest.json','previous-package/bin/YimeCoreTrialRuntime.exe')) {
        $file=Join-Path $target $relative
        $escaped=$file.Replace('\','\\').Replace("'","''")
        $native=Get-CimInstance CIM_DataFile -Filter "Name='$escaped'"
        if(-not $native -or [uint64]$native.FileSize -ne [uint64](Get-Item -LiteralPath $file).Length){throw "System cannot see exported recovery file: $file"}
        $visible+=@{path=$file;system_visible=$true;bytes=$native.FileSize}
    }
    $exports+=@{source=$source;destination=$target;source_preserved=$true;copied_file_count=$copied.Count;all_hashes_match=$true;records=$copied;system_visibility=$visible}
    Write-Host "Recovery archive copied and verified outside AppData: $target"
}
[ordered]@{schema_version='yimecore-recovery-archive-export-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;
    archives=$exports;passed=$true;source_deleted=$false;live_user_data_modified=$false}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding utf8
