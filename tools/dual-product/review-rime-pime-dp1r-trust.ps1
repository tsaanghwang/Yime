[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateRepoRoot,
    [Parameter(Mandatory)][string]$IndependentPostbuildResultPath,
    [Parameter(Mandatory)][string]$OutputRoot
)

$ErrorActionPreference='Stop'
$actualRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
$candidate=[IO.Path]::GetFullPath($CandidateRepoRoot).TrimEnd([char]92)
$allowedParent=Join-Path $actualRepo '.tmp\dual-product'
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd([char]92)
if(-not $candidate.StartsWith($allowedParent+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $candidate) -cne 'repo' -or
    (Split-Path -Leaf (Split-Path -Parent $candidate)) -cnotmatch '^dp1-o-candidate-[A-Za-z0-9-]+$'){
    throw 'CandidateRepoRoot must be the repo child of a local dp1-o-candidate-* workspace.'
}
if((Split-Path -Parent $output) -ine $allowedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-r-trust-review-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-r-trust-review-* output root.'
}

function Assert-PlainPath([string]$Path,[bool]$MustExist=$true){
    $full=[IO.Path]::GetFullPath($Path)
    if($MustExist -and -not(Test-Path -LiteralPath $full)){throw "Required path is missing: $full"}
    for($cursor=$full;$cursor;$cursor=Split-Path -Parent $cursor){
        if(Test-Path -LiteralPath $cursor){
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse path rejected: $cursor"}
        }
        if($cursor -ieq (Split-Path -Qualifier $cursor)){break}
    }
    return $full
}
function Get-Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-SealedJson([string]$Path,[string]$Context){
    $full=Assert-PlainPath $Path
    $sidecar=Assert-PlainPath ($full+'.sha256')
    $digest=Get-Hash $full
    $line=[IO.File]::ReadAllText($sidecar).Trim()
    if($line -cnotmatch ('^'+[regex]::Escape($digest)+'(?:\s+\*?'+[regex]::Escape((Split-Path -Leaf $full))+')?$')){
        throw "$Context sidecar does not bind the JSON bytes."
    }
    try{$value=[IO.File]::ReadAllText($full)|ConvertFrom-Json}
    catch{throw "$Context is not valid JSON: $($_.Exception.Message)"}
    return [pscustomobject]@{Path=$full;Digest=$digest;Value=$value}
}
function Resolve-CandidatePath([string]$Relative,[string]$Context){
    if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains('..') -or $Relative.Contains(':')){
        throw "$Context path is not a canonical candidate-relative path."
    }
    $full=[IO.Path]::GetFullPath((Join-Path $candidate $Relative.Replace('/','\')))
    if(-not $full.StartsWith($candidate+'\',[StringComparison]::OrdinalIgnoreCase)){throw "$Context escaped candidate root."}
    return Assert-PlainPath $full
}
function Assert-False([object]$Value,[string]$Context){if($Value -isnot [bool] -or [bool]$Value){throw "$Context must remain false."}}
function Assert-True([object]$Value,[string]$Context){if($Value -isnot [bool] -or -not [bool]$Value){throw "$Context must be true."}}

$null=Assert-PlainPath $candidate
$independentPath=Assert-PlainPath $IndependentPostbuildResultPath
if(-not $independentPath.StartsWith($candidate+'\',[StringComparison]::OrdinalIgnoreCase)){
    throw 'Independent postbuild evidence must remain inside the isolated candidate repository for DP1-R review.'
}
$receiptLease=Read-SealedJson (Join-Path $candidate 'installer\package-build-receipt.json') 'strict candidate receipt'
$receipt=$receiptLease.Value
if([string]$receipt.schema_version -cne 'yime-rime-pime-package-build-receipt-v2' -or
    [string]$receipt.product -cne 'rime-pime' -or [string]$receipt.receipt_state -cne 'canonical-static-closure-disabled'){
    throw 'Candidate receipt is not the reviewed strict disabled v2 schema.'
}
foreach($name in @('generated_uninstaller_verified','generated_uninstaller_trusted','final_payload_closure',
    'delivery_admitted','installer_executed','uninstaller_executed','installed_product_processes_touched',
    'product_registry_mutated','default_input_method_changed','production_user_data_read_or_written',
    'installed_yimecore_local12_touched')){Assert-False $receipt.$name "candidate receipt $name"}
$buildLease=Read-SealedJson (Resolve-CandidatePath ([string]$receipt.disabled_build.result_path) 'build result') 'build result'
$primaryPostbuildLease=Read-SealedJson (Resolve-CandidatePath ([string]$receipt.static_postbuild.result_path) 'primary postbuild') 'primary postbuild'
$independentPostbuildLease=Read-SealedJson $independentPath 'independent postbuild'
if($buildLease.Digest -cne [string]$receipt.disabled_build.result_sha256 -or
    $primaryPostbuildLease.Digest -cne [string]$receipt.static_postbuild.result_sha256){
    throw 'Receipt evidence digest binding failed.'
}
$installerPath=Resolve-CandidatePath ([string]$receipt.installer.path) 'candidate installer'
if((Get-Hash $installerPath) -cne [string]$receipt.installer.sha256 -or
    (Get-Item -LiteralPath $installerPath).Length -ne [long]$receipt.installer.bytes){
    throw 'Physical candidate installer differs from its strict receipt.'
}
$installerSourcePath=Resolve-CandidatePath ([string]$receipt.installer.source_path) 'installer source'
$installerSourceHash=Get-Hash $installerSourcePath
if($installerSourceHash -cne [string]$receipt.installer.source_sha256){throw 'Installer source differs from its strict receipt.'}
$payloadNshPath=Resolve-CandidatePath ([string]$receipt.payload_include.path) 'payload include'
$payloadNshHash=Get-Hash $payloadNshPath
if($payloadNshHash -cne [string]$receipt.payload_include.sha256){throw 'Payload include differs from its strict receipt.'}

$build=$buildLease.Value
$executed=@($build.executed_build_logic_sources)
if($executed.Count -ne [int]$build.executed_build_logic_source_count -or
    $executed.Count -ne [int]$build.build_logic_read_lease_count){throw 'Executed build-logic source set is incomplete.'}
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($row in $executed){
    $path=Resolve-CandidatePath ([string]$row.path) 'executed build logic'
    if(-not $seen.Add($path) -or (Get-Hash $path) -cne [string]$row.sha256){throw 'Executed build-logic source hash binding failed.'}
}
$auditPaths=[Collections.Generic.List[string]]::new()
$auditPaths.Add($installerSourcePath);$auditPaths.Add($payloadNshPath)
foreach($locale in Get-ChildItem -LiteralPath (Join-Path $candidate 'installer\locale') -File -Filter '*.nsh'){$auditPaths.Add($locale.FullName)}
$dynamic='(?mi)^\s*!(?:system|execute|packhdr|addplugindir|addincludedir)\b'
$environment='\$%[^%\r\n]+%'
$wildcard='(?mi)^\s*File(?:\s+/[^\s]+)*\s+[^\r\n]*[*?]'
foreach($path in $auditPaths){
    $text=[IO.File]::ReadAllText($path)
    if($text -match $dynamic){throw "Dynamic compiler directive rejected in audited source: $path"}
    if($text -match $environment){throw "Environment macro read rejected in audited source: $path"}
    if($text -match $wildcard){throw "Wildcard compiler payload read rejected in audited source: $path"}
}
$main=[IO.File]::ReadAllText($installerSourcePath)
$includeLines=@([regex]::Matches($main,'(?mi)^\s*!include\s+"([^"]+)"')|ForEach-Object{$_.Groups[1].Value})
$expectedIncludes=@(
    '${NSISDIR}\Include\MUI2.nsh','${NSISDIR}\Include\x64.nsh','${NSISDIR}\Include\Winver.nsh',
    '${NSISDIR}\Include\LogicLib.nsh','${NSISDIR}\Include\FileFunc.nsh','${PACKAGE_PAYLOAD_NSH_PATH}',
    '${PACKAGE_LOCALE_ROOT}\${LANGLOAD}.nsh'
)
if($includeLines.Count -ne $expectedIncludes.Count){throw 'Installer source include set is not closed.'}
for($i=0;$i -lt $expectedIncludes.Count;$i++){if([string]$includeLines[$i] -cne [string]$expectedIncludes[$i]){throw 'Installer source include order or root changed.'}}
$sourceAudit=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1r-source-audit-v1';installer_source_sha256=$installerSourceHash
    payload_nsh_sha256=$payloadNshHash;actual_source_bytes_examined=$true
    dynamic_compiler_directives_absent=$true;environment_macro_reads_absent=$true
    wildcard_payload_reads_absent=$true;include_roots_closed=$true
    executed_build_logic_source_set_hash_bound=$true;installer_or_uninstaller_executed=$false
    registry_or_product_process_touched=$false;installed_yimecore_local12_touched=$false
    production_user_data_read_or_written=$false
}
Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1r-trust-admission.psm1') -Force
$admission=Get-RimePimeDp1RTrustAdmission -Build $build -PostbuildPs5 $independentPostbuildLease.Value `
    -PostbuildPs7 $primaryPostbuildLease.Value -SourceAudit $sourceAudit
if(-not $admission.review_ready){throw ('DP1-R trust admission rejected actual candidate evidence: '+(@($admission.reasons)-join ', '))}

$null=New-Item -ItemType Directory -Path $output
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-dp1r-actual-trust-review-v1'
    generated_at_utc=[DateTime]::UtcNow.ToString('o');affected_product='rime-pime';review_passed=$true
    candidate_repo_root=$candidate;product_version=[string]$build.product_version
    candidate_installer=[pscustomobject][ordered]@{path=$installerPath;bytes=[long]$receipt.installer.bytes;sha256=[string]$receipt.installer.sha256}
    generated_uninstaller=[pscustomobject][ordered]@{bytes=[long]$primaryPostbuildLease.Value.generated_uninstaller.bytes;sha256=[string]$primaryPostbuildLease.Value.generated_uninstaller.sha256}
    build_result=[pscustomobject][ordered]@{path=$buildLease.Path;sha256=$buildLease.Digest}
    ps5_postbuild=[pscustomobject][ordered]@{path=$independentPostbuildLease.Path;sha256=$independentPostbuildLease.Digest}
    ps7_postbuild=[pscustomobject][ordered]@{path=$primaryPostbuildLease.Path;sha256=$primaryPostbuildLease.Digest}
    source_audit=$sourceAudit;admission=$admission
    actual_source_and_candidate_bytes_examined=$true;actual_installer_or_uninstaller_executed=$false
    registry_or_product_process_touched=$false;installed_yimecore_local12_touched=$false
    production_user_data_read_or_written=$false
    full_payload_static_closure=$true;nsis_non_os_compiler_input_closure=$true
    generated_uninstaller_verified=$true;generated_uninstaller_trusted_for_unsigned_disabled_static_scope=$true
    historical_build_and_postbuild_non_claims_preserved=$true
    active_same_sid_physical_replacement_prevented=$false;full_nsis_toolchain_input_closure=$false
    generated_uninstaller_signature_trusted=$false;signing_complete=$false;delivery_admitted=$false
    installed_or_registered_host_verified=$false;dp1_complete=$false;dp2_complete=$false;dp3_complete=$false
}
$resultPath=Join-Path $output 'result.json'
$json=($result|ConvertTo-Json -Depth 10)+"`n"
[IO.File]::WriteAllText($resultPath,$json,[Text.UTF8Encoding]::new($false))
$digest=Get-Hash $resultPath
[IO.File]::WriteAllText($resultPath+'.sha256',$digest+'  result.json'+"`n",[Text.UTF8Encoding]::new($false))
Write-Host "PASS: actual DP1-R static trust review completed without executing installer or uninstaller. Evidence: $resultPath ($digest)"
