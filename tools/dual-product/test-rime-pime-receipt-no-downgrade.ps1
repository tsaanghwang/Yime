[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$allowed=Join-Path $repo '.tmp\dual-product'
if((Split-Path -Parent $output) -ine $allowed -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-receipt-no-downgrade-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $output)){
    throw 'Use a fresh immediate .tmp/dual-product/dp1-receipt-no-downgrade-* fixture root.'
}
if(-not(Test-Path -LiteralPath $allowed)){New-Item -ItemType Directory -Path $allowed -Force|Out-Null}
New-Item -ItemType Directory -Path $output|Out-Null
. (Join-Path $PSScriptRoot 'rime-pime-package-plan.ps1')

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})}
}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Rejected([scriptblock]$Action,[string]$Like){
    try{& $Action|Out-Null;throw 'Expected rejection did not occur.'}
    catch{
        if($_.Exception.Message -eq 'Expected rejection did not occur.'){throw}
        if($_.Exception.Message -notlike $Like){throw "Unexpected rejection: $($_.Exception.Message)"}
    }
}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-Bytes([string]$Path,[byte[]]$Bytes){
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllBytes($Path,$Bytes)
}
function Write-Text([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function New-Case([string]$Name,[string]$Schema='yime-rime-pime-package-build-receipt-v2'){
    $root=Join-Path $output ('cases\'+$Name+'\repo');$installerRoot=Join-Path $root 'installer'
    New-Item -ItemType Directory -Path $installerRoot -Force|Out-Null
    $digest=('a'*64);$plan=Join-Path $installerRoot 'package-plan.json';$source=Join-Path $installerRoot 'installer.nsi'
    Write-Text $plan '{"fixture":true}';Write-Text $source '; disabled fixture source'
    $installer=Join-Path $installerRoot 'YIME-test-setup.exe';$bytes=New-Object byte[] 70000
    for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=65}
    $marker=[Text.Encoding]::ASCII.GetBytes($digest);[Array]::Copy($marker,0,$bytes,1024,$marker.Length);Write-Bytes $installer $bytes
    $receipt=Join-Path $installerRoot 'package-build-receipt.json'
    Write-RimePimeSealedJson ([pscustomobject][ordered]@{schema_version=$Schema;marker='sealed'}) $receipt|Out-Null
    return [pscustomobject]@{
        Repo=$root;Plan=$plan;Source=$source;Installer=$installer;Receipt=$receipt
        Package=[pscustomobject]@{RepoRoot=$root;Path=$plan;Digest=$digest;Plan=[pscustomobject]@{architectures=@('x86','x64')}}
    }
}
function Get-State($Case){
    $state=[ordered]@{}
    foreach($path in @($Case.Installer,$Case.Source,$Case.Plan,$Case.Receipt,($Case.Receipt+'.sha256'))){
        $state[$path]=if(Test-Path -LiteralPath $path -PathType Leaf){Hash $path}else{$null}
    }
    return $state
}
function Assert-State($Case,$Before,[string]$Context){
    foreach($path in $Before.Keys){
        $after=if(Test-Path -LiteralPath $path -PathType Leaf){Hash $path}else{$null}
        if([string]$after -cne [string]$Before[$path]){throw "$Context changed fixture input: $path"}
    }
}
function Write-ValidV1($Case){
    $value=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v1';product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload';architectures=@('x86','x64')
        package_plan_path='installer/package-plan.json';package_plan_sha256=[string]$Case.Package.Digest;nsis_profile='x86-x64-v1'
        installer_source_path='installer/installer.nsi';installer_source_sha256=(Hash $Case.Source)
        installer_path='installer/YIME-test-setup.exe';installer_size=[long](Get-Item $Case.Installer).Length
        installer_sha256=(Hash $Case.Installer);sealed_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    Write-RimePimeSealedJson $value $Case.Receipt|Out-Null
}

Check 'legacy-writer-rejects-v2-and-unknown-with-exact-bytes-unchanged' {
    foreach($schema in @('yime-rime-pime-package-build-receipt-v2','fixture-unknown-receipt-v9')){
        $case=New-Case ('writer-'+[IO.Path]::GetFileNameWithoutExtension($schema)) $schema;$before=Get-State $case
        Assert-Rejected {Write-RimePimePackageBuildReceipt -Package $case.Package -InstallerPath $case.Installer `
            -InstallerSourcePath $case.Source -ReceiptPath $case.Receipt} '*Refusing to overwrite canonical package build receipt schema*'
        Assert-State $case $before $schema
    }
}

Check 'legacy-writer-rejects-a-partial-receipt-pair-without-mutation' {
    $case=New-Case 'writer-partial';Remove-Item -LiteralPath ($case.Receipt+'.sha256')
    $before=Get-State $case
    Assert-Rejected {Write-RimePimePackageBuildReceipt -Package $case.Package -InstallerPath $case.Installer `
        -InstallerSourcePath $case.Source -ReceiptPath $case.Receipt} '*JSON/sidecar pair is partial*'
    Assert-State $case $before 'partial writer target'
}

Check 'validated-v1-writer-refresh-remains-supported' {
    $case=New-Case 'writer-v1';Write-ValidV1 $case
    $stream=[IO.File]::Open($case.Installer,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.WriteByte(83)}finally{$stream.Dispose()}
    $written=Write-RimePimePackageBuildReceipt -Package $case.Package -InstallerPath $case.Installer `
        -InstallerSourcePath $case.Source -ReceiptPath $case.Receipt
    Assert-True ([string]$written.Receipt.schema_version -ceq 'yime-rime-pime-package-build-receipt-v1') 'V1 refresh changed schema.'
    Assert-True ([string]$written.Receipt.installer_sha256 -ceq (Hash $case.Installer)) 'V1 refresh did not bind changed installer bytes.'
}

Check 'strict-v1-reader-still-rejects-v2' {
    $case=New-Case 'strict-reader'
    Assert-Rejected {Read-RimePimePackageBuildReceipt -Package $case.Package -ReceiptPath $case.Receipt} '*open or incomplete schema*'
}

Check 'sign-release-rejects-v2-before-plan-read-or-signing-in-both-modes' {
    $case=New-Case 'sign-v2';$before=Get-State $case;$sign=Join-Path $repo 'tools\sign-release.ps1'
    $missingPlan=Join-Path $case.Repo 'installer\must-not-be-read.json'
    Assert-Rejected {& $sign -Root $case.Repo -IncludeInstaller -PackagePlanPath $missingPlan -ReceiptPath $case.Receipt} '*disabled v2 evidence cannot be signed*'
    Assert-State $case $before 'installer signing v2 guard'
    Assert-Rejected {& $sign -Root $case.Repo -PackagePlanPath $missingPlan -ReceiptPath $case.Receipt} '*disabled v2 evidence cannot be signed*'
    Assert-State $case $before 'payload signing v2 guard'
    Assert-Rejected {& $sign -Root $case.Repo -IncludeInstaller -PackagePlanPath $missingPlan `
        -ReceiptPath (Join-Path $case.Repo 'alternate-receipt.json')} '*disabled v2 evidence cannot be signed*'
    Assert-State $case $before 'alternate-path signing v2 guard'
}

Check 'sign-release-rejects-unknown-and-partial-receipts-before-plan-read' {
    $sign=Join-Path $repo 'tools\sign-release.ps1'
    $unknown=New-Case 'sign-unknown' 'fixture-unknown-receipt-v9';$before=Get-State $unknown
    Assert-Rejected {& $sign -Root $unknown.Repo -IncludeInstaller -PackagePlanPath (Join-Path $unknown.Repo 'missing.json') `
        -ReceiptPath $unknown.Receipt} '*refuses canonical package receipt schema*'
    Assert-State $unknown $before 'unknown signing guard'
    $partial=New-Case 'sign-partial';Remove-Item -LiteralPath ($partial.Receipt+'.sha256');$before=Get-State $partial
    Assert-Rejected {& $sign -Root $partial.Repo -IncludeInstaller -PackagePlanPath (Join-Path $partial.Repo 'missing.json') `
        -ReceiptPath $partial.Receipt} '*JSON/sidecar pair is partial*'
    Assert-State $partial $before 'partial signing guard'
}

Check 'signing-guard-is-lexically-before-package-read-and-signer-call' {
    $source=[IO.File]::ReadAllText((Join-Path $repo 'tools\sign-release.ps1'))
    $guard=$source.IndexOf('Read-RimePimePackageBuildReceiptEnvelope',[StringComparison]::Ordinal)
    $planRead=$source.IndexOf('Read-RimePimePackagePlan',[StringComparison]::Ordinal)
    $signCall=$source.IndexOf("'sign-file.ps1'",[StringComparison]::Ordinal)
    Assert-True ($guard -ge 0 -and $guard -lt $planRead -and $planRead -lt $signCall) 'Signing guard is not before package parsing and signer invocation.'
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-receipt-no-downgrade-test-v1';generated_at_utc=[DateTime]::UtcNow.ToString('o')
    checks_count=$checks.Count;passed=($failed.Count -eq 0);checks=@($checks)
    signing_process_executed=$false;installer_or_uninstaller_executed=$false;product_process_touched=$false
    registry_touched=$false;default_input_method_changed=$false;production_user_data_read_or_written=$false
    package_plan_helper_sha256=(Hash (Join-Path $PSScriptRoot 'rime-pime-package-plan.ps1'))
    sign_release_sha256=(Hash (Join-Path $repo 'tools\sign-release.ps1'))
}
$resultPath=Join-Path $output 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 12)+"`n"),[Text.UTF8Encoding]::new($false))
if($failed.Count){$failed|ForEach-Object{Write-Error "$($_.name): $($_.error)"};throw "$($failed.Count) no-downgrade checks failed."}
Write-Host "PASS: $($checks.Count) v1/v2 no-downgrade checks passed without signing or product execution. Evidence: $resultPath"
