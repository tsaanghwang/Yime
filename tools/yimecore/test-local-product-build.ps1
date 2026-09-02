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
$ids = Get-Content -LiteralPath (Join-Path $repo 'YimeTextServiceExperiment\YimeTextServiceIds.h') -Raw -Encoding UTF8
foreach ($pair in @(@('CLSID_YimeTextServiceExperiment','clsid'), @('GUID_YimeTextServiceExperimentProfile','profile'))) {
    $body = [regex]::Match($ids, ($pair[0] + '\s*=\s*\{(?<body>.*?)\};'), [Text.RegularExpressions.RegexOptions]::Singleline).Groups['body'].Value
    $tokens = @([regex]::Matches($body, '0x([0-9a-fA-F]+)'))
    Assert-Check ($tokens.Count -eq 11) "native GUID shape $($pair[0])"
    $widths = @(8,4,4,2,2,2,2,2,2,2,2)
    $actual = -join @(for ($i=0; $i -lt $tokens.Count; $i++) { $tokens[$i].Groups[1].Value.PadLeft($widths[$i],'0') })
    Assert-Check ($actual -ieq ($product.identity.($pair[1]) -replace '[{}-]','')) "stable native identity $($pair[0])"
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
