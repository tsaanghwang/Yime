# Rime/PIME pre-package copy-stage helpers. Definitions only; no action on import.
#
# This module deliberately stops before a final install payload can be claimed:
# Uninstall.exe remains a declared generated output and must not exist in this
# copy stage. A later, separately verified generator receipt is required before
# the NSIS input and post-build extraction gates may call the payload final.
$script:RimePimeStageSpecSchema = 'yime-rime-pime-payload-spec-v1'
$script:RimePimeStageContentSchema = 'yime-rime-pime-copied-content-v1'
$script:RimePimeStageObservationSchema = 'yime-rime-pime-stage-observation-v1'
$script:RimePimeStageLimits = [pscustomobject][ordered]@{
    max_files = 512
    max_directories = 256
    max_total_bytes = 536870912
    max_file_bytes = 134217728
    max_path_chars = 512
    max_path_depth = 16
}

$packagePlanHelper = Join-Path $PSScriptRoot 'rime-pime-package-plan.ps1'
$payloadClosureHelper = Join-Path $PSScriptRoot 'rime-pime-payload-closure.ps1'
# This file is loaded by rime-pime-package-staging.psm1. Load both fixed-path
# dependencies unconditionally inside that module scope so an ambient function
# with the same name cannot substitute an implementation.
. $packagePlanHelper
. $payloadClosureHelper

function Add-RimePimeStageCanonicalJsonValue {
    param(
        [Parameter(Mandatory)][Text.StringBuilder]$Builder,
        [AllowNull()]$Value
    )
    if($null -eq $Value){$null=$Builder.Append('null');return}
    if($Value -is [bool]){$null=$Builder.Append($(if($Value){'true'}else{'false'}));return}
    if($Value -is [string] -or $Value -is [char]){
        $text=[string]$Value;$null=$Builder.Append('"')
        for($i=0;$i -lt $text.Length;$i++){
            $character=$text[$i]
            $code=[int][char]$character
            if($code -eq 8){$null=$Builder.Append('\b');continue}
            if($code -eq 9){$null=$Builder.Append('\t');continue}
            if($code -eq 10){$null=$Builder.Append('\n');continue}
            if($code -eq 12){$null=$Builder.Append('\f');continue}
            if($code -eq 13){$null=$Builder.Append('\r');continue}
            if($code -eq 34){$null=$Builder.Append('\"');continue}
            if($code -eq 92){$null=$Builder.Append('\\');continue}
            if($code -lt 32){$null=$Builder.Append(('\u{0:x4}' -f $code));continue}
            if([char]::IsHighSurrogate($character)){
                if($i+1 -ge $text.Length -or -not [char]::IsLowSurrogate($text[$i+1])){
                    throw 'Canonical stage JSON rejected an unpaired UTF-16 surrogate.'
                }
                $null=$Builder.Append($character);$i++;$null=$Builder.Append($text[$i]);continue
            }
            if([char]::IsLowSurrogate($character)){throw 'Canonical stage JSON rejected an unpaired UTF-16 surrogate.'}
            $null=$Builder.Append($character)
        }
        $null=$Builder.Append('"');return
    }
    if(Test-RimePimeStageInteger $Value){
        $null=$Builder.Append(([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$Value)));return
    }
    if($Value -is [float] -or $Value -is [double] -or $Value -is [decimal]){
        throw 'Canonical stage JSON accepts integer numeric values only.'
    }
    if($Value -is [Collections.IDictionary]){
        $keys=[string[]]@($Value.Keys|ForEach-Object{[string]$_});[Array]::Sort($keys,[StringComparer]::Ordinal)
        $null=$Builder.Append('{');$first=$true
        foreach($key in $keys){
            if(-not $first){$null=$Builder.Append(',')};$first=$false
            Add-RimePimeStageCanonicalJsonValue $Builder $key;$null=$Builder.Append(':')
            Add-RimePimeStageCanonicalJsonValue $Builder $Value[$key]
        }
        $null=$Builder.Append('}');return
    }
    if($Value -is [Collections.IEnumerable]){
        $null=$Builder.Append('[');$first=$true
        foreach($item in $Value){
            if(-not $first){$null=$Builder.Append(',')};$first=$false
            Add-RimePimeStageCanonicalJsonValue $Builder $item
        }
        $null=$Builder.Append(']');return
    }
    if($null -ne $Value.PSObject){
        $properties=@($Value.PSObject.Properties|Where-Object{$_.MemberType -in @('NoteProperty','Property')})
        if($properties.Count -eq 0){throw "Canonical stage JSON rejected unsupported value type: $($Value.GetType().FullName)"}
        $null=$Builder.Append('{');$first=$true
        foreach($property in $properties){
            if(-not $first){$null=$Builder.Append(',')};$first=$false
            Add-RimePimeStageCanonicalJsonValue $Builder ([string]$property.Name);$null=$Builder.Append(':')
            Add-RimePimeStageCanonicalJsonValue $Builder $property.Value
        }
        $null=$Builder.Append('}');return
    }
    throw 'Canonical stage JSON rejected an unsupported value.'
}

function ConvertTo-RimePimeStageCanonicalJson {
    param([Parameter(Mandatory)]$Value)
    $builder=[Text.StringBuilder]::new()
    Add-RimePimeStageCanonicalJsonValue $builder $Value
    return $builder.ToString()
}

function Write-RimePimeStageSealedJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path);$sidecar=$full+'.sha256'
    Assert-RimePimeNoReparsePath $full;Assert-RimePimeNoReparsePath $sidecar
    $parent=Split-Path -Parent $full
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $text=(ConvertTo-RimePimeStageCanonicalJson $Value)+"`n"
    if([Text.Encoding]::UTF8.GetByteCount($text) -gt 1048576){throw 'Canonical stage JSON exceeds the 1 MiB bound.'}
    [IO.File]::WriteAllText($full,$text,(New-Object Text.UTF8Encoding($false)))
    $digest=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($sidecar,"$digest  $([IO.Path]::GetFileName($full))`n",(New-Object Text.ASCIIEncoding))
    return $digest
}

function Get-RimePimeStageFullPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )
    $relative = ConvertTo-YimePimeCanonicalPayloadPath $RelativePath
    $rootFull = (Assert-YimePimePayloadAbsolutePath $Root).TrimEnd('\')
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $relative.Replace('/','\')))
    if (-not $full.StartsWith($rootFull + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Stage path escapes its root: $relative"
    }
    return $full
}

function Get-RimePimeStageRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FullPath
    )
    $rootFull = (Assert-YimePimePayloadAbsolutePath $Root).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($rootFull + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path is outside its declared root.'
    }
    return ConvertTo-YimePimeCanonicalPayloadPath $full.Substring($rootFull.Length + 1).Replace('\','/')
}

function Test-RimePimeStageInteger {
    param($Value)
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-RimePimeStagePathDepth {
    param([Parameter(Mandatory)][string]$Path)
    return @($Path.Split('/')).Count
}

function Assert-RimePimeStagePathWithinLimits {
    param([Parameter(Mandatory)][string]$Path)
    $relative = ConvertTo-YimePimeCanonicalPayloadPath $Path
    if ($relative.Length -gt $script:RimePimeStageLimits.max_path_chars -or
        (Get-RimePimeStagePathDepth $relative) -gt $script:RimePimeStageLimits.max_path_depth) {
        throw "Stage path exceeds its sealed length or depth bound: $relative"
    }
    foreach ($segment in $relative.Split('/')) {
        if ($segment.Length -gt 255) { throw "Stage path segment is too long: $relative" }
    }
    return $relative
}

function Get-RimePimeOrdinalKeys {
    param([Parameter(Mandatory)][object[]]$Values,[Parameter(Mandatory)][scriptblock]$Selector)
    $map = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($value in $Values) {
        $key = [string](& $Selector $value)
        if ($map.ContainsKey($key)) { throw "Duplicate ordinal stage key: $key" }
        $map.Add($key,$value)
    }
    $keys = [string[]]@($map.Keys)
    [Array]::Sort($keys,[StringComparer]::Ordinal)
    return [pscustomobject]@{Keys=$keys;Map=$map}
}

function Get-RimePimeFramedSha256 {
    param([Parameter(Mandatory)][string[]]$Frames)
    $memory = [IO.MemoryStream]::new()
    try {
        foreach ($frame in $Frames) {
            $bytes = [Text.Encoding]::UTF8.GetBytes([string]$frame)
            $length = [BitConverter]::GetBytes([uint32]$bytes.Length)
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($length) }
            $memory.Write($length,0,$length.Length)
            if ($bytes.Length) { $memory.Write($bytes,0,$bytes.Length) }
        }
        $memory.Position = 0
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($memory))).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { $memory.Dispose() }
}

