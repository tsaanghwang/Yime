[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$scope=Get-YimeCoreDevelopmentScope
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$root=[IO.Path]::GetFullPath($EvidenceRoot)
if(-not $root.StartsWith((Join-Path $repo '.tmp\yimecore-experiment\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid evidence root.'}
$before=Get-Content (Join-Path $root 'actual-rollback\before.json') -Raw|ConvertFrom-Json
$after=Get-Content (Join-Path $root 'post-acceptance-state.json') -Raw|ConvertFrom-Json
$rollback=Get-Content (Join-Path $root 'actual-rollback-final\summary.json') -Raw|ConvertFrom-Json
if(-not $rollback.system_registry_rollback_verified) {
    throw 'Historical rollback lacks independent system-visible registry evidence. Repeat the actual rehearsal from standalone Windows PowerShell; refusing to overwrite the historical closure summary or promote process-view checks to passed.'
}
$registered=Get-Content (Join-Path $root 'registered-x64-final\summary.json') -Raw|ConvertFrom-Json
$desktop=Get-Content (Join-Path $root 'desktop-checks.json') -Raw|ConvertFrom-Json
$continuity=Get-Content (Join-Path $root 'data-continuity.json') -Raw|ConvertFrom-Json
$archive=Join-Path $env:USERPROFILE 'YimeCore Recovery Archives\local-closure-20260902'
$restored=Get-Content (Join-Path $archive 'restore-evidence.json') -Raw|ConvertFrom-Json
$production=$true
foreach($view in @('Registry64','Registry32')) {
    foreach($key in @('production_com','production_tip')) {
        if(($before.registration.$view.$key|ConvertTo-Json -Depth 30 -Compress) -cne ($after.registration.$view.$key|ConvertTo-Json -Depth 30 -Compress)){$production=$false}
    }
}
$checks=[ordered]@{
    production_registration_unchanged=$production
    language_list_unchanged=(($before.user.language_profile|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.user.language_profile|ConvertTo-Json -Depth 30 -Compress))
    keyboard_preload_unchanged=(($before.user.keyboard_preload|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.user.keyboard_preload|ConvertTo-Json -Depth 30 -Compress))
    successful_upgrade_preserves_user_tip=(($before.user.trial_tip|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.user.trial_tip|ConvertTo-Json -Depth 30 -Compress))
    actual_failed_upgrade_rollback=($rollback.passed -and $null -ne $rollback.failed_installer_exit_code -and $rollback.failed_installer_exit_code -ne 0)
    live_quiesced_restore_passed=[bool]$restored.passed
    installed_x64_registered_hosts_passed=[bool]$registered.passed
    production_fallback_host_input=[bool]$desktop.notepad.production_fallback_input_passed
    returned_to_trial_host=[bool]$desktop.notepad.returned_to_trial_after_fallback
    final_word_physical_language_bar=[bool]$desktop.final_package_physical_taskbar_left_right_passed
    final_word_input_acceptance=[bool]$desktop.word_final_package_passed
    learning_and_user_lexicon_continuity=[bool]$continuity.passed
}
$references=@()
foreach($path in @((Join-Path $root 'actual-rollback-final\summary.json'),(Join-Path $root 'registered-x64-final\summary.json'),
    (Join-Path $root 'final-installed-state.json'),(Join-Path $archive 'backup-manifest.json'),(Join-Path $archive 'restore-evidence.json'),
    (Join-Path $root 'desktop-checks.json'),(Join-Path $root 'word-final-live.json'),(Join-Path $root 'notepad-final-build.txt'),
    (Join-Path $root 'post-acceptance-state.json'),(Join-Path $root 'data-continuity.json'),(Join-Path $root 'word-final-build.docx'),
    (Join-Path $repo '.tmp\yimecore-experiment\e6d-independence\local-closure-final-20260902\summary.json'))) {
    $references+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
}
[ordered]@{schema_version='yimecore-local-closure-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;
    package_root=$after.runtime_config.install_root;manifest_sha256=$after.manifest_sha256;checks=$checks;
    maintenance_subset_passed=(-not ($checks.Values -contains $false));pre_reboot_local_acceptance_passed=(-not ($checks.Values -contains $false));all_local_acceptance_completed=$false;
    pending=@('next normal reboot autostart and package identity recheck');
    cautions=@('Initial Word Shift+3 attempt emitted t#; retry passed; cause unproven.','GUI settings backup/restore has not been certified as a quiesced durable-model snapshot; use maintenance workflow.','Initial rollback exposed missing per-user TIP Enable; fixed and verified in actual-rollback-final.','actual-rollback-fixed has null exit status; final evidence supersedes it.');
    current_default_input_method=Get-WinDefaultInputMethodOverride;references=$references
}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'closure-summary.json') -Encoding utf8
if($checks.Values -contains $false){throw 'Maintenance evidence contains a failure.'}
Write-Host 'Pre-reboot local host, backup/restore, and actual rollback acceptance passed; reboot recheck remains explicit.'
