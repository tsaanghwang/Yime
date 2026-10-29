[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer=Join-Path $repo '.generated/arm64-toolchain/downloads/vs_BuildTools.exe'
$expected='4aad1082e180f558598c346eb105b465b4908148cb9f7f0511aa1105620e0c30'
if((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'Installer hash changed.'}
$signature=Get-AuthenticodeSignature -LiteralPath $installer
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=Microsoft Corporation,'){throw 'Expected a valid Microsoft installer signature.'}
$destination='C:\Program Files\Microsoft Visual Studio\2022\BuildTools'
$components=@('Microsoft.VisualStudio.Workload.VCTools','Microsoft.VisualStudio.Component.VC.Tools.ARM64','Microsoft.VisualStudio.Component.Windows11SDK.26100','Microsoft.VisualStudio.Component.VC.CMake.Project')
$arguments=@('--quiet','--wait','--norestart','--installPath',('"'+$destination+'"'))
foreach($component in $components){$arguments+=@('--add',$component)}
$started=[DateTime]::UtcNow.ToString('o')
$code=$null;$failure=$null
try {
    $process=Start-Process -FilePath $installer -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    $code=$process.ExitCode
} catch {$failure=$_.Exception.Message}
$record=[ordered]@{scope='Development compiler/SDK only; no input-method installation';started_at_utc=$started;finished_at_utc=[DateTime]::UtcNow.ToString('o');source_url='https://aka.ms/vs/17/release/vs_BuildTools.exe';installer_sha256=$expected;signer=$signature.SignerCertificate.Subject;bootstrapper_version=(Get-Item -LiteralPath $installer).VersionInfo.FileVersion;install_path=$destination;components=$components;exit_code=$code;failure=$failure;automatic_restart=$false;restart_required=($code -eq 3010)}
$report=Join-Path $repo 'docs/testing/arm64/2026-10-26/native-build-toolchain-install.json'
if(Test-Path -LiteralPath $report){throw 'Preserve previous installer receipt.'}
$record|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $report -Encoding utf8
$record|ConvertTo-Json -Depth 5
if($null -ne $failure){throw $failure}
if($code -ne 0){throw ('Build Tools returned '+$code+'; no automatic restart or compilation.')}
