# Fixture-only durable transaction-journal helpers for DP1-I.
#
# Definitions only. Importing this file performs no I/O. Every exported writer
# requires a caller-created, repository-local DP1-I fixture root and rejects
# paths outside that root. This is deliberately not wired to the real product.

$script:RimePimeFixtureSchemas = [pscustomobject][ordered]@{
    RegistryState = 'yime-rime-pime-fixture-registry-state-v1'
    RemovalManifest = 'yime-rime-pime-fixture-removal-manifest-v1'
    Prepared = 'yime-rime-pime-fixture-journal-prepared-v1'
    Step = 'yime-rime-pime-fixture-journal-step-v1'
    Commit = 'yime-rime-pime-fixture-journal-commit-v1'
    Terminal = 'yime-rime-pime-fixture-journal-terminal-v1'
}
$script:RimePimeFixtureZeroSha256 = '0' * 64
$script:RimePimeFixtureLockText = "yime-rime-pime-fixture-journal-lock-v1`n"
$script:RimePimeFixtureRepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$script:RimePimeFixtureUtf8 = New-Object Text.UTF8Encoding($false,$true)
$script:RimePimeFixtureUtf8NoThrow = New-Object Text.UTF8Encoding($false)
$script:RimePimeFixtureAscii = New-Object Text.ASCIIEncoding
$script:RimePimeFixtureRegistryCatalog = @(
    [pscustomobject][ordered]@{ coordinate_id='machine-com-server-x86'; allowed_kind='String' },
    [pscustomobject][ordered]@{ coordinate_id='machine-com-server-native'; allowed_kind='String' },
    [pscustomobject][ordered]@{ coordinate_id='machine-profile-icon-index'; allowed_kind='DWord' },
    [pscustomobject][ordered]@{ coordinate_id='machine-product-root'; allowed_kind='ExpandString' },
    [pscustomobject][ordered]@{ coordinate_id='target-profile-enabled'; allowed_kind='DWord' },
    [pscustomobject][ordered]@{ coordinate_id='target-profile-metadata'; allowed_kind='MultiString' }
)

function Test-RimePimeFixtureInteger {
    param($Value)
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Assert-RimePimeFixtureExactProperties {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$Label
    )
    if ($null -eq $Value -or $null -eq $Value.PSObject) {
        throw "$Label is not an object."
    }
    $actual = [string[]]@($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actual.Count -ne $Names.Count) { throw "$Label has an open or incomplete schema." }
    foreach ($name in $Names) {
        if ($actual -cnotcontains $name) { throw "$Label has an open or incomplete schema." }
    }
}

function Assert-RimePimeFixtureBoolean {
    param($Value,[Parameter(Mandatory)][string]$Label)
    if ($Value -isnot [bool]) { throw "$Label must be Boolean." }
    return [bool]$Value
}

function Assert-RimePimeFixtureSha256 {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Label)
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Label is not a canonical SHA-256 digest." }
    return $Value
}

function Assert-RimePimeFixtureTimestamp {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -cnotmatch '^20[0-9]{2}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$') {
        throw 'Fixture timestamp is not canonical UTC.'
    }
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($Value,'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsed)) {
        throw 'Fixture timestamp is not valid UTC.'
    }
    return $Value
}

function Add-RimePimeFixtureCanonicalJsonValue {
    param(
        [Parameter(Mandatory)][Text.StringBuilder]$Builder,
        [AllowNull()]$Value
    )
    if ($null -eq $Value) { $null=$Builder.Append('null'); return }
    if ($Value -is [bool]) { $null=$Builder.Append($(if($Value){'true'}else{'false'})); return }
    if ($Value -is [string] -or $Value -is [char]) {
        $text=[string]$Value; $null=$Builder.Append('"')
        for ($i=0; $i -lt $text.Length; $i++) {
            $character=$text[$i]; $code=[int][char]$character
            if ($code -eq 8) { $null=$Builder.Append('\b'); continue }
            if ($code -eq 9) { $null=$Builder.Append('\t'); continue }
            if ($code -eq 10) { $null=$Builder.Append('\n'); continue }
            if ($code -eq 12) { $null=$Builder.Append('\f'); continue }
            if ($code -eq 13) { $null=$Builder.Append('\r'); continue }
            if ($code -eq 34) { $null=$Builder.Append('\"'); continue }
            if ($code -eq 92) { $null=$Builder.Append('\\'); continue }
            if ($code -lt 32) { $null=$Builder.Append(('\u{0:x4}' -f $code)); continue }
            if ([char]::IsHighSurrogate($character)) {
                if ($i+1 -ge $text.Length -or -not [char]::IsLowSurrogate($text[$i+1])) {
                    throw 'Canonical fixture JSON rejected an unpaired UTF-16 surrogate.'
                }
                $null=$Builder.Append($character); $i++; $null=$Builder.Append($text[$i]); continue
            }
            if ([char]::IsLowSurrogate($character)) {
                throw 'Canonical fixture JSON rejected an unpaired UTF-16 surrogate.'
            }
            $null=$Builder.Append($character)
        }
        $null=$Builder.Append('"'); return
    }
    if (Test-RimePimeFixtureInteger $Value) {
        $null=$Builder.Append(([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$Value)))
        return
    }
    if ($Value -is [float] -or $Value -is [double] -or $Value -is [decimal]) {
        throw 'Canonical fixture JSON accepts integer numeric values only.'
    }
    if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) {
        throw 'Canonical fixture JSON accepts timestamps as strings only.'
    }
    if ($Value -is [Collections.IDictionary]) {
        $keys=[string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys,[StringComparer]::Ordinal)
        $null=$Builder.Append('{'); $first=$true
        foreach ($key in $keys) {
            if (-not $first) { $null=$Builder.Append(',') }; $first=$false
            Add-RimePimeFixtureCanonicalJsonValue $Builder $key; $null=$Builder.Append(':')
            Add-RimePimeFixtureCanonicalJsonValue $Builder $Value[$key]
        }
        $null=$Builder.Append('}'); return
    }
    if ($Value -is [Collections.IEnumerable]) {
        $null=$Builder.Append('['); $first=$true
        foreach ($item in $Value) {
            if (-not $first) { $null=$Builder.Append(',') }; $first=$false
            Add-RimePimeFixtureCanonicalJsonValue $Builder $item
        }
        $null=$Builder.Append(']'); return
    }
    if ($null -ne $Value.PSObject) {
        $properties=@($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty','Property') })
        if ($properties.Count -eq 0) { throw 'Canonical fixture JSON rejected an unsupported object.' }
        $null=$Builder.Append('{'); $first=$true
        foreach ($property in $properties) {
            if (-not $first) { $null=$Builder.Append(',') }; $first=$false
            Add-RimePimeFixtureCanonicalJsonValue $Builder ([string]$property.Name)
            $null=$Builder.Append(':')
            Add-RimePimeFixtureCanonicalJsonValue $Builder $property.Value
        }
        $null=$Builder.Append('}'); return
    }
    throw 'Canonical fixture JSON rejected an unsupported value.'
}

function ConvertTo-RimePimeFixtureCanonicalJson {
    param([Parameter(Mandatory)]$Value)
    $builder = New-Object Text.StringBuilder
    Add-RimePimeFixtureCanonicalJsonValue $builder $Value
    return $builder.ToString()
}

function Get-RimePimeFixtureBytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-RimePimeFixtureObjectSha256 {
    param([Parameter(Mandatory)]$Value)
    $bytes=$script:RimePimeFixtureUtf8NoThrow.GetBytes((ConvertTo-RimePimeFixtureCanonicalJson $Value))
    return Get-RimePimeFixtureBytesSha256 $bytes
}

function ConvertFrom-RimePimeFixtureJson {
    param([Parameter(Mandatory)][string]$Text)
    $command=Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey('DateKind')) {
        return $Text | ConvertFrom-Json -DateKind String -ErrorAction Stop
    }
    return $Text | ConvertFrom-Json -ErrorAction Stop
}

