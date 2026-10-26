[CmdletBinding()]
param()
# Load only the named read-only functions and P/Invoke declarations from the
# current wrapper AST. Never dot-source the wrapper or execute its host loop.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$source=Join-Path $PSScriptRoot 'registered-host-arm64-r2-20261026.ps1'
$output=Join-Path $PSScriptRoot 'arm64-r2-runtime-observer-only.json'
if(Test-Path -LiteralPath $output){throw 'Preserve previous observer verification.'}
$text=Get-Content -LiteralPath $source -Raw -Encoding UTF8
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Wrapper AST has parse errors.'}
foreach($name in @('Get-LimitedProcessObservation','Convert-RuntimeTimestampToUtc','Assert-ProcessCreationNotAfterStatus','Get-InstalledRuntimeObservation')){
 $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -ceq $name
 if(@($definition).Count -ne 1){throw ('Expected exactly one function: '+$name)}
 . ([scriptblock]::Create($definition.Extent.Text))
}
$native=[regex]::Match($text,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if(-not $native.Success){throw 'P/Invoke declarations missing.'}
Add-Type -TypeDefinition $native.Groups[1].Value
$installedRoot='C:\Program Files\YimeCore'
$Pipe='\\.\pipe\YimeBroker.YimeCoreTrial.v1'
$runtimeStatusPath='C:\Users\tsaan\AppData\Local\YimeCore Experimental Trial\runtime-status.json'
$observed=Get-InstalledRuntimeObservation
$parsed=Get-Content -LiteralPath $runtimeStatusPath -Raw -Encoding UTF8|ConvertFrom-Json
$utc=Convert-RuntimeTimestampToUtc $parsed.updated_at
$stringUtc=Convert-RuntimeTimestampToUtc '2026-10-26T13:51:20.5196831Z'
$offsetUtc=Convert-RuntimeTimestampToUtc '2026-10-26T21:51:20.5196831+08:00'
$futureRejected=$false
try{Assert-ProcessCreationNotAfterStatus ($utc.ToFileTimeUtc()+1) $utc}catch{$futureRejected=$true}
$unspecifiedRejected=$false
try{$null=Convert-RuntimeTimestampToUtc ([DateTime]::SpecifyKind($utc,[DateTimeKind]::Unspecified))}catch{$unspecifiedRejected=$true}
if(-not $futureRejected -or -not $unspecifiedRejected -or $stringUtc.ToFileTimeUtc() -ne $offsetUtc.ToFileTimeUtc()){
 throw 'UTC normalization or future-process rejection regression.'
}
$record=[ordered]@{
 wrapper_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 observation_passed=$true;read_only_functions_only=$true;wrapper_body_executed=$false
 product_processes_started_or_stopped=$false;host_tests_started=0
 observation=$observed
 normalization=[ordered]@{parsed_type=$parsed.updated_at.GetType().FullName;parsed_kind=$parsed.updated_at.Kind.ToString();utc=$utc.ToString('o');iso_string_utc=$stringUtc.ToString('o');offset_string_utc=$offsetUtc.ToString('o');one_tick_newer_process_rejected=$futureRejected;unspecified_timezone_rejected=$unspecifiedRejected}
}
$json=$record|ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($output,$json,[Text.UTF8Encoding]::new($false))
$json
