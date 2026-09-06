# Definitions-only, fixture-only receipt-v2 publication supersession protocol.
#
# Every mutating public operation is confined to one fresh immediate
# .tmp/dual-product/dp1-j-receipt-v2-supersession-* root below this repository.
# This helper never reads or writes the canonical package receipt, starts a
# process, invokes a build/sign/install/uninstall surface, or touches product
# state.  File flushes and a same-volume atomic head replacement are exercised,
# but retention, directory-metadata and power-loss durability remain unclaimed.

$script:RimePimeSupersessionRepoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$script:RimePimeSupersessionContextSchema='yime-rime-pime-receipt-v2-supersession-context-v1'
$script:RimePimeSupersessionReceiptSchema='yime-rime-pime-package-build-receipt-v2'
$script:RimePimeSupersessionGenerationSchema='yime-rime-pime-publication-generation-v1'
$script:RimePimeSupersessionHeadSchema='yime-rime-pime-publication-head-v1'
$script:RimePimeSupersessionJournalSchema='yime-rime-pime-publication-journal-record-v1'
$script:RimePimeSupersessionZeroDigest=('0'*64)
$script:RimePimeSupersessionJournalKinds=@('prepared','head-switched','commit','terminal')

function Get-RimePimeSupersessionSha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-RimePimeSupersessionDigest {
    param($Value)
    return $Value -is [string] -and [string]$Value -cmatch '^[0-9a-f]{64}$'
}

function Test-RimePimeSupersessionInteger {
    param($Value)
    return $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64]
}

function Assert-RimePimeSupersessionExactProperties {
    param($Value,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Context)
    if ($null -eq $Value -or $Value -is [string] -or $null -eq $Value.PSObject) {
        throw "$Context must be an object."
    }
    $actual=@($Value.PSObject.Properties | ForEach-Object Name)
    if ($actual.Count -ne $Expected.Count) { throw "$Context has an open or incomplete property set." }
    for ($i=0;$i -lt $Expected.Count;$i++) {
        if ([string]$actual[$i] -cne [string]$Expected[$i]) {
            throw "$Context property order or membership is invalid."
        }
    }
}

function ConvertTo-RimePimeSupersessionJsonString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $builder=New-Object Text.StringBuilder
    $null=$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code=[int][char]$character
        switch ($code) {
            8  { $null=$builder.Append('\b');continue }
            9  { $null=$builder.Append('\t');continue }
            10 { $null=$builder.Append('\n');continue }
            12 { $null=$builder.Append('\f');continue }
            13 { $null=$builder.Append('\r');continue }
            34 { $null=$builder.Append('\"');continue }
            92 { $null=$builder.Append('\\');continue }
        }
        if ($code -lt 32) { $null=$builder.Append(('\u{0:x4}' -f $code)) }
        else { $null=$builder.Append($character) }
    }
    $null=$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-RimePimeSupersessionCanonicalJson {
    param([Parameter(Mandatory=$false)]$Value,[int]$Depth=0)
    if ($Depth -gt 32) { throw 'Supersession canonical JSON exceeds its depth bound.' }
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' }; return 'false' }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-RimePimeSupersessionJsonString ([string]$Value)
    }
    if (Test-RimePimeSupersessionInteger $Value) {
        return ([Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture))
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset] -or $Value -is [decimal] -or
        $Value -is [double] -or $Value -is [single] -or $Value -is [uint64]) {
        throw "Unsupported supersession canonical JSON scalar type: $($Value.GetType().FullName)"
    }
    if ($Value -is [Collections.IDictionary]) {
        $parts=New-Object 'Collections.Generic.List[string]'
        foreach ($key in $Value.Keys) {
            if ($key -isnot [string]) { throw 'Supersession canonical JSON object keys must be strings.' }
            $parts.Add((ConvertTo-RimePimeSupersessionJsonString ([string]$key))+':'+
                (ConvertTo-RimePimeSupersessionCanonicalJson $Value[$key] ($Depth+1)))
        }
        return '{'+($parts -join ',')+'}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $parts=New-Object 'Collections.Generic.List[string]'
        foreach ($item in $Value) { $parts.Add((ConvertTo-RimePimeSupersessionCanonicalJson $item ($Depth+1))) }
        return '['+($parts -join ',')+']'
    }
    if ($null -ne $Value.PSObject) {
        $parts=New-Object 'Collections.Generic.List[string]'
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -notin @('NoteProperty','Property','AliasProperty','ScriptProperty')) { continue }
            $parts.Add((ConvertTo-RimePimeSupersessionJsonString ([string]$property.Name))+':'+
                (ConvertTo-RimePimeSupersessionCanonicalJson $property.Value ($Depth+1)))
        }
        return '{'+($parts -join ',')+'}'
    }
    throw "Unsupported supersession canonical JSON type: $($Value.GetType().FullName)"
}

function ConvertTo-RimePimeSupersessionCanonicalBytes {
    param([Parameter(Mandatory)]$Value)
    $text=(ConvertTo-RimePimeSupersessionCanonicalJson $Value)+"`n"
    return ,[Text.UTF8Encoding]::new($false,$true).GetBytes($text)
}

function Test-RimePimeSupersessionBytesEqual {
    param([Parameter(Mandatory)][byte[]]$Left,[Parameter(Mandatory)][byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i=0;$i -lt $Left.Length;$i++) { if ($Left[$i] -ne $Right[$i]) { return $false } }
    return $true
}

function ConvertFrom-RimePimeSupersessionCanonicalBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][string]$Context)
    if ($Bytes.Length -lt 3 -or $Bytes.Length -gt 8388608) { throw "$Context exceeds its byte bound." }
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    try { $text=$utf8.GetString($Bytes) }
    catch { throw "$Context is not strict UTF-8: $($_.Exception.Message)" }
    if (-not $text.EndsWith("`n",[StringComparison]::Ordinal) -or $text.Contains("`r")) {
        throw "$Context is not canonical LF JSON."
    }
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
            $value=$text | ConvertFrom-Json -DateKind String
        } else {
            $value=$text | ConvertFrom-Json
        }
    } catch { throw "$Context is not JSON: $($_.Exception.Message)" }
    $canonical=ConvertTo-RimePimeSupersessionCanonicalBytes $value
    if (-not(Test-RimePimeSupersessionBytesEqual $Bytes $canonical)) {
        throw "$Context bytes are not in the canonical representation."
    }
    return $value
}

function Assert-RimePimeSupersessionPathUnderRoot {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Context)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes its fixture root."
    }
    return $full
}

