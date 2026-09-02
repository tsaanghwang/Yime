[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePackage,[Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
Assert-YimeCoreNativeGo
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith((Join-Path $repo '.tmp\yimecore-experiment\') ,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)) {throw 'Rehearsal output must be a new experiment child.'}
$source=[IO.Path]::GetFullPath($SourcePackage)
Assert-YimeCorePlainPath $source
Assert-YimeCorePlainPath $out
$manifest=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $source 'package-manifest.json') -Raw|ConvertFrom-Json
foreach($record in $manifest.files){if((Get-FileHash -LiteralPath (Join-Path $source $record.path)).Hash -ne $record.sha256){throw 'Source package hash mismatch.'}}
New-Item -ItemType Directory -Path $out|Out-Null
foreach($item in Get-ChildItem -LiteralPath $source -Force){Copy-Item -LiteralPath $item.FullName -Destination $out -Recurse}
Push-Location (Join-Path $repo 'go-backend')
try{& go build -trimpath -ldflags '-H=windowsgui' -o (Join-Path $out 'bin\YimeCoreTrialRuntime.exe') (Join-Path $PSScriptRoot 'rollback-failure-runtime.go'); if($LASTEXITCODE -ne 0){throw 'Could not build failure runtime.'}}finally{Pop-Location}
$runtime=Get-Item -LiteralPath (Join-Path $out 'bin\YimeCoreTrialRuntime.exe')
$record=@($manifest.files|Where-Object path -eq 'bin/YimeCoreTrialRuntime.exe')
if($record.Count -ne 1){throw 'No unique runtime record.'}
$record[0].bytes=$runtime.Length
$record[0].sha256=(Get-FileHash -LiteralPath $runtime.FullName).Hash.ToLowerInvariant()
# The transaction copies its current manager into staging and then verifies the
# entire manifest. Pin that exact script in this isolated fault package too.
$manager=Join-Path $out 'maintenance\Manage-YimeCoreTrial.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') -Destination $manager -Force
$managerRecord=@($manifest.files|Where-Object path -eq 'maintenance/Manage-YimeCoreTrial.ps1')
if($managerRecord.Count -ne 1){throw 'No unique maintenance-script record.'}
$managerRecord[0].bytes=(Get-Item -LiteralPath $manager).Length
$managerRecord[0].sha256=(Get-FileHash -LiteralPath $manager).Hash.ToLowerInvariant()
$frozen=@($manifest.files|Where-Object {$_.path -match '^(x86|arm64)/'})
foreach($item in $frozen){if((Get-FileHash -LiteralPath (Join-Path $out $item.path)).Hash -ne $item.sha256){throw 'Frozen payload changed.'}}
$manifest|Add-Member -NotePropertyName frozen_payload_provenance -NotePropertyValue ([ordered]@{
    source_package=$source;source_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $source 'package-manifest.json')).Hash;
    copied_unchanged=$frozen;rebuilt=$false;executed=$false}) -Force
$manifest.scope='REHEARSAL ONLY: runtime exits 86; MUST NOT be used for normal installation.'
$manifest|Add-Member -NotePropertyName rehearsal_only -NotePropertyValue $true -Force
$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'package-manifest.json') -Encoding utf8
Write-Host "Failure-only rehearsal package prepared: $out"
