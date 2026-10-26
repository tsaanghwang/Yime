$ErrorActionPreference='Stop'
try {
 . 'C:\dev\Yime\tools\yimecore\build-system-observation.ps1'
 . 'C:\dev\Yime\tools\yimecore\local-product-build-common.ps1'
 $result=Get-LocalProductProtectionEvidence -HashesOnly
 Write-Output ('PROTECTION_HASH_COUNT='+$result.registry.Count)
} catch { Write-Output $_.Exception.Message;Write-Output $_.ScriptStackTrace;throw }
