$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'tools/yimecore/local-product-build-common.ps1')
. (Join-Path $repo 'tools/yimecore/local-product-speech-build.ps1')
$output=Join-Path $PSScriptRoot 'pr78-r2-admission-readonly.json'
if(Test-Path -LiteralPath $output){throw 'Preserve previous R2 check evidence.'}
$admission='C:\dev\Yime\.tmp\yimecore-experiment\speech-admission-20261026-201515-5d821f4f168e4024af3615cffc00b779'
$summarySHA='b1423ab265d78bcfb2e3b0e366f019381a00245c15d8be1854244fd9d29cff4e'
$inventorySHA='d52f43b5d6ec5a9c088aa616a85e3927dc2f4291dce638e43e91126eaa00709e'
$product=Get-LocalProductDescriptor (Join-Path $repo 'tools/yimecore/local-product.json')
$passed=Assert-LocalProductSpeechBuildInputs $product $admission $summarySHA $inventorySHA -ExpectedTarget arm64
Write-LocalProductJson ([ordered]@{
    observed_at_utc=[DateTime]::UtcNow.ToString('o');passed=[bool]$passed
    fixed_r2_admission_root=$admission;summary_sha256=$summarySHA;source_inventory_sha256=$inventorySHA
    expected_target='arm64';guard_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'tools/yimecore/local-product-speech-build.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    scope='Read-only new preflight against original pinned R2 admission. No admission/export/build/install. Does not compare that historical source inventory with the newly merged source.'
}) $output
Write-Output ('PASS: fixed R2 admission satisfies the new native ARM64 preflight. '+$output)
