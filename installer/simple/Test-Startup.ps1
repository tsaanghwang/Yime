$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-UserStartup'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
# Exercise the actual provider on a unique, non-startup test key only.
$runKey='Software\YimeSimpleStartupTest-'+[guid]::NewGuid().ToString('N')
$runName='test-product'
$address=@{hDefKey=[uint32]2147483651;sSubKeyName=$sid+'\'+$runKey}
try{
 Set-UserStartup ''
 Set-UserStartup 'test-only-not-an-executable'
 Set-UserStartup 'updated-test-value'
 $peer=$address.Clone();$peer.sValueName='other-product';$peer.sValue='keep'
 $r=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName SetStringValue -Arguments $peer
 if($r.ReturnValue -ne 0){throw 'Cannot create peer fixture'}
 Set-UserStartup ''
 Set-UserStartup ''
 $peer.Remove('sValue')
 $r=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments $peer
 if($r.ReturnValue -ne 0 -or $r.sValue -cne 'keep'){throw 'Peer value changed'}
 Write-Output 'PASS: absent key, write/update/readback, delete/repeated delete, peer preserved (real StdRegProv).'
}finally{
 $r=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName DeleteKey -Arguments $address
 if($r.ReturnValue -notin @(0,2)){throw ('Test-key cleanup failed: '+$r.ReturnValue)}
}
# Provider failures and a value that remains listed must still stop setup.
function Invoke-CimMethod {param($Namespace,$ClassName,$MethodName,$Arguments)
 if($script:scenario -eq 'denied'){return [pscustomobject]@{ReturnValue=5;sNames=$null}}
 if($MethodName -eq 'EnumValues'){return [pscustomobject]@{ReturnValue=0;sNames=@('test-product')}}
 return [pscustomobject]@{ReturnValue=0}
}
foreach($scenario in @('denied','still-present')){
 $failed=$false;try{Set-UserStartup ''}catch{$failed=$true}
 if(-not $failed){throw ('Did not reject '+$scenario)}
}
Write-Output 'PASS: provider access failure and incomplete deletion rejected.'
