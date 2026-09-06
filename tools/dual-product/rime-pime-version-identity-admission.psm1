# Pure-data DP1-P admission contract for a proposed Rime/PIME installer
# identity transition. Importing and calling this module performs no filesystem,
# registry, process, build, installer, uninstaller, or product action.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RimePimeVersionIdentityAdmissionSchema = 'yime-rime-pime-version-identity-admission-v1'
$script:RimePimeVersionPattern = '^(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)(?:-(?<suffix>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'
$script:RimePimeSha256Pattern = '^[0-9a-f]{64}$'

function Test-RimePimeProductVersionValue {
    param($Value)

    if ($Value -isnot [string] -or $Value.Length -gt 64) { return $false }
    $match = [regex]::Match($Value, $script:RimePimeVersionPattern)
    if (-not $match.Success) { return $false }
    foreach ($name in @('major', 'minor', 'patch')) {
        [uint64]$part = 0
        if (-not [uint64]::TryParse($match.Groups[$name].Value, [ref]$part) -or $part -gt 65535) {
            return $false
        }
    }
    if ($match.Groups['suffix'].Success) {
        foreach ($identifier in $match.Groups['suffix'].Value.Split('.')) {
            if ($identifier -match '^[0-9]+$' -and $identifier.Length -gt 1 -and $identifier[0] -eq '0') {
                return $false
            }
        }
    }
    return $true
}

function Test-RimePimePositiveIntegerValue {
    param($Value)

    if ($Value -isnot [byte] -and $Value -isnot [sbyte] -and
        $Value -isnot [int16] -and $Value -isnot [uint16] -and
        $Value -isnot [int32] -and $Value -isnot [uint32] -and
        $Value -isnot [int64] -and $Value -isnot [uint64]) {
        return $false
    }
    return [decimal]$Value -ge 1
}

function Compare-RimePimeProductVersionPrecedence {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    $leftMatch = [regex]::Match($Left, $script:RimePimeVersionPattern)
    $rightMatch = [regex]::Match($Right, $script:RimePimeVersionPattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) {
        throw 'Version precedence comparison requires two validated product versions.'
    }

    foreach ($name in @('major', 'minor', 'patch')) {
        $leftPart = [uint32]::Parse($leftMatch.Groups[$name].Value)
        $rightPart = [uint32]::Parse($rightMatch.Groups[$name].Value)
        if ($leftPart -lt $rightPart) { return -1 }
        if ($leftPart -gt $rightPart) { return 1 }
    }

    $leftHasSuffix = $leftMatch.Groups['suffix'].Success
    $rightHasSuffix = $rightMatch.Groups['suffix'].Success
    if (-not $leftHasSuffix -and -not $rightHasSuffix) { return 0 }
    if (-not $leftHasSuffix) { return 1 }
    if (-not $rightHasSuffix) { return -1 }

    $leftIdentifiers = $leftMatch.Groups['suffix'].Value.Split('.')
    $rightIdentifiers = $rightMatch.Groups['suffix'].Value.Split('.')
    $sharedCount = [Math]::Min($leftIdentifiers.Count, $rightIdentifiers.Count)
    for ($index = 0; $index -lt $sharedCount; $index++) {
        $leftIdentifier = $leftIdentifiers[$index]
        $rightIdentifier = $rightIdentifiers[$index]
        $leftNumeric = $leftIdentifier -cmatch '^[0-9]+$'
        $rightNumeric = $rightIdentifier -cmatch '^[0-9]+$'
        if ($leftNumeric -and $rightNumeric) {
            # Leading zeroes are rejected by validation, so digit count and then
            # ordinal text compare arbitrary-size numeric identifiers safely.
            if ($leftIdentifier.Length -lt $rightIdentifier.Length) { return -1 }
            if ($leftIdentifier.Length -gt $rightIdentifier.Length) { return 1 }
        } elseif ($leftNumeric) {
            return -1
        } elseif ($rightNumeric) {
            return 1
        }
        $ordinal = [string]::CompareOrdinal($leftIdentifier, $rightIdentifier)
        if ($ordinal -lt 0) { return -1 }
        if ($ordinal -gt 0) { return 1 }
    }
    if ($leftIdentifiers.Count -lt $rightIdentifiers.Count) { return -1 }
    if ($leftIdentifiers.Count -gt $rightIdentifiers.Count) { return 1 }
    return 0
}

function Get-RimePimeIdentityProperty {
    param(
        $Identity,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Reasons
    )

    if ($null -eq $Identity -or $null -eq $Identity.PSObject -or
        $null -eq $Identity.PSObject.Properties[$Name]) {
        $Reasons.Add("$Context-missing-$($Name.Replace('_', '-'))")
        return $null
    }
    return $Identity.PSObject.Properties[$Name].Value
}

