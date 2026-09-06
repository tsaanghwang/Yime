[CmdletBinding()]
param(
    [switch]$WritePlan,
    [string]$PlanRepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$OutputPlanPath = (Join-Path (Join-Path $PSScriptRoot '..\..') 'installer\package-plan.json')
)

$ErrorActionPreference = 'Stop'

function Assert-RimePimeExactProperties($Value,[string[]]$Expected,[string]$Context) {
    if ($null -eq $Value -or $Value -is [string] -or $null -eq $Value.PSObject) {
        throw "$Context must be an object."
    }
    $actual=@($Value.PSObject.Properties | ForEach-Object Name)
    if ($actual.Count -ne $Expected.Count) { throw "$Context has an open or incomplete schema." }
    foreach ($name in $Expected) {
        if ($actual -cnotcontains $name) { throw "$Context is missing exact property $name." }
    }
}

function ConvertTo-RimePimePackagePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.EndsWith('/') -or
        $Path.Contains('//') -or $Path -match '[\x00-\x1f<>:"|?*]' -or
        -not $Path.IsNormalized([Text.NormalizationForm]::FormC)) {
        throw "Non-canonical package-plan path: $Path"
    }
    foreach ($segment in $Path.Split('/')) {
        if (-not $segment -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Ambiguous package-plan path: $Path"
        }
    }
    return $Path
}

function Assert-RimePimeNoReparsePath([string]$Path) {
    for ($cursor=[IO.Path]::GetFullPath($Path); $cursor; $cursor=Split-Path -Parent $cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Package-plan path traverses a reparse point: $cursor"
        }
        if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
    }
}

