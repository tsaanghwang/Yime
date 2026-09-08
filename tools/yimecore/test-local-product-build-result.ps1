[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$builder=Join-Path $PSScriptRoot 'build-local-product.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
$buildTry=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Body.Extent.Text.Contains('Assert-LocalProductSourceUnchanged')})
if($buildTry.Count -ne 1){throw 'Expected one build/protection transaction.'}
# Execute only the actual summary finalizer with in-memory protection/writer
# mocks. Nothing from the builder's compilation, export, package or test body runs.
$finalize=[scriptblock]::Create('try { & $simulatedBuild } finally '+$buildTry[0].Finally.Extent.Text)
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
function Get-LocalProductProtectionEvidence {param([switch]$HashesOnly) $script:protectionAfter}
function Write-LocalProductJson {param($Value,[string]$Path) $script:writes.Add([pscustomobject]@{value=$Value;path=$Path})}
function Stop-Transcript { $script:transcriptStopped=$true }
foreach($case in @('export-failed','verification-failed','protection-changed','complete-product','complete-runtime-bundle','truthy-descriptor')){
    $out='C:\synthetic-build-result\'+$case
    $before=[ordered]@{protected_identity='same'}
    $script:protectionAfter=[ordered]@{protected_identity=if($case -eq 'protection-changed'){'different'}else{'same'}}
    $passed=($case -notin @('export-failed','verification-failed'))
    $product=[pscustomobject]@{installable=if($case -eq 'complete-runtime-bundle'){$false}elseif($case -eq 'truthy-descriptor'){'true'}else{$true}}
    $script:writes=New-Object 'Collections.Generic.List[object]';$script:transcriptStopped=$false;$caught=$null
    $simulatedBuild=if($case -in @('export-failed','verification-failed')){{throw 'Synthetic upstream build gate failure.'}}else{{}}
    try{. $finalize}catch{$caught=$_.Exception.Message}
    $summaries=@($script:writes|Where-Object{$_.path -like '*\summary.json'})
    Check ($summaries.Count -eq 1 -and $script:transcriptStopped) "$case emits one summary and closes transcript"
    $summary=$summaries[0].value
    Check ($summary.schema_version -ceq 'yimecore-local-build-result-v1' -and $summary.installable -is [bool] -and $summary.requested_installable -is [bool]) "$case preserves schema and literal boolean result fields"
    Check (-not $summary.local_product_ready -and -not $summary.public_release_ready) "$case never claims installed or public readiness"
    if($case -in @('export-failed','verification-failed','protection-changed')){
        Check ($null -ne $caught -and -not $summary.passed -and -not $summary.installable -and $summary.requested_installable) "$case failure cannot claim an installable artifact"
        Check ($summary.completed_scope -like '*incomplete*' -and $summary.next_step -like '*do not install*') "$case reports repair and fresh build instead of installation"
    }elseif($case -eq 'complete-product'){
        Check ($null -eq $caught -and $summary.passed -and $summary.installable -and $summary.requested_installable) 'complete verified product retains installable result'
        Check ($summary.next_step -like 'Native same-user*') 'complete verified product keeps next acceptance stage'
    }else{
        Check ($null -eq $caught -and $summary.passed -and -not $summary.installable -and -not $summary.requested_installable) "$case cannot coerce or invent installability"
    }
    if($case -eq 'protection-changed'){Check (-not $summary.registration_and_default_preserved -and $caught -like '*System registration/default changed*') 'protection failure retains explicit failure reason'}
}
$result=[ordered]@{schema_version='yimecore-local-product-build-result-test-v1';passed=$true;powershell_version=$PSVersionTable.PSVersion.ToString();
    checks_passed=$checks.Count;checks=$checks.ToArray();builder_source_sha256=(Get-FileHash -LiteralPath $builder -Algorithm SHA256).Hash.ToLowerInvariant();
    actual_summary_finalizer_tested=$true;full_builder_invoked=$false;compiler_executed=$false;product_executed=$false;registry_read_or_written=$false;user_data_read=$false}
if($OutputPath){$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8}
Write-Host ('PASS: local build-result '+$checks.Count+' synthetic finalizer contracts; no build or product executed.')
