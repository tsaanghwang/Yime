[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$WorkerCasePath,
    [string]$Phase,
    [string]$CheckPattern='*'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$modulePath = Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.psm1'

if ($WorkerCasePath) {
    $worker = [IO.Path]::GetFullPath($WorkerCasePath)
    $caseRoot = Split-Path -Parent $worker
    $casesRoot = Split-Path -Parent $caseRoot
    $runRoot = Split-Path -Parent $casesRoot
    $allowedParent = Join-Path $repo '.tmp\dual-product'
    if ([IO.Path]::GetFileName($worker) -cne 'worker.json' -or
        (Split-Path -Leaf $casesRoot) -cne 'cases' -or
        (Split-Path -Leaf $caseRoot) -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or
        (Split-Path -Leaf $runRoot) -cnotmatch '^dp1-candidate-evidence-archive-test-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        (Split-Path -Parent $runRoot) -ine $allowedParent) {
        throw 'Candidate evidence archive worker is fixture-only.'
    }
    $module = Import-Module -Name $modulePath -Force -PassThru
    $workerRecord = & $module { param($Path) Get-YimePimePayloadFileRecord $Path } $worker
    $workerBytes = [IO.File]::ReadAllBytes($worker)
    $workerAfter = & $module { param($Path) Get-YimePimePayloadFileRecord $Path } $worker
    if ([string]$workerRecord.sha256 -cne [string]$workerAfter.sha256 -or
        [string]$workerRecord.file_id -cne [string]$workerAfter.file_id -or
        [long]$workerRecord.bytes -ne [long]$workerAfter.bytes) {
        throw 'Candidate evidence archive worker input changed while read.'
    }
    $workerText = [Text.UTF8Encoding]::new($false,$true).GetString($workerBytes)
    try { $configuration = $workerText | ConvertFrom-Json }
    catch { throw 'Candidate evidence archive worker input is not JSON.' }
    & $module {
        param($Value)
        Assert-RimePimeExactProperties $Value @(
            'schema_version','case_root','expected_runner_result_sha256','mode'
        ) 'candidate archive worker input'
    } $configuration
    if ([string]$configuration.schema_version -cne 'yime-rime-pime-candidate-evidence-archive-worker-v1' -or
        [IO.Path]::GetFullPath([string]$configuration.case_root).TrimEnd('\') -ine $caseRoot -or
        [string]$configuration.expected_runner_result_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$configuration.mode -cnotin @('publish','resume')) {
        throw 'Candidate evidence archive worker input is invalid.'
    }
    $allowedPhases = @(
        'none','lock-created','object-copy','object-data','manifest-data','intent-data','intent-sidecar',
        'head-data','complete-data','before-archive-root','archive-root','locked'
    )
    if ($Phase -cnotin $allowedPhases) { throw 'Candidate evidence archive worker phase is invalid.' }
    if ($Phase -cne 'locked') {
        & $module {
            param($StopPhase)
            $script:CandidateArchiveStopPhase = $StopPhase
            function script:Invoke-RimePimeCandidateEvidenceArchiveCheckpoint([string]$Checkpoint) {
                if ($Checkpoint -ceq $script:CandidateArchiveStopPhase) { [Environment]::Exit(73) }
            }
        } $Phase
    }
    try {
        if ([string]$configuration.mode -ceq 'resume') {
            $null = Resume-RimePimeCandidateEvidenceArchive -CaseRoot $configuration.case_root `
                -ExpectedRunnerResultSha256 $configuration.expected_runner_result_sha256
        } else {
            $null = Publish-RimePimeCandidateEvidenceArchive -CaseRoot $configuration.case_root `
                -ExpectedRunnerResultSha256 $configuration.expected_runner_result_sha256
        }
    } catch {
        if ($Phase -ceq 'locked') {
            # The parent owns the exact fixture lock with FileShare.None.  The
            # worker must fail before archive state exists; Windows/.NET can
            # surface this lease conflict as IOException or UnauthorizedAccess
            # with localized/native error variants, so 74 is the test-worker
            # classification for any fail-closed result at this boundary.
            [IO.File]::WriteAllText($worker+'.lock-error.txt',($_ | Out-String),[Text.UTF8Encoding]::new($false))
            exit 74
        }
        throw
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { throw 'OutputRoot is required outside worker mode.' }
$allowedParent = Join-Path $repo '.tmp\dual-product'
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ((Split-Path -Parent $output) -ine $allowedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-candidate-evidence-archive-test-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'OutputRoot must be a fresh immediate .tmp/dual-product/dp1-candidate-evidence-archive-test-* directory.'
}
if (-not(Test-Path -LiteralPath $allowedParent)) { New-Item -ItemType Directory -Path $allowedParent | Out-Null }
New-Item -ItemType Directory -Path $output | Out-Null
$casesRoot = Join-Path $output 'cases'
New-Item -ItemType Directory -Path $casesRoot | Out-Null
$module = Import-Module -Name $modulePath -Force -PassThru

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body) {
    if ($Name -notlike $CheckPattern) { return }
    try {
        & $Body
        $script:checks.Add([pscustomobject][ordered]@{ name=$Name;passed=$true;message=$null })
        Write-Host "PASS: $Name"
    } catch {
        $script:checks.Add([pscustomobject][ordered]@{ name=$Name;passed=$false;message=[string]$_.Exception.Message })
        Write-Host "FAIL: $Name - $($_.Exception.Message)"
    }
}
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Body,[string]$Pattern='*') {
    $caught = $null
    try { & $Body } catch { $caught = $_ }
    if ($null -eq $caught) { throw 'Expected fail-closed rejection did not occur.' }
    if ([string]$caught.Exception.Message -notlike $Pattern) { throw "Unexpected rejection: $($caught.Exception.Message)" }
}
function Get-TestSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-TestCanonicalBytes($Value) {
    return ,[byte[]](& $script:module { param($InputValue) ConvertTo-RimePimeCandidateArchiveBytes $InputValue } $Value)
}
function Ensure-TestDirectory([string]$Path) {
    if (-not(Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}
function Write-TestNewBytes([string]$Path,[byte[]]$Bytes) {
    Ensure-TestDirectory (Split-Path -Parent $Path)
    $stream = [IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
}
function Write-TestSealedBytes([string]$Path,[byte[]]$Bytes) {
    Write-TestNewBytes $Path $Bytes
    $digest = Get-TestSha256 $Bytes
    Write-TestNewBytes ($Path+'.sha256') ([Text.Encoding]::ASCII.GetBytes($digest+'  '+[IO.Path]::GetFileName($Path)+"`n"))
    return $digest
}
function Set-TestSealedBytes([string]$Path,[byte[]]$Bytes) {
    [IO.File]::WriteAllBytes($Path,$Bytes)
    $digest = Get-TestSha256 $Bytes
    [IO.File]::WriteAllText(
        ($Path+'.sha256'),($digest+'  '+[IO.Path]::GetFileName($Path)+"`n"),[Text.Encoding]::ASCII)
    return $digest
}
function Read-TestStrictJson([string]$Path,[string]$Context) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return & $script:module {
        param([byte[]]$ValueBytes,[string]$ValueContext)
        ConvertFrom-RimePimeCandidateArchiveJsonBytes $ValueBytes $ValueContext
    } $bytes $Context
}
function Write-TestSealedJson([string]$Path,$Value) {
    $bytes = Get-TestCanonicalBytes $Value
    $digest = Write-TestSealedBytes $Path $bytes
    return [pscustomobject]@{ Path=$Path;Bytes=[byte[]]$bytes;Digest=$digest;Length=[long]$bytes.Length }
}
function Add-TestRetainedObject([string]$SourceRoot,[byte[]]$Bytes) {
    $digest = Get-TestSha256 $Bytes
    $path = Join-Path $SourceRoot ('repo\installer\receipt-evidence\sha256\'+$digest.Substring(0,2)+'\'+$digest+'.blob')
    if (-not(Test-Path -LiteralPath $path)) {
        Write-TestNewBytes $path $Bytes
        Write-TestNewBytes ($path+'.sha256') ([Text.Encoding]::ASCII.GetBytes($digest+'  '+[IO.Path]::GetFileName($path)+"`n"))
    }
    return [pscustomobject]@{ Digest=$digest;Path=$path;Bytes=[byte[]]$Bytes;Length=[long]$Bytes.Length }
}
function New-TestEvidence([string]$CaseName) {
    $caseRoot = Join-Path $casesRoot $CaseName
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $source = Join-Path $caseRoot 'outer-tmp'
    Ensure-TestDirectory (Join-Path $source 'repo\evidence')
    Ensure-TestDirectory (Join-Path $source 'repo\installer\receipt-evidence\sha256')
    $records = @{}
    foreach ($definition in @(
        @('plan','package-plan.json'),@('build','build-result.json'),@('manifest','content-manifest.json'),
        @('postbuild','postbuild-result.json'),@('history','historical-v1.json'),@('payload','payload.nsh'),
        @('payloadReceipt','payload.nsh.receipt.json'),@('spec','payload-spec.json'),@('inventory','go-inventory.json'),
        @('lock','nsis-toolchain-lock.json'),@('installerSource','installer.nsi')
    )) {
        $name = [string]$definition[0]
        $file = [string]$definition[1]
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes("fixture-$CaseName-$name`n")
        $sourcePath = Join-Path $source ('repo\evidence\'+$file)
        $record = if ($file.EndsWith('.json')) {
            Write-TestSealedJson $sourcePath ([pscustomobject][ordered]@{ schema_version=('fixture-'+$name+'-v1');case=$CaseName })
        } else {
            Write-TestNewBytes $sourcePath $bytes
            [pscustomobject]@{ Path=$sourcePath;Bytes=[byte[]]$bytes;Digest=(Get-TestSha256 $bytes);Length=[long]$bytes.Length }
        }
        $records[$name] = $record
        $null = Add-TestRetainedObject $source ([byte[]]$record.Bytes)
    }

    $installerBytes = [Text.UTF8Encoding]::new($false).GetBytes("disabled-unsigned-installer-$CaseName`n")
    $installerPath = Join-Path $source 'repo\installer\YIME-1.2.3-setup.exe'
    Write-TestNewBytes $installerPath $installerBytes
    $installerObject = Add-TestRetainedObject $source $installerBytes
    $receipt = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v2';product='rime-pime';product_version='1.2.3'
        package_plan=[pscustomobject][ordered]@{ sha256=[string]$records.plan.Digest }
        sealed_stage=[pscustomobject][ordered]@{
            content_manifest_sha256=[string]$records.manifest.Digest
            payload_spec_sha256=[string]$records.spec.Digest
            go_payload_inventory_sha256=[string]$records.inventory.Digest
        }
        payload_include=[pscustomobject][ordered]@{
            sha256=[string]$records.payload.Digest;receipt_sha256=[string]$records.payloadReceipt.Digest
        }
        predecessor_v1=[pscustomobject][ordered]@{ sha256=[string]$records.history.Digest }
        disabled_build=[pscustomobject][ordered]@{
            schema_version='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
            result_sha256=[string]$records.build.Digest;nsis_toolchain_lock_sha256=[string]$records.lock.Digest
        }
        static_postbuild=[pscustomobject][ordered]@{ result_sha256=[string]$records.postbuild.Digest }
        installer=[pscustomobject][ordered]@{
            path='installer/YIME-1.2.3-setup.exe';source_sha256=[string]$records.installerSource.Digest
            sha256=[string]$installerObject.Digest;bytes=[long]$installerObject.Length
        }
        evidence_artifacts_durable=$true;delivery_admitted=$false
    }
    $receiptPath = Join-Path $source 'repo\installer\package-build-receipt.json'
    $receiptRecord = Write-TestSealedJson $receiptPath $receipt
    $null = Add-TestRetainedObject $source ([byte[]]$receiptRecord.Bytes)

    $boundaries = [pscustomobject][ordered]@{
        installer_executed=$false;uninstaller_executed=$false;signing_process_executed=$false
        installed_product_processes_touched=$false;product_registry_mutated=$false;default_input_method_changed=$false
        production_user_data_read_or_written=$false;installed_yimecore_local12_touched=$false
        actual_canonical_migrated=$false;actual_canonical_migration_admitted=$false;actual_installer_published=$false
        real_installer_transaction_adapter_wired=$false;release_signing_complete=$false;delivery_admitted=$false
        hardware_power_loss_durability_verified=$false;directory_metadata_durability_verified=$false
        outer_tmp_retention_guaranteed=$false;evidence_archived_outside_tmp=$false
        active_same_sid_physical_replacement_prevented=$false;full_nsis_toolchain_input_closure=$false
    }
    $identityAdmission = [pscustomobject][ordered]@{
        identity_transition_admitted=$true;actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
    }
    $result = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-isolated-candidate-result-v1';generated_at_utc='2026-09-07T00:00:00.0000000Z';status='pass'
        source=[pscustomobject][ordered]@{
            repo_root='fixture-only';exact_head=('1'*40);exact_tree=('2'*40)
            runner_relative_path='tools/dual-product/run-rime-pime-isolated-candidate.ps1'
            runner_head_blob=('3'*40);runner_worktree_blob=('3'*40);runner_matches_exact_head=$true
            clone_core_autocrlf='false';clone_detached_exact_head=$true;actual_protected_snapshot_unchanged=$true
            before_snapshot_sha256=('4'*64);after_snapshot_sha256=('4'*64)
        }
        commands=@([pscustomobject][ordered]@{ name='fixture';exit_code=0 })
        evidence=[pscustomobject][ordered]@{
            clone_path='repo';source_head=('1'*40);source_tree=('2'*40);clone_current_version='1.2.3'
            distinct_versioned_installer_leaf_for_dp1n=$true;dp1n_version_identity_admission=$identityAdmission
            package_plan=[pscustomobject][ordered]@{ path='repo/evidence/package-plan.json';sha256=[string]$records.plan.Digest }
            build_result=[pscustomobject][ordered]@{
                path='repo/evidence/build-result.json';sha256=[string]$records.build.Digest
                schema_version='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'
            }
            build_manifest=[pscustomobject][ordered]@{
                path='repo/evidence/content-manifest.json';sha256=[string]$records.manifest.Digest
                bytes=[long]$records.manifest.Length;static_only_passed=$true
            }
            postbuild_result=[pscustomobject][ordered]@{ path='repo/evidence/postbuild-result.json';sha256=[string]$records.postbuild.Digest }
            installer=[pscustomobject][ordered]@{
                path='repo/installer/YIME-1.2.3-setup.exe';sha256=[string]$installerObject.Digest
                bytes=[long]$installerObject.Length;unsigned_disabled=$true
            }
            historical_v1_receipt=[pscustomobject][ordered]@{ path='repo/evidence/historical-v1.json';sha256=[string]$records.history.Digest }
            durable_v2_receipt=[pscustomobject][ordered]@{
                path='repo/installer/package-build-receipt.json';sha256=[string]$receiptRecord.Digest
                schema_version='yime-rime-pime-package-build-receipt-v2';evidence_artifacts_durable=$true
                durability_scope='isolated-clone-content-addressed-process-interruption-protocol'
            }
        }
        failure=$null;boundaries=$boundaries
    }
    $resultRecord = Write-TestSealedJson (Join-Path $source 'result.json') $result
    return [pscustomobject]@{
        CaseRoot=$caseRoot;SourceRoot=$source;ArchiveRoot=(Join-Path $caseRoot 'archive')
        ResultDigest=[string]$resultRecord.Digest;InstallerDigest=[string]$installerObject.Digest
        ResultValue=$result
        InstallerPath=$installerPath;RequiredObjectPath=[string](Join-Path $source `
            ('repo\installer\receipt-evidence\sha256\'+$records.plan.Digest.Substring(0,2)+'\'+$records.plan.Digest+'.blob'))
    }
}
function Write-TestWorker([object]$Fixture,[string]$Mode) {
    $path = Join-Path $Fixture.CaseRoot 'worker.json'
    $value = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-worker-v1'
        case_root=[string]$Fixture.CaseRoot;expected_runner_result_sha256=[string]$Fixture.ResultDigest;mode=$Mode
    }
    [IO.File]::WriteAllText($path,((ConvertTo-Json $value -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    return $path
}
function Invoke-TestWorker([object]$Fixture,[string]$StopPhase,[string]$Mode) {
    $worker = Write-TestWorker $Fixture $Mode
    $shell = (Get-Process -Id $PID).Path
    $escapedScript = $PSCommandPath.Replace("'","''")
    $escapedWorker = $worker.Replace("'","''")
    $command = "& '$escapedScript' -WorkerCasePath '$escapedWorker' -Phase '$StopPhase'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process -FilePath $shell -ArgumentList @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded
    ) -WindowStyle Hidden -Wait -PassThru
    return [int]$process.ExitCode
}
function Get-TestArchiveObjectPath([string]$ArchiveRoot,[string]$Digest) {
    return Join-Path $ArchiveRoot ('objects\sha256\'+$Digest.Substring(0,2)+'\'+$Digest+'.blob')
}
function Move-TestArchiveObjectOutside([object]$Fixture,[string]$Digest,[string]$Label) {
    $path = Get-TestArchiveObjectPath $Fixture.ArchiveRoot $Digest
    $quarantine = Join-Path $Fixture.CaseRoot 'tamper-reseal-withheld'
    Ensure-TestDirectory $quarantine
    Move-Item -LiteralPath $path -Destination (Join-Path $quarantine ($Label+'.blob'))
    Move-Item -LiteralPath ($path+'.sha256') -Destination (Join-Path $quarantine ($Label+'.blob.sha256'))
    $prefix = Split-Path -Parent $path
    if (@(Get-ChildItem -LiteralPath $prefix -Force).Count -eq 0) {
        Move-Item -LiteralPath $prefix -Destination (Join-Path $quarantine ($Label+'-empty-prefix'))
    }
}

$hardExitPhases = @(
    'lock-created','object-copy','object-data','manifest-data','intent-data','intent-sidecar',
    'head-data','complete-data','before-archive-root','archive-root'
)
$expectedCheckNames = @(
    'module-exports-exact-public-api',
    'clean-publish-read-and-source-independent-idempotency',
    'wrong-expected-runner-is-rejected-before-an-archive',
    'foreign-final-root-is-preserved',
    'corrupt-source-sidecar-is-rejected',
    'missing-retained-object-is-rejected',
    'archive-object-corruption-is-detected',
    'hardlinked-source-is-rejected',
    'alternate-data-stream-source-is-rejected',
    'reparse-source-ancestor-is-rejected',
    'shared-lock-blocks-an-independent-process',
    'foreign-final-root-wins-before-commit-race-without-replacement',
    'actual-checkout-root-is-rejected',
    'semantically-resealed-and-scalar-shape-tampering-is-rejected'
) + @($hardExitPhases | ForEach-Object { 'hard-exit-'+$_+'-resumes-in-a-fresh-process' })

Check 'module-exports-exact-public-api' {
    $actual = @((Get-Command -Module $module.Name).Name | Sort-Object)
    $expected = @(
        'Publish-RimePimeCandidateEvidenceArchive','Read-RimePimeCandidateEvidenceArchive',
        'Resume-RimePimeCandidateEvidenceArchive'
    ) | Sort-Object
    Assert-True (($actual -join "`n") -ceq ($expected -join "`n")) 'Candidate archive module exports an unexpected API.'
}

Check 'clean-publish-read-and-source-independent-idempotency' {
    $fixture = New-TestEvidence 'clean'
    $published = Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot `
        -ExpectedRunnerResultSha256 $fixture.ResultDigest
    Assert-True ([string]$published.status -ceq 'fixture-archive-complete') 'Clean publish did not complete.'
    Assert-True (-not[bool]$published.actual_archive_root_published) 'Fixture was mislabeled as an actual archive root.'
    Assert-True ([bool]$published.fixture_sibling_archive_protocol_passed) 'Fixture archive protocol did not pass.'
    $withheld = Join-Path $fixture.CaseRoot 'source-withheld-after-commit'
    Move-Item -LiteralPath $fixture.SourceRoot -Destination $withheld
    $read = Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot
    $resumed = Resume-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot `
        -ExpectedRunnerResultSha256 $fixture.ResultDigest
    Assert-True ([string]$read.manifest_sha256 -ceq [string]$resumed.manifest_sha256) 'Committed archive was not source-independent/idempotent.'
}

Check 'wrong-expected-runner-is-rejected-before-an-archive' {
    $fixture = New-TestEvidence 'wrong-digest'
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 ('f'*64)
    } '*digest differs*'
    Assert-True (-not(Test-Path -LiteralPath $fixture.ArchiveRoot)) 'Wrong expected digest created an archive root.'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture.CaseRoot -Directory -Filter '.rpa-*').Count -eq 0) `
        'Wrong expected digest created a transaction stage.'
}

Check 'foreign-final-root-is-preserved' {
    $fixture = New-TestEvidence 'foreign-final'
    New-Item -ItemType Directory -Path $fixture.ArchiveRoot | Out-Null
    $foreign = Join-Path $fixture.ArchiveRoot 'foreign.txt'
    [IO.File]::WriteAllText($foreign,'foreign',[Text.UTF8Encoding]::new($false))
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    }
    Assert-True ([IO.File]::ReadAllText($foreign) -ceq 'foreign') 'Foreign final archive root was replaced or changed.'
}

Check 'corrupt-source-sidecar-is-rejected' {
    $fixture = New-TestEvidence 'bad-sidecar'
    [IO.File]::WriteAllText((Join-Path $fixture.SourceRoot 'result.json.sha256'),"bad`n",[Text.Encoding]::ASCII)
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    } '*sidecar*'
    Assert-True (-not(Test-Path -LiteralPath $fixture.ArchiveRoot)) 'Bad source sidecar produced an archive.'
}

Check 'missing-retained-object-is-rejected' {
    $fixture = New-TestEvidence 'missing-object'
    $withheldRoot = Join-Path $fixture.CaseRoot 'withheld-retained-object'
    New-Item -ItemType Directory -Path $withheldRoot | Out-Null
    $withheld = Join-Path $withheldRoot ([IO.Path]::GetFileName($fixture.RequiredObjectPath))
    Move-Item -LiteralPath $fixture.RequiredObjectPath -Destination $withheld
    Move-Item -LiteralPath ($fixture.RequiredObjectPath+'.sha256') -Destination ($withheld+'.sha256')
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    } '*missing*'
}

Check 'archive-object-corruption-is-detected' {
    $fixture = New-TestEvidence 'object-corruption'
    $null = Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    $object = Join-Path $fixture.ArchiveRoot `
        ('objects\sha256\'+$fixture.InstallerDigest.Substring(0,2)+'\'+$fixture.InstallerDigest+'.blob')
    $original = [IO.File]::ReadAllBytes($object)
    $replacement = New-Object byte[] $original.Length
    for ($i=0;$i -lt $original.Length;$i++) { $replacement[$i] = [byte]($original[$i] -bxor 0x5a) }
    $replacementDigest = Get-TestSha256 $replacement
    Assert-True ($replacementDigest -cne $fixture.InstallerDigest) 'Same-length corruption fixture did not change digest.'
    [IO.File]::WriteAllBytes($object,$replacement)
    [IO.File]::WriteAllText(
        ($object+'.sha256'),($replacementDigest+'  '+[IO.Path]::GetFileName($object)+"`n"),[Text.Encoding]::ASCII)
    Assert-Rejected { Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot } '*digest or byte count differs*'
}

Check 'hardlinked-source-is-rejected' {
    $fixture = New-TestEvidence 'hardlink'
    $original = $fixture.InstallerPath+'.original'
    Move-Item -LiteralPath $fixture.InstallerPath -Destination $original
    New-Item -ItemType HardLink -Path $fixture.InstallerPath -Target $original | Out-Null
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    } '*Hard-linked*'
}

Check 'alternate-data-stream-source-is-rejected' {
    $fixture = New-TestEvidence 'ads'
    # Windows PowerShell 5.1's System.IO path parser rejects an ADS suffix;
    # the FileSystem provider's Stream parameter works in both PS5 and PS7.
    Set-Content -LiteralPath $fixture.InstallerPath -Stream fixture-stream -Value 'ads' -Encoding Ascii
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    } '*Alternate data stream*'
}

Check 'reparse-source-ancestor-is-rejected' {
    $fixture = New-TestEvidence 'reparse'
    $evidence = Join-Path $fixture.SourceRoot 'repo\evidence'
    $target = Join-Path $fixture.CaseRoot 'evidence-target'
    Move-Item -LiteralPath $evidence -Destination $target
    New-Item -ItemType Junction -Path $evidence -Target $target | Out-Null
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    } '*reparse*'
}