function Test-RimePimeFixturePathStartsWith {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
    $rootWithSeparator=$Root.TrimEnd('\')+'\'
    return $Path.StartsWith($rootWithSeparator,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-RimePimeFixtureNoReparsePath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$StopRoot)
    $full=[IO.Path]::GetFullPath($Path)
    $stop=[IO.Path]::GetFullPath($StopRoot).TrimEnd('\')
    if ($full -ne $stop -and -not (Test-RimePimeFixturePathStartsWith $full $stop)) {
        throw 'Fixture path leaves its sealed root.'
    }
    $cursor=$full
    while ($true) {
        if ([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)) {
            if (([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Fixture path contains a reparse point.'
            }
        }
        if ($cursor -eq $stop) { break }
        $next=[IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrEmpty($next) -or $next.Length -ge $cursor.Length) {
            throw 'Fixture path root could not be established.'
        }
        $cursor=$next.TrimEnd('\')
    }
}

function Assert-RimePimeFixtureRoot {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FixtureRoot)
    $repo=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    if ($repo -ine $script:RimePimeFixtureRepoRoot) {
        throw 'Fixture repository root is not the helper-owned repository.'
    }
    $fixture=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
    if ([IO.Path]::GetFileName($fixture) -cne 'fixture') {
        throw 'Fixture root leaf must be fixture.'
    }
    $runRoot=[IO.Path]::GetDirectoryName($fixture)
    if ([IO.Path]::GetFileName($runRoot) -cnotmatch '^dp1-i-journal-[a-z0-9-]{1,80}$') {
        throw 'Fixture run root is not an immediate DP1-I output.'
    }
    $expectedParent=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($runRoot) -ine $expectedParent) {
        throw 'Fixture run root is outside the repository DP1-I output parent.'
    }
    if (-not [IO.Directory]::Exists($fixture)) { throw 'Fixture root must already exist.' }
    Assert-RimePimeFixtureNoReparsePath $fixture $repo
    return $fixture
}

function Assert-RimePimeFixtureContainedPath {
    param([Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$Path)
    $root=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path)
    if (-not (Test-RimePimeFixturePathStartsWith $full $root)) {
        throw 'Mutable fixture path leaves the fixture root.'
    }
    if ($full.IndexOf(':',3) -ge 0) { throw 'Mutable fixture path contains an alternate stream delimiter.' }
    Assert-RimePimeFixtureNoReparsePath $full $root
    return $full
}

function New-RimePimeFixtureDirectory {
    param([Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$Path)
    $null=Assert-RimePimeFixtureRoot $script:RimePimeFixtureRepoRoot $FixtureRoot
    $full=Assert-RimePimeFixtureContainedPath $FixtureRoot $Path
    if ([IO.File]::Exists($full)) { throw 'Fixture directory collides with a file.' }
    $null=[IO.Directory]::CreateDirectory($full)
    Assert-RimePimeFixtureNoReparsePath $full $FixtureRoot
    return $full
}

function New-RimePimeFixtureTransactionContext {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)][string]$CaseId
    )
    $fixture=Assert-RimePimeFixtureRoot $RepoRoot $FixtureRoot
    if ($CaseId -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Fixture case ID is not canonical.' }
    $cases=New-RimePimeFixtureDirectory $fixture (Join-Path $fixture 'cases')
    $caseRoot=Join-Path $cases $CaseId
    if ([IO.File]::Exists($caseRoot) -or [IO.Directory]::Exists($caseRoot)) {
        throw 'Fixture case must be fresh.'
    }
    $caseRoot=New-RimePimeFixtureDirectory $fixture $caseRoot
    $state=New-RimePimeFixtureDirectory $fixture (Join-Path $caseRoot 'state')
    $records=New-RimePimeFixtureDirectory $fixture (Join-Path $state 'records')
    $registry=New-RimePimeFixtureDirectory $fixture (Join-Path $caseRoot 'registry')
    $trusted=New-RimePimeFixtureDirectory $fixture (Join-Path $caseRoot 'trusted')
    $install=New-RimePimeFixtureDirectory $fixture (Join-Path $caseRoot 'install')
    $context=[pscustomobject][ordered]@{
        fixture_only=$true
        repo_root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
        fixture_root=$fixture
        case_id=$CaseId
        case_root=$caseRoot
        state_root=$state
        records_root=$records
        registry_root=$registry
        trusted_root=$trusted
        install_root=$install
    }
    Assert-RimePimeFixtureTransactionContext $context | Out-Null
    return $context
}

function Assert-RimePimeFixtureTransactionContext {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureExactProperties $Context @(
        'fixture_only','repo_root','fixture_root','case_id','case_root','state_root','records_root',
        'registry_root','trusted_root','install_root') 'Fixture transaction context'
    if ($Context.fixture_only -ne $true -or [string]$Context.case_id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
        throw 'Fixture transaction context identity is invalid.'
    }
    $repo=[IO.Path]::GetFullPath([string]$Context.repo_root).TrimEnd('\')
    $fixture=Assert-RimePimeFixtureRoot $repo ([string]$Context.fixture_root)
    $caseRoot=[IO.Path]::GetFullPath((Join-Path (Join-Path $fixture 'cases') ([string]$Context.case_id))).TrimEnd('\')
    $expected=[ordered]@{
        case_root=$caseRoot
        state_root=(Join-Path $caseRoot 'state')
        records_root=(Join-Path $caseRoot 'state\records')
        registry_root=(Join-Path $caseRoot 'registry')
        trusted_root=(Join-Path $caseRoot 'trusted')
        install_root=(Join-Path $caseRoot 'install')
    }
    foreach ($name in $expected.Keys) {
        if ([IO.Path]::GetFullPath([string]$Context.$name).TrimEnd('\') -ine
            [IO.Path]::GetFullPath([string]$expected[$name]).TrimEnd('\')) {
            throw 'Fixture transaction context path binding is invalid.'
        }
        $null=Assert-RimePimeFixtureContainedPath $fixture ([string]$Context.$name)
    }
    foreach ($name in @('case_root','state_root','records_root','registry_root','trusted_root')) {
        if (-not [IO.Directory]::Exists([string]$Context.$name)) {
            throw 'Fixture transaction context directory is absent.'
        }
    }
    if (-not [IO.Directory]::Exists([string]$Context.install_root) -and
        [IO.File]::Exists([string]$Context.install_root)) {
        throw 'Fixture install coordinate collides with a file.'
    }
    return $true
}

function Invoke-RimePimeFixtureFault {
    param([string]$FaultAt,[Parameter(Mandatory)][string]$Point)
    if (-not [string]::IsNullOrEmpty($FaultAt) -and $FaultAt -ceq $Point) {
        throw "Injected fixture persistence fault at $Point."
    }
}

function Write-RimePimeFixtureBytesCreateNew {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FaultAt,
        [Parameter(Mandatory)][string]$AfterFlushPoint
    )
    $null=Assert-RimePimeFixtureRoot $script:RimePimeFixtureRepoRoot $FixtureRoot
    $full=Assert-RimePimeFixtureContainedPath $FixtureRoot $Path
    $parent=[IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($parent)) { throw 'Durable fixture parent directory is absent.' }
    $stream=New-Object IO.FileStream($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try {
        $stream.Write($Bytes,0,$Bytes.Length)
        $stream.Flush($true)
        Invoke-RimePimeFixtureFault $FaultAt $AfterFlushPoint
    } finally {
        $stream.Dispose()
    }
}

function Write-RimePimeFixtureSealedJson {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FixtureRoot,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')]
        [string]$FaultAt=''
    )
    $null=Assert-RimePimeFixtureRoot $script:RimePimeFixtureRepoRoot $FixtureRoot
    $full=Assert-RimePimeFixtureContainedPath $FixtureRoot $Path
    $sidecar=Assert-RimePimeFixtureContainedPath $FixtureRoot ($full+'.sha256')
    if ([IO.File]::Exists($full) -or [IO.File]::Exists($sidecar)) {
        throw 'Durable fixture output already exists.'
    }
    $json=(ConvertTo-RimePimeFixtureCanonicalJson $Value)+"`n"
    $bytes=$script:RimePimeFixtureUtf8NoThrow.GetBytes($json)
    if ($bytes.Length -gt 1048576) { throw 'Durable fixture JSON exceeds one MiB.' }
    Write-RimePimeFixtureBytesCreateNew -Path $full -Bytes $bytes -FixtureRoot $FixtureRoot `
        -FaultAt $FaultAt -AfterFlushPoint 'after-json-flush'
    Invoke-RimePimeFixtureFault $FaultAt 'before-sidecar-create'
    $digest=Get-RimePimeFixtureBytesSha256 $bytes
    $sidecarText="$digest  $([IO.Path]::GetFileName($full))`n"
    $sidecarBytes=$script:RimePimeFixtureAscii.GetBytes($sidecarText)
    Write-RimePimeFixtureBytesCreateNew -Path $sidecar -Bytes $sidecarBytes -FixtureRoot $FixtureRoot `
        -FaultAt $FaultAt -AfterFlushPoint 'after-sidecar-flush'
    return [pscustomobject][ordered]@{ path=$full; sha256=$digest; bytes=[long]$bytes.Length }
}

function Read-RimePimeFixtureSealedJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FixtureRoot
    )
    $null=Assert-RimePimeFixtureRoot $script:RimePimeFixtureRepoRoot $FixtureRoot
    $full=Assert-RimePimeFixtureContainedPath $FixtureRoot $Path
    $sidecar=Assert-RimePimeFixtureContainedPath $FixtureRoot ($full+'.sha256')
    if (-not [IO.File]::Exists($full) -or -not [IO.File]::Exists($sidecar)) {
        throw 'Sealed fixture JSON pair is incomplete.'
    }
    if ((New-Object IO.FileInfo($full)).Length -gt 1048576 -or
        (New-Object IO.FileInfo($sidecar)).Length -gt 256) {
        throw 'Sealed fixture JSON pair exceeds its size bound.'
    }
    $jsonBytes=[IO.File]::ReadAllBytes($full)
    $sidecarBytes=[IO.File]::ReadAllBytes($sidecar)
    $sidecarText=$script:RimePimeFixtureAscii.GetString($sidecarBytes)
    $expectedName=[Regex]::Escape([IO.Path]::GetFileName($full))
    if ($sidecarText -cnotmatch "^([0-9a-f]{64})  $expectedName`n$") {
        throw 'Sealed fixture digest sidecar is not canonical.'
    }
    $digest=Get-RimePimeFixtureBytesSha256 $jsonBytes
    if ($digest -cne $Matches[1]) { throw 'Sealed fixture JSON digest mismatch.' }
    try { $jsonText=$script:RimePimeFixtureUtf8.GetString($jsonBytes) }
    catch { throw 'Sealed fixture JSON is not strict UTF-8.' }
    if (-not $jsonText.EndsWith("`n",[StringComparison]::Ordinal) -or $jsonText.EndsWith("`r`n",[StringComparison]::Ordinal)) {
        throw 'Sealed fixture JSON terminator is not canonical.'
    }
    try { $value=ConvertFrom-RimePimeFixtureJson $jsonText.Substring(0,$jsonText.Length-1) }
    catch { throw 'Sealed fixture JSON could not be parsed.' }
    $canonical=(ConvertTo-RimePimeFixtureCanonicalJson $value)+"`n"
    if ($canonical -cne $jsonText) { throw 'Sealed fixture JSON is not canonical.' }
    return [pscustomobject][ordered]@{ value=$value; sha256=$digest; bytes=[long]$jsonBytes.Length; path=$full }
}

function Open-RimePimeFixtureJournalLock {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $path=Assert-RimePimeFixtureContainedPath $Context.fixture_root (Join-Path $Context.state_root 'journal.lock')
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try {
        if ($stream.Length -eq 0) {
            $bytes=$script:RimePimeFixtureAscii.GetBytes($script:RimePimeFixtureLockText)
            $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true)
        } else {
            if ($stream.Length -gt 128) { throw 'Fixture journal lock anchor is invalid.' }
            $bytes=New-Object byte[] ([int]$stream.Length)
            $stream.Position=0; $read=$stream.Read($bytes,0,$bytes.Length)
            if ($read -ne $bytes.Length -or $script:RimePimeFixtureAscii.GetString($bytes) -cne $script:RimePimeFixtureLockText) {
                throw 'Fixture journal lock anchor is invalid.'
            }
        }
        return [pscustomobject][ordered]@{
            fixture_only=$true; case_id=$Context.case_id; path=$path; stream=$stream
        }
    } catch {
        $stream.Dispose(); throw
    }
}

function Close-RimePimeFixtureJournalLock {
    param([Parameter(Mandatory)]$Lock)
    Assert-RimePimeFixtureExactProperties $Lock @('fixture_only','case_id','path','stream') 'Fixture journal lock'
    if ($Lock.fixture_only -ne $true -or [string]$Lock.case_id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or
        $Lock.stream -isnot [IO.FileStream]) { throw 'Fixture journal lock object is invalid.' }
    $path=[IO.Path]::GetFullPath([string]$Lock.path)
    $stateRoot=[IO.Path]::GetDirectoryName($path)
    $caseRoot=[IO.Path]::GetDirectoryName($stateRoot)
    $casesRoot=[IO.Path]::GetDirectoryName($caseRoot)
    $fixtureRoot=[IO.Path]::GetDirectoryName($casesRoot)
    if ([IO.Path]::GetFileName($path) -cne 'journal.lock' -or
        [IO.Path]::GetFileName($stateRoot) -cne 'state' -or
        [IO.Path]::GetFileName($caseRoot) -cne [string]$Lock.case_id -or
        [IO.Path]::GetFileName($casesRoot) -cne 'cases' -or
        [IO.Path]::GetFullPath([string]$Lock.stream.Name) -ine $path) {
        throw 'Fixture journal lock path binding is invalid.'
    }
    $null=Assert-RimePimeFixtureRoot $script:RimePimeFixtureRepoRoot $fixtureRoot
    $Lock.stream.Dispose()
}

function Assert-RimePimeFixtureJournalLock {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $expected=[IO.Path]::GetFullPath((Join-Path $Context.state_root 'journal.lock'))
    if ($Lock.fixture_only -ne $true -or $Lock.case_id -cne $Context.case_id -or
        [IO.Path]::GetFullPath([string]$Lock.path) -ine $expected -or
        $null -eq $Lock.stream -or -not $Lock.stream.CanRead -or -not $Lock.stream.CanWrite) {
        throw 'A live fixture journal lock is required.'
    }
}

function Get-RimePimeFixtureRegistryCoordinateCatalog {
    return @($script:RimePimeFixtureRegistryCatalog | ForEach-Object {
        [pscustomobject][ordered]@{ coordinate_id=$_.coordinate_id; allowed_kind=$_.allowed_kind }
    })
}

function New-RimePimeFixtureRegistryRecord {
    param(
        [Parameter(Mandatory)][string]$CoordinateId,
        [Parameter(Mandatory)][ValidateSet('Absent','String','ExpandString','DWord','MultiString')][string]$ValueKind,
        [AllowNull()]$Value
    )
    $present=$ValueKind -cne 'Absent'
    $encoding=switch ($ValueKind) {
        'Absent' { 'none' }
        'DWord' { 'uint32-decimal' }
        'MultiString' { 'utf8-array' }
        default { 'utf8' }
    }
    return [pscustomobject][ordered]@{
        coordinate_id=$CoordinateId
        present=$present
        value_kind=$ValueKind
        value_encoding=$encoding
        value=$Value
    }
}

function Assert-RimePimeFixtureRegistryRecord {
    param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$CatalogRow)
    Assert-RimePimeFixtureExactProperties $Record @(
        'coordinate_id','present','value_kind','value_encoding','value') 'Fixture registry record'
    if ([string]$Record.coordinate_id -cne [string]$CatalogRow.coordinate_id) {
        throw 'Fixture registry coordinates are not the fixed catalog.'
    }
    $present=Assert-RimePimeFixtureBoolean $Record.present 'Fixture registry present flag'
    $kind=[string]$Record.value_kind
    if ($kind -cnotmatch '^(Absent|String|ExpandString|DWord|MultiString)$') {
        throw 'Fixture registry kind is not admitted.'
    }
    if ($kind -cne 'Absent' -and $kind -cne [string]$CatalogRow.allowed_kind) {
        throw 'Fixture registry kind is not admitted for the fixed coordinate.'
    }
    if ($kind -ceq 'Absent') {
        if ($present -or [string]$Record.value_encoding -cne 'none' -or $null -ne $Record.value) {
            throw 'Absent fixture registry value is not canonical.'
        }
        return
    }
    if (-not $present) { throw 'Present fixture registry value is not canonical.' }
    if ($kind -ceq 'DWord') {
        if ([string]$Record.value_encoding -cne 'uint32-decimal' -or
            $Record.value -isnot [string] -or [string]$Record.value -cnotmatch '^(0|[1-9][0-9]{0,9})$') {
            throw 'Fixture DWord is not canonical decimal text.'
        }
        $parsed=[uint64]0
        if (-not [uint64]::TryParse([string]$Record.value,[Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,[ref]$parsed) -or $parsed -gt [uint32]::MaxValue) {
            throw 'Fixture DWord is outside the UInt32 range.'
        }
        return
    }
    if ($kind -ceq 'MultiString') {
        if ([string]$Record.value_encoding -cne 'utf8-array' -or $Record.value -is [string] -or
            $Record.value -isnot [Collections.IEnumerable]) {
            throw 'Fixture MultiString is not a JSON array.'
        }
        $values=@($Record.value)
        if ($values.Count -gt 32) { throw 'Fixture MultiString exceeds its count bound.' }
        foreach ($item in $values) {
            if ($item -isnot [string] -or ($item.Length -gt 0 -and $item -cnotmatch '^fixture:[a-z0-9][a-z0-9._-]{0,63}$')) {
                throw 'Fixture MultiString contains non-fixture text.'
            }
        }
        return
    }
    if ([string]$Record.value_encoding -cne 'utf8' -or $Record.value -isnot [string] -or
        [string]$Record.value -cnotmatch '^fixture:[a-z0-9][a-z0-9._-]{0,63}$') {
        throw 'Fixture registry string contains non-fixture text.'
    }
}

function New-RimePimeFixtureRegistryState {
    param(
        [Parameter(Mandatory)][string]$SyntheticTargetUserSid,
        [Parameter(Mandatory)][object[]]$Records
    )
    $value=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.RegistryState
        fixture_only=$true
        product='rime-pime'
        synthetic_target_user_sid=$SyntheticTargetUserSid
        source='synthetic-json-only'
        contains_user_text=$false
        records=@($Records)
    }
    Assert-RimePimeFixtureRegistryState $value | Out-Null
    return $value
}

function Assert-RimePimeFixtureRegistryState {
    param([Parameter(Mandatory)]$State)
    Assert-RimePimeFixtureExactProperties $State @(
        'schema_version','fixture_only','product','synthetic_target_user_sid','source','contains_user_text','records') `
        'Fixture registry state'
    if ([string]$State.schema_version -cne $script:RimePimeFixtureSchemas.RegistryState -or
        $State.fixture_only -ne $true -or [string]$State.product -cne 'rime-pime' -or
        [string]$State.source -cne 'synthetic-json-only' -or $State.contains_user_text -ne $false) {
        throw 'Fixture registry state identity is invalid.'
    }
    if ([string]$State.synthetic_target_user_sid -cnotmatch '^S-1-5-21-100-200-300-[1-9][0-9]{0,8}$') {
        throw 'Fixture registry state does not use an admitted synthetic SID.'
    }
    $records=@($State.records)
    if ($records.Count -ne $script:RimePimeFixtureRegistryCatalog.Count) {
        throw 'Fixture registry state is not a complete fixed-coordinate snapshot.'
    }
    for ($i=0; $i -lt $records.Count; $i++) {
        Assert-RimePimeFixtureRegistryRecord $records[$i] $script:RimePimeFixtureRegistryCatalog[$i]
    }
    return $true
}

function Write-RimePimeFixtureRegistryState {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name
    )
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}\.json$') { throw 'Fixture registry snapshot name is not canonical.' }
    Assert-RimePimeFixtureRegistryState $State | Out-Null
    return Write-RimePimeFixtureSealedJson -Value $State -Path (Join-Path $Context.registry_root $Name) `
        -FixtureRoot $Context.fixture_root
}

function Read-RimePimeFixtureRegistryState {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Name)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}\.json$') { throw 'Fixture registry snapshot name is not canonical.' }
    $sealed=Read-RimePimeFixtureSealedJson -Path (Join-Path $Context.registry_root $Name) `
        -FixtureRoot $Context.fixture_root
    Assert-RimePimeFixtureRegistryState $sealed.value | Out-Null
    return $sealed
}

function ConvertTo-RimePimeFixtureRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 240 -or
        [IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or
        $Path -match '[<>:"|?*\x00-\x1f]') {
        throw 'Fixture manifest path is not canonical.'
    }
    $segments=@($Path.Split('/'))
    if ($segments.Count -gt 12) { throw 'Fixture manifest path exceeds its depth bound.' }
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.Length -gt 80 -or $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$') {
            throw 'Fixture manifest path has an inadmissible segment.'
        }
    }
    return ($segments -join '/')
}

function Get-RimePimeFixtureInstallPath {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$RelativePath)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $relative=ConvertTo-RimePimeFixtureRelativePath $RelativePath
    $root=[IO.Path]::GetFullPath([string]$Context.install_root).TrimEnd('\')
    $full=[IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/','\')))
    if (-not (Test-RimePimeFixturePathStartsWith $full $root)) {
        throw 'Fixture manifest path leaves the install fixture.'
    }
    $null=Assert-RimePimeFixtureContainedPath $Context.fixture_root $full
    return $full
}

function Write-RimePimeFixtureInstallFile {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][byte[]]$Bytes
    )
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    if ($Bytes.Length -gt 16777216) { throw 'Fixture install file exceeds its size bound.' }
    $relative=ConvertTo-RimePimeFixtureRelativePath $RelativePath
    $path=Get-RimePimeFixtureInstallPath $Context $relative
    $parent=[IO.Path]::GetDirectoryName($path)
    if (-not [IO.Directory]::Exists($parent)) {
        $null=New-RimePimeFixtureDirectory $Context.fixture_root $parent
    }
    Write-RimePimeFixtureBytesCreateNew -Path $path -Bytes $Bytes -FixtureRoot $Context.fixture_root `
        -FaultAt '' -AfterFlushPoint 'fixture-file-flushed'
    return [pscustomobject][ordered]@{
        path=$relative; bytes=[int64]$Bytes.Length; sha256=(Get-RimePimeFixtureBytesSha256 $Bytes)
    }
}

