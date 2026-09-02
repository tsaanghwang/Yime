[CmdletBinding()]
param([Parameter(Mandatory)][string]$FailurePackage,[Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][string]$TargetUserSid)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
. (Join-Path $PSScriptRoot 'local-maintenance-safety.ps1')
$scope=Get-YimeCoreDevelopmentScope
Assert-YimeCoreUnpackagedDataMaintenance
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -ne $TargetUserSid -or -not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use an elevated token of the initiating user only.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=[IO.Path]::GetFullPath($OutputRoot)
$allowed=(Join-Path $repo '.tmp\yimecore-experiment\')
if(-not $out.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid evidence boundary.'}
if(Test-Path -LiteralPath $out){throw 'Use a fresh rollback evidence directory.'}
Assert-YimeCorePlainPath $out
$failureRoot=[IO.Path]::GetFullPath($FailurePackage)
if(-not $failureRoot.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Failure package must be isolated in experiment output.'}
Assert-YimeCorePlainPath $failureRoot
$fault=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $failureRoot 'package-manifest.json') -Raw|ConvertFrom-Json
if(-not $fault.rehearsal_only){throw 'Missing rehearsal-only marker.'}
$backup=[IO.Path]::GetFullPath($BackupRoot)
if(-not $backup.StartsWith((Join-Path $env:USERPROFILE 'YimeCore Recovery Archives\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid backup boundary; use the system-visible archive outside AppData.'}
Assert-YimeCorePlainPath $backup
$backupManifest=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $backup 'backup-manifest.json') -Raw|ConvertFrom-Json
if(-not $backupManifest.passed -or -not $backupManifest.native_context_verified -or -not (Test-YimeCoreScopeEvidence $backupManifest.development_scope $scope)){throw 'Missing matching native-context backup.'}
foreach($record in $backupManifest.package_files){if((Get-FileHash -LiteralPath (Join-Path (Join-Path $backup 'previous-package') $record.path)).Hash -ne $record.sha256){throw 'Recovery package hash mismatch.'}}
if(Get-Process WINWORD -ErrorAction SilentlyContinue){throw 'Close Word before rollback rehearsal.'}
New-Item -ItemType Directory -Path $out -Force|Out-Null
Start-Transcript -LiteralPath (Join-Path $out 'transcript.txt')|Out-Null
try {
    $beforePath=Join-Path $out 'before.json'
    & (Join-Path $PSScriptRoot 'capture-local-maintenance-state.ps1') -OutputPath $beforePath
    $before=Get-Content -Encoding UTF8 -LiteralPath $beforePath -Raw|ConvertFrom-Json
    $expectedHash=(Get-FileHash -LiteralPath (Join-Path $backup 'previous-package\package-manifest.json')).Hash
    if($before.manifest_sha256 -ne $expectedHash -or -not $before.live_runtime.passed){throw 'Active old package does not match the recoverable backup or lacks live identities.'}
    Assert-YimeCoreUnchangedData $backupManifest.data_files $before.data_files
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Install -PackageRoot "{1}" -Force -NoElevation -NativeX64Rehearsal -TargetUserSid "{2}" -StateRoot "{3}"' -f
        (Join-Path $PSScriptRoot 'manage-e6c-trial-install.ps1'),$failureRoot,$TargetUserSid,$before.runtime_config.state_root
    # -Wait also waits for descendant processes, including the restored resident runtime.
    # Wait for the installer itself; runtime readiness is checked independently below.
    $installer=[Diagnostics.Process]::new()
    $installer.StartInfo.FileName=$ps
    $installer.StartInfo.Arguments=$arguments
    $installer.StartInfo.UseShellExecute=$false
    $installer.StartInfo.CreateNoWindow=$true
    $installer.StartInfo.RedirectStandardOutput=$true
    $installer.StartInfo.RedirectStandardError=$true
    try {
        if(-not $installer.Start()){throw 'Installer did not start.'}
        $stdout=$installer.StandardOutput.ReadToEndAsync()
        $stderr=$installer.StandardError.ReadToEndAsync()
        $installer.WaitForExit()
        $installExit=$installer.ExitCode
        $stdout.GetAwaiter().GetResult()|Set-Content -LiteralPath (Join-Path $out 'failed-install-stdout.txt') -Encoding utf8
        $stderr.GetAwaiter().GetResult()|Set-Content -LiteralPath (Join-Path $out 'failed-install-stderr.txt') -Encoding utf8
    } finally {$installer.Dispose()}
    $afterPath=Join-Path $out 'after.json'
    & (Join-Path $PSScriptRoot 'capture-local-maintenance-state.ps1') -OutputPath $afterPath
    $after=Get-Content -Encoding UTF8 -LiteralPath $afterPath -Raw|ConvertFrom-Json
    $checks=[ordered]@{
        failure_was_triggered=($null -ne $installExit -and $installExit -ne 0 -and (Get-Content -Encoding UTF8 (Join-Path $out 'failed-install-stderr.txt') -Raw) -match 'trial runtime did not become ready')
        registration_restored=(($before.registration|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.registration|ConvertTo-Json -Depth 30 -Compress))
        user_registration_and_value_kinds_restored=(($before.user|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.user|ConvertTo-Json -Depth 30 -Compress))
        system_visible_registry_restored=($before.system_registry_reader -eq 'StdRegProv/HKEY_USERS+HKLM' -and
            $after.system_registry_reader -eq 'StdRegProv/HKEY_USERS+HKLM' -and
            $null -ne $before.system_registry_trees -and
            ($before.system_registry_trees|ConvertTo-Json -Depth 35 -Compress) -ceq ($after.system_registry_trees|ConvertTo-Json -Depth 35 -Compress))
        runtime_config_restored=($before.runtime_config_sha256 -eq $after.runtime_config_sha256)
        package_identity_restored=($before.manifest_sha256 -eq $after.manifest_sha256)
        runtime_running_restored=($before.live_runtime.passed -and $after.live_runtime.passed)
        learning_lexicon_settings_preserved=((ConvertTo-Json -InputObject @($before.data_files) -Depth 8 -Compress) -ceq (ConvertTo-Json -InputObject @($after.data_files) -Depth 8 -Compress))
        old_root_preserved=(Test-Path -LiteralPath $before.runtime_config.install_root)
        recovery_archive_preserved=(Test-Path -LiteralPath (Join-Path $backup 'previous-package\package-manifest.json'))
    }
    $passed=-not ($checks.Values -contains $false)
    [ordered]@{schema_version='yimecore-real-install-rollback-v1';generated_at=(Get-Date).ToUniversalTime().ToString('o');development_scope=$scope;
        failed_installer_exit_code=$installExit;failure_package=$failureRoot;backup_root=$backup;checks=$checks;passed=$passed;
        system_registry_rollback_verified=($passed -and $checks.system_visible_registry_restored);
        native_context_verified=$true;remaining_production_fallback_host_rehearsal='covered by retained physical Notepad production acceptance; not rerun here'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding utf8
    if(-not $passed){throw 'Actual rollback checks failed; preserve evidence and do not continue installing.'}
    Write-Host 'Actual installer failure and rollback checks passed.'
}finally{Stop-Transcript|Out-Null}
