# A separate contract for guarded isolated-target executable candidates.
# The canonical disabled receipt is deliberately not accepted or upgraded here.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:CandidateNative = $null
$script:CandidateStore = $null
$script:CandidateJson = $null
$script:CandidateRemoval = $null
$script:CandidateExpected = $null
$script:CandidateNativePins = @{
    'rime-pime-dp1u-exact-file-removal.cs' = '38ca72ec665187b1ecb958797660508e9f755a7b6f9d57b64eff6e7396e3b5a6'
    'rime-pime-dp1u-native-transaction.cs' = '4859d2abcd3f8eafd17053f10b6063944572796fc81b853606d1ce0da34431b8'
}

function Get-CandidateBytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Assert-CandidateHash($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-f]{64}$') { throw 'Expected literal candidate SHA256.' }
}
function Assert-CandidateObject($Value, [string[]]$Names) {
    if ($Value -isnot [pscustomobject]) { throw 'Expected literal candidate object.' }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count -or @($Names | Where-Object { $actual -cnotcontains $_ }).Count) {
        throw 'Candidate field set differs from supported schema.'
    }
}
function Initialize-CandidateNative {
    if ($null -ne $script:CandidateNative) { return }
    $source = ''; $leases = [Collections.Generic.List[object]]::new()
    try {
        foreach ($name in @('rime-pime-dp1u-exact-file-removal.cs', 'rime-pime-dp1u-native-transaction.cs')) {
            $stream = [IO.File]::Open((Join-Path $PSScriptRoot $name), 'Open', 'Read', 'Read')
            $leases.Add($stream)
            if ($stream.Length -gt 1048576) { throw 'Candidate helper source exceeds limit.' }
            $memory = [IO.MemoryStream]::new()
            try { $stream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $memory.Dispose() }
            if ((Get-CandidateBytesHash $bytes) -cne $script:CandidateNativePins[$name]) { throw 'Candidate helper source pin mismatch.' }
            $source += [Text.UTF8Encoding]::new($false,$true).GetString($bytes) + "`n"
        }
        $ns = 'Yime.Candidate_' + [guid]::NewGuid().ToString('N')
        $types = Add-Type -TypeDefinition $source.Replace('namespace Yime.Dp1UExactRemoval {', ('namespace ' + $ns + ' {')) -PassThru
        $script:CandidateNative = @($types | Where-Object FullName -CEQ ($ns + '.Native'))[0]
        $script:CandidateStore = @($types | Where-Object FullName -CEQ ($ns + '.TransactionStore'))[0]
        $script:CandidateJson = @($types | Where-Object FullName -CEQ ($ns + '.TransactionJson'))[0]
        $script:CandidateRemoval = @($types | Where-Object FullName -CEQ ($ns + '.RemovalContext'))[0]
        $script:CandidateExpected = @($types | Where-Object FullName -CEQ ($ns + '.ExpectedFile'))[0]
    } finally { foreach ($lease in $leases) { $lease.Dispose() } }
}
function ConvertFrom-CandidateJson([byte[]]$Bytes) {
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt 1048576) { throw 'Candidate JSON exceeds bounded size.' }
    Initialize-CandidateNative
    $text = [Text.UTF8Encoding]::new($false,$true).GetString($Bytes)
    $script:CandidateJson::Check($text)
    $options = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    ConvertFrom-Json -InputObject $text @options
}
function Get-CandidatePath([string]$Root, $Relative) {
    if ($Relative -isnot [string] -or $Relative.Length -gt 200 -or
        $Relative -cnotmatch '^[A-Za-z0-9_.+()-]+(?:/[A-Za-z0-9_.+()-]+)*$') { throw 'Candidate member is not a literal relative path.' }
    foreach ($part in $Relative.Split('/')) {
        if ($part -in @('.', '..') -or $part.EndsWith('.') -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw 'Ambiguous candidate member.' }
    }
    Join-Path $Root $Relative.Replace('/', '\')
}
function Open-CandidateSourceEvidence([string]$SourceRoot,[object[]]$Records) {
    # Provenance only: these default streams are never compiler inputs or copied
    # by this helper. Preserve origin ADS; actual bundle/compiler leases remain
    # subject to the strict no-ADS contract above and below.
    Initialize-CandidateNative
    $root=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\');$script:CandidateNative::CanonicalPath($root)
    $leases=[Collections.Generic.List[object]]::new();$directories=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $files=[Collections.Generic.List[object]]::new()
    $openDirectory=$script:CandidateNative.GetMethod('OpenDirectory',[Reflection.BindingFlags]'NonPublic,Static')
    $verify=$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static')
    try {
        foreach($row in $Records){
            Assert-CandidateObject $row @('path','bytes','sha256');Assert-CandidateHash $row.sha256
            if($row.path -isnot [string] -or $row.path -cnotmatch '^[A-Za-z0-9_.+() -]+(?:/[A-Za-z0-9_.+() -]+)*$' -or
                ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 0 -or $row.bytes -gt 536870912){throw 'Invalid source provenance record.'}
            foreach($part in $row.path.Split('/')){if($part -in @('.','..') -or $part -cne $part.Trim() -or $part.EndsWith('.') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Ambiguous source provenance path.'}}
            $path=Join-Path $root $row.path.Replace('/','\')
            $pending=[Collections.Generic.Stack[string]]::new()
            for($p=[IO.Path]::GetDirectoryName($path);$null -ne $p;$p=[IO.Path]::GetDirectoryName($p)){if($directories.ContainsKey($p)){break};$pending.Push($p)}
            while($pending.Count){$p=$pending.Pop();$handle=$openDirectory.Invoke($null,[object[]]@([string]$p));$leases.Add($handle)
                $id=$verify.Invoke($null,[object[]]@($handle,[string]$p,$true));$directories.Add($p,[pscustomobject]@{path=$p;id=$id;handle=$handle})}
            $stream=[IO.File]::Open($path,'Open','Read','Read');$leases.Add($stream)
            $id=$verify.Invoke($null,[object[]]@($stream.SafeFileHandle,[string]$path,$false))
            $files.Add([pscustomobject]@{path=$path;bytes=[long]$row.bytes;sha256=[string]$row.sha256;id=$id;stream=$stream})
        }
        $result=[pscustomobject]@{files=$files;directories=$directories;leases=$leases;provenance_only=$true}
        $null=Assert-CandidateSourceEvidence $result
        return $result
    }catch{foreach($lease in $leases){$lease.Dispose()};throw}
}
function Assert-CandidateSourceEvidence($Evidence) {
    $verify=$script:CandidateNative.GetMethod('Verify',[Reflection.BindingFlags]'NonPublic,Static')
    foreach($directory in $Evidence.directories.Values){if($verify.Invoke($null,[object[]]@($directory.handle,[string]$directory.path,$true)) -cne $directory.id){throw 'Source provenance directory identity changed.'}}
    foreach($file in $Evidence.files){
        if($verify.Invoke($null,[object[]]@($file.stream.SafeFileHandle,[string]$file.path,$false)) -cne $file.id){throw 'Source provenance identity changed.'}
        $file.stream.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($file.stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$file.stream.Position=0}
        if($file.stream.Length -ne $file.bytes -or $hash -cne $file.sha256){throw ('Source provenance default stream differs: '+$file.path)}
    }
}
function Close-CandidateSourceEvidence($Evidence) {foreach($lease in $Evidence.leases){$lease.Dispose()}}
function Assert-CandidateManifest($Manifest) {
    Assert-CandidateObject $Manifest @('schema_version','product','product_version','architectures','installation_scope',
        'launcher_mode','maintenance_entry','registration_provider','runtime_provider','files','source_inventory_sha256',
        'public_release_admitted','installed_acceptance_passed')
    $constants = @{
        schema_version='yime-rime-pime-executable-candidate-v1'; product='rime-pime'
        architectures='x86,x64'; installation_scope='approved-clean-isolated-x64-target'
        launcher_mode='required-dp1-candidate-state'; maintenance_entry='maintenance/invoke-rime-pime-candidate.ps1'
        registration_provider='maintenance/rime-pime-dp1u-candidate-registration.psm1'
        runtime_provider='maintenance/rime-pime-dp1u-candidate-runtime.psm1'
    }
    foreach ($key in $constants.Keys) {
        if ($Manifest.$key -isnot [string] -or $Manifest.$key -cne $constants[$key]) { throw ('Unsupported candidate identity: ' + $key) }
    }
    if ($Manifest.product_version -isnot [string] -or $Manifest.product_version -cnotmatch '^1\.4\.0-dev\.[1-9][0-9]*$') { throw 'Candidate version is outside the independent development line.' }
    Assert-CandidateHash $Manifest.source_inventory_sha256
    foreach ($flag in @('public_release_admitted','installed_acceptance_passed')) {
        if ($Manifest.$flag -isnot [bool] -or $Manifest.$flag) { throw 'Candidate source cannot grant release or installed acceptance.' }
    }
    if ($Manifest.files -isnot [array] -or $Manifest.files.Count -lt 8 -or $Manifest.files.Count -gt 4096) { throw 'Candidate file set is missing or outside limits.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Manifest.files) {
        Assert-CandidateObject $row @('path','bytes','sha256')
        $null = Get-CandidatePath 'C:\Candidate' $row.path
        if (-not $seen.Add($row.path) -or $row.path -ieq 'candidate.json' -or $row.path -ieq 'rime-pime-candidate-state.json' -or $row.path -ieq 'maintenance-candidate.exe') { throw 'Duplicate or reserved candidate member.' }
        Assert-CandidateHash $row.sha256
        if (($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -lt 0 -or $row.bytes -gt 4294967296) { throw 'Candidate member length is not a bounded integer.' }
    }
    foreach ($required in @('PIMELauncher.exe','x86/PIMETextService.dll','x64/PIMETextService.dll',
        'x86/PIMERegistrationStatus.exe','x64/PIMERegistrationStatus.exe','go-backend/server.exe',
        $Manifest.maintenance_entry,$Manifest.registration_provider,$Manifest.runtime_provider)) {
        if (-not $seen.Contains($required)) { throw ('Candidate required member missing: ' + $required) }
    }
    return $Manifest
}
function Open-RimePimeExecutableCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [object[]]$InstalledGeneratedFiles = @())
    Assert-CandidateHash $ExpectedManifestSha256
    Initialize-CandidateNative
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
    $script:CandidateNative::CanonicalPath($root)
    $leases = [Collections.Generic.List[object]]::new()
    try {
        # Directory handles remain held until the caller closes the candidate.
        $directoryIds = [ordered]@{}
        $directories = [Collections.Generic.Stack[string]]::new(); $directories.Push($root)
        for ($parent = [IO.Path]::GetDirectoryName($root); $null -ne $parent; $parent = [IO.Path]::GetDirectoryName($parent)) { $directories.Push($parent) }
        $openDirectory = $script:CandidateNative.GetMethod('OpenDirectory', [Reflection.BindingFlags]'NonPublic,Static')
        $verify = $script:CandidateNative.GetMethod('Verify', [Reflection.BindingFlags]'NonPublic,Static')
        $noAds = $script:CandidateNative.GetMethod('RejectNamedStreams', [Reflection.BindingFlags]'NonPublic,Static')
        while ($directories.Count) {
            $path = $directories.Pop()
            if ($directoryIds.Contains($path)) { continue }
            $handle = $openDirectory.Invoke($null, [object[]]@([string]$path)); $leases.Add($handle)
            $directoryIds[$path] = $verify.Invoke($null, [object[]]@([Microsoft.Win32.SafeHandles.SafeFileHandle]$handle,[string]$path,$true))
            $null = $noAds.Invoke($null, [object[]]@([string]$path))
        }
        $manifestPath = Join-Path $root 'candidate.json'
        $stream = [IO.File]::Open($manifestPath,'Open','Read','Read'); $leases.Add($stream)
        $null = $verify.Invoke($null,[object[]]@($stream.SafeFileHandle,[string]$manifestPath,$false))
        $null = $noAds.Invoke($null,[object[]]@([string]$manifestPath))
        if ($stream.Length -gt 1048576) { throw 'Candidate manifest exceeds limit.' }
        $memory = [IO.MemoryStream]::new()
        try { $stream.CopyTo($memory); $raw = $memory.ToArray() } finally { $memory.Dispose() }
        if ((Get-CandidateBytesHash $raw) -cne $ExpectedManifestSha256) { throw 'Candidate manifest differs from external digest.' }
        $manifest = Assert-CandidateManifest (ConvertFrom-CandidateJson $raw)
        $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $null = $expected.Add($manifestPath)
        $observations = @()
        if ($InstalledGeneratedFiles.Count -notin @(0,2)) { throw 'Installed generated member set must be empty or exact.' }
        if ($InstalledGeneratedFiles.Count) {
            $generatedNames=@($InstalledGeneratedFiles | ForEach-Object { $_.path })
            if ($generatedNames -cnotcontains 'rime-pime-candidate-state.json' -or $generatedNames -cnotcontains 'maintenance-candidate.exe') { throw 'Unsupported installed generated members.' }
            foreach ($generated in $InstalledGeneratedFiles) {
                Assert-CandidateObject $generated @('path','bytes','sha256')
                Assert-CandidateHash $generated.sha256
                if (($generated.bytes -isnot [int] -and $generated.bytes -isnot [long]) -or $generated.bytes -lt 1 -or $generated.bytes -gt 4294967296) { throw 'Invalid installed generated length.' }
            }
        }
        foreach ($row in @($manifest.files) + $InstalledGeneratedFiles) {
            $path = Get-CandidatePath $root $row.path
            for ($parent = [IO.Path]::GetDirectoryName($path); $parent.Length -gt $root.Length; $parent = [IO.Path]::GetDirectoryName($parent)) {
                if ($directoryIds.Contains($parent)) { continue }
                $handle = $openDirectory.Invoke($null,[object[]]@([string]$parent)); $leases.Add($handle)
                $directoryIds[$parent] = $verify.Invoke($null,[object[]]@([Microsoft.Win32.SafeHandles.SafeFileHandle]$handle,[string]$parent,$true))
                $null = $noAds.Invoke($null,[object[]]@([string]$parent))
            }
            $stream = [IO.File]::Open($path,'Open','Read','Read'); $leases.Add($stream)
            $id = $verify.Invoke($null,[object[]]@($stream.SafeFileHandle,[string]$path,$false))
            $null = $noAds.Invoke($null,[object[]]@([string]$path))
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
            if ($stream.Length -ne $row.bytes -or $hash -cne $row.sha256) { throw ('Candidate member differs: ' + $row.path) }
            $stream.Position = 0; $null = $expected.Add($path)
            $observations += [pscustomobject]@{path=$row.path;bytes=$row.bytes;sha256=$hash;file_id=$id;stream=$stream}
        }
        foreach ($directory in @($directoryIds.Keys | Where-Object { $_ -ieq $root -or $_.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) })) {
            foreach ($entry in Get-ChildItem -LiteralPath $directory -Force) {
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Candidate contains an indirect member.' }
                if ($entry.PSIsContainer) {
                    if (-not $directoryIds.Contains($entry.FullName)) { throw 'Unlisted candidate directory.' }
                } elseif (-not $expected.Contains($entry.FullName)) { throw 'Unlisted candidate file.' }
            }
        }
        return [pscustomobject]@{root=$root;manifest=$manifest;manifest_sha256=$ExpectedManifestSha256;manifest_bytes=$raw;
            files=$observations;directory_ids=$directoryIds;leases=$leases;execution_authorized=$false}
    } catch { foreach ($lease in $leases) { $lease.Dispose() }; throw }
}
function Close-RimePimeExecutableCandidate {
    param([Parameter(Mandatory)]$Candidate)
    foreach ($lease in $Candidate.leases) { $lease.Dispose() }
}
function Open-CandidateJournal([string]$Root,[bool]$Create) {
    Initialize-CandidateNative
    $ctor = $script:CandidateStore.GetConstructor([type[]]@([string],[bool]))
    $ctor.Invoke([object[]]@([string]$Root,[bool]$Create))
}
function Read-CandidateJournal($Store,[string]$Name,[string]$ExpectedSha256) {
    Assert-CandidateHash $ExpectedSha256
    $raw = $Store.Read($Name)
    if ((Get-CandidateBytesHash $raw) -cne $ExpectedSha256) { throw 'Journal differs from original external prepared digest.' }
    ConvertFrom-CandidateJson $raw
}
function Publish-CandidateJournal($Store,[string]$Name,$Value) {
    $text = ConvertTo-Json -InputObject $Value -Depth 30 -Compress
    $Store.Publish($Name,[Text.UTF8Encoding]::new($false,$true).GetBytes($text))
}
function Remove-CandidateExactFiles([string]$Root,[object[]]$Files) {
    Initialize-CandidateNative
    $array = [Array]::CreateInstance($script:CandidateExpected,$Files.Count)
    $ctor = $script:CandidateExpected.GetConstructor([type[]]@([string],[long],[string],[string]))
    for ($i=0; $i -lt $Files.Count; $i++) {
        $row=$Files[$i]
        $array.SetValue($ctor.Invoke([object[]]@([string]$row.path.Replace('/','\'),[long]$row.bytes,[string]$row.sha256,[string]$row.file_id)),$i)
    }
    $context = $script:CandidateRemoval.GetMethod('Open').Invoke($null,[object[]]@([string]$Root,$array))
    try { $context.Remove() } finally { $context.Dispose() }
}
function Get-CandidateLeafStatus([string]$Path) {
    Initialize-CandidateNative
    $arguments=[object[]]@([string]$Path,[int]0)
    $method=$script:CandidateNative.GetMethod('ClosedLeafStatus',[Reflection.BindingFlags]'NonPublic,Static')
    $status=$method.Invoke($null,$arguments)
    if($status -notin @('removed','path-present')){throw ('Candidate leaf is pending or inaccessible: '+$arguments[1])}
    [string]$status
}
Export-ModuleMember -Function Open-RimePimeExecutableCandidate,Close-RimePimeExecutableCandidate