function Get-RimePimeStageContentDigest {
    param(
        [Parameter(Mandatory)][object[]]$Directories,
        [Parameter(Mandatory)][object[]]$Files
    )
    $frames = [Collections.Generic.List[string]]::new()
    $frames.Add('yime-rime-pime-content-tree-framing-v1')
    $directoryOrder = Get-RimePimeOrdinalKeys @($Directories) { param($row) "$($row.stage_scope)`0$($row.path)" }
    foreach ($key in $directoryOrder.Keys) {
        $row = $directoryOrder.Map[$key]
        foreach ($field in @('directory',[string]$row.stage_scope,[string]$row.path,
                [string]$row.owner_class,[string]$row.removal_policy,[string]$row.install_scope)) {
            $frames.Add($field)
        }
    }
    $fileOrder = Get-RimePimeOrdinalKeys @($Files) { param($row) "$($row.stage_scope)`0$($row.path)" }
    foreach ($key in $fileOrder.Keys) {
        $row = $fileOrder.Map[$key]
        foreach ($field in @('file',[string]$row.stage_scope,[string]$row.path,
                ([long]$row.bytes).ToString([Globalization.CultureInfo]::InvariantCulture),
                [string]$row.sha256,[string]$row.owner_class,[string]$row.architecture,
                [string]$row.install_scope,[string]$row.origin_class)) {
            $frames.Add($field)
        }
    }
    return Get-RimePimeFramedSha256 @($frames)
}

function Get-RimePimeStageObservationDigest {
    param([Parameter(Mandatory)][object[]]$Files)
    $frames = [Collections.Generic.List[string]]::new()
    $frames.Add('yime-rime-pime-local-file-observation-framing-v1')
    $order = Get-RimePimeOrdinalKeys @($Files) { param($row) "$($row.stage_scope)`0$($row.path)" }
    foreach ($key in $order.Keys) {
        $row = $order.Map[$key]
        foreach ($field in @([string]$row.stage_scope,[string]$row.path,[string]$row.file_id,
                ([long]$row.bytes).ToString([Globalization.CultureInfo]::InvariantCulture),[string]$row.sha256)) {
            $frames.Add($field)
        }
    }
    return Get-RimePimeFramedSha256 @($frames)
}

function Get-RimePimeDerivedStageDirectories {
    param([Parameter(Mandatory)][object[]]$CopyFiles)
    $rows = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $CopyFiles) {
        $relative = Assert-RimePimeStagePathWithinLimits ([string]$file.destination_path)
        $segments = @($relative.Split('/'))
        for ($count=1; $count -lt $segments.Count; $count++) {
            $path = [string]::Join('/',@($segments | Select-Object -First $count))
            $key = [string]$file.stage_scope + '/' + $path
            $owner = [string]$file.owner_class
            $scope = [string]$file.install_scope
            $removal = if ([string]$file.stage_scope -ceq 'payload') { 'owned-tree-exact' } else { 'transient-delete' }
            if ($rows.ContainsKey($key)) {
                $existing = $rows[$key]
                if ([string]$existing.owner_class -cne $owner -or [string]$existing.install_scope -cne $scope) {
                    throw "Stage directory has conflicting ownership semantics: $key"
                }
                continue
            }
            $rows.Add($key,[pscustomobject][ordered]@{
                stage_scope=[string]$file.stage_scope
                path=$path
                owner_class=$owner
                removal_policy=$removal
                install_scope=$scope
            })
        }
    }
    $order = [string[]]@($rows.Keys)
    [Array]::Sort($order,[StringComparer]::Ordinal)
    return @($order | ForEach-Object { $rows[$_] })
}

function Get-RimePimeSourceTreeFiles {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TreeRelativePath
    )
    $treeRelative = Assert-RimePimeStagePathWithinLimits $TreeRelativePath
    $tree = Get-RimePimeStageFullPath $SourceRoot $treeRelative
    if (-not (Test-Path -LiteralPath $tree -PathType Container)) { throw "Closed source tree is missing: $treeRelative" }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($tree)
    $paths = [Collections.Generic.List[string]]::new()
    while ($pending.Count) {
        $directory = $pending.Pop()
        Assert-YimePimePayloadAbsolutePath $directory | Out-Null
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Closed source tree contains a reparse point: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
            $relative = Get-RimePimeStageRelativePath $SourceRoot $item.FullName
            $null = Get-YimePimePayloadFileRecord $item.FullName
            $paths.Add($relative)
        }
    }
    $result = [string[]]@($paths)
    [Array]::Sort($result,[StringComparer]::Ordinal)
    return $result
}

function Read-RimePimeGoPayloadInventory {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$InventoryPath,
        [string]$ExpectedDigest,
        [switch]$VerifySourceTree
    )
    $source = Assert-YimePimePayloadAbsolutePath $SourceRoot
    $inventoryFull = Get-RimePimeStageFullPath $source $InventoryPath
    $sealed = Read-RimePimeSealedJson $inventoryFull 'Go payload inventory'
    if ($ExpectedDigest -and ([string]$sealed.Digest -cne [string]$ExpectedDigest)) {
        throw 'Go payload inventory does not match the externally supplied digest.'
    }
    $inventory = $sealed.Value
    Assert-YimePimePayloadProperties $inventory @(
        'schema_version','source_root','destination_root','selection_policy','files') 'Go payload inventory'
    $sourceTree = Assert-RimePimeStagePathWithinLimits ([string]$inventory.source_root)
    $destinationTree = Assert-RimePimeStagePathWithinLimits ([string]$inventory.destination_root)
    $files = @($inventory.files)
    if ([string]$inventory.schema_version -cne 'yime-rime-pime-go-payload-inventory-v1' -or
        $sourceTree -cne 'go-backend/build/go-backend' -or $destinationTree -cne 'go-backend' -or
        [string]$inventory.selection_policy -cne 'exact-versioned-path-list-v1' -or
        $files.Count -lt 1 -or $files.Count -gt $script:RimePimeStageLimits.max_files) {
        throw 'Go payload inventory identity, policy, or count is invalid.'
    }
    $caseFolded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $previous = $null
    $sourcePaths = [Collections.Generic.List[string]]::new()
    foreach ($entry in $files) {
        if ($entry -isnot [string]) { throw 'Go payload inventory paths must be JSON strings.' }
        $relative = Assert-RimePimeStagePathWithinLimits ([string]$entry)
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$relative) -ge 0) {
            throw 'Go payload inventory paths are not in canonical ordinal order.'
        }
        if (-not $caseFolded.Add($relative)) { throw "Case-folded duplicate Go payload inventory path: $relative" }
        $previous = $relative
        $sourcePaths.Add($sourceTree + '/' + $relative)
    }
    if ($VerifySourceTree) {
        $actual = @(Get-RimePimeSourceTreeFiles $source $sourceTree)
        if ($actual.Count -ne $sourcePaths.Count) {
            throw "Go payload source tree differs from the exact versioned inventory: expected $($sourcePaths.Count), found $($actual.Count)."
        }
        for ($i=0; $i -lt $actual.Count; $i++) {
            if ([string]$actual[$i] -cne [string]$sourcePaths[$i]) {
                throw "Go payload source tree differs from the exact versioned inventory at index ${i}."
            }
        }
    }
    return [pscustomobject]@{
        Inventory=$inventory;Digest=[string]$sealed.Digest;Path=[string]$sealed.Path;Sidecar=[string]$sealed.Sidecar
        SourceRoot=$sourceTree;DestinationRoot=$destinationTree;RelativeFiles=@($files);SourcePaths=@($sourcePaths)
    }
}

