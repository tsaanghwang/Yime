[CmdletBinding()]
param()
# Static AST + pure synthetic contracts only. Never dot-source the runner main.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'run-connected-speech-reconnect.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
$count = 0
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:count++
}
function Reject([scriptblock]$Body,[string]$Name) {
    $rejected = $false; try { & $Body | Out-Null } catch { $rejected = $true }
    Check $rejected $Name
}
Check ($errors.Count -eq 0) 'runner parses'
$source = $ast.Extent.Text
$pureNames = @('Resolve-SpeechChild','Resolve-SpeechOutput','Set-SpeechEnvironmentValue','Assert-SpeechSameRecords','Assert-SpeechBaseline',
    'Get-SpeechBaselineIdentity','Assert-SpeechBaselineUnchanged','Get-SpeechDefinitions','Assert-SpeechBundleReport')
foreach ($name in $pureNames) {
    $functions = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true))
    Check ($functions.Count -eq 1) ('one pure function '+$name)
    . ([scriptblock]::Create($functions[0].Extent.Text))
}
# Mock all filesystem probes used by path guards; no fixture directory is created.
function Assert-SpeechPlainPath([string]$Path) { if ($Path -match 'indirect') { throw 'mock reparse point' } }
function Test-Path { param([string]$LiteralPath) return $LiteralPath -match 'existing' }
$repo = 'C:\fixture\repo'
$valid = 'C:\fixture\repo\.tmp\yimecore-experiment\speech-reconnect-new'
Check ((Resolve-SpeechOutput $repo $valid) -ceq $valid) 'new immediate output accepted'
Check ((Resolve-SpeechChild $repo 'go-backend/go.mod') -ceq 'C:\fixture\repo\go-backend\go.mod') 'canonical child accepted'
foreach ($bad in @('C:\fixture\repo','C:\fixture\repo\.tmp\yimecore-experiment','C:\fixture\elsewhere\speech-reconnect-new',
    'C:\fixture\repo\.tmp\yimecore-experiment\other-new','C:\fixture\repo\.tmp\yimecore-experiment\speech-reconnect-new\child',
    'C:\fixture\repo\.tmp\yimecore-experiment\speech-reconnect-existing','C:\fixture\repo\.tmp\yimecore-experiment\speech-reconnect-indirect',
    'C:\fixture\repo\.tmp\yimecore-experiment\speech-reconnect-old\..\speech-reconnect-new')) {
    Reject { Resolve-SpeechOutput $repo $bad } 'unsafe output rejected'
}
foreach ($bad in @('../file','a/../file','/absolute','C:\outside','x:stream','x//y','x./y','x /y','a/./y')) {
    Reject { Resolve-SpeechChild $repo $bad } 'noncanonical child rejected'
}
$records = @([ordered]@{path='b';bytes=2;sha256='bb'},[ordered]@{path='a';bytes=1;sha256='aa'})
Assert-SpeechSameRecords $records @($records[1],$records[0]); Check $true 'source order irrelevant'
Reject { Assert-SpeechSameRecords $records @($records[0]) } 'source removal rejected'
Reject { Assert-SpeechSameRecords $records @($records[0],[ordered]@{path='a';bytes=1;sha256='cc'}) } 'source drift rejected'
$digest = 'a' * 64
$keys = [ordered]@{}; 1..12 | ForEach-Object { $keys["key$_"] = $digest }
$baseline = [ordered]@{schema_version='yimecore-l5-metadata-v1';install_root='C:\fixture\installed';manifest_sha256=$digest;package_version='fixture';package_file_count=74;
    package_integrity_passed=$true;package_mismatches=@();runtime_identity_passed=$true;registered_x64_matches=$true;registered_x64_dll=@('C:\fixture\installed\x64\surface.dll');
    protected_registry_sha256=$keys;user_text_read=$false;learning_data_read=$false;boot_at='2026-09-05T00:00:00Z';
    processes=@([ordered]@{name='YimeCoreTrialRuntime.exe';pid=10;image='C:\fixture\installed\bin\YimeCoreTrialRuntime.exe';started_at='2026-09-05T00:01:00Z';current_package=$true;after_boot=$true},
        [ordered]@{name='YimeBroker.exe';pid=11;image='C:\fixture\installed\bin\YimeBroker.exe';started_at='2026-09-05T00:01:01Z';current_package=$true;after_boot=$true})} | ConvertTo-Json -Depth 12 | ConvertFrom-Json