function Assert-RimePimeSupersessionExistingPathSafe {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[switch]$Leaf)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path)
    if ($full -ine $rootFull) { $null=Assert-RimePimeSupersessionPathUnderRoot $rootFull $full 'Supersession path' }
    $cursor=$full
    while ($cursor -and $cursor.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Supersession fixture traverses a reparse point: $cursor"
            }
        }
        if ($cursor -ieq $rootFull) { break }
        $cursor=Split-Path -Parent $cursor
    }
    if ($Leaf) {
        if (-not(Test-Path -LiteralPath $full -PathType Leaf)) { throw "Supersession fixture leaf is missing: $full" }
        $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $full -Force -ErrorAction Stop
        $link=$item.PSObject.Properties['LinkType']
        if ($null -ne $link -and -not[string]::IsNullOrEmpty([string]$link.Value)) {
            throw "Supersession fixture leaf has link topology: $full"
        }
        $streams=@(Microsoft.PowerShell.Management\Get-Item -LiteralPath $full -Stream * -Force -ErrorAction Stop)
        if ($streams.Count -ne 1 -or [string]$streams[0].Stream -cne ':$DATA') {
            throw "Supersession fixture leaf has alternate data streams: $full"
        }
    }
    return $full
}

function Write-RimePimeSupersessionCreateNewBytes {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes)
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Read-RimePimeSupersessionFileBytes {
    param([Parameter(Mandatory)][string]$Path,[long]$Maximum=536870912)
    $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0 -or $item.Length -lt 1 -or $item.Length -gt $Maximum) {
        throw "Supersession fixture file exceeds its byte bound: $Path"
    }
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        [IO.FileShare]::Read,65536,[IO.FileOptions]::SequentialScan)
    try {
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while ($offset -lt $bytes.Length) {
            $count=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($count -le 0) { throw "Supersession fixture file ended early: $Path" }
            $offset+=$count
        }
        if ($stream.ReadByte() -ne -1) { throw "Supersession fixture file grew while read: $Path" }
        return ,$bytes
    } finally { $stream.Dispose() }
}

function Write-RimePimeSupersessionSidecar {
    param([Parameter(Mandatory)][string]$DataPath,[Parameter(Mandatory)][string]$Digest)
    if (-not(Test-RimePimeSupersessionDigest $Digest)) { throw 'Invalid supersession sidecar digest.' }
    $sidecar=$DataPath+'.sha256'
    $bytes=[Text.Encoding]::ASCII.GetBytes("$Digest  $([IO.Path]::GetFileName($DataPath))`n")
    Write-RimePimeSupersessionCreateNewBytes $sidecar $bytes
    return $sidecar
}

function Test-RimePimeSupersessionSidecarExplicitlyShort {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$DataPath,[Parameter(Mandatory)][string]$SidecarPath)
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $SidecarPath -Leaf
    $item=Microsoft.PowerShell.Management\Get-Item -LiteralPath $SidecarPath -Force -ErrorAction Stop
    $expectedLength=64+2+[Text.Encoding]::ASCII.GetByteCount([IO.Path]::GetFileName($DataPath))+1
    return [long]$item.Length -lt [long]$expectedLength
}

function Read-RimePimeSupersessionSealedBytes {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Path,[long]$Maximum=536870912)
    $full=Assert-RimePimeSupersessionPathUnderRoot $Context.output_root $Path 'Sealed fixture file'
    $sidecar=$full+'.sha256'
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $full -Leaf
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $sidecar -Leaf
    $bytes=Read-RimePimeSupersessionFileBytes $full $Maximum
    $digest=Get-RimePimeSupersessionSha256Bytes $bytes
    $marker=Read-RimePimeSupersessionFileBytes $sidecar 256
    foreach ($one in $marker) { if ($one -gt 127) { throw 'Supersession sidecar is not ASCII.' } }
    $expected="$digest  $([IO.Path]::GetFileName($full))`n"
    if ([Text.Encoding]::ASCII.GetString($marker) -cne $expected) { throw 'Supersession sidecar does not seal its data bytes.' }
    return [pscustomobject]@{path=$full;sidecar=$sidecar;bytes=[byte[]]$bytes;sha256=$digest;length=[long]$bytes.Length}
}

