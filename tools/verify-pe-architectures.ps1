param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$X86TextService,
    [string]$X64TextService,
    [string]$X86Launcher,
    [string]$Arm64TextService,
    [string]$X86RegistrationStatus,
    [string]$X64RegistrationStatus,
    [string]$Arm64RegistrationStatus,
    [string]$RimeDll,
    [string]$RimeDeployer,
    [string]$RimeDictManager,
    [string]$GoBackendRoot,
    [switch]$SkipPackagedRime
)

$ErrorActionPreference = 'Stop'

if (-not $X86TextService) {
    $X86TextService = Join-Path $RepoRoot 'build\PIMETextService\Release\PIMETextService.dll'
}
if (-not $X64TextService) {
    $X64TextService = Join-Path $RepoRoot 'build64\PIMETextService\Release\PIMETextService.dll'
}
if (-not $X86Launcher) {
    $X86Launcher = Join-Path $RepoRoot 'build\PIMELauncher\PIMELauncher.exe'
}
if (-not $X86RegistrationStatus) {
    $X86RegistrationStatus = Join-Path $RepoRoot 'build\PIMETextService\Release\PIMERegistrationStatus.exe'
}
if (-not $X64RegistrationStatus) {
    $X64RegistrationStatus = Join-Path $RepoRoot 'build64\PIMETextService\Release\PIMERegistrationStatus.exe'
}
if ([bool]$Arm64TextService -xor [bool]$Arm64RegistrationStatus) {
    throw 'ARM64 PE verification requires both -Arm64TextService and -Arm64RegistrationStatus explicitly.'
}
if (-not $SkipPackagedRime -and -not $RimeDll) {
    $RimeDll = Join-Path $RepoRoot 'go-backend\build\go-backend\input_methods\yime\rime.dll'
}
if (-not $SkipPackagedRime -and -not $RimeDeployer) {
    $RimeDeployer = Join-Path $RepoRoot 'go-backend\build\go-backend\input_methods\yime\rime_deployer.exe'
}
if (-not $SkipPackagedRime -and -not $RimeDictManager) {
    $RimeDictManager = Join-Path $RepoRoot 'go-backend\build\go-backend\input_methods\yime\rime_dict_manager.exe'
}
if (-not $SkipPackagedRime -and -not $GoBackendRoot) {
    $GoBackendRoot = Join-Path $RepoRoot 'go-backend\build\go-backend'
}

function Get-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "PE file not found: $Path"
    }

    $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file (missing MZ header): $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a PE file (missing PE header): $Path"
        }
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Convert-PeRvaToFileOffset {
    param(
        [Parameter(Mandatory)][uint32]$Rva,
        [Parameter(Mandatory)][object[]]$Sections,
        [Parameter(Mandatory)][uint32]$SizeOfHeaders,
        [Parameter(Mandatory)][long]$FileLength,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Rva -lt $SizeOfHeaders -and [long]$Rva -lt $FileLength) {
        return [long]$Rva
    }

    foreach ($section in $Sections) {
        $mappedSize = [uint64]$section.VirtualSize
        if ([uint64]$section.SizeOfRawData -gt $mappedSize) {
            $mappedSize = [uint64]$section.SizeOfRawData
        }
        $sectionStart = [uint64]$section.VirtualAddress
        $sectionEnd = $sectionStart + $mappedSize
        if ([uint64]$Rva -lt $sectionStart -or [uint64]$Rva -ge $sectionEnd) {
            continue
        }

        $delta = [uint64]$Rva - $sectionStart
        if ($delta -ge [uint64]$section.SizeOfRawData) {
            throw "PE RVA 0x$('{0:X8}' -f $Rva) has no raw-file mapping: $Path"
        }
        $offset = [uint64]$section.PointerToRawData + $delta
        if ($offset -ge [uint64]$FileLength) {
            throw "PE RVA 0x$('{0:X8}' -f $Rva) maps outside the file: $Path"
        }
        return [long]$offset
    }

    throw "PE RVA 0x$('{0:X8}' -f $Rva) is not covered by any section: $Path"
}

