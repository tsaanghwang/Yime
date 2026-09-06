[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-target-user-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-target-user-* fixture root.'
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Target-user evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Must-Reject([scriptblock]$Body) {
    $rejected = $false
    try { & $Body | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Expected fail-closed rejection.'
}

$sourceFiles = @(
    'installer/installer.nsi',
    'tools/dual-product/rime-pime-target-user.ps1',
    'tools/dual-product/invoke-rime-pime-target-user.ps1',
    'tools/dual-product/rime-pime-ownership.ps1',
    'tools/dual-product/invoke-rime-pime-maintenance.ps1',
    'tools/pime-registry-cleanup.ps1',
    'tools/dev-install.ps1',
    'tools/dev-uninstall.ps1',
    'tools/dev-stop-pime.ps1',
    'tools/dev-build-install-verify.ps1',
    'tools/refresh-ime-profiles.ps1',
    'tools/refresh-dev-test-cmds.ps1',
    'tools/templates/Install-PIME-Test.cmd',
    'tools/templates/Reinstall-PIME-Test.cmd',
    'tools/templates/Uninstall-PIME-Test.cmd',
    'Reinstall-PIME-Test.cmd',
    'Install-PIME-Test.cmd',
    'Uninstall-PIME-Test.cmd',
    'dev-install.ps1',
    'dev-uninstall.ps1'
)
$source = @{}
$beforeHashes = [ordered]@{}
foreach ($relative in $sourceFiles) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $source[$relative] = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $beforeHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
        $source[$relative] = $null
        $beforeHashes[$relative] = $null
    }
}

$library = $source['tools/dual-product/rime-pime-target-user.ps1']
$entry = $source['tools/dual-product/invoke-rime-pime-target-user.ps1']
$installer = $source['installer/installer.nsi']
$cleanup = $source['tools/pime-registry-cleanup.ps1']
$devInstall = $source['tools/dev-install.ps1']
$devUninstall = $source['tools/dev-uninstall.ps1']
$buildInstall = $source['tools/dev-build-install-verify.ps1']
$refresh = $source['tools/refresh-ime-profiles.ps1']
$template = $source['tools/templates/Reinstall-PIME-Test.cmd']
$rootReinstall = $source['Reinstall-PIME-Test.cmd']