foreach ($hardExitPhase in $hardExitPhases) {
    $phaseCopy = $hardExitPhase
    Check ('hard-exit-'+$phaseCopy+'-resumes-in-a-fresh-process') {
        $fixture = New-TestEvidence ('exit-'+$phaseCopy)
        $exit = Invoke-TestWorker $fixture $phaseCopy 'publish'
        Assert-True ($exit -eq 73) "Worker did not stop at checkpoint $phaseCopy (exit $exit)."
        if ($phaseCopy -in @('intent-sidecar','head-data','complete-data','before-archive-root','archive-root')) {
            Move-Item -LiteralPath $fixture.SourceRoot -Destination (Join-Path $fixture.CaseRoot 'source-withheld-before-resume')
        }
        $resumeExit = Invoke-TestWorker $fixture 'none' 'resume'
        Assert-True ($resumeExit -eq 0) "Fresh resume failed after $phaseCopy (exit $resumeExit)."
        $read = Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot
        Assert-True ([string]$read.runner_result_sha256 -ceq $fixture.ResultDigest) 'Recovered archive has the wrong runner identity.'
        $archiveWritingLeaves = @(Get-ChildItem -LiteralPath $fixture.ArchiveRoot -Recurse -Force | Where-Object {
            -not $_.PSIsContainer -and $_.Name -cmatch '^\.writing-[0-9a-f]{32}\.tmp$'
        })
        Assert-True ($archiveWritingLeaves.Count -eq 0) 'Committed archive retained an interrupted writing orphan.'
        if ($phaseCopy -ceq 'object-copy') {
            $quarantineRoot = Join-Path $fixture.CaseRoot '.candidate-evidence-archive-quarantine'
            $isolated = @(Get-ChildItem -LiteralPath $quarantineRoot -Recurse -File -Force)
            Assert-True ($isolated.Count -ge 1) 'Interrupted object-copy orphan was not isolated outside the archive capsule.'
        }
    }
}