function Read-PeAsciiString {
    param(
        [Parameter(Mandatory)][IO.BinaryReader]$Reader,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][long]$FileLength,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Offset -lt 0 -or $Offset -ge $FileLength) {
        throw "PE string offset is outside the file: $Path"
    }

    $Reader.BaseStream.Position = $Offset
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($Reader.BaseStream.Position -lt $FileLength -and $bytes.Count -lt 4096) {
        $value = $Reader.ReadByte()
        if ($value -eq 0) {
            return [Text.Encoding]::ASCII.GetString($bytes.ToArray())
        }
        $bytes.Add($value)
    }

    throw "PE import name is not a bounded null-terminated ASCII string: $Path"
}

function Read-PeNormalImportNames {
    param(
        [Parameter(Mandatory)][IO.BinaryReader]$Reader,
        [Parameter(Mandatory)][uint32]$DirectoryRva,
        [Parameter(Mandatory)][uint32]$DirectorySize,
        [Parameter(Mandatory)][object[]]$Sections,
        [Parameter(Mandatory)][uint32]$SizeOfHeaders,
        [Parameter(Mandatory)][long]$FileLength,
        [Parameter(Mandatory)][string]$Path
    )

    if ($DirectoryRva -eq 0) {
        if ($DirectorySize -ne 0) {
            throw "PE import directory has size without an RVA: $Path"
        }
        return
    }
    if ($DirectorySize -lt 20) {
        throw "PE import directory is too small for a descriptor: $Path"
    }

    $maxDescriptors = [math]::Floor($DirectorySize / 20)
    if ($maxDescriptors -gt 65536) {
        throw "PE import directory declares an unreasonable descriptor count: $Path"
    }
    $imports = [System.Collections.Generic.List[string]]::new()
    $terminatorFound = $false
    for ($descriptorIndex = 0; $descriptorIndex -lt $maxDescriptors; $descriptorIndex++) {
        $descriptorRva64 = [uint64]$DirectoryRva + ([uint64]$descriptorIndex * 20)
        if ($descriptorRva64 -gt [uint32]::MaxValue) {
            throw "PE import descriptor RVA overflows 32 bits: $Path"
        }
        $descriptorOffset = Convert-PeRvaToFileOffset -Rva ([uint32]$descriptorRva64) -Sections $Sections -SizeOfHeaders $SizeOfHeaders -FileLength $FileLength -Path $Path
        if ($descriptorOffset + 20 -gt $FileLength) {
            throw "PE import descriptor extends outside the file: $Path"
        }
        $Reader.BaseStream.Position = $descriptorOffset
        $originalFirstThunk = $Reader.ReadUInt32()
        $timeDateStamp = $Reader.ReadUInt32()
        $forwarderChain = $Reader.ReadUInt32()
        $nameRva = $Reader.ReadUInt32()
        $firstThunk = $Reader.ReadUInt32()
        if ($originalFirstThunk -eq 0 -and $timeDateStamp -eq 0 -and
            $forwarderChain -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) {
            $terminatorFound = $true
            break
        }
        if ($nameRva -eq 0) {
            throw "PE import descriptor has no DLL name RVA: $Path"
        }
        $nameOffset = Convert-PeRvaToFileOffset -Rva $nameRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -FileLength $FileLength -Path $Path
        $name = Read-PeAsciiString -Reader $Reader -Offset $nameOffset -FileLength $FileLength -Path $Path
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "PE import descriptor has an empty DLL name: $Path"
        }
        $imports.Add($name)
    }
    if (-not $terminatorFound) {
        throw "PE import directory has no terminating descriptor within its declared size: $Path"
    }

    $imports
}