function Assert-RimePimeFixtureRemovalManifest {
    param([Parameter(Mandatory)]$Manifest)
    Assert-RimePimeFixtureExactProperties $Manifest @(
        'schema_version','fixture_only','product','manifest_id','contains_user_text','files') `
        'Fixture removal manifest'
    if ([string]$Manifest.schema_version -cne $script:RimePimeFixtureSchemas.RemovalManifest -or
        $Manifest.fixture_only -ne $true -or [string]$Manifest.product -cne 'rime-pime' -or
        $Manifest.contains_user_text -ne $false -or [string]$Manifest.manifest_id -cnotmatch '^[0-9a-f]{32}$') {
        throw 'Fixture removal manifest identity is invalid.'
    }
    $files=@($Manifest.files)
    if ($files.Count -lt 3 -or $files.Count -gt 128) { throw 'Fixture removal manifest file count is invalid.' }
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $previous=$null; $installedManifestCount=0; $specialCount=0; $total=[int64]0
    foreach ($file in $files) {
        Assert-RimePimeFixtureExactProperties $file @('path','bytes','sha256','removal_class') 'Fixture removal file'
        $path=ConvertTo-RimePimeFixtureRelativePath ([string]$file.path)
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$path) -ge 0) {
            throw 'Fixture removal manifest paths are not unique ordinal order.'
        }
        $previous=$path
        if (-not $seen.Add($path)) { throw 'Fixture removal manifest has a case-insensitive collision.' }
        if (-not (Test-RimePimeFixtureInteger $file.bytes) -or [int64]$file.bytes -lt 0 -or
            [int64]$file.bytes -gt 16777216) { throw 'Fixture removal file size is invalid.' }
        $total+=[int64]$file.bytes
        if ($total -gt 67108864) { throw 'Fixture removal manifest exceeds its byte bound.' }
        $null=Assert-RimePimeFixtureSha256 ([string]$file.sha256) 'Fixture removal file digest'
        switch ([string]$file.removal_class) {
            'ordinary' {
                if ($path -ceq 'Uninstall.exe' -or $path -ceq 'install-payload-manifest.json') {
                    throw 'Fixture removal class is inconsistent.'
                }
            }
            'installed-manifest' {
                if ($path -cne 'install-payload-manifest.json') { throw 'Fixture installed manifest coordinate is invalid.' }
                $installedManifestCount++
            }
            'special-self' {
                if ($path -cne 'Uninstall.exe') { throw 'Fixture special-self coordinate is invalid.' }
                $specialCount++
            }
            default { throw 'Fixture removal class is not admitted.' }
        }
    }
    if ($installedManifestCount -ne 1 -or $specialCount -ne 1) {
        throw 'Fixture removal manifest lacks its fixed terminal leaves.'
    }
    return $true
}

function New-RimePimeFixtureRemovalManifest {
    param([Parameter(Mandatory)][string]$ManifestId,[Parameter(Mandatory)][object[]]$Files)
    $map=New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach ($file in $Files) {
        $path=ConvertTo-RimePimeFixtureRelativePath ([string]$file.path)
        if ($map.ContainsKey($path)) { throw 'Fixture removal manifest has duplicate paths.' }
        $map.Add($path,[pscustomobject][ordered]@{
            path=$path; bytes=[int64]$file.bytes; sha256=[string]$file.sha256; removal_class=[string]$file.removal_class
        })
    }
    $keys=[string[]]@($map.Keys); [Array]::Sort($keys,[StringComparer]::Ordinal)
    $ordered=@()
    foreach ($key in $keys) { $ordered += $map[$key] }
    $value=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.RemovalManifest
        fixture_only=$true
        product='rime-pime'
        manifest_id=$ManifestId
        contains_user_text=$false
        files=$ordered
    }
    Assert-RimePimeFixtureRemovalManifest $value | Out-Null
    return $value
}

function Write-RimePimeFixtureRemovalManifest {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Manifest)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    Assert-RimePimeFixtureRemovalManifest $Manifest | Out-Null
    return Write-RimePimeFixtureSealedJson -Value $Manifest `
        -Path (Join-Path $Context.trusted_root 'removal-manifest.json') -FixtureRoot $Context.fixture_root
}

