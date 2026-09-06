# Deterministic NSIS include generation for one verified Rime/PIME copy stage.
# Definitions only; import through rime-pime-nsis-stage.psm1.
$script:RimePimeNsisStageReceiptSchema = 'yime-rime-pime-nsis-stage-include-v1'
$script:RimePimeNsisStageMacroNames = @(
    'YimePimeStageTargetUserHelpers',
    'YimePimeStageOwnershipHelpers',
    'YimePimeStageRegistrationTools',
    'YimePimeStageMainPayload',
    'YimePimeStageTextServiceX86',
    'YimePimeStageTextServiceX64'
)

function Assert-RimePimeNsisStagePathLiteral {
    param([Parameter(Mandatory)][string]$Path)
    $canonical = Assert-RimePimeStagePathWithinLimits $Path
    foreach ($segment in $canonical.Split('/')) {
        if ($segment -cnotmatch '^[A-Za-z0-9._+()-]+$') {
            throw "NSIS stage path is outside the sealed ASCII literal subset: $canonical"
        }
    }
    return $canonical
}

function Assert-RimePimeNsisDefinePath {
    param([Parameter(Mandatory)][string]$Path)
    $full = Assert-YimePimePayloadAbsolutePath $Path
    if ($full -cnotmatch '^[A-Za-z]:\\[A-Za-z0-9 ._+()\\-]+$') {
        throw "NSIS command-line define path is outside the sealed literal subset: $full"
    }
    return $full
}

function Assert-RimePimeNsisRecordSemantics {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$OwnerClass,
        [Parameter(Mandatory)][string[]]$Architectures
    )
    if ([string]$Row.owner_class -cne $OwnerClass -or
        $Architectures -cnotcontains [string]$Row.architecture) {
        throw "NSIS stage record has wrong owner or architecture semantics: $($Row.stage_scope)/$($Row.path)"
    }
}

function Get-RimePimeNsisStageRecordIndex {
    param([Parameter(Mandatory)]$Manifest)
    $index = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($row in @($Manifest.files)) {
        $path = Assert-RimePimeNsisStagePathLiteral ([string]$row.path)
        $key = [string]$row.stage_scope + '/' + $path
        if ($index.ContainsKey($key)) { throw "Duplicate NSIS stage record: $key" }
        $index.Add($key,$row)
    }
    return $index
}

function Get-RimePimeNsisRequiredStageRecord {
    param(
        [Parameter(Mandatory)][Collections.Generic.Dictionary[string,object]]$Index,
        [Parameter(Mandatory)][string]$Key
    )
    if (-not $Index.ContainsKey($Key)) { throw "Required NSIS stage input is missing: $Key" }
    return $Index[$Key]
}

