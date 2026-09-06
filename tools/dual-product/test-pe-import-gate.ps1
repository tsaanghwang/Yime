[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$expectedParent = Join-Path $repo '.tmp\dual-product'
if ((Split-Path -Parent $output) -ine $expectedParent -or
    (Split-Path -Leaf $output) -cnotmatch '^dp1-pe-import-gate-[a-zA-Z0-9-]+$' -or
    (Test-Path -LiteralPath $output)) {
    throw 'Use a new immediate .tmp/dual-product/dp1-pe-import-gate-* fixture root.'
}
for ($cursor = $expectedParent; $cursor; $cursor = Split-Path -Parent $cursor) {
    if ((Test-Path -LiteralPath $cursor) -and
        ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'PE-import evidence path traverses a reparse point.'
    }
    if ($cursor -ieq (Split-Path -Qualifier $cursor)) { break }
}
if (-not (Test-Path -LiteralPath $expectedParent)) {
    New-Item -ItemType Directory -Path $expectedParent -Force | Out-Null
}
New-Item -ItemType Directory -Path $output | Out-Null

$verifier = Join-Path $repo 'tools\verify-pe-architectures.ps1'
$verifierHash = (Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash.ToLowerInvariant()
$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Action) {
    try { & $Action; $checks.Add([pscustomobject]@{name=$Name;passed=$true}) }
    catch { $checks.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message}) }
}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Like) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike $Like) {
            throw "Unexpected rejection: $($_.Exception.Message)"
        }
        return
    }
    throw 'Unsafe synthetic PE image was accepted.'
}

function Set-UInt16([byte[]]$Bytes, [int]$Offset, [uint16]$Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}
function Set-UInt32([byte[]]$Bytes, [int]$Offset, [uint32]$Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}

function Write-SyntheticPe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][uint16]$Machine,
        [ValidateSet('none','normal','delay')][string]$ImportKind = 'none',
        [string]$ImportedDll = ''
    )

    $isPe32Plus = $Machine -ne 0x014c
    $optionalSize = if ($isPe32Plus) { 0xF0 } else { 0xE0 }
    $optionalMagic = if ($isPe32Plus) { [uint16]0x020b } else { [uint16]0x010b }
    $peOffset = 0x80
    $optionalOffset = $peOffset + 24
    $sectionOffset = $optionalOffset + $optionalSize
    $numberOfDirectoriesOffset = if ($isPe32Plus) { $optionalOffset + 108 } else { $optionalOffset + 92 }
    $directoryOffset = if ($isPe32Plus) { $optionalOffset + 112 } else { $optionalOffset + 96 }
    $bytes = New-Object byte[] 0x400

    $bytes[0] = 0x4d
    $bytes[1] = 0x5a
    Set-UInt32 $bytes 0x3c $peOffset
    $bytes[$peOffset] = 0x50
    $bytes[$peOffset + 1] = 0x45
    Set-UInt16 $bytes ($peOffset + 4) $Machine
    Set-UInt16 $bytes ($peOffset + 6) 1
    Set-UInt16 $bytes ($peOffset + 20) $optionalSize
    Set-UInt16 $bytes $optionalOffset $optionalMagic
    Set-UInt32 $bytes ($optionalOffset + 60) 0x200
    Set-UInt32 $bytes $numberOfDirectoriesOffset 16

    [Text.Encoding]::ASCII.GetBytes('.rdata').CopyTo($bytes, $sectionOffset)
    Set-UInt32 $bytes ($sectionOffset + 8) 0x200
    Set-UInt32 $bytes ($sectionOffset + 12) 0x1000
    Set-UInt32 $bytes ($sectionOffset + 16) 0x200
    Set-UInt32 $bytes ($sectionOffset + 20) 0x200

    if ($ImportKind -ne 'none') {
        if ([string]::IsNullOrWhiteSpace($ImportedDll) -or $ImportedDll.Length -gt 127) {
            throw 'Synthetic import names must contain 1 through 127 characters.'
        }
        $nameBytes = [Text.Encoding]::ASCII.GetBytes($ImportedDll + [char]0)
        $nameBytes.CopyTo($bytes, 0x280)
        if ($ImportKind -eq 'normal') {
            Set-UInt32 $bytes ($directoryOffset + 8) 0x1000
            Set-UInt32 $bytes ($directoryOffset + 12) 40
            Set-UInt32 $bytes (0x200 + 12) 0x1080
            Set-UInt32 $bytes (0x200 + 16) 0x1090
        } else {
            Set-UInt32 $bytes ($directoryOffset + (13 * 8)) 0x1000
            Set-UInt32 $bytes ($directoryOffset + (13 * 8) + 4) 64
            Set-UInt32 $bytes 0x200 1
            Set-UInt32 $bytes 0x204 0x1080
        }
    }

    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-PeGateCase([string]$Name) {
    $root = Join-Path $output $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    $case = [pscustomobject][ordered]@{
        Root = $root
        X86TextService = Join-Path $root 'x86-text-service.dll'
        X64TextService = Join-Path $root 'x64-text-service.dll'
        X86Launcher = Join-Path $root 'x86-launcher.exe'
        X86RegistrationStatus = Join-Path $root 'x86-registration-status.exe'
        X64RegistrationStatus = Join-Path $root 'x64-registration-status.exe'
    }
    Write-SyntheticPe -Path $case.X86TextService -Machine 0x014c
    Write-SyntheticPe -Path $case.X64TextService -Machine 0x8664
    Write-SyntheticPe -Path $case.X86Launcher -Machine 0x014c
    Write-SyntheticPe -Path $case.X86RegistrationStatus -Machine 0x014c
    Write-SyntheticPe -Path $case.X64RegistrationStatus -Machine 0x8664
    $case
}

