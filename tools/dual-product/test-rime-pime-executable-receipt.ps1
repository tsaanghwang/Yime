[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $OutputRoot){$OutputRoot=Join-Path $repo ('.tmp\dual-product\executable-receipt-test-'+[guid]::NewGuid().ToString('N'))}
$out=[IO.Path]::GetFullPath($OutputRoot)
if(-not $out.StartsWith((Join-Path $repo '.tmp\dual-product')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)){throw 'Fresh repository fixture root required.'}
$null=[IO.Directory]::CreateDirectory($out)
Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-receipt.psm1') -Scope Local
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
$installer=Join-Path $out 'synthetic-bytes.exe';[IO.File]::WriteAllBytes($installer,(New-Object byte[] 65536));$installerHash=Hash $installer
$hash='a'*64;$sourceNames=@('tools/dual-product/build-rime-pime-executable-candidate.ps1','installer/rime-pime-candidate.nsi','tools/dual-product/rime-pime-executable-receipt.psm1','tools/dual-product/rime-pime-executable-candidate.psm1')
$base=[ordered]@{schema_version='yime-rime-pime-executable-build-receipt-v1';product='rime-pime';product_version='1.4.0-dev.2';installer=[ordered]@{sha256=$installerHash;bytes=65536};manifest_sha256=$hash;source_inventory_sha256=$hash;build_sources=@($sourceNames|ForEach-Object{[ordered]@{path=$_;bytes=1;sha256=$hash}});compiler_interval=[ordered]@{schema_version='yime-rime-pime-nsis-compiler-membership-interval-v1';armed_before_baseline=$true;completion_barrier_after_compiler_exit=$true;unexpected_membership_event_count=0;notification_batch_count=1;physical_membership_prevention_claimed=$false;active_same_sid_transient_tree_membership_interference_excluded=$false;nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false};static_payload=[ordered]@{verified=$true;member_count=10;tree_sha256=$hash};makensis_sha256=$hash;nsis_toolchain_lock_sha256=$hash;signing_complete=$false;installed_acceptance_passed=$false;public_release_admitted=$false}
$results=[Collections.Generic.List[object]]::new();$counter=0
function Check([string]$Name,[scriptblock]$Edit,[bool]$Accept=$false){
    $script:counter++;$r=$base|ConvertTo-Json -Depth 30|ConvertFrom-Json
    & $Edit $r
    $p=Join-Path $out ('receipt-'+$script:counter+'.json');[IO.File]::WriteAllText($p,($r|ConvertTo-Json -Depth 30 -Compress),[Text.UTF8Encoding]::new($false))
    $ok=$false;$detail='';try{$result=Read-RimePimeExecutableReceipt -ReceiptPath $p -ExpectedReceiptSha256 (Hash $p) -InstallerPath $installer -ExpectedInstallerSha256 $installerHash -ExpectedManifestSha256 $hash;if($result.execution_authorized -or $result.installer_executed -or $result.uninstaller_executed){throw 'Reader granted execution.'};$ok=$true}catch{$detail=$_.Exception.Message}
    if($ok -ne $Accept){throw ('Unexpected receipt result '+$Name+': '+$detail)};$results.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host ('PASS '+$Name)
}
Check 'synthetic exact evidence is read without execution' {} $true
Check 'disabled receipt not promoted' {param($r)$r.schema_version='yime-rime-pime-package-build-receipt-v2'}
Check 'array schema rejected' {param($r)$r.schema_version=@($r.schema_version)}
Check 'wrong installer bytes' {param($r)$r.installer.bytes=65537}
Check 'wrong installer digest' {param($r)$r.installer.sha256='b'*64}
Check 'wrong manifest digest' {param($r)$r.manifest_sha256='b'*64}
Check 'array manifest digest' {param($r)$r.manifest_sha256=@($r.manifest_sha256)}
Check 'no source closure' {param($r)$r.build_sources=@()}
Check 'duplicate source' {param($r)$r.build_sources[1]=$r.build_sources[0]}
Check 'source path traversal' {param($r)$r.build_sources[0].path='../escape.ps1'}
Check 'zero source length' {param($r)$r.build_sources[0].bytes=0}
Check 'unknown receipt field' {param($r)$r|Add-Member forged $true}
Check 'unarmed interval' {param($r)$r.compiler_interval.armed_before_baseline=$false}
Check 'no after-exit barrier' {param($r)$r.compiler_interval.completion_barrier_after_compiler_exit=$false}
Check 'transient event observed' {param($r)$r.compiler_interval.unexpected_membership_event_count=1}
Check 'array event count' {param($r)$r.compiler_interval.unexpected_membership_event_count=@(0)}
Check 'negative batch count' {param($r)$r.compiler_interval.notification_batch_count=-1}
Check 'physical prevention unproven' {param($r)$r.compiler_interval.physical_membership_prevention_claimed=$true}
Check 'same SID physical prevention unproven' {param($r)$r.compiler_interval.active_same_sid_transient_tree_membership_interference_excluded=$true}
Check 'full toolchain closure unproven' {param($r)$r.compiler_interval.full_nsis_toolchain_input_closure=$true}
Check 'static byte comparison absent' {param($r)$r.static_payload.verified=$false}
Check 'static array boolean' {param($r)$r.static_payload.verified=@($true)}
Check 'signed claim refused' {param($r)$r.signing_complete=$true}
Check 'installed acceptance claim refused' {param($r)$r.installed_acceptance_passed=$true}
Check 'public release claim refused' {param($r)$r.public_release_admitted=$true}
$dup=Join-Path $out 'duplicate.json';$json=$base|ConvertTo-Json -Depth 30 -Compress;$json=$json.Replace('"product":"rime-pime"','"product":"rime-pime","Product":"rime-pime"');[IO.File]::WriteAllText($dup,$json,[Text.UTF8Encoding]::new($false));$rejected=$false
try{$null=Read-RimePimeExecutableReceipt -ReceiptPath $dup -ExpectedReceiptSha256 (Hash $dup) -InstallerPath $installer -ExpectedInstallerSha256 $installerHash -ExpectedManifestSha256 $hash}catch{$rejected=$true};if(-not $rejected){throw 'Duplicate JSON key accepted'};$results.Add([pscustomobject]@{name='case duplicate JSON rejected';passed=$true})
$report=[ordered]@{schema_version='yime-rime-pime-executable-receipt-test-v1';passed=$true;test_count=$results.Count;powershell=$PSVersionTable.PSVersion.ToString();synthetic_fixture=$true;installer_executed=$false;uninstaller_executed=$false;local12_touched=$false;results=@($results)}
[IO.File]::WriteAllText((Join-Path $out 'result.json'),($report|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false));Write-Host ('PASS '+$results.Count+'; '+$out)
