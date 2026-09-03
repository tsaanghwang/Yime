[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'local-product-build-common.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out = Join-Path $repo ('.tmp\yimecore-local-product\contract-' + [guid]::NewGuid().ToString('N'))
$out = New-LocalProductBuildRoot $repo $out
$checks = [Collections.Generic.List[string]]::new()
function Assert-Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $checks.Add($Name)
}
function Expect-Rejection([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Check $rejected $Name
}
$descriptorPath = Join-Path $PSScriptRoot 'local-product.json'
$product = Get-LocalProductDescriptor $descriptorPath
$legacyClsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
$legacyProfile = '{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
$approvedName = -join ([char[]](0x97F3,0x5143,0x62FC,0x97F3))
Assert-Check ($product.display_name -ceq $approvedName) 'local product uses the approved display name'
Assert-Check ($product.identity.clsid -cne $legacyClsid -and $product.identity.profile -cne $legacyProfile) `
    'local x64 product has an identity independent from the frozen legacy profile'
$decorated=Get-Content -LiteralPath $descriptorPath -TotalCount 1
$plain=Convert-LocalProductPlainText $decorated
$plainJson=ConvertTo-Json -InputObject @($plain) -Depth 2 -Compress
Assert-Check ($plainJson -eq '["{"]') 'PS5 evidence text must not serialize provider object graphs'
Assert-Check ($product.installable -eq $true -and $product.package_contract -eq 'yimecore-local-product-package-v1') 'installable candidate has a separate explicit contract'
Assert-LocalProductDependencies @('fmt', 'project/win32ui')
Assert-Check $true 'native tool UI is allowed outside core'
Expect-Rejection { Assert-LocalProductDependencies @('project/win32ui') -Core } 'core still rejects UI dependencies'
Expect-Rejection { Assert-LocalProductDependencies @('project/pime') } 'all tools reject PIME dependencies'
Expect-Rejection { Assert-LocalProductDependencies @('project/librime') } 'all tools reject Rime dependencies'
foreach ($path in @('', '..\outside', 'C:\Windows', '\\server\share', 'x/../y', 'x//y', 'x/y.', 'x/y ', 'x/y:ads')) {
    Expect-Rejection { Resolve-LocalProductChild $out $path } "reject path [$path]"
}
Expect-Rejection { New-LocalProductBuildRoot $repo $repo } 'reject workspace as output'
Expect-Rejection { New-LocalProductBuildRoot $repo $out } 'never reuse or erase prior output'
Assert-Check ((Resolve-LocalProductChild $out 'bin/YimeBroker.exe') -eq (Join-Path $out 'bin\YimeBroker.exe')) 'canonical child accepted'
foreach ($scenario in @('architecture', 'identity', 'installable', 'duplicate', 'command')) {
    $copy = Get-Content -LiteralPath $descriptorPath -Raw -Encoding UTF8 | ConvertFrom-Json
    switch ($scenario) {
        'architecture' { $copy.scope.active_architectures = @('x64','arm64') }
        'identity' { $copy.identity.model_source_id = 'changed' }
        'installable' { $copy.installable = $false }
        'duplicate' { $copy.assets += $copy.assets[0] }
        'command' { $copy.go_binaries[0].source = '../unexpected.go' }
    }
    $fixture = Join-Path $out "$scenario.json"
    Write-LocalProductJson $copy $fixture
    Expect-Rejection { Get-LocalProductDescriptor $fixture } "reject descriptor $scenario"
}
$template = Get-Content -LiteralPath (Join-Path $repo 'YimeTextServiceExperiment\LocalProductIdentity.h.in') -Raw -Encoding UTF8
foreach ($prefix in @('YIME_LOCAL_CLSID','YIME_LOCAL_PROFILE')) {
    foreach ($field in @('D1','D2','D3','B0','B1','B2','B3','B4','B5','B6','B7')) {
        Assert-Check $template.Contains("@$($prefix)_$field@") "generated native identity field $prefix/$field"
    }
}
$legacyIds = Get-Content -LiteralPath (Join-Path $repo 'YimeTextServiceExperiment\YimeTextServiceIds.h') -Raw -Encoding UTF8
Assert-Check ($legacyIds.Contains('#ifdef YIME_LOCAL_PRODUCT') -and $legacyIds.Contains('LocalProductIdentity.h')) `
    'native identity selection is compile-time isolated to local x64 builds'
foreach ($legacy in @($legacyClsid,$legacyProfile)) {
    $compact=$legacy.Trim('{}').Replace('-','').ToLowerInvariant()
    $tokens=@([regex]::Matches($legacyIds,'0x([0-9a-fA-F]+)'))
    $encoded=-join @($tokens|ForEach-Object{$_.Groups[1].Value.PadLeft($(if($_.Groups[1].Value.Length -gt 2){4}else{2}),'0')})
    Assert-Check ($encoded.Contains($compact)) "historical GUID remains available for frozen builds [$legacy]"
}
$runtime = Get-Content -LiteralPath (Join-Path $repo 'go-backend\cmd\yimecore-trial-runtime\main.go') -Raw -Encoding UTF8
foreach ($literal in @($product.identity.pipe, $product.identity.model_source_id, $product.identity.state_directory)) {
    Assert-Check ($runtime.Contains($literal)) "runtime preserves [$literal]"
}
$record = Get-LocalProductFileRecord $out 'identity.json'
Assert-LocalProductSourceUnchanged $out @($record)
Assert-Check $true 'source content hash verified'
'changed' | Set-Content -LiteralPath (Join-Path $out 'identity.json') -Encoding UTF8
Expect-Rejection { Assert-LocalProductSourceUnchanged $out @($record) } 'dirty source changes invalidate build'
Assert-LocalProductSourceSet @('a.go','b.go') @('a.go','b.go')
Assert-Check $true 'unchanged source inventory accepted'
Expect-Rejection { Assert-LocalProductSourceSet @('a.go') @('a.go','new.go') } 'new untracked source invalidates build'
Expect-Rejection { Assert-LocalProductSourceSet @('a.go','b.go') @('a.go') } 'removed source invalidates build'
foreach ($script in @('build-local-product.ps1', 'local-product-build-common.ps1', 'test-local-product-runtime.ps1')) {
    $parseTokens = $null; $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $script), [ref]$parseTokens, [ref]$parseErrors)
    Assert-Check (@($parseErrors).Count -eq 0) "PowerShell parser $script"
}
Write-LocalProductJson ([ordered]@{ passed=$true; count=$checks.Count; checks=@($checks); powershell=$PSVersionTable.PSVersion.ToString() }) (Join-Path $out 'summary.json')
Write-Output "PASS: $($checks.Count) local product build contracts. Evidence: $out"