function Get-RimePimeVersionIdentityAdmission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$OldIdentity,
        [Parameter(Mandatory)]$SuccessorIdentity,
        [Parameter(Mandatory)][string]$ExpectedSuccessorProductVersion
    )

    $reasons = [Collections.Generic.List[string]]::new()
    $oldVersion = Get-RimePimeIdentityProperty $OldIdentity 'product_version' 'old' $reasons
    $oldPath = Get-RimePimeIdentityProperty $OldIdentity 'installer_path' 'old' $reasons
    $oldSha256 = Get-RimePimeIdentityProperty $OldIdentity 'installer_sha256' 'old' $reasons
    $oldBytes = Get-RimePimeIdentityProperty $OldIdentity 'installer_bytes' 'old' $reasons
    $oldStrict = Get-RimePimeIdentityProperty $OldIdentity 'strict_receipt' 'old' $reasons

    $newVersion = Get-RimePimeIdentityProperty $SuccessorIdentity 'product_version' 'successor' $reasons
    $newPath = Get-RimePimeIdentityProperty $SuccessorIdentity 'installer_path' 'successor' $reasons
    $newSha256 = Get-RimePimeIdentityProperty $SuccessorIdentity 'installer_sha256' 'successor' $reasons
    $newBytes = Get-RimePimeIdentityProperty $SuccessorIdentity 'installer_bytes' 'successor' $reasons
    $newStrict = Get-RimePimeIdentityProperty $SuccessorIdentity 'strict_receipt' 'successor' $reasons
    $newDurable = Get-RimePimeIdentityProperty $SuccessorIdentity 'evidence_artifacts_durable' 'successor' $reasons
    $newCurrent = Get-RimePimeIdentityProperty $SuccessorIdentity 'current_build_evidence' 'successor' $reasons

    if (-not (Test-RimePimeProductVersionValue $ExpectedSuccessorProductVersion)) {
        $reasons.Add('expected-successor-invalid-product-version')
    }
    if (-not (Test-RimePimeProductVersionValue $oldVersion)) {
        $reasons.Add('old-invalid-product-version')
    }
    if (-not (Test-RimePimeProductVersionValue $newVersion)) {
        $reasons.Add('successor-invalid-product-version')
    } elseif ($newVersion -cne $ExpectedSuccessorProductVersion) {
        $reasons.Add('successor-product-version-differs-from-expected')
    }

    $expectedOldPath = if (Test-RimePimeProductVersionValue $oldVersion) {
        'installer/YIME-' + $oldVersion + '-setup.exe'
    } else { $null }
    $expectedNewPath = if (Test-RimePimeProductVersionValue $newVersion) {
        'installer/YIME-' + $newVersion + '-setup.exe'
    } else { $null }
    if ($oldPath -isnot [string] -or $null -eq $expectedOldPath -or $oldPath -cne $expectedOldPath) {
        $reasons.Add('old-installer-path-is-not-canonical-versioned-leaf')
    }
    if ($newPath -isnot [string] -or $null -eq $expectedNewPath -or $newPath -cne $expectedNewPath) {
        $reasons.Add('successor-installer-path-is-not-canonical-versioned-leaf')
    }
    if ($oldSha256 -isnot [string] -or $oldSha256 -cnotmatch $script:RimePimeSha256Pattern) {
        $reasons.Add('old-invalid-installer-sha256')
    }
    if ($newSha256 -isnot [string] -or $newSha256 -cnotmatch $script:RimePimeSha256Pattern) {
        $reasons.Add('successor-invalid-installer-sha256')
    }
    if (-not (Test-RimePimePositiveIntegerValue $oldBytes)) {
        $reasons.Add('old-invalid-installer-bytes')
    }
    if (-not (Test-RimePimePositiveIntegerValue $newBytes)) {
        $reasons.Add('successor-invalid-installer-bytes')
    }
    if ($oldStrict -isnot [bool] -or -not $oldStrict) {
        $reasons.Add('old-strict-receipt-not-proven')
    }
    if ($newStrict -isnot [bool] -or -not $newStrict) {
        $reasons.Add('successor-strict-receipt-not-proven')
    }
    if ($newDurable -isnot [bool] -or -not $newDurable) {
        $reasons.Add('successor-durable-evidence-not-proven')
    }
    if ($newCurrent -isnot [bool] -or -not $newCurrent) {
        $reasons.Add('successor-current-build-evidence-not-proven')
    }

    $oldVersionValid = Test-RimePimeProductVersionValue $oldVersion
    $newVersionValid = Test-RimePimeProductVersionValue $newVersion
    if ($oldVersionValid -and $newVersionValid) {
        $versionPrecedence = Compare-RimePimeProductVersionPrecedence $oldVersion $newVersion
        if ($versionPrecedence -ge 0) {
            $reasons.Add('successor-product-version-is-not-strictly-greater-by-semver')
        }
        if ($oldVersion -ceq $newVersion) {
            $reasons.Add('old-and-successor-product-version-not-distinct')
        }
    }
    if ($oldPath -is [string] -and $newPath -is [string] -and $oldPath -ieq $newPath) {
        $reasons.Add('old-and-successor-installer-path-not-distinct-on-windows')
    }
    if ($oldSha256 -is [string] -and $newSha256 -is [string] -and $oldSha256 -ceq $newSha256) {
        $reasons.Add('old-and-successor-installer-sha256-not-distinct')
    }

    $uniqueReasons = @($reasons | Select-Object -Unique)
    return [pscustomobject][ordered]@{
        schema_version = $script:RimePimeVersionIdentityAdmissionSchema
        identity_transition_admitted = $uniqueReasons.Count -eq 0
        reasons = $uniqueReasons
        old_product_version = if ($oldVersion -is [string]) { $oldVersion } else { $null }
        successor_product_version = if ($newVersion -is [string]) { $newVersion } else { $null }
        expected_successor_product_version = $ExpectedSuccessorProductVersion
        old_installer_path = if ($oldPath -is [string]) { $oldPath } else { $null }
        successor_installer_path = if ($newPath -is [string]) { $newPath } else { $null }
        paths_compared_case_insensitively_for_windows = $true
        actual_canonical_migration_admitted = $false
        actual_canonical_migrated = $false
        installer_or_uninstaller_executed = $false
        registry_or_product_process_touched = $false
    }
}

Export-ModuleMember -Function 'Get-RimePimeVersionIdentityAdmission'