function Assert-RimePimeStageSpecValue {
    param(
        [Parameter(Mandatory)]$Spec,
        [Parameter(Mandatory)][string]$SourceRoot,
        [switch]$VerifySources
    )
    Assert-YimePimePayloadProperties $Spec @(
        'schema_version','product','product_version','package_profile','architectures','phase',
        'hash_algorithm','directory_policy','limits','package_plan_sha256','source_trees',
        'directories','copy_files','generated_outputs') 'payload stage spec'
    $architectures = @($Spec.architectures)
    if ([string]$Spec.schema_version -cne $script:RimePimeStageSpecSchema -or
        [string]$Spec.product -cne 'rime-pime' -or
        [string]$Spec.product_version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$' -or
        [string]$Spec.package_profile -cne 'x86-x64-v1' -or
        $architectures.Count -ne 2 -or [string]$architectures[0] -cne 'x86' -or
        [string]$architectures[1] -cne 'x64' -or
        [string]$Spec.phase -cne 'declared-copy-inputs-before-generated-output' -or
        [string]$Spec.hash_algorithm -cne 'sha256' -or
        [string]$Spec.directory_policy -cne 'derived-nonempty-only-v1' -or
        [string]$Spec.package_plan_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Payload stage spec identity or phase is invalid.'
    }
    Assert-YimePimePayloadProperties $Spec.limits @(
        'max_files','max_directories','max_total_bytes','max_file_bytes','max_path_chars','max_path_depth') 'stage limits'
    foreach ($name in @('max_files','max_directories','max_total_bytes','max_file_bytes','max_path_chars','max_path_depth')) {
        if (-not (Test-RimePimeStageInteger $Spec.limits.$name) -or
            [long]$Spec.limits.$name -ne [long]$script:RimePimeStageLimits.$name) {
            throw "Payload stage spec changed sealed limit: $name"
        }
    }

    $files = @($Spec.copy_files)
    $directories = @($Spec.directories)
    $generated = @($Spec.generated_outputs)
    if ($files.Count -eq 0 -or $files.Count -gt $script:RimePimeStageLimits.max_files -or
        $directories.Count -gt $script:RimePimeStageLimits.max_directories) {
        throw 'Payload stage spec file or directory count is outside the sealed bound.'
    }
    $destinationSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $previous = $null
    $totalBytes = [long]0
    foreach ($row in $files) {
        Assert-YimePimePayloadProperties $row @(
            'source_path','destination_path','stage_scope','owner_class','architecture','install_scope',
            'source_bytes','source_sha256') 'payload stage copy record'
        $sourceRelative = Assert-RimePimeStagePathWithinLimits ([string]$row.source_path)
        $destination = Assert-RimePimeStagePathWithinLimits ([string]$row.destination_path)
        $scope = [string]$row.stage_scope
        $key = $scope + '/' + $destination
        if ($scope -notin @('payload','bootstrap') -or
            [string]$row.owner_class -notin @('metadata','license','runtime','backend','text-service','maintenance') -or
            [string]$row.architecture -notin @('neutral','x86','x64') -or
            ($scope -ceq 'payload' -and [string]$row.install_scope -cne 'installed') -or
            ($scope -ceq 'bootstrap' -and [string]$row.install_scope -cne 'transient') -or
            -not (Test-RimePimeStageInteger $row.source_bytes) -or [long]$row.source_bytes -lt 0 -or
            [long]$row.source_bytes -gt $script:RimePimeStageLimits.max_file_bytes -or
            [string]$row.source_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Invalid payload stage copy record: $key"
        }
        if (-not $destinationSet.Add($key)) { throw "Case-folded duplicate stage destination: $key" }
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$key) -ge 0) {
            throw 'Payload stage copy records are not in canonical ordinal order.'
        }
        $previous = $key
        $totalBytes += [long]$row.source_bytes
        if ($totalBytes -gt $script:RimePimeStageLimits.max_total_bytes) {
            throw 'Payload stage copy bytes exceed the sealed total bound.'
        }
        if ($VerifySources) {
            $path = Get-RimePimeStageFullPath $SourceRoot $sourceRelative
            $record = Get-YimePimePayloadFileRecord $path
            if ([long]$record.bytes -ne [long]$row.source_bytes -or
                [string]$record.sha256 -cne [string]$row.source_sha256) {
                throw "Source content does not match the sealed stage spec: $sourceRelative"
            }
        }
    }

    $previous = $null
    $directorySet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $directories) {
        Assert-YimePimePayloadProperties $row @('stage_scope','path','owner_class','removal_policy','install_scope') `
            'payload stage directory record'
        $path = Assert-RimePimeStagePathWithinLimits ([string]$row.path)
        $key = [string]$row.stage_scope + '/' + $path
        if ([string]$row.stage_scope -notin @('payload','bootstrap') -or
            [string]$row.owner_class -notin @('metadata','license','runtime','backend','text-service','maintenance') -or
            [string]$row.removal_policy -notin @('owned-tree-exact','transient-delete') -or
            ([string]$row.stage_scope -ceq 'payload' -and [string]$row.install_scope -cne 'installed') -or
            ([string]$row.stage_scope -ceq 'bootstrap' -and [string]$row.install_scope -cne 'transient')) {
            throw "Invalid payload stage directory record: $key"
        }
        if (-not $directorySet.Add($key)) { throw "Case-folded duplicate stage directory: $key" }
        if ($destinationSet.Contains($key)) { throw "Stage path is both file and directory: $key" }
        if ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$key) -ge 0) {
            throw 'Payload stage directories are not in canonical ordinal order.'
        }
        $previous = $key
    }
    $derived = @(Get-RimePimeDerivedStageDirectories $files)
    if ($derived.Count -ne $directories.Count) {
        throw 'Stage directories do not implement derived-nonempty-only-v1 exactly.'
    }
    for ($i=0; $i -lt $derived.Count; $i++) {
        $wanted = $derived[$i]
        $actual = $directories[$i]
        foreach ($name in @('stage_scope','path','owner_class','removal_policy','install_scope')) {
            if ([string]$wanted.$name -cne [string]$actual.$name) {
                throw 'Stage directory declaration differs from the exact derived nonempty set.'
            }
        }
    }

    if ($generated.Count -ne 1) { throw 'Exactly one pending generated uninstaller is required.' }
    $generatedRow = $generated[0]
    Assert-YimePimePayloadProperties $generatedRow @(
        'destination_path','stage_scope','generator_id','identity_policy_id','owner_class','architecture','install_scope') `
        'pending generated output'
    $generatedPath = Assert-RimePimeStagePathWithinLimits ([string]$generatedRow.destination_path)
    $generatedKey = [string]$generatedRow.stage_scope + '/' + $generatedPath
    if ($generatedPath -cne 'Uninstall.exe' -or [string]$generatedRow.stage_scope -cne 'payload' -or
        [string]$generatedRow.generator_id -cne 'nsis-uninstaller-prebuild-v1' -or
        [string]$generatedRow.identity_policy_id -cne 'authenticode-rime-pime-uninstaller-v1' -or
        [string]$generatedRow.owner_class -cne 'runtime' -or [string]$generatedRow.architecture -cne 'x86' -or
        [string]$generatedRow.install_scope -cne 'installed' -or $destinationSet.Contains($generatedKey) -or
        $directorySet.Contains($generatedKey)) {
        throw 'Pending generated uninstaller contract is invalid or collides with copied content.'
    }

    $trees = @($Spec.source_trees)
    $previous = $null
    foreach ($tree in $trees) {
        Assert-YimePimePayloadProperties $tree @(
            'source_root','destination_root','stage_scope','file_count','inventory_path','inventory_sha256') `
            'closed source tree record'
        $sourceTree = Assert-RimePimeStagePathWithinLimits ([string]$tree.source_root)
        $destinationTree = Assert-RimePimeStagePathWithinLimits ([string]$tree.destination_root)
        $inventoryPath = Assert-RimePimeStagePathWithinLimits ([string]$tree.inventory_path)
        $key = [string]$tree.stage_scope + '/' + $sourceTree
        if ([string]$tree.stage_scope -notin @('payload','bootstrap') -or
            -not (Test-RimePimeStageInteger $tree.file_count) -or [long]$tree.file_count -lt 1 -or
            [long]$tree.file_count -gt $script:RimePimeStageLimits.max_files -or
            [string]$tree.inventory_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$key) -ge 0)) {
            throw 'Closed source tree record is invalid or unordered.'
        }
        $previous = $key
        $expected = [Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            $sourcePath = [string]$file.source_path
            if ([string]$file.stage_scope -ceq [string]$tree.stage_scope -and
                $sourcePath.StartsWith($sourceTree + '/',[StringComparison]::Ordinal)) {
                $suffix = $sourcePath.Substring($sourceTree.Length + 1)
                $expectedDestination = $destinationTree + '/' + $suffix
                if ([string]$file.destination_path -cne $expectedDestination) {
                    throw "Closed source tree mapping changed destination: $sourcePath"
                }
                $expected.Add($sourcePath)
            }
        }
        $expectedArray = [string[]]@($expected)
        [Array]::Sort($expectedArray,[StringComparer]::Ordinal)
        if ($expectedArray.Count -ne [int]$tree.file_count) {
            throw 'Closed source tree file count differs from its declared bindings.'
        }
        $inventory = Read-RimePimeGoPayloadInventory -SourceRoot $SourceRoot -InventoryPath $inventoryPath `
            -ExpectedDigest ([string]$tree.inventory_sha256) -VerifySourceTree:$VerifySources
        if ([string]$inventory.SourceRoot -cne $sourceTree -or
            [string]$inventory.DestinationRoot -cne $destinationTree -or
            $inventory.SourcePaths.Count -ne $expectedArray.Count) {
            throw 'Closed source tree differs from its exact versioned inventory.'
        }
        for ($i=0; $i -lt $expectedArray.Count; $i++) {
            if ([string]$inventory.SourcePaths[$i] -cne [string]$expectedArray[$i]) {
                throw "Closed source tree binding differs from its exact versioned inventory at index ${i}."
            }
        }
    }
    return [pscustomobject]@{Files=$files;Directories=$directories;Generated=$generated;SourceTrees=$trees;TotalBytes=$totalBytes}
}

