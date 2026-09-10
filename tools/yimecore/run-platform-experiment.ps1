[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('mainstream_x64','arm64')][string]$Target,
    [ValidateSet('Plan','Build','Package')][string]$Action='Plan',
    [string]$OutputRoot,
    [string]$SpeechAdmissionRoot,
    [string]$ExpectedSpeechAdmissionSummarySha256,
    [string]$ExpectedSpeechSourceInventorySha256
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$targetConfig=Get-YimeCoreExperimentTarget $Target
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$plan=[ordered]@{target=$Target;status='active';architecture=$targetConfig.architecture;
    stages=@('source_build','isolated_native_contracts','target_package_transactions','installed_registered_host','physical_live_host','daily_use_and_sealing');
    physical_host=$targetConfig.physical_host;physical_host_passed=$null;installed=$false;
    cloud_provisioning_authorized=$false;hardware_purchase_authorized=$false;
    note='Build produces current-identity source artifacts only. No registration, installation or target executable execution. Native acceptance requires an identified physical host.'}
if($Action -eq 'Plan'){$plan|ConvertTo-Json -Depth 8;return}
$scope=Get-YimeCoreExperimentBuildScope $Target
$allowed=Join-Path $repo '.tmp\yimecore-platform-experiments'
if(-not $OutputRoot){$prefix=if($Action -eq 'Package' -and $Target -eq 'mainstream_x64'){'mx64-package-'}else{$Target+'-'};$OutputRoot=Join-Path $allowed ($prefix+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Use a new isolated platform-experiment output child.'}
Assert-LocalProductPlainPath $out
$expectedLeaf=if($Action -eq 'Package' -and $Target -eq 'mainstream_x64'){'^mx64-package-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'}else{'^'+[regex]::Escape($Target)+'-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'}
if((Split-Path -Leaf $out) -cnotmatch $expectedLeaf){throw 'Output name must identify the isolated target and action.'}
if($Action -eq 'Package'){
    if([string]::IsNullOrWhiteSpace($SpeechAdmissionRoot) -or $ExpectedSpeechAdmissionSummarySha256 -notmatch '^[a-fA-F0-9]{64}$' -or $ExpectedSpeechSourceInventorySha256 -notmatch '^[a-fA-F0-9]{64}$'){
        throw 'Package requires an explicit completed speech admission root and both SHA256 pins.'
    }
    & (Join-Path $PSScriptRoot 'build-local-product.ps1') -OutputRoot $out -ExperimentTarget $Target `
        -SpeechAdmissionRoot $SpeechAdmissionRoot -ExpectedSpeechAdmissionSummarySha256 $ExpectedSpeechAdmissionSummarySha256 `
        -ExpectedSpeechSourceInventorySha256 $ExpectedSpeechSourceInventorySha256
    if($LASTEXITCODE -ne 0){throw 'Target package build failed; inspect its isolated evidence.'}
    Write-Output "Experiment package complete only; installation and host acceptance pending. Evidence: $out"
    return
}
$null=Get-Command cmake,go -ErrorAction Stop
$nativeGenerator=if($Target -eq 'mainstream_x64'){'Visual Studio 18 2026'}else{'Visual Studio 17 2022'}
New-Item -ItemType Directory -Path $out | Out-Null
$before=Get-LocalProductProtectionEvidence
$product=Get-LocalProductDescriptor (Join-Path $PSScriptRoot 'local-product.json')
$sourcePaths=@(Get-LocalProductSourcePaths $repo $product)
$sourceRecords=@($sourcePaths | ForEach-Object {Get-LocalProductFileRecord $repo $_})
Write-LocalProductJson $sourceRecords (Join-Path $out 'source-hashes.json')
$environmentNames=@('GOOS','GOARCH','CGO_ENABLED','GOFLAGS')
$oldEnvironment=@{}
foreach($name in $environmentNames){$oldEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$passed=$false;$failure=$null;$records=@();$protected=$false
try {
    $env:GOOS='windows';$env:GOARCH=$targetConfig.go_arch;$env:CGO_ENABLED='0';$env:GOFLAGS=''
    $build=Join-Path $out 'tsf-build'
    & cmake -S (Join-Path $repo 'YimeTextServiceExperiment') -B $build -G $nativeGenerator -A $targetConfig.cmake_platform -DYIME_LOCAL_PRODUCT=ON 2>&1 | Tee-Object -FilePath (Join-Path $out 'configure.txt')
    if($LASTEXITCODE -ne 0){throw 'Target TSF configure failed; inspect the isolated configure log.'}
    & cmake --build $build --config Release --parallel 2>&1 | Tee-Object -FilePath (Join-Path $out 'build.txt')
    if($LASTEXITCODE -ne 0){throw 'Target TSF build failed.'}
    Push-Location (Join-Path $repo 'go-backend')
    try {
        foreach($entry in $product.go_binaries){
            $dest=Resolve-LocalProductChild $out $entry.path
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            $buildArgs=@('build','-trimpath','-buildvcs=false','-o',$dest)
            if($entry.gui){$buildArgs+=@('-ldflags','-H=windowsgui')}
            & go @buildArgs $entry.source 2>&1 | Tee-Object -FilePath (Join-Path $out 'go-build.txt') -Append
            if($LASTEXITCODE -ne 0){throw "Target Go build failed: $($entry.source)"}
        }
    } finally {Pop-Location}
    $peFiles=@(Get-ChildItem -LiteralPath (Join-Path $build 'Release') -File | Where-Object Extension -in @('.exe','.dll')) + @(Get-ChildItem -LiteralPath (Join-Path $out 'bin') -Filter '*.exe' -File)
    if($peFiles.Count -lt 7){throw 'Expected target artifacts missing.'}
    foreach($file in $peFiles){
        $stream=[IO.File]::OpenRead($file.FullName);$reader=[IO.BinaryReader]::new($stream)
        try {$stream.Position=0x3c;$offset=$reader.ReadInt32();$stream.Position=$offset;if($reader.ReadUInt32() -ne 0x4550){throw 'Invalid PE signature'};$machine=$reader.ReadUInt16()}finally{$reader.Dispose()}
        $expectedMachine=if($Target -eq 'arm64'){0xaa64}else{0x8664}
        if($machine -ne $expectedMachine){throw "Wrong target machine: $($file.Name)"}
        $record=Get-LocalProductFileRecord $out $file.FullName.Substring($out.Length+1)
        $record['pe_machine']='0x{0:x4}' -f $machine
        $records+=$record
    }
    Assert-LocalProductSourceUnchanged $repo $sourceRecords
    $passed=$true
} catch {$failure=$_.Exception.Message;throw}
finally {
    foreach($name in $environmentNames){[Environment]::SetEnvironmentVariable($name,$oldEnvironment[$name],'Process')}
    $after=Get-LocalProductProtectionEvidence
    $protected=($before|ConvertTo-Json -Depth 30 -Compress) -ceq ($after|ConvertTo-Json -Depth 30 -Compress)
    Write-LocalProductJson ([ordered]@{schema_version='yimecore-platform-source-build-v1';generated_at=[DateTime]::UtcNow.ToString('o');
        target=$Target;development_scope=$scope;git_commit=(& git -C $repo rev-parse HEAD).Trim();git_dirty=[bool]((& git -C $repo status --porcelain).Count);
        current_product_identity=$product.identity;source_build_passed=($passed -and $protected);failure=$failure;
        protected_registration_unchanged=$protected;artifacts=$records;target_executables_run=$false;installed=$false;
        native_contracts_passed=$null;target_package_passed=$null;physical_host_passed=$null;release_ready=$false}) (Join-Path $out 'summary.json')
    if(-not $protected){throw 'Protected registration/default changed during build; stop and inspect.'}
}
Write-Output "Source build complete only; native acceptance pending. Evidence: $out"
