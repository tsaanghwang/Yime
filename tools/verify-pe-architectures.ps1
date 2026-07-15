param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$X86TextService,
    [string]$X64TextService,
    [string]$X86Launcher,
    [string]$Arm64TextService
)

$ErrorActionPreference = 'Stop'

if (-not $X86TextService) {
    $X86TextService = Join-Path $RepoRoot 'build\PIMETextService\Release\PIMETextService.dll'
}
if (-not $X64TextService) {
    $X64TextService = Join-Path $RepoRoot 'build64\PIMETextService\Release\PIMETextService.dll'
}
if (-not $X86Launcher) {
    $X86Launcher = Join-Path $RepoRoot 'build\PIMELauncher\PIMELauncher.exe'
}
if (-not $Arm64TextService) {
    $candidate = Join-Path $RepoRoot 'build_arm64\PIMETextService\Release\PIMETextService.dll'
    if (Test-Path -LiteralPath $candidate) {
        $Arm64TextService = $candidate
    }
}

function Get-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "PE file not found: $Path"
    }

    $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file (missing MZ header): $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a PE file (missing PE header): $Path"
        }
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$targets = @(
    @{ Path = $X86TextService; Expected = [uint16]0x014C; Label = 'Win32 PIMETextService.dll' }
    @{ Path = $X64TextService; Expected = [uint16]0x8664; Label = 'x64 PIMETextService.dll' }
    @{ Path = $X86Launcher; Expected = [uint16]0x014C; Label = 'Win32 PIMELauncher.exe' }
)
if ($Arm64TextService) {
    $targets += @{ Path = $Arm64TextService; Expected = [uint16]0xAA64; Label = 'ARM64 PIMETextService.dll' }
}

$failures = foreach ($target in $targets) {
    $machine = Get-PeMachine -Path $target.Path
    $actual = '0x{0:X4}' -f $machine
    $expected = '0x{0:X4}' -f $target.Expected
    Write-Host "$($target.Label): $actual ($($target.Path))"
    if ($machine -ne $target.Expected) {
        "$($target.Label) expected $expected but found ${actual}: $($target.Path)"
    }
}

if ($failures) {
    throw "PE architecture verification failed:`n$($failures -join "`n")"
}

Write-Host 'PE architecture verification passed.'