function Read-RimePimeFixtureRemovalManifest {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $sealed=Read-RimePimeFixtureSealedJson -Path (Join-Path $Context.trusted_root 'removal-manifest.json') `
        -FixtureRoot $Context.fixture_root
    Assert-RimePimeFixtureRemovalManifest $sealed.value | Out-Null
    return $sealed
}

function Get-RimePimeFixturePathDepth {
    param([Parameter(Mandatory)][string]$Path)
    return @($Path.Split('/')).Count
}

function Sort-RimePimeFixturePathsLeafFirst {
    param([Parameter(Mandatory)][string[]]$Paths)
    $result=@()
    if ($Paths.Count -eq 0) { return @() }
    $max=0
    foreach ($path in $Paths) { $max=[Math]::Max($max,(Get-RimePimeFixturePathDepth $path)) }
    for ($depth=$max; $depth -ge 1; $depth--) {
        $atDepth=[string[]]@($Paths | Where-Object { (Get-RimePimeFixturePathDepth $_) -eq $depth })
        [Array]::Sort($atDepth,[StringComparer]::Ordinal)
        foreach ($path in $atDepth) { $result += $path }
    }
    return @($result)
}

function Get-RimePimeFixtureRemovalPlan {
    param([Parameter(Mandatory)]$Manifest)
    Assert-RimePimeFixtureRemovalManifest $Manifest | Out-Null
    $ordinaryMap=New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $installed=$null; $special=$null
    foreach ($file in @($Manifest.files)) {
        switch ([string]$file.removal_class) {
            'ordinary' { $ordinaryMap.Add([string]$file.path,$file) }
            'installed-manifest' { $installed=$file }
            'special-self' { $special=$file }
        }
    }
    $ordinaryPaths=Sort-RimePimeFixturePathsLeafFirst ([string[]]@($ordinaryMap.Keys))
    $filePlan=@()
    foreach ($path in $ordinaryPaths) { $filePlan += $ordinaryMap[$path] }
    $filePlan += $installed; $filePlan += $special

    $directorySet=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($Manifest.files)) {
        $path=[string]$file.path
        while ($path.Contains('/')) {
            $path=$path.Substring(0,$path.LastIndexOf('/'))
            $null=$directorySet.Add($path)
        }
    }
    $directories=Sort-RimePimeFixturePathsLeafFirst ([string[]]@($directorySet))
    return [pscustomobject][ordered]@{ files=@($filePlan); directories=@($directories) }
}

function Get-RimePimeFixtureFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        [IO.FileShare]::Read,65536,[IO.FileOptions]::SequentialScan)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Test-RimePimeFixtureExpectedFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Expected)
    try {
        if (-not [IO.File]::Exists($Path)) { return $false }
        $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            [int64]$item.Length -ne [int64]$Expected.bytes) { return $false }
        $linkProperty=$item.PSObject.Properties['LinkType']
        if ($null -ne $linkProperty -and -not [string]::IsNullOrEmpty([string]$linkProperty.Value)) { return $false }
        $streams=@(Microsoft.PowerShell.Management\Get-Item -LiteralPath $Path -Stream * -Force -ErrorAction Stop)
        if ($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA') { return $false }
        return (Get-RimePimeFixtureFileSha256 $Path) -ceq [string]$Expected.sha256
    } catch { return $false }
}

function Get-RimePimeFixtureTreeInventory {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $root=[IO.Path]::GetFullPath([string]$Context.install_root).TrimEnd('\')
    $files=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $directories=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not [IO.Directory]::Exists($root)) {
        return [pscustomobject]@{ files=$files; directories=$directories; root_present=$false; root_safe=$true }
    }
    $rootAttributes=[IO.File]::GetAttributes($root)
    if (($rootAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return [pscustomobject]@{ files=$files; directories=$directories; root_present=$true; root_safe=$false }
    }
    $queue=New-Object Collections.Generic.Queue[string]
    $queue.Enqueue($root)
    while ($queue.Count -gt 0) {
        $directory=$queue.Dequeue()
        try { $entries=[string[]]@([IO.Directory]::EnumerateFileSystemEntries($directory)) }
        catch { throw 'Fixture install tree could not be inventoried safely.' }
        foreach ($entry in $entries) {
            try { $attributes=[IO.File]::GetAttributes($entry) }
            catch { throw 'Fixture install tree could not be inventoried safely.' }
            $relative=$entry.Substring($root.Length+1).Replace('\','/')
            $relative=ConvertTo-RimePimeFixtureRelativePath $relative
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                if ($directories.ContainsKey($relative)) { throw 'Fixture install inventory collision.' }
                $directories.Add($relative,$entry)
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $queue.Enqueue($entry) }
            } else {
                if ($files.ContainsKey($relative)) { throw 'Fixture install inventory collision.' }
                $files.Add($relative,$entry)
            }
        }
    }
    return [pscustomobject]@{ files=$files; directories=$directories; root_present=$true; root_safe=$true }
}

function Test-RimePimeFixtureRemovalClosure {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Manifest,[switch]$RequireExact)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    Assert-RimePimeFixtureRemovalManifest $Manifest | Out-Null
    $inventory=Get-RimePimeFixtureTreeInventory $Context
    $expectedFiles=New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $expectedDirectories=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($Manifest.files)) {
        $expectedFiles.Add([string]$file.path,$file)
        $path=[string]$file.path
        while ($path.Contains('/')) { $path=$path.Substring(0,$path.LastIndexOf('/')); $null=$expectedDirectories.Add($path) }
    }
    $missing=0; $changed=0; $unexpectedFiles=0; $unexpectedDirectories=0; $unsafeDirectories=0
    foreach ($path in $expectedFiles.Keys) {
        if (-not $inventory.files.ContainsKey($path)) { $missing++; continue }
        if (-not (Test-RimePimeFixtureExpectedFile $inventory.files[$path] $expectedFiles[$path])) { $changed++ }
    }
    foreach ($path in $inventory.files.Keys) { if (-not $expectedFiles.ContainsKey($path)) { $unexpectedFiles++ } }
    foreach ($path in $expectedDirectories) {
        if (-not $inventory.directories.ContainsKey($path)) { $missing++; continue }
        $attributes=[IO.File]::GetAttributes($inventory.directories[$path])
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $unsafeDirectories++ }
    }
    foreach ($path in $inventory.directories.Keys) {
        if (-not $expectedDirectories.Contains($path)) { $unexpectedDirectories++ }
    }
    if (-not $inventory.root_safe) { $unsafeDirectories++ }
    $exact=$inventory.root_present -and $missing -eq 0 -and $changed -eq 0 -and
        $unexpectedFiles -eq 0 -and $unexpectedDirectories -eq 0 -and $unsafeDirectories -eq 0
    $result=[pscustomobject][ordered]@{
        exact=[bool]$exact
        expected_file_count=[int]$expectedFiles.Count
        expected_directory_count=[int]$expectedDirectories.Count
        missing_count=[int]$missing
        changed_count=[int]$changed
        unexpected_file_count=[int]$unexpectedFiles
        unexpected_directory_count=[int]$unexpectedDirectories
        unsafe_directory_count=[int]$unsafeDirectories
        unexpected_filenames_disclosed=$false
        registry_provider_used=$false
        recursive_delete_used=$false
        concurrent_replacement_excluded=$false
    }
    if ($RequireExact -and -not $exact) { throw 'Fixture removal closure is not exact.' }
    return $result
}

function Invoke-RimePimeFixtureExactRemoval {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Manifest)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    Assert-RimePimeFixtureRemovalManifest $Manifest | Out-Null
    $initial=Test-RimePimeFixtureRemovalClosure $Context $Manifest
    $plan=Get-RimePimeFixtureRemovalPlan $Manifest
    $removedFiles=0; $alreadyAbsent=0; $preservedChanged=0; $removedDirectories=0; $preservedDirectories=0
    foreach ($expected in @($plan.files)) {
        $path=Get-RimePimeFixtureInstallPath $Context ([string]$expected.path)
        if (-not [IO.File]::Exists($path)) { $alreadyAbsent++; continue }
        if (-not (Test-RimePimeFixtureExpectedFile $path $expected)) { $preservedChanged++; continue }
        try { [IO.File]::Delete($path); $removedFiles++ }
        catch { $preservedChanged++ }
    }
    foreach ($relative in @($plan.directories)) {
        $path=Get-RimePimeFixtureInstallPath $Context $relative
        if (-not [IO.Directory]::Exists($path)) { continue }
        try {
            if (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $preservedDirectories++; continue
            }
            [IO.Directory]::Delete($path,$false); $removedDirectories++
        } catch { $preservedDirectories++ }
    }
    $rootRemoved=$false
    if ([IO.Directory]::Exists($Context.install_root)) {
        try {
            if (([IO.File]::GetAttributes($Context.install_root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $preservedDirectories++
            } else {
                [IO.Directory]::Delete($Context.install_root,$false); $rootRemoved=$true
            }
        } catch { $preservedDirectories++ }
    } else { $rootRemoved=$true }
    return [pscustomobject][ordered]@{
        removed_file_count=[int]$removedFiles
        already_absent_file_count=[int]$alreadyAbsent
        preserved_changed_file_count=[int]$preservedChanged
        removed_directory_count=[int]$removedDirectories
        preserved_directory_count=[int]$preservedDirectories
        unexpected_file_count=[int]$initial.unexpected_file_count
        unexpected_directory_count=[int]$initial.unexpected_directory_count
        install_root_removed=[bool]$rootRemoved
        changed_or_foreign_preserved=[bool]($preservedChanged -gt 0 -or $preservedDirectories -gt 0 -or
            $initial.unexpected_file_count -gt 0 -or $initial.unexpected_directory_count -gt 0)
        unexpected_filenames_disclosed=$false
        registry_provider_used=$false
        recursive_delete_used=$false
        concurrent_replacement_excluded=$false
    }
}

function Assert-RimePimeFixtureRecordCommon {
    param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Schema,[Parameter(Mandatory)][string]$Type)
    if ([string]$Record.schema_version -cne $Schema -or $Record.fixture_only -ne $true -or
        [string]$Record.product -cne 'rime-pime' -or [string]$Record.record_type -cne $Type -or
        $Record.contains_user_text -ne $false) {
        throw 'Fixture journal record identity is invalid.'
    }
    if ([string]$Record.transaction_id -cnotmatch '^[0-9a-f]{32}$') {
        throw 'Fixture transaction ID is not canonical.'
    }
    if (-not (Test-RimePimeFixtureInteger $Record.sequence) -or [int64]$Record.sequence -lt 0 -or
        [int64]$Record.sequence -gt 99999999) { throw 'Fixture record sequence is invalid.' }
    $null=Assert-RimePimeFixtureSha256 ([string]$Record.previous_record_sha256) 'Previous record digest'
    $null=Assert-RimePimeFixtureTimestamp ([string]$Record.recorded_utc)
}

function Assert-RimePimeFixturePreparedRecord {
    param([Parameter(Mandatory)]$Record)
    Assert-RimePimeFixtureExactProperties $Record @(
        'schema_version','fixture_only','product','record_type','transaction_id','action','architectures',
        'synthetic_target_user_sid','sequence','previous_record_sha256','registry_snapshot_sha256',
        'removal_manifest_sha256','before_state_sha256','protected_state_sha256','operation_plan_sha256',
        'recorded_utc','contains_user_text') 'Fixture prepared record'
    Assert-RimePimeFixtureRecordCommon $Record $script:RimePimeFixtureSchemas.Prepared 'prepared'
    if ([int64]$Record.sequence -ne 0 -or [string]$Record.previous_record_sha256 -cne $script:RimePimeFixtureZeroSha256) {
        throw 'Fixture prepared record is not the chain root.'
    }
    if ([string]$Record.action -cnotmatch '^(upgrade|uninstall)$') { throw 'Fixture action is not admitted.' }
    if ([string]$Record.synthetic_target_user_sid -cnotmatch '^S-1-5-21-100-200-300-[1-9][0-9]{0,8}$') {
        throw 'Fixture prepared record does not use a synthetic SID.'
    }
    if ($Record.architectures -is [string] -or $Record.architectures -isnot [Collections.IEnumerable]) {
        throw 'Fixture architecture set is not an array.'
    }
    $architectures=@($Record.architectures)
    if ($architectures.Count -ne 2 -or [string]$architectures[0] -cne 'x86' -or
        ([string]$architectures[1] -cne 'x64' -and [string]$architectures[1] -cne 'arm64')) {
        throw 'Fixture architecture set is not admitted.'
    }
    foreach ($name in @('registry_snapshot_sha256','removal_manifest_sha256','before_state_sha256',
            'protected_state_sha256','operation_plan_sha256')) {
        $null=Assert-RimePimeFixtureSha256 ([string]$Record.$name) $name
    }
    return $true
}

function Assert-RimePimeFixtureStepRecord {
    param([Parameter(Mandatory)]$Record)
    Assert-RimePimeFixtureExactProperties $Record @(
        'schema_version','fixture_only','product','record_type','transaction_id','sequence','previous_record_sha256',
        'operation_id','stage_id','direction','before_sha256','after_sha256','readback_sha256','protected_state_sha256','status',
        'recorded_utc','contains_user_text') 'Fixture step record'
    Assert-RimePimeFixtureRecordCommon $Record $script:RimePimeFixtureSchemas.Step 'step'
    if ([int64]$Record.sequence -lt 1 -or [string]$Record.operation_id -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Record.stage_id -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or
        [string]$Record.direction -cnotmatch '^(forward|rollback|cleanup)$' -or
        [string]$Record.status -cnotmatch '^(applied|already-converged)$') {
        throw 'Fixture step semantics are invalid.'
    }
    $expectedOperationId=Get-RimePimeFixtureOperationId ([string]$Record.transaction_id) ([string]$Record.stage_id)
    if ([string]$Record.operation_id -cne $expectedOperationId) {
        throw 'Fixture operation ID is not bound to its transaction and stage.'
    }
    foreach ($name in @('before_sha256','after_sha256','readback_sha256','protected_state_sha256')) {
        $null=Assert-RimePimeFixtureSha256 ([string]$Record.$name) $name
    }
    if ([string]$Record.after_sha256 -cne [string]$Record.readback_sha256) {
        throw 'Fixture step readback does not converge on its after state.'
    }
    if ([string]$Record.before_sha256 -ceq [string]$Record.after_sha256) {
        throw 'Fixture step may not encode an empty transition.'
    }
    return $true
}

function Assert-RimePimeFixtureCommitRecord {
    param([Parameter(Mandatory)]$Record)
    Assert-RimePimeFixtureExactProperties $Record @(
        'schema_version','fixture_only','product','record_type','transaction_id','sequence','previous_record_sha256',
        'prepared_record_sha256','final_state_sha256','protected_state_sha256','status','recorded_utc',
        'contains_user_text') 'Fixture commit record'
    Assert-RimePimeFixtureRecordCommon $Record $script:RimePimeFixtureSchemas.Commit 'commit'
    if ([int64]$Record.sequence -lt 1 -or [string]$Record.status -cne 'committed') {
        throw 'Fixture commit semantics are invalid.'
    }
    foreach ($name in @('prepared_record_sha256','final_state_sha256','protected_state_sha256')) {
        $null=Assert-RimePimeFixtureSha256 ([string]$Record.$name) $name
    }
    return $true
}

function Assert-RimePimeFixtureTerminalRecord {
    param([Parameter(Mandatory)]$Record)
    Assert-RimePimeFixtureExactProperties $Record @(
        'schema_version','fixture_only','product','record_type','transaction_id','sequence','previous_record_sha256',
        'commit_record_sha256','outcome','final_state_sha256','protected_state_sha256',
        'changed_or_foreign_preserved','recorded_utc','contains_user_text') 'Fixture terminal record'
    Assert-RimePimeFixtureRecordCommon $Record $script:RimePimeFixtureSchemas.Terminal 'terminal'
    if ([int64]$Record.sequence -lt 1 -or
        [string]$Record.outcome -cnotmatch '^(rolled-back|committed|cleanup-blocked-foreign-preserved)$') {
        throw 'Fixture terminal semantics are invalid.'
    }
    foreach ($name in @('commit_record_sha256','final_state_sha256','protected_state_sha256')) {
        $null=Assert-RimePimeFixtureSha256 ([string]$Record.$name) $name
    }
    $null=Assert-RimePimeFixtureBoolean $Record.changed_or_foreign_preserved 'Fixture preservation flag'
    if ([string]$Record.outcome -ceq 'cleanup-blocked-foreign-preserved' -and
        $Record.changed_or_foreign_preserved -ne $true) {
        throw 'Fixture cleanup-blocked terminal must preserve foreign content.'
    }
    if ([string]$Record.outcome -cne 'cleanup-blocked-foreign-preserved' -and
        $Record.changed_or_foreign_preserved -ne $false) {
        throw 'Fixture terminal preservation flag is inconsistent.'
    }
    return $true
}

function Assert-RimePimeFixtureJournalRecord {
    param([Parameter(Mandatory)]$Record)
    switch ([string]$Record.schema_version) {
        $script:RimePimeFixtureSchemas.Prepared { return Assert-RimePimeFixturePreparedRecord $Record }
        $script:RimePimeFixtureSchemas.Step { return Assert-RimePimeFixtureStepRecord $Record }
        $script:RimePimeFixtureSchemas.Commit { return Assert-RimePimeFixtureCommitRecord $Record }
        $script:RimePimeFixtureSchemas.Terminal { return Assert-RimePimeFixtureTerminalRecord $Record }
        default { throw 'Fixture journal record schema is not admitted.' }
    }
}

function Get-RimePimeFixtureRecordPath {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][int]$Sequence,
        [Parameter(Mandatory)][ValidateSet('prepared','step','commit','terminal')][string]$Type)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    return Join-Path $Context.records_root (('{0:d8}-{1}.json' -f $Sequence,$Type))
}

function Write-RimePimeFixtureJournalRecord {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$Record,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')]
        [string]$FaultAt=''
    )
    Assert-RimePimeFixtureJournalLock $Context $Lock
    Assert-RimePimeFixtureJournalRecord $Record | Out-Null
    return Write-RimePimeFixtureSealedJson -Value $Record `
        -Path (Get-RimePimeFixtureRecordPath $Context ([int]$Record.sequence) ([string]$Record.record_type)) `
        -FixtureRoot $Context.fixture_root -FaultAt $FaultAt
}

function Get-RimePimeFixtureRecordFiles {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $json=@()
    $sidecars=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $entries=[string[]]@([IO.Directory]::EnumerateFileSystemEntries($Context.records_root))
    foreach ($entry in $entries) {
        if ([IO.Directory]::Exists($entry)) { throw 'Fixture journal contains an unexpected control directory.' }
    }
    $all=[string[]]@($entries)
    if ($all.Count -gt 256) { throw 'Fixture journal exceeds its record-file bound.' }
    foreach ($path in $all) {
        $name=[IO.Path]::GetFileName($path)
        if ($name -cmatch '^[0-9]{8}-(prepared|step|commit|terminal)\.json$') {
            $json += $name; continue
        }
        if ($name -cmatch '^[0-9]{8}-(prepared|step|commit|terminal)\.json\.sha256$') {
            $null=$sidecars.Add($name); continue
        }
        throw 'Fixture journal contains an unexpected control file.'
    }
    $names=[string[]]$json; [Array]::Sort($names,[StringComparer]::Ordinal)
    return [pscustomobject]@{ json=$names; sidecars=$sidecars }
}

function Repair-RimePimeFixtureUncommittedTail {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock)
    Assert-RimePimeFixtureJournalLock $Context $Lock
    $files=Get-RimePimeFixtureRecordFiles $Context
    $orphanJson=@()
    foreach ($name in $files.json) {
        if (-not $files.sidecars.Contains($name+'.sha256')) { $orphanJson += $name }
    }
    foreach ($sidecar in $files.sidecars) {
        $jsonName=$sidecar.Substring(0,$sidecar.Length-7)
        if ($files.json -cnotcontains $jsonName) { throw 'Fixture journal contains an orphan digest sidecar.' }
    }
    if ($orphanJson.Count -eq 0) { return $false }
    if ($orphanJson.Count -ne 1) { throw 'Fixture journal has multiple uncommitted tails.' }
    $completeCount=$files.json.Count-1
    $tail=[string]$orphanJson[0]
    if ($tail -cnotmatch '^(?<sequence>[0-9]{8})-(prepared|step|commit|terminal)\.json$' -or
        [int]$Matches.sequence -ne $completeCount -or $tail -cne $files.json[$files.json.Count-1]) {
        throw 'Fixture journal uncommitted record is not the unique tail.'
    }
    $path=Assert-RimePimeFixtureContainedPath $Context.fixture_root (Join-Path $Context.records_root $tail)
    [IO.File]::Delete($path)
    return $true
}

function Read-RimePimeFixtureJournal {
    param([Parameter(Mandatory)]$Context)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    $files=Get-RimePimeFixtureRecordFiles $Context
    if ($files.json.Count -ne $files.sidecars.Count) { throw 'Fixture journal has an incomplete sealed record pair.' }
    $records=@()
    $prepared=$null; $commit=$null; $terminal=$null; $head=$script:RimePimeFixtureZeroSha256
    $transactionId=$null; $protected=$null
    $operations=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rollbackSeen=$false; $stepCount=0
    for ($i=0; $i -lt $files.json.Count; $i++) {
        $name=[string]$files.json[$i]
        if (-not $files.sidecars.Contains($name+'.sha256') -or
            $name -cnotmatch '^(?<sequence>[0-9]{8})-(?<type>prepared|step|commit|terminal)\.json$' -or
            [int]$Matches.sequence -ne $i) { throw 'Fixture journal sequence is not contiguous.' }
        $sealed=Read-RimePimeFixtureSealedJson -Path (Join-Path $Context.records_root $name) `
            -FixtureRoot $Context.fixture_root
        $record=$sealed.value
        Assert-RimePimeFixtureJournalRecord $record | Out-Null
        if ([int]$record.sequence -ne $i -or [string]$record.record_type -cne [string]$Matches.type -or
            [string]$record.previous_record_sha256 -cne $head) {
            throw 'Fixture journal hash chain is invalid.'
        }
        if ($i -eq 0) {
            if ([string]$record.record_type -cne 'prepared') { throw 'Fixture journal does not begin with prepared.' }
            $prepared=$sealed; $transactionId=[string]$record.transaction_id; $protected=[string]$record.protected_state_sha256
        } else {
            if ([string]$record.transaction_id -cne $transactionId -or
                [string]$record.protected_state_sha256 -cne $protected) {
                throw 'Fixture journal candidate binding changed inside the chain.'
            }
            if ($null -ne $terminal) { throw 'Fixture terminal record is not final.' }
            switch ([string]$record.record_type) {
                'prepared' { throw 'Fixture journal has more than one prepared record.' }
                'step' {
                    if (-not $operations.Add([string]$record.operation_id)) { throw 'Fixture journal operation ID is repeated.' }
                    if ($null -eq $commit) {
                        if ([string]$record.direction -ceq 'cleanup') { throw 'Fixture cleanup step precedes commit.' }
                        if ([string]$record.direction -ceq 'rollback') { $rollbackSeen=$true }
                        elseif ($rollbackSeen) { throw 'Fixture forward step follows rollback.' }
                    } elseif ([string]$record.direction -cne 'cleanup') {
                        throw 'Fixture non-cleanup step follows commit.'
                    }
                    $stepCount++
                }
                'commit' {
                    if ($null -ne $commit -or $rollbackSeen -or
                        [string]$record.prepared_record_sha256 -cne [string]$prepared.sha256) {
                        throw 'Fixture commit boundary is invalid.'
                    }
                    $commit=$sealed
                }
                'terminal' {
                    if ([string]$record.outcome -ceq 'rolled-back') {
                        if ($null -ne $commit -or [string]$record.commit_record_sha256 -cne $script:RimePimeFixtureZeroSha256 -or
                            [string]$record.final_state_sha256 -cne [string]$prepared.value.before_state_sha256) {
                            throw 'Fixture rollback terminal is inconsistent.'
                        }
                    } else {
                        if ($null -eq $commit -or [string]$record.commit_record_sha256 -cne [string]$commit.sha256 -or
                            [string]$record.final_state_sha256 -cne [string]$commit.value.final_state_sha256) {
                            throw 'Fixture committed terminal is inconsistent.'
                        }
                    }
                    $terminal=$sealed
                }
            }
        }
        $head=[string]$sealed.sha256
        $records += [pscustomobject][ordered]@{ value=$record; sha256=$sealed.sha256; bytes=$sealed.bytes }
    }
    return [pscustomobject][ordered]@{
        fixture_only=$true
        records=$records
        record_count=[int]$records.Count
        step_count=[int]$stepCount
        head_sha256=$head
        prepared=$prepared
        commit=$commit
        terminal=$terminal
        contains_user_text=$false
    }
}

