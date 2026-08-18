[CmdletBinding()]
param(
    [string]$RimeUserDir = $(if ($env:APPDATA) { Join-Path $env:APPDATA 'PIME\Rime' }),
    [string[]]$SchemaIDs = @('yime_full', 'yime_variable', 'yime_shorthand')
)

$ErrorActionPreference = 'Stop'

function Get-YamlSectionScalar {
    param([string]$Path, [string]$Section, [string]$Name)

    $reader = [IO.StreamReader]::new($Path, [Text.Encoding]::UTF8, $true)
    try {
        $inSection = $false
        $sectionIndent = -1
        while (($line = $reader.ReadLine()) -ne $null) {
            $trimmed = $line.Trim()
            if (-not $inSection) {
                if ($trimmed -eq ($Section + ':')) {
                    $inSection = $true
                    $sectionIndent = $line.Length - $line.TrimStart().Length
                }
                continue
            }
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le $sectionIndent) { break }
            if ($trimmed.StartsWith($Name + ':', [StringComparison]::Ordinal)) {
                return $trimmed.Substring($Name.Length + 1).Trim().Trim('"', "'")
            }
        }
    } finally {
        $reader.Dispose()
    }
    return $null
}

function Get-RimeDictionaryImports {
    param([string]$Path)

    $reader = [IO.StreamReader]::new($Path, [Text.Encoding]::UTF8, $true)
    try {
        $result = [Collections.Generic.List[string]]::new()
        $inImports = $false
        $importsIndent = -1
        while (($line = $reader.ReadLine()) -ne $null) {
            $trimmed = $line.Trim()
            if (-not $inImports) {
                if ($trimmed -eq '...') { break }
                if ($trimmed -eq 'import_tables:') {
                    $inImports = $true
                    $importsIndent = $line.Length - $line.TrimStart().Length
                }
                continue
            }
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le $importsIndent -or -not $trimmed.StartsWith('-')) { break }
            $value = $trimmed.Substring(1).Trim()
            $comment = $value.IndexOf(' #', [StringComparison]::Ordinal)
            if ($comment -ge 0) { $value = $value.Substring(0, $comment).Trim() }
            $value = $value.Trim('"', "'")
            if ($value) { $result.Add($value) }
        }
        return @($result)
    } finally {
        $reader.Dispose()
    }
}

function Assert-SafeDictionaryID {
    param([string]$DictionaryID)

    if (-not $DictionaryID -or $DictionaryID -in @('.', '..') -or
        [IO.Path]::GetFileName($DictionaryID) -ne $DictionaryID) {
        throw "Rime imported dictionary ID is unsafe: '$DictionaryID'"
    }
}

function Get-RimeDictionaryClosure {
    param([string]$RootDirectory, [string]$RootDictionaryID)

    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($RootDictionaryID)
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $paths = [Collections.Generic.List[string]]::new()
    while ($queue.Count -gt 0) {
        $dictionaryID = $queue.Dequeue()
        Assert-SafeDictionaryID $dictionaryID
        if (-not $visited.Add($dictionaryID)) { continue }
        $path = Join-Path $RootDirectory ($dictionaryID + '.dict.yaml')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Rime imported dictionary is missing: $path"
        }
        $paths.Add($path)
        foreach ($import in @(Get-RimeDictionaryImports $path)) { $queue.Enqueue($import) }
    }
    return @($paths)
}