Check 'target-user-library-exists-and-is-definitions-only' {
    Assert-True ($null -ne $library) 'Target-user contract source is missing.'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($library,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Target-user contract does not parse.'
    $topCommands=@($ast.EndBlock.Statements | Where-Object {$_ -isnot [Management.Automation.Language.FunctionDefinitionAst]})
    Assert-True ($topCommands.Count -eq 0) 'Importing the target-user contract would execute an action.'
}
Check 'target-user-entry-is-explicit-and-fail-closed' {
    Assert-True ($null -ne $entry) 'Target-user entry source is missing.'
    foreach($anchor in @("[ValidateSet('CaptureInitiator','CreateEnvelope','ValidateWorker')]",'[string]$TargetUserSid',
            '[string]$InitiatingSid','one-time correlation identity','Confirm-YimePimeElevationEnvelopeFile',
            '-Consume')) {
        Assert-True $entry.Contains($anchor) "Target-user entry is missing: $anchor"
    }
    Assert-True ([regex]::Matches($entry,'Assert-YimePimeUnpackagedExplorerInitiator').Count -eq 2) `
        'CaptureInitiator/CreateEnvelope do not both reject packaged ancestry before elevation.'
}

if ($null -ne $library) {
    . (Join-Path $repo 'tools\dual-product\rime-pime-target-user.ps1')
    Check 'same-sid-elevation-envelope-accepts-only-the-declared-shape' {
        $sid='S-1-5-21-100-200-300-1001'
        $result=Assert-YimePimeElevationEnvelope -InitiatingSid $sid -TargetUserSid $sid -WorkerSid $sid `
            -InitiatingTokenElevated:$false -WorkerTokenElevated:$true
        Assert-True ($result.target_user_sid -ceq $sid) 'Accepted envelope changed the target SID.'
    }
    Check 'same-sid-elevation-envelope-rejects-other-user-and-token-inversion' {
        $sid='S-1-5-21-100-200-300-1001';$other='S-1-5-21-100-200-300-1002'
        Must-Reject {Assert-YimePimeElevationEnvelope $sid $other $other $false $true}
        Must-Reject {Assert-YimePimeElevationEnvelope $sid $sid $sid $true $true}
        Must-Reject {Assert-YimePimeElevationEnvelope $sid $sid $sid $false $false}
    }
    Check 'packaged-or-unproven-initiator-ancestry-is-rejected' {
        foreach($anchor in @('GetCurrentPackageFullName','packageResult -ne 15700',
                "Join-Path `$env:ProgramFiles 'WindowsApps\'",'Get-CimInstance Win32_Process',
                "process.Name -ieq 'explorer.exe'",'depth -lt 32')) {
            Assert-True $library.Contains($anchor) "Unpackaged ancestry guard is missing: $anchor"
        }
        $script:packageResult=15700;$script:ancestryCase='native'
        function Get-YimePimePackageIdentityResult {return $script:packageResult}
        function Get-CimInstance {
            param([string]$ClassName,[string]$Filter,$ErrorAction)
            $id=[int]($Filter -replace '^ProcessId=','')
            if($id -eq $PID) {
                return [pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';ParentProcessId=424242}
            }
            if($script:ancestryCase -eq 'unknown'){return $null}
            if($script:ancestryCase -eq 'cycle') {
                return [pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';ParentProcessId=424242}
            }
            if($script:ancestryCase -eq 'packaged') {
                return [pscustomobject]@{Name='packaged.exe';ExecutablePath=(Join-Path $env:ProgramFiles 'WindowsApps\Fixture\packaged.exe');ParentProcessId=0}
            }
            return [pscustomobject]@{Name='explorer.exe';ExecutablePath='C:\Windows\explorer.exe';ParentProcessId=0}
        }
        Assert-True (Assert-YimePimeUnpackagedExplorerInitiator) 'Explorer-launched fixture was rejected.'
        foreach($case in @('packaged','unknown','cycle')) {
            $script:ancestryCase=$case
            Must-Reject {Assert-YimePimeUnpackagedExplorerInitiator}
        }
        $script:ancestryCase='native';$script:packageResult=0
        Must-Reject {Assert-YimePimeUnpackagedExplorerInitiator}
    }
    Check 'target-user-registry-path-is-exact-and-injection-safe' {
        $sid='S-1-5-21-100-200-300-1001'
        $path=Get-YimePimeTargetUserRegistryPath -TargetUserSid $sid -RelativePath 'Control Panel\International\User Profile'
        Assert-True ($path -ceq "Registry::HKEY_USERS\$sid\Control Panel\International\User Profile") 'Wrong target-user registry path.'
        Must-Reject {Get-YimePimeTargetUserRegistryPath 'S-1-5-21-1\Software' 'Control Panel'}
        Must-Reject {Get-YimePimeTargetUserRegistryPath $sid '..\OtherUser'}
    }
    Check 'one-time-correlation-record-rejects-mismatch-and-staleness' {
        $sid='S-1-5-21-100-200-300-1001';$now=[datetime]::UtcNow;$correlation='a'*32
        $record=New-YimePimeElevationEnvelopeRecord -InitiatingSid $sid -TargetUserSid $sid `
            -CreatedUtc $now -CorrelationId $correlation
        $accepted=Assert-YimePimeElevationEnvelopeRecord $record $correlation $sid $true $now
        Assert-True ($accepted.target_user_sid -ceq $sid) 'Correlated envelope changed the target SID.'
        Must-Reject {Assert-YimePimeElevationEnvelopeRecord $record ('b'*32) $sid $true $now}
        Must-Reject {Assert-YimePimeElevationEnvelopeRecord $record $correlation $sid $true $now.AddMinutes(11)}
    }
    Check 'envelope-file-contract-is-owned-bounded-and-consumed' {
        foreach($anchor in @("[IO.Path]::GetFileName(`$Path) -cne 'rime-pime-target-user-envelope.json'",
                'GetAccessControl().Owner','Length -gt 4096','if($Consume){Remove-Item -LiteralPath $full')) {
            Assert-True $library.Contains($anchor) "One-time envelope guard is missing: $anchor"
        }
    }
}