function New-RimePimeFixturePreparedRecord {
    param(
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][ValidateSet('upgrade','uninstall')][string]$Action,
        [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$NativeArchitecture,
        [Parameter(Mandatory)][string]$SyntheticTargetUserSid,
        [Parameter(Mandatory)][string]$RegistrySnapshotSha256,
        [Parameter(Mandatory)][string]$RemovalManifestSha256,
        [Parameter(Mandatory)][string]$BeforeStateSha256,
        [Parameter(Mandatory)][string]$ProtectedStateSha256,
        [Parameter(Mandatory)][string]$OperationPlanSha256,
        [Parameter(Mandatory)][string]$RecordedUtc
    )
    $record=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.Prepared; fixture_only=$true; product='rime-pime'
        record_type='prepared'; transaction_id=$TransactionId; action=$Action
        architectures=@('x86',$NativeArchitecture); synthetic_target_user_sid=$SyntheticTargetUserSid
        sequence=0; previous_record_sha256=$script:RimePimeFixtureZeroSha256
        registry_snapshot_sha256=$RegistrySnapshotSha256; removal_manifest_sha256=$RemovalManifestSha256
        before_state_sha256=$BeforeStateSha256; protected_state_sha256=$ProtectedStateSha256
        operation_plan_sha256=$OperationPlanSha256; recorded_utc=$RecordedUtc; contains_user_text=$false
    }
    Assert-RimePimeFixturePreparedRecord $record | Out-Null
    return $record
}