function New-RimePimeReceiptV2SupersessionFixture {
    param([string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot=$script:RimePimeSupersessionRepoRoot }
    $repo=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    if ($repo -ine $script:RimePimeSupersessionRepoRoot) { throw 'Supersession fixture RepoRoot must be this helper repository.' }
    $output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
    $allowed=Join-Path $repo '.tmp\dual-product'
    if ((Split-Path -Parent $output) -ine $allowed -or
        (Split-Path -Leaf $output) -cnotmatch '^dp1-j-receipt-v2-supersession-[A-Za-z0-9-]+$' -or
        (Test-Path -LiteralPath $output)) {
        throw 'Use a fresh immediate .tmp/dual-product/dp1-j-receipt-v2-supersession-* fixture root.'
    }
    foreach ($path in @($repo,(Join-Path $repo '.tmp'),$allowed)) {
        if (Test-Path -LiteralPath $path) { $null=Assert-RimePimeSupersessionExistingPathSafe $repo $path }
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    $objects=Join-Path $output 'objects\sha256';$transactions=Join-Path $output 'transactions'
    New-Item -ItemType Directory -Path $objects,$transactions | Out-Null
    $lock=Join-Path $output '.rime-pime-supersession.lock'
    Write-RimePimeSupersessionCreateNewBytes $lock ([Text.Encoding]::ASCII.GetBytes("fixture-only-lock-v1`n"))
    return Open-RimePimeReceiptV2SupersessionFixture -RepoRoot $repo -OutputRoot $output
}

function Open-RimePimeReceiptV2SupersessionFixture {
    param([string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot=$script:RimePimeSupersessionRepoRoot }
    $repo=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
    $allowed=Join-Path $script:RimePimeSupersessionRepoRoot '.tmp\dual-product'
    if ($repo -ine $script:RimePimeSupersessionRepoRoot -or (Split-Path -Parent $output) -ine $allowed -or
        (Split-Path -Leaf $output) -cnotmatch '^dp1-j-receipt-v2-supersession-[A-Za-z0-9-]+$') {
        throw 'Supersession fixture context is outside its closed repository scope.'
    }
    $context=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeSupersessionContextSchema
        repo_root=$repo
        output_root=$output
        objects_root=(Join-Path $output 'objects\sha256')
        transactions_root=(Join-Path $output 'transactions')
        head_path=(Join-Path $output 'current-head.json')
        lock_path=(Join-Path $output '.rime-pime-supersession.lock')
    }
    $null=Assert-RimePimeReceiptV2SupersessionContext $context
    return $context
}

function Assert-RimePimeReceiptV2SupersessionContext {
    param([Parameter(Mandatory)]$Context)
    $names=@('schema_version','repo_root','output_root','objects_root','transactions_root','head_path','lock_path')
    Assert-RimePimeSupersessionExactProperties $Context $names 'Supersession fixture context'
    if ([string]$Context.schema_version -cne $script:RimePimeSupersessionContextSchema) { throw 'Invalid supersession context schema.' }
    $repo=$script:RimePimeSupersessionRepoRoot;$output=[IO.Path]::GetFullPath([string]$Context.output_root).TrimEnd('\')
    $allowed=Join-Path $repo '.tmp\dual-product'
    if ([string]$Context.repo_root -ine $repo -or (Split-Path -Parent $output) -ine $allowed -or
        (Split-Path -Leaf $output) -cnotmatch '^dp1-j-receipt-v2-supersession-[A-Za-z0-9-]+$' -or
        [string]$Context.objects_root -ine (Join-Path $output 'objects\sha256') -or
        [string]$Context.transactions_root -ine (Join-Path $output 'transactions') -or
        [string]$Context.head_path -ine (Join-Path $output 'current-head.json') -or
        [string]$Context.lock_path -ine (Join-Path $output '.rime-pime-supersession.lock')) {
        throw 'Supersession fixture context paths are not the closed derived set.'
    }
    foreach ($directory in @($output,$Context.objects_root,$Context.transactions_root)) {
        if (-not(Test-Path -LiteralPath $directory -PathType Container)) { throw "Supersession fixture directory is missing: $directory" }
        $null=Assert-RimePimeSupersessionExistingPathSafe $output $directory
    }
    $null=Assert-RimePimeSupersessionExistingPathSafe $output $Context.lock_path -Leaf
    return $Context
}

function Open-RimePimeSupersessionExclusiveLock {
    param([Parameter(Mandatory)]$Context)
    $null=Assert-RimePimeReceiptV2SupersessionContext $Context
    return [IO.File]::Open([string]$Context.lock_path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}

function Get-RimePimeSupersessionObjectPath {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Digest)
    if (-not(Test-RimePimeSupersessionDigest $Digest)) { throw 'Invalid supersession object digest.' }
    return Join-Path (Join-Path $Context.objects_root $Digest.Substring(0,2)) ($Digest+'.blob')
}

function Ensure-RimePimeSupersessionObject {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][byte[]]$Bytes)
    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt 536870912) { throw 'Supersession object exceeds its byte bound.' }
    $digest=Get-RimePimeSupersessionSha256Bytes $Bytes;$path=Get-RimePimeSupersessionObjectPath $Context $digest
    $directory=Split-Path -Parent $path
    if (-not(Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $directory
    $sidecar=$path+'.sha256'
    $dataExists=Test-Path -LiteralPath $path;$sidecarExists=Test-Path -LiteralPath $sidecar
    if ($sidecarExists -and -not $dataExists) { throw 'Supersession object has an orphan sidecar.' }
    if ($dataExists) {
        $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $path -Leaf
        $actual=Read-RimePimeSupersessionFileBytes $path
        $matches=(Test-RimePimeSupersessionBytesEqual $actual $Bytes) -and
            (Get-RimePimeSupersessionSha256Bytes $actual) -ceq $digest
        if (-not $matches -and -not $sidecarExists) {
            # An unsealed content-addressed object is not published state.  A
            # process interruption may have left its CreateNew write short, so
            # discard only that unsealed byte sequence and recreate it below.
            [IO.File]::Delete($path)
            $dataExists=$false
        } elseif (-not $matches) {
            throw 'Content-addressed supersession object collision or mutation detected.'
        }
    }
    if (-not $dataExists) { Write-RimePimeSupersessionCreateNewBytes $path $Bytes }
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $path -Leaf
    $actual=Read-RimePimeSupersessionFileBytes $path
    if (-not(Test-RimePimeSupersessionBytesEqual $actual $Bytes) -or
        (Get-RimePimeSupersessionSha256Bytes $actual) -cne $digest) {
        throw 'Content-addressed supersession object collision or mutation detected.'
    }
    if (Test-Path -LiteralPath $sidecar) {
        try { $null=Read-RimePimeSupersessionSealedBytes $Context $path }
        catch {
            # The data object is the exact expected digest and length.  Its
            # sidecar is merely a publication marker and may have been torn
            # after CreateNew but before Flush(true).
            if (-not(Test-RimePimeSupersessionSidecarExplicitlyShort $Context $path $sidecar)) { throw }
            [IO.File]::Delete($sidecar)
        }
    }
    if (-not(Test-Path -LiteralPath $sidecar)) { $null=Write-RimePimeSupersessionSidecar $path $digest }
    $sealed=Read-RimePimeSupersessionSealedBytes $Context $path
    if ($sealed.sha256 -cne $digest -or $sealed.length -ne $Bytes.Length) { throw 'Supersession object seal differs.' }
    return [pscustomobject][ordered]@{sha256=$digest;bytes=[long]$Bytes.Length}
}

function Read-RimePimeSupersessionObject {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Digest,[long]$ExpectedBytes=0)
    $path=Get-RimePimeSupersessionObjectPath $Context $Digest
    $sealed=Read-RimePimeSupersessionSealedBytes $Context $path
    if ($sealed.sha256 -cne $Digest -or ($ExpectedBytes -gt 0 -and $sealed.length -ne $ExpectedBytes)) {
        throw 'Supersession content object identity differs.'
    }
    return $sealed
}

function Get-RimePimeSupersessionMaterial {
    param(
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string]$MutationId,
        [Parameter(Mandatory)][string]$ExpectedHeadSha256,
        [Parameter(Mandatory)][int64]$GenerationOrdinal,
        [Parameter(Mandatory)][byte[]]$ReceiptBytes,
        [object[]]$Artifacts=@()
    )
    if ($TransactionId -cnotmatch '^[0-9a-f]{32}$' -or $MutationId -cnotmatch '^[0-9a-f]{32}$') {
        throw 'Supersession transaction and mutation IDs must be 32 lowercase hexadecimal characters.'
    }
    if (-not(Test-RimePimeSupersessionDigest $ExpectedHeadSha256) -or $GenerationOrdinal -lt 1) {
        throw 'Supersession expected head or generation ordinal is invalid.'
    }
    $receipt=ConvertFrom-RimePimeSupersessionCanonicalBytes $ReceiptBytes 'Supersession receipt-v2 object'
    if ($null -eq $receipt.PSObject.Properties['schema_version'] -or
        [string]$receipt.schema_version -cne $script:RimePimeSupersessionReceiptSchema) {
        throw 'Supersession accepts only canonical JSON with the receipt-v2 schema marker.'
    }
    $catalog=New-Object 'Collections.Generic.List[object]'
    $roles=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $receiptDigest=Get-RimePimeSupersessionSha256Bytes $ReceiptBytes
    $catalog.Add([pscustomobject][ordered]@{ordinal=0;role='receipt-v2';sha256=$receiptDigest;bytes=[long]$ReceiptBytes.Length})
    $null=$roles.Add('receipt-v2');$objectBytes=New-Object 'Collections.Generic.List[object]'
    $objectBytes.Add([pscustomobject]@{role='receipt-v2';bytes=[byte[]]$ReceiptBytes})
    $ordinal=1
    foreach ($artifact in @($Artifacts)) {
        Assert-RimePimeSupersessionExactProperties $artifact @('role','bytes') 'Supersession artifact input'
        $role=[string]$artifact.role
        if ($role -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or -not $roles.Add($role)) {
            throw 'Supersession artifact roles must be unique lowercase identifiers.'
        }
        try { $bytes=[byte[]]$artifact.bytes } catch { throw "Supersession artifact $role has invalid bytes." }
        if ($bytes.Length -lt 1 -or $bytes.Length -gt 536870912) { throw "Supersession artifact $role exceeds its byte bound." }
        $digest=Get-RimePimeSupersessionSha256Bytes $bytes
        $catalog.Add([pscustomobject][ordered]@{ordinal=$ordinal;role=$role;sha256=$digest;bytes=[long]$bytes.Length})
        $objectBytes.Add([pscustomobject]@{role=$role;bytes=$bytes});$ordinal++
    }
    $generation=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeSupersessionGenerationSchema
        generation_ordinal=$GenerationOrdinal
        receipt_schema_version=$script:RimePimeSupersessionReceiptSchema
        receipt_sha256=$receiptDigest
        receipt_bytes=[long]$ReceiptBytes.Length
        predecessor_head_sha256=$ExpectedHeadSha256
        artifact_count=$catalog.Count
        artifacts=@($catalog | ForEach-Object { $_ })
        retention_durability_claimed=$false
        directory_metadata_durability_verified=$false
        power_loss_verified=$false
        canonical_receipt_mutated=$false
    }
    $generationBytes=ConvertTo-RimePimeSupersessionCanonicalBytes $generation
    $generationDigest=Get-RimePimeSupersessionSha256Bytes $generationBytes
    $head=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeSupersessionHeadSchema
        generation_ordinal=$GenerationOrdinal
        generation_manifest_sha256=$generationDigest
        receipt_sha256=$receiptDigest
        transaction_id=$TransactionId
        mutation_id=$MutationId
        predecessor_head_sha256=$ExpectedHeadSha256
        retention_durability_claimed=$false
        directory_metadata_durability_verified=$false
        power_loss_verified=$false
        canonical_receipt_mutated=$false
    }
    $headBytes=ConvertTo-RimePimeSupersessionCanonicalBytes $head
    return [pscustomobject]@{
        transaction_id=$TransactionId;mutation_id=$MutationId;expected_head_sha256=$ExpectedHeadSha256
        generation_ordinal=$GenerationOrdinal;receipt_sha256=$receiptDigest;receipt_bytes=[long]$ReceiptBytes.Length
        object_bytes=@($objectBytes | ForEach-Object { $_ });generation=$generation;generation_bytes=$generationBytes
        generation_manifest_sha256=$generationDigest;head=$head;head_bytes=$headBytes
        new_head_sha256=(Get-RimePimeSupersessionSha256Bytes $headBytes)
    }
}

