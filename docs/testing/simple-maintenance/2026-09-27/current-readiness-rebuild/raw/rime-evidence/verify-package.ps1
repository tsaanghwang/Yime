[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo='C:\dev\Yime'
$delivery='C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312'
$evidence=Join-Path $delivery 'rime-evidence'
$package=Join-Path $delivery 'rime-build\rime-pime'
$payload=Join-Path $package 'payload'
$runtime=Join-Path $payload 'go-backend\input_methods\yime'
Start-Transcript -LiteralPath (Join-Path $evidence 'package-validation-transcript.log') -NoClobber
try {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $evidence 'verify-package.ps1')
    Set-Location -LiteralPath $repo
    Import-Module (Join-Path $package 'Product.psm1') -Force
    $parsed=Read-Package -Root $package
    Write-Host ('Read-Package passed: '+$parsed.manifest.product+' files='+$parsed.manifest.files.Count)
    & (Join-Path $repo 'tools\verify-pe-architectures.ps1') -RepoRoot $repo -X86TextService (Join-Path $payload 'x86\PIMETextService.dll') -X64TextService (Join-Path $payload 'x64\PIMETextService.dll') -X86Launcher (Join-Path $payload 'PIMELauncher.exe') -X86RegistrationStatus (Join-Path $payload 'x86\PIMERegistrationStatus.exe') -X64RegistrationStatus (Join-Path $payload 'x64\PIMERegistrationStatus.exe') -RimeDll (Join-Path $runtime 'rime.dll') -RimeDeployer (Join-Path $runtime 'rime_deployer.exe') -RimeDictManager (Join-Path $runtime 'rime_dict_manager.exe') -GoBackendRoot (Join-Path $payload 'go-backend')
    & (Join-Path $repo 'tools\verify-rime-runtime.ps1') -RuntimeDir $runtime -LockFile (Join-Path $runtime 'rime_runtime.lock.json')
    & python.exe 'tools/lexicon/verify_package_handoff.py' --package-root $runtime --repo-root $repo --output (Join-Path $evidence 'package-handoff.json')
    if($LASTEXITCODE -ne 0){throw "verify_package_handoff failed $LASTEXITCODE"}
    & python.exe '.tmp/current-readiness-delivery-20260927/rime/verify-rime.py'
    if($LASTEXITCODE -ne 0){throw "verify-rime failed $LASTEXITCODE"}
    Write-Host 'RIME_PACKAGE_VALIDATION_SUCCESS'
} finally {Stop-Transcript}
