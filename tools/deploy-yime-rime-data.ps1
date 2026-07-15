param(
    [Parameter(Mandatory = $true)]
    [string]$Input,
    [string]$PimeRoot = "",
    [string]$RimeUserDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $PimeRoot) {
    $PimeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}
if (-not $RimeUserDir) {
    $RimeUserDir = Join-Path $env:APPDATA "PIME\Rime"
}

$sharedDir = Join-Path $PimeRoot "go-backend\input_methods\yime\data"
$importer = Join-Path $PSScriptRoot "import-yime-full-lexicon.ps1"

# The fixed-length dictionary is the only imported source. The importer derives
# variable and shorthand dictionaries and writes the generation manifest.
& $importer -Input $Input -OutputDir $sharedDir
if ($LASTEXITCODE -ne 0) {
    throw "Yime lexicon import failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Path $RimeUserDir -Force | Out-Null
foreach ($mode in @("full", "variable", "shorthand")) {
    foreach ($suffix in @("dict.yaml", "schema.yaml")) {
        $name = "yime_${mode}.${suffix}"
        Copy-Item -LiteralPath (Join-Path $sharedDir $name) -Destination (Join-Path $RimeUserDir $name) -Force
    }
}
Copy-Item -LiteralPath (Join-Path $sharedDir "yime_lexicon_manifest.json") -Destination (Join-Path $RimeUserDir "yime_lexicon_manifest.json") -Force

Write-Host "Yime single-source data generated and deployed."
Write-Host "  imported source: $((Resolve-Path -LiteralPath $Input).Path)"
Write-Host "  generated data:  $sharedDir"
Write-Host "  PIME user dir:   $RimeUserDir"
Write-Host "Redeploy Rime or restart the installed YIME runtime before verification."