function Assert-RimePimeSupersessionGeneration {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Digest)
    $sealed=Read-RimePimeSupersessionObject $Context $Digest
    $generation=ConvertFrom-RimePimeSupersessionCanonicalBytes $sealed.bytes 'Supersession generation manifest'
    Assert-RimePimeSupersessionExactProperties $generation @(
        'schema_version','generation_ordinal','receipt_schema_version','receipt_sha256','receipt_bytes',
        'predecessor_head_sha256','artifact_count','artifacts','retention_durability_claimed',
        'directory_metadata_durability_verified','power_loss_verified','canonical_receipt_mutated') 'Supersession generation manifest'
    if ([string]$generation.schema_version -cne $script:RimePimeSupersessionGenerationSchema -or
        -not(Test-RimePimeSupersessionInteger $generation.generation_ordinal) -or [int64]$generation.generation_ordinal -lt 1 -or
        [string]$generation.receipt_schema_version -cne $script:RimePimeSupersessionReceiptSchema -or
        -not(Test-RimePimeSupersessionDigest $generation.receipt_sha256) -or
        -not(Test-RimePimeSupersessionInteger $generation.receipt_bytes) -or [int64]$generation.receipt_bytes -lt 1 -or
        -not(Test-RimePimeSupersessionDigest $generation.predecessor_head_sha256) -or
        -not(Test-RimePimeSupersessionInteger $generation.artifact_count) -or
        $generation.retention_durability_claimed -isnot [bool] -or [bool]$generation.retention_durability_claimed -or
        $generation.directory_metadata_durability_verified -isnot [bool] -or [bool]$generation.directory_metadata_durability_verified -or
        $generation.power_loss_verified -isnot [bool] -or [bool]$generation.power_loss_verified -or
        $generation.canonical_receipt_mutated -isnot [bool] -or [bool]$generation.canonical_receipt_mutated) {
        throw 'Supersession generation manifest identity or boundary is invalid.'
    }
    $artifacts=@($generation.artifacts)
    if ([int]$generation.artifact_count -ne $artifacts.Count -or $artifacts.Count -lt 1) {
        throw 'Supersession generation artifact count is invalid.'
    }
    $roles=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for ($i=0;$i -lt $artifacts.Count;$i++) {
        $artifact=$artifacts[$i]
        Assert-RimePimeSupersessionExactProperties $artifact @('ordinal','role','sha256','bytes') 'Supersession generation artifact'
        if (-not(Test-RimePimeSupersessionInteger $artifact.ordinal) -or [int]$artifact.ordinal -ne $i -or
            [string]$artifact.role -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or -not $roles.Add([string]$artifact.role) -or
            -not(Test-RimePimeSupersessionDigest $artifact.sha256) -or -not(Test-RimePimeSupersessionInteger $artifact.bytes) -or
            [long]$artifact.bytes -lt 1) { throw 'Supersession generation artifact identity is invalid.' }
        $null=Read-RimePimeSupersessionObject $Context ([string]$artifact.sha256) ([long]$artifact.bytes)
    }
    if ([string]$artifacts[0].role -cne 'receipt-v2' -or
        [string]$artifacts[0].sha256 -cne [string]$generation.receipt_sha256 -or
        [long]$artifacts[0].bytes -ne [long]$generation.receipt_bytes) {
        throw 'Supersession generation does not bind receipt-v2 as its first artifact.'
    }
    $receiptObject=Read-RimePimeSupersessionObject $Context ([string]$generation.receipt_sha256) ([long]$generation.receipt_bytes)
    $receipt=ConvertFrom-RimePimeSupersessionCanonicalBytes $receiptObject.bytes 'Supersession generation receipt-v2'
    if ($null -eq $receipt.PSObject.Properties['schema_version'] -or
        [string]$receipt.schema_version -cne $script:RimePimeSupersessionReceiptSchema) {
        throw 'Supersession generation receipt schema is not v2.'
    }
    return $generation
}