function Assert-RimePimeFixturePreparedArtifactBindings {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$PreparedRecord)
    Assert-RimePimeFixtureTransactionContext $Context | Out-Null
    Assert-RimePimeFixturePreparedRecord $PreparedRecord | Out-Null
    $registry=Read-RimePimeFixtureRegistryState $Context 'before.json'
    $manifest=Read-RimePimeFixtureRemovalManifest $Context
    if ([string]$registry.sha256 -cne [string]$PreparedRecord.registry_snapshot_sha256 -or
        [string]$manifest.sha256 -cne [string]$PreparedRecord.removal_manifest_sha256 -or
        [string]$registry.value.synthetic_target_user_sid -cne [string]$PreparedRecord.synthetic_target_user_sid) {
        throw 'Fixture prepared record is not bound to its case-local sealed recovery artifacts.'
    }
    return $true
}

function Start-RimePimeFixtureTransaction {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)]$PreparedRecord,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')][string]$FaultAt=''
    )
    Assert-RimePimeFixtureJournalLock $Context $Lock
    Assert-RimePimeFixturePreparedRecord $PreparedRecord | Out-Null
    Assert-RimePimeFixturePreparedArtifactBindings $Context $PreparedRecord | Out-Null
    $chain=Read-RimePimeFixtureJournal $Context
    if ($chain.record_count -gt 0) {
        if ((ConvertTo-RimePimeFixtureCanonicalJson $chain.prepared.value) -cne
            (ConvertTo-RimePimeFixtureCanonicalJson $PreparedRecord)) {
            throw 'Fixture prepared retry conflicts with the durable transaction.'
        }
        return [pscustomobject][ordered]@{ new_record=$false; sha256=$chain.prepared.sha256; sequence=0 }
    }
    $written=Write-RimePimeFixtureJournalRecord $Context $Lock $PreparedRecord -FaultAt $FaultAt
    return [pscustomobject][ordered]@{ new_record=$true; sha256=$written.sha256; sequence=0 }
}

