[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent=Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-payload-closure-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-payload-closure-* fixture root.'
}
for ($cursor=$expectedParent; $cursor; $cursor=Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Payload-closure evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$helperPath=Join-Path $PSScriptRoot 'rime-pime-payload-closure.ps1'
$helperHash=(Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant()
$beforeFunctions=@(Get-Command -CommandType Function | ForEach-Object Name)
. $helperPath

$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action) {
    try {
        & $Action
        $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$true})
    } catch {
        $checks.Add([pscustomobject][ordered]@{name=$Name;passed=$false;error=$_.Exception.Message})
    }
}
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action,[string]$Like='*') {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike $Like) {
            throw "Unexpected rejection: $($_.Exception.Message)"
        }
        return
    }
    throw 'Unsafe payload case was accepted.'
}

function Write-CaseManifest($Case) {
    $Case.Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Case.Trusted -Encoding UTF8
    Copy-Item -LiteralPath $Case.Trusted -Destination $Case.Installed -Force
}

function New-PayloadCase([string]$Name) {
    $caseRoot=Join-Path $output $Name
    $payload=Join-Path $caseRoot 'payload'
    $trustedDir=Join-Path $caseRoot 'trusted'
    New-Item -ItemType Directory -Path $payload,$trustedDir | Out-Null
    $content=[ordered]@{
        'PIMELauncher.exe'='fixture launcher'
        'Uninstall.exe'='fixture independently signed uninstaller'
        'maintenance-helper.exe'='fixture maintenance helper'
        'fonts/annotation-note.txt'='font ownership marker'
        'go-backend/server.exe'='fixture backend'
        'licenses/NOTICE.md'='fixture notice'
        'version.txt'='1.4.0-dev'
        'x64/PIMETextService.dll'='fixture x64 text service'
        'x86/PIMETextService.dll'='fixture x86 text service'
    }
    foreach ($relative in $content.Keys) {
        $path=Join-Path $payload $relative.Replace('/','\')
        $parent=Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        Set-Content -LiteralPath $path -Value $content[$relative] -Encoding UTF8
    }
    $paths=[Collections.Generic.List[string]]::new()
    foreach ($relative in $content.Keys) {
        if ($relative -cne 'Uninstall.exe') { $paths.Add($relative) }
    }
    $paths.Sort([StringComparer]::Ordinal)
    $rows=[Collections.Generic.List[object]]::new()
    foreach ($relative in $paths) {
        $path=Join-Path $payload $relative.Replace('/','\')
        $owner=switch -Regex ($relative) {
            '^licenses/' {'license';break}
            '^fonts/' {'font';break}
            '^go-backend/' {'backend';break}
            '^x(64|86)/' {'text-service';break}
            '^maintenance-helper\.exe$' {'maintenance';break}
            '^PIMELauncher\.exe$' {'runtime';break}
            default {'metadata'}
        }
        $architecture=switch -Regex ($relative) {
            '^x64/' {'x64';break}
            '^x86/' {'x86';break}
            '^PIMELauncher\.exe$' {'x86';break}
            default {'neutral'}
        }
        $rows.Add([pscustomobject][ordered]@{
            path=$relative
            bytes=[long](Get-Item -LiteralPath $path).Length
            sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            owner_class=$owner
            architecture=$architecture
        })
    }
    $manifest=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-install-payload-v1'
        product='rime-pime'
        product_version='1.4.0-dev'
        architectures=@('x86','x64')
        manifest_path='install-payload-manifest.json'
        special_files=@([pscustomobject][ordered]@{
            path='Uninstall.exe'
            identity_class='signed-self-image-v1'
        })
        files=@($rows)
    }
    $trustedUninstaller=Join-Path $trustedDir 'trusted-Uninstall.exe'
    Copy-Item -LiteralPath (Join-Path $payload 'Uninstall.exe') -Destination $trustedUninstaller
    $specialFiles=@([pscustomobject][ordered]@{
        path='Uninstall.exe'
        bytes=[long](Get-Item -LiteralPath $trustedUninstaller).Length
        sha256=(Get-FileHash -LiteralPath $trustedUninstaller -Algorithm SHA256).Hash.ToLowerInvariant()
        trust_class='authenticode-product-self-image-v1'
    })
    $case=[pscustomobject][ordered]@{
        Root=$caseRoot
        Payload=$payload
        Trusted=(Join-Path $trustedDir 'install-payload-manifest.json')
        Installed=(Join-Path $payload 'install-payload-manifest.json')
        Manifest=$manifest
        SpecialFiles=$specialFiles
    }
    Write-CaseManifest $case
    return $case
}

function Invoke-CaseClosure($Case,[scriptblock]$BetweenPassHook) {
    if ($null -eq $BetweenPassHook) {
        return Test-YimePimePayloadClosure $Case.Payload $Case.Trusted $Case.Installed $Case.SpecialFiles
    }
    return Test-YimePimePayloadClosure $Case.Payload $Case.Trusted $Case.Installed $Case.SpecialFiles `
        -BetweenPassHook $BetweenPassHook
}

Check 'definitions-only-helper-loads-without-product-action' {
    Assert-True ((Get-Command Test-YimePimePayloadClosure -CommandType Function -ErrorAction Stop) -ne $null) 'Closure function is missing.'
    Assert-True ((Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $helperHash) 'Helper changed while loading.'
    Assert-True ((@($beforeFunctions | Where-Object { $_ -like 'Test-YimePimePayloadClosure' })).Count -eq 0) 'Fixture shell was already contaminated.'
}

Check 'exact-closed-tree-passes-twice' {
    $case=New-PayloadCase 'positive'
    $result=Invoke-CaseClosure $case
    Assert-True ($result.passed -and $result.file_count -eq 10 -and $result.directory_count -eq 5) 'Closed-tree counts are wrong.'
    Assert-True (-not $result.actual_install_or_removal_executed) 'Pure validation claimed a product mutation.'
}

foreach ($invalid in @(
    @{name='absolute-path';path='C:/outside.bin'},
    @{name='parent-segment';path='../outside.bin'},
    @{name='ads-path';path='version.txt:secret'},
    @{name='backslash-path';path='go-backend\server.exe'},
    @{name='trailing-dot';path='bad./file.bin'},
    @{name='reserved-device';path='aux.txt'}
)) {
    Check "manifest-rejects-$($invalid.name)" {
        $case=New-PayloadCase "invalid-$($invalid.name)"
        $case.Manifest.files[0].path=$invalid.path
        Write-CaseManifest $case
        Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*payload*'
    }.GetNewClosure()
}

Check 'manifest-rejects-case-folded-file-duplicate' {
    $case=New-PayloadCase 'case-duplicate'
    $first=$case.Manifest.files[0]
    $duplicate=[pscustomobject][ordered]@{
        path=$first.path.ToLowerInvariant();bytes=$first.bytes;sha256=$first.sha256
        owner_class=$first.owner_class;architecture=$first.architecture
    }
    $case.Manifest.files=@($first,$duplicate)+@($case.Manifest.files | Select-Object -Skip 1)
    Write-CaseManifest $case
    Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*duplicate*'
}

Check 'manifest-rejects-manifest-file-collision' {
    $case=New-PayloadCase 'manifest-collision'
    $case.Manifest.manifest_path=[string]$case.Manifest.files[0].path
    Write-CaseManifest $case
    Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*duplicate*'
}

Check 'manifest-rejects-open-root-schema' {
    $case=New-PayloadCase 'open-schema'
    $case.Manifest | Add-Member -NotePropertyName untrusted_extension -NotePropertyValue $true
    Write-CaseManifest $case
    Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*schema*'
}

Check 'manifest-rejects-invalid-architecture' {
    $case=New-PayloadCase 'bad-architecture'
    $case.Manifest.architectures=@('x86','arm64')
    Write-CaseManifest $case
    Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*architecture*'
}

Check 'manifest-rejects-uninstaller-as-ordinary-row' {
    $case=New-PayloadCase 'uninstaller-self-identity'
    $case.Manifest.files[0].path='Uninstall.exe'
    Write-CaseManifest $case
    Assert-Rejected { Read-YimePimePayloadManifest $case.Trusted } '*self-identity contract*'
}

Check 'closure-rejects-missing-verified-special-uninstaller' {
    $case=New-PayloadCase 'missing-special-record'
    Assert-Rejected {
        Test-YimePimePayloadClosure -InstallRoot $case.Payload -TrustedManifestPath $case.Trusted `
            -InstalledManifestPath $case.Installed -VerifiedSpecialFiles @()
    } '*special*'
}

