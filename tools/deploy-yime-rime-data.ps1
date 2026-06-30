param(
    [string]$YimeRoot = "C:\dev\Yime-variable-length",
    [ValidateSet("full", "variable", "shorthand")]
    [string]$Mode = "variable",
    [ValidateSet("layout-key", "runtime-symbol")]
    [string]$CodeForm = "layout-key",
    [string]$PimeRoot = "",
    [string]$WeaselDataDir = "C:\dev\weasel\output\data",
    [string]$RimeUserDir = "",
    [string]$OutputDir = "",
    [switch]$SkipExport,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Backup-IfNeeded {
    param([string]$Path)

    if ($NoBackup -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $Path -Destination "$Path.yime-bak-$timestamp" -Force
}

if (-not $PimeRoot) {
    $PimeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}
else {
    $PimeRoot = Resolve-RequiredPath -Path $PimeRoot -Label "PIME root"
}

$YimeRoot = Resolve-RequiredPath -Path $YimeRoot -Label "Yime root"
$WeaselDataDir = Resolve-RequiredPath -Path $WeaselDataDir -Label "Rime shared data"

if (-not $OutputDir) {
    $OutputDir = Join-Path $YimeRoot ".generated\rime"
}
if (-not $RimeUserDir) {
    $RimeUserDir = Join-Path $env:APPDATA "PIME\Rime"
}

$schemaId = "yime_$Mode"
$exporter = Resolve-RequiredPath -Path (Join-Path $YimeRoot "yime\export_rime_yime.py") -Label "Yime Rime exporter"
$pimeSharedDir = Join-Path $PimeRoot "go-backend\input_methods\rime\data"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $RimeUserDir -Force | Out-Null
New-Item -ItemType Directory -Path $pimeSharedDir -Force | Out-Null

if (-not $SkipExport) {
    Push-Location $YimeRoot
    try {
        & python $exporter --mode $Mode --code-form $CodeForm --output-dir $OutputDir
        if ($LASTEXITCODE -ne 0) {
            throw "Yime Rime export failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$schemaFile = Resolve-RequiredPath -Path (Join-Path $OutputDir "$schemaId.schema.yaml") -Label "Generated Yime schema"
$dictFile = Resolve-RequiredPath -Path (Join-Path $OutputDir "$schemaId.dict.yaml") -Label "Generated Yime dict"

Copy-Item -Path (Join-Path $WeaselDataDir "*") -Destination $pimeSharedDir -Recurse -Force
Copy-Item -LiteralPath $schemaFile -Destination (Join-Path $pimeSharedDir "$schemaId.schema.yaml") -Force
Copy-Item -LiteralPath $dictFile -Destination (Join-Path $pimeSharedDir "$schemaId.dict.yaml") -Force

Copy-Item -LiteralPath $schemaFile -Destination (Join-Path $RimeUserDir "$schemaId.schema.yaml") -Force
Copy-Item -LiteralPath $dictFile -Destination (Join-Path $RimeUserDir "$schemaId.dict.yaml") -Force

$defaultCustom = Join-Path $RimeUserDir "default.custom.yaml"
$userYaml = Join-Path $RimeUserDir "user.yaml"
Backup-IfNeeded -Path $defaultCustom
Backup-IfNeeded -Path $userYaml

Write-Utf8NoBom -Path $defaultCustom -Text @"
patch:
  schema_list:
    - schema: $schemaId
"@

Write-Utf8NoBom -Path $userYaml -Text @"
var:
  previously_selected_schema: $schemaId
"@

Write-Host "Yime Rime data deployed for PIME."
Write-Host "  schema:        $schemaId"
Write-Host "  PIME shared:   $pimeSharedDir"
Write-Host "  PIME user dir: $RimeUserDir"
Write-Host "  source shared: $WeaselDataDir"