function Get-RimePimeReceiptV2SupersessionHead {
    param([Parameter(Mandatory)]$Context)
    $null=Assert-RimePimeReceiptV2SupersessionContext $Context
    if (-not(Test-Path -LiteralPath $Context.head_path)) {
        return [pscustomobject]@{present=$false;sha256=$script:RimePimeSupersessionZeroDigest;generation_ordinal=0;head=$null}
    }
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $Context.head_path -Leaf
    $bytes=Read-RimePimeSupersessionFileBytes $Context.head_path 1048576
    $head=ConvertFrom-RimePimeSupersessionCanonicalBytes $bytes 'Supersession publication head'
    Assert-RimePimeSupersessionExactProperties $head @(
        'schema_version','generation_ordinal','generation_manifest_sha256','receipt_sha256','transaction_id','mutation_id',
        'predecessor_head_sha256','retention_durability_claimed','directory_metadata_durability_verified',
        'power_loss_verified','canonical_receipt_mutated') 'Supersession publication head'
    if ([string]$head.schema_version -cne $script:RimePimeSupersessionHeadSchema -or
        -not(Test-RimePimeSupersessionInteger $head.generation_ordinal) -or [int64]$head.generation_ordinal -lt 1 -or
        -not(Test-RimePimeSupersessionDigest $head.generation_manifest_sha256) -or
        -not(Test-RimePimeSupersessionDigest $head.receipt_sha256) -or
        [string]$head.transaction_id -cnotmatch '^[0-9a-f]{32}$' -or [string]$head.mutation_id -cnotmatch '^[0-9a-f]{32}$' -or
        -not(Test-RimePimeSupersessionDigest $head.predecessor_head_sha256) -or
        $head.retention_durability_claimed -isnot [bool] -or [bool]$head.retention_durability_claimed -or
        $head.directory_metadata_durability_verified -isnot [bool] -or [bool]$head.directory_metadata_durability_verified -or
        $head.power_loss_verified -isnot [bool] -or [bool]$head.power_loss_verified -or
        $head.canonical_receipt_mutated -isnot [bool] -or [bool]$head.canonical_receipt_mutated) {
        throw 'Supersession publication head identity or boundary is invalid.'
    }
    $generation=Assert-RimePimeSupersessionGeneration $Context ([string]$head.generation_manifest_sha256)
    if ([int64]$generation.generation_ordinal -ne [int64]$head.generation_ordinal -or
        [string]$generation.receipt_sha256 -cne [string]$head.receipt_sha256 -or
        [string]$generation.predecessor_head_sha256 -cne [string]$head.predecessor_head_sha256) {
        throw 'Supersession head does not bind its immutable generation manifest.'
    }
    return [pscustomobject]@{present=$true;sha256=(Get-RimePimeSupersessionSha256Bytes $bytes);generation_ordinal=[int64]$head.generation_ordinal;head=$head}
}

function Get-RimePimeSupersessionTransactionPaths {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    if ($TransactionId -cnotmatch '^[0-9a-f]{32}$') { throw 'Invalid supersession transaction ID.' }
    $root=Join-Path $Context.transactions_root ('tx-'+$TransactionId)
    return [pscustomobject]@{
        root=$root;journal=(Join-Path $root 'journal')
        next_head=(Join-Path $Context.output_root ('.'+$TransactionId+'.head.next'))
        previous_head=(Join-Path $Context.output_root ('.'+$TransactionId+'.head.previous'))
    }
}