function Add-RimePimeNsisMacro {
    param(
        [Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Commands
    )
    $Lines.Add("!macro $Name")
    foreach ($command in $Commands) { $Lines.Add("`t$command") }
    $Lines.Add('!macroend')
    $Lines.Add('')
}

function Get-RimePimeNsisPluginFileCommands {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$Scope
    )
    $commands = [Collections.Generic.List[string]]::new()
    foreach ($row in $Rows) {
        $path = Assert-RimePimeNsisStagePathLiteral ([string]$row.path)
        $name = [IO.Path]::GetFileName($path)
        $source = '${PACKAGE_STAGE_ROOT}\' + $Scope + '\' + $path.Replace('/','\')
        $commands.Add('File /oname=$PLUGINSDIR\' + $name + ' "' + $source + '"')
    }
    return [string[]]@($commands)
}

function Get-RimePimeNsisMainPayloadCommands {
    param([Parameter(Mandatory)][object[]]$Rows)
    $commands = [Collections.Generic.List[string]]::new()
    $currentDirectory = $null
    foreach ($row in $Rows) {
        $path = Assert-RimePimeNsisStagePathLiteral ([string]$row.path)
        $slash = $path.LastIndexOf('/')
        $directory = if ($slash -lt 0) { '' } else { $path.Substring(0,$slash) }
        $name = if ($slash -lt 0) { $path } else { $path.Substring($slash+1) }
        if ($null -eq $currentDirectory -or [string]$currentDirectory -cne $directory) {
            $target = if ($directory) { '$INSTDIR\' + $directory.Replace('/','\') } else { '$INSTDIR' }
            $commands.Add('SetOutPath "' + $target + '"')
            $currentDirectory = $directory
        }
        $source = '${PACKAGE_STAGE_ROOT}\payload\' + $path.Replace('/','\')
        $commands.Add('File /oname=' + $name + ' "' + $source + '"')
    }
    return [string[]]@($commands)
}

function Get-RimePimeNsisStageIncludeDocument {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ContentManifestDigest,
        [Parameter(Mandatory)][string]$ExpectedPackagePlanDigest
    )
    if ($ContentManifestDigest -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedPackagePlanDigest -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Manifest.package_plan_sha256 -cne $ExpectedPackagePlanDigest) {
        throw 'NSIS stage generation received an invalid or mismatched package-plan/content-manifest digest.'
    }
    $index = Get-RimePimeNsisStageRecordIndex $Manifest
    $targetPaths = @('invoke-rime-pime-target-user.ps1','rime-pime-target-user.ps1')
    $ownershipPaths = @(
        'invoke-rime-pime-maintenance.ps1','rime-pime-directed-stop-contract.ps1',
        'rime-pime-ownership.ps1','rime-pime-target-user.ps1'
    )
    $registrationPaths = @(
        'PIMERegistrationStatus_x64.exe','PIMERegistrationStatus_x86.exe',
        'PIMETextService_x64.dll','PIMETextService_x86.dll'
    )
    $requiredBootstrap = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in @($targetPaths + $ownershipPaths + $registrationPaths)) { $null=$requiredBootstrap.Add($path) }
    $bootstrapRows = @($Manifest.files | Where-Object { [string]$_.stage_scope -ceq 'bootstrap' })
    if ($bootstrapRows.Count -ne $requiredBootstrap.Count) {
        throw 'NSIS bootstrap stage set is not the exact fixed helper/tool set.'
    }
    foreach ($row in $bootstrapRows) {
        if (-not $requiredBootstrap.Contains([string]$row.path)) {
            throw "Unexpected NSIS bootstrap stage input: $($row.path)"
        }
        switch -CaseSensitive ([string]$row.path) {
            'PIMERegistrationStatus_x64.exe' { Assert-RimePimeNsisRecordSemantics $row 'maintenance' @('x64') }
            'PIMERegistrationStatus_x86.exe' { Assert-RimePimeNsisRecordSemantics $row 'maintenance' @('x86') }
            'PIMETextService_x64.dll' { Assert-RimePimeNsisRecordSemantics $row 'text-service' @('x64') }
            'PIMETextService_x86.dll' { Assert-RimePimeNsisRecordSemantics $row 'text-service' @('x86') }
            default { Assert-RimePimeNsisRecordSemantics $row 'maintenance' @('neutral') }
        }
    }
    $targetRows = @($targetPaths | ForEach-Object { Get-RimePimeNsisRequiredStageRecord $index ('bootstrap/' + $_) })
    $ownershipRows = @($ownershipPaths | ForEach-Object { Get-RimePimeNsisRequiredStageRecord $index ('bootstrap/' + $_) })
    $registrationRows = @($registrationPaths | ForEach-Object { Get-RimePimeNsisRequiredStageRecord $index ('bootstrap/' + $_) })

    $x86 = Get-RimePimeNsisRequiredStageRecord $index 'payload/x86/PIMETextService.dll'
    $x64 = Get-RimePimeNsisRequiredStageRecord $index 'payload/x64/PIMETextService.dll'
    Assert-RimePimeNsisRecordSemantics $x86 'text-service' @('x86')
    Assert-RimePimeNsisRecordSemantics $x64 'text-service' @('x64')
    foreach($pair in @(
        @($x86,(Get-RimePimeNsisRequiredStageRecord $index 'bootstrap/PIMETextService_x86.dll')),
        @($x64,(Get-RimePimeNsisRequiredStageRecord $index 'bootstrap/PIMETextService_x64.dll'))
    )){
        if([long]$pair[0].bytes -ne [long]$pair[1].bytes -or [string]$pair[0].sha256 -cne [string]$pair[1].sha256){
            throw 'NSIS bootstrap and installed text-service bytes differ for one architecture.'
        }
    }
    $mainRows = @($Manifest.files | Where-Object {
        [string]$_.stage_scope -ceq 'payload' -and
        [string]$_.path -cne 'x86/PIMETextService.dll' -and
        [string]$_.path -cne 'x64/PIMETextService.dll'
    })
    $mainSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $mainRows) {
        $path = Assert-RimePimeNsisStagePathLiteral ([string]$row.path)
        if ($path -cnotin @('version.txt','backends.json','PIMELauncher.exe') -and
            -not $path.StartsWith('licenses/',[StringComparison]::Ordinal) -and
            -not $path.StartsWith('go-backend/',[StringComparison]::Ordinal)) {
            throw "NSIS main payload path is outside the fixed installed namespaces: $path"
        }
        if ($path -cin @('version.txt','backends.json')) {
            Assert-RimePimeNsisRecordSemantics $row 'metadata' @('neutral')
        } elseif ($path -ceq 'PIMELauncher.exe') {
            Assert-RimePimeNsisRecordSemantics $row 'runtime' @('x86')
        } elseif ($path.StartsWith('licenses/',[StringComparison]::Ordinal)) {
            Assert-RimePimeNsisRecordSemantics $row 'license' @('neutral')
        } else {
            Assert-RimePimeNsisRecordSemantics $row 'backend' @('neutral','x64')
        }
        $null=$mainSet.Add($path)
    }
    $requiredMain=@(
        'version.txt','backends.json','PIMELauncher.exe',
        'licenses/APACHE-2.0.txt','licenses/AUTHORS.txt','licenses/LGPL-2.0.txt','licenses/LICENSE.txt',
        'licenses/NLOHMANN-JSON-MIT.txt','licenses/NOTICE.md','licenses/PIME-UPSTREAM-LICENSE.txt',
        'licenses/RIME-BSD-3-Clause.txt','licenses/RIME-FROST-GPL-3.0.txt','licenses/RUST-DEPENDENCIES.md',
        'licenses/SIL-OFL-1.1.txt','licenses/THIRD_PARTY_NOTICES.md','licenses/UNICODE-3.0.txt'
    )
    foreach ($required in $requiredMain) {
        if (-not $mainSet.Contains($required)) { throw "Required NSIS main payload input is missing: $required" }
    }
    if (@($mainRows | Where-Object { [string]$_.path -clike 'go-backend/*' }).Count -lt 1) {
        throw 'NSIS main payload has no closed Go backend tree.'
    }
    $payloadCount = @($Manifest.files | Where-Object { [string]$_.stage_scope -ceq 'payload' }).Count
    if ($mainRows.Count + 2 -ne $payloadCount -or $payloadCount + $bootstrapRows.Count -ne $index.Count) {
        throw 'NSIS macro partition does not exactly cover the staged file set.'
    }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('; Generated from a sealed Rime/PIME copied-content manifest. Do not edit.')
    $lines.Add('; package-plan-sha256: ' + [string]$Manifest.package_plan_sha256)
    $lines.Add('; content-manifest-sha256: ' + $ContentManifestDigest)
    $lines.Add('; content-tree-sha256: ' + [string]$Manifest.content_tree_sha256)
    $lines.Add('')
    Add-RimePimeNsisMacro $lines 'YimePimeStageTargetUserHelpers' `
        (Get-RimePimeNsisPluginFileCommands $targetRows 'bootstrap')
    Add-RimePimeNsisMacro $lines 'YimePimeStageOwnershipHelpers' `
        (Get-RimePimeNsisPluginFileCommands $ownershipRows 'bootstrap')
    Add-RimePimeNsisMacro $lines 'YimePimeStageRegistrationTools' `
        (Get-RimePimeNsisPluginFileCommands $registrationRows 'bootstrap')
    Add-RimePimeNsisMacro $lines 'YimePimeStageMainPayload' `
        (Get-RimePimeNsisMainPayloadCommands $mainRows)
    Add-RimePimeNsisMacro $lines 'YimePimeStageTextServiceX86' @(
        'File /oname=PIMETextService.dll "${PACKAGE_STAGE_ROOT}\payload\x86\PIMETextService.dll"')
    Add-RimePimeNsisMacro $lines 'YimePimeStageTextServiceX64' @(
        'File /oname=PIMETextService.dll "${PACKAGE_STAGE_ROOT}\payload\x64\PIMETextService.dll"')
    $text = ([string]::Join("`n",@($lines))).TrimEnd("`n") + "`n"
    $macroCounts = @(
        [pscustomobject][ordered]@{name='YimePimeStageTargetUserHelpers';file_reference_count=$targetRows.Count},
        [pscustomobject][ordered]@{name='YimePimeStageOwnershipHelpers';file_reference_count=$ownershipRows.Count},
        [pscustomobject][ordered]@{name='YimePimeStageRegistrationTools';file_reference_count=$registrationRows.Count},
        [pscustomobject][ordered]@{name='YimePimeStageMainPayload';file_reference_count=$mainRows.Count},
        [pscustomobject][ordered]@{name='YimePimeStageTextServiceX86';file_reference_count=1},
        [pscustomobject][ordered]@{name='YimePimeStageTextServiceX64';file_reference_count=1}
    )
    return [pscustomobject]@{
        Text=$text;MacroCounts=$macroCounts;PayloadCount=$payloadCount;BootstrapCount=$bootstrapRows.Count
        MainPayloadCount=$mainRows.Count;UniqueStageFileCount=$index.Count
        FileReferenceCount=($targetRows.Count+$ownershipRows.Count+$registrationRows.Count+$mainRows.Count+2)
    }
}

