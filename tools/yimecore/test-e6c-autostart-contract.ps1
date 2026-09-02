[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'repair-e6c-trial-autostart.ps1'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureState = Join-Path $repoRoot '.tmp\yimecore-experiment\autostart-contract-fixture'
$fixtureInstall = Join-Path $env:ProgramFiles 'YimeCore Experimental Trial\autostart-contract-new'
$fixtureRuntime = Join-Path $fixtureInstall 'bin\YimeCoreTrialRuntime.exe'
$expected = '"{0}" -no-toolbar' -f $fixtureRuntime
$stale = '"{0}" -no-toolbar' -f (Join-Path $env:ProgramFiles `
    'YimeCore Experimental Trial\autostart-contract-old\bin\YimeCoreTrialRuntime.exe')
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$valueName = 'YimeCoreExperimentalTrial'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-AutostartCase([string]$Name) {
    # These mocks execute the complete validator without reading or changing any
    # real registry values or creating a fake installation in Program Files.
    $fixture = @{
        keyExists = $Name -ne 'missing_key'
        valueExists = $Name -notin @('missing_key', 'missing_value')
        kind = $(if ($Name -eq 'wrong_kind') { 'ExpandString' } else { 'String' })
        value = $(if ($Name -in @('stale', 'repair', 'repair_not_sticking')) { $stale } else { $expected })
        writes = 0
        systemWrites = 0
        systemReads = 0
        systemValue = $(if ($Name -in @('stale', 'repair', 'repair_not_sticking', 'virtualized_valid', 'virtualized_repair')) { $stale } else { $expected })
        evidence = $null
        caseName = $Name
    }
    function Test-Path {
        param([string]$LiteralPath, [string]$PathType)
        if ($LiteralPath -eq $runKey) { return $fixture.keyExists }
        Assert-True ($LiteralPath -in @(
            (Join-Path $fixtureState 'runtime-config.json'),
            (Join-Path $fixtureInstall 'package-manifest.json'), $fixtureRuntime)) `
            "unexpected Test-Path in fixture: $LiteralPath"
        return $true
    }
    function Get-Content {
        param([string]$LiteralPath, [switch]$Raw, [string]$Encoding)
        if ($LiteralPath -eq (Join-Path $fixtureState 'runtime-config.json')) {
            return (@{
                install_root = $(if ($fixture.caseName -eq 'outside_root') {
                    Join-Path $env:ProgramFiles 'PIME'
                } else { $fixtureInstall })
                runtime_path = $fixtureRuntime
                state_root = $fixtureState
                experimental_clsid = '{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}'
            } | ConvertTo-Json)
        }
        Assert-True ($LiteralPath -eq (Join-Path $fixtureInstall 'package-manifest.json')) `
            "unexpected Get-Content in fixture: $LiteralPath"
        return (@{ files = @(@{ path = 'bin/YimeCoreTrialRuntime.exe'; sha256 = ('a' * 64) }) } |
            ConvertTo-Json -Depth 4)
    }
    function Get-FileHash {
        param([string]$LiteralPath, [string]$Algorithm)
        Assert-True ($LiteralPath -in @($fixtureRuntime, (Join-Path $fixtureInstall 'package-manifest.json'))) `
            "unexpected hash request: $LiteralPath"
        return [pscustomobject]@{ Hash = $(if ($fixture.caseName -eq 'bad_hash') {
            'b' * 64
        } else { 'a' * 64 }) }
    }
    function Get-Item {
        param([string]$LiteralPath)
        Assert-True ($LiteralPath -eq $runKey) 'validator accessed an unrelated registry key'
        $key = [pscustomobject]@{}
        $key | Add-Member ScriptMethod GetValueNames {
            if ($fixture.valueExists) { return @('YimeCoreExperimentalTrial') }
            return @()
        }
        $key | Add-Member ScriptMethod GetValueKind {
            param($Name)
            Assert-True ($Name -eq 'YimeCoreExperimentalTrial') 'read unrelated registry value kind'
            return $fixture.kind
        }
        $key | Add-Member ScriptMethod GetValue {
            param($Name, $Default, $Options)
            Assert-True ($Name -eq 'YimeCoreExperimentalTrial') 'read unrelated registry value'
            Assert-True ($Options -eq [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) `
                'registry read must preserve the literal stored value'
            return $fixture.value
        }
        $key | Add-Member ScriptMethod Close {}
        return $key
    }
    function New-Item {
        param([string]$Path, [string]$ItemType, [switch]$Force)
        Assert-True ($Path -in @($runKey, $fixtureState)) "unexpected New-Item: $Path"
        if ($Path -eq $runKey) { $fixture.keyExists = $true }
    }
    function New-ItemProperty {
        param([string]$LiteralPath, [string]$Name, [string]$Value, [string]$PropertyType, [switch]$Force)
        Assert-True ($LiteralPath -eq $runKey -and $Name -eq $valueName -and
            $Value -ceq $expected -and $PropertyType -eq 'String') 'repair wrote outside its exact contract'
        $fixture.writes++
        if ($fixture.caseName -ne 'repair_not_sticking') {
            $fixture.valueExists = $true
            $fixture.kind = 'String'
            $fixture.value = $Value
        }
    }
    function Set-Content {
        param([string]$LiteralPath, [string]$Encoding, [Parameter(ValueFromPipeline)]$Value)
        process {
            Assert-True ($LiteralPath -eq (Join-Path $fixtureState 'evidence.json')) 'unexpected evidence path'
            $fixture.evidence = $Value | ConvertFrom-Json
        }
    }

    function Invoke-CimMethod {
        param([string]$Namespace, [string]$ClassName, [string]$MethodName, [hashtable]$Arguments)
        Assert-True ($Namespace -eq 'root/default' -and $ClassName -eq 'StdRegProv') 'unexpected registry provider'
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Assert-True ($Arguments.hDefKey -eq [uint32]2147483651 -and
            $Arguments.sSubKeyName -eq "$sid\Software\Microsoft\Windows\CurrentVersion\Run") 'system read/write escaped initiating SID and Run key'
        if ($MethodName -in @('SetStringValue','GetStringValue','DeleteValue')) {
            Assert-True ($Arguments.sValueName -eq $valueName) 'system provider accessed unrelated value'
        }
        if ($Name -eq 'system_provider_denied') { return [pscustomobject]@{ReturnValue=5} }
        switch ($MethodName) {
            'EnumValues' {
                $fixture.systemReads++
                if (-not $fixture.keyExists) { return [pscustomobject]@{ReturnValue=2} }
                return [pscustomobject]@{ReturnValue=0;sNames=$(if($fixture.valueExists){@($valueName)}else{@()});Types=$(if($fixture.valueExists){@($(if($fixture.kind -eq 'String'){1}else{2}))}else{@()})}
            }
            'GetStringValue' { return [pscustomobject]@{ReturnValue=0;sValue=$fixture.systemValue} }
            'CreateKey' { $fixture.keyExists=$true; return [pscustomobject]@{ReturnValue=0} }
            'SetStringValue' {
                Assert-True ($Arguments.sValue -ceq $expected) 'unexpected native repair command'
                $fixture.systemWrites++
                if($fixture.caseName -ne 'repair_not_sticking') {
                    $fixture.valueExists=$true; $fixture.kind='String'; $fixture.systemValue=$Arguments.sValue
                }
                return [pscustomobject]@{ReturnValue=0}
            }
            default { throw "unexpected system registry method: $MethodName" }
        }
    }

    $repair = $Name -in @('repair', 'repair_not_sticking', 'virtualized_repair')
    $errorText = ''
    try {
        $null = & $validator -StateRoot $fixtureState -ValidateOnly:(-not $repair) `
            -OutputPath (Join-Path $fixtureState 'evidence.json')
    } catch { $errorText = $_.Exception.Message }
    $shouldPass = $Name -in @('valid', 'repair', 'virtualized_repair')
    Assert-True (($errorText.Length -eq 0) -eq $shouldPass) "unexpected outcome for ${Name}: $errorText"
    Assert-True ($fixture.writes -eq 0 -and $fixture.systemWrites -eq $(if ($repair) { 1 } else { 0 })) `
        "${Name}: repair must write exactly once through the system provider; ValidateOnly must not write"
    if ($Name -in @('outside_root', 'bad_hash')) {
        Assert-True ($null -eq $fixture.evidence) "${Name}: untrusted package reached registry acceptance"
        Assert-True ($errorText -match 'invalid E6-C runtime configuration|does not match its package manifest') `
            "${Name}: failed for the wrong reason: $errorText"
    } elseif ($Name -eq 'system_provider_denied') {
        Assert-True ($errorText -match 'system registry.*5') 'provider failure must fail closed without process-view fallback'
    } else {
        $e = $fixture.evidence
        Assert-True ($null -ne $e -and $e.passed -eq $shouldPass -and
            $e.validated_only -eq (-not $repair) -and $e.registry_mutation_requested -eq $repair) `
            "${Name}: missing or incorrect persisted success/failure evidence"
        Assert-True ($e.expected_value -ceq $expected -and
            $e.target_user_sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) `
            "${Name}: expected value or calling SID was not preserved"
        Assert-True ($e.registry_reader -eq 'StdRegProv/HKEY_USERS' -and $fixture.systemReads -ge 2) 'missing independent system registry readback'
        if ($Name -in @('stale', 'repair', 'repair_not_sticking', 'virtualized_valid', 'virtualized_repair')) {
            Assert-True ($e.before.value -ceq $stale) "${Name}: original stale value was lost"
        }
        if (-not $shouldPass) {
            Assert-True ($errorText -match 'expected REG_SZ' -and $errorText -match 'actual exists=') `
                "${Name}: error does not identify the observed registry mismatch"
        }
    }
    [ordered]@{ name = $Name; passed = $true; process_registry_writes_mocked = $fixture.writes; system_registry_writes_mocked = $fixture.systemWrites }
}

$cases = @('virtualized_valid', 'valid', 'stale', 'missing_value', 'missing_key', 'wrong_kind', 'repair',
    'repair_not_sticking', 'bad_hash', 'outside_root', 'virtualized_repair', 'system_provider_denied')
$results = @($cases | ForEach-Object { Test-AutostartCase $_ })
$e6d = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run-e6d-independence-readiness.ps1') -Raw
Assert-True (([regex]::Matches($e6d, '& \$autostartValidator -StateRoot \$stateRootPath -ValidateOnly')).Count -eq 2) `
    'E6-D must validate actual autostart before and after its audit, without repairing'
$e7 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run-e7-cutover-readiness.ps1') -Raw
Assert-True ($e7.Contains("'current_user_autostart_convergence_passed'") -and
    $e7.Contains("'e6d_autostart_evidence'") -and $e7.Contains('$autostartHashValid = Test-EvidenceHash')) `
    'E7 must reject summaries without hash-linked read-only autostart evidence'
$upgrade = Get-Content -LiteralPath (Join-Path $repoRoot 'Build-Install-YimeCore-Trial-v3.cmd') -Raw
$lastHost = $upgrade.LastIndexOf('YimeRegisteredHostTests.exe')
$finalValidation = $upgrade.IndexOf('-ValidateOnly -OutputPath')
Assert-True ($lastHost -gt 0 -and $finalValidation -gt $lastHost -and
    $finalValidation -lt $upgrade.IndexOf('echo Build, installation, and live runtime verification completed successfully.')) `
    'upgrade must read back autostart after registered-host tests and before announcing success'
$result = [ordered]@{
    schema_version = 'yimecore-e6c-autostart-contract-v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    cases = $results
    actual_registry_mutated = $false
    e6d_e7_upgrade_wiring_passed = $true
    passed = $true
}
if ($OutputPath) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) | Out-Null
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
$result | ConvertTo-Json -Depth 5

