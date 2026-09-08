[CmdletBinding()]
param([string]$OutputRoot,[switch]$ReviewCurrentCanonical)
$ErrorActionPreference='Stop'
$testRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testAllowed=Join-Path $testRepo '.tmp\dual-product'
if (-not $OutputRoot) { $OutputRoot=Join-Path $testAllowed ('dp1-u-native-candidate-'+[Guid]::NewGuid().ToString('N')) }
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($testAllowed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'Use one fresh owned .tmp/dual-product result directory' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$probeModule=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -Force -PassThru
& $probeModule { Initialize-Dp1UNativeFacts }
$testChecks=[Collections.Generic.List[object]]::new()
function Check-Candidate([string]$Name,[bool]$Passed) {
    if (-not $Passed) { throw ('FAIL: '+$Name) }
    $testChecks.Add([pscustomobject]@{name=$Name;passed=$true})
}
function Reject-Candidate([string]$Name,[scriptblock]$Action,[string]$Pattern) {
    $failure=$null
    try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    Check-Candidate $Name ($null -ne $failure -and $failure -match $Pattern)
}
function Read-CandidateJson([string]$Path) {
    $options=@{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind='String' }
    ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) @options
}
function Write-CandidateSealedJson([string]$Path,$Value) {
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($Path+'.sha256',$hash+'  '+[IO.Path]::GetFileName($Path)+"`n",[Text.Encoding]::ASCII)
}
function New-CandidateFixture([string]$Name) {
    # Reuse the repository's complete source-owned receipt fixture factory.
    # DefinitionsOnly performs no installer/build/extractor/product execution.
    $factoryRoot=Join-Path $testAllowed ('dp1-package-receipt-v2-test-u-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
    & {
        param($factoryPath,$factoryOutput,$caseName)
        . $factoryPath -OutputRoot $factoryOutput -DefinitionsOnly
        $candidateCase=New-Case $caseName
        $prepared=Prepare $candidateCase
        try {
            [pscustomobject]@{Root=$candidateCase.Root;Package=$candidateCase.Installer;Receipt=$prepared.ReceiptPath;Build=$candidateCase.BuildPath;Manifest=$candidateCase.ManifestPath;Source=(Join-Path $candidateCase.Root 'installer\installer.nsi')}
        } finally { Close-RimePimePackageReceiptV2Preparation $prepared }
    } (Join-Path $PSScriptRoot 'test-rime-pime-package-receipt-v2.ps1') $factoryRoot $Name
}
function Assess-CandidateFixture($Case,[string]$OverrideReceiptHash) {
    $packageHash=(Get-FileHash -LiteralPath $Case.Package -Algorithm SHA256).Hash.ToLowerInvariant()
    $receiptHash=(Get-FileHash -LiteralPath $Case.Receipt -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($OverrideReceiptHash) { $receiptHash=$OverrideReceiptHash }
    & $probeModule {
        param($c,$packageHash,$receiptHash)
        $package=Open-Dp1UNativeArtifact $c.Package $packageHash 4294967296
        try {
            $receipt=Open-Dp1UNativeArtifact $c.Receipt $receiptHash -Json
            try { Get-Dp1UNativeCandidateAssessment $c.Root $package $receipt }
            finally { $receipt.stream.Dispose() }
        } finally { $package.stream.Dispose() }
    } $Case $packageHash $receiptHash
}

$case=New-CandidateFixture 'ok'
$good=Assess-CandidateFixture $case
Check-Candidate 'real strict reader validates complete fixture evidence chain' ($good.strict_receipt_evidence_chain_verified -is [bool] -and $good.strict_receipt_evidence_chain_verified)
Check-Candidate 'valid canonical disabled receipt is rejected for execution' (-not $good.executable_candidate_safe -and -not $good.candidate_execution_admitted -and -not $good.execution_authorized -and $good.rejection_reasons.Count -eq 3)
Check-Candidate 'strict assessment identifies exact receipt and package' ($good.receipt_sha256 -ceq (Get-FileHash -LiteralPath $case.Receipt -Algorithm SHA256).Hash.ToLowerInvariant() -and $good.package_sha256 -ceq (Get-FileHash -LiteralPath $case.Package -Algorithm SHA256).Hash.ToLowerInvariant())
Reject-Candidate 'approved receipt hash cannot be substituted' { Assess-CandidateFixture $case ('0'*64) } 'digest mismatch'

$case=New-CandidateFixture 'sidecar'
[IO.File]::WriteAllText($case.Receipt+'.sha256',('0'*64)+'  '+[IO.Path]::GetFileName($case.Receipt)+"`n",[Text.Encoding]::ASCII)
Reject-Candidate 'valid raw receipt with forged sidecar is rejected' { Assess-CandidateFixture $case } 'sidecar does not match'

$case=New-CandidateFixture 'absent'
$missingPath=[IO.Path]::GetFullPath($case.Manifest)
if (-not $missingPath.StartsWith($testAllowed+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture move outside owned namespace' }
Move-Item -LiteralPath $missingPath -Destination ($missingPath+'.missing')
Reject-Candidate 'missing bound source evidence is rejected' { Assess-CandidateFixture $case } 'missing|does not exist|not found'

$case=New-CandidateFixture 'flag'
$value=Read-CandidateJson $case.Receipt; $value.delivery_admitted=$true
Write-CandidateSealedJson $case.Receipt $value
Reject-Candidate 'resealed delivery true cannot turn canonical into executable candidate' { Assess-CandidateFixture $case } 'fail-closed boundary'

$case=New-CandidateFixture 'bool'
$value=Read-CandidateJson $case.Receipt; $value.signing_complete='false'
Write-CandidateSealedJson $case.Receipt $value
Reject-Candidate 'string signing boolean is rejected by trusted reader' { Assess-CandidateFixture $case } 'fail-closed boundary'

$case=New-CandidateFixture 'semantic'
$value=Read-CandidateJson $case.Receipt; $value.product_version='2.0-forged'
Write-CandidateSealedJson $case.Receipt $value
Reject-Candidate 'recomputed receipt hash cannot conceal cross-evidence version contradiction' { Assess-CandidateFixture $case } 'contradict|different|invalid'

$case=New-CandidateFixture 'build'
$value=Read-CandidateJson $case.Build; $value.prebuild_stage_verified=$false
Write-CandidateSealedJson $case.Build $value
Reject-Candidate 'changed bound build file is rejected despite valid new sidecar' { Assess-CandidateFixture $case } 'differs from the canonical receipt'

$case=New-CandidateFixture 'minimal'
$old=Read-CandidateJson $case.Receipt
Write-CandidateSealedJson $case.Receipt ([ordered]@{schema_version=$old.schema_version;product='rime-pime';installer=@{sha256=$old.installer.sha256;bytes=$old.installer.bytes}})
Reject-Candidate 'schema and package digest alone are insufficient' { Assess-CandidateFixture $case } 'schema|properties|property|incomplete'

$case=New-CandidateFixture 'future'
$value=Read-CandidateJson $case.Receipt; $value.schema_version='yime-rime-pime-package-build-receipt-v999'
Write-CandidateSealedJson $case.Receipt $value
Reject-Candidate 'unknown executable receipt version is rejected' { Assess-CandidateFixture $case } 'fail-closed boundary'

$case=New-CandidateFixture 'duplicate'
$raw=[IO.File]::ReadAllText($case.Receipt)
$raw=$raw.Replace('"product":"rime-pime"','"product":"rime-pime","product":"rime-pime"')
[IO.File]::WriteAllText($case.Receipt,$raw,[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $case.Receipt -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($case.Receipt+'.sha256',$hash+'  '+[IO.Path]::GetFileName($case.Receipt)+"`n",[Text.Encoding]::ASCII)
Reject-Candidate 'duplicate JSON names cannot bypass strict reader through native JSON parsing' { Assess-CandidateFixture $case } 'strict UTF-8 JSON|Duplicate|duplicate'

$case=New-CandidateFixture 'source'
[IO.File]::AppendAllText($case.Source,' changed source',[Text.UTF8Encoding]::new($false))
Reject-Candidate 'changed NSIS source is rejected by strict source evidence binding' { Assess-CandidateFixture $case } 'changed|differ|mismatch'

$case=New-CandidateFixture 'root'
$case.Root=Join-Path $OutputRoot 'wrong-root'
New-Item -ItemType Directory -Path $case.Root | Out-Null
Reject-Candidate 'explicit evidence root cannot search outside itself' { Assess-CandidateFixture $case } 'outside its explicit receipt evidence root'

$liveReview=$null
if ($ReviewCurrentCanonical) {
    # Only the declared repository canonical build artifacts and their retained
    # provenance are read. No native target probe or installed product is used.
    $canonicalPath=Join-Path $testRepo 'installer\package-build-receipt.json'
    $canonical=Read-CandidateJson $canonicalPath
    if ($canonical.installer.path -cnotmatch '^installer/YIME-[A-Za-z0-9.+_-]+-setup\.exe$') { throw 'Unexpected canonical build artifact path' }
    $liveCase=[pscustomobject]@{Root=$testRepo;Package=(Join-Path $testRepo $canonical.installer.path);Receipt=$canonicalPath}
    $liveReview=Assess-CandidateFixture $liveCase
    Check-Candidate 'actual canonical retained evidence strict chain validates' ($liveReview.strict_receipt_evidence_chain_verified -and $liveReview.retained_evidence_used)
    Check-Candidate 'actual canonical remains refused for execution' (-not $liveReview.executable_candidate_safe -and -not $liveReview.candidate_execution_admitted -and -not $liveReview.execution_authorized)
}
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-native-candidate-tests-v1'; powershell_version=$PSVersionTable.PSVersion.ToString()
    passed=$true;checks_passed=$testChecks.Count;checks=@($testChecks);actual_canonical_review=$liveReview
    strict_reader_mocked=$false;complete_source_fixture_executed=$true;actual_canonical_read=$ReviewCurrentCanonical.IsPresent
    native_target_probe_executed=$false;execution_authorized=$false;installer_or_uninstaller_executed=$false
    installed_yimecore_local12_touched=$false;registry_mutated=$false;user_data_read=$false;dp1_u_acceptance_passed=$false
}
$result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $OutputRoot 'result.json') -Encoding UTF8
Write-Host ('PASS: '+$testChecks.Count+' DP1-U strict candidate checks; '+$OutputRoot)
