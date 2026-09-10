# This entry reads a JSON request from stdin. Run through run_checked.py.
$ErrorActionPreference = 'Stop'
try {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $parameters = @{}
    foreach ($property in $request.parameters.PSObject.Properties) {
        $parameters[$property.Name] = $property.Value
    }
    $tokens=$null; $parseErrors=$null
    if ($request.script) {
        $path = [IO.Path]::GetFullPath([string]$request.script)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ine '.ps1') {
            throw 'Script must be an existing .ps1 file.'
        }
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    } else {
        $ast = [Management.Automation.Language.Parser]::ParseInput([string]$request.command, [ref]$tokens, [ref]$parseErrors)
    }
    if ($parseErrors.Count) {
        throw (($parseErrors | ForEach-Object { 'line {0}: {1}' -f $_.Extent.StartLineNumber,$_.Message }) -join "`n")
    }
    if ($request.script) {
        # Only unconditional mandatory parameters can be proved without executing
        # dynamic parameter providers or guessing which parameter set is selected.
        $known = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction',
                   'ErrorVariable','WarningVariable','InformationVariable','OutVariable',
                   'OutBuffer','PipelineVariable')
        foreach ($parameter in $ast.ParamBlock.Parameters) {
            $name = $parameter.Name.VariablePath.UserPath
            $known += $name
            foreach ($attribute in $parameter.Attributes) {
                if ($attribute -isnot [Management.Automation.Language.AttributeAst]) { continue }
                if ($attribute.TypeName.Name -eq 'Alias') {
                    foreach ($alias in $attribute.PositionalArguments) { $known += $alias.SafeGetValue() }
                }
                if ($attribute.TypeName.Name -ne 'Parameter') { continue }
                $set = @($attribute.NamedArguments | Where-Object {$_.ArgumentName -eq 'ParameterSetName'})
                $mandatory = @($attribute.NamedArguments | Where-Object {$_.ArgumentName -eq 'Mandatory'})
                if ($set.Count -or -not $mandatory.Count) { continue }
                $required = $mandatory[0].ExpressionOmitted -or $mandatory[0].Argument.SafeGetValue() -eq $true
                if ($required -and -not $parameters.ContainsKey($name)) {
                    $aliases = @($parameter.Attributes | Where-Object {$_.TypeName.Name -eq 'Alias'} |
                        ForEach-Object {$_.PositionalArguments} | ForEach-Object {$_.SafeGetValue()})
                    if (-not @($aliases | Where-Object {$parameters.ContainsKey($_)}).Count) {
                        throw "Missing mandatory parameter: -$name"
                    }
                }
            }
        }
        if (-not $ast.DynamicParamBlock) {
            foreach ($name in $parameters.Keys) {
                if ($name -notin $known) { throw "Unknown parameter: -$name (use its full name)" }
            }
        }
    }
    if ($request.check_only) {
        Write-Output ('PASS: PowerShell {0} static preflight; script not executed.' -f $PSVersionTable.PSVersion)
        exit 0
    }
} catch {
    [Console]::Error.WriteLine('PowerShell preflight: '+$_.Exception.Message)
    exit 2
}
# The script runs with normal path/PSScriptRoot semantics in this selected shell.
# Do not retry commands, elevate, change profile or guess missing parameters.
$global:LASTEXITCODE = 0
try {
    if ($request.script) { & $path @parameters }
    else { & ([scriptblock]::Create([string]$request.command)) }
    if (-not $?) { exit 1 }
    exit $global:LASTEXITCODE
} catch {
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
