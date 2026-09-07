[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot, [switch]$StaticOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-rime-maint-[a-zA-Z0-9-]+$' -or (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-rime-maint-* fixture root.'
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Maintenance evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
New-Item -ItemType Directory -Path $output | Out-Null
$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $checks.Add([ordered]@{name=$Name;passed=$true}) }
    catch { $checks.Add([ordered]@{name=$Name;passed=$false;reason=$_.Exception.Message}) }
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Must-Reject([scriptblock]$Body) {
    $rejected=$false; try { & $Body | Out-Null } catch { $rejected=$true }
    Assert-True $rejected 'Expected fail-closed rejection.'
}
$files=@('tools/dev-stop-pime.ps1','tools/dev-install.ps1','tools/dev-uninstall.ps1','installer/installer.nsi',
    'tools/dual-product/rime-pime-ownership.ps1','tools/dual-product/rime-pime-directed-stop-contract.ps1',
    'tools/dual-product/invoke-rime-pime-maintenance.ps1','tools/dual-product/rime-pime-package-staging.ps1',
    'tools/dual-product/rime-pime-nsis-stage.ps1','go-backend/build.bat')
$source=@{}; foreach($relative in $files){$source[$relative]=Get-Content -LiteralPath (Join-Path $repo $relative) -Raw}
Check 'no-global-image-name-stop-or-blind-quit' {
    foreach($text in $source.Values) {
        Assert-True ($text -notmatch '/IM\s+PIMELauncher|\$runningLaunchers\s*\|\s*Stop-Process|PIMELauncher\.exe[^\r\n]*?/quit') 'Global/name-only termination or blind launcher quit remains.'
    }
}
Check 'dev-stop-exact-owned-helper' {
    Assert-True ($source['tools/dev-stop-pime.ps1'] -match 'Stop-YimePimeOwnedProcesses') 'Stop entry does not use the ownership helper.'
    Assert-True ($source['tools/dev-stop-pime.ps1'] -match 'exit 2') 'DLL-lock exit 2 was lost.'
}
Check 'dev-install-missing-helper-fails-closed' {
    Assert-True ($source['tools/dev-install.ps1'] -match 'Assert-YimePimeOwnedRoot') 'Install target is not identity-checked.'
    Assert-True ($source['tools/dev-install.ps1'] -match 'Invoke-YimePimeRequiredStopScript') 'Missing-helper fallback is not fail closed.'
}
Check 'dev-uninstall-validates-collected-and-deleted-roots' {
    Assert-True ($source['tools/dev-uninstall.ps1'] -match 'Assert-YimePimeOwnedRoot') 'Uninstall targets lack ownership checks.'
    Assert-True ($source['tools/dev-uninstall.ps1'] -notmatch 'function Stop-ProcessByPathPrefix') 'Unsafe private stop fallback remains.'
}
Check 'nsis-embeds-independent-helper-and-validates-before-old-cleanup' {
    $text=$source['installer/installer.nsi']
    $staging=$source['tools/dual-product/rime-pime-package-staging.ps1']
    $generator=$source['tools/dual-product/rime-pime-nsis-stage.ps1']
    Assert-True ($text.Contains('!insertmacro YimePimeStageOwnershipHelpers') -and
        $staging.Contains("'rime-pime-ownership.ps1'") -and
        $staging.Contains("'invoke-rime-pime-maintenance.ps1'") -and
        $generator.Contains("'rime-pime-ownership.ps1','rime-pime-target-user.ps1'") -and
        $generator.Contains("Add-RimePimeNsisMacro `$lines 'YimePimeStageOwnershipHelpers'")) 'NSIS helper is not self-contained.'
    $function=[regex]::Match($text,'(?s)Function uninstallOldVersion\s+(.*?)FunctionEnd').Groups[1].Value
    $installInit=[regex]::Match($text,'(?s)Function \.onInit\s+(.*?)FunctionEnd').Groups[1].Value
    $main=[regex]::Match($text,'(?s)Section \$\(SECTION_MAIN\) SecMain\s+(.*?)SectionEnd').Groups[1].Value
    Assert-True ($installInit -notmatch 'Call (?:uninstallOldVersion|stopRunningBackend)') 'Product maintenance still runs before license acceptance.'
    Assert-True ($function.Contains('In-place upgrade is not enabled') -and
        $function -notmatch '(?:/u /s|Call stopRunningBackend|RMDir|DeleteReg|\bFile\b)') `
        'Current-family upgrade is not a read-only fail-closed lane.'
    Assert-True ($main.IndexOf('Call uninstallOldVersion') -ge 0 -and
        $function.Contains('Call verifyStagedRegistrationAbsent') -and
        [regex]::Matches($main,'Call verifyStagedRegistrationAbsent').Count -ge 1 -and
        $main.LastIndexOf('Call verifyStagedRegistrationAbsent') -lt $main.IndexOf('SetOverwrite on')) `
        'Fresh install does not recheck vacancy immediately before payload writes.'
    Assert-True ($function -notmatch 'DeleteRegKey\s+HKLM\s+"\$\{LEGACY_PRODUCT_(?:UNINST|INSTALL)_KEY\}"') `
        'Old cleanup can still delete an unowned legacy marker family.'
    $uninstall=[regex]::Match($text,'(?s)Section "Uninstall"\s+(.*?)SectionEnd').Groups[1].Value
    Assert-True ($uninstall.IndexOf('Call un.verifyRegistrationOwnership') -ge 0 -and
        $uninstall.IndexOf('Call un.verifyRegistrationOwnership') -lt $uninstall.IndexOf('Call un.stopOwnedPime')) `
        'Uninstall registration/root verification does not precede process mutation.'
    Assert-True ($text.Contains('Function un.stageTrustedRegistrationTools') -and
        $uninstall -notmatch 'RunCheckedRegistrationCommand[^\r\n]+\$INSTDIR\\') `
        'Privileged uninstall still executes replaceable installed registration helpers.'
}
Check 'developer-lock-flow-retained-and-product-upgrade-deferred' {
    Assert-True ($source['tools/dev-install.ps1'] -match '-AllowLocked') 'Locked DLL copying lost.'
    Assert-True ($source['tools/dev-uninstall.ps1'] -match '\$KeepInstallRoot = \$true') 'In-place uninstall fallback lost.'
    $macro=[regex]::Match($source['installer/installer.nsi'],
        '(?s)!macro InstallTextServiceDll\s+.*?(!macroend)').Value
    Assert-True ($macro.Contains('Only a vacant fresh root reaches this macro') -and
        $macro -notmatch '(?:Rename|Delete) /REBOOTOK') `
        'Fresh-only NSIS still permits deferred replacement of mapped old DLL bytes.'
}
Check 'owned-stop-uses-directed-contract-without-force-or-broadcast' {
    Assert-True ($source['tools/dual-product/rime-pime-ownership.ps1'] -notmatch '(?m)^\s*(Stop-Process|Wait-Process|Start-Process|& .*?/quit)\b') 'Mutation in quiescent admission helper.'
    Assert-True ($source['tools/dual-product/rime-pime-directed-stop-contract.ps1'] -notmatch '(?i)\bStop-Process\b|\btaskkill(?:\.exe)?\b|PIMELauncher2_QuitEvent') 'Directed helper uses force/global quit.'
    Assert-True ($source['tools/dual-product/rime-pime-ownership.ps1'] -match 'Invoke-YimePimeDirectedStop') 'Running owned process is not routed to the bound contract.'
}
Check 'uninstall-selects-only-explicit-root-and-keeps-legacy-markers' {
    $text=$source['tools/dev-uninstall.ps1']
    Assert-True ($text -match 'Get-InstallRootsForMaintenance -SelectedRoot \$InstallRoot') 'Explicit root selection absent.'
    Assert-True ($text -notmatch '\$LegacyDefaultInstallRoot|\$legacyInstallRootFromRegistry|Remove-RegistryTree -Path "HKLM:.*\\PIME"') 'Unproven legacy root or key is still maintained.'
}
foreach($relative in $files | Where-Object { $_ -like '*.ps1' }) {
    Check ('powershell-parse-'+$relative) {
        $parseTokens=$null;$parseErrors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($source[$relative],[ref]$parseTokens,[ref]$parseErrors)
        Assert-True ($parseErrors.Count -eq 0) 'PowerShell parse failed.'
    }
}