function Get-RimePimeFixtureOperationId {
    param([Parameter(Mandatory)][string]$TransactionId,[Parameter(Mandatory)][string]$StageId)
    if ($TransactionId -cnotmatch '^[0-9a-f]{32}$' -or $StageId -cnotmatch '^[a-z][a-z0-9-]{0,63}$') {
        throw 'Fixture operation identity input is invalid.'
    }
    $bytes=$script:RimePimeFixtureUtf8NoThrow.GetBytes("fixture-operation-v1`0$TransactionId`0$StageId")
    return Get-RimePimeFixtureBytesSha256 $bytes
}

function Add-RimePimeFixtureStep {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][ValidateSet('forward','rollback','cleanup')][string]$Direction,
        [Parameter(Mandatory)][string]$BeforeSha256,[Parameter(Mandatory)][string]$AfterSha256,
        [Parameter(Mandatory)][string]$ReadbackSha256,
        [ValidateSet('applied','already-converged')][string]$Status='applied',
        [Parameter(Mandatory)][string]$RecordedUtc,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')][string]$FaultAt=''
    )
    Assert-RimePimeFixtureJournalLock $Context $Lock
    $chain=Read-RimePimeFixtureJournal $Context
    if ($chain.record_count -eq 0) { throw 'Fixture step requires a durable prepared record.' }
    Assert-RimePimeFixturePreparedArtifactBindings $Context $chain.prepared.value | Out-Null
    foreach ($existing in @($chain.records)) {
        if ([string]$existing.value.record_type -ceq 'step' -and [string]$existing.value.operation_id -ceq $OperationId) {
            foreach ($pair in @(@('stage_id',$StageId),@('direction',$Direction),@('before_sha256',$BeforeSha256),
                    @('after_sha256',$AfterSha256),@('readback_sha256',$ReadbackSha256),@('status',$Status))) {
                if ([string]$existing.value.($pair[0]) -cne [string]$pair[1]) {
                    throw 'Fixture operation retry conflicts with the durable step.'
                }
            }
            return [pscustomobject][ordered]@{ new_record=$false; sha256=$existing.sha256; sequence=[int]$existing.value.sequence }
        }
    }
    if ($null -ne $chain.terminal) { throw 'Fixture step cannot follow terminal.' }
    if ($null -eq $chain.commit -and $Direction -ceq 'cleanup') { throw 'Fixture cleanup requires commit.' }
    if ($null -ne $chain.commit -and $Direction -cne 'cleanup') { throw 'Only cleanup can follow commit.' }
    $sequence=[int]$chain.record_count
    $record=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.Step; fixture_only=$true; product='rime-pime'; record_type='step'
        transaction_id=[string]$chain.prepared.value.transaction_id; sequence=$sequence
        previous_record_sha256=[string]$chain.head_sha256; operation_id=$OperationId; stage_id=$StageId
        direction=$Direction; before_sha256=$BeforeSha256; after_sha256=$AfterSha256
        readback_sha256=$ReadbackSha256; protected_state_sha256=[string]$chain.prepared.value.protected_state_sha256
        status=$Status; recorded_utc=$RecordedUtc; contains_user_text=$false
    }
    $written=Write-RimePimeFixtureJournalRecord $Context $Lock $record -FaultAt $FaultAt
    return [pscustomobject][ordered]@{ new_record=$true; sha256=$written.sha256; sequence=$sequence }
}