Assert-SpeechBaseline $baseline 'C:\fixture\installed' $digest; Check $true 'complete synthetic baseline accepted'
Assert-SpeechBaselineUnchanged $baseline $baseline; Check $true 'same identity accepted'
foreach ($field in @('boot_at','manifest_sha256','package_version')) {
    $changed = $baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.$field = 'changed'
    Reject { Assert-SpeechBaselineUnchanged $baseline $changed } ('changed '+$field+' rejected')
}
foreach ($field in @('pid','image','started_at')) {
    $changed = $baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.processes[0].$field = 'changed'
    Reject { Assert-SpeechBaselineUnchanged $baseline $changed } ('changed process '+$field+' rejected')
}
$changed = $baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.protected_registry_sha256.key1 = 'b'*64
Reject { Assert-SpeechBaselineUnchanged $baseline $changed } 'changed protected key rejected'
$changed = $baseline | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.processes[1].name = 'YimeCoreTrialRuntime.exe'
Reject { Assert-SpeechBaseline $changed 'C:\fixture\installed' $digest } 'duplicate runtime rejected'
$ids = @((Get-SpeechDefinitions).id)
Check (($ids -join '|') -ceq 'psc-peripheral|explicit-erhua|third-tone-stage5c|particle-a-stage6d') 'four exact module IDs'
$builds = @{}; $modulePaths = [ordered]@{}; $coverage = @(); $checks = @()
foreach ($id in $ids) {
    $builds[$id] = @{build=@{indexed_records=2}}; $modulePaths[$id] = "fixture/$id.yidx"
    $coverage += @{module_id=$id;indexed_records=2;reachable_records=2;direct_first_page_records=1;direct_later_page_records=1;passed=$true}
    $checks += @{id=$id;module=$id;alias_available=$true;alias_source_verified=$true;canonical_available=$true;canonical_source_verified=$true;alias_removed_when_disabled=$true;canonical_survives_disable=$true;passed=$true}
}
$report = @{mode='full';passed=$true;module_indexes=$modulePaths;coverage=$coverage;checks=$checks} | ConvertTo-Json -Depth 12 | ConvertFrom-Json
Assert-SpeechBundleReport $report 'full' $builds; Check $true 'complete coverage and rollback accepted'
$changed = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.coverage[0].reachable_records = 1
Reject { Assert-SpeechBundleReport $changed 'full' $builds } 'coverage shortfall rejected'
$changed = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.checks[0].alias_removed_when_disabled = $false
Reject { Assert-SpeechBundleReport $changed 'full' $builds } 'rollback source failure rejected'
$changed = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.coverage[0].module_id = 'unknown'
Reject { Assert-SpeechBundleReport $changed 'full' $builds } 'unknown module rejected'
$changed = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $changed.checks = @($changed.checks[0])
Reject { Assert-SpeechBundleReport $changed 'full' $builds } 'missing probe module rejected'
Check ($source -match 'Get-YimeCoreDevelopmentScope' -and $source -match 'Assert-SpeechBaselineUnchanged') 'scope and baseline guards wired'
Check ($source -match "GOTOOLCHAIN='local'" -and $source -match "GOPROXY='off'" -and $source -match "GOSUMDB='off'" -and
    $source -match "GOWORK='off'" -and $source -match "GOENV='off'" -and $source -match "CGO_ENABLED='0'") 'offline local Go controls'
Check ($source -match 'environmentRestored' -and $source -match 'environment_restore_failures' -and $source -match 'GetEnvironmentVariable\(\$name') 'environment restoration verified'
Check ($source -notmatch 'Start-Process|Stop-Process|regsvr32|run-e4-connected|run-e7-cutover|capture-local-reboot|runtime-config\.json|runtime-status\.json|go test') 'no maintenance, old runner or user-state reads'
Check ($source -match "'-iterations','10'" -and $source -match '\$buildCount -ne 15') 'bounded complete matrix'
Check ($source -match 'broker_reconnect_gate_passed=\$null' -and $source -match 'real_rime_gate_passed=\$null' -and $source -match 'installed_reconnect_gate_passed=\$null') 'later gates never inferred'
Check ($source -match 'PSEdition -ne ''Core''' -and $source -match "\[version\]'7.5'") 'unsupported full-run shell rejected early'
# Restore the actual provider before testing one unique, test-owned variable.
# The test never mutates a normal product, user or toolchain environment name.
Remove-Item -LiteralPath Function:\Test-Path
$environmentName = 'YIME_SPEECH_ENV_TEST_' + [guid]::NewGuid().ToString('N')
$initial = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
Check ($null -eq $initial) 'test environment name initially absent'
try {
    $supportsExactEmpty = $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion -ge [version]'7.5'
    $values = @($null, 'speech-fixture-value')
    if ($supportsExactEmpty) { $values += '' }
    foreach ($value in $values) {
        Set-SpeechEnvironmentValue $environmentName $value
        $observed = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
        Check (($null -eq $value -and $null -eq $observed) -or ($null -ne $value -and $null -ne $observed -and $observed -ceq $value)) 'exact environment input state'
        $saved = $observed
        Set-SpeechEnvironmentValue $environmentName 'temporary-fixture-override'
        Set-SpeechEnvironmentValue $environmentName $saved
        $restored = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
        Check (($null -eq $saved -and $null -eq $restored) -or ($null -ne $saved -and $null -ne $restored -and $restored -ceq $saved)) 'exact environment round trip'
    }
    if (-not $supportsExactEmpty) {
        Reject { Set-SpeechEnvironmentValue $environmentName '' } 'unsupported empty environment state rejected, not normalized'
        Check ($null -eq [Environment]::GetEnvironmentVariable($environmentName, 'Process')) 'legacy managed empty assignment loses presence as expected'
    }
} finally {
    Set-SpeechEnvironmentValue $environmentName $initial
}
Check ($null -eq [Environment]::GetEnvironmentVariable($environmentName, 'Process')) 'test environment name removed'
Write-Output "PASS: $count static/pure synthetic speech reconnect contracts; no baseline, tool build, Rime, Broker or host execution."