if(-not $StaticOnly) {
    . (Join-Path $PSScriptRoot 'rime-pime-ownership.ps1')
    $fixtureSid='S-1-5-21-100-200-300-1001'
    function Get-YimePimeCurrentSid { return $fixtureSid }
    function New-FixtureProduct([string]$Name,[string]$Guid='{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}') {
        $root=Join-Path $output $Name
        $markerDir=Join-Path $root 'go-backend\input_methods\yime'
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $markerDir 'ime.json'),('{"guid":"'+$Guid+'"}'))
        [IO.File]::WriteAllText((Join-Path $root 'PIMELauncher.exe'),'DP1 FAKE NONEXECUTABLE PAYLOAD')
        return $root
    }
    $rimeRoot=New-FixtureProduct 'marked custom install'
    $coreRoot=New-FixtureProduct 'YimeCore Experimental Trial' '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
    $wrongRoot=New-FixtureProduct 'foreign marker' '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
    $emptyRoot=Join-Path $output 'empty new'; New-Item -ItemType Directory -Path $emptyRoot | Out-Null
    $absentRoot=Join-Path $output 'not installed'
    $unknownRoot=Join-Path $output 'unknown'; New-Item -ItemType Directory -Path $unknownRoot | Out-Null
    [IO.File]::WriteAllText((Join-Path $unknownRoot 'unknown.txt'),'NONPRIVATE FIXTURE')
    # Load only three selected function ASTs, never the uninstall entry body.
    $parseTokens=$null;$parseErrors=$null
    $uninstallAst=[Management.Automation.Language.Parser]::ParseInput($source['tools/dev-uninstall.ps1'],[ref]$parseTokens,[ref]$parseErrors)
    foreach($functionName in @('Add-InstallRootCandidate','Get-InstallRootsForMaintenance','Remove-InstallTree')) {
        $selected=@($uninstallAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$false))
        if($selected.Count -ne 1){throw 'Required unique uninstall function missing.'}
        . ([scriptblock]::Create($selected[0].Extent.Text))
    }
    Check 'actual-root-selection-ignores-foreign-implicit-legacy' {
        $LegacyDefaultInstallRoot=$wrongRoot;$legacyInstallRootFromRegistry=$unknownRoot
        $roots=Get-InstallRootsForMaintenance $rimeRoot
        Assert-True ($roots.Count -eq 1 -and $roots[0] -eq $rimeRoot) 'Foreign implicit root became dependency.'
        foreach($root in @($wrongRoot,$unknownRoot,$absentRoot)){Must-Reject {Get-InstallRootsForMaintenance $root}}
    }
    Check 'actual-remove-function-rejects-foreign-before-mocked-delete' {
        $script:fixtureDeletes=@()
        function Remove-Item { param($LiteralPath,[switch]$Recurse,[switch]$Force,$ErrorAction) $script:fixtureDeletes+=$LiteralPath }
        foreach($root in @($wrongRoot,$unknownRoot,$coreRoot)){Must-Reject {Remove-InstallTree $root}}
        Assert-True ($script:fixtureDeletes.Count -eq 0) 'Foreign root reached deletion.'
        Remove-InstallTree $rimeRoot
        Assert-True ($script:fixtureDeletes.Count -eq 1 -and $script:fixtureDeletes[0] -eq $rimeRoot) 'Owned removal branch did not reach exact mocked path.'
    }
    Check 'exact-process-inventory-matches-actual-build-destinations' {
        $expected=@((Join-Path $rimeRoot 'PIMELauncher.exe'))
        foreach($match in [regex]::Matches($source['go-backend/build.bat'],'(?m)^set "[A-Z_]+_EXE=%PACKAGE_DIR%\\([^"\r\n]+\.exe)"')) {
            $expected+=Join-Path $rimeRoot ('go-backend\'+$match.Groups[1].Value)
        }
        foreach($match in [regex]::Matches($source['go-backend/build.bat'],'(?m)^\s*copy /Y [^\r\n]+ "%PACKAGE_DIR%\\([^"\r\n]+\.exe)"')) {
            $expected+=Join-Path $rimeRoot ('go-backend\'+$match.Groups[1].Value)
        }
        $actual=@(Get-YimePimeExecutablePaths $rimeRoot)
        Assert-True ($expected.Count -eq 15 -and @(Compare-Object ($expected | Sort-Object -Unique) ($actual | Sort-Object -Unique)).Count -eq 0) 'Published executable ownership inventory drifted.'
    }
    Check 'marked-custom-root-accepted' { Assert-True ((Assert-YimePimeOwnedRoot $rimeRoot).identity -eq 'rime-pime-yime-profile') 'Marked custom root rejected.' }
    Check 'empty-and-absent-new-install-accepted' {
        Assert-True ((Assert-YimePimeOwnedRoot $emptyRoot -AllowNew).identity -eq 'new-empty') 'Empty target rejected.'
        Assert-True (-not (Assert-YimePimeOwnedRoot $absentRoot -AllowNew).exists) 'Absent target rejected.'
    }
    Check 'core-foreign-marker-and-unknown-root-rejected' {
        foreach($root in @($coreRoot,$wrongRoot,$unknownRoot)){Must-Reject { Assert-YimePimeOwnedRoot $root -AllowNew }}
    }
    Check 'broad-and-noncanonical-targets-rejected' {
        foreach($root in @('C:\',($rimeRoot+'\..'),($rimeRoot+'\file:ads'),($rimeRoot+'.'),($rimeRoot+'\NUL'),('\\?\'+$rimeRoot),($rimeRoot+'\*'))){Must-Reject {Assert-YimePimeOwnedRoot $root -AllowNew}}
        Must-Reject {Assert-YimePimeOwnedRoot ([Environment]::GetFolderPath('UserProfile')) -AllowNew}
    }
    Check 'wrong-target-sid-rejected' { Must-Reject {Invoke-YimePimeMaintenanceGuard ValidateExisting $rimeRoot 'S-1-5-21-100-200-300-2002'} }
    $script:fixtureRecords=@(); $script:fixtureProcesses=@{}; $script:stopped=@(); $script:waited=@(); $script:ownerFailure=$false
    function Get-CimInstance { param($ClassName,$ErrorAction) if($ClassName -ne 'Win32_Process'){throw 'Unexpected CIM request'}; return $script:fixtureRecords }
    function Get-Process { param($Id,$ErrorAction) if(-not $script:fixtureProcesses.ContainsKey([int]$Id)){throw 'Unexpected real process lookup'};return $script:fixtureProcesses[[int]$Id] }
    function Invoke-CimMethod { param($InputObject,$MethodName,$ErrorAction) if($MethodName -ne 'GetOwnerSid'){throw 'Unexpected CIM method'};return [pscustomobject]@{ReturnValue=$(if($script:ownerFailure){1}else{0});Sid=$InputObject.OwnerSid} }
    function Stop-Process { param($InputObject,[switch]$Force,$ErrorAction) if(-not $InputObject -or -not $Force){throw 'Unbound process stop'};$script:stopped+=$InputObject.Id }
    function Wait-Process { param($InputObject,$Timeout,$ErrorAction) if($Timeout -ne 3){throw 'Unexpected wait budget'};$script:waited+=$InputObject.Id }
    function Seed-Process([int]$Id,[string]$Path,[string]$Sid=$fixtureSid) {
        $time=[datetime]'2026-09-05T12:00:00Z'
        $script:fixtureRecords+=[pscustomobject]@{ProcessId=$Id;ExecutablePath=$Path;CreationDate=$time;OwnerSid=$Sid}
        $script:fixtureProcesses[$Id]=[pscustomobject]@{Id=$Id;Path=$Path;Handle=123;StartTime=$time}
    }
    function Clear-Processes { $script:fixtureRecords=@();$script:fixtureProcesses=@{};$script:stopped=@();$script:waited=@();$script:ownerFailure=$false }
    Check 'every-shipped-tool-alone-blocks-maintenance-without-force' {
        foreach($path in Get-YimePimeExecutablePaths $rimeRoot) {
            Clear-Processes;Seed-Process 101 $path
            Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
            Assert-True ($script:stopped.Count -eq 0) 'Tool-only live process was force stopped.'
        }
    }
    Check 'relevant-unreadable-image-fails-closed-unrelated-image-ignored' {
        foreach($path in Get-YimePimeExecutablePaths $rimeRoot) {
            Clear-Processes
            $script:fixtureRecords=@([pscustomobject]@{Name=[IO.Path]::GetFileName($path);ExecutablePath=$null;ProcessId=101})
            Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
            Assert-True ($script:stopped.Count -eq 0) 'Unreadable process was stopped.'
        }
        Clear-Processes
        $script:fixtureRecords=@([pscustomobject]@{Name='unrelated-fixture.exe';ExecutablePath=$null;ProcessId=102})
        Assert-True ((Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid) -eq 0) 'Unrelated image became product dependency.'
    }
    Check 'exact-image-and-sid-only-no-peer-product-required' {
        Clear-Processes
        Seed-Process 102 (Join-Path $coreRoot 'bin\YimeBroker.exe')
        Seed-Process 103 (Join-Path ($rimeRoot+'-other') 'PIMELauncher.exe')
        Seed-Process 104 (Join-Path $rimeRoot 'nested\PIMELauncher.exe')
        Assert-True ((Stop-YimePimeOwnedProcesses @($rimeRoot,$absentRoot) $fixtureSid) -eq 0) 'Foreign product blocked independent admission.'
        Assert-True ($script:stopped.Count -eq 0 -and $script:waited.Count -eq 0) 'Foreign/name-prefix process was stopped.'
        Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe')
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot,$absentRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Running product was forcibly stopped without graceful protocol.'
    }
    Check 'foreign-sid-rejects-whole-stop-batch-before-any-stop' {
        Clear-Processes; Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe'); Seed-Process 102 (Join-Path $rimeRoot 'go-backend\server.exe') 'S-1-5-21-100-200-300-2002'
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Partial stop before owner validation.'
    }
    Check 'all-roots-validated-before-any-stop' {
        Clear-Processes; Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe')
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot,$wrongRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Partial stop before root validation.'
    }
    Check 'owner-query-error-fails-closed' {
        Clear-Processes; Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe');$script:ownerFailure=$true
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Stopped without owner evidence.'
    }
    Check 'reused-pid-or-image-change-fails-closed' {
        Clear-Processes; Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe')
        $script:fixtureProcesses[101].StartTime=$script:fixtureProcesses[101].StartTime.AddSeconds(1)
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Reused process was stopped.'
        Clear-Processes; Seed-Process 101 (Join-Path $rimeRoot 'PIMELauncher.exe');$script:fixtureProcesses[101].Path=Join-Path $coreRoot 'bin\YimeBroker.exe'
        Must-Reject {Stop-YimePimeOwnedProcesses @($rimeRoot) $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Changed image was stopped.'
    }
    Check 'missing-stop-helper-has-no-fallback' {
        Clear-Processes
        Must-Reject {Invoke-YimePimeRequiredStopScript -ScriptPath (Join-Path $output 'missing.ps1') -InstallRoots @($rimeRoot) -TargetUserSid $fixtureSid}
        Assert-True ($script:stopped.Count -eq 0) 'Missing helper ran fallback stop.'
    }
    Check 'stop-helper-lock-exit-2-preserved-other-failure-blocks' {
        foreach($code in @(0,2,3)) {
            $fake=Join-Path $output ('fake-stop-'+$code+'.ps1')
            [IO.File]::WriteAllText($fake,('param([string[]]$InstallRoots,[string]$TargetUserSid,[switch]$Quiet,[switch]$Auto)'+[Environment]::NewLine+'exit '+$code))
            if($code -eq 3){Must-Reject {Invoke-YimePimeRequiredStopScript $fake @($rimeRoot) $fixtureSid}}
            else {Assert-True ((Invoke-YimePimeRequiredStopScript $fake @($rimeRoot) $fixtureSid) -eq $code) 'Exit 2/0 contract changed.'}
        }
    }
    # Never let later additions accidentally reach real process mutation commands.
    Clear-Processes
}
$failed=@($checks | Where-Object { -not $_.passed })
$receipt=[ordered]@{schema_version='yime-rime-maintenance-isolated-v1';passed=($failed.Count -eq 0);static_only=[bool]$StaticOnly;
    checks=$checks.ToArray();checks_count=$checks.Count;failed_count=$failed.Count;
    actual_install_or_uninstall_executed=$false;real_stop_process_or_taskkill_executed=$false;
    registry_mutated=$false;production_or_user_data_read=$false;dp2_physical_acceptance_passed=$false}
$receipt.source_sha256=[ordered]@{}
foreach($relative in $files){$receipt.source_sha256[$relative]=(Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash.ToLowerInvariant()}
$receipt.source_sha256['tools/dual-product/test-rime-maintenance.ps1']=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$receipt.test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$receipt.powershell_edition=$PSVersionTable.PSEdition
$receipt.powershell_version=$PSVersionTable.PSVersion.ToString()
$receipt.dp1_full_implementation_passed=$false
$receipt.maintenance_scope='directed-source-wired-synthetic-only-installed-live-acceptance-pending'
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
Write-Output "DP1 Rime maintenance fixtures: $($checks.Count) checks; $($failed.Count) failed; evidence $output"
if($failed.Count){exit 1}
