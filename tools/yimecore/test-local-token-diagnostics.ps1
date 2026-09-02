[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'development-scope.ps1')
$null=Get-YimeCoreDevelopmentScope
. (Join-Path $PSScriptRoot 'local-token-diagnostics.ps1')
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"};$checks.Add($Name)}
foreach($code in @(5,1346,1314,0)) {
    $native=[ComponentModel.Win32Exception]::new($code,'Duplicate linked primary token')
    $inner=[InvalidOperationException]::new('intermediate wrapper',$native)
    $outer=[Management.Automation.MethodInvocationException]::new('PowerShell invocation wrapper',$inner)
    $evidence=@(Get-YimeCoreExceptionEvidence $outer)
    Check ($evidence.Count -eq 3) "all exception wrappers retained ($code)"
    Check ($null -eq $evidence[0].native_error_code -and $null -eq $evidence[1].native_error_code) "non-Win32 wrappers are not assigned an error code ($code)"
    Check ($evidence[2].native_error_code -eq $code -and $evidence[2].message -ceq 'Duplicate linked primary token') "original native code and operation retained ($code)"
    Check ($evidence[2].native_error_message -ceq ([ComponentModel.Win32Exception]::new($code)).Message) "Windows system message recovered despite custom operation message ($code)"
    $roundtrip=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $evidence -Depth 8)
    Check ($roundtrip[2].native_error_code -eq $code) "native error survives JSON serialization ($code)"
}
$ordinary=@(Get-YimeCoreExceptionEvidence ([InvalidOperationException]::new('ordinary error')))
Check ($ordinary.Count -eq 1 -and $null -eq $ordinary[0].native_error_code) 'ordinary exceptions stay ordinary'

# This calls only GetTokenInformation on this test process and its own linked
# token (if present). No native launch, privilege change or app-context escape.
$snapshot=Get-YimeCoreLaunchTokenDiagnostics
Check ($snapshot.Caller.Sid -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'current-process token SID read correctly'
Check ($snapshot.Caller.TokenType -eq 1 -and $snapshot.Caller.TokenTypeName -ceq 'Primary') 'primary token identified without an impersonation-level query'
Check ($null -eq $snapshot.Caller.ImpersonationLevel) 'primary token impersonation level remains unavailable rather than fabricated'
Check ($snapshot.Caller.Session -eq (Get-Process -Id $PID).SessionId) 'current session captured'
if(-not $snapshot.Caller.Elevated) {
    Check ($null -eq $snapshot.Linked) 'non-elevated diagnostic does not acquire a linked elevated token'
}
$helperText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local-token-diagnostics.ps1') -Raw -Encoding UTF8
$imports=@([regex]::Matches($helperText,'static extern \w+ (\w+)\(')|ForEach-Object{$_.Groups[1].Value})
Check (($imports -join ',') -ceq 'GetTokenInformation,CloseHandle') 'only query and handle-close native APIs are imported'
Check ($helperText -notmatch '\b(Process\.Start|Start-Process|CreateProcessWithTokenW|DuplicateTokenEx|AdjustTokenPrivileges|Set-ItemProperty|Stop-Process)\b') 'diagnostic has no process launch, token duplication, privilege or registry mutation'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'invoke-local-product-native-install.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'native acceptance script parses'
$out=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) ('.tmp\yimecore-local-product\token-diagnostics-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
[ordered]@{passed=$true;count=$checks.Count;checks=@($checks);powershell=$PSVersionTable.PSVersion.ToString();
    test_caller_token=$snapshot;actual_elevated_launch_tested=$false;actual_install_executed=$false;actual_registry_writes=$false}|
    ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
Write-Output "PASS: $($checks.Count) read-only token diagnostic contracts. Evidence: $out"