function Read-PeDelayImportNames {
    param(
        [Parameter(Mandatory)][IO.BinaryReader]$Reader,
        [Parameter(Mandatory)][uint32]$DirectoryRva,
        [Parameter(Mandatory)][uint32]$DirectorySize,
        [Parameter(Mandatory)][object[]]$Sections,
        [Parameter(Mandatory)][uint32]$SizeOfHeaders,
        [Parameter(Mandatory)][long]$FileLength,
        [Parameter(Mandatory)][string]$Path
    )

    if ($DirectoryRva -eq 0) {
        if ($DirectorySize -ne 0) {
            throw "PE delay-import directory has size without an RVA: $Path"
        }
        return
    }
    if ($DirectorySize -lt 32) {
        throw "PE delay-import directory is too small for a descriptor: $Path"
    }

    $maxDescriptors = [math]::Floor($DirectorySize / 32)
    if ($maxDescriptors -gt 65536) {
        throw "PE delay-import directory declares an unreasonable descriptor count: $Path"
    }
    $imports = [System.Collections.Generic.List[string]]::new()
    $terminatorFound = $false
    for ($descriptorIndex = 0; $descriptorIndex -lt $maxDescriptors; $descriptorIndex++) {
        $descriptorRva64 = [uint64]$DirectoryRva + ([uint64]$descriptorIndex * 32)
        if ($descriptorRva64 -gt [uint32]::MaxValue) {
            throw "PE delay-import descriptor RVA overflows 32 bits: $Path"
        }
        $descriptorOffset = Convert-PeRvaToFileOffset -Rva ([uint32]$descriptorRva64) -Sections $Sections -SizeOfHeaders $SizeOfHeaders -FileLength $FileLength -Path $Path
        if ($descriptorOffset + 32 -gt $FileLength) {
            throw "PE delay-import descriptor extends outside the file: $Path"
        }
        $Reader.BaseStream.Position = $descriptorOffset
        $attributes = $Reader.ReadUInt32()
        $nameRva = $Reader.ReadUInt32()
        $moduleHandleRva = $Reader.ReadUInt32()
        $iatRva = $Reader.ReadUInt32()
        $intRva = $Reader.ReadUInt32()
        $boundIatRva = $Reader.ReadUInt32()
        $unloadIatRva = $Reader.ReadUInt32()
        $timeDateStamp = $Reader.ReadUInt32()
        if ($attributes -eq 0 -and $nameRva -eq 0 -and $moduleHandleRva -eq 0 -and
            $iatRva -eq 0 -and $intRva -eq 0 -and $boundIatRva -eq 0 -and
            $unloadIatRva -eq 0 -and $timeDateStamp -eq 0) {
            $terminatorFound = $true
            break
        }
        if ($attributes -ne 1) {
            throw "PE delay-import descriptor does not use the supported RVA form: $Path"
        }
        if ($nameRva -eq 0) {
            throw "PE delay-import descriptor has no DLL name RVA: $Path"
        }
        $nameOffset = Convert-PeRvaToFileOffset -Rva $nameRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -FileLength $FileLength -Path $Path
        $name = Read-PeAsciiString -Reader $Reader -Offset $nameOffset -FileLength $FileLength -Path $Path
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "PE delay-import descriptor has an empty DLL name: $Path"
        }
        $imports.Add($name)
    }
    if (-not $terminatorFound) {
        throw "PE delay-import directory has no terminating descriptor within its declared size: $Path"
    }

    $imports
}