function Invoke-PeGate {
    param(
        $Case,
        [string]$Arm64TextService,
        [string]$Arm64RegistrationStatus
    )
    $arguments = @{
        RepoRoot = $Case.Root
        X86TextService = $Case.X86TextService
        X64TextService = $Case.X64TextService
        X86Launcher = $Case.X86Launcher
        X86RegistrationStatus = $Case.X86RegistrationStatus
        X64RegistrationStatus = $Case.X64RegistrationStatus
        SkipPackagedRime = $true
    }
    if ($Arm64TextService) { $arguments.Arm64TextService = $Arm64TextService }
    if ($Arm64RegistrationStatus) { $arguments.Arm64RegistrationStatus = $Arm64RegistrationStatus }
    & $verifier @arguments
}

Check 'accepts-images-with-no-import-directories-without-executing-them' {
    $case = New-PeGateCase 'no-imports'
    Invoke-PeGate $case | Out-Null
}

Check 'accepts-safe-normal-import' {
    $case = New-PeGateCase 'safe-normal'
    Write-SyntheticPe -Path $case.X86TextService -Machine 0x014c -ImportKind normal -ImportedDll 'kernel32.dll'
    Invoke-PeGate $case | Out-Null
}

Check 'accepts-safe-delay-import' {
    $case = New-PeGateCase 'safe-delay'
    Write-SyntheticPe -Path $case.X64TextService -Machine 0x8664 -ImportKind delay -ImportedDll 'kernel32.dll'
    Invoke-PeGate $case | Out-Null
}

Check 'default-gate-ignores-unselected-stale-arm64-build-tree' {
    $case = New-PeGateCase 'stale-unselected-arm64'
    $armRoot = Join-Path $case.Root 'build_arm64\PIMETextService\Release'
    New-Item -ItemType Directory -Path $armRoot | Out-Null
    Write-SyntheticPe -Path (Join-Path $armRoot 'PIMETextService.dll') -Machine 0x014c
    Write-SyntheticPe -Path (Join-Path $armRoot 'PIMERegistrationStatus.exe') -Machine 0x014c
    Invoke-PeGate $case | Out-Null
}

Check 'accepts-explicit-paired-arm64-inputs' {
    $case = New-PeGateCase 'explicit-arm64'
    $armTextService = Join-Path $case.Root 'explicit-arm64-text-service.dll'
    $armStatus = Join-Path $case.Root 'explicit-arm64-registration-status.exe'
    Write-SyntheticPe -Path $armTextService -Machine 0xaa64
    Write-SyntheticPe -Path $armStatus -Machine 0xaa64
    Invoke-PeGate $case -Arm64TextService $armTextService -Arm64RegistrationStatus $armStatus | Out-Null
}

Check 'rejects-one-sided-arm64-input' {
    $case = New-PeGateCase 'one-sided-arm64'
    $armTextService = Join-Path $case.Root 'explicit-arm64-text-service.dll'
    Write-SyntheticPe -Path $armTextService -Machine 0xaa64
    Assert-Rejected { Invoke-PeGate $case -Arm64TextService $armTextService } `
        '*requires both -Arm64TextService and -Arm64RegistrationStatus explicitly*'
}

Check 'rejects-msvcr-in-normal-import-directory' {
    $case = New-PeGateCase 'normal-msvcr'
    Write-SyntheticPe -Path $case.X86Launcher -Machine 0x014c -ImportKind normal -ImportedDll 'msvcr120.dll'
    Assert-Rejected { Invoke-PeGate $case } '*imports forbidden dynamic CRT dependencies:*msvcr120.dll*'
}

Check 'rejects-vcruntime-in-delay-import-directory' {
    $case = New-PeGateCase 'delay-vcruntime'
    Write-SyntheticPe -Path $case.X64RegistrationStatus -Machine 0x8664 -ImportKind delay -ImportedDll 'vcruntime140.dll'
    Assert-Rejected { Invoke-PeGate $case } '*imports forbidden dynamic CRT dependencies:*vcruntime140.dll*'
}

Check 'verifier-source-remains-unchanged-during-synthetic-read-only-gates' {
    Assert-True ((Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $verifierHash) `
        'PE verifier changed while its synthetic fixtures were checked.'
}

$failed = @($checks | Where-Object { -not $_.passed })
$result = [pscustomobject][ordered]@{
    schema_version = 'yime-pe-import-gate-test-v1'
    generated_at = [DateTime]::UtcNow.ToString('o')
    test_level = 'isolated-static-no-execution'
    checks_count = $checks.Count
    passed = $failed.Count -eq 0
    synthetic_pe_images_executed = $false
    installer_or_registration_entry_executed = $false
    registry_or_process_touched = $false
    default_input_method_changed = $false
    production_user_data_read_or_written = $false
    verifier_sha256 = $verifierHash
    test_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks = @($checks)
}
$resultPath = Join-Path $output 'result.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($failed.Count) {
    foreach ($failure in $failed) { Write-Host "FAIL: $($failure.name): $($failure.error)" }
    throw "$($failed.Count) of $($checks.Count) PE-import checks failed."
}
Write-Host "PASS: $($checks.Count) synthetic PE-import checks passed without executing a fixture. Evidence: $resultPath"
