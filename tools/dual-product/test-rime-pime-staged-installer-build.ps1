[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-staged-build-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-staged-build-* fixture root.'
}
if(-not (Test-Path -LiteralPath $expectedParent)){New-Item -ItemType Directory -Path $expectedParent -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null

$modulePath=Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.psm1'
$moduleHash=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
Import-Module -Name $modulePath -Force
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action){
    try{& $Action|Out-Null}catch{return}
    throw 'Unsafe staged-build case was accepted.'
}
function Write-Bytes([string]$Path,[byte[]]$Bytes){
    $parent=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($Bytes,0,$Bytes.Length)}finally{$stream.Dispose()}
}
function Write-Text([string]$Path,[string]$Text){Write-Bytes $Path ([Text.Encoding]::UTF8.GetBytes($Text))}
function Get-Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function New-PublicationCase([string]$Name,[bool]$SeedOld=$true){
    $root=Join-Path $output $Name;$fixtureRepo=Join-Path $root 'repo';$installerDir=Join-Path $fixtureRepo 'installer'
    New-Item -ItemType Directory -Path $installerDir -Force|Out-Null
    $digest=('a'*64);$source=Join-Path $installerDir 'installer.nsi';$plan=Join-Path $installerDir 'package-plan.json'
    Write-Text $source '; fixture installer source';Write-Text $plan '{"fixture":true}'
    $candidate=Join-Path $root 'candidate.exe';$bytes=New-Object byte[] 70000
    for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=65}
    $digestBytes=[Text.Encoding]::ASCII.GetBytes($digest);[Array]::Copy($digestBytes,0,$bytes,1024,$digestBytes.Length)
    Write-Bytes $candidate $bytes
    $installer=Join-Path $installerDir 'YIME-test-setup.exe';$receipt=Join-Path $installerDir 'package-build-receipt.json'
    $package=[pscustomobject]@{
        RepoRoot=$fixtureRepo;Path=$plan;Digest=$digest
        Plan=[pscustomobject]@{architectures=@('x86','x64')}
    }
    if($SeedOld){
        $oldBytes=New-Object byte[] 70000
        for($i=0;$i -lt $oldBytes.Length;$i++){$oldBytes[$i]=79}
        [Array]::Copy($digestBytes,0,$oldBytes,2048,$digestBytes.Length)
        Write-Bytes $installer $oldBytes
        $oldReceipt=[pscustomobject][ordered]@{
            schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
            closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload';architectures=@('x86','x64')
            package_plan_path='installer/package-plan.json';package_plan_sha256=$digest;nsis_profile='x86-x64-v1'
            installer_source_path='installer/installer.nsi';installer_source_sha256=(Get-Hash $source)
            installer_path='installer/YIME-test-setup.exe';installer_size=[long]$oldBytes.Length;installer_sha256=(Get-Hash $installer)
            sealed_at_utc=[DateTime]::UtcNow.ToString('o')
        }
        Write-RimePimeSealedJson $oldReceipt $receipt|Out-Null
    }
    return [pscustomobject]@{
        Root=$root;Package=$package;Source=$source;Candidate=$candidate;Installer=$installer;Receipt=$receipt
    }
}
function Open-CandidateLease($Case){
    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expected.Add([IO.Path]::GetFullPath($Case.Candidate),(Get-Hash $Case.Candidate))
    return Open-RimePimeBuildInputLeases $expected
}
function Get-CanonicalBundleState($Case){
    $state=[ordered]@{}
    foreach($path in @($Case.Installer,$Case.Receipt,($Case.Receipt+'.sha256'))){
        $state[$path]=if(Test-Path -LiteralPath $path -PathType Leaf){Get-Hash $path}else{$null}
    }
    return $state
}
function Assert-CanonicalBundleState($Case,$Before,[string]$Context){
    foreach($path in @($Case.Installer,$Case.Receipt,($Case.Receipt+'.sha256'))){
        $after=if(Test-Path -LiteralPath $path -PathType Leaf){Get-Hash $path}else{$null}
        if([string]$after -cne [string]$Before[$path]){throw "$Context changed canonical member: $path"}
    }
}
function New-PreparedCase($Case,$Leases){
    return New-RimePimePreparedPublication -Package $Case.Package -CandidateStream $Leases[0].Stream `
        -CandidateDigest ([string]$Leases[0].Sha256) -InstallerSourcePath $Case.Source -InstallerPath $Case.Installer `
        -ReceiptPath $Case.Receipt -PublicationRoot (Join-Path $Case.Root 'prepared')
}

