[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot 'local12-maintenance-preparation.psm1'
$module=Import-Module $modulePath -Force -PassThru
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-local13-preparation-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Pass,[string]$Name) { if (-not $Pass) {throw "FAIL: $Name"};$checks.Add($Name) }
function Reject([scriptblock]$Code,[string]$Name) { $failed=$false;try {$null=& $Code} catch {$failed=$true};Check $failed $Name }
function Hash([string]$Path) {(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json($Value,[string]$Path) {$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Path -Encoding UTF8}
function Fixture([string]$Name) {
    $path=Join-Path $root $Name
    $paths=@('local-product.json','maintenance/Manage-YimeCoreTrial.ps1','maintenance/manage-local-product.ps1',
        'maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1',
        'x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll',
        'x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
        'bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','bin/YimeCoreRecoveryProbe.exe')
    foreach ($member in $paths) {
        $file=Join-Path $path $member;New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force|Out-Null
        Set-Content -LiteralPath $file -Value "throw 'Synthetic package payload must never execute.'" -Encoding UTF8
    }
    # The exported helper independently pins the reviewed guard, so a positive
    # fixture uses its real source bytes as data. No package script is invoked.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1') -Destination (Join-Path $path 'maintenance/Manage-YimeCoreTrial.ps1') -Force
    $descriptor=@{schema_version='yimecore-local-product-v1';version='0.1.0-local.13';
        scope=@{computer_name='MYCOMPUTER';active_architectures=@('x64','x86')};
        identity=@{product_key='YimeCoreExperimentalTrial';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'}}
    Json $descriptor (Join-Path $path 'local-product.json')
    $manifest=@{tool_version='yimecore-local-builder-v1';package_contract='yimecore-local-product-package-v1';product_version='0.1.0-local.13';
        package_id='synthetic-local13-normal';scope='fixture only';files=@(foreach ($member in $paths) {
            $file=Join-Path $path $member;@{path=$member;sha256=(Hash $file);bytes=(Get-Item -LiteralPath $file).Length}
        })}
    Json $manifest (Join-Path $path 'package-manifest.json')
    $contract=@{product_version='0.1.0-local.13';package_id=$manifest.package_id;guarded_native_desktop_rehearsal=$true;member_count=$paths.Count;
        manifest_sha256=(Hash (Join-Path $path 'package-manifest.json'));manager_sha256=(Hash (Join-Path $path 'maintenance/Manage-YimeCoreTrial.ps1'));
        wrapper_sha256=(Hash (Join-Path $path 'maintenance/manage-local-product.ps1'))}
    return @{root=$path;contract=$contract;manifest=$manifest;descriptor=$descriptor}
}
try {
    $fixture=Fixture 'source'
    $source=Join-Path $PSScriptRoot 'rollback-failure-runtime.go'
    $probeBytes=New-Object byte[] 256
    $probeBytes[0]=0x4d;$probeBytes[1]=0x5a;$probeBytes[0x3c]=0x80;$probeBytes[0x80]=0x50;$probeBytes[0x81]=0x45
    $probeBytes[0x84]=0x64;$probeBytes[0x85]=0x86;$probeBytes[0x98]=0x0b;$probeBytes[0x99]=0x02
    $probe=Join-Path $root 'probe.exe';[IO.File]::WriteAllBytes($probe,$probeBytes);$probeHash=Hash $probe
    $before=@(Get-ChildItem -LiteralPath $root -Recurse -File).Count
    $plan=Get-YimeCoreFaultPreparationPlan $fixture.root $fixture.contract $source (Hash $source)
    Check ($plan.package_version -ceq '0.1.0-local.13' -and $plan.schema_version -ceq 'yimecore-local13-fault-preparation-plan-v1') 'version-specific plan'
    Check ($plan.unexpected_success_rollback_guard_available -and -not $plan.execution_authorized -and -not $plan.ready_to_execute -and -not $plan.probe_exit_observed) 'guard availability never authorizes execution'
    Check (@(Get-ChildItem -LiteralPath $root -Recurse -File).Count -eq $before) 'Plan remains read-only'
    $wrong=$fixture.contract.Clone();$wrong.Remove('product_version')
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'legacy version default cannot accept local13 guard'
    $wrong=$fixture.contract.Clone();$wrong.guarded_native_desktop_rehearsal='true'
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'guard intent requires literal bool'
    $wrong=$fixture.contract.Clone();$wrong.package_id='other'
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'source package ID is pinned'
    $wrong=$fixture.contract.Clone();$wrong.Remove('package_id')
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'guarded source requires package ID pin'
    $wrong=$fixture.contract.Clone();$wrong.manager_sha256='0'*64
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'source guard controller hash is pinned'
    $fake=Fixture 'self-attested-controller'
    $fakeManager=Join-Path $fake.root 'maintenance/Manage-YimeCoreTrial.ps1'
    Set-Content -LiteralPath $fakeManager -Value "throw 'No rollback guard exists here.'" -Encoding UTF8
    $fake.contract.manager_sha256=Hash $fakeManager
    $fakeRecord=@($fake.manifest.files|Where-Object {$_.path -ceq 'maintenance/Manage-YimeCoreTrial.ps1'})[0]
    $fakeRecord.sha256=$fake.contract.manager_sha256;$fakeRecord.bytes=(Get-Item -LiteralPath $fakeManager).Length
    Json $fake.manifest (Join-Path $fake.root 'package-manifest.json');$fake.contract.manifest_sha256=Hash (Join-Path $fake.root 'package-manifest.json')
    Reject {Get-YimeCoreFaultPreparationPlan $fake.root $fake.contract $source (Hash $source)} 'self-attested fake controller cannot claim guard availability'
    $wrong=$fixture.contract.Clone();$wrong.manager_sha256='ff3a563bf58999683f34e9c6fb73656ea6790b120e48fd322b71f97c99818cca'
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'legacy controller cannot claim the local13 guard'
    foreach ($field in @('package_contract','tool_version','product_version','package_id')) {
        $bad=Fixture ('array-manifest-'+$field);$bad.manifest[$field]=@($bad.manifest[$field])
        Json $bad.manifest (Join-Path $bad.root 'package-manifest.json');$bad.contract.manifest_sha256=Hash (Join-Path $bad.root 'package-manifest.json')
        Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} ('reject singleton array manifest '+$field)
    }
    foreach ($field in @('schema_version','version','scope.computer_name','identity.product_key','identity.clsid','identity.profile')) {
        $bad=Fixture ('array-descriptor-'+$field);$parts=$field.Split('.');$owner=$bad.descriptor
        if($parts.Count -gt 1){$owner=$owner[$parts[0]]};$name=$parts[-1];$owner[$name]=@($owner[$name])
        $descriptorPath=Join-Path $bad.root 'local-product.json';Json $bad.descriptor $descriptorPath
        $record=@($bad.manifest.files|Where-Object {$_.path -ceq 'local-product.json'})[0]
        $record.sha256=Hash $descriptorPath;$record.bytes=(Get-Item -LiteralPath $descriptorPath).Length
        Json $bad.manifest (Join-Path $bad.root 'package-manifest.json');$bad.contract.manifest_sha256=Hash (Join-Path $bad.root 'package-manifest.json')
        Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} ('reject singleton array descriptor '+$field)
    }
    foreach ($field in @('product_version','package_id')) {
        $wrong=$fixture.contract.Clone();$wrong[$field]=@($wrong[$field])
        Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} ('reject array contract '+$field)
    }
    $wrong=$fixture.contract.Clone();$wrong.member_count=[string]$wrong.member_count
    Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'reject string contract member count'
    $bad=Fixture 'string-architectures';$bad.descriptor.scope.active_architectures='x64|x86'
    $descriptorPath=Join-Path $bad.root 'local-product.json';Json $bad.descriptor $descriptorPath
    $record=@($bad.manifest.files|Where-Object {$_.path -ceq 'local-product.json'})[0]
    $record.sha256=Hash $descriptorPath;$record.bytes=(Get-Item -LiteralPath $descriptorPath).Length
    Json $bad.manifest (Join-Path $bad.root 'package-manifest.json');$bad.contract.manifest_sha256=Hash (Join-Path $bad.root 'package-manifest.json')
    Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject scalar architecture string masquerading as array'
    $catalog=Get-YimeCoreFaultPreparationCatalog $fixture.root $fixture.contract
    $sameBytes=& $module {param($p,$h) Read-PreparationPinnedJson $p $h} (Join-Path $fixture.root 'package-manifest.json') $fixture.contract.manifest_sha256
    Check ($sameBytes.package_id -ceq $fixture.contract.package_id) 'pinned JSON decodes the same held bytes that were hashed'
    Reject {& $module {param($p) Read-PreparationPinnedJson $p ('0'*64)} (Join-Path $fixture.root 'package-manifest.json')} 'pinned JSON rejects alternate content before parsing'
    $leases=& $module {param($c,$p,$h) Open-PreparationInputLeases $c $p $h} $catalog $probe $probeHash
    try {
        Check ($leases.Count -eq 14) 'all source members manifest and replacement leased together'
        $lockedFile=Join-Path $fixture.root 'bin/YimeBroker.exe'
        Reject {$s=[IO.File]::Open($lockedFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$s.Dispose()} 'write rejected while input lease is held'
        Reject {[IO.File]::Delete($lockedFile)} 'delete rejected while input lease is held'
        Reject {$s=[IO.File]::Open($probe,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$s.Dispose()} 'replacement write rejected while leased'
        Reject {& $module {param($s,$p) Copy-PreparationLeasedFile $s $p ('0'*64) $s.Length} $leases['bin/YimeBroker.exe'] (Join-Path $root 'wrong-copy')} 'destination copy hash independently verified'
    } finally {foreach ($stream in $leases.Values) {$stream.Dispose()}}
    $stream=[IO.File]::Open($lockedFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$stream.Dispose()
    Check $true 'source write handle available after lease disposal'
    Reject {& $module {param($c,$p) Open-PreparationInputLeases $c $p ('0'*64)} $catalog $probe} 'late replacement hash failure rejects lease set'
    $stream=[IO.File]::Open($lockedFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Dispose()
    Check $true 'partial acquisition failure disposes earlier input handles'
    $out=Join-Path $root 'prepared'
    $result=New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe $probeHash $out $root
    $manifest=Get-Content (Join-Path $out 'package-manifest.json') -Raw|ConvertFrom-Json
    Check ($result.static_package_verification_passed -and $result.file_count -eq 12 -and $result.schema_version -ceq 'yimecore-local13-fault-preparation-output-v1') 'guarded fault copy verifies all members'
    Check ($manifest.package_id -cne $fixture.contract.package_id -and $manifest.package_id -ceq $result.failure_package_id -and $manifest.source_package_id -ceq $fixture.contract.package_id) 'fault identity is distinct and source identity preserved'
    Check ($manifest.source_package_manifest_sha256 -ceq $fixture.contract.manifest_sha256 -and $result.failure_manifest_sha256 -cne $fixture.contract.manifest_sha256) 'fault manifest preserves source manifest provenance'
    Check ($manifest.rehearsal_only -is [bool] -and $manifest.rehearsal_only -and $manifest.preparation_only -is [bool] -and $manifest.preparation_only) 'strict failure-only JSON markers'
    Check ($manifest.rehearsal_mode -ceq 'NativeDesktopRehearsal' -and $manifest.expected_runtime_exit_code -eq 86) 'failure mode and expected exit recorded without running probe'
    # Exercise only the controller's pure manifest predicate from source, never
    # the controller entry point, the copied script, or a registration operation.
    $guardTokens=$null;$guardErrors=$null
    $guardAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'),[ref]$guardTokens,[ref]$guardErrors)
    $guardFunction=@($guardAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-NativeDesktopRehearsalPackage'},$true))
    Check ($guardErrors.Count -eq 0 -and $guardFunction.Count -eq 1) 'source manifest guard is uniquely extracted'
    . ([scriptblock]::Create($guardFunction[0].Extent.Text))
    $NativeDesktopRehearsal=$true
    Assert-NativeDesktopRehearsalPackage $manifest
    Check $true 'prepared manifest passes guarded rehearsal predicate'
    $NativeDesktopRehearsal=$false
    Reject {Assert-NativeDesktopRehearsalPackage $manifest} 'prepared fault manifest rejects ordinary NativeDesktop route'
    $NativeDesktopRehearsal=$true
    $ordinaryManifest=Get-Content (Join-Path $fixture.root 'package-manifest.json') -Raw|ConvertFrom-Json
    Reject {Assert-NativeDesktopRehearsalPackage $ordinaryManifest} 'ordinary manifest rejects rehearsal route'
    Check (-not $result.execution_authorized -and -not $result.ready_to_execute -and -not $result.same_sid_execution_boundary -and -not $result.product_executed -and -not $result.probe_exit_observed) 'copy leases do not claim native execution safety or success'
    Check ($result.unexpected_success_rollback_guard_available -and (Hash (Join-Path $out 'maintenance/Manage-YimeCoreTrial.ps1')) -ceq $fixture.contract.manager_sha256) 'copied guarded controller preserved'
    Check ((Hash (Join-Path $fixture.root 'package-manifest.json')) -ceq $fixture.contract.manifest_sha256) 'ordinary source manifest unchanged'
    $unchanged=@($fixture.manifest.files|Where-Object {$_.path -cne 'bin/YimeCoreTrialRuntime.exe'}|Where-Object {(Hash (Join-Path $out $_.path)) -cne $_.sha256})
    Check ($unchanged.Count -eq 0) 'all non-Runtime public payloads preserved byte for byte'
    Reject {New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe $probeHash $out $root} 'fault output cannot be overwritten'
    $stream=[IO.File]::Open($probe,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Dispose()
    Check $true 'successful preparation disposes replacement lease'
    $entry=Join-Path $PSScriptRoot 'prepare-local13-maintenance.ps1'
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'entry parses on current shell'
    $entryText=Get-Content $entry -Raw
    Check ($entryText.Contains("`$Action='Plan'") -and $entryText.Contains("GOPROXY='off'") -and $entryText.Contains("GOTOOLCHAIN='local'") -and $entryText.Contains("GOWORK='off'")) 'default Plan and offline local compiler'
    Check ($entryText.Contains('$compileSourceLease=[IO.File]::Open($buildSource,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)') -and $entryText.Contains('$compileSourceHasher.ComputeHash($compileSourceLease)') -and $entryText.LastIndexOf('$compileSourceLease.Dispose()') -gt $entryText.IndexOf('$process.WaitForExit(60000)')) 'verified compiler source lease spans compiler interval'
    Check ($entryText.Contains("manifest_sha256='dccbf6f7ef553bda1e20d7b8fa1659fe7e4b691d5d492b8210c9b7c606a7ced4'") -and $entryText.Contains("manager_sha256='e65ea013b5c947c68604bc633e180563a811b856ed6c2aa7b09f3d5c291cd95a'") -and $entryText.Contains('member_count=85')) 'entry pins reviewed real public candidate'
    $invocations=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.InvocationOperator -in @([Management.Automation.Language.TokenKind]::Ampersand,[Management.Automation.Language.TokenKind]::Dot)},$true))
    Check ($invocations.Count -eq 0 -and $entryText.Contains('$start.FileName=$go')) 'entry only starts compiler and never invokes package scripts'
    $evidence=[ordered]@{schema_version='yimecore-local13-maintenance-preparation-test-v1';passed=$true;powershell_version=$PSVersionTable.PSVersion.ToString();checks_passed=$checks.Count;checks=@($checks.ToArray());
        synthetic_fixtures_only=$true;compiler_executed=$false;product_executed=$false;installer_executed=$false;user_state_read=$false;installed_package_read=$false;execution_authorized=$false;ready_to_execute=$false}
} finally {
    $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notmatch '^yimecore-local13-preparation-[a-f0-9]{32}$') {throw 'Unsafe fixture cleanup root.'}
    if (Test-Path -LiteralPath $resolved) {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if ($OutputPath) {Json $evidence $OutputPath}
Write-Host ('PASS: local.13 preparation fixtures '+$checks.Count+'; native execution remains unauthorized.')