function Get-PeImportedDlls {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "PE file not found: $Path"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $stream = [IO.File]::OpenRead($resolvedPath)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        $fileLength = $stream.Length
        if ($fileLength -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file (missing MZ header): $Path"
        }

        $stream.Position = 0x3C
        $peOffset = [uint32]$reader.ReadUInt32()
        if ([uint64]$peOffset + 24 -gt [uint64]$fileLength) {
            throw "Invalid PE header offset: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a PE file (missing PE header): $Path"
        }

        [void]$reader.ReadUInt16()
        $numberOfSections = [uint16]$reader.ReadUInt16()
        $stream.Position = [long]$peOffset + 20
        $sizeOfOptionalHeader = [uint16]$reader.ReadUInt16()
        $optionalHeaderOffset = [long]$peOffset + 24
        if ([uint64]$optionalHeaderOffset + [uint64]$sizeOfOptionalHeader -gt [uint64]$fileLength) {
            throw "PE optional header extends outside the file: $Path"
        }

        $stream.Position = $optionalHeaderOffset
        $optionalMagic = $reader.ReadUInt16()
        switch ($optionalMagic) {
            0x010B {
                $numberOfRvaAndSizesOffset = $optionalHeaderOffset + 92
                $dataDirectoryOffset = $optionalHeaderOffset + 96
            }
            0x020B {
                $numberOfRvaAndSizesOffset = $optionalHeaderOffset + 108
                $dataDirectoryOffset = $optionalHeaderOffset + 112
            }
            default {
                throw "Unsupported PE optional-header magic 0x$('{0:X4}' -f $optionalMagic): $Path"
            }
        }
        $optionalHeaderEnd = [uint64]$optionalHeaderOffset + [uint64]$sizeOfOptionalHeader
        if ([uint64]($optionalHeaderOffset + 64) -gt $optionalHeaderEnd -or
            [uint64]($numberOfRvaAndSizesOffset + 4) -gt $optionalHeaderEnd) {
            throw "PE optional header is too small for its fixed fields: $Path"
        }
        $stream.Position = $optionalHeaderOffset + 60
        $sizeOfHeaders = [uint32]$reader.ReadUInt32()
        $stream.Position = $numberOfRvaAndSizesOffset
        $numberOfRvaAndSizes = [uint32]$reader.ReadUInt32()
        if ($numberOfRvaAndSizes -gt 16) {
            throw "PE optional header declares more than 16 data directories: $Path"
        }
        $dataDirectoriesEnd = [uint64]$dataDirectoryOffset + ([uint64]$numberOfRvaAndSizes * 8)
        if ($dataDirectoriesEnd -gt $optionalHeaderEnd) {
            throw "PE data-directory table extends outside the optional header: $Path"
        }
        if ($numberOfRvaAndSizes -lt 2) {
            return
        }

        $stream.Position = $dataDirectoryOffset + 8
        $importRva = [uint32]$reader.ReadUInt32()
        $importSize = [uint32]$reader.ReadUInt32()
        $delayImportRva = [uint32]0
        $delayImportSize = [uint32]0
        if ($numberOfRvaAndSizes -ge 14) {
            $stream.Position = $dataDirectoryOffset + (13 * 8)
            $delayImportRva = [uint32]$reader.ReadUInt32()
            $delayImportSize = [uint32]$reader.ReadUInt32()
        }
        if ($importRva -eq 0 -and $importSize -eq 0 -and
            $delayImportRva -eq 0 -and $delayImportSize -eq 0) {
            return
        }

        $sectionTableOffset = $optionalHeaderOffset + $sizeOfOptionalHeader
        if ([uint64]$sectionTableOffset + ([uint64]$numberOfSections * 40) -gt [uint64]$fileLength) {
            throw "PE section table extends outside the file: $Path"
        }
        $sections = @()
        for ($sectionIndex = 0; $sectionIndex -lt $numberOfSections; $sectionIndex++) {
            $stream.Position = $sectionTableOffset + ($sectionIndex * 40) + 8
            $sections += [pscustomobject]@{
                VirtualSize = [uint32]$reader.ReadUInt32()
                VirtualAddress = [uint32]$reader.ReadUInt32()
                SizeOfRawData = [uint32]$reader.ReadUInt32()
                PointerToRawData = [uint32]$reader.ReadUInt32()
            }
        }

        $imports = @(
            Read-PeNormalImportNames -Reader $reader -DirectoryRva $importRva -DirectorySize $importSize -Sections $sections -SizeOfHeaders $sizeOfHeaders -FileLength $fileLength -Path $Path
            Read-PeDelayImportNames -Reader $reader -DirectoryRva $delayImportRva -DirectorySize $delayImportSize -Sections $sections -SizeOfHeaders $sizeOfHeaders -FileLength $fileLength -Path $Path
        )
        $imports | Sort-Object -Unique
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$targets = @(
    @{ Path = $X86TextService; Expected = [uint16]0x014C; Label = 'Win32 PIMETextService.dll'; VerifyStaticCrt = $true }
    @{ Path = $X64TextService; Expected = [uint16]0x8664; Label = 'x64 PIMETextService.dll'; VerifyStaticCrt = $true }
    @{ Path = $X86Launcher; Expected = [uint16]0x014C; Label = 'Win32 PIMELauncher.exe'; VerifyStaticCrt = $true }
    @{ Path = $X86RegistrationStatus; Expected = [uint16]0x014C; Label = 'Win32 PIMERegistrationStatus.exe'; VerifyStaticCrt = $true }
    @{ Path = $X64RegistrationStatus; Expected = [uint16]0x8664; Label = 'x64 PIMERegistrationStatus.exe'; VerifyStaticCrt = $true }
)
if (-not $SkipPackagedRime) {
    $targets += @{ Path = $RimeDll; Expected = [uint16]0x8664; Label = 'x64 packaged rime.dll'; VerifyStaticCrt = $true }
    $targets += @{ Path = $RimeDeployer; Expected = [uint16]0x8664; Label = 'x64 packaged rime_deployer.exe'; VerifyStaticCrt = $true }
    $targets += @{ Path = $RimeDictManager; Expected = [uint16]0x8664; Label = 'x64 packaged rime_dict_manager.exe'; VerifyStaticCrt = $true }
    foreach ($name in @(
        'server.exe','tool-hub.exe','yime-trainer.exe','input-toolbar.exe',
        'settings-tool.exe','diagnostics-tool.exe','yime-layout-designer.exe',
        'lexicon-manager.exe','reverse-lookup.exe','system-lexicon-audit.exe',
        'lexicon-promotion-scan.exe','blocklist-manager.exe')) {
        $targets += @{
            Path = Join-Path $GoBackendRoot $name
            Expected = [uint16]0x8664
            Label = "x64 packaged Go $name"
            VerifyStaticCrt = $true
        }
    }
}
if ($Arm64TextService) {
    $targets += @{ Path = $Arm64TextService; Expected = [uint16]0xAA64; Label = 'ARM64 PIMETextService.dll'; VerifyStaticCrt = $true }
    $targets += @{ Path = $Arm64RegistrationStatus; Expected = [uint16]0xAA64; Label = 'ARM64 PIMERegistrationStatus.exe'; VerifyStaticCrt = $true }
}

$failures = foreach ($target in $targets) {
    $machine = Get-PeMachine -Path $target.Path
    $actual = '0x{0:X4}' -f $machine
    $expected = '0x{0:X4}' -f $target.Expected
    Write-Host "$($target.Label): $actual ($($target.Path))"
    if ($machine -ne $target.Expected) {
        "$($target.Label) expected $expected but found ${actual}: $($target.Path)"
    }
    if ($target.VerifyStaticCrt) {
        $imports = @(Get-PeImportedDlls -Path $target.Path)
        Write-Host "$($target.Label) imports: $($imports -join ', ')"
        $dynamicCrtImports = @($imports | Where-Object {
            $_ -match '^(?:vcruntime.*|msvcr.*|msvcp.*|concrt.*|ucrtbase.*|api-ms-win-crt.*)\.dll$'
        })
        if ($dynamicCrtImports) {
            "$($target.Label) imports forbidden dynamic CRT dependencies: $($dynamicCrtImports -join ', ')"
        }
    }
}

if ($failures) {
    throw "PE architecture verification failed:`n$($failures -join "`n")"
}

Write-Host 'PE architecture verification passed.'