function Write-RimePimeNsisStageInclude {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$ContentManifestPath,
        [Parameter(Mandatory)][string]$ExpectedContentManifestDigest,
        [Parameter(Mandatory)][string]$ExpectedPackagePlanDigest,
        [Parameter(Mandatory)][string]$IncludePath,
        [Parameter(Mandatory)][string]$ReceiptPath
    )
    $stage = (Assert-RimePimeNsisDefinePath $StageRoot).TrimEnd('\')
    $null=Assert-RimePimeNsisDefinePath $IncludePath
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($IncludePath))) -ine
        (Split-Path -Parent ([IO.Path]::GetFullPath($ReceiptPath)))) {
        throw 'NSIS include and its receipt must share one evidence directory.'
    }
    foreach ($outside in @($IncludePath,$IncludePath+'.sha256',$ReceiptPath,$ReceiptPath+'.sha256')) {
        $full = [IO.Path]::GetFullPath($outside)
        if ($full.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'NSIS include evidence must remain outside the copied stage tree.'
        }
        if (Test-Path -LiteralPath $full) { throw "NSIS include output already exists: $full" }
    }
    $manifest = Read-RimePimeCopiedContentManifest $ContentManifestPath $ExpectedContentManifestDigest
    foreach($controlPath in @($manifest.Path,$manifest.Sidecar)){
        $null=Get-YimePimePayloadFileRecord $controlPath
    }
    if ([string]$manifest.Manifest.package_plan_sha256 -cne $ExpectedPackagePlanDigest) {
        throw 'NSIS stage manifest names a different package plan.'
    }
    $null = Test-RimePimePackageCopyStage $stage $manifest.Path $manifest.Digest
    $document = Get-RimePimeNsisStageIncludeDocument $manifest.Manifest $manifest.Digest $ExpectedPackagePlanDigest
    $includeFull = [IO.Path]::GetFullPath($IncludePath)
    $parent = Split-Path -Parent $includeFull
    Assert-RimePimeNoReparsePath $includeFull
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $bytes = [Text.Encoding]::ASCII.GetBytes($document.Text)
    $stream = [IO.File]::Open($includeFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    $includeDigest = (Get-FileHash -LiteralPath $includeFull -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = $includeFull + '.sha256'
    $sidecarText = "$includeDigest  $([IO.Path]::GetFileName($includeFull))`n"
    $sidecarBytes = [Text.Encoding]::ASCII.GetBytes($sidecarText)
    $sidecarStream = [IO.File]::Open($sidecar,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $sidecarStream.Write($sidecarBytes,0,$sidecarBytes.Length) } finally { $sidecarStream.Dispose() }
    $receipt = [pscustomobject][ordered]@{
        schema_version=$script:RimePimeNsisStageReceiptSchema;product='rime-pime';package_profile='x86-x64-v1'
        architectures=@('x86','x64');phase='copied-inputs-awaiting-generated-output'
        package_plan_sha256=$ExpectedPackagePlanDigest;payload_spec_sha256=[string]$manifest.Manifest.payload_spec_sha256
        content_manifest_sha256=$manifest.Digest;content_tree_sha256=[string]$manifest.Manifest.content_tree_sha256
        include_file=[IO.Path]::GetFileName($includeFull);include_sha256=$includeDigest;include_bytes=[long]$bytes.Length
        encoding='us-ascii';line_ending='lf';macros=@($document.MacroCounts)
        unique_stage_file_count=[int]$document.UniqueStageFileCount;payload_file_count=[int]$document.PayloadCount
        bootstrap_file_count=[int]$document.BootstrapCount;main_payload_file_count=[int]$document.MainPayloadCount
        macro_file_reference_count=[int]$document.FileReferenceCount;final_payload_closure=$false
    }
    $receiptDigest = Write-RimePimeStageSealedJson $receipt $ReceiptPath
    $verified = Test-RimePimeNsisStageInclude -StageRoot $stage -ContentManifestPath $manifest.Path `
        -ExpectedContentManifestDigest $manifest.Digest -ExpectedPackagePlanDigest $ExpectedPackagePlanDigest `
        -ReceiptPath $ReceiptPath -ExpectedReceiptDigest $receiptDigest
    return [pscustomobject]@{
        IncludePath=$includeFull;IncludeDigest=$includeDigest;ReceiptPath=[IO.Path]::GetFullPath($ReceiptPath)
        ReceiptDigest=$receiptDigest;Document=$document;Verification=$verified
    }
}

function Assert-RimePimeNsisStageIncludeReceiptValue {
    param(
        [Parameter(Mandatory)]$Receipt,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ContentManifestDigest,
        [Parameter(Mandatory)][string]$ExpectedPackagePlanDigest
    )
    $receipt=$Receipt
    Assert-YimePimePayloadProperties $receipt @(
        'schema_version','product','package_profile','architectures','phase','package_plan_sha256','payload_spec_sha256',
        'content_manifest_sha256','content_tree_sha256','include_file','include_sha256','include_bytes','encoding','line_ending',
        'macros','unique_stage_file_count','payload_file_count','bootstrap_file_count','main_payload_file_count',
        'macro_file_reference_count','final_payload_closure') 'NSIS stage include receipt'
    $architectures=@($receipt.architectures)
    foreach($name in @(
        'schema_version','product','package_profile','phase','package_plan_sha256','payload_spec_sha256',
        'content_manifest_sha256','content_tree_sha256','include_file','include_sha256','encoding','line_ending')){
        if($receipt.$name -isnot [string]){throw "NSIS stage include receipt has non-string $name."}
    }
    if($receipt.architectures -isnot [Array] -or $architectures.Count -ne 2 -or
        $architectures[0] -isnot [string] -or $architectures[1] -isnot [string] -or
        $receipt.macros -isnot [Array] -or
        [string]$receipt.schema_version -cne $script:RimePimeNsisStageReceiptSchema -or
        [string]$receipt.product -cne 'rime-pime' -or [string]$receipt.package_profile -cne 'x86-x64-v1' -or
        [string]$architectures[0] -cne 'x86' -or [string]$architectures[1] -cne 'x64' -or
        [string]$receipt.phase -cne 'copied-inputs-awaiting-generated-output' -or
        [string]$receipt.package_plan_sha256 -cne $ExpectedPackagePlanDigest -or
        [string]$receipt.payload_spec_sha256 -cne [string]$Manifest.payload_spec_sha256 -or
        [string]$receipt.content_manifest_sha256 -cne $ContentManifestDigest -or
        [string]$receipt.content_tree_sha256 -cne [string]$Manifest.content_tree_sha256 -or
        [string]$receipt.include_file -cnotmatch '^[A-Za-z0-9._-]+\.nsh$' -or
        [string]$receipt.include_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        -not (Test-RimePimeStageInteger $receipt.include_bytes) -or [long]$receipt.include_bytes -lt 1 -or
        [string]$receipt.encoding -cne 'us-ascii' -or [string]$receipt.line_ending -cne 'lf' -or
        $receipt.final_payload_closure -isnot [bool] -or $receipt.final_payload_closure) {
        throw 'NSIS stage include receipt identity or boundary is invalid.'
    }
    $document=Get-RimePimeNsisStageIncludeDocument $Manifest $ContentManifestDigest $ExpectedPackagePlanDigest
    $macros=@($receipt.macros)
    if($macros.Count -ne $document.MacroCounts.Count){throw 'NSIS stage include macro inventory is incomplete.'}
    for($i=0;$i -lt $macros.Count;$i++){
        Assert-YimePimePayloadProperties $macros[$i] @('name','file_reference_count') 'NSIS stage macro receipt'
        if($macros[$i].name -isnot [string] -or
            [string]$macros[$i].name -cne [string]$document.MacroCounts[$i].name -or
            -not (Test-RimePimeStageInteger $macros[$i].file_reference_count) -or
            [long]$macros[$i].file_reference_count -ne [long]$document.MacroCounts[$i].file_reference_count){
            throw 'NSIS stage include macro inventory differs from generated commands.'
        }
    }
    foreach($name in @('unique_stage_file_count','payload_file_count','bootstrap_file_count','main_payload_file_count','macro_file_reference_count')){
        if(-not (Test-RimePimeStageInteger $receipt.$name)){throw "NSIS stage include receipt count is not an integer: $name"}
    }
    if([long]$receipt.unique_stage_file_count -ne [long]$document.UniqueStageFileCount -or
        [long]$receipt.payload_file_count -ne [long]$document.PayloadCount -or
        [long]$receipt.bootstrap_file_count -ne [long]$document.BootstrapCount -or
        [long]$receipt.main_payload_file_count -ne [long]$document.MainPayloadCount -or
        [long]$receipt.macro_file_reference_count -ne [long]$document.FileReferenceCount){
        throw 'NSIS stage include receipt counts differ from the exact macro partition.'
    }
    return [pscustomobject]@{Receipt=$receipt;Document=$document}
}

function Test-RimePimeNsisStageInclude {
    param(
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)][string]$ContentManifestPath,
        [Parameter(Mandatory)][string]$ExpectedContentManifestDigest,
        [Parameter(Mandatory)][string]$ExpectedPackagePlanDigest,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$ExpectedReceiptDigest
    )
    $stage = (Assert-RimePimeNsisDefinePath $StageRoot).TrimEnd('\')
    $manifest = Read-RimePimeCopiedContentManifest $ContentManifestPath $ExpectedContentManifestDigest
    $null = Test-RimePimePackageCopyStage $stage $manifest.Path $manifest.Digest
    $sealed = Read-RimePimeSealedJson $ReceiptPath 'NSIS stage include receipt'
    if ([string]$sealed.Digest -cne $ExpectedReceiptDigest) { throw 'NSIS stage include receipt does not match its external digest.' }
    $validated=Assert-RimePimeNsisStageIncludeReceiptValue $sealed.Value $manifest.Manifest $manifest.Digest $ExpectedPackagePlanDigest
    $receipt=$validated.Receipt
    $document=$validated.Document
    $include = Join-Path (Split-Path -Parent $sealed.Path) ([string]$receipt.include_file)
    Assert-RimePimeNoReparsePath $include
    if (-not (Test-Path -LiteralPath $include -PathType Leaf)) { throw 'NSIS stage include is missing.' }
    $sidecar = $include + '.sha256'
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { throw 'NSIS stage include sidecar is missing.' }
    foreach($controlPath in @($manifest.Path,$manifest.Sidecar,$sealed.Path,$sealed.Sidecar,$include,$sidecar)){
        $null=Get-YimePimePayloadFileRecord $controlPath
    }
    $sidecarText=[IO.File]::ReadAllText($sidecar)
    if($sidecarText -cne ([string]$receipt.include_sha256+'  '+[IO.Path]::GetFileName($include)+"`n")){
        throw 'NSIS stage include sidecar is stale or malformed.'
    }
    $actualBytes=[IO.File]::ReadAllBytes($include)
    $expectedBytes=[Text.Encoding]::ASCII.GetBytes($document.Text)
    if([long]$actualBytes.Length -ne [long]$receipt.include_bytes -or $actualBytes.Length -ne $expectedBytes.Length){
        throw 'NSIS stage include byte count is invalid.'
    }
    for($i=0;$i -lt $actualBytes.Length;$i++){if($actualBytes[$i] -ne $expectedBytes[$i]){throw 'NSIS stage include bytes are not deterministic.'}}
    $actualDigest=(Get-FileHash -LiteralPath $include -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actualDigest -cne [string]$receipt.include_sha256){throw 'NSIS stage include hash is invalid.'}
    return [pscustomobject][ordered]@{
        passed=$true;include_sha256=$actualDigest;include_bytes=$actualBytes.Length
        unique_stage_file_count=$document.UniqueStageFileCount;payload_file_count=$document.PayloadCount
        bootstrap_file_count=$document.BootstrapCount;main_payload_file_count=$document.MainPayloadCount
        macro_file_reference_count=$document.FileReferenceCount;final_payload_closure=$false
    }
}