function Read-RimePimeSupersessionJournalInternal {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId,[switch]$RepairTornTail)
    $paths=Get-RimePimeSupersessionTransactionPaths $Context $TransactionId
    if (-not(Test-Path -LiteralPath $paths.root)) { return @() }
    if (-not(Test-Path -LiteralPath $paths.root -PathType Container) -or -not(Test-Path -LiteralPath $paths.journal -PathType Container)) {
        throw 'Supersession transaction directory is partial.'
    }
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $paths.root
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $paths.journal
    $unexpected=@(Get-ChildItem -LiteralPath $paths.root -Force | Where-Object { $_.Name -cne 'journal' })
    if ($unexpected.Count -ne 0) { throw 'Supersession transaction root has unexpected entries.' }
    $entries=@(Get-ChildItem -LiteralPath $paths.journal -Force)
    if (@($entries | Where-Object { $_.PSIsContainer }).Count -ne 0) {
        throw 'Supersession journal has an unexpected non-file entry.'
    }
    $files=@($entries | Where-Object { -not $_.PSIsContainer })
    foreach ($file in $files) {
        if ($file.Name -cnotmatch '^[0-9]{8}-(prepared|head-switched|commit|terminal)\.json(\.sha256)?$') {
            throw 'Supersession journal has an unexpected entry.'
        }
        $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $file.FullName -Leaf
    }
    $bases=@($files | ForEach-Object { $_.Name -replace '\.sha256$','' } | Sort-Object -Unique)
    $records=New-Object 'Collections.Generic.List[object]';$previous=$script:RimePimeSupersessionZeroDigest
    for ($i=0;$i -lt $bases.Count;$i++) {
        $sequence=$i+1;$kind=if($sequence -le $script:RimePimeSupersessionJournalKinds.Count){$script:RimePimeSupersessionJournalKinds[$i]}else{$null}
        if ($null -eq $kind) { throw 'Supersession journal contains too many records.' }
        $expectedName=('{0:D8}-{1}.json' -f $sequence,$kind)
        if ([string]$bases[$i] -cne $expectedName) { throw 'Supersession journal sequence or kind is not contiguous.' }
        $json=Join-Path $paths.journal $expectedName;$sidecar=$json+'.sha256'
        $jsonExists=Test-Path -LiteralPath $json -PathType Leaf;$sidecarExists=Test-Path -LiteralPath $sidecar -PathType Leaf
        if ($sidecarExists -and -not $jsonExists) { throw 'Supersession journal has an orphan sidecar.' }
        if ($jsonExists -and -not $sidecarExists) {
            if (-not $RepairTornTail -or $i -ne $bases.Count-1) { throw 'Supersession journal has an unsealed non-tail record.' }
            [IO.File]::Delete($json)
            break
        }
        try { $sealed=Read-RimePimeSupersessionSealedBytes $Context $json 1048576 }
        catch {
            if (-not $RepairTornTail -or $i -ne $bases.Count-1 -or
                -not(Test-RimePimeSupersessionSidecarExplicitlyShort $Context $json $sidecar)) { throw }
            # A tail sidecar can exist yet still be short if interruption
            # occurred inside its CreateNew write.  No later record can bind
            # an unverified tail, so discard both names and append it again.
            if (Test-Path -LiteralPath $sidecar) { [IO.File]::Delete($sidecar) }
            if (Test-Path -LiteralPath $json) { [IO.File]::Delete($json) }
            break
        }
        $record=ConvertFrom-RimePimeSupersessionCanonicalBytes $sealed.bytes 'Supersession journal record'
        Assert-RimePimeSupersessionExactProperties $record @(
            'schema_version','record_kind','sequence','transaction_id','mutation_id','expected_head_sha256','new_head_sha256',
            'generation_manifest_sha256','receipt_sha256','generation_ordinal','previous_record_sha256',
            'retention_durability_claimed','directory_metadata_durability_verified','power_loss_verified','canonical_receipt_mutated') 'Supersession journal record'
        if ([string]$record.schema_version -cne $script:RimePimeSupersessionJournalSchema -or
            [string]$record.record_kind -cne $kind -or -not(Test-RimePimeSupersessionInteger $record.sequence) -or [int]$record.sequence -ne $sequence -or
            [string]$record.transaction_id -cne $TransactionId -or [string]$record.mutation_id -cnotmatch '^[0-9a-f]{32}$' -or
            -not(Test-RimePimeSupersessionDigest $record.expected_head_sha256) -or -not(Test-RimePimeSupersessionDigest $record.new_head_sha256) -or
            -not(Test-RimePimeSupersessionDigest $record.generation_manifest_sha256) -or -not(Test-RimePimeSupersessionDigest $record.receipt_sha256) -or
            -not(Test-RimePimeSupersessionInteger $record.generation_ordinal) -or [int64]$record.generation_ordinal -lt 1 -or
            [string]$record.previous_record_sha256 -cne $previous -or
            $record.retention_durability_claimed -isnot [bool] -or [bool]$record.retention_durability_claimed -or
            $record.directory_metadata_durability_verified -isnot [bool] -or [bool]$record.directory_metadata_durability_verified -or
            $record.power_loss_verified -isnot [bool] -or [bool]$record.power_loss_verified -or
            $record.canonical_receipt_mutated -isnot [bool] -or [bool]$record.canonical_receipt_mutated) {
            throw 'Supersession journal identity, chain or boundary is invalid.'
        }
        if ($records.Count -gt 0) {
            $first=$records[0].record
            foreach ($property in @('transaction_id','mutation_id','expected_head_sha256','new_head_sha256','generation_manifest_sha256','receipt_sha256','generation_ordinal')) {
                if ([string]$record.$property -cne [string]$first.$property) { throw 'Supersession journal intent changed within its chain.' }
            }
        }
        $records.Add([pscustomobject]@{record=$record;sha256=$sealed.sha256;path=$sealed.path});$previous=$sealed.sha256
    }
    return @($records | ForEach-Object { $_ })
}

function Get-RimePimeReceiptV2SupersessionJournal {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    $null=Assert-RimePimeReceiptV2SupersessionContext $Context
    return @(Read-RimePimeSupersessionJournalInternal $Context $TransactionId)
}

function New-RimePimeSupersessionJournalValue {
    param([Parameter(Mandatory)]$Intent,[Parameter(Mandatory)][string]$Kind,[Parameter(Mandatory)][int]$Sequence,[Parameter(Mandatory)][string]$Previous)
    return [pscustomobject][ordered]@{
        schema_version=$script:RimePimeSupersessionJournalSchema;record_kind=$Kind;sequence=$Sequence
        transaction_id=[string]$Intent.transaction_id;mutation_id=[string]$Intent.mutation_id
        expected_head_sha256=[string]$Intent.expected_head_sha256;new_head_sha256=[string]$Intent.new_head_sha256
        generation_manifest_sha256=[string]$Intent.generation_manifest_sha256;receipt_sha256=[string]$Intent.receipt_sha256
        generation_ordinal=[int64]$Intent.generation_ordinal;previous_record_sha256=$Previous
        retention_durability_claimed=$false;directory_metadata_durability_verified=$false
        power_loss_verified=$false;canonical_receipt_mutated=$false
    }
}

function Add-RimePimeSupersessionJournalRecord {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Intent,[Parameter(Mandatory)][string]$Kind,[switch]$JsonOnly)
    $records=@(Read-RimePimeSupersessionJournalInternal $Context $Intent.transaction_id)
    $sequence=$records.Count+1
    if ($sequence -gt $script:RimePimeSupersessionJournalKinds.Count -or
        [string]$script:RimePimeSupersessionJournalKinds[$sequence-1] -cne $Kind) {
        throw 'Supersession journal append is out of order.'
    }
    $previous=if($records.Count){[string]$records[-1].sha256}else{$script:RimePimeSupersessionZeroDigest}
    $value=New-RimePimeSupersessionJournalValue $Intent $Kind $sequence $previous
    $path=Join-Path (Get-RimePimeSupersessionTransactionPaths $Context $Intent.transaction_id).journal ('{0:D8}-{1}.json' -f $sequence,$Kind)
    $bytes=ConvertTo-RimePimeSupersessionCanonicalBytes $value
    Write-RimePimeSupersessionCreateNewBytes $path $bytes
    if ($JsonOnly) { return [pscustomobject]@{path=$path;sha256=(Get-RimePimeSupersessionSha256Bytes $bytes);sealed=$false} }
    $null=Write-RimePimeSupersessionSidecar $path (Get-RimePimeSupersessionSha256Bytes $bytes)
    $sealed=Read-RimePimeSupersessionSealedBytes $Context $path 1048576
    return [pscustomobject]@{path=$path;sha256=$sealed.sha256;sealed=$true}
}

