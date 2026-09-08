[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$outer=Join-Path $repo '.tmp\dual-product'
$out=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if((Split-Path -Parent $out) -ine $outer -or (Split-Path -Leaf $out) -cnotmatch '^dp1-u-preflight-test-[A-Za-z0-9-]+$' -or
    (Test-Path -LiteralPath $out)){throw 'Use a fresh immediate .tmp/dual-product/dp1-u-preflight-test-* output'}
$ancestor=$out
while($ancestor){
    if(Test-Path -LiteralPath $ancestor){
        if((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse output ancestor'}
    }
    $ancestor=Split-Path -Parent $ancestor
}
$modulePath=Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.psm1'
$schemaPath=Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.schema.json'
$fixturePath=Join-Path $PSScriptRoot 'fixtures\dp1u-isolated-preflight.synthetic.json'
$m=Import-Module $modulePath -Force -PassThru
$schema=Get-Content $schemaPath -Raw | ConvertFrom-Json
$fixture=Get-Content $fixturePath -Raw
$golden='1ec93931984f798639703f602e30921882a8f221a83aafa9af83082f04a272e2'
$now='2026-09-08T02:02:00Z'
$checks=[Collections.Generic.List[object]]::new()
function Fresh {
    $jsonOptions=@{}
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$jsonOptions.DateKind='String'}
    $value=ConvertFrom-Json $fixture @jsonOptions
    foreach($field in @('approved_at_utc','expires_at_utc')){
        if($value.authorization.$field -is [datetime]){$value.authorization.$field=$value.authorization.$field.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}
    }
    if($value.preflight.observed_at_utc -is [datetime]){$value.preflight.observed_at_utc=$value.preflight.observed_at_utc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}
    return $value
}
function Check([string]$CheckName,[scriptblock]$Body){
    try{& $Body;$checks.Add([ordered]@{name=$CheckName;passed=$true;error=''})}
    catch{$checks.Add([ordered]@{name=$CheckName;passed=$false;error=$_.Exception.Message})}
}
function Assert([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Digest($Evidence){
    # Test-only resealing lets semantic negative tests get past digest binding.
    $hash=& $m {param($b,$s) Get-Dp1UDigest $b $s 'dp1u-product-boundary-v1'} $Evidence.product_boundary $schema.properties.product_boundary
    $Evidence.authorization.product_boundary_sha256=$hash
    $Evidence.preflight.product_boundary_sha256=$hash
    & $m {param($a,$s) Get-Dp1UDigest $a $s} $Evidence.authorization $schema.properties.authorization
}
function Reject($Evidence,[string]$Reason='', [string]$Digest=$golden, [string]$Time=$now){
    $r=Test-RimePimeDp1UIsolatedPreflight -Evidence $Evidence -TrustedApprovalSha256 $Digest -NowUtc $Time
    Assert (-not $r.supplied_contract_valid -and -not $r.execution_authorized -and -not $r.dp1_u_acceptance_passed) 'Invalid evidence admitted'
    Assert ($r.reasons.Count -gt 0) 'Missing refusal reason'
    if($Reason){Assert (($r.reasons -join '|') -like "*$Reason*") "Wrong refusal: $($r.reasons)"}
}
Check 'single-pure-export' {Assert ((@($m.ExportedCommands.Keys)-join ',') -ceq 'Test-RimePimeDp1UIsolatedPreflight') 'Unexpected export'}
Check 'synthetic-positive-never-authorizes-execution-or-installed-gates' {
    $r=Test-RimePimeDp1UIsolatedPreflight (Fresh) $golden $now
    Assert $r.supplied_contract_valid ($r.reasons -join '|')
    Assert ($r.authorization_sha256 -ceq $golden) 'Cross-shell golden digest drift'
    foreach($name in @('execution_authorized','native_target_verified','registration_gate_passed','rollback_gate_passed',
        'removal_gate_passed','runtime_gate_passed','dp1_u_acceptance_passed')){Assert (-not $r.$name) "Promoted $name"}
}
Check 'missing-authorization-observation-and-null-fail-closed' {
    Reject $null
    Reject ([pscustomobject]@{})
    $e=Fresh;$e.authorization=$null;Reject $e
    $e=Fresh;$e.preflight=$null;Reject $e
}
Check 'external-approval-digest-required' {Reject (Fresh) 'digest' '';Reject (Fresh) 'digest' ('d'*64)}
Check 'approval-cannot-be-reused-for-changed-request' {
    foreach($name in @('approval_reference','approved_by','target_name','run_id','state_root','package_sha256','product_boundary_sha256')){
        $e=Fresh;$e.authorization.$name=$e.authorization.$name.Replace('1','2')+'X';Reject $e
    }
}
foreach($section in @('authorization','preflight','product_boundary')){
    foreach($name in $schema.properties.$section.required){
        Check "missing-$section-$name" {
            $e=Fresh;$e.$section.PSObject.Properties.Remove($name);Reject $e 'field set'
        }
        Check "wrong-type-$section-$name" {
            $e=Fresh;$e.$section.$name=7;Reject $e
        }
        $spec=$schema.properties.$section.properties.$name
        if($spec.PSObject.Properties['const']){
            Check "changed-constant-$section-$name" {
                $e=Fresh
                if($spec.const -is [bool]){$e.$section.$name=-not $spec.const}else{$e.$section.$name='unsupported'}
                Reject $e 'constant mismatch'
            }
        }
    }
    Check "unknown-field-$section" {$e=Fresh;$e.$section|Add-Member extra $true;Reject $e 'field set'}
}
Check 'unknown-root-field-and-schema' {
    $e=Fresh;$e|Add-Member extra $true;Reject $e
    $e=Fresh;$e.schema_version='future';Reject $e
}
Check 'observed-target-root-artifact-binding' {
    foreach($name in @('run_id','target_name','target_machine_id','initiating_sid','state_root','install_root','recovery_root',
        'package_sha256','canonical_receipt_sha256','product_boundary_sha256')){
        $e=Fresh
        switch($name){
            target_name {$e.preflight.$name='OTHER-PC'}
            {$_ -match 'root$'} {$e.preflight.$name='C:\Other'}
            initiating_sid {$e.preflight.$name='S-1-5-21-111-222-333-1002'}
            default {$e.preflight.$name=$e.preflight.$name.Replace('1','3').Replace('2','3').Replace('a','d').Replace('b','d').Replace('c','d')}
        }
        Reject $e 'binding mismatch'
    }
}
Check 'mycomputer-rejected-even-with-resealed-approval' {
    foreach($name in @('MYCOMPUTER','mycomputer','MyComputer')){
        $e=Fresh;$e.authorization.target_name=$name;$e.preflight.target_name=$name
        Reject $e 'MYCOMPUTER' (Digest $e)
    }
}
Check 'same-sid-chain-and-explicit-hku-required' {
    foreach($name in @('process_sid','elevation_worker_sid','runtime_sid')){
        $e=Fresh;$e.preflight.$name='S-1-5-21-111-222-333-1002';Reject $e 'SID chain'
    }
    $e=Fresh;$e.preflight.registry_hku_path='HKEY_CURRENT_USER';Reject $e 'user scope'
}
Check 'expired-future-unbounded-and-stale-evidence' {
    Reject (Fresh) 'validity' $golden '2026-09-08T03:00:00Z'
    Reject (Fresh) 'validity' $golden '2026-09-08T01:59:59Z'
    Reject (Fresh) 'stale' $golden '2026-09-08T02:07:00Z'
    $e=Fresh;$e.preflight.observed_at_utc='2026-09-08T02:03:00Z';Reject $e 'future'
    $e=Fresh;$e.authorization.expires_at_utc='2026-09-10T03:00:00Z';Reject $e 'validity' (Digest $e)
    Reject (Fresh) '' $golden ''
}
Check 'unsafe-path-forms-rejected-after-resealing' {
    foreach($root in @('C:\','relative','\\server\share','\\?\C:\DP1','C:/DP1','C:\DP1\..\Other',
        'C:\DP1\','C:\DP1:stream','C:\DP1\file.','C:\DP1\CON','C:\DP1\PROGRA~1','C:\DP1\\child',
        'C:\Users\Test\AppData\DP1','C:\Program Files (x86)\YIME','C:\Windows\DP1','C:\%USERPROFILE%\DP1')){
        $e=Fresh;$e.authorization.state_root=$root;$e.preflight.state_root=$root;$e.product_boundary.state_root=$root;Reject $e '' (Digest $e)
    }
}
Check 'equal-or-nested-roots-rejected-component-wise' {
    foreach($root in @('C:\DP1-Install','C:\dp1-install','C:\DP1-Install\State')){
        $e=Fresh;$e.authorization.state_root=$root;$e.preflight.state_root=$root;$e.product_boundary.state_root=$root;Reject $e 'Overlapping' (Digest $e)
    }
    $e=Fresh;$e.authorization.state_root='C:\DP1-Install-Sibling';$e.preflight.state_root=$e.authorization.state_root
    $e.product_boundary.state_root=$e.authorization.state_root
    $r=Test-RimePimeDp1UIsolatedPreflight $e (Digest $e) $now;Assert $r.supplied_contract_valid 'Prefix sibling incorrectly rejected'
}
Check 'explicit-product-boundary-hash-roots-and-identities' {
    $e=Fresh;$e.product_boundary.peer_runtime_endpoint='tampered';Reject $e 'boundary digest'
    $e=Fresh;$e.product_boundary.install_root='C:\Other';Reject $e 'boundary root' (Digest $e)
    foreach($field in @('runtime_endpoint','run_value_name','uninstall_key_name','clsid','profile_guid')){
        $e=Fresh;$e.product_boundary.('peer_'+$field)=$e.product_boundary.$field
        Reject $e 'overlap' (Digest $e)
    }
    foreach($field in @('peer_install_root','peer_state_root','peer_recovery_root','production_install_root','production_state_root')){
        $e=Fresh;$e.product_boundary.$field=$e.authorization.state_root+'\Protected'
        Reject $e 'Overlapping' (Digest $e)
    }
}
Check 'source-has-no-process-registry-or-maintenance-execution-commands' {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Module parse errors'
    $allowed=@('Join-Path','Set-StrictMode','Assert-Dp1UShape','Get-Dp1UDigest','Assert-Dp1URoot','Get-Content','ConvertFrom-Json','Select-Object','Export-ModuleMember')
    foreach($command in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)){
        Assert ($allowed -contains $command.GetCommandName()) "Unexpected command $($command.Extent.Text)"
    }
}
$failed=@($checks|Where-Object{-not $_.passed})
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-isolated-preflight-test-v1'
    powershell_edition=$PSVersionTable.PSEdition;powershell_version=$PSVersionTable.PSVersion.ToString()
    module_sha256=(Get-FileHash $modulePath).Hash.ToLowerInvariant()
    schema_sha256=(Get-FileHash $schemaPath).Hash.ToLowerInvariant()
    fixture_sha256=(Get-FileHash $fixturePath).Hash.ToLowerInvariant()
    test_sha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant()
    passed=($failed.Count -eq 0);check_count=$checks.Count;passed_count=$checks.Count-$failed.Count
    failed_count=$failed.Count;checks=@($checks)
    fixture_only=$true;real_target_approved=$false;execution_authorized=$false
    actual_installer_or_uninstaller_executed=$false;actual_registry_or_product_process_touched=$false
    installed_yimecore_local12_touched=$false;production_user_data_accessed=$false;default_input_method_changed=$false
    dp1_u_acceptance_passed=$false
}
New-Item -ItemType Directory -Path $out | Out-Null
$path=Join-Path $out 'result.json'
[IO.File]::WriteAllText($path,($result|ConvertTo-Json -Depth 20 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
Remove-Module $m -Force
if($failed.Count){$failed|Format-Table -AutoSize;throw "DP1-U preflight failed: $($failed.Count). $path"}
Write-Host "PASS: DP1-U preflight $($checks.Count)/$($checks.Count). $path"
