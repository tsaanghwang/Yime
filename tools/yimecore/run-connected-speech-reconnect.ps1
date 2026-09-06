[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
    [string]$OutputRoot
)
# SR0 only: reviewed, immutable dictionaries -> private indexes -> bundle probes.
# This script never starts a Broker, a registered host, Rime or maintenance.
$ErrorActionPreference = 'Stop'

function Assert-SpeechPlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Speech reconnect paths cannot traverse reparse points.'
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
}
function Resolve-SpeechChild([string]$Root, [string]$Relative) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match ':|(^|[\\/])\.?\.?([\\/]|$)|[. ]([\\/]|$)') {
        throw 'Noncanonical relative speech path.'
    }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Speech path escaped its root.' }
    Assert-SpeechPlainPath $path
    return $path
}
function Resolve-SpeechOutput([string]$Repo, [string]$Requested) {
    $allowed = Join-Path $Repo '.tmp\yimecore-experiment'
    if (-not $Requested) { $Requested = Join-Path $allowed ('speech-reconnect-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')) }
    if ($Requested -match '(^|[\\/])\.\.?([\\/]|$)|[. ]([\\/]|$)') { throw 'Use a canonical speech output path without dot segments.' }
    $path = [IO.Path]::GetFullPath($Requested)
    if ((Split-Path -Parent $path) -ine [IO.Path]::GetFullPath($allowed) -or
        (Split-Path -Leaf $path) -cnotmatch '^speech-reconnect-[A-Za-z0-9-]+$') { throw 'Use a new immediate speech-reconnect child of .tmp/yimecore-experiment.' }
    Assert-SpeechPlainPath $path
    if (Test-Path -LiteralPath $path) { throw 'Speech reconnect output already exists; preserve it.' }
    return $path
}
function Write-SpeechJson($Value, [string]$Path) {
    ConvertTo-Json -InputObject $Value -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Set-SpeechEnvironmentValue([string]$Name, $Value) {
    # PowerShell can coerce $null to an empty managed string. Absence is a
    # different state: remove it through the provider and verify exact readback.
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw 'Invalid isolated environment variable name.' }
    if ($null -eq $Value) {
        $path = 'Env:\' + $Name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop }
    } else {
        [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process')
    }
    $actual = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (($null -eq $Value -and $null -ne $actual) -or
        ($null -ne $Value -and ($null -eq $actual -or $actual -cne [string]$Value))) {
        throw 'Exact process environment state did not apply; null and empty are not interchangeable.'
    }
}
function Get-SpeechRecord([string]$Root, [string]$Relative) {
    $path = Resolve-SpeechChild $Root $Relative
    $file = Get-Item -LiteralPath $path
    if ($file.PSIsContainer) { throw 'Expected a speech input file.' }
    [pscustomobject][ordered]@{path=$Relative.Replace('\','/');bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Assert-SpeechSameRecords($Before, $After) {
    $left = @($Before | ForEach-Object { [pscustomobject][ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256} } | Sort-Object path)
    $right = @($After | ForEach-Object { [pscustomobject][ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256} } | Sort-Object path)
    if ((ConvertTo-Json -InputObject $left -Depth 8 -Compress) -cne (ConvertTo-Json -InputObject $right -Depth 8 -Compress)) { throw 'Speech source/input file set or hashes changed; preserve this run.' }
}
function Assert-SpeechBaseline($Value, [string]$Root, [string]$Hash) {
    if ($Value.schema_version -ne 'yimecore-l5-metadata-v1' -or $Value.install_root -ine [IO.Path]::GetFullPath($Root) -or
        $Value.manifest_sha256 -ine $Hash -or $Value.package_integrity_passed -ne $true -or
        @($Value.package_mismatches).Count -ne 0 -or $Value.runtime_identity_passed -ne $true -or
        $Value.registered_x64_matches -ne $true -or @($Value.processes).Count -ne 2 -or
        @($Value.protected_registry_sha256.PSObject.Properties).Count -ne 12 -or
        $Value.user_text_read -ne $false -or $Value.learning_data_read -ne $false) { throw 'Pinned installed metadata baseline failed.' }
    foreach ($name in @('YimeCoreTrialRuntime.exe','YimeBroker.exe')) {
        $matches = @($Value.processes | Where-Object name -ieq $name)
        if ($matches.Count -ne 1 -or $matches[0].current_package -ne $true -or $matches[0].after_boot -ne $true) { throw 'Unexpected daily runtime process set.' }
    }
    foreach ($property in $Value.protected_registry_sha256.PSObject.Properties) {
        if ([string]$property.Value -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid protected registration digest.' }
    }
}
function Get-SpeechBaselineIdentity($Value) {
    $keys = @($Value.protected_registry_sha256.PSObject.Properties | Sort-Object Name | ForEach-Object { [ordered]@{name=$_.Name;sha256=$_.Value} })
    $processes = @($Value.processes | Sort-Object name | ForEach-Object { [ordered]@{name=$_.name;pid=$_.pid;image=$_.image;started_at=$_.started_at} })
    [ordered]@{install_root=$Value.install_root;manifest_sha256=$Value.manifest_sha256;package_version=$Value.package_version;
        package_file_count=$Value.package_file_count;boot_at=$Value.boot_at;processes=$processes;registered_x64_dll=@($Value.registered_x64_dll);protected=$keys}
}
function Assert-SpeechBaselineUnchanged($Before, $After) {
    $left = Get-SpeechBaselineIdentity $Before
    $right = Get-SpeechBaselineIdentity $After
    if ((ConvertTo-Json $left -Depth 12 -Compress) -cne (ConvertTo-Json $right -Depth 12 -Compress)) { throw 'Installed package, daily process, boot or protected registry changed; no repair attempted.' }
}
function Get-SpeechDefinitions {
    @(
        [ordered]@{id='psc-peripheral';stem='yime_psc_peripheral_sentence';manifest='yime_psc_peripheral_manifest.json';role='psc_neutral_tone_and_erhua_layer';outputs=@('yime_psc_peripheral_{0}.dict.yaml','yime_psc_peripheral_sentence_{0}.dict.yaml')},
        [ordered]@{id='explicit-erhua';stem='yime_erhua_mixed_sentence';manifest='yime_erhua_mixed_manifest.json';role='explicit_erhua_layer';outputs=@('yime_erhua_mixed_{0}.dict.yaml','yime_erhua_mixed_sentence_{0}.dict.yaml','yime_sentence_{0}.dict.yaml','yime_erhua_reverse_source.tsv')},
        [ordered]@{id='third-tone-stage5c';stem='yime_third_tone_stage5c';manifest='yime_third_tone_stage5c_manifest.json';role='third_tone_sandhi_layer';outputs=@('yime_third_tone_stage5c_{0}.dict.yaml')},
        [ordered]@{id='particle-a-stage6d';stem='yime_particle_a_stage6d';manifest='yime_particle_a_stage6d_manifest.json';role='particle_a_sound_change_layer';outputs=@('yime_particle_a_stage6d_{0}.dict.yaml')}
    )
}
function Get-SpeechLockedInputs([string]$Repo) {
    $dataRelative = 'go-backend/input_methods/yime/data/'
    $dataRoot = Resolve-SpeechChild $Repo $dataRelative.TrimEnd('/')
    $lockRelative = 'tools/lexicon/data/yime_core_target.lock.json'
    $lock = Get-Content -LiteralPath (Resolve-SpeechChild $Repo $lockRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
    $records = @{}; $records[$lockRelative] = Get-SpeechRecord $Repo $lockRelative
    $roles = [ordered]@{full_mode_dictionary='yime_full.dict.yaml';variable_mode_dictionary='yime_variable.dict.yaml';shorthand_mode_dictionary='yime_shorthand.dict.yaml'}
    foreach ($definition in Get-SpeechDefinitions) { $roles[$definition.role] = $definition.manifest }
    foreach ($role in $roles.Keys) {
        $entries = @($lock.artifacts | Where-Object role -ceq $role)
        $relative = $dataRelative + $roles[$role]
        if ($entries.Count -ne 1 -or $entries[0].path -cne $relative -or [string]$entries[0].sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Target lock role/path is not exactly allowlisted.' }
        $record = Get-SpeechRecord $Repo $relative
        if ($record.sha256 -ine $entries[0].sha256 -or $record.bytes -ne $entries[0].size) { throw 'Locked speech input hash/size mismatch.' }
        $records[$relative] = $record
    }
    foreach ($definition in Get-SpeechDefinitions) {
        $manifest = Get-Content -LiteralPath (Resolve-SpeechChild $dataRoot $definition.manifest) -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.summary.passed -ne $true) { throw 'Reviewed speech manifest is not passed.' }
        $expected = @(foreach ($template in $definition.outputs) {
            if ($template.Contains('{0}')) { foreach ($mode in @('full','variable','shorthand')) { $template -f $mode } } else { $template }
        }) | Sort-Object -Unique
        $actual = @($manifest.output_sha256.PSObject.Properties.Name | Sort-Object)
        if (($expected -join '|') -cne ($actual -join '|')) { throw 'Reviewed manifest output set is not exactly allowlisted.' }
        foreach ($property in $manifest.output_sha256.PSObject.Properties) {
            $relative = $dataRelative + $property.Name
            $record = Get-SpeechRecord $Repo $relative
            if ([string]$property.Value -notmatch '^[a-fA-F0-9]{64}$' -or $record.sha256 -ine $property.Value) { throw 'Reviewed module output hash mismatch.' }
            $records[$relative] = $record
        }
    }
    foreach ($mode in @('full','variable','shorthand')) {
        $relative = $dataRelative + "yime_sentence_$mode.dict.yaml"
        $imports = @(Get-Content -LiteralPath (Resolve-SpeechChild $Repo $relative) | Where-Object { $_ -match '^\s+-\s+' } | ForEach-Object { ($_ -replace '^\s+-\s+','').Trim() })
        $expected = @("yime_$mode") + @(Get-SpeechDefinitions | ForEach-Object { $_.stem + '_' + $mode })
        if (($imports -join '|') -cne ($expected -join '|')) { throw 'Three-mode speech import closure changed.' }
        $records[$relative] = Get-SpeechRecord $Repo $relative
    }
    @($records.Values | Sort-Object path)
}
function Get-SpeechSourceRecords([string]$Repo) {
    $paths = @('go-backend/go.mod','docs/project/MANDARIN_CONNECTED_SPEECH_PLAN.md','tools/yimecore/development-scope.json',
        'tools/yimecore/development-scope.ps1','tools/yimecore/local-maintenance-safety.ps1','tools/yimecore/get-l5-daily-use-baseline.ps1',
        'tools/yimecore/run-connected-speech-reconnect.ps1','tools/yimecore/test-connected-speech-reconnect.ps1')
    foreach ($relative in @('go-backend/input_methods/yime/engineapi','go-backend/input_methods/yime/yimecore',
        'go-backend/input_methods/yime/yimebroker','go-backend/cmd/yimebroker','go-backend/cmd/yimecore-trial-runtime',
        'go-backend/cmd/yimecore-index','go-backend/cmd/yimecore-bundle-experiment','go-backend/internal/processmemory')) {
        $directory = Resolve-SpeechChild $Repo $relative
        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -Force) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Speech source tree contains an indirect path.' }
            # Only these source trees: never inspect live state, logs or user files.
            if ($file.Extension -eq '.go' -or $file.Name -eq 'e4_reviewed_alias_probes.json') { $paths += $file.FullName.Substring($Repo.Length + 1).Replace('\','/') }
        }
    }
    @($paths | Sort-Object -Unique | ForEach-Object { Get-SpeechRecord $Repo $_ })
}
function Assert-SpeechBundleReport($Report, [string]$Mode, $Builds) {
    $ids = @((Get-SpeechDefinitions).id | Sort-Object)
    if ($Report.mode -cne $Mode -or $Report.passed -ne $true -or @($Report.checks).Count -eq 0 -or
        @($Report.coverage).Count -ne 4 -or (@($Report.module_indexes.PSObject.Properties.Name | Sort-Object) -join '|') -cne ($ids -join '|') -or
        (@($Report.coverage.module_id | Sort-Object) -join '|') -cne ($ids -join '|')) { throw 'Bundle summary/mode/module set failed.' }
    foreach ($item in $Report.checks) {
        if ($item.module -cnotin $ids -or $item.passed -ne $true) { throw 'Bundle probe failed or has unknown module.' }
        foreach ($name in @('alias_available','alias_source_verified','canonical_available','canonical_source_verified','alias_removed_when_disabled','canonical_survives_disable')) {
            if ($item.$name -ne $true) { throw 'Required bundle probe/rollback result missing.' }
        }
    }
    if ((@($Report.checks.module | Sort-Object -Unique) -join '|') -cne ($ids -join '|') -or
        @($Report.checks.id | Sort-Object -Unique).Count -ne @($Report.checks).Count) { throw 'Probe module coverage or unique IDs incomplete.' }
    foreach ($item in $Report.coverage) {
        $build = $Builds[$item.module_id]
        if ($null -eq $build -or $item.passed -ne $true -or $item.indexed_records -le 0 -or
            $item.indexed_records -ne $build.build.indexed_records -or $item.reachable_records -ne $item.indexed_records -or
            ($item.direct_first_page_records + $item.direct_later_page_records) -ne $item.indexed_records -or
            ($null -ne $item.inaccessible_or_shadowed_examples -and @($item.inaccessible_or_shadowed_examples).Count -ne 0)) { throw 'Full module source coverage failed.' }
    }
}
function Invoke-SpeechTool([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Isolated speech child failed (exit $LASTEXITCODE). No raw output retained." }
}

# Windows PowerShell 5.1 collapses an empty process value into absence. Reject
# unsupported hosts before baseline reads/output creation or environment changes.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5') {
    throw 'SR0 full execution requires PowerShell 7.5+ with exact empty environment values; use pwsh, not Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope = Get-YimeCoreDevelopmentScope
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$install = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
Assert-SpeechPlainPath $install
$out = Resolve-SpeechOutput $repo $OutputRoot
$go = (Get-Command go -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$baselineScript = Join-Path $PSScriptRoot 'get-l5-daily-use-baseline.ps1'
$before = & $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256.ToLowerInvariant() | ConvertFrom-Json
Assert-SpeechBaseline $before $install $ExpectedManifestSha256
$inputsBefore = @(Get-SpeechLockedInputs $repo)
$sourcesBefore = @(Get-SpeechSourceRecords $repo)
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
Write-SpeechJson $before (Join-Path $out 'installed-before.json')
Write-SpeechJson $inputsBefore (Join-Path $out 'locked-inputs-before.json')
Write-SpeechJson $sourcesBefore (Join-Path $out 'source-hashes-before.json')
$environment = [ordered]@{
    TEMP=(Join-Path $out 'private\temp');TMP=(Join-Path $out 'private\tmp');APPDATA=(Join-Path $out 'private\appdata');LOCALAPPDATA=(Join-Path $out 'private\localappdata');
    GOCACHE=(Join-Path $out 'private\gocache');GOMODCACHE=(Join-Path $out 'private\gomodcache');GOPATH=(Join-Path $out 'private\gopath');
    GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOWORK='off';GOENV='off';
    GOFLAGS='-mod=readonly -trimpath -buildvcs=false';GOPRIVATE=$null;GONOPROXY='none';GONOSUMDB='none';GOEXPERIMENT=$null;GOAMD64='v1';
    YIME_RUN_REAL_RIME_TESTS=$null;YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE=$null;YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST=$null;YIME_TEXTSERVICE_EXPERIMENT_PIPE=$null
}
$original = @{}; foreach ($name in $environment.Keys) { $original[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$passed = $false; $failure = $null; $after = $null; $protectionPassed = $false; $inputsUnchanged = $false; $sourcesUnchanged = $false
$environmentRestored = $false; $restoreFailures = @(); $modeResults = @(); $toolRecords = @(); $buildCount = 0
$goVersion = $null
try {
    foreach ($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA','GOCACHE','GOMODCACHE','GOPATH')) { New-Item -ItemType Directory -Path $environment[$name] | Out-Null }
    foreach ($name in $environment.Keys) {
        Set-SpeechEnvironmentValue $name $environment[$name]
    }
    $bin = Join-Path $out 'bin'; New-Item -ItemType Directory -Path $bin | Out-Null
    $versionLines = @(& $go version)
    if ($LASTEXITCODE -ne 0 -or $versionLines.Count -ne 1 -or [string]$versionLines[0] -notmatch '^go version go[0-9][A-Za-z0-9.]* windows/amd64$') { throw 'Expected a local Windows AMD64 Go toolchain.' }
    $goVersion = [string]$versionLines[0]
    Push-Location (Join-Path $repo 'go-backend')
    try {
        foreach ($name in @('yimecore-index','yimecore-bundle-experiment')) {
            Invoke-SpeechTool $go @('build','-o',(Join-Path $bin "$name.exe"),("./cmd/$name"))
            $toolRecords += Get-SpeechRecord $out "bin/$name.exe"
        }
    } finally { Pop-Location }
    $data = Join-Path $repo 'go-backend\input_methods\yime\data'
    $probes = Join-Path $repo 'go-backend\input_methods\yime\yimecore\testdata\e4_reviewed_alias_probes.json'
    foreach ($mode in @('full','variable','shorthand')) {
        $directory = Join-Path $out "indexes\$mode"; New-Item -ItemType Directory -Path $directory | Out-Null
        $sources = [ordered]@{core="yime_$mode.dict.yaml"}
        foreach ($definition in Get-SpeechDefinitions) { $sources[$definition.id] = $definition.stem + "_$mode.dict.yaml" }
        $indexes = [ordered]@{}; $builds = [ordered]@{}
        foreach ($id in $sources.Keys) {
            $indexPath = Join-Path $directory "$id.yidx"; $buildPath = Join-Path $directory "$id-build.json"
            Invoke-SpeechTool (Join-Path $bin 'yimecore-index.exe') @('-mode',$mode,'-source',(Join-Path $data $sources[$id]),'-output',$indexPath,
                '-manifest',$buildPath,'-allowed-source-root',$data,'-allowed-output-root',$out)
            $build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($build.verified -ne $true -or $build.build.mode -cne $mode -or $build.build.indexed_records -le 0 -or
                $build.build.source_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $data $sources[$id]) -Algorithm SHA256).Hash -or
                $build.build.index_sha256 -ine (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash) { throw 'New index build metadata/hash failed.' }
            $indexes[$id] = $indexPath; $builds[$id] = $build; $buildCount++
        }
        $bundlePath = Join-Path $out "bundle-$mode.json"
        $arguments = @('-mode',$mode,'-core-index',$indexes.core,'-probes',$probes,'-output',$bundlePath,'-iterations','10')
        foreach ($definition in Get-SpeechDefinitions) { $arguments += @('-module',($definition.id + '=' + $indexes[$definition.id])) }
        Invoke-SpeechTool (Join-Path $bin 'yimecore-bundle-experiment.exe') $arguments
        $report = Get-Content -LiteralPath $bundlePath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-SpeechBundleReport $report $mode $builds
        $modeResults += [ordered]@{mode=$mode;passed=$true;bundle_source_id=$report.bundle_source_id;index_builds=$builds;
            probe_checks=$report.checks;module_coverage=$report.coverage;bundle_evidence=Get-SpeechRecord $out "bundle-$mode.json"}
    }
    if ($buildCount -ne 15 -or $modeResults.Count -ne 3) { throw 'Incomplete three-mode reconnect matrix.' }
    $passed = $true
} catch { $failure = $_.Exception.Message }
finally {
    foreach ($name in $environment.Keys) {
        try {
            Set-SpeechEnvironmentValue $name $original[$name]
        } catch { $restoreFailures += $name }
    }
    $environmentRestored = $restoreFailures.Count -eq 0
    try {
        $inputsAfter = @(Get-SpeechLockedInputs $repo); Write-SpeechJson $inputsAfter (Join-Path $out 'locked-inputs-after.json')
        Assert-SpeechSameRecords $inputsBefore $inputsAfter; $inputsUnchanged = $true
        $sourcesAfter = @(Get-SpeechSourceRecords $repo); Write-SpeechJson $sourcesAfter (Join-Path $out 'source-hashes-after.json')
        Assert-SpeechSameRecords $sourcesBefore $sourcesAfter; $sourcesUnchanged = $true
    } catch { if (-not $failure) { $failure = $_.Exception.Message } }
    try {
        $after = & $baselineScript -InstallRoot $install -ExpectedManifestSha256 $ExpectedManifestSha256.ToLowerInvariant() | ConvertFrom-Json
        Write-SpeechJson $after (Join-Path $out 'installed-after.json')
        Assert-SpeechBaseline $after $install $ExpectedManifestSha256
        Assert-SpeechBaselineUnchanged $before $after; $protectionPassed = $true
    } catch { if (-not $failure) { $failure = $_.Exception.Message } }
    $passed = $passed -and $protectionPassed -and $inputsUnchanged -and $sourcesUnchanged -and $environmentRestored
    $summary = [ordered]@{schema_version='yimecore-speech-reconnect-sr0-v1';generated_at=(Get-Date).ToString('o');development_scope=$scope;
        sr0_passed=$passed;failure=$failure;install_root=$install;manifest_sha256=$ExpectedManifestSha256.ToLowerInvariant();index_build_count=$buildCount;
        go_toolchain_path=$go;go_version=$goVersion;tools=$toolRecords;modes=$modeResults;locked_inputs_unchanged=$inputsUnchanged;source_set_unchanged=$sourcesUnchanged;installed_baseline_unchanged=$protectionPassed;
        private_environment_names=@($environment.Keys);environment_restored=$environmentRestored;environment_restore_failures=$restoreFailures;
        iterations=10;performance_ratio_gate_run=$false;real_rime_executed=$false;real_rime_gate_passed=$null;broker_executed=$false;broker_reconnect_gate_passed=$null;
        installed_reconnect_gate_passed=$null;new_package_installed=$false;registered_hosts_executed=$false;frozen_targets_executed=$false;
        user_text_read=$false;live_config_read=$false;learning_data_read=$false;daily_broker_connected=$false;product_or_registry_mutated=$false;
        local_product_ready=$false;public_release_ready=$false;
        limitations=@('SR0 validates existing reviewed module indexes only; no new rules, runtime inference or canonical rewrite.',
            'PSC is a reviewed canonical neutral-tone/erhua auxiliary layer, not new contextual neutral-tone behavior.',
            'Module disable is immutable bundle reconstruction; product UI/configuration persistence and Broker wiring are not tested.',
            'The existing bundle tool records isolated timings; no performance comparison or acceptance is inferred.',
            'Fresh four-yinyuan projection and non-lengthening admission, real Rime, Broker, packaging and installed-host gates remain separate.',
            'L5 daily-use confirmation and L6 final sealing remain user-controlled; this run cannot close them.')}
    Write-SpeechJson $summary (Join-Path $out 'summary.json')
}
if (-not $passed) { throw "SR0 speech reconnect did not pass; inspect only isolated evidence: $out" }
Write-Output "PASS: SR0 reviewed speech bundles only; Broker/Rime/install gates not inferred. Evidence: $out"