Check 'definitions-only-module-exposes-lease-and-publication-functions' {
    Assert-True ((Get-Command Open-RimePimeBuildInputLeases -CommandType Function -ErrorAction Stop) -ne $null) 'Lease helper is missing.'
    Assert-True ((Get-Command Open-RimePimePublicationLock -CommandType Function -ErrorAction Stop) -ne $null) 'Publication lock helper is missing.'
    Assert-True ((Get-Command Invoke-RimePimePublicationCommit -CommandType Function -ErrorAction Stop) -ne $null) 'Publication helper is missing.'
    Assert-True ((Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $moduleHash) 'Module changed while importing.'
}

Check 'candidate-read-lease-blocks-writers-and-retains-the-same-bytes' {
    $case=New-PublicationCase 'lease' $false;$leases=Open-CandidateLease $case
    try{
        Assert-Rejected {
            $writer=[IO.File]::Open($case.Candidate,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
            try{$writer.WriteByte(66)}finally{$writer.Dispose()}
        }
        Test-RimePimeBuildInputLeases @($leases)
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

Check 'canonical-publication-lock-excludes-a-second-publisher-and-is-reusable' {
    $case=New-PublicationCase 'publication-lock' $false
    $case.Installer=Join-Path (Split-Path -Parent $case.Installer) 'YIME-1.4.0+build.7-setup.exe'
    $first=Open-RimePimePublicationLock -InstallerPath $case.Installer -ReceiptPath $case.Receipt
    try{
        Assert-Rejected {Open-RimePimePublicationLock -InstallerPath $case.Installer -ReceiptPath $case.Receipt}
    }finally{$first.Stream.Dispose()}
    $second=Open-RimePimePublicationLock -InstallerPath $case.Installer -ReceiptPath $case.Receipt
    $second.Stream.Dispose()
}

Check 'prepared-publication-and-sidecar-last-commit-preserve-candidate-identity' {
    $case=New-PublicationCase 'success' $true;$leases=Open-CandidateLease $case
    try{
        $digest=[string]$leases[0].Sha256
        $prepared=New-RimePimePreparedPublication -Package $case.Package -CandidateStream $leases[0].Stream `
            -CandidateDigest $digest -InstallerSourcePath $case.Source -InstallerPath $case.Installer `
            -ReceiptPath $case.Receipt -PublicationRoot (Join-Path $case.Root 'prepared')
        $receipt=Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
            -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot (Join-Path $case.Root 'recovery')
        Assert-True ((Get-Hash $case.Installer) -ceq $digest) 'Published installer differs from the leased candidate.'
        Assert-True ([string]$receipt.Digest -ceq [string]$prepared.ReceiptDigest) 'Committed receipt differs from the prepared receipt.'
        Assert-True ((Get-ChildItem -LiteralPath (Join-Path $case.Root 'recovery\previous') -File).Count -eq 3) 'Previous bundle was not preserved.'
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

Check 'fresh-publication-with-no-previous-bundle-commits-all-three-members' {
    $case=New-PublicationCase 'fresh-success' $false;$leases=Open-CandidateLease $case
    try{
        $prepared=New-RimePimePreparedPublication -Package $case.Package -CandidateStream $leases[0].Stream `
            -CandidateDigest ([string]$leases[0].Sha256) -InstallerSourcePath $case.Source -InstallerPath $case.Installer `
            -ReceiptPath $case.Receipt -PublicationRoot (Join-Path $case.Root 'prepared')
        $null=Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
            -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot (Join-Path $case.Root 'recovery')
        foreach($path in @($case.Installer,$case.Receipt,($case.Receipt+'.sha256'))){
            Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Fresh publication member is missing: $path"
        }
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $case.Root 'recovery\previous') -File).Count -eq 0) 'Fresh publication invented a previous bundle.'
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

Check 'v2-and-unknown-canonical-receipts-cannot-be-replaced-by-v1-publication' {
    foreach($schema in @('yime-rime-pime-package-build-receipt-v2','fixture-unknown-receipt-v9')){
        $suffix=if($schema -like '*-v2'){'v2'}else{'unknown'}
        $case=New-PublicationCase ('reject-'+$suffix) $true
        Write-RimePimeSealedJson ([pscustomobject][ordered]@{schema_version=$schema;marker='sealed'}) $case.Receipt|Out-Null
        $before=Get-CanonicalBundleState $case;$leases=Open-CandidateLease $case
        try{
            $prepared=New-PreparedCase $case $leases;$recovery=Join-Path $case.Root 'recovery'
            Assert-Rejected {Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
                -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot $recovery}
            Assert-CanonicalBundleState $case $before $schema
            Assert-True (-not(Test-Path -LiteralPath $recovery)) 'Rejected schema created publication recovery state.'
        }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
    }
}

Check 'every-partial-canonical-bundle-is-rejected-before-recovery-mutation' {
    for($mask=1;$mask -lt 7;$mask++){
        $case=New-PublicationCase ('partial-'+$mask) $false
        if($mask -band 1){Write-Text $case.Installer 'partial installer'}
        if($mask -band 2){Write-Text $case.Receipt 'partial receipt'}
        if($mask -band 4){Write-Text ($case.Receipt+'.sha256') 'partial sidecar'}
        $before=Get-CanonicalBundleState $case;$leases=Open-CandidateLease $case
        try{
            $prepared=New-PreparedCase $case $leases;$recovery=Join-Path $case.Root 'recovery'
            Assert-Rejected {Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
                -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot $recovery}
            Assert-CanonicalBundleState $case $before "partial mask $mask"
            Assert-True (-not(Test-Path -LiteralPath $recovery)) "Partial mask $mask created publication recovery state."
        }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
    }
}

Check 'complete-but-invalid-v1-bundle-is-rejected-before-recovery-mutation' {
    $case=New-PublicationCase 'invalid-v1' $true
    $stream=[IO.File]::Open($case.Installer,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Position=0;$stream.WriteByte(88)}finally{$stream.Dispose()}
    $before=Get-CanonicalBundleState $case;$leases=Open-CandidateLease $case
    try{
        $prepared=New-PreparedCase $case $leases;$recovery=Join-Path $case.Root 'recovery'
        Assert-Rejected {Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
            -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot $recovery}
        Assert-CanonicalBundleState $case $before 'invalid v1'
        Assert-True (-not(Test-Path -LiteralPath $recovery)) 'Invalid v1 created publication recovery state.'
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

Check 'third-item-failure-rolls-back-the-original-three-file-bundle' {
    $case=New-PublicationCase 'rollback' $true;$before=@{}
    foreach($path in @($case.Installer,$case.Receipt,($case.Receipt+'.sha256'))){$before[$path]=Get-Hash $path}
    $leases=Open-CandidateLease $case
    try{
        $prepared=New-RimePimePreparedPublication -Package $case.Package -CandidateStream $leases[0].Stream `
            -CandidateDigest ([string]$leases[0].Sha256) -InstallerSourcePath $case.Source -InstallerPath $case.Installer `
            -ReceiptPath $case.Receipt -PublicationRoot (Join-Path $case.Root 'prepared')
        # Permit the pre-mutation validation read while denying the later
        # delete/move required for the third publication member.
        $blocker=[IO.File]::Open(($case.Receipt+'.sha256'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try{
            Assert-Rejected {
                Invoke-RimePimePublicationCommit -Package $case.Package -Prepared $prepared `
                    -InstallerPath $case.Installer -ReceiptPath $case.Receipt -RecoveryRoot (Join-Path $case.Root 'recovery')
            }
        }finally{$blocker.Dispose()}
        foreach($path in $before.Keys){Assert-True ((Get-Hash $path) -ceq [string]$before[$path]) "Rollback changed original bundle member: $path"}
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $case.Root 'recovery\failed-new') -File).Count -eq 2) 'Rollback did not quarantine the first two committed new members.'
        Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $case.Root 'recovery\previous') -File).Count -eq 0) 'Rollback did not restore every moved previous member.'
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

Check 'hard-linked-candidate-is-rejected-before-lease' {
    $case=New-PublicationCase 'hardlink' $false
    $link=Join-Path $case.Root 'candidate-link.exe';New-Item -ItemType HardLink -Path $link -Target $case.Candidate|Out-Null
    Assert-Rejected {Open-CandidateLease $case}
}

Check 'alternate-data-stream-candidate-is-rejected-before-lease' {
    $case=New-PublicationCase 'ads' $false
    Set-Content -LiteralPath ($case.Candidate+':Zone.Identifier') -Value 'fixture' -Encoding ASCII
    Assert-Rejected {Open-CandidateLease $case}
}

Check 'leased-wrong-architecture-stage-cannot-be-swapped-and-is-rejected' {
    $root=Join-Path $output 'leased-stage-pe';New-Item -ItemType Directory -Path $root|Out-Null
    $wrongX86=Join-Path $root 'PIMETextService_x86.dll'
    $correctReplacement=Join-Path $root 'correct-x86-replacement.dll'
    Copy-Item -LiteralPath (Join-Path $repo 'build64\PIMETextService\Release\PIMETextService.dll') -Destination $wrongX86
    Copy-Item -LiteralPath (Join-Path $repo 'build\PIMETextService\Release\PIMETextService.dll') -Destination $correctReplacement
    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expected.Add($wrongX86,(Get-Hash $wrongX86))
    $leases=Open-RimePimeBuildInputLeases $expected
    try{
        Assert-Rejected {[IO.File]::Replace($correctReplacement,$wrongX86,(Join-Path $root 'swap-backup.dll'),$true)}
        $message=''
        try{
            & (Join-Path $repo 'tools\verify-pe-architectures.ps1') -RepoRoot $repo `
                -X86TextService $wrongX86 `
                -X64TextService (Join-Path $repo 'build64\PIMETextService\Release\PIMETextService.dll') `
                -X86Launcher (Join-Path $repo 'build\PIMELauncher\PIMELauncher.exe') `
                -X86RegistrationStatus (Join-Path $repo 'build\PIMETextService\Release\PIMERegistrationStatus.exe') `
                -X64RegistrationStatus (Join-Path $repo 'build64\PIMETextService\Release\PIMERegistrationStatus.exe') `
                -SkipPackagedRime 6>$null | Out-Null
            throw 'Wrong-architecture leased stage fixture was accepted.'
        }catch{$message=$_.Exception.Message}
        Assert-True ($message -like '*expected 0x014C but found 0x8664*') 'Wrong-architecture stage did not fail the explicit PE machine gate.'
        Test-RimePimeBuildInputLeases @($leases)
    }finally{foreach($lease in $leases){$lease.Stream.Dispose()}}
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-staged-installer-build-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    test_level='isolated-filesystem-build-lease-and-publication-transaction-only';checks_count=$checks.Count
    passed=($failed.Count -eq 0);actual_makensis_executed=$false;actual_installer_or_uninstaller_executed=$false
    registry_or_product_process_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
    final_payload_closure=$false;module_sha256=$moduleHash
    helper_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();checks=@($checks)
}
$resultPath=Join-Path $output 'result.json';$digest=Write-RimePimeStageSealedJson $result $resultPath
if($failed.Count -gt 0){$failed|ForEach-Object{Write-Error "$($_.name): $($_.error)"};throw "$($failed.Count) staged-build checks failed."}
Write-Host "PASS: $($checks.Count) isolated staged-build lease/publication checks passed. Evidence: $resultPath ($digest)"