function Resolve-RimePimePackageFile([string]$Root,[string]$RelativePath) {
    $relative=ConvertTo-RimePimePackagePath $RelativePath
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $full=[IO.Path]::GetFullPath((Join-Path $rootFull $relative.Replace('/','\')))
    if (-not $full.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Package-plan path escapes the repository root: $relative"
    }
    return $full
}

function Test-RimePimePortableExecutableFile([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $reader=[IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position=0x3c
        $peOffset=[uint32]$reader.ReadUInt32()
        if ([uint64]$peOffset+4 -gt [uint64]$stream.Length) { return $false }
        $stream.Position=$peOffset
        return $reader.ReadUInt32() -eq 0x00004550
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-RimePimePackagedPePaths([string]$Root,[string]$TreeRelativePath) {
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $tree=Resolve-RimePimePackageFile $rootFull $TreeRelativePath
    if (-not (Test-Path -LiteralPath $tree -PathType Container)) { throw "Packaged tree is missing: $TreeRelativePath" }
    $pending=[Collections.Generic.Stack[string]]::new()
    $pending.Push($tree)
    $results=[Collections.Generic.List[string]]::new()
    while($pending.Count){
        $directory=$pending.Pop()
        Assert-RimePimeNoReparsePath $directory
        foreach($item in @(Get-ChildItem -LiteralPath $directory -Force)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
                throw "Packaged tree contains a reparse point: $($item.FullName)"
            }
            if($item.PSIsContainer){
                $pending.Push($item.FullName)
            }elseif(Test-RimePimePortableExecutableFile $item.FullName){
                $results.Add($item.FullName.Substring($rootFull.Length+1).Replace('\','/'))
            }
        }
    }
    return @($results | Sort-Object)
}

function Get-RimePimePackageArtifactSpecs([string[]]$ArchitectureSet) {
    $architectures=@($ArchitectureSet)
    if ($architectures.Count -eq 2 -and
        $architectures[0] -ceq 'x86' -and $architectures[1] -ceq 'x64') {
        return @(
            [pscustomobject]@{path='build/PIMELauncher/PIMELauncher.exe';architecture='x86'},
            [pscustomobject]@{path='build/PIMETextService/Release/PIMETextService.dll';architecture='x86'},
            [pscustomobject]@{path='build/PIMETextService/Release/PIMERegistrationStatus.exe';architecture='x86'},
            [pscustomobject]@{path='build64/PIMETextService/Release/PIMETextService.dll';architecture='x64'},
            [pscustomobject]@{path='build64/PIMETextService/Release/PIMERegistrationStatus.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/server.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/tool-hub.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/yime-trainer.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/input-toolbar.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/settings-tool.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/diagnostics-tool.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/yime-layout-designer.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/lexicon-manager.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/reverse-lookup.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/system-lexicon-audit.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/lexicon-promotion-scan.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/blocklist-manager.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/input_methods/yime/rime.dll';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/input_methods/yime/rime_deployer.exe';architecture='x64'},
            [pscustomobject]@{path='go-backend/build/go-backend/input_methods/yime/rime_dict_manager.exe';architecture='x64'}
        )
    }
    if ($architectures.Count -eq 2 -and
        $architectures[0] -ceq 'x86' -and $architectures[1] -ceq 'arm64x') {
        throw 'The x86/arm64x package-plan profile is reserved but not admitted until Arm64X artifacts and the three-host matrix are sealed.'
    }
    throw "Unsupported ordered package architecture set: $($architectures -join ',')"
}

function Test-RimePimeUtcTimestamp($Value) {
    if ($Value -is [datetime]) { return ([datetime]$Value).Kind -eq [DateTimeKind]::Utc }
    $parsed=[DateTimeOffset]::MinValue
    return ([string]$Value -cmatch 'Z$') -and
        [DateTimeOffset]::TryParse([string]$Value,[ref]$parsed)
}

function Write-RimePimeSealedJson($Value,[string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    $sidecar=$full+'.sha256'
    Assert-RimePimeNoReparsePath $full
    Assert-RimePimeNoReparsePath $sidecar
    $parent=Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Assert-RimePimeNoReparsePath $parent
    Assert-RimePimeNoReparsePath $full
    Assert-RimePimeNoReparsePath $sidecar
    $utf8=New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($full,($Value | ConvertTo-Json -Depth 8)+"`n",$utf8)
    $digest=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($sidecar,"$digest  $([IO.Path]::GetFileName($full))`n",(New-Object Text.ASCIIEncoding))
    return $digest
}

function Read-RimePimeSealedLeaseBytes([IO.FileStream]$Stream,[long]$Maximum,[string]$Context) {
    if($null -eq $Stream -or -not $Stream.CanRead -or -not $Stream.CanSeek){throw "$Context read lease is invalid."}
    $length=[long]$Stream.Length
    if($length -le 0 -or $length -gt $Maximum){throw "$Context size is outside its sealed bound."}
    $bytes=New-Object byte[] ([int]$length)
    $Stream.Position=0;$offset=0
    while($offset -lt $bytes.Length){
        $read=$Stream.Read($bytes,$offset,$bytes.Length-$offset)
        if($read -le 0){throw "$Context ended before its leased length."}
        $offset+=$read
    }
    if($Stream.ReadByte() -ne -1){throw "$Context grew while its read lease was held."}
    $Stream.Position=0
    return ,$bytes
}

function Open-RimePimeSealedJsonReadLeases([string]$Path,[string]$Context) {
    $full=[IO.Path]::GetFullPath($Path);$sidecar=$full+'.sha256'
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Context is missing: $full" }
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { throw "$Context SHA-256 sidecar is missing: $sidecar" }
    Assert-RimePimeNoReparsePath $full;Assert-RimePimeNoReparsePath $sidecar
    $jsonStream=$null;$sidecarStream=$null
    try{
        $jsonStream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sidecarStream=[IO.File]::Open($sidecar,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        # Re-check after both non-write/non-delete leases are held. The parsed
        # value and returned digest below are derived from JsonBytes, never from
        # a second path read.
        Assert-RimePimeNoReparsePath $full;Assert-RimePimeNoReparsePath $sidecar
        $jsonBytes=Read-RimePimeSealedLeaseBytes $jsonStream 1048576 $Context
        $sidecarBytes=Read-RimePimeSealedLeaseBytes $sidecarStream 256 "$Context SHA-256 sidecar"
        return [pscustomobject]@{
            Path=$full;Sidecar=$sidecar;JsonStream=$jsonStream;SidecarStream=$sidecarStream
            JsonBytes=[byte[]]$jsonBytes;SidecarBytes=[byte[]]$sidecarBytes
        }
    }catch{
        if($null -ne $sidecarStream){$sidecarStream.Dispose()}
        if($null -ne $jsonStream){$jsonStream.Dispose()}
        throw
    }
}

function Read-RimePimeSealedJson([string]$Path,[string]$Context) {
    $leases=Open-RimePimeSealedJsonReadLeases $Path $Context
    try{
        foreach($one in $leases.SidecarBytes){if($one -gt 127){throw "$Context SHA-256 sidecar is not ASCII."}}
        $sidecarText=[Text.Encoding]::ASCII.GetString($leases.SidecarBytes)
        $expectedPattern='^([0-9a-f]{64})  '+[regex]::Escape([IO.Path]::GetFileName($leases.Path))+'\r?\n?$'
        if ($sidecarText -cnotmatch $expectedPattern) { throw "$Context SHA-256 sidecar is malformed." }
        $expected=[string]$Matches[1]
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=([BitConverter]::ToString($sha.ComputeHash([byte[]]$leases.JsonBytes))).Replace('-','').ToLowerInvariant()}
        finally{$sha.Dispose()}
        if ($actual -cne $expected) { throw "$Context SHA-256 sidecar does not match its JSON bytes." }
        $strictUtf8=New-Object Text.UTF8Encoding($false,$true)
        try{
            $jsonText=$strictUtf8.GetString([byte[]]$leases.JsonBytes)
            if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){
                $value=$jsonText|ConvertFrom-Json -DateKind String
            }else{$value=$jsonText|ConvertFrom-Json}
        }
        catch{throw "Invalid $Context JSON or UTF-8: $($_.Exception.Message)"}
        return [pscustomobject]@{Value=$value;Digest=$actual;Path=$leases.Path;Sidecar=$leases.Sidecar}
    }finally{
        $leases.SidecarStream.Dispose();$leases.JsonStream.Dispose()
    }
}

function Write-RimePimePackagePlan(
    [string]$RepoRoot,
    [string]$PlanPath,
    [string[]]$ArchitectureSet=@('x86','x64')
) {
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $plan=[IO.Path]::GetFullPath($PlanPath)
    Assert-RimePimeNoReparsePath $root
    if (-not $plan.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package plan must be written inside the repository root.'
    }
    $specs=@(Get-RimePimePackageArtifactSpecs $ArchitectureSet)
    $rows=@()
    foreach ($spec in $specs) {
        $path=Resolve-RimePimePackageFile $root $spec.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required package artifact is missing: $($spec.path)" }
        Assert-RimePimeNoReparsePath $path
        $item=Get-Item -LiteralPath $path -Force
        $rows+=@([pscustomobject][ordered]@{
            path=$spec.path
            architecture=$spec.architecture
            size=[long]$item.Length
            sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    $value=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-plan-v1'
        product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'
        architectures=@($ArchitectureSet)
        hash_algorithm='sha256'
        sealed_at_utc=[DateTime]::UtcNow.ToString('o')
        artifacts=@($rows)
    }
    Write-RimePimeSealedJson $value $plan | Out-Null
    return Read-RimePimePackagePlan -RepoRoot $root -PlanPath $plan -VerifyArtifacts
}

function Assert-RimePimePackagePlanValue {
    param([Parameter(Mandatory)]$Plan)
    $plan=$Plan
    Assert-RimePimeExactProperties $plan @(
        'schema_version','product','closure_scope','architectures','hash_algorithm','sealed_at_utc','artifacts') 'package plan'
    $architectures=@($plan.architectures)
    if ($plan.schema_version -isnot [string] -or
        $plan.product -isnot [string] -or
        $plan.closure_scope -isnot [string] -or
        $plan.hash_algorithm -isnot [string] -or
        $plan.sealed_at_utc -isnot [string] -or
        $plan.architectures -isnot [Array] -or $architectures.Count -ne 2 -or
        $plan.artifacts -isnot [Array] -or
        $architectures[0] -isnot [string] -or $architectures[1] -isnot [string] -or
        [string]$architectures[0] -cne 'x86' -or [string]$architectures[1] -cne 'x64' -or
        [string]$plan.schema_version -cne 'yime-rime-pime-package-plan-v1' -or
        [string]$plan.product -cne 'rime-pime' -or
        [string]$plan.closure_scope -cne 'declared-packaged-product-pe-inputs-only-not-installed-payload' -or
        [string]$plan.hash_algorithm -cne 'sha256' -or
        -not (Test-RimePimeUtcTimestamp $plan.sealed_at_utc)) {
        throw 'Package plan identity or seal metadata is invalid.'
    }
    $specs=@(Get-RimePimePackageArtifactSpecs @($plan.architectures))
    $rows=@($plan.artifacts)
    if ($rows.Count -ne $specs.Count) { throw 'Package plan does not contain the exact declared product PE input set.' }
    $seen=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $rows) {
        Assert-RimePimeExactProperties $row @('path','architecture','size','sha256') 'package-plan artifact'
        if ($row.path -isnot [string] -or $row.architecture -isnot [string] -or $row.sha256 -isnot [string]) {
            throw 'Package-plan artifact strings have invalid JSON types.'
        }
        $relative=ConvertTo-RimePimePackagePath ([string]$row.path)
        if ($seen.ContainsKey($relative)) { throw "Case-folded duplicate package artifact: $relative" }
        $minimumPeBytes=if ([string]$row.architecture -ceq 'x86') { 122L } else { 138L }
        if (-not ($row.size -is [int] -or $row.size -is [long]) -or [long]$row.size -lt $minimumPeBytes -or
            [string]$row.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Invalid package artifact size or SHA-256: $relative"
        }
        $seen.Add($relative,$row)
    }
    for ($i=0;$i -lt $specs.Count;$i++) {
        $spec=$specs[$i]
        $row=$rows[$i]
        if ([string]$row.path -cne [string]$spec.path -or
            [string]$row.architecture -cne [string]$spec.architecture) {
            throw "Package plan artifact order, path, or architecture drifted at index $i."
        }
    }
    return [pscustomobject]@{Plan=$plan;Specs=@($specs);Rows=@($rows)}
}

function Read-RimePimePackagePlan(
    [string]$RepoRoot,
    [string]$PlanPath,
    [switch]$VerifyArtifacts
) {
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $planFull=[IO.Path]::GetFullPath($PlanPath)
    if (-not $planFull.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package plan must stay inside the repository root.'
    }
    $sealed=Read-RimePimeSealedJson $planFull 'package plan'
    $validated=Assert-RimePimePackagePlanValue $sealed.Value
    $plan=$validated.Plan
    $specs=@($validated.Specs)
    $rows=@($validated.Rows)
    for ($i=0;$i -lt $specs.Count;$i++) {
        $spec=$specs[$i]
        $row=$rows[$i]
        if ($VerifyArtifacts) {
            $path=Resolve-RimePimePackageFile $root $spec.path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package artifact is missing: $($spec.path)" }
            Assert-RimePimeNoReparsePath $path
            $item=Get-Item -LiteralPath $path -Force
            $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ([long]$row.size -ne [long]$item.Length -or [string]$row.sha256 -cne $hash) {
                throw "Package artifact content does not match the sealed plan: $($spec.path)"
            }
        }
    }
    if ($VerifyArtifacts) {
        $expectedPackagedPe=@($specs | Where-Object { $_.path.StartsWith('go-backend/build/go-backend/') } |
            ForEach-Object { $_.path } | Sort-Object)
        $actualPackagedPe=@(Get-RimePimePackagedPePaths $root 'go-backend/build/go-backend')
        if ($actualPackagedPe.Count -ne $expectedPackagedPe.Count) {
            throw "Packaged Go-tree PE set is not the exact sealed allowlist: expected $($expectedPackagedPe.Count), found $($actualPackagedPe.Count)."
        }
        for($i=0;$i -lt $expectedPackagedPe.Count;$i++){
            if($actualPackagedPe[$i] -cne $expectedPackagedPe[$i]){
                throw "Packaged Go-tree PE set differs from the sealed allowlist at index $i."
            }
        }
        $peVerifier=Join-Path $PSScriptRoot '..\verify-pe-architectures.ps1'
        & $peVerifier -RepoRoot $root `
            -X86TextService (Resolve-RimePimePackageFile $root 'build/PIMETextService/Release/PIMETextService.dll') `
            -X64TextService (Resolve-RimePimePackageFile $root 'build64/PIMETextService/Release/PIMETextService.dll') `
            -X86Launcher (Resolve-RimePimePackageFile $root 'build/PIMELauncher/PIMELauncher.exe') `
            -X86RegistrationStatus (Resolve-RimePimePackageFile $root 'build/PIMETextService/Release/PIMERegistrationStatus.exe') `
            -X64RegistrationStatus (Resolve-RimePimePackageFile $root 'build64/PIMETextService/Release/PIMERegistrationStatus.exe') `
            -RimeDll (Resolve-RimePimePackageFile $root 'go-backend/build/go-backend/input_methods/yime/rime.dll') `
            -RimeDeployer (Resolve-RimePimePackageFile $root 'go-backend/build/go-backend/input_methods/yime/rime_deployer.exe') `
            -RimeDictManager (Resolve-RimePimePackageFile $root 'go-backend/build/go-backend/input_methods/yime/rime_dict_manager.exe') `
            -GoBackendRoot (Resolve-RimePimePackageFile $root 'go-backend/build/go-backend') 6>$null | Out-Null
    }
    return [pscustomobject]@{
        Plan=$plan
        Digest=$sealed.Digest
        Path=$sealed.Path
        Sidecar=$sealed.Sidecar
        RepoRoot=$root
    }
}

function Test-RimePimeInstallerPlanDigest([string]$InstallerPath,[string]$PlanDigest) {
    $bytes=[IO.File]::ReadAllBytes($InstallerPath)
    return [Text.Encoding]::ASCII.GetString($bytes).Contains($PlanDigest) -or
        [Text.Encoding]::Unicode.GetString($bytes).Contains($PlanDigest)
}

function Read-RimePimePackageBuildReceiptEnvelope(
    [string]$RepoRoot,
    [string]$ReceiptPath
) {
    $root=[IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $receiptFull=[IO.Path]::GetFullPath($ReceiptPath)
    if (-not $receiptFull.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package build receipt must stay inside the repository root.'
    }
    $sidecar=$receiptFull+'.sha256'
    $receiptOccupied=Test-Path -LiteralPath $receiptFull
    $sidecarOccupied=Test-Path -LiteralPath $sidecar
    if (-not $receiptOccupied -and -not $sidecarOccupied) {
        return [pscustomobject]@{State='absent';SchemaVersion=$null;Sealed=$null}
    }
    if (-not $receiptOccupied -or -not $sidecarOccupied -or
        -not (Test-Path -LiteralPath $receiptFull -PathType Leaf) -or
        -not (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
        throw 'Canonical package build receipt JSON/sidecar pair is partial or not made of files.'
    }
    $sealed=Read-RimePimeSealedJson $receiptFull 'package build receipt envelope'
    $schemaProperty=$sealed.Value.PSObject.Properties['schema_version']
    if ($null -eq $schemaProperty -or -not ($schemaProperty.Value -is [string]) -or
        [string]::IsNullOrWhiteSpace([string]$schemaProperty.Value)) {
        throw 'Package build receipt envelope has no explicit schema version.'
    }
    return [pscustomobject]@{
        State='present'
        SchemaVersion=[string]$schemaProperty.Value
        Sealed=$sealed
    }
}

function Assert-RimePimePackageBuildReceiptV1Document($Receipt,$Package) {
    Assert-RimePimeExactProperties $Receipt @(
        'schema_version','product','closure_scope','architectures','package_plan_path','package_plan_sha256','nsis_profile',
        'installer_source_path','installer_source_sha256','installer_path','installer_size','installer_sha256','sealed_at_utc') `
        'package build receipt'
    $architectures=@($Receipt.architectures)
    if ([string]$Receipt.schema_version -cne 'yime-rime-pime-package-build-receipt-v1' -or
        [string]$Receipt.product -cne 'rime-pime' -or $architectures.Count -ne 2 -or
        [string]$Receipt.closure_scope -cne 'declared-packaged-product-pe-inputs-only-not-installed-payload' -or
        $architectures[0] -cne 'x86' -or $architectures[1] -cne 'x64' -or
        [string]$Receipt.package_plan_sha256 -cne $Package.Digest -or
        [string]$Receipt.nsis_profile -cne 'x86-x64-v1' -or
        [string]$Receipt.installer_source_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Receipt.installer_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        -not ($Receipt.installer_size -is [int] -or $Receipt.installer_size -is [long]) -or
        [long]$Receipt.installer_size -lt 65536 -or
        -not (Test-RimePimeUtcTimestamp $Receipt.sealed_at_utc)) {
        throw 'Package build receipt identity, architecture set, or seal metadata is invalid.'
    }
    $planRelative=ConvertTo-RimePimePackagePath ([string]$Receipt.package_plan_path)
    $expectedPlan=$Package.Path.Substring($Package.RepoRoot.Length+1).Replace('\','/')
    if ($planRelative -cne $expectedPlan) { throw 'Package build receipt names a different package plan.' }
    return $true
}

function Assert-RimePimeLegacyV1ReceiptWriteTarget($Package,[string]$ReceiptPath) {
    $envelope=Read-RimePimePackageBuildReceiptEnvelope -RepoRoot $Package.RepoRoot -ReceiptPath $ReceiptPath
    if ([string]$envelope.State -ceq 'absent') { return }
    if ([string]$envelope.SchemaVersion -cne 'yime-rime-pime-package-build-receipt-v1') {
        throw "Refusing to overwrite canonical package build receipt schema $($envelope.SchemaVersion) with legacy v1."
    }
    $null=Assert-RimePimePackageBuildReceiptV1Document $envelope.Sealed.Value $Package
}

function Write-RimePimePackageBuildReceipt(
    $Package,
    [string]$InstallerPath,
    [string]$InstallerSourcePath,
    [string]$ReceiptPath
) {
    $root=$Package.RepoRoot
    $installer=[IO.Path]::GetFullPath($InstallerPath)
    $source=[IO.Path]::GetFullPath($InstallerSourcePath)
    $receiptFull=[IO.Path]::GetFullPath($ReceiptPath)
    if (-not $receiptFull.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package build receipt must stay inside the repository root.'
    }
    foreach ($path in @($installer,$source)) {
        if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Package build-receipt input is outside the repository or missing: $path"
        }
        Assert-RimePimeNoReparsePath $path
    }
    if (-not (Test-RimePimeInstallerPlanDigest $installer $Package.Digest)) {
        throw 'Installer does not embed the exact sealed package-plan digest.'
    }
    Assert-RimePimeLegacyV1ReceiptWriteTarget -Package $Package -ReceiptPath $receiptFull
    $installerRelative=$installer.Substring($root.Length+1).Replace('\','/')
    $sourceRelative=$source.Substring($root.Length+1).Replace('\','/')
    $planRelative=$Package.Path.Substring($root.Length+1).Replace('\','/')
    $value=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-package-build-receipt-v1'
        product='rime-pime'
        closure_scope='declared-packaged-product-pe-inputs-only-not-installed-payload'
        architectures=@($Package.Plan.architectures)
        package_plan_path=$planRelative
        package_plan_sha256=$Package.Digest
        nsis_profile='x86-x64-v1'
        installer_source_path=$sourceRelative
        installer_source_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        installer_path=$installerRelative
        installer_size=[long](Get-Item -LiteralPath $installer).Length
        installer_sha256=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        sealed_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    Write-RimePimeSealedJson $value $receiptFull | Out-Null
    return Read-RimePimePackageBuildReceipt -Package $Package -ReceiptPath $receiptFull
}

function Read-RimePimePackageBuildReceipt($Package,[string]$ReceiptPath) {
    $receiptFull=[IO.Path]::GetFullPath($ReceiptPath)
    if (-not $receiptFull.StartsWith($Package.RepoRoot+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package build receipt must stay inside the repository root.'
    }
    $sealed=Read-RimePimeSealedJson $receiptFull 'package build receipt'
    $receipt=$sealed.Value
    $null=Assert-RimePimePackageBuildReceiptV1Document $receipt $Package
    $source=Resolve-RimePimePackageFile $Package.RepoRoot ([string]$receipt.installer_source_path)
    $installer=Resolve-RimePimePackageFile $Package.RepoRoot ([string]$receipt.installer_path)
    foreach ($path in @($source,$installer)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package build receipt input is missing: $path" }
        Assert-RimePimeNoReparsePath $path
    }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$receipt.installer_source_sha256 -or
        [long](Get-Item -LiteralPath $installer).Length -ne [long]$receipt.installer_size -or
        (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$receipt.installer_sha256 -or
        -not (Test-RimePimeInstallerPlanDigest $installer $Package.Digest)) {
        throw 'Package build receipt does not match the installer source, installer bytes, or embedded plan digest.'
    }
    return [pscustomobject]@{
        Receipt=$receipt
        Digest=$sealed.Digest
        Path=$sealed.Path
        Sidecar=$sealed.Sidecar
        InstallerPath=$installer
        InstallerSourcePath=$source
    }
}

if ($WritePlan) {
    Write-RimePimePackagePlan -RepoRoot $PlanRepoRoot -PlanPath $OutputPlanPath -ArchitectureSet @('x86','x64')
}
