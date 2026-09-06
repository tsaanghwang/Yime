[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-installer-static-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-installer-static-* fixture root.'
}
for ($cursor=$expectedParent; $cursor; $cursor=Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Installer-static evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$smoke=Join-Path $repo 'tools\test-installer-smoke.ps1'
$manifestWriter=Join-Path $repo 'tools\write-build-manifest.ps1'
$installerBuilder=Join-Path $repo 'tools\build-rime-pime-installer.ps1'
$packageModule=Join-Path $repo 'tools\dual-product\rime-pime-package-plan.ps1'
. $packageModule
$smokeHash=(Get-FileHash -LiteralPath $smoke -Algorithm SHA256).Hash.ToLowerInvariant()
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action; $checks.Add([pscustomobject]@{name=$Name;passed=$true}) }
    catch { $checks.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message}) }
}
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action,[string]$Like='*') {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike $Like) { throw "Unexpected rejection: $($_.Exception.Message)" }
        return
    }
    throw 'Unsafe static installer artifact was accepted.'
}

Check 'sealed-json-value-and-digest-use-one-read-leased-byte-source' {
    $path=Join-Path $output 'sealed-reader.json'
    $null=Write-RimePimeSealedJson ([pscustomobject][ordered]@{schema='fixture';value=1}) $path
    $leases=Open-RimePimeSealedJsonReadLeases $path 'sealed reader fixture'
    try{
        Assert-Rejected {[IO.File]::WriteAllText($path,'{"schema":"swapped","value":2}')}
        Assert-Rejected {[IO.File]::WriteAllText(($path+'.sha256'),'swapped')}
    }finally{$leases.SidecarStream.Dispose();$leases.JsonStream.Dispose()}
    $sealed=Read-RimePimeSealedJson $path 'sealed reader fixture'
    Assert-True ([string]$sealed.Value.schema -ceq 'fixture') 'Sealed JSON parsed another value.'
    Assert-True ([string]$sealed.Digest -ceq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) 'Sealed JSON digest is not derived from the parsed bytes.'
}

Check 'sealed-json-reader-rejects-invalid-utf8-from-the-leased-bytes' {
    $path=Join-Path $output 'sealed-invalid-utf8.json'
    [IO.File]::WriteAllBytes($path,[byte[]]@(0x7b,0x22,0x78,0x22,0x3a,0xff,0x7d))
    $digest=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($path+'.sha256'),"$digest  sealed-invalid-utf8.json`n",(New-Object Text.ASCIIEncoding))
    Assert-Rejected {Read-RimePimeSealedJson $path 'invalid UTF-8 fixture'} '*Invalid*JSON or UTF-8*'
}

