[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$allowed=Join-Path $repo '.tmp\dual-product'
if (-not $OutputRoot) { $OutputRoot=Join-Path $allowed ('dp1-u-native-probe-'+[Guid]::NewGuid().ToString('N')) }
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'Use one new owned .tmp/dual-product result directory' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$module=Import-Module (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -Force -PassThru
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Passed) {
    if (-not $Passed) { throw ('FAIL: '+$Name) }
    $checks.Add([pscustomobject]@{name=$Name;passed=$true})
}
function Reject([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    $failure=$null
    try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    Check $Name ($null -ne $failure -and $failure -match $Pattern)
}
$options=@{}
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind='String' }
$fixture=ConvertFrom-Json -InputObject (Get-Content (Join-Path $PSScriptRoot 'fixtures\dp1u-isolated-preflight.synthetic.json') -Raw) @options
$a=$fixture.authorization; $b=$fixture.product_boundary
$b.clsid='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'; $b.profile_guid='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}'
$b.peer_clsid='{E40FA752-BB96-461D-A51D-F40EB437EC65}'; $b.peer_profile_guid='{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
foreach ($field in @('clsid','profile_guid','peer_clsid','peer_profile_guid')) { $b.$field=$b.$field.ToLowerInvariant() }
$b.run_value_name='PIMELauncher'; $b.uninstall_key_name='YIME'
$b.peer_run_value_name='YimeCoreExperimentalTrial'; $b.peer_uninstall_key_name='YimeCoreExperimentalTrial'
function Digest($Object,[string]$Section,[string]$Domain) {
    & $module { param($v,$section,$domain)
        $schema=Get-Content (Join-Path $PSScriptRoot 'rime-pime-dp1u-isolated-preflight.schema.json') -Raw | ConvertFrom-Json
        Get-Dp1UNativeObjectDigest $v $schema.properties.$section $domain
    } $Object $Section $Domain
}
$a.product_boundary_sha256=Digest $b 'product_boundary' 'dp1u-product-boundary-v1'
$digest=Digest $a 'authorization' 'dp1u-authorization-v1'
$now=[DateTime]::Parse('2026-09-08T02:30:00Z').ToUniversalTime()
function Validate($Approval,$Boundary,[string]$Digest,[string]$Machine='DP1-FIXTURE-PC',[DateTime]$Time=$now) {
    & $module { param($a,$b,$d,$machine,$time) Assert-Dp1UNativeRequest $a $b $d $machine $time } $Approval $Boundary $Digest $Machine $Time
}
Validate $a $b $digest
Check 'explicit synthetic source-identity policy accepts valid binding' $true
Reject 'missing approval digest' { Validate $a $b '' } 'approval digest'
Reject 'wrong approval digest' { Validate $a $b ('f'*64) } 'approval digest'
Reject 'wrong native target' { Validate $a $b $digest 'OTHER-PC' } 'native computer'
Reject 'MYCOMPUTER case insensitive policy' { Validate $a $b $digest 'mycomputer' } 'MYCOMPUTER'
Reject 'expired approval' { Validate $a $b $digest 'DP1-FIXTURE-PC' $now.AddHours(1) } 'validity'
Reject 'future approval' { Validate $a $b $digest 'DP1-FIXTURE-PC' $now.AddHours(-1) } 'validity'
foreach ($property in @($a.PSObject.Properties)) {
    $copy=ConvertFrom-Json -InputObject ($a|ConvertTo-Json -Depth 8) @options
    $copy.PSObject.Properties.Remove($property.Name)
    Reject ('authorization missing '+$property.Name) { Validate $copy $b $digest } 'field set'
}
$copy=ConvertFrom-Json -InputObject ($a|ConvertTo-Json -Depth 8) @options
$copy.production_user_data_allowed='false'
Reject 'string false is not boolean permission' { Validate $copy $b $digest } 'boolean'
$copy=ConvertFrom-Json -InputObject ($a|ConvertTo-Json -Depth 8) @options
$copy.yimecore_local12_allowed=$true
Reject 'local12 permission cannot bypass prohibition' { Validate $copy $b $digest } 'constant mismatch'
$badBoundary=ConvertFrom-Json -InputObject ($b|ConvertTo-Json -Depth 8) @options
$badBoundary.peer_clsid='{55555555-5555-4555-8555-555555555555}'
$copy=ConvertFrom-Json -InputObject ($a|ConvertTo-Json -Depth 8) @options
$copy.product_boundary_sha256=Digest $badBoundary 'product_boundary' 'dp1u-product-boundary-v1'
$badDigest=Digest $copy 'authorization' 'dp1u-authorization-v1'
Reject 'approval cannot substitute fictitious peer identity' { Validate $copy $badBoundary $badDigest } 'Source product identity'
foreach ($badPath in @('C:\safe\..\bad','C:\safe\item:stream','C:\safe\tail.','C:\safe\NUL','C:\safe\short~1','\\server\share','C:\safe\\child')) {
    Reject ('ambiguous path '+$badPath) { & $module { param($p) Assert-Dp1UNativePlainPath $p } $badPath } 'path|component'
}
$catalog=@(& $module { Get-Dp1UNativeRegistryCatalog 'S-1-5-21-111-222-333-1001' })
Check 'fixed protected registry catalog has 17 keys' ($catalog.Count -eq 17)
Check 'catalog has no caller-selected key or HKCU' (@($catalog|Where-Object {$_.hive -notin @([uint32]2147483650,[uint32]2147483651)}).Count -eq 0)
Check 'fixed current and legacy YimeCore identities are included' (@($catalog|Where-Object {$_.key -like '*E40FA752*'}).Count -eq 4 -and @($catalog|Where-Object {$_.key -like '*41EC6C9B*'}).Count -eq 4)
Check 'all user coordinates use exact explicit HKU SID' (@($catalog|Where-Object {$_.hive -eq 2147483651 -and -not $_.key.StartsWith('S-1-5-21-111-222-333-1001\')}).Count -eq 0)
Reject 'registry SID injection' { & $module { Get-Dp1UNativeRegistryCatalog 'S-1-5-21-111-222-333-1001\Other' } } 'SID'
foreach ($kind in @(0,1,2,3,4,7,11,99)) {
    $reply=[pscustomobject]@{ReturnValue=0;sNames=@('PIMELauncher');Types=@($kind)}
    $present=& $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply
    Check ('protected Run presence rejects registry type '+$kind) $present
}
$reply=[pscustomobject]@{ReturnValue=0;sNames=@('pimelauncher');Types=@(3)}
Check 'protected Run presence is case insensitive' (& $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply)
$reply=[pscustomobject]@{ReturnValue=0;sNames=$null;Types=$null}
Check 'empty native Run enumeration is absent' (-not (& $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply))
$reply=[pscustomobject]@{ReturnValue=2}
Check 'missing native Run key is absent' (-not (& $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply))
$reply=[pscustomobject]@{ReturnValue=0;sNames=@('PIMELauncher');Types=@()}
Reject 'inconsistent Run names/types fail closed' { & $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply } 'Inconsistent'
foreach ($code in @(5,'0',$false)) {
    $reply=[pscustomobject]@{ReturnValue=$code}
    Reject ('provider failure or wrong type '+[string]$code) { & $module { param($r) Test-Dp1UNativeNamedValuePresent $r 'PIMELauncher' } $reply } 'Invalid native'
}

# Native Win32 calls below inspect only this owned test host and files we create.
& $module { Initialize-Dp1UNativeFacts }
$own=[Yime.Dp1UNative.Facts]::OpenProcessFacts($PID)
try {
    Check 'native owned-process PID/image/token observation' ($own.Pid -eq $PID -and $own.Sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $own.CreationFileTime -gt 0 -and $own.Image)
} finally { $own.Dispose() }
$artifact=Join-Path $OutputRoot 'owned-artifact.json'
[IO.File]::WriteAllText($artifact,'{"id":"owned-fixture","at":"2026-09-08T02:30:00Z"}',[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
$lease=& $module { param($p,$h) Open-Dp1UNativeArtifact $p $h -Json } $artifact $hash
try {
    Check 'native file handle/digest/identity binding' ($lease.sha256 -ceq $hash -and $lease.file_identity -match '^[a-f0-9]{8}:[a-f0-9]{16}$')
    Check 'PS5/PS7 timestamp stays string' ($lease.value.at -is [string])
    Reject 'artifact read lease denies concurrent write' { $s=[IO.File]::Open($artifact,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite); $s.Dispose() } 'used by another process|being used|另一个进程|使用'
} finally { $lease.stream.Dispose() }
Reject 'artifact hash substitution' { & $module { param($p) Open-Dp1UNativeArtifact $p ('0'*64) -Json } $artifact } 'digest mismatch'
Reject 'bounded artifact read' { & $module { param($p) Open-Dp1UNativeArtifact $p '' 1 -Json } $artifact } 'size'
$hardlink=Join-Path $OutputRoot 'owned-hardlink.json'
New-Item -ItemType HardLink -Path $hardlink -Target $artifact | Out-Null
Reject 'multiply-linked artifact rejected' { & $module { param($p) Open-Dp1UNativeArtifact $p '' -Json } $hardlink } 'multiply-linked'

$earlyRejection=$false
if ([Environment]::MachineName -ieq 'MYCOMPUTER') {
    Reject 'live MYCOMPUTER rejected before nonexistent authorization read' {
        Invoke-RimePimeDp1UNativeReadOnlyProbe -AuthorizationPath 'C:\nonexistent-dp1u-probe-approval.json' -TrustedApprovalSha256 ('0'*64) -BoundaryPath 'C:\none-boundary.json' -PackagePath 'C:\none-package.exe' -CanonicalReceiptPath 'C:\none-receipt.json' -ReceiptEvidenceRoot 'C:\none-evidence'
    } 'MYCOMPUTER.*before probing'
    $earlyRejection=$true
}
Check 'only native read-only entry exported' (@($module.ExportedFunctions.Keys).Count -eq 1 -and $module.ExportedFunctions.ContainsKey('Invoke-RimePimeDp1UNativeReadOnlyProbe'))
$source=Get-Content (Join-Path $PSScriptRoot 'rime-pime-dp1u-native-probe.psm1') -Raw
Check 'adapter has no caller-injected command/scriptblock provider' ($source -notmatch '(?i)\[scriptblock\]|Invoke-Expression|Start-Process|Set-ItemProperty|CreateProcess|Stop-Process')
Check 'execution and installed acceptance are never promoted' ($source.Contains('native_preflight_complete=$false; execution_authorized=$false') -and $source.Contains('dp1_u_acceptance_passed=$false'))
$result=[ordered]@{
    schema_version='yime-rime-pime-dp1u-native-readonly-probe-tests-v1'; powershell_version=$PSVersionTable.PSVersion.ToString()
    passed=$true; checks_passed=$checks.Count; checks=@($checks); actual_mycomputer_early_rejection_executed=$earlyRejection
    native_win32_owned_process_and_file_primitives_tested=$true; native_success_on_isolated_target_tested=$false
    stdregprov_native_positive_path_tested=$false; installers_or_product_processes_executed=$false; registry_mutated=$false; user_data_read=$false
    execution_authorized=$false; dp1_u_acceptance_passed=$false
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputRoot 'result.json') -Encoding UTF8
Write-Host ('PASS: '+$checks.Count+' DP1-U native read-only probe checks; '+$OutputRoot)