function Get-RimePimeSupersessionIntentFromRecord {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Record)
    $generation=Assert-RimePimeSupersessionGeneration $Context ([string]$Record.generation_manifest_sha256)
    if ([int64]$generation.generation_ordinal -ne [int64]$Record.generation_ordinal -or
        [string]$generation.receipt_sha256 -cne [string]$Record.receipt_sha256 -or
        [string]$generation.predecessor_head_sha256 -cne [string]$Record.expected_head_sha256) {
        throw 'Supersession prepared record does not bind its generation manifest.'
    }
    $head=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeSupersessionHeadSchema;generation_ordinal=[int64]$Record.generation_ordinal
        generation_manifest_sha256=[string]$Record.generation_manifest_sha256;receipt_sha256=[string]$Record.receipt_sha256
        transaction_id=[string]$Record.transaction_id;mutation_id=[string]$Record.mutation_id
        predecessor_head_sha256=[string]$Record.expected_head_sha256
        retention_durability_claimed=$false;directory_metadata_durability_verified=$false
        power_loss_verified=$false;canonical_receipt_mutated=$false
    }
    $headBytes=ConvertTo-RimePimeSupersessionCanonicalBytes $head
    if ((Get-RimePimeSupersessionSha256Bytes $headBytes) -cne [string]$Record.new_head_sha256) {
        throw 'Supersession prepared record does not bind its deterministic head bytes.'
    }
    return [pscustomobject]@{
        transaction_id=[string]$Record.transaction_id;mutation_id=[string]$Record.mutation_id
        expected_head_sha256=[string]$Record.expected_head_sha256;new_head_sha256=[string]$Record.new_head_sha256
        generation_manifest_sha256=[string]$Record.generation_manifest_sha256;receipt_sha256=[string]$Record.receipt_sha256
        generation_ordinal=[int64]$Record.generation_ordinal;head=$head;head_bytes=$headBytes
    }
}

function Assert-RimePimeSupersessionIntentsEqual {
    param([Parameter(Mandatory)]$Left,[Parameter(Mandatory)]$Right)
    foreach ($property in @('transaction_id','mutation_id','expected_head_sha256','new_head_sha256','generation_manifest_sha256','receipt_sha256','generation_ordinal')) {
        if ([string]$Left.$property -cne [string]$Right.$property) {
            throw 'Supersession retry conflicts with the durable prepared intent.'
        }
    }
}

function Assert-RimePimeSupersessionMutationUnused {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId,[Parameter(Mandatory)][string]$MutationId)
    foreach ($directory in @(Get-ChildItem -LiteralPath $Context.transactions_root -Directory -Force)) {
        if ($directory.Name -cnotmatch '^tx-([0-9a-f]{32})$') { throw 'Supersession transaction catalog has an unexpected directory.' }
        $other=[string]$Matches[1]
        if ($other -ceq $TransactionId) { continue }
        $records=@(Read-RimePimeSupersessionJournalInternal $Context $other)
        if ($records.Count -gt 0 -and [string]$records[0].record.mutation_id -ceq $MutationId) {
            throw 'Supersession mutation ID is already bound to another transaction.'
        }
    }
}

function Assert-RimePimeSupersessionNoUnresolvedTransactionExcept {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    foreach ($entry in @(Get-ChildItem -LiteralPath $Context.transactions_root -Force)) {
        if (-not $entry.PSIsContainer -or $entry.Name -cnotmatch '^tx-([0-9a-f]{32})$') {
            throw 'Supersession transaction catalog has an unexpected entry.'
        }
        $other=[string]$Matches[1]
        if ($other -ceq $TransactionId) { continue }
        $records=@(Read-RimePimeSupersessionJournalInternal $Context $other)
        if ($records.Count -ne 4 -or [string]$records[-1].record.record_kind -cne 'terminal') {
            throw 'Supersession has an unresolved transaction; resume it before creating a successor.'
        }
    }
}

function Ensure-RimePimeSupersessionTransactionDirectories {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    $paths=Get-RimePimeSupersessionTransactionPaths $Context $TransactionId
    if (-not(Test-Path -LiteralPath $paths.root)) { New-Item -ItemType Directory -Path $paths.root | Out-Null }
    if (-not(Test-Path -LiteralPath $paths.journal)) { New-Item -ItemType Directory -Path $paths.journal | Out-Null }
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $paths.root
    $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $paths.journal
    return $paths
}

function Ensure-RimePimeSupersessionHeadTemp {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Intent)
    $paths=Get-RimePimeSupersessionTransactionPaths $Context $Intent.transaction_id
    if (Test-Path -LiteralPath $paths.next_head) {
        $null=Assert-RimePimeSupersessionExistingPathSafe $Context.output_root $paths.next_head -Leaf
        $bytes=Read-RimePimeSupersessionFileBytes $paths.next_head 1048576
        if (-not(Test-RimePimeSupersessionBytesEqual $bytes $Intent.head_bytes)) {
            # The prepared journal binds the deterministic head bytes.  This
            # temp name is unpublished scratch and may be safely rebuilt.
            [IO.File]::Delete($paths.next_head)
        }
    }
    if (-not(Test-Path -LiteralPath $paths.next_head)) {
        Write-RimePimeSupersessionCreateNewBytes $paths.next_head $Intent.head_bytes
    }
    return $paths
}

function Assert-RimePimeSupersessionCurrentHeadReadyForSuccessor {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Head)
    if (-not $Head.present) { return }
    $ownerTransaction=[string]$Head.head.transaction_id
    $records=@(Read-RimePimeSupersessionJournalInternal $Context $ownerTransaction)
    if ($records.Count -ne 4 -or [string]$records[-1].record.record_kind -cne 'terminal') {
        throw 'Supersession current-head owner is unresolved; resume it before creating a successor.'
    }
    $intent=Get-RimePimeSupersessionIntentFromRecord $Context $records[0].record
    if ([string]$intent.new_head_sha256 -cne [string]$Head.sha256 -or
        [string]$intent.transaction_id -cne $ownerTransaction -or
        [string]$intent.mutation_id -cne [string]$Head.head.mutation_id) {
        throw 'Supersession current head is not bound to its terminal owner journal.'
    }
}

