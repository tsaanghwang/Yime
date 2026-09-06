[CmdletBinding()]
param()
# AST plus pure receipt/path checks; no installer, Broker or filesystem mutation.
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'run-connected-speech-package.ps1'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
$count=0
function Check([bool]$Value,[string]$Name) { if (-not $Value) { throw "FAIL: $Name" }; $script:count++ }
function Reject([scriptblock]$Body,[string]$Name) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Check $failed $Name }
Check (@($parseErrors).Count -eq 0) 'runner parses'
foreach ($name in @('Resolve-PackageAdmission','Assert-PackageAdmission')) {
    $items=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -CEQ $name)
    Check ($items.Count -eq 1) ('one pure helper '+$name)
    . ([scriptblock]::Create($items[0].Extent.Text))
}
function Assert-SpeechPlainPath([string]$Path) { if ($Path -match 'indirect') { throw 'synthetic indirect path' } }
$repo='C:\fixture\repo'
$root=$repo+'\.tmp\yimecore-experiment\speech-admission-20260905-120000-'+('a'*32)
Check ((Resolve-PackageAdmission $repo $root) -ceq $root) 'canonical fixed admission accepted'
foreach ($bad in @($repo,'relative',($root+'\child'),($repo+'\..\repo\.tmp\yimecore-experiment\'+(Split-Path -Leaf $root)),
    ('C:\fixture\elsewhere\'+(Split-Path -Leaf $root)),($repo+'\.tmp\yimecore-experiment\speech-admission-old'),($root+'.'))) {
    Reject { Resolve-PackageAdmission $repo $bad } 'wrong or noncanonical admission rejected'
}
Reject { Resolve-PackageAdmission 'C:\indirect\repo' ($root.Replace($repo,'C:\indirect\repo')) } 'indirect root rejected'
$install='C:\fixture\installed'; $hash='b'*64
$good=[ordered]@{schema_version='yimecore-speech-admission-isolated-v1';passed=$true;trial_root=$root;install_root=$install;installed_manifest_sha256=$hash;
    module='third-tone-stage5c';reviewed_records=24;mode_alias_rows=72;
    directed_tests=@(@{package='./cmd/yimecore-speech-admission';selector='^TestSpeech(Exercise|Package)';passed=$true;passed_count=1;failed_count=0})}
$required=@('forward_source_passed','admission_prepare_passed','owned_process_acceptance_passed','dependency_boundary_passed','python_contracts_passed',
    'installed_baseline_unchanged','locked_inputs_unchanged','source_set_unchanged','legacy_static_unchanged','environment_restored')
$forbidden=@('real_rime_executed','registered_hosts_executed','frozen_targets_executed','default_input_method_changed','new_package_installed',
    'daily_broker_connected','user_text_read','live_learning_data_read','live_config_read','product_or_registry_mutated')
foreach ($field in $required) { $good[$field]=$true }
foreach ($field in $forbidden) { $good[$field]=$false }
$good=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json
Assert-PackageAdmission $good $root $install $hash; Check $true 'complete bounded source receipt accepted'
foreach ($field in $required) {
    $changed=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $changed.$field=$false
    Reject { Assert-PackageAdmission $changed $root $install $hash } ('missing '+$field)
}
foreach ($field in $forbidden) {
    $changed=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $changed.$field=$true
    Reject { Assert-PackageAdmission $changed $root $install $hash } ('scope overreach '+$field)
}
foreach ($field in @('schema_version','trial_root','install_root','installed_manifest_sha256','module','reviewed_records','mode_alias_rows')) {
    $changed=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $changed.$field='wrong'
    Reject { Assert-PackageAdmission $changed $root $install $hash } ('wrong '+$field)
}
$changed=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $changed.directed_tests[0].selector='^TestSpeechExercise'
Reject { Assert-PackageAdmission $changed $root $install $hash } 'old exercise-only test evidence rejected'
$changed=$good | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $changed.directed_tests=@()
Reject { Assert-PackageAdmission $changed $root $install $hash } 'absent package test evidence rejected'
$source=$ast.Extent.Text
Check ($source -match 'ExpectedAdmissionSummarySha256' -and $source -match 'Assert-SpeechSameRecords \$admissionSources \$sourcesBefore') 'current source and prior summary pinned'
Check ($source -match 'Assert-SpeechBaselineUnchanged' -and $source -match 'Get-AdmissionLegacyRecords') 'installed and historical protection retained'
Check ($source -match "'verify-package'" -and $source -match "'exercise-package'" -and $source -match 'Push-Location \$relocated') 'relocated verification and exercise explicit'
Check ($source -notmatch 'GetTempPath\(' -and $source -match 'YimeCore Isolated Fixtures\\SR4') 'inherited TEMP cannot select fixture roots'
Check ($source -match 'Set-SpeechEnvironmentValue \$name \$privatePath' -and $source -match 'external_environment_root=\$externalEnvironmentRoot') 'relocated tool environment also outside repository'
Check ($source -match 'manifest\.default_enabled -ne \$false') 'default off checked'
Check ($source -match 'sealed_package_unchanged=\$sealedUnchanged' -and $source -match 'installable=\$false') 'non-installable immutable outcome explicit'
$commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() })
foreach ($name in @('Start-Process','Stop-Process','regsvr32','taskkill','Set-WinUserLanguageList','Invoke-Expression')) {
    Check ($commands -notcontains $name) ('no '+$name)
}
Check ($source -notmatch 'runtime-config\.json|runtime-status\.json|PRIVATE-OBSERVATIONS|首日测试') 'no live config or user text files'
Check ($source -match 'environment_restore_failures' -and $source -match 'finally') 'environment restored on failure'
Write-Output "PASS: $count SR4 package runner AST and synthetic contracts; no package, process or installed acceptance inferred."
