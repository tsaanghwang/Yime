[CmdletBinding()]
param()
$ErrorActionPreference='Stop'

# Pure model tests: this script reads the definitions file but creates no test
# directory and performs no filesystem, registry, process, native or product
# operation.
. (Join-Path $PSScriptRoot 'rime-pime-transaction-engine.ps1')

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true;reason=$null})}
    catch{$checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message})}
}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Must-Reject([scriptblock]$Body,[string]$Pattern='*'){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notlike $Pattern){throw};return}
    throw 'Expected fail-closed rejection.'
}
function Assert-Sequence($Actual,[string[]]$Expected,[string]$Name){
    $values=@($Actual)
    Assert-True ($values.Count -eq $Expected.Count) "$Name count differs."
    for($index=0;$index -lt $Expected.Count;$index++){
        Assert-True ([string]$values[$index] -ceq [string]$Expected[$index]) "$Name differs at index $index."
    }
}
function Hash([string]$Text){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Identity([string]$Type,[string]$Label){
    return [pscustomobject][ordered]@{type=$Type;digest=Hash $Label}
}
function New-Manifest {
    return [pscustomobject][ordered]@{
        schema_version='yime-pime-logical-removal-manifest-v1'
        root_id='rime-pime-install-root'
        manifest_path='package-manifest.json'
        uninstaller_path='Uninstall.exe'
        files=[object[]]@(
            'PIMETextService.dll','go-backend\server.exe','go-backend\data\dict.bin',
            'a\one.bin','package-manifest.json','Uninstall.exe'
        )
        directories=[object[]]@('go-backend','go-backend\data','a')
    }
}

$expectedUpgrade=@(
    'validate-selected-root','validate-complete-manifest','validate-package-architectures',
    'stage-complete-package','verify-staged-hashes','snapshot-target','snapshot-protected',
    'write-prepared-journal','directed-stop','verify-quiescence','quarantine-old-root',
    'activate-staged-root','unregister-old','register-new','verify-registration',
    'apply-target-user-profile','write-product-registration','verify-product-registration',
    'start-runtime-non-elevated','verify-runtime','verify-protected-state',
    'write-activation-commit','purge-quarantine','finalize-journal'
)
$expectedUninstall=@(
    'validate-selected-root','validate-complete-manifest','validate-removal-plan',
    'snapshot-target','snapshot-protected','write-prepared-journal','directed-stop',
    'verify-quiescence','unregister-current','verify-registration-absent',
    'remove-target-user-profile','remove-product-registration','verify-product-registration-absent',
    'remove-manifest-files','remove-manifest-directories','remove-install-root',
    'verify-target-absent','verify-protected-state','write-activation-commit',
    'purge-recovery-archive','finalize-journal'
)

Check 'new-pure-model-functions-are-present' {
    foreach($name in @('Get-YimePimeTransactionStageCatalog','Get-YimePimeReplayDisposition',
            'Resolve-YimePimeIdempotentTransition','Get-YimePimeManifestRemovalPlan')){
        Assert-True ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) "Missing function: $name"
    }
}
Check 'generic-upgrade-catalog-preserves-the-existing-24-stage-contract' {
    $legacy=@(Get-YimePimeUpgradeStageCatalog);$generic=@(Get-YimePimeTransactionStageCatalog -Action Upgrade)
    Assert-Sequence @($legacy.id) $expectedUpgrade 'Legacy upgrade catalog'
    Assert-Sequence @($generic.id) $expectedUpgrade 'Generic upgrade catalog'
    Assert-True ($legacy.Count -eq 24 -and $generic.Count -eq 24) 'Upgrade stage count changed.'
    Assert-True (($legacy|ConvertTo-Json -Depth 5 -Compress) -ceq ($generic|ConvertTo-Json -Depth 5 -Compress)) `
        'Generic Upgrade did not delegate the exact legacy catalog.'
}
Check 'uninstall-catalog-has-journal-mutation-commit-and-cleanup-boundaries' {
    $stages=@(Get-YimePimeTransactionStageCatalog -Action Uninstall);$ids=@($stages.id)
    Assert-Sequence $ids $expectedUninstall 'Uninstall catalog'
    Assert-True (@($ids|Select-Object -Unique).Count -eq 21) 'Uninstall catalog contains duplicate stages.'
    for($index=0;$index -lt $stages.Count;$index++){
        Assert-True ([int]$stages[$index].position -eq $index+1) 'Uninstall stage positions are not contiguous.'
    }
    Assert-True (@($stages|Where-Object active_product_mutation)[0].id -ceq 'directed-stop') 'Uninstall mutation begins before directed stop.'
    Assert-True ([array]::IndexOf($ids,'write-prepared-journal') -lt [array]::IndexOf($ids,'directed-stop')) 'Prepared journal is too late.'
    Assert-True ([array]::IndexOf($ids,'write-activation-commit') -lt [array]::IndexOf($ids,'purge-recovery-archive')) 'Recovery is purged before commit.'
}
Check 'unknown-transaction-action-is-rejected' {
    Must-Reject {Get-YimePimeTransactionStageCatalog -Action Repair} '*ValidateSet*'
}
Check 'replay-none-is-no-action' {
    foreach($state in @($null,'none')){
        $result=Get-YimePimeReplayDisposition -JournalState $state
        Assert-True ([string]$result.disposition -ceq 'none' -and -not $result.rollback_required -and
            -not $result.cleanup_required -and -not $result.terminal_noop) 'Absent journal was not classified as none.'
    }
}
Check 'replay-prepared-requires-rollback' {
    $result=Get-YimePimeReplayDisposition -JournalState prepared
    Assert-True ([string]$result.disposition -ceq 'rollback' -and $result.rollback_required -and
        -not $result.cleanup_required -and -not $result.terminal_noop) 'Prepared journal was not classified for rollback.'
}
Check 'replay-committed-requires-cleanup' {
    $result=Get-YimePimeReplayDisposition -JournalState committed
    Assert-True ([string]$result.disposition -ceq 'cleanup' -and -not $result.rollback_required -and
        $result.cleanup_required -and -not $result.terminal_noop) 'Committed journal was not classified for cleanup.'
}
Check 'replay-terminal-states-are-idempotent-noops' {
    foreach($state in @('terminal','rolled-back','cleanup-complete','finalized')){
        $result=Get-YimePimeReplayDisposition -JournalState $state
        Assert-True ([string]$result.disposition -ceq 'noop' -and $result.terminal_noop -and
            -not $result.rollback_required -and -not $result.cleanup_required) "Terminal replay state was not a no-op: $state"
    }
}
Check 'replay-invalid-state-or-type-fails-closed' {
    foreach($state in @('', 'Prepared','unknown',42,$true)){
        Must-Reject {Get-YimePimeReplayDisposition -JournalState $state} '*journal state*'
    }
}
Check 'idempotent-transition-applies-only-from-the-exact-before-identity' {
    $before=Identity file before;$after=Identity file after;$current=Identity file before
    $result=Resolve-YimePimeIdempotentTransition -Current $current -Before $before -After $after
    Assert-True ([string]$result.disposition -ceq 'apply' -and $result.apply_required -and
        -not $result.already_converged -and -not $result.recovery_required) 'Exact before identity did not request apply.'
}
Check 'idempotent-transition-recognizes-an-exact-converged-identity' {
    $before=Identity registry-value before;$after=Identity registry-value after;$current=Identity registry-value after
    $result=Resolve-YimePimeIdempotentTransition -Current $current -Before $before -After $after
    Assert-True ([string]$result.disposition -ceq 'already-converged' -and -not $result.apply_required -and
        $result.already_converged -and -not $result.recovery_required) 'Exact after identity was not converged.'
}
Check 'idempotent-transition-refuses-unrecognized-current-identity' {
    $result=Resolve-YimePimeIdempotentTransition -Current (Identity file foreign) `
        -Before (Identity file before) -After (Identity file after)
    Assert-True ([string]$result.disposition -ceq 'recovery-required' -and -not $result.apply_required -and
        -not $result.already_converged -and $result.recovery_required) 'Foreign current identity was not sent to recovery.'
}
Check 'idempotent-transition-enforces-closed-types-and-lowercase-digests' {
    $validBefore=Identity file before;$validAfter=Identity file after
    $badCases=[Collections.Generic.List[object]]::new()
    $badCases.Add(@{current=[pscustomobject]@{type='file';digest=('A'*64)};before=$validBefore;after=$validAfter})
    $badCases.Add(@{current=[pscustomobject]@{type='file';digest=42};before=$validBefore;after=$validAfter})
    $badCases.Add(@{current=[pscustomobject]@{type='file';digest=Hash foreign;extra=$true};before=$validBefore;after=$validAfter})
    $badCases.Add(@{current=[pscustomobject]@{type='File';digest=Hash foreign};before=$validBefore;after=$validAfter})
    $badCases.Add(@{current=Hash foreign;before=$validBefore;after=$validAfter})
    $badCases.Add(@{current=Identity file before;before=Identity file before;after=Identity directory after})
    $badCases.Add(@{current=Identity file same;before=Identity file same;after=Identity file same})
    foreach($case in $badCases){
        Must-Reject {Resolve-YimePimeIdempotentTransition -Current $case.current -Before $case.before -After $case.after}
    }
}
Check 'manifest-removal-plan-is-leaf-first-and-reserves-two-final-files' {
    $manifest=New-Manifest;$before=$manifest|ConvertTo-Json -Depth 10 -Compress
    $plan=Get-YimePimeManifestRemovalPlan -Manifest $manifest
    Assert-Sequence $plan.file_order @(
        'go-backend\data\dict.bin','a\one.bin','go-backend\server.exe','PIMETextService.dll',
        'package-manifest.json','Uninstall.exe') 'Removal file order'
    Assert-Sequence $plan.directory_order @('go-backend\data','a','go-backend') 'Removal directory order'
    $ops=@($plan.operations)
    Assert-Sequence @($ops.operation) @(
        'remove-file','remove-file','remove-file','remove-file','remove-file','remove-file',
        'remove-directory','remove-directory','remove-directory','remove-root') 'Removal operations'
    Assert-True ([string]$ops[4].role -ceq 'manifest' -and [string]$ops[5].role -ceq 'uninstaller') 'Reserved files are not last among files.'
    Assert-True ([string]$ops[-1].operation -ceq 'remove-root' -and $null -eq $ops[-1].relative_path) 'Install root is not last.'
    Assert-True (-not @($ops|Where-Object recursive).Count -and $plan.directories_non_recursive -and
        $plan.root_last -and -not $plan.physical_deletion_executed) 'Removal plan promoted recursive or physical deletion.'
    Assert-True (($manifest|ConvertTo-Json -Depth 10 -Compress) -ceq $before) 'Removal manifest input was mutated.'
}
Check 'manifest-order-uses-depth-then-ordinal-not-culture-or-input-order' {
    $manifest=New-Manifest
    $manifest.files=[object[]]@('z\b.bin','a\z.bin','z\a.bin','package-manifest.json','Uninstall.exe')
    $manifest.directories=[object[]]@('z','a')
    $plan=Get-YimePimeManifestRemovalPlan $manifest
    Assert-Sequence $plan.file_order @('a\z.bin','z\a.bin','z\b.bin','package-manifest.json','Uninstall.exe') 'Ordinal file order'
    Assert-Sequence $plan.directory_order @('a','z') 'Ordinal directory order'
}
Check 'manifest-schema-collections-and-logical-paths-fail-closed' {
    $cases=[Collections.Generic.List[object]]::new()
    $bad=New-Manifest;$bad.schema_version='future';$cases.Add($bad)
    $bad=New-Manifest;$bad.root_id='foreign-root';$cases.Add($bad)
    $bad=New-Manifest;$bad|Add-Member extra $true;$cases.Add($bad)
    $bad=New-Manifest;$bad.files='Uninstall.exe';$cases.Add($bad)
    $bad=New-Manifest;$bad.directories='go-backend';$cases.Add($bad)
    $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe','uninstall.EXE');$bad.directories=[object[]]@();$cases.Add($bad)
    $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe','go-backend');$bad.directories=[object[]]@('go-backend');$cases.Add($bad)
    $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe','missing\child.bin');$bad.directories=[object[]]@();$cases.Add($bad)
    $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe');$bad.directories=[object[]]@('missing\child');$cases.Add($bad)
    $bad=New-Manifest;$bad.files=[object[]]@('Uninstall.exe');$bad.directories=[object[]]@();$cases.Add($bad)
    $bad=New-Manifest;$bad.uninstaller_path='bin\Uninstall.exe';$bad.files=[object[]]@('package-manifest.json','bin\Uninstall.exe');$bad.directories=[object[]]@('bin');$cases.Add($bad)
    foreach($path in @('../evil','..\evil','a/evil','file:ads','AUX.txt','trail.','lead\\child')){
        $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe',$path);$bad.directories=[object[]]@();$cases.Add($bad)
    }
    $bad=New-Manifest;$bad.files=[object[]]@('package-manifest.json','Uninstall.exe',42);$bad.directories=[object[]]@();$cases.Add($bad)
    foreach($case in $cases){Must-Reject {Get-YimePimeManifestRemovalPlan -Manifest $case}}
}

$failed=@($checks|Where-Object{-not $_.passed})
$result=[pscustomobject][ordered]@{
    schema_version='yime-pime-transaction-replay-model-test-v1'
    passed=($failed.Count -eq 0);checks_count=$checks.Count;failed_count=$failed.Count;checks=$checks.ToArray()
    legacy_upgrade_stage_count=@(Get-YimePimeUpgradeStageCatalog).Count
    generic_upgrade_stage_count=@(Get-YimePimeTransactionStageCatalog -Action Upgrade).Count
    uninstall_stage_count=@(Get-YimePimeTransactionStageCatalog -Action Uninstall).Count
    pure_objects_and_strings_only=$true;physical_deletion_executed=$false
    actual_filesystem_registry_process_native_installer_or_product_operation_executed=$false
}
$result|ConvertTo-Json -Depth 10
if($failed.Count){exit 1}