function Complete-RimePimeFixtureCommit {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][string]$FinalStateSha256,[Parameter(Mandatory)][string]$RecordedUtc,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')][string]$FaultAt=''
    )
    Assert-RimePimeFixtureJournalLock $Context $Lock
    $chain=Read-RimePimeFixtureJournal $Context
    if ($chain.record_count -eq 0) { throw 'Fixture commit requires prepared.' }
    Assert-RimePimeFixturePreparedArtifactBindings $Context $chain.prepared.value | Out-Null
    if ($null -ne $chain.commit) {
        if ([string]$chain.commit.value.final_state_sha256 -cne $FinalStateSha256) {
            throw 'Fixture commit retry conflicts with the durable commit.'
        }
        return [pscustomobject][ordered]@{ new_record=$false; sha256=$chain.commit.sha256; sequence=[int]$chain.commit.value.sequence }
    }
    if ($null -ne $chain.terminal) { throw 'Fixture commit cannot follow terminal.' }
    foreach ($row in @($chain.records)) {
        if ([string]$row.value.record_type -ceq 'step' -and [string]$row.value.direction -ceq 'rollback') {
            throw 'Fixture commit cannot follow rollback.'
        }
    }
    $sequence=[int]$chain.record_count
    $record=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.Commit; fixture_only=$true; product='rime-pime'; record_type='commit'
        transaction_id=[string]$chain.prepared.value.transaction_id; sequence=$sequence
        previous_record_sha256=[string]$chain.head_sha256; prepared_record_sha256=[string]$chain.prepared.sha256
        final_state_sha256=$FinalStateSha256; protected_state_sha256=[string]$chain.prepared.value.protected_state_sha256
        status='committed'; recorded_utc=$RecordedUtc; contains_user_text=$false
    }
    $written=Write-RimePimeFixtureJournalRecord $Context $Lock $record -FaultAt $FaultAt
    return [pscustomobject][ordered]@{ new_record=$true; sha256=$written.sha256; sequence=$sequence }
}

function Complete-RimePimeFixtureTerminal {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock,
        [Parameter(Mandatory)][ValidateSet('rolled-back','committed','cleanup-blocked-foreign-preserved')][string]$Outcome,
        [Parameter(Mandatory)][string]$FinalStateSha256,
        [Parameter(Mandatory)][bool]$ChangedOrForeignPreserved,
        [Parameter(Mandatory)][string]$RecordedUtc,
        [ValidateSet('','after-json-flush','before-sidecar-create','after-sidecar-flush')][string]$FaultAt=''
    )
    Assert-RimePimeFixtureJournalLock $Context $Lock
    $chain=Read-RimePimeFixtureJournal $Context
    if ($chain.record_count -eq 0) { throw 'Fixture terminal requires prepared.' }
    Assert-RimePimeFixturePreparedArtifactBindings $Context $chain.prepared.value | Out-Null
    if ($null -ne $chain.terminal) {
        if ([string]$chain.terminal.value.outcome -cne $Outcome -or
            [string]$chain.terminal.value.final_state_sha256 -cne $FinalStateSha256 -or
            [bool]$chain.terminal.value.changed_or_foreign_preserved -ne $ChangedOrForeignPreserved) {
            throw 'Fixture terminal retry conflicts with the durable terminal.'
        }
        return [pscustomobject][ordered]@{ new_record=$false; sha256=$chain.terminal.sha256; sequence=[int]$chain.terminal.value.sequence }
    }
    $commitSha=$script:RimePimeFixtureZeroSha256
    if ($Outcome -ceq 'rolled-back') {
        if ($null -ne $chain.commit -or $FinalStateSha256 -cne [string]$chain.prepared.value.before_state_sha256 -or
            $ChangedOrForeignPreserved) { throw 'Fixture rollback terminal input is inconsistent.' }
    } else {
        if ($null -eq $chain.commit -or $FinalStateSha256 -cne [string]$chain.commit.value.final_state_sha256) {
            throw 'Fixture committed terminal input is inconsistent.'
        }
        $commitSha=[string]$chain.commit.sha256
        if (($Outcome -ceq 'cleanup-blocked-foreign-preserved') -ne $ChangedOrForeignPreserved) {
            throw 'Fixture committed terminal preservation input is inconsistent.'
        }
    }
    $sequence=[int]$chain.record_count
    $record=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeFixtureSchemas.Terminal; fixture_only=$true; product='rime-pime'; record_type='terminal'
        transaction_id=[string]$chain.prepared.value.transaction_id; sequence=$sequence
        previous_record_sha256=[string]$chain.head_sha256; commit_record_sha256=$commitSha; outcome=$Outcome
        final_state_sha256=$FinalStateSha256; protected_state_sha256=[string]$chain.prepared.value.protected_state_sha256
        changed_or_foreign_preserved=$ChangedOrForeignPreserved; recorded_utc=$RecordedUtc; contains_user_text=$false
    }
    $written=Write-RimePimeFixtureJournalRecord $Context $Lock $record -FaultAt $FaultAt
    return [pscustomobject][ordered]@{ new_record=$true; sha256=$written.sha256; sequence=$sequence }
}

# Validate the durable fixture chain, discard only an unsealed tail, and return
# the replay disposition. This primitive never executes rollback or cleanup.
function Resume-RimePimeFixtureTransaction {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lock)
    Assert-RimePimeFixtureJournalLock $Context $Lock
    $discarded=Repair-RimePimeFixtureUncommittedTail $Context $Lock
    $chain=Read-RimePimeFixtureJournal $Context
    if ($null -ne $chain.prepared) {
        Assert-RimePimeFixturePreparedArtifactBindings $Context $chain.prepared.value | Out-Null
    }
    $disposition='no-mutation-admitted'
    if ($null -ne $chain.terminal) { $disposition='complete-noop' }
    elseif ($null -ne $chain.commit) { $disposition='roll-forward-cleanup' }
    elseif ($null -ne $chain.prepared) { $disposition='rollback-to-before' }
    return [pscustomobject][ordered]@{
        fixture_only=$true
        disposition=$disposition
        record_count=[int]$chain.record_count
        step_count=[int]$chain.step_count
        head_sha256=[string]$chain.head_sha256
        uncommitted_tail_discarded=[bool]$discarded
        installer_or_uninstaller_executed=$false
        registry_provider_used=$false
        product_process_accessed=$false
        contains_user_text=$false
    }
}