function Read-RimePimePackageStageSpec {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$SpecPath,
        [Parameter(Mandatory)][string]$ExpectedDigest,
        [switch]$VerifySources
    )
    if ($ExpectedDigest -cnotmatch '^[0-9a-f]{64}$') { throw 'Expected payload-spec digest is invalid.' }
    $sealed = Read-RimePimeSealedJson $SpecPath 'payload stage spec'
    if ([string]$sealed.Digest -cne $ExpectedDigest) { throw 'Payload stage spec does not match the externally supplied digest.' }
    $validated = Assert-RimePimeStageSpecValue $sealed.Value $SourceRoot -VerifySources:$VerifySources
    return [pscustomobject]@{
        Spec=$sealed.Value;Digest=$sealed.Digest;Path=$sealed.Path;Sidecar=$sealed.Sidecar
        SourceRoot=(Assert-YimePimePayloadAbsolutePath $SourceRoot);Validated=$validated
    }
}

function Write-RimePimePackageStageSpec {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$SpecPath,
        [Parameter(Mandatory)][string]$ProductVersion,
        [Parameter(Mandatory)][string]$PackagePlanDigest,
        [Parameter(Mandatory)][object[]]$CopyBindings,
        [Parameter(Mandatory)][object[]]$ClosedSourceTrees,
        [Parameter(Mandatory)][object[]]$GeneratedOutputs
    )
    $source = Assert-YimePimePayloadAbsolutePath $SourceRoot
    if ($PackagePlanDigest -cnotmatch '^[0-9a-f]{64}$') { throw 'Package-plan digest is invalid.' }
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($binding in $CopyBindings) {
        Assert-YimePimePayloadProperties $binding @(
            'source_path','destination_path','stage_scope','owner_class','architecture','install_scope') `
            'stage binding input'
        $sourceRelative = Assert-RimePimeStagePathWithinLimits ([string]$binding.source_path)
        $destination = Assert-RimePimeStagePathWithinLimits ([string]$binding.destination_path)
        $record = Get-YimePimePayloadFileRecord (Get-RimePimeStageFullPath $source $sourceRelative)
        $rows.Add([pscustomobject][ordered]@{
            source_path=$sourceRelative
            destination_path=$destination
            stage_scope=[string]$binding.stage_scope
            owner_class=[string]$binding.owner_class
            architecture=[string]$binding.architecture
            install_scope=[string]$binding.install_scope
            source_bytes=[long]$record.bytes
            source_sha256=[string]$record.sha256
        })
    }
    $order = Get-RimePimeOrdinalKeys @($rows) { param($row) "$($row.stage_scope)`0$($row.destination_path)" }
    $sortedRows = @($order.Keys | ForEach-Object { $order.Map[$_] })
    $versionRows = @($sortedRows | Where-Object {
        [string]$_.source_path -ceq 'version.txt' -and [string]$_.destination_path -ceq 'version.txt' -and
        [string]$_.stage_scope -ceq 'payload'
    })
    if ($versionRows.Count -gt 1) { throw 'Payload stage contains duplicate canonical version.txt bindings.' }
    if ($versionRows.Count -eq 1) {
        $versionPath = Get-RimePimeStageFullPath $source 'version.txt'
        $versionText = [IO.File]::ReadAllText($versionPath).Trim()
        $versionRecord = Get-YimePimePayloadFileRecord $versionPath
        if ($versionText -cne $ProductVersion -or
            [long]$versionRecord.bytes -ne [long]$versionRows[0].source_bytes -or
            [string]$versionRecord.sha256 -cne [string]$versionRows[0].source_sha256) {
            throw 'ProductVersion differs from the sealed version.txt source binding.'
        }
    }
    $directories = @(Get-RimePimeDerivedStageDirectories $sortedRows)
    $trees = [Collections.Generic.List[object]]::new()
    foreach ($tree in $ClosedSourceTrees) {
        Assert-YimePimePayloadProperties $tree @(
            'source_root','destination_root','stage_scope','inventory_path','inventory_sha256') 'closed source tree input'
        $sourceTree = Assert-RimePimeStagePathWithinLimits ([string]$tree.source_root)
        $destinationTree = Assert-RimePimeStagePathWithinLimits ([string]$tree.destination_root)
        $inventoryPath = Assert-RimePimeStagePathWithinLimits ([string]$tree.inventory_path)
        $inventory = Read-RimePimeGoPayloadInventory -SourceRoot $source -InventoryPath $inventoryPath `
            -ExpectedDigest ([string]$tree.inventory_sha256) -VerifySourceTree
        if ([string]$inventory.SourceRoot -cne $sourceTree -or [string]$inventory.DestinationRoot -cne $destinationTree) {
            throw 'Closed source tree input does not match its exact versioned inventory roots.'
        }
        $count = @($sortedRows | Where-Object {
            [string]$_.stage_scope -ceq [string]$tree.stage_scope -and
            [string]$_.source_path -clike ($sourceTree + '/*')
        }).Count
        if ($count -ne $inventory.SourcePaths.Count) {
            throw 'Closed source tree bindings do not cover the exact versioned inventory.'
        }
        $trees.Add([pscustomobject][ordered]@{
            source_root=$sourceTree
            destination_root=$destinationTree
            stage_scope=[string]$tree.stage_scope
            file_count=[int]$count
            inventory_path=$inventoryPath
            inventory_sha256=[string]$inventory.Digest
        })
    }
    $treeOrder = Get-RimePimeOrdinalKeys @($trees) { param($row) "$($row.stage_scope)`0$($row.source_root)" }
    $sortedTrees = @($treeOrder.Keys | ForEach-Object { $treeOrder.Map[$_] })
    $value = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeStageSpecSchema
        product='rime-pime'
        product_version=$ProductVersion
        package_profile='x86-x64-v1'
        architectures=@('x86','x64')
        phase='declared-copy-inputs-before-generated-output'
        hash_algorithm='sha256'
        directory_policy='derived-nonempty-only-v1'
        limits=$script:RimePimeStageLimits
        package_plan_sha256=$PackagePlanDigest
        source_trees=@($sortedTrees)
        directories=@($directories)
        copy_files=@($sortedRows)
        generated_outputs=@($GeneratedOutputs)
    }
    $digest = Write-RimePimeStageSealedJson $value $SpecPath
    return Read-RimePimePackageStageSpec $source $SpecPath $digest -VerifySources
}

