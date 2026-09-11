[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$parent=Join-Path $repo '.tmp\dual-product'
if(-not $OutputRoot){$OutputRoot=Join-Path $parent ('dp1-executable-candidate-test-'+[guid]::NewGuid().ToString('N'))}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if([IO.Path]::GetDirectoryName($OutputRoot) -ine $parent -or [IO.Path]::GetFileName($OutputRoot) -notmatch '^dp1-executable-candidate-test-' -or (Test-Path -LiteralPath $OutputRoot)){throw 'Fresh owned candidate test root required.'}
$null=[IO.Directory]::CreateDirectory($OutputRoot)
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-executable-candidate.psm1') -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    & $Body
    $checks.Add([pscustomobject]@{name=$Name;passed=$true})
    Write-Host ('PASS '+$Name)
}
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    $errorText=$null;try{& $Body | Out-Null}catch{$errorText=$_.Exception.ToString()}
    Assert ($null -ne $errorText -and $errorText -match $Pattern) ('Expected rejection '+$Pattern+'; observed '+$errorText)
}
function New-Fixture {
    $root=Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($root)
    $rows=@()
    foreach($name in @('PIMELauncher.exe','x86/PIMETextService.dll','x64/PIMETextService.dll','x86/PIMERegistrationStatus.exe',
        'x64/PIMERegistrationStatus.exe','go-backend/server.exe','maintenance/invoke-rime-pime-candidate.ps1',
        'maintenance/rime-pime-dp1u-candidate-registration.psm1','maintenance/rime-pime-dp1u-candidate-runtime.psm1','maintenance/rime-pime-peer-protection.psm1')){
        $path=Join-Path $root $name;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,'inert owned fixture: '+$name,[Text.UTF8Encoding]::new($false))
        $rows += [pscustomobject]@{path=$name;bytes=[long](Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $manifest=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-executable-candidate-v2';product='rime-pime';product_version='1.4.0-dev.2';architectures='x86,x64'
        installation_scope='approved-isolated-x64-current-peer-protected';launcher_mode='required-dp1-candidate-state'
        maintenance_entry='maintenance/invoke-rime-pime-candidate.ps1';registration_provider='maintenance/rime-pime-dp1u-candidate-registration.psm1'
        runtime_provider='maintenance/rime-pime-dp1u-candidate-runtime.psm1';files=$rows;source_inventory_sha256=('a'*64)
        public_release_admitted=$false;installed_acceptance_passed=$false
    }
    $case=[pscustomobject]@{root=$root;manifest=$manifest;hash=''};Seal $case;return $case
}
function Seal($Case){
    $path=Join-Path $Case.root 'candidate.json'
    [IO.File]::WriteAllText($path,($Case.manifest|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
    $Case.hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Open-Case($Case){Open-RimePimeExecutableCandidate -PackageRoot $Case.root -ExpectedManifestSha256 $Case.hash}
Check 'exact owned bundle holds files and does not grant execution' {
    $case=New-Fixture;$opened=Open-Case $case
    try{
        Assert ($opened.files.Count -eq 10 -and -not $opened.execution_authorized) 'Wrong candidate observation.'
        Reject {[IO.File]::WriteAllText((Join-Path $case.root 'PIMELauncher.exe'),'changed')} 'used by another process|being used|sharing|process cannot'
    }finally{Close-RimePimeExecutableCandidate $opened}
}
foreach($flag in @('public_release_admitted','installed_acceptance_passed')){
    Check ('candidate cannot grant '+$flag) {$case=New-Fixture;$case.manifest.$flag=$true;Seal $case;Reject {Open-Case $case} 'cannot grant'}
    Check ('candidate rejects string '+$flag) {$case=New-Fixture;$case.manifest.$flag='false';Seal $case;Reject {Open-Case $case} 'cannot grant'}
}
Check 'disabled receipt is never silently upgraded' {$case=New-Fixture;$case.manifest.schema_version='yime-rime-pime-package-build-receipt-v2';Seal $case;Reject {Open-Case $case} 'Unsupported candidate identity'}
Check 'external manifest digest required' {$case=New-Fixture;$case.hash='b'*64;Reject {Open-Case $case} 'external digest'}
Check 'literal schema type required' {$case=New-Fixture;$case.manifest.schema_version=@('yime-rime-pime-executable-candidate-v2');Seal $case;Reject {Open-Case $case} 'Unsupported candidate identity'}
Check 'historical clean-only manifest cannot become peer-protected by relabeling scope' {$case=New-Fixture;$case.manifest.schema_version='yime-rime-pime-executable-candidate-v1';Seal $case;Reject {Open-Case $case} 'Unsupported candidate identity'}
Check 'peer protection is a required packaged dependency' {$case=New-Fixture;$case.manifest.files=@($case.manifest.files|Where-Object path -CNE 'maintenance/rime-pime-peer-protection.psm1');Seal $case;Reject {Open-Case $case} 'required member missing'}
Check 'changed payload rejected' {$case=New-Fixture;[IO.File]::AppendAllText((Join-Path $case.root 'PIMELauncher.exe'),'x');Reject {Open-Case $case} 'member differs'}
Check 'unlisted file rejected' {$case=New-Fixture;[IO.File]::WriteAllText((Join-Path $case.root 'foreign.txt'),'retain');Reject {Open-Case $case} 'Unlisted candidate file';Assert ([IO.File]::ReadAllText((Join-Path $case.root 'foreign.txt')) -ceq 'retain') 'Foreign file changed.'}
Check 'unlisted empty directory rejected' {$case=New-Fixture;$null=[IO.Directory]::CreateDirectory((Join-Path $case.root 'foreign'));Reject {Open-Case $case} 'Unlisted candidate directory'}
Check 'case duplicate member rejected' {$case=New-Fixture;$case.manifest.files += $case.manifest.files[0];Seal $case;Reject {Open-Case $case} 'Duplicate'}
Check 'traversal rejected before member open' {$case=New-Fixture;$case.manifest.files[0].path='../escape.exe';Seal $case;Reject {Open-Case $case} 'Ambiguous candidate member'}
Check 'runtime fallback mode rejected' {$case=New-Fixture;$case.manifest.launcher_mode='optional-state-file';Seal $case;Reject {Open-Case $case} 'Unsupported candidate identity'}
Check 'missing registration provider rejected' {$case=New-Fixture;$case.manifest.files=@($case.manifest.files|Where-Object path -NotMatch 'registration.psm1$');Seal $case;Reject {Open-Case $case} 'required member missing'}
Check 'duplicate json key rejected with matching outer digest' {
    $case=New-Fixture;$path=Join-Path $case.root 'candidate.json';$raw=[IO.File]::ReadAllText($path)
    [IO.File]::WriteAllText($path,('{"product":"rime-pime",'+$raw.Substring(1)),[Text.UTF8Encoding]::new($false))
    $case.hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();Reject {Open-Case $case} 'Invalid transaction JSON'
}
Check 'source provenance retains origin ADS while pinning only default bytes' {
    $case=New-Fixture;$path=Join-Path $case.root 'PIMELauncher.exe'
    Set-Content -LiteralPath $path -Stream Zone.Identifier -Value 'owned origin metadata' -Encoding ASCII -NoNewline
    $e=& $module {param($root,$rows)Open-CandidateSourceEvidence $root $rows} $case.root @($case.manifest.files[0])
    try{& $module {param($v)Assert-CandidateSourceEvidence $v} $e;Assert ($e.provenance_only -and (Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw) -ceq 'owned origin metadata') 'Source metadata changed.'}
    finally{& $module {param($v)Close-CandidateSourceEvidence $v} $e}
}
Check 'actual payload continues to reject named streams' {
    $case=New-Fixture;Set-Content -LiteralPath (Join-Path $case.root 'PIMELauncher.exe') -Stream Zone.Identifier -Value 'owned metadata' -Encoding ASCII -NoNewline
    Reject {Open-Case $case} 'Named stream rejected'
}
Check 'source provenance blocks writes and rejects changed default bytes' {
    $case=New-Fixture;$path=Join-Path $case.root 'PIMELauncher.exe'
    $e=& $module {param($root,$rows)Open-CandidateSourceEvidence $root $rows} $case.root @($case.manifest.files[0])
    try{Reject {[IO.File]::AppendAllText($path,'changed')} 'used by another process|being used|sharing|process cannot'}
    finally{& $module {param($v)Close-CandidateSourceEvidence $v} $e}
    [IO.File]::AppendAllText($path,'changed')
    Reject {& $module {param($root,$rows)Open-CandidateSourceEvidence $root $rows} $case.root @($case.manifest.files[0])} 'default stream differs'
}
$result=[ordered]@{schema_version='yime-rime-pime-executable-candidate-reader-test-v1';passed=$true;checks=@($checks.ToArray());
    powershell_version=$PSVersionTable.PSVersion.ToString();installer_executed=$false;product_runtime_started=$false;
    production_registration_modified=$false;installed_local12_touched=$false;dp1_u_acceptance_passed=$false}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'result.json'),($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host ('PASS '+$checks.Count+' candidate-reader checks: '+$OutputRoot)
