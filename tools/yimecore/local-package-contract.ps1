# Package-local, read-only validation. Hashes prove consistency, not a trusted
# publisher signature. Native maintenance still requires the unpackaged guard.
function Assert-LocalProductPackage([string]$PackageRoot) {
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
    Assert-YimeCorePlainPath $root
    $manifestPath = Join-Path $root 'package-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.package_contract -ne 'yimecore-local-product-package-v1' -or
        $manifest.tool_version -ne 'yimecore-local-builder-v1') { throw 'Not an installable local product package.' }
    $expected = @{}
    foreach ($record in @($manifest.files)) {
        $relative = [string]$record.path
        if (-not $relative -or $relative -match '\\|:|(^|/)(\.|\.\.|)(/|$)|[. ](/|$)' -or
            [IO.Path]::IsPathRooted($relative) -or $expected.ContainsKey($relative) -or
            $relative -in @('package-manifest.json','install-metadata.json') -or
            [string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$record.bytes -lt 0) {
            throw "Invalid or duplicate local package record: $relative"
        }
        $expected[$relative] = $record
    }
    $count = 0
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Indirect package entry: $($item.FullName)" }
        if ($item.PSIsContainer) { continue }
        $relative = $item.FullName.Substring($root.Length + 1).Replace('\','/')
        if ($relative -in @('package-manifest.json','install-metadata.json')) { continue }
        $wanted = $expected[$relative]
        if (-not $wanted -or $item.Length -ne [long]$wanted.bytes -or
            (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ine [string]$wanted.sha256) {
            throw "Local package hash mismatch: $relative"
        }
        $count++
    }
    if ($count -ne $expected.Count -or -not $expected.ContainsKey('bin/YimeCoreIndependenceAudit.exe')) {
        throw 'Local package payload is incomplete.'
    }
    # The auditor is one of the hash-checked x64 payloads; it independently
    # checks the fixed file catalog, PE imports/architectures and install marker.
    $json = (& (Join-Path $root 'bin\YimeCoreIndependenceAudit.exe') -package $root -output -) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Local package contract/independence audit failed.' }
    $audit = $json | ConvertFrom-Json
    if (-not $audit.passed) { throw 'Local package audit did not pass.' }
    $descriptor = Get-Content -LiteralPath (Join-Path $root 'local-product.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    return [ordered]@{ root=$root; manifest=$manifest; descriptor=$descriptor; audit=$audit;
        manifest_sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Assert-LocalProductInstalledContext([string]$PackageRoot, [string]$StateRoot) {
    $package = Assert-LocalProductPackage $PackageRoot
    $state = [IO.Path]::GetFullPath($StateRoot)
    Assert-YimeCorePlainPath $state
    if ($state -ine [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YimeCore Experimental Trial'))) {
        throw 'Local maintenance must preserve the initiating user state namespace.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $package.root 'install-metadata.json') -PathType Leaf)) {
        throw 'This package is not the installed local product; install it before data maintenance.'
    }
    $config = Get-Content -LiteralPath (Join-Path $state 'runtime-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$config.install_root -ine $package.root -or [string]$config.state_root -ine $state -or
        [string]$config.runtime_path -ine (Join-Path $package.root 'bin\YimeCoreTrialRuntime.exe') -or
        [string]$config.broker_path -ine (Join-Path $package.root 'bin\YimeBroker.exe') -or
        [string]$config.pipe_name -cne '\\.\pipe\YimeBroker.YimeCoreTrial.v1') {
        throw 'Installed local product and current runtime configuration do not converge.'
    }
    return [ordered]@{package=$package; config=$config; state_root=$state}
}