function Get-RimePimeCurrentPackageStageDeclaration {
    param([Parameter(Mandatory)]$Package)
    $root = [string]$Package.RepoRoot
    $bindings = [Collections.Generic.List[object]]::new()
    function Add-CurrentStageBinding(
        [string]$SourcePath,[string]$DestinationPath,[string]$StageScope,
        [string]$OwnerClass,[string]$Architecture,[string]$InstallScope) {
        $bindings.Add([pscustomobject][ordered]@{
            source_path=$SourcePath;destination_path=$DestinationPath;stage_scope=$StageScope
            owner_class=$OwnerClass;architecture=$Architecture;install_scope=$InstallScope
        })
    }
    Add-CurrentStageBinding 'version.txt' 'version.txt' 'payload' 'metadata' 'neutral' 'installed'
    Add-CurrentStageBinding 'backends.json' 'backends.json' 'payload' 'metadata' 'neutral' 'installed'
    foreach ($mapping in @(
        @('LICENSE.txt','LICENSE.txt'),@('NOTICE.md','NOTICE.md'),@('AUTHORS.txt','AUTHORS.txt'),
        @('THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'),@('LGPL-2.0.txt','LGPL-2.0.txt'),
        @('APACHE-2.0.txt','APACHE-2.0.txt'),@('json/LICENSE.MIT','NLOHMANN-JSON-MIT.txt'),
        @('LICENSES/PIME-UPSTREAM-LICENSE.txt','PIME-UPSTREAM-LICENSE.txt'),
        @('LICENSES/RIME-BSD-3-Clause.txt','RIME-BSD-3-Clause.txt'),
        @('LICENSES/RIME-FROST-GPL-3.0.txt','RIME-FROST-GPL-3.0.txt'),
        @('LICENSES/SIL-OFL-1.1.txt','SIL-OFL-1.1.txt'),
        @('LICENSES/UNICODE-3.0.txt','UNICODE-3.0.txt'),
        @('LICENSES/RUST-DEPENDENCIES.md','RUST-DEPENDENCIES.md')
    )) {
        Add-CurrentStageBinding $mapping[0] ('licenses/' + $mapping[1]) 'payload' 'license' 'neutral' 'installed'
    }
    Add-CurrentStageBinding 'build/PIMELauncher/PIMELauncher.exe' 'PIMELauncher.exe' 'payload' 'runtime' 'x86' 'installed'
    Add-CurrentStageBinding 'build/PIMETextService/Release/PIMETextService.dll' 'x86/PIMETextService.dll' 'payload' 'text-service' 'x86' 'installed'
    Add-CurrentStageBinding 'build64/PIMETextService/Release/PIMETextService.dll' 'x64/PIMETextService.dll' 'payload' 'text-service' 'x64' 'installed'

    $inventoryRelative = 'tools/dual-product/rime-pime-go-payload-inventory.json'
    $inventory = Read-RimePimeGoPayloadInventory -SourceRoot $root -InventoryPath $inventoryRelative -VerifySourceTree
    $goRootRelative = [string]$inventory.SourceRoot
    foreach ($sourcePath in @($inventory.SourcePaths)) {
        $suffix = $sourcePath.Substring($goRootRelative.Length + 1)
        $architecture = if (Test-RimePimePortableExecutableFile (Get-RimePimeStageFullPath $root $sourcePath)) { 'x64' } else { 'neutral' }
        Add-CurrentStageBinding $sourcePath ('go-backend/' + $suffix) 'payload' 'backend' $architecture 'installed'
    }
    foreach ($helper in @(
        'rime-pime-target-user.ps1','invoke-rime-pime-target-user.ps1','rime-pime-ownership.ps1',
        'rime-pime-directed-stop-contract.ps1','invoke-rime-pime-maintenance.ps1'
    )) {
        Add-CurrentStageBinding ('tools/dual-product/' + $helper) $helper 'bootstrap' 'maintenance' 'neutral' 'transient'
    }
    Add-CurrentStageBinding 'build/PIMETextService/Release/PIMETextService.dll' 'PIMETextService_x86.dll' 'bootstrap' 'text-service' 'x86' 'transient'
    Add-CurrentStageBinding 'build64/PIMETextService/Release/PIMETextService.dll' 'PIMETextService_x64.dll' 'bootstrap' 'text-service' 'x64' 'transient'
    Add-CurrentStageBinding 'build/PIMETextService/Release/PIMERegistrationStatus.exe' 'PIMERegistrationStatus_x86.exe' 'bootstrap' 'maintenance' 'x86' 'transient'
    Add-CurrentStageBinding 'build64/PIMETextService/Release/PIMERegistrationStatus.exe' 'PIMERegistrationStatus_x64.exe' 'bootstrap' 'maintenance' 'x64' 'transient'

    $declaredSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($binding in $bindings) { $null=$declaredSources.Add([string]$binding.source_path) }
    foreach ($artifact in @($Package.Plan.artifacts)) {
        if (-not $declaredSources.Contains([string]$artifact.path)) {
            throw "Sealed package-plan artifact has no stage binding: $($artifact.path)"
        }
    }
    return [pscustomobject]@{
        CopyBindings=@($bindings)
        ClosedSourceTrees=@([pscustomobject][ordered]@{
            source_root=$goRootRelative;destination_root='go-backend';stage_scope='payload'
            inventory_path=$inventoryRelative;inventory_sha256=[string]$inventory.Digest
        })
        GeneratedOutputs=@([pscustomobject][ordered]@{
            destination_path='Uninstall.exe';stage_scope='payload';generator_id='nsis-uninstaller-prebuild-v1'
            identity_policy_id='authenticode-rime-pime-uninstaller-v1';owner_class='runtime'
            architecture='x86';install_scope='installed'
        })
    }
}

