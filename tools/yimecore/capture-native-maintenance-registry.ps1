[CmdletBinding()]
param([ValidateSet('Plan','Capture')][string]$Action='Plan',[string]$OutputRoot,
    [string]$TargetUserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'native-maintenance-context.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'native-maintenance-evidence.psm1') -Force
if ($Action -eq 'Plan') {
    if ($OutputRoot) { throw 'Plan writes no output; OutputRoot belongs to Capture only.' }
    $catalog=Get-YimeCoreNativeMaintenanceRegistryCatalog -TargetUserSid $TargetUserSid
    [ordered]@{schema_version='yimecore-native-maintenance-registry-plan-v1';action='Plan';target_user_sid=$TargetUserSid;
        catalog=$catalog;capture_requires='Standalone non-elevated same-SID PowerShell under native MYCOMPUTER Explorer';
        registry_read=$false;product_or_user_state_read=$false;execution_authorized=$false;maintenance_executed=$false;
        local_product_ready=$false;L6_sealed=$false} | ConvertTo-Json -Depth 12
    exit 0
}
$context=$null;$stream=$null;$out=$null
try {
    # No product registry read, directory creation or caller-path access precedes
    # actual native-context verification; the default Plan remains purely static.
    $context=Open-YimeCoreNativeMaintenanceContext -TargetUserSid $TargetUserSid
    if (-not $OutputRoot) {
        $parent=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'YimeCore Recovery Archives'
        $OutputRoot=Join-Path $parent ('native-maintenance-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
    }
    $out=New-YimeCoreNativeObservationDirectory -OutputRoot $OutputRoot
    $snapshot=Get-YimeCoreNativeMaintenanceSnapshot -TargetUserSid $TargetUserSid
    $sources=[ordered]@{}
    foreach ($relative in @('capture-native-maintenance-registry.ps1','native-maintenance-context.psm1','native-maintenance-evidence.psm1','../dual-product/rime-pime-dp1u-native-facts.cs')) {
        $sources[$relative]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $result=[ordered]@{schema_version='yimecore-native-maintenance-registry-capture-v1';captured_at=[DateTime]::UtcNow.ToString('o');
        context=$context.evidence;registry=$snapshot;source_sha256=$sources;capture_complete=$true;
        user_text_or_settings_or_learning_read=$false;product_mutated=$false;maintenance_executed=$false;
        execution_authorized=$false;L6_sealed=$false;local_product_ready=$false;public_release_ready=$false;
        continuous_registry_protection=$false;independent_recovery_media=$false}
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($result|ConvertTo-Json -Depth 100)+"`n")
    $path=Join-Path $out 'registry-observation.json'
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    [Yime.Dp1UNative.Facts]::VerifyFileHandle($stream,$path) | Out-Null
    $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true);$stream.Position=0
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
    [ordered]@{capture_complete=$true;path=$path;bytes=$bytes.Length;sha256=$digest;maintenance_executed=$false;L6_sealed=$false} | ConvertTo-Json
} finally {
    if ($stream) {$stream.Dispose()}
    Close-YimeCoreNativeMaintenanceContext $context
}