Check 'closure-rejects-wrong-special-uninstaller-hash' {
    $case=New-PayloadCase 'wrong-special-hash'
    $case.SpecialFiles[0].sha256=('0'*64)
    Assert-Rejected { Invoke-CaseClosure $case } '*content mismatch*'
}

Check 'closure-rejects-unlisted-file' {
    $case=New-PayloadCase 'unknown-file'
    Set-Content -LiteralPath (Join-Path $case.Payload 'unknown.bin') -Value 'unknown' -Encoding UTF8
    Assert-Rejected { Invoke-CaseClosure $case } '*Unlisted payload file*'
}

Check 'closure-rejects-unlisted-empty-directory' {
    $case=New-PayloadCase 'unknown-directory'
    New-Item -ItemType Directory -Path (Join-Path $case.Payload 'unknown-dir') | Out-Null
    Assert-Rejected { Invoke-CaseClosure $case } '*directory*'
}

Check 'closure-rejects-modified-file' {
    $case=New-PayloadCase 'modified-file'
    Add-Content -LiteralPath (Join-Path $case.Payload 'version.txt') -Value 'changed'
    Assert-Rejected { Invoke-CaseClosure $case } '*content mismatch*'
}

Check 'closure-rejects-missing-file' {
    $case=New-PayloadCase 'missing-file'
    Remove-Item -LiteralPath (Join-Path $case.Payload 'version.txt')
    Assert-Rejected { Invoke-CaseClosure $case } '*missing files*'
}

