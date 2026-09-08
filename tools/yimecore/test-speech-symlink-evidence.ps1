[CmdletBinding()]
param([switch]$RequireFixtures, [string]$OutputRoot)
# Source/fixture-only SR4-B supplement, compatible with PS5.1 and PS7.
# Never elevates, changes Developer Mode, opens installed packages or user data.
$ErrorActionPreference='Stop'
function Get-SymlinkEvidenceStatus($Terminal, [string]$Output, [bool]$Required, [bool]$PolicyTest) {
 if (@($Terminal).Count -ne 1) { return 'FAIL' }
 if ($Terminal[0] -ceq 'pass' -and ($PolicyTest -or ($Output.Contains('SYMLINK_FIXTURE_READY') -and $Output.Contains('SYMLINK_REJECTION_EXERCISED')))) { return 'PASS' }
 if ($Terminal[0] -ceq 'skip' -and -not $Required -and $Output.Contains('SYMLINK_FIXTURE_UNAVAILABLE windows_error=1314 rejection_exercised=false')) { return 'SKIP' }
 return 'FAIL'
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=Join-Path $repo ('.tmp\sr4b-symlink-'+[guid]::NewGuid().ToString('N'))
if ($OutputRoot) {
 $out=[IO.Path]::GetFullPath($OutputRoot)
 if ((Split-Path -Parent $out) -ine (Join-Path $repo '.tmp') -or (Split-Path -Leaf $out) -cnotmatch '^sr4b-symlink-[a-zA-Z0-9-]+$') { throw 'Output must be a new .tmp/sr4b-symlink-* directory.' }
}
if (Test-Path -LiteralPath $out) { throw 'Preserve previous evidence: output must not exist.' }
for ($p=$out; $p; $p=Split-Path -Parent $p) {
    if (Test-Path -LiteralPath $p) {
        if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Indirect fixture parent: $p" }
    }
}
New-Item -ItemType Directory -Path $out | Out-Null
$envs=@{TEMP="$out\temp";TMP="$out\temp";APPDATA="$out\appdata";LOCALAPPDATA="$out\localappdata";
 GOCACHE="$out\gocache";GOMODCACHE="$out\gomodcache";GOPATH="$out\gopath";
 GOENV='off';GOWORK='off';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOTELEMETRY='off';
 GOOS='windows';GOARCH='amd64';CGO_ENABLED='0';GOFLAGS='';GOEXPERIMENT='';
 YIME_REQUIRE_SYMLINK_FIXTURE='0'}
if ($RequireFixtures) { $envs.YIME_REQUIRE_SYMLINK_FIXTURE='1' }
$saved=@{}; $rows=@(); $failure=$null; $logs=@(); $parserCases=@()
$jobs=@(
 @{package='./cmd/yimecore-speech-admission';names=@('TestSpeechPackageRejectsSymlinkPayload','TestSpeechProductExportRejectsIndirectSources')},
 @{package='./cmd/yimecore-independence-audit';names=@('TestLocalSpeechContractRejectsIndirectResources')},
 @{package='./input_methods/yime/speechruntime';names=@('TestSpeechManifestRejectsOutsideAndIndirectPaths/symlink')},
 @{package='./internal/symlinkfixture';names=@('TestUnavailableClassification')})
try {
 # Synthetic reporting contracts are explicitly separate from real OS evidence.
 $ready='SYMLINK_FIXTURE_READY SYMLINK_REJECTION_EXERCISED'
 $unavailable='SYMLINK_FIXTURE_UNAVAILABLE windows_error=1314 rejection_exercised=false'
 foreach ($case in @(
  @{name='exercised';terminal=@('pass');output=$ready;required=$false;want='PASS'},
  @{name='unavailable';terminal=@('skip');output=$unavailable;required=$false;want='SKIP'},
  @{name='required-unavailable';terminal=@('skip');output=$unavailable;required=$true;want='FAIL'},
  @{name='unexplained-skip';terminal=@('skip');output='access denied';required=$false;want='FAIL'},
  @{name='unexercised-pass';terminal=@('pass');output='';required=$false;want='FAIL'},
  @{name='missing-test';terminal=@();output='';required=$false;want='FAIL'},
  @{name='duplicate-terminal';terminal=@('pass','skip');output=$ready;required=$false;want='FAIL'},
  @{name='failed-after-ready';terminal=@('fail');output=$ready;required=$false;want='FAIL'})) {
  $actual=Get-SymlinkEvidenceStatus $case.terminal $case.output $case.required $false
  $parserCases+=@{name=$case.name;expected=$case.want;actual=$actual;passed=($actual -ceq $case.want);synthetic=$true}
  if ($actual -cne $case.want) { throw 'Reporting classification contract failed.' }
 }
 foreach ($key in $envs.Keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,$envs[$key],'Process') }
 foreach ($key in @('TEMP','APPDATA','LOCALAPPDATA','GOCACHE','GOMODCACHE','GOPATH')) { New-Item -ItemType Directory -Path $envs[$key] -Force | Out-Null }
 Push-Location (Join-Path $repo 'go-backend')
 try {
  $i=0
  foreach ($job in $jobs) {
   $i++; $log=Join-Path $out "go-$i.jsonl"
   $pattern='^('+($job.names -join '|')+')$'
   # Go splits -run at slash; use exact parent/subtest selection for the fourth gap.
   if ($i -eq 3) { $pattern='^TestSpeechManifestRejectsOutsideAndIndirectPaths$/^symlink$' }
   & 'C:\Program Files\Go\bin\go.exe' test -json -count=1 -timeout=3m $job.package -run $pattern 1> $log 2> "$log.stderr"
   $exitCode=$LASTEXITCODE
   $events=@(Get-Content -LiteralPath $log -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
   $logs+=@{path=$log;sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant();exit_code=$exitCode}
   foreach ($name in $job.names) {
    $terminal=@($events | Where-Object { $_.Test -ceq $name -and $_.Action -in @('pass','skip','fail') })
    $output=(@($events | Where-Object { $_.Test -ceq $name -and $_.Action -eq 'output' } | ForEach-Object { $_.Output }) -join '')
    $status=Get-SymlinkEvidenceStatus @($terminal | ForEach-Object { $_.Action }) $output ([bool]$RequireFixtures) ($i -eq 4)
    $exercised=($status -eq 'PASS' -and $i -ne 4)
    $rows+=@{package=$job.package;test=$name;status=$status;rejection_exercised=$exercised;output=$output;kind=$(if($i -eq 4){'classification-contract'}else{'os-negative-test'})}
   }
   if ($exitCode -ne 0) { $failure='One or more Go invocations failed; inspect preserved logs.' }
  }
 } finally { Pop-Location }
} catch { $failure=$_.Exception.Message }
finally {
 foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
 $negative=@($rows | Where-Object kind -eq 'os-negative-test')
 $failed=@($rows | Where-Object status -eq 'FAIL').Count
 $skipped=@($negative | Where-Object status -eq 'SKIP').Count
 $exercised=@($negative | Where-Object rejection_exercised -eq $true).Count
 $passed=($null -eq $failure -and $rows.Count -eq 5 -and $failed -eq 0)
 $result=[ordered]@{schema_version='yimecore-sr4b-symlink-evidence-v1';generated_at=(Get-Date).ToString('o');
  powershell_version=$PSVersionTable.PSVersion.ToString();require_fixtures=[bool]$RequireFixtures;
  passed=$passed;checks_count=$rows.Count;failed_count=$failed;skipped_count=$skipped;
  exercised_rejection_count=$exercised;all_four_rejections_exercised=($exercised -eq 4);failure=$failure;tests=$rows;logs=$logs;
  synthetic_reporting_contracts=$parserCases;
  fixture_root=$out;installed_package_accessed=$false;maintenance_executed=$false;user_data_accessed=$false;
  default_input_method_changed=$false;package_rebuilt=$false;product_process_executed=$false}
 $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $out 'result.json') -Encoding UTF8
 Write-Output "Evidence: $out\result.json; exercised=$exercised/4; SKIP=$skipped; passed=$passed"
}
if (-not $passed) { throw 'SR4-B symlink evidence failed; unavailable fixtures never count as exercised rejection.' }