$records = [Collections.Generic.List[object]]::new()
foreach ($schemaID in $SchemaIDs) {
    $record = [ordered]@{
        name = "user-rime/$schemaID/import-cache"
        schemaID = $schemaID
        dictionaryID = $null
        compiledSchema = $null
        compiledTable = $null
        compiledReverse = $null
        compiledPrism = $null
        newestSource = $null
        newestSourceUtc = $null
        compiledUtc = $null
        compiledReverseUtc = $null
        compiledPrismUtc = $null
        compiledSchemaUtc = $null
        sourceCount = 0
        staleSources = @()
        staleArtifacts = @()
        status = 'unknown'
        detail = $null
    }
    try {
        if (-not $RimeUserDir -or -not (Test-Path -LiteralPath $RimeUserDir -PathType Container)) {
            $record.status = 'not-deployed'
            $record.detail = "Rime user directory is missing: $RimeUserDir"
            $records.Add([pscustomobject]$record)
            continue
        }
        $schemaPath = Join-Path $RimeUserDir ($schemaID + '.schema.yaml')
        if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
            $record.status = 'not-deployed'
            $record.detail = "Source schema is missing: $schemaPath"
            $records.Add([pscustomobject]$record)
            continue
        }
        $dictionaryID = Get-YamlSectionScalar $schemaPath 'translator' 'dictionary'
        if (-not $dictionaryID) { throw "Schema does not declare translator dictionary: $schemaPath" }
        Assert-SafeDictionaryID $dictionaryID
        $record.dictionaryID = $dictionaryID
        $compiledSchema = Join-Path $RimeUserDir ('build\' + $schemaID + '.schema.yaml')
        $compiledTable = Join-Path $RimeUserDir ('build\' + $dictionaryID + '.table.bin')
        $compiledReverse = Join-Path $RimeUserDir ('build\' + $dictionaryID + '.reverse.bin')
        $compiledPrism = Join-Path $RimeUserDir ('build\' + $dictionaryID + '.prism.bin')
        $record.compiledSchema = $compiledSchema
        $record.compiledTable = $compiledTable
        $record.compiledReverse = $compiledReverse
        $record.compiledPrism = $compiledPrism
        $requiredCompiled = @($compiledSchema, $compiledTable, $compiledReverse, $compiledPrism)
        $missingCompiled = @($requiredCompiled | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($missingCompiled.Count -gt 0) {
            $record.status = 'compiled-missing'
            $record.detail = "Compiled schema/dictionary artifact is missing: $($missingCompiled -join ' ; ')"
            $records.Add([pscustomobject]$record)
            continue
        }
        $compiledSchemaInfo = Get-Item -LiteralPath $compiledSchema
        $compiledInfo = Get-Item -LiteralPath $compiledTable
        $compiledReverseInfo = Get-Item -LiteralPath $compiledReverse
        $compiledPrismInfo = Get-Item -LiteralPath $compiledPrism
        $record.compiledSchemaUtc = $compiledSchemaInfo.LastWriteTimeUtc.ToString('o')
        $record.compiledUtc = $compiledInfo.LastWriteTimeUtc.ToString('o')
        $record.compiledReverseUtc = $compiledReverseInfo.LastWriteTimeUtc.ToString('o')
        $record.compiledPrismUtc = $compiledPrismInfo.LastWriteTimeUtc.ToString('o')
        $sourcePaths = @(Get-RimeDictionaryClosure $RimeUserDir $dictionaryID)
        $sourceInfos = @($sourcePaths | ForEach-Object { Get-Item -LiteralPath $_ })
        $record.sourceCount = $sourceInfos.Count
        $newest = $sourceInfos | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $record.newestSource = $newest.FullName
        $record.newestSourceUtc = $newest.LastWriteTimeUtc.ToString('o')
        $compiledDictionaryArtifacts = @($compiledInfo, $compiledReverseInfo, $compiledPrismInfo)
        $stale = @($sourceInfos | Where-Object {
            $sourceInfo = $_
            $compiledDictionaryArtifacts | Where-Object { $sourceInfo.LastWriteTimeUtc -gt $_.LastWriteTimeUtc } | Select-Object -First 1
        })
        $staleArtifacts = @($compiledDictionaryArtifacts | Where-Object {
            $artifactInfo = $_
            $sourceInfos | Where-Object { $_.LastWriteTimeUtc -gt $artifactInfo.LastWriteTimeUtc } | Select-Object -First 1
        })
        foreach ($semanticField in @(
            @('schema', 'version'),
            @('speller', 'alphabet')
        )) {
            $sourceValue = Get-YamlSectionScalar $schemaPath $semanticField[0] $semanticField[1]
            $compiledValue = Get-YamlSectionScalar $compiledSchema $semanticField[0] $semanticField[1]
            if ($sourceValue -and $sourceValue -ne $compiledValue) {
                $stale += Get-Item -LiteralPath $schemaPath
                break
            }
        }
        $record.staleSources = @($stale | ForEach-Object FullName)
        $record.staleArtifacts = @($staleArtifacts | ForEach-Object FullName)
        if ($stale.Count -gt 0) {
            $record.status = 'stale'
            $record.detail = "$($stale.Count) source schema/dictionary dependency file(s) are newer than or differ from $($staleArtifacts.Count) compiled artifact(s)."
        } else {
            $record.status = 'match'
        }
    } catch {
        $record.status = 'error'
        $record.detail = $_.Exception.Message
    }
    $records.Add([pscustomobject]$record)
}

@($records)