Check 'unsigned-installer-wrapper-rejects-inherited-signing-context-before-reading-inputs' {
    foreach($name in @('YIME_SIGN_CERT_SHA1','YIME_RELEASE_SIGNING_REQUIRED','YIME_SIGNTOOL_EXE','YIME_TIMESTAMP_URL')) {
        $old=[Environment]::GetEnvironmentVariable($name,'Process')
        try {
            [Environment]::SetEnvironmentVariable($name,'unexpected-signing-context','Process')
            Assert-Rejected {
                & $installerBuilder -RepoRoot (Join-Path $output 'must-not-be-read') `
                    -PackagePlanPath (Join-Path $output 'must-not-be-read.json')
            } '*only builds an unsigned disabled package*'
        } finally {
            [Environment]::SetEnvironmentVariable($name,$old,'Process')
        }
    }
}

function Write-TestPe(
    [string]$Path,
    [uint16]$Machine=0x014c,
    [int]$Length=65536,
    [string]$PlanDigest='',
    [ValidateSet('none','normal','delay')][string]$ImportKind='none',
    [string]$ImportedDll=''
) {
    $bytes=New-Object byte[] $Length
    if ($Length -ge 1024) {
        $isPlus=$Machine -ne 0x014c
        $optionalSize=if($isPlus){0xF0}else{0xE0}
        $optionalMagic=if($isPlus){[uint16]0x020b}else{[uint16]0x010b}
        $peOffset=0x80
        $optionalOffset=$peOffset+24
        $sectionOffset=$optionalOffset+$optionalSize
        $directoryOffset=if($isPlus){$optionalOffset+112}else{$optionalOffset+96}
        $numberOfDirectoriesOffset=if($isPlus){$optionalOffset+108}else{$optionalOffset+92}
        $bytes[0]=0x4d; $bytes[1]=0x5a
        [BitConverter]::GetBytes([uint32]$peOffset).CopyTo($bytes,0x3c)
        $bytes[$peOffset]=0x50; $bytes[$peOffset+1]=0x45
        [BitConverter]::GetBytes($Machine).CopyTo($bytes,$peOffset+4)
        [BitConverter]::GetBytes([uint16]1).CopyTo($bytes,$peOffset+6)
        [BitConverter]::GetBytes([uint16]$optionalSize).CopyTo($bytes,$peOffset+20)
        [BitConverter]::GetBytes($optionalMagic).CopyTo($bytes,$optionalOffset)
        [BitConverter]::GetBytes([uint32]0x200).CopyTo($bytes,$optionalOffset+60)
        [BitConverter]::GetBytes([uint32]16).CopyTo($bytes,$numberOfDirectoriesOffset)
        [Text.Encoding]::ASCII.GetBytes('.rdata').CopyTo($bytes,$sectionOffset)
        [BitConverter]::GetBytes([uint32]0x200).CopyTo($bytes,$sectionOffset+8)
        [BitConverter]::GetBytes([uint32]0x1000).CopyTo($bytes,$sectionOffset+12)
        [BitConverter]::GetBytes([uint32]0x200).CopyTo($bytes,$sectionOffset+16)
        [BitConverter]::GetBytes([uint32]0x200).CopyTo($bytes,$sectionOffset+20)
        if($ImportKind -ne 'none'){
            [Text.Encoding]::ASCII.GetBytes($ImportedDll+[char]0).CopyTo($bytes,0x280)
            if($ImportKind -eq 'normal'){
                [BitConverter]::GetBytes([uint32]0x1000).CopyTo($bytes,$directoryOffset+8)
                [BitConverter]::GetBytes([uint32]40).CopyTo($bytes,$directoryOffset+12)
                [BitConverter]::GetBytes([uint32]0x1080).CopyTo($bytes,0x200+12)
                [BitConverter]::GetBytes([uint32]0x1090).CopyTo($bytes,0x200+16)
            }else{
                [BitConverter]::GetBytes([uint32]0x1000).CopyTo($bytes,$directoryOffset+(13*8))
                [BitConverter]::GetBytes([uint32]64).CopyTo($bytes,$directoryOffset+(13*8)+4)
                [BitConverter]::GetBytes([uint32]1).CopyTo($bytes,0x200)
                [BitConverter]::GetBytes([uint32]0x1080).CopyTo($bytes,0x204)
            }
        }
    }
    if ($PlanDigest -and $Length -ge 512+$PlanDigest.Length) {
        [Text.Encoding]::ASCII.GetBytes($PlanDigest).CopyTo($bytes,512)
    }
    [IO.File]::WriteAllBytes($Path,$bytes)
}

function New-StaticCase([string]$Name) {
    $root=Join-Path $output $Name
    $installerName='YIME-1.4.0-dev-setup.exe'
    $payloadSpecs=@(Get-RimePimePackageArtifactSpecs @('x86','x64'))
    $payloadPaths=@($payloadSpecs | ForEach-Object { $_.path })
    $arm64Paths=@(
        'build_arm64/PIMETextService/Release/PIMETextService.dll',
        'build_arm64/PIMETextService/Release/PIMERegistrationStatus.exe'
    )
    $fixturePaths=@($payloadPaths)+@($arm64Paths)
    New-Item -ItemType Directory -Path $root | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'version.txt') -Value '1.4.0-dev' -Encoding UTF8
    foreach ($relative in $fixturePaths) {
        $path=Join-Path $root $relative.Replace('/','\')
        $parent=Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        $spec=@($payloadSpecs | Where-Object { $_.path -ceq $relative })
        if($spec.Count -eq 1){
            $machine=if($spec[0].architecture -ceq 'x86'){[uint16]0x014c}else{[uint16]0x8664}
            Write-TestPe -Path $path -Machine $machine
        }else{
            Set-Content -LiteralPath $path -Value "fixture:$relative" -Encoding UTF8
        }
    }
    $installer=Join-Path $root "installer\$installerName"
    New-Item -ItemType Directory -Path (Split-Path -Parent $installer) -Force | Out-Null
    $installerSource=Join-Path $root 'installer\installer.nsi'
    Set-Content -LiteralPath $installerSource -Value 'synthetic NSIS source' -Encoding UTF8
    $planPath=Join-Path $root 'installer\package-plan.json'
    $package=Write-RimePimePackagePlan -RepoRoot $root -PlanPath $planPath -ArchitectureSet @('x86','x64')
    Write-TestPe -Path $installer -PlanDigest $package.Digest
    $receiptPath=Join-Path $root 'installer\package-build-receipt.json'
    $receipt=Write-RimePimePackageBuildReceipt -Package $package -InstallerPath $installer `
        -InstallerSourcePath $installerSource -ReceiptPath $receiptPath
    $paths=@($payloadPaths)+@(
        "installer/$installerName",
        'installer/package-plan.json','installer/package-plan.json.sha256',
        'installer/package-build-receipt.json','installer/package-build-receipt.json.sha256')
    $rows=@($paths | ForEach-Object {
        $path=Join-Path $root $_.Replace('/','\')
        [pscustomobject][ordered]@{
            path=$_
            size=[long](Get-Item -LiteralPath $path).Length
            sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    })
    $manifest=[pscustomobject][ordered]@{
        schemaVersion=3
        product='YIME'
        version='1.4.0-dev'
        commit=('a'*40)
        ref='refs/heads/synthetic'
        builtAtUtc=[DateTime]::UtcNow.ToString('o')
        signedRelease=$false
        sourceIdentity=[pscustomobject][ordered]@{
            kind='working-tree'
            treeDirty=$true
            commitIsCompleteSourceIdentity=$false
        }
        packagePlan=[pscustomobject][ordered]@{
            path='installer/package-plan.json'
            sha256=$package.Digest
            closureScope='declared-packaged-product-pe-inputs-only-not-installed-payload'
            architectures=@('x86','x64')
            receiptPath='installer/package-build-receipt.json'
            receiptSha256=$receipt.Digest
        }
        files=$rows
    }
    $case=[pscustomobject][ordered]@{
        Root=$root
        Installer=$installer
        ManifestPath=(Join-Path $root 'installer\build-manifest.json')
        Manifest=$manifest
        ExpectedCommit=('a'*40)
        PlanPath=$planPath
        ReceiptPath=$receiptPath
        PlanDigest=$package.Digest
    }
    $manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $case.ManifestPath -Encoding UTF8
    return $case
}

function Write-StaticManifest($Case) {
    $Case.Manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Case.ManifestPath -Encoding UTF8
}

function Invoke-StaticValidation($Case) {
    $arguments=@{
        InstallerPath=$Case.Installer
        RepoRoot=$Case.Root
        StaticOnly=$true
        ExpectedCommit=[string]$Case.ExpectedCommit
        ExpectedRef='refs/heads/synthetic'
        ExpectedSignedRelease='false'
        ExpectedSourceTreeDirty='true'
        PackagePlanPath=$Case.PlanPath
        ReceiptPath=$Case.ReceiptPath
    }
    & $smoke @arguments | Out-Null
}

function Invoke-ProductionManifestWriter($Case,[switch]$UseMismatchedSha) {
    $oldSha=$env:GITHUB_SHA
    $oldRef=$env:GITHUB_REF
    $oldSigning=$env:YIME_RELEASE_SIGNING_REQUIRED
    try {
        & git -C $Case.Root init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize the isolated manifest-writer fixture repository.' }
        & git -C $Case.Root -c user.name=YimeFixture -c user.email=yime-fixture.invalid `
            commit --allow-empty --no-gpg-sign --quiet -m synthetic
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create the isolated manifest-writer fixture commit.' }
        $fixtureHead=(& git -C $Case.Root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the isolated manifest-writer fixture HEAD.' }
        $Case.ExpectedCommit=$fixtureHead
        if ($UseMismatchedSha) {
            $env:GITHUB_SHA=if ($fixtureHead -ceq ('f'*40)) { 'e'*40 } else { 'f'*40 }
        } else {
            $env:GITHUB_SHA=$fixtureHead
        }
        $env:GITHUB_REF='refs/heads/synthetic'
        $env:YIME_RELEASE_SIGNING_REQUIRED='0'
        & $manifestWriter -RepoRoot $Case.Root -OutputPath $Case.ManifestPath `
            -PackagePlanPath $Case.PlanPath -ReceiptPath $Case.ReceiptPath | Out-Null
    } finally {
        $env:GITHUB_SHA=$oldSha
        $env:GITHUB_REF=$oldRef
        $env:YIME_RELEASE_SIGNING_REQUIRED=$oldSigning
    }
}

Check 'production-manifest-writer-rejects-github-sha-head-mismatch' {
    $case=New-StaticCase 'manifest-writer-head-mismatch'
    Assert-Rejected { Invoke-ProductionManifestWriter $case -UseMismatchedSha } '*does not match the checked-out source HEAD*'
}

Check 'rejects-inconsistent-working-tree-source-identity' {
    $case=New-StaticCase 'inconsistent-source-identity'
    $case.Manifest.sourceIdentity.commitIsCompleteSourceIdentity=$true
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*source identity is inconsistent*'
}

Check 'rejects-wrong-expected-source-tree-state' {
    $case=New-StaticCase 'wrong-source-tree-state'
    $case.Manifest.sourceIdentity.kind='git-commit'
    $case.Manifest.sourceIdentity.treeDirty=$false
    $case.Manifest.sourceIdentity.commitIsCompleteSourceIdentity=$true
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*source-tree state does not match*'
}

Check 'default-closure-ignores-existing-unselected-arm64-artifacts' {
    $case=New-StaticCase 'positive'
    Invoke-StaticValidation $case
    Assert-True ((Get-FileHash -LiteralPath $smoke -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $smokeHash) 'Static verifier changed while running.'
}

Check 'production-manifest-writer-consumes-the-same-sealed-plan-and-receipt' {
    $case=New-StaticCase 'production-manifest-writer'
    Invoke-ProductionManifestWriter $case
    Invoke-StaticValidation $case
}

Check 'rejects-reserved-arm64x-plan-profile' {
    $case=New-StaticCase 'reserved-arm64x'
    $plan=Get-Content -LiteralPath $case.PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan.architectures=@('x86','arm64x')
    Write-RimePimeSealedJson $plan $case.PlanPath | Out-Null
    Assert-Rejected { Invoke-StaticValidation $case } '*Package plan identity or seal metadata is invalid*'
}

Check 'rejects-missing-package-plan-sidecar' {
    $case=New-StaticCase 'missing-plan-sidecar'
    Remove-Item -LiteralPath ($case.PlanPath+'.sha256')
    Assert-Rejected { Invoke-StaticValidation $case } '*sidecar is missing*'
}

Check 'rejects-package-plan-output-outside-repository-root' {
    $case=New-StaticCase 'plan-output-outside-root'
    $outside=Join-Path $output 'outside-package-plan.json'
    Assert-Rejected {
        Write-RimePimePackagePlan -RepoRoot $case.Root -PlanPath $outside -ArchitectureSet @('x86','x64')
    } '*inside the repository root*'
}

Check 'rejects-oversized-package-plan-sidecar' {
    $case=New-StaticCase 'oversized-plan-sidecar'
    [IO.File]::WriteAllText($case.PlanPath+'.sha256',('a'*257))
    Assert-Rejected { Invoke-StaticValidation $case } '*sidecar size is outside its sealed bound*'
}

Check 'rejects-artifact-changed-after-package-plan-seal' {
    $case=New-StaticCase 'artifact-after-plan'
    Add-Content -LiteralPath (Join-Path $case.Root 'go-backend\build\go-backend\server.exe') -Value 'changed'
    Assert-Rejected { Invoke-StaticValidation $case } '*does not match the sealed plan*'
}

Check 'rejects-wrong-machine-even-when-plan-hash-is-resealed' {
    $case=New-StaticCase 'wrong-plan-machine'
    Write-TestPe -Path (Join-Path $case.Root 'build\PIMETextService\Release\PIMETextService.dll') -Machine 0x8664
    Assert-Rejected {
        Write-RimePimePackagePlan -RepoRoot $case.Root -PlanPath $case.PlanPath -ArchitectureSet @('x86','x64')
    } '*expected 0x014C*'
}

Check 'rejects-delay-crt-even-when-plan-hash-is-resealed' {
    $case=New-StaticCase 'delay-crt-plan'
    Write-TestPe -Path (Join-Path $case.Root 'go-backend\build\go-backend\server.exe') -Machine 0x8664 `
        -ImportKind delay -ImportedDll 'vcruntime140.dll'
    Assert-Rejected {
        Write-RimePimePackagePlan -RepoRoot $case.Root -PlanPath $case.PlanPath -ArchitectureSet @('x86','x64')
    } '*forbidden dynamic CRT dependencies*'
}

Check 'rejects-extra-pe-in-recursively-packaged-go-tree' {
    $case=New-StaticCase 'extra-packaged-pe'
    Write-TestPe -Path (Join-Path $case.Root 'go-backend\build\go-backend\unplanned.bin') -Machine 0x8664
    Assert-Rejected {
        Write-RimePimePackagePlan -RepoRoot $case.Root -PlanPath $case.PlanPath -ArchitectureSet @('x86','x64')
    } '*PE set is not the exact sealed allowlist*'
}

Check 'rejects-missing-package-build-receipt' {
    $case=New-StaticCase 'missing-receipt'
    Remove-Item -LiteralPath $case.ReceiptPath
    Assert-Rejected { Invoke-StaticValidation $case } '*package build receipt is missing*'
}

Check 'rejects-package-receipt-output-outside-repository-root' {
    $case=New-StaticCase 'receipt-output-outside-root'
    $package=Read-RimePimePackagePlan -RepoRoot $case.Root -PlanPath $case.PlanPath -VerifyArtifacts
    Assert-Rejected {
        Write-RimePimePackageBuildReceipt -Package $package -InstallerPath $case.Installer `
            -InstallerSourcePath (Join-Path $case.Root 'installer\installer.nsi') `
            -ReceiptPath (Join-Path $output 'outside-package-receipt.json')
    } '*inside the repository root*'
}

Check 'rejects-installer-without-embedded-plan-digest' {
    $case=New-StaticCase 'missing-embedded-digest'
    Write-TestPe -Path $case.Installer
    Assert-Rejected { Invoke-StaticValidation $case } '*does not match the installer source, installer bytes, or embedded plan digest*'
}

Check 'rejects-manifest-package-plan-digest-mismatch' {
    $case=New-StaticCase 'manifest-plan-digest'
    $case.Manifest.packagePlan.sha256=('0'*64)
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*package-plan or build-receipt binding*'
}

Check 'rejects-omitted-package-plan-file-record' {
    $case=New-StaticCase 'omitted-plan-record'
    $case.Manifest.files=@($case.Manifest.files | Where-Object { $_.path -cne 'installer/package-plan.json' })
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*exact declared product-PE evidence set*'
}

Check 'rejects-truncated-installer' {
    $case=New-StaticCase 'truncated'
    Write-TestPe $case.Installer -Length 1024
    Assert-Rejected { Invoke-StaticValidation $case } '*unexpectedly small*'
}

Check 'rejects-bad-installer-dos-header' {
    $case=New-StaticCase 'bad-mz'
    $bytes=[IO.File]::ReadAllBytes($case.Installer);$bytes[0]=0;[IO.File]::WriteAllBytes($case.Installer,$bytes)
    Assert-Rejected { Invoke-StaticValidation $case } '*not a PE image*'
}

Check 'rejects-wrong-installer-machine' {
    $case=New-StaticCase 'wrong-machine'
    Write-TestPe $case.Installer -Machine 0x8664
    Assert-Rejected { Invoke-StaticValidation $case } '*not the expected Win32*'
}

Check 'rejects-missing-build-manifest' {
    $case=New-StaticCase 'missing-manifest'
    Remove-Item -LiteralPath $case.ManifestPath
    Assert-Rejected { Invoke-StaticValidation $case } '*requires the build manifest*'
}

Check 'rejects-malformed-build-manifest' {
    $case=New-StaticCase 'bad-json'
    Set-Content -LiteralPath $case.ManifestPath -Value '{' -Encoding UTF8
    Assert-Rejected { Invoke-StaticValidation $case } '*Invalid build manifest JSON*'
}

Check 'rejects-zero-installer-manifest-entry' {
    $case=New-StaticCase 'zero-installer'
    $case.Manifest.files=@($case.Manifest.files | Where-Object { $_.path -notlike 'installer/*.exe' })
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*exact declared product-PE evidence set*'
}

Check 'rejects-foreign-installer-basename-collision' {
    $case=New-StaticCase 'basename-collision'
    $foreign=Join-Path $case.Root 'foreign\YIME-1.4.0-dev-setup.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $foreign) | Out-Null
    Copy-Item -LiteralPath $case.Installer -Destination $foreign
    $case.Manifest.files+=@([pscustomobject][ordered]@{
        path='foreign/YIME-1.4.0-dev-setup.exe';size=[long](Get-Item $foreign).Length
        sha256=(Get-FileHash $foreign -Algorithm SHA256).Hash
    })
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*exact declared product-PE evidence set*'
}

Check 'rejects-installer-entry-at-foreign-path' {
    $case=New-StaticCase 'foreign-installer-path'
    $row=@($case.Manifest.files | Where-Object { $_.path -like 'installer/*.exe' })[0]
    $row.path='foreign/YIME-1.4.0-dev-setup.exe'
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*missing or case-mismatches*'
}

Check 'rejects-artifact-size-mismatch' {
    $case=New-StaticCase 'wrong-size'
    $case.Manifest.files[1].size=[long]$case.Manifest.files[1].size+1
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*content mismatch*'
}

Check 'rejects-artifact-hash-mismatch' {
    $case=New-StaticCase 'wrong-hash'
    $case.Manifest.files[1].sha256=('0'*64)
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*content mismatch*'
}

Check 'rejects-missing-non-installer-artifact' {
    $case=New-StaticCase 'missing-artifact'
    Remove-Item -LiteralPath (Join-Path $case.Root 'go-backend\build\go-backend\server.exe')
    Assert-Rejected { Invoke-StaticValidation $case } '*Package artifact is missing*'
}

Check 'rejects-unlisted-manifest-artifact' {
    $case=New-StaticCase 'unknown-artifact'
    $extra=Join-Path $case.Root 'foreign\extra.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $extra) | Out-Null
    Set-Content -LiteralPath $extra -Value 'extra' -Encoding UTF8
    $case.Manifest.files+=@([pscustomobject][ordered]@{
        path='foreign/extra.exe';size=[long](Get-Item $extra).Length
        sha256=(Get-FileHash $extra -Algorithm SHA256).Hash
    })
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*exact declared product-PE evidence set*'
}

Check 'rejects-open-manifest-schema' {
    $case=New-StaticCase 'open-schema'
    $case.Manifest | Add-Member -NotePropertyName extra -NotePropertyValue $true
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*schema*'
}

Check 'rejects-open-record-schema' {
    $case=New-StaticCase 'open-record'
    $case.Manifest.files[0] | Add-Member -NotePropertyName owner -NotePropertyValue 'foreign'
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*schema*'
}

Check 'rejects-parent-traversal-record' {
    $case=New-StaticCase 'parent-path'
    $case.Manifest.files[0].path='../installer/YIME-1.4.0-dev-setup.exe'
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*path*'
}

Check 'rejects-case-folded-record-duplicate' {
    $case=New-StaticCase 'case-duplicate'
    $row=$case.Manifest.files[1]
    $case.Manifest.files+=@([pscustomobject][ordered]@{
        path=$row.path.ToUpperInvariant();size=$row.size;sha256=$row.sha256
    })
    Write-StaticManifest $case
    Assert-Rejected { Invoke-StaticValidation $case } '*duplicate*'
}

foreach ($metadataCase in @(
    @{name='product';property='product';value='foreign'},
    @{name='version';property='version';value='0.0.0'},
    @{name='commit';property='commit';value=('b'*40)},
    @{name='ref';property='ref';value='refs/tags/foreign'},
    @{name='signed-state';property='signedRelease';value=$true}
)) {
    Check "rejects-wrong-$($metadataCase.name)" {
        $case=New-StaticCase "wrong-$($metadataCase.name)"
        $case.Manifest.($metadataCase.property)=$metadataCase.value
        Write-StaticManifest $case
        Assert-Rejected { Invoke-StaticValidation $case } '*manifest*'
    }.GetNewClosure()
}

$failed=@($checks | Where-Object { -not $_.passed })
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-installer-static-test-v1'
    generated_at=[DateTime]::UtcNow.ToString('o')
    test_level='synthetic-static-artifacts-only'
    checks_count=$checks.Count
    passed=$failed.Count -eq 0
    installer_executed=$false
    registry_or_process_touched=$false
    default_input_method_changed=$false
    production_user_data_read_or_written=$false
    verifier_sha256=$smokeHash
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks=@($checks)
}
$resultPath=Join-Path $output 'result.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($failed.Count) {
    foreach ($failure in $failed) { Write-Host "FAIL: $($failure.name): $($failure.error)" }
    throw "$($failed.Count) of $($checks.Count) installer-static checks failed."
}
Write-Host "PASS: $($checks.Count) synthetic installer-static checks passed. Evidence: $resultPath"
