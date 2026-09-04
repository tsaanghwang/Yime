# Build-only helpers. No installation, registry writes, or live AppData access.
Set-StrictMode -Version Latest

function Write-LocalProductJson($Value, [string]$Path) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Convert-LocalProductPlainText($Value) {
    # PS5 Get-Content decorates strings with PSDrive/PSProvider. Serializing
    # that graph at evidence depth can grow without bound; keep literal text.
    return $Value.ToString()
}

function Assert-LocalProductDependencies($Dependencies, [switch]$Core) {
    $forbidden = @($Dependencies | Where-Object {
        $_ -match '(^|/)pime($|/)|librime|native_cgo' -or
        $_ -eq 'github.com/tsaanghwang/Yime/go-backend/input_methods/yime' -or
        ($Core -and $_ -match '(^|/)win32ui($|/)')
    })
    if ($forbidden.Count) { throw "Forbidden runtime dependencies (core=$Core): $($forbidden -join ', ')" }
}

function Resolve-LocalProductChild([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match ':' -or
        $Relative -match '(^|[\\/])(\.|\.\.|)([\\/]|$)' -or
        $Relative -match '[. ]([\\/]|$)') { throw "Non-canonical relative path: $Relative" }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes root: $Relative"
    }
    Assert-LocalProductPlainPath $path
    return $path
}

function Assert-LocalProductPlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Build paths must not traverse a symlink or junction: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Get-LocalProductDescriptor([string]$Path) {
    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($value.schema_version -ne 'yimecore-local-product-v1' -or
        $value.package_contract -notin @('yimecore-local-runtime-bundle-v1','yimecore-local-product-package-v1') -or
        ($value.installable -ne ($value.package_contract -eq 'yimecore-local-product-package-v1')) -or
        $value.version -notmatch '^\d+\.\d+\.\d+-local\.\d+$' -or
        $value.scope.computer_name -ne 'MYCOMPUTER' -or
        @($value.scope.active_architectures).Count -ne 2 -or
        $value.scope.active_architectures[0] -ne 'x64' -or
        $value.scope.active_architectures[1] -ne 'x86') {
        throw 'Unsupported local product descriptor, scope or package contract'
    }
    $expected = @{
        product_key = 'YimeCoreExperimentalTrial'
        clsid = '{E40FA752-BB96-461D-A51D-F40EB437EC65}'
        profile = '{126F54C6-E9B1-4E22-8652-03224CBD49F9}'
        legacy_clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
        legacy_profile = '{607895A8-9504-4A2E-9BB1-2C159E3A1757}'
        state_directory = 'YimeCore Experimental Trial'
        install_directory = 'YimeCore Experimental Trial'
        pipe = '\\.\pipe\YimeBroker.YimeCoreTrial.v1'
        model_source_id = 'yimecore-e6c-three-mode-trial-v1'
    }
    foreach ($name in $expected.Keys) {
        if ($value.identity.$name -cne $expected[$name]) { throw "Stable identity changed: $name" }
    }
    $seen = @{}
    $maintenance = if ($value.PSObject.Properties['maintenance_assets']) { @($value.maintenance_assets) } else { @() }
    foreach ($entry in @($value.go_binaries) + @($value.assets) + @($maintenance)) {
        $null = Resolve-LocalProductChild $PSScriptRoot $entry.path
        if ($seen.ContainsKey($entry.path)) { throw "Duplicate payload: $($entry.path)" }
        $seen[$entry.path] = $true
    }
    foreach ($entry in $value.go_binaries) {
        if ($entry.path -notmatch '^bin/[A-Za-z0-9]+\.exe$' -or
            ($entry.source -notmatch '^\./cmd/[a-z0-9-]+$' -and
             $entry.source -ne '../tools/yimecore/model-recovery-probe.go')) {
            throw "Unsupported Go build input: $($entry.source)"
        }
    }
    return $value
}

