$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Setup.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Setup parse failed'}
# Execute the actual teardown statements, with every external operation replaced.
# Never execute Setup itself or load input.dll in this regression.
$statements=@($ast.Find({param($node) $node -is [Management.Automation.Language.TryStatementAst]},$false).Body.Statements)
$start=-1;$end=-1
for($i=0;$i -lt $statements.Count;$i++){
    if($statements[$i].Extent.Text -eq "`$stage='unregister selected product'"){$start=$i}
    if($statements[$i].Extent.Text -eq "`$stage='copy new product files'"){$end=$i}
}
if($start -lt 0 -or $end -le $start){throw 'Cannot locate setup teardown'}
$teardown=[scriptblock]::Create(($statements[$start..($end-1)]|ForEach-Object {$_.Extent.Text}) -join "`n")
Add-Type @'
public static class SimpleInputProfile {
 public static bool Result;
 public static string Profile;
 public static uint Flags;
 public static int Calls;
 public static bool InstallLayoutOrTip(string profile, uint flags) {
  Profile=profile; Flags=flags; Calls++; return Result;
 }
}
'@
function Set-Registration([bool]$Install,[string]$Payload){
    if([SimpleInputProfile]::Calls -ne 1){throw 'COM unregistered before profile removal'}
    if($Install){throw 'Unexpected registration'}
    if($Payload -cne $expectedPayload){throw ('Wrong maintenance resource path: '+$Payload)}
    $script:events.Add('unregister')
}
function Set-UserStartup([string]$Value){
    if([SimpleInputProfile]::Calls -ne 1 -or -not [SimpleInputProfile]::Result){throw 'Startup cleared before successful profile removal'}
    if($Value){throw 'Unexpected startup write'}
    $script:events.Add('startup')
}
function Remove-ProductDirectory([string]$Root,[string]$Product){
    if([SimpleInputProfile]::Calls -ne 1 -or -not [SimpleInputProfile]::Result){throw 'Files removed before successful profile removal'}
    if($Root -cne 'C:\synthetic-product' -or $Product -cne $productId){throw 'Wrong product directory selected'}
    $script:events.Add('files')
}
function Remove-Item {throw 'Unexpected data deletion'}
$Action='Install';$ResetData=$false
$package=[pscustomobject]@{root='C:\synthetic-package'}
$root='C:\synthetic-product'
foreach($productId in @('yimecore','rime-pime')){
    $product=[pscustomobject]@{id=$productId}
    $tip='synthetic-'+$productId
    foreach($installedEntry in @($false,$true)){
        $expectedPayload=Join-Path $package.root $(if($installedEntry){'native'}else{'payload'})
        foreach($hasRegistration in @($false,$true)){
            foreach($success in @($false,$true)){
                $script:events=[Collections.Generic.List[string]]::new()
                [SimpleInputProfile]::Result=$success;[SimpleInputProfile]::Calls=0
                $failure=''
                try{& $teardown}catch{$failure=$_.Exception.Message}
                if([SimpleInputProfile]::Calls -ne 1 -or [SimpleInputProfile]::Profile -cne $tip -or [SimpleInputProfile]::Flags -ne 1){throw 'Wrong profile removal request'}
                if($success){
                    $expected=if($hasRegistration){'unregister,startup,files'}else{'startup,files'}
                    if($failure -or ($events -join ',') -cne $expected){throw ('Successful teardown failed: '+$failure)}
                }else{
                    if($failure -cne 'Could not remove the input profile; product files and COM registration were kept' -or $events.Count){throw ('Failed profile removal did not preserve installation: '+$failure)}
                }
            }
        }
    }
}
Write-Output 'PASS: profile removal failure stops before COM/startup/file deletion; success proceeds for both products and package/installed entry paths. Synthetic API only.'