Check 'installer-is-a-two-stage-same-sid-bootstrap' {
    foreach($anchor in @('RequestExecutionLevel user','var InitiatingSid','var TargetUserSid','Function bootstrapTargetUser',
            'Function un.bootstrapTargetUser','CaptureInitiator','CreateEnvelope','ValidateWorker','ExecShellWait "runas"',
            '/InitiatingSid=','/TargetUserSid=','/EnvelopePath=','/CorrelationId=',
            'Call acceptTargetUserWorker','Call un.acceptTargetUserWorker')) {
        Assert-True $installer.Contains($anchor) "Installer bootstrap is missing: $anchor"
    }
}
Check 'installer-validates-before-install-or-uninstall-initialization' {
    $installInit=[regex]::Match($installer,'(?s)Function \.onInit\s+(.*?)FunctionEnd').Groups[1].Value
    $uninstallInit=[regex]::Match($installer,'(?s)Function un\.onInit\s+(.*?)FunctionEnd').Groups[1].Value
    Assert-True ($installInit.IndexOf('Call bootstrapTargetUser') -ge 0) 'Installer initialization does not bootstrap target SID.'
    Assert-True ($uninstallInit.IndexOf('Call un.bootstrapTargetUser') -ge 0) 'Uninstaller initialization does not bootstrap target SID.'
}
Check 'installer-passes-target-sid-to-every-maintenance-guard' {
    Assert-True ($installer.Contains('-TargetUserSid "$TargetUserSid"')) 'Installer maintenance helper omits target SID.'
    Assert-True ($installer.Contains('-InitiatingSid "$InitiatingSid"')) 'Installer target-user helper omits initiating SID.'
}
Check 'profile-enable-disable-is-bound-to-validated-target-user' {
    foreach($anchor in @('Function InstallLayoutOrTipForUser','Call validateTargetUserWorker',
            'Function un.InstallLayoutOrTipForUser','Call un.validateTargetUserWorker')) {
        Assert-True $installer.Contains($anchor) "Profile operation is missing: $anchor"
    }
    Assert-True ($installer -notmatch '(?m)^Function (?:un\.)?(?:enable|disable)YimeProfile\s*$') 'Unbound profile function remains.'
}
Check 'cleanup-requires-one-explicit-target-sid' {
    foreach($anchor in @('[Parameter(Mandatory = $true)]','[string]$TargetUserSid','Assert-PIMERegistryTargetUserSid')) {
        Assert-True $cleanup.Contains($anchor) "Cleanup target SID contract is missing: $anchor"
    }
    Assert-True ($cleanup -notmatch 'Get-ChildItem\s+-LiteralPath\s+"Registry::HKEY_USERS"') 'Cleanup still enumerates every loaded user.'
    Assert-True ($cleanup -notmatch 'HKCU:') 'Cleanup still relies on elevated process HKCU.'
}
Check 'cleanup-builds-only-the-explicit-hku-root' {
    Assert-True ($cleanup.Contains("Get-YimePimeTargetUserRegistryPath -TargetUserSid `$TargetUserSid")) 'Cleanup does not derive the exact HKU target root.'
    Assert-True ($cleanup.Contains('Remove-PIMEUserLanguageProfileValues -TargetUserSid $TargetUserSid')) 'Nested user cleanup loses target SID.'
}
Check 'developer-install-and-uninstall-require-and-pass-target-sid' {
    foreach($text in @($devInstall,$devUninstall)) {
        Assert-True ($text.Contains('Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit')) 'Mutating developer entry permits an implicit SID.'
        Assert-True ($text.Contains('Remove-PIMETextServiceRegistry -TargetUserSid $TargetUserSid')) 'Registry cleanup call loses target SID.'
    }
}
Check 'profile-refresh-requires-target-sid-through-stop-reset' {
    foreach($anchor in @('[Parameter(Mandatory)][string]$TargetUserSid','Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit',
            '-TargetUserSid $TargetUserSid','Reset-PIMETextServiceProfiles -InstallRoot $InstallRoot -TargetUserSid $TargetUserSid')) {
        Assert-True $refresh.Contains($anchor) "Refresh path loses target SID: $anchor"
    }
}
Check 'canonical-reinstall-captures-before-elevation-and-forwards-every-step' {
    foreach($text in @($template,$rootReinstall)) {
        Assert-True ($text.Contains('CaptureInitiator')) 'Canonical reinstall does not capture initiating SID.'
        Assert-True ($text.IndexOf('CaptureInitiator') -lt $text.IndexOf('-Verb RunAs')) 'Initiating SID is captured after elevation.'
        foreach($anchor in @('-TargetUserSid "%TARGET_USER_SID%"','/TargetUserSid=!TARGET_USER_SID!')) {
            Assert-True $text.Contains($anchor) "Canonical reinstall is missing: $anchor"
        }
    }
}
Check 'install-and-uninstall-wrappers-preserve-target-sid' {
    foreach($relative in @('Install-PIME-Test.cmd','Uninstall-PIME-Test.cmd')) {
        $text=$source[$relative]
        Assert-True ($text.Contains('CaptureInitiator') -and $text.Contains('/TargetUserSid=!TARGET_USER_SID!') -and
            $text.Contains('-TargetUserSid "%TARGET_USER_SID%"')) "$relative loses the initiating SID."
    }
}
Check 'generated-command-files-match-their-canonical-templates' {
    foreach($name in @('Install-PIME-Test.cmd','Reinstall-PIME-Test.cmd','Uninstall-PIME-Test.cmd')) {
        $generated=$source[$name].Replace("`r`n","`n")
        $canonical=$source["tools/templates/$name"].Replace("`r`n","`n")
        Assert-True ($generated -ceq $canonical) "$name drifted from its canonical template."
    }
}
Check 'command-refresh-copies-all-three-target-sid-templates' {
    $generator=$source['tools/refresh-dev-test-cmds.ps1']
    foreach($name in @('Install-PIME-Test.cmd','Reinstall-PIME-Test.cmd','Uninstall-PIME-Test.cmd')) {
        Assert-True ($generator.Contains("Copy-TestCommandTemplate -TemplateName `"$name`"")) "Refresh generator does not copy $name."
    }
}
Check 'powershell-wrappers-preserve-an-explicit-target-sid' {
    foreach($relative in @('dev-install.ps1','dev-uninstall.ps1')) {
        $text=$source[$relative]
        Assert-True ($text.Contains('[Parameter(Mandatory)][string]$TargetUserSid') -and
            $text.Contains('-TargetUserSid $TargetUserSid')) "$relative loses explicit target SID."
    }
}
Check 'build-install-elevation-carries-and-revalidates-initiator-sid' {
    foreach($anchor in @('[string]$TargetUserSid','Get-YimePimeCurrentSid','-TargetUserSid',
            'Assert-YimePimeTargetSid $TargetUserSid -RequireExplicit','/TargetUserSid=')) {
        Assert-True $buildInstall.Contains($anchor) "Build/install elevation chain is missing: $anchor"
    }
}
Check 'maintenance-cli-requires-target-sid' {
    $maintenance=$source['tools/dual-product/invoke-rime-pime-maintenance.ps1']
    Assert-True ($maintenance.Contains('[Parameter(Mandatory)][string]$TargetUserSid')) 'Maintenance CLI allows target SID omission.'
}
Check 'ownership-validator-supports-explicit-worker-mode' {
    $ownership=$source['tools/dual-product/rime-pime-ownership.ps1']
    Assert-True ($ownership.Contains('[switch]$RequireExplicit') -and
        $ownership.Contains('if($RequireExplicit')) 'Ownership helper cannot require an elevation-carried SID.'
}

$afterHashes=[ordered]@{}
foreach($relative in $sourceFiles) {
    $path=Join-Path $repo $relative
    $afterHashes[$relative]=if(Test-Path -LiteralPath $path -PathType Leaf){
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }else{$null}
}
$sourceUnchanged=(($beforeHashes|ConvertTo-Json -Depth 5 -Compress) -ceq ($afterHashes|ConvertTo-Json -Depth 5 -Compress))
Check 'source-remained-unchanged-during-test' { Assert-True $sourceUnchanged 'Source changed during target-user test.' }

$failed=@($checks|Where-Object{-not $_.passed})
$receipt=[ordered]@{
    schema_version='yime-rime-pime-target-user-source-fixture-v1'
    passed=($failed.Count -eq 0)
    checks_run=$checks.Count
    failures=$failed.Count
    checks=$checks
    source_sha256=$beforeHashes
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    powershell_edition=$PSVersionTable.PSEdition
    powershell_version=$PSVersionTable.PSVersion.ToString()
    source_unchanged=$sourceUnchanged
    actual_elevation_executed=$false
    actual_installer_or_uninstaller_executed=$false
    actual_registry_or_profile_mutation_executed=$false
    actual_process_stop_or_start_executed=$false
    real_user_registry_or_data_read=$false
    source_target_sid_wiring_passed=($failed.Count -eq 0)
    native_uac_and_registered_profile_acceptance_passed=$false
    dp1_full_implementation_passed=$false
    dp2_physical_acceptance_passed=$false
}
$receiptPath=Join-Path $output 'result.json'
$receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $receiptPath -Encoding UTF8
if($failed.Count){
    Write-Host "FAIL: $($failed.Count) of $($checks.Count) target-user source/fixture checks failed. Evidence: $receiptPath"
    exit 1
}
Write-Host "PASS: $($checks.Count) target-user source/fixture checks passed without OS mutation. Evidence: $receiptPath"