function Assert-RimePimePackagePlanStageBindings {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$ContentManifest
    )
    if ([string]$ContentManifest.package_plan_sha256 -cne [string]$Package.Digest) {
        throw 'Copied stage names a different package plan.'
    }
    $planBySource = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($artifact in @($Package.Plan.artifacts)) {
        $sourcePath = Assert-RimePimeStagePathWithinLimits ([string]$artifact.path)
        if ($planBySource.ContainsKey($sourcePath)) {
            throw "Package plan contains a duplicate artifact path: $sourcePath"
        }
        $planBySource.Add($sourcePath,$artifact)
    }
    if ($planBySource.Count -lt 1) { throw 'Package plan does not contain any staged PE artifacts.' }

    $bindingCounts = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
    foreach ($sourcePath in $planBySource.Keys) { $bindingCounts.Add($sourcePath,0) }
    foreach ($row in @($ContentManifest.files)) {
        $sourcePath = Assert-RimePimeStagePathWithinLimits ([string]$row.source_path)
        $isArchitectureBound = [string]$row.architecture -cin @('x86','x64')
        if ($isArchitectureBound -and -not $planBySource.ContainsKey($sourcePath)) {
            throw "Architecture-bound copied stage input is absent from the package plan: $sourcePath"
        }
        if (-not $planBySource.ContainsKey($sourcePath)) { continue }
        $artifact = $planBySource[$sourcePath]
        if ([long]$row.bytes -ne [long]$artifact.size -or
            [string]$row.sha256 -cne [string]$artifact.sha256 -or
            [string]$row.architecture -cne [string]$artifact.architecture) {
            throw "Copied stage input differs from its sealed package-plan artifact: $sourcePath"
        }
        $bindingCounts[$sourcePath] = [int]$bindingCounts[$sourcePath] + 1
    }
    foreach ($sourcePath in $planBySource.Keys) {
        if ([int]$bindingCounts[$sourcePath] -lt 1) {
            throw "Package-plan artifact has no copied stage destination: $sourcePath"
        }
    }
    return [pscustomobject]@{
        passed=$true
        package_plan_artifact_count=[int]$planBySource.Count
        matching_stage_binding_count=[int](($bindingCounts.Values | Measure-Object -Sum).Sum)
    }
}

function Assert-RimePimeStagedProductVersion {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)]$ContentManifest
    )
    $rows=@($ContentManifest.files|Where-Object{
        [string]$_.stage_scope -ceq 'payload' -and [string]$_.path -ceq 'version.txt' -and
        [string]$_.source_path -ceq 'version.txt'
    })
    if($rows.Count -ne 1){throw 'Copied stage does not contain exactly one canonical version.txt.'}
    $path=Join-Path (Join-Path ([IO.Path]::GetFullPath($StageRoot)) 'payload') 'version.txt'
    $record=Get-YimePimePayloadFileRecord $path
    $text=[IO.File]::ReadAllText($path).Trim()
    if($text -cne [string]$ContentManifest.product_version -or
        [long]$record.bytes -ne [long]$rows[0].bytes -or [string]$record.sha256 -cne [string]$rows[0].sha256){
        throw 'Copied version.txt differs from the staged product version identity.'
    }
    return $text
}

function Copy-RimePimeStageFile {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)]$ExpectedSource
    )
    $before = Get-YimePimePayloadFileRecord $SourcePath
    if ([long]$before.bytes -ne [long]$ExpectedSource.source_bytes -or
        [string]$before.sha256 -cne [string]$ExpectedSource.source_sha256) {
        throw "Source changed before stage copy: $($ExpectedSource.source_path)"
    }
    $sourceStream = [IO.File]::Open($SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $destinationStream = [IO.File]::Open($DestinationPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $sourceStream.CopyTo($destinationStream) }
        finally { $destinationStream.Dispose() }
    } finally { $sourceStream.Dispose() }
    $after = Get-YimePimePayloadFileRecord $SourcePath
    $copied = Get-YimePimePayloadFileRecord $DestinationPath
    if ([string]$before.file_id -cne [string]$after.file_id -or [long]$before.bytes -ne [long]$after.bytes -or
        [string]$before.sha256 -cne [string]$after.sha256 -or [long]$copied.bytes -ne [long]$before.bytes -or
        [string]$copied.sha256 -cne [string]$before.sha256) {
        throw "Source identity or copied bytes changed during stage copy: $($ExpectedSource.source_path)"
    }
    return $copied
}

