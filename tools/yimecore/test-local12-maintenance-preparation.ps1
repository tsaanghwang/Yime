[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'local12-maintenance-preparation.psm1'
Import-Module $module -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('yimecore-local12-preparation-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
$junction=''
$junctionStatus='not_attempted'
function Assert-Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $checks.Add($Name)
}
function Assert-Reject([scriptblock]$Code,[string]$Name) {
    $rejected=$false
    try { $null=& $Code } catch { $rejected=$true }
    Assert-Check $rejected $Name
}
function Write-Json($Value,[string]$Path) { $Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Path -Encoding UTF8 }
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function New-Fixture([string]$Name) {
    $package=Join-Path $root $Name
    New-Item -ItemType Directory -Path $package | Out-Null
    $paths=@('local-product.json','maintenance/Manage-YimeCoreTrial.ps1','maintenance/manage-local-product.ps1',
        'maintenance/backup-local-trial-state.ps1','maintenance/restore-local-trial-state.ps1',
        'x64/YimeTextServiceExperiment.dll','x86/YimeTextServiceExperiment.dll',
        'x64/YimeTextServiceRegistration.exe','x86/YimeTextServiceRegistration.exe',
        'bin/YimeCoreTrialRuntime.exe','bin/YimeBroker.exe','bin/YimeCoreRecoveryProbe.exe')
    foreach($path in $paths) {
        $absolute=Join-Path $package $path
        New-Item -ItemType Directory -Path (Split-Path -Parent $absolute) -Force | Out-Null
        Set-Content -LiteralPath $absolute -Value ('FIXTURE '+$path) -Encoding UTF8
    }
    # If a preparation helper executes a package script, it will produce this sentinel.
    Set-Content -LiteralPath (Join-Path $package 'maintenance/Manage-YimeCoreTrial.ps1') -Value "throw 'A package script was executed during preparation.'" -Encoding UTF8
    $descriptor=[ordered]@{schema_version='yimecore-local-product-v1';version='0.1.0-local.12';
        scope=@{computer_name='MYCOMPUTER';active_architectures=@('x64','x86')};
        identity=@{product_key='YimeCoreExperimentalTrial';clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}';profile='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'}}
    Write-Json $descriptor (Join-Path $package 'local-product.json')
    $records=@(foreach($path in $paths) { $absolute=Join-Path $package $path;[ordered]@{path=$path;bytes=(Get-Item -LiteralPath $absolute).Length;sha256=(Hash $absolute)} })
    $manifest=[ordered]@{tool_version='yimecore-local-builder-v1';package_contract='yimecore-local-product-package-v1';product_version='0.1.0-local.12';scope='synthetic fixture';files=$records}
    Write-Json $manifest (Join-Path $package 'package-manifest.json')
    $contract=@{manifest_sha256=(Hash (Join-Path $package 'package-manifest.json'));
        manager_sha256=(Hash (Join-Path $package 'maintenance/Manage-YimeCoreTrial.ps1'));
        wrapper_sha256=(Hash (Join-Path $package 'maintenance/manage-local-product.ps1'));member_count=$paths.Count}
    return @{root=$package;contract=$contract;manifest=$manifest;descriptor=$descriptor}
}
function Save-Manifest($Fixture) {
    Write-Json $Fixture.manifest (Join-Path $Fixture.root 'package-manifest.json')
    $Fixture.contract.manifest_sha256=Hash (Join-Path $Fixture.root 'package-manifest.json')
}
function Save-Descriptor($Fixture) {
    $path=Join-Path $Fixture.root 'local-product.json'
    Write-Json $Fixture.descriptor $path
    $record=@($Fixture.manifest.files|Where-Object {$_.path -ceq 'local-product.json'})[0]
    $record.bytes=(Get-Item -LiteralPath $path).Length;$record.sha256=Hash $path
    Save-Manifest $Fixture
}
try {
    $fixture=New-Fixture 'source'
    $probeSource=Join-Path $PSScriptRoot 'rollback-failure-runtime.go'
    $sourceHash=Hash $probeSource
    $before=@(Get-ChildItem -LiteralPath $root -Recurse -File).Count
    $plan=Get-YimeCoreFaultPreparationPlan $fixture.root $fixture.contract $probeSource $sourceHash
    Assert-Check ($plan.verified_member_count -eq 12 -and $plan.source_catalog_verified) 'valid catalog and dual-architecture identity'
    Assert-Check (@(Get-ChildItem -LiteralPath $root -Recurse -File).Count -eq $before) 'Plan is read-only'
    Assert-Check (-not $plan.execution_authorized -and -not $plan.ready_to_execute -and -not $plan.installer_executed -and -not $plan.product_executed -and -not $plan.probe_exit_observed -and -not $plan.unexpected_success_rollback_guard_available) 'Plan never implies native execution authorization'
    Assert-Check (-not $plan.user_state_read -and -not $plan.installed_package_read -and -not $plan.product_mutated) 'Plan privacy and product preservation'
    $wrong=$fixture.contract.Clone();$wrong.manifest_sha256='0'*64
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'reject mismatched pinned manifest'
    $wrong=$fixture.contract.Clone();$wrong.manager_sha256='0'*64
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $fixture.root $wrong} 'reject changed manager pin'
    Assert-Reject {Get-YimeCoreFaultPreparationPlan $fixture.root $fixture.contract $probeSource ('0'*64)} 'reject changed exit probe source'

    $bad=New-Fixture 'wrong-profile';$bad.descriptor.identity.profile='{607895A8-9504-4A2E-9BB1-2C159E3A1757}';Save-Descriptor $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject legacy product profile'
    $bad=New-Fixture 'wrong-architecture';$bad.descriptor.scope.active_architectures=@('x64');Save-Descriptor $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject single-architecture descriptor'
    $bad=New-Fixture 'wrong-version';$bad.manifest.product_version='0.1.0-local.13';Save-Manifest $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject current source version as local.12'
    $bad=New-Fixture 'traversal';$bad.manifest.files[0].path='../outside';Save-Manifest $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject member traversal'
    $bad=New-Fixture 'duplicate';$bad.manifest.files[0].path='BIN/yimebroker.EXE';Save-Manifest $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject case-insensitive duplicate member'
    $bad=New-Fixture 'size-string';$bad.manifest.files[0].bytes='10';Save-Manifest $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject coerced size string'
    $bad=New-Fixture 'installed';Set-Content -LiteralPath (Join-Path $bad.root 'install-metadata.json') -Value '{}'
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject installed package metadata'
    $bad=New-Fixture 'unlisted';Set-Content -LiteralPath (Join-Path $bad.root 'unlisted.txt') -Value 'extra'
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject unlisted file'
    $bad=New-Fixture 'unlisted-directory';New-Item -ItemType Directory -Path (Join-Path $bad.root 'unlisted')|Out-Null
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject unlisted empty directory'
    $bad=New-Fixture 'missing-x86';$bad.manifest.files=@($bad.manifest.files|Where-Object {$_.path -cne 'x86/YimeTextServiceRegistration.exe'});$bad.contract.member_count--;Save-Manifest $bad
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject missing x86 registration tool'
    $bad=New-Fixture 'tampered';Add-Content -LiteralPath (Join-Path $bad.root 'bin/YimeBroker.exe') -Value 'tamper'
    Assert-Reject {Get-YimeCoreFaultPreparationCatalog $bad.root $bad.contract} 'reject member hash drift'

    # Synthetic PE header only: no executable is compiled or launched by fixtures.
    $bytes=New-Object byte[] 256
    $bytes[0]=0x4d;$bytes[1]=0x5a;$bytes[0x3c]=0x80;$bytes[0x80]=0x50;$bytes[0x81]=0x45
    $bytes[0x84]=0x64;$bytes[0x85]=0x86;$bytes[0x98]=0x0b;$bytes[0x99]=0x02
    $probe=Join-Path $root 'synthetic-probe.exe';[IO.File]::WriteAllBytes($probe,$bytes)
    $probeHash=Hash $probe
    $wrongProbe=Join-Path $root 'synthetic-x86.exe';$bytes[0x84]=0x4c;$bytes[0x85]=0x01;[IO.File]::WriteAllBytes($wrongProbe,$bytes)
    Assert-Reject {Assert-YimeCoreFailureProbePe $wrongProbe} 'reject non-amd64 failure probe'
    $out=Join-Path $root 'prepared'
    $prepared=New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe $probeHash $out $root
    Assert-Check ($prepared.failure_package_prepared -and $prepared.static_package_verification_passed -and $prepared.file_count -eq 12) 'assemble synthetic preparation output'
    Assert-Check ($prepared.failure_manifest_sha256 -cne $fixture.contract.manifest_sha256 -and $prepared.failure_runtime_sha256 -ceq $probeHash) 'derive independent failure manifest'
    Assert-Check ((Hash (Join-Path $out 'maintenance/Manage-YimeCoreTrial.ps1')) -ceq $fixture.contract.manager_sha256) 'preserve pinned manager without workspace substitution'
    Assert-Check ((Hash (Join-Path $fixture.root 'package-manifest.json')) -ceq $fixture.contract.manifest_sha256) 'preserve source manifest'
    $unchanged=@($fixture.manifest.files|Where-Object {$_.path -cne 'bin/YimeCoreTrialRuntime.exe'}|Where-Object {(Hash (Join-Path $out $_.path)) -cne $_.sha256})
    Assert-Check ($unchanged.Count -eq 0) 'only replace runtime payload'
    Assert-Check (-not $prepared.ready_to_execute -and -not $prepared.execution_authorized -and -not $prepared.probe_exit_observed -and -not $prepared.installer_executed -and -not $prepared.product_executed -and -not $prepared.unexpected_success_rollback_guard_available) 'prepared fixture is not an execution pass'
    Assert-Reject {New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe $probeHash $out $root} 'reject existing output instead of overwriting'
    Assert-Reject {New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe $probeHash (Join-Path $root '../outside') $root} 'reject output outside approved parent'
    Assert-Reject {New-YimeCoreFaultPreparationOutput $fixture.root $fixture.contract $probe ('0'*64) (Join-Path $root 'wrong-probe') $root} 'reject replacement hash mismatch'
    Assert-Check (-not (Test-Path -LiteralPath (Join-Path $root 'wrong-probe'))) 'reject before output mutation'

    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($module,[ref]$tokens,[ref]$errors)
    Assert-Check ($errors.Count -eq 0) 'module syntax'
    $packageInvocation=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.InvocationOperator -in @([Management.Automation.Language.TokenKind]::Ampersand,[Management.Automation.Language.TokenKind]::Dot)},$true))
    Assert-Check ($packageInvocation.Count -eq 0) 'module contains no script invocation operator'
    $entry=Join-Path $PSScriptRoot 'prepare-local12-maintenance.ps1'
    $null=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
    Assert-Check ($errors.Count -eq 0) 'entry syntax'
    $entryText=Get-Content -LiteralPath $entry -Raw -Encoding UTF8
    Assert-Check ($entryText.Contains("`$Action='Plan'") -and $entryText.Contains("GOPROXY='off'") -and $entryText.Contains("GOTOOLCHAIN='local'")) 'entry defaults to Plan and offline local compiler'
    Assert-Check ($entryText.Contains("`$probeHash='$sourceHash'")) 'entry pins the exact reviewed exit probe source'

    $junction=Join-Path $root 'source-junction'
    try { New-Item -ItemType Junction -Path $junction -Target $fixture.root -ErrorAction Stop|Out-Null;$junctionStatus='created' } catch { $junctionStatus='unavailable' }
    if ($junctionStatus -eq 'created') {
        Assert-Reject {Get-YimeCoreFaultPreparationCatalog $junction $fixture.contract} 'reject package root junction'
        $junctionStatus='rejected'
    }
    $result=[ordered]@{schema_version='yimecore-local12-maintenance-preparation-test-v1';passed=$true;
        powershell_version=$PSVersionTable.PSVersion.ToString();checks_passed=$checks.Count;checks=@($checks.ToArray());junction_fixture=$junctionStatus;
        synthetic_fixtures_only=$true;real_candidate_prepared=$false;compiler_executed=$false;installer_executed=$false;product_executed=$false;
        installed_package_read=$false;user_state_read=$false;execution_authorized=$false;ready_to_execute=$false}
} finally {
    if ($junction -and (Test-Path -LiteralPath $junction)) {
        if ([IO.Path]::GetFullPath($junction).StartsWith([IO.Path]::GetFullPath($root)+'\',[StringComparison]::OrdinalIgnoreCase)) {
            # PS5 Remove-Item can throw NullReferenceException for a junction.
            # Nonrecursive Directory.Delete removes this verified fixture link only.
            [IO.Directory]::Delete($junction,$false)
        }
    }
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'yimecore-local12-preparation-*') { throw 'Unsafe fixture cleanup root.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
if ($OutputPath) { Write-Json $result $OutputPath }
Write-Host ('PASS: local.12 preparation fixtures '+$checks.Count+'; native execution remains unauthorized.')
