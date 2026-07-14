$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot 'verify-pe-architectures.ps1'
$x64Dll = Join-Path $root 'build64\PIMETextService\Release\PIMETextService.dll'
$launcher = Join-Path $root 'build\PIMELauncher\PIMELauncher.exe'

try {
    & $verifier -RepoRoot $root -X86TextService $x64Dll -X64TextService $x64Dll -X86Launcher $launcher
    throw 'Architecture verifier accepted an x64 DLL in the Win32 slot.'
} catch {
    if ($_.Exception.Message -notmatch 'Win32 PIMETextService\.dll expected 0x014C but found 0x8664') {
        throw
    }
    Write-Host 'Architecture mismatch rejection test passed.'
}

& $verifier -RepoRoot $root
Write-Host 'Build guard tests passed.'