Check 'closure-rejects-file-directory-type-swap' {
    $case=New-PayloadCase 'type-swap'
    $target=Join-Path $case.Payload 'version.txt'
    Remove-Item -LiteralPath $target
    New-Item -ItemType Directory -Path $target | Out-Null
    Assert-Rejected { Invoke-CaseClosure $case } '*became a directory*'
}

Check 'closure-rejects-installed-manifest-byte-mismatch' {
    $case=New-PayloadCase 'manifest-mismatch'
    Add-Content -LiteralPath $case.Installed -Value ' '
    Assert-Rejected { Invoke-CaseClosure $case } '*manifest bytes*'
}

Check 'closure-rejects-alternate-installed-manifest-location' {
    $case=New-PayloadCase 'manifest-location'
    $alternate=Join-Path $case.Payload 'alternate-manifest.json'
    Copy-Item -LiteralPath $case.Installed -Destination $alternate
    Assert-Rejected {
        Test-YimePimePayloadClosure $case.Payload $case.Trusted $alternate $case.SpecialFiles
    } '*path does not match*'
}

Check 'closure-rejects-trusted-manifest-inside-payload' {
    $case=New-PayloadCase 'manifest-independence'
    Assert-Rejected {
        Test-YimePimePayloadClosure $case.Payload $case.Installed $case.Installed $case.SpecialFiles
    } '*independent*'
}

Check 'closure-rejects-child-junction' {
    $case=New-PayloadCase 'junction'
    $backend=Join-Path $case.Payload 'go-backend'
    $outside=Join-Path $case.Root 'outside-backend'
    New-Item -ItemType Directory -Path $outside | Out-Null
    Move-Item -LiteralPath (Join-Path $backend 'server.exe') -Destination (Join-Path $outside 'server.exe')
    Remove-Item -LiteralPath $backend
    New-Item -ItemType Junction -Path $backend -Target $outside | Out-Null
    Assert-Rejected { Invoke-CaseClosure $case } '*Indirect payload entry*'
}

Check 'closure-rejects-hard-linked-file' {
    $case=New-PayloadCase 'hardlink'
    New-Item -ItemType HardLink -Path (Join-Path $case.Root 'outside-link.bin') `
        -Target (Join-Path $case.Payload 'version.txt') | Out-Null
    Assert-Rejected { Invoke-CaseClosure $case } '*Hard-linked*'
}

Check 'closure-rejects-file-alternate-data-stream' {
    $case=New-PayloadCase 'stream'
    Set-Content -LiteralPath ((Join-Path $case.Payload 'version.txt')+':private') -Value 'hidden' -Encoding UTF8
    Assert-Rejected { Invoke-CaseClosure $case } '*Alternate data stream*'
}

Check 'closure-rejects-case-mismatched-tree-entry' {
    $case=New-PayloadCase 'case-mismatch'
    $row=@($case.Manifest.files | Where-Object { $_.path -ceq 'x86/PIMETextService.dll' })[0]
    $row.path='x86/pIMETextService.dll'
    Write-CaseManifest $case
    Assert-Rejected { Invoke-CaseClosure $case } '*case mismatch*'
}

Check 'closure-rejects-second-pass-insertion' {
    $case=New-PayloadCase 'toctou-insert'
    Assert-Rejected {
        Invoke-CaseClosure $case -BetweenPassHook {
            param($root)
            Set-Content -LiteralPath (Join-Path $root 'raced.bin') -Value 'race' -Encoding UTF8
        }
    } '*Unlisted payload file*'
}

Check 'closure-rejects-second-pass-content-change' {
    $case=New-PayloadCase 'toctou-content'
    Assert-Rejected {
        Invoke-CaseClosure $case -BetweenPassHook {
            param($root)
            Add-Content -LiteralPath (Join-Path $root 'version.txt') -Value 'race'
        }
    } '*content mismatch*'
}

$failed=@($checks | Where-Object { -not $_.passed })
$result=[pscustomobject][ordered]@{
    schema_version='yime-rime-pime-payload-closure-test-v1'
    generated_at=[DateTime]::UtcNow.ToString('o')
    test_level='isolated-fixtures-only'
    checks_count=$checks.Count
    passed=$failed.Count -eq 0
    actual_installer_or_uninstaller_executed=$false
    registry_or_process_touched=$false
    default_input_method_changed=$false
    production_user_data_read_or_written=$false
    helper_sha256=$helperHash
    test_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks=@($checks)
}
$resultPath=Join-Path $output 'result.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($failed.Count) {
    foreach ($failure in $failed) { Write-Host "FAIL: $($failure.name): $($failure.error)" }
    throw "$($failed.Count) of $($checks.Count) payload-closure checks failed."
}
Write-Host "PASS: $($checks.Count) isolated payload-closure checks passed. Evidence: $resultPath"
