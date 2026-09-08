[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
. (Join-Path $PSScriptRoot 'local-product-speech-build.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$out=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $out) -ine (Join-Path $repo '.tmp\yimecore-experiment') -or
    (Split-Path -Leaf $out) -cnotmatch '^speech-build-contract-[a-zA-Z0-9-]+$' -or (Test-Path -LiteralPath $out)) { throw 'Use a fresh immediate speech-build-contract-* output.' }
Assert-LocalProductPlainPath $out
New-Item -ItemType Directory -Path $out | Out-Null
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body | Out-Null; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Must-Reject([scriptblock]$Body) { $rejected=$false; try { & $Body | Out-Null } catch { $rejected=$true }; Assert-True $rejected 'Invalid fixture was accepted.' }
function New-Descriptor { Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
$product=New-Descriptor
$descriptor=Join-Path $out 'descriptor.json'
Check 'declared-default-off-descriptor' {
    Write-LocalProductJson $product $descriptor
    $v=Get-LocalProductDescriptor $descriptor
    Assert-True (-not $v.speech.default_enabled) 'Speech default changed.'
}
$old=New-Descriptor; $old.PSObject.Properties.Remove('speech'); $old.version='0.1.0-local.12'
Check 'older-core-only-descriptor-remains-valid' {
    Write-LocalProductJson $old $descriptor
    $v=Get-LocalProductDescriptor $descriptor
    Assert-True (-not (Assert-LocalProductSpeechBuildInputs $v '' '' '')) 'Old product requested speech.'
}
foreach ($bad in @('null','empty','true','string','path','extra')) {
    Check ('invalid-capability-'+$bad) {
        $v=New-Descriptor
        switch ($bad) {
            null { $v.speech=$null }; empty { $v.speech=[pscustomobject]@{} }
            true { $v.speech.default_enabled=$true }; string { $v.speech.default_enabled='false' }
            path { $v.speech.capability_path='../speech-capability.json' }
            extra { $v.speech | Add-Member extra $true }
        }
        Write-LocalProductJson $v $descriptor
        Must-Reject { Get-LocalProductDescriptor $descriptor }
    }
}
$pin='a'*64
Check 'declared-capability-requires-explicit-pins' { Must-Reject { Assert-LocalProductSpeechBuildInputs $product '' '' '' } }
Check 'undeclared-capability-rejects-speech-inputs' { Must-Reject { Assert-LocalProductSpeechBuildInputs $old $out $pin $pin } }
$admission=Join-Path $out 'speech-admission-synthetic'
New-Item -ItemType Directory -Path $admission | Out-Null
$inventory=Join-Path $admission 'source-hashes-after.json'
Write-LocalProductJson @([ordered]@{path='synthetic-source';sha256=$pin;bytes=1}) $inventory
$inventorySHA=(Get-FileHash -LiteralPath $inventory -Algorithm SHA256).Hash.ToLowerInvariant()
$summaryPath=Join-Path $admission 'summary.json'
function New-Summary {
    [ordered]@{schema_version='yimecore-speech-admission-isolated-v1';passed=$true;stage='complete';reviewed_records=24;mode_alias_rows=72;
        source_inventory=[ordered]@{path='source-hashes-after.json';sha256=$inventorySHA;bytes=(Get-Item -LiteralPath $inventory).Length};
        source_inventory_before=[ordered]@{path='source-hashes-before.json';sha256=$inventorySHA;bytes=(Get-Item -LiteralPath $inventory).Length}}
}
Check 'bound-summary-preflight-accepts-synthetic-envelope-only' {
    Write-LocalProductJson (New-Summary) $summaryPath
    $summarySHA=(Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True (Assert-LocalProductSpeechBuildInputs $product $admission $summarySHA $inventorySHA) 'Valid preflight failed.'
    # This envelope does not prove semantic admission; actual Go export validates it independently.
}
foreach ($bad in @('summary-pin','inventory-pin','before-pin','incomplete','bytes','records')) {
    Check ('reject-'+$bad) {
        $v=New-Summary
        switch ($bad) { 'before-pin' {$v.source_inventory_before.sha256=$pin}; incomplete {$v.stage='incomplete'}; bytes {$v.source_inventory.bytes=0}; records {$v.reviewed_records=23} }
        Write-LocalProductJson $v $summaryPath
        $summarySHA=(Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $sourceSHA=$inventorySHA
        if ($bad -ceq 'summary-pin') {$summarySHA=$pin}; if ($bad -ceq 'inventory-pin') {$sourceSHA=$pin}
        Must-Reject { Assert-LocalProductSpeechBuildInputs $product $admission $summarySHA $sourceSHA }
    }
}
Check 'exact-eleven-non-tool-payloads' {
    $paths=@(Get-LocalProductSpeechPayloadPaths)
    Assert-True ($paths.Count -eq 11 -and @($paths | Sort-Object -Unique).Count -eq 11) 'Payload count or uniqueness wrong.'
    Assert-True (@($paths | Where-Object {$_ -match '\.(exe|py)$|(^|/)(sources|state|private)/|bundle-(on|off)'}).Count -eq 0) 'Fixture or tool leaked into payload.'
}
Check 'protection-evidence-hashes-only-no-raw-registry-values' {
    function Read-YimeCoreSystemKey { param($Hive,$Path) [ordered]@{exists=$true;synthetic='fixture-value-not-for-evidence';value_kind=1} }
    $v=Get-LocalProductProtectionEvidence -HashesOnly
    Assert-True ($v.registry.Count -eq 19) 'Protection key count changed unexpectedly.'
    foreach ($value in $v.registry.Values) { Assert-True ($value -cmatch '^[a-f0-9]{64}$') 'Registry evidence not hashed.' }
    Assert-True (($v | ConvertTo-Json -Depth 30 -Compress) -notmatch 'fixture-value-not-for-evidence') 'Raw fixture value exposed.'
}
Check 'build-order-and-export-output-isolation-source-contract' {
    $builder=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-local-product.ps1') -Raw
    Assert-True ($builder.IndexOf('Assert-LocalProductSpeechBuildInputs') -lt $builder.IndexOf('New-LocalProductBuildRoot')) 'Build mutated output before admission input preflight.'
    Assert-True ($builder.IndexOf('$indexEvidence = @()') -lt $builder.IndexOf('Add-LocalProductSpeechPayload') -and
        $builder.IndexOf('Add-LocalProductSpeechPayload') -lt $builder.IndexOf('$manifest = [ordered]')) 'Speech staging order wrong.'
    Assert-True (($builder -split 'Get-LocalProductProtectionEvidence -HashesOnly').Count -eq 3) 'Both protection snapshots must be hash-only.'
    $helper=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-product-speech-build.ps1') -Raw
    Assert-True ($helper.Contains('-export-receipt $mappingPath | Out-Host')) 'Exporter stdout would pollute build-input binding.'
    Assert-True ($helper.Contains('-summary-sha256 $SummarySHA256.ToLowerInvariant()') -and
        $helper.Contains('-source-inventory-sha256 $SourceInventorySHA256.ToLowerInvariant()')) 'Accepted uppercase pins must be normalized at the strict Go CLI boundary.'
    Assert-True ($helper.Contains('[IO.File]::Copy($source,$destination,$false)')) 'Speech staging may overwrite files.'
}
Check 'admission-collector-covers-independent-exporter-fixed-sources' {
    # Execute only the reviewed source inventory function against owned empty
    # code trees. Synthetic record helpers return paths without reading files.
    # This covers the actual runner, unlike exporter fixtures generated from
    # exportFixedSources itself, which could not detect the omitted runner row.
    $runner=Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1'
    $tokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$parseErrors)
    Assert-True (@($parseErrors).Count -eq 0) 'Admission runner parse failed.'
    $functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-AdmissionSourceRecords'},$false))
    Assert-True ($functions.Count -eq 1) 'Admission inventory function is ambiguous.'
    $fixture=Join-Path $out 'source-collector-fixture'
    foreach ($tree in @('go-backend/input_methods/yime','go-backend/cmd','go-backend/internal','syllable','yime')) {
        New-Item -ItemType Directory -Path (Join-Path $fixture $tree) -Force | Out-Null
    }
    $collected=@(& {
        function Resolve-SpeechChild([string]$Root,[string]$Relative) { Join-Path $Root $Relative }
        function Get-SpeechRecord([string]$Root,[string]$Relative) { [pscustomobject]@{path=$Relative} }
        . ([scriptblock]::Create($functions[0].Extent.Text))
        Get-AdmissionSourceRecords $fixture
    })
    $exporter=Get-Content -LiteralPath (Join-Path $repo 'go-backend/cmd/yimecore-speech-admission/product_export.go') -Raw
    $block=[regex]::Match($exporter,'(?s)var exportFixedSources = \[\]string\{(.*?)\r?\n\}')
    Assert-True $block.Success 'Independent exporter fixed source declaration is unavailable.'
    $required=@([regex]::Matches($block.Groups[1].Value,'"([^"\r\n]+)"') | ForEach-Object {$_.Groups[1].Value})
    Assert-True ($required.Count -gt 0) 'Independent exporter source set is empty.'
    foreach ($path in $required) {
        Assert-True (@($collected | Where-Object {$_.path -ceq $path}).Count -eq 1) "Admission collector omitted or duplicated independent exporter source: $path"
    }
}
$failed=@($checks | Where-Object {-not $_.passed})
$sources=[ordered]@{}
foreach ($file in @('local-product.json','local-product-build-common.ps1','local-product-speech-build.ps1','build-local-product.ps1','test-local-product-speech-build.ps1')) {
    $sources[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$sources['run-connected-speech-admission.ps1']=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'run-connected-speech-admission.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
$sources['go-backend/cmd/yimecore-speech-admission/product_export.go']=(Get-FileHash -LiteralPath (Join-Path $repo 'go-backend/cmd/yimecore-speech-admission/product_export.go') -Algorithm SHA256).Hash.ToLowerInvariant()
Write-LocalProductJson ([ordered]@{schema_version='yimecore-speech-build-contract-v1';passed=($failed.Count -eq 0);checks=$checks.ToArray();checks_count=$checks.Count;
    failed_count=$failed.Count;powershell=$PSVersionTable.PSVersion.ToString();source_sha256=$sources;
    installed_or_user_data_read=$false;registry_read_or_written=$false;package_exported=$false;
    level='synthetic PowerShell preflight and source-order contracts; not semantic admission or package execution'}) (Join-Path $out 'result.json')
Write-Output "Speech build fixture: $($checks.Count) checks, $($failed.Count) failed; $out"
if ($failed.Count) { exit 1 }
