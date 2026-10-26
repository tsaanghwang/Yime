[CmdletBinding()]
param([string]$GoExecutable = 'go')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'arm64-go-environment.ps1')
$checks = 0
function Check-GoEnvironment([bool]$Passed,[string]$Name) {
    if (-not $Passed) { throw "ARM64 Go environment regression: $Name" }
    $script:checks++
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$go = (Get-Command $GoExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$fixture = Join-Path $repo ('.tmp/arm64-goenv-contract-'+[guid]::NewGuid().ToString('N'))
$module = Join-Path $fixture 'module'
$null = [IO.Directory]::CreateDirectory($module)
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $module 'go.mod'),"module synthetic.example/arm64goenv`n`ngo 1.20`n",$utf8)
$source = Join-Path $module 'main.go'
[IO.File]::WriteAllText($source,"package fixture`nconst Value = 1`n",$utf8)
$external = Join-Path $fixture 'outside-module.go'
[IO.File]::WriteAllText($external,"package fixture`nimport _ `"encoding/base64`"`nconst Value = 2`n",$utf8)
$overlay = Join-Path $fixture 'overlay.json'
$replace = @{}; $replace[$source] = $external
[IO.File]::WriteAllText($overlay,(@{Replace=$replace}|ConvertTo-Json -Depth 4),$utf8)
$goenv = Join-Path $fixture 'go.env'
$persistedFlags = '"-overlay='+$overlay+'"'
[IO.File]::WriteAllText($goenv,('GOFLAGS='+$persistedFlags+"`n"),$utf8)
$configHash = (Get-FileHash -LiteralPath $goenv -Algorithm SHA256).Hash
$testEnvironment = [ordered]@{GOENV=$goenv;GOFLAGS='';GOWORK='off';GOTOOLCHAIN='local';GOPROXY='off';GOSUMDB='off';GOCACHE=(Join-Path $fixture 'cache')}
$savedTestEnvironment = @{}
foreach ($name in $testEnvironment.Keys) { $savedTestEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
function Invoke-FixtureGo([string[]]$Arguments) {
    $result = @(& $go -C $module @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Synthetic Go query failed: '+($result -join ' ')) }
    return ($result -join "`n")
}
function Assert-FixtureGoEnvironmentRestored {
    foreach ($name in @('GOENV','GOFLAGS','GOWORK','GOTOOLCHAIN')) {
        Check-GoEnvironment ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $testEnvironment[$name]) ("restore process $name")
    }
}
try {
    foreach ($name in $testEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$testEnvironment[$name],'Process') }
    Check-GoEnvironment ((Invoke-FixtureGo @('env','GOFLAGS')) -ceq $persistedFlags) 'empty process flags reproduce persistent GOENV overlay'
    Check-GoEnvironment ((Invoke-FixtureGo @('list','-f','{{join .Imports ","}}','.')) -ceq 'encoding/base64') 'persistent overlay reads source outside the module'
    Invoke-Arm64ProductGoEnvironment {
        Check-GoEnvironment ([Environment]::GetEnvironmentVariable('GOENV','Process') -ceq 'off' -and
            (Invoke-FixtureGo @('env','GOENV')) -ceq '') 'Go reports no persistent configuration file when GOENV is off'
        Check-GoEnvironment ((Invoke-FixtureGo @('env','GOFLAGS')) -ceq '') 'actual Go cannot recover persistent flags'
        Check-GoEnvironment ((Invoke-FixtureGo @('list','-f','{{join .Imports ","}}','.')) -ceq '') 'actual Go reads original source with overlay disabled'
        Check-GoEnvironment ([Environment]::GetEnvironmentVariable('GOWORK','Process') -ceq 'off' -and
            [Environment]::GetEnvironmentVariable('GOTOOLCHAIN','Process') -ceq 'local') 'first query uses local toolchain without an inherited workspace'
    }
    Assert-FixtureGoEnvironmentRestored
    $failure = $null
    try {
        Invoke-Arm64ProductGoEnvironment {
            Check-GoEnvironment ([Environment]::GetEnvironmentVariable('GOENV','Process') -ceq 'off') 'early preflight sees isolated environment'
            throw 'synthetic preflight failure before output'
        }
    } catch { $failure = $_.Exception.Message }
    Check-GoEnvironment ($failure -ceq 'synthetic preflight failure before output') 'preflight failure propagates without build output'
    Assert-FixtureGoEnvironmentRestored
    foreach ($originalFlags in @([NullString]::Value,'','-tags=synthetic-caller')) {
        [Environment]::SetEnvironmentVariable('GOFLAGS',$originalFlags,'Process')
        $expectedFlags = [Environment]::GetEnvironmentVariable('GOFLAGS','Process')
        $expectedPresent = [Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS')
        Invoke-Arm64ProductGoEnvironment { Check-GoEnvironment ((Invoke-FixtureGo @('env','GOFLAGS')) -ceq '') 'caller flags cleared before Go query' }
        Check-GoEnvironment ([Environment]::GetEnvironmentVariable('GOFLAGS','Process') -ceq $expectedFlags -and
            [Environment]::GetEnvironmentVariables('Process').Contains('GOFLAGS') -eq $expectedPresent) 'restore absent, empty or nonempty caller flags exactly'
    }
    Check-GoEnvironment ((Get-FileHash -LiteralPath $goenv -Algorithm SHA256).Hash -ceq $configHash) 'persistent fixture configuration remains byte-identical'
} finally {
    foreach ($name in $testEnvironment.Keys) {
        if ($null -eq $savedTestEnvironment[$name]) {
            [Environment]::SetEnvironmentVariable($name,[NullString]::Value,'Process')
        } else {
            [Environment]::SetEnvironmentVariable($name,$savedTestEnvironment[$name],'Process')
        }
    }
}
foreach ($name in $testEnvironment.Keys) {
    Check-GoEnvironment ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $savedTestEnvironment[$name]) ("test restores original process $name")
}

# This verifies the production call structure, without invoking the builder.
$builder = Join-Path $PSScriptRoot 'build-arm64-product.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
Check-GoEnvironment (@($errors).Count -eq 0) 'ARM builder parses'
$commands = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
$isolation = @($commands | Where-Object {$_.GetCommandName() -ceq 'Invoke-Arm64ProductGoEnvironment'})
Check-GoEnvironment ($isolation.Count -eq 1) 'ARM builder has one enclosing Go configuration scope'
$block = @($isolation[0].CommandElements | Where-Object {$_ -is [Management.Automation.Language.ScriptBlockExpressionAst]})
Check-GoEnvironment ($block.Count -eq 1) 'ARM Go isolation owns a script block'
$nativeGo = @($commands | Where-Object {$_.GetCommandName() -ceq 'Assert-YimeCoreNativeGo'})
$admission = @($commands | Where-Object {$_.GetCommandName() -ceq 'Assert-LocalProductSpeechBuildInputs'})
$outputs = @($commands | Where-Object {$_.GetCommandName() -ceq 'New-LocalProductBuildRoot'})
$goCommands = @($commands | Where-Object {$_.CommandElements[0].Extent.Text -ceq '$GoExecutable'})
$scoped = @($nativeGo) + @($admission) + @($outputs) + @($goCommands)
Check-GoEnvironment ($nativeGo.Count -eq 1 -and $admission.Count -eq 1 -and $outputs.Count -eq 1 -and $goCommands.Count -gt 0 -and
    @($scoped | Where-Object {$_.Extent.StartOffset -lt $block[0].Extent.StartOffset -or $_.Extent.EndOffset -gt $block[0].Extent.EndOffset}).Count -eq 0) 'first Go query, admission and build remain inside restoring environment scope'
Check-GoEnvironment ($nativeGo[0].Extent.EndOffset -lt $outputs[0].Extent.StartOffset -and
    $admission[0].Extent.EndOffset -lt $outputs[0].Extent.StartOffset) 'native Go and admission checks still precede output creation'
Write-Output "PASS: $checks ARM64 Go environment contracts; only synthetic go env/list, no product build or installation. Fixture: $fixture"