function Read-RimePimeCopiedContentManifest {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ExpectedDigest
    )
    if ($ExpectedDigest -cnotmatch '^[0-9a-f]{64}$') { throw 'Expected copied-content digest is invalid.' }
    $sealed = Read-RimePimeSealedJson $ManifestPath 'copied-content manifest'
    if ([string]$sealed.Digest -cne $ExpectedDigest) { throw 'Copied-content manifest does not match its external digest.' }
    $manifest = $sealed.Value
    Assert-YimePimePayloadProperties $manifest @(
        'schema_version','product','product_version','package_profile','architectures','phase','hash_algorithm',
        'directory_policy','package_plan_sha256','payload_spec_sha256','content_tree_sha256','directories','files',
        'pending_generated_outputs','final_payload_closure') 'copied-content manifest'
    $architectures=@($manifest.architectures)
    if ([string]$manifest.schema_version -cne $script:RimePimeStageContentSchema -or
        [string]$manifest.product -cne 'rime-pime' -or
        [string]$manifest.product_version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$' -or
        [string]$manifest.package_profile -cne 'x86-x64-v1' -or
        $architectures.Count -ne 2 -or [string]$architectures[0] -cne 'x86' -or [string]$architectures[1] -cne 'x64' -or
        [string]$manifest.phase -cne 'copied-inputs-awaiting-generated-output' -or
        [string]$manifest.hash_algorithm -cne 'sha256' -or
        [string]$manifest.directory_policy -cne 'derived-nonempty-only-v1' -or
        [string]$manifest.package_plan_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.payload_spec_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.content_tree_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $manifest.final_payload_closure -isnot [bool] -or $manifest.final_payload_closure) {
        throw 'Copied-content manifest identity or evidence boundary is invalid.'
    }
    $files=@($manifest.files)
    $directories=@($manifest.directories)
    if($files.Count -lt 1 -or $files.Count -gt $script:RimePimeStageLimits.max_files -or
        $directories.Count -gt $script:RimePimeStageLimits.max_directories){
        throw 'Copied-content manifest file or directory count is outside the sealed bound.'
    }
    $previous=$null
    $totalBytes=[long]0
    $fileSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $files){
        Assert-YimePimePayloadProperties $row @(
            'stage_scope','path','bytes','sha256','owner_class','architecture','install_scope','origin_class','source_path') `
            'copied-content file record'
        $path=Assert-RimePimeStagePathWithinLimits ([string]$row.path)
        $key=[string]$row.stage_scope+'/'+$path
        if([string]$row.stage_scope -notin @('payload','bootstrap') -or -not (Test-RimePimeStageInteger $row.bytes) -or
            [long]$row.bytes -lt 0 -or [long]$row.bytes -gt $script:RimePimeStageLimits.max_file_bytes -or
            [string]$row.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$row.owner_class -notin @('metadata','license','runtime','backend','text-service','maintenance') -or
            [string]$row.architecture -notin @('neutral','x86','x64') -or
            ([string]$row.stage_scope -ceq 'payload' -and [string]$row.install_scope -cne 'installed') -or
            ([string]$row.stage_scope -ceq 'bootstrap' -and [string]$row.install_scope -cne 'transient') -or
            [string]$row.origin_class -cne 'copied' -or
            ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$key) -ge 0)){
            throw 'Copied-content file record is invalid or unordered.'
        }
        if(-not $fileSet.Add($key)){throw "Case-folded duplicate copied-content file: $key"}
        $null=Assert-RimePimeStagePathWithinLimits ([string]$row.source_path)
        $totalBytes += [long]$row.bytes
        if($totalBytes -gt $script:RimePimeStageLimits.max_total_bytes){
            throw 'Copied-content bytes exceed the sealed total bound.'
        }
        $previous=$key
    }
    $previous=$null
    $directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $directories){
        Assert-YimePimePayloadProperties $row @('stage_scope','path','owner_class','removal_policy','install_scope') `
            'copied-content directory record'
        $path=Assert-RimePimeStagePathWithinLimits ([string]$row.path)
        $key=[string]$row.stage_scope+'/'+$path
        if([string]$row.stage_scope -notin @('payload','bootstrap') -or
            [string]$row.owner_class -notin @('metadata','license','runtime','backend','text-service','maintenance') -or
            ([string]$row.stage_scope -ceq 'payload' -and
                ([string]$row.removal_policy -cne 'owned-tree-exact' -or [string]$row.install_scope -cne 'installed')) -or
            ([string]$row.stage_scope -ceq 'bootstrap' -and
                ([string]$row.removal_policy -cne 'transient-delete' -or [string]$row.install_scope -cne 'transient')) -or
            ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$key) -ge 0)){
            throw 'Copied-content directory record is invalid or unordered.'
        }
        if(-not $directorySet.Add($key)){throw "Case-folded duplicate copied-content directory: $key"}
        if($fileSet.Contains($key)){throw "Copied-content path is both file and directory: $key"}
        $previous=$key
    }
    $derivedInputs=@($files|ForEach-Object{[pscustomobject][ordered]@{
        destination_path=[string]$_.path;stage_scope=[string]$_.stage_scope;owner_class=[string]$_.owner_class
        install_scope=[string]$_.install_scope
    }})
    $derived=@(Get-RimePimeDerivedStageDirectories $derivedInputs)
    if($derived.Count -ne $directories.Count){throw 'Copied-content directories are not the exact derived nonempty set.'}
    for($i=0;$i -lt $derived.Count;$i++){
        foreach($name in @('stage_scope','path','owner_class','removal_policy','install_scope')){
            if([string]$derived[$i].$name -cne [string]$directories[$i].$name){
                throw 'Copied-content directories differ from the exact derived nonempty set.'
            }
        }
    }
    $pending=@($manifest.pending_generated_outputs)
    if($pending.Count -ne 1){
        throw 'Copied-content manifest lost its pending generated uninstaller boundary.'
    }
    $generated=$pending[0]
    Assert-YimePimePayloadProperties $generated @(
        'destination_path','stage_scope','generator_id','identity_policy_id','owner_class','architecture','install_scope') `
        'copied-content pending generated output'
    $generatedPath=Assert-RimePimeStagePathWithinLimits ([string]$generated.destination_path)
    $generatedKey=[string]$generated.stage_scope+'/'+$generatedPath
    if($generatedPath -cne 'Uninstall.exe' -or [string]$generated.stage_scope -cne 'payload' -or
        [string]$generated.generator_id -cne 'nsis-uninstaller-prebuild-v1' -or
        [string]$generated.identity_policy_id -cne 'authenticode-rime-pime-uninstaller-v1' -or
        [string]$generated.owner_class -cne 'runtime' -or [string]$generated.architecture -cne 'x86' -or
        [string]$generated.install_scope -cne 'installed' -or $fileSet.Contains($generatedKey) -or
        $directorySet.Contains($generatedKey)){
        throw 'Copied-content pending generated uninstaller contract is invalid.'
    }
    $computed=Get-RimePimeStageContentDigest $directories $files
    if($computed -cne [string]$manifest.content_tree_sha256){throw 'Copied-content tree digest is invalid.'}
    return [pscustomobject]@{Manifest=$manifest;Digest=$sealed.Digest;Path=$sealed.Path;Sidecar=$sealed.Sidecar}
}

function Get-RimePimeCopiedStageSnapshot {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)]$Manifest
    )
    $stage=(Assert-YimePimePayloadAbsolutePath $StageRoot).TrimEnd('\')
    $expectedFiles=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($Manifest.files)){
        $key=[string]$row.stage_scope+'/'+[string]$row.path
        if($expectedFiles.ContainsKey($key)){throw "Duplicate expected staged file: $key"}
        $expectedFiles.Add($key,$row)
    }
    $expectedDirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($Manifest.directories)){
        $key=[string]$row.stage_scope+'/'+[string]$row.path
        if(-not $expectedDirs.Add($key)){throw "Duplicate expected staged directory: $key"}
    }
    $actualFiles=[Collections.Generic.List[object]]::new()
    $actualDirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $fileIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($scope in @('payload','bootstrap')){
        $scopeRoot=Join-Path $stage $scope
        if(-not (Test-Path -LiteralPath $scopeRoot -PathType Container)){throw "Stage scope root is missing: $scope"}
        if((Get-Item -LiteralPath $scopeRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
            throw "Stage scope root is a reparse point: $scope"
        }
        $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($scopeRoot)
        while($pending.Count){
            $directory=$pending.Pop()
            foreach($item in @(Get-ChildItem -LiteralPath $directory -Force)){
                if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Indirect staged entry rejected: $($item.FullName)"}
                $relative=$item.FullName.Substring($scopeRoot.Length+1).Replace('\','/')
                $canonical=Assert-RimePimeStagePathWithinLimits $relative
                $key=$scope+'/'+$canonical
                if($item.PSIsContainer){
                    if(-not $expectedDirs.Contains($key)){throw "Unlisted or empty staged directory: $key"}
                    $null=$actualDirs.Add($key);$pending.Push($item.FullName);continue
                }
                if(-not $expectedFiles.ContainsKey($key)){throw "Unlisted staged file: $key"}
                $wanted=$expectedFiles[$key]
                if([string]$wanted.path -cne $canonical){throw "Staged file path case mismatch: $key"}
                $record=Get-YimePimePayloadFileRecord $item.FullName
                if([long]$wanted.bytes -ne [long]$record.bytes -or [string]$wanted.sha256 -cne [string]$record.sha256){
                    throw "Staged file content mismatch: $key"
                }
                if(-not $fileIds.Add([string]$record.file_id)){throw "Duplicate staged file identity: $key"}
                $actualFiles.Add([pscustomobject][ordered]@{
                    stage_scope=$scope;path=$canonical;bytes=[long]$record.bytes;sha256=[string]$record.sha256
                    owner_class=[string]$wanted.owner_class;architecture=[string]$wanted.architecture
                    install_scope=[string]$wanted.install_scope;origin_class=[string]$wanted.origin_class
                    source_path=[string]$wanted.source_path;file_id=[string]$record.file_id
                })
            }
        }
    }
    if($actualFiles.Count -ne $expectedFiles.Count){throw 'Copied stage has missing files.'}
    if($actualDirs.Count -ne $expectedDirs.Count){throw 'Copied stage has missing directories.'}
    $contentFiles=@($actualFiles | ForEach-Object {[pscustomobject][ordered]@{
        stage_scope=$_.stage_scope;path=$_.path;bytes=$_.bytes;sha256=$_.sha256;owner_class=$_.owner_class
        architecture=$_.architecture;install_scope=$_.install_scope;origin_class=$_.origin_class
    }})
    $total=[long]0;foreach($file in $actualFiles){$total += [long]$file.bytes}
    return [pscustomobject][ordered]@{
        files=@($actualFiles);directories=@($Manifest.directories);file_count=$actualFiles.Count
        directory_count=$actualDirs.Count;total_bytes=$total
        content_tree_sha256=(Get-RimePimeStageContentDigest @($Manifest.directories) $contentFiles)
        local_observation_sha256=(Get-RimePimeStageObservationDigest @($actualFiles))
    }
}

function Test-RimePimePackageCopyStage {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ExpectedManifestDigest,
        [scriptblock]$BetweenPassHook
    )
    $stage=(Assert-YimePimePayloadAbsolutePath $StageRoot).TrimEnd('\')
    $manifestFull=Assert-YimePimePayloadAbsolutePath $ManifestPath
    if($manifestFull.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'Copied-content manifest must remain outside the mutable stage tree.'
    }
    $sealed=Read-RimePimeCopiedContentManifest $manifestFull $ExpectedManifestDigest
    $rootItems=@(Get-ChildItem -LiteralPath $stage -Force)
    if($rootItems.Count -ne 2 -or @($rootItems | Where-Object {$_.PSIsContainer -and $_.Name -cin @('payload','bootstrap')}).Count -ne 2){
        throw 'Copied stage root must contain exactly payload and bootstrap directories.'
    }
    $first=Get-RimePimeCopiedStageSnapshot $stage $sealed.Manifest
    if($first.content_tree_sha256 -cne [string]$sealed.Manifest.content_tree_sha256){
        throw 'Copied stage does not match the portable content digest.'
    }
    if($null -ne $BetweenPassHook){& $BetweenPassHook $stage}
    $second=Get-RimePimeCopiedStageSnapshot $stage $sealed.Manifest
    foreach($name in @('file_count','directory_count','total_bytes','content_tree_sha256','local_observation_sha256')){
        if([string]$first.$name -cne [string]$second.$name){throw "Copied stage changed between verification passes: $name"}
    }
    return [pscustomobject][ordered]@{
        passed=$true;file_count=$second.file_count;directory_count=$second.directory_count;total_bytes=$second.total_bytes
        content_tree_sha256=$second.content_tree_sha256;local_observation_sha256=$second.local_observation_sha256
        final_payload_closure=$false;pending_generated_output_count=@($sealed.Manifest.pending_generated_outputs).Count
        actual_installer_or_uninstaller_executed=$false;registry_or_process_touched=$false
        default_input_method_changed=$false;production_user_data_read_or_written=$false
    }
}

function New-RimePimePackageCopyStage {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$AllowedStageParent,
        [Parameter(Mandatory)][string]$SpecPath,
        [Parameter(Mandatory)][string]$ExpectedSpecDigest,
        [Parameter(Mandatory)][string]$ContentManifestPath,
        [Parameter(Mandatory)][string]$ObservationPath
    )
    $source=Assert-YimePimePayloadAbsolutePath $SourceRoot
    $parent=(Assert-YimePimePayloadAbsolutePath $AllowedStageParent).TrimEnd('\')
    $stage=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
    if((Split-Path -Parent $stage) -ine $parent -or (Test-Path -LiteralPath $stage)){
        throw 'Stage root must be a new immediate child of its explicitly allowed parent.'
    }
    foreach($outside in @($ContentManifestPath,$ObservationPath)){
        $full=[IO.Path]::GetFullPath($outside)
        if($full.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)){
            throw 'Stage evidence must be outside the copied stage tree.'
        }
    }
    $spec=Read-RimePimePackageStageSpec $source $SpecPath $ExpectedSpecDigest -VerifySources
    New-Item -ItemType Directory -Path $stage | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stage 'payload'),(Join-Path $stage 'bootstrap') | Out-Null
    foreach($directory in @($spec.Spec.directories)){
        $scopeRoot=Join-Path $stage ([string]$directory.stage_scope)
        $path=Get-RimePimeStageFullPath $scopeRoot ([string]$directory.path)
        if(-not (Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Path $path | Out-Null}
    }
    $manifestFiles=[Collections.Generic.List[object]]::new()
    foreach($row in @($spec.Spec.copy_files)){
        $sourcePath=Get-RimePimeStageFullPath $source ([string]$row.source_path)
        $scopeRoot=Join-Path $stage ([string]$row.stage_scope)
        $destination=Get-RimePimeStageFullPath $scopeRoot ([string]$row.destination_path)
        $record=Copy-RimePimeStageFile $sourcePath $destination $row
        $manifestFiles.Add([pscustomobject][ordered]@{
            stage_scope=[string]$row.stage_scope;path=[string]$row.destination_path;bytes=[long]$record.bytes
            sha256=[string]$record.sha256;owner_class=[string]$row.owner_class;architecture=[string]$row.architecture
            install_scope=[string]$row.install_scope;origin_class='copied';source_path=[string]$row.source_path
        })
    }
    $fileOrder=Get-RimePimeOrdinalKeys @($manifestFiles) {param($row) "$($row.stage_scope)`0$($row.path)"}
    $sortedFiles=@($fileOrder.Keys | ForEach-Object {$fileOrder.Map[$_]})
    $contentRows=@($sortedFiles | ForEach-Object {[pscustomobject][ordered]@{
        stage_scope=$_.stage_scope;path=$_.path;bytes=$_.bytes;sha256=$_.sha256;owner_class=$_.owner_class
        architecture=$_.architecture;install_scope=$_.install_scope;origin_class=$_.origin_class
    }})
    $contentDigest=Get-RimePimeStageContentDigest @($spec.Spec.directories) $contentRows
    $content=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeStageContentSchema;product='rime-pime';product_version=[string]$spec.Spec.product_version
        package_profile='x86-x64-v1';architectures=@('x86','x64');phase='copied-inputs-awaiting-generated-output'
        hash_algorithm='sha256';directory_policy='derived-nonempty-only-v1';package_plan_sha256=[string]$spec.Spec.package_plan_sha256
        payload_spec_sha256=$spec.Digest;content_tree_sha256=$contentDigest;directories=@($spec.Spec.directories)
        files=@($sortedFiles);pending_generated_outputs=@($spec.Spec.generated_outputs);final_payload_closure=$false
    }
    $manifestDigest=Write-RimePimeStageSealedJson $content $ContentManifestPath
    $verified=Test-RimePimePackageCopyStage $stage $ContentManifestPath $manifestDigest
    $observation=[pscustomobject][ordered]@{
        schema_version=$script:RimePimeStageObservationSchema;product='rime-pime';phase='copied-inputs-awaiting-generated-output'
        source_root=$source;stage_root=$stage;payload_spec_path=[IO.Path]::GetFullPath($SpecPath)
        payload_spec_sha256=$spec.Digest;content_manifest_path=[IO.Path]::GetFullPath($ContentManifestPath)
        content_manifest_sha256=$manifestDigest;content_tree_sha256=$verified.content_tree_sha256
        local_observation_sha256=$verified.local_observation_sha256;file_count=$verified.file_count
        directory_count=$verified.directory_count;total_bytes=$verified.total_bytes;verification_passes=2
        generated_at_utc=[DateTime]::UtcNow.ToString('o');final_payload_closure=$false
        actual_installer_or_uninstaller_executed=$false;registry_or_process_touched=$false
        default_input_method_changed=$false;production_user_data_read_or_written=$false
    }
    $observationDigest=Write-RimePimeStageSealedJson $observation $ObservationPath
    return [pscustomobject]@{
        StageRoot=$stage;Spec=$spec;ContentManifestPath=[IO.Path]::GetFullPath($ContentManifestPath)
        ContentManifestDigest=$manifestDigest;ObservationPath=[IO.Path]::GetFullPath($ObservationPath)
        ObservationDigest=$observationDigest;Verification=$verified
    }
}