Check 'shared-lock-blocks-an-independent-process' {
    $fixture = New-TestEvidence 'shared-lock'
    $context = & $module { param($Root) Assert-RimePimeCandidateArchiveCaseRoot $Root } $fixture.CaseRoot
    $lock = & $module { param($Context) Open-RimePimeCandidateArchiveLock $Context } $context
    try {
        $exit = Invoke-TestWorker $fixture 'locked' 'publish'
        Assert-True ($exit -ne 0) 'Independent worker unexpectedly acquired the shared lock.'
        $lockErrorPath = (Join-Path $fixture.CaseRoot 'worker.json.lock-error.txt')
        Assert-True (Test-Path -LiteralPath $lockErrorPath -PathType Leaf) 'Locked worker did not seal its lock-boundary diagnostic.'
        $lockError = [IO.File]::ReadAllText($lockErrorPath)
        Assert-True ($lockError.Contains('.rime-pime-candidate-evidence-archive.lock')) `
            'Independent worker failure was not bound to the fixture lock anchor.'
        Assert-True (-not(Test-Path -LiteralPath $fixture.ArchiveRoot)) 'Locked worker published an archive.'
    } finally { $lock.Dispose() }
    $null = Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
}

Check 'foreign-final-root-wins-before-commit-race-without-replacement' {
    $fixture = New-TestEvidence 'final-race'
    $exit = Invoke-TestWorker $fixture 'before-archive-root' 'publish'
    Assert-True ($exit -eq 73) 'Worker did not stop immediately before final archive ownership.'
    New-Item -ItemType Directory -Path $fixture.ArchiveRoot | Out-Null
    $foreign = Join-Path $fixture.ArchiveRoot 'foreign.txt'
    [IO.File]::WriteAllText($foreign,'race-winner',[Text.UTF8Encoding]::new($false))
    Assert-Rejected {
        Resume-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot -ExpectedRunnerResultSha256 $fixture.ResultDigest
    }
    Assert-True ([IO.File]::ReadAllText($foreign) -ceq 'race-winner') 'Foreign final race winner was replaced.'
}

Check 'actual-checkout-root-is-rejected' {
    Assert-Rejected {
        Publish-RimePimeCandidateEvidenceArchive -CaseRoot $repo -ExpectedRunnerResultSha256 ('a'*64)
    } '*allowed only*'
}

Check 'semantically-resealed-and-scalar-shape-tampering-is-rejected' {
    $fixture = New-TestEvidence 'semantic-reseal'

    $arrayRunner = Read-TestStrictJson (Join-Path $fixture.SourceRoot 'result.json') 'array runner test'
    $oneRepo = [object[]]::new(1);$oneRepo[0] = 'repo'
    $arrayRunner.evidence.PSObject.Properties['clone_path'].Value = $oneRepo
    Assert-True ($arrayRunner.evidence.clone_path -is [Array]) 'Array-shape runner tamper fixture collapsed to a scalar.'
    Assert-Rejected {
        & $module { param($Value) Assert-RimePimeCandidateArchiveRunnerResult $Value } $arrayRunner
    } '*'
    $zeroRunner = Read-TestStrictJson (Join-Path $fixture.SourceRoot 'result.json') 'zero runner test'
    $zeroRunner.evidence.build_manifest.bytes = 0
    Assert-Rejected {
        & $module { param($Value) Assert-RimePimeCandidateArchiveRunnerResult $Value } $zeroRunner
    } '*byte type*'
    $autocrlfRunner = Read-TestStrictJson (Join-Path $fixture.SourceRoot 'result.json') 'autocrlf runner test'
    $autocrlfRunner.source.clone_core_autocrlf = 'true'
    Assert-Rejected {
        & $module { param($Value) Assert-RimePimeCandidateArchiveRunnerResult $Value } $autocrlfRunner
    } '*source metadata*'

    $null = Publish-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot `
        -ExpectedRunnerResultSha256 $fixture.ResultDigest
    $manifestPath = Join-Path $fixture.ArchiveRoot 'manifest.json'
    $manifest = ([IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json)
    $arrayManifest = ([IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json)
    $oneManifestSchema = [object[]]::new(1);$oneManifestSchema[0] = [string]$manifest.schema_version
    $arrayManifest.PSObject.Properties['schema_version'].Value = $oneManifestSchema
    Assert-True ($arrayManifest.schema_version -is [Array]) 'Array-shape manifest tamper fixture collapsed to a scalar.'
    Assert-Rejected {
        & $module { param($Value) Assert-RimePimeCandidateArchiveManifest $Value } $arrayManifest
    } '*identity*'
    $pathManifest = ([IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json)
    $nonSemanticRow = @($pathManifest.artifacts | Where-Object { [string]$_.kind -ceq 'retained-object' })[0]
    $nonSemanticRow.source_relative_path = 'repo//invalid'
    Assert-Rejected {
        & $module { param($Value) Assert-RimePimeCandidateArchiveManifest $Value } $pathManifest
    } '*canonical relative*'

    $rootPath = Join-Path $fixture.ArchiveRoot 'archive-root.json'
    $originalRootBytes = [IO.File]::ReadAllBytes($rootPath)
    $arrayRoot = ([Text.UTF8Encoding]::new($false,$true).GetString($originalRootBytes) | ConvertFrom-Json)
    $oneRootSchema = [object[]]::new(1);$oneRootSchema[0] = [string]$arrayRoot.schema_version
    $arrayRoot.PSObject.Properties['schema_version'].Value = $oneRootSchema
    Assert-True ($arrayRoot.schema_version -is [Array]) 'Array-shape root tamper fixture collapsed to a scalar.'
    $null = Set-TestSealedBytes $rootPath (Get-TestCanonicalBytes $arrayRoot)
    Assert-Rejected { Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot } '*root ownership*'
    $null = Set-TestSealedBytes $rootPath $originalRootBytes

    $intentPath = Join-Path $fixture.ArchiveRoot 'transactions\intent.json'
    $originalIntentBytes = [IO.File]::ReadAllBytes($intentPath)
    $arrayIntent = ([Text.UTF8Encoding]::new($false,$true).GetString($originalIntentBytes) | ConvertFrom-Json)
    $oneIntentSchema = [object[]]::new(1);$oneIntentSchema[0] = [string]$arrayIntent.schema_version
    $arrayIntent.PSObject.Properties['schema_version'].Value = $oneIntentSchema
    Assert-True ($arrayIntent.schema_version -is [Array]) 'Array-shape intent tamper fixture collapsed to a scalar.'
    $null = Set-TestSealedBytes $intentPath (Get-TestCanonicalBytes $arrayIntent)
    Assert-Rejected { Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot } '*intent*'
    $null = Set-TestSealedBytes $intentPath $originalIntentBytes

    # Rewrap every manifest-dependent control and its sidecar around a
    # manifest whose physical digest set is unchanged but whose unique runner
    # semantic kind was removed.  Digest-only readers accept this shape; the
    # DP1-Q semantic reader must still reject it.
    $runnerRow = @($manifest.artifacts | Where-Object { [string]$_.kind -ceq 'runner-result' })[0]
    $runnerRow.kind = 'retained-object'
    $newManifestBytes = Get-TestCanonicalBytes $manifest
    $newManifestDigest = Get-TestSha256 $newManifestBytes
    $owner = ([IO.File]::ReadAllText($rootPath) | ConvertFrom-Json)
    $oldManifestDigest = [string]$owner.manifest_sha256
    $oldHeadDigest = [string]$owner.head_sha256
    $archiveIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-identity-v1';product='rime-pime'
        runner_result_sha256=[string]$manifest.source_runner_result_sha256
        receipt_sha256=[string]$manifest.retained_receipt_sha256
        installer_sha256=[string]$manifest.installer_sha256;installer_bytes=[long]$manifest.installer_bytes
    }
    Assert-True ((Get-TestSha256 (Get-TestCanonicalBytes $archiveIdentity)) -ceq [string]$owner.archive_id) `
        'Tamper fixture changed the archive evidence identity instead of only its semantic mapping.'
    $operationIdentity = [pscustomobject][ordered]@{
        schema_version='yime-rime-pime-candidate-evidence-archive-operation-v1'
        archive_id=[string]$owner.archive_id;manifest_sha256=$newManifestDigest
        runner_result_sha256=[string]$manifest.source_runner_result_sha256
        retained_receipt_sha256=[string]$manifest.retained_receipt_sha256
    }
    $owner.manifest_sha256 = $newManifestDigest
    $owner.operation_id = Get-TestSha256 (Get-TestCanonicalBytes $operationIdentity)
    $newHead = & $module { param($Value) New-RimePimeCandidateArchiveHeadFromRoot $Value } $owner
    $newHeadBytes = Get-TestCanonicalBytes $newHead
    $owner.head_sha256 = Get-TestSha256 $newHeadBytes
    $newIntent = & $module { param($Value) New-RimePimeCandidateArchiveIntentFromRoot $Value } $owner
    $newCompletion = & $module { param($Value) New-RimePimeCandidateArchiveCompletionFromRoot $Value } $owner

    Move-TestArchiveObjectOutside $fixture $oldManifestDigest 'old-manifest'
    Move-TestArchiveObjectOutside $fixture $oldHeadDigest 'old-head'
    $newManifestObjectPath = Get-TestArchiveObjectPath $fixture.ArchiveRoot $newManifestDigest
    $null = Write-TestSealedBytes $newManifestObjectPath $newManifestBytes
    $newHeadObjectPath = Get-TestArchiveObjectPath $fixture.ArchiveRoot ([string]$owner.head_sha256)
    $null = Write-TestSealedBytes $newHeadObjectPath $newHeadBytes
    $null = Set-TestSealedBytes $manifestPath $newManifestBytes
    $null = Set-TestSealedBytes (Join-Path $fixture.ArchiveRoot 'head.json') $newHeadBytes
    $null = Set-TestSealedBytes $rootPath (Get-TestCanonicalBytes $owner)
    $null = Set-TestSealedBytes $intentPath (Get-TestCanonicalBytes $newIntent)
    $null = Set-TestSealedBytes (Join-Path $fixture.ArchiveRoot 'transactions\completed.json') `
        (Get-TestCanonicalBytes $newCompletion)
    Assert-Rejected { Read-RimePimeCandidateEvidenceArchive -CaseRoot $fixture.CaseRoot } '*uniquely bind*runner-result*'
}

$failed = @($checks | Where-Object { -not[bool]$_.passed })
$selectedNames = @($checks | ForEach-Object { [string]$_.name } | Sort-Object)
$expectedNames = @($expectedCheckNames | Sort-Object)
$fullSuiteExecuted = (($selectedNames -join "`n") -ceq ($expectedNames -join "`n"))
$allPassed = ($checks.Count -gt 0 -and $failed.Count -eq 0)
function Test-ChecksPassed([string[]]$Names) {
    foreach ($name in $Names) {
        $matches = @($checks | Where-Object { [string]$_.name -ceq $name -and [bool]$_.passed })
        if ($matches.Count -ne 1) { return $false }
    }
    return $true
}
$hardExitNames = @($hardExitPhases | ForEach-Object { 'hard-exit-'+$_+'-resumes-in-a-fresh-process' })
$result = [pscustomobject][ordered]@{
    schema_version='yime-rime-pime-candidate-evidence-archive-test-v1'
    generated_at_utc=[DateTime]::UtcNow.ToString('o')
    powershell_edition=[string]$PSVersionTable.PSEdition;powershell_version=[string]$PSVersionTable.PSVersion
    total=[int]$checks.Count;passed=[int]($checks.Count-$failed.Count);failed=[int]$failed.Count;checks=@($checks)
    selected_check_pattern=$CheckPattern;expected_check_count=[int]$expectedCheckNames.Count
    full_suite_executed=[bool]$fullSuiteExecuted;all_executed_checks_passed=[bool]$allPassed
    verified=[pscustomobject][ordered]@{
        fixture_archive_exporter_matrix=[bool]($fullSuiteExecuted -and $allPassed)
        content_addressed_objects_and_sealed_control_files=(Test-ChecksPassed @('clean-publish-read-and-source-independent-idempotency'))
        create_new_no_replace=(Test-ChecksPassed @('foreign-final-root-is-preserved','foreign-final-root-wins-before-commit-race-without-replacement'))
        process_interruption_checkpoint_matrix=(Test-ChecksPassed $hardExitNames)
        interrupted_writing_orphans_isolated_before_commit=(Test-ChecksPassed @('hard-exit-object-copy-resumes-in-a-fresh-process'))
        source_independent_post_intent_recovery=(Test-ChecksPassed @(
            'hard-exit-intent-sidecar-resumes-in-a-fresh-process','hard-exit-head-data-resumes-in-a-fresh-process',
            'hard-exit-complete-data-resumes-in-a-fresh-process','hard-exit-before-archive-root-resumes-in-a-fresh-process',
            'hard-exit-archive-root-resumes-in-a-fresh-process'))
        cross_process_exclusive_lock=(Test-ChecksPassed @('shared-lock-blocks-an-independent-process'))
        hardlink_ads_reparse_rejection=(Test-ChecksPassed @(
            'hardlinked-source-is-rejected','alternate-data-stream-source-is-rejected','reparse-source-ancestor-is-rejected'))
        semantic_reseal_scalar_shape_and_zero_length_rejection=(Test-ChecksPassed @(
            'semantically-resealed-and-scalar-shape-tampering-is-rejected'))
    }
    scope_declarations=[pscustomobject][ordered]@{
        fixture_only=$true;fixture_archive_location='case-sibling-archive-under-repository-tmp'
        actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false
        actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false
        installer_or_uninstaller_executed=$false;registry_process_or_production_user_data_touched=$false
    }
    limitations=[pscustomobject][ordered]@{
        hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false
        active_hostile_same_sid_physical_replacement_prevented=$false
        cross_shell_result_requires_independent_ps5_and_ps7_invocations=$true
    }
}
$resultPath = Join-Path $output 'candidate-evidence-archive-result.json'
$resultBytes = Get-TestCanonicalBytes $result
$resultDigest = Write-TestSealedBytes $resultPath $resultBytes
if (-not $allPassed) {
    $failed | Format-Table -AutoSize | Out-String | Write-Host
    throw "Candidate evidence archive checks failed: $resultPath ($resultDigest)"
}
Write-Host "PASS: $($checks.Count) fixture-only candidate evidence archive checks under $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion). $resultPath ($resultDigest)"
