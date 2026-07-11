param(
    [Parameter(Mandatory = $true)]
    [string]$Input,
    [string]$OutputDir = "",
    [switch]$DeployToUserDir
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$goBackend = Join-Path $root "go-backend"
$inputPath = (Resolve-Path -LiteralPath $Input).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $goBackend "input_methods\yime\data"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDir).Path

Push-Location $goBackend
try {
    go run ./cmd/yime-lexicon-derive -input $inputPath -output-dir $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Yime lexicon derivation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host "Generated full, variable, and shorthand dictionaries from $inputPath"
Write-Host "Generation manifest: $(Join-Path $outputPath 'yime_lexicon_manifest.json')"

if ($DeployToUserDir) {
    $userDir = Join-Path $env:APPDATA "PIME\Rime"
    New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    foreach ($name in @("yime_full.dict.yaml", "yime_variable.dict.yaml", "yime_shorthand.dict.yaml", "yime_lexicon_manifest.json")) {
        Copy-Item -LiteralPath (Join-Path $outputPath $name) -Destination (Join-Path $userDir $name) -Force
    }
    Write-Host "Generated dictionaries copied to $userDir"
    Write-Host "Run the existing Yime '重新部署 Rime' command to activate them."
}