function New-LocalProductBuildRoot([string]$RepoRoot, [string]$OutputRoot) {
    $allowed = Join-Path $RepoRoot '.tmp\yimecore-local-product'
    $rootPath = [IO.Path]::GetFullPath($OutputRoot)
    if (-not $rootPath.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Output must be a new child of $allowed"
    }
    Assert-LocalProductPlainPath $rootPath
    if (Test-Path -LiteralPath $rootPath) { throw "Build output already exists; preserve it: $rootPath" }
    New-Item -ItemType Directory -Path $rootPath | Out-Null
    return $rootPath
}

function Get-LocalProductFileRecord([string]$Root, [string]$Relative) {
    $path = Resolve-LocalProductChild $Root $Relative
    $item = Get-Item -LiteralPath $path
    if ($item.PSIsContainer) { throw "Expected file: $path" }
    [ordered]@{ path = $Relative.Replace('\', '/'); bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Get-LocalProductPayloadRecords([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -ne (Join-Path $Root 'package-manifest.json') } |
        ForEach-Object { Get-LocalProductFileRecord $Root $_.FullName.Substring($Root.Length + 1) } | Sort-Object path)
}

function Assert-LocalProductSourceUnchanged([string]$Root, $Records) {
    foreach ($entry in $Records) {
        $actual = Get-LocalProductFileRecord $Root $entry.path
        if ($actual.bytes -ne $entry.bytes -or $actual.sha256 -ne $entry.sha256) {
            throw "Source changed during build: $($entry.path). Preserve this run; rebuild from a new output."
        }
    }
}

function Get-LocalProductSourcePaths([string]$RepoRoot, $Product) {
    $paths = @(& git -C $RepoRoot -c core.quotepath=false ls-files --cached --others --exclude-standard -- `
        go-backend YimeTextServiceExperiment json tools/yimecore internal_data/manual_key_layout.json AGENTS.md)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate source' }
    $paths += @($Product.assets | ForEach-Object { $_.source })
    if ($Product.PSObject.Properties['maintenance_assets']) { $paths += @($Product.maintenance_assets | ForEach-Object { $_.source }) }
    $paths += @('json/single_include/nlohmann/json.hpp', 'tools/assert-data-source-boundary.ps1',
        'Install-YimeCore-Local-Dev.cmd', 'Test-YimeCore-Standard-Launch.cmd')
    @($paths | Sort-Object -Unique | Where-Object {
        Test-Path -LiteralPath (Resolve-LocalProductChild $RepoRoot $_) -PathType Leaf
    })
}

function Assert-LocalProductSourceSet($Expected, $Actual) {
    if ((ConvertTo-Json -InputObject @($Expected) -Compress) -cne (ConvertTo-Json -InputObject @($Actual) -Compress)) {
        throw 'Source files were added or removed during build; preserve this run and rebuild.'
    }
}

function Get-LocalProductProtectionEvidence {
    # Out-of-process system view, never the calling app's virtualized HKCU view.
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $result = [ordered]@{ user_sid = $sid; registry = [ordered]@{} }
    foreach ($clsid in @('{35F67E9D-A54D-4177-9697-8B0AB71A9E04}',
            '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}',
            '{E40FA752-BB96-461D-A51D-F40EB437EC65}')) {
        foreach ($path in @("SOFTWARE\Classes\CLSID\$clsid", "SOFTWARE\Classes\WOW6432Node\CLSID\$clsid",
                "SOFTWARE\Microsoft\CTF\TIP\$clsid", "SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$clsid")) {
            $result.registry[$path] = Read-YimeCoreSystemKey ([uint32]2147483650) $path
        }
        $userPath = "$sid\Software\Microsoft\CTF\TIP\$clsid"
        $result.registry[$userPath] = Read-YimeCoreSystemKey ([uint32]2147483651) $userPath
    }
    foreach ($path in @('Control Panel\International\User Profile', 'Keyboard Layout\Preload',
            'Software\Microsoft\Windows\CurrentVersion\Run',
            'Software\Microsoft\Windows\CurrentVersion\Uninstall\YimeCoreExperimentalTrial')) {
        $result.registry[$path] = Read-YimeCoreSystemKey ([uint32]2147483651) "$sid\$path"
    }
    return $result
}
