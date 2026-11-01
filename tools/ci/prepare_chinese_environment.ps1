# Run only through tools/powershell/run_checked.py --edition ps5.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Prepare','Restore','Verify')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$LedgerDirectory,
    [Parameter(Mandatory=$true)][string]$QueryExecutable
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Tip = '0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA038EC515D7}'
$Schema = 'chinese-environment-ledger-v1'
$lock = $null
$ledger = $null
$result = [ordered]@{ schema='chinese-environment-result-v1'; mode=$Mode; status='error'; reason='not-started'; mutationAttempted=$false; configurationAppended=$false; warningCount=0; observation=$null; scope='user-language-defaults-and-observed-pinyin-profile-only'; componentServicingRollbackClaimed=$false }
$exitCode = 4
function Json($value) { ConvertTo-Json -InputObject $value -Depth 20 -Compress }
function Same($a, $b) { return (Json $a) -ceq (Json $b) }
function Save-Json([string]$path, $value) {
    # Durable write-ahead state, same-directory atomic replacement, no partial ledger.
    $temporary = $path + '.tmp'
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes((Json $value))
    $stream = New-Object System.IO.FileStream($temporary, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary,$path,$null) } else { [IO.File]::Move($temporary,$path) }
}
function Language-Snapshot($languages) {
    return ,@($languages | ForEach-Object {
        [ordered]@{ languageTag=[string]$_.LanguageTag; inputMethodTips=@($_.InputMethodTips | ForEach-Object { [string]$_ }); handwriting=[bool]$_.Handwriting; spellchecking=[bool]$_.Spellchecking }
    })
}
function Typed-Languages($snapshot) {
    $typed = New-WinUserLanguageList -Language ([string]$snapshot[0].languageTag)
    $typed.Clear()
    foreach ($item in $snapshot) {
        $one = New-WinUserLanguageList -Language ([string]$item.languageTag)
        $entry = $one[0]
        $entry.InputMethodTips.Clear()
        foreach ($inputTip in $item.inputMethodTips) { $entry.InputMethodTips.Add([string]$inputTip) }
        $entry.Handwriting = [bool]$item.handwriting
        $entry.Spellchecking = [bool]$item.spellchecking
        $typed.Add($entry)
    }
    if (-not (Same (Language-Snapshot $typed) @($snapshot))) { throw 'typed-language-roundtrip-mismatch' }
    # Preserve List<WinUserLanguage>, not pipeline-unrolled entries or deserialized CLIXML.
    return ,$typed
}
function Defaults-Snapshot {
    $ime = Get-WinDefaultInputMethodOverride
    $ui = Get-WinUILanguageOverride
    return [ordered]@{ inputTip= if ($null -eq $ime) { $null } else { [string]$ime.InputMethodTip }; uiLanguage= if ($null -eq $ui) { $null } else { [string]$ui.Name }; systemLocale=[string](Get-WinSystemLocale).Name; culture=[string](Get-Culture).Name }
}
function Native-Observation {
    # Preserve partial blocked JSON/stage; failed verification is not missing-component proof.
    $evidence = [ordered]@{ exitCode=$null; query=$null; verified=$false; verificationReason='query-failed'; componentSha256=$null; signatureStatus=$null; signerSubject=$null }
    try {
        $raw = & $QueryExecutable
        $evidence.exitCode = $LASTEXITCODE
        $q = ($raw -join "`n") | ConvertFrom-Json
        $evidence.query = $q
        if ($evidence.exitCode -ne 0) { $evidence.verificationReason='native-query-blocked-or-failed'; return $evidence }
        if ($q.schema -cne 'chinese-input-component-query-v1' -or $q.scope -cne 'readonly-component-and-language' -or $q.status -cne 'complete' -or $q.code -ne 0 -or $q.registrationView -cne 'native-x64' -or $q.expectedTip -cne $Tip -or $q.profileRegistered -ne $true -or $q.componentBinaryPresent -ne $true -or $null -eq $q.profileEnabled -or $null -eq $q.profileActive) { $evidence.verificationReason='native-query-contract-or-prerequisite-failed'; return $evidence }
        $binary = [IO.Path]::GetFullPath([string]$q.componentBinaryPath)
        $system = [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32')) + [IO.Path]::DirectorySeparatorChar
        if (-not $binary.StartsWith($system,[StringComparison]::OrdinalIgnoreCase)) { $evidence.verificationReason='component-outside-system32'; return $evidence }
        $file = Get-Item -LiteralPath $binary
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $evidence.verificationReason='component-not-regular-file'; return $evidence }
        $signature = Get-AuthenticodeSignature -LiteralPath $binary
        $evidence.signatureStatus = [string]$signature.Status
        if ($null -ne $signature.SignerCertificate) { $evidence.signerSubject=[string]$signature.SignerCertificate.Subject }
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { $evidence.verificationReason='component-microsoft-signature-unverified'; return $evidence }
        $evidence.componentSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
        $evidence.verified=$true; $evidence.verificationReason='verified-existing-component'
    } catch { $evidence.verificationReason='query-or-signature-read-failed' }
    return $evidence
}
function Snapshot {
    return [ordered]@{ languages=(Language-Snapshot (Get-WinUserLanguageList)); defaults=(Defaults-Snapshot); native=(Native-Observation) }
}
function Stable-Native($native) {
    # HKL/TSF/active may be process-local; include profileActive separately in observed comparison.
    return [ordered]@{ profileRegistered=$native.query.profileRegistered; profileEnabled=$native.query.profileEnabled; profileActive=$native.query.profileActive; componentBinaryPath=$native.query.componentBinaryPath; componentSha256=$native.componentSha256; signatureStatus=$native.signatureStatus; signerSubject=$native.signerSubject }
}
function Baseline-Matches($current) {
    if (-not $current.native.verified -or -not $ledger.baseline.native.verified) { return $false }
    return (Same @($current.languages) @($ledger.baseline.languages)) -and (Same $current.defaults $ledger.baseline.defaults) -and (Same (Stable-Native $current.native) (Stable-Native $ledger.baseline.native))
}
function Assert-OwnerDead {
    if ([int]$ledger.ownerPid -le 0) { throw 'invalid-owner-identity' }
    try { $owner = [Diagnostics.Process]::GetProcessById([int]$ledger.ownerPid) }
    catch [ArgumentException] { return } # Documented no-process result only.
    catch { throw 'owner-liveness-unknown' }
    try {
        $start = $owner.StartTime.ToUniversalTime().ToString('o')
        if ($start -ceq $ledger.ownerStartUtc) { throw 'prepare-owner-still-alive' }
        # Different start time proves PID reuse, not the original writer.
    } finally { $owner.Dispose() }
}

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) { throw 'requires-native-x64-windows-powershell-5' }
    if (-not [IO.Path]::IsPathRooted($LedgerDirectory) -or -not [IO.Path]::IsPathRooted($QueryExecutable)) { throw 'absolute-paths-required' }
    $LedgerDirectory = [IO.Path]::GetFullPath($LedgerDirectory)
    $QueryExecutable = [IO.Path]::GetFullPath($QueryExecutable)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($Mode -eq 'Prepare') {
        if (Test-Path -LiteralPath $LedgerDirectory) { throw 'ledger-already-exists-no-retry' }
        [void](New-Item -ItemType Directory -Path $LedgerDirectory -ErrorAction Stop)
    } elseif (-not (Test-Path -LiteralPath $LedgerDirectory -PathType Container)) { throw 'ledger-missing-no-restore-authority' }
    $lock = New-Object IO.FileStream((Join-Path $LedgerDirectory 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $ledgerPath = Join-Path $LedgerDirectory 'ledger.json'
    $queryHash = (Get-FileHash -LiteralPath $QueryExecutable -Algorithm SHA256).Hash
    if ($Mode -eq 'Prepare') {
        if (Test-Path -LiteralPath $ledgerPath) { throw 'ledger-already-exists-no-retry' }
        $baseline = Snapshot
        $owner = Get-Process -Id $PID
        $ledger = [ordered]@{ schema=$Schema; machine=$env:COMPUTERNAME; sid=$sid; queryPath=$QueryExecutable; querySha256=$queryHash; ownerPid=$PID; ownerStartUtc=$owner.StartTime.ToUniversalTime().ToString('o'); baseline=$baseline; mutationAttempted=$false; restoreAttempted=$false }
        Save-Json $ledgerPath $ledger
        $result.observation = $baseline
        if (-not $baseline.native.verified) { throw 'native-query-blocked-or-failed' }
        if ($baseline.languages.Count -lt 1 -or $baseline.languages[0].languageTag -notmatch '^en-') { throw 'english-first-baseline-required' }
        if (@($baseline.languages | Where-Object { $_.languageTag -ieq 'zh-CN' }).Count -ne 0) { throw 'zh-CN-already-listed-no-append' }
        $typed = Typed-Languages $baseline.languages
        $zh = New-WinUserLanguageList -Language 'zh-CN'
        $zh[0].InputMethodTips.Clear()
        $zh[0].InputMethodTips.Add($Tip)
        $typed.Add($zh[0])
        $ledger.mutationAttempted = $true
        Save-Json $ledgerPath $ledger
        $setterWarnings = @()
        Set-WinUserLanguageList -LanguageList $typed -Force -WarningVariable setterWarnings -WarningAction Continue
        $result.warningCount = @($setterWarnings).Count
        if ($result.warningCount -gt 0) { throw 'language-setter-warning-stop' }
        $after = Snapshot
        $result.observation = $after
        $result.configurationAppended = Same @($after.languages) (Language-Snapshot $typed)
        if (-not $after.native.verified) { throw 'native-query-blocked-or-failed' }
        if (-not (Same $after.defaults $baseline.defaults)) { throw 'defaults-changed-restore-required' }
        if (-not (Same @($after.languages) (Language-Snapshot $typed))) { throw 'unexpected-language-list-restore-required' }
        if ($after.native.query.actualHklLanguageHint -ne 2052 -or $after.native.query.actualTsfLanguage -ne 2052) {
            $result.status='blocked'; $result.reason='actual-hkl-or-tsf-not-0804'; $exitCode=3
        } else { $result.status='prepared'; $result.reason='actual-hkl-and-tsf-0804-observed'; $exitCode=0 }
    } else {
        $ledger = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
        if ($ledger.schema -cne $Schema -or $ledger.machine -cne $env:COMPUTERNAME -or $ledger.sid -cne $sid -or $ledger.queryPath -cne $QueryExecutable -or $ledger.querySha256 -cne $queryHash) { throw 'ledger-identity-mismatch' }
        Assert-OwnerDead
        if ($Mode -eq 'Restore' -and $ledger.mutationAttempted -and -not $ledger.restoreAttempted) {
            $typed = Typed-Languages $ledger.baseline.languages
            # Mark before every possible write: interruption never silently retries restoration.
            $ledger.restoreAttempted = $true
            Save-Json $ledgerPath $ledger
            $setterWarnings = @()
            Set-WinUserLanguageList -LanguageList $typed -Force -WarningVariable setterWarnings -WarningAction Continue
            $result.warningCount = @($setterWarnings).Count
            if ($result.warningCount -gt 0) { throw 'language-setter-warning-stop' }
            # Defaults remain observe-only, including null overrides. A remaining
            # change is cleanup-failed, never silently reset to a guessed default.
            # No Set-WinSystemLocale, profile disabling, restart or component rollback.
        }
        $current = Snapshot
        $result.observation = $current
        if (-not $ledger.mutationAttempted -and (Same @($current.languages) @($ledger.baseline.languages)) -and (Same $current.defaults $ledger.baseline.defaults)) { $result.status='unchanged-no-mutation'; $result.reason='no-script-settings-write-observed-defaults-and-list-match'; $exitCode=0 }
        elseif (Baseline-Matches $current) { $result.status='verified'; $result.reason='observed-baseline-fields-match'; $exitCode=0 }
        else { $result.status='cleanup-failed'; $result.reason='observed-baseline-fields-differ'; $exitCode=4 }
    }
} catch {
    # Fixed messages only: do not emit arbitrary exception text/credentials/environment.
    $result.reason = 'operation-failed'
    $known = @('language-setter-warning-stop','invalid-owner-identity','owner-liveness-unknown','nullable-default-restore-not-supported-no-write','english-first-baseline-required','zh-CN-already-listed-no-append','actual-hkl-or-tsf-not-0804','defaults-changed-restore-required','unexpected-language-list-restore-required','prepare-owner-still-alive','native-query-blocked-or-failed','native-query-contract-or-prerequisite-failed','component-microsoft-signature-unverified','ledger-already-exists-no-retry','ledger-missing-no-restore-authority','ledger-identity-mismatch','typed-language-roundtrip-mismatch','requires-native-x64-windows-powershell-5','absolute-paths-required','component-outside-system32','component-not-regular-file')
    if ($known -contains $_.Exception.Message) { $result.reason = $_.Exception.Message }
    if ($Mode -eq 'Prepare' -and ($null -eq $ledger -or -not $ledger.mutationAttempted)) { $result.status='blocked'; $exitCode=3 }
    else { $result.status='cleanup-failed'; $exitCode=4 }
} finally {
    if ($null -ne $ledger) { $result.mutationAttempted = [bool]$ledger.mutationAttempted }
    # Workflow owns the sole finally Restore after its job tree is quiescent.
    if ($null -ne $lock) {
        try { Save-Json (Join-Path $LedgerDirectory ($Mode.ToLowerInvariant() + '-result.json')) $result } finally { $lock.Dispose() }
    }
}
Write-Output (Json $result)
exit $exitCode