function Complete-RimePimeReceiptV2Supersession {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Intent,
        [ValidateSet('none','after-head-temp','after-head-switch','after-head-switched-json','after-commit','after-terminal')]
        [string]$FaultPoint='none'
    )
    $records=@(Read-RimePimeSupersessionJournalInternal $Context $Intent.transaction_id -RepairTornTail)
    if ($records.Count -lt 1) { throw 'Supersession replay requires a sealed prepared record.' }
    Assert-RimePimeSupersessionIntentsEqual $Intent (Get-RimePimeSupersessionIntentFromRecord $Context $records[0].record)
    $head=Get-RimePimeReceiptV2SupersessionHead $Context
    if ($records.Count -eq 4) {
        if ([string]$head.sha256 -cne [string]$Intent.new_head_sha256) { throw 'Terminal supersession no longer owns the current head.' }
        return [pscustomobject]@{status='terminal-noop';head_sha256=$head.sha256;record_count=4;replayed=$true}
    }
    if ([string]$head.sha256 -ceq [string]$Intent.expected_head_sha256) {
        if ([int64]$Intent.generation_ordinal -ne ([int64]$head.generation_ordinal+1)) { throw 'Supersession generation ordinal is not the next current generation.' }
        $paths=Ensure-RimePimeSupersessionHeadTemp $Context $Intent
        if ($FaultPoint -ceq 'after-head-temp') { throw 'Injected fixture fault after head temp flush.' }
        if (Test-Path -LiteralPath $paths.previous_head) { throw 'Supersession previous-head recovery file already exists before CAS.' }
        if ($head.present) { [IO.File]::Replace($paths.next_head,$Context.head_path,$paths.previous_head) }
        else { [IO.File]::Move($paths.next_head,$Context.head_path) }
        $head=Get-RimePimeReceiptV2SupersessionHead $Context
        if ([string]$head.sha256 -cne [string]$Intent.new_head_sha256) { throw 'Atomic supersession head switch did not publish the expected bytes.' }
        if ($FaultPoint -ceq 'after-head-switch') { throw 'Injected fixture fault after atomic head switch.' }
    } elseif ([string]$head.sha256 -cne [string]$Intent.new_head_sha256) {
        throw 'Supersession replay found a third-party head and refuses mutation.'
    }
    if ($records.Count -eq 1) {
        if ($FaultPoint -ceq 'after-head-switched-json') {
            $null=Add-RimePimeSupersessionJournalRecord $Context $Intent 'head-switched' -JsonOnly
            throw 'Injected fixture fault after head-switched JSON and before sidecar.'
        }
        $null=Add-RimePimeSupersessionJournalRecord $Context $Intent 'head-switched'
        $records=@(Read-RimePimeSupersessionJournalInternal $Context $Intent.transaction_id)
    }
    if ($records.Count -eq 2) {
        $null=Add-RimePimeSupersessionJournalRecord $Context $Intent 'commit'
        if ($FaultPoint -ceq 'after-commit') { throw 'Injected fixture fault after commit record.' }
        $records=@(Read-RimePimeSupersessionJournalInternal $Context $Intent.transaction_id)
    }
    if ($records.Count -eq 3) {
        $null=Add-RimePimeSupersessionJournalRecord $Context $Intent 'terminal'
        if ($FaultPoint -ceq 'after-terminal') { throw 'Injected fixture fault after terminal record.' }
    }
    $final=@(Read-RimePimeSupersessionJournalInternal $Context $Intent.transaction_id)
    $head=Get-RimePimeReceiptV2SupersessionHead $Context
    if ($final.Count -ne 4 -or [string]$head.sha256 -cne [string]$Intent.new_head_sha256) {
        throw 'Supersession transaction did not reach its exact terminal state.'
    }
    return [pscustomobject]@{status='committed';head_sha256=$head.sha256;record_count=4;replayed=$false}
}

function Invoke-RimePimeReceiptV2Supersession {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string]$MutationId,
        [string]$ExpectedHeadSha256=$script:RimePimeSupersessionZeroDigest,
        [Parameter(Mandatory)][int64]$GenerationOrdinal,
        [Parameter(Mandatory)][byte[]]$ReceiptBytes,
        [object[]]$Artifacts=@(),
        [ValidateSet('none','after-prepared','after-head-temp','after-head-switch','after-head-switched-json','after-commit','after-terminal')]
        [string]$FaultPoint='none'
    )
    $null=Assert-RimePimeReceiptV2SupersessionContext $Context
    $material=Get-RimePimeSupersessionMaterial $TransactionId $MutationId $ExpectedHeadSha256 $GenerationOrdinal $ReceiptBytes $Artifacts
    $lock=Open-RimePimeSupersessionExclusiveLock $Context
    try {
        Assert-RimePimeSupersessionMutationUnused $Context $TransactionId $MutationId
        $paths=Get-RimePimeSupersessionTransactionPaths $Context $TransactionId
        $existing=@(Read-RimePimeSupersessionJournalInternal $Context $TransactionId -RepairTornTail)
        if ($existing.Count -gt 0) {
            $intent=Get-RimePimeSupersessionIntentFromRecord $Context $existing[0].record
            Assert-RimePimeSupersessionIntentsEqual $material $intent
            return Complete-RimePimeReceiptV2Supersession $Context $intent $FaultPoint
        }
        $head=Get-RimePimeReceiptV2SupersessionHead $Context
        Assert-RimePimeSupersessionCurrentHeadReadyForSuccessor $Context $head
        Assert-RimePimeSupersessionNoUnresolvedTransactionExcept $Context $TransactionId
        if ([string]$head.sha256 -cne $ExpectedHeadSha256 -or $GenerationOrdinal -ne ([int64]$head.generation_ordinal+1)) {
            throw 'Supersession compare-and-swap precondition failed before transaction mutation.'
        }
        foreach ($object in $material.object_bytes) { $null=Ensure-RimePimeSupersessionObject $Context ([byte[]]$object.bytes) }
        $generationObject=Ensure-RimePimeSupersessionObject $Context ([byte[]]$material.generation_bytes)
        if ([string]$generationObject.sha256 -cne [string]$material.generation_manifest_sha256) { throw 'Supersession generation object differs.' }
        $null=Assert-RimePimeSupersessionGeneration $Context $material.generation_manifest_sha256
        $paths=Ensure-RimePimeSupersessionTransactionDirectories $Context $TransactionId
        $null=Add-RimePimeSupersessionJournalRecord $Context $material 'prepared'
        if ($FaultPoint -ceq 'after-prepared') { throw 'Injected fixture fault after prepared record.' }
        return Complete-RimePimeReceiptV2Supersession $Context $material $FaultPoint
    } finally { $lock.Dispose() }
}

function Resume-RimePimeReceiptV2Supersession {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TransactionId)
    $null=Assert-RimePimeReceiptV2SupersessionContext $Context
    $lock=Open-RimePimeSupersessionExclusiveLock $Context
    try {
        $records=@(Read-RimePimeSupersessionJournalInternal $Context $TransactionId -RepairTornTail)
        if ($records.Count -lt 1) { throw 'Supersession resume found no durable prepared record.' }
        $intent=Get-RimePimeSupersessionIntentFromRecord $Context $records[0].record
        return Complete-RimePimeReceiptV2Supersession $Context $intent
    } finally { $lock.Dispose() }
}
